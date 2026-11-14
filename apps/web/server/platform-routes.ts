import { createHash, randomBytes, randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { matchesSecret, type Session } from './session.js';
import { openingCode } from './opening-routes.js';
import type { ApiResult } from './upstream.js';

/**
 * Console des opérateurs de la plateforme (R01-T01, R01-T02). Le navigateur ne parle qu'à ce relais : il ne connaît ni l'API, ni
 * un jeton, ni l'empreinte d'un code. Les droits sont relus par l'API à chaque appel ; ce relais ne décide de rien.
 */
export type PlatformRequest = { method: 'GET' | 'POST' | 'PATCH'; path: string; body?: unknown; idempotencyKey?: string; ifMatch?: string };
export type PlatformGateway = (command: PlatformRequest, accessToken: string) => Promise<ApiResult>;

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

export const clientPreparations = ['AWAITING_SCHOOL', 'IN_PREPARATION', 'ACTIVE', 'ARCHIVED'] as const;
export const codeStates = ['AVAILABLE', 'USED', 'EXPIRED', 'REVOKED'] as const;
export const offerStatuses = ['ACTIVE', 'ARCHIVED'] as const;

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
    return query === '' && (staticReads.has(path) || operationPath.test(path) || clientPath.test(path) || entitlementsPath.test(path));
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
    || adjustmentLiftPath.test(path)) return keyed && versioned;
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
/** L'emplacement commercial reste tolérant sur `dueDates` : le lot des conditions (#456) y ajoute ses échéances sans changer cette forme. */
const commercialSchema = z.object({ state: token, offer: offerBriefSchema.nullable(), scheduledOffer: offerBriefSchema.nullable(),
  entitlementVersion: z.number().int().min(1), dueDates: z.array(z.unknown()).max(50) });
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
