import { randomUUID } from 'node:crypto';
import { setTimeout as sleep } from 'node:timers/promises';
import { afterAll, beforeAll, beforeEach, expect, test } from 'vitest';
import { Pool } from 'pg';
import { buildApp } from '../src/app.js';
import { AttemptLimiter } from '../src/attempt-limiter.js';
import type { Identity } from '../src/auth.js';
import { ApiError } from '../src/errors.js';
import { platformCommand } from '../src/platform-command.js';
import { bootstrapPlatformOperators, readBootstrapEntries } from '../src/platform-bootstrap.js';
import { generatePlatformCode, platformCodeHasher } from '../src/platform-model.js';
import { fixtureIds } from '../scripts/fixtures.js';
import { freshDatabase, issuer, seedPlatformOperator } from './support/harness.js';

/**
 * R01-T01 (#453) sur PostgreSQL réelle : porte relue en base, invitations, dernier opérateur sous concurrence,
 * versions, reçus durables et journal commercial. Jeu d'essai synthétique ; aucune identité ni adresse réelle.
 * Jeton de recette : `sujet`, `sujet|adresse` (vérifiée), `sujet|~adresse` (non vérifiée), `sujet|adresse|Nom`.
 */
let pool: Pool, owner: Pool, app: ReturnType<typeof buildApp>;
const cursorSecret = 'platform-synthetic-test-secret-32-characters';
const hashOf = platformCodeHasher(cursorSecret);
const verifyToken = async (header: string | undefined): Promise<Identity> => {
  if (!header?.startsWith('Bearer ')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  const [subject, rawEmail, name] = header.slice(7).split('|');
  const verified = rawEmail && !rawEmail.startsWith('~') ? rawEmail : undefined;
  return { issuer, subject: subject!, ...(verified ? { verifiedEmail: verified } : {}), ...(name ? { displayName: name } : {}) };
};
const A = 'op-a', B = 'op-b';
const emailA = 'camille@example.invalid';

beforeAll(async () => {
  pool = await freshDatabase();
  owner = new Pool({ connectionString: process.env.TEST_DATABASE_URL, options: '-c role=drivy_harness_migrator' });
  app = buildApp({ pool, verifyToken, cursorSecret });
});
beforeEach(async () => {
  await pool.query('TRUNCATE drivy.platform_audit_event, drivy.platform_operation, drivy.platform_operator_invitation, drivy.platform_client, drivy.school_opening_link, drivy.platform_operator');
  await seedPlatformOperator(pool, A, { displayName: 'Camille Exemple', email: emailA });
  await seedPlatformOperator(pool, B, { displayName: 'Jean Exemple' });
});
afterAll(async () => { await app?.close(); await owner?.end(); await pool?.end(); });

interface Options { body?: Record<string, unknown>; version?: number | null; key?: boolean; headers?: Record<string, string>; target?: ReturnType<typeof buildApp> }
const api = (subject: string, method: 'GET' | 'POST', url: string, options: Options = {}) => (options.target ?? app).inject({
  method, url, headers: {
    authorization: `Bearer ${subject}`,
    ...(options.body?.operationId && options.key !== false ? { 'idempotency-key': String(options.body.operationId) } : {}),
    ...(options.version ? { 'if-match': `"${options.version}"` } : {}), ...options.headers,
  },
  ...(options.body ? { payload: options.body } : {}),
});
const idOf = async (subject: string) => (await pool.query<{ id: string }>("SELECT id FROM drivy.platform_operator WHERE subject=$1 AND status='ACTIVE'", [subject])).rows[0]!.id;
const versionOf = async (operatorId: string) => (await pool.query<{ version: number }>('SELECT version FROM drivy.platform_operator WHERE id=$1', [operatorId])).rows[0]!.version;
const activeCount = async () => Number((await pool.query<{ n: string }>("SELECT count(*) AS n FROM drivy.platform_operator WHERE status='ACTIVE'")).rows[0]!.n);
const journal = async (where = 'true') => (await pool.query(`SELECT * FROM drivy.platform_audit_event WHERE ${where} ORDER BY occurred_at,id`)).rows;
const invite = async (as: string, email: string, extra: Record<string, unknown> = {}) => {
  const code = generatePlatformCode(), body = { operationId: randomUUID(), code, email, ...extra };
  const response = await api(as, 'POST', '/v1/platform/invitations', { body });
  return { code, body, response, data: response.statusCode === 201 ? response.json().data : undefined };
};
const accept = (as: string, code: string, operationId = randomUUID()) => api(as, 'POST', '/v1/platform/invitations/accept', { body: { operationId, code } });
const preview = (as: string, code: string) => api(as, 'POST', '/v1/platform/invitations/preview', { body: { code } });
const revokeOperator = (as: string, targetId: string, version: number, operationId = randomUUID()) =>
  api(as, 'POST', `/v1/platform/operators/${targetId}/revoke`, { body: { operationId }, version });

/** Requête sous le rôle applicatif, avec l'identité donnée : ce que la base laisse voir ou faire, quel que soit le service. */
async function asApp(subject: string, sql: string, params: unknown[] = [], context: { email?: string; hash?: string } = {}) {
  const db = await pool.connect();
  try {
    await db.query('BEGIN'); await db.query('SET LOCAL ROLE drivy_app');
    await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.verified_email',$3,true),set_config('app.platform_invitation_hash',$4,true)",
      [issuer, subject, context.email ?? '', context.hash ?? '']);
    const result = await db.query(sql, params);
    return { rows: result.rows as Array<Record<string, unknown>>, rowCount: result.rowCount ?? 0, error: undefined as (Error & { code?: string }) | undefined };
  } catch (error) { return { rows: [], rowCount: 0, error: error as Error & { code?: string } }; }
  finally { await db.query('ROLLBACK').catch(() => undefined); db.release(); }
}

test('la porte : seul un opérateur actif relu en base entre, tout autre compte reçoit 403 sans rien écrire', async () => {
  // Un ancien opérateur : son appartenance existe encore, révoquée.
  await seedPlatformOperator(pool, 'op-former');
  const former = await idOf('op-former');
  await pool.query("UPDATE drivy.platform_operator SET status='REVOKED',revoked_at=now(),revoked_by=$1 WHERE id=$2", [await idOf(A), former]);
  const someId = randomUUID();
  const routes: Array<[string, 'GET' | 'POST', string, Options]> = [
    ['me', 'GET', '/v1/platform/me', {}], ['équipe', 'GET', '/v1/platform/operators', {}], ['invitations', 'GET', '/v1/platform/invitations', {}],
    ['journal', 'GET', '/v1/platform/journal', {}], ['reçu', 'GET', `/v1/platform/operations/${someId}`, {}],
    ['inviter', 'POST', '/v1/platform/invitations', { body: { operationId: randomUUID(), code: generatePlatformCode(), email: 'x@example.invalid' } }],
    ['révoquer une invitation', 'POST', `/v1/platform/invitations/${someId}/revoke`, { body: { operationId: randomUUID() }, version: 1 }],
    ['retirer un opérateur', 'POST', `/v1/platform/operators/${someId}/revoke`, { body: { operationId: randomUUID() }, version: 1 }],
  ];
  for (const subject of ['demo-admin', 'demo-instructor', 'demo-alice', 'stranger', 'op-former']) {
    for (const [label, method, url, options] of routes) {
      const response = await api(subject, method, url, options);
      expect(response.statusCode, `${subject} ${label}`).toBe(403);
      expect(response.json().code, `${subject} ${label}`).toBe('PLATFORM_OPERATOR_REQUIRED');
    }
  }
  for (const [label, method, url, options] of routes) {
    const anonymous = await app.inject({ method, url, ...(options.body ? { payload: options.body } : {}) });
    expect(anonymous.statusCode, label).toBe(401);
  }
  // Rien n'a été écrit par ces refus : ni reçu, ni invitation, ni ligne de journal.
  for (const table of ['platform_operation', 'platform_operator_invitation', 'platform_audit_event'])
    expect((await pool.query(`SELECT 1 FROM drivy.${table}`)).rowCount, table).toBe(0);
  const me = await api(A, 'GET', '/v1/platform/me');
  expect(me.statusCode).toBe(200);
  expect(me.json().data).toMatchObject({ level: 'COMMERCIAL', rights: ['MANAGE_PLATFORM_TEAM', 'MANAGE_SCHOOL_OPENINGS', 'READ_COMMERCIAL_JOURNAL'],
    notGranted: ['SCHOOL_RECORDS', 'TRIPS', 'MESSAGES', 'SCHOOL_ROLES'], operator: { displayName: 'Camille Exemple', self: true, maskedEmail: 'c***@example.invalid', status: 'ACTIVE' } });
});

