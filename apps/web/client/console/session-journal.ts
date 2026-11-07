import { useCallback, useMemo, useSyncExternalStore } from 'react';
import { useConsole } from './context';

/**
 * Journal de session (#430) : listes en mémoire (intentions gardées, refus à reprendre) posées dans les brouillons de la console,
 * donc renouvelées avec le compte, l'école, le rattachement et l'époque d'accès, et jamais écrites dans le stockage du navigateur.
 * Une réponse qui arrive après la fermeture de la page écrit ici, pas dans un état de composant démonté : en revenant, la saisie
 * et le motif du refus sont encore là. Chaque mise à jour relit le journal au moment d'écrire, jamais une copie d'une page quittée.
 */
type Store = Map<string, unknown>;
const listeners = new WeakMap<Store, Map<string, Set<() => void>>>();
const EMPTY: readonly never[] = [];

export function readJournal<T>(store: Store | undefined, key: string): readonly T[] {
  return (store?.get(key) as readonly T[] | undefined) ?? EMPTY;
}

export function updateJournal<T>(store: Store | undefined, key: string, next: (items: readonly T[]) => readonly T[]): readonly T[] {
  const current = readJournal<T>(store, key);
  const updated = next(current);
  if (!store || updated === current) return current;
  store.set(key, updated);
  for (const listener of listeners.get(store)?.get(key) ?? []) listener();
  return updated;
}

function subscribeJournal(store: Store | undefined, key: string, listener: () => void): () => void {
  if (!store) return () => {};
  let byKey = listeners.get(store);
  if (!byKey) { byKey = new Map(); listeners.set(store, byKey); }
  let set = byKey.get(key);
  if (!set) { set = new Set(); byKey.set(key, set); }
  set.add(listener);
  return () => { set.delete(listener); };
}

/**
 * Liste du journal sous `key`. `update` est liée aux brouillons de la page qui l'a obtenue : appelée après un changement de compte
 * ou d'école, elle écrit dans l'ancien journal et ne révèle rien au nouveau.
 */
export function useJournal<T>(key: string) {
  const { drafts } = useConsole();
  // Sans brouillons de console (aperçu isolé), un journal propre à la page.
  const store = useMemo<Store | undefined>(() => drafts ?? new Map<string, unknown>(), [drafts]);
  const subscribe = useCallback((listener: () => void) => subscribeJournal(store, key, listener), [store, key]);
  const list = useSyncExternalStore(subscribe, () => readJournal<T>(store, key));
  const update = useCallback((next: (items: readonly T[]) => readonly T[]) => updateJournal<T>(store, key, next), [store, key]);
  return [list, update] as const;
}
