import { afterEach, describe, expect, test, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { createCommand } from '../client/command-core.js';

/**
 * #106, décision L1 du 12 novembre 2026 : une demande restée en file n'est jamais supprimée ni renvoyée en silence, quelle que
 * soit la durée écoulée ; la personne la voit et choisit de la renvoyer ou d'arrêter son suivi. Aucune durée d'expiration.
 */
type Entry = { phase: string; command: unknown };
type Store = {
  submit(command: unknown, csrf: string): Promise<{ status: string }>;
  resend(schoolId: string, csrf: string, operationId?: string): Promise<{ status: string }>;
  release(schoolId: string, operationId?: string): void;
  get(schoolId: string, operationId?: string): Entry | undefined;
  getSnapshot(): { entries: ReadonlyMap<string, Entry> };
};
const storeModule = '../client/command-store.ts';
const storageKey = 'drivy-gestion-demandes-v1';
const schoolId = randomUUID(), member = randomUUID();
const DAY = 86_400_000;
const memory = () => {
  const items = new Map<string, string>();
  return { items, getItem: (key: string) => items.get(key) ?? null, removeItem: (key: string) => { items.delete(key); }, setItem: (key: string, value: string) => { items.set(key, value); } };
};
let calls: { method: string; headers: Record<string, string> }[] = [];
const answer = (status: number, body: unknown) => vi.fn(async (input: URL | string, init?: RequestInit) => {
  calls.push({ method: init?.method ?? 'GET', headers: (init?.headers ?? {}) as Record<string, string> });
  return { status, ok: status >= 200 && status < 300, url: String(input), headers: new Headers({ 'content-type': 'application/json' }), json: async () => body };
});
async function open(session: ReturnType<typeof memory>): Promise<Store> {
  vi.resetModules();
  vi.stubGlobal('window', { location: { origin: 'https://drivy.example' }, sessionStorage: session, localStorage: memory() });
  return (await import(/* @vite-ignore */ storeModule) as { commandStore: Store }).commandStore;
}
const change = () => createCommand({ schoolId, kind: 'updateMember', path: `members/${member}`, ifMatch: 4, resourceId: member, resourceVersion: 4,
  body: { roles: ['INSTRUCTOR'], grants: ['TAKE_ATTENDANCE'], reason: 'Changement de fonction' } });

afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); calls = []; });

describe('L1 : garder et demander, sans durée d\'expiration', () => {
  test('une demande à vérifier reste suivie après des mois, sans aucun envoi de plus, et ne repart que sur le geste de la personne', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-11-12T08:00:00Z'));
    const store = await open(memory()), command = change();
    vi.stubGlobal('fetch', answer(503, { code: 'SERVICE_UNAVAILABLE' }));
    await store.submit(command, 'csrf');
    expect(calls).toHaveLength(1);
    for (const days of [1, 30, 400, 3650]) {
      vi.setSystemTime(new Date(Date.parse('2026-11-12T08:00:00Z') + days * DAY));
      expect(store.get(schoolId, command.operationId)).toMatchObject({ phase: 'uncertain' });
    }
    expect(calls).toHaveLength(1);
    vi.stubGlobal('fetch', answer(200, { data: { id: member, schoolId, version: 5 }, requestId: randomUUID(), serverTime: '2036-11-12T08:00:00.000Z' }));
    calls = [];
    await expect(store.resend(schoolId, 'csrf', command.operationId)).resolves.toMatchObject({ status: 'confirmed' });
    expect(calls).toHaveLength(1);
    expect(calls[0]!.headers['Idempotency-Key']).toBe(command.operationId);
  });

  test('rechargée des mois plus tard, la demande est montrée comme à vérifier : rien n\'est supprimé ni renvoyé tout seul', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-11-12T08:00:00Z'));
    const session = memory();
    const before = await open(session), command = change();
    vi.stubGlobal('fetch', answer(503, { code: 'SERVICE_UNAVAILABLE' }));
    await before.submit(command, 'csrf');
    calls = [];
    vi.setSystemTime(new Date('2028-01-01T08:00:00Z'));
    const fetcher = answer(200, { data: { id: member, schoolId, version: 5 } });
    vi.stubGlobal('fetch', fetcher);
    const after = await open(session);
    expect(after.get(schoolId, command.operationId)).toMatchObject({ phase: 'orphaned', command: null });
    expect(JSON.parse(session.items.get(storageKey)!)).toHaveLength(1);
    // Ni à la lecture, ni à l'appel de renvoi sur une entrée sans contenu : aucun paquet.
    await expect(after.resend(schoolId, 'csrf', command.operationId)).resolves.toMatchObject({ status: 'pending' });
    expect(fetcher).not.toHaveBeenCalled();
    expect(after.get(schoolId, command.operationId)).toBeDefined();
  });

  test('seul l’arrêt du suivi demandé par la personne retire une demande rechargée, y compris de ce qui est gardé', async () => {
    const session = memory();
    const first = await open(session), command = change();
    vi.stubGlobal('fetch', answer(503, { code: 'SERVICE_UNAVAILABLE' }));
    await first.submit(command, 'csrf');
    const store = await open(session);
    expect(JSON.parse(session.items.get(storageKey)!)).toHaveLength(1);
    expect(store.get(schoolId, command.operationId)).toBeDefined();
    store.release(schoolId, command.operationId);
    expect(store.get(schoolId, command.operationId)).toBeUndefined();
    expect(JSON.parse(session.items.get(storageKey)!)).toHaveLength(0);
  });
});