test('les cinq tables de la plateforme sont sous RLS forcée, comme toute table du schéma', async () => {
  // Les tests de capture ne rejouent que les migrations numérotées : ce contrôle couvre la migration datée de la plateforme.
  const rls = await pool.query<{ relname: string; relrowsecurity: boolean; relforcerowsecurity: boolean }>(
    "SELECT c.relname::text AS relname,relrowsecurity,relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND relkind='r' AND c.relname LIKE 'platform\\_%' ORDER BY 1");
  expect(rls.rows.map(row => row.relname)).toEqual(['platform_audit_event', 'platform_client', 'platform_operation', 'platform_operator', 'platform_operator_invitation']);
  for (const row of rls.rows) expect([row.relrowsecurity, row.relforcerowsecurity], row.relname).toEqual([true, true]);
  const unforced = await pool.query("SELECT c.relname::text AS relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND relkind='r' AND NOT (relrowsecurity AND relforcerowsecurity)");
  expect(unforced.rows).toEqual([]);
});

test('l’opérateur ne voit des tables scolaires que ce qu’en voit un inconnu, et ne s’ajoute pas lui-même', async () => {
  const tables = (await pool.query<{ relname: string }>(`SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='drivy' AND c.relkind IN('r','p') AND c.relname NOT LIKE 'platform\\_%' ORDER BY 1`)).rows.map(row => row.relname);
  expect(tables.length).toBeGreaterThan(30);
  const view = async (subject: string, table: string) => { const result = await asApp(subject, `SELECT count(*)::int AS n FROM drivy."${table}"`); return result.error ? `refusé:${result.error.code}` : String(result.rows[0]!.n); };
  const differences: string[] = [];
  for (const table of tables) {
    const [operator, stranger] = [await view(A, table), await view('stranger', table)];
    if (operator !== stranger) differences.push(`${table}: opérateur=${operator} inconnu=${stranger}`);
  }
  expect(differences).toEqual([]);
  // Les tables sensibles, nommément : rien de lisible, quelle que soit la manière dont la base les protège.
  for (const table of ['person', 'identity_link', 'school']) {
    const result = await asApp(A, `SELECT count(*)::int AS n FROM drivy."${table}"`);
    expect(result.error ? 0 : result.rows[0]!.n, table).toBe(0);
  }
  // Un compte scolaire (ADMIN) ne lit ni l'équipe, ni les invitations, ni le journal, ni les reçus.
  for (const table of ['platform_operator', 'platform_operator_invitation', 'platform_audit_event', 'platform_operation', 'platform_client']) {
    expect((await asApp('demo-admin', `SELECT 1 FROM drivy.${table}`)).rowCount, table).toBe(0);
    expect((await asApp('stranger', `SELECT 1 FROM drivy.${table}`)).rowCount, table).toBe(0);
    expect((await asApp(A, `SELECT 1 FROM drivy.${table}`)).error, table).toBeUndefined();
  }
  const insert = "INSERT INTO drivy.platform_operator(id,issuer,subject,display_name,added_via) VALUES(gen_random_uuid(),$1,'self-added','Soi-même','BOOTSTRAP')";
  for (const subject of ['demo-admin', 'stranger', A]) expect((await asApp(subject, insert, [issuer])).error?.code, subject).toBe('42501');
  // Un opérateur ne modifie ni le nom, ni l'identité d'un collègue, et ne supprime personne.
  expect((await asApp(A, "UPDATE drivy.platform_operator SET display_name='autre'")).error?.code).toBe('42501');
  expect((await asApp(A, 'DELETE FROM drivy.platform_operator')).error?.code).toBe('42501');
  expect(await activeCount()).toBe(2);
});

test('invitation : création idempotente, droits et adresse masquée, code jamais conservé, journal sans secret', async () => {
  const { code, body, response, data } = await invite(A, 'Invitee@Example.invalid', { validityDays: 3 });
  expect(response.statusCode, response.body).toBe(201);
  expect(data).toMatchObject({ status: 'AVAILABLE', level: 'COMMERCIAL', maskedEmail: 'i***@example.invalid', createdByName: 'Camille Exemple', version: 1 });
  expect(Math.round((Date.parse(data.expiresAt) - Date.parse(data.createdAt)) / 86_400_000)).toBe(3);
  const row = (await pool.query('SELECT * FROM drivy.platform_operator_invitation')).rows[0];
  expect(row.code_hash).toBe(hashOf(code));
  expect(row.invitee_email).toBe('invitee@example.invalid');
  expect(JSON.stringify(row).includes(code)).toBe(false);
  // Rejeu à l'identique : même invitation, une seule ligne de journal ; autre contenu avec la même clé : refusé.
  const again = await api(A, 'POST', '/v1/platform/invitations', { body });
  expect(again.statusCode).toBe(201); expect(again.json().data.id).toBe(data.id);
  expect((await pool.query('SELECT 1 FROM drivy.platform_operator_invitation')).rowCount).toBe(1);
  const mismatch = await api(A, 'POST', '/v1/platform/invitations', { body: { ...body, email: 'autre@example.invalid' } });
  expect(mismatch.statusCode).toBe(409); expect(mismatch.json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await api(A, 'POST', '/v1/platform/invitations', { body, key: false })).statusCode).toBe(400);
  // Reçu durable : relisible par son auteur seulement, sans le code.
  const receipt = await api(A, 'GET', `/v1/platform/operations/${body.operationId}`);
  expect(receipt.statusCode).toBe(200);
  expect(receipt.json().data).toMatchObject({ operationId: body.operationId, kind: 'CREATE_PLATFORM_INVITATION', statusCode: 201 });
  expect(JSON.stringify(receipt.json()).includes(code)).toBe(false);
  expect((await api(B, 'GET', `/v1/platform/operations/${body.operationId}`)).statusCode).toBe(404);
  const entries = await journal("action='CREATE_PLATFORM_INVITATION'");
  expect(entries).toHaveLength(1);
  expect(entries[0]).toMatchObject({ actor_kind: 'OPERATOR', actor_name: 'Camille Exemple', result: 'SUCCESS', subject_type: 'PlatformInvitation', subject_id: data.id, school_id: null });
  expect(entries[0].changes).toMatchObject({ level: 'COMMERCIAL', maskedEmail: 'i***@example.invalid' });
  expect(JSON.stringify(entries).includes(code) || JSON.stringify(entries).includes('invitee@example.invalid')).toBe(false);
  // Les deux invitations ne se mélangent pas : une adresse déjà membre, une invitation en attente, un code déjà attribué.
  const member = await invite(B, emailA);
  expect(member.response.statusCode).toBe(409); expect(member.response.json().code).toBe('PLATFORM_OPERATOR_EXISTS');
  const pending = await invite(B, 'invitee@example.invalid');
  expect(pending.response.statusCode).toBe(409); expect(pending.response.json().code).toBe('PLATFORM_INVITATION_PENDING');
  const taken = await api(B, 'POST', '/v1/platform/invitations', { body: { operationId: randomUUID(), code, email: 'quelquun@example.invalid' } });
  expect(taken.statusCode).toBe(409); expect(taken.json().code).toBe('PLATFORM_CODE_TAKEN');
  const refused = await journal("result='REFUSED'");
  expect(refused.map(entry => entry.reason_code).sort()).toEqual(['PLATFORM_CODE_TAKEN', 'PLATFORM_INVITATION_PENDING', 'PLATFORM_OPERATOR_EXISTS']);
  const listed = await api(B, 'GET', '/v1/platform/invitations');
  expect(listed.json().data.items).toHaveLength(1);
});

