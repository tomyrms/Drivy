import { describe, expect, it } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  actionLabel, clientTitle, codeStateLabel, ficheChanges, ficheDraftOf, ficheProblem, formatPlatformCode, invitationStatusLabel, isInviteeEmail, isPlatformCode,
  journalDetail, levelLabel, linkSourceLabel, notGrantedLabel, platformClientDetailResult, platformClientsResult, platformFailure, platformFailureKind,
  platformInvitationsResult, platformIssuedCodeResult, platformIssuedResult, platformJournalResult, platformMeResult, platformOperatorsResult,
  platformPendingCodeResult, platformPreviewResult, platformUnattachedResult, preparationLabel, reasonLabel, rightLabel, schoolStatusLabel, setupProgress,
  type PlatformClient, type PlatformClientDetail, type PlatformJournalEntry,
} from '../client/platform-model';
import { RequestFailure } from '../client/protocol';
import { PlatformConsolePage } from '../client/portal/platform/platform-page';
import { PlatformJoinPage } from '../client/portal/platform/platform-join-page';
import { ClientsSection } from '../client/portal/platform/clients-section';
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
  latestCode: { id, state: 'USED', expiresAt: when, createdAt: when }, commercial: { state: 'NOT_CONFIGURED', offer: null, dueDates: [] }, version: 2, createdAt: when, updatedAt: when,
};
const detail: PlatformClientDetail = {
  ...client, contactPhone: null, billing: { street: 'Rue du Lac 12', postalCode: '1800', city: 'Vevey', country: null }, internalNotes: 'Reprise de l’ancien site.',
  link: { source: 'OPENING_CODE', linkedAt: when, issuedByName: 'Camille Aubry' },
  codes: [{ id, state: 'USED', clientId: id, clientName: 'Auto-école du Léman', createdAt: when, expiresAt: when, usedAt: when, revokedAt: null, issuedByName: 'Camille Aubry',
    school: { id, ...facts } as PlatformClientDetail['codes'][number]['school'] }],
};

describe('écoles clientes : contrats du relais', () => {
  it('accepte l’annuaire paginé et la fiche, avec l’offre et les échéances seulement réservées', () => {
    expect(platformClientsResult.safeParse({ data: { items: [client], total: 140, nextCursor: 'abc' } }).success).toBe(true);
    expect(platformClientsResult.safeParse({ data: { items: [], total: 0, nextCursor: null } }).success).toBe(true);
    expect(platformClientDetailResult.safeParse({ data: detail }).success).toBe(true);
    // Un lot suivant renseignera l'offre et les échéances : l'écran les tolère sans les interpréter.
    const later = { ...client, commercial: { state: 'CONFIGURED', offer: { code: 'FUTURE' }, dueDates: [{ on: when }] } };
    expect(platformClientsResult.safeParse({ data: { items: [later], total: 1, nextCursor: null } }).success).toBe(true);
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
