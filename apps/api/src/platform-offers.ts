import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { checkIdempotency, requireVersion } from './commands.js';
import { assignmentPreview, entitlementDetailView } from './entitlements-model.js';
import { readClientEntitlements, readModuleUsage } from './entitlements.js';
import { ApiError, notFound } from './errors.js';
import { platformCommand, platformRead } from './platform-command.js';
import {
  adjustModuleBody, assignOfferBody, assignmentPreviewQuery, createOfferBody, entitlementQuery, liftAdjustmentBody, maxEffectiveDays,
  offerCommandBody, offerListQuery, offerView, updateOfferBody, type OfferItem,
} from './platform-offers-model.js';

const empty = z.object({}).strict();
const idParams = z.object({ id: z.uuid() }).strict();
const assignmentParams = z.object({ id: z.uuid(), assignmentId: z.uuid() }).strict();
const adjustmentParams = z.object({ id: z.uuid(), adjustmentId: z.uuid() }).strict();
const offerConflict = () => new ApiError(412, 'VERSION_CONFLICT', 'Cette offre a changé. Rechargez-la avant de confirmer.');
const rightsConflict = () => new ApiError(412, 'VERSION_CONFLICT', 'Les droits de cette école ont changé. Rechargez-les avant de confirmer.');
const offerArchived = () => new ApiError(409, 'OFFER_ARCHIVED', 'Cette offre est archivée.');
/** Même verrou que les commandes de la fiche (R01-T02) : une attribution, un ajustement et un rattachement ne s'entrecroisent pas. */
const lockClient = (db: PoolClient, clientId: string) => db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`platform-client:${clientId}`]);

const offerRows = async (db: PoolClient, id: string | null, status: string | null) =>
  (await db.query<{ item: OfferItem }>('SELECT item FROM drivy.platform_offer_overview($1::uuid,$2::text)', [id, status])).rows.map(row => row.item);
async function readOffer(db: PoolClient, id: string) {
  const item = (await offerRows(db, id, null))[0];
  if (!item) throw notFound();
  return offerView(item);
}

/**
 * Date d'effet d'une attribution : absente = immédiate ; sinon strictement à venir et pas au-delà d'une saison.
 * Le serveur la valide au moment de la demande ; la base refuse de toute façon une date remontée dans le passé.
 */
export function effectiveInstant(value: string | null | undefined, now: number = Date.now()): string | null {
  if (value === null || value === undefined) return null;
  const at = new Date(value).getTime();
  if (at <= now) throw new ApiError(409, 'EFFECTIVE_DATE_PAST', 'La date d’effet doit être à venir.');
  if (at > now + maxEffectiveDays * 86_400_000) throw new ApiError(400, 'INVALID_REQUEST', 'La date d’effet est trop éloignée.');
  return new Date(at).toISOString();
}

/** Fiche existante (404 sinon), verrouillée pour la commande ; rend l'école reliée, s'il y en a une. */
async function lockedClient(db: PoolClient, clientId: string): Promise<string | null> {
  await lockClient(db, clientId);
  const row = (await db.query<{ school_id: string | null }>('SELECT school_id FROM drivy.platform_client WHERE id=$1', [clientId])).rows[0];
  if (!row) throw notFound();
  return row.school_id;
}
/** Droits relus dans la transaction de la commande : la version affichée par l'opérateur doit être celle d'à présent. */
async function currentRights(db: PoolClient, clientId: string, expected: number) {
  const detail = entitlementDetailView(await readClientEntitlements(db, clientId), new Date());
  if (detail.version !== expected) throw rightsConflict();
  return detail;
}
const rightsView = async (db: PoolClient, clientId: string) => entitlementDetailView(await readClientEntitlements(db, clientId), new Date());

/**
 * Offres, attributions et ajustements de modules (R01-T03, #455). Toutes les écritures passent par `platformCommand` : équipe relue en base,
 * reçu durable, ligne du journal commercial et effet dans un même commit. Aucun montant, essai ni échéance : ils relèvent de #456.
 */
