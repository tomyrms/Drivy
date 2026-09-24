import { randomUUID } from 'node:crypto';
import Fastify, { LogController, type FastifyReply, type FastifyRequest } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import { z, ZodError } from 'zod';
import type { TokenVerifier } from './auth.js';
import { withActor, type Actor, type Membership } from './database.js';
import { ApiError, forbidden, notFound } from './errors.js';
import { Cursors } from './cursor.js';
import { getLearner, getTraining, listLearners, listTrainings } from './queries.js';
import { registerSchoolSetup } from './school-setup.js';
import { registerInvitations } from './invitations.js';
import { registerProfiles } from './profiles.js';
import { registerCatalogue } from './catalogue.js';
import { registerLessons } from './lessons.js';
import { registerLessonSetup } from './lesson-setup.js';
import type { InvitationMailConfig } from './invitation-mail.js';

const pagination = { limit: z.coerce.number().int().min(1).max(100).default(50), cursor: z.string().max(6000).optional() };
const schoolParams = z.object({ schoolId: z.uuid() });
const learnerQuery = z.object({ ...pagination, q: z.string().max(200).optional(),
  trainingStatus: z.enum(['ACTIVE','PAUSED','COMPLETED','CANCELLED']).optional(),
  status: z.enum(['ACTIVE','ARCHIVED','ALL']).default('ACTIVE'), instructorMembershipId: z.uuid().optional(),
  categoryCode: z.string().max(30).optional(), requiresAction: z.enum(['true','false']).transform(value => value === 'true').optional()
}).strict();
const trainingQuery = z.object({ ...pagination, learnerId: z.uuid().optional() }).strict();
const emptyQuery = z.object({}).strict();

