export type ReadState<T> = { status: 'loading' | 'ready' | 'error'; data: T | undefined; error: string | null };
export type ScopedReadState<T> = ReadState<T> & { scope: string };

/** Data can survive a refresh, never a change of the resource being displayed. */
export function readStateFor<T>(state: ScopedReadState<T>, scope: string): ReadState<T> {
  return state.scope === scope ? state : { status: 'loading', data: undefined, error: null };
}
