import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { commandMessage, createCommand } from '../client/command-core.js';
import { revisionOf } from '../client/command-families.js';
import { RequestFailure } from '../client/protocol.js';
import { observationThemesSchema, readSchool } from '../client/school-api.js';

/**
 * Critères d'acceptation de #106 côté web, au niveau du magasin de commandes : transport simulé, aucune requête réelle.
 * Chaque test décrit ce que la personne voit pendant qu'une écriture attend : ce qui part, ce qui attend, ce qui reste.
 */
type SubmitResult = { status: string; body?: unknown; code?: string; message?: string; needsLogin?: boolean; via?: string };
type Entry = { phase: string; command: unknown; message: string; attempts: number } | undefined;
type Snapshot = {
  entries: ReadonlyMap<string, unknown>;
  revision: number;
  confirmed: { operationId: string } | null;
  confirmations: readonly { operationId: string }[];
  byKind: Readonly<Record<string, number>>;
  rereads: number;
};
type Store = {
  submit(command: unknown, csrf: string): Promise<SubmitResult>;
  verify(schoolId: string, operationId?: string): Promise<SubmitResult>;
  resend(schoolId: string, csrf: string, operationId?: string): Promise<SubmitResult>;
  get(schoolId: string, operationId?: string): Entry;
  getSnapshot(): Snapshot;
  scopeToPerson(personId: string): boolean;
  scopeToAccess(schoolId: string, membershipId: string, accessEpoch: number): void;
  clear(): void;
};

const schoolId = randomUUID();
const otherSchool = randomUUID();
const storeModule = '../client/command-store.ts';

const memory = () => {
  const items = new Map<string, string>();
  return { getItem: (key: string) => items.get(key) ?? null, removeItem: (key: string) => { items.delete(key); },
    setItem: (key: string, value: string) => { items.set(key, value); }, snapshot: () => [...items.values()] };
};
let session: ReturnType<typeof memory>;
let local: ReturnType<typeof memory>;
const envelope = (data: unknown) => ({ data, requestId: randomUUID(), serverTime: '2026-11-03T08:00:00.000Z' });

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

/** Deux agrégats indépendants : les signalements et les réglages des cours ne partagent rien. */
const themes = (now: number) => createCommand({ schoolId, kind: 'saveObservationThemes', path: 'observation-themes',
  ifMatch: 2, resourceVersion: 2, body: { themes: [] }, now });
const policy = (now: number) => createCommand({ schoolId, kind: 'saveCoursePolicy', path: 'course-policy',
  ifMatch: 1, resourceVersion: 1, body: { cancellationHours: 24 }, now });

const gate = () => { let release!: () => void; const opened = new Promise<void>(resolve => { release = resolve; }); return { opened, release: () => release() }; };
const bodyOperationId = (call: unknown[]) => JSON.parse(String((call[1] as { body?: unknown } | undefined)?.body)).operationId as string;
const isEmission = (call: unknown[]) => ((call[1] as { method?: string } | undefined)?.method ?? 'GET') !== 'GET';

beforeEach(() => {
  session = memory(); local = memory();
  vi.stubGlobal('window', { location: { origin: 'https://drivy.example' }, sessionStorage: session, localStorage: local });
});
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

