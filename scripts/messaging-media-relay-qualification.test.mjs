import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';
import { inflateSync } from 'node:zlib';
import { Pool } from 'pg';
import { buildQualificationRelay, qualificationConfig } from './messaging-relay-qualification.mts';
import { mediaFixtureCollisions, mediaFixtureIds, mediaFixtureSubjects, mediaReadinessFixture,
  seedMessagingMediaFixtures } from './qualification/messaging-media-fixtures.mjs';
import { fixtureIds } from '../apps/api/scripts/fixtures.js';

/**
 * Fixture image partagée avec `MessagingMediaRealRelayTests.swift` (même base64, PNG 1×1 RGB).
 * Ce fichier en vérifie réellement les CRC et la décompression zlib ; ImageIO reste du ressort
 * de la future exécution Apple, et cette preuve ne la remplace pas.
 */
const fixturePngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mNQaFAAAAGEAMFfsCuZAAAAAElFTkSuQmCC';

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}

/** Forme UUID (8-4-4-4-12 hex), sans épingler la version : `randomUUID()` de la production. */
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Parité de forme avec la production (`genReqId: () => randomUUID()` dans `app.ts`) : le
 * décodeur Swift décode `requestId` en `UUID` pour les enveloppes média (PUT et DELETE).
 * Le contrôle n'imprime que le libellé et un booléen, jamais l'identifiant.
 */
function expectUuidRequestId(envelope, label) {
  const value = envelope?.requestId;
  assert.equal(typeof value === 'string' && uuidPattern.test(value), true,
    `${label} : requestId UUID attendu, comme la production`);
}


/**
 * Qualification Node du bootstrap média (#97, Q97).
 *
 * Ce fichier ne réimplémente aucune route : il construit le **même** relais de qualification
 * que le harnais iOS (mêmes gardes, mêmes fixtures, mêmes routes produit) et injecte des
 * requêtes dans l'instance Fastify. Il s'exécute sur une vraie PostgreSQL 17 synthétique
 * (`TEST_DATABASE_URL`, base `drivy_test` loopback) et n'écrit aucune donnée réelle.
 *
 * Le serveur HTTPS jetable reste lancé par `scripts/ios/relay-qualification.sh` : ici, le
 * certificat éphémère est seulement exigé par la garde de configuration (aucune clé d'hôte).
 */

const base = {
  NODE_ENV: 'test', DRIVY_RELAY_ALLOW_RESET: '1',
  TEST_DATABASE_URL: 'postgresql://fixture:fixture@127.0.0.1:15497/drivy_test',
  DRIVY_RELAY_TLS_CERT: '/temporary/localhost.crt', DRIVY_RELAY_TLS_KEY: '/temporary/localhost.key'
};

// La porte de messagerie lit `process.env.NODE_ENV` : le relais de qualification ne sert
// qu'avec la même valeur que le harnais iOS, jamais en production.
process.env.NODE_ENV = 'test';

/** Certificat et clé éphémères de ce run, sous un répertoire temporaire appelant. */
function makeEphemeralTls(directory) {
  const extension = join(directory, 'tls.cnf');
  writeFileSync(extension, '[server]\nsubjectAltName = DNS:localhost,IP:127.0.0.1\nextendedKeyUsage = serverAuth\n');
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-days', '1',
    '-subj', '/CN=Drivy fixture qualification CA', '-keyout', join(directory, 'ca.key'), '-out', join(directory, 'ca.crt')]);
  execFileSync('openssl', ['req', '-new', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-subj', '/CN=localhost',
    '-keyout', join(directory, 'server.key'), '-out', join(directory, 'server.csr')]);
  execFileSync('openssl', ['x509', '-req', '-sha256', '-days', '1', '-in', join(directory, 'server.csr'),
    '-CA', join(directory, 'ca.crt'), '-CAkey', join(directory, 'ca.key'), '-CAcreateserial',
    '-extfile', extension, '-extensions', 'server', '-out', join(directory, 'server.crt')]);
  return { certificate: join(directory, 'server.crt'), key: join(directory, 'server.key') };
}