test('aperçu puis acceptation : aucun privilège avant l’acceptation confirmée par le serveur', async () => {
  const { code, data } = await invite(A, 'newcomer@example.invalid');
  const asNewcomer = 'newcomer|newcomer@example.invalid|Jean Nouveau';
  const before = await api('newcomer', 'GET', '/v1/platform/me');
  expect(before.statusCode).toBe(403);
  // Les droits sont montrés avant l'acceptation, avec ce qui n'est jamais accordé et l'adresse masquée.
  const shown = await preview(asNewcomer, code);
  expect(shown.statusCode, shown.body).toBe(200);
  expect(shown.json().data).toMatchObject({ status: 'AVAILABLE', level: 'COMMERCIAL', maskedEmail: 'n***@example.invalid', matchesAccount: true, alreadyMember: false,
    rights: ['MANAGE_PLATFORM_TEAM', 'MANAGE_SCHOOL_OPENINGS', 'READ_COMMERCIAL_JOURNAL'], notGranted: ['SCHOOL_RECORDS', 'TRIPS', 'MESSAGES', 'SCHOOL_ROLES'] });
  expect(JSON.stringify(shown.json()).includes('newcomer@example.invalid')).toBe(false);
  expect((await preview('newcomer|autre@example.invalid', code)).json().data.matchesAccount).toBe(false);
  expect((await preview('newcomer', code)).json().data.matchesAccount).toBe(false);
  expect((await preview(A + '|' + emailA, code)).json().data.alreadyMember).toBe(true);
  // L'aperçu ne consomme rien et n'ouvre aucun droit.
  expect(await activeCount()).toBe(2);
  expect((await api('newcomer', 'GET', '/v1/platform/me')).statusCode).toBe(403);
  expect((await pool.query('SELECT status FROM drivy.platform_operator_invitation WHERE id=$1', [data.id])).rows[0].status).toBe('AVAILABLE');
  // Un code inconnu ou d’un autre format n’est jamais résolu à la place d’un code de plateforme.
  const unknown = await preview(asNewcomer, generatePlatformCode());
  expect(unknown.statusCode).toBe(404); expect(unknown.json().code).toBe('PLATFORM_INVITATION_INVALID');
  expect((await preview(asNewcomer, 'ABCD-EFGH')).statusCode).toBe(400);
  const openingToken = 'x'.repeat(43);
  expect((await api('demo-admin', 'POST', '/v1/school-openings/preview', { body: { token: code } })).statusCode).not.toBe(200);
  expect((await preview(asNewcomer, openingToken)).statusCode).toBe(400);

  const operationId = randomUUID();
  const accepted = await accept(asNewcomer, code, operationId);
  expect(accepted.statusCode, accepted.body).toBe(201);
  expect(accepted.json().data).toMatchObject({ level: 'COMMERCIAL', operator: { displayName: 'Jean Nouveau', status: 'ACTIVE', addedVia: 'INVITATION', self: true } });
  expect(await activeCount()).toBe(3);
  expect((await api('newcomer', 'GET', '/v1/platform/me')).statusCode).toBe(200);
  const used = (await pool.query('SELECT status,used_at,used_by,version FROM drivy.platform_operator_invitation WHERE id=$1', [data.id])).rows[0];
  expect(used.status).toBe('USED'); expect(used.used_by).toBe(accepted.json().data.operator.id); expect(used.used_at).toBeTruthy(); expect(used.version).toBe(2);
  const entry = (await journal("action='ACCEPT_PLATFORM_INVITATION'"));
  expect(entry).toHaveLength(1);
  expect(entry[0]).toMatchObject({ actor_name: 'Jean Nouveau', result: 'SUCCESS', operation_id: operationId, subject_id: accepted.json().data.operator.id });
  expect(JSON.stringify(entry).includes(code)).toBe(false);

  // Réponse perdue : le rejeu rend le même résultat sans doubler l'appartenance ni le journal ; un autre code avec la même clé est refusé.
  const replay = await accept(asNewcomer, code, operationId);
  expect(replay.statusCode).toBe(201); expect(replay.json().data.operator.id).toBe(accepted.json().data.operator.id);
  expect(await activeCount()).toBe(3);
  expect(await journal("action='ACCEPT_PLATFORM_INVITATION'")).toHaveLength(1);
  const otherCode = await accept(asNewcomer, generatePlatformCode(), operationId);
  expect(otherCode.statusCode).toBe(409); expect(otherCode.json().code).toBe('IDEMPOTENCY_MISMATCH');
  // Déjà membre, et code déjà consommé pour un autre compte.
  const member = await accept(asNewcomer, code);
  expect(member.statusCode).toBe(409); expect(member.json().code).toBe('PLATFORM_ALREADY_MEMBER');
  const consumed = await accept('late|newcomer@example.invalid', code);
  expect(consumed.statusCode).toBe(409); expect(consumed.json().code).toBe('PLATFORM_INVITATION_USED');
  expect((await preview('late|newcomer@example.invalid', code)).json().code).toBe('PLATFORM_INVITATION_USED');
  const revokeUsed = await api(A, 'POST', `/v1/platform/invitations/${data.id}/revoke`, { body: { operationId: randomUUID() }, version: 2 });
  expect(revokeUsed.statusCode).toBe(409); expect(revokeUsed.json().code).toBe('PLATFORM_INVITATION_USED');
});

