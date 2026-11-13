import { createHash, randomBytes, randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { matchesSecret, type Session } from './session.js';
import type { ApiResult } from './upstream.js';

/**
 * Console des opérateurs de la plateforme (R01-T01). Le navigateur ne parle qu'à ce relais : il ne connaît ni l'API, ni
 * un jeton, ni l'empreinte d'un code. Les droits sont relus par l'API à chaque appel ; ce relais ne décide de rien.
 */
export type PlatformRequest = { method: 'GET' | 'POST'; path: string; body?: unknown; idempotencyKey?: string; ifMatch?: string };
export type PlatformGateway = (command: PlatformRequest, accessToken: string) => Promise<ApiResult>;

const uuidPath = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const strongVersion = /^"[1-9][0-9]{0,9}"$/;
const staticReads = new Set(['/v1/platform/me', '/v1/platform/operators', '/v1/platform/invitations']);
const operationPath = new RegExp(`^/v1/platform/operations/${uuidPath}$`);
const revokePath = new RegExp(`^/v1/platform/(?:invitations|operators)/${uuidPath}/revoke$`);

function validJournalQuery(query: string): boolean {
  if (query === '') return true;
  const seen = new Set<string>();
  for (const [key, value] of new URLSearchParams(query)) {
    if (seen.has(key)) return false;
    seen.add(key);
    if (key === 'limit') { if (!/^[1-9][0-9]{0,2}$/.test(value) || Number(value) > 100) return false; }
    else if (key === 'cursor') { if (!/^[A-Za-z0-9_-]{1,6000}$/.test(value)) return false; }
    else if (key === 'schoolId') { if (!new RegExp(`^${uuidPath}$`).test(value)) return false; }
    else if (key === 'result') { if (value !== 'SUCCESS' && value !== 'REFUSED') return false; }
    else return false;
  }
  return true;
}

/** Liste fermée des appels que le relais peut émettre vers l'API de la plateforme : toute autre route reste inaccessible. */
export function allowedPlatformRequest(request: PlatformRequest): boolean {
  const cut = request.path.indexOf('?');
  const path = cut < 0 ? request.path : request.path.slice(0, cut);
  const query = cut < 0 ? '' : request.path.slice(cut + 1);
  if (request.method === 'GET') {
    if (request.body !== undefined || request.idempotencyKey !== undefined || request.ifMatch !== undefined) return false;
    if (path === '/v1/platform/journal') return validJournalQuery(query);
    return query === '' && (staticReads.has(path) || operationPath.test(path));
  }
  if (request.method !== 'POST' || query !== '') return false;
  const keyed = typeof request.idempotencyKey === 'string' && z.uuid().safeParse(request.idempotencyKey).success;
  if (path === '/v1/platform/invitations/preview') return request.idempotencyKey === undefined && request.ifMatch === undefined;
  if (path === '/v1/platform/invitations' || path === '/v1/platform/invitations/accept') return keyed && request.ifMatch === undefined;
  if (revokePath.test(path)) return keyed && typeof request.ifMatch === 'string' && strongVersion.test(request.ifMatch);
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

// --- État de session : un code émis et une acceptation en cours appartiennent au compte qui les a lancés. ---
export type PlatformInviteState = { operationId: string; email: string; validityDays?: number; code: string; busy?: boolean };
export type PlatformJoinState = { identity: string; operationId: string; code?: string; confirmation?: { id: string; digest: string };
  busy?: boolean; submitted?: boolean; uncertain?: boolean; accepted?: PlatformJoinResult };

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
const digestOf = (data: unknown) => createHash('sha256').update(JSON.stringify(data)).digest('hex');
/** Refus définitifs d'une acceptation : le code ne servira plus, l'état est abandonné. 403 et 429 laissent corriger puis reprendre. */
const terminalJoinStatuses = new Set([404, 409, 410]);

export function registerPlatformRoutes(app: FastifyInstance, deps: {
  current: (req: FastifyRequest) => Session; protect: (req: FastifyRequest) => Session;
  call: (session: Session, command: PlatformRequest) => Promise<ApiResult>; send: (reply: FastifyReply, result: ApiResult) => unknown;
  error: (status: number, code: string) => Error;
}) {
  const failureCode = (result: ApiResult) => z.object({ code: z.string().regex(/^[A-Z0-9_]{1,80}$/) }).safeParse(result.body);
  /** Un compte qui n'est plus opérateur perd sur-le-champ ce que le relais gardait pour lui. */
  const refused = (session: Session, result: ApiResult) => {
    const code = failureCode(result);
    if (result.status === 403 && code.success && code.data.code === 'PLATFORM_OPERATOR_REQUIRED') delete session.platformInvite;
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
    if (result.data.self) delete session.platformInvite;
    return result;
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
