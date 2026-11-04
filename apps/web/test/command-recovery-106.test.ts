import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { createCommand } from '../client/command-core.js';
import { desiredSlotOf, lessonResendAllowed, lessonResendReason } from '../client/command-recovery.js';

/**
 * #106, reste L1 web : la barrière d'horaire est dans le magasin de commandes, pas seulement dans l'écran qui affiche le bouton.
 * Transport simulé : aucun réseau, aucune école. Un appel direct au magasin doit se comporter comme le bureau.
 */
type Result = { status: string; code?: string; message?: string };
type Entry = { phase: string; command: unknown; message: string; attempts: number } | undefined;
type Snapshot = { revision: number; confirmed: unknown };
type Store = {
  submit(command: unknown, csrf: string): Promise<Result>;
  verify(schoolId: string, operationId?: string): Promise<Result>;
  resend(schoolId: string, csrf: string, operationId?: string, now?: number): Promise<Result>;
  get(schoolId: string, operationId?: string): Entry;
  getSnapshot(): Snapshot;
  scopeToAccess(schoolId: string, membershipId: string, accessEpoch: number): void;
  clear(): void;
};

const schoolId = randomUUID();
const lessonId = randomUUID();
const storeModule = '../client/command-store.ts';
/** La clé et le format de la liste v1 font partie du contrat : une page ouverte avant ce lot doit rester relisible. */
const storageKey = 'drivy-gestion-demandes-v1';

const memory = () => {
  const items = new Map<string, string>();
  return { getItem: (key: string) => items.get(key) ?? null, removeItem: (key: string) => { items.delete(key); },
    setItem: (key: string, value: string) => { items.set(key, value); }, snapshot: () => [...items.values()] };
};
let session: ReturnType<typeof memory>;
const envelope = (data: unknown) => ({ data, requestId: randomUUID(), serverTime: '2026-11-04T08:00:00.000Z' });

function answer(status: number, body: unknown) {
  return vi.fn(async (input: URL | string, _init?: RequestInit) => ({
    status, ok: status >= 200 && status < 300, url: String(input), headers: new Headers({ 'content-type': 'application/json' }),
    json: async () => body,
  }));
}

async function loadStore(): Promise<Store> {
  vi.resetModules();
  const module = await import(/* @vite-ignore */ storeModule) as { commandStore: Store };
  return module.commandStore;
}

beforeEach(() => { fresh(); });
afterEach(() => { vi.unstubAllGlobals(); });

/** Une page neuve : stockage vide et magasin rechargé, sans réutiliser la liste de l'itération précédente. */
function fresh() {
  session = memory();
  vi.stubGlobal('window', { location: { origin: 'https://drivy.example' }, sessionStorage: session, localStorage: memory() });
}

/** Le créneau voulu par la saisie, et l'instant où l'on juge le renvoi. */
const slot = '2026-11-05T10:00:00.000Z';
const at = (iso: string) => Date.parse(iso);
const create = (plannedStart: string | null = slot) => createCommand({ schoolId, kind: 'createLesson', path: 'lessons', resourceVersion: 0,
  body: { meetingPoint: 'Gare', ...(plannedStart === null ? {} : { plannedStart }) } });
const move = (plannedStart: string | null = slot) => createCommand({ schoolId, kind: 'moveLesson', path: `lessons/${lessonId}/move`,
  resourceId: lessonId, resourceVersion: 3, ifMatch: 3, body: { meetingPoint: 'Gare', ...(plannedStart === null ? {} : { plannedStart }) } });
const lost = () => answer(503, { code: 'SERVICE_UNAVAILABLE' });

