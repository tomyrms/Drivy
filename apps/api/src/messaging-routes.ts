import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import type { IncomingHttpHeaders } from 'node:http';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { messagingSchoolGate, type MessagingAccessOptions } from './messaging-access.js';
import { rollbackQuietly } from './database.js';
import { ApiError, forbidden } from './errors.js';
import { eligibleContacts, generalMembers, generalRemovedMembers, findOrCreateGeneral, findOrCreatePrivate, listConversations, pageEnvelopes,
  resumeEnvelopes, sendEnvelope, updateReadState, messagingUnavailable, conversationMembers, deleteMessage, setReaction, setPinned,
  setPollVotes, closePoll, setGroupAdmin, removeGeneralMember, reinstateGeneralMember, createReport, listReports, setReportStatus, reportStatuses,
  reactionPalette, type MessagingActor } from './messaging.js';
import { mapDatabaseError } from './messaging-view.js';
import { deviceIdPattern } from './messaging-keys.js';
import { cancelMedia, downloadMedia, invalidMedia, mediaBodyLimit, mediaMaxBytes, mediaPayloadTooLarge, requireActiveDevice, uploadMedia } from './messaging-media.js';
import { lockCommandOperation } from './commands.js';
import { executeMessagingMutation, messagingMutation, type MessagingMutation } from './messaging-commands.js';

const id = z.uuid();
const base = z.object({ schoolId: id });
const conversation = base.extend({ conversationId: id });
const envelope = z.object({ scheme: z.string().regex(/^[A-Za-z0-9._-]{1,80}$/), keyId: z.string().regex(/^[A-Za-z0-9._:-]{1,128}$/),
  payload: z.string().min(4).max(12000).regex(/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/) }).strict();
const message = z.object({ clientMessageId: id, ciphertext: envelope, mentionPersonIds: z.array(id).max(8).default([]),
  expectedMembersEpoch: z.number().int().min(0).safe().optional(),
  replyToMessageId: id.nullable().optional(),
  poll: z.object({ optionCount: z.number().int().min(2).max(12), multiple: z.boolean().default(false) }).strict().nullable().optional(),
  // Forme validée par le schéma partagé à la frontière du domaine (400 INVALID_MEDIA), pas par le schéma de route.
  media: z.unknown().nullable().optional() }).strict()
  .refine(value => !(value.media != null && value.poll != null), { message: 'Un message ne peut pas porter un sondage et une pièce jointe.' });
const directoryQuery = z.object({ limit: z.coerce.number().int().min(1).max(100).default(50), cursor: id.optional() }).strict();