test('acceptation refusée : mauvaise adresse, adresse non vérifiée, expiration, révocation, déjà membre', async () => {
  const { code, data } = await invite(A, 'target@example.invalid');
  const wrong = await accept('someone|other@example.invalid', code);
  expect(wrong.statusCode).toBe(403); expect(wrong.json().code).toBe('PLATFORM_INVITATION_EMAIL_MISMATCH');
  const unverified = await accept('someone|~target@example.invalid', code);
  expect(unverified.statusCode).toBe(403); expect(unverified.json().code).toBe('EMAIL_VERIFICATION_REQUIRED');
  expect((await accept('someone', code)).json().code).toBe('EMAIL_VERIFICATION_REQUIRED');
  expect(await activeCount()).toBe(2);
  // Un membre qui tenterait d'accepter une invitation à son adresse reste un seul opérateur.
  const own = await invite(A, 'jean@example.invalid');
  const already = await accept(B + '|jean@example.invalid', own.code);
  expect(already.statusCode).toBe(409); expect(already.json().code).toBe('PLATFORM_ALREADY_MEMBER');
  // Expirée : insérée avec des dates passées (la base refuse de modifier une invitation existante).
  const expiredCode = generatePlatformCode();
  await pool.query(`INSERT INTO drivy.platform_operator_invitation(id,code_hash,invitee_email,created_by,created_at,expires_at)
    VALUES($1,$2,'late@example.invalid',$3,now()-interval '10 days',now()-interval '1 day')`, [randomUUID(), hashOf(expiredCode), await idOf(A)]);
  const expired = await accept('late|late@example.invalid', expiredCode);
  expect(expired.statusCode).toBe(410); expect(expired.json().code).toBe('PLATFORM_INVITATION_EXPIRED');
  expect((await preview('late|late@example.invalid', expiredCode)).json().code).toBe('PLATFORM_INVITATION_EXPIRED');
  const listed = (await api(A, 'GET', '/v1/platform/invitations')).json().data.items as Array<{ status: string; maskedEmail: string }>;
  expect(listed.find(item => item.maskedEmail === 'l***@example.invalid')?.status).toBe('EXPIRED');
  // Révoquée : plus utilisable, version vérifiée, rejeu possible, double révocation refusée.
  const stale = await api(A, 'POST', `/v1/platform/invitations/${data.id}/revoke`, { body: { operationId: randomUUID() }, version: 5 });
  expect(stale.statusCode).toBe(412); expect(stale.json().code).toBe('VERSION_CONFLICT');
  expect((await api(A, 'POST', `/v1/platform/invitations/${data.id}/revoke`, { body: { operationId: randomUUID() } })).statusCode).toBe(428);
  const revokeId = randomUUID();
  const revoked = await api(A, 'POST', `/v1/platform/invitations/${data.id}/revoke`, { body: { operationId: revokeId }, version: 1 });
  expect(revoked.statusCode, revoked.body).toBe(200);
  expect(revoked.json().data).toMatchObject({ status: 'REVOKED', version: 2 });
  expect((await api(A, 'POST', `/v1/platform/invitations/${data.id}/revoke`, { body: { operationId: revokeId }, version: 1 })).json().data.status).toBe('REVOKED');
  const twice = await api(A, 'POST', `/v1/platform/invitations/${data.id}/revoke`, { body: { operationId: randomUUID() }, version: 2 });
  expect(twice.statusCode).toBe(409); expect(twice.json().code).toBe('PLATFORM_INVITATION_REVOKED');
  const gone = await accept('target|target@example.invalid', code);
  expect(gone.statusCode).toBe(410); expect(gone.json().code).toBe('PLATFORM_INVITATION_REVOKED');
  expect((await preview('target|target@example.invalid', code)).statusCode).toBe(410);
  expect(await activeCount()).toBe(2);
  expect((await api('target', 'GET', '/v1/platform/me')).statusCode).toBe(403);
  expect(await journal("action='REVOKE_PLATFORM_INVITATION' AND result='SUCCESS'")).toHaveLength(1);
  expect((await journal("action='REVOKE_PLATFORM_INVITATION' AND result='REFUSED'")).map(entry => entry.reason_code).sort()).toEqual(['PLATFORM_INVITATION_REVOKED', 'VERSION_CONFLICT']);
});

test('deux comptes visant la même invitation en même temps : un seul devient opérateur', async () => {
  const { code } = await invite(A, 'shared@example.invalid');
  const [first, second] = await Promise.all([accept('twin-1|shared@example.invalid', code), accept('twin-2|shared@example.invalid', code)]);
  expect([first.statusCode, second.statusCode].sort()).toEqual([201, 409]);
  expect(await activeCount()).toBe(3);
  expect((await pool.query("SELECT 1 FROM drivy.platform_operator WHERE added_via='INVITATION'")).rowCount).toBe(1);
  expect((await pool.query("SELECT 1 FROM drivy.platform_operator_invitation WHERE status='USED'")).rowCount).toBe(1);
});

test('acceptation et révocation simultanées d’une même invitation : une seule issue, jamais d’accès accordé à une invitation révoquée', async () => {
  for (let round = 0; round < 4; round += 1) {
    const email = `race${round}@example.invalid`;
    const { code, data } = await invite(A, email);
    const [accepted, revoked] = await Promise.all([accept(`racer${round}|${email}`, code), api(A, 'POST', `/v1/platform/invitations/${data.id}/revoke`, { body: { operationId: randomUUID() }, version: 1 })]);
    const status = (await pool.query('SELECT status FROM drivy.platform_operator_invitation WHERE id=$1', [data.id])).rows[0].status;
    const member = (await pool.query("SELECT 1 FROM drivy.platform_operator WHERE subject=$1 AND status='ACTIVE'", [`racer${round}`])).rowCount;
    if (accepted.statusCode === 201) { expect(status, accepted.body + revoked.body).toBe('USED'); expect(member).toBe(1); expect([409, 412]).toContain(revoked.statusCode); }
    else { expect(status, accepted.body + revoked.body).toBe('REVOKED'); expect(member).toBe(0); expect(revoked.statusCode).toBe(200); expect([409, 410]).toContain(accepted.statusCode); }
  }
});

test('essais de codes : frein par identité, le compte patient n’est pas touché', async () => {
  const limited = buildApp({ pool, verifyToken, cursorSecret, platformAttempts: new AttemptLimiter(3, 60_000) });
  try {
    for (let attempt = 0; attempt < 3; attempt += 1)
      expect((await api('guesser', 'POST', '/v1/platform/invitations/preview', { body: { code: generatePlatformCode() }, target: limited })).statusCode).toBe(404);
    const blocked = await api('guesser', 'POST', '/v1/platform/invitations/preview', { body: { code: generatePlatformCode() }, target: limited });
    expect(blocked.statusCode).toBe(429); expect(blocked.json().code).toBe('INVITATION_CODE_ATTEMPTS');
    const { code } = await invite(A, 'guesser@example.invalid');
    const stillBlocked = await api('guesser|guesser@example.invalid', 'POST', '/v1/platform/invitations/accept', { body: { operationId: randomUUID(), code }, target: limited });
    expect(stillBlocked.statusCode).toBe(429);
    const other = await api('patient|patient@example.invalid', 'POST', '/v1/platform/invitations/preview', { body: { code }, target: limited });
    expect(other.statusCode).toBe(200);
  } finally { await limited.close(); }
});

