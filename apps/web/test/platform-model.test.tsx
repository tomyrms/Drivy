import { describe, expect, it } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  actionLabel, adjustmentEffectLabel, adjustmentPhaseLabel, assignmentPhaseLabel, clientTitle, codeStateLabel, commercialStateLabel, consequenceLabel, effectiveInstant,
  existingUsageLabel, ficheChanges, ficheDraftOf, ficheProblem, formatPlatformCode, invitationStatusLabel, isInviteeEmail, isPlatformCode,
  journalDetail, levelLabel, linkSourceLabel, moduleLabel, modulesLabel, notGrantedLabel, offerProblem, offerStatusLabel, orderedModules,
  platformAssignmentPreviewResult, platformClientDetailResult, platformClientsResult, platformEntitlementsResult, platformFailure, platformFailureKind,
  platformInvitationsResult, platformIssuedCodeResult, platformIssuedResult, platformJournalResult, platformMeResult, platformModulesResult, platformOffersResult,
  platformOperatorsResult, platformPendingCodeResult, platformPreviewResult, platformRoutes, platformUnattachedResult, preparationLabel, reasonLabel, reasonProblem,
  rightLabel, sameModules, schoolStatusLabel, setupProgress,
  type PlatformClient, type PlatformClientDetail, type PlatformJournalEntry,
} from '../client/platform-model';
import { RequestFailure } from '../client/protocol';
import { PlatformConsolePage } from '../client/portal/platform/platform-page';
import { Accepted, PlatformJoinPage, Review } from '../client/portal/platform/platform-join-page';
import type { PlatformJoinState } from '../client/portal/platform/use-platform-join';
import { ClientsSection } from '../client/portal/platform/clients-section';
import { OffersSection } from '../client/portal/platform/offers-section';
import { RightsPanel } from '../client/portal/platform/rights-section';
import type { PlatformConsoleState } from '../client/portal/platform/use-platform-console';

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

// --- Écoles clientes et codes d'ouverture (R01-T02) ---
const facts = { name: 'Auto-école du Léman', status: 'DRAFT', contactEmail: 'ecole@example.test', contactPhone: null,
  setup: { step: 'STEP_4', stepsDone: 3, stepsTotal: 6, completedAt: null, savedAt: when } };
const client: PlatformClient = {
  id, displayName: 'Auto-école du Léman', preparation: 'IN_PREPARATION', schoolId: id, school: facts as PlatformClient['school'], contactName: 'Sophie Rochat', contactEmail: 'sophie@example.test',
  latestCode: { id, state: 'USED', expiresAt: when, createdAt: when }, commercial: { state: 'NOT_CONFIGURED', offer: null, scheduledOffer: null, entitlementVersion: 1, dueDates: [] }, version: 2, createdAt: when, updatedAt: when,
};
const detail: PlatformClientDetail = {
  ...client, contactPhone: null, billing: { street: 'Rue du Lac 12', postalCode: '1800', city: 'Vevey', country: null }, internalNotes: 'Reprise de l’ancien site.',
  link: { source: 'OPENING_CODE', linkedAt: when, issuedByName: 'Camille Aubry' },
  codes: [{ id, state: 'USED', clientId: id, clientName: 'Auto-école du Léman', createdAt: when, expiresAt: when, usedAt: when, revokedAt: null, issuedByName: 'Camille Aubry',
    school: { id, ...facts } as PlatformClientDetail['codes'][number]['school'] }],
};

