import { z } from 'zod';
import { errorMessage, RequestFailure } from './protocol';

/**
 * Console des opérateurs de la plateforme (R01-T01). Ces schémas décrivent ce que le relais /app/bff/platform/* renvoie ;
 * ils sont volontairement stricts sur les formes et tolérants sur les valeurs que les lots suivants ajouteront.
 */
const id = z.string().uuid();
const iso = z.string().datetime({ offset: true });
const token = z.string().regex(/^[A-Z][A-Z0-9_]{2,63}$/);

export const platformOperatorSchema = z.object({
  id, displayName: z.string().max(200), maskedEmail: z.string().max(254).nullable(), level: token,
  status: z.enum(['ACTIVE', 'REVOKED']), addedVia: z.enum(['BOOTSTRAP', 'INVITATION']), joinedAt: iso, revokedAt: iso.nullable(),
  version: z.number().int().positive(), self: z.boolean(),
});
export const platformInvitationSchema = z.object({
  id, status: z.enum(['AVAILABLE', 'USED', 'REVOKED', 'EXPIRED']), level: token, maskedEmail: z.string().max(254),
  createdAt: iso, expiresAt: iso, version: z.number().int().positive(), usedAt: iso.nullable(), revokedAt: iso.nullable(), createdByName: z.string().max(200).nullable(),
});
export const platformJournalSchema = z.object({
  id, occurredAt: iso, actorKind: z.enum(['OPERATOR', 'SYSTEM']), actorName: z.string().max(200), action: token,
  result: z.enum(['SUCCESS', 'REFUSED']), reasonCode: token.nullable(), schoolId: id.nullable(),
  subject: z.object({ type: z.string().max(80), id: z.string().max(80) }).nullable(), operationId: id.nullable(), changes: z.record(z.string(), z.unknown()),
});
const rights = { level: token, rights: z.array(token).max(40), notGranted: z.array(token).max(40) };

export const platformMeResult = z.object({ data: z.object({ operator: platformOperatorSchema, ...rights }) });
export const platformOperatorsResult = z.object({ data: z.object({ items: z.array(platformOperatorSchema).max(200) }) });
export const platformOperatorResult = z.object({ data: platformOperatorSchema });
export const platformInvitationsResult = z.object({
  data: z.object({ items: z.array(platformInvitationSchema).max(100) }),
  /** Une invitation créée dont le code n'a pas été confié : de quoi la reprendre, jamais le code. */
  pending: z.object({ operationId: id, email: z.string().max(254), validityDays: z.number().int().min(1).max(14).optional() }).optional(),
});
export const platformIssuedResult = z.object({ data: platformInvitationSchema, code: z.string().regex(/^[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}$/) });
export const platformInvitationResult = z.object({ data: platformInvitationSchema });
export const platformJournalResult = z.object({ data: z.object({ items: z.array(platformJournalSchema).max(100), nextCursor: z.string().max(6000).nullable() }) });
export const platformPreviewResult = z.object({
  confirmation: z.string().min(1).max(100),
  data: z.object({ status: z.literal('AVAILABLE'), maskedEmail: z.string().max(254), expiresAt: iso, matchesAccount: z.boolean(), alreadyMember: z.boolean(), ...rights }),
});
export const platformAcceptedResult = z.object({ data: z.object({ operator: platformOperatorSchema, ...rights }) });
export const platformJoinStatus = z.object({ pending: z.boolean(), uncertain: z.boolean(), accepted: z.boolean() });

// --- Écoles clientes et codes d'ouverture (R01-T02) ---
// Mêmes formes que le relais : l'offre et les échéances sont des emplacements que les lots suivants rempliront, d'où leur souplesse.
export const clientPreparations = ['AWAITING_SCHOOL', 'IN_PREPARATION', 'ACTIVE', 'ARCHIVED'] as const;
export const clientCodeStates = ['AVAILABLE', 'USED', 'EXPIRED', 'REVOKED'] as const;
export const platformOpeningCodePattern = /^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/;
const schoolSetupSchema = z.object({ step: z.string().max(80).nullable(), stepsDone: z.number().int().min(0).max(100), stepsTotal: z.number().int().min(0).max(100),
  completedAt: iso.nullable(), savedAt: iso.nullable() });
