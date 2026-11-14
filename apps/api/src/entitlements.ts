import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { withActor } from './database.js';
import { ApiError, notFound } from './errors.js';
import {
  moduleActionAllowed, schoolEntitlementsView, type ActionClass, type EntitlementDetailRow, type ModuleCode, type ModuleUsage, type SchoolEntitlementRow,
} from './entitlements-model.js';

/**
 * Droits commerciaux aux modules, relus au serveur (R01-T03, #455). Jamais une autorisation issue de l'interface : la web et l'iPhone
 * affichent ce que cette lecture rend, et l'API refuse de toute façon l'usage nouveau d'un module non accordé.
 */
const messages: Record<ModuleCode, string> = {
  MESSAGING: 'La messagerie n’est pas incluse dans l’offre de cette école.',
  COLLECTIVE_COURSES: 'Les cours collectifs ne sont pas inclus dans l’offre de cette école.',
};
export const moduleNotEntitled = (module: ModuleCode) => new ApiError(403, 'MODULE_NOT_ENTITLED', messages[module]);

type Queryable = Pick<PoolClient, 'query'>;

/** Lit le droit commercial de l'école courante sur un module ; faux pour un appelant qui n'est pas membre de l'école (échec fermé). */
export async function schoolModuleEntitled(db: Queryable, schoolId: string, module: ModuleCode): Promise<boolean> {
  const row = (await db.query<{ entitled: boolean }>('SELECT drivy.school_module_entitled($1::uuid,$2::text) AS entitled', [schoolId, module])).rows[0];
  return row?.entitled === true;
}

/**
 * Porte d'entrée d'un usage de module. Seule la classe WRITE_NEW (nouvel usage : écrire, créer, publier, inscrire) exige le droit ;
 * consulter l'historique et terminer un engagement déjà pris restent possibles après un retrait (voir la matrice du document de décision).
 */
export async function requireModule(db: Queryable, schoolId: string, module: ModuleCode, action: ActionClass = 'WRITE_NEW'): Promise<void> {
  if (moduleActionAllowed(false, action)) return;
  if (!(await schoolModuleEntitled(db, schoolId, module))) throw moduleNotEntitled(module);
}

export async function readSchoolEntitlements(db: Queryable, schoolId: string, at: Date = new Date()) {
  const row = (await db.query<{ entitlements: SchoolEntitlementRow }>('SELECT drivy.school_entitlements($1::uuid) AS entitlements', [schoolId])).rows[0]?.entitlements;
  if (!row) throw notFound();
  return schoolEntitlementsView(row, at);
}

/** Droits d'une fiche vus par l'équipe (détail et historique). 404 si la fiche n'existe pas. */
export async function readClientEntitlements(db: Queryable, clientId: string): Promise<EntitlementDetailRow> {
  const row = (await db.query<{ detail: EntitlementDetailRow | null }>('SELECT drivy.platform_client_entitlements($1::uuid) AS detail', [clientId])).rows[0]?.detail;
  if (!row) throw notFound();
  return row;
}

/** Volumes d'objets existants par module (conversations, séries, inscriptions, séances à venir) : jamais un contenu. */
export async function readModuleUsage(db: Queryable, clientId: string): Promise<ModuleUsage> {
  const row = (await db.query<{ usage: ModuleUsage }>('SELECT drivy.platform_module_usage($1::uuid) AS usage', [clientId])).rows[0];
  return row?.usage ?? {};
}

const schoolParams = z.object({ schoolId: z.uuid() }).strict();
const emptyQuery = z.object({}).strict();

/**
 * `GET /v1/schools/{schoolId}/entitlements` : les droits de l'école courante, pour la web et l'iPhone. Réservé aux membres actifs de
 * l'école, tous rôles confondus (il ne contient ni offre, ni motif, ni auteur) ; un ancien client hors ligne n'en est jamais l'autorité.
 */
export function registerEntitlements(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier }) {
  const envelope = (data: unknown, request: FastifyRequest) => ({ data, requestId: request.id, serverTime: new Date().toISOString() });
  app.get('/v1/schools/:schoolId/entitlements', async (request, reply) => {
    const identity = await options.verifyToken(request.headers.authorization);
    const { schoolId } = schoolParams.parse(request.params); emptyQuery.parse(request.query);
    const data = await withActor(options.pool, identity, schoolId, async db => readSchoolEntitlements(db, schoolId));
    reply.header('ETag', `"${data.version}"`).header('Cache-Control', 'no-store');
    return envelope(data, request);
  });
}