describe('gardes de configuration du relais média', () => {
  test('la configuration jetable reste acceptée à l’identique', () => {
    assert.equal(qualificationConfig(base).port, 18443);
  });
  for (const [name, changes] of [
    ['mode production', { NODE_ENV: 'production' }],
    ['opt-in de reset absent', { DRIVY_RELAY_ALLOW_RESET: '' }],
    ['base distante', { TEST_DATABASE_URL: 'postgresql://fixture:fixture@db.example.invalid/drivy_test' }],
    ['base non dédiée', { TEST_DATABASE_URL: 'postgresql://fixture:fixture@localhost/production' }],
    ['paramètre de contournement', { TEST_DATABASE_URL: 'postgresql://fixture:fixture@localhost/drivy_test?host=remote' }],
    ['TLS absent', { DRIVY_RELAY_TLS_CERT: '' }],
    ['port invalide', { DRIVY_RELAY_PORT: '0' }]
  ]) {
    test(`refuse ${name} sans divulguer la configuration`, async () => {
      const sentinel = 'SYNTHETIC_SENTINEL_NEVER_PRINT';
      const env = { ...base, ...changes, DRIVY_RELAY_TLS_KEY: `/temporary/${sentinel}.key` };
      // Le refus précède toute connexion : aucun corps ni chemin n'est répété.
      await assert.rejects(buildQualificationRelay(env), error => {
        assert.equal(error.message, 'RELAY_QUALIFICATION_CONFIGURATION_REQUIRED');
        assert.equal(error.message.includes(sentinel), false);
        return true;
      });
    });
  }
  test('les identités média sont disjointes des fixtures canoniques', () => {
    assert.deepEqual(mediaFixtureCollisions(), []);
    const canonical = new Set(Object.values(fixtureIds));
    for (const value of Object.values(mediaFixtureIds)) {
      assert.match(value, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
      assert.equal(canonical.has(value), false);
    }
    assert.notEqual(mediaFixtureSubjects.instructor, 'demo-instructor');
    assert.notEqual(mediaFixtureSubjects.learner, 'demo-alice');
  });
  test('le seed refuse un émetteur non synthétique avant toute connexion', async () => {
    const denied = { connect() { throw new Error('DATABASE_MUST_NOT_BE_CONTACTED'); } };
    await assert.rejects(seedMessagingMediaFixtures(denied, 'https://identity.example.com'), /^Error: MEDIA_FIXTURE_ISSUER_REQUIRED$/);
    await assert.rejects(seedMessagingMediaFixtures(denied, ''), /^Error: MEDIA_FIXTURE_ISSUER_REQUIRED$/);
  });
  test('la fixture image est un PNG réellement valide (CRC et zlib)', () => {
    const bytes = Buffer.from(fixturePngBase64, 'base64');
    assert.deepEqual([...bytes.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const chunks = [];
    let offset = 8;
    while (offset < bytes.length) {
      const length = bytes.readUInt32BE(offset);
      const type = bytes.subarray(offset + 4, offset + 8).toString('ascii');
      const data = bytes.subarray(offset + 8, offset + 8 + length);
      const stored = bytes.readUInt32BE(offset + 8 + length);
      // Chaque CRC de chunk est recalculé : un IDAT corrompu (cas du premier jet) échoue ici.
      assert.equal(stored, crc32(bytes.subarray(offset + 4, offset + 8 + length)), `CRC ${type}`);
      chunks.push({ type, data });
      offset += 12 + length;
    }
    assert.deepEqual(chunks.map(chunk => chunk.type), ['IHDR', 'IDAT', 'IEND']);
    const header = chunks[0].data;
    assert.equal(header.readUInt32BE(0), 1);
    assert.equal(header.readUInt32BE(4), 1);
    assert.equal(header[8], 8);
    assert.equal(header[9], 2);
    // Décompression réelle du flux IDAT : un zlib corrompu lèverait ici.
    assert.deepEqual([...inflateSync(chunks[1].data)], [0, 0x20, 0x80, 0x20]);
  });
});

describe('cible de reset réellement consommée', () => {
  // `freshDatabase()` lit `process.env.TEST_DATABASE_URL` : une configuration validée qui
  // diverge de l'environnement du processus ne doit jamais atteindre le reset. Les chemins TLS
  // volontairement absents prouvent que le refus précède toute lecture de fichier, et aucune
  // adresse n'est contactée (cible loopback ou base non dédiée uniquement).
  const divergent = [
    ['hôte', { TEST_DATABASE_URL: 'postgresql://fixture:fixture@127.0.0.1:15498/drivy_test' }],
    ['base', { TEST_DATABASE_URL: 'postgresql://fixture:fixture@127.0.0.1:15497/other_database' }],
    ['mode', { NODE_ENV: 'production' }],
    ['opt-in', { DRIVY_RELAY_ALLOW_RESET: '' }]
  ];
  const watched = ['TEST_DATABASE_URL', 'NODE_ENV', 'DRIVY_RELAY_ALLOW_RESET'];

  for (const [name, change] of divergent) {
    test(`refuse une cible de reset divergente (${name}) avant TLS et connexion`, async () => {
      const saved = Object.fromEntries(watched.map(key => [key, process.env[key]]));
      try {
        process.env.TEST_DATABASE_URL = base.TEST_DATABASE_URL;
        process.env.NODE_ENV = 'test';
        process.env.DRIVY_RELAY_ALLOW_RESET = '1';
        for (const [key, value] of Object.entries(change)) process.env[key] = value;
        await assert.rejects(buildQualificationRelay({
          ...base, DRIVY_RELAY_TLS_CERT: '/nonexistent/media-fixture.crt', DRIVY_RELAY_TLS_KEY: '/nonexistent/media-fixture.key'
        }), error => {
          assert.equal(error.message, 'RELAY_QUALIFICATION_ENVIRONMENT_DIVERGED');
          return true;
        });
      } finally {
        for (const key of watched) {
          if (saved[key] === undefined) delete process.env[key];
          else process.env[key] = saved[key];
        }
      }
    });
  }

  test('refuse une mutation de l’environnement pendant la lecture TLS (alias process.env)', async () => {
    // Chemin réel du CLI : c'est `process.env` lui-même qui est passé. La comparaison ne peut
    // donc pas porter sur le même objet mutable ; la cible validée doit être figée avant les
    // attentes puis comparée à la source consommée juste avant le reset.
    const saved = Object.fromEntries([...watched, 'DRIVY_RELAY_TLS_CERT', 'DRIVY_RELAY_TLS_KEY']
      .map(key => [key, process.env[key]]));
    const directory = mkdtempSync(join(tmpdir(), 'drivy-msgrelay97-alias-'));
    try {
      const tls = makeEphemeralTls(directory);
      process.env.TEST_DATABASE_URL = base.TEST_DATABASE_URL;
      process.env.NODE_ENV = 'test';
      process.env.DRIVY_RELAY_ALLOW_RESET = '1';
      process.env.DRIVY_RELAY_TLS_CERT = tls.certificate;
      process.env.DRIVY_RELAY_TLS_KEY = tls.key;
      const operation = buildQualificationRelay(process.env);
      // Mutation pendant la première suspension (lecture TLS) : sans snapshot figé, ce second
      // contrôle comparerait l'objet à lui-même et laisserait atteindre freshDatabase.
      delete process.env.TEST_DATABASE_URL;
      await assert.rejects(operation, error => {
        // Le helper échoue avant tout Pool : aucune base, aucun hôte distant n'est contacté.
        assert.equal(error.message, 'RELAY_QUALIFICATION_ENVIRONMENT_DIVERGED');
        return true;
      });
    } finally {
      for (const key of [...watched, 'DRIVY_RELAY_TLS_CERT', 'DRIVY_RELAY_TLS_KEY']) {
        const value = saved[key];
        if (value === undefined) delete process.env[key];
        else process.env[key] = value;
      }
      rmSync(directory, { recursive: true, force: true });
    }
  });
});

describe('bootstrap média sur PostgreSQL synthétique', () => {
  let directory;
  let relay;
  let pool;
  let accessEpoch;
  let conversationId;
  let membersEpoch;
  let uploadedSha;
  const mediaId = '5c1f0000-0000-4000-8000-000000000001';
  const cancelledMediaId = '5c1f0000-0000-4000-8000-000000000002';
  const conflictMediaId = '5c1f0000-0000-4000-8000-000000000003';
  const deviceId = 'MEDIAFIXTURE01';
  const learnerDeviceId = 'MEDIALEARNER01';
  const foreignDeviceId = 'MEDIAFOREIGN01';
  const ciphertext = Buffer.from(Array.from({ length: 512 }, (_, index) => (index * 37 + 11) % 256));
  const otherCiphertext = Buffer.from(Array.from({ length: 64 }, (_, index) => (index * 13 + 7) % 256));

  const url = (schoolId, suffix) => `/v1/schools/${schoolId}/messaging${suffix}`;
  const headers = (subject, personId) => ({
    authorization: `Bearer ${subject}`,
    'x-drivy-expected-person-id': personId,
    'x-drivy-expected-access-epoch': String(accessEpoch)
  });
  const instructor = () => headers(mediaFixtureSubjects.instructor, mediaFixtureIds.instructor);
  const learner = () => headers(mediaFixtureSubjects.learner, mediaFixtureIds.learner);

  before(async () => {
    if (!process.env.TEST_DATABASE_URL) throw new Error('TEST_DATABASE_URL_REQUIRED');
    directory = mkdtempSync(join(tmpdir(), 'drivy-msgrelay97-'));
    const tls = makeEphemeralTls(directory);
    // Le chemin positif doit être exactement celui du CLI : le relais reçoit l'environnement
    // qu'il consommera pour le reset, donc aucune cible validée ne peut différer de la cible réelle.
    process.env.NODE_ENV = 'test';
    process.env.DRIVY_RELAY_ALLOW_RESET = '1';
    process.env.DRIVY_RELAY_TLS_CERT = tls.certificate;
    process.env.DRIVY_RELAY_TLS_KEY = tls.key;
    relay = await buildQualificationRelay(process.env);
    pool = new Pool({ connectionString: process.env.TEST_DATABASE_URL });
    const membership = await pool.query('SELECT access_epoch FROM drivy.membership WHERE id=$1', [mediaFixtureIds.instructorMember]);
    accessEpoch = membership.rows[0].access_epoch;
    await pool.query(`INSERT INTO drivy.messaging_device(school_id,person_id,device_id,created_by_issuer,created_by_subject)
      VALUES($1,$2,$3,'https://messaging-relay.example.invalid',$4)`,
      [mediaFixtureIds.school, mediaFixtureIds.instructor, deviceId, mediaFixtureSubjects.instructor]);
  });

  after(async () => {
    await pool?.end();
    await relay?.close();
    for (const key of ['DRIVY_RELAY_TLS_CERT', 'DRIVY_RELAY_TLS_KEY', 'DRIVY_RELAY_ALLOW_RESET']) delete process.env[key];
    if (directory) rmSync(directory, { recursive: true, force: true });
  });

  test('la readiness annonce les identités média sans changer les champs canoniques', async () => {
    const response = await relay.app.inject({ method: 'GET', url: '/qualification/ready' });
    assert.equal(response.statusCode, 200);
    const body = response.json();
    assert.equal(body.ready, true);
    assert.equal(body.fixture, 'drivy-messaging-relay-v1');
    assert.equal(body.schoolId, fixtureIds.schoolA);
    assert.equal(body.adminId, fixtureIds.admin);
    assert.equal(body.instructorId, fixtureIds.instructor);
    assert.equal(body.learnerId, fixtureIds.alice);
    assert.deepEqual(body.media, {
      fixture: mediaReadinessFixture, schoolId: mediaFixtureIds.school,
      instructorId: mediaFixtureIds.instructor, learnerId: mediaFixtureIds.learner,
      foreignSchoolId: mediaFixtureIds.foreignSchool, foreignId: mediaFixtureIds.foreign
    });
  });

  test('le seed isole les scénarios et reste idempotent', async () => {
    const canonical = await pool.query('SELECT name, status FROM drivy.school WHERE id=$1', [fixtureIds.schoolA]);
    assert.deepEqual(canonical.rows[0], { name: 'Auto-école Horizon · Démonstration', status: 'ACTIVE' });
    const mediaSchool = await pool.query('SELECT name FROM drivy.school WHERE id=$1', [mediaFixtureIds.school]);
    assert.equal(mediaSchool.rows[0].name, 'Auto-école Média · Qualification');
    const roles = await pool.query('SELECT roles FROM drivy.membership WHERE id=ANY($1) ORDER BY id',
      [[mediaFixtureIds.instructorMember, mediaFixtureIds.learnerMember]]);
    assert.deepEqual(roles.rows.map(row => row.roles), [['INSTRUCTOR'], ['LEARNER']]);
    // Précondition du test historique : son élève canonique reste sans clés, sans conversation.
    for (const person of [fixtureIds.alice, mediaFixtureIds.learner]) {
      const devices = await pool.query('SELECT count(*)::int AS total FROM drivy.messaging_device WHERE person_id=$1', [person]);
      assert.equal(devices.rows[0].total, 0);
      const conversations = await pool.query(
        'SELECT count(*)::int AS total FROM drivy.messaging_conversation WHERE person_low=$1 OR person_high=$1', [person]);
      assert.equal(conversations.rows[0].total, 0);
    }
    const before = await pool.query(`SELECT
      (SELECT count(*)::int FROM drivy.person) AS persons,
      (SELECT count(*)::int FROM drivy.membership) AS memberships,
      (SELECT count(*)::int FROM drivy.training) AS trainings`);
    await seedMessagingMediaFixtures(pool, 'https://messaging-relay.example.invalid');
    const again = await pool.query(`SELECT
      (SELECT count(*)::int FROM drivy.person) AS persons,
      (SELECT count(*)::int FROM drivy.membership) AS memberships,
      (SELECT count(*)::int FROM drivy.training) AS trainings`);
    assert.deepEqual(again.rows[0], before.rows[0]);
  });

  test('l’authentification média refuse un jeton inconnu et une école étrangère', async () => {
    const unknown = await relay.app.inject({ method: 'GET', url: url(mediaFixtureIds.school, '/conversations'),
      headers: { ...learner(), authorization: 'Bearer unknown-fixture' } });
    assert.equal(unknown.statusCode, 401);
    const wrongSchool = await relay.app.inject({ method: 'GET', url: url(mediaFixtureIds.school, '/conversations'),
      headers: headers('demo-alice', fixtureIds.alice) });
    assert.equal(wrongSchool.statusCode, 403);
  });

  test('la conversation privée média est autorisée par les relations réelles', async () => {
    const created = await relay.app.inject({ method: 'PUT',
      url: url(mediaFixtureIds.school, `/private/${mediaFixtureIds.learner}`), headers: instructor() });
    assert.equal(created.statusCode, 200);
    conversationId = created.json().data.conversationId;
    assert.match(conversationId, /^[0-9a-f-]{36}$/);
    membersEpoch = Number((await pool.query('SELECT members_epoch FROM drivy.messaging_conversation WHERE id=$1', [conversationId]))
      .rows[0].members_epoch);
    const repeated = await relay.app.inject({ method: 'PUT',
      url: url(mediaFixtureIds.school, `/private/${mediaFixtureIds.learner}`), headers: instructor() });
    assert.equal(repeated.json().data.conversationId, conversationId);
  });

  test('le dépôt média exige un appareil actif puis reste idempotent', async () => {
    const mediaPath = `/conversations/${conversationId}/media/`;
    const withoutDevice = await relay.app.inject({ method: 'PUT', url: url(mediaFixtureIds.school, mediaPath + mediaId),
      headers: { ...instructor(), 'content-type': 'application/octet-stream' }, payload: ciphertext });
    assert.equal(withoutDevice.statusCode, 403);
    assert.equal(withoutDevice.json().code, 'MESSAGING_DEVICE_REQUIRED');
    const unregistered = await relay.app.inject({ method: 'PUT', url: url(mediaFixtureIds.school, mediaPath + mediaId),
      headers: { ...instructor(), 'content-type': 'application/octet-stream', 'x-drivy-device-id': 'UNREGISTERED01' },
      payload: ciphertext });
    assert.equal(unregistered.statusCode, 403);

    const uploaded = await relay.app.inject({ method: 'PUT', url: url(mediaFixtureIds.school, mediaPath + mediaId),
      headers: { ...instructor(), 'content-type': 'application/octet-stream', 'x-drivy-device-id': deviceId },
      payload: ciphertext });
    assert.equal(uploaded.statusCode, 200);
    assert.equal(uploaded.json().data.state, 'UPLOADED');
    assert.equal(uploaded.json().data.byteSize, ciphertext.length);
    assert.match(uploaded.json().data.sha256, /^[0-9a-f]{64}$/);
    uploadedSha = uploaded.json().data.sha256;
    // Forme de production : `requestId` UUID (le décodeur Swift le décode en `UUID`).
    expectUuidRequestId(uploaded.json(), 'PUT média');

    const replayed = await relay.app.inject({ method: 'PUT', url: url(mediaFixtureIds.school, mediaPath + mediaId),
      headers: { ...instructor(), 'content-type': 'application/octet-stream', 'x-drivy-device-id': deviceId },
      payload: ciphertext });
    assert.equal(replayed.statusCode, 200);
    assert.equal(replayed.json().data.sha256, uploaded.json().data.sha256);
    expectUuidRequestId(replayed.json(), 'PUT média rejoué');

    const conflicting = await relay.app.inject({ method: 'PUT', url: url(mediaFixtureIds.school, mediaPath + mediaId),
      headers: { ...instructor(), 'content-type': 'application/octet-stream', 'x-drivy-device-id': deviceId },
      payload: otherCiphertext });
    assert.equal(conflicting.statusCode, 409);
    assert.equal(conflicting.json().code, 'MEDIA_INTENT_CONFLICT');

    const cancellation = await relay.app.inject({ method: 'PUT', url: url(mediaFixtureIds.school, mediaPath + cancelledMediaId),
      headers: { ...instructor(), 'content-type': 'application/octet-stream', 'x-drivy-device-id': deviceId },
      payload: otherCiphertext });
    assert.equal(cancellation.statusCode, 200);
  });

  test('le message porte la référence média, le destinataire la relit et télécharge les octets', async () => {
    // Appareils supplémentaires strictement synthétiques : le harnais iOS, lui, enregistre les
    // siens par la vraie machine Matrix. Ici, seule la garde « appareil actif » est exercée.
    for (const [school, person, device, subject] of [
      [mediaFixtureIds.school, mediaFixtureIds.learner, learnerDeviceId, mediaFixtureSubjects.learner],
      [mediaFixtureIds.foreignSchool, mediaFixtureIds.foreign, foreignDeviceId, mediaFixtureSubjects.foreign]
    ]) {
      await pool.query(`INSERT INTO drivy.messaging_device(school_id,person_id,device_id,created_by_issuer,created_by_subject)
        VALUES($1,$2,$3,'https://messaging-relay.example.invalid',$4) ON CONFLICT DO NOTHING`, [school, person, device, subject]);
    }
    const messageId = randomUUID();
    const sent = await relay.app.inject({ method: 'POST',
      url: url(mediaFixtureIds.school, `/conversations/${conversationId}/messages`), headers: instructor(),
      payload: { clientMessageId: messageId,
        ciphertext: { scheme: 'megolm.v1', keyId: 'fixture-key', payload: Buffer.from('synthetic-envelope').toString('base64') },
        mentionPersonIds: [], expectedMembersEpoch: membersEpoch, media: { mediaId, byteSize: ciphertext.length } } });
    assert.equal(sent.statusCode, 200);
    const accepted = sent.json().data;
    assert.equal(accepted.media.mediaId, mediaId);
    assert.equal(accepted.media.byteSize, ciphertext.length);
    assert.equal(accepted.media.deleted, false);
    assert.equal(JSON.stringify(accepted).includes('synthetic-envelope'), false);
    expectUuidRequestId(sent.json(), 'POST message média');

    const page = await relay.app.inject({ method: 'GET',
      url: url(mediaFixtureIds.school, `/conversations/${conversationId}/messages`), headers: learner() });
    assert.equal(page.statusCode, 200);
    const item = page.json().data.items.find(entry => entry.id === accepted.id);
    assert.ok(item, 'le destinataire relit le message accepté');
    assert.equal(item.senderId, mediaFixtureIds.instructor);
    assert.deepEqual(item.media, { mediaId, byteSize: ciphertext.length, deleted: false });

    const download = await relay.app.inject({ method: 'GET',
      url: url(mediaFixtureIds.school, `/conversations/${conversationId}/media/${mediaId}`),
      headers: { ...learner(), 'x-drivy-device-id': learnerDeviceId } });
    assert.equal(download.statusCode, 200);
    assert.equal(download.headers['content-type'], 'application/octet-stream');
    assert.equal(download.headers['cache-control'], 'private, no-store');
    assert.equal(download.headers['x-drivy-media-sha256'], uploadedSha);
    assert.deepEqual(Buffer.from(download.rawPayload), ciphertext);

    const foreign = await relay.app.inject({ method: 'GET',
      url: url(mediaFixtureIds.foreignSchool, `/conversations/${conversationId}/media/${mediaId}`),
      headers: { ...headers(mediaFixtureSubjects.foreign, mediaFixtureIds.foreign), 'x-drivy-device-id': foreignDeviceId } });
    assert.equal(foreign.statusCode, 404);
    assert.equal(foreign.json().code, 'MEDIA_NOT_FOUND');
  });

  test('l’annulation reste possible avant attache et la suppression pour tous purge le média', async () => {
    const cancelPath = url(mediaFixtureIds.school, `/conversations/${conversationId}/media/${cancelledMediaId}`);
    const cancelled = await relay.app.inject({ method: 'DELETE', url: cancelPath,
      headers: { ...instructor(), 'x-drivy-device-id': deviceId } });
    assert.equal(cancelled.statusCode, 200);
    assert.equal(cancelled.json().data.deleted, true);
    // L'enveloppe d'annulation est aussi décodée en `UUID` côté Swift.
    expectUuidRequestId(cancelled.json(), 'DELETE annulation');
    const again = await relay.app.inject({ method: 'DELETE', url: cancelPath,
      headers: { ...instructor(), 'x-drivy-device-id': deviceId } });
    assert.equal(again.statusCode, 200);
    expectUuidRequestId(again.json(), 'DELETE annulation idempotente');
    const gone = await relay.app.inject({ method: 'GET', url: cancelPath,
      headers: { ...instructor(), 'x-drivy-device-id': deviceId } });
    assert.equal(gone.statusCode, 404);

    const attachedCancel = await relay.app.inject({ method: 'DELETE',
      url: url(mediaFixtureIds.school, `/conversations/${conversationId}/media/${mediaId}`),
      headers: { ...instructor(), 'x-drivy-device-id': deviceId } });
    assert.equal(attachedCancel.statusCode, 409);
    assert.equal(attachedCancel.json().code, 'MEDIA_ALREADY_ATTACHED');

    const messages = await relay.app.inject({ method: 'GET',
      url: url(mediaFixtureIds.school, `/conversations/${conversationId}/messages`), headers: instructor() });
    const serverMessageId = messages.json().data.items.find(entry => entry.media?.mediaId === mediaId).id;
    const deleted = await relay.app.inject({ method: 'DELETE',
      url: url(mediaFixtureIds.school, `/conversations/${conversationId}/messages/${serverMessageId}?scope=everyone`),
      headers: instructor() });
    assert.equal(deleted.statusCode, 200);
    const afterDeletion = await relay.app.inject({ method: 'GET',
      url: url(mediaFixtureIds.school, `/conversations/${conversationId}/messages`), headers: learner() });
    const tombstone = afterDeletion.json().data.items.find(entry => entry.id === serverMessageId);
    assert.equal(tombstone.deletedForEveryone, true);
    assert.equal(tombstone.ciphertext, null);
    assert.deepEqual(tombstone.media, { mediaId, byteSize: ciphertext.length, deleted: true });
    const purged = await relay.app.inject({ method: 'GET',
      url: url(mediaFixtureIds.school, `/conversations/${conversationId}/media/${mediaId}`),
      headers: { ...learner(), 'x-drivy-device-id': learnerDeviceId } });
    assert.equal(purged.statusCode, 404);
  });
});
