import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import Fastify from 'fastify';
import { freshDatabase } from '../apps/api/test/support/harness.js';
import { seedFixtures, fixtureIds } from '../apps/api/scripts/fixtures.js';
import { registerMessaging } from '../apps/api/src/messaging-routes.js';
import { registerMessagingKeys } from '../apps/api/src/messaging-keys-routes.js';
import { ApiError } from '../apps/api/src/errors.js';
import { mediaFixtureIds, mediaFixtureSubjects, mediaReadinessFixture, seedMessagingMediaFixtures }
  from './qualification/messaging-media-fixtures.mjs';

/** Test-only bootstrap. Never import into the deployed API composition. */
export function qualificationConfig(env: Record<string, string | undefined>) {
  const deny = () => { throw new Error('RELAY_QUALIFICATION_CONFIGURATION_REQUIRED'); };
  if (env.NODE_ENV !== 'test' || env.DRIVY_RELAY_ALLOW_RESET !== '1') deny();
  let database: URL;
  try { database = new URL(env.TEST_DATABASE_URL ?? ''); } catch { return deny(); }
  if (!['postgres:', 'postgresql:'].includes(database.protocol)
      || !['localhost', '127.0.0.1', '[::1]'].includes(database.hostname)
      || database.pathname !== '/drivy_test' || database.search || database.hash) deny();
  const port = Number(env.DRIVY_RELAY_PORT ?? '18443');
  if (!Number.isInteger(port) || port < 1024 || port > 65535
      || !env.DRIVY_RELAY_TLS_CERT || !env.DRIVY_RELAY_TLS_KEY) deny();
  return { port, certificate: env.DRIVY_RELAY_TLS_CERT!, key: env.DRIVY_RELAY_TLS_KEY! };
}

/** Cible de reset figée : un snapshot indépendant, jamais l'objet `env` mutable (souvent `process.env`). */
interface ResetTarget {
  readonly database: string | undefined;
  readonly mode: string | undefined;
  readonly reset: string | undefined;
}

/**
 * La réinitialisation destructrice lit `process.env.TEST_DATABASE_URL` : la seule cible
 * effective est donc l'environnement du processus. Les valeurs validées sont figées dans un
 * snapshot immuable *avant* les attentes, puis comparées à cette source réellement consommée
 * avant tout fichier TLS et de nouveau juste avant le reset. Comparer `env` à lui-même ne
 * prouverait rien quand l'appelant passe `process.env`.
 */
function captureResetTarget(env: Record<string, string | undefined>): ResetTarget {
  return Object.freeze({
    database: env.TEST_DATABASE_URL,
    mode: env.NODE_ENV,
    reset: env.DRIVY_RELAY_ALLOW_RESET
  });
}

function assertEffectiveResetEnvironment(target: ResetTarget) {
  const diverged = target.database !== process.env.TEST_DATABASE_URL
    || target.mode !== process.env.NODE_ENV
    || target.reset !== process.env.DRIVY_RELAY_ALLOW_RESET;
  if (diverged) throw new Error('RELAY_QUALIFICATION_ENVIRONMENT_DIVERGED');
}

export async function startQualificationRelay() {
  const { app, pool, config, close: closeResources } = await buildQualificationRelay(process.env);
  try {
    await app.listen({ host: '127.0.0.1', port: config.port });
  } catch {
    await closeResources();
    throw new Error('RELAY_QUALIFICATION_START_FAILED');
  }
  let closed = false;
  const close = async () => {
    if (closed) return;
    closed = true;
    await app.close();
    await pool.end();
  };
  return { close };
}

/**
 * Construction seule, sans écoute : même configuration, mêmes gardes, mêmes fixtures et
 * mêmes routes que le serveur TLS. Réservée à la qualification Node, qui injecte des
 * requêtes dans l'instance Fastify (le serveur HTTPS jetable reste lancé par le harnais iOS).
 */