export function registerPlatformOffers(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier }) {
  const envelope = (data: unknown, request: FastifyRequest) => ({ data, requestId: request.id, serverTime: new Date().toISOString() });
  const identityOf = (request: FastifyRequest) => options.verifyToken(request.headers.authorization);

  app.get('/v1/platform/modules', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const data = await platformRead(options.pool, identity, async db => ({
      items: (await db.query<{ code: string; sort_order: number }>('SELECT code,sort_order FROM drivy.platform_module ORDER BY sort_order')).rows
        .map(row => ({ code: row.code, sortOrder: row.sort_order })),
    }));
    return envelope(data, request);
  });

  app.get('/v1/platform/offers', async request => {
    const identity = await identityOf(request); const query = offerListQuery.parse(request.query);
    const data = await platformRead(options.pool, identity, async db => ({ items: (await offerRows(db, null, query.status ?? null)).map(offerView) }));
    return envelope(data, request);
  });

  app.post('/v1/platform/offers', async (request, reply) => {
    const identity = await identityOf(request); empty.parse(request.query);
    const body = createOfferBody.parse(request.body); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const { operationId, ...content } = body;
    const result = await platformCommand(options.pool, identity, {
      kind: 'CREATE_OFFER', operationId, expectedVersion: null, body: content, refusal: { action: 'CREATE_OFFER' },
    }, async (db, actor) => {
      const id = randomUUID();
      await db.query('INSERT INTO drivy.platform_offer(id,name,modules,created_by) VALUES($1,$2,$3::text[],$4)', [id, body.name, body.modules, actor.operatorId]);
      const data = await readOffer(db, id);
      return { data, status: 201 as const, journal: { action: 'CREATE_OFFER', subject: { type: 'PlatformOffer', id }, changes: { name: data.name, modules: data.modules } } };
    });
    reply.status(result.status); return envelope(result.data, request);
  });

  app.patch('/v1/platform/offers/:id', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const { id } = idParams.parse(request.params); const body = updateOfferBody.parse(request.body);
    const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const { operationId, ...content } = body;
    const result = await platformCommand(options.pool, identity, {
      kind: 'UPDATE_OFFER', operationId, expectedVersion: expected, body: { id, ...content }, refusal: { action: 'UPDATE_OFFER', subject: { type: 'PlatformOffer', id } },
    }, async (db, actor) => {
      const row = (await db.query<{ name: string; modules: string[]; status: string; version: number }>(
        'SELECT name,modules,status,version FROM drivy.platform_offer WHERE id=$1 FOR UPDATE', [id])).rows[0];
      if (!row) throw notFound();
      if (row.version !== expected) throw offerConflict();
      if (row.status === 'ARCHIVED') throw offerArchived();
      const updated = await db.query('UPDATE drivy.platform_offer SET name=$2,modules=$3::text[],updated_by=$4 WHERE id=$1 AND version=$5',
        [id, body.name ?? row.name, body.modules ?? row.modules, actor.operatorId, expected]);
      if (updated.rowCount !== 1) throw offerConflict();
      const data = await readOffer(db, id);
      const fields = [...(body.name !== undefined ? ['name'] : []), ...(body.modules !== undefined ? ['modules'] : [])];
      return { data, journal: { action: 'UPDATE_OFFER', subject: { type: 'PlatformOffer', id },
        changes: { fields, name: data.name, modules: data.modules, previousModules: row.modules } } };
    });
    return envelope(result.data, request);
  });

  /** Archiver ou restaurer : une offre archivée n'est plus proposée à l'attribution ; les écoles qui l'ont déjà gardent leurs droits. */
  const offerStatusRoute = (path: 'archive' | 'restore') => app.post(`/v1/platform/offers/:id/${path}`, async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const { id } = idParams.parse(request.params); const body = offerCommandBody.parse(request.body);
    const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const archiving = path === 'archive'; const action = archiving ? 'ARCHIVE_OFFER' : 'RESTORE_OFFER';
    const result = await platformCommand(options.pool, identity, {
      kind: action, operationId: body.operationId, expectedVersion: expected, body: { id }, refusal: { action, subject: { type: 'PlatformOffer', id } },
    }, async (db, actor) => {
      const row = (await db.query<{ status: string; version: number }>('SELECT status,version FROM drivy.platform_offer WHERE id=$1 FOR UPDATE', [id])).rows[0];
      if (!row) throw notFound();
      if (row.version !== expected) throw offerConflict();
      if (archiving && row.status === 'ARCHIVED') throw offerArchived();
      if (!archiving && row.status !== 'ARCHIVED') throw new ApiError(409, 'OFFER_NOT_ARCHIVED', 'Cette offre n’est pas archivée.');
      const to = archiving ? 'ARCHIVED' : 'ACTIVE';
      const updated = await db.query('UPDATE drivy.platform_offer SET status=$2,updated_by=$3 WHERE id=$1 AND version=$4', [id, to, actor.operatorId, expected]);
      if (updated.rowCount !== 1) throw offerConflict();
      const data = await readOffer(db, id);
      return { data, journal: { action, subject: { type: 'PlatformOffer', id }, changes: { status: { from: row.status, to }, schoolsInForce: data.schoolsInForce } } };
    });
    return envelope(result.data, request);
  });
  offerStatusRoute('archive'); offerStatusRoute('restore');

  // Droits d'une fiche : en vigueur, programmés, historique. `version` est l'If-Match des commandes ci-dessous.
  app.get('/v1/platform/clients/:id/entitlements', async request => {
    const identity = await identityOf(request); entitlementQuery.parse(request.query); const { id } = idParams.parse(request.params);
    return envelope(await platformRead(options.pool, identity, db => rightsView(db, id)), request);
  });

  // Conséquences d'une attribution avant toute écriture : droit avant/après par module et volumes existants de ce qui serait retiré.
  app.get('/v1/platform/clients/:id/assignment-preview', async request => {
    const identity = await identityOf(request); const { id } = idParams.parse(request.params); const query = assignmentPreviewQuery.parse(request.query);
    const effectiveAt = effectiveInstant(query.effectiveAt);
    const data = await platformRead(options.pool, identity, async db => {
      const offer = (await offerRows(db, query.offerId, null))[0];
      if (!offer) throw notFound();
      if (offer.status !== 'ACTIVE') throw offerArchived();
      const current = await rightsView(db, id);
      const usage = await readModuleUsage(db, id);
      return assignmentPreview({ current, offer: { id: offer.id, name: offer.name, modules: offer.modules }, effectiveAt, usage });
    });
    return envelope(data, request);
  });

  app.post('/v1/platform/clients/:id/assignments', async (request, reply) => {
    const identity = await identityOf(request); empty.parse(request.query);
    const { id } = idParams.parse(request.params); const body = assignOfferBody.parse(request.body);
    const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const effectiveAt = effectiveInstant(body.effectiveAt);
    const result = await platformCommand(options.pool, identity, {
      kind: 'ASSIGN_OFFER', operationId: body.operationId, expectedVersion: expected, body: { id, offerId: body.offerId, effectiveAt },
      refusal: { action: 'ASSIGN_OFFER', subject: { type: 'PlatformClient', id } },
    }, async (db, actor) => {
      const schoolId = await lockedClient(db, id);
      const before = await currentRights(db, id, expected);
      // Verrou partagé : l'offre ne change pas entre la lecture et la copie de ses modules dans l'attribution.
      const offer = (await db.query<{ id: string; name: string; modules: string[]; status: string }>(
        'SELECT id,name,modules,status FROM drivy.platform_offer WHERE id=$1 FOR SHARE', [body.offerId])).rows[0];
      if (!offer) throw notFound();
      if (offer.status !== 'ACTIVE') throw offerArchived();
      // Une nouvelle attribution remplace celle qui était programmée : jamais deux échéances concurrentes.
      const pending = before.assignments.filter(item => item.phase === 'SCHEDULED');
      for (const item of pending) await db.query('UPDATE drivy.platform_offer_assignment SET status=$3,cancelled_by=$2 WHERE id=$1', [item.id, actor.operatorId, 'CANCELLED']);
      const assignmentId = randomUUID();
      await db.query(`INSERT INTO drivy.platform_offer_assignment(id,client_id,offer_id,offer_name,modules,effective_at,created_by)
        VALUES($1,$2,$3,$4,$5::text[],coalesce($6::timestamptz,date_trunc('milliseconds',statement_timestamp())),$7)`,
      [assignmentId, id, offer.id, offer.name, offer.modules, effectiveAt, actor.operatorId]);
      const data = await rightsView(db, id);
      return { data, status: 201 as const, journal: { action: 'ASSIGN_OFFER', schoolId, subject: { type: 'PlatformClient', id },
        changes: { assignmentId, offerId: offer.id, offerName: offer.name, modules: offer.modules, immediate: effectiveAt === null, effectiveAt: effectiveAt ?? 'IMMEDIATE', replacedScheduled: pending.length } } };
    });
    reply.status(result.status); return envelope(result.data, request);
  });

  // Seule une attribution programmée (date d'effet à venir) s'annule ; une attribution en vigueur ne se réécrit pas, on en attribue une autre.
  app.post('/v1/platform/clients/:id/assignments/:assignmentId/cancel', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const { id, assignmentId } = assignmentParams.parse(request.params); const body = offerCommandBody.parse(request.body);
    const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const result = await platformCommand(options.pool, identity, {
      kind: 'CANCEL_OFFER_ASSIGNMENT', operationId: body.operationId, expectedVersion: expected, body: { id, assignmentId },
      refusal: { action: 'CANCEL_OFFER_ASSIGNMENT', subject: { type: 'PlatformClient', id } },
    }, async (db, actor) => {
      const schoolId = await lockedClient(db, id);
      const before = await currentRights(db, id, expected);
      const target = before.assignments.find(item => item.id === assignmentId);
      if (!target) throw notFound();
      if (target.phase !== 'SCHEDULED') throw new ApiError(409, 'ASSIGNMENT_NOT_PENDING', 'Cette attribution a déjà pris effet ou a été annulée.');
      await db.query('UPDATE drivy.platform_offer_assignment SET status=$3,cancelled_by=$2 WHERE id=$1', [assignmentId, actor.operatorId, 'CANCELLED']);
      const data = await rightsView(db, id);
      return { data, journal: { action: 'CANCEL_OFFER_ASSIGNMENT', schoolId, subject: { type: 'PlatformClient', id }, changes: { assignmentId, offerId: target.offerId, offerName: target.offerName } } };
    });
    return envelope(result.data, request);
  });

  // Ajustement : un module accordé ou retiré en plus de l'offre en vigueur, immédiatement, avec motif. Il se lève ; il ne s'efface jamais.
  app.post('/v1/platform/clients/:id/adjustments', async (request, reply) => {
    const identity = await identityOf(request); empty.parse(request.query);
    const { id } = idParams.parse(request.params); const body = adjustModuleBody.parse(request.body);
    const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const { operationId, ...content } = body;
    const result = await platformCommand(options.pool, identity, {
      kind: 'ADJUST_SCHOOL_MODULE', operationId, expectedVersion: expected, body: { id, ...content },
      refusal: { action: 'ADJUST_SCHOOL_MODULE', subject: { type: 'PlatformClient', id } },
    }, async (db, actor) => {
      const schoolId = await lockedClient(db, id);
      const before = await currentRights(db, id, expected);
      const inForce = before.assignments.find(item => item.phase === 'IN_FORCE');
      if (before.state !== 'OFFER_ACTIVE' || !inForce) throw new ApiError(409, 'ADJUSTMENT_REQUIRES_OFFER', 'Cette école n’a pas d’offre en vigueur à ajuster.');
      const module = before.modules.find(item => item.code === body.moduleCode);
      if (!module) throw new ApiError(404, 'MODULE_UNKNOWN', 'Ce module n’existe pas.');
      if (module.adjustment) throw new ApiError(409, 'ADJUSTMENT_ACTIVE', 'Un ajustement est déjà actif pour ce module.');
      if (body.effect === 'GRANT' ? module.inOffer : !module.inOffer) throw new ApiError(409, 'ADJUSTMENT_NO_EFFECT', 'Cet ajustement ne changerait rien aux droits de l’école.');
      const adjustmentId = randomUUID();
      await db.query('INSERT INTO drivy.platform_module_adjustment(id,client_id,assignment_id,module_code,effect,reason,created_by) VALUES($1,$2,$3,$4,$5,$6,$7)',
        [adjustmentId, id, inForce.id, body.moduleCode, body.effect, body.reason, actor.operatorId]);
      const data = await rightsView(db, id);
      // Le motif reste dans l'historique de la fiche ; le journal garde l'identité de l'ajustement et son effet.
      return { data, status: 201 as const, journal: { action: 'ADJUST_SCHOOL_MODULE', schoolId, subject: { type: 'PlatformClient', id },
        changes: { adjustmentId, assignmentId: inForce.id, moduleCode: body.moduleCode, effect: body.effect } } };
    });
    reply.status(result.status); return envelope(result.data, request);
  });

  app.post('/v1/platform/clients/:id/adjustments/:adjustmentId/lift', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const { id, adjustmentId } = adjustmentParams.parse(request.params); const body = liftAdjustmentBody.parse(request.body);
    const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const { operationId, ...content } = body;
    const result = await platformCommand(options.pool, identity, {
      kind: 'LIFT_MODULE_ADJUSTMENT', operationId, expectedVersion: expected, body: { id, adjustmentId, ...content },
      refusal: { action: 'LIFT_MODULE_ADJUSTMENT', subject: { type: 'PlatformClient', id } },
    }, async (db, actor) => {
      const schoolId = await lockedClient(db, id);
      const before = await currentRights(db, id, expected);
      const target = before.adjustments.find(item => item.id === adjustmentId);
      if (!target) throw notFound();
      if (target.phase !== 'ACTIVE') throw new ApiError(409, 'ADJUSTMENT_NOT_ACTIVE', 'Cet ajustement n’est plus actif.');
      await db.query('UPDATE drivy.platform_module_adjustment SET lifted_by=$2,lift_reason=$3 WHERE id=$1 AND lifted_at IS NULL', [adjustmentId, actor.operatorId, body.reason]);
      const data = await rightsView(db, id);
      return { data, journal: { action: 'LIFT_MODULE_ADJUSTMENT', schoolId, subject: { type: 'PlatformClient', id },
        changes: { adjustmentId, moduleCode: target.moduleCode, effect: target.effect } } };
    });
    return envelope(result.data, request);
  });
}
