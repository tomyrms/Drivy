import { afterEach, describe, expect, test, vi } from 'vitest';
import { endSession } from '../client/protocol.js';

const origin = 'https://drivy.example.test';
const session = (authenticated = true) => ({ authenticated, csrfToken: 'fresh-csrf', invitationPending: false });
const reply = (path: string, body: unknown, status = 200) => ({
  status, ok: status >= 200 && status < 300, url: `${origin}/app/bff/${path}`,
  headers: new Headers({ 'content-type': 'application/json' }), json: async () => body,
});
afterEach(() => vi.unstubAllGlobals());

describe('Déconnexion confirmée par le serveur', () => {
  test('relit la session et utilise son CSRF courant avant la fermeture', async () => {
    vi.stubGlobal('window', { location: { origin } });
    const fetch = vi.fn().mockResolvedValueOnce(reply('session', session())).mockResolvedValueOnce(reply('logout', { ok: true }));
    vi.stubGlobal('fetch', fetch);
    await expect(endSession()).resolves.toBeUndefined();
    expect(fetch).toHaveBeenCalledTimes(2);
    expect(fetch.mock.calls[1]![1]).toMatchObject({ method: 'POST', headers: { 'X-CSRF-Token': 'fresh-csrf' }, body: '{}' });
  });

  test.each([0, 403, 503])('une fermeture sans confirmation (%s) reste un échec visible et peut être réessayée', async status => {
    vi.stubGlobal('window', { location: { origin } });
    const fetch = vi.fn().mockResolvedValueOnce(reply('session', session()));
    if (status === 0) fetch.mockRejectedValueOnce(new Error('offline'));
    else fetch.mockResolvedValueOnce(reply('logout', { code: status === 403 ? 'CSRF_REJECTED' : 'SERVICE_UNAVAILABLE' }, status));
    fetch.mockResolvedValueOnce(reply('session', session())).mockResolvedValueOnce(reply('logout', { ok: true }));
    vi.stubGlobal('fetch', fetch);
    await expect(endSession()).rejects.toBeInstanceOf(Error);
    await expect(endSession()).resolves.toBeUndefined();
  });

  test('une session déjà fermée ne demande pas une seconde fermeture', async () => {
    vi.stubGlobal('window', { location: { origin } });
    const fetch = vi.fn().mockResolvedValueOnce(reply('session', session(false)));
    vi.stubGlobal('fetch', fetch);
    await expect(endSession()).resolves.toBeUndefined();
    expect(fetch).toHaveBeenCalledTimes(1);
  });
});
