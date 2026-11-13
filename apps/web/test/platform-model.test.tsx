import { describe, expect, it } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  actionLabel, formatPlatformCode, invitationStatusLabel, isInviteeEmail, isPlatformCode, journalDetail, levelLabel, notGrantedLabel,
  platformFailure, platformFailureKind, platformInvitationsResult, platformIssuedResult, platformJournalResult, platformMeResult, platformOperatorsResult,
  platformPreviewResult, platformRoutes, reasonLabel, rightLabel, type PlatformJournalEntry,
} from '../client/platform-model';
import { RequestFailure } from '../client/protocol';
import { PlatformConsolePage } from '../client/portal/platform/platform-page';
import { Accepted, PlatformJoinPage, Review } from '../client/portal/platform/platform-join-page';
import type { PlatformJoinState } from '../client/portal/platform/use-platform-join';

const id = '5b5f0b2e-7f55-4c52-9c43-3a2a6c0d8e11';
const when = '2026-11-13T09:30:00.000Z';
const operator = { id, displayName: 'Camille Aubry', maskedEmail: 'c***@example.test', level: 'COMMERCIAL', status: 'ACTIVE', addedVia: 'BOOTSTRAP', joinedAt: when, revokedAt: null, version: 1, self: true };
const invitation = { id, status: 'AVAILABLE', level: 'COMMERCIAL', maskedEmail: 'n***@example.test', createdAt: when, expiresAt: when, version: 1, usedAt: null, revokedAt: null, createdByName: 'Camille Aubry' };
const rights = { level: 'COMMERCIAL', rights: ['MANAGE_PLATFORM_TEAM'], notGranted: ['SCHOOL_RECORDS', 'TRIPS'] };
const entry = (overrides: Partial<PlatformJournalEntry> = {}): PlatformJournalEntry => ({
  id, occurredAt: when, actorKind: 'OPERATOR', actorName: 'Camille Aubry', action: 'CREATE_PLATFORM_INVITATION', result: 'SUCCESS', reasonCode: null,
  schoolId: null, subject: null, operationId: null, changes: {}, ...overrides,
});

describe('code d’accès à la plateforme : saisie', () => {
  it('met en majuscules, retire les séparateurs étrangers et ajoute le tiret', () => {
    expect(formatPlatformCode('abcde')).toBe('ABCDE');
    expect(formatPlatformCode('abcdef')).toBe('ABCDE-F');
    expect(formatPlatformCode(' abc de-fgh jk ')).toBe('ABCDE-FGHJK');
    expect(formatPlatformCode('abcde fghjk lmnpq')).toBe('ABCDE-FGHJK');
    expect(formatPlatformCode('é!?')).toBe('');
  });

  it('n’accepte que l’alphabet sans O, 0, I et 1', () => {
    expect(isPlatformCode('ABCDE-FGH23')).toBe(true);
    expect(isPlatformCode('ABCDE-FGHJ')).toBe(false);
    expect(isPlatformCode('ABCDEFGHJK')).toBe(false);
    expect(isPlatformCode('ABCDO-FGH23')).toBe(false);
    expect(isPlatformCode('ABCD0-FGH23')).toBe(false);
    expect(isPlatformCode('ABCDI-FGH23')).toBe(false);
    expect(isPlatformCode('ABCD1-FGH23')).toBe(false);
    expect(isPlatformCode('abcde-fgh23')).toBe(false);
  });

  it('reconnaît une adresse plausible et refuse le reste', () => {
    expect(isInviteeEmail('nina@example.test')).toBe(true);
    expect(isInviteeEmail('nina@example')).toBe(false);
    expect(isInviteeEmail('nina example@x.test')).toBe(false);
    expect(isInviteeEmail(`${'a'.repeat(250)}@x.test`)).toBe(false);
  });
});

