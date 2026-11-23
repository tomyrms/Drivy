import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { checkIdempotency, requireVersion, schoolCommand } from './commands.js';
import { withActor } from './database.js';
import { iso } from './entitlements-model.js';
import { ApiError, notFound } from './errors.js';
import type { InvoiceKind } from './platform-billing-model.js';
import { addDays, maxAheadDays, nextPeriodStart, zurichDay } from './platform-commercial-model.js';
import { databaseRefusal } from './platform-command.js';
import { invoiceFileName } from './platform-invoice-pdf.js';
import { subscriptionCommandBody, subscriptionRequestBody, type SchoolSubscription } from './school-subscription-contract.js';

const schoolParams = z.object({ schoolId: z.uuid() }).strict();
const requestParams = z.object({ schoolId: z.uuid(), requestId: z.uuid() }).strict();
const invoiceParams = z.object({ schoolId: z.uuid(), invoiceId: z.uuid() }).strict();
const emptyQuery = z.object({}).strict();

type Always = 'hasClient' | 'today' | 'contact' | 'version';
/** Ligne de `drivy.school_commercial_view` : sans fiche, seuls `hasClient`, `today`, `contact` et `version` sont présents. */
export type SubscriptionRow = Pick<SchoolSubscription, Always> & Partial<Omit<SchoolSubscription, Always | 'nextPeriodStart' | 'nextDueOn'>>;

/**
 * Vue de l'école : les horodatages sont ramenés au format du contrat. La prochaine période s'arrête à la résiliation confirmée ;
 * la prochaine échéance est la plus proche facture encore due et pas en retard. Aucun montant n'est calculé ici.
 */
export function subscriptionView(row: SubscriptionRow): SchoolSubscription {
  const invoices = row.invoices ?? [];
  const paidStartsOn = row.paidStartsOn ?? null; const terminationOn = row.terminationOn ?? null;
  const next = paidStartsOn ? nextPeriodStart(paidStartsOn, row.today) : null;
  const dues = invoices.flatMap(item => item.dueOn && item.settlement && item.settlement.balance > 0 && !item.settlement.overdue ? [item.dueOn] : []).sort();
  const trial = row.trial ?? null;
  const offerOf = (offer: SchoolSubscription['offer'] | undefined) => offer ? { name: offer.name, effectiveAt: iso(offer.effectiveAt)! } : null;
  return {
    hasClient: row.hasClient, today: row.today, contact: row.contact ?? null,
    lifecycle: row.lifecycle ?? 'NONE', state: row.state ?? 'NOT_CONFIGURED', restriction: row.restriction ?? null,
    trial: trial ? { startsAt: iso(trial.startsAt)!, endsAt: iso(trial.endsAt)! } : null,
    paidStartsOn, terminationOn, nextPeriodStart: next && (!terminationOn || next < terminationOn) ? next : null, nextDueOn: dues[0] ?? null,
    offer: offerOf(row.offer), scheduledOffer: offerOf(row.scheduledOffer), modules: row.modules ?? [],
    terms: row.terms ?? null, scheduledTerms: row.scheduledTerms ?? null, debt: row.debt ?? null, invoices, payments: row.payments ?? [],
    requests: (row.requests ?? []).map(item => ({
      ...item, decidedAt: iso(item.decidedAt), createdAt: iso(item.createdAt)!,
      revisions: item.revisions.map(revision => ({ ...revision, decidedAt: iso(revision.decidedAt)! })),
    })),
    availableOffers: row.availableOffers ?? [],
    notices: (row.notices ?? []).map(item => ({ ...item, createdAt: iso(item.createdAt)! })),
    dunning: row.dunning ?? null,
    version: row.version,
  };
}

/** Les refus de la base deviennent des refus métier lisibles, en lecture comme en écriture. */
const refused = async <T>(work: () => Promise<T>): Promise<T> => {
  try { return await work(); } catch (error) { throw databaseRefusal(error) ?? error; }
};

/**
 * Autorisation commerciale propre (`drivy.current_school_commercial`) : responsable actif, quel que soit l'état de l'école.
 * Une école archivée, suspendue ou résiliée garde donc ses documents et son contact ; rien ici ne rouvre un droit.
 */
