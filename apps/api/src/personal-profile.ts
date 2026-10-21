import { createHash } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { checkIdempotency, checkVersion, requireVersion } from './commands.js';
import { rollbackQuietly } from './database.js';
import { ApiError, forbidden } from './errors.js';

// Le compte global n'est ni la fiche d'un élève, ni l'identité d'authentification Keycloak.
// Seul le nom public est modifiable à ce stade. L'e-mail de connexion ne l'est pas.
const personalChange = z.object({
  operationId: z.uuid(),
  displayName: z.string().transform(value => value.trim().normalize('NFC'))
    .refine(value => [...value].length >= 1 && [...value].length <= 200 && !/[\u0000-\u001f\u007f]/u.test(value),
      'Nom invalide.')
}).strict();

interface PersonRow { personId: string; version: number; displayName: string; locale: string }
interface Receipt { payload_hash: string; response_version: number; response_display_name: string; response_locale: string }

export function registerPersonalProfile(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier }) {
  const envelope = (data: unknown, requestId: string) => ({ data, requestId, serverTime: new Date().toISOString() });

  app.patch('/v1/me', async (request, reply) => {
    z.object({}).strict().parse(request.query);
    const body = personalChange.parse(request.body);
    const expected = requireVersion(request.headers['if-match']);
    checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const identity = await options.verifyToken(request.headers.authorization);
    const payloadHash = createHash('sha256').update(JSON.stringify({ displayName: body.displayName, expected })).digest('hex');
    const db = await options.pool.connect();
    let broken = false;
    try {
      await db.query('BEGIN');
      await db.query("SET LOCAL lock_timeout = '5s'");
      await db.query("SET LOCAL statement_timeout = '10s'");
      await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.school_id','',true)",
        [identity.issuer, identity.subject]);
      const link = (await db.query<{ person_id: string }>(
        'SELECT person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2', [identity.issuer, identity.subject]
      )).rows[0];
      if (!link) throw new ApiError(403, 'IDENTITY_NOT_LINKED', 'Ce compte ne dispose pas encore d’un accès Drivy.');
      const personId = link.person_id;
      await db.query("SELECT set_config('app.person_id',$1,true)", [personId]);
      // Même un rejeu connu est refusé une fois le compte suspendu.
      const active = await db.query("SELECT 1 FROM drivy.person WHERE id=$1 AND status='ACTIVE'", [personId]);
      if (!active.rowCount) throw forbidden();
      await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [personId + ':' + body.operationId]);
      const previous = (await db.query<Receipt>(
        'SELECT payload_hash,response_version,response_display_name,response_locale FROM drivy.personal_profile_operation WHERE person_id=$1 AND operation_id=$2',
        [personId, body.operationId]
      )).rows[0];
      let result: PersonRow;
      if (previous) {
        if (previous.payload_hash !== payloadHash) {
          throw new ApiError(409, 'IDEMPOTENCY_MISMATCH', 'Cette modification a déjà été utilisée avec un autre contenu.');
        }
        result = {personId, version: previous.response_version, displayName: previous.response_display_name, locale: previous.response_locale};
      } else {
        const current = (await db.query<PersonRow>(
          'SELECT id AS "personId",version,display_name AS "displayName",locale FROM drivy.person WHERE id=$1 AND status=\'ACTIVE\' FOR UPDATE',
          [personId]
        )).rows[0];
        if (!current) throw forbidden();
        checkVersion(current.version, expected);
        result = (await db.query<PersonRow>(
          'SELECT * FROM drivy.update_personal_display_name($1,$2,$3)',
          [personId, expected, body.displayName]
        )).rows[0]!;
        await db.query(
          'INSERT INTO drivy.personal_profile_operation(person_id,operation_id,payload_hash,response_version,response_display_name,response_locale) VALUES($1,$2,$3,$4,$5,$6)',
          [personId,body.operationId,payloadHash,result.version,result.displayName,result.locale]
        );
      }
      await db.query('COMMIT');
      reply.header('ETag', '"' + result.version + '"');
      return envelope(result, request.id);
    } catch (error) {
      broken = !(await rollbackQuietly(db));
      throw error;
    } finally {
      db.release(broken);
    }
  });
}
