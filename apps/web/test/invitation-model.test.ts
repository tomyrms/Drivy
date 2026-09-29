import { describe, expect, test } from 'vitest';
import { randomUUID } from 'node:crypto';
import {
  activeInstructors, defaultInstructorId, invitationCodeMessage, invitationLabel, invitationSchema, issuedCodeOf, offeringLabel, openOfferings,
  parseInvitationResponse, type Invitation,
} from '../client/invitation-model.js';

const schoolId = randomUUID();
const offeringId = randomUUID();
const instructorId = randomUUID();
const expiresAt = '2026-10-06T08:00:00.000Z';
const envelope = (data: unknown) => ({ data, requestId: randomUUID(), serverTime: '2026-09-29T08:00:00.000Z' });
const codeInvitation = (extra: Record<string, unknown> = {}) => ({
  id: randomUUID(), schoolId, version: 1, delivery: 'CODE', maskedEmail: null, roles: ['LEARNER'], status: 'PENDING', expiresAt,
  training: { offeringId, instructorMembershipId: instructorId }, ...extra,
});
const emailInvitation = (extra: Record<string, unknown> = {}) => ({
  id: randomUUID(), schoolId, version: 2, delivery: 'EMAIL', maskedEmail: 'p***@example.test', roles: ['INSTRUCTOR'], status: 'PENDING', expiresAt, ...extra,
});

describe('Invitation : lecture et code à usage unique', () => {
  test('la liste accepte l’e-mail masqué et le code sans adresse ; le code n’y figure pas', () => {
    expect(invitationSchema.safeParse(emailInvitation()).success).toBe(true);
    const listed = invitationSchema.parse(codeInvitation());
    expect(listed.maskedEmail).toBeNull();
    expect(listed.code).toBeUndefined();
    expect(invitationSchema.safeParse(codeInvitation({ training: null })).success).toBe(true);
    expect(invitationSchema.safeParse(emailInvitation({ training: undefined })).success).toBe(true);
  });

  test('un mode de remise inconnu, une adresse absente ou un code vide sont refusés', () => {
    expect(invitationSchema.safeParse(codeInvitation({ delivery: 'SMS' })).success).toBe(false);
    const { maskedEmail: _omitted, ...withoutAddress } = codeInvitation();
    expect(invitationSchema.safeParse(withoutAddress).success).toBe(false);
    expect(invitationSchema.safeParse(codeInvitation({ code: '' })).success).toBe(false);
    expect(invitationSchema.safeParse(codeInvitation({ training: { offeringId: 'x', instructorMembershipId: instructorId } })).success).toBe(false);
  });

  test('la réponse de création ou de renouvellement porte le code, vérifié contre l’école et l’invitation visée', () => {
    const created = codeInvitation({ code: 'K7Q4-MX2P' });
    const parsed = parseInvitationResponse(envelope(created), { schoolId });
    expect(issuedCodeOf(parsed)).toEqual({ invitationId: created.id, code: 'K7Q4-MX2P', expiresAt });
    // Renouvellement : la réponse doit concerner l’invitation renouvelée, casse des UUID ignorée.
    expect(parseInvitationResponse(envelope(created), { schoolId: schoolId.toUpperCase(), invitationId: created.id.toUpperCase() })).not.toBeNull();
    expect(parseInvitationResponse(envelope(created), { schoolId, invitationId: randomUUID() })).toBeNull();
    expect(parseInvitationResponse(envelope(created), { schoolId: randomUUID() })).toBeNull();
  });

  test('sans enveloppe valide, aucun code n’est montré', () => {
    const created = codeInvitation({ code: 'K7Q4-MX2P' });
    expect(parseInvitationResponse(created, { schoolId })).toBeNull();
    expect(parseInvitationResponse(null, { schoolId })).toBeNull();
    expect(parseInvitationResponse({ data: created, requestId: '', serverTime: 'hier' }, { schoolId })).toBeNull();
    expect(parseInvitationResponse(envelope({ ...created, delivery: 'ROBOT' }), { schoolId })).toBeNull();
    expect(issuedCodeOf(null)).toBeNull();
  });

  test('seule une invitation par code en attente et portant un code peut en afficher un', () => {
    const shown = (extra: Record<string, unknown>) => issuedCodeOf(parseInvitationResponse(envelope(codeInvitation(extra)), { schoolId }));
    expect(shown({ code: 'K7Q4-MX2P' })).not.toBeNull();
    expect(shown({})).toBeNull();
    expect(shown({ code: 'K7Q4-MX2P', status: 'REVOKED' })).toBeNull();
    const email = parseInvitationResponse(envelope(emailInvitation({ code: 'K7Q4-MX2P' })), { schoolId });
    expect(issuedCodeOf(email)).toBeNull();
  });
});