describe('écoles clientes : contrats du relais', () => {
  it('accepte l’annuaire paginé et la fiche, avec l’offre en vigueur, l’offre programmée et les échéances seulement réservées', () => {
    expect(platformClientsResult.safeParse({ data: { items: [client], total: 140, nextCursor: 'abc' } }).success).toBe(true);
    expect(platformClientsResult.safeParse({ data: { items: [], total: 0, nextCursor: null } }).success).toBe(true);
    expect(platformClientDetailResult.safeParse({ data: detail }).success).toBe(true);
    const brief = { offerId: id, name: 'Offre complète', effectiveAt: when, modules: ['MESSAGING', 'COLLECTIVE_COURSES'] };
    const inForce = { ...client, commercial: { state: 'OFFER_ACTIVE', offer: brief, scheduledOffer: { ...brief, name: 'Offre à venir' }, entitlementVersion: 3, dueDates: [] } };
    expect(platformClientsResult.safeParse({ data: { items: [inForce], total: 1, nextCursor: null } }).success).toBe(true);
    // Les échéances restent un emplacement réservé : l'écran les tolère sans les interpréter (conditions commerciales, #456).
    const later = { ...client, commercial: { ...client.commercial, dueDates: [{ on: when }] } };
    expect(platformClientsResult.safeParse({ data: { items: [later], total: 1, nextCursor: null } }).success).toBe(true);
  });

  it('refuse un emplacement commercial incomplet ou à la forme inattendue', () => {
    const without = (key: string) => { const copy: Record<string, unknown> = { ...client.commercial }; delete copy[key]; return copy; };
    for (const key of ['offer', 'scheduledOffer', 'entitlementVersion', 'dueDates'])
      expect(platformClientsResult.safeParse({ data: { items: [{ ...client, commercial: without(key) }], total: 1, nextCursor: null } }).success, key).toBe(false);
    expect(platformClientsResult.safeParse({ data: { items: [{ ...client, commercial: { ...client.commercial, entitlementVersion: 0 } }], total: 1, nextCursor: null } }).success).toBe(false);
    expect(platformClientsResult.safeParse({ data: { items: [{ ...client, commercial: { ...client.commercial, offer: { code: 'FUTURE' } } }], total: 1, nextCursor: null } }).success).toBe(false);
  });

  it('refuse une réponse qui sort du contrat plutôt que de l’afficher', () => {
    expect(platformClientsResult.safeParse({ data: { items: [{ ...client, preparation: 'SUSPENDED' }], total: 1, nextCursor: null } }).success).toBe(false);
    expect(platformClientsResult.safeParse({ data: { items: [{ ...client, id: 'pas-un-identifiant' }], total: 1, nextCursor: null } }).success).toBe(false);
    expect(platformClientsResult.safeParse({ data: { items: [client], total: -1, nextCursor: null } }).success).toBe(false);
    expect(platformClientDetailResult.safeParse({ data: { ...detail, codes: [{ ...detail.codes[0], state: 'PENDING' }] } }).success).toBe(false);
    expect(platformUnattachedResult.safeParse({ data: { items: [{ id, ...facts, status: 'SUSPENDED' }] } }).success).toBe(false);
    expect(platformUnattachedResult.safeParse({ data: { items: [{ id, ...facts }] } }).success).toBe(true);
  });

  it('ne laisse apparaître le code d’ouverture que dans la réponse de création, au bon format', () => {
    const created = { data: { codeId: id, client: detail }, code: 'DEMK-X7K4', link: 'https://example.test/app/ouvrir#token=DEMK-X7K4' };
    expect(platformIssuedCodeResult.safeParse(created).success).toBe(true);
    expect(platformIssuedCodeResult.safeParse({ ...created, code: 'DEMNK-X7K42' }).success).toBe(false);
    expect(platformIssuedCodeResult.safeParse({ ...created, code: 'DEMO-X7K4' }).success).toBe(false);
    expect(platformIssuedCodeResult.safeParse({ data: created.data }).success).toBe(false);
    // L'annuaire, la fiche et la reprise d'une opération ne portent jamais de code.
    const listed = platformClientsResult.parse({ data: { items: [client], total: 1, nextCursor: null } });
    const opened = platformClientDetailResult.parse({ data: detail });
    const waiting = platformPendingCodeResult.parse({ pending: { operationId: id, displayName: 'Auto-école du Léman', validityDays: 7 } });
    for (const projection of [listed, opened, waiting]) expect(JSON.stringify(projection)).not.toMatch(/[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}/);
    expect(platformPendingCodeResult.safeParse({ pending: null }).success).toBe(true);
    expect(platformPendingCodeResult.safeParse({ pending: { operationId: id, validityDays: 90 } }).success).toBe(false);
  });
});

