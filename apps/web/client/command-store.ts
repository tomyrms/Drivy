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
  readonly attempts: number;
}
export type SubmitResult =
  | { status: 'confirmed'; body: unknown; via: 'response' | 'receipt' }
  | { status: 'rejected'; code: string; message: string }
  | { status: 'pending'; message: string };

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
          notRecorded: false, attempts: 1, message: 'Le résultat de cette demande reste à vérifier. Son contenu n’est plus disponible dans cette page.' });
      }
      this.snapshot = { ...this.snapshot, entries };
    } catch { /* Storage unavailable: pending requests stay in memory for this page only. */ }
  }

  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  getSnapshot = () => this.snapshot;

  private update(schoolId: string, entry: PendingEntry | null, confirmed?: CommandMetadata) {
    const entries = new Map(this.snapshot.entries);
    if (entry) entries.set(schoolId, entry); else entries.delete(schoolId);
    this.snapshot = { entries, revision: this.snapshot.revision + (confirmed ? 1 : 0),
      confirmed: confirmed ? { kind: confirmed.kind, operationId: confirmed.operationId, at: Date.now() } : this.snapshot.confirmed };
    try { window.sessionStorage.setItem(storageKey, JSON.stringify([...entries.values()].map(item => item.meta))); } catch { /* memory only */ }
    for (const listener of this.listeners) listener();
  }

  get(schoolId: string): PendingEntry | undefined { return this.snapshot.entries.get(schoolId); }

  async submit(command: SchoolCommand, csrf: string): Promise<SubmitResult> {
    if (this.get(command.schoolId)) return { status: 'pending', message: 'Une demande attend encore sa vérification. Traitez-la avant une autre modification.' };
    this.update(command.schoolId, { meta: toMetadata(command), command, phase: 'sending', message: '', needsLogin: false, notRecorded: false, attempts: 0 });
    return this.emit(command, csrf);
  }

  async resend(schoolId: string, csrf: string): Promise<SubmitResult> {
    const entry = this.get(schoolId);
    if (!entry?.command || !['uncertain'].includes(entry.phase)) return { status: 'pending', message: entry?.message ?? '' };
    return this.emit(entry.command, csrf);
  }

  private async emit(command: SchoolCommand, csrf: string): Promise<SubmitResult> {
    const previous = this.get(command.schoolId);
    const attempts = previous?.attempts ?? 0;
    const base: PendingEntry = previous ?? { meta: toMetadata(command), command, phase: 'sending', message: '', needsLogin: false, notRecorded: false, attempts: 0 };
    this.update(command.schoolId, { ...base, command, phase: 'sending', message: '', needsLogin: false, attempts: attempts + 1 });
    const spec = commandSpecs[command.kind];
    const response = await schoolFetch(command.schoolId, command.path, { method: spec.method, headers: commandHeaders(command, csrf), body: command.body });
    if (response.status === spec.expectedStatus) {
      const data = confirmedData(response.body);
      const valid = data !== null && (data.schoolId === undefined || data.schoolId.toLowerCase() === command.schoolId.toLowerCase())
        && (data.version === undefined || data.version > command.resourceVersion)
        && (spec.target !== 'resource' || data.id === undefined || data.id.toLowerCase() === command.resourceId?.toLowerCase());
      if (valid) { this.update(command.schoolId, null, toMetadata(command)); return { status: 'confirmed', body: response.body, via: 'response' }; }
      return this.keep(command, 'uncertain', 'INVALID_RESPONSE', false, attempts + 1);
    }
    const code = response.status >= 200 && response.status < 300 ? 'INVALID_RESPONSE' : response.code || 'REQUEST_FAILED';
    const outcome = response.status >= 200 && response.status < 300 ? { type: 'uncertain' as const, code, needsLogin: false } : classifyFailure(response.status, code, attempts === 0);
    if (outcome.type === 'rejected') { this.update(command.schoolId, null); return { status: 'rejected', code, message: commandMessage(code) }; }
    return this.keep(command, outcome.type, code, outcome.type === 'uncertain' && outcome.needsLogin, attempts + 1);
  }

  private keep(command: SchoolCommand, phase: 'uncertain' | 'review', code: string, needsLogin: boolean, attempts: number): SubmitResult {
    const message = phase === 'review'
      ? `${commandMessage(code)} Cette réponse ne prouve pas que la demande précédente est restée sans effet : vérifiez-la auprès de l’école.`
      : commandMessage(code);
    this.update(command.schoolId, { meta: toMetadata(command), command, phase, message, needsLogin, notRecorded: false, attempts });
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
      const message = notRecorded
        ? entry.command
          ? 'L’école n’a pas trouvé cette demande : elle n’a pas été appliquée pour l’instant. Renvoyez la même demande pour la terminer.'
          : 'L’école n’a pas trouvé cette demande : elle n’a pas été appliquée. Vous pouvez arrêter son suivi puis refaire la modification.'
        : failure.status === 401 ? 'Votre connexion a expiré. Reconnectez-vous, puis vérifiez à nouveau.'
          : failure.status === 403 ? 'Vos accès actuels ne permettent pas de consulter ce résultat. La demande reste suivie.'
            : 'Le résultat n’a pas pu être établi. La demande reste suivie : réessayez la vérification.';
      this.update(schoolId, { ...current, phase: restore, message, notRecorded, needsLogin: failure.status === 401 });
      return { status: 'pending', message };
    }
  }

  /** Stop following a request whose result stays unknown; only offered with an explicit warning. */
  release(schoolId: string) {
    const entry = this.get(schoolId);
    if (entry && entry.phase !== 'sending' && entry.phase !== 'verifying') this.update(schoolId, null);
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
