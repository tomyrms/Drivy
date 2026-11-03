import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { createCommand, type SchoolCommand } from '../client/command-core.js';
import { CommandLane, laneView, type LaneHooks, type LaneStore } from '../client/command-lane.js';
import { participantScope } from '../client/portal/courses/participants-projection.js';

/**
 * The facts of one course (#99, lot E) against the real command store: two participants answer side by side, the same one waits,
 * a double press sends nothing more, a lost reply is followed and confirmed by its receipt without a second write. Scripted
 * network, simulated clock, no server, no real person.
 */
type Store = LaneStore & {
  verify(schoolId: string, operationId?: string): Promise<{ status: string }>;
};
const storeModule = '../client/command-store.ts';
const schoolId = randomUUID();
const seriesId = randomUUID();
const memory = () => {
  const items = new Map<string, string>();
  return { getItem: (key: string) => items.get(key) ?? null, removeItem: (key: string) => { items.delete(key); }, setItem: (key: string, value: string) => { items.set(key, value); } };
};
const envelope = (data: unknown) => ({ data, requestId: randomUUID(), serverTime: '2026-11-03T08:00:00.000Z' });
type Scripted = { status: number; body?: unknown; delayMs?: number };
type Call = { path: string; method: string; body: string | undefined };
let calls: Call[] = [];
function script(answer: (call: Call) => Scripted) {
  calls = [];
  vi.stubGlobal('fetch', vi.fn((input: URL | string, init?: RequestInit) => {
    calls.push({ path: new URL(String(input)).pathname, method: init?.method ?? 'GET', body: init?.body as string | undefined });
    const chosen = answer(calls[calls.length - 1]!);
    const reply = () => ({ status: chosen.status, ok: chosen.status >= 200 && chosen.status < 300, url: String(input),
      headers: new Headers({ 'content-type': 'application/json' }), json: async () => chosen.body ?? null });
    return chosen.delayMs ? new Promise(resolve => setTimeout(() => resolve(reply()), chosen.delayMs)) : Promise.resolve(reply());
  }));
}
let store: Store;
let hooks: { csrf: ReturnType<typeof vi.fn>; confirmed: ReturnType<typeof vi.fn> };
let lane: CommandLane;
beforeEach(async () => {
  vi.resetModules();
  vi.stubGlobal('window', { location: { origin: 'https://drivy.example' }, sessionStorage: memory(), localStorage: memory() });
  store = (await import(/* @vite-ignore */ storeModule) as { commandStore: Store }).commandStore;
  hooks = { csrf: vi.fn(() => 'csrf'), confirmed: vi.fn() };
  lane = new CommandLane(store, () => hooks as LaneHooks);
});
afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

const created = () => envelope({ schoolId, version: 1 });
/** The status each fact expects: a presence answers 200, a creation 201. */
const accepted = (call: Call, delayMs?: number): Scripted => ({ status: call.method === 'PUT' ? 200 : 201, body: created(), ...(delayMs ? { delayMs } : {}) });
const receipt = (command: SchoolCommand) => envelope({ operationId: command.operationId, commandType: 'RECORD_COURSE_ATTENDANCE', resourceType: 'CourseAttendance',
  resourceId: command.resourceId, committedAt: '2026-11-03T08:00:00.000Z', resourceVersion: command.resourceVersion + 1 });
/** Same shape and same aggregate as the participant screen builds them. */
const attendance = (enrollmentId: string, participant: string) => createCommand({ schoolId, kind: 'recordCourseAttendance',
  path: `course-enrollments/${enrollmentId}/attendance/${randomUUID()}`, resourceId: enrollmentId, resourceVersion: 0,
  body: { status: 'PRESENT', expectedVersion: null, note: null }, scope: participantScope(seriesId, participant) });
const payment = (enrollmentId: string, participant: string, amountCents = 12_050) => createCommand({ schoolId, kind: 'recordCoursePayment',
  path: `course-enrollments/${enrollmentId}/payments`, resourceVersion: 0, body: { amountCents, note: 'Espèces' }, scope: participantScope(seriesId, participant) });
const validation = (enrollmentId: string, participant: string) => createCommand({ schoolId, kind: 'validateCourse',
  path: `course-enrollments/${enrollmentId}/validate`, resourceVersion: 0, body: { note: null }, scope: participantScope(seriesId, participant) });
const view = (tag: string) => laneView(lane.getSnapshot(), tag);
const start = (command: SchoolCommand, tag: string, success = 'Le fait est enregistré.') => lane.start(command, success, tag);

const participantA = randomUUID(), participantB = randomUUID();
const enrollmentA = randomUUID(), enrollmentB = randomUUID();
const tagA = `call:${enrollmentA}`, tagB = `payments:${enrollmentB}`;