export function buildApp(options: { pool: Pool; verifyToken: TokenVerifier; cursorSecret: string; logger?: boolean; invitationMail?:InvitationMailConfig;reauthMaxAgeSeconds?:number }) {
  const app = Fastify({ logger: options.logger ?? false, logController: new LogController({ disableRequestLogging: true }), genReqId: () => randomUUID(), bodyLimit: 16_384 });
  const cursors = new Cursors(options.cursorSecret);
  app.addHook('onRequest', async (_request, reply) => { reply.header('Cache-Control', 'no-store'); reply.header('X-Content-Type-Options','nosniff'); });
  app.setErrorHandler((error, request, reply) => {
    const known = error instanceof ApiError ? error : error instanceof ZodError
      ? new ApiError(400, 'INVALID_REQUEST', 'Paramètres invalides.')
      : new ApiError(503, 'SERVICE_UNAVAILABLE', 'Service temporairement indisponible.');
    if (!(error instanceof ApiError) && !(error instanceof ZodError)) request.log.error({ requestId: request.id }, 'Échec de traitement API');
    if (known.status === 401) reply.header('WWW-Authenticate','Bearer');
    return reply.status(known.status).type('application/problem+json').send({
      type: `urn:drivy:problem:${known.code.toLowerCase()}`, title: known.message,
      status: known.status, code: known.code, requestId: request.id
    });
  });
  app.setNotFoundHandler((_request, _reply) => { throw notFound(); });
  const envelope = (data: unknown, request: FastifyRequest) => ({ data, requestId: request.id, serverTime: new Date().toISOString() });
  const schoolRead = async (request: FastifyRequest, work: (db: PoolClient, actor: Actor, member: Membership, schoolId: string) => Promise<unknown>) => {
    const identity = await options.verifyToken(request.headers.authorization);
    const { schoolId } = schoolParams.parse(request.params);
    return withActor(options.pool, identity, schoolId, async (db, actor, member) => {
      if (!member) throw forbidden();
      return work(db, actor, member, schoolId);
    });
  };
  const versionHeader = (data: unknown, reply: FastifyReply) => {
    if (typeof data === 'object' && data !== null && 'version' in data) reply.header('ETag', `"${String(data.version)}"`);
  };
  app.get('/v1/me', async (request, reply) => {
    const identity = await options.verifyToken(request.headers.authorization);
    emptyQuery.parse(request.query);
    const data = await withActor(options.pool, identity, undefined, async (db, actor) => {
      const memberships = await db.query(`SELECT m.id AS "membershipId",m.school_id AS "schoolId",s.name AS "schoolName",
        m.roles,m.grants,m.access_epoch AS "accessEpoch" FROM drivy.membership m JOIN drivy.school s ON s.id=m.school_id
        WHERE m.person_id=$1 AND m.status='ACTIVE' ORDER BY s.name,s.id`, [actor.personId]);
      return { ...actor, memberships: memberships.rows };
    });
    versionHeader(data, reply);
    return envelope(data, request);
  });
  app.get('/v1/schools/:schoolId', async (request, reply) => {
    const data = await schoolRead(request, async (db, _actor, _member, schoolId) => {
      emptyQuery.parse(request.query);
      const result = await db.query(`SELECT id,id AS "schoolId",version,name,time_zone AS "timeZone",status,
        contact_email AS "contactEmail",contact_phone AS "contactPhone",NULL AS "logoAssetId",modules,
        configuration_version AS "configurationVersion" FROM drivy.school WHERE id=$1`, [schoolId]);
      if (!result.rows[0]) throw notFound();
      return result.rows[0];
    });
    versionHeader(data, reply); return envelope(data, request);
  });
  app.get('/v1/schools/:schoolId/learners', async request => {
    const data = await schoolRead(request, async (db, actor, member, schoolId) => {
      const { limit, cursor, ...filters } = learnerQuery.parse(request.query);
      const scope = JSON.stringify(['learners',schoolId,actor.personId,member.accessEpoch,filters,limit]);
      const rows = await listLearners(db, schoolId, actor, member, filters, limit, cursors.decode(cursor, scope));
      const last = rows.length > limit ? rows[limit - 1] : undefined;
      return { items: rows.slice(0,limit).map(({ _createdAt: _ignored, ...row }) => row),
        nextCursor: last ? cursors.encode(scope, { id: last.id, createdAt: last._createdAt }) : null };
    });
    return envelope(data, request);
  });
  app.get('/v1/schools/:schoolId/learners/:learnerId', async (request, reply) => {
    const data = await schoolRead(request, async (db, actor, member, schoolId) => {
      emptyQuery.parse(request.query);
      const { learnerId } = z.object({ learnerId: z.uuid() }).parse(request.params);
      return getLearner(db, schoolId, actor, member, learnerId);
    });
    versionHeader(data, reply); return envelope(data, request);
  });
  app.get('/v1/schools/:schoolId/trainings', async request => {
    const data = await schoolRead(request, async (db, actor, member, schoolId) => {
      const { limit, cursor, learnerId } = trainingQuery.parse(request.query);
      const scope = JSON.stringify(['trainings',schoolId,actor.personId,member.accessEpoch,learnerId ?? null,limit]);
      const rows = await listTrainings(db, schoolId, actor, member, learnerId, limit, cursors.decode(cursor, scope));
      const last = rows.length > limit ? rows[limit - 1] : undefined;
      return { items: rows.slice(0,limit).map(({ _createdAt: _ignored, ...row }) => row),
        nextCursor: last ? cursors.encode(scope, { id: last.id, createdAt: last._createdAt }) : null };
    });
    return envelope(data, request);
  });
  app.get('/v1/schools/:schoolId/trainings/:trainingId', async (request, reply) => {
    const data = await schoolRead(request, async (db, actor, member, schoolId) => {
      emptyQuery.parse(request.query);
      const { trainingId } = z.object({ trainingId: z.uuid() }).parse(request.params);
      return getTraining(db, schoolId, actor, member, trainingId);
    });
    versionHeader(data, reply); return envelope(data, request);
  });
  registerSchoolSetup(app,options);
  registerInvitations(app,options);
  registerProfiles(app,options);
  registerCatalogue(app,options);
  registerLessonSetup(app,options);
  registerLessons(app,options);
  return app;
}
