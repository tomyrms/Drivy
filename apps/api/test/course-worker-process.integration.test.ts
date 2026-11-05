import { randomBytes, randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:net';
import { promisify } from 'node:util';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { freshDatabase, harness, prepareSchool, id, type Call } from './support/harness.js';
import { posix, startWorker, waitFor, waitForExit, workerEnvironment, type WorkerHandle } from './fixtures/course-worker-process/worker-process.js';

/**
 * #37 / C37 — qualification du processus réel du service des cours.
 *
 * Chaque scénario lance `src/course-worker.ts` dans un processus Node distinct : le module exécute son propre
 * `run()` au chargement. Les tests existants appelaient `processPushBatch` directement ; ceux-ci exercent le
 * lancement, la boucle de 15 s, la reprise et la fermeture avec une vraie PostgreSQL 17 et des rôles synthétiques.
 *
 * Aucune connexion APNs : le sous-processus ne reçoit ni `APNS_KEY_ID`, ni `APNS_TEAM_ID`, ni `APNS_PRIVATE_KEY`.
 * Sans expéditeur, la file est avancée et les notifications préparées, jamais « envoyées ».
 * PostgreSQL tourne dans un conteneur jetable au digest déjà verrouillé, sur loopback et port libre ; il est
 * supprimé en fin de suite. Aucune base, aucun secret et aucun privilège de production n'est utilisé.
 */
const image = 'postgres:17-alpine@sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24';
const container = `drivy-c37-pg-${randomBytes(4).toString('hex')}`;
const postgresPassword = randomBytes(24).toString('hex');
const loginRole = 'drivy_c37_worker_login';
const loginPassword = randomBytes(24).toString('hex');
const forbiddenRole = 'drivy_c37_worker_bypassrls';
const forbiddenPassword = randomBytes(24).toString('hex');
const execFileAsync = promisify(execFile);

let port = 0, databaseUrl = '', workerUrl = '', forbiddenUrl = '';
let admin: Pool;
let app: Awaited<ReturnType<typeof harness>>['app'] | undefined;
let call: Call;
const children = new Set<WorkerHandle>();

const sleep = (milliseconds: number) => new Promise<void>(resolve => setTimeout(resolve, milliseconds));

async function freeLoopbackPort(): Promise<number> {
  return await new Promise<number>((resolve, reject) => {
    const server = createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const chosen = typeof address === 'object' && address ? address.port : 0;
      server.close(error => error ? reject(error) : resolve(chosen));
    });
  });
}

async function docker(...args: string[]): Promise<string> {
  const { stdout } = await execFileAsync('docker', args, { timeout: 60_000, windowsHide: true });
  return stdout.trim();
}

async function startContainer(): Promise<void> {
  port = await freeLoopbackPort();
  await docker('run', '-d', '--name', container, '-e', `POSTGRES_PASSWORD=${postgresPassword}`,
    '-e', 'POSTGRES_DB=drivy_test', '-p', `127.0.0.1:${port}:5432`, image);
  databaseUrl = `postgres://postgres:${postgresPassword}@127.0.0.1:${port}/drivy_test`;
  // L'entrée officielle démarre un serveur temporaire pendant l'initialisation, puis le remplace : `pg_isready` sur la
  // socket du conteneur répond déjà sur le temporaire, et une connexion TCP établie à ce moment est coupée au
  // redémarrage. On attend donc la SECONDE annonce « ready to accept connections » (serveur final), puis une requête
  // TCP réelle. Sans cette barrière, la recette échouait par « Connection terminated unexpectedly ».
  const deadline = Date.now() + 90_000;
  let lastError: unknown;
  while (Date.now() < deadline) {
    const logs = await execFileAsync('docker', ['logs', container], { timeout: 10_000, windowsHide: true })
      .then(({ stdout, stderr }) => `${stdout}\n${stderr}`).catch(() => '');
    if ((logs.match(/database system is ready to accept connections/g) ?? []).length >= 2) {
      const probe = new Pool({ connectionString: databaseUrl, max: 1, connectionTimeoutMillis: 5_000 });
      try { await probe.query('SELECT 1'); return; } catch (error) { lastError = error; } finally { await probe.end().catch(() => undefined); }
    }
    await sleep(250);
  }
  throw new Error(`PostgreSQL jetable non prêt en 90 s${lastError instanceof Error ? ` (${lastError.message})` : ''}`);
}

