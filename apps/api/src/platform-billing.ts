import { createHash, randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { encryptBillingMail, maskEmail, type BillingMailConfig } from './billing-mail.js';
import { checkIdempotency, requireVersion } from './commands.js';
import { ApiError, notFound } from './errors.js';
import {
  activationBody, activationStopBody, billingView, cancelBody, creditBody, deliveryBody, documentBody, documentQuery, invoiceListQuery, invoiceView, issueBody,
  issuerBody, issuerView, prepareBody, runBody, sentBody, type ActivationRow, type BillingView, type InvoiceListQuery, type InvoiceRow, type IssuerRow,
} from './platform-billing-model.js';
import { commercialView, lockedClient } from './platform-commercial.js';
import { addDays, maxAheadDays } from './platform-commercial-model.js';
import { platformCommand, platformRead } from './platform-command.js';
import { invoiceFileName, invoiceMailContent, invoicePdfGenerator, renderInvoicePdf } from './platform-invoice-pdf.js';
import { documentMode, paymentPlan, type PaymentMode, type QrProblem } from './platform-invoice-qr.js';
import {
  allocateBody, correctBody, paymentBody, regularizationCancelBody, regularizeBody, releaseBody, voidBody, type DebtRow, type PaymentRow,
} from './platform-payments-model.js';

const empty = z.object({}).strict();
const idParams = z.object({ id: z.uuid() }).strict();
const invoiceParams = z.object({ id: z.uuid(), invoiceId: z.uuid() }).strict();
const invoiceOnlyParams = z.object({ invoiceId: z.uuid() }).strict();
const paymentParams = z.object({ id: z.uuid(), paymentId: z.uuid() }).strict();
const allocationParams = z.object({ id: z.uuid(), paymentId: z.uuid(), allocationId: z.uuid() }).strict();
const regularizationParams = z.object({ id: z.uuid(), paymentId: z.uuid(), regularizationId: z.uuid() }).strict();

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
    'credited_number', (SELECT x.number FROM drivy.platform_invoice x WHERE x.id = i.credits_invoice_id),
    'settlement', drivy.platform_invoice_settlement(i.id),
    'allocations', coalesce((SELECT jsonb_agg(jsonb_build_object('id', a.id, 'payment_id', a.payment_id, 'amount', a.amount,
        'received_on', p.received_on, 'method', p.method, 'created_at', a.created_at,
        'created_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = a.created_by)) ORDER BY a.created_at, a.id)
      FROM drivy.platform_payment_allocation a JOIN drivy.platform_payment p ON p.id = a.payment_id
      WHERE a.invoice_id = i.id AND a.status = 'ACTIVE'), '[]'::jsonb),
    'documents', coalesce((SELECT jsonb_agg(jsonb_build_object('id', d.id, 'revision', d.revision, 'payment_mode', d.payment_mode,
        'reference_type', d.reference_type, 'reference', d.reference, 'amount', d.amount, 'byte_size', d.byte_size, 'sha256', d.sha256, 'created_at', d.created_at,
        'created_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = d.created_by)) ORDER BY d.revision DESC)
      FROM drivy.platform_invoice_document d WHERE d.invoice_id = i.id), '[]'::jsonb),
    'delivery', (SELECT jsonb_build_object('id', m.id, 'status', m.status, 'recipient_masked', m.recipient_masked, 'attempts', m.attempts,
        'failure_code', m.failure_code, 'document_id', m.document_id, 'resend_of', m.resend_of, 'requested_at', m.requested_at, 'accepted_at', m.accepted_at,
        'finished_at', m.finished_at, 'requested_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = m.requested_by))
      FROM drivy.platform_invoice_delivery m WHERE m.invoice_id = i.id ORDER BY m.requested_at DESC, m.id DESC LIMIT 1)) AS row
  FROM drivy.platform_invoice i JOIN drivy.platform_client c ON c.id = i.client_id`;

/** Lecture d'un règlement : auteurs, correction, reste relu en base, affectations (libérées comprises) et régularisations. */
const paymentSelect = `SELECT to_jsonb(p) - 'recorded_by' - 'voided_by' || jsonb_build_object(
    'recorded_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = p.recorded_by),
    'voided_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = p.voided_by),
    'corrected_by_id', (SELECT n.id FROM drivy.platform_payment n WHERE n.corrects_payment_id = p.id),
    'available', drivy.platform_payment_available(p.id),
    'allocations', coalesce((SELECT jsonb_agg(jsonb_build_object('id', a.id, 'invoice_id', a.invoice_id, 'invoice_number', i.number, 'amount', a.amount,
        'status', a.status, 'created_at', a.created_at, 'released_at', a.released_at, 'release_cause', a.release_cause, 'release_reason', a.release_reason,
        'created_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = a.created_by),
        'released_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = a.released_by)) ORDER BY a.created_at, a.id)
      FROM drivy.platform_payment_allocation a JOIN drivy.platform_invoice i ON i.id = a.invoice_id WHERE a.payment_id = p.id), '[]'::jsonb),
    'regularizations', coalesce((SELECT jsonb_agg(jsonb_build_object('id', r.id, 'amount', r.amount, 'kind', r.kind, 'reason', r.reason,
        'status', r.status, 'created_at', r.created_at, 'cancelled_at', r.cancelled_at, 'cancel_reason', r.cancel_reason,
        'created_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = r.created_by),
        'cancelled_by_name', (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = r.cancelled_by)) ORDER BY r.created_at, r.id)
      FROM drivy.platform_payment_regularization r WHERE r.payment_id = p.id), '[]'::jsonb)) AS row
  FROM drivy.platform_payment p`;

async function readToday(db: PoolClient): Promise<string> {
  return (await db.query<{ today: string }>('SELECT drivy.zurich_today()::text AS today')).rows[0]!.today;
}
async function readInvoice(db: PoolClient, invoiceId: string, clientId?: string): Promise<InvoiceRow> {
  const row = (await db.query<{ row: InvoiceRow }>(`${invoiceSelect} WHERE i.id = $1 AND ($2::uuid IS NULL OR i.client_id = $2)`,
    [invoiceId, clientId ?? null])).rows[0]?.row;
  if (!row) throw notFound();
  return row;
}
async function readPayment(db: PoolClient, paymentId: string, clientId: string): Promise<PaymentRow> {
  const row = (await db.query<{ row: PaymentRow }>(`${paymentSelect} WHERE p.id = $1 AND p.client_id = $2`, [paymentId, clientId])).rows[0]?.row;
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
  // Prêt : un émetteur existe et permet une section de paiement valable.
  const issuer = (await db.query<{ problem: string | null }>(`SELECT drivy.platform_billing_issuer_problem(i) AS problem
    FROM drivy.platform_billing_issuer i ORDER BY i.sequence DESC LIMIT 1`)).rows[0];
  const issuerReady = issuer !== undefined && issuer.problem === null;
  const payments = (await db.query<{ row: PaymentRow }>(`${paymentSelect} WHERE p.client_id = $1 ORDER BY p.received_on DESC, p.recorded_at DESC, p.id DESC
    LIMIT 200`, [clientId])).rows.map(item => item.row);
  const debt = (await db.query<{ debt: DebtRow }>('SELECT drivy.platform_client_debt($1) AS debt', [clientId])).rows[0]!.debt;
  const version = (await db.query<{ version: number }>('SELECT drivy.platform_client_billing_version($1) AS version', [clientId])).rows[0]!.version;
  return billingView({
    commercial, activation: activations.find(item => item.status === 'ACTIVE') ?? null, activations, invoices, issuerReady, version, payments, debt,
  });
}

// --- Documents et envois (R01-T07, #459) -----------------------------------------------------------------------------------------------

const notIssued = () => new ApiError(409, 'INVOICE_NOT_ISSUED', 'Ce document n’est pas émis.');
const mailNotConfigured = 'L’envoi des factures n’est pas configuré.';
const contactMissing = 'Renseignez l’adresse du contact de facturation de l’école.';

type IssuedRow = InvoiceRow & { number: string; issued_on: string; issuer: Record<string, string | null>; recipient: Record<string, string | null> };
function issued(row: InvoiceRow): IssuedRow {
  if (row.status !== 'ISSUED' || !row.number || !row.issued_on || !row.issuer || !row.recipient) throw notIssued();
  return row as IssuedRow;
}
async function contactEmail(db: PoolClient, clientId: string) {
  return (await db.query<{ contact_email: string | null }>('SELECT contact_email FROM drivy.platform_client WHERE id = $1', [clientId])).rows[0]?.contact_email ?? null;
}
const mailContent = (row: IssuedRow, mode: PaymentMode) => invoiceMailContent({
  kind: row.kind, number: row.number, creditedNumber: row.credited_number, total: row.total ?? 0, dueOn: row.due_on,
  issuerName: row.issuer.legalName ?? '', mode,
});
const mayHaveBeenSent = (row: InvoiceRow) => row.send_status === 'SENT' || row.delivery?.status === 'ACCEPTED' || row.delivery?.status === 'UNCERTAIN';

/** Ce qui empêche l'envoi, pour l'aperçu. La base relit les mêmes règles au moment de mettre en file. */
function deliveryProblems(row: IssuedRow, mode: PaymentMode, to: string | null, configured: boolean): { code: string; message: string }[] {
  const problems: { code: string; message: string }[] = [];
  if (!configured) problems.push({ code: 'BILLING_MAIL_NOT_CONFIGURED', message: mailNotConfigured });
  if (!to) problems.push({ code: 'BILLING_CONTACT_MISSING', message: contactMissing });
  if (row.delivery?.status === 'QUEUED' || row.delivery?.status === 'PROCESSING') {
    problems.push({ code: 'INVOICE_DELIVERY_ACTIVE', message: 'Un envoi de cette facture est déjà en cours.' });
  }
  if (row.settlement?.state === 'CREDITED') problems.push({ code: 'INVOICE_DELIVERY_CREDITED', message: 'Cette facture est créditée. Envoyez l’avoir.' });
  else if (mode === 'QR' && row.settlement && row.settlement.state !== 'UNPAID') {
    problems.push({ code: 'INVOICE_DELIVERY_SETTLED', message: 'Cette facture est déjà réglée au moins en partie : son QR ne correspond plus au solde.' });
  }
  if (mode === 'QR' && !row.documents.some(item => item.payment_mode === 'QR')) {
    const plan = paymentPlan(row);
    if (!plan.ok) problems.push(...plan.problems.map((item: QrProblem) => ({ code: item.code, message: item.message })));
  }
  return problems;
}

/** Rend le document du mode voulu s'il n'existe pas encore. Depuis l'instantané seul, sous le verrou de la fiche ; un document existant est repris tel quel. */
async function ensureDocument(db: PoolClient, invoiceId: string, clientId: string) {
  const row = issued(await readInvoice(db, invoiceId, clientId));
  const mode = documentMode(row, row.documents);
  const existing = row.documents.find(item => item.payment_mode === mode);
  if (existing) return { row, document: existing, created: false };
  let plan = null;
  if (mode === 'QR') {
    const result = paymentPlan(row);
    if (!result.ok) throw new ApiError(409, 'INVOICE_QR_INVALID', result.problems[0]!.message);
    plan = result.plan;
  }
  const content = await renderInvoicePdf({
    kind: row.kind, number: row.number, creditedNumber: row.credited_number, issuedOn: row.issued_on, issuedAt: row.issued_at, dueOn: row.due_on,
    period: row.period_start && row.period_end ? { startsOn: row.period_start, endsOn: row.period_end } : null,
    issuer: row.issuer, recipient: row.recipient, lines: row.lines, subtotal: row.subtotal, discountTotal: row.discount_total, netTotal: row.net_total,
    tax: row.tax_mode === null ? null : { mode: row.tax_mode, rateBp: row.tax_rate_bp, pricesIncludeTax: row.prices_include_tax, amount: row.tax_amount ?? 0 },
    total: row.total ?? 0, payment: plan?.data ?? null,
  });
  const stored = (await db.query<{ id: string }>('SELECT drivy.platform_invoice_document_store($1,$2,$3,$4,$5,$6,$7,$8,$9) AS id', [randomUUID(), invoiceId, mode,
    plan?.referenceType ?? null, plan?.reference ?? null, plan?.amount ?? 0, content, createHash('sha256').update(content).digest('hex'), invoicePdfGenerator])).rows[0]!.id;
  const fresh = issued(await readInvoice(db, invoiceId, clientId));
  return { row: fresh, document: fresh.documents.find(item => item.id === stored)!, created: true };
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
  // Retard et état de règlement : le calcul de la base, le même que celui de la fiche et de la suspension.
  if (query.overdue) add(index => `coalesce((drivy.platform_invoice_settlement(i.id, ${index}::date)->>'overdue')::boolean, false)`, today);
  if (query.settlement) add(index => `drivy.platform_invoice_settlement(i.id)->>'state' = ${index}`, query.settlement);
  return { where: clauses.length ? `WHERE ${clauses.join(' AND ')}` : '', values };
}

/**
 * Factures, avoirs, émetteur et préparation planifiée (R01-T05, #457), puis règlements manuels (R01-T06, #458). Écritures par `platformCommand`
 * (équipe relue en base, reçu, journal, effet dans un même commit) ; les montants, numéros et figements sont décidés par les fonctions de la base.
 * Le journal reçoit l'action, les identifiants, numéros et montants ; jamais un motif.
 */
export function registerPlatformBilling(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier; billingMail?: BillingMailConfig }) {
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
          tax_rate_bp,prices_include_tax,tax_note,created_by,building_number,account_holder) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)`,
      [id, sequence, body.legalName, body.street, body.postalCode, body.city, body.country, body.email, body.iban, body.taxMode, body.vatNumber,
        body.taxRateBp, body.pricesIncludeTax, body.taxNote, actor.operatorId, body.buildingNumber, body.accountHolder]);
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
      return { items: rows.map(item => invoiceView(item.row)), total, limit: query.limit, offset: query.offset, today };
    }), request);
  });
  app.get('/v1/platform/invoices/:invoiceId', async request => {
    const identity = await identityOf(request); empty.parse(request.query); const { invoiceId } = invoiceOnlyParams.parse(request.params);
    return envelope(await platformRead(options.pool, identity, async db => invoiceView(await readInvoice(db, invoiceId))), request);
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
  type Route = { id: string; invoiceId?: string; paymentId?: string; allocationId?: string; regularizationId?: string };
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
        // Un règlement d'une autre fiche, ou une affectation ou régularisation d'un autre règlement, n'existe pas ici.
        if (route.paymentId) {
          const payment = await readPayment(db, route.paymentId, id);
          if (route.allocationId && !payment.allocations.some(item => item.id === route.allocationId)) throw notFound();
          if (route.regularizationId && !payment.regularizations.some(item => item.id === route.regularizationId)) throw notFound();
        }
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

  // --- Documents PDF et envoi (R01-T07, #459) ----------------------------------------------------------------------------------------
  // Générer, télécharger ou envoyer ne change ni le paiement ni l'échéance. Seule une acceptation SMTP marque la facture envoyée.
  command('/invoices/:invoiceId/document', 'GENERATE_INVOICE_DOCUMENT', documentBody, async (db, _actor, _before, _body, { id, invoiceId }) => {
    const { row, document, created } = await ensureDocument(db, invoiceId!, id);
    return { status: created ? 201 : 200, journal: { action: 'GENERATE_INVOICE_DOCUMENT', changes: {
      invoiceId, number: row.number, documentId: document.id, revision: document.revision, paymentMode: document.payment_mode, amount: document.amount, created,
    } } };
  }, invoiceParams);

  // Téléchargement authentifié : la facture doit appartenir à la fiche demandée. Aucune URL publique, aucun cache.
  app.get(`${base}/invoices/:invoiceId/document`, async (request, reply) => {
    const identity = await identityOf(request); const query = documentQuery.parse(request.query); const { id, invoiceId } = invoiceParams.parse(request.params);
    const file = await platformRead(options.pool, identity, async db => {
      const found = (await db.query<{ content: Buffer; kind: InvoiceRow['kind']; number: string }>(`SELECT d.content, i.kind, i.number
        FROM drivy.platform_invoice_document d JOIN drivy.platform_invoice i ON i.id = d.invoice_id AND i.client_id = d.client_id
        WHERE d.invoice_id = $1 AND d.client_id = $2 AND ($3::smallint IS NULL OR d.revision = $3) ORDER BY d.revision DESC LIMIT 1`,
      [invoiceId, id, query.revision ?? null])).rows[0];
      if (!found) throw notFound();
      return found;
    });
    return reply.header('content-type', 'application/pdf').header('content-disposition', `attachment; filename="${invoiceFileName(file.kind, file.number)}"`)
      .header('cache-control', 'no-store').header('x-content-type-options', 'nosniff').send(file.content);
  });

  app.get(`${base}/invoices/:invoiceId/delivery/preview`, async request => {
    const identity = await identityOf(request); empty.parse(request.query); const { id, invoiceId } = invoiceParams.parse(request.params);
    return envelope(await platformRead(options.pool, identity, async db => {
      const row = issued(await readInvoice(db, invoiceId, id));
      const to = await contactEmail(db, id);
      const mode = documentMode(row, row.documents);
      const problems = deliveryProblems(row, mode, to, options.billingMail !== undefined);
      return {
        to, ...mailContent(row, mode), fileName: invoiceFileName(row.kind, row.number), paymentMode: mode, amount: mode === 'QR' ? row.total ?? 0 : 0,
        resend: mayHaveBeenSent(row), ready: problems.length === 0, problems,
      };
    }), request);
  });

  // Mise en file après aperçu. Le contenu est chiffré ici ; la base refuse un second envoi en cours et un renvoi non demandé.
  command('/invoices/:invoiceId/delivery', 'QUEUE_INVOICE_DELIVERY', deliveryBody, async (db, _actor, _before, body, { id, invoiceId }) => {
    const mail = options.billingMail;
    if (!mail) throw new ApiError(409, 'BILLING_MAIL_NOT_CONFIGURED', mailNotConfigured);
    const email = await contactEmail(db, id);
    if (!email) throw new ApiError(409, 'BILLING_CONTACT_MISSING', contactMissing);
    const { row, document } = await ensureDocument(db, invoiceId!, id);
    const content = (await db.query<{ content: Buffer }>('SELECT content FROM drivy.platform_invoice_document WHERE id = $1', [document.id])).rows[0]!.content;
    const deliveryId = randomUUID();
    const payload = encryptBillingMail(deliveryId, {
      email, ...mailContent(row, document.payment_mode), fileName: invoiceFileName(row.kind, row.number), pdf: content.toString('base64'),
    }, mail.encryptionKey);
    await db.query('SELECT drivy.platform_invoice_delivery_queue($1,$2,$3,$4,$5,$6)', [deliveryId, invoiceId, document.id, payload, maskEmail(email), body.resend]);
    return { status: 201, journal: { action: 'QUEUE_INVOICE_DELIVERY', changes: {
      invoiceId, number: row.number, deliveryId, documentId: document.id, revision: document.revision, paymentMode: document.payment_mode, resend: body.resend,
    } } };
  }, invoiceParams);

  // --- Règlements (R01-T06, #458) --------------------------------------------------------------------------------------------------
  // Faits confirmés à la main par l'équipe. La base relit l'école, le reste du règlement, le solde de la facture et le doublon probable, sous le
  // verrou de la fiche. Le journal reçoit montants, dates, moyen et identifiants ; jamais la référence, la note ni un motif.
  const activeParts = (items: readonly { invoiceId: string; amount: number; status: string }[]) =>
    items.filter(item => item.status === 'ACTIVE').map(item => ({ invoiceId: item.invoiceId, amount: item.amount }));

  command('/payments', 'RECORD_PAYMENT', paymentBody, async (db, _actor, _before, body, { id }) => {
    const paymentId = randomUUID();
    await db.query('SELECT drivy.platform_payment_record($1,$2,$3,$4,$5::date,$6,$7,$8,$9::jsonb,$10,$11)', [paymentId, id, body.amount, body.currency,
      body.receivedOn, body.method, body.reference, body.note, JSON.stringify(body.allocations), body.spread, body.confirmDuplicate]);
    const payment = await readPayment(db, paymentId, id);
    return { status: 201, journal: { action: 'RECORD_PAYMENT', changes: {
      paymentId, amount: payment.amount, receivedOn: payment.received_on, method: payment.method, spread: body.spread,
      allocations: payment.allocations.map(item => ({ invoiceId: item.invoice_id, amount: item.amount })), available: payment.available,
      duplicateConfirmed: body.confirmDuplicate,
    } } };
  });

  command('/payments/:paymentId/allocations', 'ALLOCATE_PAYMENT', allocateBody, async (db, _actor, _before, body, { paymentId }) => {
    const allocationId = (await db.query<{ id: string }>('SELECT drivy.platform_payment_allocate($1,$2,$3) AS id',
      [paymentId, body.invoiceId, body.amount])).rows[0]!.id;
    return { status: 201, journal: { action: 'ALLOCATE_PAYMENT', changes: { paymentId, allocationId, invoiceId: body.invoiceId, amount: body.amount } } };
  }, paymentParams);

  command('/payments/:paymentId/allocations/:allocationId/release', 'RELEASE_ALLOCATION', releaseBody,
    async (db, _actor, before, body, { paymentId, allocationId }) => {
      const allocation = before.payments.find(item => item.id === paymentId)?.allocations.find(item => item.id === allocationId);
      await db.query('SELECT drivy.platform_payment_release($1,$2)', [allocationId, body.reason]);
      return { journal: { action: 'RELEASE_ALLOCATION', changes: {
        paymentId, allocationId, invoiceId: allocation?.invoiceId ?? null, amount: allocation?.amount ?? null,
      } } };
    }, allocationParams);

  // Annulation d'une erreur de saisie : le règlement reste lisible, ses affectations sont libérées.
  command('/payments/:paymentId/void', 'VOID_PAYMENT', voidBody, async (db, _actor, before, body, { paymentId }) => {
    const payment = before.payments.find(item => item.id === paymentId);
    await db.query('SELECT drivy.platform_payment_void($1,$2)', [paymentId, body.reason]);
    return { journal: { action: 'VOID_PAYMENT', changes: {
      paymentId, amount: payment?.amount ?? null, released: payment ? activeParts(payment.allocations) : [],
    } } };
  }, paymentParams);

  // Correction : l'original reste (annulé, avec son auteur) ; le nouveau règlement reprend ses factures jusqu'à son montant.
  command('/payments/:paymentId/correct', 'CORRECT_PAYMENT', correctBody, async (db, _actor, before, body, { id, paymentId }) => {
    const original = before.payments.find(item => item.id === paymentId);
    const correctionId = randomUUID();
    await db.query('SELECT drivy.platform_payment_correct($1,$2,$3,$4,$5::date,$6,$7,$8,$9)', [paymentId, correctionId, body.amount, body.currency,
      body.receivedOn, body.method, body.reference, body.note, body.reason]);
    const correction = await readPayment(db, correctionId, id);
    return { status: 201, journal: { action: 'CORRECT_PAYMENT', changes: {
      paymentId, correctionId,
      before: original ? { amount: original.amount, receivedOn: original.receivedOn, method: original.method, allocations: activeParts(original.allocations) } : null,
      after: { amount: correction.amount, receivedOn: correction.received_on, method: correction.method,
        allocations: correction.allocations.map(item => ({ invoiceId: item.invoice_id, amount: item.amount })) },
    } } };
  }, paymentParams);

  // Régularisation explicite du reste non affecté : jamais déduite d'un avoir ni d'une correction.
  command('/payments/:paymentId/regularizations', 'REGULARIZE_PAYMENT', regularizeBody, async (db, _actor, _before, body, { paymentId }) => {
    const regularizationId = randomUUID();
    await db.query('SELECT drivy.platform_payment_regularize($1,$2,$3,$4,$5)', [paymentId, regularizationId, body.amount, body.kind, body.reason]);
    return { status: 201, journal: { action: 'REGULARIZE_PAYMENT', changes: { paymentId, regularizationId, amount: body.amount, kind: body.kind } } };
  }, paymentParams);

  command('/payments/:paymentId/regularizations/:regularizationId/cancel', 'CANCEL_REGULARIZATION', regularizationCancelBody,
    async (db, _actor, before, body, { paymentId, regularizationId }) => {
      const regularization = before.payments.find(item => item.id === paymentId)?.regularizations.find(item => item.id === regularizationId);
      await db.query('SELECT drivy.platform_payment_regularization_cancel($1,$2)', [regularizationId, body.reason]);
      return { journal: { action: 'CANCEL_REGULARIZATION', changes: {
        paymentId, regularizationId, amount: regularization?.amount ?? null, kind: regularization?.kind ?? null,
      } } };
    }, regularizationParams);
}
