import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import nodemailer from 'nodemailer';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import { rollbackQuietly } from './database.js';

/**
 * Envoi des factures (R01-T07, #459) : même transport et mêmes pratiques que les invitations (`invitation-mail.ts`), dans un domaine commercial
 * distinct : clé, table, rôle et service à part. Le contenu reste chiffré dans la file et s'efface dès que l'envoi est terminé.
 *
 * Une acceptation SMTP n'est pas une preuve de livraison ni de lecture. Une erreur dont on ne peut pas dire si le serveur a reçu le message donne
 * UNCERTAIN : elle n'est jamais rejouée automatiquement, pour ne pas envoyer deux fois la même facture.
 */
export interface BillingMailConfig {
  encryptionKey: string; host: string; port: number; secure: boolean; from: string; requireTLS: boolean; user?: string; password?: string;
}
const loopback = (host: string) => ['localhost', '127.0.0.1', '[::1]', '::1'].includes(host);

/** `undefined` tant que la clé de la file n'est pas configurée : aucun envoi n'est alors accepté. */
export function billingMailConfig(env: NodeJS.ProcessEnv = process.env): BillingMailConfig | undefined {
  if (!env.BILLING_OUTBOX_KEY) return undefined;
  const host = z.string().min(1).parse(env.SMTP_HOST);
  const secure = z.enum(['true', 'false']).default('false').parse(env.SMTP_SECURE) === 'true';
  const user = env.SMTP_USER; const password = env.SMTP_PASSWORD;
  if (Boolean(user) !== Boolean(password)) throw new Error('Configuration SMTP incomplète.');
  return {
    encryptionKey: z.string().regex(/^[a-fA-F0-9]{64}$/).parse(env.BILLING_OUTBOX_KEY), host,
    port: z.coerce.number().int().min(1).max(65535).default(587).parse(env.SMTP_PORT), secure,
    from: z.email().parse(env.BILLING_MAIL_FROM ?? env.SMTP_FROM), requireTLS: env.NODE_ENV === 'production' || !loopback(host),
    ...(user && password ? { user, password } : {}),
  };
}

const payloadSchema = z.object({
  email: z.email(), subject: z.string().min(1).max(200), text: z.string().min(1).max(4000),
  fileName: z.string().regex(/^[A-Za-z0-9-]{1,60}\.pdf$/), pdf: z.base64().min(1),
}).strict();
export type BillingMailPayload = z.infer<typeof payloadSchema>;

export function encryptBillingMail(id: string, payload: BillingMailPayload, key: string): Buffer {
  const iv = randomBytes(12); const cipher = createCipheriv('aes-256-gcm', Buffer.from(key, 'hex'), iv);
  cipher.setAAD(Buffer.from(id));
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(payload), 'utf8'), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), ciphertext]);
}
export function decryptBillingMail(id: string, encrypted: Buffer, key: string): BillingMailPayload {
  const cipher = createDecipheriv('aes-256-gcm', Buffer.from(key, 'hex'), encrypted.subarray(0, 12));
  cipher.setAAD(Buffer.from(id)); cipher.setAuthTag(encrypted.subarray(12, 28));
  const value = JSON.parse(Buffer.concat([cipher.update(encrypted.subarray(28)), cipher.final()]).toString('utf8')) as unknown;
  return payloadSchema.parse(value);
}

/** Adresse lisible par l'équipe dans le suivi, sans la conserver en clair. */
export function maskEmail(email: string) {
  const [local = '', domain = ''] = email.split('@');
  return `${local.slice(0, 2)}***@${domain}`;
}

export type DeliveryOutcome = { outcome: 'ACCEPTED' | 'RETRY' | 'FAILED' | 'UNCERTAIN'; code: string | null };

/**
 * Classe une erreur d'envoi. Seuls une réponse explicite du serveur ou un échec survenu avant toute transmission permettent de conclure.
 * Nodemailer range sous `CONN` toute erreur de socket, y compris en plein DATA : une coupure ou un délai dépassé reste donc incertain.
 */