export async function buildQualificationRelay(env: Record<string, string | undefined>) {
  const config = qualificationConfig(env);
  // Snapshot figé AVANT les lectures : un `env` mutable (alias de `process.env` dans le CLI)
  // ne peut plus faire coïncider « validé » et « consommé ».
  const target = captureResetTarget(env);
  // Aucune lecture de fichier ni connexion avant la preuve que la cible validée est bien celle
  // que le reset consommera réellement.
  assertEffectiveResetEnvironment(target);
  // Read TLS inputs BEFORE the destructive, explicitly opted-in fixture reset.
  const cert = await readFile(config.certificate);
  const key = await readFile(config.key);
  // Contrôle répété dans la même passe synchrone que l'appel : `freshDatabase()` lit
  // `process.env` en tout premier, sans suspension intermédiaire.
  assertEffectiveResetEnvironment(target);
  const pool = await freshDatabase();
  const issuer = 'https://messaging-relay.example.invalid';
  // Parité de forme avec la production (`apps/api/src/app.ts`, `genReqId: () => randomUUID()`) :
  // l'enveloppe média renvoie `request.id`, que les décodeurs Swift attendent en `UUID`.
  // Aucune autre option, route, garde ni certificat n'est modifié.
  const app = Fastify({ logger: false, disableRequestLogging: true, genReqId: () => randomUUID(),
    https: { cert, key }, bodyLimit: 1_048_576 });
  try {
    // Canonical fixture IDs and relationships. Adds this synthetic issuer only.
    await seedFixtures(pool, issuer);
    // École et comptes média strictement distincts : jamais les identités du harnais texte.
    await seedMessagingMediaFixtures(pool, issuer);
    const accepted = new Set(['demo-instructor', 'demo-alice', 'demo-admin',
      mediaFixtureSubjects.instructor, mediaFixtureSubjects.learner, mediaFixtureSubjects.foreign]);
    const verifyToken = async (authorization?: string) => {
      const subject = authorization?.startsWith('Bearer ') ? authorization.slice(7) : '';
      if (!accepted.has(subject)) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
      return { issuer, subject };
    };
    app.setErrorHandler((error, _request, reply) => {
      const status = error instanceof ApiError ? error.status : 500;
      // No error.message/stack/request/body/token, including validation errors.
      return reply.status(status).send({ code: error instanceof ApiError ? error.code : 'QUALIFICATION_REQUEST_FAILED' });
    });
    registerMessaging(app, { pool, verifyToken, mode: 'test-synthetic' });
    registerMessagingKeys(app, { pool, verifyToken, mode: 'test-synthetic' });
    app.get('/qualification/ready', async () => ({
      ready: true, fixture: 'drivy-messaging-relay-v1',
      schoolId: fixtureIds.schoolA, adminId: fixtureIds.admin, instructorId: fixtureIds.instructor, learnerId: fixtureIds.alice,
      // Champs additionnels média : les consommateurs historiques lisent les précédents sans changement.
      media: {
        fixture: mediaReadinessFixture,
        schoolId: mediaFixtureIds.school,
        instructorId: mediaFixtureIds.instructor,
        learnerId: mediaFixtureIds.learner,
        foreignSchoolId: mediaFixtureIds.foreignSchool,
        foreignId: mediaFixtureIds.foreign
      }
    }));
  } catch {
    await app.close();
    await pool.end();
    throw new Error('RELAY_QUALIFICATION_START_FAILED');
  }
  let closed = false;
  const close = async () => {
    if (closed) return;
    closed = true;
    await app.close();
    await pool.end();
  };
  return { app, pool, config, close };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  startQualificationRelay().then(({ close }) => {
    process.stdout.write('RELAY_QUALIFICATION_READY\n');
    const stop = () => { close().then(() => process.exit(0), () => process.exit(1)); };
    process.once('SIGINT', stop);
    process.once('SIGTERM', stop);
    // Bound orphan lifetime. CI must still trap and stop its own process.
    setTimeout(stop, 120 * 60_000).unref();
  }).catch(() => {
    process.stderr.write('RELAY_QUALIFICATION_START_FAILED\n');
    process.exitCode = 1;
  });
}
