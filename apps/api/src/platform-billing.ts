import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { checkIdempotency, requireVersion } from './commands.js';
import { ApiError, notFound } from './errors.js';
import {
  activationBody, activationStopBody, billingView, cancelBody, creditBody, invoiceListQuery, invoiceView, issueBody, issuerBody, issuerView, prepareBody,
  runBody, sentBody, type ActivationRow, type BillingView, type InvoiceListQuery, type InvoiceRow, type IssuerRow,
} from './platform-billing-model.js';
import { commercialView, lockedClient } from './platform-commercial.js';
import { addDays, maxAheadDays } from './platform-commercial-model.js';
import { platformCommand, platformRead } from './platform-command.js';

const empty = z.object({}).strict();
const idParams = z.object({ id: z.uuid() }).strict();
const invoiceParams = z.object({ id: z.uuid(), invoiceId: z.uuid() }).strict();
const invoiceOnlyParams = z.object({ invoiceId: z.uuid() }).strict();

const billingConflict = () => new ApiError(412, 'VERSION_CONFLICT', 'La facturation de cette école a changé. Rechargez-la avant de confirmer.');
const issuerConflict = () => new ApiError(412, 'VERSION_CONFLICT', 'Les paramètres de facturation ont changé. Rechargez-les avant de confirmer.');

/** Lecture d'une facture avec ce que l'équipe affiche : fiche, auteurs, avoir lié. Lue sous les politiques de l'équipe (RLS). */
const invoiceSelect = `SELECT to_jsonb(i) || jsonb_build_object(
    'client_name', coalesce(c.display_name, i.recipient->>'name'), 'school_id', c.school_id,
    'prepared_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = i.prepared_by),
    'issued_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = i.issued_by),
    'cancelled_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = i.cancelled_by),
    'sent_recorded_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = i.sent_recorded_by),
    'credit_note', (SELECT jsonb_build_object('id', n.id, 'number', n.number, 'total', n.total, 'issued_on', n.issued_on)
       FROM drivy.platform_invoice n WHERE n.credits_invoice_id = i.id),
    'credited_number', (SELECT x.number FROM drivy.platform_invoice x WHERE x.id = i.credits_invoice_id)) AS row
  FROM drivy.platform_invoice i JOIN drivy.platform_client c ON c.id = i.client_id`;

async function readToday(db: PoolClient): Promise<string> {
  return (await db.query<{ today: string }>('SELECT drivy.zurich_today()::text AS today')).rows[0]!.today;
}
async function readInvoice(db: PoolClient, invoiceId: string, clientId?: string): Promise<InvoiceRow> {
  const row = (await db.query<{ row: InvoiceRow }>(`${invoiceSelect} WHERE i.id = $1 AND ($2::uuid IS NULL OR i.client_id = $2)`,
    [invoiceId, clientId ?? null])).rows[0]?.row;
  if (!row) throw notFound();
  return row;
}
async function readIssuers(db: PoolClient): Promise<IssuerRow[]> {
  return (await db.query<{ row: IssuerRow }>(`SELECT to_jsonb(i) || jsonb_build_object('created_by_name',
      (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = i.created_by)) AS row
    FROM drivy.platform_billing_issuer i ORDER BY i.sequence DESC LIMIT 50`)).rows.map(item => item.row);
}
async function issuerSettings(db: PoolClient) {
  const versions = await readIssuers(db);
  const count = (await db.query<{ n: number }>('SELECT count(*)::int AS n FROM drivy.platform_billing_issuer')).rows[0]!.n;
  return { current: versions[0] ? issuerView(versions[0]) : null, versions: versions.map(issuerView), version: count + 1 };
}

async function billingDetail(db: PoolClient, clientId: string): Promise<BillingView> {
  const commercial = await commercialView(db, clientId);
  const activations = (await db.query<{ row: ActivationRow }>(`SELECT to_jsonb(a) || jsonb_build_object(
      'activated_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = a.activated_by),
      'stopped_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = a.stopped_by)) AS row
    FROM drivy.platform_billing_activation a WHERE a.client_id = $1 ORDER BY a.activated_at DESC, a.id DESC LIMIT 20`, [clientId])).rows.map(item => item.row);
  const invoices = (await db.query<{ row: InvoiceRow }>(`${invoiceSelect} WHERE i.client_id = $1 ORDER BY i.prepared_at DESC, i.id DESC LIMIT 200`, [clientId]))
    .rows.map(item => item.row);
  const issuerReady = ((await db.query('SELECT 1 FROM drivy.platform_billing_issuer LIMIT 1')).rowCount ?? 0) > 0;
  const version = (await db.query<{ version: number }>('SELECT drivy.platform_client_billing_version($1) AS version', [clientId])).rows[0]!.version;
  return billingView({ commercial, activation: activations.find(item => item.status === 'ACTIVE') ?? null, activations, invoices, issuerReady, version });
}

