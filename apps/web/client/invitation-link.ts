export interface InvitationLink { token: string | null; error: boolean }

/** Remove the entire fragment before rendering, fetching or authenticating. */
export function readInvitationLink(): InvitationLink {
  const fragment = window.location.hash;
  const isInvitation = window.location.pathname.replace(/\/$/, '') === '/app/invitation';
  if (!fragment || (!isInvitation && !fragment.includes('token='))) return { token: null, error: false };
  window.history.replaceState(null, '', window.location.pathname + window.location.search);
  const parameters = new URLSearchParams(fragment.slice(1));
  const values = parameters.getAll('token');
  const token = values[0];
  if (!isInvitation || values.length !== 1 || !token || !/^[A-Za-z0-9_-]{32,256}$/.test(token)) {
    return { token: null, error: true };
  }
  return { token, error: false };
}
