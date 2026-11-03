import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { createCommand, type SchoolCommand } from '../client/command-core.js';
import { CommandLane, type LaneHooks, type LaneStore } from '../client/command-lane.js';
import { lessonResendAllowed, lessonResendReason } from '../client/console/agenda-intentions.js';

/**
 * La voie de planification du bureau (#109) contre le vrai magasin de commandes, un faux `window` et un réseau scripté :
 * double appui, réponse perdue puis reçu sans seconde écriture, refus qui n'annonce aucune réservation, et renvoi retiré
 * quand l'horaire voulu est passé.
 */
type Store = LaneStore & {
  verify(schoolId: string, operationId?: string): Promise<{ status: string }>;
};
const storeModule = '../client/command-store.ts';
const schoolId = randomUUID();
const lessonId = randomUUID();
const memory = () => {
  const items = new Map<string, string>();
  return { getItem: (key: string) => items.get(key) ?? null, removeItem: (key: string) => { items.delete(key); },
    setItem: (key: string, value: string) => { items.set(key, value); }, snapshot: () => [...items.values()] };
};
const envelope = (data: unknown) => ({ data, requestId: randomUUID(), serverTime: '2026-11-03T08:00:00.000Z' });
type Scripted = { status: number; body?: unknown; delayMs?: number };
type Call = { path: string; method: string; headers: Record<string, string>; body: string | undefined };
let calls: Call[] = [];
function script(handle: (call: Call) => Scripted) {
  calls = [];
  vi.stubGlobal('fetch', vi.fn((input: URL | string, init?: RequestInit) => {
    const call: Call = { path: new URL(String(input)).pathname.replace(`/app/bff/schools/${schoolId}/`, ''), method: init?.method ?? 'GET',
      headers: (init?.headers ?? {}) as Record<string, string>, body: init?.body as string | undefined };
    calls.push(call);
    const answer = handle(call);
    const reply = () => ({ status: answer.status, ok: answer.status >= 200 && answer.status < 300, url: String(input),
      headers: new Headers({ 'content-type': 'application/json' }), json: async () => answer.body ?? null });
    return answer.delayMs ? new Promise(resolve => setTimeout(() => resolve(reply()), answer.delayMs)) : Promise.resolve(reply());
  }));
}
let store: Store;
let session: ReturnType<typeof memory>, local: ReturnType<typeof memory>;
let hooks: { csrf: ReturnType<typeof vi.fn>; confirmed: ReturnType<typeof vi.fn> };
let lane: CommandLane;
async function fresh() {
  vi.resetModules();
  store = (await import(/* @vite-ignore */ storeModule) as { commandStore: Store }).commandStore;
  hooks = { csrf: vi.fn(() => 'csrf'), confirmed: vi.fn() };
  lane = new CommandLane(store, () => hooks as LaneHooks);
}
beforeEach(async () => {
  session = memory(); local = memory();
  vi.stubGlobal('window', { location: { origin: 'https://drivy.example' }, sessionStorage: session, localStorage: local });
  await fresh();
});
afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

const create = (plannedStart = '2027-01-12T08:00:00Z') => createCommand({ schoolId, kind: 'createLesson', path: 'lessons', resourceVersion: 0,
  body: { trainingId: randomUUID(), instructorMembershipId: randomUUID(), plannedStart, plannedEnd: '2027-01-12T09:00:00Z', timeZone: 'Europe/Zurich' } });
const move = (plannedStart = '2027-01-13T08:00:00Z') => createCommand({ schoolId, kind: 'moveLesson', path: `lessons/${lessonId}/move`, resourceId: lessonId,
  resourceVersion: 3, ifMatch: 3, body: { plannedStart, plannedEnd: '2027-01-13T09:00:00Z', timeZone: 'Europe/Zurich' } });
const created = (command: SchoolCommand) => envelope({ id: randomUUID(), schoolId, version: command.resourceVersion + 1 });
const receipt = (command: SchoolCommand, type: string, resourceType: string) => envelope({ operationId: command.operationId, commandType: type, resourceType,
  resourceId: command.resourceId ?? randomUUID(), committedAt: '2026-11-03T08:00:00.000Z', resourceVersion: command.resourceVersion + 1 });
/** L'entrée suivie par le magasin pour cette opération (lecture seule). */
const entryOf = (operationId: string) => (store as unknown as {
  get: (schoolId: string, operationId?: string) => { meta: { kind: string }; command: SchoolCommand | null; phase: string } | undefined;
}).get(schoolId, operationId);

