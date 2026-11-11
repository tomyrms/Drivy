import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { createCommand } from '../client/command-core.js';

/**
 * #131, écritures web de l'équipe sans test dédié (matrice W47 « modifier rôles et droits », W48 « retirer un accès ») :
 * ce que la commande envoie (méthode, chemin, précondition de version, clé d'idempotence), ce qu'elle fait d'un refus de
 * version, d'une réponse perdue et d'un second appui, et qu'un même membre ne reçoit jamais deux écritures à la fois.
 */
type Store = {
  submit(command: unknown, csrf: string): Promise<{ status: string; code?: string }>;
  resend(schoolId: string, csrf: string, operationId?: string): Promise<{ status: string }>;
  get(schoolId: string, operationId?: string): { phase: string } | undefined;
  clear(): void;
};
const storeModule = '../client/command-store.ts';
const schoolId = randomUUID(), member = randomUUID(), other = randomUUID();
const memory = () => {
  const items = new Map<string, string>();
  return { getItem: (key: string) => items.get(key) ?? null, removeItem: (key: string) => { items.delete(key); }, setItem: (key: string, value: string) => { items.set(key, value); } };
};
const envelope = (data: unknown) => ({ data, requestId: randomUUID(), serverTime: '2026-11-11T08:00:00.000Z' });
type Call = { method: string; path: string; headers: Record<string, string>; body: string | undefined };
let calls: Call[] = [];
function answer(status: number, body: unknown) {
  return vi.fn(async (input: URL | string, init?: RequestInit) => {
    calls.push({ method: init?.method ?? 'GET', path: new URL(String(input)).pathname, headers: (init?.headers ?? {}) as Record<string, string>, body: init?.body as string | undefined });
    return { status, ok: status >= 200 && status < 300, url: String(input), headers: new Headers({ 'content-type': 'application/json' }), json: async () => body };
  });
}
async function openStore(): Promise<Store> {
  vi.resetModules();
  vi.stubGlobal('window', { location: { origin: 'https://drivy.example' }, sessionStorage: memory(), localStorage: memory() });
  return (await import(/* @vite-ignore */ storeModule) as { commandStore: Store }).commandStore;
}
const change = (id = member, version = 4) => createCommand({ schoolId, kind: 'updateMember', path: `members/${id}`, ifMatch: version, resourceId: id, resourceVersion: version,
  body: { roles: ['INSTRUCTOR'], grants: ['TAKE_ATTENDANCE'], reason: 'Changement de fonction' } });
const removal = (id = member, version = 4) => createCommand({ schoolId, kind: 'deactivateMember', path: `members/${id}/deactivate`, ifMatch: version, resourceId: id,
  resourceVersion: version, body: { reason: 'Départ de l’école' } });

beforeEach(() => { calls = []; });
afterEach(() => { vi.unstubAllGlobals(); });

