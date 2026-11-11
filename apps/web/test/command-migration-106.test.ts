import { afterEach, describe, expect, test, vi } from 'vitest';
import { randomUUID } from 'node:crypto';

/**
 * #106, critères « migration » et « retour arrière » avec une file remplie. Le suivi d'onglet est un tableau
 * d'identifiants sous une clé versionnée (`…-v1`). Une version plus récente ou plus ancienne du client peut avoir laissé
 * dans le stockage : des entrées en trop, des champs inconnus, un autre format sous une autre clé, du texte illisible.
 * La règle : ce qui est reconnu est repris sans corps (« à vérifier », jamais renvoyé), ce qui ne l'est pas est ignoré sans
 * exception, et ce qu'une autre version a écrit sous une autre clé n'est jamais effacé.
 */
type Entry = { phase: string; command: unknown; meta: { operationId: string } };
type Store = { get(schoolId: string, operationId?: string): Entry | undefined; clear(): void };
type Snapshot = { entries: ReadonlyMap<string, Entry>; metadata: { durability: string; last: string } };
const storageKey = 'drivy-gestion-demandes-v1';
const futureKey = 'drivy-gestion-demandes-v2';
const schoolId = randomUUID();
const memory = (initial: Record<string, string> = {}) => {
  const items = new Map<string, string>(Object.entries(initial));
  return { getItem: (key: string) => items.get(key) ?? null, removeItem: (key: string) => { items.delete(key); },
    setItem: (key: string, value: string) => { items.set(key, value); }, items };
};
const valid = (overrides: Record<string, unknown> = {}) =>
  ({ operationId: randomUUID(), schoolId, kind: 'updateModules', resourceVersion: 4, createdAt: 1_760_000_000_000, ...overrides });
async function reload(session: ReturnType<typeof memory>) {
  vi.resetModules();
  vi.stubGlobal('window', { location: { origin: 'https://drivy.example' }, sessionStorage: session, localStorage: memory() });
  const module = await import(/* @vite-ignore */ '../client/command-store.ts') as { commandStore: Store & { getSnapshot(): Snapshot } };
  return module.commandStore;
}
afterEach(() => { vi.unstubAllGlobals(); });

describe('File remplie rechargée par une autre version du client', () => {
  test('une file pleine est reprise telle quelle, plafonnée à 50, sans contenu et sans renvoi', async () => {
    const stored = Array.from({ length: 60 }, () => valid());
    const store = await reload(memory({ [storageKey]: JSON.stringify(stored) }));
    const entries = [...store.getSnapshot().entries.values()];
    expect(entries).toHaveLength(50);
    expect(entries.map(entry => entry.meta.operationId)).toEqual(stored.slice(0, 50).map(entry => entry.operationId));
    expect(entries.every(entry => entry.phase === 'orphaned' && entry.command === null)).toBe(true);
    expect(store.getSnapshot().metadata).toEqual({ durability: 'saved', last: 'read' });
  });

  test('les entrées d\'une autre version sont écartées une à une, les reconnues sont gardées', async () => {
    const keep = [valid(), valid({ createdAt: 1_760_000_000_001 })];
    const stored = [
      keep[0], { ...valid(), futureField: 'x' }, valid({ kind: 'kindFromTheFuture' }), valid({ operationId: 'pas-un-uuid' }),
      valid({ resourceVersion: -1 }), valid({ createdAt: 0 }), 'texte', 7, null, [], keep[1], keep[0],
    ];
    const store = await reload(memory({ [storageKey]: JSON.stringify(stored) }));
    expect([...store.getSnapshot().entries.keys()]).toEqual(keep.map(entry => entry.operationId));
    expect(store.get(schoolId, keep[0]!.operationId)).toMatchObject({ phase: 'orphaned', command: null });
  });

  test('un contenu illisible ou d\'un autre format ne lève pas et ne reprend rien', async () => {
    for (const raw of ['{pas du json', '{"version":2,"items":[]}', '"texte"', '42', 'null']) {
      const store = await reload(memory({ [storageKey]: raw }));
      expect(store.getSnapshot().entries.size).toBe(0);
    }
  });
});

describe('Retour arrière : ce qu\'une version plus récente a écrit n\'est pas détruit', () => {
  test('un format sous une autre clé est ignoré à la lecture et survit à l\'effacement de la file', async () => {
    const future = JSON.stringify({ version: 2, items: [{ id: randomUUID(), body: 'contenu réservé à la version suivante' }] });
    const session = memory({ [futureKey]: future, [storageKey]: JSON.stringify([valid()]) });
    const store = await reload(session);
    expect(store.getSnapshot().entries.size).toBe(1);
    store.clear();
    expect(session.items.has(storageKey)).toBe(false);
    expect(session.items.get(futureKey)).toBe(future);
    expect((await reload(session)).getSnapshot().entries.size).toBe(0);
  });

  test('sans clé reconnue, aucune entrée n\'est inventée à partir de l\'autre format', async () => {
    const session = memory({ [futureKey]: JSON.stringify([valid()]) });
    const store = await reload(session);
    expect(store.getSnapshot().entries.size).toBe(0);
    expect(session.items.get(futureKey)).toBeDefined();
  });
});