const schoolFactsSchema = z.object({ name: z.string().max(200), status: z.enum(['DRAFT', 'ACTIVE', 'ARCHIVED']), contactEmail: z.string().max(254),
  contactPhone: z.string().max(32).nullable(), setup: schoolSetupSchema });
export const platformClientCodeSchema = z.object({
  id, state: z.enum(clientCodeStates), clientId: id.nullable(), clientName: z.string().max(150).nullable(), createdAt: iso, expiresAt: iso,
  usedAt: iso.nullable(), revokedAt: iso.nullable(), issuedByName: z.string().max(200).nullable(), school: schoolFactsSchema.extend({ id }).nullable(),
});
// --- Offres et droits aux modules (R01-T03) : codes de modules en jetons (le catalogue vit côté API), petits vocabulaires fermés stricts. ---
export const adjustmentEffects = ['GRANT', 'REVOKE'] as const;
export const consequenceKinds = ['GAINS', 'LOSES', 'KEEPS', 'STAYS_OFF'] as const;
export const platformOfferStatuses = ['ACTIVE', 'ARCHIVED'] as const;
const moduleToken = token;
export const platformOfferBriefSchema = z.object({ offerId: id, name: z.string().max(100), effectiveAt: iso, modules: z.array(moduleToken).max(20) });
/** L'emplacement commercial : état dérivé, offre en vigueur, offre programmée. `dueDates` reste l'emplacement réservé aux échéances (#456). */
export const platformCommercialSchema = z.object({
  state: token, offer: platformOfferBriefSchema.nullable(), scheduledOffer: platformOfferBriefSchema.nullable(),
  entitlementVersion: z.number().int().min(1), dueDates: z.array(z.unknown()).max(50),
});
export const platformOfferSchema = z.object({
  id, name: z.string().max(100), modules: z.array(moduleToken).max(20), status: z.enum(platformOfferStatuses), version: z.number().int().min(1),
  createdAt: iso, updatedAt: iso, archivedAt: iso.nullable(), schoolsInForce: z.number().int().min(0),
});
export const platformModuleSchema = z.object({ code: moduleToken, sortOrder: z.number().int().min(1) });
const adjustmentDetailSchema = z.object({ id, effect: z.enum(adjustmentEffects), reason: z.string().max(500), createdAt: iso, createdByName: z.string().max(200).nullable() });
export const platformEntitlementsSchema = z.object({
  state: token, offer: platformOfferBriefSchema.nullable(), scheduledOffer: platformOfferBriefSchema.nullable(),
  modules: z.array(z.object({ code: moduleToken, inOffer: z.boolean(), entitled: z.boolean(), adjustment: adjustmentDetailSchema.nullable() })).max(20),
  assignments: z.array(z.object({ id, offerId: id, offerName: z.string().max(100), modules: z.array(moduleToken).max(20), effectiveAt: iso,
    phase: z.enum(['IN_FORCE', 'SCHEDULED', 'SUPERSEDED', 'CANCELLED']), createdAt: iso, createdByName: z.string().max(200).nullable(), cancelledAt: iso.nullable() })).max(500),
  adjustments: z.array(z.object({ id, moduleCode: moduleToken, effect: z.enum(adjustmentEffects), reason: z.string().max(500), createdAt: iso,
    createdByName: z.string().max(200).nullable(), phase: z.enum(['ACTIVE', 'ENDED', 'LIFTED']), liftedAt: iso.nullable(), liftedByName: z.string().max(200).nullable(),
    liftReason: z.string().max(500).nullable() })).max(500),
  version: z.number().int().min(1), nextChangeAt: iso.nullable(),
});
export const platformAssignmentPreviewSchema = z.object({
  offer: z.object({ id, name: z.string().max(100), modules: z.array(moduleToken).max(20) }), effectiveAt: iso.nullable(), immediate: z.boolean(),
  replacesScheduled: platformOfferBriefSchema.nullable(),
  endingAdjustments: z.array(z.object({ id, moduleCode: moduleToken, effect: z.enum(adjustmentEffects) })).max(50),
  modules: z.array(z.object({ code: moduleToken, before: z.boolean(), after: z.boolean(), kind: z.enum(consequenceKinds),
    existing: z.record(z.string().max(80), z.number().int().min(0)).nullable() })).max(20),
  version: z.number().int().min(1),
});
export const platformModulesResult = z.object({ data: z.object({ items: z.array(platformModuleSchema).max(20) }) });
export const platformOffersResult = z.object({ data: z.object({ items: z.array(platformOfferSchema).max(200) }) });
export const platformOfferResult = z.object({ data: platformOfferSchema });
export const platformEntitlementsResult = z.object({ data: platformEntitlementsSchema });
export const platformAssignmentPreviewResult = z.object({ data: platformAssignmentPreviewSchema });

