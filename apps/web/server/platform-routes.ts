import { createHash, randomBytes, randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { matchesSecret, type Session } from './session.js';
import { openingCode } from './opening-routes.js';
import type { ApiResult } from './upstream.js';

/**
 * Console des opérateurs de la plateforme (R01-T01 à R01-T04). Le navigateur ne parle qu'à ce relais : il ne connaît ni l'API, ni
 * un jeton, ni l'empreinte d'un code. Les droits sont relus par l'API à chaque appel ; ce relais ne décide de rien.
 */
export type PlatformRequest = { method: 'GET' | 'POST' | 'PATCH'; path: string; body?: unknown; idempotencyKey?: string; ifMatch?: string };
export type PlatformGateway = (command: PlatformRequest, accessToken: string) => Promise<ApiResult>;
/** Un PDF de facture ne passe pas par le relais JSON : il est lu en mémoire sous une borne et n'est jamais conservé. */
export type PlatformDocumentRequest = { clientId: string; invoiceId: string; revision?: number };
export type PlatformDocumentResult = { status: 200; pdf: Buffer; disposition: string } | { status: number; body: unknown };
export type PlatformDocumentGateway = (request: PlatformDocumentRequest, accessToken: string) => Promise<PlatformDocumentResult>;

const uuidPath = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const strongVersion = /^"[1-9][0-9]{0,9}"$/;
const staticReads = new Set(['/v1/platform/me', '/v1/platform/operators', '/v1/platform/invitations', '/v1/platform/modules']);
const operationPath = new RegExp(`^/v1/platform/operations/${uuidPath}$`);
const revokePath = new RegExp(`^/v1/platform/(?:invitations|operators)/${uuidPath}/revoke$`);
const clientPath = new RegExp(`^/v1/platform/clients/${uuidPath}$`);
const attachPath = new RegExp(`^/v1/platform/clients/${uuidPath}/attach-school$`);
const codeRevokePath = new RegExp(`^/v1/platform/school-codes/${uuidPath}/revoke$`);
// Offres et droits aux modules (R01-T03) : une offre, ses deux changements d'état, puis les droits d'une fiche cliente.
const offerPath = new RegExp(`^/v1/platform/offers/${uuidPath}$`);
const offerStatusPath = new RegExp(`^/v1/platform/offers/${uuidPath}/(?:archive|restore)$`);
const entitlementsPath = new RegExp(`^/v1/platform/clients/${uuidPath}/entitlements$`);
const previewPath = new RegExp(`^/v1/platform/clients/${uuidPath}/assignment-preview$`);
const assignmentsPath = new RegExp(`^/v1/platform/clients/${uuidPath}/assignments$`);
const assignmentCancelPath = new RegExp(`^/v1/platform/clients/${uuidPath}/assignments/${uuidPath}/cancel$`);
const adjustmentsPath = new RegExp(`^/v1/platform/clients/${uuidPath}/adjustments$`);
const adjustmentLiftPath = new RegExp(`^/v1/platform/clients/${uuidPath}/adjustments/${uuidPath}/lift$`);
// Conditions commerciales, essai, début payant et demandes (R01-T04) : le dossier d'une fiche, puis ses commandes versionnées.
const commercialPath = new RegExp(`^/v1/platform/clients/${uuidPath}/commercial$`);
const commercialCommandPath = new RegExp(`^/v1/platform/clients/${uuidPath}/commercial/(?:terms|trial/(?:start|extend|end)|paid-start(?:/cancel)?|requests|requests/${uuidPath}/decision)$`);
// Factures, avoirs, émetteur et activation (R01-T05), règlements (R01-T06) : la facturation d'une fiche, ses commandes versionnées, la liste et l'émetteur.
const billingPath = new RegExp(`^/v1/platform/clients/${uuidPath}/billing$`);
const billingCommandPath = new RegExp(`^/v1/platform/clients/${uuidPath}/(?:billing/activation(?:/stop)?|invoices|invoices/${uuidPath}/(?:issue|cancel|credit|sent|document|delivery)|payments|payments/${uuidPath}/(?:allocations|void|correct|regularizations)|payments/${uuidPath}/allocations/${uuidPath}/release|payments/${uuidPath}/regularizations/${uuidPath}/cancel)$`);
const invoicePath = new RegExp(`^/v1/platform/invoices/${uuidPath}$`);
const deliveryPreviewPath = new RegExp(`^/v1/platform/clients/${uuidPath}/invoices/${uuidPath}/delivery/preview$`);

export const clientPreparations = ['AWAITING_SCHOOL', 'IN_PREPARATION', 'ACTIVE', 'ARCHIVED'] as const;
export const codeStates = ['AVAILABLE', 'USED', 'EXPIRED', 'REVOKED'] as const;
export const offerStatuses = ['ACTIVE', 'ARCHIVED'] as const;
export const invoiceStatuses = ['DRAFT', 'ISSUED', 'CANCELLED'] as const;
export const invoiceKinds = ['INITIAL', 'PERIOD', 'CREDIT_NOTE'] as const;
export const sendStatuses = ['NOT_SENT', 'SENT'] as const;
export const settlementStates = ['PAID', 'PARTIAL', 'UNPAID', 'CREDITED'] as const;
const paymentMethods = ['BANK_TRANSFER', 'CASH', 'OTHER'] as const;

type QueryRule = (value: string) => boolean;
const limitUpTo = (max: number): QueryRule => value => /^[1-9][0-9]{0,2}$/.test(value) && Number(value) <= max;
const cursorRule: QueryRule = value => /^[A-Za-z0-9_-]{1,6000}$/.test(value);
const uuidRule: QueryRule = value => new RegExp(`^${uuidPath}$`).test(value);
const oneOf = (values: readonly string[]): QueryRule => value => values.includes(value);
// La recherche est un texte libre court : pas de caractère de contrôle, longueur bornée comme côté API.
const searchRule: QueryRule = value => value.length <= 100 && !/[\u0000-\u001f\u007f]/.test(value);

/** Chaque paramètre doit être connu, unique et valide : une requête qui sort de la liste n'est jamais émise. */
function validQuery(query: string, rules: Record<string, QueryRule>): boolean {
  if (query === '') return true;
  const seen = new Set<string>();
  for (const [key, value] of new URLSearchParams(query)) {
    if (seen.has(key) || !Object.hasOwn(rules, key) || !rules[key]!(value)) return false;
    seen.add(key);
  }
  return true;
}
const journalRules: Record<string, QueryRule> = { limit: limitUpTo(100), cursor: cursorRule, schoolId: uuidRule, result: oneOf(['SUCCESS', 'REFUSED']) };
const clientListRules: Record<string, QueryRule> = { limit: limitUpTo(100), cursor: cursorRule, q: searchRule, preparation: oneOf(clientPreparations) };
const codeListRules: Record<string, QueryRule> = { limit: limitUpTo(100), cursor: cursorRule, clientId: uuidRule, state: oneOf(codeStates) };
const unattachedRules: Record<string, QueryRule> = { limit: limitUpTo(50), q: searchRule };
const offerListRules: Record<string, QueryRule> = { status: oneOf(offerStatuses) };
// L'API relit la date (ISO, UTC) ; ici seule la forme est vérifiée, sous une borne de longueur.
const instantRule: QueryRule = value => value.length <= 40 && z.iso.datetime().safeParse(value).success;
const previewRules: Record<string, QueryRule> = { offerId: uuidRule, effectiveAt: instantRule };
const dayRule: QueryRule = value => /^\d{4}-\d{2}-\d{2}$/.test(value) && z.iso.date().safeParse(value).success;
const invoiceListRules: Record<string, QueryRule> = { clientId: uuidRule, status: oneOf(invoiceStatuses), kind: oneOf(invoiceKinds), sendStatus: oneOf(sendStatuses),
  settlement: oneOf(settlementStates), from: dayRule, to: dayRule, dueBefore: dayRule, overdue: oneOf(['true']), limit: limitUpTo(100), offset: value => /^(0|[1-9][0-9]{0,5})$/.test(value) && Number(value) <= 100_000 };

/** Liste fermée des appels que le relais peut émettre vers l'API de la plateforme : toute autre route reste inaccessible. */
export function allowedPlatformRequest(request: PlatformRequest): boolean {
  const cut = request.path.indexOf('?');
  const path = cut < 0 ? request.path : request.path.slice(0, cut);
  const query = cut < 0 ? '' : request.path.slice(cut + 1);
  if (request.method === 'GET') {
    if (request.body !== undefined || request.idempotencyKey !== undefined || request.ifMatch !== undefined) return false;
    if (path === '/v1/platform/journal') return validQuery(query, journalRules);
    if (path === '/v1/platform/clients') return validQuery(query, clientListRules);
    if (path === '/v1/platform/school-codes') return validQuery(query, codeListRules);
    if (path === '/v1/platform/unattached-schools') return validQuery(query, unattachedRules);
    if (path === '/v1/platform/offers') return validQuery(query, offerListRules);
    // L'aperçu des conséquences porte toujours l'offre visée : sans elle il n'y a rien à prévoir.
    if (previewPath.test(path)) return new URLSearchParams(query).has('offerId') && validQuery(query, previewRules);
    if (path === '/v1/platform/invoices') return validQuery(query, invoiceListRules);
    return query === '' && (staticReads.has(path) || operationPath.test(path) || clientPath.test(path) || entitlementsPath.test(path) || commercialPath.test(path)
      || path === '/v1/platform/billing/issuer' || billingPath.test(path) || invoicePath.test(path) || deliveryPreviewPath.test(path));
  }
  if ((request.method !== 'POST' && request.method !== 'PATCH') || query !== '') return false;
  const keyed = typeof request.idempotencyKey === 'string' && z.uuid().safeParse(request.idempotencyKey).success;
  const versioned = typeof request.ifMatch === 'string' && strongVersion.test(request.ifMatch);
  if (request.method === 'PATCH') return (clientPath.test(path) || offerPath.test(path)) && keyed && versioned;
  if (path === '/v1/platform/invitations/preview') return request.idempotencyKey === undefined && request.ifMatch === undefined;
  if (path === '/v1/platform/invitations' || path === '/v1/platform/invitations/accept') return keyed && request.ifMatch === undefined;
  if (revokePath.test(path)) return keyed && versioned;
  if (path === '/v1/platform/clients' || path === '/v1/platform/school-codes' || path === '/v1/platform/offers' || codeRevokePath.test(path)) return keyed && request.ifMatch === undefined;
  if (attachPath.test(path) || offerStatusPath.test(path) || assignmentsPath.test(path) || assignmentCancelPath.test(path) || adjustmentsPath.test(path)
    || adjustmentLiftPath.test(path) || commercialCommandPath.test(path)) return keyed && versioned;
  // L'émetteur et la facturation d'une fiche partent sous leur version ; le passage manuel est idempotent par nature, sans version.
  if (path === '/v1/platform/billing/issuer' || billingCommandPath.test(path)) return keyed && versioned;
  if (path === '/v1/platform/billing/run') return keyed && request.ifMatch === undefined;
  return false;
}

// --- Réponses de l'API : seuls les champs connus sont relayés, une forme inattendue devient une erreur du service. ---
const iso = z.iso.datetime({ offset: true });
const token = z.string().regex(/^[A-Z][A-Z0-9_]{2,63}$/);
const rightsFields = { level: token, rights: z.array(token).max(40), notGranted: z.array(token).max(40) };
const operatorSchema = z.object({ id: z.uuid(), displayName: z.string().max(200), maskedEmail: z.string().max(254).nullable(), level: token,
  status: z.enum(['ACTIVE', 'REVOKED']), addedVia: z.enum(['BOOTSTRAP', 'INVITATION']), joinedAt: iso, revokedAt: iso.nullable(),
  version: z.number().int().positive(), self: z.boolean() });
const invitationSchema = z.object({ id: z.uuid(), status: z.enum(['AVAILABLE', 'USED', 'REVOKED', 'EXPIRED']), level: token, maskedEmail: z.string().max(254),
  createdAt: iso, expiresAt: iso, version: z.number().int().positive(), usedAt: iso.nullable(), revokedAt: iso.nullable(), createdByName: z.string().max(200).nullable() });
const journalSchema = z.object({ id: z.uuid(), occurredAt: iso, actorKind: z.enum(['OPERATOR', 'SYSTEM']), actorName: z.string().max(200), action: token,
  result: z.enum(['SUCCESS', 'REFUSED']), reasonCode: token.nullable(), schoolId: z.uuid().nullable(),
  subject: z.object({ type: z.string().max(80), id: z.string().max(80) }).nullable(), operationId: z.uuid().nullable(), changes: z.record(z.string(), z.unknown()) });
const meResult = z.object({ data: z.object({ operator: operatorSchema, ...rightsFields }) });
const operatorsResult = z.object({ data: z.object({ items: z.array(operatorSchema).max(200) }) });
const operatorResult = z.object({ data: operatorSchema });
const invitationsResult = z.object({ data: z.object({ items: z.array(invitationSchema).max(100) }) });
const invitationResult = z.object({ data: invitationSchema });
const journalResult = z.object({ data: z.object({ items: z.array(journalSchema).max(100), nextCursor: z.string().max(6000).nullable() }) });
const operationResult = z.object({ data: z.object({ operationId: z.uuid(), kind: token, statusCode: z.number().int(), result: z.unknown() }) });
const previewResult = z.object({ data: z.object({ status: z.literal('AVAILABLE'), maskedEmail: z.string().max(254), expiresAt: iso, matchesAccount: z.boolean(),
  alreadyMember: z.boolean(), ...rightsFields }) });
const acceptedResult = z.object({ data: z.object({ operator: operatorSchema, ...rightsFields }) });
export type PlatformJoinResult = z.infer<typeof acceptedResult>['data'];

// --- Écoles clientes (R01-T02) : seuls les faits d'école de la projection fixe de l'API sont relayés, jamais un dossier, un trajet ni un message. ---
const text = (max: number) => z.string().max(max);
const schoolStatus = z.enum(['DRAFT', 'ACTIVE', 'ARCHIVED']);
const setupSchema = z.object({ step: text(80).nullable(), stepsDone: z.number().int().min(0).max(100), stepsTotal: z.number().int().min(0).max(100),
  completedAt: iso.nullable(), savedAt: iso.nullable() });
const schoolFacts = z.object({ name: text(200), status: schoolStatus, contactEmail: text(254), contactPhone: text(32).nullable(), setup: setupSchema });
const codeStateSchema = z.enum(codeStates);
const latestCodeSchema = z.object({ id: z.uuid(), state: codeStateSchema, expiresAt: iso, createdAt: iso });
// --- Offres et droits aux modules (R01-T03) : codes de modules et états tolérants (le catalogue évolue côté API), petits vocabulaires fermés stricts. ---
const moduleToken = token;
const offerBriefSchema = z.object({ offerId: z.uuid(), name: text(100), effectiveAt: iso, modules: z.array(moduleToken).max(20) });
/**
 * L'emplacement commercial de la fiche : état des droits (R01-T03) et cycle commercial (R01-T04). Le cycle est optionnel pour qu'une API
 * antérieure reste lisible ; `dueDates` ne porte que des instants, jamais un montant.
 */
const commercialSchema = z.object({ state: token, lifecycle: token.optional(), offer: offerBriefSchema.nullable(), scheduledOffer: offerBriefSchema.nullable(),
  trialEndsAt: iso.nullable().optional(), paidStartsOn: z.iso.date().nullable().optional(), terminationOn: z.iso.date().nullable().optional(),
  billingReady: z.boolean().optional(), entitlementVersion: z.number().int().min(1), dueDates: z.array(iso).max(50) });
const offerSchema = z.object({ id: z.uuid(), name: text(100), modules: z.array(moduleToken).max(20), status: z.enum(offerStatuses), version: z.number().int().min(1),
  createdAt: iso, updatedAt: iso, archivedAt: iso.nullable(), schoolsInForce: z.number().int().min(0) });
const moduleCatalogueSchema = z.object({ code: moduleToken, sortOrder: z.number().int().min(1) });
const adjustmentDetailSchema = z.object({ id: z.uuid(), effect: z.enum(['GRANT', 'REVOKE']), reason: text(500), createdAt: iso, createdByName: text(200).nullable() });
const entitlementsSchema = z.object({
  state: token, offer: offerBriefSchema.nullable(), scheduledOffer: offerBriefSchema.nullable(),
  modules: z.array(z.object({ code: moduleToken, inOffer: z.boolean(), entitled: z.boolean(), adjustment: adjustmentDetailSchema.nullable() })).max(20),
  assignments: z.array(z.object({ id: z.uuid(), offerId: z.uuid(), offerName: text(100), modules: z.array(moduleToken).max(20), effectiveAt: iso,
    phase: z.enum(['IN_FORCE', 'SCHEDULED', 'SUPERSEDED', 'CANCELLED']), createdAt: iso, createdByName: text(200).nullable(), cancelledAt: iso.nullable() })).max(500),
  adjustments: z.array(z.object({ id: z.uuid(), moduleCode: moduleToken, effect: z.enum(['GRANT', 'REVOKE']), reason: text(500), createdAt: iso,
    createdByName: text(200).nullable(), phase: z.enum(['ACTIVE', 'ENDED', 'LIFTED']), liftedAt: iso.nullable(), liftedByName: text(200).nullable(),
    liftReason: text(500).nullable() })).max(500),
  version: z.number().int().min(1), nextChangeAt: iso.nullable(),
});
const assignmentPreviewSchema = z.object({
  offer: z.object({ id: z.uuid(), name: text(100), modules: z.array(moduleToken).max(20) }), effectiveAt: iso.nullable(), immediate: z.boolean(),
  replacesScheduled: offerBriefSchema.nullable(),
  endingAdjustments: z.array(z.object({ id: z.uuid(), moduleCode: moduleToken, effect: z.enum(['GRANT', 'REVOKE']) })).max(50),
  modules: z.array(z.object({ code: moduleToken, before: z.boolean(), after: z.boolean(), kind: z.enum(['GAINS', 'LOSES', 'KEEPS', 'STAYS_OFF']),
    existing: z.record(z.string().max(80), z.number().int().min(0)).nullable() })).max(20),
  version: z.number().int().min(1),
});
const modulesResult = z.object({ data: z.object({ items: z.array(moduleCatalogueSchema).max(20) }) });
const offersResult = z.object({ data: z.object({ items: z.array(offerSchema).max(200) }) });
const offerResult = z.object({ data: offerSchema });
const entitlementsResult = z.object({ data: entitlementsSchema });
const previewConsequencesResult = z.object({ data: assignmentPreviewSchema });
const clientSummarySchema = z.object({ id: z.uuid(), displayName: text(150).nullable(), preparation: z.enum(clientPreparations), schoolId: z.uuid().nullable(),
  school: schoolFacts.nullable(), contactName: text(200).nullable(), contactEmail: text(254).nullable(), latestCode: latestCodeSchema.nullable(),
  commercial: commercialSchema, version: z.number().int().positive(), createdAt: iso, updatedAt: iso });
const codeSchema = z.object({ id: z.uuid(), state: codeStateSchema, clientId: z.uuid().nullable(), clientName: text(150).nullable(), createdAt: iso, expiresAt: iso,
  usedAt: iso.nullable(), revokedAt: iso.nullable(), issuedByName: text(200).nullable(), school: schoolFacts.extend({ id: z.uuid() }).nullable() });
const clientDetailSchema = clientSummarySchema.extend({
  contactPhone: text(32).nullable(),
  billing: z.object({ street: text(200).nullable(), postalCode: text(20).nullable(), city: text(100).nullable(), country: text(100).nullable() }),
  internalNotes: text(4000).nullable(),
  link: z.object({ source: z.enum(['OPENING_CODE', 'EXISTING_SCHOOL']), linkedAt: iso, issuedByName: text(200).nullable() }).nullable(),
  codes: z.array(codeSchema).max(50),
});
const page = <T extends z.ZodType>(item: T) => z.object({ data: z.object({ items: z.array(item).max(100), total: z.number().int().min(0).nullable(), nextCursor: z.string().max(6000).nullable() }) });
const clientsResult = page(clientSummarySchema);
const clientResult = z.object({ data: clientDetailSchema });
const codesResult = page(codeSchema);
const codeResult = z.object({ data: codeSchema });
const unattachedResult = z.object({ data: z.object({ items: z.array(z.object({ id: z.uuid(), name: text(200), status: schoolStatus, contactEmail: text(254), contactPhone: text(32).nullable(), setup: setupSchema })).max(50) }) });
const issuedCodeResult = z.object({ data: z.object({ codeId: z.uuid(), client: clientDetailSchema }) });

// --- Dossier commercial (R01-T04) : montants en centimes de CHF, jours en Europe/Zurich. Vocabulaires en jetons : l'API les relit. ---
const isoDay = z.iso.date();
const cents = z.number().int().min(0).max(100_000_000);
const termsVersionSchema = z.object({ id: z.uuid(), sequence: z.number().int().min(1), currency: z.literal('CHF'), initialAmount: cents.nullable(),
  initialDiscount: cents, initialDueOn: isoDay.nullable(), monthlyAmount: cents.nullable(), recurringDiscount: cents,
  recurringDiscountMonths: z.number().int().min(1).max(120).nullable(), paymentTermDays: z.number().int().min(0).max(120).nullable(),
  suspensionBilling: token.nullable(), effectiveFrom: isoDay, exceptionReason: text(500).nullable(), createdAt: iso, createdByName: text(200).nullable(), phase: token });
const commercialRequestSchema = z.object({ id: z.uuid(), kind: token, status: token, requestedOn: isoDay, requestedOfferId: z.uuid().nullable(),
  requestedOfferName: text(100).nullable(), desiredOn: isoDay.nullable(), details: text(1000).nullable(), response: text(1000).nullable(),
  effectiveOn: isoDay.nullable(), assignmentId: z.uuid().nullable(), decidedAt: iso.nullable(), decidedByName: text(200).nullable(),
  version: z.number().int().min(1), createdAt: iso, createdByName: text(200).nullable(), updatedAt: iso });
const commercialDetailSchema = z.object({
  state: token, lifecycle: token, restriction: z.object({ reason: token, closes: z.array(token).max(5) }).nullable(),
  offer: offerBriefSchema.nullable(), scheduledOffer: offerBriefSchema.nullable(),
  milestones: z.object({ codeIssuedAt: iso.nullable(), schoolCreatedAt: iso.nullable(), schoolLinkedAt: iso.nullable(), activatedAt: iso.nullable(),
    trialStartsAt: iso.nullable(), paidStartsOn: isoDay.nullable() }),
  proposedTrialStart: iso.nullable(),
  trial: z.object({ startsAt: iso, endsAt: iso, phase: token }).nullable(),
  trialChanges: z.array(z.object({ id: z.uuid(), sequence: z.number().int().min(1), kind: token, startsAt: iso, endsAt: iso, reason: text(500).nullable(),
    createdAt: iso, createdByName: text(200).nullable() })).max(500),
  terms: z.object({ status: token, missing: z.array(token).max(10), currency: z.literal('CHF'), inForce: termsVersionSchema.nullable(),
    scheduled: termsVersionSchema.nullable(), versions: z.array(termsVersionSchema).max(500) }),
  paidStart: z.object({ id: z.uuid(), startsOn: isoDay, started: z.boolean(), termsSequence: z.number().int().min(1).nullable(), confirmedAt: iso,
    confirmedByName: text(200).nullable() }).nullable(),
  paidStarts: z.array(z.object({ id: z.uuid(), startsOn: isoDay, status: token, confirmedAt: iso, confirmedByName: text(200).nullable(), cancelledAt: iso.nullable(),
    cancelledByName: text(200).nullable(), cancelReason: text(500).nullable() })).max(500),
  termination: z.object({ requestId: z.uuid(), effectiveOn: isoDay, decidedAt: iso }).nullable(),
  requests: z.array(commercialRequestSchema).max(100),
  billable: z.boolean(), nextPeriodStart: isoDay.nullable(),
  schedule: z.object({
    initial: z.object({ dueOn: isoDay, amount: cents, discount: cents, net: cents, termsSequence: z.number().int().min(1) }).nullable(),
    periods: z.array(z.object({ index: z.number().int().min(0), startsOn: isoDay, endsOn: isoDay, amount: cents.nullable(), discount: cents, net: cents.nullable(),
      termsSequence: z.number().int().min(1).nullable() })).max(12),
  }),
  today: isoDay, entitlementVersion: z.number().int().min(1), nextChangeAt: iso.nullable(), version: z.number().int().min(1),
});
const commercialResult = z.object({ data: commercialDetailSchema });

// --- Facturation (R01-T05) : la projection fixe de `contracts/platform-billing.json`. Montants en centimes de CHF, jours en Europe/Zurich. ---
const nullableText = (max: number) => text(max).nullable();
const issuerSchema = z.object({ id: z.uuid(), sequence: z.number().int().min(1), legalName: text(150), street: text(200), buildingNumber: nullableText(16), postalCode: text(20), city: text(100),
  country: z.string().regex(/^[A-Z]{2}$/), email: nullableText(254), iban: nullableText(42), accountHolder: nullableText(70), taxMode: z.enum(['NONE', 'VAT']), vatNumber: nullableText(40),
  taxRateBp: z.number().int().min(1).max(5000).nullable(), pricesIncludeTax: z.boolean().nullable(), taxNote: nullableText(200), createdAt: iso,
  createdByName: nullableText(200) });
const issuerSettingsResult = z.object({ data: z.object({ current: issuerSchema.nullable(), versions: z.array(issuerSchema).max(50), version: z.number().int().min(1) }) });
const invoiceLineSchema = z.object({ code: token, label: text(200), periodStart: isoDay.nullable(), periodEnd: isoDay.nullable(), amount: cents, discount: cents,
  net: cents, termsSequence: z.number().int().min(1).nullable() });
const settlementSchema = z.object({ state: z.enum(settlementStates), allocated: cents, credited: cents, balance: cents, overdue: z.boolean() });
const invoiceAllocationSchema = z.object({ id: z.uuid(), paymentId: z.uuid(), amount: cents, receivedOn: isoDay, method: z.enum(paymentMethods), createdAt: iso,
  createdByName: nullableText(200) });
// PDF et envoi (R01-T07) : `ACCEPTED` veut dire accepté par le serveur SMTP, ni livré ni lu.
const invoiceDocumentSchema = z.object({ id: z.uuid(), revision: z.number().int().min(1).max(20), paymentMode: z.enum(['QR', 'NONE']), referenceType: z.enum(['QRR', 'SCOR']).nullable(),
  reference: nullableText(40), amount: cents, byteSize: z.number().int().min(1).max(2_097_152), sha256: z.string().regex(/^[0-9a-f]{64}$/), createdAt: iso, createdByName: nullableText(200) });
const invoiceDeliverySchema = z.object({ id: z.uuid(), status: z.enum(['QUEUED', 'PROCESSING', 'ACCEPTED', 'FAILED', 'UNCERTAIN', 'CANCELLED']), recipientMasked: text(254),
  attempts: z.number().int().min(0).max(5), failureCode: nullableText(80), documentId: z.uuid(), resendOf: z.uuid().nullable(), requestedAt: iso, requestedByName: nullableText(200),
  acceptedAt: iso.nullable(), finishedAt: iso.nullable() });
const invoiceSchema = z.object({
  id: z.uuid(), clientId: z.uuid(), clientName: nullableText(150), schoolId: z.uuid().nullable(), kind: z.enum(invoiceKinds), generation: z.number().int().min(1),
  status: z.enum(invoiceStatuses), origin: z.enum(['MANUAL', 'SCHEDULED']), number: nullableText(40), currency: z.literal('CHF'),
  period: z.object({ index: z.number().int().min(0), startsOn: isoDay, endsOn: isoDay }).nullable(), termsSequence: z.number().int().min(1).nullable(),
  lines: z.array(invoiceLineSchema).min(1).max(10), subtotal: cents, discountTotal: cents, netTotal: cents,
  tax: z.object({ mode: z.enum(['NONE', 'VAT']), rateBp: z.number().int().nullable(), pricesIncludeTax: z.boolean().nullable(), amount: cents }).nullable(),
  total: cents.nullable(), issuedOn: isoDay.nullable(), dueOn: isoDay.nullable(), paymentTermDays: z.number().int().min(0).nullable(), issuedAt: iso.nullable(),
  issuedByName: nullableText(200),
  issuer: z.object({ legalName: text(150), street: text(200), buildingNumber: nullableText(16), postalCode: text(20), city: text(100), country: text(2), email: nullableText(254),
    iban: nullableText(42), accountHolder: nullableText(70), vatNumber: nullableText(40), taxNote: nullableText(200) }).nullable(),
  recipient: z.object({ name: text(150), contactName: nullableText(200), street: text(200), postalCode: text(20), city: text(100), country: text(100) }).nullable(),
  sendStatus: z.enum(sendStatuses), sentOn: isoDay.nullable(), sentRecordedAt: iso.nullable(), sentRecordedByName: nullableText(200),
  balance: cents.nullable(), overdue: z.boolean(), settlement: settlementSchema.nullable(), allocations: z.array(invoiceAllocationSchema).max(200),
  documents: z.array(invoiceDocumentSchema).max(20), delivery: invoiceDeliverySchema.nullable(),
  creditNote: z.object({ id: z.uuid(), number: text(40), total: cents, issuedOn: isoDay }).nullable(),
  creditsInvoice: z.object({ id: z.uuid(), number: nullableText(40) }).nullable(),
  reason: nullableText(500), preparedAt: iso, preparedByName: nullableText(200), cancelledAt: iso.nullable(), cancelledByName: nullableText(200),
  version: z.number().int().min(1),
});
const paymentSchema = z.object({
  id: z.uuid(), clientId: z.uuid(), amount: cents, currency: z.literal('CHF'), receivedOn: isoDay, method: z.enum(paymentMethods), reference: nullableText(140),
  note: nullableText(500), status: z.enum(['RECORDED', 'VOIDED']), allocated: cents, regularized: cents, available: cents, correctsPaymentId: z.uuid().nullable(),
  correctedByPaymentId: z.uuid().nullable(), recordedAt: iso, recordedByName: nullableText(200), voidedAt: iso.nullable(), voidedByName: nullableText(200),
  voidCause: z.enum(['VOIDED', 'CORRECTED']).nullable(), voidReason: nullableText(500),
  allocations: z.array(z.object({ id: z.uuid(), invoiceId: z.uuid(), invoiceNumber: nullableText(40), amount: cents, status: z.enum(['ACTIVE', 'RELEASED']), createdAt: iso,
    createdByName: nullableText(200), releasedAt: iso.nullable(), releasedByName: nullableText(200),
    releaseCause: z.enum(['MANUAL', 'PAYMENT_VOIDED', 'PAYMENT_CORRECTED']).nullable(), releaseReason: nullableText(500) })).max(200),
  regularizations: z.array(z.object({ id: z.uuid(), amount: cents, kind: z.enum(['REFUND_RECORDED', 'OTHER']), reason: text(500), status: z.enum(['ACTIVE', 'CANCELLED']),
    createdAt: iso, createdByName: nullableText(200), cancelledAt: iso.nullable(), cancelledByName: nullableText(200), cancelReason: nullableText(500) })).max(200),
  version: z.number().int().min(1),
});
const debtSchema = z.object({ outstanding: cents, overdueAmount: cents, overdueCount: z.number().int().min(0), oldestOverdueDueOn: isoDay.nullable(), unallocated: cents });
const activationSchema = z.object({ id: z.uuid(), startsOn: isoDay, status: z.enum(['ACTIVE', 'STOPPED']), activatedAt: iso, activatedByName: nullableText(200),
  stoppedAt: iso.nullable(), stoppedByName: nullableText(200), stopReason: nullableText(500) });
const documentState = { state: z.enum(['NOT_DUE', 'DUE', 'DRAFT', 'ISSUED', 'CREDITED']), invoiceId: z.uuid().nullable(), number: nullableText(40),
  total: cents.nullable(), balance: cents.nullable() };
const billingSchema = z.object({
  today: isoDay, billable: z.boolean(), issuerReady: z.boolean(), activation: activationSchema.nullable(), activations: z.array(activationSchema).max(20),
  paidStartsOn: isoDay.nullable(), terminationOn: isoDay.nullable(),
  initial: z.object({ dueOn: isoDay, amount: cents, discount: cents, net: cents, termsSequence: z.number().int().min(1), ...documentState }).nullable(),
  periods: z.array(z.object({ index: z.number().int().min(0), startsOn: isoDay, endsOn: isoDay, amount: cents.nullable(), discount: cents, net: cents.nullable(),
    termsSequence: z.number().int().min(1).nullable(), ...documentState })).max(36),
  invoices: z.array(invoiceSchema).max(200), outstanding: z.number().int().min(0), overdue: z.number().int().min(0), debt: debtSchema,
  payments: z.array(paymentSchema).max(200), version: z.number().int().min(1),
});
const billingResult = z.object({ data: billingSchema });
const invoiceResult = z.object({ data: invoiceSchema });
const deliveryPreviewResult = z.object({ data: z.object({ to: nullableText(254), subject: text(300), text: text(4000), fileName: text(80), paymentMode: z.enum(['QR', 'NONE']),
  amount: cents, resend: z.boolean(), ready: z.boolean(), problems: z.array(z.object({ code: token, message: text(300) })).max(10) }) });
const invoicePageResult = z.object({ data: z.object({ items: z.array(invoiceSchema).max(100), total: z.number().int().min(0), limit: z.number().int().min(1),
  offset: z.number().int().min(0), today: isoDay }) });
const billingRunResult = z.object({ data: z.union([z.object({ skipped: z.literal(true) }),
  z.object({ skipped: z.literal(false), today: isoDay, clients: z.number().int().min(0), prepared: z.number().int().min(0), issued: z.number().int().min(0),
    waiting: z.number().int().min(0), failed: z.number().int().min(0) })]) });

// --- État de session : un code émis et une acceptation en cours appartiennent au compte qui les a lancés. ---
export type PlatformInviteState = { operationId: string; email: string; validityDays?: number; code: string; busy?: boolean };
export type PlatformJoinState = { identity: string; operationId: string; code?: string; confirmation?: { id: string; digest: string };
  busy?: boolean; submitted?: boolean; uncertain?: boolean; accepted?: PlatformJoinResult };
/** « Créer un code » : le code naît ici, pour une opération, et est rendu à l'opérateur qui l'a demandée tant qu'il ne l'a pas confié. */
export type PlatformCodeState = { operationId: string; clientId?: string; displayName?: string; validityDays?: number; code: string; busy?: boolean };

// Code d'accès : 10 caractères sans O/0/I/1 (32 symboles, 50 bits) ; 256 est un multiple de 32, le tirage est sans biais.
const codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export function platformInvitationCode(): string {
  const chars = Array.from(randomBytes(10), byte => codeAlphabet[byte % 32]).join('');
  return `${chars.slice(0, 5)}-${chars.slice(5)}`;
}
export const normalizePlatformCode = (code: string) => code.trim().toUpperCase().replace(/[\s_]/g, '').replace(/^([A-Z0-9]{5})-?([A-Z0-9]{5})$/, '$1-$2');
export const platformCodeSchema = z.string().max(40).transform(normalizePlatformCode).pipe(z.string().regex(/^[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}$/));

const empty = z.object({}).strict();
const uuid = z.uuid();
const email = z.string().trim().max(254).transform(value => value.normalize('NFC').toLowerCase()).pipe(z.email());
const inviteBody = z.object({ operationId: uuid, email, validityDays: z.number().int().min(1).max(14).optional() }).strict();
const revokeBody = z.object({ operationId: uuid, version: z.number().int().min(1).max(2_147_483_647) }).strict();
const journalParams = z.object({ limit: z.coerce.number().int().min(1).max(100).optional(), cursor: z.string().regex(/^[A-Za-z0-9_-]{1,6000}$/).optional(),
  schoolId: uuid.optional(), result: z.enum(['SUCCESS', 'REFUSED']).optional() }).strict();
const cursorText = z.string().regex(/^[A-Za-z0-9_-]{1,6000}$/);
const searchText = z.string().trim().max(100).refine(value => !/[\u0000-\u001f\u007f]/.test(value));
const clientListParams = z.object({ limit: z.coerce.number().int().min(1).max(100).optional(), cursor: cursorText.optional(), q: searchText.optional(),
  preparation: z.enum(clientPreparations).optional() }).strict();
const codeListParams = z.object({ limit: z.coerce.number().int().min(1).max(100).optional(), cursor: cursorText.optional(), clientId: uuid.optional(),
  state: z.enum(codeStates).optional() }).strict();
const unattachedParams = z.object({ limit: z.coerce.number().int().min(1).max(50).optional(), q: searchText.optional() }).strict();
// Zones de la fiche : `null` efface, une zone absente reste telle quelle. Mêmes bornes que l'API, qui les relit.
const optionalText = (max: number) => z.string().trim().min(1).max(max).nullable().optional();
const fiche = {
  displayName: optionalText(150), contactName: optionalText(200), contactEmail: z.string().trim().max(254).transform(value => value.normalize('NFC').toLowerCase()).pipe(z.email()).nullable().optional(),
  contactPhone: optionalText(32), billingStreet: optionalText(200), billingPostalCode: optionalText(20), billingCity: optionalText(100), billingCountry: optionalText(100),
  internalNotes: optionalText(4000),
};
const ficheNames = Object.keys(fiche) as (keyof typeof fiche)[];
/** 4 000 caractères de notes en UTF-8 (3 octets au plus) et les autres zones, avec la marge des échappements JSON. */
const FICHE_BODY_LIMIT = 16_384;
const createClientBody = z.object({ operationId: uuid, ...fiche, schoolId: uuid.optional() }).strict();
const updateClientBody = z.object({ operationId: uuid, version: z.number().int().min(1).max(2_147_483_647), ...fiche }).strict()
  .refine(body => ficheNames.some(name => body[name] !== undefined));
const attachBody = z.object({ operationId: uuid, version: z.number().int().min(1).max(2_147_483_647), schoolId: uuid }).strict();
const issueCodeBody = z.object({ operationId: uuid, clientId: uuid.optional(), displayName: z.string().trim().min(1).max(150).optional(),
  validityDays: z.number().int().min(1).max(30).optional() }).strict().refine(body => !(body.clientId && body.displayName));
const codeRevokeBody = z.object({ operationId: uuid }).strict();
// Offres et droits aux modules : mêmes bornes que l'API, qui relit chacune. Les codes de module restent des jetons : le catalogue vit côté API.
const versionField = z.number().int().min(1).max(2_147_483_647);
const moduleCode = z.string().regex(/^[A-Z][A-Z0-9_]{2,63}$/);
const offerName = z.string().trim().min(1).max(100);
const offerModules = z.array(moduleCode).max(20).refine(list => new Set(list).size === list.length);
const reasonText = z.string().trim().min(3).max(500);
const createOfferBody = z.object({ operationId: uuid, name: offerName, modules: offerModules }).strict();
const updateOfferBody = z.object({ operationId: uuid, version: versionField, name: offerName.optional(), modules: offerModules.optional() }).strict()
  .refine(body => body.name !== undefined || body.modules !== undefined);
const offerListParams = z.object({ status: z.enum(offerStatuses).optional() }).strict();
const previewParams = z.object({ offerId: uuid, effectiveAt: z.iso.datetime().max(40).optional() }).strict();
const assignBody = z.object({ operationId: uuid, version: versionField, offerId: uuid, effectiveAt: z.iso.datetime().max(40).nullable().optional() }).strict();
const adjustBody = z.object({ operationId: uuid, version: versionField, moduleCode, effect: z.enum(['GRANT', 'REVOKE']), reason: reasonText }).strict();
const liftBody = z.object({ operationId: uuid, version: versionField, reason: reasonText }).strict();
// Commandes commerciales : mêmes bornes que l'API, qui relit chaque règle (dates, complétude, période, résiliation).
const day = z.iso.date();
const commercialReason = z.string().trim().min(3).max(500);
const longText = z.string().trim().min(3).max(1000);
const amount = (max: number) => z.number().int().min(0).max(max);
const termsCommand = z.object({ operationId: uuid, version: versionField,
  initialAmount: amount(100_000_000).nullable(), initialDiscount: amount(100_000_000).optional(), initialDueOn: day.nullable().optional(),
  monthlyAmount: amount(10_000_000).nullable(), recurringDiscount: amount(10_000_000).optional(), recurringDiscountMonths: z.number().int().min(1).max(120).nullable().optional(),
  paymentTermDays: z.number().int().min(0).max(120).nullable(), suspensionBilling: z.enum(['CONTINUE', 'PAUSE']).nullable(),
  effectiveFrom: day.optional(), exceptionReason: commercialReason.optional() }).strict();
const trialStartCommand = z.object({ operationId: uuid, version: versionField, startsAt: z.iso.datetime().max(40).optional(), endsAt: z.iso.datetime().max(40) }).strict();
const trialExtendCommand = z.object({ operationId: uuid, version: versionField, endsAt: z.iso.datetime().max(40), reason: commercialReason }).strict();
const trialEndCommand = z.object({ operationId: uuid, version: versionField, endsAt: z.iso.datetime().max(40).optional(), reason: commercialReason }).strict();
const paidStartCommand = z.object({ operationId: uuid, version: versionField, startsOn: day, confirm: z.literal(true) }).strict();
const paidStartCancelCommand = z.object({ operationId: uuid, version: versionField, reason: commercialReason }).strict();
const requestCommand = z.object({ operationId: uuid, version: versionField, kind: z.enum(['OFFER_CHANGE', 'TERMINATION']), requestedOn: day,
  requestedOfferId: uuid.optional(), desiredOn: day.optional(), details: longText.optional() }).strict();
const decisionCommand = z.object({ operationId: uuid, version: versionField, status: z.enum(['IN_PROGRESS', 'ACCEPTED', 'REFUSED', 'WITHDRAWN']),
  response: longText.optional(), effectiveOn: day.optional(), offerId: uuid.optional() }).strict();
// Facturation : mêmes bornes que l'API, qui relit l'IBAN (clé de contrôle), la TVA, les dates et chaque état de document.
const issuerCommand = z.object({ operationId: uuid, version: versionField,
  legalName: z.string().trim().min(1).max(150), street: z.string().trim().min(1).max(200), buildingNumber: z.string().trim().min(1).max(16).nullable(),
  accountHolder: z.string().trim().min(1).max(70).nullable(), postalCode: z.string().trim().min(1).max(20),
  city: z.string().trim().min(1).max(100), country: z.string().trim().toUpperCase().regex(/^[A-Z]{2}$/),
  email: z.string().trim().max(254).transform(value => value.toLowerCase()).pipe(z.email()).nullable(),
  iban: z.string().max(42).transform(value => value.replace(/\s+/g, '').toUpperCase()).pipe(z.string().regex(/^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$/)).nullable(),
  taxMode: z.enum(['NONE', 'VAT']), vatNumber: z.string().trim().max(40).nullable(), taxRateBp: z.number().int().min(1).max(5000).nullable(),
  pricesIncludeTax: z.boolean().nullable(), taxNote: z.string().trim().min(3).max(200).nullable() }).strict();
const activationCommand = z.object({ operationId: uuid, version: versionField, startsOn: day, confirm: z.literal(true) }).strict();
const activationStopCommand = z.object({ operationId: uuid, version: versionField, reason: commercialReason }).strict();
const prepareCommand = z.object({ operationId: uuid, version: versionField, kind: z.enum(['INITIAL', 'PERIOD']), periodStart: day.optional() }).strict()
  .refine(body => (body.kind === 'PERIOD') === (body.periodStart !== undefined));
const issueCommand = z.object({ operationId: uuid, version: versionField, confirm: z.literal(true) }).strict();
const cancelDraftCommand = z.object({ operationId: uuid, version: versionField, reason: commercialReason }).strict();
const creditCommand = z.object({ operationId: uuid, version: versionField, reason: commercialReason, confirm: z.literal(true) }).strict();
const sentCommand = z.object({ operationId: uuid, version: versionField, sentOn: day }).strict();
const documentCommand = z.object({ operationId: uuid, version: versionField }).strict();
const deliveryCommand = z.object({ operationId: uuid, version: versionField, confirm: z.literal(true), resend: z.boolean() }).strict();
const documentParams = z.object({ revision: z.string().regex(/^[1-9][0-9]?$/).transform(Number).pipe(z.number().max(20)).optional() }).strict();
// Règlements : mêmes bornes que l'API, qui relit la devise, la date, l'école de chaque facture et le reste disponible.
const paymentAmount = z.number().int().min(1).max(100_000_000);
const paymentFields = { operationId: uuid, version: versionField, amount: paymentAmount, currency: z.string().trim().toUpperCase().regex(/^[A-Z]{3}$/), receivedOn: day,
  method: z.enum(paymentMethods), reference: z.string().trim().max(140).nullable(), note: z.string().trim().max(500).nullable() };
const lowerUuid = uuid.transform(value => value.toLowerCase());
const paymentCommand = z.object({ ...paymentFields, allocations: z.array(z.object({ invoiceId: lowerUuid, amount: paymentAmount }).strict()).max(50), spread: z.boolean(),
  confirmDuplicate: z.boolean() }).strict();
const allocateCommand = z.object({ operationId: uuid, version: versionField, invoiceId: lowerUuid, amount: paymentAmount }).strict();
const paymentReasonCommand = z.object({ operationId: uuid, version: versionField, reason: commercialReason }).strict();
const voidPaymentCommand = z.object({ operationId: uuid, version: versionField, reason: commercialReason, confirm: z.literal(true) }).strict();
const correctPaymentCommand = z.object({ ...paymentFields, reason: commercialReason }).strict();
const regularizeCommand = z.object({ operationId: uuid, version: versionField, amount: paymentAmount, kind: z.enum(['REFUND_RECORDED', 'OTHER']), reason: commercialReason }).strict();
const optionalDay = z.preprocess(value => (value === '' ? undefined : value), day.optional());
const invoiceListParams = z.object({ clientId: uuid.optional(), status: z.enum(invoiceStatuses).optional(), kind: z.enum(invoiceKinds).optional(),
  sendStatus: z.enum(sendStatuses).optional(), settlement: z.enum(settlementStates).optional(), from: optionalDay, to: optionalDay, dueBefore: optionalDay, overdue: z.enum(['true']).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(), offset: z.coerce.number().int().min(0).max(100_000).optional() }).strict();
const searchOf = (parameters: Record<string, string | number | undefined>) => {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(parameters)) if (value !== undefined && value !== '') search.set(key, String(value));
  const queryText = search.toString();
  return queryText ? `?${queryText}` : '';
};
const digestOf = (data: unknown) => createHash('sha256').update(JSON.stringify(data)).digest('hex');
/** Refus définitifs d'une acceptation : le code ne servira plus, l'état est abandonné. 403 et 429 laissent corriger puis reprendre. */
const terminalJoinStatuses = new Set([404, 409, 410]);

