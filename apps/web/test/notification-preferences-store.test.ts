import { describe, expect, test, vi } from 'vitest';
import { NotificationPreferenceStore, type PreferenceTransport } from '../client/notification-preferences-store.js';
import { saveNotificationPreferences, type NotificationPreferences, type SaveOutcome } from '../client/notification-preferences-model.js';

const initial: NotificationPreferences = { version: 1, courseOffers: true, courseReminders: true, courseChanges: true, courseStaffAlerts: true,
  messagingPrivate: true, messagingGeneral: false, messagingMentions: true };
const flush = async () => { for (let i = 0; i < 15; i++) await Promise.resolve(); };
const deferred = <T>() => { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; };

function harness() {
  let server = { ...initial }, person = 'account-a';
  const transport: PreferenceTransport = {
    read: vi.fn(async () => ({ personId: person, value: { ...server } })),
    write: vi.fn<PreferenceTransport['write']>(async (_person, choices, version) => {
      if (version !== server.version) return { ok: false, conflict: true, kind: 'conflict' };
      server = { ...choices, version: version + 1 }; return { ok: true, value: { ...server } };
    }),
  };
  const store = new NotificationPreferenceStore(transport);
  return { store, transport, server: () => server, setServer: (value: NotificationPreferences) => { server = value; }, changePerson: () => { person = 'account-b'; } };
}

describe('Préférences : projection locale et réconciliation par catégorie', () => {
  test('les choix restent utilisables sous latence ; une ancienne réponse ne réactive pas une catégorie', async () => {
    const h = harness(); await h.store.refresh();
    const waiting = deferred<SaveOutcome>();
    vi.mocked(h.transport.write).mockImplementationOnce(() => waiting.promise);
    h.store.choose('courseOffers', false);
    expect(h.store.getSnapshot().value?.courseOffers).toBe(false);
    h.store.choose('courseOffers', true); h.store.choose('courseReminders', false);
    expect(h.store.getSnapshot().value).toMatchObject({ courseOffers: true, courseReminders: false });
    expect(h.transport.write).toHaveBeenCalledTimes(1);
    h.setServer({ ...initial, courseOffers: false, version: 2 });
    waiting.resolve({ ok: true, value: h.server() }); await flush();
    expect(h.transport.write).toHaveBeenCalledTimes(2);
    expect(h.server()).toMatchObject({ version: 3, courseOffers: true, courseReminders: false });
    expect(h.store.getSnapshot()).toMatchObject({ phase: 'ready', pendingKeys: [] });
  });

  test('un conflit sur une autre catégorie conserve le changement distant avant de renvoyer', async () => {
    const h = harness(); await h.store.refresh();
    h.setServer({ ...initial, courseChanges: false, version: 2 });
    h.store.choose('courseOffers', false); await flush();
    expect(h.server()).toMatchObject({ version: 3, courseChanges: false, courseOffers: false });
    expect(h.transport.write).toHaveBeenCalledTimes(2);
    expect(h.store.getSnapshot().pendingKeys).toEqual([]);
  });

  test('un conflit sur une catégorie modifiée pendant le PUT demande une décision explicite', async () => {
    const h = harness(); await h.store.refresh();
    const waiting = deferred<SaveOutcome>(); vi.mocked(h.transport.write).mockImplementationOnce(() => waiting.promise);
    h.store.choose('courseOffers', false); h.store.choose('courseOffers', true);
    h.setServer({ ...initial, courseOffers: false, version: 2 });
    waiting.resolve({ ok: false, conflict: true, kind: 'conflict' }); await flush();
    expect(h.store.getSnapshot()).toMatchObject({ phase: 'conflict', value: { courseOffers: true } });
    expect(h.transport.write).toHaveBeenCalledTimes(1);
    await h.store.retry();
    expect(h.server()).toMatchObject({ courseOffers: true, version: 3 });
  });

  test('les catégories de messagerie sont des choix indépendants du même objet versionné (#74)', async () => {
    const h = harness(); await h.store.refresh();
    h.store.choose('messagingGeneral', true); await flush();
    expect(h.transport.write).toHaveBeenCalledTimes(1);
    const { version: _version, ...choices } = initial;
    expect(vi.mocked(h.transport.write).mock.calls[0]![1]).toEqual({ ...choices, messagingGeneral: true });
    h.store.choose('messagingMentions', false); await flush();
    expect(h.server()).toMatchObject({ version: 3, courseOffers: true, messagingPrivate: true, messagingGeneral: true, messagingMentions: false });
    expect(h.store.getSnapshot()).toMatchObject({ phase: 'ready', pendingKeys: [] });
  });

  test('commit puis réponse perdue : la lecture confirme les choix sans second PUT', async () => {
    const h = harness(); await h.store.refresh();
    vi.mocked(h.transport.write).mockImplementationOnce(async (_person, body, version) => {
      h.setServer({ ...body, version: version + 1 }); return { ok: false, conflict: false, kind: 'uncertain' };
    });
    h.store.choose('courseOffers', false); await flush();
    expect(h.store.getSnapshot().phase).toBe('uncertain');
    await h.store.refresh();
    expect(h.transport.write).toHaveBeenCalledTimes(1);
    expect(h.store.getSnapshot()).toMatchObject({ phase: 'ready', value: { courseOffers: false }, pendingKeys: [] });
  });

  test('résultat inconnu sans nouvelle version : renvoi du même corps/version avant les nouveaux choix', async () => {
    const h = harness(); await h.store.refresh();
    vi.mocked(h.transport.write).mockResolvedValueOnce({ ok: false, conflict: false, kind: 'uncertain' });
    h.store.choose('courseOffers', false); await flush();
    h.store.choose('courseReminders', false);
    await h.store.refresh();
    expect(h.store.getSnapshot().phase).toBe('uncertain');
    expect(h.transport.write).toHaveBeenCalledTimes(1);
    await h.store.retry();
    expect(vi.mocked(h.transport.write).mock.calls[1]).toEqual(vi.mocked(h.transport.write).mock.calls[0]);
    expect(h.server()).toMatchObject({ version: 3, courseOffers: false, courseReminders: false });
  });

  test('refus sûr : seule la génération refusée est retirée, le choix plus récent reste appliqué', async () => {
    const h = harness(); await h.store.refresh();
    const waiting = deferred<SaveOutcome>(); vi.mocked(h.transport.write).mockImplementationOnce(() => waiting.promise);
    h.store.choose('courseOffers', false); h.store.choose('courseReminders', false);
    waiting.resolve({ ok: false, conflict: false, kind: 'rejected', status: 403 }); await flush();
    expect(h.store.getSnapshot().value).toMatchObject({ courseOffers: true, courseReminders: false });
    expect(h.server()).toMatchObject({ courseOffers: true, courseReminders: false });
  });

  test('une relecture lente ne remplace pas une écriture plus récente', async () => {
    const h = harness(); await h.store.refresh();
    const waiting = deferred<{ personId: string; value: NotificationPreferences }>();
    vi.mocked(h.transport.read).mockImplementationOnce(() => waiting.promise);
    const refresh = h.store.refresh(); h.store.choose('courseOffers', false);
    expect(h.transport.write).not.toHaveBeenCalled();
    h.setServer({ ...initial, courseChanges: false, version: 2 });
    waiting.resolve({ personId: 'account-a', value: h.server() }); await refresh; await flush();
    expect(h.server()).toMatchObject({ version: 3, courseChanges: false, courseOffers: false });
  });

  test('autre compte : les intentions et les réponses précédentes sont effacées', async () => {
    const h = harness(); await h.store.refresh();
    const waiting = deferred<SaveOutcome>(); vi.mocked(h.transport.write).mockImplementationOnce(() => waiting.promise);
    h.store.choose('courseOffers', false); h.store.clear(); h.changePerson(); await h.store.refresh();
    waiting.resolve({ ok: true, value: { ...initial, courseOffers: false, version: 2 } }); await flush();
    expect(h.store.getSnapshot()).toMatchObject({ value: initial, pendingKeys: [], phase: 'ready' });
  });

  test('perte de session ne conserve pas les valeurs affichées du compte précédent', async () => {
    const h = harness(); await h.store.refresh();
    vi.mocked(h.transport.read).mockRejectedValueOnce({ status: 401 });
    await h.store.refresh(); expect(h.store.getSnapshot()).toMatchObject({ value: null, phase: 'unavailable', pendingKeys: [] });
  });
});