export const platformClientSchema = z.object({
  id, displayName: z.string().max(150).nullable(), preparation: z.enum(clientPreparations), schoolId: id.nullable(), school: schoolFactsSchema.nullable(),
  contactName: z.string().max(200).nullable(), contactEmail: z.string().max(254).nullable(),
  latestCode: z.object({ id, state: z.enum(clientCodeStates), expiresAt: iso, createdAt: iso }).nullable(),
  commercial: platformCommercialSchema,
  version: z.number().int().positive(), createdAt: iso, updatedAt: iso,
});
export const platformClientDetailSchema = platformClientSchema.extend({
  contactPhone: z.string().max(32).nullable(),
  billing: z.object({ street: z.string().max(200).nullable(), postalCode: z.string().max(20).nullable(), city: z.string().max(100).nullable(), country: z.string().max(100).nullable() }),
  internalNotes: z.string().max(4000).nullable(),
  link: z.object({ source: z.enum(['OPENING_CODE', 'EXISTING_SCHOOL']), linkedAt: iso, issuedByName: z.string().max(200).nullable() }).nullable(),
  codes: z.array(platformClientCodeSchema).max(50),
});
export const platformUnattachedSchema = z.object({ id, name: z.string().max(200), status: z.enum(['DRAFT', 'ACTIVE', 'ARCHIVED']), contactEmail: z.string().max(254),
  contactPhone: z.string().max(32).nullable(), setup: schoolSetupSchema });
const pageOf = <T extends z.ZodType>(item: T) => z.object({ data: z.object({ items: z.array(item).max(100), total: z.number().int().min(0).nullable(), nextCursor: z.string().max(6000).nullable() }) });
export const platformClientsResult = pageOf(platformClientSchema);
export const platformClientDetailResult = z.object({ data: platformClientDetailSchema });
export const platformCodeResult = z.object({ data: platformClientCodeSchema });
export const platformUnattachedResult = z.object({ data: z.object({ items: z.array(platformUnattachedSchema).max(50) }) });
/** Le code n'existe que dans cette réponse, avec son lien ; les listes et les fiches n'en portent jamais. */
export const platformIssuedCodeResult = z.object({
  data: z.object({ codeId: id, client: platformClientDetailSchema }),
  code: z.string().regex(platformOpeningCodePattern), link: z.string().max(400).optional(),
});
/** Un code créé mais pas encore confié : de quoi reprendre l'opération, jamais le code. */
export const platformPendingCodeResult = z.object({
  pending: z.object({ operationId: id, clientId: id.optional(), displayName: z.string().max(150).optional(), validityDays: z.number().int().min(1).max(30).optional() }).nullable(),
});

export type PlatformOffer = z.infer<typeof platformOfferSchema>;
export type PlatformOfferStatus = (typeof platformOfferStatuses)[number];
export type PlatformModule = z.infer<typeof platformModuleSchema>;
export type PlatformEntitlements = z.infer<typeof platformEntitlementsSchema>;
export type PlatformAssignmentPreview = z.infer<typeof platformAssignmentPreviewSchema>;
export type PlatformCommercial = z.infer<typeof platformCommercialSchema>;
export type PlatformClient = z.infer<typeof platformClientSchema>;
export type PlatformClientDetail = z.infer<typeof platformClientDetailSchema>;
export type PlatformClientCode = z.infer<typeof platformClientCodeSchema>;
export type PlatformUnattachedSchool = z.infer<typeof platformUnattachedSchema>;
export type PlatformClientPreparation = (typeof clientPreparations)[number];
export type PlatformClientCodeState = (typeof clientCodeStates)[number];
export type PlatformPendingCode = NonNullable<z.infer<typeof platformPendingCodeResult>['pending']>;
export type PlatformIssuedCode = z.infer<typeof platformIssuedCodeResult>;

export type PlatformOperator = z.infer<typeof platformOperatorSchema>;
export type PlatformInvitation = z.infer<typeof platformInvitationSchema>;
export type PlatformJournalEntry = z.infer<typeof platformJournalSchema>;
export type PlatformMe = z.infer<typeof platformMeResult>['data'];
export type PlatformPending = NonNullable<z.infer<typeof platformInvitationsResult>['pending']>;
export type PlatformPreview = z.infer<typeof platformPreviewResult>;

