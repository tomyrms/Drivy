import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { createCommand, type SchoolCommand } from '../client/command-core.js';
import { CommandLane, laneView, type LaneHooks, type LaneIntent, type LaneResult, type LaneStore } from '../client/command-lane.js';

/**
 * The real command store behind a lane, against a fake window and a scripted network: latency of 15 s, lost replies,
 * double presses, refusals and an account change. Every write to browser storage is recorded.
 */
type Store = LaneStore & {
  verify(schoolId: string, operationId?: string): Promise<{ status: string }>;
  resend(schoolId: string, csrf: string, operationId?: string): Promise<{ status: string }>;
  release(schoolId: string, operationId?: string): void;
  scopeToPerson(personId: string): boolean;
};
const storeModule = '../client/command-store.ts';
const schoolId = randomUUID();
const writes: string[] = [];
const memory = () => {
  const items = new Map<string, string>();
  return { getItem: (key: string) => items.get(key) ?? null, removeItem: (key: string) => { items.delete(key); },
    setItem: (key: string, value: string) => { items.set(key, value); writes.push(key + '=' + value); }, snapshot: () => [...items.values()] };
};
const envelope = (data: unknown) => ({ data, requestId: randomUUID(), serverTime: '2026-11-02T08:00:00.000Z' });
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
  writes.length = 0; session = memory(); local = memory();
  vi.stubGlobal('window', { location: { origin: 'https://drivy.example' }, sessionStorage: session, localStorage: local });
  await fresh();
});
afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

const resend = (id: string, version = 2) => createCommand({ schoolId, kind: 'resendInvitation', path: `invitations/${id}/resend`, ifMatch: version, resourceId: id, resourceVersion: version, body: {} });
const revoke = (id: string, reason = 'Erreur de saisie', version = 2) => createCommand({ schoolId, kind: 'revokeInvitation', path: `invitations/${id}/revoke`, ifMatch: version, resourceId: id, resourceVersion: version, body: { reason } });
const created = (command: SchoolCommand, extra: Record<string, unknown> = {}) => envelope({ id: command.resourceId ?? randomUUID(), schoolId, version: command.resourceVersion + 1, ...extra });
const receipt = (command: SchoolCommand, type: string, resourceType: string) => envelope({ operationId: command.operationId, commandType: type, resourceType,
  resourceId: command.resourceId, committedAt: '2026-11-02T08:00:00.000Z', resourceVersion: command.resourceVersion + 1 });
const view = (tag: string) => laneView(lane.getSnapshot(), tag);

