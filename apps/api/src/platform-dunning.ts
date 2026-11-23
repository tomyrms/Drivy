import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { checkIdempotency, requireVersion } from './commands.js';
import { ApiError, notFound } from './errors.js';
import { platformCommand, platformRead } from './platform-command.js';
import { lockedClient } from './platform-commercial.js';
import {
  alertView, commandBody, dunningView, exceptionBody, policyBody, policyView, reasonBody, suspensionBody, type CommercialAlertRow, type DunningPolicyRow,
  type DunningRunRow, type DunningViewRow,
} from './platform-dunning-model.js';

/**
 * Relances des impayés et suspension d'une école, côté équipe Drivy (R01-T09, #461).
 *
 * La politique est globale et versionnée ; elle est créée désactivée. Le dossier de relance d'une fiche est recalculé par la base à chaque lecture
 * et avant chaque décision, sous le verrou de la fiche commun à la facturation et aux règlements : un règlement enregistré en même temps qu'une
 * suspension est vu par l'une ou l'autre, jamais par aucune. Le journal reçoit l'action, la cause et les dates, jamais le motif saisi.
 */
const empty = z.object({}).strict();
const idParams = z.object({ id: z.uuid() }).strict();
const exceptionParams = z.object({ id: z.uuid(), exceptionId: z.uuid() }).strict();
const suspensionParams = z.object({ id: z.uuid(), suspensionId: z.uuid() }).strict();
const stepParams = z.object({ id: z.uuid(), stepId: z.uuid() }).strict();
const alertParams = z.object({ alertId: z.uuid() }).strict();

const dunningConflict = () => new ApiError(412, 'VERSION_CONFLICT', 'Le dossier de relance de cette école a changé. Rechargez-le avant de confirmer.');

async function readPolicy(db: PoolClient) {
  const row = (await db.query<{ policy: DunningPolicyRow | null }>('SELECT drivy.platform_dunning_policy_read() AS policy')).rows[0]?.policy;
  if (!row) throw notFound();
  return policyView(row);
}
async function readView(db: PoolClient, clientId: string) {
  const row = (await db.query<{ view: DunningViewRow | null }>('SELECT drivy.platform_dunning_view($1::uuid) AS view', [clientId])).rows[0]?.view;
  if (!row) throw notFound();
  return dunningView(row);
}
async function readAlerts(db: PoolClient) {
  const rows = (await db.query<{ items: CommercialAlertRow[] }>('SELECT drivy.platform_commercial_alerts() AS items')).rows[0]?.items ?? [];
  return { items: rows.map(alertView) };
}