export interface PlatformRoutes { console: string; join: string }
export const platformRoutes: PlatformRoutes = { console: '/app/plateforme', join: '/app/plateforme/rejoindre' };

// --- Saisie ---
export const platformCodePattern = /^[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}$/;
/** Le code se lit à voix haute ou se recopie : majuscules, séparateur ajouté, caractères étrangers retirés. */
export function formatPlatformCode(raw: string): string {
  const letters = raw.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 10);
  return letters.length > 5 ? `${letters.slice(0, 5)}-${letters.slice(5)}` : letters;
}
export const isPlatformCode = (value: string) => platformCodePattern.test(value);
export const isInviteeEmail = (value: string) => value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);

// --- Libellés ---
export const levelLabel = (level: string) => ({ COMMERCIAL: 'Commercial' } as Record<string, string>)[level] ?? 'Opérateur';
const rightLabels: Record<string, string> = {
  MANAGE_PLATFORM_TEAM: 'Gérer l’équipe de la plateforme',
  MANAGE_SCHOOL_OPENINGS: 'Ouvrir des écoles',
  MANAGE_OFFERS: 'Gérer les offres et les droits aux modules',
  READ_COMMERCIAL_JOURNAL: 'Lire le journal commercial',
};
const deniedLabels: Record<string, string> = {
  SCHOOL_RECORDS: 'Dossiers des élèves', TRIPS: 'Trajets', MESSAGES: 'Messages', SCHOOL_ROLES: 'Rôles dans une école',
};
export const rightLabel = (right: string) => rightLabels[right] ?? 'Droit commercial';
export const notGrantedLabel = (access: string) => deniedLabels[access] ?? 'Accès scolaire';
export const invitationStatusLabel = (status: PlatformInvitation['status']) =>
  ({ AVAILABLE: 'En attente', USED: 'Acceptée', REVOKED: 'Révoquée', EXPIRED: 'Expirée' })[status];
const actionLabels: Record<string, string> = {
  CREATE_PLATFORM_INVITATION: 'Invitation créée',
  REVOKE_PLATFORM_INVITATION: 'Invitation révoquée',
  REVOKE_PLATFORM_OPERATOR: 'Opérateur retiré',
  ACCEPT_PLATFORM_INVITATION: 'Invitation acceptée',
  BOOTSTRAP_PLATFORM_OPERATOR: 'Opérateur mis en service',
  CREATE_PLATFORM_CLIENT: 'Fiche créée',
  UPDATE_PLATFORM_CLIENT: 'Fiche modifiée',
  ATTACH_EXISTING_SCHOOL: 'École existante rattachée',
  CREATE_SCHOOL_OPENING_CODE: 'Code d’ouverture créé',
  REVOKE_SCHOOL_OPENING_CODE: 'Code d’ouverture révoqué',
  SCHOOL_OPENED_FROM_CODE: 'École ouverte avec un code',
  CREATE_OFFER: 'Offre créée',
  UPDATE_OFFER: 'Offre modifiée',
  ARCHIVE_OFFER: 'Offre archivée',
  RESTORE_OFFER: 'Offre rétablie',
  ASSIGN_OFFER: 'Offre attribuée',
  CANCEL_OFFER_ASSIGNMENT: 'Attribution annulée',
  ADJUST_SCHOOL_MODULE: 'Module ajusté',
  LIFT_MODULE_ADJUSTMENT: 'Ajustement levé',
};
export const actionLabel = (action: string) => actionLabels[action] ?? 'Action enregistrée';
const reasonLabels: Record<string, string> = {
  LAST_PLATFORM_OPERATOR: 'Dernier opérateur actif',
  PLATFORM_OPERATOR_REVOKED: 'Opérateur déjà retiré',
  PLATFORM_OPERATOR_EXISTS: 'Déjà opérateur',
  PLATFORM_INVITATION_PENDING: 'Invitation déjà en attente',
  PLATFORM_INVITATION_USED: 'Invitation déjà utilisée',
  PLATFORM_INVITATION_REVOKED: 'Invitation déjà révoquée',
  PLATFORM_INVITATION_CLOSED: 'Invitation fermée',
  PLATFORM_INVITATION_INVALID: 'Code non valide',
  PLATFORM_INVITATION_EMAIL_MISMATCH: 'Autre adresse',
  PLATFORM_ALREADY_MEMBER: 'Déjà dans l’équipe',
  VERSION_CONFLICT: 'Modifié entre-temps',
  CLIENT_CODE_PENDING: 'Code déjà disponible',
  CLIENT_SCHOOL_LINKED: 'École déjà ouverte',
  CLIENT_SCHOOL_ALREADY_LINKED: 'École déjà rattachée',
  OPENING_CODE_TAKEN: 'Code déjà pris',
  OPENING_LINK_USED: 'Code déjà utilisé',
  OPENING_LINK_REVOKED: 'Code déjà révoqué',
  OPENING_LINK_EXPIRED: 'Code expiré',
  OFFER_ARCHIVED: 'Offre archivée',
  MODULE_NOT_ENTITLED: 'Module non accordé',
};
export const reasonLabel = (code: string | null) => (code ? reasonLabels[code] ?? null : null);

