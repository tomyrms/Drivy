import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import type { SchoolCommand } from '../command-core';
import { commandMessage } from '../command-core';
import { commandStore, useCommandSnapshot, type PendingEntry, type SubmitResult } from '../command-store';
import { errorMessage, RequestFailure } from '../protocol';
import type { Member, Me } from '../protocol';
import type { School } from '../school-api';

export const sectionKeys = ['apercu', 'configuration', 'champs-profil', 'offres', 'referentiels', 'procedures', 'prestations', 'conditions', 'equipe', 'invitations'] as const;
export type SectionKey = typeof sectionKeys[number];

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
  navigate: (section: SectionKey) => void;
  login: () => void;
}

export const ConsoleContext = createContext<ConsoleContextValue | null>(null);
export function useConsole(): ConsoleContextValue {
  const value = useContext(ConsoleContext);
  if (!value) throw new Error('Console absente.');
  return value;
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

/** Load with a generation guard: a late answer never replaces a newer one. Keeps the last data while reloading. */
export function useLoad<T>(loader: () => Promise<T>, deps: readonly unknown[]): Loaded<T> {
  const [state, setState] = useState<{ status: 'loading' | 'ready' | 'error'; data: T | undefined; error: string | null }>({ status: 'loading', data: undefined, error: null });
  const generation = useRef(0);
  const run = useCallback(loader, deps);
  const reload = useCallback(() => {
    const current = ++generation.current;
    setState(previous => ({ status: 'loading', data: previous.data, error: null }));
    run().then(data => { if (current === generation.current) setState({ status: 'ready', data, error: null }); },
      error => { if (current === generation.current) setState(previous => ({ status: 'error', data: previous.data, error: readError(error) })); });
  }, [run]);
  useEffect(() => { reload(); return () => { generation.current++; }; }, [reload]);
  return { ...state, reload };
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

export type Outcome = { tone: 'success' | 'error' | 'warning'; title: string; message: string; code?: string } | null;

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
    const result = await commandStore.submit(command, context.csrf());
    setBusy(false);
    if (result.status === 'confirmed') {
      setOutcome({ tone: 'success', title: 'Confirmé par l’école', message: success });
      void context.reloadSchool();
    } else if (result.status === 'rejected') {
      submitted.current = null;
      setOutcome({ tone: 'error', title: 'Modification refusée', message: `${result.message} Votre saisie est conservée.`, code: result.code });
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
