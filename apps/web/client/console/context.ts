import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import type { SchoolCommand } from '../command-core';
import { commandMessage } from '../command-core';
import { commandStore, useCommandSnapshot, type PendingEntry, type SubmitResult } from '../command-store';
import { errorMessage, RequestFailure } from '../protocol';
import type { Member, Me } from '../protocol';
import type { School } from '../school-api';
import type { NavigationQuery } from './route';
import type { SectionKey } from './sections';
import { resumableDraft } from './draft-model';
import { readStateFor, type ScopedReadState } from './load-model';
export { sectionKeys, type SectionKey } from './sections';

export interface ConsoleContextValue {
  schoolId: string;
  me: Me;
  membership: Member;
  school: School;
  /** Rights read from /v1/me for display only; the API decides on every request. */
  canConfigureCatalog: boolean;
  reloadSchool: () => Promise<void>;
  csrf: () => string;
  refreshCsrf: () => Promise<string>;
  navigate: (section: SectionKey, query?: NavigationQuery) => void;
  routeQuery?: NavigationQuery;
  setRouteQuery?: (query: NavigationQuery, replace?: boolean) => void;
  /** Unsent catalogue drafts, memory only, renewed with the authenticated school/access scope. */
  drafts?: Map<string, unknown>;
  /** Sign in again with the same account; `reauthenticate` forces the identity provider to ask for the password. */
  login: (options?: { reauthenticate?: boolean }) => void;
}

export const ConsoleContext = createContext<ConsoleContextValue | null>(null);
export function useConsole(): ConsoleContextValue {
  const value = useContext(ConsoleContext);
  if (!value) throw new Error('Console absente.');
  return value;
}

/** Selection survives reload/back; only an identifier enters browser history. */
export function useRouteSelection() {
  const { routeQuery, setRouteQuery } = useConsole();
  const [local, setLocal] = useState<string | null>(routeQuery?.selection ?? null);
  const selected = routeQuery ? routeQuery.selection ?? null : local;
  const select = (selection: string | null) => {
    setLocal(selection);
    setRouteQuery?.({ ...routeQuery, selection: selection ?? undefined });
  };
  return [selected, select] as const;
}

/** Keep a catalogue form during contextual navigation, never across reload/sign-out. */
export function useSectionDraft<T>(key: string) {
  const { drafts, routeQuery } = useConsole();
  const [draft, setDraft] = useState<T | null>(() => resumableDraft<T>(drafts?.get(key), routeQuery));
  const current = useRef(draft);
  useEffect(() => {
    const restored = resumableDraft<T>(drafts?.get(key), routeQuery);
    current.current = restored; setDraft(restored);
  }, [drafts, key, routeQuery?.selection, routeQuery?.category]);
  const update = (value: T | null | ((previous: T | null) => T | null)) => {
    const next = typeof value === 'function' ? (value as (previous: T | null) => T | null)(current.current) : value;
    current.current = next;
    if (next === null) drafts?.delete(key); else drafts?.set(key, next);
    setDraft(next);
  };
  return [draft, update] as const;
}

export function readError(error: unknown): string {
  if (error instanceof RequestFailure) {
    if (error.code === 'SETUP_ACCESS_REQUIRED' || error.code === 'ACCESS_DENIED') return 'Cette partie est réservée à l’administration de l’école. Vos accès ont peut-être changé : actualisez la page.';
    if (error.code === 'INVALID_CURSOR') return 'Cette liste a changé. Rechargez-la pour continuer.';
    if (error.code === 'SETUP_NOT_INITIALIZED') return commandMessage(error.code);
    if (error.status === 404) return 'Cette information n’est pas disponible avec vos accès actuels.';
  }
  return errorMessage(error);
}

export type Loaded<T> = { status: 'loading' | 'ready' | 'error'; data: T | undefined; error: string | null; reload: () => void };