// --- Écoles clientes : libellés et fiche ---
const preparationLabels: Record<PlatformClientPreparation, string> = { AWAITING_SCHOOL: 'En attente de l’école', IN_PREPARATION: 'En préparation', ACTIVE: 'Active', ARCHIVED: 'Archivée' };
export const preparationLabel = (value: PlatformClientPreparation) => preparationLabels[value];
const codeStateLabels: Record<PlatformClientCodeState, string> = { AVAILABLE: 'Disponible', USED: 'Utilisé', EXPIRED: 'Expiré', REVOKED: 'Révoqué' };
export const codeStateLabel = (value: PlatformClientCodeState) => codeStateLabels[value];
export const schoolStatusLabel = (status: 'DRAFT' | 'ACTIVE' | 'ARCHIVED') => ({ DRAFT: 'Brouillon', ACTIVE: 'Active', ARCHIVED: 'Archivée' })[status];
export const clientTitle =(client: Pick<PlatformClient, 'displayName' | 'school'>) => client.displayName ?? client.school?.name ?? 'École sans nom';
export const linkSourceLabel = (source: 'OPENING_CODE' | 'EXISTING_SCHOOL') => (source === 'OPENING_CODE' ? 'Ouverte avec un code' : 'École existante rattachée');

// --- Offres et droits : libellés, saisie et lecture des conséquences ---
const moduleLabels: Record<string, string> = { MESSAGING: 'Messagerie', COLLECTIVE_COURSES: 'Cours collectifs' };
export const moduleLabel = (code: string) => moduleLabels[code] ?? 'Module';
export const modulesLabel = (codes: readonly string[]) => (codes.length ? codes.map(moduleLabel).join(', ') : 'Aucun module');
export const commercialStateLabel = (state: string) => ({ NOT_CONFIGURED: 'Non configurée', OFFER_ACTIVE: 'Offre en vigueur' } as Record<string, string>)[state] ?? 'État commercial';
export const offerStatusLabel = (status: PlatformOfferStatus) => ({ ACTIVE: 'Active', ARCHIVED: 'Archivée' })[status];
export const consequenceLabel = (kind: (typeof consequenceKinds)[number]) =>
  ({ GAINS: 'Accordé', LOSES: 'Retiré', KEEPS: 'Conservé', STAYS_OFF: 'Non accordé' })[kind];
export const adjustmentEffectLabel = (effect: (typeof adjustmentEffects)[number]) => ({ GRANT: 'Accordé en plus', REVOKE: 'Retiré' })[effect];
export const assignmentPhaseLabel = (phase: PlatformEntitlements['assignments'][number]['phase']) =>
  ({ IN_FORCE: 'En vigueur', SCHEDULED: 'Prévue', SUPERSEDED: 'Remplacée', CANCELLED: 'Annulée' })[phase];
export const adjustmentPhaseLabel = (phase: PlatformEntitlements['adjustments'][number]['phase']) =>
  ({ ACTIVE: 'Actif', ENDED: 'Terminé avec l’offre', LIFTED: 'Levé' })[phase];
