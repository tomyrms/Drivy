import { useCallback, useState, type SetStateAction } from 'react';
import { useConsole } from './context';

/** List context lives only in the authenticated school’s memory; never in URLs or browser storage. */
export function useListState<T>(key: string, initial: T | (() => T)) {
  const { drafts } = useConsole();
  const storageKey = `list/${key}`;
  const read = (): T => drafts?.has(storageKey) ? drafts.get(storageKey) as T
    : typeof initial === 'function' ? (initial as () => T)() : initial;
  const [state, setState] = useState(() => ({ owner: drafts, key: storageKey, value: read() }));
  // A changed school, access epoch or list never renders the preceding context, even for one frame.
  const value = state.owner === drafts && state.key === storageKey ? state.value : read();
  const update = useCallback((action: SetStateAction<T>) => {
    setState(previous => {
      const before = previous.owner === drafts && previous.key === storageKey ? previous.value : read();
      const next = typeof action === 'function' ? (action as (previous: T) => T)(before) : action;
      drafts?.set(storageKey, next);
      return { owner: drafts, key: storageKey, value: next };
    });
  }, [drafts, storageKey]);
  return [value, update] as const;
}
