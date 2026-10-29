import type { InvitationPreview, Member } from '../../protocol';

/** Synthetic entry only. No credentials, names typed in forms or network calls are retained. */
export type EntryScene = 'login' | 'schools' | 'empty' | 'invitation' | 'expired' | 'unverified' | 'mismatch' | 'lost-reply' | 'changed' | 'slow' | 'recovery' | 'recovery-unavailable';
const signedOut = new Set<EntryScene>(['login', 'recovery', 'recovery-unavailable']);
const accountOnly = new Set<EntryScene>(['schools', 'empty']);
const member: Member = {
  membershipId: '10000000-0000-4000-8000-000000000001', schoolId: '10000000-0000-4000-8000-000000000002',
  schoolName: 'École des Rives · démonstration', roles: ['ADMIN'], grants: [], accessEpoch: 1,
};
const invitation: InvitationPreview = {
  invitationId: '10000000-0000-4000-8000-000000000003', schoolId: member.schoolId, schoolName: member.schoolName,
  roles: ['LEARNER'], delivery: 'CODE', maskedEmail: null, expiresAt: '2027-01-01T18:00:00Z',
  profileIdentity: { firstName: 'Alex', lastName: 'Exemple' },
  notice: { version: 1, noticeText: 'Ces informations entièrement fictives illustrent la notice communiquée par votre école. Le compte, les leçons et les bilans sont accessibles aux membres autorisés de cette école.',
    retentionText: 'Les durées applicables et les demandes de consultation sont présentées ici par l’école. Cet aperçu ne constitue pas une politique en vigueur.', contactEmail: 'ecole@example.test' },
};

export function createEntryPreviewTransport(scene: EntryScene, origin: string): typeof fetch {
  let authenticated = !signedOut.has(scene);
  let pending = authenticated && !accountOnly.has(scene);
  let accepted = false;
  let uncertain = false;
  let firstLostReply = true;
  let sessionVersion = 1;
  let delivery: 'CODE' | 'EMAIL' = scene === 'unverified' || scene === 'mismatch' ? 'EMAIL' : 'CODE';
  let kind = 'LEARNER_INVITATION';
  return async (input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input), origin);
    const reply = (status: number, body: unknown) => {
      const result = new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
      Object.defineProperty(result, 'url', { value: url.href });
      return result;
    };
    if (url.origin !== origin || !url.pathname.startsWith('/app/bff/')) return reply(403, { code: 'PREVIEW_NETWORK_BLOCKED' });
    const path = url.pathname.slice('/app/bff/'.length);
    const method = init?.method ?? 'GET';
    const csrf = `synthetic-entry-${sessionVersion}`;
    if (method === 'POST' && new Headers(init?.headers).get('X-CSRF-Token') !== csrf) return reply(403, { code: 'CSRF_REJECTED' });
    let body: Record<string, unknown> = {};
    try { if (init?.body) body = JSON.parse(String(init.body)); } catch { return reply(400, { code: 'INVALID_REQUEST' }); }
    if (scene === 'slow' && method === 'POST') await new Promise(resolve => setTimeout(resolve, 1200));
    if (path === 'session' && method === 'GET') return reply(200, {
      authenticated, csrfToken: csrf, invitationPending: pending && (!accepted || uncertain),
      ...(authenticated ? { user: { displayName: 'Alex Exemple', email: 'alex@example.test', emailVerified: scene !== 'unverified' } } : {}),
    });
    if (path === 'me' && method === 'GET') {
      if (!authenticated) return reply(401, { code: 'SESSION_EXPIRED' });
      const memberships = scene === 'schools' ? [member, { ...member, schoolId: '10000000-0000-4000-8000-000000000004', membershipId: '10000000-0000-4000-8000-000000000005', schoolName: 'École du Lac · démonstration', roles: ['INSTRUCTOR'] }]
        : accepted ? [{ ...member, roles: ['LEARNER'] }] : [];
      return reply(200, { data: { personId: '10000000-0000-4000-8000-000000000006', displayName: 'Alex Exemple', version: 1, memberships } });
    }
    if (path === 'access-code' && method === 'POST') {
      if (body.code !== 'DEMO-DEMO' && body.code !== 'OPEN-OPEN') return reply(404, { code: 'ACCESS_CODE_INVALID' });
      kind = body.code === 'OPEN-OPEN' ? 'SCHOOL_OPENING' : 'LEARNER_INVITATION';
      pending = kind === 'LEARNER_INVITATION'; delivery = 'CODE';
      return reply(200, { kind, schoolName: member.schoolName, expiresAt: invitation.expiresAt });
    }
    if ((path === 'password-login' || path === 'accounts') && method === 'POST') {
      if (path === 'password-login' && (!body.email || !body.password)) return reply(401, { code: 'INVALID_CREDENTIALS' });
      if (path === 'accounts' && !pending && kind !== 'SCHOOL_OPENING') return reply(404, { code: 'ACCESS_CODE_INVALID' });
      authenticated = true; sessionVersion++;
      return reply(200, path === 'accounts' ? { kind: delivery === 'EMAIL' ? 'EMAIL_INVITATION' : kind } : { ok: true });
    }
    if (path === 'logout' && method === 'POST') {
      authenticated = false; pending = false; accepted = false; sessionVersion++;
      return reply(200, { ok: true });
    }
    if (path === 'invitation' && method === 'POST') {
      if (uncertain) return reply(409, { code: 'INVITATION_RESULT_UNKNOWN' });
      pending = true; delivery = 'EMAIL'; return reply(200, { ok: true });
    }
    if (path.startsWith('invitation/') && !authenticated) return reply(401, { code: 'SESSION_EXPIRED' });
    if (path === 'invitation/preview' && method === 'POST') {
      if (!pending) return reply(404, { code: 'INVITATION_NOT_FOUND' });
      if (scene === 'expired') return reply(410, { code: 'INVITATION_EXPIRED' });
      if (scene === 'mismatch') return reply(403, { code: 'INVITATION_IDENTITY_MISMATCH' });
      return reply(200, { data: { ...invitation, delivery }, confirmation: 'synthetic-entry-confirmation', uncertain });
    }
    if (path === 'invitation/clear' && method === 'POST') {
      if (uncertain) return reply(409, { code: 'INVITATION_IN_PROGRESS' });
      pending = false; return reply(200, { ok: true });
    }
    if (path === 'invitation/accept' && method === 'POST') {
      if (!pending || body.confirmation !== 'synthetic-entry-confirmation' || body.invitationId !== invitation.invitationId || scene === 'changed') return reply(409, { code: 'INVITATION_PREVIEW_CHANGED' });
      if (scene === 'unverified') return reply(403, { code: 'EMAIL_NOT_VERIFIED' });
      accepted = true;
      if (scene === 'lost-reply' && firstLostReply) { firstLostReply = false; uncertain = true; throw new TypeError('Synthetic response lost'); }
      uncertain = false;
      return reply(201, { data: { ...member, roles: ['LEARNER'] } });
    }
    if (path === 'account-recovery/options' && method === 'GET') return reply(200, { data: scene === 'recovery-unavailable' ? { available: false, recoveryUrl: null } : { available: true, recoveryUrl: `${origin}/synthetic-identity` } });
    if (path === 'account-recovery/start' && method === 'POST') return reply(200, { url: `${origin}/synthetic-identity` });
    return reply(404, { code: 'PREVIEW_NETWORK_BLOCKED' });
  };
}