const usageLabels: Record<string, [string, string]> = {
  conversations: ['conversation', 'conversations'], publishedSeries: ['série publiée', 'séries publiées'],
  activeEnrollments: ['inscription active', 'inscriptions actives'], upcomingSessions: ['séance à venir', 'séances à venir'],
};
/** Ce qu'un retrait laisse en place, en volumes seulement (jamais un contenu) ; vide quand il n'y a rien. */
export function existingUsageLabel(existing: Record<string, number> | null): string {
  if (!existing) return '';
  return Object.entries(existing).filter(([key, count]) => count > 0 && key in usageLabels)
    .map(([key, count]) => `${count} ${usageLabels[key]![count > 1 ? 1 : 0]}`).join(' · ');
}
export const offerNameLimit = 100;
export const reasonLimit = { min: 3, max: 500 } as const;
/** La première raison de ne pas enregistrer une offre ; l'API relit les mêmes bornes. */
export function offerProblem(name: string, modules: readonly string[]): string | null {
  const trimmed = name.trim();
  if (!trimmed) return 'Donnez un nom à l’offre.';
  if (trimmed.length > offerNameLimit) return `Le nom est limité à ${offerNameLimit} caractères.`;
  if (new Set(modules).size !== modules.length) return 'Un module ne peut figurer qu’une fois.';
  return null;
}
/** Un motif d'ajustement lisible par l'équipe ; la même borne que l'API. */
export const reasonProblem = (reason: string): string | null => {
  const trimmed = reason.trim();
  if (trimmed.length < reasonLimit.min) return 'Indiquez le motif en quelques mots.';
  if (trimmed.length > reasonLimit.max) return `Le motif est limité à ${reasonLimit.max} caractères.`;
  return null;
};
/**
 * Date d'effet saisie (heure locale du navigateur) → instant ISO UTC attendu par l'API ; `null` = immédiatement.
 * Une date vide, passée ou illisible n'est jamais envoyée : `undefined` signale la saisie à corriger.
 */
export function effectiveInstant(local: string, now: Date = new Date()): string | null | undefined {
  if (local.trim() === '') return null;
  const parsed = new Date(local);
  if (Number.isNaN(parsed.getTime()) || parsed.getTime() <= now.getTime()) return undefined;
  return parsed.toISOString();
}
/** La suite des modules d'une offre, dans l'ordre du catalogue, sans doublon : ce qui part est toujours une liste canonique. */
export function orderedModules(selected: readonly string[], catalogue: readonly Pick<PlatformModule, 'code' | 'sortOrder'>[]): string[] {
  const chosen = new Set(selected);
  return [...catalogue].sort((a, b) => a.sortOrder - b.sortOrder).map(module => module.code).filter(code => chosen.has(code));
}
export const sameModules = (a: readonly string[], b: readonly string[]) => a.length === b.length && a.every(code => b.includes(code));

/** La progression de la préparation, telle que l'école l'a enregistrée : jamais inventée quand elle n'a rien enregistré. */
export function setupProgress(setup: { stepsDone: number; stepsTotal: number; completedAt: string | null }): string {
  if (setup.completedAt) return 'Préparation terminée';
  if (setup.stepsTotal === 0) return 'Préparation non commencée';
  return `${setup.stepsDone} sur ${setup.stepsTotal} étapes`;
}

export const ficheFields = ['displayName', 'contactName', 'contactEmail', 'contactPhone', 'billingStreet', 'billingPostalCode', 'billingCity', 'billingCountry', 'internalNotes'] as const;
export type FicheField = (typeof ficheFields)[number];
export type FicheDraft = Record<FicheField, string>;
export type FicheChanges = Partial<Record<FicheField, string | null>>;
export const ficheLimits: Record<FicheField, number> = { displayName: 150, contactName: 200, contactEmail: 254, contactPhone: 32, billingStreet: 200,
  billingPostalCode: 20, billingCity: 100, billingCountry: 100, internalNotes: 4000 };
