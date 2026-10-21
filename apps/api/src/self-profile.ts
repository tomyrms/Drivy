import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { ApiError, forbidden } from './errors.js';
import { rollbackQuietly } from './database.js';
import { requireVersion } from './commands.js';

/** Même contrôle que le nom saisi à l'ouverture d'une école : 1 à 200 caractères, sans caractère de contrôle. */
const displayName = z.string().transform(value => value.trim().normalize('NFC'))
  .refine(value => [...value].length >= 1 && [...value].length <= 200, 'Le nom doit compter entre 1 et 200 caractères.')
  .refine(value => !/[\u0000-\u001f\u007f]/u.test(value), 'Le nom contient un caractère non autorisé.');
const body = z.object({ displayName }).strict();
const empty = z.object({}).strict();

/**
 * Profil personnel (extension hors contrat canonique, apps/api/contracts/self-profile.json).
 * PATCH /v1/me/profile : la personne connectée renomme son propre compte Drivy. If-Match porte la version de la personne.
 * Pas d'operationId : la commande est idempotente par son contenu. Un nouvel envoi après une réponse perdue retrouve le nom déjà
 * enregistré et répond 200 au lieu d'un conflit. Aucun rôle, droit ou dossier d'élève n'est modifié ici.
 */
export function registerSelfProfile(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier }) {
  const envelope = (data: unknown, request: FastifyRequest) => ({ data, requestId: request.id, serverTime: new Date().toISOString() });
  app.patch('/v1/me/profile', async (request, reply) => {
    empty.parse(request.query);
    const value = body.parse(request.body);
    const expected = requireVersion(request.headers['if-match']);
    const identity = await options.verifyToken(request.headers.authorization);
    const db = await options.pool.connect();
    let broken = false;
    try {
      await db.query('BEGIN');
      await db.query("SET LOCAL lock_timeout='5s'");
      await db.query("SET LOCAL statement_timeout='10s'");
      await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.self_profile','true',true)",
        [identity.issuer, identity.subject]);
      const link = await db.query<{ person_id: string }>('SELECT person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2', [identity.issuer, identity.subject]);
      const personId = link.rows[0]?.person_id;
      if (!personId) throw new ApiError(403, 'IDENTITY_NOT_LINKED', 'Ce compte ne dispose pas encore d’un accès Drivy.');
      await db.query("SELECT set_config('app.person_id',$1,true)", [personId]);
      const current = (await db.query<{ display_name: string; version: number }>(
        "SELECT display_name,version FROM drivy.person WHERE id=$1 AND status='ACTIVE' FOR UPDATE", [personId])).rows[0];
      if (!current) throw forbidden();
      let version = current.version;
      if (current.display_name !== value.displayName) {
        if (current.version !== expected) throw new ApiError(412, 'VERSION_CONFLICT', 'Votre profil a changé entre-temps. Rechargez-le avant d’enregistrer.');
        const updated = await db.query<{ version: number }>('UPDATE drivy.person SET display_name=$2,version=version+1 WHERE id=$1 RETURNING version',
          [personId, value.displayName]);
        version = updated.rows[0]!.version;
      }
      await db.query('COMMIT');
      reply.header('ETag', `"${version}"`);
      return envelope({ personId, displayName: value.displayName, version }, request);
    } catch (error) {
      broken = !(await rollbackQuietly(db));
      throw error;
    } finally { db.release(broken); }
  });
}
