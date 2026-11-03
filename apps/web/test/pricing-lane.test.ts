import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { createCommand, type SchoolCommand } from '../client/command-core.js';
import { CommandLane, laneView, type LaneHooks, type LaneStore } from '../client/command-lane.js';
import { tariffTag } from '../client/portal/pricing/pricing-projection.js';

/**
 * L'ordre par agrégat du catalogue (#124) contre le vrai magasin de commandes : deux produits tarifaires indépendants partent
 * ensemble, le même produit est refusé sur place, une création et un tarif à conditions partagées attendent la révision des
 * conditions. Réseau scripté, horloge simulée, aucun serveur.
 */
type Store = LaneStore;
const storeModule = '../client/command-store.ts';
const schoolId = randomUUID();
const memory = () => {
  const items = new Map<string, string>();
  return { getItem: (key: string) => items.get(key) ?? null, removeItem: (key: string) => { items.delete(key); }, setItem: (key: string, value: string) => { items.set(key, value); } };
};
const envelope = (data: unknown) => ({ data, requestId: randomUUID(), serverTime: '2026-11-03T08:00:00.000Z' });
type Scripted = { status: number; body?: unknown; delayMs?: number };
type Call = { path: string; method: string; body: string | undefined };
let calls: Call[] = [];
function script(answer: Scripted | (() => Scripted)) {
  calls = [];
  vi.stubGlobal('fetch', vi.fn((input: URL | string, init?: RequestInit) => {
    calls.push({ path: new URL(String(input)).pathname, method: init?.method ?? 'GET', body: init?.body as string | undefined });
    const chosen = typeof answer === 'function' ? answer() : answer;
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

const created = () => envelope({ id: randomUUID(), schoolId, version: 1 });
const view = (tag: string) => laneView(lane.getSnapshot(), tag);
const tariff = (productKey: string, scope?: string) => createCommand({ schoolId, kind: 'saveTariff', path: 'formations/tariffs', resourceVersion: 0,
  body: { mode: 'UPDATE', productKey }, ...(scope ? { scope } : {}) });
const creation = () => createCommand({ schoolId, kind: 'saveTariff', path: 'formations/tariffs', resourceVersion: 0, body: { mode: 'CREATE' } });
const terms = (termsVersionId: string) => createCommand({ schoolId, kind: 'reviseSharedTerms', path: 'formations/terms/revise', resourceVersion: 0,
  scope: termsVersionId, body: { termsVersionId, termsText: 'Nouvelles conditions communes.', reviewAcknowledged: true } });
const start = (command: SchoolCommand, tag: string) => lane.start(command, 'La demande est enregistrée.', tag);

describe('Ordre du catalogue par agrégat', () => {
  test('deux produits tarifaires indépendants partent ensemble ; le même produit attend, sans envoi ni succès annoncé', async () => {
    vi.useFakeTimers();
    script({ status: 201, body: created(), delayMs: 15_000 });
    const first = start(tariff('lesson-45', 'lesson-45'), tariffTag('lesson-45'));
    const second = start(tariff('exam-support', 'exam-support'), tariffTag('exam-support'));
    expect([first.admitted, second.admitted]).toEqual([true, true]);
    // Un autre formulaire du même produit (autre étiquette) est refusé par le magasin, pas expédié.
    const sameProduct = start(tariff('lesson-45', 'lesson-45'), 'other:lesson-45');
    expect(sameProduct.admitted).toBe(false);
    await expect(sameProduct.result).resolves.toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_CONFLICT' });
    expect(calls).toHaveLength(2);
    // Rien n'est confirmé avant la réponse vérifiée.
    expect(view(tariffTag('lesson-45'))).toMatchObject({ busy: true, outcome: null });
    await vi.advanceTimersByTimeAsync(15_100);
    await expect(first.result).resolves.toMatchObject({ status: 'confirmed' });
    await expect(second.result).resolves.toMatchObject({ status: 'confirmed' });
    expect(view(tariffTag('exam-support')).outcome).toMatchObject({ tone: 'success' });
    expect(hooks.confirmed).toHaveBeenCalledTimes(2);
  });

  test('un tarif à conditions partagées attend la révision des conditions ; un tarif qui a ses propres conditions ne l’attend pas', async () => {
    vi.useFakeTimers();
    script({ status: 201, body: created(), delayMs: 5_000 });
    const revision = start(terms('terms-1'), 'terms:terms-1');
    expect(revision.admitted).toBe(true);
    const shared = start(tariff('lesson-45'), tariffTag('lesson-45'));
    expect(shared.admitted).toBe(false);
    await expect(shared.result).resolves.toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_CONFLICT' });
    // Le tarif sans conditions partagées nomme son produit : il part sans attendre la révision.
    const own = start(tariff('exam-support', 'exam-support'), tariffTag('exam-support'));
    expect(own.admitted).toBe(true);
    await vi.advanceTimersByTimeAsync(5_100);
    await expect(revision.result).resolves.toMatchObject({ status: 'confirmed' });
    await expect(own.result).resolves.toMatchObject({ status: 'confirmed' });
  });

  test('une création, qui n’a pas encore d’identifiant d’école, attend les écritures du catalogue', async () => {
    vi.useFakeTimers();
    script({ status: 201, body: created(), delayMs: 4_000 });
    expect(start(tariff('lesson-45', 'lesson-45'), tariffTag('lesson-45')).admitted).toBe(true);
    const newTariff = start(creation(), tariffTag(null));
    expect(newTariff.admitted).toBe(false);
    await expect(newTariff.result).resolves.toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_CONFLICT' });
    expect(calls).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(4_100);
    expect(hooks.confirmed).toHaveBeenCalledTimes(1);
  });

  test('une révision de conditions attend aussi la planification, comme avant #124', async () => {
    script({ status: 201, body: created(), delayMs: 1_000 });
    vi.useFakeTimers();
    const lesson = createCommand({ schoolId, kind: 'createLesson', path: 'lessons', resourceVersion: 0, body: { learnerId: randomUUID() } });
    expect(start(lesson, 'lesson:new').admitted).toBe(true);
    const revision = start(terms('terms-1'), 'terms:terms-1');
    expect(revision.admitted).toBe(false);
    await vi.advanceTimersByTimeAsync(1_100);
    await expect(revision.result).resolves.toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_CONFLICT' });
  });
});
