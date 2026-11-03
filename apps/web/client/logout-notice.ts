import type { SessionClosure } from './protocol.js';

const storageKey = 'drivy.logout-unconfirmed';

export const logoutNoticeText = 'Déconnecté de cet appareil. La fermeture des autres sessions n’a pas pu être confirmée.';

/**
 * A sign-out that closed this device but could not confirm the identity provider revocation leaves one flag for the
 * next arrival page of this tab. It holds no person, token or school, lives in `sessionStorage` only, and ends at the
 * next sign-in. Without storage the notice is simply not kept.
 */
export function noteSessionClosure(closure: SessionClosure): void {
  try {
    if (closure.revocation === 'failed' || closure.revocation === 'unknown') window.sessionStorage.setItem(storageKey, '1');
    else window.sessionStorage.removeItem(storageKey);
  } catch { /* storage unavailable: nothing is kept */ }
}

export function readLogoutNotice(): boolean {
  try { return window.sessionStorage.getItem(storageKey) === '1'; } catch { return false; }
}

export function clearLogoutNotice(): void {
  try { window.sessionStorage.removeItem(storageKey); } catch { /* nothing stored */ }
}