describe('planification : une intention conservée, jamais une réservation annoncée', () => {
  test('un double appui n’envoie qu’une requête : même intention, même opération', async () => {
    const command = create();
    script(() => ({ status: 201, body: created(command), delayMs: 50 }));
    vi.useFakeTimers();
    const first = lane.start(command, 'La leçon est planifiée.', 'lesson:new');
    const sameTag = lane.start(command, 'La leçon est planifiée.', 'lesson:new');
    const otherTag = lane.start(command, 'La leçon est planifiée.', 'lesson:other');
    expect(first.admitted).toBe(true);
    expect(sameTag.admitted).toBe(false);
    expect(otherTag.admitted).toBe(false);
    await vi.advanceTimersByTimeAsync(60);
    await first.result;
    expect(calls).toHaveLength(1);
    expect(calls[0]!.headers['Idempotency-Key']).toBe(command.operationId);
  });

  test('une réponse perdue reste suivie ; le reçu confirme sans seconde écriture', async () => {
    const command = move();
    script(() => ({ status: 503, body: { code: 'SERVICE_UNAVAILABLE' } }));
    const result = await lane.start(command, 'La leçon est déplacée.', `lesson:${lessonId}`).result;
    expect(result.status).toBe('pending');
    expect(hooks.confirmed).not.toHaveBeenCalled();
    // Rien n'est confirmé, rien n'est annulé : l'intention reste suivie par le magasin.
    expect(entryOf(command.operationId)?.phase).toBe('uncertain');
    script(call => call.method === 'GET' ? { status: 200, body: receipt(command, 'MOVE_LESSON', 'Lesson') } : { status: 500 });
    await expect(store.verify(schoolId, command.operationId)).resolves.toMatchObject({ status: 'confirmed' });
    lane.reconcile();
    expect(calls.map(call => call.method)).toEqual(['GET']);
    expect(hooks.confirmed).toHaveBeenCalledTimes(1);
  });

  test('un refus de créneau n’annonce aucune réservation et ne laisse rien à suivre', async () => {
    const command = create();
    script(() => ({ status: 409, body: { code: 'SLOT_CONFLICT' } }));
    const started = lane.start(command, 'La leçon est planifiée.', 'lesson:new');
    expect(started.admitted).toBe(true);
    await expect(started.result).resolves.toMatchObject({ status: 'rejected', code: 'SLOT_CONFLICT' });
    expect(hooks.confirmed).not.toHaveBeenCalled();
    expect(entryOf(command.operationId)).toBeUndefined();
  });

  test('une planification attend la précédente : la clé `planning` reste commune aux leçons et aux cours', async () => {
    const first = create();
    script(() => ({ status: 201, body: created(first), delayMs: 50 }));
    vi.useFakeTimers();
    const firstStarted = lane.start(first, 'La leçon est planifiée.', 'lesson:new');
    expect(firstStarted.admitted).toBe(true);
    const second = move();
    const blocked = lane.start(second, 'La leçon est déplacée.', `lesson:${lessonId}`);
    expect(blocked.admitted).toBe(false);
    await expect(blocked.result).resolves.toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_CONFLICT' });
    await vi.advanceTimersByTimeAsync(60);
    await firstStarted.result;
    expect(calls).toHaveLength(1);
  });
});

describe('renvoi d’une planification dont l’horaire est passé', () => {
  const now = Date.parse('2026-11-03T08:00:00Z');

  test('le magasin le permettrait encore ; l’horaire passé retire le renvoi, la vérification reste', async () => {
    const past = create('2026-11-02T09:00:00Z');
    script(() => ({ status: 503, body: { code: 'SERVICE_UNAVAILABLE' } }));
    await lane.start(past, 'La leçon est planifiée.', 'lesson:new').result;
    const entry = entryOf(past.operationId)!;
    // Le magasin ne connaît que l'état de la demande ; la règle d'expiration appartient à la planification.
    expect(lessonResendAllowed({ kind: 'createLesson', command: entry.command }, now)).toBe(false);
    expect(lessonResendReason({ kind: 'createLesson', command: entry.command }, now)).toContain('passé');
    // Aucune seconde écriture : on vérifie le résultat ou on arrête le suivi.
    expect(calls.map(call => call.method)).toEqual(['POST']);
    script(call => call.method === 'GET' ? { status: 200, body: receipt(past, 'CREATE_LESSON', 'Lesson') } : { status: 500 });
    await expect(store.verify(schoolId, past.operationId)).resolves.toMatchObject({ status: 'confirmed' });
    expect(calls.map(call => call.method)).toEqual(['GET']);
  });

  test('un créneau encore devant reste renvoyable', async () => {
    const future = create('2027-01-12T08:00:00Z');
    script(() => ({ status: 503, body: { code: 'SERVICE_UNAVAILABLE' } }));
    await lane.start(future, 'La leçon est planifiée.', 'lesson:new').result;
    const entry = entryOf(future.operationId)!;
    expect(lessonResendAllowed({ kind: 'createLesson', command: entry.command }, now)).toBe(true);
    expect(lessonResendReason({ kind: 'createLesson', command: entry.command }, now)).toBeNull();
  });

  test('une commande restaurée sans corps n’est jamais renvoyée', () => {
    expect(lessonResendAllowed({ kind: 'createLesson', command: null }, now)).toBe(false);
    expect(lessonResendAllowed({ kind: 'moveLesson', command: null }, now)).toBe(false);
  });
});