/** Keep the same resource during refresh; hide the previous resource immediately when scope changes. */
export function useLoad<T>(loader: () => Promise<T>, deps: readonly unknown[], scope = String(deps[0] ?? '')): Loaded<T> {
  const [state, setState] = useState<ScopedReadState<T>>({ scope, status: 'loading', data: undefined, error: null });
  const generation = useRef(0);
  const run = useCallback(loader, deps);
  const reload = useCallback(() => {
    const current = ++generation.current;
    setState(previous => ({ scope, status: 'loading', data: readStateFor(previous, scope).data, error: null }));
    run().then(data => { if (current === generation.current) setState({ scope, status: 'ready', data, error: null }); },
      error => { if (current === generation.current) setState(previous => ({ status: 'error',
        scope, data: error instanceof RequestFailure && [401, 403, 404].includes(error.status ?? 0) ? undefined : readStateFor(previous, scope).data,
        error: readError(error) })); });
  }, [run, scope]);
  useEffect(() => { reload(); return () => { generation.current++; }; }, [reload]);
  return { ...readStateFor(state, scope), reload };
}

/** Draft that follows the school's value until the person edits it. */
export function useDraft<T>(baseline: T | null) {
  const [draft, setDraft] = useState<T | null>(baseline);
  const previous = useRef<string | null>(baseline === null ? null : JSON.stringify(baseline));
  const serialized = baseline === null ? null : JSON.stringify(baseline);
  useEffect(() => {
    if (serialized === null) return;
    const before = previous.current;
    setDraft(current => current === null || before === null || JSON.stringify(current) === before ? JSON.parse(serialized) as T : current);
    previous.current = serialized;
  }, [serialized]);
  const edited = draft !== null && serialized !== null && JSON.stringify(draft) !== serialized;
  const reset = useCallback(() => { if (serialized !== null) setDraft(JSON.parse(serialized) as T); }, [serialized]);
  return { draft, setDraft: setDraft as (update: T | ((value: T | null) => T | null)) => void, edited, reset };
}

export type Outcome = { tone: 'success' | 'error' | 'warning'; title: string; message: string; code?: string; needsLogin?: boolean } | null;

/**
 * Submit one command through the shared store and report its real outcome to the section.
 * `onConfirmed` runs once the school confirms this section's request, by response or by AP72 receipt.
 */
export function useCommandRunner(onConfirmed?: () => void) {
  const context = useConsole();
  const snapshot = useCommandSnapshot();
  const pending: PendingEntry | undefined = snapshot.entries.get(context.schoolId);
  const [busy, setBusy] = useState(false);
  const [outcome, setOutcome] = useState<Outcome>(null);
  const submitted = useRef<string | null>(null);
  const callback = useRef(onConfirmed);
  callback.current = onConfirmed;
  const confirmed = snapshot.confirmed;
  useEffect(() => {
    if (!confirmed || confirmed.operationId !== submitted.current) return;
    submitted.current = null;
    callback.current?.();
  }, [confirmed]);

  async function run(command: SchoolCommand, success: string): Promise<SubmitResult> {
    setBusy(true); setOutcome(null);
    submitted.current = command.operationId;
    // Once sent, the command store owns recovery. Do not resurrect this form as a
    // new version after a receipt confirms it while its section is unmounted.
    const draftKey = ({ createCurriculum: 'curriculum', createCatalogPolicy: 'procedure', createOffering: 'offering',
      createCommercialTerms: 'terms', createServiceProduct: 'product' } as Partial<Record<SchoolCommand['kind'], string>>)[command.kind];
    const unsentDraft = draftKey ? context.drafts?.get(draftKey) : undefined;
    if (draftKey) context.drafts?.delete(draftKey);
    const result = await commandStore.submit(command, context.csrf());
    setBusy(false);
    if (result.status === 'confirmed') {
      setOutcome({ tone: 'success', title: 'Confirmé par l’école', message: success });
      void context.reloadSchool();
    } else if (result.status === 'rejected') {
      submitted.current = null;
      if (draftKey && unsentDraft !== undefined) context.drafts?.set(draftKey, unsentDraft);
      setOutcome({ tone: 'error', title: 'Modification refusée', message: result.needsLogin ? result.message : `${result.message} Votre saisie est conservée.`, code: result.code, needsLogin: result.needsLogin });
    } else {
      // The pending panel at the top of the page carries the verification; move focus there.
      window.requestAnimationFrame(() => document.getElementById('pending-title')?.focus());
    }
    return result;
  }
  return {
    run, busy: busy || pending?.phase === 'sending', pending, outcome, clearOutcome: () => setOutcome(null),
    /** Explanation shown next to disabled write controls while a request waits for its result. */
    blockedReason: pending ? 'Une demande attend la vérification de son résultat (voir en haut de la page).' : null,
  };
}
