import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { clearLogoutNotice, logoutNoticeText, noteSessionClosure, readLogoutNotice } from '../client/logout-notice.js';

function memoryStorage() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => { values.set(key, value); },
    removeItem: (key: string) => { values.delete(key); },
    values,
  };
}
let storage: ReturnType<typeof memoryStorage>;
beforeEach(() => { storage = memoryStorage(); vi.stubGlobal('window', { sessionStorage: storage, localStorage: memoryStorage() }); });
afterEach(() => vi.unstubAllGlobals());

describe('Message de déconnexion non confirmée', () => {
  test.each(['confirmed', 'not-attempted'] as const)('aucun message quand la révocation est « %s »', revocation => {
    noteSessionClosure({ sessionClosed: true, revocation });
    expect(readLogoutNotice()).toBe(false);
  });

  test.each(['failed', 'unknown'] as const)('un message est annoncé quand la révocation est « %s »', revocation => {
    noteSessionClosure({ sessionClosed: true, revocation });
    expect(readLogoutNotice()).toBe(true);
  });

  test('une déconnexion confirmée efface le message d’une précédente', () => {
    noteSessionClosure({ sessionClosed: true, revocation: 'failed' });
    noteSessionClosure({ sessionClosed: true, revocation: 'confirmed' });
    expect(readLogoutNotice()).toBe(false);
  });

  test('le message disparaît à la prochaine connexion', () => {
    noteSessionClosure({ sessionClosed: true, revocation: 'unknown' });
    clearLogoutNotice();
    expect(readLogoutNotice()).toBe(false);
  });

  test('ne garde ni donnée personnelle ni localStorage : un simple indicateur de page', () => {
    noteSessionClosure({ sessionClosed: true, revocation: 'failed' });
    expect([...storage.values.values()]).toEqual(['1']);
    expect(window.localStorage.getItem('drivy.logout-unconfirmed')).toBeNull();
  });

  test('sans stockage disponible, la lecture reste sans message et sans erreur', () => {
    vi.stubGlobal('window', {});
    expect(() => noteSessionClosure({ sessionClosed: true, revocation: 'failed' })).not.toThrow();
    expect(readLogoutNotice()).toBe(false);
  });

  test('le texte dit que la personne est déconnectée ici, jamais l’inverse', () => {
    expect(logoutNoticeText).toBe('Déconnecté de cet appareil. La fermeture des autres sessions n’a pas pu être confirmée.');
  });
});
