import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { createCommand } from '../client/command-core.js';
import { invitationSchema, issuedCodeOf, parseInvitationResponse } from '../client/invitation-model.js';

/**
 * The real browser command store, run against a fake window: every write to sessionStorage and
 * localStorage is recorded, to prove a single-use code never reaches browser storage.
 */
type Store = {
  submit(command: unknown, csrf: string): Promise<{ status: string; body?: unknown; code?: string; needsLogin?: boolean }>;
  verify(schoolId: string): Promise<{ status: string; message?: string }>;
  get(schoolId: string): { phase: string; notRecorded: boolean; message: string } | undefined;
  clear(): void;
};
const storeModule = '../client/command-store.ts';

const schoolId = randomUUID();
const secret = 'K7Q4-MX2P';
const writes: string[] = [];
const memory = () => {
  const items = new Map<string, string>();
  return { getItem: (key: string) => items.get(key) ?? null, removeItem: (key: string) => { items.delete(key); },
    setItem: (key: string, value: string) => { items.set(key, value); writes.push(value); }, snapshot: () => [...items.values()] };
};
let session: ReturnType<typeof memory>;
let local: ReturnType<typeof memory>;
const envelope = (data: unknown) => ({ data, requestId: randomUUID(), serverTime: '2026-09-29T08:00:00.000Z' });

function answer(status: number, body: unknown) {
  return vi.fn(async (input: URL | string) => ({
    status, ok: status >= 200 && status < 300, url: String(input), headers: new Headers({ 'content-type': 'application/json' }),
    json: async () => body,
  }));
}
async function loadStore(): Promise<Store> {
  vi.resetModules();
  const module = await import(/* @vite-ignore */ storeModule) as { commandStore: Store };
  return module.commandStore;
}

beforeEach(() => {
  writes.length = 0; session = memory(); local = memory();
  vi.stubGlobal('window', { location: { origin: 'https://drivy.example' }, sessionStorage: session, localStorage: local });
});
afterEach(() => { vi.unstubAllGlobals(); });

describe('Journal des demandes : le code à usage unique n’est jamais conservé', () => {
  const offeringId = randomUUID(), instructorMembershipId = randomUUID();
  const create = () => createCommand({ schoolId, kind: 'createInvitation', path: 'invitations', resourceVersion: 0,
    body: { delivery: 'CODE', roles: ['LEARNER'], training: { offeringId, instructorMembershipId } } });
  const created = (id = randomUUID()) => ({ id, schoolId, version: 1, delivery: 'CODE', maskedEmail: null, code: secret, roles: ['LEARNER'], status: 'PENDING',
    expiresAt: '2026-10-06T08:00:00.000Z', training: { offeringId, instructorMembershipId } });

  test('réponse 201 : le code va à l’écran par le résultat, et nulle part dans le stockage du navigateur', async () => {
    const store = await loadStore();
    vi.stubGlobal('fetch', answer(201, envelope(created())));
    const result = await store.submit(create(), 'csrf');
    expect(result.status).toBe('confirmed');
    const shown = issuedCodeOf(parseInvitationResponse(result.body, { schoolId }));
    expect(shown?.code).toBe(secret);
    expect(store.get(schoolId)).toBeUndefined();
    expect(writes.length).toBeGreaterThan(0);
    for (const value of [...writes, ...session.snapshot(), ...local.snapshot()]) {
      expect(value).not.toContain(secret);
      expect(value).not.toContain(offeringId);
      expect(value).not.toContain(instructorMembershipId);
    }
    expect(local.snapshot()).toEqual([]);
    expect(session.snapshot()).toEqual(['[]']);
  });

  test('réponse perdue : la demande reste suivie par identifiants seulement, sans corps ni code', async () => {
    const store = await loadStore();
    vi.stubGlobal('fetch', answer(503, { code: 'SERVICE_UNAVAILABLE' }));
    const command = create();
    const result = await store.submit(command, 'csrf');
    expect(result.status).toBe('pending');
    const persisted = session.snapshot().join('');
    expect(JSON.parse(persisted)).toEqual([{ operationId: command.operationId, schoolId, kind: 'createInvitation', resourceVersion: 0, createdAt: command.createdAt }]);
    for (const value of writes) { expect(value).not.toContain(secret); expect(value).not.toContain(instructorMembershipId); }
    store.clear();
  });

  test('un corps de réponse qui ne prouve pas la bonne école n’affiche aucun code', async () => {
    const store = await loadStore();
    vi.stubGlobal('fetch', answer(201, envelope({ ...created(), schoolId: randomUUID() })));
    const result = await store.submit(create(), 'csrf');
    expect(result.status).toBe('pending');
    expect(invitationSchema.safeParse(created()).success).toBe(true);
    for (const value of [...writes, ...session.snapshot()]) expect(value).not.toContain(secret);
    store.clear();
  });
});

describe('Refus de l’école : rien ne reste en attente', () => {
  const create = () => createCommand({ schoolId, kind: 'createInvitation', path: 'invitations', resourceVersion: 0,
    body: { delivery: 'CODE', roles: ['LEARNER'], training: { offeringId: randomUUID(), instructorMembershipId: randomUUID() } } });

  test('409 INVITATION_DELIVERY_UNAVAILABLE : refus définitif, la saisie est conservée et une autre écriture reste possible', async () => {
    const store = await loadStore();
    const fetchMock = answer(409, { code: 'INVITATION_DELIVERY_UNAVAILABLE' });
    vi.stubGlobal('fetch', fetchMock);
    const first = await store.submit(create(), 'csrf');
    expect(first).toMatchObject({ status: 'rejected', code: 'INVITATION_DELIVERY_UNAVAILABLE', needsLogin: false });
    expect(store.get(schoolId)).toBeUndefined();
    expect(session.snapshot()).toEqual(['[]']);
    const second = await store.submit(create(), 'csrf');
    expect(second.status).toBe('rejected');
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  test('session perdue avant l’envoi : refus qui propose de se reconnecter, sans demande à vérifier', async () => {
    const store = await loadStore();
    vi.stubGlobal('fetch', answer(401, { code: 'SESSION_EXPIRED' }));
    expect(await store.submit(create(), 'csrf')).toMatchObject({ status: 'rejected', code: 'SESSION_EXPIRED', needsLogin: true });
    expect(store.get(schoolId)).toBeUndefined();
  });

  test('session perdue pendant la réponse : le résultat est inconnu, la demande reste suivie', async () => {
    const store = await loadStore();
    vi.stubGlobal('fetch', answer(401, { code: 'SESSION_LOST_RESULT_UNKNOWN' }));
    expect((await store.submit(create(), 'csrf')).status).toBe('pending');
    expect(store.get(schoolId)).toMatchObject({ phase: 'uncertain' });
    store.clear();
  });

  test('réponse perdue puis vérification : l’école n’a jamais reçu la demande, elle peut être renvoyée ou abandonnée', async () => {
    const store = await loadStore();
    vi.stubGlobal('fetch', answer(503, { code: 'SERVICE_UNAVAILABLE' }));
    await store.submit(create(), 'csrf');
    vi.stubGlobal('fetch', answer(404, { code: 'NOT_FOUND' }));
    const verified = await store.verify(schoolId);
    expect(verified.status).toBe('pending');
    expect(store.get(schoolId)).toMatchObject({ phase: 'uncertain', notRecorded: true });
    expect(store.get(schoolId)?.message).toContain('jamais reçu');
    store.clear();
  });
});