export function registerPlatformRoutes(app: FastifyInstance, deps: {
  origin?: string; current: (req: FastifyRequest) => Session; protect: (req: FastifyRequest) => Session;
  call: (session: Session, command: PlatformRequest) => Promise<ApiResult>; send: (reply: FastifyReply, result: ApiResult) => unknown;
  document: (session: Session, request: PlatformDocumentRequest) => Promise<PlatformDocumentResult>;
  error: (status: number, code: string) => Error;
}) {
  const failureCode = (result: ApiResult) => z.object({ code: z.string().regex(/^[A-Z0-9_]{1,80}$/) }).safeParse(result.body);
  /** Un compte qui n'est plus opérateur perd sur-le-champ ce que le relais gardait pour lui. */
  const refused = (session: Session, result: ApiResult) => {
    const code = failureCode(result);
    if (result.status === 403 && code.success && code.data.code === 'PLATFORM_OPERATOR_REQUIRED') { delete session.platformInvite; delete session.platformCode; }
  };
  const relay = async <S extends z.ZodType>(reply: FastifyReply, session: Session, command: PlatformRequest, schema: S): Promise<z.infer<S>> => {
    const result = await deps.call(session, command);
    if (result.status >= 400) { refused(session, result); return deps.send(reply, result) as never; }
    const parsed = schema.safeParse(result.body);
    if (!parsed.success) throw deps.error(503, 'INVALID_RESPONSE');
    reply.status(result.status);
    return parsed.data;
  };
  const read = (path: string, schema: z.ZodType) => async (request: FastifyRequest, reply: FastifyReply) => {
    empty.parse(request.query);
    return relay(reply, deps.current(request), { method: 'GET', path }, schema);
  };

  app.get('/app/bff/platform/me', read('/v1/platform/me', meResult));
  app.get('/app/bff/platform/operators', read('/v1/platform/operators', operatorsResult));
  app.get('/app/bff/platform/invitations', async (request, reply) => {
    empty.parse(request.query);
    const session = deps.current(request);
    const listing = await relay(reply, session, { method: 'GET', path: '/v1/platform/invitations' }, invitationsResult);
    // Une invitation créée dont le code n'a pas été transmis : l'identifiant d'opération suffit à la reprendre, jamais le code.
    const pending = session.platformInvite;
    return { ...listing, ...(pending ? { pending: { operationId: pending.operationId, email: pending.email, ...(pending.validityDays ? { validityDays: pending.validityDays } : {}) } } : {}) };
  });
  app.get('/app/bff/platform/journal', async (request, reply) => {
    const query = journalParams.parse(request.query);
    const search = new URLSearchParams();
    if (query.limit !== undefined) search.set('limit', String(query.limit));
    if (query.cursor !== undefined) search.set('cursor', query.cursor);
    if (query.schoolId !== undefined) search.set('schoolId', query.schoolId.toLowerCase());
    if (query.result !== undefined) search.set('result', query.result);
    const text = search.toString();
    return relay(reply, deps.current(request), { method: 'GET', path: `/v1/platform/journal${text ? `?${text}` : ''}` }, journalResult);
  });
  app.get('/app/bff/platform/operations/:operationId', async (request, reply) => {
    empty.parse(request.query);
    const { operationId } = z.object({ operationId: uuid }).parse(request.params);
    return relay(reply, deps.current(request), { method: 'GET', path: `/v1/platform/operations/${operationId.toLowerCase()}` }, operationResult);
  });

  // Émission : le code est tiré ici, transmis à l'API qui n'en garde que l'empreinte, et rendu une fois à l'opérateur qui l'a demandé.
  app.post('/app/bff/platform/invitations', async (request, reply) => {
    empty.parse(request.query);
    const body = inviteBody.parse(request.body);
    const session = deps.protect(request);
    const previous = session.platformInvite;
    if (previous && previous.operationId !== body.operationId) throw deps.error(409, 'PLATFORM_INVITE_IN_PROGRESS');
    if (previous && (previous.email !== body.email || previous.validityDays !== body.validityDays)) throw deps.error(409, 'IDEMPOTENCY_MISMATCH');
    if (previous?.busy) throw deps.error(409, 'PLATFORM_INVITE_IN_PROGRESS');
    const state: PlatformInviteState = previous ?? { operationId: body.operationId, email: body.email, code: platformInvitationCode(),
      ...(body.validityDays !== undefined ? { validityDays: body.validityDays } : {}) };
    session.platformInvite = state; state.busy = true;
    try {
      const result = await deps.call(session, { method: 'POST', path: '/v1/platform/invitations', idempotencyKey: body.operationId,
        body: { operationId: body.operationId, code: state.code, email: body.email, ...(body.validityDays !== undefined ? { validityDays: body.validityDays } : {}) } });
      if (result.status >= 400) {
        // Un refus définitif libère l'émission (un nouveau code sera tiré) ; une panne du service garde le même code pour la reprise.
        if (result.status < 500 && session.platformInvite === state) delete session.platformInvite;
        refused(session, result);
        return deps.send(reply, result);
      }
      const parsed = invitationResult.safeParse(result.body);
      if (!parsed.success) throw deps.error(503, 'INVALID_RESPONSE');
      reply.status(result.status);
      return { ...parsed.data, code: state.code };
    } finally { delete state.busy; }
  });
  app.post('/app/bff/platform/invitations/clear', async request => {
    empty.parse(request.query); empty.parse(request.body);
    const session = deps.protect(request);
    if (session.platformInvite?.busy) throw deps.error(409, 'PLATFORM_INVITE_IN_PROGRESS');
    delete session.platformInvite;
    return { ok: true };
  });
  app.post('/app/bff/platform/invitations/:id/revoke', async (request, reply) => {
    empty.parse(request.query);
    const { id } = z.object({ id: uuid }).parse(request.params);
    const body = revokeBody.parse(request.body);
    return relay(reply, deps.protect(request), { method: 'POST', path: `/v1/platform/invitations/${id.toLowerCase()}/revoke`,
      body: { operationId: body.operationId }, idempotencyKey: body.operationId, ifMatch: `"${body.version}"` }, invitationResult);
  });
  app.post('/app/bff/platform/operators/:id/revoke', async (request, reply) => {
    empty.parse(request.query);
    const { id } = z.object({ id: uuid }).parse(request.params);
    const body = revokeBody.parse(request.body);
    const session = deps.protect(request);
    const result = await relay(reply, session, { method: 'POST', path: `/v1/platform/operators/${id.toLowerCase()}/revoke`,
      body: { operationId: body.operationId }, idempotencyKey: body.operationId, ifMatch: `"${body.version}"` }, operatorResult);
    // Un opérateur qui se retire perd aussi le code d'invitation que ce relais gardait pour lui.
    if (result.data.self) { delete session.platformInvite; delete session.platformCode; }
    return result;
  });

  // --- Écoles clientes et codes d'ouverture (R01-T02) ---
  app.get('/app/bff/platform/clients', async (request, reply) => {
    const query = clientListParams.parse(request.query);
    return relay(reply, deps.current(request), { method: 'GET', path: `/v1/platform/clients${searchOf({ limit: query.limit, cursor: query.cursor, q: query.q, preparation: query.preparation })}` }, clientsResult);
  });
  app.get('/app/bff/platform/clients/:id', async (request, reply) => {
    empty.parse(request.query);
    const { id } = z.object({ id: uuid }).parse(request.params);
    return relay(reply, deps.current(request), { method: 'GET', path: `/v1/platform/clients/${id.toLowerCase()}` }, clientResult);
  });
  app.get('/app/bff/platform/unattached-schools', async (request, reply) => {
    const query = unattachedParams.parse(request.query);
    return relay(reply, deps.current(request), { method: 'GET', path: `/v1/platform/unattached-schools${searchOf({ limit: query.limit, q: query.q })}` }, unattachedResult);
  });
  app.get('/app/bff/platform/school-codes', async (request, reply) => {
    const query = codeListParams.parse(request.query);
    return relay(reply, deps.current(request), { method: 'GET', path: `/v1/platform/school-codes${searchOf({ limit: query.limit, cursor: query.cursor, clientId: query.clientId?.toLowerCase(), state: query.state })}` }, codesResult);
  });
  // Les notes internes vont jusqu'à 4 000 caractères : la limite de 2 Kio du relais ne suffirait pas à les porter.
  app.post('/app/bff/platform/clients', { bodyLimit: FICHE_BODY_LIMIT }, async (request, reply) => {
    empty.parse(request.query);
    const { operationId, schoolId, ...content } = createClientBody.parse(request.body);
    return relay(reply, deps.protect(request), { method: 'POST', path: '/v1/platform/clients', idempotencyKey: operationId,
      body: { operationId, ...content, ...(schoolId ? { schoolId: schoolId.toLowerCase() } : {}) } }, clientResult);
  });
  // Le navigateur ne connaît que POST : la modification versionnée devient un PATCH ici, sous la version qu'il a lue.
  app.post('/app/bff/platform/clients/:id/update', { bodyLimit: FICHE_BODY_LIMIT }, async (request, reply) => {
    empty.parse(request.query);
    const { id } = z.object({ id: uuid }).parse(request.params);
    const { version, ...body } = updateClientBody.parse(request.body);
    return relay(reply, deps.protect(request), { method: 'PATCH', path: `/v1/platform/clients/${id.toLowerCase()}`, idempotencyKey: body.operationId,
      ifMatch: `"${version}"`, body }, clientResult);
  });
  app.post('/app/bff/platform/clients/:id/attach-school', async (request, reply) => {
    empty.parse(request.query);
    const { id } = z.object({ id: uuid }).parse(request.params);
    const { version, ...body } = attachBody.parse(request.body);
    return relay(reply, deps.protect(request), { method: 'POST', path: `/v1/platform/clients/${id.toLowerCase()}/attach-school`, idempotencyKey: body.operationId,
      ifMatch: `"${version}"`, body: { ...body, schoolId: body.schoolId.toLowerCase() } }, clientResult);
  });

  // --- Offres et droits aux modules (R01-T03) : le relais borne les formes, l'API relit chaque droit et chaque version. ---
  app.get('/app/bff/platform/modules', read('/v1/platform/modules', modulesResult));
  app.get('/app/bff/platform/offers', async (request, reply) => {
    const query = offerListParams.parse(request.query);
    return relay(reply, deps.current(request), { method: 'GET', path: `/v1/platform/offers${searchOf({ status: query.status })}` }, offersResult);
  });
  app.post('/app/bff/platform/offers', async (request, reply) => {
    empty.parse(request.query);
    const body = createOfferBody.parse(request.body);
    return relay(reply, deps.protect(request), { method: 'POST', path: '/v1/platform/offers', idempotencyKey: body.operationId, body }, offerResult);
  });
  app.post('/app/bff/platform/offers/:id/update', async (request, reply) => {
    empty.parse(request.query);
    const { id } = z.object({ id: uuid }).parse(request.params);
    const { version, ...body } = updateOfferBody.parse(request.body);
    return relay(reply, deps.protect(request), { method: 'PATCH', path: `/v1/platform/offers/${id.toLowerCase()}`, idempotencyKey: body.operationId,
      ifMatch: `"${version}"`, body }, offerResult);
  });
  for (const change of ['archive', 'restore'] as const) {
    app.post(`/app/bff/platform/offers/:id/${change}`, async (request, reply) => {
      empty.parse(request.query);
      const { id } = z.object({ id: uuid }).parse(request.params);
      const body = revokeBody.parse(request.body);
      return relay(reply, deps.protect(request), { method: 'POST', path: `/v1/platform/offers/${id.toLowerCase()}/${change}`,
        body: { operationId: body.operationId }, idempotencyKey: body.operationId, ifMatch: `"${body.version}"` }, offerResult);
    });
  }
  app.get('/app/bff/platform/clients/:id/entitlements', async (request, reply) => {
    empty.parse(request.query);
    const { id } = z.object({ id: uuid }).parse(request.params);
    return relay(reply, deps.current(request), { method: 'GET', path: `/v1/platform/clients/${id.toLowerCase()}/entitlements` }, entitlementsResult);
  });
  app.get('/app/bff/platform/clients/:id/assignment-preview', async (request, reply) => {
    const { id } = z.object({ id: uuid }).parse(request.params);
    const query = previewParams.parse(request.query);
    return relay(reply, deps.current(request), { method: 'GET', path: `/v1/platform/clients/${id.toLowerCase()}/assignment-preview${searchOf({ offerId: query.offerId.toLowerCase(), effectiveAt: query.effectiveAt })}` }, previewConsequencesResult);
  });
  app.post('/app/bff/platform/clients/:id/assignments', async (request, reply) => {
    empty.parse(request.query);
    const { id } = z.object({ id: uuid }).parse(request.params);
    const { version, ...body } = assignBody.parse(request.body);
    return relay(reply, deps.protect(request), { method: 'POST', path: `/v1/platform/clients/${id.toLowerCase()}/assignments`, idempotencyKey: body.operationId,
      ifMatch: `"${version}"`, body: { ...body, offerId: body.offerId.toLowerCase() } }, entitlementsResult);
  });
  app.post('/app/bff/platform/clients/:id/assignments/:assignmentId/cancel', async (request, reply) => {
    empty.parse(request.query);
    const { id, assignmentId } = z.object({ id: uuid, assignmentId: uuid }).parse(request.params);
    const body = revokeBody.parse(request.body);
    return relay(reply, deps.protect(request), { method: 'POST', path: `/v1/platform/clients/${id.toLowerCase()}/assignments/${assignmentId.toLowerCase()}/cancel`,
      body: { operationId: body.operationId }, idempotencyKey: body.operationId, ifMatch: `"${body.version}"` }, entitlementsResult);
  });
  app.post('/app/bff/platform/clients/:id/adjustments', async (request, reply) => {
    empty.parse(request.query);
    const { id } = z.object({ id: uuid }).parse(request.params);
    const { version, ...body } = adjustBody.parse(request.body);
    return relay(reply, deps.protect(request), { method: 'POST', path: `/v1/platform/clients/${id.toLowerCase()}/adjustments`, idempotencyKey: body.operationId,
      ifMatch: `"${version}"`, body }, entitlementsResult);
  });
  app.post('/app/bff/platform/clients/:id/adjustments/:adjustmentId/lift', async (request, reply) => {
    empty.parse(request.query);
    const { id, adjustmentId } = z.object({ id: uuid, adjustmentId: uuid }).parse(request.params);
    const { version, ...body } = liftBody.parse(request.body);
    return relay(reply, deps.protect(request), { method: 'POST', path: `/v1/platform/clients/${id.toLowerCase()}/adjustments/${adjustmentId.toLowerCase()}/lift`,
      idempotencyKey: body.operationId, ifMatch: `"${version}"`, body }, entitlementsResult);
  });

  // --- Dossier commercial (R01-T04) : lecture, puis commandes sous la version du dossier. Les identifiants partent en minuscules. ---
  app.get('/app/bff/platform/clients/:id/commercial', async (request, reply) => {
    empty.parse(request.query);
    const { id } = z.object({ id: uuid }).parse(request.params);
    return relay(reply, deps.current(request), { method: 'GET', path: `/v1/platform/clients/${id.toLowerCase()}/commercial` }, commercialResult);
  });
  const lowerIds = (body: Record<string, unknown>) => Object.fromEntries(Object.entries(body).map(([key, value]) =>
    [key, (key === 'requestedOfferId' || key === 'offerId') && typeof value === 'string' ? value.toLowerCase() : value]));
  const commercialCommands: Array<[string, z.ZodType<{ operationId: string; version: number }>]> = [
    ['terms', termsCommand], ['trial/start', trialStartCommand], ['trial/extend', trialExtendCommand], ['trial/end', trialEndCommand],
    ['paid-start', paidStartCommand], ['paid-start/cancel', paidStartCancelCommand], ['requests', requestCommand],
  ];
  for (const [path, schema] of commercialCommands) {
    app.post(`/app/bff/platform/clients/:id/commercial/${path}`, async (request, reply) => {
      empty.parse(request.query);
      const { id } = z.object({ id: uuid }).parse(request.params);
      const { version, ...body } = schema.parse(request.body);
      return relay(reply, deps.protect(request), { method: 'POST', path: `/v1/platform/clients/${id.toLowerCase()}/commercial/${path}`,
        idempotencyKey: body.operationId, ifMatch: `"${version}"`, body: lowerIds(body) }, commercialResult);
    });
  }
  app.post('/app/bff/platform/clients/:id/commercial/requests/:requestId/decision', async (request, reply) => {
    empty.parse(request.query);
    const { id, requestId } = z.object({ id: uuid, requestId: uuid }).parse(request.params);
    const { version, ...body } = decisionCommand.parse(request.body);
    return relay(reply, deps.protect(request), { method: 'POST', path: `/v1/platform/clients/${id.toLowerCase()}/commercial/requests/${requestId.toLowerCase()}/decision`,
      idempotencyKey: body.operationId, ifMatch: `"${version}"`, body: lowerIds(body) }, commercialResult);
  });

  // --- Facturation (R01-T05) : l'émetteur, la liste de toutes les factures, le passage manuel, puis la facturation d'une fiche. ---
  app.get('/app/bff/platform/billing/issuer', read('/v1/platform/billing/issuer', issuerSettingsResult));
  app.post('/app/bff/platform/billing/issuer', async (request, reply) => {
    empty.parse(request.query);
    const { version, ...body } = issuerCommand.parse(request.body);
    return relay(reply, deps.protect(request), { method: 'POST', path: '/v1/platform/billing/issuer', idempotencyKey: body.operationId,
      ifMatch: `"${version}"`, body }, issuerSettingsResult);
  });
  app.get('/app/bff/platform/invoices', async (request, reply) => {
    const query = invoiceListParams.parse(request.query);
    return relay(reply, deps.current(request), { method: 'GET', path: `/v1/platform/invoices${searchOf({ ...query, clientId: query.clientId?.toLowerCase() })}` },
      invoicePageResult);
  });
  app.get('/app/bff/platform/invoices/:invoiceId', async (request, reply) => {
    empty.parse(request.query);
    const { invoiceId } = z.object({ invoiceId: uuid }).parse(request.params);
    return relay(reply, deps.current(request), { method: 'GET', path: `/v1/platform/invoices/${invoiceId.toLowerCase()}` }, invoiceResult);
  });
  app.post('/app/bff/platform/billing/run', async (request, reply) => {
    empty.parse(request.query);
    const body = codeRevokeBody.parse(request.body);
    return relay(reply, deps.protect(request), { method: 'POST', path: '/v1/platform/billing/run', idempotencyKey: body.operationId, body }, billingRunResult);
  });
  app.get('/app/bff/platform/clients/:id/billing', async (request, reply) => {
    empty.parse(request.query);
    const { id } = z.object({ id: uuid }).parse(request.params);
    return relay(reply, deps.current(request), { method: 'GET', path: `/v1/platform/clients/${id.toLowerCase()}/billing` }, billingResult);
  });
  const billingCommands: Array<[string, z.ZodType<{ operationId: string; version: number }>]> = [
    ['billing/activation', activationCommand], ['billing/activation/stop', activationStopCommand], ['invoices', prepareCommand],
  ];
  for (const [path, schema] of billingCommands) {
    app.post(`/app/bff/platform/clients/:id/${path}`, async (request, reply) => {
      empty.parse(request.query);
      const { id } = z.object({ id: uuid }).parse(request.params);
      const { version, ...body } = schema.parse(request.body);
      return relay(reply, deps.protect(request), { method: 'POST', path: `/v1/platform/clients/${id.toLowerCase()}/${path}`,
        idempotencyKey: body.operationId, ifMatch: `"${version}"`, body }, billingResult);
    });
  }
  const invoiceCommands: Array<[string, z.ZodType<{ operationId: string; version: number }>]> = [
    ['issue', issueCommand], ['cancel', cancelDraftCommand], ['credit', creditCommand], ['sent', sentCommand], ['document', documentCommand], ['delivery', deliveryCommand],
  ];
  for (const [path, schema] of invoiceCommands) {
    app.post(`/app/bff/platform/clients/:id/invoices/:invoiceId/${path}`, async (request, reply) => {
      empty.parse(request.query);
      const { id, invoiceId } = z.object({ id: uuid, invoiceId: uuid }).parse(request.params);
      const { version, ...body } = schema.parse(request.body);
      return relay(reply, deps.protect(request), { method: 'POST', path: `/v1/platform/clients/${id.toLowerCase()}/invoices/${invoiceId.toLowerCase()}/${path}`,
        idempotencyKey: body.operationId, ifMatch: `"${version}"`, body }, billingResult);
    });
  }
  // PDF et envoi (R01-T07) : l'API relit l'école, l'opérateur et la facture ; le PDF n'a aucune adresse publique et ne reste pas dans le relais.
  app.get('/app/bff/platform/clients/:id/invoices/:invoiceId/delivery/preview', async (request, reply) => {
    empty.parse(request.query);
    const { id, invoiceId } = z.object({ id: uuid, invoiceId: uuid }).parse(request.params);
    return relay(reply, deps.current(request), { method: 'GET', path: `/v1/platform/clients/${id.toLowerCase()}/invoices/${invoiceId.toLowerCase()}/delivery/preview` }, deliveryPreviewResult);
  });
  app.get('/app/bff/platform/clients/:id/invoices/:invoiceId/document', async (request, reply) => {
    const { revision } = documentParams.parse(request.query);
    const { id, invoiceId } = z.object({ id: uuid, invoiceId: uuid }).parse(request.params);
    const session = deps.current(request);
    const result = await deps.document(session, { clientId: id.toLowerCase(), invoiceId: invoiceId.toLowerCase(), ...(revision === undefined ? {} : { revision }) });
    if ('pdf' in result) return reply.status(200).header('content-type', 'application/pdf').header('content-disposition', result.disposition).send(result.pdf);
    if (result.status < 400) throw deps.error(503, 'INVALID_RESPONSE');
    refused(session, result);
    return deps.send(reply, result);
  });
  // Règlements (R01-T06) : chaque commande part sous la version de facturation et rend la facturation relue ; rien n'est calculé ici.
  const paymentCommands: Array<[string, z.ZodType<{ operationId: string; version: number }>]> = [
    ['payments', paymentCommand], ['payments/:paymentId/allocations', allocateCommand], ['payments/:paymentId/allocations/:allocationId/release', paymentReasonCommand],
    ['payments/:paymentId/void', voidPaymentCommand], ['payments/:paymentId/correct', correctPaymentCommand], ['payments/:paymentId/regularizations', regularizeCommand],
    ['payments/:paymentId/regularizations/:regularizationId/cancel', paymentReasonCommand],
  ];
  for (const [path, schema] of paymentCommands) {
    app.post(`/app/bff/platform/clients/:id/${path}`, async (request, reply) => {
      empty.parse(request.query);
      const params = z.record(z.string(), uuid).parse(request.params);
      const target = path.replace(/:([A-Za-z]+)/g, (_match, name: string) => params[name]!.toLowerCase());
      const { version, ...body } = schema.parse(request.body);
      return relay(reply, deps.protect(request), { method: 'POST', path: `/v1/platform/clients/${params.id!.toLowerCase()}/${target}`,
        idempotencyKey: body.operationId, ifMatch: `"${version}"`, body }, billingResult);
    });
  }

  // « Créer un code » : le code est tiré ici, transmis à l'API qui n'en garde que l'empreinte à clé serveur, et rendu à l'opérateur qui l'a demandé.
  // Une coupure garde le même code pour la même opération ; un refus définitif libère l'émission, un autre code sera tiré.
  app.get('/app/bff/platform/school-codes/pending', async request => {
    empty.parse(request.query);
    const pending = deps.current(request).platformCode;
    return { pending: pending ? { operationId: pending.operationId, ...(pending.clientId ? { clientId: pending.clientId } : {}),
      ...(pending.displayName ? { displayName: pending.displayName } : {}), ...(pending.validityDays ? { validityDays: pending.validityDays } : {}) } : null };
  });
  app.post('/app/bff/platform/school-codes', async (request, reply) => {
    empty.parse(request.query);
    const body = issueCodeBody.parse(request.body);
    const content = { ...(body.clientId ? { clientId: body.clientId.toLowerCase() } : {}), ...(body.displayName ? { displayName: body.displayName } : {}),
      ...(body.validityDays !== undefined ? { validityDays: body.validityDays } : {}) };
    const session = deps.protect(request);
    const previous = session.platformCode;
    if (previous && previous.operationId !== body.operationId) throw deps.error(409, 'PLATFORM_CODE_IN_PROGRESS');
    if (previous && JSON.stringify({ clientId: previous.clientId, displayName: previous.displayName, validityDays: previous.validityDays })
      !== JSON.stringify({ clientId: content.clientId, displayName: content.displayName, validityDays: content.validityDays })) throw deps.error(409, 'IDEMPOTENCY_MISMATCH');
    if (previous?.busy) throw deps.error(409, 'PLATFORM_CODE_IN_PROGRESS');
    const state: PlatformCodeState = previous ?? { operationId: body.operationId, ...content, code: openingCode() };
    session.platformCode = state; state.busy = true;
    try {
      const result = await deps.call(session, { method: 'POST', path: '/v1/platform/school-codes', idempotencyKey: body.operationId,
        body: { operationId: body.operationId, code: state.code, ...content } });
      if (result.status >= 400) {
        if (result.status < 500 && session.platformCode === state) delete session.platformCode;
        refused(session, result);
        return deps.send(reply, result);
      }
      const parsed = issuedCodeResult.safeParse(result.body);
      if (!parsed.success) throw deps.error(503, 'INVALID_RESPONSE');
      reply.status(result.status);
      return { ...parsed.data, code: state.code, ...(deps.origin ? { link: `${deps.origin}/app/ouvrir#token=${state.code}` } : {}) };
    } finally { delete state.busy; }
  });
  app.post('/app/bff/platform/school-codes/clear', async request => {
    empty.parse(request.query); empty.parse(request.body);
    const session = deps.protect(request);
    if (session.platformCode?.busy) throw deps.error(409, 'PLATFORM_CODE_IN_PROGRESS');
    delete session.platformCode;
    return { ok: true };
  });
  app.post('/app/bff/platform/school-codes/:id/revoke', async (request, reply) => {
    empty.parse(request.query);
    const { id } = z.object({ id: uuid }).parse(request.params);
    const body = codeRevokeBody.parse(request.body);
    return relay(reply, deps.protect(request), { method: 'POST', path: `/v1/platform/school-codes/${id.toLowerCase()}/revoke`, idempotencyKey: body.operationId, body }, codeResult);
  });

  // --- Acceptation : le porteur d'un code voit ses droits, confirme, puis le serveur confirme à son tour. ---
  const signedIn = (session: Session) => {
    if (!session.tokens) throw deps.error(401, 'SESSION_EXPIRED');
    return session.tokens.principal.subject;
  };
  const joinOf = (session: Session) => {
    const identity = signedIn(session);
    const join = session.platformJoin;
    if (!join) throw deps.error(404, 'PLATFORM_JOIN_MISSING');
    if (join.identity !== identity) throw deps.error(409, 'PLATFORM_IDENTITY_CHANGED');
    return join;
  };
  const previewCode = async (session: Session, code: string): Promise<{ result: ApiResult; parsed: ReturnType<typeof previewResult.safeParse> }> => {
    const result = await deps.call(session, { method: 'POST', path: '/v1/platform/invitations/preview', body: { code } });
    return { result, parsed: previewResult.safeParse(result.body) };
  };
  app.post('/app/bff/platform/join/preview', async (request, reply) => {
    empty.parse(request.query);
    const { code } = z.object({ code: platformCodeSchema }).strict().parse(request.body);
    const session = deps.protect(request);
    const identity = signedIn(session);
    const known = session.platformJoin?.identity === identity ? session.platformJoin : undefined;
    if (known && (known.busy || (known.submitted && !known.accepted)) && known.code !== code) throw deps.error(409, 'PLATFORM_JOIN_IN_PROGRESS');
    if (known?.busy) throw deps.error(409, 'PLATFORM_JOIN_IN_PROGRESS');
    const { result, parsed } = await previewCode(session, code);
    if (result.status >= 400) {
      // Un code refusé ne laisse aucune trace : seul un état déjà soumis, dont le résultat reste à établir, est gardé.
      if (known && !known.submitted && terminalJoinStatuses.has(result.status)) delete session.platformJoin;
      return deps.send(reply, result);
    }
    if (!parsed.success) throw deps.error(503, 'INVALID_RESPONSE');
    const join: PlatformJoinState = known && known.code === code ? known : { identity, operationId: randomUUID(), code };
    join.code = code;
    const confirmation = { id: randomBytes(24).toString('base64url'), digest: digestOf(parsed.data.data) };
    if (!join.submitted) join.confirmation = confirmation;
    session.platformJoin = join;
    reply.status(200);
    return { ...parsed.data, confirmation: confirmation.id };
  });
  app.get('/app/bff/platform/join', async request => {
    empty.parse(request.query);
    const session = deps.current(request);
    const join = session.platformJoin;
    if (!join || join.identity !== signedIn(session)) return { pending: false, uncertain: false, accepted: false };
    return { pending: !join.accepted, uncertain: !!join.uncertain, accepted: !!join.accepted };
  });
  app.post('/app/bff/platform/join/accept', async (request, reply) => {
    empty.parse(request.query);
    const { confirmation } = z.object({ confirmation: z.string().max(100).optional() }).strict().parse(request.body);
    const session = deps.protect(request);
    const join = joinOf(session);
    if (join.accepted) return { data: join.accepted };
    if (join.busy) throw deps.error(409, 'PLATFORM_JOIN_IN_PROGRESS');
    if (!join.code) throw deps.error(404, 'PLATFORM_JOIN_MISSING');
    join.busy = true;
    try {
      if (!join.submitted) {
        // Premier envoi seulement : la confirmation porte sur les droits montrés. Une reprise renvoie la même demande, sans nouvelle lecture.
        if (!join.confirmation || !matchesSecret(confirmation, join.confirmation.id)) throw deps.error(409, 'PLATFORM_PREVIEW_CHANGED');
        const { result, parsed } = await previewCode(session, join.code);
        if (result.status >= 400) {
          if (terminalJoinStatuses.has(result.status)) delete session.platformJoin;
          return deps.send(reply, result);
        }
        if (!parsed.success) throw deps.error(503, 'INVALID_RESPONSE');
        if (digestOf(parsed.data.data) !== join.confirmation.digest) { delete join.confirmation; throw deps.error(409, 'PLATFORM_PREVIEW_CHANGED'); }
        join.submitted = true;
      }
      const result = await deps.call(session, { method: 'POST', path: '/v1/platform/invitations/accept', idempotencyKey: join.operationId,
        body: { operationId: join.operationId, code: join.code } });
      if (result.status >= 400) {
        if (result.status >= 500) { join.uncertain = true; return deps.send(reply, result); }
        // Refus définitif de l'API : pas de reçu, donc rien à reprendre. L'aperçu devra être confirmé de nouveau.
        delete join.submitted; delete join.confirmation; delete join.uncertain;
        if (terminalJoinStatuses.has(result.status) && session.platformJoin === join) delete session.platformJoin;
        return deps.send(reply, result);
      }
      const parsed = acceptedResult.safeParse(result.body);
      if (!parsed.success) { join.uncertain = true; throw deps.error(503, 'INVALID_RESPONSE'); }
      join.accepted = parsed.data.data;
      delete join.code; delete join.confirmation; delete join.uncertain;
      reply.status(result.status);
      return parsed.data;
    } catch (error) {
      // Rien ne dit si l'API a validé avant la coupure : seule la même demande, rejouée, le tranche.
      if (join.submitted && !join.accepted) join.uncertain = true;
      throw error;
    } finally { delete join.busy; }
  });
}