test('dernier opérateur : refusé par le service puis par la base, y compris en SQL direct', async () => {
  const [a, b] = [await idOf(A), await idOf(B)];
  const removed = await revokeOperator(A, b, 1);
  expect(removed.statusCode, removed.body).toBe(200);
  expect(removed.json().data).toMatchObject({ id: b, status: 'REVOKED', version: 2, self: false });
  // Révocation effective à la requête suivante, sans attendre l'expiration d'un jeton.
  const next = await api(B, 'GET', '/v1/platform/me');
  expect(next.statusCode).toBe(403); expect(next.json().code).toBe('PLATFORM_OPERATOR_REQUIRED');
  expect((await api(B, 'GET', '/v1/platform/journal')).statusCode).toBe(403);
  expect((await journal("action='REVOKE_PLATFORM_OPERATOR'"))[0]).toMatchObject({ actor_name: 'Camille Exemple', result: 'SUCCESS', subject_id: b });
  // Le dernier ne part pas : le service refuse et trace le refus.
  const last = await revokeOperator(A, a, await versionOf(a));
  expect(last.statusCode).toBe(409); expect(last.json().code).toBe('LAST_PLATFORM_OPERATOR');
  expect(await activeCount()).toBe(1);
  expect((await journal("result='REFUSED'"))[0]).toMatchObject({ action: 'REVOKE_PLATFORM_OPERATOR', reason_code: 'LAST_PLATFORM_OPERATOR', actor_name: 'Camille Exemple', subject_id: a });
  // Sans le service : la base refuse seule, par la connexion qui contourne toute politique comme sous le rôle applicatif.
  const direct = "UPDATE drivy.platform_operator SET status='REVOKED',revoked_at=now(),revoked_by=id WHERE id=$1";
  await expect(pool.query(direct, [a])).rejects.toThrow(/last_platform_operator/);
  const underRole = await asApp(A, direct, [a]);
  expect(underRole.error?.message).toMatch(/last_platform_operator/);
  await expect(pool.query('DELETE FROM drivy.platform_operator WHERE id=$1', [a])).rejects.toThrow(/platform_operator_not_deletable/);
  await expect(pool.query("UPDATE drivy.platform_operator SET subject='autre' WHERE id=$1", [a])).rejects.toThrow(/platform_operator_identity_fixed/);
  await expect(pool.query("UPDATE drivy.platform_operator SET status='ACTIVE',revoked_at=NULL,revoked_by=NULL WHERE id=$1", [b])).rejects.toThrow(/platform_operator_terminal/);
  expect(await activeCount()).toBe(1);
});

test('dernier opérateur sous concurrence : une transaction ouverte retient la seconde, qui voit la première et refuse', async () => {
  const [a, b] = [await idOf(A), await idOf(B)];
  const first = await pool.connect(), second = await pool.connect();
  try {
    await first.query('BEGIN'); await second.query('BEGIN'); await second.query("SET LOCAL lock_timeout='15s'");
    const pid = (await second.query<{ pid: number }>('SELECT pg_backend_pid() AS pid')).rows[0]!.pid;
    const revoke = "UPDATE drivy.platform_operator SET status='REVOKED',revoked_at=now(),revoked_by=$2 WHERE id=$1";
    await first.query(revoke, [a, b]);
    const outcome = second.query(revoke, [b, a]).then(() => 'accepté' as const, (error: Error) => error);
    let waiting = '';
    for (let attempt = 0; attempt < 50 && waiting !== 'Lock'; attempt += 1) {
      await sleep(40);
      waiting = (await pool.query<{ wait_event_type: string | null }>('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1', [pid])).rows[0]?.wait_event_type ?? '';
    }
    expect(waiting, 'la seconde révocation attend le verrou d’équipe').toBe('Lock');
    await first.query('COMMIT');
    const result = await outcome;
    expect(result).toBeInstanceOf(Error);
    expect((result as Error).message).toMatch(/last_platform_operator/);
  } finally { await first.query('ROLLBACK').catch(() => undefined); await second.query('ROLLBACK').catch(() => undefined); first.release(); second.release(); }
  expect(await activeCount()).toBe(1);
  expect((await pool.query("SELECT id FROM drivy.platform_operator WHERE status='ACTIVE'")).rows[0].id).toBe(b);
});

test('dernier opérateur sous rafale : cinq retraits simultanés en SQL, il en reste exactement un', async () => {
  const subjects = ['burst-1', 'burst-2', 'burst-3'];
  for (const subject of subjects) await seedPlatformOperator(pool, subject);
  const ids = [await idOf(A), await idOf(B), ...(await Promise.all(subjects.map(idOf)))];
  const author = ids[0]!;
  const outcomes = await Promise.allSettled(ids.map(target => pool.query("UPDATE drivy.platform_operator SET status='REVOKED',revoked_at=now(),revoked_by=$2 WHERE id=$1", [target, author])));
  expect(outcomes.filter(outcome => outcome.status === 'fulfilled')).toHaveLength(4);
  const failed = outcomes.filter(outcome => outcome.status === 'rejected') as PromiseRejectedResult[];
  expect(failed).toHaveLength(1);
  expect(String(failed[0]!.reason)).toMatch(/last_platform_operator/);
  expect(await activeCount()).toBe(1);
});

test('retraits croisés par le service : l’un des deux aboutit, l’autre est écarté, jamais zéro opérateur', async () => {
  const [a, b] = [await idOf(A), await idOf(B)];
  for (let round = 0; round < 3; round += 1) {
    if (round > 0) { await pool.query('TRUNCATE drivy.platform_audit_event, drivy.platform_operation, drivy.platform_operator_invitation, drivy.platform_client, drivy.school_opening_link, drivy.platform_operator');
      await seedPlatformOperator(pool, A, { displayName: 'Camille Exemple', email: emailA }); await seedPlatformOperator(pool, B, { displayName: 'Jean Exemple' }); }
    const [ida, idb] = [await idOf(A), await idOf(B)];
    const [first, second] = await Promise.all([revokeOperator(A, idb, 1), revokeOperator(B, ida, 1)]);
    const statuses = [first.statusCode, second.statusCode].sort();
    expect(statuses[0], `${first.body} ${second.body}`).toBe(200);
    expect([403, 409]).toContain(statuses[1]);
    expect(await activeCount()).toBe(1);
  }
  expect(a).not.toBe(b);
});

test('retrait de soi-même : accepté tant qu’un autre reste, tracé au nom de l’opérateur, accès fermé ensuite', async () => {
  const b = await idOf(B);
  const response = await revokeOperator(B, b, 1);
  expect(response.statusCode, response.body).toBe(200);
  expect(response.json().data).toMatchObject({ id: b, status: 'REVOKED', self: true });
  expect((await journal("action='REVOKE_PLATFORM_OPERATOR'"))[0]).toMatchObject({ actor_name: 'Jean Exemple', actor_operator_id: b, result: 'SUCCESS', subject_id: b });
  expect((await journal("action='REVOKE_PLATFORM_OPERATOR'"))[0].changes).toMatchObject({ self: true, status: { from: 'ACTIVE', to: 'REVOKED' } });
  expect((await api(B, 'GET', '/v1/platform/me')).statusCode).toBe(403);
  const row = (await pool.query('SELECT status,revoked_by,version FROM drivy.platform_operator WHERE id=$1', [b])).rows[0];
  expect(row).toMatchObject({ status: 'REVOKED', revoked_by: b, version: 2 });
  // Un ancien opérateur peut être invité de nouveau : une nouvelle appartenance, l'ancienne reste dans l'historique.
  const { code } = await invite(A, 'jean@example.invalid');
  const back = await accept('op-b|jean@example.invalid|Jean Exemple', code);
  expect(back.statusCode, back.body).toBe(201);
  expect((await pool.query('SELECT 1 FROM drivy.platform_operator WHERE subject=$1', [B])).rowCount).toBe(2);
  expect((await api(B, 'GET', '/v1/platform/me')).statusCode).toBe(200);
});