describe('Une section, plusieurs intentions indépendantes', () => {
  test('une demande lente de 15 s ne bloque ni une autre invitation ni sa propre ligne n’est confirmée avant la réponse', async () => {
    vi.useFakeTimers();
    const slowId = randomUUID(), quickId = randomUUID();
    const slow = resend(slowId), quick = revoke(quickId);
    script(call => call.path.includes(slowId) ? { status: 200, body: created(slow), delayMs: 15_000 } : { status: 200, body: created(quick) });
    const first = lane.start(slow, 'Le renvoi est enregistré.', `invitation:${slowId}`);
    expect(first.admitted).toBe(true);
    expect(view(`invitation:${slowId}`)).toMatchObject({ busy: true, following: false, outcome: null });
    const second = lane.start(quick, 'La révocation est enregistrée.', `invitation:${quickId}`);
    expect(second.admitted).toBe(true);
    await expect(second.result).resolves.toMatchObject({ status: 'confirmed', via: 'response' });
    expect(view(`invitation:${quickId}`)).toMatchObject({ busy: false, outcome: { tone: 'success' } });
    // Après 14,9 s la lente est toujours en cours : rien n’est annoncé confirmé à sa place.
    await vi.advanceTimersByTimeAsync(14_900);
    expect(view(`invitation:${slowId}`)).toMatchObject({ busy: true, outcome: null });
    expect(hooks.confirmed).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(200);
    await expect(first.result).resolves.toMatchObject({ status: 'confirmed' });
    expect(view(`invitation:${slowId}`)).toMatchObject({ busy: false, outcome: { tone: 'success', message: 'Le renvoi est enregistré.' } });
    expect(hooks.confirmed).toHaveBeenCalledTimes(2);
  });

  test('la même invitation reste ordonnée : la seconde demande est refusée sur place, saisie gardée, sans second envoi', async () => {
    const id = randomUUID(), pending = resend(id);
    script(() => ({ status: 503, body: { code: 'SERVICE_UNAVAILABLE' } }));
    const first = lane.start(pending, 'Renvoyée.', `invitation:${id}`);
    await first.result;
    expect(view(`invitation:${id}`)).toMatchObject({ following: true });
    const second = lane.start(revoke(id), 'Révoquée.', `revoke:${id}`);
    expect(second.admitted).toBe(false);
    await expect(second.result).resolves.toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_CONFLICT' });
    expect(view(`revoke:${id}`).outcome).toMatchObject({ tone: 'error', title: 'Modification en attente' });
    expect(view(`revoke:${id}`).outcome?.message).toContain('Votre saisie est conservée');
    expect(calls).toHaveLength(1);
    // Une autre invitation n’attend pas.
    const otherId = randomUUID();
    script(() => ({ status: 200, body: created(resend(otherId)) }));
    expect(lane.start(resend(otherId), 'Renvoyée.', `invitation:${otherId}`).admitted).toBe(true);
  });

  test('un double appui n’envoie rien de plus : même intention, même opération', async () => {
    const id = randomUUID(), command = resend(id);
    script(() => ({ status: 200, body: created(command), delayMs: 50 }));
    vi.useFakeTimers();
    const first = lane.start(command, 'Renvoyée.', `invitation:${id}`);
    const sameTag = lane.start(command, 'Renvoyée.', `invitation:${id}`);
    const otherTag = lane.start(command, 'Renvoyée.', `second:${id}`);
    expect(sameTag.admitted).toBe(false);
    expect(otherTag.admitted).toBe(false);
    await vi.advanceTimersByTimeAsync(60);
    await first.result; await otherTag.result;
    expect(calls).toHaveLength(1);
    expect(calls[0]!.headers['Idempotency-Key']).toBe(command.operationId);
  });

  test('réponse perdue : l’intention est suivie, le reçu la confirme une seule fois, sans second envoi, pendant que le reste avance', async () => {
    const id = randomUUID(), lost = revoke(id);
    script(() => ({ status: 503, body: { code: 'SERVICE_UNAVAILABLE' } }));
    const result = await lane.start(lost, 'Révoquée.', `invitation:${id}`).result;
    expect(result.status).toBe('pending');
    expect(view(`invitation:${id}`)).toMatchObject({ following: true, outcome: null });
    expect(hooks.confirmed).not.toHaveBeenCalled();
    const otherId = randomUUID(), other = resend(otherId);
    script(() => ({ status: 200, body: created(other) }));
    await expect(lane.start(other, 'Renvoyée.', `invitation:${otherId}`).result).resolves.toMatchObject({ status: 'confirmed' });
    // Le reçu de la première : AP72 répond, aucune nouvelle écriture n’est faite.
    script(call => call.method === 'GET' ? { status: 200, body: receipt(lost, 'REVOKE_INVITATION', 'Invitation') } : { status: 500 });
    await expect(store.verify(schoolId, lost.operationId)).resolves.toMatchObject({ status: 'confirmed' });
    lane.reconcile(); lane.reconcile();
    expect(calls.map(call => call.method)).toEqual(['GET']);
    // Le panneau des demandes suivies annonce déjà le reçu : la voie ne montre pas de seconde confirmation.
    expect(view(`invitation:${id}`)).toMatchObject({ following: false, outcome: null });
    expect(hooks.confirmed).toHaveBeenCalledTimes(2);
    const [intent, answer] = hooks.confirmed.mock.calls.find(([item]) => (item as LaneIntent).operationId === lost.operationId)!;
    expect((intent as LaneIntent).tag).toBe(`invitation:${id}`);
    expect(answer).toBeNull();
  });

  test('la reprise renvoie la même demande : même clé, même corps, même version', async () => {
    const id = randomUUID(), lost = revoke(id, 'Motif confidentiel');
    script(() => ({ status: 0 }));
    await lane.start(lost, 'Révoquée.', `invitation:${id}`).result;
    script(() => ({ status: 200, body: created(lost) }));
    await expect(store.resend(schoolId, 'csrf-2', lost.operationId)).resolves.toMatchObject({ status: 'confirmed' });
    lane.reconcile();
    expect(calls).toHaveLength(1);
    expect(calls[0]!.headers['Idempotency-Key']).toBe(lost.operationId);
    expect(calls[0]!.headers['If-Match']).toBe('"2"');
    expect(JSON.parse(calls[0]!.body!)).toEqual({ operationId: lost.operationId, reason: 'Motif confidentiel' });
    expect(view(`invitation:${id}`).following).toBe(false);
  });

  test('un refus définitif ne touche que son intention et garde la saisie ; l’autre intention continue', async () => {
    const refusedId = randomUUID(), fineId = randomUUID(), refused = revoke(refusedId), fine = resend(fineId);
    script(call => call.path.includes(refusedId) ? { status: 409, body: { code: 'INVITATION_USED' } } : { status: 200, body: created(fine), delayMs: 20 });
    vi.useFakeTimers();
    const a = lane.start(fine, 'Renvoyée.', `invitation:${fineId}`);
    const b = lane.start(refused, 'Révoquée.', `invitation:${refusedId}`);
    await expect(b.result).resolves.toMatchObject({ status: 'rejected', code: 'INVITATION_USED' });
    expect(view(`invitation:${refusedId}`)).toMatchObject({ busy: false, outcome: { tone: 'error', code: 'INVITATION_USED' } });
    expect(view(`invitation:${fineId}`).busy).toBe(true);
    await vi.advanceTimersByTimeAsync(30);
    await expect(a.result).resolves.toMatchObject({ status: 'confirmed' });
    expect(hooks.confirmed).toHaveBeenCalledTimes(1);
    expect(store.get(schoolId)).toBeUndefined();
  });

  test('une admission locale refusée (quatre demandes actives) n’envoie rien et garde le formulaire', async () => {
    script(() => ({ status: 200, body: envelope({}), delayMs: 1000 }));
    vi.useFakeTimers();
    const started = Array.from({ length: 5 }, () => { const id = randomUUID(); return lane.start(resend(id), 'Renvoyée.', `invitation:${id}`); });
    expect(started.map(item => item.admitted)).toEqual([true, true, true, true, false]);
    await expect(started[4]!.result).resolves.toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_LIMIT' });
    expect(calls).toHaveLength(4);
  });

  test('changement de compte : les demandes sont retirées, une réponse tardive ne rappelle personne et ne montre aucun secret', async () => {
    store.scopeToPerson('personne-a');
    const id = randomUUID(), command = resend(id);
    script(() => ({ status: 200, body: created(command, { code: 'K7Q4-MX2P' }), delayMs: 5000 }));
    vi.useFakeTimers();
    const started = lane.start(command, 'Un nouveau code est créé.', `invitation:${id}`);
    expect(store.scopeToPerson('personne-b')).toBe(true);
    lane.dispose();
    await vi.advanceTimersByTimeAsync(6000);
    await expect(started.result).resolves.toMatchObject({ status: 'pending' });
    expect(hooks.confirmed).not.toHaveBeenCalled();
    expect(lane.getSnapshot().intents.size).toBe(0);
    expect(JSON.stringify([...lane.getSnapshot().outcomes])).not.toContain('K7Q4');
    expect(store.get(schoolId)).toBeUndefined();
    expect(lane.start(resend(randomUUID()), 'x', 'tag').admitted).toBe(false);
  });

  test('suivi arrêté ou abandonné par le magasin : l’intention suivie disparaît sans succès annoncé', async () => {
    const id = randomUUID(), command = resend(id);
    script(() => ({ status: 503, body: { code: 'SERVICE_UNAVAILABLE' } }));
    await lane.start(command, 'Renvoyée.', `invitation:${id}`).result;
    expect(view(`invitation:${id}`).following).toBe(true);
    // L'école ne retrouve pas la demande : seul cet état permet d'arrêter son suivi.
    script(() => ({ status: 404, body: { code: 'NOT_FOUND' } }));
    await store.verify(schoolId, command.operationId);
    store.release(schoolId, command.operationId);
    lane.reconcile();
    expect(view(`invitation:${id}`)).toMatchObject({ following: false, busy: false, outcome: null });
    expect(hooks.confirmed).not.toHaveBeenCalled();
  });

  test('aucun contenu de la demande, aucune donnée de personne ni code n’atteint le stockage du navigateur', async () => {
    const id = randomUUID(), secret = 'Motif très confidentiel', command = revoke(id, secret);
    script(() => ({ status: 503, body: { code: 'SERVICE_UNAVAILABLE' } }));
    await lane.start(command, 'Révoquée.', `invitation:${id}`).result;
    const mail = createCommand({ schoolId, kind: 'createInvitation', path: 'invitations', resourceVersion: 0, body: { delivery: 'EMAIL', email: 'eleve.synthetique@exemple.ch', roles: ['LEARNER'] } });
    script(() => ({ status: 201, body: created(mail, { code: 'ABCD-EFGH' }) }));
    await lane.start(mail, 'Enregistrée.', 'create:email').result;
    expect(writes.length).toBeGreaterThan(0);
    for (const write of writes) {
      expect(write).not.toContain(secret);
      expect(write).not.toContain('eleve.synthetique');
      expect(write).not.toContain('ABCD-EFGH');
    }
    expect(local.snapshot()).toEqual([]);
    const stored = JSON.parse(session.snapshot()[0]!) as Record<string, unknown>[];
    for (const item of stored) expect(Object.keys(item).sort()).toEqual(['createdAt', 'kind', 'operationId', 'resourceId', 'resourceVersion', 'schoolId']);
    // L’état de la voie ne garde aucun corps de réponse.
    expect(JSON.stringify([...lane.getSnapshot().outcomes, ...lane.getSnapshot().intents])).not.toContain('ABCD-EFGH');
  });
});

