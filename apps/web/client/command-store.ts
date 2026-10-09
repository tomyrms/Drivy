import { useSyncExternalStore } from 'react';
import {
  classifyFailure, commandHeaders, commandMessage, commandSpecs, parseMetadata, receiptMatches, toMetadata,
  type CommandMetadata, type SchoolCommand,
} from './command-core';
import { confirmedData, readSchool, receiptSchema, schoolFetch } from './school-api';
import { RequestFailure } from './protocol';

/**
 * One pending command per school, as on iPhone. The full request lives in memory only;
 * sessionStorage (this tab) keeps its identifiers so that a reload can still ask the school
 * for the AP72 receipt. Typed content never reaches browser storage.
 */
export type PendingPhase = 'sending' | 'verifying' | 'uncertain' | 'review' | 'orphaned';
export interface PendingEntry {
  readonly meta: CommandMetadata;
  readonly command: SchoolCommand | null;
  readonly phase: PendingPhase;
  readonly message: string;
  readonly needsLogin: boolean;
  /** AP72 answered 404: the school has no trace of this operation yet. */
  readonly notRecorded: boolean;
  /** An emission may have reached the school since the last 404 of AP72; a later refusal then proves nothing about it. */
  readonly maybeReceived: boolean;
  /** The last verification gave no usable answer (refused or unreadable receipt): following can be stopped with a warning. */
  readonly unverifiable: boolean;
  readonly attempts: number;
}
export type SubmitResult =
  | { status: 'confirmed'; body: unknown; via: 'response' | 'receipt' }
  | { status: 'rejected'; code: string; message: string; needsLogin: boolean }
  | { status: 'pending'; message: string };

/**
 * Ways out of a followed request, the same for the panel and for the store.
 * Resend: the result is unknown, or the school has no trace of the request (whatever the last answer was).
 * Release: nothing more can be learnt here — content lost, refusal on a resend, no trace, or a verification the school does not settle.
 */
export function pendingActions(entry: Pick<PendingEntry, 'command' | 'phase' | 'notRecorded' | 'unverifiable'>): { resend: boolean; release: boolean } {
  const working = entry.phase === 'sending' || entry.phase === 'verifying';
  return {
    resend: !working && entry.command !== null && (entry.phase === 'uncertain' || entry.notRecorded),
    release: !working && (entry.command === null || entry.phase === 'review' || entry.notRecorded || entry.unverifiable),
  };
}

const storageKey = 'drivy-gestion-demandes-v1';
type Snapshot = { entries: ReadonlyMap<string, PendingEntry>; revision: number; confirmed: { kind: string; operationId: string; at: number } | null };

class CommandStore {
  private snapshot: Snapshot = { entries: new Map(), revision: 0, confirmed: null };
  private readonly listeners = new Set<() => void>();

  constructor() {
    try {
      const stored = JSON.parse(window.sessionStorage.getItem(storageKey) ?? '[]') as unknown;
      const entries = new Map<string, PendingEntry>();
      if (Array.isArray(stored)) for (const value of stored.slice(0, 50)) {
        const meta = parseMetadata(value);
        if (meta && !entries.has(meta.schoolId)) entries.set(meta.schoolId, { meta, command: null, phase: 'orphaned', needsLogin: false,
          notRecorded: false, maybeReceived: true, unverifiable: false, attempts: 1, message: 'Le résultat de cette demande reste à vérifier. Son contenu n’est plus disponible dans cette page.' });
      }
      this.snapshot = { ...this.snapshot, entries };
    } catch { /* Storage unavailable: pending requests stay in memory for this page only. */ }
  }

  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  getSnapshot = () => this.snapshot;

  /** `reread` makes every section read the school again, as a confirmation does. */
  private update(schoolId: string, entry: PendingEntry | null, confirmed?: CommandMetadata, reread = false) {
    const entries = new Map(this.snapshot.entries);
    if (entry) entries.set(schoolId, entry); else entries.delete(schoolId);
    this.snapshot = { entries, revision: this.snapshot.revision + (confirmed || reread ? 1 : 0),
      confirmed: confirmed ? { kind: confirmed.kind, operationId: confirmed.operationId, at: Date.now() } : this.snapshot.confirmed };
    try { window.sessionStorage.setItem(storageKey, JSON.stringify([...entries.values()].map(item => item.meta))); } catch { /* memory only */ }
    for (const listener of this.listeners) listener();
  }

  get(schoolId: string): PendingEntry | undefined { return this.snapshot.entries.get(schoolId); }

  async submit(command: SchoolCommand, csrf: string): Promise<SubmitResult> {
    if (this.get(command.schoolId)) return { status: 'pending', message: 'Une demande attend encore sa vérification. Traitez-la avant une autre modification.' };
    this.update(command.schoolId, { meta: toMetadata(command), command, phase: 'sending', message: '', needsLogin: false, notRecorded: false,
      maybeReceived: false, unverifiable: false, attempts: 0 });
    return this.emit(command, csrf);
  }

  async resend(schoolId: string, csrf: string): Promise<SubmitResult> {
    const entry = this.get(schoolId);
    if (!entry?.command || !pendingActions(entry).resend) return { status: 'pending', message: entry?.message ?? '' };
    return this.emit(entry.command, csrf);
  }