describe('#106 · latence, ordre et contexte des commandes web', () => {
  test('critère 1 : deux commandes indépendantes — la seconde se confirme pendant que la première attend 15 s', async () => {
    vi.useFakeTimers();
    const store = await loadStore(), slow = themes(1_000), quick = policy(2_000);
    const send = vi.fn(async (input: URL | string) => {
      if (String(input).includes('observation-themes')) {
        // Réponse de la première commande : seulement après 15 s d'horloge simulée.
        await new Promise<void>(resolve => setTimeout(resolve, 15_000));
        return answer(200, envelope({ schoolId, version: 3 }))(input);
      }
      return answer(200, envelope({ schoolId, version: 2 }))(input);
    });
    vi.stubGlobal('fetch', send);
    const first = store.submit(slow, 'csrf');
    const second = store.submit(quick, 'csrf');
    await expect(second).resolves.toMatchObject({ status: 'confirmed', via: 'response' });
    expect(send).toHaveBeenCalledTimes(2);
    expect(store.get(schoolId, slow.operationId)).toMatchObject({ phase: 'sending' });
    expect(store.get(schoolId, quick.operationId)).toBeUndefined();
    expect(store.getSnapshot().revision).toBe(1);
    await vi.advanceTimersByTimeAsync(15_000);
    await expect(first).resolves.toMatchObject({ status: 'confirmed', via: 'response' });
    expect(store.getSnapshot().entries.size).toBe(0);
    expect(store.getSnapshot().revision).toBe(2);
  });

  test('critère 2 : deux commandes en conflit — la seconde attend la première, dans l’ordre, sans être perdue', async () => {
    const store = await loadStore(), first = policy(1_000), second = policy(2_000);
    const send = gate();
    const fetchMock = vi.fn(async (input: URL | string) => { await send.opened; return answer(200, envelope({ schoolId, version: 2 }))(input); });
    vi.stubGlobal('fetch', fetchMock);
    const running = store.submit(first, 'csrf');
    const waiting = await store.submit(second, 'csrf');
    expect(waiting).toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_CONFLICT' });
    expect(waiting.message).toContain('conservée');
    expect(fetchMock).toHaveBeenCalledTimes(1);
    send.release();
    await expect(running).resolves.toMatchObject({ status: 'confirmed' });
    // La seconde intention n’a pas été perdue : elle part une fois la première confirmée, dans l’ordre.
    await expect(store.submit(second, 'csrf')).resolves.toMatchObject({ status: 'confirmed' });
    expect(fetchMock.mock.calls.map(bodyOperationId)).toEqual([first.operationId, second.operationId]);
  });

  test('critère 3 : double appui sur la même action — une seule écriture envoyée', async () => {
    const store = await loadStore(), command = themes(1_000);
    const send = gate();
    const fetchMock = vi.fn(async (input: URL | string) => { await send.opened; return answer(200, envelope({ schoolId, version: 3 }))(input); });
    vi.stubGlobal('fetch', fetchMock);
    const first = store.submit(command, 'csrf');
    const again = await store.submit(command, 'csrf');
    expect(again).toMatchObject({ status: 'rejected', code: 'LOCAL_COMMAND_CONFLICT' });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    send.release();
    await expect(first).resolves.toMatchObject({ status: 'confirmed' });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const emission = fetchMock.mock.calls.filter(isEmission);
    expect(emission).toHaveLength(1);
    const sent = emission[0] as unknown as [URL, { headers: Record<string, string>; body?: string }];
    expect(sent[1].headers).toMatchObject({ 'Idempotency-Key': command.operationId });
    expect(JSON.parse(String(sent[1].body)).operationId).toBe(command.operationId);
  });

  test('critère 4 : réponse perdue après écriture — le reçu confirme, sans second envoi ni échec', async () => {
    const store = await loadStore(), command = policy(1_000);
    const timeout = vi.fn(async () => { throw Object.assign(new Error('The operation was aborted'), { name: 'AbortError' }); });
    vi.stubGlobal('fetch', timeout);
    const sent = await store.submit(command, 'csrf');
    expect(sent).toMatchObject({ status: 'pending' });
    expect(sent.status).not.toBe('rejected');
    expect(store.get(schoolId, command.operationId)).toMatchObject({ phase: 'uncertain' });
    expect(store.getSnapshot().revision).toBe(0);
    const receipt = answer(200, envelope({ operationId: command.operationId, commandType: 'SAVE_COURSE_POLICY',
      resourceType: 'CoursePolicy', resourceId: schoolId, resourceVersion: 2, committedAt: '2026-11-03T08:00:00.000Z' }));
    vi.stubGlobal('fetch', receipt);
    await expect(store.verify(schoolId, command.operationId)).resolves.toMatchObject({ status: 'confirmed', via: 'receipt' });
    expect(receipt).toHaveBeenCalledTimes(1);
    expect(String(receipt.mock.calls[0]![0])).toContain(`/operations/${command.operationId}`);
    expect(isEmission(receipt.mock.calls[0]!)).toBe(false);
    expect(store.get(schoolId, command.operationId)).toBeUndefined();
    expect(store.getSnapshot()).toMatchObject({ revision: 1 });
    expect(store.getSnapshot().confirmed?.operationId).toBe(command.operationId);
    // Une seule écriture a quitté la page : la relecture du reçu n’en est pas une seconde.
    expect(timeout.mock.calls.filter(isEmission)).toHaveLength(1);
  });

  test('critère 5 : réponses inversées — la liste des confirmations suit l’ordre des commandes, pas l’arrivée', async () => {
    const store = await loadStore(), older = themes(1_000), newer = policy(2_000);
    const late = gate();
    const fetchMock = vi.fn(async (input: URL | string) => {
      if (String(input).includes('observation-themes')) { await late.opened; return answer(200, envelope({ schoolId, version: 3 }))(input); }
      return answer(200, envelope({ schoolId, version: 2 }))(input);
    });
    vi.stubGlobal('fetch', fetchMock);
    const first = store.submit(older, 'csrf');
    const second = store.submit(newer, 'csrf');
    await expect(second).resolves.toMatchObject({ status: 'confirmed' });
    late.release();
    await expect(first).resolves.toMatchObject({ status: 'confirmed' });
    const snapshot = store.getSnapshot();
    expect(snapshot.entries.size).toBe(0);
    // L’état rejoué dans l’ordre des commandes finit sur l’intention la plus récente, même répondue en dernier.
    expect(snapshot.confirmations.map(item => item.operationId)).toEqual([older.operationId, newer.operationId]);
    expect(snapshot.confirmations[snapshot.confirmations.length - 1]?.operationId).toBe(newer.operationId);
    expect(revisionOf(snapshot, ['saveObservationThemes', 'saveCoursePolicy'])).toBe(2);
  });

  test('une commande plus récente confirmée d’abord ne masque pas la confirmation de la sienne', async () => {
    const store = await loadStore(), mine = themes(1_000), later = policy(2_000);
    const late = gate();
    const fetchMock = vi.fn(async (input: URL | string) => {
      if (String(input).includes('observation-themes')) { await late.opened; return answer(200, envelope({ schoolId, version: 3 }))(input); }
      return answer(200, envelope({ schoolId, version: 2 }))(input);
    });
    vi.stubGlobal('fetch', fetchMock);
    const own = store.submit(mine, 'csrf');
    const newer = store.submit(later, 'csrf');
    await expect(newer).resolves.toMatchObject({ status: 'confirmed' });
    late.release();
    await expect(own).resolves.toMatchObject({ status: 'confirmed' });
    const snapshot = store.getSnapshot();
    // `confirmed` est la confirmation qui vient d’arriver : l’éditeur d’accès y reconnaît sa propre écriture
    // (access-controller : `confirmed?.operationId === operation.current`), sans faux conflit.
    expect(snapshot.confirmed?.operationId).toBe(mine.operationId);
    // La liste, elle, reste dans l’ordre de départ.
    expect(snapshot.confirmations.map(item => item.operationId)).toEqual([mine.operationId, later.operationId]);
  });

  test('critère 6 : écriture confirmée puis relecture en échec — confirmée, à actualiser, aucun échec de commande', async () => {
    const store = await loadStore(), command = themes(1_000);
    vi.stubGlobal('fetch', answer(200, envelope({ schoolId, version: 3 })));
    await expect(store.submit(command, 'csrf')).resolves.toMatchObject({ status: 'confirmed', via: 'response' });
    const confirmed = store.getSnapshot();
    expect(confirmed.confirmed?.operationId).toBe(command.operationId);
    expect(confirmed.byKind.saveObservationThemes).toBe(1);
    expect(confirmed.revision).toBe(1);
    // La section relit l’école ; cette lecture échoue. La commande reste confirmée et les sections restent à actualiser.
    vi.stubGlobal('fetch', answer(503, { code: 'SERVICE_UNAVAILABLE' }));
    await expect(readSchool(schoolId, 'observation-themes', observationThemesSchema)).rejects.toBeInstanceOf(RequestFailure);
    const after = store.getSnapshot();
    expect(after).toMatchObject({ revision: 1 });
    expect(after.confirmed?.operationId).toBe(command.operationId);
    expect(after.entries.size).toBe(0);
    expect(store.get(schoolId)).toBeUndefined();
  });

  test.each([[403, 'SETUP_ACCESS_REQUIRED'], [409, 'COURSE_POLICY_CONFLICT'], [412, 'VERSION_CONFLICT']] as const)(
    'critère 7 : refus %i %s — la saisie reste, les autres commandes continuent', async (status, code) => {
      const store = await loadStore(), running = themes(1_000), refused = policy(2_000);
      const send = gate();
      const fetchMock = vi.fn(async (input: URL | string) => {
        if (String(input).includes('course-policy')) return answer(status, { code })(input);
        await send.opened;
        return answer(200, envelope({ schoolId, version: 3 }))(input);
      });
      vi.stubGlobal('fetch', fetchMock);
      const first = store.submit(running, 'csrf');
      const second = await store.submit(refused, 'csrf');
      expect(second).toMatchObject({ status: 'rejected', code, needsLogin: false, message: commandMessage(code) });
      // Aucun rollback : la commande en cours garde son contenu et son suivi.
      expect(store.get(schoolId, running.operationId)).toMatchObject({ phase: 'sending', command: running });
      expect(store.get(schoolId, refused.operationId)).toBeUndefined();
      expect(store.getSnapshot().revision).toBe(0);
      expect(session.snapshot().join('')).not.toContain(refused.operationId);
      send.release();
      await expect(first).resolves.toMatchObject({ status: 'confirmed' });
      expect(store.getSnapshot().revision).toBe(1);
    });

  test('critère 8 : changement de compte pendant une commande en vol — aucune réponse ne s’applique', async () => {
    const store = await loadStore(), command = themes(1_000);
    store.scopeToPerson(randomUUID());
    const send = gate();
    vi.stubGlobal('fetch', vi.fn(async (input: URL | string) => { await send.opened; return answer(200, envelope({ schoolId, version: 3 }))(input); }));
    const sending = store.submit(command, 'csrf');
    expect(store.scopeToPerson(randomUUID())).toBe(true);
    send.release();
    await expect(sending).resolves.toMatchObject({ status: 'pending' });
    expect(store.getSnapshot()).toMatchObject({ revision: 0, confirmed: null });
    expect(store.getSnapshot().entries.size).toBe(0);
  });

  test('critère 8 : changement d’école pendant une commande en vol — aucune réponse ne s’applique au nouveau contexte', async () => {
    const store = await loadStore(), member = randomUUID(), command = themes(1_000);
    store.scopeToPerson(randomUUID());
    store.scopeToAccess(schoolId, member, 1);
    const send = gate();
    vi.stubGlobal('fetch', vi.fn(async (input: URL | string) => { await send.opened; return answer(200, envelope({ schoolId, version: 3 }))(input); }));
    const sending = store.submit(command, 'csrf');
    // Le bureau passe à une autre école : la réponse de la précédente ne peut plus rien confirmer ici.
    store.scopeToAccess(otherSchool, randomUUID(), 1);
    send.release();
    await expect(sending).resolves.toMatchObject({ status: 'pending' });
    const snapshot = store.getSnapshot();
    expect(snapshot).toMatchObject({ revision: 0, confirmed: null });
    expect(snapshot.byKind.saveObservationThemes).toBeUndefined();
    expect(store.get(otherSchool)).toBeUndefined();
    // La demande de l’ancienne école n’est ni appliquée ni perdue : son résultat reste à vérifier.
    expect(store.get(schoolId, command.operationId)).toMatchObject({ phase: 'uncertain', command });
  });
});