describe('Invitation : choix de l’offre et du moniteur', () => {
  const offer = (offeringKey: string, version: number, enabled: boolean, categoryCode = 'B') => ({ id: randomUUID(), offeringKey, version, enabled, categoryCode });
  const member = (displayName: string, roles: string[], status = 'ACTIVE') => ({ id: randomUUID(), displayName, roles, status });

  test('seule la dernière version de chaque offre compte, et seulement si elle est ouverte', () => {
    const oldB = offer('b-standard', 1, true), newB = offer('b-standard', 2, true);
    const disabledNow = offer('a-standard', 3, false, 'A'), enabledBefore = offer('a-standard', 2, true, 'A');
    const other = offer('am-standard', 1, true, 'AM');
    const open = openOfferings([oldB, disabledNow, newB, enabledBefore, other]);
    expect(open.map(item => item.id)).toEqual([other.id, newB.id]);
    expect(openOfferings([])).toEqual([]);
  });

  test('deux offres d’une même catégorie se distinguent par leur référence, pas leurs versions', () => {
    const standard = offer('b-standard', 2, true), intensive = offer('b-intensif', 1, true), moped = offer('am-standard', 1, true, 'AM');
    const open = openOfferings([offer('b-standard', 1, true), standard, intensive, moped]);
    expect(offeringLabel(moped, open)).toBe('Permis AM');
    expect(offeringLabel(standard, open)).toBe('Permis B · b-standard');
    expect(offeringLabel(intensive, open)).toBe('Permis B · b-intensif');
    expect(offeringLabel(standard, [offer('b-standard', 1, true), standard])).toBe('Permis B');
  });

  test('moniteurs : membres actifs avec le rôle Moniteur, par ordre alphabétique français', () => {
    const list = [member('Zoé', ['INSTRUCTOR']), member('Émile', ['INSTRUCTOR', 'ADMIN']), member('Alice', ['ADMIN']), member('Bruno', ['INSTRUCTOR'], 'SUSPENDED'), member('Élodie', ['LEARNER'])];
    expect(activeInstructors(list).map(item => item.displayName)).toEqual(['Émile', 'Zoé']);
  });

  test('le moniteur par défaut est le membre connecté seulement s’il est lui-même moniteur actif', () => {
    const self = member('Luc', ['ADMIN', 'INSTRUCTOR']);
    const instructors = activeInstructors([self, member('Marie', ['INSTRUCTOR'])]);
    expect(defaultInstructorId(self.id, instructors)).toBe(self.id);
    expect(defaultInstructorId(self.id.toUpperCase(), instructors)).toBe(self.id);
    expect(defaultInstructorId(randomUUID(), instructors)).toBe('');
    expect(defaultInstructorId(self.id, [])).toBe('');
  });
});

describe('Invitation : libellés', () => {
  const offerings = [{ id: offeringId, offeringKey: 'b-standard', version: 1, enabled: true, categoryCode: 'B' }];
  const members = [{ id: instructorId, displayName: 'Luc Martin', status: 'ACTIVE', roles: ['INSTRUCTOR'] }];
  const label = (invitation: Pick<Invitation, 'delivery' | 'maskedEmail' | 'training'>, known = true) =>
    invitationLabel(invitation, known ? offerings : [], known ? members : []);

  test('code élève : catégorie et moniteur ; e-mail : adresse masquée', () => {
    expect(label({ delivery: 'CODE', maskedEmail: null, training: { offeringId, instructorMembershipId: instructorId } })).toBe('Code élève · Permis B · Luc Martin');
    expect(label({ delivery: 'EMAIL', maskedEmail: 'p***@example.test' })).toBe('p***@example.test');
  });

  test('sans offre ou moniteur connus, le libellé reste honnête', () => {
    expect(label({ delivery: 'CODE', maskedEmail: null, training: { offeringId, instructorMembershipId: instructorId } }, false)).toBe('Code élève');
    expect(label({ delivery: 'CODE', maskedEmail: null })).toBe('Code élève');
    expect(label({ delivery: 'CODE', maskedEmail: null, training: null })).toBe('Code élève');
    expect(label({ delivery: 'EMAIL', maskedEmail: null })).toBe('Invitation');
  });

  test('message à envoyer : une ligne, avec le code et l’échéance', () => {
    const message = invitationCodeMessage('K7Q4-MX2P', '6 oct. 2026, 10:00', 'École Synthétique');
    expect(message).toContain('K7Q4-MX2P');
    expect(message).toContain('École Synthétique');
    expect(message).toContain('6 oct. 2026, 10:00');
    expect(message).not.toContain('\n');
  });
});