describe('renvoi d’une planification : la barrière est dans le magasin', () => {
  test.each(['createLesson', 'moveLesson'] as const)('%s : un créneau passé ne part pas, même appelé directement sans écran', async kind => {
    const store = await loadStore(), command = kind === 'createLesson' ? create() : move(), now = at(slot) + 1;
    const send = lost();
    vi.stubGlobal('fetch', send);
    await store.submit(command, 'csrf');
    const revision = store.getSnapshot().revision;
    const result = await store.resend(schoolId, 'csrf', command.operationId, now);
    // Zéro paquet : le transport n'est jamais atteint.
    expect(send).toHaveBeenCalledTimes(1);
    expect(result.status).toBe('pending');
    expect(result.message).toBe(lessonResendReason({ kind, command }, now));
    // Le résultat reste à vérifier : ni rejet définitif, ni abandon, ni nouvelle tentative comptée.
    expect(store.get(schoolId, command.operationId)).toMatchObject({ phase: 'uncertain', command, attempts: 1 });
    expect(store.getSnapshot()).toMatchObject({ revision, confirmed: null });
  });

  test('l’échéance se juge à l’instant du renvoi : juste avant elle part, à elle et après elle ne part plus', async () => {
    const deadline = at(slot);
    for (const [now, emitted] of [[deadline - 1, true], [deadline, false], [deadline + 1, false]] as const) {
      fresh();
      const store = await loadStore(), command = create();
      const send = lost();
      vi.stubGlobal('fetch', send);
      await store.submit(command, 'csrf');
      await store.resend(schoolId, 'csrf', command.operationId, now);
      expect(send, `maintenant=${now - deadline} ms`).toHaveBeenCalledTimes(emitted ? 2 : 1);
    }
  });

  test('un horaire absent ou illisible ne prouve pas un créneau devant : aucun paquet', async () => {
    for (const plannedStart of [null, 'pas une date']) {
      fresh();
      const store = await loadStore(), command = create(plannedStart);
      const send = lost();
      vi.stubGlobal('fetch', send);
      await store.submit(command, 'csrf');
      const result = await store.resend(schoolId, 'csrf', command.operationId, at('2020-01-01T00:00:00.000Z'));
      expect(send, String(plannedStart)).toHaveBeenCalledTimes(1);
      expect(result.status).toBe('pending');
      expect(store.get(schoolId, command.operationId)?.command).toEqual(command);
    }
  });

  test('le premier envoi garde son contrat : c’est l’école qui juge un horaire déjà passé', async () => {
    const store = await loadStore(), command = create('2026-11-01T10:00:00.000Z'), send = lost();
    vi.stubGlobal('fetch', send);
    await store.submit(command, 'csrf');
    expect(send).toHaveBeenCalledTimes(1);
    expect(store.get(schoolId, command.operationId)).toMatchObject({ phase: 'uncertain', command });
  });

  test('un renvoi autorisé reprend exactement la même clé, le même corps et la même précondition', async () => {
    const store = await loadStore(), command = move(), send = lost();
    vi.stubGlobal('fetch', send);
    await store.submit(command, 'csrf');
    const result = await store.resend(schoolId, 'csrf', command.operationId, at(slot) - 1);
    expect(result.status).toBe('pending');
    expect(send).toHaveBeenCalledTimes(2);
    const [first, second] = send.mock.calls;
    expect(String(second![0])).toBe(String(first![0]));
    expect(second![1]?.method).toBe(first![1]?.method);
    expect(second![1]?.body).toBe(first![1]?.body);
    expect(second![1]?.headers).toEqual(first![1]?.headers);
    expect(second![1]?.headers).toMatchObject({ 'Idempotency-Key': command.operationId, 'If-Match': '"3"' });
    expect(store.get(schoolId, command.operationId)?.command).toEqual(command);
  });

  test('un reçu valide arrivé après l’horaire confirme normalement : le blocage du renvoi n’efface rien', async () => {
    const store = await loadStore(), command = create(), now = at(slot) + 60_000;
    vi.stubGlobal('fetch', lost());
    await store.submit(command, 'csrf');
    expect((await store.resend(schoolId, 'csrf', command.operationId, now)).status).toBe('pending');
    const receipt = answer(200, envelope({ operationId: command.operationId, commandType: 'CREATE_LESSON', resourceType: 'Lesson',
      resourceId: lessonId, resourceVersion: 1, committedAt: '2026-11-05T09:00:00.000Z' }));
    vi.stubGlobal('fetch', receipt);
    expect((await store.verify(schoolId, command.operationId)).status).toBe('confirmed');
    expect(receipt).toHaveBeenCalledTimes(1);
    expect(String(receipt.mock.calls[0]![0])).toContain(`/operations/${command.operationId}`);
    expect(store.get(schoolId, command.operationId)).toBeUndefined();
  });

  test('les autres familles gardent leur renvoi, sans seuil d’âge universel', async () => {
    const store = await loadStore(), invitation = randomUUID();
    const command = createCommand({ schoolId, kind: 'resendInvitation', path: `invitations/${invitation}/resend`, resourceId: invitation,
      resourceVersion: 2, ifMatch: 2, body: {} });
    const send = lost();
    vi.stubGlobal('fetch', send);
    await store.submit(command, 'csrf');
    await store.resend(schoolId, 'csrf', command.operationId, at('2030-01-01T00:00:00.000Z'));
    expect(send).toHaveBeenCalledTimes(2);
  });

  test('changer d’époque reste la barrière la plus forte : aucun renvoi, même avec un créneau devant', async () => {
    const store = await loadStore(), command = create(), member = randomUUID(), send = lost();
    store.scopeToAccess(schoolId, member, 1);
    vi.stubGlobal('fetch', send);
    await store.submit(command, 'csrf');
    store.scopeToAccess(schoolId, member, 2);
    await store.resend(schoolId, 'csrf', command.operationId, at(slot) - 1);
    expect(send).toHaveBeenCalledTimes(1);
    expect(store.get(schoolId, command.operationId)).toMatchObject({ phase: 'orphaned', command: null });
  });
});

