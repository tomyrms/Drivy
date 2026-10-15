import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';
import { AttemptLimiter } from './attempt-limiter.js';
import type { AccountProvisioner } from './account-provisioning.js';
import { rollbackQuietly } from './database.js';
import { ApiError } from './errors.js';
import { invitationCodeHasher, normalizeInvitationCode } from './invitation-code.js';
import { previewCode } from './invitations.js';
import { isOpeningCode, openingDigest, openingToken, type OpeningLinkRow } from './school-opening-model.js';

/**
 * « J'ai un code » : avant toute connexion, un code dit ce qu'il ouvre (rejoindre une école comme élève, ou ouvrir une école),
 * et lui seul permet de créer un compte. Le code n'est jamais consommé ici : il l'est ensuite, connecté, par les routes habituelles
 * (`/v1/invitations/code/accept`, `/v1/school-openings`), avec leurs verrous, leur idempotence et leur preuve.
 */
const empty = z.object({}).strict();
const codeBody = z.object({ code: openingToken }).strict();
const accountBody = z.object({ code: openingToken,
  firstName: z.string().trim().min(1).max(100), lastName: z.string().trim().min(1).max(100),
  email: z.email().max(254).transform(value => value.trim().normalize('NFC').toLowerCase()),
  password: z.string().min(8).max(128) }).strict();

export type AccessCodeKind = 'LEARNER_INVITATION' | 'SCHOOL_OPENING';
const invalid = () => new ApiError(404, 'ACCESS_CODE_INVALID', 'Ce code n’est pas valide ou n’est plus utilisable.');

async function previewOpening(pool: Pool, tokenHash: string) {
  const db = await pool.connect(); let broken = false;
  try {
    await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY'); await db.query('SET LOCAL ROLE drivy_app');
    await db.query("SELECT set_config('app.issuer','',true),set_config('app.subject','',true),set_config('app.school_opening_operator','false',true),set_config('app.school_opening_hash',$1,true)", [tokenHash]);
    const row = (await db.query<Pick<OpeningLinkRow, 'status' | 'expires_at'>>('SELECT status,expires_at FROM drivy.school_opening_link WHERE token_hash=$1', [tokenHash])).rows[0];
    await db.query('COMMIT');
    if (!row || row.status !== 'AVAILABLE' || row.expires_at.getTime() <= Date.now()) return undefined;
    return { kind: 'SCHOOL_OPENING' as const, expiresAt: row.expires_at.toISOString() };
  } catch (error) { broken = !(await rollbackQuietly(db)); throw error; } finally { db.release(broken); }
}

export function registerAccounts(app: FastifyInstance, options: { pool: Pool; cursorSecret: string; invitationCodeSecret?: string;
  provisionAccount?: AccountProvisioner; accessCodeAttempts?: AttemptLimiter; accountCreations?: AttemptLimiter }) {
  const codeDigest = invitationCodeHasher(options.cursorSecret, options.invitationCodeSecret);
  const openingHashOf = openingDigest(codeDigest);
  // Sans connexion, la seule identité est l'adresse : chaque code refusé compte pour elle, et chaque compte créé aussi.
  const attempts = options.accessCodeAttempts ?? new AttemptLimiter(10, 15 * 60_000);
  const creations = options.accountCreations ?? new AttemptLimiter(10, 60 * 60_000);
  const envelope = (data: unknown, request: FastifyRequest) => ({ data, requestId: request.id, serverTime: new Date().toISOString() });

  async function resolve(code: string) {
    if (!isOpeningCode(code)) {
      const opening = await previewOpening(options.pool, openingHashOf(code));
      if (!opening) throw invalid();
      return opening;
    }
    const hashed = codeDigest(normalizeInvitationCode(code));
    try {
      const invitation = await previewCode(options.pool, hashed);
      return { kind: 'LEARNER_INVITATION' as const, schoolName: invitation.schoolName, roles: invitation.roles, expiresAt: invitation.expiresAt };
    } catch (error) {
      if (!(error instanceof ApiError) || error.code !== 'INVITATION_CODE_INVALID') throw error;
    }
    const opening = await previewOpening(options.pool, hashed);
    if (!opening) throw invalid();
    return opening;
  }
  async function guarded<T>(request: FastifyRequest, work: () => Promise<T>): Promise<T> {
    const key = `ip:${request.ip}`; const finish = attempts.begin(key); let failed = false;
    try { return await work(); }
    catch (error) { failed = error instanceof ApiError && error.code === 'ACCESS_CODE_INVALID'; throw error; }
    finally { finish(failed); if (attempts.size > 1000) attempts.sweep(); }
  }
  const tooMany = (error: unknown) => error instanceof ApiError && error.status === 429
    ? new ApiError(429, 'ACCESS_CODE_ATTEMPTS', 'Trop de tentatives. Réessayez dans quelques minutes.') : error;

  app.post('/v1/access-codes/preview', async request => {
    empty.parse(request.query); const body = codeBody.parse(request.body);
    try { return envelope(await guarded(request, () => resolve(body.code)), request); } catch (error) { throw tooMany(error); }
  });

  app.post('/v1/accounts', async (request, reply) => {
    empty.parse(request.query); const body = accountBody.parse(request.body);
    if (!options.provisionAccount) throw new ApiError(503, 'ACCOUNT_CREATION_UNAVAILABLE', 'La création de compte est momentanément indisponible. Réessayez plus tard.');
    const key = `ip:${request.ip}`;
    try { creations.check(key); } catch (error) { throw tooMany(error); }
    let kind: AccessCodeKind;
    try { kind = (await guarded(request, () => resolve(body.code))).kind; } catch (error) { throw tooMany(error); }
    // Chaque création réussie ou refusée par le fournisseur compte : on ne crée pas des comptes en série depuis une même adresse.
    creations.fail(key); if (creations.size > 1000) creations.sweep();
    await options.provisionAccount({ email: body.email, firstName: body.firstName, lastName: body.lastName, password: body.password });
    reply.code(201);
    return envelope({ kind, email: body.email }, request);
  });
}
