import { describe, expect, it } from 'vitest';
import { RequestFailure, type InvitationPreview, type Session } from '../../protocol';
import {
  acceptanceFailure, accountCreationFailure, accountEntryDestination, canAcceptInvitation, codeFromInput,
  initialEntryStep, invitationNeedsVerifiedEmail, recoveryStartFailure,
} from './entry-model';

const session: Session = { authenticated: true, csrfToken: 'synthetic-csrf', invitationPending: true, user: { displayName: 'Compte fictif', emailVerified: true } };
const invitation: InvitationPreview = {
  invitationId: '10000000-0000-4000-8000-000000000001', schoolId: '10000000-0000-4000-8000-000000000002', schoolName: 'École fictive',
  roles: ['LEARNER'], delivery: 'EMAIL', maskedEmail: 'f***@example.test', expiresAt: '2027-01-01T12:00:00Z',
  notice: { version: 1, noticeText: 'Information fictive', retentionText: 'Durée fictive', contactEmail: 'ecole@example.test' },
};

describe('entrée reconstruite — intentions et refus', () => {
  it('ne crée aucun parcours d’inscription publique sans code ni invitation', () => {
    expect(initialEntryStep({})).toBe('login');
    expect(initialEntryStep({ signedIn: true, invitation: true })).toBe('code');
    expect(initialEntryStep({ invitation: true })).toBe('register');
    expect(initialEntryStep({ initialCode: 'DEMO-DEMO' })).toBe('register');
  });

  it('garde la destination reconnue par le serveur après connexion', () => {
    expect(accountEntryDestination('SCHOOL_OPENING')).toBe('/app/ouvrir');
    expect(accountEntryDestination('LEARNER_INVITATION')).toBe('/app/invitation');
    expect(accountEntryDestination('EMAIL_INVITATION')).toBe('/app/invitation');
    expect(accountEntryDestination(null)).toBeNull();
    expect(codeFromInput(' https://example.test/app/ouvrir#token=synthetic_token ')).toBe('synthetic_token');
  });

  it('exige session authentifiée, confirmation et adresse vérifiée pour une invitation e-mail', () => {
    expect(canAcceptInvitation(invitation, session, true)).toBe(true);
    expect(canAcceptInvitation(invitation, session, false)).toBe(false);
    expect(canAcceptInvitation(invitation, { ...session, authenticated: false }, true)).toBe(false);
    expect(canAcceptInvitation(invitation, { ...session, user: { displayName: 'Compte fictif', emailVerified: false } }, true)).toBe(false);
    expect(canAcceptInvitation(invitation, null, true)).toBe(false);
  });

  it('conserve le parcours par code sans inventer une vérification e-mail', () => {
    const unverified = { ...session, user: { displayName: 'Compte fictif', emailVerified: false } };
    expect(invitationNeedsVerifiedEmail(invitation, unverified)).toBe(true);
    expect(canAcceptInvitation({ ...invitation, delivery: 'CODE' }, unverified, true)).toBe(true);
  });

  it.each(['INVITATION_PREVIEW_CHANGED', 'INVITATION_REVOKED', 'INVITATION_EXPIRED', 'INVITATION_IDENTITY_MISMATCH'])(
    'retire le détail devenu invalide après %s', code => {
      expect(acceptanceFailure(new RequestFailure(code, 409))).toEqual({ dropPreview: true, uncertain: false });
    },
  );

  it.each([['NETWORK_UNAVAILABLE', 0], ['UPSTREAM_UNAVAILABLE', 503], ['INVITATION_IN_PROGRESS', 409], ['INVITATION_RESULT_UNKNOWN', 409], ['SESSION_LOST_RESULT_UNKNOWN', 401]] as const)(
    'conserve la même intention lorsque le résultat reste inconnu : %s', (code, status) => {
      expect(acceptanceFailure(new RequestFailure(code, status))).toEqual({ dropPreview: false, uncertain: true });
    },
  );

  it('distingue une autre adresse du refus de code classique', () => {
    const failure = new RequestFailure('ACCESS_CODE_INVALID', 404);
    expect(accountCreationFailure('EMAIL_INVITATION', failure)).toMatchObject({ code: 'EMAIL_INVITATION_MISMATCH' });
    expect(accountCreationFailure('LEARNER_INVITATION', failure)).toBe(failure);
  });

  it('ne présente pas un service de récupération indisponible comme ouvert', () => {
    expect(recoveryStartFailure(new RequestFailure('ACCOUNT_RECOVERY_UNAVAILABLE', 503))).toBe('unavailable');
    expect(recoveryStartFailure(new RequestFailure('NETWORK_UNAVAILABLE'))).toBe('error');
  });
});