export const ficheDraftOf = (client: PlatformClientDetail): FicheDraft => ({
  displayName: client.displayName ?? '', contactName: client.contactName ?? '', contactEmail: client.contactEmail ?? '', contactPhone: client.contactPhone ?? '',
  billingStreet: client.billing.street ?? '', billingPostalCode: client.billing.postalCode ?? '', billingCity: client.billing.city ?? '',
  billingCountry: client.billing.country ?? '', internalNotes: client.internalNotes ?? '',
});
const normalizedFiche = (field: FicheField, value: string) => (field === 'contactEmail' ? value.trim().normalize('NFC').toLowerCase() : value.trim());
/** Ce qui change, au format de la commande : une zone vidée devient `null`, une zone intacte est absente. Rien de plus ne part. */
export function ficheChanges(client: PlatformClientDetail, draft: FicheDraft): FicheChanges {
  const current = ficheDraftOf(client), changes: FicheChanges = {};
  for (const field of ficheFields) {
    const next = normalizedFiche(field, draft[field]);
    if (next !== normalizedFiche(field, current[field])) changes[field] = next === '' ? null : next;
  }
  return changes;
}
/** La première zone refusée avant tout envoi ; l'API relit les mêmes bornes. */
export function ficheProblem(draft: FicheDraft): { field: FicheField; message: string } | null {
  const email = draft.contactEmail.trim();
  if (email && !isInviteeEmail(email)) return { field: 'contactEmail', message: 'Saisissez une adresse e-mail valide.' };
  for (const field of ficheFields) if (draft[field].trim().length > ficheLimits[field]) return { field, message: `Ce champ est limité à ${ficheLimits[field]} caractères.` };
  return null;
}
export const openingCodeValidities = [1, 3, 7, 14, 30] as const;

/** La modification utile d'une ligne du journal, en une phrase courte ; rien quand l'action se suffit à elle-même. */
export function journalDetail(entry: PlatformJournalEntry, format: (iso: string) => string): string | null {
  const parts: string[] = [];
  const masked = entry.changes.maskedEmail;
  if (typeof masked === 'string') parts.push(masked);
  const expires = entry.changes.expiresAt;
  if (typeof expires === 'string' && iso.safeParse(expires).success) parts.push(`valable jusqu’au ${format(expires)}`);
  if (entry.changes.self === true) parts.push('retrait volontaire');
  const stopped = entry.changes.revokedInvitations;
  if (typeof stopped === 'number' && Number.isInteger(stopped) && stopped > 0) parts.push(stopped === 1 ? '1 invitation révoquée' : `${stopped} invitations révoquées`);
  return parts.length ? parts.join(' · ') : null;
}