describe('W47 : modifier les rôles et les droits d\'un membre', () => {
  test('part en PATCH sur le membre, avec la version affichée et la clé de l\'opération', async () => {
    const store = await openStore(), command = change();
    vi.stubGlobal('fetch', answer(200, envelope({ id: member, schoolId, version: 5 })));
    await expect(store.submit(command, 'csrf')).resolves.toMatchObject({ status: 'confirmed' });
    expect(calls).toHaveLength(1);
    expect(calls[0]).toMatchObject({ method: 'PATCH', path: `/app/bff/schools/${schoolId}/members/${member}` });
    expect(calls[0]!.headers['If-Match']).toBe('"4"');
    expect(calls[0]!.headers['Idempotency-Key']).toBe(command.operationId);
    expect(JSON.parse(calls[0]!.body!)).toMatchObject({ roles: ['INSTRUCTOR'], grants: ['TAKE_ATTENDANCE'], reason: 'Changement de fonction', operationId: command.operationId });
    expect(store.get(schoolId, command.operationId)).toBeUndefined();
  });

  test('une version périmée est un refus : rien n\'est renvoyé tout seul et la demande n\'est plus suivie', async () => {
    const store = await openStore();
    vi.stubGlobal('fetch', answer(412, { code: 'VERSION_CONFLICT' }));
    const result = await store.submit(change(), 'csrf');
    expect(result).toMatchObject({ status: 'rejected', code: 'VERSION_CONFLICT' });
    expect(calls).toHaveLength(1);
    expect(store.get(schoolId)).toBeUndefined();
  });

  test('une réponse perdue laisse la demande à vérifier ; le renvoi garde clé, version et corps', async () => {
    const store = await openStore(), command = change();
    vi.stubGlobal('fetch', answer(503, { code: 'SERVICE_UNAVAILABLE' }));
    await expect(store.submit(command, 'csrf')).resolves.toMatchObject({ status: 'pending' });
    expect(store.get(schoolId, command.operationId)).toMatchObject({ phase: 'uncertain' });
    const first = calls[0]!;
    calls = [];
    vi.stubGlobal('fetch', answer(200, envelope({ id: member, schoolId, version: 5 })));
    await expect(store.resend(schoolId, 'csrf')).resolves.toMatchObject({ status: 'confirmed' });
    expect(calls).toHaveLength(1);
    expect(calls[0]).toMatchObject({ method: first.method, path: first.path, body: first.body });
    expect(calls[0]!.headers['Idempotency-Key']).toBe(first.headers['Idempotency-Key']);
    expect(calls[0]!.headers['If-Match']).toBe(first.headers['If-Match']);
  });

  test('un second appui sur la même demande n\'envoie rien de plus', async () => {
    const store = await openStore(), command = change();
    let release!: () => void;
    const open = new Promise<void>(resolve => { release = resolve; });
    vi.stubGlobal('fetch', vi.fn(async (input: URL | string, init?: RequestInit) => {
      calls.push({ method: init?.method ?? 'GET', path: new URL(String(input)).pathname, headers: {}, body: init?.body as string | undefined });
      await open;
      return { status: 200, ok: true, url: String(input), headers: new Headers({ 'content-type': 'application/json' }), json: async () => envelope({ id: member, schoolId, version: 5 }) };
    }));
    const running = store.submit(command, 'csrf');
    await expect(store.submit(command, 'csrf')).resolves.toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_CONFLICT' });
    release();
    await running;
    expect(calls).toHaveLength(1);
  });
});

describe('W48 : retirer l\'accès d\'un membre', () => {
  test('part en POST sur « deactivate », avec le motif, la version et la clé', async () => {
    const store = await openStore(), command = removal();
    vi.stubGlobal('fetch', answer(200, envelope({ id: member, schoolId, version: 5 })));
    await expect(store.submit(command, 'csrf')).resolves.toMatchObject({ status: 'confirmed' });
    expect(calls[0]).toMatchObject({ method: 'POST', path: `/app/bff/schools/${schoolId}/members/${member}/deactivate` });
    expect(calls[0]!.headers['If-Match']).toBe('"4"');
    expect(calls[0]!.headers['Idempotency-Key']).toBe(command.operationId);
    expect(JSON.parse(calls[0]!.body!)).toMatchObject({ reason: 'Départ de l’école', operationId: command.operationId });
  });

  test('le dernier administrateur refusé par l\'école reste un refus : motif conservé par l\'appelant, rien de suivi', async () => {
    const store = await openStore();
    vi.stubGlobal('fetch', answer(409, { code: 'LAST_ADMIN' }));
    await expect(store.submit(removal(), 'csrf')).resolves.toMatchObject({ status: 'rejected', code: 'LAST_ADMIN' });
    expect(calls).toHaveLength(1);
    expect(store.get(schoolId)).toBeUndefined();
  });

  test('les écritures de membres sont sérialisées pour toute l’école (règle du dernier administrateur) : la seconde attend, sans rien envoyer', async () => {
    const store = await openStore();
    let release!: () => void;
    const open = new Promise<void>(resolve => { release = resolve; });
    vi.stubGlobal('fetch', vi.fn(async (input: URL | string, init?: RequestInit) => {
      calls.push({ method: init?.method ?? 'GET', path: new URL(String(input)).pathname, headers: {}, body: init?.body as string | undefined });
      await open;
      return { status: 200, ok: true, url: String(input), headers: new Headers({ 'content-type': 'application/json' }), json: async () => envelope({ id: member, schoolId, version: 5 }) };
    }));
    const removing = store.submit(removal(), 'csrf');
    await expect(store.submit(change(), 'csrf')).resolves.toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_CONFLICT' });
    await expect(store.submit(change(other, 2), 'csrf')).resolves.toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_CONFLICT' });
    expect(calls.map(call => call.path)).toEqual([`/app/bff/schools/${schoolId}/members/${member}/deactivate`]);
    release();
    await removing;
  });
});