/** Filtres de la liste des factures, en paramètres liés uniquement. */
function invoiceFilters(query: InvoiceListQuery, today: string) {
  const clauses: string[] = []; const values: unknown[] = [];
  const add = (clause: (index: string) => string, value: unknown) => { values.push(value); clauses.push(clause(`$${values.length}`)); };
  if (query.clientId) add(index => `i.client_id = ${index}`, query.clientId);
  if (query.status) add(index => `i.status = ${index}`, query.status);
  if (query.kind) add(index => `i.kind = ${index}`, query.kind);
  if (query.sendStatus) add(index => `i.send_status = ${index}`, query.sendStatus);
  // Période facturée (les avoirs et l'initial se rangent à leur date d'émission, à défaut de préparation).
  if (query.from) add(index => `coalesce(i.period_start, i.issued_on, (i.prepared_at AT TIME ZONE 'Europe/Zurich')::date) >= ${index}::date`, query.from);
  if (query.to) add(index => `coalesce(i.period_start, i.issued_on, (i.prepared_at AT TIME ZONE 'Europe/Zurich')::date) <= ${index}::date`, query.to);
  if (query.dueBefore) add(index => `i.due_on < ${index}::date`, query.dueBefore);
  if (query.overdue) {
    add(index => `i.status = 'ISSUED' AND i.kind <> 'CREDIT_NOTE' AND i.due_on < ${index}::date
      AND NOT EXISTS(SELECT 1 FROM drivy.platform_invoice n WHERE n.credits_invoice_id = i.id)`, today);
  }
  return { where: clauses.length ? `WHERE ${clauses.join(' AND ')}` : '', values };
}

/**
 * Factures initiales et mensuelles, avoirs, paramètres de l'émetteur et préparation planifiée (R01-T05, #457). Écritures par `platformCommand`
 * (équipe relue en base, reçu, journal, effet dans un même commit) ; les montants, numéros et figements sont décidés par les fonctions de la base.
 * Le journal reçoit l'action, les identifiants, numéros et montants ; jamais un motif.
 */