async function removeContainer(): Promise<void> {
  await docker('rm', '-f', container).catch(() => undefined);
}

function launch(url: string): WorkerHandle {
  const handle = startWorker(workerEnvironment(url));
  children.add(handle);
  void handle.exit().then(() => children.delete(handle));
  return handle;
}

async function stop(handle: WorkerHandle): Promise<void> {
  await handle.stop();
  children.delete(handle);
}

beforeAll(async () => {
  // Une autre version de Node changerait le runtime du service : refus explicite plutôt qu'une preuve décalée.
  if (Number(process.versions.node.split('.')[0]) !== 24) {
    throw new Error(`Node 24 requis pour qualifier le processus, runtime observé : ${process.versions.node}`);
  }
  try {
    await startContainer();
    process.env.TEST_DATABASE_URL = databaseUrl;
    admin = await freshDatabase();
    ({ call, app } = await harness(admin));
    await prepareSchool(admin);
    workerUrl = `postgres://${loginRole}:${loginPassword}@127.0.0.1:${port}/drivy_test`;
    forbiddenUrl = `postgres://${forbiddenRole}:${forbiddenPassword}@127.0.0.1:${port}/drivy_test`;
    // Deux lignes distinctes exigées par le service : le login et le rôle technique, tous deux sans superuser ni
    // BYPASSRLS. Le login n'hérite pas du rôle technique mais peut le prendre (SET ROLE), comme en exploitation.
    await admin.query(`CREATE ROLE ${loginRole} LOGIN PASSWORD '${loginPassword}' NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT`);
    await admin.query(`GRANT drivy_course_worker TO ${loginRole} WITH SET TRUE, INHERIT FALSE`);
    // Rôle volontairement interdit : même forme que le login, avec BYPASSRLS. Il ne sert qu'à ce refus synthétique.
    await admin.query(`CREATE ROLE ${forbiddenRole} LOGIN PASSWORD '${forbiddenPassword}' NOSUPERUSER BYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT`);
  } catch (error) {
    await Promise.allSettled([...children].map(handle => stop(handle)));
    await Promise.allSettled([app?.close(), admin?.end()]);
    await removeContainer();
    throw error;
  }
}, 180_000);

afterAll(async () => {
  await Promise.allSettled([...children].map(handle => stop(handle)));
  await Promise.allSettled([app?.close()]);
  if (admin) {
    for (const role of [loginRole, forbiddenRole]) {
      await admin.query('SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename=$1', [role]).catch(() => undefined);
      await admin.query(`DROP ROLE IF EXISTS ${role}`).catch(() => undefined);
    }
    await admin.end().catch(() => undefined);
  }
  await removeContainer();
}, 120_000);

const at = (offset: number, hourUtc: number) => { const date = new Date(); date.setUTCDate(date.getUTCDate() + offset); date.setUTCHours(hourUtc, 0, 0, 0); return date.toISOString(); };
let cursor = 10;

async function createType(title: string): Promise<string> {
  const response = await call('POST', '/course-types', { operationId: randomUUID(), title: `${title} ${randomUUID()}`, description: '' }, null, 'demo-admin');
  expect(response.statusCode, response.body).toBe(201);
  return response.json().data.id;
}

async function published(options: { typeId: string; title: string; capacity?: number }): Promise<{ id: string; version: number }> {
  const start = cursor += 4;
  const draft = await call('POST', '/course-series', { operationId: randomUUID(), typeId: options.typeId, title: options.title, description: '', location: 'Recette synthétique',
    conditions: '', teachingLanguage: null, responsibleMembershipId: id.adminMember, capacity: options.capacity ?? 5, minParticipants: null, timeZone: 'Europe/Zurich',
    occurrences: [{ startsAt: at(start, 8), endsAt: at(start, 11), instructorMembershipId: id.otherInstructorMember, attendanceRequired: true }] }, null, 'demo-admin');
  expect(draft.statusCode, draft.body).toBe(201);
  const response = await call('POST', `/course-series/${draft.json().data.id}/publish`, { operationId: randomUUID() }, draft.json().data.version, 'demo-admin');
  expect(response.statusCode, response.body).toBe(200);
  return response.json().data as { id: string; version: number };
}

async function follow(typeId: string): Promise<void> {
  const response = await call('PUT', `/v1/schools/${id.schoolA}/course-follows/me/${typeId}`, undefined, null, 'demo-alice');
  expect(response.statusCode, response.body).toBe(200);
}