describe('contrats du relais', () => {
  it('accepte les réponses de l’équipe, des invitations et du journal', () => {
    expect(platformMeResult.safeParse({ data: { operator, ...rights } }).success).toBe(true);
    expect(platformOperatorsResult.safeParse({ data: { items: [operator] } }).success).toBe(true);
    expect(platformInvitationsResult.safeParse({ data: { items: [invitation] } }).success).toBe(true);
    expect(platformJournalResult.safeParse({ data: { items: [entry()], nextCursor: null } }).success).toBe(true);
  });

  it('refuse une réponse qui sort du contrat plutôt que de l’afficher', () => {
    expect(platformOperatorsResult.safeParse({ data: { items: [{ ...operator, status: 'SUSPENDED' }] } }).success).toBe(false);
    expect(platformOperatorsResult.safeParse({ data: { items: [{ ...operator, id: 'pas-un-identifiant' }] } }).success).toBe(false);
    expect(platformJournalResult.safeParse({ data: { items: [entry({ result: 'PARTIAL' as 'SUCCESS' })], nextCursor: null } }).success).toBe(false);
  });

  it('ne laisse apparaître le code que dans la réponse de création, et seulement s’il est bien formé', () => {
    expect(platformIssuedResult.safeParse({ data: invitation, code: 'DEMNK-X7K42' }).success).toBe(true);
    expect(platformIssuedResult.safeParse({ data: invitation, code: 'DEMON-X7K42' }).success).toBe(false);
    expect(platformIssuedResult.safeParse({ data: invitation }).success).toBe(false);
    // La liste des invitations ne porte jamais de code : de quoi reprendre l’opération, rien de plus.
    const listed = platformInvitationsResult.parse({ data: { items: [invitation] }, pending: { operationId: id, email: 'nina@example.test', validityDays: 7 } });
    expect(JSON.stringify(listed)).not.toMatch(/[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}/);
  });

  it('exige l’aperçu complet avant toute acceptation : droits, adresse masquée, expiration et confirmation liée', () => {
    const data = { status: 'AVAILABLE', maskedEmail: 'n***@example.test', expiresAt: when, matchesAccount: true, alreadyMember: false, ...rights };
    expect(platformPreviewResult.safeParse({ confirmation: 'c', data }).success).toBe(true);
    expect(platformPreviewResult.safeParse({ data }).success).toBe(false);
    expect(platformPreviewResult.safeParse({ confirmation: 'c', data: { ...data, status: 'USED' } }).success).toBe(false);
  });
});

describe('libellés', () => {
  it('nomme les droits accordés et les accès jamais accordés, sans exposer un identifiant technique', () => {
    expect(levelLabel('COMMERCIAL')).toBe('Commercial');
    expect(rightLabel('MANAGE_PLATFORM_TEAM')).toBe('Gérer l’équipe de la plateforme');
    expect(rightLabel('QUELQUE_CHOSE_DE_NOUVEAU')).toBe('Droit commercial');
    expect(notGrantedLabel('SCHOOL_RECORDS')).toBe('Dossiers des élèves');
    expect(notGrantedLabel('QUELQUE_CHOSE_DE_NOUVEAU')).toBe('Accès scolaire');
    expect(invitationStatusLabel('EXPIRED')).toBe('Expirée');
  });

  it('couvre chaque action et chaque motif que le journal peut porter aujourd’hui', () => {
    for (const action of ['CREATE_PLATFORM_INVITATION', 'REVOKE_PLATFORM_INVITATION', 'REVOKE_PLATFORM_OPERATOR', 'ACCEPT_PLATFORM_INVITATION', 'BOOTSTRAP_PLATFORM_OPERATOR']) {
      expect(actionLabel(action)).not.toBe('Action enregistrée');
    }
    expect(actionLabel('ACTION_DES_LOTS_SUIVANTS')).toBe('Action enregistrée');
    expect(reasonLabel('LAST_PLATFORM_OPERATOR')).toBe('Dernier opérateur actif');
    expect(reasonLabel(null)).toBeNull();
    expect(reasonLabel('MOTIF_INCONNU')).toBeNull();
  });

  it('résume la modification utile d’une ligne du journal, ou rien', () => {
    const format = (value: string) => `le ${value.slice(0, 10)}`;
    expect(journalDetail(entry(), format)).toBeNull();
    expect(journalDetail(entry({ changes: { maskedEmail: 'n***@example.test', expiresAt: when } }), format)).toBe('n***@example.test · valable jusqu’au le 2026-11-13');
    expect(journalDetail(entry({ changes: { self: true } }), format)).toBe('retrait volontaire');
    expect(journalDetail(entry({ changes: { expiresAt: 'pas une date' } }), format)).toBeNull();
    // Le retrait d'un opérateur révoque ses invitations en attente : le journal dit combien, et ne dit rien quand il n'y en avait aucune.
    expect(journalDetail(entry({ changes: { self: false, revokedInvitations: 0 } }), format)).toBeNull();
    expect(journalDetail(entry({ changes: { self: false, revokedInvitations: 1 } }), format)).toBe('1 invitation révoquée');
    expect(journalDetail(entry({ changes: { self: true, revokedInvitations: 2 } }), format)).toBe('retrait volontaire · 2 invitations révoquées');
    expect(journalDetail(entry({ changes: { revokedInvitations: 'beaucoup' } }), format)).toBeNull();
  });
});