test('retrait d’un opérateur : ses invitations en attente sont révoquées avec lui, un code qu’il avait émis ne s’accepte plus (I1)', async () => {
  const a = await idOf(A), b = await idOf(B);
  const fromA = await invite(A, 'target@example.invalid'), secondFromA = await invite(A, 'second@example.invalid');
  const fromB = await invite(B, 'kept@example.invalid');
  // Une invitation déjà acceptée reste acceptée : seule l'attente est révoquée.
  const used = await invite(A, 'used@example.invalid');
  expect((await accept('used|used@example.invalid', used.code)).statusCode).toBe(201);
  const removal = await revokeOperator(B, a, 1);
  expect(removal.statusCode, removal.body).toBe(200);
  const rows = (await pool.query<{ invitee_email: string; status: string; revoked_by: string | null }>('SELECT invitee_email,status,revoked_by FROM drivy.platform_operator_invitation')).rows;
  const byEmail = Object.fromEntries(rows.map(row => [row.invitee_email, row]));
  expect(byEmail['target@example.invalid']).toMatchObject({ status: 'REVOKED', revoked_by: b });
  expect(byEmail['second@example.invalid']).toMatchObject({ status: 'REVOKED', revoked_by: b });
  expect(byEmail['used@example.invalid']).toMatchObject({ status: 'USED', revoked_by: null });
  expect(byEmail['kept@example.invalid']).toMatchObject({ status: 'AVAILABLE' });
  // Le code de l'opérateur retiré est refusé à l'aperçu comme à l'acceptation : aucune ligne d'opérateur n'est créée.
  for (const [code, subject, email] of [[fromA.code, 'target', 'target@example.invalid'], [secondFromA.code, 'second', 'second@example.invalid']] as const) {
    const refused = await accept(`${subject}|${email}`, code);
    expect([refused.statusCode, refused.json().code], refused.body).toEqual([410, 'PLATFORM_INVITATION_REVOKED']);
    expect((await preview(`${subject}|${email}`, code)).statusCode).toBe(410);
    expect((await pool.query('SELECT 1 FROM drivy.platform_operator WHERE subject=$1', [subject])).rowCount).toBe(0);
    expect((await api(subject, 'GET', '/v1/platform/me')).statusCode).toBe(403);
  }
  // L'invitation d'un opérateur resté dans l'équipe n'est pas touchée.
  expect((await preview('kept|kept@example.invalid', fromB.code)).statusCode).toBe(200);
  expect((await accept('kept|kept@example.invalid', fromB.code)).statusCode).toBe(201);
  // La console le reflète : liste lue par l'opérateur resté, journal avec le nombre d'invitations révoquées.
  const listed = (await api(B, 'GET', '/v1/platform/invitations')).json().data.items as Array<{ maskedEmail: string; status: string }>;
  expect(Object.fromEntries(listed.map(item => [item.maskedEmail, item.status]))).toMatchObject({
    't***@example.invalid': 'REVOKED', 's***@example.invalid': 'REVOKED', 'u***@example.invalid': 'USED', 'k***@example.invalid': 'USED' });
  const entries = await journal("action='REVOKE_PLATFORM_OPERATOR' AND result='SUCCESS'");
  expect(entries).toHaveLength(1);
  expect(entries[0].changes).toMatchObject({ self: false, status: { from: 'ACTIVE', to: 'REVOKED' }, revokedInvitations: 2 });
  expect(JSON.stringify(entries[0])).not.toContain(fromA.code);
  expect(await journal("action='REVOKE_PLATFORM_INVITATION'")).toHaveLength(0);
});

test('retrait de soi-même : les invitations en attente de l’opérateur partent aussi, au nom de l’opérateur encore actif au moment du retrait (I1)', async () => {
  const b = await idOf(B);
  const own = await invite(B, 'own@example.invalid');
  const response = await revokeOperator(B, b, 1);
  expect(response.statusCode, response.body).toBe(200);
  const row = (await pool.query('SELECT status,revoked_by FROM drivy.platform_operator_invitation WHERE invitee_email=$1', ['own@example.invalid'])).rows[0];
  expect(row).toMatchObject({ status: 'REVOKED', revoked_by: b });
  expect((await accept('own|own@example.invalid', own.code)).statusCode).toBe(410);
  expect((await journal("action='REVOKE_PLATFORM_OPERATOR'"))[0].changes).toMatchObject({ self: true, revokedInvitations: 1 });
  // Aucune invitation en attente : le compte est zéro, jamais absent.
  await seedPlatformOperator(pool, 'op-c', { displayName: 'Claire Exemple' });
  const c = await idOf('op-c');
  expect((await revokeOperator(A, c, 1)).statusCode).toBe(200);
  expect((await journal(`action='REVOKE_PLATFORM_OPERATOR' AND subject_id='${c}'`))[0].changes).toMatchObject({ revokedInvitations: 0 });
});

test('défense en profondeur : une invitation dont l’auteur n’est plus actif n’est acceptable ni par le service ni par la base, même sans révocation (I1)', async () => {
  const orphan = await invite(A, 'orphan@example.invalid'), fine = await invite(B, 'fine@example.invalid');
  const idByEmail = async (email: string) => (await pool.query<{ id: string }>('SELECT id FROM drivy.platform_operator_invitation WHERE invitee_email=$1', [email])).rows[0]!.id;
  const insertAs = (subject: string, email: string, code: string, invitationId: string) => asApp(subject,
    "INSERT INTO drivy.platform_operator(id,issuer,subject,display_name,contact_email,added_via,invitation_id) VALUES(gen_random_uuid(),$1,$2,'Invité','"
    + email + "','INVITATION',$3)", [issuer, subject, invitationId], { email, hash: hashOf(code) });
  // Témoin : la base laisse entrer le porteur d'un code dont l'auteur est actif.
  expect((await insertAs('witness', 'fine@example.invalid', fine.code, await idByEmail('fine@example.invalid'))).error).toBeUndefined();
  // Retrait en SQL direct, hors du service : l'invitation de A reste AVAILABLE, son auteur ne l'est plus.
  await pool.query("UPDATE drivy.platform_operator SET status='REVOKED',revoked_at=now(),revoked_by=$1 WHERE id=$2", [await idOf(B), await idOf(A)]);
  expect((await pool.query('SELECT status FROM drivy.platform_operator_invitation WHERE invitee_email=$1', ['orphan@example.invalid'])).rows[0].status).toBe('AVAILABLE');
  const refused = await accept('orphan|orphan@example.invalid', orphan.code);
  expect([refused.statusCode, refused.json().code], refused.body).toEqual([410, 'PLATFORM_INVITATION_REVOKED']);
  expect((await preview('orphan|orphan@example.invalid', orphan.code)).statusCode).toBe(410);
  const insert = await insertAs('orphan', 'orphan@example.invalid', orphan.code, await idByEmail('orphan@example.invalid'));
  expect(insert.error?.code).toBe('42501');
  expect((await pool.query('SELECT 1 FROM drivy.platform_operator WHERE subject=$1', ['orphan'])).rowCount).toBe(0);
  // L'invitation d'un auteur encore actif reste acceptable par le service.
  expect((await accept('fine|fine@example.invalid', fine.code)).statusCode).toBe(201);
});