describe('Faits de cours : deux participants indépendants, le même ordonné', () => {
  test('deux participants partent ensemble ; le même participant attend, sans second envoi ni succès annoncé', async () => {
    vi.useFakeTimers();
    script(call => accepted(call, 15_000));
    const first = start(attendance(enrollmentA, participantA), tagA, 'Présence enregistrée.');
    const second = start(payment(enrollmentB, participantB), tagB, 'Règlement enregistré.');
    expect([first.admitted, second.admitted]).toEqual([true, true]);
    // Le même participant, un autre geste : refusé sur place par le magasin.
    const samePerson = start(validation(enrollmentA, participantA), `completion:${enrollmentA}`, 'Cours validé.');
    expect(samePerson.admitted).toBe(false);
    await expect(samePerson.result).resolves.toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_CONFLICT' });
    expect(calls).toHaveLength(2);
    // Rien n'est confirmé avant la réponse vérifiée, et la marque reste à confirmer.
    expect(view(tagA)).toMatchObject({ busy: true, outcome: null });
    expect(view(tagB)).toMatchObject({ busy: true, outcome: null });
    await vi.advanceTimersByTimeAsync(15_100);
    await expect(first.result).resolves.toMatchObject({ status: 'confirmed' });
    await expect(second.result).resolves.toMatchObject({ status: 'confirmed' });
    expect(view(tagA).outcome).toMatchObject({ tone: 'success', message: 'Présence enregistrée.' });
    expect(hooks.confirmed).toHaveBeenCalledTimes(2);
  });

  test('un double appui n’envoie rien de plus : même intention, même opération', async () => {
    vi.useFakeTimers();
    const command = attendance(enrollmentA, participantA);
    script(call => accepted(call, 50));
    const first = start(command, tagA);
    const sameTag = start(command, tagA);
    const otherTag = start(command, 'other:whatever');
    expect(sameTag.admitted).toBe(false);
    expect(otherTag.admitted).toBe(false);
    await vi.advanceTimersByTimeAsync(60);
    await first.result; await sameTag.result; await otherTag.result;
    expect(calls).toHaveLength(1);
    expect(calls[0]!.body).toContain(command.operationId);
    expect(hooks.confirmed).toHaveBeenCalledTimes(1);
  });

  test('réponse perdue : le fait reste suivi, le reçu le confirme sans seconde écriture, l’autre participant avance', async () => {
    const lost = attendance(enrollmentA, participantA);
    script(() => ({ status: 503, body: { code: 'SERVICE_UNAVAILABLE' } }));
    await expect(start(lost, tagA).result).resolves.toMatchObject({ status: 'pending' });
    expect(view(tagA)).toMatchObject({ following: true, outcome: null });
    expect(hooks.confirmed).not.toHaveBeenCalled();
    // Un autre participant ne l'attend pas.
    script(call => accepted(call));
    await expect(start(payment(enrollmentB, participantB), tagB).result).resolves.toMatchObject({ status: 'confirmed' });
    // Le reçu de la première réponse : AP72 répond, aucune nouvelle écriture.
    script(call => call.method === 'GET' ? { status: 200, body: receipt(lost) } : { status: 500 });
    await expect(store.verify(schoolId, lost.operationId)).resolves.toMatchObject({ status: 'confirmed' });
    lane.reconcile(); lane.reconcile();
    expect(calls.map(call => call.method)).toEqual(['GET']);
    expect(view(tagA)).toMatchObject({ following: false, outcome: null });
    expect(hooks.confirmed).toHaveBeenCalledTimes(2);
  });

  test('un refus ne touche que son intention : l’autre participant continue et garde son succès', async () => {
    vi.useFakeTimers();
    script(call => accepted(call, 20));
    const slow = start(attendance(enrollmentA, participantA), tagA, 'Présence enregistrée.');
    script(() => ({ status: 409, body: { code: 'COURSE_REQUIREMENTS_MISSING' } }));
    const refused = start(validation(enrollmentB, participantB), `completion:${enrollmentB}`, 'Cours validé.');
    expect(refused.admitted).toBe(true);
    await expect(refused.result).resolves.toMatchObject({ status: 'rejected', code: 'COURSE_REQUIREMENTS_MISSING' });
    expect(view(`completion:${enrollmentB}`).outcome).toMatchObject({ tone: 'error', code: 'COURSE_REQUIREMENTS_MISSING' });
    expect(view(tagA)).toMatchObject({ busy: true, outcome: null });
    await vi.advanceTimersByTimeAsync(30);
    await expect(slow.result).resolves.toMatchObject({ status: 'confirmed' });
    expect(view(tagA).outcome).toMatchObject({ tone: 'success' });
    expect(hooks.confirmed).toHaveBeenCalledTimes(1);
  });

  test('la voie ne garde ni montant ni motif : seulement l’intention et son texte de succès', async () => {
    script(call => accepted(call, 1_000));
    vi.useFakeTimers();
    start(payment(enrollmentA, participantA, 12_345), tagA, 'Règlement enregistré.');
    const state = JSON.stringify([...lane.getSnapshot().intents.values()]);
    expect(state).toContain('Règlement enregistré.');
    expect(state).not.toContain('12345');
    expect(state).not.toContain('Espèces');
    await vi.advanceTimersByTimeAsync(1_100);
  });
});