export function registerPlatformDunning(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier }) {
  const envelope = (data: unknown, request: FastifyRequest) => ({ data, requestId: request.id, serverTime: new Date().toISOString() });
  const identityOf = (request: FastifyRequest) => options.verifyToken(request.headers.authorization);

  // --- Politique globale ------------------------------------------------------------------------------------------------------------
  app.get('/v1/platform/dunning/policy', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    return envelope(await platformRead(options.pool, identity, db => readPolicy(db)), request);
  });
  app.post('/v1/platform/dunning/policy', async (request, reply) => {
    const identity = await identityOf(request); empty.parse(request.query);
    const body = policyBody.parse(request.body);
    const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const { operationId, ...content } = body;
    const result = await platformCommand(options.pool, identity, {
      kind: 'UPDATE_DUNNING_POLICY', operationId, expectedVersion: expected, body: content, refusal: { action: 'UPDATE_DUNNING_POLICY', subject: null },
    }, async db => {
      // La base relit la version sous verrou (412 si elle a changé) et revalide toutes les bornes.
      const row = (await db.query<{ policy: DunningPolicyRow }>(
        'SELECT drivy.platform_dunning_policy_update($1::integer,$2::boolean,$3::boolean,$4::integer[],$5::integer,$6::integer,$7::integer) AS policy',
        [expected, content.remindersEnabled, content.autoSuspend, content.reminderDays, content.suspensionMonths, content.warningDays, content.trialAlertDays])).rows[0]!.policy;
      const policy = policyView(row);
      return { data: policy, journal: { action: 'UPDATE_DUNNING_POLICY', subject: null, changes: { ...content, reminderDays: [...content.reminderDays], version: policy.version } } };
    });
    reply.status(result.status); return envelope(result.data, request);
  });

  // Passage demandé par un opérateur : même traitement que le service planifié, au jour de Zurich. Sans version : il est idempotent par nature.
  app.post('/v1/platform/dunning/run', async (request, reply) => {
    const identity = await identityOf(request); empty.parse(request.query);
    const body = commandBody.parse(request.body); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const result = await platformCommand(options.pool, identity, {
      kind: 'RUN_DUNNING', operationId: body.operationId, expectedVersion: null, body: {}, refusal: { action: 'RUN_DUNNING', subject: null },
    }, async db => {
      const run = (await db.query<{ result: DunningRunRow }>('SELECT drivy.platform_dunning_run_manual() AS result')).rows[0]!.result;
      return { data: run, journal: { action: 'RUN_DUNNING', subject: null, changes: { ...run } } };
    });
    reply.status(result.status); return envelope(result.data, request);
  });

  // --- Alertes de la console --------------------------------------------------------------------------------------------------------
  app.get('/v1/platform/commercial-alerts', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    return envelope(await platformRead(options.pool, identity, db => readAlerts(db)), request);
  });
  // Prise en compte d'une alerte : elle quitte la liste. Elle ne règle, ne suspend et ne lève rien.
  app.post('/v1/platform/commercial-alerts/:alertId/acknowledge', async (request, reply) => {
    const identity = await identityOf(request); empty.parse(request.query); const { alertId } = alertParams.parse(request.params);
    const body = commandBody.parse(request.body); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const result = await platformCommand(options.pool, identity, {
      kind: 'ACKNOWLEDGE_COMMERCIAL_ALERT', operationId: body.operationId, expectedVersion: null, body: { alertId },
      refusal: { action: 'ACKNOWLEDGE_COMMERCIAL_ALERT', subject: null },
    }, async db => {
      const clientId = (await db.query<{ client: string }>('SELECT drivy.platform_commercial_alert_ack($1::uuid) AS client', [alertId])).rows[0]!.client;
      const schoolId = (await db.query<{ school_id: string | null }>('SELECT school_id FROM drivy.platform_client WHERE id=$1', [clientId])).rows[0]?.school_id ?? null;
      return { data: await readAlerts(db), journal: { action: 'ACKNOWLEDGE_COMMERCIAL_ALERT', schoolId, subject: { type: 'PlatformClient', id: clientId }, changes: { alertId } } };
    });
    reply.status(result.status); return envelope(result.data, request);
  });

  // --- Dossier de relance d'une fiche -----------------------------------------------------------------------------------------------
  const base = '/v1/platform/clients/:id/dunning';
  app.get(base, async request => {
    const identity = await identityOf(request); empty.parse(request.query); const { id } = idParams.parse(request.params);
    return envelope(await platformRead(options.pool, identity, db => readView(db, id)), request);
  });

  type Route = { id: string; exceptionId?: string; suspensionId?: string; stepId?: string };
  type Effect = { status?: 200 | 201; changes: Record<string, unknown> };
  /** Commande d'un dossier : verrou de la fiche, version relue, effet calculé par la base, dossier relu après écriture. */
  function command<B extends { operationId: string }>(path: string, kind: string, schema: z.ZodType<B>, params: z.ZodType<Route>,
    work: (db: PoolClient, body: B, route: Route) => Promise<Effect>) {
    app.post(`${base}${path}`, async (request, reply) => {
      const identity = await identityOf(request); empty.parse(request.query);
      const route = params.parse(request.params); const body = schema.parse(request.body);
      const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
      const { operationId, ...content } = body as B & Record<string, unknown>;
      const result = await platformCommand(options.pool, identity, {
        kind, operationId, expectedVersion: expected, body: { ...route, ...content }, refusal: { action: kind, subject: { type: 'PlatformClient', id: route.id } },
      }, async db => {
        const schoolId = await lockedClient(db, route.id);
        const version = (await db.query<{ version: number | null }>('SELECT drivy.platform_dunning_version($1::uuid) AS version', [route.id])).rows[0]?.version;
        if (version !== expected) throw dunningConflict();
        const effect = await work(db, body, route);
        return { data: await readView(db, route.id), status: effect.status ?? 200,
          journal: { action: kind, schoolId, subject: { type: 'PlatformClient', id: route.id }, changes: effect.changes } };
      });
      reply.status(result.status); return envelope(result.data, request);
    });
  }

  // Exception temporaire motivée : délai propre à l'école (DELAY) ou arrêt des relances et de la suspension automatique (HOLD). Une seule active.
  command('/exceptions', 'GRANT_DUNNING_EXCEPTION', exceptionBody, idParams, async (db, body, { id }) => {
    const exceptionId = randomUUID();
    await db.query('SELECT drivy.platform_dunning_exception_create($1::uuid,$2::uuid,$3::text,$4::integer,$5::date,$6::text)',
      [id, exceptionId, body.kind, body.suspensionMonths ?? null, body.endsOn, body.reason]);
    return { status: 201, changes: { exceptionId, kind: body.kind, suspensionMonths: body.suspensionMonths ?? null, endsOn: body.endsOn } };
  });
  command('/exceptions/:exceptionId/revoke', 'REVOKE_DUNNING_EXCEPTION', reasonBody, exceptionParams, async (db, body, { id, exceptionId }) => {
    await db.query('SELECT drivy.platform_dunning_exception_revoke($1::uuid,$2::uuid,$3::text)', [id, exceptionId, body.reason]);
    return { changes: { exceptionId } };
  });

  // Suspension par un opérateur. Pour impayé, la base exige une dette arrivée à son délai et aucune exception d'arrêt ; une autre cause reste motivée.
  command('/suspensions', 'SUSPEND_SCHOOL', suspensionBody, idParams, async (db, body, { id }) => {
    const suspensionId = randomUUID();
    await db.query('SELECT drivy.platform_suspension_create($1::uuid,$2::uuid,$3::text,$4::text)', [id, suspensionId, body.cause, body.reason]);
    return { status: 201, changes: { suspensionId, cause: body.cause } };
  });
  // Levée motivée. Une suspension pour impayé dont la dette reste due ne se lève que sous une exception active ; les autres causes restent en place.
  command('/suspensions/:suspensionId/lift', 'LIFT_SUSPENSION', reasonBody, suspensionParams, async (db, body, { id, suspensionId }) => {
    await db.query('SELECT drivy.platform_suspension_lift($1::uuid,$2::uuid,$3::text)', [id, suspensionId, body.reason]);
    return { changes: { suspensionId } };
  });

  // Remise d'un avertissement confirmée par un autre canal après un échec connu : un fait attesté par l'opérateur, jamais déduit.
  command('/steps/:stepId/confirm', 'CONFIRM_DUNNING_WARNING', reasonBody, stepParams, async (db, body, { id, stepId }) => {
    await db.query('SELECT drivy.platform_dunning_warning_confirm($1::uuid,$2::uuid,$3::text)', [id, stepId, body.reason]);
    return { changes: { stepId } };
  });
}
