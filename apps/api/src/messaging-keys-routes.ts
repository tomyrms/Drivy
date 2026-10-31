import type { FastifyInstance } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import type { IncomingHttpHeaders } from 'node:http';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { messagingSchoolGate, type MessagingAccessOptions } from './messaging-access.js';
import { rollbackQuietly } from './database.js';
import { forbidden } from './errors.js';
import { messagingUnavailable } from './messaging.js';
import { mapDatabaseError } from './messaging-view.js';
import { bindDevice, claimKeys, createBackupVersion, deviceIdPattern, getBackupKeys, getBackupVersion, listOwnDevices, queryKeys,
  reportRecipients, revokeDevice, sendToDevice, sync, uploadDeviceSigning, uploadKeys, uploadSignatures, putBackupKeys, type KeyActor } from './messaging-keys.js';

const id = z.uuid();
const base = z.object({ schoolId: id });
const versionQuery = z.object({ version: z.string().regex(/^[1-9][0-9]{0,14}$/) }).strict();

/** Relais de clés Matrix : même garde que la messagerie, plus l'appareil déclaré par X-Drivy-Device-Id. */
export function registerMessagingKeys(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier } & MessagingAccessOptions) {
  const enabled = messagingSchoolGate(options);
  async function execute(headers: IncomingHttpHeaders, requestId: string, schoolId: string,
    work: (db: PoolClient, actor: KeyActor) => Promise<object>, register = true): Promise<object> {
    if (!enabled(schoolId)) throw messagingUnavailable();
    const expectedActor = id.parse(headers['x-drivy-expected-person-id']);
    const expectedEpoch = z.coerce.number().int().positive().safe().parse(headers['x-drivy-expected-access-epoch']);
    const deviceId = z.string().regex(deviceIdPattern).parse(headers['x-drivy-device-id']);
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
      const person = await db.query('SELECT id FROM drivy.person WHERE id=$1 AND status=\'ACTIVE\' FOR SHARE', [personId]);
      if (!person.rows[0]) throw forbidden();
      const school = await db.query('SELECT id FROM drivy.school WHERE id=$1 AND status=\'ACTIVE\' FOR SHARE', [schoolId]);
      if (!school.rows[0]) throw forbidden();
      const member = await db.query<{ id: string; accessEpoch: number }>(`SELECT m.id,m.access_epoch AS "accessEpoch" FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
        WHERE m.school_id=$1 AND m.person_id=$2 AND m.status='ACTIVE' AND p.status='ACTIVE' FOR SHARE OF m`, [schoolId, personId]);
      if (!member.rows[0] || member.rows[0].accessEpoch !== expectedEpoch) throw forbidden();
      await db.query("SELECT set_config('app.membership_id',$1,true)", [member.rows[0].id]);
      const actor: KeyActor = { schoolId, personId: personId.toLowerCase(), membershipId: member.rows[0].id, deviceId };
      if (register) await bindDevice(db, actor);
      const data = await work(db, actor);
      await db.query('COMMIT');
      return { data, context: { schoolId, actorPersonId: personId, accessEpoch: member.rows[0].accessEpoch },
        requestId, serverTime: new Date().toISOString() };
    } catch (error) { broken = !(await rollbackQuietly(db)); throw mapDatabaseError(error); }
    finally { db.release(broken); }
  }
  const path = '/v1/schools/:schoolId/messaging/crypto';
  const body = { bodyLimit: 262_144 };
  const school = (params: unknown) => base.parse(params).schoolId;
  app.post(`${path}/keys/upload`, { bodyLimit: 65_536 }, request =>
    execute(request.headers, request.id, school(request.params), (db, actor) => uploadKeys(db, actor, request.body)));
  app.post(`${path}/keys/query`, body, request =>
    execute(request.headers, request.id, school(request.params), (db, actor) => queryKeys(db, actor, request.body)));
  app.post(`${path}/keys/claim`, { bodyLimit: 65_536 }, request =>
    execute(request.headers, request.id, school(request.params), (db, actor) => claimKeys(db, actor, request.body)));
  app.post(`${path}/keys/device_signing/upload`, { bodyLimit: 32_768 }, request =>
    execute(request.headers, request.id, school(request.params), (db, actor) => uploadDeviceSigning(db, actor, request.body)));
  app.post(`${path}/keys/signatures/upload`, { bodyLimit: 65_536 }, request =>
    execute(request.headers, request.id, school(request.params), (db, actor) => uploadSignatures(db, actor, request.body)));
  app.put(`${path}/sendToDevice/:eventType/:txnId`, body, request => {
    const params = base.extend({ eventType: z.string().regex(/^[A-Za-z0-9._-]{1,64}$/), txnId: z.string().regex(/^[A-Za-z0-9._~-]{1,64}$/) }).parse(request.params);
    return execute(request.headers, request.id, params.schoolId, (db, actor) => sendToDevice(db, actor, params.eventType, params.txnId, request.body));
  });
  app.get(`${path}/sync`, request => {
    const query = z.object({ since: z.string().max(40).optional() }).strict().parse(request.query);
    return execute(request.headers, request.id, school(request.params), (db, actor) => sync(db, actor, query.since));
  });
  app.get(`${path}/report-recipients`, request =>
    execute(request.headers, request.id, school(request.params), (db, actor) => reportRecipients(db, actor)));
  app.get(`${path}/devices`, request =>
    execute(request.headers, request.id, school(request.params), (db, actor) => listOwnDevices(db, actor)));
  app.delete(`${path}/devices/:deviceId`, request => {
    const params = base.extend({ deviceId: z.string().regex(deviceIdPattern) }).parse(request.params);
    return execute(request.headers, request.id, params.schoolId, (db, actor) => revokeDevice(db, actor, params.deviceId));
  });
  app.post(`${path}/room_keys/version`, { bodyLimit: 4_096 }, request =>
    execute(request.headers, request.id, school(request.params), (db, actor) => createBackupVersion(db, actor, request.body)));
  app.get(`${path}/room_keys/version`, request =>
    execute(request.headers, request.id, school(request.params), (db, actor) => getBackupVersion(db, actor)));
  app.put(`${path}/room_keys/keys`, { bodyLimit: 4_194_304 }, request => {
    const query = versionQuery.parse(request.query);
    return execute(request.headers, request.id, school(request.params), (db, actor) => putBackupKeys(db, actor, query.version, request.body));
  });
  app.get(`${path}/room_keys/keys`, request => {
    const query = versionQuery.parse(request.query);
    return execute(request.headers, request.id, school(request.params), (db, actor) => getBackupKeys(db, actor, query.version));
  });
}