/** Qualification explicite par école, identité OIDC et droits serveur toujours obligatoires. */
export function registerMessaging(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier } & MessagingAccessOptions) {
  const enabled = messagingSchoolGate(options);
  interface RunContext { schoolId: string; actorPersonId: string; accessEpoch: number }
  /** Transaction commune : porte, identité, époque, droits et enveloppe de contexte. Rend aussi les octets bruts. */
  async function run<T>(headers: IncomingHttpHeaders, schoolId: string,
    work: (db: import('pg').PoolClient, actor: MessagingActor) => Promise<T>, mutation?:MessagingMutation):
    Promise<{ result: T; context: RunContext; mutationReceipt?: { operationId: string } }> {
    if (!enabled(schoolId)) throw messagingUnavailable();
    const expectedActor = id.parse(headers['x-drivy-expected-person-id']);
    const expectedEpoch = z.coerce.number().int().positive().safe().parse(headers['x-drivy-expected-access-epoch']);
    const identity = await options.verifyToken(headers.authorization);
    const db = await options.pool.connect();
    let broken = false;
    try {
      await db.query('BEGIN ISOLATION LEVEL READ COMMITTED');
      await db.query("SET LOCAL lock_timeout='5s'");
      await db.query("SET LOCAL statement_timeout='10s'");
      await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.school_id',$3,true)",
        [identity.issuer, identity.subject, schoolId]);
      const link = await db.query<{ personId: string }>('SELECT person_id AS "personId" FROM drivy.identity_link WHERE issuer=$1 AND subject=$2', [identity.issuer, identity.subject]);
      if (!link.rows[0]) throw forbidden();
      const personId = link.rows[0].personId;
      if (personId.toLowerCase() !== expectedActor.toLowerCase()) throw forbidden();
      await db.query("SELECT set_config('app.person_id',$1,true)", [personId]);
      // Match schoolCommand: person, school, then membership, with epoch checked under lock.
      const person = await db.query('SELECT id FROM drivy.person WHERE id=$1 AND status=\'ACTIVE\' FOR SHARE', [personId]);
      if (!person.rows[0]) throw forbidden();
      if (mutation) await lockCommandOperation(db,personId,mutation.operationId);
      const school = await db.query('SELECT id FROM drivy.school WHERE id=$1 AND status=\'ACTIVE\' FOR SHARE', [schoolId]);
      if (!school.rows[0]) throw forbidden();
      const member = await db.query<{ id: string; accessEpoch: number }>(`SELECT m.id,m.access_epoch AS "accessEpoch" FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
        WHERE m.school_id=$1 AND m.person_id=$2 AND m.status='ACTIVE' AND p.status='ACTIVE' FOR SHARE OF m`, [schoolId, personId]);
      if (!member.rows[0] || member.rows[0].accessEpoch !== expectedEpoch) throw forbidden();
      await db.query("SELECT set_config('app.membership_id',$1,true)", [member.rows[0].id]);
      const actor = { schoolId, personId, membershipId: member.rows[0].id };
      const data = mutation ? await executeMessagingMutation(db,actor,mutation,()=>work(db,actor)) : await work(db,actor);
      await db.query('COMMIT');
      return { result: data, context: { schoolId, actorPersonId: personId, accessEpoch: member.rows[0].accessEpoch },
        ...(mutation ? {mutationReceipt:{operationId:mutation.operationId}} : {}) };
    } catch (error) { broken = !(await rollbackQuietly(db)); throw mapDatabaseError(error); }
    finally { db.release(broken); }
  }
  async function execute<T>(headers: IncomingHttpHeaders, requestId: string,
    schoolId: string, work: (db: import('pg').PoolClient, actor: MessagingActor) => Promise<T>, mutation?:MessagingMutation): Promise<T> {
    const { result, ...rest } = await run(headers, schoolId, work, mutation);
    return { ...(result as object), ...rest, requestId, serverTime: new Date().toISOString() } as T;
  }
  /** Appareil déclaré : un identifiant, jamais une preuve de possession ; son refus est explicite et stable. */
  const deviceHeader = (value: string | string[] | undefined): string => {
    const parsed = z.string().regex(deviceIdPattern).safeParse(value);
    if (!parsed.success) throw new ApiError(403, 'MESSAGING_DEVICE_REQUIRED', 'Appareil de messagerie requis.');
    return parsed.data;
  };
  const path = '/v1/schools/:schoolId/messaging';
  app.get(`${path}/contacts`, request => {
    const { schoolId } = base.parse(request.params);
    const query = directoryQuery.parse(request.query);
    return execute(request.headers, request.id, schoolId, (db, actor) => eligibleContacts(db, actor, query.limit, query.cursor).then(data => ({ data })));
  });
  app.get(`${path}/general/members`, request => {
    const { schoolId } = base.parse(request.params);
    const query = directoryQuery.parse(request.query);
    return execute(request.headers, request.id, schoolId, (db, actor) => generalMembers(db, actor, query.limit, query.cursor).then(data => ({ data })));
  });
  app.get(`${path}/general/removed-members`, request => {
    const { schoolId } = base.parse(request.params);
    const query = directoryQuery.parse(request.query);
    return execute(request.headers, request.id, schoolId, (db, actor) => generalRemovedMembers(db, actor, query.limit, query.cursor).then(data => ({ data })));
  });
  app.put(`${path}/private/:personId`, request => {
    const { schoolId, personId } = base.extend({ personId: id }).parse(request.params);
    return execute(request.headers, request.id, schoolId, async (db, actor) => ({ data: { conversationId: await findOrCreatePrivate(db, actor, personId) } }));
  });
  app.put(`${path}/general`, request => {
    const { schoolId } = base.parse(request.params);
    return execute(request.headers, request.id, schoolId, async (db, actor) => ({ data: { conversationId: await findOrCreateGeneral(db, actor) } }));
  });
  app.get(`${path}/conversations`, request => {
    const { schoolId } = base.parse(request.params);
    const query = z.object({ limit: z.coerce.number().int().min(1).max(100).default(50), before: id.optional() }).strict().parse(request.query);
    return execute(request.headers, request.id, schoolId, (db, actor) => listConversations(db, actor, query.limit, query.before).then(data => ({ data })));
  });
  app.get(`${path}/conversations/:conversationId/messages`, request => {
    const { schoolId, conversationId } = conversation.parse(request.params);
    const query = z.object({ limit: z.coerce.number().int().min(1).max(100).default(50), cursor: z.string().regex(/^[1-9][0-9]{0,15}$/).optional() }).strict().parse(request.query);
    return execute(request.headers, request.id, schoolId, (db, actor) => pageEnvelopes(db, actor, conversationId, query.cursor ? Number(query.cursor) : undefined, query.limit).then(data => ({ data })));
  });
  app.get(`${path}/conversations/:conversationId/events`, request => {
    const { schoolId, conversationId } = conversation.parse(request.params);
    const query = z.object({ limit: z.coerce.number().int().min(1).max(100).default(50),
      afterSequence: z.coerce.number().int().min(0).safe().default(0) }).strict().parse(request.query);
    return execute(request.headers, request.id, schoolId, (db, actor) => resumeEnvelopes(db, actor, conversationId, query.afterSequence, query.limit).then(data => ({ data })));
  });
  app.post(`${path}/conversations/:conversationId/messages`, request => {
    const { schoolId, conversationId } = conversation.parse(request.params);
    const body = message.parse(request.body);
    return execute(request.headers, request.id, schoolId, (db, actor) => sendEnvelope(db, actor, conversationId,
      body.clientMessageId, body.ciphertext, body.mentionPersonIds, body.replyToMessageId ?? null, body.poll ?? null,
      body.expectedMembersEpoch, body.media ?? null).then(data => ({ data })));
  });
  // Médias : octets chiffrés bruts. Parser et routes sont encapsulés dans un scope Fastify : hors média, aucun
  // parser `application/octet-stream` n'existe (Fastify refuse le type en 415) et le bodyLimit global reste à 16 Kio.
  const mediaPath = `${path}/conversations/:conversationId/media/:mediaId`;
  // L'identifiant média est validé par le module média (400 INVALID_MEDIA), pas par le schéma de route.
  const mediaParams = conversation.extend({ mediaId: z.string().min(1).max(64) });
  app.register(async function messagingMediaRoutes(scope) {
    scope.addContentTypeParser('application/octet-stream', { parseAs: 'buffer', bodyLimit: mediaBodyLimit },
      (_request, body, done) => done(null, body));
    scope.put(mediaPath, { bodyLimit: mediaBodyLimit }, request => {
      const { schoolId, conversationId, mediaId } = mediaParams.parse(request.params);
      // La porte de qualification précède toute validation métier (appareil, média) : école fermée = 503.
      if (!enabled(schoolId)) throw messagingUnavailable();
      if (!Buffer.isBuffer(request.body))
        throw new ApiError(415, 'UNSUPPORTED_MEDIA_TYPE', 'Envoyez les octets chiffrés en application/octet-stream.');
      const bytes = request.body;
      // Longueur déclarée obligatoire et exacte : aucune troncature silencieuse, aucun octet ignoré.
      const declared = Number(request.headers['content-length']);
      if (!Number.isSafeInteger(declared) || declared !== bytes.length || bytes.length < 1) throw invalidMedia();
      if (bytes.length > mediaMaxBytes) throw mediaPayloadTooLarge();
      const deviceId = deviceHeader(request.headers['x-drivy-device-id']);
      return execute(request.headers, request.id, schoolId, async (db, actor) => {
        await requireActiveDevice(db, actor, deviceId);
        return { data: await uploadMedia(db, actor, conversationId, mediaId, bytes) };
      });
    });
    scope.get(mediaPath, async (request, reply) => {
      const { schoolId, conversationId, mediaId } = mediaParams.parse(request.params);
      if (!enabled(schoolId)) throw messagingUnavailable();
      const deviceId = deviceHeader(request.headers['x-drivy-device-id']);
      const { result, context } = await run(request.headers, schoolId, async (db, actor) => {
        await requireActiveDevice(db, actor, deviceId);
        return downloadMedia(db, actor, conversationId, mediaId);
      });
      reply.header('Cache-Control', 'private, no-store')
        .header('X-Drivy-School-Id', context.schoolId)
        .header('X-Drivy-Access-Epoch', String(context.accessEpoch))
        .header('X-Drivy-Media-Sha256', result.sha256)
        .header('Content-Length', String(result.bytes.length));
      return reply.type('application/octet-stream').send(result.bytes);
    });
    scope.delete(mediaPath, request => {
      const { schoolId, conversationId, mediaId } = mediaParams.parse(request.params);
      if (!enabled(schoolId)) throw messagingUnavailable();
      const deviceId = deviceHeader(request.headers['x-drivy-device-id']);
      return execute(request.headers, request.id, schoolId, async (db, actor) => {
        await requireActiveDevice(db, actor, deviceId);
        return { data: await cancelMedia(db, actor, conversationId, mediaId) };
      });
    });
  });
  app.put(`${path}/conversations/:conversationId/read-state`, request => {
    const { schoolId, conversationId } = conversation.parse(request.params);
    const body = z.object({ lastReadSequence: z.number().int().min(0).safe(),
      mutedUntil: z.iso.datetime({ offset: true }).nullable().optional(), expectedVersion: z.number().int().min(0).safe().optional() })
      .strict().refine(value => value.mutedUntil === undefined || value.expectedVersion !== undefined).parse(request.body);
    return execute(request.headers, request.id, schoolId, (db, actor) => updateReadState(db, actor, conversationId,
      body.lastReadSequence, body.mutedUntil, body.expectedVersion).then(data => ({ data })));
  });
  const messagePath = `${path}/conversations/:conversationId/messages/:messageId`;
  const messageParams = conversation.extend({ messageId: id });
  app.get(`${path}/conversations/:conversationId/members`, request => {
    const { schoolId, conversationId } = conversation.parse(request.params);
    return execute(request.headers, request.id, schoolId, (db, actor) => conversationMembers(db, actor, conversationId).then(data => ({ data })));
  });
  app.delete(messagePath, request => {
    const { schoolId, conversationId, messageId } = messageParams.parse(request.params);
    const { scope } = z.object({ scope: z.enum(['me', 'everyone']) }).strict().parse(request.query);
    return execute(request.headers, request.id, schoolId, (db, actor) => deleteMessage(db, actor, conversationId, messageId, scope).then(data => ({ data })),
      messagingMutation(request.headers['idempotency-key'],scope==='me'?'MESSAGING_HIDE':'MESSAGING_DELETE',schoolId,conversationId,messageId,{scope}));
  });
  for (const active of [true, false]) {
    (active ? app.put.bind(app) : app.delete.bind(app))(`${messagePath}/reactions/:emoji`, request => {
      const { schoolId, conversationId, messageId, emoji } = messageParams.extend({ emoji: z.enum(reactionPalette) }).parse(request.params);
      return execute(request.headers, request.id, schoolId, (db, actor) => setReaction(db, actor, conversationId, messageId, emoji, active).then(data => ({ data })),
        messagingMutation(request.headers['idempotency-key'],'MESSAGING_REACTION',schoolId,conversationId,messageId,{emoji,active}));
    });
    (active ? app.put.bind(app) : app.delete.bind(app))(`${messagePath}/pin`, request => {
      const { schoolId, conversationId, messageId } = messageParams.parse(request.params);
      return execute(request.headers, request.id, schoolId, (db, actor) => setPinned(db, actor, conversationId, messageId, active).then(data => ({ data })),
        messagingMutation(request.headers['idempotency-key'],'MESSAGING_PIN',schoolId,conversationId,messageId,{pinned:active}));
    });
    (active ? app.put.bind(app) : app.delete.bind(app))(`${path}/general/admins/:personId`, request => {
      const { schoolId, personId } = base.extend({ personId: id }).parse(request.params);
      return execute(request.headers, request.id, schoolId, (db, actor) => setGroupAdmin(db, actor, personId, active).then(data => ({ data })));
    });
  }
  app.put(`${messagePath}/poll/votes`, request => {
    const { schoolId, conversationId, messageId } = messageParams.parse(request.params);
    const body = z.object({ optionIndexes: z.array(z.number().int().min(0).max(11)).max(12) }).strict().parse(request.body);
    return execute(request.headers, request.id, schoolId, (db, actor) => setPollVotes(db, actor, conversationId, messageId, body.optionIndexes).then(data => ({ data })),
      messagingMutation(request.headers['idempotency-key'],'MESSAGING_VOTE',schoolId,conversationId,messageId,body));
  });
  app.post(`${messagePath}/poll/close`, request => {
    const { schoolId, conversationId, messageId } = messageParams.parse(request.params);
    return execute(request.headers, request.id, schoolId, (db, actor) => closePoll(db, actor, conversationId, messageId).then(data => ({ data })));
  });
  app.delete(`${path}/general/members/:personId`, request => {
    const { schoolId, personId } = base.extend({ personId: id }).parse(request.params);
    return execute(request.headers, request.id, schoolId, (db, actor) => removeGeneralMember(db, actor, personId).then(data => ({ data })));
  });
  // Réintégration par un administrateur du groupe : ne voit que ce qui suit.
  app.put(`${path}/general/members/:personId`, request => {
    const { schoolId, personId } = base.extend({ personId: id }).parse(request.params);
    return execute(request.headers, request.id, schoolId, (db, actor) => reinstateGeneralMember(db, actor, personId).then(data => ({ data })));
  });
  // 50 enveloppes de 12 000 caractères au plus : au-delà de la limite commune de 16 Kio.
  app.post(`${path}/reports`, { bodyLimit: 655_360 }, request => {
    const { schoolId } = base.parse(request.params);
    const body = z.object({ clientReportId: id, conversationId: id,
      items: z.array(z.object({ messageId: id, ciphertext: envelope }).strict()).min(1).max(50) }).strict().parse(request.body);
    return execute(request.headers, request.id, schoolId, (db, actor) => createReport(db, actor, body.clientReportId, body.conversationId, body.items).then(data => ({ data })));
  });
  app.get(`${path}/reports`, request => {
    const { schoolId } = base.parse(request.params);
    const query = z.object({ limit: z.coerce.number().int().min(1).max(100).default(50), before: id.optional(),
      status: z.enum(reportStatuses).optional() }).strict().parse(request.query);
    return execute(request.headers, request.id, schoolId, (db, actor) => listReports(db, actor, query.limit, query.before, query.status).then(data => ({ data })));
  });
  // Statut de traitement : administrateurs de l'école seulement, statut attendu comparé sous verrou (409 si périmé).
  app.put(`${path}/reports/:reportId/status`, request => {
    const { schoolId, reportId } = base.extend({ reportId: id }).parse(request.params);
    const body = z.object({ status: z.enum(reportStatuses), expectedStatus: z.enum(reportStatuses) }).strict().parse(request.body);
    return execute(request.headers, request.id, schoolId, (db, actor) => setReportStatus(db, actor, reportId, body.status, body.expectedStatus).then(data => ({ data })));
  });
  // Médias : dépôt et téléchargement d'octets chiffrés opaques, sans temps réel ni notification porteuse de média.
  // La clé de fichier reste dans l'événement Megolm ; aucune route n'est ajoutée au relais crypto.
}
