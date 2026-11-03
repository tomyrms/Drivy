import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { createCommand, type SchoolCommand } from '../client/command-core.js';
import { CommandLane, laneView, type LaneHooks, type LaneIntent, type LaneStore } from '../client/command-lane.js';
import { formationTag } from '../client/portal/formations/formation-projection.js';

/**
 * L'ordre par agrégat des programmes (#124) contre le vrai magasin de commandes : deux formations indépendantes partent ensemble,
 * la même formation est refusée sur place, une création sans identifiant d'école attend les écritures du catalogue, une réponse
 * perdue attend son reçu sans seconde écriture, et un refus ne touche que sa formation. Réseau scripté, horloge simulée, aucun serveur.
 */
type Store = LaneStore & { verify(schoolId: string, operationId?: string): Promise<{ status: string }> };
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
function script(answer: Scripted | ((call: Call) => Scripted)) {
  calls = [];
  vi.stubGlobal('fetch', vi.fn((input: URL | string, init?: RequestInit) => {
    const call: Call = { path: new URL(String(input)).pathname, method: init?.method ?? 'GET', body: init?.body as string | undefined };
    calls.push(call);
    const chosen = typeof answer === 'function' ? answer(call) : answer;
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
const receipt = (command: SchoolCommand) => envelope({ operationId: command.operationId, commandType: 'UPDATE_FORMATION_PROGRAMME',
  resourceType: 'Offering', resourceId: randomUUID(), committedAt: '2026-11-03T08:00:00.000Z', resourceVersion: command.resourceVersion + 1 });
const view = (tag: string) => laneView(lane.getSnapshot(), tag);
/** Un enregistrement de programme nomme sa formation par la portée : c'est elle qui ordonne, pas le corps. */
const save = (offeringKey: string) => createCommand({ schoolId, kind: 'saveFormationProgramme', path: 'formations/programmes', resourceVersion: 0,
  scope: offeringKey, body: { offeringKey, expectedOfferingVersionId: randomUUID(), label: 'Parcours' } });
const creation = () => createCommand({ schoolId, kind: 'createFormation', path: 'formations', resourceVersion: 0,
  body: { categoryCode: 'B', intent: 'NEW', programmeLabel: null } });
const start = (command: SchoolCommand, tag: string) => lane.start(command, 'Le parcours est enregistré.', tag);

describe('Ordre des programmes par formation', () => {
  test('deux formations indépendantes partent ensemble ; la même formation attend, sans envoi ni succès annoncé', async () => {
    vi.useFakeTimers();
    script({ status: 201, body: created(), delayMs: 15_000 });
    const offerA = 'offering-a', offerB = 'offering-b';
    const first = start(save(offerA), formationTag(offerA));
    const second = start(save(offerB), formationTag(offerB));
    expect([first.admitted, second.admitted]).toEqual([true, true]);
    // Un autre formulaire de la même formation est refusé par le magasin, pas expédié.
    const sameFormation = start(save(offerA), 'other:offering-a');
    expect(sameFormation.admitted).toBe(false);
    await expect(sameFormation.result).resolves.toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_CONFLICT' });
    expect(calls).toHaveLength(2);
    // Rien n'est confirmé avant la réponse vérifiée.
    expect(view(formationTag(offerA))).toMatchObject({ busy: true, outcome: null });
    await vi.advanceTimersByTimeAsync(15_100);
    await expect(first.result).resolves.toMatchObject({ status: 'confirmed', via: 'response' });
    await expect(second.result).resolves.toMatchObject({ status: 'confirmed', via: 'response' });
    expect(view(formationTag(offerB)).outcome).toMatchObject({ tone: 'success' });
    expect(hooks.confirmed).toHaveBeenCalledTimes(2);
  });

  test('une création, qui n’a pas encore d’identifiant d’école, attend les écritures du catalogue', async () => {
    vi.useFakeTimers();
    script({ status: 201, body: created(), delayMs: 4_000 });
    expect(start(save('offering-a'), formationTag('offering-a')).admitted).toBe(true);
    const newFormation = start(creation(), formationTag(null));
    expect(newFormation.admitted).toBe(false);
    await expect(newFormation.result).resolves.toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_CONFLICT' });
    expect(calls).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(4_100);
    expect(hooks.confirmed).toHaveBeenCalledTimes(1);
  });

  test('réponse perdue : la demande reste suivie, le reçu la confirme sans seconde écriture', async () => {
    const lost = save('offering-a');
    script({ status: 503, body: { code: 'SERVICE_UNAVAILABLE' } });
    await expect(start(lost, formationTag('offering-a')).result).resolves.toMatchObject({ status: 'pending' });
    expect(view(formationTag('offering-a'))).toMatchObject({ following: true, outcome: null });
    expect(hooks.confirmed).not.toHaveBeenCalled();
    // AP72 répond pour la même opération : aucune nouvelle écriture n'est faite.
    script(call => call.method === 'GET' ? { status: 200, body: receipt(lost) } : { status: 500 });
    await expect(store.verify(schoolId, lost.operationId)).resolves.toMatchObject({ status: 'confirmed' });
    lane.reconcile(); lane.reconcile();
    expect(calls.map(call => call.method)).toEqual(['GET']);
    expect(view(formationTag('offering-a'))).toMatchObject({ following: false, outcome: null });
    expect(hooks.confirmed).toHaveBeenCalledTimes(1);
    const [intent, answer] = hooks.confirmed.mock.calls[0]!;
    expect((intent as LaneIntent).tag).toBe(formationTag('offering-a'));
    expect(answer).toBeNull();
  });

  test('un refus ne touche que sa formation : l’autre continue et rien n’est annoncé publié pour la refusée', async () => {
    vi.useFakeTimers();
    const refused = save('offering-a'), fine = save('offering-b');
    script(call => call.body?.includes('offering-a') ? { status: 409, body: { code: 'FORMATION_CHANGED' } } : { status: 201, body: created(), delayMs: 20 });
    const a = start(refused, formationTag('offering-a'));
    const b = start(fine, formationTag('offering-b'));
    await expect(a.result).resolves.toMatchObject({ status: 'rejected', code: 'FORMATION_CHANGED' });
    expect(view(formationTag('offering-a'))).toMatchObject({ busy: false, outcome: { tone: 'error', code: 'FORMATION_CHANGED' } });
    // Rien n'est confirmé pour la formation refusée ; l'autre demande est toujours en cours.
    expect(hooks.confirmed).not.toHaveBeenCalled();
    expect(view(formationTag('offering-b')).busy).toBe(true);
    await vi.advanceTimersByTimeAsync(30);
    await expect(b.result).resolves.toMatchObject({ status: 'confirmed' });
    expect(hooks.confirmed).toHaveBeenCalledTimes(1);
    expect(store.get(schoolId)).toBeUndefined();
  });
});