export function registerSchoolSubscription(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier }) {
  const envelope = (data: unknown, request: FastifyRequest) => ({ data, requestId: request.id, serverTime: new Date().toISOString() });
  const base = '/v1/schools/:schoolId/subscription';

  app.get(base, async (request, reply) => {
    const identity = await options.verifyToken(request.headers.authorization);
    const { schoolId } = schoolParams.parse(request.params); emptyQuery.parse(request.query);
    const row = await refused(() => withActor(options.pool, identity, schoolId, async db =>
      (await db.query<{ view: SubscriptionRow }>('SELECT drivy.school_commercial_view($1::uuid) AS view', [schoolId])).rows[0]!.view));
    const data = subscriptionView(row);
    reply.header('ETag', `"${data.version}"`).header('Cache-Control', 'no-store');
    return envelope(data, request);
  });

  app.post(`${base}/requests`, async (request, reply) => {
    const identity = await options.verifyToken(request.headers.authorization);
    const { schoolId } = schoolParams.parse(request.params); emptyQuery.parse(request.query);
    const body = subscriptionRequestBody.parse(request.body);
    checkIdempotency(request.headers['idempotency-key'], body.operationId);
    if (body.desiredOn && body.desiredOn > addDays(zurichDay(new Date()), maxAheadDays)) throw new ApiError(400, 'INVALID_REQUEST', 'La date est trop éloignée.');
    const data = await refused(() => schoolCommand(options.pool, identity, schoolId, 'CREATE_SUBSCRIPTION_REQUEST', body, null, async db => {
      const id = randomUUID();
      await db.query('SELECT drivy.school_commercial_request_create($1,$2,$3,$4,$5::text[],$6::date,$7)',
        [schoolId, id, body.kind, body.offerId ?? null, body.modules ?? [], body.desiredOn ?? null, body.details ?? null]);
      // Le motif reste sur la demande : il n'est pas recopié dans l'audit de l'école.
      return { data: { id, status: 'RECEIVED' as 'RECEIVED' | 'WITHDRAWN', version: 1 }, action: 'CREATE_SUBSCRIPTION_REQUEST', resourceType: 'SubscriptionRequest',
        resourceId: id, resourceVersion: 1, changedFields: ['status'] };
    }, ['ADMIN'], { allowArchived: true }));
    reply.status(201);
    return envelope(data, request);
  });

  app.post(`${base}/requests/:requestId/withdraw`, async (request, reply) => {
    const identity = await options.verifyToken(request.headers.authorization);
    const { schoolId, requestId } = requestParams.parse(request.params); emptyQuery.parse(request.query);
    const body = subscriptionCommandBody.parse(request.body);
    const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    // La demande visée fait partie de l'empreinte : la même clé ne peut pas en retirer une autre.
    const command = { ...body, requestId };
    const data = await refused(() => schoolCommand(options.pool, identity, schoolId, 'WITHDRAW_SUBSCRIPTION_REQUEST', command, expected, async db => {
      const version = (await db.query<{ version: number | null }>('SELECT drivy.school_commercial_request_withdraw($1,$2,$3) AS version', [schoolId, requestId, expected])).rows[0]?.version;
      if (version == null) throw notFound();
      return { data: { id: requestId, status: 'WITHDRAWN' as 'RECEIVED' | 'WITHDRAWN', version }, action: 'WITHDRAW_SUBSCRIPTION_REQUEST', resourceType: 'SubscriptionRequest',
        resourceId: requestId, resourceVersion: version, changedFields: ['status'] };
    }, ['ADMIN'], { allowArchived: true }));
    reply.status(200);
    return envelope(data, request);
  });

  app.post(`${base}/notices/read`, async (request, reply) => {
    const identity = await options.verifyToken(request.headers.authorization);
    const { schoolId } = schoolParams.parse(request.params); emptyQuery.parse(request.query);
    const body = subscriptionCommandBody.parse(request.body);
    checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const data = await refused(() => schoolCommand(options.pool, identity, schoolId, 'ACKNOWLEDGE_SUBSCRIPTION_NOTICES', body, null, async db => {
      const read = (await db.query<{ read: number }>('SELECT drivy.school_commercial_notice_read($1) AS read', [schoolId])).rows[0]?.read ?? 0;
      return { data: { schoolId, read }, action: 'ACKNOWLEDGE_SUBSCRIPTION_NOTICES', resourceType: 'School', resourceId: schoolId, resourceVersion: 1, changedFields: ['read_at'] };
    }, ['ADMIN'], { allowArchived: true }));
    reply.status(200);
    return envelope(data, request);
  });

  // Seul le document déjà conservé est servi : cette route n'en génère jamais et ne dépend pas de l'état de l'école.
  app.get(`${base}/invoices/:invoiceId/document`, async (request, reply) => {
    const identity = await options.verifyToken(request.headers.authorization);
    const { schoolId, invoiceId } = invoiceParams.parse(request.params); emptyQuery.parse(request.query);
    const file = await refused(() => withActor(options.pool, identity, schoolId, async db =>
      (await db.query<{ invoice_kind: InvoiceKind; invoice_number: string; content: Buffer | null }>(
        'SELECT invoice_kind,invoice_number,content FROM drivy.school_invoice_document($1,$2)', [schoolId, invoiceId])).rows[0]));
    if (!file) throw notFound();
    if (!file.content) throw new ApiError(409, 'DOCUMENT_UNAVAILABLE', 'Le document de cette facture n’est pas encore disponible.');
    return reply.header('content-type', 'application/pdf')
      .header('content-disposition', `attachment; filename="${invoiceFileName(file.invoice_kind, file.invoice_number)}"`)
      .header('cache-control', 'no-store').header('x-content-type-options', 'nosniff').send(file.content);
  });
}
