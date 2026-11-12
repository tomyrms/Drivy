import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { createCommand } from '../client/command-core.js';
import { saveStatus, ScopedDrafts } from '../client/console/observation-preferences-model.js';

/**
 * Deux gardes de #468, prouvées contre le vrai magasin de commandes et le vrai modèle :
 * un brouillon d'un autre compte n'est jamais affiché, et un envoi au sort incertain n'est jamais « Enregistré » sans confirmation.
 */
type Store = {
  submit(command: unknown, csrf: string): Promise<{ status: string; code?: string }>;
  verify(schoolId: string): Promise<{ status: string }>;
  get(schoolId: string, operationId?: string): { phase: string } | undefined;
  getSnapshot(): { confirmations: unknown[] };
  scopeToPerson(personId: string): boolean;
  scopeToAccess(schoolId: string, membershipId: string, accessEpoch: number): void;
};
const schoolId = randomUUID();
const memory = () => { const items = new Map<string, string>(); return { getItem: (k: string) => items.get(k) ?? null, removeItem: (k: string) => { items.delete(k); }, setItem: (k: string, v: string) => { items.set(k, v); } }; };
const storeModule = '../client/command-store.ts';
async function loadStore(): Promise<Store> {
  vi.resetModules();
  return (await import(/* @vite-ignore */ storeModule) as { commandStore: Store }).commandStore;
}
const lost = () => vi.fn(async () => { throw new TypeError('réseau perdu'); });
const save = (version = 3) => createCommand({ schoolId, kind: 'saveObservationPreferences', path: 'observation-preferences', ifMatch: version, resourceVersion: version,
  resourceId: randomUUID(), body: { order: ['observation'] } });

beforeEach(() => { vi.stubGlobal('window', { location: { origin: 'https://drivy.example' }, sessionStorage: memory(), localStorage: memory() }); });
afterEach(() => { vi.unstubAllGlobals(); });

describe('Un envoi au sort incertain n’est jamais « Enregistré »', () => {
  test('une réponse perdue reste en attente, sans confirmation, et la barre dit « Résultat à vérifier »', async () => {
    const store = await loadStore(), command = save();
    vi.stubGlobal('fetch', lost());
    const result = await store.submit(command, 'csrf');
    expect(result.status).toBe('pending');
    expect(store.getSnapshot().confirmations).toHaveLength(0);
    expect(store.get(schoolId)?.phase).toBe('uncertain');
    // Même si l'écran croit une action terminée, l'envoi encore suivi passe devant.
    expect(saveStatus({ busy: false, pending: true, done: 'save', dirty: true })).toBe('Résultat à vérifier');
  });

  test('une vérification sans reçu ne confirme rien ; seul le reçu de la même opération confirme', async () => {
    const store = await loadStore(), command = save();
    vi.stubGlobal('fetch', lost());
    await store.submit(command, 'csrf');
    vi.stubGlobal('fetch', vi.fn(async (input: string | URL) => ({ status: 404, ok: false, url: String(input), headers: new Headers({ 'content-type': 'application/json' }), json: async () => ({ code: 'NOT_FOUND' }) })));
    expect((await store.verify(schoolId)).status).not.toBe('confirmed');
    expect(store.getSnapshot().confirmations).toHaveLength(0);
  });

  test('« Enregistré » exige une confirmation et aucun envoi en cours', () => {
    expect(saveStatus({ busy: false, pending: false, done: null, dirty: true })).toBe('Modifications non enregistrées');
    expect(saveStatus({ busy: true, pending: false, done: null, dirty: true })).toBe('Enregistrement…');
    expect(saveStatus({ busy: false, pending: false, done: 'save', dirty: false })).toBe('Enregistré');
    expect(saveStatus({ busy: false, pending: false, done: 'presentation', dirty: false })).toBeNull();
  });
});

describe('Le brouillon d’un autre compte n’est jamais affiché', () => {
  test('changer de portée donne un magasin vide, et y revenir n’en ressuscite rien', () => {
    const store = new ScopedDrafts();
    const alice = `${randomUUID()}/${schoolId}/m1/1`, bob = `${randomUUID()}/${schoolId}/m2/1`;
    store.forScope(alice).set('observation-preferences', { version: 3, rows: ['brouillon d’Alice'] });
    expect(store.forScope(alice).get('observation-preferences')).toBeDefined();
    expect(store.forScope(bob).size).toBe(0);
    expect(store.forScope(alice).size).toBe(0);
    // La même personne dans une autre école, ou avec un autre accès, repart aussi d’un état vide.
    store.forScope(alice).set('observation-preferences', { version: 3 });
    expect(store.forScope(`${alice.split('/')[0]}/${randomUUID()}/m1/1`).size).toBe(0);
    store.forScope(null);
    expect(store.forScope(alice).size).toBe(0);
  });

  test('le magasin de commandes oublie les envois suivis d’une autre personne', async () => {
    const store = await loadStore();
    const first = randomUUID(), second = randomUUID();
    store.scopeToPerson(first);
    store.scopeToAccess(schoolId, randomUUID(), 1);
    vi.stubGlobal('fetch', lost());
    await store.submit(save(), 'csrf');
    expect(store.get(schoolId)).toBeDefined();
    expect(store.scopeToPerson(second)).toBe(true);
    expect(store.get(schoolId)).toBeUndefined();
  });
});
