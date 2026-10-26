import { createContext, useCallback, useContext, useEffect, useId, useRef, useState } from 'react';
import type { SchoolCommand } from '../command-core';
import { commandMessage } from '../command-core';
import { commandRefreshesSchool } from '../command-conflicts';
import { commandStore, useCommandSnapshot, type PendingEntry, type SubmitResult } from '../command-store';
import { errorMessage, RequestFailure } from '../protocol';
import type { Member, Me } from '../protocol';
import type { School } from '../school-api';
import type { NavigationQuery } from './route';
import type { SectionKey } from './sections';
import { resumableDraft } from './draft-model';
import { failedReadState, readStateFor, type ScopedReadState, type ScopedReadCache } from './load-model';
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
  navigate: (section: SectionKey, query?: NavigationQuery, options?: { replace?: boolean }) => void;
  setNavigationGuard?: (guard: ((proceed: () => void) => void) | null) => void;
  registerUnsavedChanges?: (id: string) => () => void;
  confirmNavigation?: (proceed: () => void) => void;
  routeQuery?: NavigationQuery;
  /** `keepForms` : navigation interne à une section qui reste montée avec ses formulaires (rubriques d'une fiche). */
  setRouteQuery?: (query: NavigationQuery, replace?: boolean, keepForms?: boolean) => void;
  /** Unsent catalogue drafts, memory only, renewed with the authenticated school/access scope. */
  drafts?: Map<string, unknown>;
  /** Memory cache, replaced and purged whenever account, school, membership or access epoch changes. */
  readCache?: ScopedReadCache;
  /** Sign in within Drivy; step-up preserves the same account and any reviewed form. */
  login: (options?: { reauthenticate?: boolean }) => void;
  confirmIdentity?: () => Promise<boolean>;
}

export const ConsoleContext = createContext<ConsoleContextValue | null>(null);
export function useConsole(): ConsoleContextValue {
  const value = useContext(ConsoleContext);
  if (!value) throw new Error('Console absente.');
  return value;
}

