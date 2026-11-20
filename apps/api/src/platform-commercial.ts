import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { checkIdempotency, requireVersion } from './commands.js';
import { entitlementDetailView } from './entitlements-model.js';
import { readClientEntitlements } from './entitlements.js';
import { ApiError, notFound } from './errors.js';
import {
  addDays, commercialDetailView, commercialQuery, decisionBody, isPeriodStart, maxAheadDays, maxTrialDays, nextPeriodStart, paidStartBody,
  paidStartCancelBody, requestBody, requestTransitionAllowed, termsAt, termsBody, trialEndBody, trialExtendBody, trialStartBody,
  type CommercialDetail, type CommercialRow, type MissingField, type RequestKind, type RequestStatus,
} from './platform-commercial-model.js';
import { platformCommand, platformRead } from './platform-command.js';

const empty = z.object({}).strict();
const idParams = z.object({ id: z.uuid() }).strict();
const requestParams = z.object({ id: z.uuid(), requestId: z.uuid() }).strict();
const dayMs = 86_400_000;

const commercialConflict = () => new ApiError(412, 'VERSION_CONFLICT', 'Le dossier commercial de cette école a changé. Rechargez-le avant de confirmer.');
const datePast = () => new ApiError(409, 'EFFECTIVE_DATE_PAST', 'La date doit être aujourd’hui ou plus tard.');
const dateTooFar = () => new ApiError(400, 'INVALID_REQUEST', 'La date est trop éloignée.');
const terminated = () => new ApiError(409, 'CLIENT_TERMINATED', 'La résiliation de cette école est confirmée.');

/** Même verrou que les autres commandes de la fiche (R01-T02, R01-T03) : conditions, essai, attributions et rattachement ne s'entrecroisent pas. */
export async function lockedClient(db: PoolClient, clientId: string): Promise<string | null> {
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`platform-client:${clientId}`]);
  const row = (await db.query<{ school_id: string | null }>('SELECT school_id FROM drivy.platform_client WHERE id=$1', [clientId])).rows[0];
  if (!row) throw notFound();
  return row.school_id;
}
async function readCommercialRow(db: PoolClient, clientId: string): Promise<CommercialRow> {
  const row = (await db.query<{ detail: CommercialRow | null }>('SELECT drivy.platform_client_commercial($1::uuid) AS detail', [clientId])).rows[0]?.detail;
  if (!row) throw notFound();
  return row;
}
export const commercialView = async (db: PoolClient, clientId: string) => commercialDetailView(await readCommercialRow(db, clientId), new Date());
/** Dossier relu dans la transaction de la commande : la version affichée par l'opérateur doit être celle d'à présent. */
async function currentCommercial(db: PoolClient, clientId: string, expected: number): Promise<CommercialDetail> {
  const detail = await commercialView(db, clientId);
  if (detail.version !== expected) throw commercialConflict();
  return detail;
}

/** Jour commercial saisi : aujourd'hui (Zurich) ou plus tard, pas au-delà d'une saison. */
function futureDay(day: string, today: string) {
  if (day < today) throw datePast();
  if (day > addDays(today, maxAheadDays)) throw dateTooFar();
  return day;
}

type TermsFields = { initialAmount: number | null; monthlyAmount: number | null; paymentTermDays: number | null; suspensionBilling: string | null };
/** Zones d'une version de conditions encore à compléter (même règle que `drivy.platform_terms_missing`). */
export function termsFieldsMissing(version: TermsFields | null): MissingField[] {
  if (!version) return ['TERMS'];
  return [
    ...(version.initialAmount === null ? ['INITIAL_AMOUNT' as const] : []), ...(version.monthlyAmount === null ? ['MONTHLY_AMOUNT' as const] : []),
    ...(version.paymentTermDays === null ? ['PAYMENT_TERM' as const] : []), ...(version.suspensionBilling === null ? ['SUSPENSION_BILLING' as const] : []),
  ];
}
/** Ce qui manque pour qu'une version soit facturable ; `OFFER` si aucune offre n'est attribuée (en vigueur ou programmée). */
export const termsMissing = (detail: Pick<CommercialDetail, 'offer' | 'scheduledOffer'>, version: TermsFields | null): MissingField[] =>
  [...(!detail.offer && !detail.scheduledOffer ? ['OFFER' as const] : []), ...termsFieldsMissing(version)];

/**
 * Date d'effet par défaut d'une nouvelle version : aujourd'hui tant que le payant n'a pas commencé (elle s'appliquera dès la première période),
 * sinon le prochain début de période, sans prorata. Une date choisie hors début de période, après le début payant, exige un motif.
 */