describe('Relecture ciblée', () => {
  test('confirmer une invitation relit les invitations, pas les horaires ni les dossiers', async () => {
    const { revisionOf, kindsOf } = await import('../client/command-families.js');
    const before = store.getSnapshot() as unknown as { byKind: Record<string, number>; rereads: number };
    const startInvitations = revisionOf(before, kindsOf('invitations')), startAvailability = revisionOf(before, kindsOf('availability')), startLearners = revisionOf(before, kindsOf('learners'));
    const id = randomUUID(), command = resend(id);
    script(() => ({ status: 200, body: created(command) }));
    await lane.start(command, 'Renvoyée.', `invitation:${id}`).result;
    const after = store.getSnapshot() as unknown as { byKind: Record<string, number>; rereads: number };
    expect(revisionOf(after, kindsOf('invitations'))).toBe(startInvitations + 1);
    expect(revisionOf(after, kindsOf('availability'))).toBe(startAvailability);
    expect(revisionOf(after, kindsOf('learners'))).toBe(startLearners);
    // Un refus définitif ne change aucune relecture : rien n'a été écrit.
    const refusedId = randomUUID();
    script(() => ({ status: 409, body: { code: 'INVITATION_USED' } }));
    await lane.start(revoke(refusedId), 'Révoquée.', `invitation:${refusedId}`).result;
    expect(revisionOf(store.getSnapshot() as unknown as { byKind: Record<string, number>; rereads: number }, kindsOf('invitations'))).toBe(startInvitations + 1);
  });
});