describe('écoles clientes : fiche', () => {
  it('ne propose une modification que pour ce qui a vraiment changé', () => {
    expect(ficheChanges(detail, ficheDraftOf(detail))).toEqual({});
    const draft = { ...ficheDraftOf(detail), contactName: '  Sophie Rochat-Martin ', contactEmail: ' SOPHIE@Example.test ', billingCountry: 'Suisse' };
    // L'adresse est comparée sans casse ni espaces : la même adresse ne repart pas.
    expect(ficheChanges(detail, draft)).toEqual({ contactName: 'Sophie Rochat-Martin', billingCountry: 'Suisse' });
  });

  it('une zone vidée part en null, et rien n’est obligatoire', () => {
    expect(ficheChanges(detail, { ...ficheDraftOf(detail), internalNotes: '   ', billingStreet: '' })).toEqual({ internalNotes: null, billingStreet: null });
    const blank = ficheDraftOf({ ...detail, displayName: null, contactName: null, contactEmail: null, internalNotes: null, billing: { street: null, postalCode: null, city: null, country: null } });
    expect(Object.values(blank).every(value => value === '')).toBe(true);
    expect(ficheProblem(blank)).toBeNull();
  });

  it('signale avant envoi une adresse invalide ou une zone trop longue, sur la bonne zone', () => {
    expect(ficheProblem({ ...ficheDraftOf(detail), contactEmail: 'pas-un-email' })).toEqual({ field: 'contactEmail', message: 'Saisissez une adresse e-mail valide.' });
    expect(ficheProblem({ ...ficheDraftOf(detail), internalNotes: 'a'.repeat(4001) })).toEqual({ field: 'internalNotes', message: 'Ce champ est limité à 4000 caractères.' });
    expect(ficheProblem({ ...ficheDraftOf(detail), contactPhone: '0'.repeat(33) })?.field).toBe('contactPhone');
    expect(ficheProblem({ ...ficheDraftOf(detail), internalNotes: 'a'.repeat(4000) })).toBeNull();
  });
});

describe('écoles clientes : libellés', () => {
  it('dit l’état de préparation, de l’école et des codes en français', () => {
    expect(preparationLabel('AWAITING_SCHOOL')).toBe('En attente de l’école');
    expect(preparationLabel('IN_PREPARATION')).toBe('En préparation');
    expect(preparationLabel('ACTIVE')).toBe('Active');
    expect(preparationLabel('ARCHIVED')).toBe('Archivée');
    expect(codeStateLabel('AVAILABLE')).toBe('Disponible');
    expect(codeStateLabel('USED')).toBe('Utilisé');
    expect(codeStateLabel('EXPIRED')).toBe('Expiré');
    expect(codeStateLabel('REVOKED')).toBe('Révoqué');
    expect(schoolStatusLabel('DRAFT')).toBe('Brouillon');
    expect(linkSourceLabel('EXISTING_SCHOOL')).toBe('École existante rattachée');
  });

  it('nomme une fiche par son nom commercial, sinon par l’école, sinon sans inventer', () => {
    expect(clientTitle(client)).toBe('Auto-école du Léman');
    expect(clientTitle({ displayName: null, school: facts as PlatformClient['school'] })).toBe('Auto-école du Léman');
    expect(clientTitle({ displayName: null, school: null })).toBe('École sans nom');
  });

  it('montre la progression enregistrée par l’école, jamais une progression inventée', () => {
    expect(setupProgress({ stepsDone: 3, stepsTotal: 6, completedAt: null })).toBe('3 sur 6 étapes');
    expect(setupProgress({ stepsDone: 6, stepsTotal: 6, completedAt: when })).toBe('Préparation terminée');
    expect(setupProgress({ stepsDone: 0, stepsTotal: 0, completedAt: null })).toBe('Préparation non commencée');
  });

  it('couvre les actions et les motifs des écoles clientes au journal', () => {
    for (const action of ['CREATE_PLATFORM_CLIENT', 'UPDATE_PLATFORM_CLIENT', 'ATTACH_EXISTING_SCHOOL', 'CREATE_SCHOOL_OPENING_CODE', 'REVOKE_SCHOOL_OPENING_CODE', 'SCHOOL_OPENED_FROM_CODE'])
      expect(actionLabel(action)).not.toBe('Action enregistrée');
    for (const reason of ['CLIENT_CODE_PENDING', 'CLIENT_SCHOOL_LINKED', 'CLIENT_SCHOOL_ALREADY_LINKED', 'OPENING_LINK_USED', 'OPENING_LINK_REVOKED', 'OPENING_LINK_EXPIRED'])
      expect(reasonLabel(reason)).not.toBeNull();
  });

  it('explique chaque refus métier des écoles clientes en français, sans afficher de code technique', () => {
    for (const code of ['CLIENT_CODE_PENDING', 'CLIENT_SCHOOL_LINKED', 'CLIENT_SCHOOL_ALREADY_LINKED', 'OPENING_LINK_USED', 'OPENING_LINK_REVOKED', 'OPENING_LINK_EXPIRED',
      'PLATFORM_CODE_IN_PROGRESS', 'NOT_FOUND', 'IDEMPOTENCY_MISMATCH']) {
      const message = platformFailure(new RequestFailure(code, 409));
      expect(message).toMatch(/[.]$/);
      expect(message).not.toContain(code);
    }
    expect(platformFailureKind(new RequestFailure('CLIENT_SCHOOL_LINKED', 409))).toBe('refused');
  });
});