type NotificationRow = { dedupe_key: string; category: string; status: string; sent_at: Date | null };
const notificationsOf = async (seriesId: string): Promise<NotificationRow[]> => (await admin.query<NotificationRow>(
  'SELECT dedupe_key,category,status,sent_at FROM drivy.push_notification WHERE series_id=$1 ORDER BY dedupe_key', [seriesId])).rows;
const offerRows = async (seriesId: string) => (await admin.query<{ id: string; status: string }>(
  'SELECT id,status FROM drivy.course_seat_offer WHERE series_id=$1', [seriesId])).rows;
const backendsOf = async (role: string): Promise<number> => (await admin.query<{ n: number }>(
  'SELECT count(*)::int AS n FROM pg_stat_activity WHERE usename=$1', [role])).rows[0]!.n;
const businessState = async () => ({
  notifications: (await admin.query<{ n: number }>('SELECT count(*)::int AS n FROM drivy.push_notification')).rows[0]!.n,
  offers: (await admin.query<{ n: number }>('SELECT count(*)::int AS n FROM drivy.course_seat_offer')).rows[0]!.n,
  undelivered: (await admin.query<{ n: number }>('SELECT count(*)::int AS n FROM drivy.course_event_outbox WHERE delivered_at IS NULL')).rows[0]!.n,
});

describe('#37 service des cours : lancement réel et refus fermé', () => {
  it('configuration absente : code non nul, message générique unique, aucune sortie standard', async () => {
    const environment = workerEnvironment(undefined);
    expect(Object.keys(environment).filter(name => name.startsWith('APNS_'))).toEqual([]);
    expect(environment.COURSE_WORKER_DATABASE_URL).toBeUndefined();
    const before = await businessState();
    const handle = startWorker(environment);
    children.add(handle);
    try {
      const result = await waitForExit(handle, 20_000);
      expect(result.code).toBe(1);
      expect(result.signal).toBeNull();
      expect(handle.stdout()).toBe('');
      const lines = handle.stderr().split('\n').filter(Boolean);
      expect(lines).toEqual(['Service des cours : démarrage impossible, vérifier configuration et droits.']);
    } finally { await stop(handle); }
    expect(await businessState()).toEqual(before);
  }, 40_000);

  it('rôle interdit (BYPASSRLS) : refus fermé, aucune opération métier, aucun contenu privé', async () => {
    const before = await businessState();
    const handle = launch(forbiddenUrl);
    try {
      const result = await waitForExit(handle, 20_000);
      expect(result.code).toBe(1);
      expect(result.signal).toBeNull();
      const stderr = handle.stderr();
      expect(stderr.trim()).toBe('Service des cours : démarrage impossible, vérifier configuration et droits.');
      expect(stderr).not.toContain(forbiddenPassword);
      expect(stderr).not.toContain('postgres://');
      expect(stderr).not.toContain('127.0.0.1');
      expect(handle.stdout()).toBe('');
    } finally { await stop(handle); }
    expect(await businessState()).toEqual(before);
    await waitFor('libération des connexions du rôle interdit', 5_000, async () => await backendsOf(forbiddenRole) === 0);
  }, 40_000);
});