/** Memory-only registration; multiple forms can protect navigation without replacing each other's guard. */
export function useUnsavedChanges(dirty: boolean) {
  const context = useContext(ConsoleContext), id = useId();
  const register = context?.registerUnsavedChanges;
  const release = useRef<(() => void) | undefined>(undefined);
  useEffect(() => {
    if (dirty && register) release.current = register(id);
    return () => { release.current?.(); release.current = undefined; };
  }, [dirty, register, id]);
  return () => { release.current?.(); release.current = undefined; };
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

/** Keep a form during contextual navigation; configuration editors may protect only effective changes. */
export function useSectionDraft<T>(key: string, shouldProtectDraft: (draft: T) => boolean = () => true) {
  const { drafts, routeQuery } = useConsole();
  const [draft, setDraft] = useState<T | null>(() => resumableDraft<T>(drafts?.get(key), routeQuery));
  const current = useRef(draft);
  const releaseGuard = useUnsavedChanges(draft !== null && shouldProtectDraft(draft));
  useEffect(() => {
    const restored = resumableDraft<T>(drafts?.get(key), routeQuery);
    current.current = restored; setDraft(restored);
  }, [drafts, key, routeQuery?.selection, routeQuery?.category]);
  const update = (value: T | null | ((previous: T | null) => T | null)) => {
    const next = typeof value === 'function' ? (value as (previous: T | null) => T | null)(current.current) : value;
    if (next === null) releaseGuard();
    current.current = next;
    if (next === null) drafts?.delete(key); else drafts?.set(key, next);
    setDraft(next);
  };
  return [draft, update] as const;
}

export function readError(error: unknown): string {
  if (error instanceof RequestFailure) {
    if (error.code === 'SETUP_ACCESS_REQUIRED' || error.code === 'ACCESS_DENIED') return 'Cette partie est réservée à l’administration de l’école. Vos accès ont peut-être changé : actualisez la page.';
    if (error.code === 'OBSERVATION_THEMES_ACCESS_REQUIRED') return 'Vos accès ne permettent pas de consulter les signalements.';
    if (error.code === 'INVALID_CURSOR') return 'Cette liste a changé. Rechargez-la pour continuer.';
    if (error.code === 'SETUP_NOT_INITIALIZED') return commandMessage(error.code);
    if (error.status === 404) return 'Cette information n’est pas disponible avec vos accès actuels.';
  }
  return errorMessage(error);
}

export type Loaded<T> = {
  status: 'loading' | 'ready' | 'error'; data: T | undefined; error: string | null; needsLogin?: boolean; reload: () => void;
  /** Re-read in the background: what is shown stays on screen (no loading state) until the answer replaces it. */
  refresh?: () => void;
  /** When the data on screen was last read successfully, in milliseconds. */
  readAt?: number;
};

/** Keep the same resource during refresh; hide the previous resource immediately when scope changes. */
export function useLoad<T>(loader: () => Promise<T>, deps: readonly unknown[], scope = String(deps[0] ?? ''), resourceKey?: string): Loaded<T> {
  const context = useContext(ConsoleContext);
  const cache = context?.readCache;
  const cacheKey = resourceKey === undefined ? undefined : `${scope}/${resourceKey}`;
  const accessScope = context ? `${context.me.personId}/${context.membership.membershipId}/${context.membership.accessEpoch}/${scope}` : scope;
  const restored = cacheKey === undefined ? undefined : cache?.peek<T>(cacheKey);
  const [state, setState] = useState<ScopedReadState<T> & { readAt?: number }>({ scope: accessScope,
    status: restored ? 'ready' : 'loading', data: restored?.value, error: null, ...(restored ? { readAt: restored.readAt } : {}) });
  const generation = useRef(0);
  const inFlight = useRef(false);
  const lastLoader = useRef<(() => Promise<T>) | null>(null);
  const run = useCallback(loader, deps);
  const start = useCallback((silent: boolean, force = false) => {
    const current = ++generation.current;
    inFlight.current = true;
    if (cache && cacheKey !== undefined && (force || lastLoader.current !== null && lastLoader.current !== run)) cache.invalidate(cacheKey);
    lastLoader.current = run;
    if (!silent) setState(previous => {
      const retained = readStateFor(previous, accessScope).data ?? (cacheKey === undefined ? undefined : cache?.peek<T>(cacheKey)?.value);
      return { scope: accessScope, status: retained === undefined ? 'loading' : 'ready', data: retained, error: null,
        ...(previous.scope === accessScope && previous.readAt !== undefined ? { readAt: previous.readAt } : {}) };
    });
    const request = cache && cacheKey !== undefined ? cache.read(cacheKey, run) : run();
    request.then(data => { if (current === generation.current) { inFlight.current = false; setState({ scope: accessScope, status: 'ready', data, error: null, readAt: Date.now() }); } },
      error => { if (current === generation.current) { inFlight.current = false; setState(previous => {
        const failed = failedReadState(previous, accessScope, error instanceof RequestFailure ? error : {}, readError(error));
        // Kept data keeps the time it was read: the screen tells how old it is.
        return failed.data !== undefined && previous.scope === accessScope && previous.readAt !== undefined ? { ...failed, readAt: previous.readAt } : failed;
      }); } });
  }, [run, accessScope, cache, cacheKey]);
  const reload = useCallback(() => start(false, true), [start]);
  // A background refresh never overlaps a read in progress: the newest answer would be thrown away anyway.
  const refresh = useCallback(() => { if (!inFlight.current) start(true, true); }, [start]);
  useEffect(() => { start(false); return () => { generation.current++; inFlight.current = false; }; }, [start]);
  const visible = readStateFor(state, accessScope);
  return { ...visible, reload, refresh, ...(state.scope === accessScope && state.readAt !== undefined ? { readAt: state.readAt } : {}) };
}

/** Draft that follows the school's value until the person edits it. */
export function useDraft<T>(baseline: T | null) {
  const [draft, setDraft] = useState<T | null>(baseline);
  const [acknowledged, setAcknowledged] = useState<string | null>(null);
  const previous = useRef<string | null>(baseline === null ? null : JSON.stringify(baseline));
  const serialized = baseline === null ? null : JSON.stringify(baseline);
  useEffect(() => {
    if (serialized === null) return;
    const before = previous.current;
    setDraft(current => current === null || before === null || JSON.stringify(current) === before ? JSON.parse(serialized) as T : current);
    previous.current = serialized;
    setAcknowledged(null);
  }, [serialized]);
  const saved = acknowledged ?? serialized;
  const edited = draft !== null && saved !== null && JSON.stringify(draft) !== saved;
  const releaseGuard = useUnsavedChanges(edited);
  const reset = () => { releaseGuard(); if (saved !== null) setDraft(JSON.parse(saved) as T); };
  const markSaved = (value: T) => { releaseGuard(); setDraft(value); setAcknowledged(JSON.stringify(value)); };
  return { draft, setDraft: setDraft as (update: T | ((value: T | null) => T | null)) => void, edited, reset, markSaved };
}

export type Outcome = { tone: 'success' | 'error' | 'warning'; title: string; message: string; code?: string; needsLogin?: boolean } | null;

/**
 * Submit one command through the shared store and report its real outcome to the section.
 * `onConfirmed` runs once the school confirms this section's request, by response or by AP72 receipt.
 */
export function useCommandRunner(onConfirmed?: () => void) {
  const context = useConsole();
  const snapshot = useCommandSnapshot();
  const [busy, setBusy] = useState(false);
  const [outcome, setOutcome] = useState<Outcome>(null);
  const submitted = useRef<string | null>(null);
  const pending: PendingEntry | undefined = submitted.current ? snapshot.entries.get(submitted.current) : undefined;
  const callback = useRef(onConfirmed);
  callback.current = onConfirmed;
  const confirmed = snapshot.confirmations.find(item => item.operationId === submitted.current);
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
      if (commandRefreshesSchool(command.kind)) void context.reloadSchool();
    } else if (result.status === 'rejected') {
      submitted.current = null;
      if (draftKey && unsentDraft !== undefined) context.drafts?.set(draftKey, unsentDraft);
      setOutcome({ tone: 'error', title: result.code.startsWith('LOCAL_COMMAND_') ? 'Modification en attente' : 'Modification refusée', message: result.needsLogin ? result.message : `${result.message} Votre saisie est conservée.`, code: result.code, needsLogin: result.needsLogin });
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
