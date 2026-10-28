import { db, ids, previewId, type FixtureRecord } from '../fixtures';
import type { PreviewFamily, PreviewRequest } from '../family';

/**
 * Synthetic behaviour of the team and invitations families. Synthetic data only: this module is reachable from the
 * separate preview entry and is never imported by the product code.
 *
 * The school never lists a code or a link: the single-use code travels only in the response of the command that
 * creates or renews it. It is therefore kept out of the stored records and added to that response alone.
 */
const day = 86_400_000;
const codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const issueCode = () => {
  const value = Array.from({ length: 8 }, () => codeAlphabet[Math.floor(Math.random() * codeAlphabet.length)]).join('');
  return `${value.slice(0, 4)}-${value.slice(4)}`;
};
const mask = (email: string) => `${email.trim().charAt(0).toLowerCase()}***@${email.split('@')[1] ?? 'example.test'}`;
/** Address of each e-mail invitation (the school never lists it): a second waiting invitation for it is refused, a revoked one frees it. */
const addresses = new Map<string, string>();
const isWaiting = (address: string) => db.invitations!.some(item => item.status === 'PENDING' && addresses.get(item.id) === address);
const member = (n: number, displayName: string, roles: string[], grants: string[], status = 'ACTIVE') =>
  ({ id: previewId(5100 + n), schoolId: ids.school, version: 1, personId: previewId(5300 + n), displayName, status, roles, grants, accessEpoch: 1 });
const invitationId = (n: number) => previewId(5500 + n);
const roleSet = (value: unknown): string[] => (Array.isArray(value) ? value.filter(item => ['ADMIN', 'INSTRUCTOR', 'LEARNER'].includes(item)) : []).sort();
const findInvitation = (id: string | undefined) => db.invitations!.find(item => item.id === id);

function seedMembers() {
  db.members!.push(
    member(1, 'Marie Dupont', ['INSTRUCTOR'], ['TAKE_ATTENDANCE']),
    member(2, 'Camille Roche', ['INSTRUCTOR'], [], 'INACTIVE'),
    member(3, 'Anne-Sophie Müller-Rochat de la Tour-Delacroix', ['INSTRUCTOR'], ['permit_review', 'MANAGE_COURSES']),
    ...['Éloïse Müller', 'Bruno Blanc', 'Jade Perrin', 'Sami Dubois', 'Léa Rochat', 'Noah Meier', 'Inès Favre', 'Hugo Charpentier', 'Lina Gachet', 'Théo Pasche', 'Zoé Cottier',
      'Louis Dufour', 'Maëlle Girard', 'Nathan Bovet', 'Elsa Mottier', 'Yanis Corboz', 'Alice Chappuis', 'Gabriel Jaquet', 'Mia Rossier', 'Liam Moret', 'Sofia Veillon',
      'Adam Pittet', 'Clara Pache', 'Rayan Cherix'].map((name, index) => member(10 + index, name, ['LEARNER'], [], index === 7 ? 'INACTIVE' : 'ACTIVE')),
  );
}

function seedInvitations() {
  const now = Date.now(), marieDupont = previewId(5101);
  const base = { schoolId: ids.school, version: 1 };
  const code = (n: number, status: string, instructor: string, days: number) => ({ ...base, id: invitationId(n), delivery: 'CODE', maskedEmail: null, roles: ['LEARNER'], status,
    expiresAt: new Date(now + days * day).toISOString(), trainings: [{ offeringId: ids.offering, instructorMembershipId: instructor }] });
  const mail = (n: number, address: string, roles: string[], status: string, days: number) => {
    addresses.set(invitationId(n), address);
    return { ...base, id: invitationId(n), delivery: 'EMAIL', maskedEmail: mask(address), roles, status, expiresAt: new Date(now + days * day).toISOString() };
  };
  // Oldest first, as the school lists them; the page shows the most recent first.
  const history = Array.from({ length: 22 }, (_, index) => mail(100 + index, `${'abcdefghijklmnopqrstuv'[index]}.archive${index}@example.test`, ['LEARNER'], index % 3 ? 'ACCEPTED' : 'EXPIRED', -30 - index));
  db.invitations!.push(
    ...history,
    mail(1, 'sam.team@example.test', ['INSTRUCTOR'], 'ACCEPTED', -12),
    code(1, 'ACCEPTED', ids.instructor, -9),
    mail(2, 'rene.team@example.test', ['ADMIN'], 'REVOKED', -8),
    code(2, 'REVOKED', ids.instructor, -6),
    mail(3, 'paul.team@example.test', ['INSTRUCTOR'], 'EXPIRED', -3),
    code(3, 'EXPIRED', ids.instructor, -2),
    mail(4, 'julie.martin@example.test', ['LEARNER'], 'PENDING', 5),
    mail(5, 'jean.martin@example.test', ['LEARNER'], 'PENDING', 4),
    mail(6, 'claire.team@example.test', ['INSTRUCTOR'], 'PENDING', 6),
    code(4, 'PENDING', previewId(6), 3),
    mail(7, 'hana.team@example.test', ['ADMIN', 'INSTRUCTOR'], 'PENDING', 2),
    code(5, 'PENDING', ids.instructor, 6),
    code(6, 'PENDING', marieDupont, 5),
  );
}