export function termsEffectiveFrom(args: { requested: string | undefined; exceptionReason: string | undefined; paidStartsOn: string | null; today: string }) {
  const { requested, exceptionReason, paidStartsOn: anchor, today } = args;
  const started = anchor !== null && anchor <= today;
  const effectiveFrom = requested ?? (started ? nextPeriodStart(anchor, today) : today);
  futureDay(effectiveFrom, today);
  if (anchor && effectiveFrom > anchor && !isPeriodStart(anchor, effectiveFrom) && !exceptionReason) {
    throw new ApiError(409, 'TERMS_EXCEPTION_REASON_REQUIRED', 'Cette date n’est pas un début de période. Indiquez le motif de l’exception.');
  }
  return effectiveFrom;
}

/**
 * Conditions commerciales, essai, début payant et demandes d'une fiche (R01-T04, #456). Toutes les écritures passent par `platformCommand` :
 * équipe relue en base, reçu durable, ligne du journal commercial et effet dans un même commit. `version` du dossier sert d'If-Match.
 * Aucune facture n'est émise ici (#457) ; les motifs et textes libres restent dans le dossier, jamais dans le journal.
 */
export function registerPlatformCommercial(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier }) {
  const envelope = (data: unknown, request: FastifyRequest) => ({ data, requestId: request.id, serverTime: new Date().toISOString() });
  const identityOf = (request: FastifyRequest) => options.verifyToken(request.headers.authorization);
  const base = '/v1/platform/clients/:id/commercial';

  app.get(base, async request => {
    const identity = await identityOf(request); commercialQuery.parse(request.query); const { id } = idParams.parse(request.params);
    return envelope(await platformRead(options.pool, identity, db => commercialView(db, id)), request);
  });

  /** Commande d'une fiche : verrou, dossier relu à la version attendue, effet, dossier rendu. */
  type Effect = { status?: 200 | 201; journal: { action: string; changes: Record<string, unknown> } };
  function command<B extends { operationId: string }>(path: string, kind: string, schema: z.ZodType<B>,
    work: (db: PoolClient, actor: { operatorId: string }, before: CommercialDetail, body: B, route: { id: string; requestId?: string }) => Promise<Effect>,
    params: z.ZodType<{ id: string; requestId?: string }> = idParams) {
    app.post(`${base}${path}`, async (request, reply) => {
      const identity = await identityOf(request); empty.parse(request.query);
      const routeParams = params.parse(request.params); const id = routeParams.id; const body = schema.parse(request.body);
      const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
      const { operationId, ...content } = body as B & Record<string, unknown>;
      const result = await platformCommand(options.pool, identity, {
        kind, operationId, expectedVersion: expected, body: { ...routeParams, ...content }, refusal: { action: kind, subject: { type: 'PlatformClient', id } },
      }, async (db, actor) => {
        const schoolId = await lockedClient(db, id);
        const before = await currentCommercial(db, id, expected);
        const effect = await work(db, actor, before, body, routeParams);
        const data = await commercialView(db, id);
        return { data, status: effect.status ?? 200, journal: { action: effect.journal.action, schoolId, subject: { type: 'PlatformClient', id }, changes: effect.journal.changes } };
      });
      reply.status(result.status); return envelope(result.data, request);
    });
  }

  // Nouvelle version des conditions : jamais une réécriture. Une version complète reste exigée tant qu'un début payant est confirmé.
  command('/terms', 'SET_COMMERCIAL_TERMS', termsBody, async (db, actor, before, body, { id }) => {
    const today = before.today;
    if (before.lifecycle === 'TERMINATED') throw terminated();
    const anchor = before.paidStart?.startsOn ?? null;
    const effectiveFrom = termsEffectiveFrom({ requested: body.effectiveFrom, exceptionReason: body.exceptionReason, paidStartsOn: anchor, today });
    const fieldsMissing = termsFieldsMissing(body);
    if (anchor && fieldsMissing.length) {
      throw new ApiError(409, 'TERMS_INCOMPLETE', 'Un début payant est confirmé : les conditions doivent rester complètes.');
    }
    const sequence = 1 + Math.max(0, ...before.terms.versions.map(item => item.sequence));
    const termsId = randomUUID();
    await db.query(`INSERT INTO drivy.platform_commercial_terms(id,client_id,sequence,initial_amount,initial_discount,initial_due_on,monthly_amount,
        recurring_discount,recurring_discount_months,payment_term_days,suspension_billing,effective_from,exception_reason,created_by)
      VALUES($1,$2,$3,$4,$5,$6::date,$7,$8,$9,$10,$11,$12::date,$13,$14)`,
    [termsId, id, sequence, body.initialAmount, body.initialDiscount, body.initialDueOn, body.monthlyAmount, body.recurringDiscount,
      body.recurringDiscountMonths, body.paymentTermDays, body.suspensionBilling, effectiveFrom, body.exceptionReason ?? null, actor.operatorId]);
    return { status: 201, journal: { action: 'SET_COMMERCIAL_TERMS', changes: {
      termsId, sequence, effectiveFrom, complete: fieldsMissing.length === 0, exception: body.exceptionReason !== undefined,
      initialAmount: body.initialAmount, initialDiscount: body.initialDiscount, monthlyAmount: body.monthlyAmount, recurringDiscount: body.recurringDiscount,
      recurringDiscountMonths: body.recurringDiscountMonths, paymentTermDays: body.paymentTermDays, suspensionBilling: body.suspensionBilling,
    } } };
  });

  // Début d'essai : proposé à l'activation effective de l'école, ajustable ; la fin est toujours explicite.
  command('/trial/start', 'START_TRIAL', trialStartBody, async (db, actor, before, body, { id }) => {
    if (before.trial) throw new ApiError(409, 'TRIAL_EXISTS', 'Un essai a déjà été accordé à cette école.');
    if (before.lifecycle === 'PAID' || before.lifecycle === 'TERMINATED') throw new ApiError(409, 'TRIAL_CLOSED', 'L’essai n’est plus possible pour cette école.');
    const now = Date.now();
    const startsAt = new Date(body.startsAt ?? before.milestones.activatedAt ?? new Date(now).toISOString());
    const endsAt = new Date(body.endsAt);
    if (endsAt.getTime() <= now) throw new ApiError(409, 'TRIAL_END_PAST', 'La fin de l’essai doit être à venir.');
    if (endsAt <= startsAt || endsAt.getTime() - startsAt.getTime() > maxTrialDays * dayMs || startsAt.getTime() > now + maxAheadDays * dayMs) {
      throw new ApiError(400, 'INVALID_REQUEST', 'Les dates de l’essai ne sont pas valides.');
    }
    const trialId = randomUUID();
    await db.query(`INSERT INTO drivy.platform_trial_change(id,client_id,sequence,kind,starts_at,ends_at,created_by) VALUES($1,$2,1,'START',$3,$4,$5)`,
      [trialId, id, startsAt.toISOString(), endsAt.toISOString(), actor.operatorId]);
    return { status: 201, journal: { action: 'START_TRIAL', changes: {
      trialChangeId: trialId, startsAt: startsAt.toISOString(), endsAt: endsAt.toISOString(), fromActivation: body.startsAt === undefined && before.milestones.activatedAt !== null,
    } } };
  });

  // Prolongation : rétablit les droits d'un essai expiré ; motivée, historisée.
  command('/trial/extend', 'EXTEND_TRIAL', trialExtendBody, async (db, actor, before, body, { id }) => {
    const trial = before.trial;
    if (!trial) throw new ApiError(409, 'TRIAL_MISSING', 'Aucun essai n’a été accordé à cette école.');
    if (before.lifecycle === 'PAID' || before.lifecycle === 'TERMINATED') throw new ApiError(409, 'TRIAL_CLOSED', 'L’essai n’est plus possible pour cette école.');
    const endsAt = new Date(body.endsAt);
    if (endsAt.getTime() <= Date.now() || endsAt <= new Date(trial.endsAt)) throw new ApiError(409, 'TRIAL_EXTEND_INVALID', 'La nouvelle fin doit être après la fin actuelle et à venir.');
    if (endsAt.getTime() - new Date(trial.startsAt).getTime() > maxTrialDays * dayMs) throw new ApiError(400, 'INVALID_REQUEST', 'L’essai serait trop long.');
    const trialId = randomUUID(); const sequence = before.trialChanges.length + 1;
    await db.query(`INSERT INTO drivy.platform_trial_change(id,client_id,sequence,kind,starts_at,ends_at,reason,created_by) VALUES($1,$2,$3,'EXTEND',$4,$5,$6,$7)`,
      [trialId, id, sequence, trial.startsAt, endsAt.toISOString(), body.reason, actor.operatorId]);
    return { status: 201, journal: { action: 'EXTEND_TRIAL', changes: { trialChangeId: trialId, previousEndsAt: trial.endsAt, endsAt: endsAt.toISOString(), reopened: trial.phase === 'ENDED' } } };
  });

  // Fin anticipée d'un essai en cours : maintenant par défaut. Jamais de montant ni d'abonnement créé par la fin d'un essai.
  command('/trial/end', 'END_TRIAL_EARLY', trialEndBody, async (db, actor, before, body, { id }) => {
    const trial = before.trial;
    if (!trial || trial.phase !== 'RUNNING') throw new ApiError(409, 'TRIAL_NOT_RUNNING', 'Aucun essai n’est en cours.');
    const now = Date.now();
    const endsAt = body.endsAt === undefined ? null : new Date(body.endsAt);
    if (endsAt && (endsAt.getTime() < now - 1000 || endsAt >= new Date(trial.endsAt))) {
      throw new ApiError(409, 'TRIAL_END_INVALID', 'La fin anticipée doit être entre maintenant et la fin prévue.');
    }
    const trialId = randomUUID(); const sequence = before.trialChanges.length + 1;
    const inserted = await db.query<{ ends_at: Date }>(`INSERT INTO drivy.platform_trial_change(id,client_id,sequence,kind,starts_at,ends_at,reason,created_by)
      VALUES($1,$2,$3,'END_EARLY',$4,coalesce($5::timestamptz,date_trunc('milliseconds',statement_timestamp())),$6,$7) RETURNING ends_at`,
    [trialId, id, sequence, trial.startsAt, endsAt?.toISOString() ?? null, body.reason, actor.operatorId]);
    return { status: 201, journal: { action: 'END_TRIAL_EARLY', changes: { trialChangeId: trialId, previousEndsAt: trial.endsAt, endsAt: new Date(inserted.rows[0]!.ends_at).toISOString() } } };
  });

  // Début payant : confirmation et date explicites, sur des conditions complètes applicables à cette date. Jamais rétroactif.
  command('/paid-start', 'CONFIRM_PAID_START', paidStartBody, async (db, actor, before, body, { id }) => {
    if (before.termination) throw terminated();
    if (before.paidStart) throw new ApiError(409, 'PAID_START_EXISTS', 'Un début payant est déjà confirmé.');
    const startsOn = futureDay(body.startsOn, before.today);
    const version = termsAt(before.terms.versions, startsOn);
    const missing = termsMissing(before, version);
    if (!version || missing.length) {
      throw new ApiError(409, 'TERMS_INCOMPLETE', 'Les conditions applicables à cette date sont à compléter.');
    }
    const paidStartId = randomUUID();
    await db.query('INSERT INTO drivy.platform_paid_start(id,client_id,starts_on,terms_id,confirmed_by) VALUES($1,$2,$3::date,$4,$5)',
      [paidStartId, id, startsOn, version.id, actor.operatorId]);
    return { status: 201, journal: { action: 'CONFIRM_PAID_START', changes: { paidStartId, startsOn, termsId: version.id, termsSequence: version.sequence } } };
  });

  // Annulation d'un début payant tant que sa date n'est pas atteinte ; ensuite, la fin passe par une résiliation.
  command('/paid-start/cancel', 'CANCEL_PAID_START', paidStartCancelBody, async (db, actor, before, body) => {
    const paid = before.paidStart;
    if (!paid) throw new ApiError(409, 'PAID_START_MISSING', 'Aucun début payant n’est confirmé.');
    if (paid.started) throw new ApiError(409, 'PAID_START_STARTED', 'Le payant a déjà commencé. Passez par une résiliation.');
    const updated = await db.query("UPDATE drivy.platform_paid_start SET status='CANCELLED',cancelled_by=$2,cancel_reason=$3 WHERE id=$1 AND status='ACTIVE'",
      [paid.id, actor.operatorId, body.reason]);
    if (updated.rowCount !== 1) throw commercialConflict();
    return { journal: { action: 'CANCEL_PAID_START', changes: { paidStartId: paid.id, startsOn: paid.startsOn } } };
  });

  // Demande reçue de l'école (changement d'offre ou résiliation) : enregistrée, elle ne vaut pas confirmation.
  command('/requests', 'RECORD_COMMERCIAL_REQUEST', requestBody, async (db, actor, before, body, { id }) => {
    if (body.requestedOn > before.today) throw new ApiError(409, 'REQUEST_DATE_FUTURE', 'La date de la demande ne peut pas être à venir.');
    if (body.desiredOn) futureDay(body.desiredOn, before.today);
    let offerName: string | null = null;
    if (body.requestedOfferId) {
      offerName = (await db.query<{ name: string }>('SELECT name FROM drivy.platform_offer WHERE id=$1', [body.requestedOfferId])).rows[0]?.name ?? null;
      if (!offerName) throw notFound();
    }
    const requestId = randomUUID();
    await db.query(`INSERT INTO drivy.platform_commercial_request(id,client_id,kind,requested_on,requested_offer_id,requested_offer_name,desired_on,details,created_by)
      VALUES($1,$2,$3,$4::date,$5,$6,$7::date,$8,$9)`,
    [requestId, id, body.kind, body.requestedOn, body.requestedOfferId ?? null, offerName, body.desiredOn ?? null, body.details ?? null, actor.operatorId]);
    return { status: 201, journal: { action: 'RECORD_COMMERCIAL_REQUEST', changes: {
      requestId, kind: body.kind, requestedOn: body.requestedOn, requestedOfferId: body.requestedOfferId ?? null, desiredOn: body.desiredOn ?? null,
    } } };
  });

  // Décision : en traitement, acceptée (avec date d'effet), refusée (avec réponse) ou retirée. Une décision est définitive.
  command('/requests/:requestId/decision', 'DECIDE_COMMERCIAL_REQUEST', decisionBody, async (db, actor, before, body, { id, requestId }) => {
    // Une demande d'une autre fiche n'existe pas ici.
    const row = (await db.query<{ kind: RequestKind; status: RequestStatus; requested_offer_id: string | null }>(
      'SELECT kind,status,requested_offer_id FROM drivy.platform_commercial_request WHERE id=$1 AND client_id=$2 FOR UPDATE', [requestId!, id])).rows[0];
    if (!row) throw notFound();
    if (!requestTransitionAllowed(row.status, body.status)) throw new ApiError(409, 'REQUEST_CLOSED', 'Cette demande a déjà reçu une décision.');
    let effectiveOn: string | null = null; let assignmentId: string | null = null; let offerId: string | null = null;
    if (body.status === 'ACCEPTED') {
      effectiveOn = futureDay(body.effectiveOn!, before.today);
      if (before.lifecycle === 'TERMINATED' || (row.kind === 'TERMINATION' && before.termination)) throw terminated();
      if (row.kind === 'TERMINATION' && body.offerId) throw new ApiError(400, 'INVALID_REQUEST', 'Une résiliation ne désigne pas d’offre.');
      if (row.kind === 'OFFER_CHANGE') {
        offerId = body.offerId ?? row.requested_offer_id;
        if (!offerId) throw new ApiError(400, 'INVALID_REQUEST', 'Choisissez l’offre acceptée.');
        const offer = (await db.query<{ id: string; name: string; modules: string[]; status: string }>(
          'SELECT id,name,modules,status FROM drivy.platform_offer WHERE id=$1 FOR SHARE', [offerId])).rows[0];
        if (!offer) throw notFound();
        if (offer.status !== 'ACTIVE') throw new ApiError(409, 'OFFER_ARCHIVED', 'Cette offre est archivée.');
        // Comme une attribution (R01-T03) : celle qui était programmée est remplacée ; l'effet est à minuit (Zurich) du jour accepté, ou maintenant.
        const rights = entitlementDetailView(await readClientEntitlements(db, id), new Date());
        for (const item of rights.assignments.filter(entry => entry.phase === 'SCHEDULED')) {
          await db.query("UPDATE drivy.platform_offer_assignment SET status='CANCELLED',cancelled_by=$2 WHERE id=$1", [item.id, actor.operatorId]);
        }
        assignmentId = randomUUID();
        await db.query(`INSERT INTO drivy.platform_offer_assignment(id,client_id,offer_id,offer_name,modules,effective_at,created_by)
          VALUES($1,$2,$3,$4,$5::text[],date_trunc('milliseconds',greatest(statement_timestamp(),drivy.zurich_day_start($6::date))),$7)`,
        [assignmentId, id, offer.id, offer.name, offer.modules, effectiveOn, actor.operatorId]);
      }
    }
    const decided = body.status !== 'IN_PROGRESS';
    const updated = await db.query(`UPDATE drivy.platform_commercial_request SET status=$2,response=coalesce($3,response),effective_on=$4::date,assignment_id=$5,
        decided_by=$6,updated_by=$7 WHERE id=$1 AND status IN ('RECEIVED','IN_PROGRESS')`,
    [requestId, body.status, body.response ?? null, effectiveOn, assignmentId, decided ? actor.operatorId : null, actor.operatorId]);
    if (updated.rowCount !== 1) throw commercialConflict();
    return { journal: { action: 'DECIDE_COMMERCIAL_REQUEST', changes: {
      requestId, kind: row.kind, from: row.status, to: body.status, effectiveOn, assignmentId, offerId, responded: body.response !== undefined,
    } } };
  }, requestParams);
}