export function classifyDeliveryError(error: unknown): DeliveryOutcome {
  const { responseCode, code } = (error ?? {}) as { responseCode?: unknown; code?: unknown };
  if (typeof responseCode === 'number') {
    if (responseCode >= 400 && responseCode < 500) return { outcome: 'RETRY', code: 'SMTP_TEMPORARY' };
    if (responseCode >= 500 && responseCode < 600) return { outcome: 'FAILED', code: 'SMTP_REJECTED' };
  }
  if (typeof code === 'string' && ['EDNS', 'ETLS', 'EAUTH', 'ENOAUTH'].includes(code)) return { outcome: 'RETRY', code: 'SMTP_UNREACHABLE' };
  return { outcome: 'UNCERTAIN', code: 'SMTP_UNCERTAIN' };
}

interface Job { job_id: string; job_payload: Buffer; job_lease: string; job_attempts: number }
export interface BillingTransport {
  verify(): Promise<unknown>;
  sendMail(message: Record<string, unknown>): Promise<{ rejected?: unknown[] }>;
  close(): void;
}

async function workerTransaction<T>(pool: Pool, work: (db: PoolClient) => Promise<T>): Promise<T> {
  const db = await pool.connect(); let broken = false;
  try {
    await db.query('BEGIN'); await db.query('SET LOCAL ROLE drivy_billing_mailer');
    const result = await work(db);
    await db.query('COMMIT');
    return result;
  } catch (error) {
    broken = !(await rollbackQuietly(db));
    throw error;
  } finally {
    db.release(broken);
  }
}
const settle = (pool: Pool, job: Job, result: DeliveryOutcome) => workerTransaction(pool, db =>
  db.query('SELECT drivy.platform_invoice_delivery_settle($1,$2,$3,$4)', [job.job_id, job.job_lease, result.outcome, result.code]));

function createTransport(config: BillingMailConfig): BillingTransport {
  return nodemailer.createTransport({
    host: config.host, port: config.port, secure: config.secure, requireTLS: config.requireTLS,
    ...(config.user && config.password ? { auth: { user: config.user, pass: config.password } } : {}),
    logger: false, debug: false, connectionTimeout: 10_000, greetingTimeout: 10_000, socketTimeout: 20_000, disableFileAccess: true, disableUrlAccess: true,
  }) as unknown as BillingTransport;
}

async function attempt(transport: BillingTransport, config: BillingMailConfig, job: Job, payload: BillingMailPayload): Promise<DeliveryOutcome> {
  // Tant que la connexion n'est pas vérifiée, rien de la facture n'a quitté Drivy : la reprise est sûre.
  try { await transport.verify(); } catch { return { outcome: 'RETRY', code: 'SMTP_UNREACHABLE' }; }
  try {
    const info = await transport.sendMail({
      from: config.from, to: payload.email, subject: payload.subject, text: payload.text,
      messageId: `<drivy-invoice-${job.job_id}@${config.from.split('@')[1]}>`,
      attachments: [{ filename: payload.fileName, content: Buffer.from(payload.pdf, 'base64'), contentType: 'application/pdf' }],
    });
    return info.rejected?.length ? { outcome: 'FAILED', code: 'SMTP_REJECTED' } : { outcome: 'ACCEPTED', code: null };
  } catch (error) {
    return classifyDeliveryError(error);
  }
}

/**
 * Traite un envoi. Si l'écriture de l'issue échoue après une acceptation, l'envoi reste au bail et devient UNCERTAIN à son expiration :
 * il n'est pas rejoué.
 */
export async function deliverOneInvoice(pool: Pool, config: BillingMailConfig, transportFactory: (config: BillingMailConfig) => BillingTransport = createTransport) {
  const job = await workerTransaction(pool, async db => (await db.query<Job>('SELECT * FROM drivy.platform_invoice_delivery_claim()')).rows[0] ?? null);
  if (!job) return false;
  let payload: BillingMailPayload;
  try {
    payload = decryptBillingMail(job.job_id, job.job_payload, config.encryptionKey);
  } catch {
    await settle(pool, job, { outcome: 'FAILED', code: 'PAYLOAD_INVALID' });
    return true;
  }
  const transport = transportFactory(config);
  let result: DeliveryOutcome;
  try {
    result = await attempt(transport, config, job, payload);
  } finally {
    transport.close();
  }
  await settle(pool, job, result);
  return true;
}