test('versions et reçus des retraits : pas d’écrasement silencieux, rejeu à l’identique, double envoi simultané', async () => {
  const b = await idOf(B);
  const target = `/v1/platform/operators/${b}/revoke`;
  expect((await api(A, 'POST', target, { body: { operationId: randomUUID() } })).statusCode).toBe(428);
  expect((await api(A, 'POST', target, { body: { operationId: randomUUID() }, headers: { 'if-match': 'W/"1"' } })).statusCode).toBe(400);
  expect((await api(A, 'POST', target, { body: { operationId: randomUUID() }, version: 1, key: false })).statusCode).toBe(400);
  expect((await api(A, 'POST', `/v1/platform/operators/${randomUUID()}/revoke`, { body: { operationId: randomUUID() }, version: 1 })).statusCode).toBe(404);
  const staleId = randomUUID();
  const stale = await revokeOperator(A, b, 9, staleId);
  expect(stale.statusCode).toBe(412); expect(stale.json().code).toBe('VERSION_CONFLICT');
  expect((await pool.query('SELECT status FROM drivy.platform_operator WHERE id=$1', [b])).rows[0].status).toBe('ACTIVE');
  expect(await journal("result='REFUSED'")).toEqual([expect.objectContaining({ action: 'REVOKE_PLATFORM_OPERATOR', reason_code: 'VERSION_CONFLICT', operation_id: staleId, subject_id: b })]);
  // Même clé, même contenu : un seul retrait, un seul reçu, une seule ligne de succès, deux réponses identiques.
  const operationId = randomUUID();
  const [one, two] = await Promise.all([revokeOperator(A, b, 1, operationId), revokeOperator(A, b, 1, operationId)]);
  expect([one.statusCode, two.statusCode]).toEqual([200, 200]);
  expect(one.json().data).toEqual(two.json().data);
  expect(await journal("action='REVOKE_PLATFORM_OPERATOR' AND result='SUCCESS'")).toHaveLength(1);
  expect((await pool.query('SELECT 1 FROM drivy.platform_operation WHERE operation_id=$1', [operationId])).rowCount).toBe(1);
  // Réponse perdue : la lecture du reçu rend le résultat enregistré, et un autre contenu avec la même clé est refusé.
  const receipt = await api(A, 'GET', `/v1/platform/operations/${operationId}`);
  expect(receipt.json().data).toMatchObject({ kind: 'REVOKE_PLATFORM_OPERATOR', statusCode: 200, result: one.json().data });
  const mismatch = await revokeOperator(A, b, 2, operationId);
  expect(mismatch.statusCode).toBe(409); expect(mismatch.json().code).toBe('IDEMPOTENCY_MISMATCH');
  const again = await revokeOperator(A, b, 2);
  expect(again.statusCode).toBe(409); expect(again.json().code).toBe('PLATFORM_OPERATOR_REVOKED');
});

test('journal : acteur, date, résultat et modification utile ; filtres, pagination, ajout seul', async () => {
  for (const email of ['un@example.invalid', 'deux@example.invalid', 'trois@example.invalid']) expect((await invite(A, email)).response.statusCode).toBe(201);
  expect((await invite(B, 'un@example.invalid')).response.statusCode).toBe(409);
  const all = await api(B, 'GET', '/v1/platform/journal?limit=50');
  expect(all.statusCode).toBe(200);
  const items = all.json().data.items as Array<Record<string, any>>;
  expect(items).toHaveLength(4);
  expect(items.map(item => item.occurredAt)).toEqual([...items.map(item => item.occurredAt)].sort().reverse());
  expect(items[0]).toMatchObject({ actorKind: 'OPERATOR', actorName: 'Jean Exemple', action: 'CREATE_PLATFORM_INVITATION', result: 'REFUSED', reasonCode: 'PLATFORM_INVITATION_PENDING', schoolId: null });
  expect(items[1]).toMatchObject({ actorName: 'Camille Exemple', result: 'SUCCESS', reasonCode: null, subject: { type: 'PlatformInvitation' }, changes: { level: 'COMMERCIAL' } });
  expect(new Date(items[1]!.occurredAt).getTime()).toBeGreaterThan(Date.now() - 60_000);
  expect(JSON.stringify(items)).not.toMatch(/[a-z0-9]@example\.invalid|code_?hash/i);
  const refusals = (await api(A, 'GET', '/v1/platform/journal?result=REFUSED')).json().data.items;
  expect(refusals).toHaveLength(1);
  // Pagination à curseur signé : aucune ligne perdue ni doublée, curseur refusé hors de son filtre.
  const pageOne = (await api(A, 'GET', '/v1/platform/journal?limit=3')).json().data;
  expect(pageOne.items).toHaveLength(3); expect(pageOne.nextCursor).toBeTruthy();
  const pageTwo = (await api(A, 'GET', `/v1/platform/journal?limit=3&cursor=${pageOne.nextCursor}`)).json().data;
  expect(pageTwo.items).toHaveLength(1); expect(pageTwo.nextCursor).toBeNull();
  expect([...pageOne.items, ...pageTwo.items].map((item: { id: string }) => item.id)).toEqual(items.map(item => item.id));
  const wrongScope = await api(A, 'GET', `/v1/platform/journal?limit=2&cursor=${pageOne.nextCursor}`);
  expect(wrongScope.statusCode).toBe(400); expect(wrongScope.json().code).toBe('INVALID_CURSOR');
  expect((await api(A, 'GET', '/v1/platform/journal?limit=0')).statusCode).toBe(400);
  expect((await api(A, 'GET', '/v1/platform/journal?unknown=1')).statusCode).toBe(400);
  // Ajout seul : ni le service, ni la base, ni le rôle applicatif ne modifient ou ne suppriment une ligne.
  await expect(pool.query("UPDATE drivy.platform_audit_event SET result='SUCCESS'")).rejects.toThrow(/platform_append_only/);
  await expect(pool.query('DELETE FROM drivy.platform_audit_event')).rejects.toThrow(/platform_append_only/);
  await expect(pool.query("UPDATE drivy.platform_operation SET kind='AUTRE_ACTION'")).rejects.toThrow(/platform_append_only/);
  await expect(pool.query('DELETE FROM drivy.platform_operation')).rejects.toThrow(/platform_append_only/);
  expect((await asApp(A, "UPDATE drivy.platform_audit_event SET result='SUCCESS'")).error?.code).toBe('42501');
  expect((await asApp(A, 'DELETE FROM drivy.platform_audit_event')).error?.code).toBe('42501');
  // Aucune écriture au nom d'un autre opérateur ni au nom du système.
  const forged = `INSERT INTO drivy.platform_audit_event(id,actor_kind,actor_operator_id,actor_name,action,result) VALUES(gen_random_uuid(),$1,$2,'Quelqu''un','FORGED_ACTION','SUCCESS')`;
  expect((await asApp(A, forged, ['OPERATOR', await idOf(B)])).error?.code).toBe('42501');
  expect((await asApp(A, forged.replace('actor_operator_id,', '').replace('$2,', ''), ['SYSTEM'])).error).toBeDefined();
});

