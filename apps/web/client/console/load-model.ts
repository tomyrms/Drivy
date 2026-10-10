export type ReadState<T> = {
  status: 'loading' | 'ready' | 'error';
  data: T | undefined;
  error: string | null;
  /** The read failed because the session ended: retrying is useless, signing in again is the way out. */
  needsLogin?: boolean;
};
export type ScopedReadState<T> = ReadState<T> & { scope: string };

/** Data can survive a refresh, never a change of the resource being displayed. */
export function readStateFor<T>(state: ScopedReadState<T>, scope: string): ReadState<T> {
  return state.scope === scope ? state : { status: 'loading', data: undefined, error: null };
}

/**
 * State after a failed read. A refusal or a missing resource (401, 403, 404) hides what was shown before;
 * any other failure keeps it, flagged as possibly stale by the caller.
 */
export function failedReadState<T>(previous: ScopedReadState<T>, scope: string, failure: { status?: number }, message: string): ScopedReadState<T> {
  const status = failure.status ?? 0;
  return {
    scope, status: 'error', error: message,
    data: [401, 403, 404].includes(status) ? undefined : readStateFor(previous, scope).data,
    ...(status === 401 ? { needsLogin: true } : {}),
  };
}