/** Codes a refusal would plausibly carry for each write of this family. */
function refusal(request: PreviewRequest): string | undefined {
  if (request.collection !== 'invitations') return undefined;
  if (!request.resourceId) return request.body.delivery === 'CODE' ? 'INVITATION_TRAINING_INVALID' : 'INVITATION_ALREADY_PENDING';
  return request.action === 'resend' ? 'INVITATION_DELIVERY_UNAVAILABLE' : 'INVITATION_USED';
}

export const teamFamily: PreviewFamily = {
  name: 'team',
  seed() { seedMembers(); seedInvitations(); },
  read(request, tools) {
    if (request.method === 'GET' && request.path === 'invitation-options') return tools.reply(200, tools.envelope({ emailInvitationsAvailable: true, codeInvitationsAvailable: true }));
    return undefined;
  },
  refusalCode: refusal,
  write(request, tools) {
    if (request.collection !== 'invitations') return undefined;
    const { body } = request;
    if (!request.resourceId && request.method === 'POST') {
      const record: FixtureRecord = { schoolId: ids.school, version: 1, id: tools.nextId(), status: 'PENDING', expiresAt: new Date(Date.now() + 7 * day).toISOString() };
      if (body.delivery === 'CODE') {
        const trainings = Array.isArray(body.trainings) ? body.trainings : [];
        const valid = JSON.stringify(roleSet(body.roles)) === '["LEARNER"]' && trainings.length > 0 && trainings.length <= 16
          && trainings.every((item: FixtureRecord) => db.offerings!.some(offering => offering.id === item.offeringId && offering.enabled)
            && db.members!.some(candidate => candidate.id === item.instructorMembershipId && candidate.status === 'ACTIVE' && candidate.roles.includes('INSTRUCTOR')));
        if (!valid) return tools.reply(400, { code: 'INVITATION_TRAINING_INVALID' });
        Object.assign(record, { delivery: 'CODE', maskedEmail: null, roles: ['LEARNER'], trainings: trainings.map((item: FixtureRecord) => ({ offeringId: item.offeringId, instructorMembershipId: item.instructorMembershipId })) });
        db.invitations!.push(record);
        return tools.commit('createInvitation', { ...record, code: issueCode() });
      }
      const address = String(body.email ?? '').trim().toLowerCase(), roles = roleSet(body.roles);
      if (body.delivery !== 'EMAIL' || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(address) || !roles.length) return tools.reply(400, { code: 'INVALID_REQUEST' });
      if (isWaiting(address)) return tools.reply(409, { code: 'INVITATION_ALREADY_PENDING' });
      addresses.set(record.id, address);
      Object.assign(record, { delivery: 'EMAIL', maskedEmail: mask(address), roles });
      db.invitations!.push(record);
      return tools.commit('createInvitation', record);
    }
    const target = findInvitation(request.resourceId);
    if (!target || !['resend', 'revoke'].includes(request.action ?? '')) return tools.reply(404, { code: 'NOT_FOUND' });
    if (!tools.versionMatches(target)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
    if (target.status === 'ACCEPTED') return tools.reply(409, { code: 'INVITATION_USED' });
    if (target.status === 'REVOKED') return tools.reply(409, { code: 'INVITATION_REVOKED' });
    if (request.action === 'revoke') {
      if (!String(body.reason ?? '').trim()) return tools.reply(400, { code: 'INVALID_REQUEST' });
      target.status = 'REVOKED'; target.version++;
      return tools.commit('revokeInvitation', target);
    }
    target.status = 'PENDING'; target.expiresAt = new Date(Date.now() + 7 * day).toISOString(); target.version++;
    return tools.commit('resendInvitation', target.delivery === 'CODE' ? { ...target, code: issueCode() } : target);
  },
};