describe('liste v1 relue : des identifiants, jamais un renvoi', () => {
  test('une création suivie avant rechargement reste vérifiable mais n’est jamais renvoyée, même avec un créneau devant', async () => {
    const operationId = randomUUID();
    session.setItem(storageKey, JSON.stringify([{ operationId, schoolId, kind: 'createLesson', resourceVersion: 0,
      createdAt: at('2026-11-04T07:00:00.000Z') }]));
    const store = await loadStore(), send = lost();
    vi.stubGlobal('fetch', send);
    expect(store.get(schoolId, operationId)).toMatchObject({ phase: 'orphaned', command: null });
    const result = await store.resend(schoolId, 'csrf', operationId, at(slot) - 1);
    expect(send).not.toHaveBeenCalled();
    expect(result.status).toBe('pending');
    expect(result.message).not.toBe('');
  });
});

describe('la règle partagée juge le créneau demandé, pas la famille', () => {
  test('le créneau lu est celui du corps, en millisecondes, et seulement pour une leçon', () => {
    expect(desiredSlotOf(create())).toBe(at(slot));
    expect(desiredSlotOf(move())).toBe(at(slot));
    expect(desiredSlotOf(create(null))).toBeNull();
    expect(desiredSlotOf(create('pas une date'))).toBeNull();
    expect(desiredSlotOf(null)).toBeNull();
    expect(desiredSlotOf(createCommand({ schoolId, kind: 'cancelLesson', path: `lessons/${lessonId}/cancel`, resourceId: lessonId,
      resourceVersion: 3, ifMatch: 3, body: { plannedStart: slot } }))).toBeNull();
  });

  test('une échéance égale à maintenant est déjà passée', () => {
    expect(lessonResendAllowed({ kind: 'createLesson', command: create() }, at(slot) - 1)).toBe(true);
    expect(lessonResendAllowed({ kind: 'createLesson', command: create() }, at(slot))).toBe(false);
    expect(lessonResendAllowed({ kind: 'createLesson', command: create() }, at(slot) + 1)).toBe(false);
  });
});