describe('écoles clientes : affichage', () => {
  /** Un état minimal : seul ce que la section lit. Aucun appel réseau, aucune action. */
  const state = (clients: Record<string, unknown>) => ({ busy: false, error: null, clients: {
    page: { items: [client], total: 1, nextCursor: null }, search: '', preparation: 'ALL', selected: null, pending: null, ...clients,
  } }) as unknown as PlatformConsoleState;

  it('l’annuaire met « Créer un code » en action principale et n’affiche aucun code', () => {
    const html = renderToStaticMarkup(<ClientsSection state={state({})} />);
    expect(html).toContain('Créer un code');
    expect(html).toContain('Rattacher une école');
    expect(html).toContain('Auto-école du Léman');
    expect(html).toContain('1 sur 1 école');
    expect(html).not.toMatch(/[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}/);
    // Le contenu pédagogique n'est jamais lu ni proposé à l'opérateur.
    expect(html).not.toMatch(/élève|trajet|message|dossier/i);
  });

  it('un annuaire vide dit pourquoi, et ne propose « Afficher plus » que s’il reste des écoles', () => {
    expect(renderToStaticMarkup(<ClientsSection state={state({ page: { items: [], total: 0, nextCursor: null } })} />)).toContain('Aucune école cliente');
    expect(renderToStaticMarkup(<ClientsSection state={state({ page: { items: [], total: 0, nextCursor: null }, search: 'zzz' })} />)).toContain('Aucune école trouvée');
    expect(renderToStaticMarkup(<ClientsSection state={state({})} />)).not.toContain('Afficher plus');
    expect(renderToStaticMarkup(<ClientsSection state={state({ page: { items: [client], total: 140, nextCursor: 'abc' } })} />)).toContain('Afficher plus');
  });

  it('un code expiré ou révoqué est le seul état inhabituel signalé par un badge', () => {
    const awaiting = { ...client, preparation: 'AWAITING_SCHOOL', schoolId: null, school: null };
    const html = (code: PlatformClient['latestCode']) => renderToStaticMarkup(<ClientsSection state={state({ page: { items: [{ ...awaiting, latestCode: code }], total: 1, nextCursor: null } })} />);
    expect(html({ id, state: 'EXPIRED', expiresAt: when, createdAt: when })).toContain('Code expiré');
    expect(html({ id, state: 'REVOKED', expiresAt: when, createdAt: when })).toContain('Code révoqué');
    expect(html({ id, state: 'AVAILABLE', expiresAt: when, createdAt: when })).not.toContain('Code expiré');
    expect(html(null)).not.toContain('Code révoqué');
  });

  it('un code créé mais non confié est repris dans l’annuaire, sans le montrer', () => {
    const html = renderToStaticMarkup(<ClientsSection state={state({ pending: { operationId: id, displayName: 'Auto-école Reprise' } })} />);
    expect(html).toContain('Code non transmis');
    expect(html).toContain('Afficher le code');
    expect(html).not.toMatch(/[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}/);
  });

  it('la fiche montre l’école, son contact et sa progression, l’offre et les échéances réservées, et rien du contenu pédagogique', () => {
    const html = renderToStaticMarkup(<ClientsSection state={state({ selected: detail })} />);
    for (const expected of ['Auto-école du Léman', 'Contact de l’école', '3 sur 6 étapes', 'Ouverte avec un code', 'Offre', 'Non configurée', 'Échéances', 'Aucune', 'Codes d’ouverture', 'Adresse de facturation', 'Notes internes'])
      expect(html).toContain(expected);
    expect(html).not.toMatch(/élève|trajet|message|dossier/i);
    // Une école ouverte n'émet plus de code et ne se rattache plus.
    expect(html).not.toContain('Créer un code');
    expect(html).not.toContain('Rattacher une école');
  });

  it('la fiche d’une école pas encore ouverte propose un code, sauf si un code est déjà disponible', () => {
    const open = { ...detail, preparation: 'AWAITING_SCHOOL', schoolId: null, school: null, link: null, codes: [{ ...detail.codes[0], state: 'EXPIRED', school: null }] };
    expect(renderToStaticMarkup(<ClientsSection state={state({ selected: open })} />)).toContain('Créer un code');
    const waiting = { ...open, codes: [{ ...open.codes[0], state: 'AVAILABLE' }] };
    const html = renderToStaticMarkup(<ClientsSection state={state({ selected: waiting })} />);
    expect(html).not.toContain('Créer un code');
    expect(html).toContain('Révoquer');
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

// --- Offres et droits aux modules (R01-T03) : synthétiques, aucun montant ni état commercial détaillé (#456) ---
const moduleCodes = ['MESSAGING', 'COLLECTIVE_COURSES'];
const catalogue = [{ code: 'COLLECTIVE_COURSES', sortOrder: 2 }, { code: 'MESSAGING', sortOrder: 1 }];
const offerBrief = { offerId: id, name: 'Offre complète', effectiveAt: when, modules: moduleCodes };
const offer = { id, name: 'Offre complète', modules: moduleCodes, status: 'ACTIVE', version: 1, createdAt: when, updatedAt: when, archivedAt: null, schoolsInForce: 2 };
const revoked = { id, effect: 'REVOKE', reason: 'Demande de l’école', createdAt: when, createdByName: 'Camille Aubry' };
const entitlements = {
  state: 'OFFER_ACTIVE', offer: offerBrief, scheduledOffer: null,
  modules: [{ code: 'MESSAGING', inOffer: true, entitled: true, adjustment: null }, { code: 'COLLECTIVE_COURSES', inOffer: true, entitled: false, adjustment: revoked }],
  assignments: [{ id, offerId: id, offerName: 'Offre complète', modules: moduleCodes, effectiveAt: when, phase: 'IN_FORCE', createdAt: when, createdByName: 'Camille Aubry', cancelledAt: null }],
  adjustments: [{ id, moduleCode: 'COLLECTIVE_COURSES', effect: 'REVOKE', reason: 'Demande de l’école', createdAt: when, createdByName: 'Camille Aubry', phase: 'ACTIVE',
    liftedAt: null, liftedByName: null, liftReason: null }],
  version: 3, nextChangeAt: null,
};
const preview = {
  offer: { id, name: 'Messagerie seule', modules: ['MESSAGING'] }, effectiveAt: null, immediate: true, replacesScheduled: null, endingAdjustments: [],
  modules: [{ code: 'MESSAGING', before: true, after: true, kind: 'KEEPS', existing: null },
    { code: 'COLLECTIVE_COURSES', before: true, after: false, kind: 'LOSES', existing: { publishedSeries: 2, activeEnrollments: 1, upcomingSessions: 0 } }],
  version: 3,
};

describe('offres et droits : contrats du relais', () => {
  it('accepte le catalogue de modules, les offres et les droits d’une école', () => {
    expect(platformModulesResult.safeParse({ data: { items: catalogue } }).success).toBe(true);
    expect(platformOffersResult.safeParse({ data: { items: [offer, { ...offer, status: 'ARCHIVED', archivedAt: when, schoolsInForce: 0 }] } }).success).toBe(true);
    expect(platformEntitlementsResult.safeParse({ data: entitlements }).success).toBe(true);
    expect(platformEntitlementsResult.safeParse({ data: { ...entitlements, state: 'NOT_CONFIGURED', offer: null, assignments: [], adjustments: [],
      modules: entitlements.modules.map(item => ({ ...item, entitled: true, adjustment: null })) } }).success).toBe(true);
  });

  it('refuse ce qui sort du contrat : statut, phase, version, nombre négatif, module hors jeton', () => {
    expect(platformModulesResult.safeParse({ data: { items: [{ code: 'MESSAGING', sortOrder: 0 }] } }).success).toBe(false);
    expect(platformModulesResult.safeParse({ data: { items: [{ code: 'messagerie', sortOrder: 1 }] } }).success).toBe(false);
    expect(platformOffersResult.safeParse({ data: { items: [{ ...offer, status: 'DELETED' }] } }).success).toBe(false);
    expect(platformOffersResult.safeParse({ data: { items: [{ ...offer, schoolsInForce: -1 }] } }).success).toBe(false);
    expect(platformOffersResult.safeParse({ data: { items: [{ ...offer, version: 0 }] } }).success).toBe(false);
    expect(platformEntitlementsResult.safeParse({ data: { ...entitlements, version: 0 } }).success).toBe(false);
    expect(platformEntitlementsResult.safeParse({ data: { ...entitlements, assignments: [{ ...entitlements.assignments[0], phase: 'DELETED' }] } }).success).toBe(false);
    expect(platformEntitlementsResult.safeParse({ data: { ...entitlements, adjustments: [{ ...entitlements.adjustments[0], effect: 'DELETE' }] } }).success).toBe(false);
    expect(platformEntitlementsResult.safeParse({ data: { ...entitlements, offer: { ...offerBrief, offerId: 'pas-un-identifiant' } } }).success).toBe(false);
  });

  it('l’aperçu des conséquences ne porte que des volumes, jamais un contenu', () => {
    expect(platformAssignmentPreviewResult.safeParse({ data: preview }).success).toBe(true);
    expect(platformAssignmentPreviewResult.safeParse({ data: { ...preview, version: 0 } }).success).toBe(false);
    expect(platformAssignmentPreviewResult.safeParse({ data: { ...preview, modules: [{ ...preview.modules[0], kind: 'DELETES' }] } }).success).toBe(false);
    expect(platformAssignmentPreviewResult.safeParse({ data: { ...preview, modules: [{ ...preview.modules[1], existing: { publishedSeries: 'beaucoup' } }] } }).success).toBe(false);
    expect(platformAssignmentPreviewResult.safeParse({ data: { ...preview, modules: [{ ...preview.modules[1], existing: { publishedSeries: -1 } }] } }).success).toBe(false);
  });
});

describe('offres et droits : saisie et libellés', () => {
  it('nomme les modules, les états et les phases en français', () => {
    expect(moduleLabel('MESSAGING')).toBe('Messagerie');
    expect(moduleLabel('COLLECTIVE_COURSES')).toBe('Cours collectifs');
    expect(moduleLabel('QUELQUE_CHOSE_DE_NOUVEAU')).toBe('Module');
    expect(modulesLabel(moduleCodes)).toBe('Messagerie, Cours collectifs');
    expect(modulesLabel([])).toBe('Aucun module');
    expect(commercialStateLabel('NOT_CONFIGURED')).toBe('Non configurée');
    expect(commercialStateLabel('OFFER_ACTIVE')).toBe('Offre en vigueur');
    expect(commercialStateLabel('ETAT_FUTUR')).toBe('État commercial');
    expect(offerStatusLabel('ARCHIVED')).toBe('Archivée');
    expect(consequenceLabel('LOSES')).toBe('Retiré');
    expect(adjustmentEffectLabel('GRANT')).toBe('Accordé en plus');
    expect(assignmentPhaseLabel('SCHEDULED')).toBe('Prévue');
    expect(adjustmentPhaseLabel('LIFTED')).toBe('Levé');
  });

  it('couvre les droits, les actions et les motifs des offres au journal', () => {
    expect(rightLabel('MANAGE_OFFERS')).not.toBe('Droit commercial');
    for (const action of ['CREATE_OFFER', 'UPDATE_OFFER', 'ARCHIVE_OFFER', 'RESTORE_OFFER', 'ASSIGN_OFFER', 'CANCEL_OFFER_ASSIGNMENT', 'ADJUST_SCHOOL_MODULE', 'LIFT_MODULE_ADJUSTMENT'])
      expect(actionLabel(action), action).not.toBe('Action enregistrée');
    for (const reason of ['OFFER_ARCHIVED', 'MODULE_NOT_ENTITLED']) expect(reasonLabel(reason), reason).not.toBeNull();
  });

  it('explique chaque refus métier des offres en français, sans afficher de code technique', () => {
    for (const code of ['OFFER_ARCHIVED', 'OFFER_NOT_ARCHIVED', 'EFFECTIVE_DATE_PAST', 'ASSIGNMENT_NOT_PENDING', 'ADJUSTMENT_REQUIRES_OFFER', 'ADJUSTMENT_ACTIVE',
      'ADJUSTMENT_NO_EFFECT', 'ADJUSTMENT_NOT_ACTIVE', 'MODULE_UNKNOWN']) {
      const message = platformFailure(new RequestFailure(code, 409));
      expect(message, code).toMatch(/[.]$/);
      expect(message, code).not.toContain(code);
    }
    expect(platformFailureKind(new RequestFailure('VERSION_CONFLICT', 412))).toBe('conflict');
    expect(platformFailureKind(new RequestFailure('OFFER_ARCHIVED', 409))).toBe('refused');
  });

  it('refuse une offre sans nom, trop longue ou avec un module en double', () => {
    expect(offerProblem('', moduleCodes)).not.toBeNull();
    expect(offerProblem('   ', moduleCodes)).not.toBeNull();
    expect(offerProblem('x'.repeat(101), moduleCodes)).not.toBeNull();
    expect(offerProblem('Offre', ['MESSAGING', 'MESSAGING'])).not.toBeNull();
    expect(offerProblem('x'.repeat(100), moduleCodes)).toBeNull();
    expect(offerProblem('  Offre complète  ', moduleCodes)).toBeNull();
  });

  it('exige un motif lisible pour ajuster un module, avec les mêmes bornes que l’API', () => {
    expect(reasonProblem('')).not.toBeNull();
    expect(reasonProblem('  ab  ')).not.toBeNull();
    expect(reasonProblem('abc')).toBeNull();
    expect(reasonProblem('x'.repeat(500))).toBeNull();
    expect(reasonProblem('x'.repeat(501))).not.toBeNull();
  });

  it('ne transmet une date d’effet que si elle est à venir et lisible, sinon l’attribution est immédiate ou à corriger', () => {
    const now = new Date('2026-11-14T10:00:00.000Z');
    expect(effectiveInstant('', now)).toBeNull();
    expect(effectiveInstant('   ', now)).toBeNull();
    expect(effectiveInstant('pas une date', now)).toBeUndefined();
    expect(effectiveInstant('2026-11-01T10:00', now)).toBeUndefined();
    const future = effectiveInstant('2026-12-01T10:00', now);
    expect(future).toBe(new Date('2026-12-01T10:00').toISOString());
    expect(future).toMatch(/Z$/);
  });

  it('range les modules d’une offre dans l’ordre du catalogue, sans doublon ni module inconnu', () => {
    expect(orderedModules(['COLLECTIVE_COURSES', 'MESSAGING', 'MESSAGING', 'INCONNU'], catalogue)).toEqual(['MESSAGING', 'COLLECTIVE_COURSES']);
    expect(orderedModules([], catalogue)).toEqual([]);
    expect(sameModules(['MESSAGING', 'COLLECTIVE_COURSES'], ['COLLECTIVE_COURSES', 'MESSAGING'])).toBe(true);
    expect(sameModules(['MESSAGING'], ['MESSAGING', 'COLLECTIVE_COURSES'])).toBe(false);
    expect(sameModules(['MESSAGING'], ['COLLECTIVE_COURSES'])).toBe(false);
  });

  it('résume ce qu’un retrait laisse en place, en volumes seulement', () => {
    expect(existingUsageLabel(null)).toBe('');
    expect(existingUsageLabel({ conversations: 0 })).toBe('');
    expect(existingUsageLabel({ inconnu: 5 })).toBe('');
    expect(existingUsageLabel({ conversations: 1 })).toBe('1 conversation');
    expect(existingUsageLabel({ conversations: 3, publishedSeries: 2 })).toBe('3 conversations · 2 séries publiées');
    expect(existingUsageLabel({ publishedSeries: 1, activeEnrollments: 1, upcomingSessions: 4 })).toBe('1 série publiée · 1 inscription active · 4 séances à venir');
  });
});

describe('offres et droits : affichage', () => {
  const offersState = (items: unknown[]) => ({ busy: false, error: null, offers: { offers: items, modules: catalogue, editor: null, startOffer: () => {}, stopOffer: () => {},
    archiveOffer: async () => {}, restoreOffer: async () => {}, saveOffer: async () => {} } }) as unknown as PlatformConsoleState;
  const rightsState = (data: unknown) => ({ busy: false, error: null, rights: { rights: data, dialog: null, preview: null, stop: () => {}, startAssign: () => {}, startAdjust: () => {},
    startLift: () => {}, startCancel: () => {} } }) as unknown as PlatformConsoleState;

  it('les offres actives sont listées avec leurs modules, et seulement ce qui est possible : modifier ou archiver', () => {
    const html = renderToStaticMarkup(<OffersSection state={offersState([offer, { ...offer, id: '6c6f1c3f-8a66-4d63-8d54-4b3b7d1e9f22', name: 'Ancienne offre', status: 'ARCHIVED', archivedAt: when, schoolsInForce: 0 }])} />);
    for (const expected of ['Créer une offre', 'Offre complète', 'Messagerie, Cours collectifs', '2 écoles', 'Modifier', 'Archiver', 'Actives', 'Archivées'])
      expect(html).toContain(expected);
    expect(html).not.toContain('Ancienne offre');
    expect(html).not.toContain('Rétablir');
    expect(html).not.toMatch(/CHF|€|prix|tarif|essai|échéance/i);
  });

  it('sans offre active, l’écran le dit simplement', () => {
    expect(renderToStaticMarkup(<OffersSection state={offersState([])} />)).toContain('Aucune offre active');
  });

  it('la fiche montre l’offre en vigueur, chaque module avec son ajustement, et propose de lever ou de retirer', () => {
    const html = renderToStaticMarkup(<RightsPanel state={rightsState(entitlements)} client={detail} />);
    for (const expected of ['Offre et modules', 'Attribuer une offre', 'Offre complète', 'Messagerie', 'Cours collectifs', 'Accordé', 'Non accordé', 'Retiré', 'Demande de l’école', 'Lever', 'Retirer', 'Historique'])
      expect(html).toContain(expected);
    // Aucun contenu pédagogique, aucun montant : l'écran ne montre que des droits.
    expect(html).not.toMatch(/élève|trajet|message[^r]|dossier|CHF|€|prix|tarif|essai/i);
  });

  it('une école sans offre garde tous les modules et ne propose aucun ajustement', () => {
    const open = { ...entitlements, state: 'NOT_CONFIGURED', offer: null, assignments: [], adjustments: [], modules: entitlements.modules.map(item => ({ ...item, entitled: true, adjustment: null })) };
    const html = renderToStaticMarkup(<RightsPanel state={rightsState(open)} client={detail} />);
    expect(html).toContain('Non configurée');
    expect(html).toContain('Attribuer une offre');
    expect(html).not.toContain('Retirer');
    expect(html).not.toContain('Accorder');
    expect(html).not.toContain('Lever');
    expect(html).not.toContain('Historique');
  });

  it('une offre programmée se voit et s’annule, sans remplacer l’offre en vigueur', () => {
    const scheduledOffer = { ...offerBrief, name: 'Offre à venir', effectiveAt: '2027-01-15T08:00:00.000Z' };
    const withSchedule = { ...entitlements, scheduledOffer, assignments: [{ ...entitlements.assignments[0], id: '6c6f1c3f-8a66-4d63-8d54-4b3b7d1e9f22', offerName: 'Offre à venir',
      effectiveAt: scheduledOffer.effectiveAt, phase: 'SCHEDULED' }, ...entitlements.assignments] };
    const html = renderToStaticMarkup(<RightsPanel state={rightsState(withSchedule)} client={detail} />);
    expect(html).toContain('Offre programmée');
    expect(html).toContain('Offre à venir');
    expect(html).toContain('Annuler l’attribution prévue de Offre à venir');
    expect(html).toContain('Offre complète');
  });

  it('tant que les droits ne sont pas lus, la fiche n’invente rien', () => {
    expect(renderToStaticMarkup(<RightsPanel state={rightsState(null)} client={detail} />)).toBe('');
  });
});
