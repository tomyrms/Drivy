import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { createCommand } from '../client/command-core.js';

/**
 * #106, critère « multi-onglets » : le suivi ne vit que dans le sessionStorage de l'onglet et son contenu seulement en
 * mémoire. Un onglet dupliqué hérite des identifiants, jamais du corps : il peut vérifier un reçu en lecture, pas
 * renvoyer, et l'onglet d'origine renvoie toujours la même clé.
 */
type Store = {
  submit(command: unknown, csrf: string): Promise<{ status: string }>;
  verify(schoolId: string, operationId?: string): Promise<{ status: string }>;
  resend(schoolId: string, csrf: string, operationId?: string): Promise<{ status: string }>;
  get(schoolId: string, operationId?: string): { phase: string; command: unknown } | undefined;
  clear(): void;
};
type Actions = (entry: { command: unknown; phase: string; notRecorded: boolean; unverifiable: boolean }) => { resend: boolean; release: boolean };
const storeModule = '../client/command-store.ts';
const schoolId = randomUUID();
const memory = (initial?: Map<string, string>) => {
  const items = new Map<string, string>(initial);
  return { getItem: (key: string) => items.get(key) ?? null, removeItem: (key: string) => { items.delete(key); },
    setItem: (key: string, value: string) => { items.set(key, value); }, items };
};
const envelope = (data: unknown) => ({ data, requestId: randomUUID(), serverTime: '2026-11-11T08:00:00.000Z' });
type Call = { method: string; key: string | undefined; body: string | undefined; path: string };
let calls: Call[] = [];
function answer(status: number, body: unknown) {
  return vi.fn(async (input: URL | string, init?: RequestInit) => {
    calls.push({ method: init?.method ?? 'GET', path: new URL(String(input)).pathname,
      key: (init?.headers as Record<string, string> | undefined)?.['Idempotency-Key'], body: init?.body as string | undefined });
    return { status, ok: status >= 200 && status < 300, url: String(input), headers: new Headers({ 'content-type': 'application/json' }), json: async () => body };
  });
}
let actions: Actions;
async function openTab(session: ReturnType<typeof memory>): Promise<Store> {
  vi.resetModules();
  vi.stubGlobal('window', { location: { origin: 'https://drivy.example' }, sessionStorage: session, localStorage: memory() });
  const module = await import(/* @vite-ignore */ storeModule) as { commandStore: Store; pendingActions: Actions };
  actions = module.pendingActions;
  return module.commandStore;
}
const change = () => createCommand({ schoolId, kind: 'updateModules', path: 'modules', ifMatch: 4, resourceVersion: 4, body: { gpsEnabled: true } });

beforeEach(() => { calls = []; });
afterEach(() => { vi.unstubAllGlobals(); });

describe('Onglet dupliqué : aucun rejeu depuis des identifiants seuls', () => {
  test('l\'onglet copié retrouve la demande sans contenu : il vérifie en lecture, ne renvoie pas', async () => {
    const original = memory(), command = change();
    const tabA = await openTab(original);
    vi.stubGlobal('fetch', answer(503, { code: 'SERVICE_UNAVAILABLE' }));
    await tabA.submit(command, 'csrf');
    expect(tabA.get(schoolId)).toMatchObject({ phase: 'uncertain' });
    expect(calls.map(call => call.method)).toEqual(['PUT']);

    // « Dupliquer l'onglet » copie le sessionStorage tel quel ; la mémoire du premier onglet n'est pas copiée.
    const tabB = await openTab(memory(new Map(original.items)));
    const copy = tabB.get(schoolId)!;
    expect(copy).toMatchObject({ phase: 'orphaned', command: null });
    expect(actions(copy as never).resend).toBe(false);

    calls = [];
    vi.stubGlobal('fetch', answer(404, { code: 'NOT_FOUND' }));
    await tabB.verify(schoolId);
    expect(calls.length).toBeGreaterThan(0);
    expect(calls.every(call => call.method === 'GET' && call.body === undefined)).toBe(true);
    tabB.clear();
  });

  test('l\'onglet d\'origine renvoie la même clé et le même corps, l\'onglet copié n\'y change rien', async () => {
    const original = memory(), command = change();
    const tabA = await openTab(original);
    vi.stubGlobal('fetch', answer(503, { code: 'SERVICE_UNAVAILABLE' }));
    await tabA.submit(command, 'csrf');
    const first = calls[0]!;

    await openTab(memory(new Map(original.items)));
    const back = await openTab(original);
    // Le magasin rechargé de l'onglet d'origine est lui aussi sans contenu : seul un magasin resté vivant renvoie.
    expect(back.get(schoolId)).toMatchObject({ command: null });

    const live = await openTab(memory());
    vi.stubGlobal('fetch', answer(503, { code: 'SERVICE_UNAVAILABLE' }));
    await live.submit(command, 'csrf');
    calls = [];
    vi.stubGlobal('fetch', answer(200, envelope({ id: schoolId, schoolId, version: 5 })));
    expect((await live.resend(schoolId, 'csrf')).status).toBe('confirmed');
    expect(calls).toHaveLength(1);
    expect(calls[0]).toMatchObject({ method: first.method, key: first.key, body: first.body, path: first.path });
    live.clear();
  });
});