describe('erreurs : ce que l’écran en fait', () => {
  const failure = (code: string, status: number) => new RequestFailure(code, status);

  it('ferme l’accès dès que le serveur ne reconnaît plus l’opérateur', () => {
    expect(platformFailureKind(failure('PLATFORM_OPERATOR_REQUIRED', 403))).toBe('denied');
    expect(platformFailureKind(failure('FORBIDDEN', 403))).toBe('refused');
  });

  it('traite un conflit de version comme un rechargement, jamais comme un écrasement', () => {
    expect(platformFailureKind(failure('VERSION_CONFLICT', 412))).toBe('conflict');
    expect(platformFailureKind(failure('PRECONDITION_FAILED', 412))).toBe('conflict');
  });

  it('distingue une session expirée, un refus net et une réponse perdue', () => {
    expect(platformFailureKind(failure('SESSION_EXPIRED', 401))).toBe('expired');
    expect(platformFailureKind(failure('LAST_PLATFORM_OPERATOR', 409))).toBe('refused');
    expect(platformFailureKind(failure('NETWORK_UNAVAILABLE', 0))).toBe('unconfirmed');
    expect(platformFailureKind(failure('INTERNAL', 503))).toBe('unconfirmed');
    expect(platformFailureKind(failure('INVALID_RESPONSE', 200))).toBe('unconfirmed');
    expect(platformFailureKind(new TypeError('Synthetic'))).toBe('unconfirmed');
  });

  it('explique chaque refus métier en français, sans afficher de code technique', () => {
    for (const code of ['LAST_PLATFORM_OPERATOR', 'PLATFORM_INVITATION_USED', 'PLATFORM_INVITATION_REVOKED', 'PLATFORM_INVITATION_EXPIRED', 'PLATFORM_OPERATOR_EXISTS',
      'PLATFORM_ALREADY_MEMBER', 'PLATFORM_INVITE_IN_PROGRESS', 'PLATFORM_PREVIEW_CHANGED', 'PLATFORM_IDENTITY_CHANGED', 'VERSION_CONFLICT']) {
      const message = platformFailure(failure(code, 409));
      expect(message).toMatch(/[.]$/);
      expect(message).not.toContain(code);
    }
    expect(platformFailure(failure('INCONNU', 403))).toBe('Cette action n’est pas disponible avec vos accès actuels.');
    expect(platformFailure(failure('INCONNU', 429))).toMatch(/Patientez/);
    expect(platformFailure(new Error('x'))).toBe('La demande n’a pas pu être confirmée. Réessayez.');
  });
});

describe('premier affichage (aucune réponse du serveur encore reçue)', () => {
  it('la console n’affiche ni équipe, ni invitation, ni journal avant la preuve du serveur', () => {
    const html = renderToStaticMarkup(<PlatformConsolePage />);
    expect(html).toContain('aria-busy="true"');
    expect(html).toContain('role="status"');
    for (const word of ['Retirer', 'Inviter', 'Révoquer', 'Journal', 'Camille']) expect(html).not.toContain(word);
  });

  it('la page d’acceptation ne montre ni droits ni bouton d’acceptation avant l’aperçu', () => {
    const html = renderToStaticMarkup(<PlatformJoinPage />);
    expect(html).toContain('aria-busy="true"');
    expect(html).not.toContain('Accepter et rejoindre');
    expect(html).not.toContain('Droits accordés');
    expect(html).not.toContain('Voir les droits');
  });
});

describe('liens de la console et de l’acceptation', () => {
  // Un Button Base UI rendu en <a> reçoit role="button" : les lecteurs d’écran annonceraient un bouton. Ce sont de vrais liens, stylés comme les boutons du portail.
  const link = (html: string, label: string) => html.match(new RegExp(`<a [^>]*>${label}</a>`))?.[0] ?? '';

  it('« Ouvrir la console » après acceptation est un lien natif vers la console, sans rôle de bouton', () => {
    const html = renderToStaticMarkup(<Accepted result={{ operator: { ...operator, self: true }, ...rights } as never} platform={platformRoutes} />);
    const anchor = link(html, 'Ouvrir la console');
    expect(anchor).toContain(`href="${platformRoutes.console}"`);
    expect(anchor).toContain('ui-button');
    expect(anchor).not.toContain('role=');
    expect(html).not.toContain('<button');
  });

  it('« Ouvrir la console » d’un compte déjà dans l’équipe est un lien natif, sans rôle de bouton', () => {
    const data = { status: 'AVAILABLE', maskedEmail: 'n***@example.test', expiresAt: when, matchesAccount: true, alreadyMember: true, ...rights };
    const html = renderToStaticMarkup(<Review state={{ busy: false } as PlatformJoinState} preview={{ confirmation: 'c', data } as never} platform={platformRoutes} />);
    const anchor = link(html, 'Ouvrir la console');
    expect(anchor).toContain(`href="${platformRoutes.console}"`);
    expect(anchor).toContain('ui-button-outline');
    expect(anchor).not.toContain('role=');
  });
});