test('point d’entrée des lots suivants : acteur de plateforme, école, reçu, rejeu et refus sans secret', async () => {
  const schoolId = fixtureIds.schoolA;
  const identity: Identity = { issuer, subject: A };
  const operationId = randomUUID();
  const spec = { kind: 'SYNTHETIC_SCHOOL_ACTION', operationId, expectedVersion: null, body: { schoolId, plan: 'essai' }, refusal: { action: 'SYNTHETIC_SCHOOL_ACTION', schoolId } };
  const effect = async () => ({ data: { ok: true }, journal: { action: 'SYNTHETIC_SCHOOL_ACTION', schoolId, subject: { type: 'School', id: schoolId }, changes: { plan: { from: null, to: 'essai' } } } });
  const first = await platformCommand(pool, identity, spec, effect);
  expect(first).toMatchObject({ data: { ok: true }, status: 200, replayed: false });
  const replay = await platformCommand(pool, identity, spec, effect);
  expect(replay).toMatchObject({ data: { ok: true }, replayed: true });
  expect(await journal("action='SYNTHETIC_SCHOOL_ACTION'")).toHaveLength(1);
  expect((await journal("action='SYNTHETIC_SCHOOL_ACTION'"))[0]).toMatchObject({ school_id: schoolId, actor_name: 'Camille Exemple', result: 'SUCCESS', operation_id: operationId, changes: { plan: { from: null, to: 'essai' } } });
  const filtered = (await api(B, 'GET', `/v1/platform/journal?schoolId=${schoolId}`)).json().data.items;
  expect(filtered).toHaveLength(1); expect(filtered[0]).toMatchObject({ schoolId, action: 'SYNTHETIC_SCHOOL_ACTION' });
  expect((await api(B, 'GET', `/v1/platform/journal?schoolId=${randomUUID()}`)).json().data.items).toHaveLength(0);
  await expect(platformCommand(pool, identity, { ...spec, body: { ...spec.body, plan: 'autre' } }, effect)).rejects.toMatchObject({ code: 'IDEMPOTENCY_MISMATCH' });
  await expect(platformCommand(pool, { issuer, subject: 'demo-admin' }, { ...spec, operationId: randomUUID() }, effect)).rejects.toMatchObject({ code: 'PLATFORM_OPERATOR_REQUIRED' });
  // Un secret au journal annule la commande entière : ni reçu, ni effet, ni ligne.
  const secretId = randomUUID();
  await expect(platformCommand(pool, identity, { ...spec, operationId: secretId },
    async () => ({ data: { ok: true }, journal: { action: 'SYNTHETIC_SCHOOL_ACTION', changes: { code: 'ABCDE-FGHJK' } } }))).rejects.toThrow(/secret/);
  expect((await pool.query('SELECT 1 FROM drivy.platform_operation WHERE operation_id=$1', [secretId])).rowCount).toBe(0);
  expect(await journal("action='SYNTHETIC_SCHOOL_ACTION'")).toHaveLength(1);
});

test('mise en service : propriétaire seul, idempotente, tracée au journal par le système, sans identifiant dans le rapport', async () => {
  await pool.query('TRUNCATE drivy.platform_audit_event, drivy.platform_operation, drivy.platform_operator_invitation, drivy.platform_client, drivy.school_opening_link, drivy.platform_operator');
  await expect(bootstrapPlatformOperators(owner, [])).rejects.toThrow(/Aucune identité/);
  const entries = [{ issuer, subject: 'first-account' }, { issuer, subject: 'second-account', displayName: 'Camille Exemple' }];
  expect(await bootstrapPlatformOperators(owner, entries)).toEqual({ added: 2, alreadyActive: 0 });
  expect(await bootstrapPlatformOperators(owner, entries)).toEqual({ added: 0, alreadyActive: 2 });
  const team = (await pool.query("SELECT subject,display_name,added_via,level,status,version FROM drivy.platform_operator ORDER BY created_at,id")).rows;
  expect(team).toEqual([
    { subject: 'first-account', display_name: 'Opérateur 1', added_via: 'BOOTSTRAP', level: 'COMMERCIAL', status: 'ACTIVE', version: 1 },
    { subject: 'second-account', display_name: 'Camille Exemple', added_via: 'BOOTSTRAP', level: 'COMMERCIAL', status: 'ACTIVE', version: 1 },
  ]);
  const events = await journal("action='BOOTSTRAP_PLATFORM_OPERATOR'");
  expect(events).toHaveLength(2);
  expect(events[0]).toMatchObject({ actor_kind: 'SYSTEM', actor_operator_id: null, actor_name: 'Mise en service', result: 'SUCCESS', subject_type: 'PlatformOperator' });
  expect(events[0].changes).toEqual({ level: 'COMMERCIAL', source: 'PRIVATE_CONFIG' });
  expect(JSON.stringify(events).includes('first-account')).toBe(false);
  // Les comptes mis en service entrent dans la console ; le journal montre leur mise en service.
  expect((await api('first-account', 'GET', '/v1/platform/me')).statusCode).toBe(200);
  const shown = (await api('second-account', 'GET', '/v1/platform/journal')).json().data.items;
  expect(shown.map((item: { action: string; actorKind: string }) => `${item.actorKind}:${item.action}`)).toEqual(['SYSTEM:BOOTSTRAP_PLATFORM_OPERATOR', 'SYSTEM:BOOTSTRAP_PLATFORM_OPERATOR']);
  // Lecture de la configuration privée : au plus dix identités, l'ancienne liste d'ouverture seulement sur demande.
  const env = { PLATFORM_OPERATORS_BOOTSTRAP_JSON: JSON.stringify([{ issuer, subject: 'configured-one' }]),
    SCHOOL_OPENING_OPERATORS_JSON: JSON.stringify([{ issuer, subject: 'legacy-one' }, { issuer, subject: 'configured-one' }]) } as NodeJS.ProcessEnv;
  expect(readBootstrapEntries(env).map(entry => entry.subject)).toEqual(['configured-one']);
  expect(readBootstrapEntries(env, { legacyOpeningOperators: true }).map(entry => `${entry.subject}:${entry.source}`)).toEqual(['configured-one:PRIVATE_CONFIG', 'legacy-one:LEGACY_OPENING_LIST']);
  const legacy = readBootstrapEntries(env, { legacyOpeningOperators: true });
  expect(await bootstrapPlatformOperators(owner, legacy)).toEqual({ added: 2, alreadyActive: 0 });
  expect((await journal("action='BOOTSTRAP_PLATFORM_OPERATOR' AND changes->>'source'='LEGACY_OPENING_LIST'"))).toHaveLength(1);
  // Le propriétaire ne peut rien d'autre qu'amorcer : pas de révocation ni de falsification du journal par cette voie.
  await expect(owner.query("INSERT INTO drivy.platform_operator(id,issuer,subject,display_name,added_via) VALUES(gen_random_uuid(),$1,'forged','F','INVITATION')", [issuer])).rejects.toThrow();
});
