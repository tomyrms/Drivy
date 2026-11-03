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
    const fetch = vi.fn().mockResolvedValueOnce(reply('session', session())).mockResolvedValueOnce(reply('logout', { sessionClosed: true, revocation: 'confirmed' }));
    vi.stubGlobal('fetch', fetch);
    await expect(endSession()).resolves.toEqual({ sessionClosed: true, revocation: 'confirmed' });
    expect(fetch).toHaveBeenCalledTimes(2);
    expect(fetch.mock.calls[1]![1]).toMatchObject({ method: 'POST', headers: { 'X-CSRF-Token': 'fresh-csrf' }, body: '{}' });
  });

  test.each([0, 403, 503])('une fermeture sans confirmation (%s) reste un échec visible et peut être réessayée', async status => {
    vi.stubGlobal('window', { location: { origin } });
    const fetch = vi.fn().mockResolvedValueOnce(reply('session', session()));
    if (status === 0) fetch.mockRejectedValueOnce(new Error('offline'));
    else fetch.mockResolvedValueOnce(reply('logout', { code: status === 403 ? 'CSRF_REJECTED' : 'SERVICE_UNAVAILABLE' }, status));
    fetch.mockResolvedValueOnce(reply('session', session())).mockResolvedValueOnce(reply('logout', { sessionClosed: true, revocation: 'confirmed' }));
    vi.stubGlobal('fetch', fetch);
    await expect(endSession()).rejects.toBeInstanceOf(Error);
    await expect(endSession()).resolves.toEqual({ sessionClosed: true, revocation: 'confirmed' });
  });

  test('une session déjà fermée ne demande pas une seconde fermeture', async () => {
    vi.stubGlobal('window', { location: { origin } });
    const fetch = vi.fn().mockResolvedValueOnce(reply('session', session(false)));
    vi.stubGlobal('fetch', fetch);
    await expect(endSession()).resolves.toEqual({ sessionClosed: true, revocation: 'not-attempted' });
    expect(fetch).toHaveBeenCalledTimes(1);
  });
});

describe('Déconnexion : ce qui est confirmé et ce qui ne l’est pas', () => {
  const close = (logout: unknown) => {
    vi.stubGlobal('window', { location: { origin } });
    const fetch = vi.fn().mockResolvedValueOnce(reply('session', session())).mockResolvedValueOnce(reply('logout', logout));
    vi.stubGlobal('fetch', fetch);
    return endSession();
  };

  test('une révocation confirmée par le fournisseur est transmise', async () => {
    await expect(close({ sessionClosed: true, revocation: 'confirmed' }))
      .resolves.toEqual({ sessionClosed: true, revocation: 'confirmed' });
  });

  test('un échec de révocation n’empêche pas de dire que la session est fermée', async () => {
    await expect(close({ sessionClosed: true, revocation: 'failed' }))
      .resolves.toEqual({ sessionClosed: true, revocation: 'failed' });
  });

  test('sans jeton à révoquer, la révocation est dite non tentée', async () => {
    await expect(close({ sessionClosed: true, revocation: 'not-attempted' }))
      .resolves.toEqual({ sessionClosed: true, revocation: 'not-attempted' });
  });

  test('une ancienne réponse ne prétend pas savoir ce que la révocation est devenue', async () => {
    await expect(close({ ok: true })).resolves.toEqual({ sessionClosed: true, revocation: 'unknown' });
  });

  test('une valeur de révocation inconnue reste inconnue plutôt que de perdre la fermeture', async () => {
    await expect(close({ sessionClosed: true, revocation: 'UNAVAILABLE' }))
      .resolves.toEqual({ sessionClosed: true, revocation: 'unknown' });
  });
});