  private async emit(command: SchoolCommand, csrf: string): Promise<SubmitResult> {
    const previous = this.get(command.schoolId);
    const attempts = previous?.attempts ?? 0;
    const maybeReceived = previous?.maybeReceived ?? false;
    const base: PendingEntry = previous ?? { meta: toMetadata(command), command, phase: 'sending', message: '', needsLogin: false, notRecorded: false,
      maybeReceived: false, unverifiable: false, attempts: 0 };
    this.update(command.schoolId, { ...base, command, phase: 'sending', message: '', needsLogin: false, attempts: attempts + 1 });
    const spec = commandSpecs[command.kind];
    const response = await schoolFetch(command.schoolId, command.path, { method: spec.method, headers: commandHeaders(command, csrf), body: command.body });
    if (response.status === spec.expectedStatus) {
      const data = confirmedData(response.body);
      const valid = data !== null && (data.schoolId === undefined || data.schoolId.toLowerCase() === command.schoolId.toLowerCase())
        && (data.version === undefined || data.version > command.resourceVersion)
        && (spec.target !== 'resource' || data.id === undefined || data.id.toLowerCase() === command.resourceId?.toLowerCase());
      if (valid) { this.update(command.schoolId, null, toMetadata(command)); return { status: 'confirmed', body: response.body, via: 'response' }; }
      return this.keep(command, 'uncertain', 'INVALID_RESPONSE', false, attempts + 1, true);
    }
    const success = response.status >= 200 && response.status < 300;
    // A 4xx without a readable code is still a refusal of the school, not an unavailability.
    const refusal = response.status >= 400 && response.status < 500 && response.status !== 408 && response.status !== 429;
    const code = success ? 'INVALID_RESPONSE' : refusal && response.code === 'API_UNAVAILABLE' ? 'REQUEST_FAILED' : response.code || 'REQUEST_FAILED';
    const outcome = success ? { type: 'uncertain' as const, code, needsLogin: false } : classifyFailure(response.status, code, !maybeReceived);
    if (outcome.type === 'rejected') {
      // Refused on a resend: nothing else tells the sections to read the school again.
      this.update(command.schoolId, null, undefined, attempts > 0);
      return { status: 'rejected', code, message: commandMessage(code), needsLogin: outcome.needsLogin };
    }
    // The BFF refused the page's CSRF value before calling the school: this emission reached nobody.
    return this.keep(command, outcome.type, code, outcome.needsLogin, attempts + 1, maybeReceived || code !== 'CSRF_REJECTED');
  }

  private keep(command: SchoolCommand, phase: 'uncertain' | 'review', code: string, needsLogin: boolean, attempts: number, maybeReceived: boolean): SubmitResult {
    const message = phase === 'review'
      ? `${commandMessage(code)} Cette réponse ne prouve pas que la demande précédente est restée sans effet : vérifiez-la auprès de l’école.`
      : commandMessage(code);
    this.update(command.schoolId, { meta: toMetadata(command), command, phase, message, needsLogin, notRecorded: false, maybeReceived, unverifiable: false, attempts });
    return { status: 'pending', message };
  }

  /** AP72: ask the school whether this operation was committed, without sending it again. */
  async verify(schoolId: string): Promise<SubmitResult> {
    const entry = this.get(schoolId);
    if (!entry || entry.phase === 'sending' || entry.phase === 'verifying') return { status: 'pending', message: entry?.message ?? '' };
    const restore = entry.phase;
    this.update(schoolId, { ...entry, phase: 'verifying' });
    try {
      const receipt = await readSchool(schoolId, `operations/${entry.meta.operationId}`, receiptSchema);
      if (!receiptMatches(entry.meta, receipt)) throw new RequestFailure('INVALID_RESPONSE');
      this.update(schoolId, null, entry.meta);
      return { status: 'confirmed', body: null, via: 'receipt' };
    } catch (error) {
      const current = this.get(schoolId);
      if (current?.meta.operationId !== entry.meta.operationId) return { status: 'pending', message: '' };
      const failure = error instanceof RequestFailure ? error : new RequestFailure('INVALID_RESPONSE');
      const notRecorded = failure.status === 404;
      // The school answered, but with nothing that settles the request: retrying alone may never end.
      const unverifiable = failure.status === 403 || failure.code === 'INVALID_RESPONSE';
      const message = notRecorded
        ? entry.command
          ? 'L’école ne retrouve pas cette demande : rien n’a été modifié. Renvoyez la même demande, ou abandonnez-la.'
          : 'L’école ne retrouve pas cette demande : rien n’a été modifié. Son contenu n’est plus dans cette page : abandonnez-la, puis refaites la modification.'
        : failure.status === 401 ? 'Votre connexion a expiré. Reconnectez-vous, puis vérifiez à nouveau.'
          : failure.status === 403 ? 'Vos accès actuels ne permettent pas de consulter ce résultat. Vérifiez à nouveau, ou arrêtez le suivi de cette demande.'
            : unverifiable ? 'La réponse de l’école ne permet pas d’établir le résultat. Vérifiez à nouveau, ou arrêtez le suivi de cette demande.'
              : 'Le résultat n’a pas pu être établi. La demande reste suivie : réessayez la vérification.';
      this.update(schoolId, { ...current, phase: restore, message, notRecorded, unverifiable, needsLogin: failure.status === 401,
        maybeReceived: notRecorded ? false : current.maybeReceived });
      return { status: 'pending', message };
    }
  }

  /** Give up a request (unknown result, or no trace at the school), behind an explicit confirmation only. The sections then read the school again. */
  release(schoolId: string) {
    const entry = this.get(schoolId);
    if (entry && pendingActions(entry).release) this.update(schoolId, null, undefined, true);
  }

  clear() {
    this.snapshot = { entries: new Map(), revision: this.snapshot.revision, confirmed: null };
    try { window.sessionStorage.removeItem(storageKey); } catch { /* nothing stored */ }
    for (const listener of this.listeners) listener();
  }
}

export const commandStore = new CommandStore();

export function useCommandSnapshot(): Snapshot {
  return useSyncExternalStore(commandStore.subscribe, commandStore.getSnapshot);
}