describe('Transport PUT : absence de confirmation distincte du refus', () => {
  test.each([
    [200, { data: { ...initial } }],
    [200, { wrong: true }],
    [503, { code: 'API_UNAVAILABLE' }],
    [401, { code: 'SESSION_LOST_RESULT_UNKNOWN' }],
  ])('%i sans preuve de résultat reste incertain', async (status, body) => {
    const send = vi.fn(async () => new Response(JSON.stringify(body), { status: status as number }));
    expect(await saveNotificationPreferences(initial, 1, 'csrf', send as typeof fetch)).toMatchObject({ ok: false, kind: 'uncertain' });
  });
  test('une réponse sans les catégories de messagerie ne prouve pas le résultat (API trop ancienne)', async () => {
    const { messagingPrivate: _a, messagingGeneral: _b, messagingMentions: _c, ...legacy } = initial;
    const send = vi.fn(async () => new Response(JSON.stringify({ data: { ...legacy, version: 2 } }), { status: 200 }));
    expect(await saveNotificationPreferences({ ...initial, courseOffers: false }, 1, 'csrf', send as typeof fetch)).toMatchObject({ ok: false, kind: 'uncertain' });
  });
  test('refus sûr et version en conflit ont des résultats distincts', async () => {
    for (const [status, kind] of [[403, 'rejected'], [412, 'conflict']] as const) {
      const send = vi.fn(async () => new Response(JSON.stringify({ code: 'REFUSED' }), { status }));
      expect(await saveNotificationPreferences(initial, 1, 'csrf', send as typeof fetch)).toMatchObject({ ok: false, kind });
    }
  });
});