describe('#37 service des cours : boucle vivante sans APNs', () => {
  it('rôle autorisé : un processus vivant expire une proposition échue et prépare ses notifications sans rien envoyer', async () => {
    const typeId = await createType('Cours C37');
    const series = await published({ typeId, title: 'Cours C37 offre', capacity: 1 });
    const holder = (await call('POST', `/course-series/${series.id}/enroll`, { operationId: randomUUID() }, null, 'demo-alice')).json().data.me.enrollment;
    expect((await call('POST', `/course-series/${series.id}/waitlist`, { operationId: randomUUID() }, null, 'demo-bob')).statusCode).toBe(201);
    const cancelled = await call('POST', `/course-enrollments/${holder.id}/cancel`, { operationId: randomUUID() }, holder.version, 'demo-alice');
    expect(cancelled.statusCode, cancelled.body).toBe(200);
    // Avant tout processus, l'outbox n'a rien produit : c'est bien la boucle réelle qui prépare la file.
    expect(await notificationsOf(series.id)).toEqual([]);

    const handle = launch(workerUrl);
    try {
      const pending = await waitFor('notification OFFER préparée par le processus', 30_000,
        async () => (await notificationsOf(series.id)).find(row => row.category === 'OFFER' && row.status === 'PENDING') ?? false);
      expect(pending.sent_at).toBeNull();
      expect(handle.alive()).toBe(true);
      expect(handle.stdout()).toBe('');

      // Échéance dépassée écrite en SQL : l'expiration doit venir du passage suivant du processus, sans action d'utilisateur.
      await admin.query("UPDATE drivy.course_seat_offer SET offered_at=now()-interval '13 hours',expires_at=now()-interval '1 minute' WHERE series_id=$1 AND status='ACTIVE'", [series.id]);
      await waitFor('proposition expirée par le service', 40_000,
        async () => (await offerRows(series.id)).some(row => row.status === 'EXPIRED'));

      const rows = await notificationsOf(series.id);
      const offers = rows.filter(row => row.category === 'OFFER');
      expect(offers).toHaveLength(1);
      expect(offers.every(row => row.status === 'EXPIRED')).toBe(true);
      expect(offers.every(row => row.sent_at === null)).toBe(true);
      // Aucun expéditeur configuré : rien ne peut être SENT, et aucune livraison n'est revendiquée.
      expect(rows.some(row => row.status === 'SENT')).toBe(false);
      expect(handle.alive()).toBe(true);
    } finally { await stop(handle); }
  }, 90_000);

  it('plusieurs passages puis relance : aucun doublon d’offre ni de notification, état conservé', async () => {
    const typeId = await createType('Cours C37 boucle');
    await follow(typeId);
    const offerTypeId = await createType('Cours C37 offre stable');
    const offerSeries = await published({ typeId: offerTypeId, title: 'Cours C37 offre stable', capacity: 1 });
    const holder = (await call('POST', `/course-series/${offerSeries.id}/enroll`, { operationId: randomUUID() }, null, 'demo-alice')).json().data.me.enrollment;
    expect((await call('POST', `/course-series/${offerSeries.id}/waitlist`, { operationId: randomUUID() }, null, 'demo-bob')).statusCode).toBe(201);
    expect((await call('POST', `/course-enrollments/${holder.id}/cancel`, { operationId: randomUUID() }, holder.version, 'demo-alice')).statusCode).toBe(200);

    let a: { id: string } | undefined, b: { id: string } | undefined;
    const first = launch(workerUrl);
    try {
      a = await published({ typeId, title: 'Cours C37 boucle A' });
      await waitFor('annonce de la première session', 40_000, async () => (await notificationsOf(a!.id)).length === 1);
      b = await published({ typeId, title: 'Cours C37 boucle B' });
      // Observer B prouve un second passage de boucle, sans utiliser un délai fixe comme preuve.
      await waitFor('annonce de la seconde session (deuxième passage)', 45_000, async () => (await notificationsOf(b!.id)).length === 1);
      expect((await notificationsOf(offerSeries.id)).filter(row => row.category === 'OFFER')).toHaveLength(1);
      expect((await offerRows(offerSeries.id)).filter(row => row.status === 'ACTIVE')).toHaveLength(1);
    } finally { await stop(first); }

    expect(a).toBeDefined(); expect(b).toBeDefined();
    const beforeRestart = { a: await notificationsOf(a!.id), b: await notificationsOf(b!.id), offer: await notificationsOf(offerSeries.id) };
    const second = launch(workerUrl);
    try {
      const c = await published({ typeId, title: 'Cours C37 boucle C' });
      await waitFor('annonce de la troisième session après relance', 45_000, async () => (await notificationsOf(c.id)).length === 1);
      const afterRestart = { a: await notificationsOf(a!.id), b: await notificationsOf(b!.id), offer: await notificationsOf(offerSeries.id) };
      expect(afterRestart).toEqual(beforeRestart);
      expect(afterRestart.a).toHaveLength(1);
      expect(afterRestart.b).toHaveLength(1);
      expect(afterRestart.offer.filter(row => row.category === 'OFFER')).toHaveLength(1);
      expect([...afterRestart.a, ...afterRestart.b, ...afterRestart.offer].some(row => row.status === 'SENT')).toBe(false);
      expect((await offerRows(offerSeries.id)).filter(row => row.status === 'ACTIVE')).toHaveLength(1);
      expect((await businessState()).undelivered).toBe(0);
      expect(second.alive()).toBe(true);
    } finally { await stop(second); }
  }, 180_000);

  it('perte de connexion PostgreSQL contrôlée : diagnostic générique, processus vivant, reprise sans contenu sensible', async () => {
    const typeId = await createType('Cours C37 panne');
    await follow(typeId);
    const handle = launch(workerUrl);
    try {
      const a = await published({ typeId, title: 'Cours C37 panne A' });
      await waitFor('première annonce avant la panne', 40_000, async () => (await notificationsOf(a.id)).length === 1);
      const terminated = await admin.query<{ n: number }>(
        'SELECT count(*)::int AS n FROM (SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename=$1 AND pid<>pg_backend_pid()) gone', [loginRole]);
      expect(terminated.rows[0]!.n).toBeGreaterThan(0);
      await waitFor('diagnostic générique après la coupure', 20_000, async () => handle.stderr().length > 0);
      expect(handle.stderr()).toMatch(/Service des cours : traitement temporairement indisponible\.|Connexion inactive perdue \([A-Za-z]+\)\./);
      expect(handle.alive()).toBe(true);

      // La reprise se prouve par une nouvelle annonce traitée par un passage ultérieur, pas par un délai.
      const b = await published({ typeId, title: 'Cours C37 panne B' });
      await waitFor('reprise du traitement après la coupure', 60_000, async () => (await notificationsOf(b.id)).length === 1);
      expect(await notificationsOf(a.id)).toHaveLength(1);

      const stderr = handle.stderr();
      for (const line of stderr.split('\n').filter(Boolean)) {
        expect(line).toMatch(/^(Service des cours : traitement temporairement indisponible\.|Connexion inactive perdue \([A-Za-z]+\)\.)$/);
      }
      for (const secret of [loginPassword, 'postgres://', '127.0.0.1', 'Cours C37 panne']) expect(stderr).not.toContain(secret);
      expect(stderr).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}/);
      expect(handle.stdout()).toBe('');
      expect(handle.alive()).toBe(true);
    } finally { await stop(handle); }
  }, 150_000);
});

