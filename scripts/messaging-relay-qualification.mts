import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import Fastify from 'fastify';
import { freshDatabase } from '../apps/api/test/support/harness.js';
import { seedFixtures, fixtureIds } from '../apps/api/scripts/fixtures.js';
import { registerMessaging } from '../apps/api/src/messaging-routes.js';
import { registerMessagingKeys } from '../apps/api/src/messaging-keys-routes.js';
import { ApiError } from '../apps/api/src/errors.js';

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

export async function startQualificationRelay() {
  const config = qualificationConfig(process.env);
  // Read TLS inputs BEFORE the destructive, explicitly opted-in fixture reset.
  const cert = await readFile(config.certificate);
  const key = await readFile(config.key);
  const pool = await freshDatabase();
  const issuer = 'https://messaging-relay.example.invalid';
  const app = Fastify({ logger: false, disableRequestLogging: true, https: { cert, key }, bodyLimit: 1_048_576 });
  try {
    // Canonical fixture IDs and relationships. Adds this synthetic issuer only.
    await seedFixtures(pool, issuer);
    const accepted = new Set(['demo-instructor', 'demo-alice']);
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
      schoolId: fixtureIds.schoolA, instructorId: fixtureIds.instructor, learnerId: fixtureIds.alice
    }));
    await app.listen({ host: '127.0.0.1', port: config.port });
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
  return { close };
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