// --- Erreurs ---
const failures: Record<string, string> = {
  PLATFORM_OPERATOR_REQUIRED: 'Cet espace est réservé aux opérateurs de la plateforme.',
  VERSION_CONFLICT: 'Cet élément a changé entre-temps. L’écran est à jour : vérifiez, puis recommencez.',
  CLIENT_CODE_PENDING: 'Un code est déjà disponible pour cette école. Révoquez-le avant d’en créer un autre ou de rattacher une école.',
  CLIENT_SCHOOL_LINKED: 'Cette école est déjà ouverte : elle n’a plus besoin de code.',
  CLIENT_SCHOOL_ALREADY_LINKED: 'Cette école est déjà rattachée à une autre fiche.',
  OPENING_CODE_TAKEN: 'Le code tiré existe déjà. Recommencez.',
  OPENING_LINK_USED: 'Ce code a déjà été utilisé : une école est ouverte.',
  OPENING_LINK_REVOKED: 'Ce code est déjà révoqué.',
  OPENING_LINK_EXPIRED: 'Ce code a expiré.',
  OFFER_ARCHIVED: 'Cette offre est archivée : rétablissez-la avant de la modifier ou de l’attribuer.',
  OFFER_NOT_ARCHIVED: 'Cette offre n’est pas archivée.',
  EFFECTIVE_DATE_PAST: 'La date d’effet doit être à venir. L’aperçu a été actualisé.',
  ASSIGNMENT_NOT_PENDING: 'Cette attribution a déjà pris effet ou a été annulée. L’écran est à jour.',
  ADJUSTMENT_REQUIRES_OFFER: 'Cette école n’a pas d’offre en vigueur : attribuez-en une avant d’ajuster un module.',
  ADJUSTMENT_ACTIVE: 'Un ajustement est déjà actif pour ce module. Levez-le d’abord.',
  ADJUSTMENT_NO_EFFECT: 'Cet ajustement ne changerait rien aux droits de l’école.',
  ADJUSTMENT_NOT_ACTIVE: 'Cet ajustement n’est plus actif. L’écran est à jour.',
  MODULE_UNKNOWN: 'Ce module n’existe pas dans le catalogue.',
  PLATFORM_CODE_IN_PROGRESS: 'Un code est déjà en cours de création. Affichez-le ou fermez-le avant d’en créer un autre.',
  NOT_FOUND: 'Cet élément n’existe plus. L’écran a été actualisé.',
  LAST_PLATFORM_OPERATOR: 'Le dernier opérateur actif ne peut pas être retiré.',
  PLATFORM_OPERATOR_REVOKED: 'Cet opérateur n’a déjà plus d’accès.',
  PLATFORM_OPERATOR_EXISTS: 'Cette adresse appartient déjà à un opérateur actif.',
  PLATFORM_INVITATION_PENDING: 'Une invitation est déjà en attente pour cette adresse. Révoquez-la d’abord.',
  PLATFORM_INVITATION_USED: 'Cette invitation a déjà été utilisée.',
  PLATFORM_INVITATION_REVOKED: 'Cette invitation a été révoquée. Demandez-en une nouvelle.',
  PLATFORM_INVITATION_EXPIRED: 'Cette invitation a expiré. Demandez-en une nouvelle.',
  PLATFORM_INVITATION_CLOSED: 'Cette invitation n’est plus ouverte.',
  PLATFORM_INVITATION_INVALID: 'Ce code n’est pas valide ou n’est plus utilisable.',
  PLATFORM_INVITATION_EMAIL_MISMATCH: 'Cette invitation est destinée à une autre adresse. Connectez-vous avec le compte invité.',
  PLATFORM_ALREADY_MEMBER: 'Ce compte fait déjà partie de l’équipe.',
  PLATFORM_CODE_TAKEN: 'Le code tiré existe déjà. Recommencez.',
  EMAIL_VERIFICATION_REQUIRED: 'Vérifiez votre adresse e-mail auprès du service de connexion, puis reconnectez-vous.',
  INVITATION_CODE_ATTEMPTS: 'Trop d’essais. Patientez un instant avant de saisir un autre code.',
  PLATFORM_INVITE_IN_PROGRESS: 'Une invitation est déjà en cours. Terminez-la avant d’en créer une autre.',
  IDEMPOTENCY_MISMATCH: 'Cette demande ne correspond plus à celle déjà envoyée. Actualisez la page.',
  PLATFORM_JOIN_MISSING: 'Saisissez de nouveau le code pour continuer.',
  PLATFORM_JOIN_IN_PROGRESS: 'Une acceptation est déjà en cours. Attendez sa confirmation.',
  PLATFORM_IDENTITY_CHANGED: 'Cette demande appartient à un autre compte. Reconnectez-vous avec ce compte ou saisissez de nouveau le code.',
  PLATFORM_PREVIEW_CHANGED: 'Les droits proposés ont changé. Relisez-les, puis confirmez à nouveau.',
  SESSION_EXPIRED: 'Votre session a expiré. Reconnectez-vous pour continuer.',
  INVALID_REQUEST: 'Certaines informations ne sont pas valides. Vérifiez-les, puis réessayez.',
};
export function platformFailure(error: unknown): string {
  if (error instanceof RequestFailure) {
    const known = failures[error.code];
    if (known) return known;
    if (error.status === 401) return failures.SESSION_EXPIRED!;
    if (error.status === 429) return 'Trop de demandes ont été envoyées. Patientez un instant avant de réessayer.';
    if (error.status === 403) return 'Cette action n’est pas disponible avec vos accès actuels.';
    if (error.status === 0 || error.status >= 500 || error.code === 'INVALID_RESPONSE' || error.code.startsWith('CSRF_')) return errorMessage(error);
  }
  return 'La demande n’a pas pu être confirmée. Réessayez.';
}
/** Ce que l'écran doit faire d'une erreur : se fermer (plus d'accès), recharger (conflit) ou seulement l'afficher. */
export type PlatformFailureKind = 'denied' | 'conflict' | 'expired' | 'unconfirmed' | 'refused';
export function platformFailureKind(error: unknown): PlatformFailureKind {
  if (!(error instanceof RequestFailure)) return 'unconfirmed';
  if (error.status === 403 && error.code === 'PLATFORM_OPERATOR_REQUIRED') return 'denied';
  if (error.status === 412 || error.code === 'VERSION_CONFLICT') return 'conflict';
  if (error.status === 401 || error.code === 'SESSION_EXPIRED') return 'expired';
  // Réseau, réponse illisible ou panne du service : on ne sait pas si l'opération a eu lieu, seule la même demande le tranche.
  if (error.status === 0 || error.status >= 500 || error.code === 'INVALID_RESPONSE') return 'unconfirmed';
  return 'refused';
}