describe('#37 service des cours : fermeture bornée (contrat systemd existant)', () => {
  it('la borne d’arrêt lue est celle du service livré (TimeoutStopSec=30)', async () => {
    const unit = await readFile(new URL('../../../infra/deploy/drivy-refonte-course-worker.service', import.meta.url), 'utf8');
    const seconds = Number(/^TimeoutStopSec=(\d+)$/m.exec(unit)?.[1]);
    expect(seconds).toBe(30);
  });

  // Windows ne livre pas SIGTERM à un processus : `child.kill()` y est une terminaison forcée. Ce scénario n'est donc
  // exécutable que sur POSIX ; il est préparé tel quel pour le runner Linux et n'est jamais simulé par process.emit.
  it.skipIf(!posix)('SIGTERM pendant l’attente : sortie gracieuse sous la borne, connexions et verrous libérés', async () => {
    const unit = await readFile(new URL('../../../infra/deploy/drivy-refonte-course-worker.service', import.meta.url), 'utf8');
    const boundMs = Number(/^TimeoutStopSec=(\d+)$/m.exec(unit)?.[1]) * 1_000;
    const typeId = await createType('Cours C37 arrêt');
    await follow(typeId);
    const handle = launch(workerUrl);
    try {
      const series = await published({ typeId, title: 'Cours C37 arrêt' });
      await waitFor('première annonce avant l’arrêt', 40_000, async () => (await notificationsOf(series.id)).length === 1);
      // À cet instant la boucle attend entre deux passages : aucune transaction ouverte à interrompre.
      expect((await admin.query<{ n: number }>("SELECT count(*)::int AS n FROM pg_stat_activity WHERE usename=$1 AND state='idle in transaction'", [loginRole])).rows[0]!.n).toBe(0);
      const startedAt = Date.now();
      const result = await handle.stop(boundMs);
      const elapsed = Date.now() - startedAt;
      expect(result.forced).toBe(false);
      expect(result.code).toBe(0);
      expect(result.signal).toBeNull();
      expect(elapsed).toBeLessThan(boundMs);
      await waitFor('connexions PostgreSQL libérées', 5_000, async () => await backendsOf(loginRole) === 0);
      const locks = (await admin.query<{ n: number }>(
        'SELECT count(*)::int AS n FROM pg_locks l JOIN pg_stat_activity a ON a.pid=l.pid WHERE a.usename=$1', [loginRole])).rows[0]!.n;
      expect(locks).toBe(0);
      expect(await notificationsOf(series.id)).toHaveLength(1);
      expect((await businessState()).undelivered).toBe(0);
    } finally { await stop(handle); }
  }, 90_000);
});