describe('Relecture ciblée du catalogue', () => {
  test('un tarif confirmé relit le catalogue ; une invitation, un horaire ou un dossier d’un autre domaine n’y touche pas', async () => {
    const { revisionOf, catalogueReads, kindsOf } = await import('../client/command-families.js');
    const view = () => store.getSnapshot() as unknown as { byKind: Record<string, number>; rereads: number };
    const start = revisionOf(view(), catalogueReads), startInvitations = revisionOf(view(), kindsOf('invitations'));
    const id = randomUUID(), invitation = resend(id);
    script(() => ({ status: 200, body: created(invitation) }));
    await lane.start(invitation, 'Renvoyée.', `invitation:${id}`).result;
    expect(revisionOf(view(), catalogueReads)).toBe(start);
    expect(revisionOf(view(), kindsOf('invitations'))).toBe(startInvitations + 1);
    const tariff = createCommand({ schoolId, kind: 'saveTariff', path: 'formations/tariffs', resourceVersion: 0, body: { mode: 'CREATE' } });
    script(() => ({ status: 201, body: envelope({ id: randomUUID(), schoolId, version: 1 }) }));
    await expect(lane.start(tariff, 'Le tarif est ajouté.', 'tariff:new').result).resolves.toMatchObject({ status: 'confirmed' });
    expect(revisionOf(view(), catalogueReads)).toBe(start + 1);
    expect(revisionOf(view(), kindsOf('invitations'))).toBe(startInvitations + 1);
    // Une inscription ouverte change les effectifs d'une formation : le catalogue les relit aussi.
    const training = createCommand({ schoolId, kind: 'createTraining', path: 'trainings', resourceVersion: 0, scope: randomUUID(), body: { learnerId: randomUUID() } });
    script(() => ({ status: 201, body: envelope({ id: randomUUID(), schoolId, version: 1 }) }));
    await lane.start(training, 'La formation est ouverte.', 'training:new').result;
    expect(revisionOf(view(), catalogueReads)).toBe(start + 2);
  });

  test('chaque famille ne contient que des commandes connues, sans doublon dans une famille', async () => {
    const { commandFamilies } = await import('../client/command-families.js');
    const { commandSpecs } = await import('../client/command-core.js');
    for (const [family, kinds] of Object.entries(commandFamilies)) {
      expect(new Set(kinds).size, family).toBe(kinds.length);
      for (const kind of kinds) expect(commandSpecs[kind as keyof typeof commandSpecs], `${family}:${kind}`).toBeDefined();
    }
  });
});

describe('Résultat que la voie ne confirme jamais d’elle-même', () => {
  test('un résultat incertain n’appelle jamais la confirmation et garde l’intention suivie', async () => {
    const id = randomUUID(), command = resend(id);
    script(() => ({ status: 200, body: envelope({ id: randomUUID(), schoolId, version: 3 }) }));
    const result = await lane.start(command, 'Renvoyée.', `invitation:${id}`).result as LaneResult;
    // La réponse nomme une autre invitation : elle ne prouve pas cette demande.
    expect(result.status).toBe('pending');
    expect(view(`invitation:${id}`)).toMatchObject({ following: true, outcome: null });
    expect(hooks.confirmed).not.toHaveBeenCalled();
  });
});
