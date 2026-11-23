import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { withActor } from './database.js';
import { ApiError, notFound } from './errors.js';
import {
  moduleActionAllowed, schoolEntitlementsView, type ActionClass, type EntitlementDetailRow, type ModuleAccess, type ModuleCode, type ModuleUsage,
  type SchoolEntitlementRow,
} from './entitlements-model.js';

/**
 * Droits commerciaux aux modules, relus au serveur (R01-T03, #455). Jamais une autorisation issue de l'interface : la web et l'iPhone
 * affichent ce que cette lecture rend, et l'API refuse de toute façon l'usage nouveau d'un module non accordé.
 */
const messages: Record<ModuleCode, string> = {
  MESSAGING: 'La messagerie n’est pas incluse dans l’offre de cette école.',
  COLLECTIVE_COURSES: 'Les cours collectifs ne sont pas inclus dans l’offre de cette école.',
};
/**
 * Même code pour tout refus d'usage nouveau (les clients existants le reconnaissent déjà) ; le texte dit la marche à suivre quand la cause
 * est le cycle commercial (R01-T04) : essai terminé ou contrat résilié. L'historique et les engagements en cours restent accessibles.
 */
const restrictedMessages: Record<Exclude<ModuleAccess, 'ENTITLED' | 'NOT_ENTITLED'>, string> = {
  TRIAL_EXPIRED: 'L’essai de cette école est terminé. Contactez Drivy pour le prolonger ou passer à l’abonnement.',
  TERMINATED: 'Le contrat de cette école est résilié. L’historique reste consultable.',
  SUSPENDED: 'L’abonnement de cette école est suspendu. L’historique reste consultable. Contactez Drivy pour le rétablir.',
};
export const moduleNotEntitled = (module: ModuleCode, access: ModuleAccess = 'NOT_ENTITLED') =>
  new ApiError(403, 'MODULE_NOT_ENTITLED', access !== 'ENTITLED' && access !== 'NOT_ENTITLED' ? restrictedMessages[access] : messages[module]);

type Queryable = Pick<PoolClient, 'query'>;

/** Lit le droit commercial de l'école courante sur un module ; faux pour un appelant qui n'est pas membre de l'école (échec fermé). */
export async function schoolModuleEntitled(db: Queryable, schoolId: string, module: ModuleCode): Promise<boolean> {
  return (await schoolModuleAccess(db, schoolId, module)) === 'ENTITLED';
}
/** Accès d'un usage nouveau et sa raison ; NOT_ENTITLED pour un appelant hors de l'école ou une réponse inattendue (échec fermé). */
export async function schoolModuleAccess(db: Queryable, schoolId: string, module: ModuleCode): Promise<ModuleAccess> {
  const row = (await db.query<{ access: string }>('SELECT drivy.school_module_access($1::uuid,$2::text) AS access', [schoolId, module])).rows[0];
  return row?.access === 'ENTITLED' || row?.access === 'TRIAL_EXPIRED' || row?.access === 'TERMINATED' || row?.access === 'SUSPENDED' ? row.access : 'NOT_ENTITLED';
}

/**
 * Porte d'entrée d'un usage de module. Seule la classe WRITE_NEW (nouvel usage : écrire, créer, publier, inscrire) exige le droit ;
 * consulter l'historique et terminer un engagement déjà pris restent possibles après un retrait (voir la matrice du document de décision).
 */
export async function requireModule(db: Queryable, schoolId: string, module: ModuleCode, action: ActionClass = 'WRITE_NEW'): Promise<void> {
  if (moduleActionAllowed(false, action)) return;
  const access = await schoolModuleAccess(db, schoolId, module);
  if (access !== 'ENTITLED') throw moduleNotEntitled(module, access);
}

/**
 * Porte des opérations de base d'une école suspendue (R01-T09, #461) : relue au serveur dans la transaction de la commande, quel que soit
 * l'âge du client. Même 403 MODULE_NOT_ENTITLED que tout refus d'usage nouveau, avec la marche à suivre. Faux hors de l'école (échec fermé
 * côté appelant : la commande vérifie déjà l'appartenance).
 */
export const schoolSuspended = () => new ApiError(403, 'MODULE_NOT_ENTITLED', restrictedMessages.SUSPENDED);
export async function requireSchoolNotSuspended(db: Queryable, schoolId: string): Promise<void> {
  const row = (await db.query<{ suspended: boolean }>('SELECT drivy.school_commercially_suspended($1::uuid) AS suspended', [schoolId])).rows[0];
  if (row?.suspended) throw schoolSuspended();
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