export function registerPlatformBilling(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier }) {
  const envelope = (data: unknown, request: FastifyRequest) => ({ data, requestId: request.id, serverTime: new Date().toISOString() });
  const identityOf = (request: FastifyRequest) => options.verifyToken(request.headers.authorization);

  // --- Émetteur -----------------------------------------------------------------------------------------------------------------
  app.get('/v1/platform/billing/issuer', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    return envelope(await platformRead(options.pool, identity, db => issuerSettings(db)), request);
  });
  app.post('/v1/platform/billing/issuer', async (request, reply) => {
    const identity = await identityOf(request); empty.parse(request.query);
    const body = issuerBody.parse(request.body);
    const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const { operationId, ...content } = body;
    const result = await platformCommand(options.pool, identity, {
      kind: 'SET_BILLING_ISSUER', operationId, expectedVersion: expected, body: content, refusal: { action: 'SET_BILLING_ISSUER', subject: null },
    }, async (db, actor) => {
      await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', ['platform-billing-issuer']);
      const before = await issuerSettings(db);
      if (before.version !== expected) throw issuerConflict();
      const id = randomUUID(); const sequence = before.version;
      await db.query(`INSERT INTO drivy.platform_billing_issuer(id,sequence,legal_name,street,postal_code,city,country,email,iban,tax_mode,vat_number,
          tax_rate_bp,prices_include_tax,tax_note,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)`,
      [id, sequence, body.legalName, body.street, body.postalCode, body.city, body.country, body.email, body.iban, body.taxMode, body.vatNumber,
        body.taxRateBp, body.pricesIncludeTax, body.taxNote, actor.operatorId]);
      return { data: await issuerSettings(db), status: 201, journal: { action: 'SET_BILLING_ISSUER', subject: { type: 'PlatformBillingIssuer', id }, changes: {
        issuerId: id, sequence, taxMode: body.taxMode, taxRateBp: body.taxRateBp, pricesIncludeTax: body.pricesIncludeTax, country: body.country,
        hasIban: body.iban !== null, hasEmail: body.email !== null,
      } } };
    });
    reply.status(result.status); return envelope(result.data, request);
  });

  // --- Factures, toutes écoles ------------------------------------------------------------------------------------------------------
  app.get('/v1/platform/invoices', async request => {
    const identity = await identityOf(request); const query = invoiceListQuery.parse(request.query);
    return envelope(await platformRead(options.pool, identity, async db => {
      const today = await readToday(db);
      const { where, values } = invoiceFilters(query, today);
      const total = (await db.query<{ n: number }>(`SELECT count(*)::int AS n FROM drivy.platform_invoice i ${where}`, values)).rows[0]!.n;
      const rows = (await db.query<{ row: InvoiceRow }>(`${invoiceSelect} ${where}
        ORDER BY coalesce(i.issued_at, i.prepared_at) DESC, i.id DESC LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
      [...values, query.limit, query.offset])).rows;
      return { items: rows.map(item => invoiceView(item.row, today)), total, limit: query.limit, offset: query.offset, today };
    }), request);
  });
  app.get('/v1/platform/invoices/:invoiceId', async request => {
    const identity = await identityOf(request); empty.parse(request.query); const { invoiceId } = invoiceOnlyParams.parse(request.params);
    return envelope(await platformRead(options.pool, identity, async db => invoiceView(await readInvoice(db, invoiceId), await readToday(db))), request);
  });

  // Passage demandé par un opérateur : même traitement que le service planifié, au jour de Zurich. Sans version : il est idempotent par nature.
  app.post('/v1/platform/billing/run', async (request, reply) => {
    const identity = await identityOf(request); empty.parse(request.query);
    const body = runBody.parse(request.body); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const result = await platformCommand(options.pool, identity, {
      kind: 'RUN_BILLING', operationId: body.operationId, expectedVersion: null, body: {}, refusal: { action: 'RUN_BILLING', subject: null },
    }, async db => {
      const run = (await db.query<{ result: Record<string, unknown> }>('SELECT drivy.platform_billing_run_manual() AS result')).rows[0]!.result;
      return { data: run, journal: { action: 'RUN_BILLING', subject: null, changes: run } };
    });
    reply.status(result.status); return envelope(result.data, request);
  });

  // --- Facturation d'une fiche ------------------------------------------------------------------------------------------------------
  const base = '/v1/platform/clients/:id';
  app.get(`${base}/billing`, async request => {
    const identity = await identityOf(request); empty.parse(request.query); const { id } = idParams.parse(request.params);
    return envelope(await platformRead(options.pool, identity, db => billingDetail(db, id)), request);
  });

  type Effect = { status?: 200 | 201; journal: { action: string; changes: Record<string, unknown> } };
  type Route = { id: string; invoiceId?: string };
  /** Commande de facturation d'une fiche : verrou de la fiche, version relue, effet, facturation rendue. */
  function command<B extends { operationId: string }>(path: string, kind: string, schema: z.ZodType<B>,
    work: (db: PoolClient, actor: { operatorId: string }, before: BillingView, body: B, route: Route) => Promise<Effect>,
    params: z.ZodType<Route> = idParams) {
    app.post(`${base}${path}`, async (request, reply) => {
      const identity = await identityOf(request); empty.parse(request.query);
      const route = params.parse(request.params); const id = route.id; const body = schema.parse(request.body);
      const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
      const { operationId, ...content } = body as B & Record<string, unknown>;
      const result = await platformCommand(options.pool, identity, {
        kind, operationId, expectedVersion: expected, body: { ...route, ...content }, refusal: { action: kind, subject: { type: 'PlatformClient', id } },
      }, async (db, actor) => {
        const schoolId = await lockedClient(db, id);
        // Une facture d'une autre fiche n'existe pas ici.
        if (route.invoiceId) await readInvoice(db, route.invoiceId, id);
        const before = await billingDetail(db, id);
        if (before.version !== expected) throw billingConflict();
        const effect = await work(db, actor, before, body, route);
        return { data: await billingDetail(db, id), status: effect.status ?? 200,
          journal: { action: effect.journal.action, schoolId, subject: { type: 'PlatformClient', id }, changes: effect.journal.changes } };
      });
      reply.status(result.status); return envelope(result.data, request);
    });
  }

  // Activation de la préparation planifiée : jamais rétroactive ; une école facturable seulement (la base relit tout).
  command('/billing/activation', 'ACTIVATE_BILLING', activationBody, async (db, actor, before, body, { id }) => {
    if (before.activation) throw new ApiError(409, 'BILLING_ACTIVE', 'La facturation planifiée est déjà active pour cette école.');
    if (body.startsOn < before.today) throw new ApiError(409, 'EFFECTIVE_DATE_PAST', 'La date doit être aujourd’hui ou plus tard.');
    if (body.startsOn > addDays(before.today, maxAheadDays)) throw new ApiError(400, 'INVALID_REQUEST', 'La date est trop éloignée.');
    if (!before.billable) throw new ApiError(409, 'BILLING_NOT_READY', 'Confirmez d’abord un début payant sur des conditions complètes.');
    const activationId = randomUUID();
    await db.query('INSERT INTO drivy.platform_billing_activation(id,client_id,starts_on,activated_by) VALUES($1,$2,$3::date,$4)',
      [activationId, id, body.startsOn, actor.operatorId]);
    return { status: 201, journal: { action: 'ACTIVATE_BILLING', changes: { activationId, startsOn: body.startsOn } } };
  });

  command('/billing/activation/stop', 'STOP_BILLING', activationStopBody, async (db, actor, before, body, { id }) => {
    const activation = before.activation;
    if (!activation) throw new ApiError(409, 'BILLING_NOT_ACTIVE', 'La facturation planifiée n’est pas active pour cette école.');
    const updated = await db.query("UPDATE drivy.platform_billing_activation SET status='STOPPED',stopped_by=$3,stop_reason=$4 WHERE id=$1 AND client_id=$2 AND status='ACTIVE'",
      [activation.id, id, actor.operatorId, body.reason]);
    if (updated.rowCount !== 1) throw billingConflict();
    return { journal: { action: 'STOP_BILLING', changes: { activationId: activation.id, startsOn: activation.startsOn } } };
  });

  // Brouillon préparé par un opérateur : montant initial ou une période commencée (ou la prochaine). Le contenu est calculé par la base.
  command('/invoices', 'PREPARE_INVOICE', prepareBody, async (db, _actor, _before, body, { id }) => {
    const invoiceId = randomUUID();
    await db.query('SELECT drivy.platform_invoice_prepare($1,$2,$3::date,$4)', [id, body.kind, body.periodStart ?? null, invoiceId]);
    const row = await readInvoice(db, invoiceId, id);
    return { status: 201, journal: { action: 'PREPARE_INVOICE', changes: {
      invoiceId, kind: row.kind, generation: row.generation, periodStart: row.period_start, termsSequence: row.terms_sequence, netTotal: row.net_total,
    } } };
  });

  // Émission : numéro, émetteur, destinataire, taxe et échéance figés par la base, dans ce commit.
  command('/invoices/:invoiceId/issue', 'ISSUE_INVOICE', issueBody, async (db, _actor, _before, _body, { id, invoiceId }) => {
    await db.query('SELECT drivy.platform_invoice_issue($1)', [invoiceId]);
    const row = await readInvoice(db, invoiceId!, id);
    return { journal: { action: 'ISSUE_INVOICE', changes: {
      invoiceId, number: row.number, kind: row.kind, periodStart: row.period_start, total: row.total, taxAmount: row.tax_amount, issuedOn: row.issued_on, dueOn: row.due_on,
    } } };
  }, invoiceParams);

  command('/invoices/:invoiceId/cancel', 'CANCEL_INVOICE_DRAFT', cancelBody, async (db, _actor, _before, body, { id, invoiceId }) => {
    await db.query('SELECT drivy.platform_invoice_cancel($1,$2)', [invoiceId, body.reason]);
    const row = await readInvoice(db, invoiceId!, id);
    return { journal: { action: 'CANCEL_INVOICE_DRAFT', changes: { invoiceId, kind: row.kind, periodStart: row.period_start } } };
  }, invoiceParams);

  // Avoir total : la facture d'origine n'est jamais modifiée ; son solde tombe à zéro.
  command('/invoices/:invoiceId/credit', 'ISSUE_CREDIT_NOTE', creditBody, async (db, _actor, _before, body, { id, invoiceId }) => {
    const creditId = randomUUID();
    await db.query('SELECT drivy.platform_invoice_credit($1,$2,$3)', [invoiceId, body.reason, creditId]);
    const credit = await readInvoice(db, creditId, id);
    return { status: 201, journal: { action: 'ISSUE_CREDIT_NOTE', changes: {
      invoiceId, creditNoteId: creditId, number: credit.number, creditedNumber: credit.credited_number, total: credit.total,
    } } };
  }, invoiceParams);

  command('/invoices/:invoiceId/sent', 'MARK_INVOICE_SENT', sentBody, async (db, _actor, _before, body, { id, invoiceId }) => {
    await db.query('SELECT drivy.platform_invoice_mark_sent($1,$2::date)', [invoiceId, body.sentOn]);
    const row = await readInvoice(db, invoiceId!, id);
    return { journal: { action: 'MARK_INVOICE_SENT', changes: { invoiceId, number: row.number, sentOn: body.sentOn } } };
  }, invoiceParams);
}
