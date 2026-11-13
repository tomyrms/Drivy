import { randomBytes, randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, expect, test } from 'vitest';
import { Pool } from 'pg';
import { buildApp } from '../src/app.js';
import type { Identity } from '../src/auth.js';
import { ApiError } from '../src/errors.js';
import { invitationCodeHasher } from '../src/invitation-code.js';
import { openingDigest } from '../src/school-opening-model.js';
import { fixtureIds, seedFixtures } from '../scripts/fixtures.js';
import { freshDatabase, issuer, seedPlatformOperator } from './support/harness.js';

/**
 * R01-T02 (#454) sur PostgreSQL réelle : fiches des écoles clientes, codes d'ouverture rattachés, liaison unique école, fiche
 * et premier ADMIN, reprise des écoles pilotes, concurrence, pagination au-delà de 100 et garde-fous de la base.
 * Jeu d'essai synthétique ; aucune identité, adresse ni école réelle. Jeton de recette : `sujet`, `sujet|adresse`, `sujet|adresse|Nom`.
 */
let pool: Pool, app: ReturnType<typeof buildApp>;
const cursorSecret = 'platform-clients-synthetic-secret-32-characters';
const hashOf = openingDigest(invitationCodeHasher(cursorSecret));
const verifyToken = async (header: string | undefined): Promise<Identity> => {
  if (!header?.startsWith('Bearer ')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  const [subject, rawEmail, name] = header.slice(7).split('|');
  const verified = rawEmail && !rawEmail.startsWith('~') ? rawEmail : undefined;
  return { issuer, subject: subject!, ...(verified ? { verifiedEmail: verified } : {}), ...(name ? { displayName: name } : {}) };
};
const A = 'op-a', B = 'op-b';
const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const newCode = () => { const chars = Array.from(randomBytes(8), byte => alphabet[byte % 32]).join(''); return `${chars.slice(0, 4)}-${chars.slice(4)}`; };

beforeAll(async () => {
  pool = await freshDatabase();
  app = buildApp({ pool, verifyToken, cursorSecret });
});
beforeEach(async () => {
  // Base remise à l'état de départ : jeu d'essai de l'API, deux opérateurs, aucune fiche ni aucun code.
  await pool.query('TRUNCATE drivy.person, drivy.school, drivy.platform_operator, drivy.platform_operation, drivy.platform_audit_event, drivy.platform_operator_invitation CASCADE');
  await seedFixtures(pool, issuer);
  await seedPlatformOperator(pool, A, { displayName: 'Camille Exemple' });
  await seedPlatformOperator(pool, B, { displayName: 'Jean Exemple' });
});
afterAll(async () => { await app?.close(); await pool?.end(); });

interface Options { body?: Record<string, unknown>; version?: number | null; key?: boolean; headers?: Record<string, string>; target?: ReturnType<typeof buildApp> }
const api = (subject: string, method: 'GET' | 'POST' | 'PATCH', url: string, options: Options = {}) => (options.target ?? app).inject({
  method, url, headers: {
    authorization: `Bearer ${subject}`,
    ...(options.body?.operationId && options.key !== false ? { 'idempotency-key': String(options.body.operationId) } : {}),
    ...(options.version ? { 'if-match': `"${options.version}"` } : {}), ...options.headers,
  },
  ...(options.body ? { payload: options.body } : {}),
});
const operatorId = async (subject: string) => (await pool.query<{ id: string }>("SELECT id FROM drivy.platform_operator WHERE subject=$1 AND status='ACTIVE'", [subject])).rows[0]!.id;
const journal = async (where = 'true') => (await pool.query(`SELECT * FROM drivy.platform_audit_event WHERE ${where} ORDER BY occurred_at,id`)).rows;
const count = async (table: string, where = 'true') => Number((await pool.query<{ n: string }>(`SELECT count(*) AS n FROM drivy.${table} WHERE ${where}`)).rows[0]!.n);

const fiche = { displayName: 'Auto-école des Lilas', contactName: 'Marie Exemple', contactEmail: 'marie@example.invalid', contactPhone: '+41 79 000 00 00',
  billingStreet: 'Rue Exemple 1', billingPostalCode: '1000', billingCity: 'Lausanne', billingCountry: 'Suisse', internalNotes: 'Relancer en janvier' };
const createClient = (as: string, extra: Record<string, unknown> = {}) => api(as, 'POST', '/v1/platform/clients', { body: { operationId: randomUUID(), ...fiche, ...extra } });
const getClient = async (id: string, as = A) => { const response = await api(as, 'GET', `/v1/platform/clients/${id}`); expect(response.statusCode, response.body).toBe(200); return response.json().data; };
/** « Créer un code » : le code est tiré par la passerelle, le service ne reçoit que lui et n'en garde que l'empreinte. */
async function issueCode(as = A, extra: Record<string, unknown> = {}) {
  const code = newCode(), body = { operationId: randomUUID(), code, displayName: 'Auto-école des Lilas', ...extra };
  const response = await api(as, 'POST', '/v1/platform/school-codes', { body });
  return { code, body, response, data: response.statusCode === 201 ? response.json().data : undefined };
}
const command = (token: string, extra: Record<string, unknown> = {}) => ({ operationId: randomUUID(), token, schoolName: 'École de recette', displayName: 'Responsable de recette',
  contactEmail: 'school@example.invalid', contactPhone: null, timeZone: 'Europe/Zurich', instructs: false, ...extra });
const openSchool = (token: string, subject: string, extra: Record<string, unknown> = {}, target?: ReturnType<typeof buildApp>) =>
  api(subject, 'POST', '/v1/school-openings', { body: command(token, extra), ...(target ? { target } : {}) });
const revoke = (as: string, codeId: string, operationId = randomUUID()) => api(as, 'POST', `/v1/platform/school-codes/${codeId}/revoke`, { body: { operationId } });

/** Requête sous le rôle applicatif avec l'identité donnée : ce que la base laisse voir ou faire, quel que soit le service. */
async function asApp(subject: string, sql: string, params: unknown[] = [], { operator = false }: { operator?: boolean } = {}) {
  const db = await pool.connect();
  try {
    await db.query('BEGIN'); await db.query('SET LOCAL ROLE drivy_app');
    await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.school_opening_operator',$3,true)", [issuer, subject, operator ? 'true' : '']);
    const result = await db.query(sql, params);
    return { rows: result.rows as Array<Record<string, any>>, rowCount: result.rowCount ?? 0, error: undefined as (Error & { code?: string }) | undefined };
  } catch (error) { return { rows: [], rowCount: 0, error: error as Error & { code?: string } }; }
  finally { await db.query('ROLLBACK').catch(() => undefined); db.release(); }
}

test('la porte : seul un opérateur actif relu en base entre, tout autre compte reçoit 403 sans rien écrire', async () => {
  await seedPlatformOperator(pool, 'op-former');
  await pool.query("UPDATE drivy.platform_operator SET status='REVOKED',revoked_at=now(),revoked_by=$1 WHERE subject='op-former'", [await operatorId(A)]);
  const someId = randomUUID();
  const routes: Array<[string, 'GET' | 'POST' | 'PATCH', string, Options]> = [
    ['annuaire', 'GET', '/v1/platform/clients', {}], ['fiche', 'GET', `/v1/platform/clients/${someId}`, {}], ['écoles libres', 'GET', '/v1/platform/unattached-schools', {}],
    ['codes', 'GET', '/v1/platform/school-codes', {}],
    ['créer une fiche', 'POST', '/v1/platform/clients', { body: { operationId: randomUUID(), displayName: 'Intrus' } }],
    ['modifier une fiche', 'PATCH', `/v1/platform/clients/${someId}`, { body: { operationId: randomUUID(), contactName: 'Intrus' }, version: 1 }],
    ['rattacher', 'POST', `/v1/platform/clients/${someId}/attach-school`, { body: { operationId: randomUUID(), schoolId: fixtureIds.schoolA }, version: 1 }],
    ['créer un code', 'POST', '/v1/platform/school-codes', { body: { operationId: randomUUID(), code: newCode(), displayName: 'Intrus' } }],
    ['révoquer un code', 'POST', `/v1/platform/school-codes/${someId}/revoke`, { body: { operationId: randomUUID() } }],
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
  // Rien n'a été écrit par ces refus : ni fiche, ni code, ni reçu, ni journal.
  for (const table of ['platform_client', 'school_opening_link', 'platform_operation', 'platform_audit_event']) expect(await count(table), table).toBe(0);
  expect((await api(A, 'GET', '/v1/platform/clients')).statusCode).toBe(200);
});

test('une fiche : création idempotente, lecture, modification versionnée, aucune zone obligatoire, journal sans coordonnées', async () => {
  const body = { operationId: randomUUID(), ...fiche };
  const created = await api(A, 'POST', '/v1/platform/clients', { body });
  expect(created.statusCode, created.body).toBe(201);
  const data = created.json().data;
  expect(data).toMatchObject({ displayName: fiche.displayName, contactName: fiche.contactName, contactEmail: fiche.contactEmail, contactPhone: fiche.contactPhone,
    billing: { street: 'Rue Exemple 1', postalCode: '1000', city: 'Lausanne', country: 'Suisse' }, internalNotes: fiche.internalNotes,
    preparation: 'AWAITING_SCHOOL', schoolId: null, school: null, link: null, codes: [], version: 1, latestCode: null,
    commercial: { state: 'NOT_CONFIGURED', offer: null, dueDates: [] } });
  expect(await getClient(data.id, B)).toEqual(data);
  // Rejeu à l'identique : même fiche, une seule ligne ; autre contenu avec la même clé : refusé ; sans clé : refusé.
  const again = await api(A, 'POST', '/v1/platform/clients', { body });
  expect(again.statusCode).toBe(201); expect(again.json().data.id).toBe(data.id);
  expect(await count('platform_client')).toBe(1);
  const mismatch = await api(A, 'POST', '/v1/platform/clients', { body: { ...body, displayName: 'Autre nom' } });
  expect(mismatch.statusCode).toBe(409); expect(mismatch.json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await api(A, 'POST', '/v1/platform/clients', { body: { ...body, operationId: randomUUID() }, key: false })).statusCode).toBe(400);
  const receipt = await api(A, 'GET', `/v1/platform/operations/${body.operationId}`);
  expect(receipt.statusCode).toBe(200); expect(receipt.json().data).toMatchObject({ operationId: body.operationId, kind: 'CREATE_PLATFORM_CLIENT', statusCode: 201 });
  expect((await api(B, 'GET', `/v1/platform/operations/${body.operationId}`)).statusCode).toBe(404);
  // Aucune zone n'est obligatoire : une fiche vide est une fiche de suivi légère.
  const bare = await api(A, 'POST', '/v1/platform/clients', { body: { operationId: randomUUID() } });
  expect(bare.statusCode, bare.body).toBe(201);
  expect(bare.json().data).toMatchObject({ displayName: null, contactName: null, contactEmail: null, preparation: 'AWAITING_SCHOOL', version: 1 });
  // Modification : If-Match obligatoire, version stricte, `null` efface, une zone absente reste telle quelle.
  const patchBody = { operationId: randomUUID(), contactName: 'Paul Exemple', internalNotes: null };
  expect((await api(A, 'PATCH', `/v1/platform/clients/${data.id}`, { body: patchBody })).statusCode).toBe(428);
  const patched = await api(A, 'PATCH', `/v1/platform/clients/${data.id}`, { body: patchBody, version: 1 });
  expect(patched.statusCode, patched.body).toBe(200);
  expect(patched.json().data).toMatchObject({ contactName: 'Paul Exemple', internalNotes: null, displayName: fiche.displayName, contactEmail: fiche.contactEmail, version: 2 });
  const replay = await api(A, 'PATCH', `/v1/platform/clients/${data.id}`, { body: patchBody, version: 1 });
  expect(replay.statusCode).toBe(200); expect(replay.json().data.version).toBe(2);
  const stale = await api(B, 'PATCH', `/v1/platform/clients/${data.id}`, { body: { operationId: randomUUID(), contactName: 'Ancienne version' }, version: 1 });
  expect(stale.statusCode).toBe(412); expect(stale.json().code).toBe('VERSION_CONFLICT');
  expect((await getClient(data.id)).contactName).toBe('Paul Exemple');
  expect((await api(A, 'PATCH', `/v1/platform/clients/${data.id}`, { body: { operationId: randomUUID() }, version: 2 })).statusCode).toBe(400);
  expect((await api(A, 'GET', `/v1/platform/clients/${randomUUID()}`)).statusCode).toBe(404);
  expect((await api(A, 'PATCH', `/v1/platform/clients/${randomUUID()}`, { body: { operationId: randomUUID(), contactName: 'X' }, version: 1 })).statusCode).toBe(404);
  // Le journal retient les zones modifiées, jamais leur valeur, avec l'opérateur confirmé par la base.
  const created2 = await journal("action='CREATE_PLATFORM_CLIENT'");
  expect(created2.length).toBe(2);
  expect(created2.find(entry => entry.subject_id === data.id)).toMatchObject({ actor_kind: 'OPERATOR', actor_name: 'Camille Exemple', result: 'SUCCESS', subject_type: 'PlatformClient', subject_id: data.id, school_id: null });
  const updated = await journal("action='UPDATE_PLATFORM_CLIENT' AND result='SUCCESS'");
  expect(updated).toHaveLength(1);
  expect(updated[0].changes).toEqual({ fields: ['contactName', 'internalNotes'] });
  const everything = JSON.stringify(await journal());
  for (const secret of [fiche.contactEmail, fiche.contactPhone, fiche.internalNotes, 'Paul Exemple', fiche.billingStreet]) expect(everything.includes(secret), secret).toBe(false);
});

test('« Créer un code » : empreinte seule en base, rejeu à l’identique, un seul code utilisable par fiche, révocation', async () => {
  const { code, body, response, data } = await issueCode(A, { validityDays: 3 });
  expect(response.statusCode, response.body).toBe(201);
  expect(data.client).toMatchObject({ displayName: fiche.displayName, preparation: 'AWAITING_SCHOOL', schoolId: null, version: 1 });
  expect(data.client.codes).toHaveLength(1);
  expect(data.client.codes[0]).toMatchObject({ id: data.codeId, state: 'AVAILABLE', clientId: data.client.id, clientName: fiche.displayName, issuedByName: 'Camille Exemple', school: null });
  expect(data.client.latestCode).toMatchObject({ id: data.codeId, state: 'AVAILABLE' });
  expect(Math.round((Date.parse(data.client.codes[0].expiresAt) - Date.parse(data.client.codes[0].createdAt)) / 86_400_000)).toBe(3);
  // Le code n'est ni dans une réponse, ni dans la base, ni dans un reçu, ni dans le journal : seule son empreinte à clé serveur y est.
  const link = (await pool.query('SELECT * FROM drivy.school_opening_link')).rows[0];
  expect(link.token_hash).toBe(hashOf(code)); expect(link.client_id).toBe(data.client.id); expect(link.issued_by_operator_id).toBe(await operatorId(A));
  const bare = code.replace('-', '');
  for (const text of [response.body, JSON.stringify(link), JSON.stringify((await pool.query('SELECT * FROM drivy.platform_operation')).rows), JSON.stringify(await journal())]) {
    expect(text.includes(code) || text.includes(bare)).toBe(false);
  }
  // Rejeu (réponse perdue) : même code, un seul lien ; même clé avec un autre contenu : refusée.
  const again = await api(A, 'POST', '/v1/platform/school-codes', { body });
  expect(again.statusCode).toBe(201); expect(again.json().data.codeId).toBe(data.codeId);
  expect(await count('school_opening_link')).toBe(1); expect(await count('platform_client')).toBe(1);
  const mismatch = await api(A, 'POST', '/v1/platform/school-codes', { body: { ...body, code: newCode() } });
  expect(mismatch.statusCode).toBe(409); expect(mismatch.json().code).toBe('IDEMPOTENCY_MISMATCH');
  // Un même code ne sert qu'une fois ; un second code utilisable sur la même fiche est refusé tant que le premier vit.
  const taken = await api(B, 'POST', '/v1/platform/school-codes', { body: { operationId: randomUUID(), code, displayName: 'Autre' } });
  expect(taken.statusCode).toBe(409); expect(taken.json().code).toBe('OPENING_CODE_TAKEN');
  const pending = await issueCode(B, { clientId: data.client.id, displayName: undefined });
  expect(pending.response.statusCode).toBe(409); expect(pending.response.json().code).toBe('CLIENT_CODE_PENDING');
  const exclusive = await api(A, 'POST', '/v1/platform/school-codes', { body: { operationId: randomUUID(), code: newCode(), clientId: data.client.id, displayName: 'Les deux' } });
  expect(exclusive.statusCode).toBe(400);
  // Révocation : état REVOKED, rejeu identique, seconde révocation refusée, puis un nouveau code redevient possible.
  const revocation = randomUUID();
  const revoked = await revoke(B, data.codeId, revocation);
  expect(revoked.statusCode, revoked.body).toBe(200); expect(revoked.json().data).toMatchObject({ id: data.codeId, state: 'REVOKED', clientId: data.client.id });
  expect(revoked.json().data.revokedAt).toBeTruthy();
  expect((await revoke(B, data.codeId, revocation)).json().data).toEqual(revoked.json().data);
  const twice = await revoke(A, data.codeId); expect(twice.statusCode).toBe(409); expect(twice.json().code).toBe('OPENING_LINK_REVOKED');
  expect((await revoke(A, randomUUID())).statusCode).toBe(404);
  const second = await issueCode(A, { clientId: data.client.id, displayName: undefined });
  expect(second.response.statusCode, second.response.body).toBe(201);
  expect(second.data.client.codes.map((item: { state: string }) => item.state).sort()).toEqual(['AVAILABLE', 'REVOKED']);
  expect(second.data.client.id).toBe(data.client.id);
  expect((await api(A, 'POST', '/v1/platform/school-codes', { body: { operationId: randomUUID(), code: newCode(), clientId: randomUUID() } })).statusCode).toBe(404);
  // Journal : un événement par commande réussie, jamais le code.
  expect((await journal("result='SUCCESS'")).map(entry => entry.action).sort()).toEqual(['CREATE_SCHOOL_OPENING_CODE', 'CREATE_SCHOOL_OPENING_CODE', 'REVOKE_SCHOOL_OPENING_CODE']);
  expect((await journal("action='CREATE_SCHOOL_OPENING_CODE'")).find(entry => entry.changes.newClient === true).changes).toMatchObject({ clientId: data.client.id, newClient: true, validityDays: 3 });
  // Suivi : liste des codes par état et par fiche.
  const listed = await api(A, 'GET', '/v1/platform/school-codes');
  expect(listed.json().data.total).toBe(2); expect(listed.json().data.items).toHaveLength(2);
  expect((await api(A, 'GET', '/v1/platform/school-codes?state=REVOKED')).json().data.items.map((item: { id: string }) => item.id)).toEqual([data.codeId]);
  expect((await api(A, 'GET', `/v1/platform/school-codes?clientId=${data.client.id}&state=AVAILABLE`)).json().data.total).toBe(1);
  expect((await api(A, 'GET', `/v1/platform/school-codes?clientId=${randomUUID()}`)).json().data.total).toBe(0);
});

test('ouverture par code : école, fiche et premier ADMIN reliés une fois, reçu retrouvé après coupure, rien de pédagogique côté opérateur', async () => {
  const { code, data } = await issueCode(A);
  const body = command(code), before = await count('school');
  const opened = await api('new-person', 'POST', '/v1/school-openings', { body });
  expect(opened.statusCode, opened.body).toBe(201);
  const receipt = opened.json().data;
  expect(receipt).toMatchObject({ status: 'DRAFT', roles: ['ADMIN'], operationId: body.operationId });
  expect(await count('school')).toBe(before + 1);
  // La fiche du code porte maintenant l'école, le lien d'origine, le premier ADMIN et l'opérateur émetteur, une seule fois.
  const row = (await pool.query('SELECT * FROM drivy.platform_client WHERE id=$1', [data.client.id])).rows[0];
  expect(row).toMatchObject({ school_id: receipt.schoolId, link_source: 'OPENING_CODE', opened_via_link_id: data.codeId, first_admin_membership_id: receipt.membershipId,
    issued_by_operator_id: await operatorId(A), school_linked_by: null, commercial_state: 'NOT_CONFIGURED', version: 2 });
  expect(row.school_linked_at).toBeTruthy();
  expect((await pool.query('SELECT roles,school_id FROM drivy.membership WHERE id=$1', [receipt.membershipId])).rows[0]).toMatchObject({ roles: ['ADMIN'], school_id: receipt.schoolId });
  expect((await pool.query('SELECT client_id,status FROM drivy.school_opening_link WHERE id=$1', [data.codeId])).rows[0]).toMatchObject({ client_id: data.client.id, status: 'USED' });
  // Ce que voit l'opérateur : l'école, son contact, sa progression, le code utilisé ; jamais une personne, un dossier ni un trajet.
  const detail = await getClient(data.client.id);
  expect(detail).toMatchObject({ preparation: 'IN_PREPARATION', schoolId: receipt.schoolId, version: 2,
    school: { name: 'École de recette', status: 'DRAFT', contactEmail: 'school@example.invalid', contactPhone: null, setup: { step: 'IDENTITY', stepsDone: 0, stepsTotal: 6, completedAt: null } },
    link: { source: 'OPENING_CODE', issuedByName: 'Camille Exemple' } });
  expect(Object.keys(detail.school).sort()).toEqual(['contactEmail', 'contactPhone', 'name', 'setup', 'status']);
  expect(detail.codes[0]).toMatchObject({ id: data.codeId, state: 'USED', school: { id: receipt.schoolId, name: 'École de recette' } });
  expect(Object.keys(detail.codes[0].school).sort()).toEqual(['contactEmail', 'contactPhone', 'id', 'name', 'setup', 'status']);
  for (const hidden of ['Responsable de recette', 'Camille Administration', 'Alice', 'learner', 'trip', 'message']) expect(JSON.stringify(detail).includes(hidden), hidden).toBe(false);
  // Le code retrouve l'école : suivi du code, puis fiche par la recherche du nom de l'école.
  const byCode = (await api(A, 'GET', `/v1/platform/school-codes?clientId=${data.client.id}`)).json().data.items[0];
  expect(byCode).toMatchObject({ state: 'USED', school: { id: receipt.schoolId } }); expect(byCode.usedAt).toBeTruthy();
  expect((await api(A, 'GET', '/v1/platform/clients?q=recette')).json().data.items.map((item: { id: string }) => item.id)).toEqual([data.client.id]);
  expect((await api(A, 'GET', '/v1/platform/clients?q=school@example')).json().data.total).toBe(1);
  // La progression suit la mise en place de l'école, sans en montrer le contenu.
  await pool.query("UPDATE drivy.school_setup SET current_step='OFFERINGS',completed_steps=ARRAY['IDENTITY','ORGANISATION'] WHERE school_id=$1", [receipt.schoolId]);
  expect((await getClient(data.client.id)).school.setup).toMatchObject({ step: 'OFFERINGS', stepsDone: 2, stepsTotal: 6 });
  // Journal : l'événement système lie l'école à la fiche et au code, sans le code.
  const system = await journal("action='SCHOOL_OPENED_FROM_CODE'");
  expect(system).toHaveLength(1);
  expect(system[0]).toMatchObject({ actor_kind: 'SYSTEM', result: 'SUCCESS', school_id: receipt.schoolId, subject_type: 'PlatformClient', subject_id: data.client.id });
  expect(system[0].changes).toEqual({ linkId: data.codeId, issuedByOperatorId: await operatorId(A) });
  // Réponse perdue : le rejeu rend le même reçu, le reçu se relit sans le code, rien ne se double.
  const replay = await api('new-person', 'POST', '/v1/school-openings', { body });
  expect(replay.statusCode).toBe(201); expect(replay.json().data).toEqual(receipt);
  expect((await api('new-person', 'GET', `/v1/school-openings/operations/${body.operationId}`)).json().data).toEqual(receipt);
  expect((await api('someone-else', 'GET', `/v1/school-openings/operations/${body.operationId}`)).statusCode).toBe(404);
  // Redémarrage du service au milieu de la reprise : une nouvelle instance retrouve la même école avec la même identité.
  const restarted = buildApp({ pool, verifyToken, cursorSecret });
  try {
    const again = await openSchool(code, 'new-person', { schoolName: 'Nom ignoré à la reprise' }, restarted);
    expect(again.statusCode, again.body).toBe(201); expect(again.json().data.schoolId).toBe(receipt.schoolId);
    const me = await api('new-person', 'GET', '/v1/me', { target: restarted });
    expect(me.json().data.memberships.map((member: { schoolId: string }) => member.schoolId)).toContain(receipt.schoolId);
  } finally { await restarted.close(); }
  expect(await count('school')).toBe(before + 1);
  expect(await count('platform_client')).toBe(1); expect(await count('platform_client', 'school_id IS NOT NULL')).toBe(1);
  expect(await journal("action='SCHOOL_OPENED_FROM_CODE'")).toHaveLength(1);
  // Une autre identité ne reçoit ni l'école ni la fiche, et ne peut pas reprendre le code.
  const other = await openSchool(code, 'second-person');
  expect(other.statusCode).toBe(409); expect(other.json().code).toBe('OPENING_LINK_USED');
  for (const secret of [receipt.schoolId, data.client.id, 'École de recette', fiche.displayName]) expect(other.body.includes(secret), secret).toBe(false);
  expect(await count('school')).toBe(before + 1);
  // Un code utilisé ne se révoque pas, et la fiche reliée n'accepte plus de nouveau code.
  const usedRevoke = await revoke(A, data.codeId); expect(usedRevoke.statusCode).toBe(409); expect(usedRevoke.json().code).toBe('OPENING_LINK_USED');
  const more = await issueCode(A, { clientId: data.client.id, displayName: undefined });
  expect(more.response.statusCode).toBe(409); expect(more.response.json().code).toBe('CLIENT_SCHOOL_LINKED');
  // Préparation dérivée des faits de l'école : active, puis archivée, sans lien avec l'état commercial.
  await pool.query("UPDATE drivy.school SET status='ACTIVE' WHERE id=$1", [receipt.schoolId]);
  expect(await getClient(data.client.id)).toMatchObject({ preparation: 'ACTIVE', commercial: { state: 'NOT_CONFIGURED' } });
  await pool.query("UPDATE drivy.school SET status='ARCHIVED' WHERE id=$1", [receipt.schoolId]);
  expect((await getClient(data.client.id)).preparation).toBe('ARCHIVED');
});

test('code distribué avant ce lot : toujours valable, la fiche naît à l’ouverture, avec ou sans émetteur connu', async () => {
  // Lien long créé par l'ancienne route : aucune fiche ni libellé.
  const token = randomBytes(32).toString('base64url');
  const legacy = await api(A, 'POST', '/v1/operator/school-opening-links', { body: { operationId: randomUUID(), token } });
  expect(legacy.statusCode, legacy.body).toBe(201);
  expect((await pool.query('SELECT client_id,issued_by_operator_id FROM drivy.school_opening_link WHERE id=$1', [legacy.json().data.id])).rows[0]).toEqual({ client_id: null, issued_by_operator_id: await operatorId(A) });
  expect(await count('platform_client')).toBe(0);
  const opened = await openSchool(token, 'legacy-person');
  expect(opened.statusCode, opened.body).toBe(201);
  const row = (await pool.query('SELECT * FROM drivy.platform_client')).rows[0];
  expect(row).toMatchObject({ school_id: opened.json().data.schoolId, link_source: 'OPENING_CODE', opened_via_link_id: legacy.json().data.id, display_name: null,
    issued_by_operator_id: await operatorId(A), created_by: await operatorId(A) });
  expect((await pool.query('SELECT client_id FROM drivy.school_opening_link WHERE id=$1', [legacy.json().data.id])).rows[0].client_id).toBe(row.id);
  expect(await getClient(row.id)).toMatchObject({ preparation: 'IN_PREPARATION', displayName: null, link: { source: 'OPENING_CODE', issuedByName: 'Camille Exemple' } });
  expect(await journal("action='SCHOOL_OPENED_FROM_CODE'")).toHaveLength(1);
  // Code d'avant la traçabilité des émetteurs : même ouverture, émetteur inconnu.
  const oldToken = randomBytes(32).toString('base64url');
  const old = await api(A, 'POST', '/v1/operator/school-opening-links', { body: { operationId: randomUUID(), token: oldToken } });
  await pool.query('UPDATE drivy.school_opening_link SET issued_by_operator_id=NULL WHERE id=$1', [old.json().data.id]);
  const reopened = await openSchool(oldToken, 'old-person');
  expect(reopened.statusCode, reopened.body).toBe(201);
  const oldRow = (await pool.query('SELECT * FROM drivy.platform_client WHERE school_id=$1', [reopened.json().data.schoolId])).rows[0];
  expect(oldRow).toMatchObject({ issued_by_operator_id: null, created_by: null, link_source: 'OPENING_CODE' });
  expect((await getClient(oldRow.id)).link).toMatchObject({ source: 'OPENING_CODE', issuedByName: null });
  expect(await count('platform_client')).toBe(2);
  const listed = await api(A, 'GET', '/v1/platform/clients');
  expect(listed.json().data.total).toBe(2);
  // Rejeu des deux : aucune fiche en plus, aucune école en plus.
  const schools = await count('school');
  expect((await openSchool(token, 'legacy-person')).statusCode).toBe(201);
  expect(await count('school')).toBe(schools); expect(await count('platform_client')).toBe(2);
});

test('deux destinataires en concurrence sur un code : une seule école, une seule fiche liée, un seul premier ADMIN', async () => {
  const before = await count('school');
  for (let round = 0; round < 3; round += 1) {
    const { code, data } = await issueCode(A, { displayName: `Course ${round}` });
    const results = await Promise.all(['racer-one', 'racer-two'].map(subject => openSchool(code, subject)));
    expect(results.map(result => result.statusCode).sort(), results.map(result => result.body).join(' | ')).toEqual([201, 409]);
    const winner = results.find(result => result.statusCode === 201)!.json().data, loser = results.find(result => result.statusCode === 409)!;
    expect(loser.body.includes(winner.schoolId)).toBe(false);
    const row = (await pool.query('SELECT * FROM drivy.platform_client WHERE id=$1', [data.client.id])).rows[0];
    expect(row).toMatchObject({ school_id: winner.schoolId, first_admin_membership_id: winner.membershipId, opened_via_link_id: data.codeId });
    expect((await pool.query("SELECT count(*)::int AS n FROM drivy.membership WHERE school_id=$1 AND 'ADMIN'=ANY(roles)", [winner.schoolId])).rows[0].n).toBe(1);
  }
  expect(await count('school')).toBe(before + 3);
  expect(await count('platform_client', 'school_id IS NOT NULL')).toBe(3);
  expect(await count('school_opening_link', "status='USED'")).toBe(3);
  expect(await journal("action='SCHOOL_OPENED_FROM_CODE'")).toHaveLength(3);
  // Deux clics du même compte : un reçu identique et une seule liaison.
  const { code } = await issueCode(A, { displayName: 'Double clic' });
  const body = command(code);
  const both = await Promise.all([api('same-person', 'POST', '/v1/school-openings', { body }), api('same-person', 'POST', '/v1/school-openings', { body })]);
  expect(both.map(result => result.statusCode)).toEqual([201, 201]); expect(both[0]!.json().data).toEqual(both[1]!.json().data);
  expect(await count('school')).toBe(before + 4);
  expect(await count('platform_client', 'school_id IS NOT NULL')).toBe(4);
});

test('révocation et utilisation en course : un seul des deux l’emporte, jamais les deux', async () => {
  for (let round = 0; round < 4; round += 1) {
    const { code, data } = await issueCode(A, { displayName: `Course ${round}` });
    const [opening, revocation] = await Promise.all([openSchool(code, `person-${round}`), revoke(B, data.codeId)]);
    const opened = opening.statusCode === 201, revoked = revocation.statusCode === 200;
    expect(opened !== revoked, `${opening.statusCode} ${opening.body} / ${revocation.statusCode} ${revocation.body}`).toBe(true);
    const link = (await pool.query('SELECT status FROM drivy.school_opening_link WHERE id=$1', [data.codeId])).rows[0];
    expect(link.status).toBe(opened ? 'USED' : 'REVOKED');
    expect((await pool.query('SELECT school_id FROM drivy.platform_client WHERE id=$1', [data.client.id])).rows[0].school_id !== null).toBe(opened);
    if (opened) expect(revocation.json().code).toBe('OPENING_LINK_USED'); else expect(['OPENING_LINK_REVOKED', 'OPENING_LINK_USED']).toContain(opening.json().code);
  }
});

test('code expiré, révoqué ou utilisé par un autre compte : message utile sans fuite, aucune école créée', async () => {
  const before = await count('school');
  const expired = await issueCode(A);
  await pool.query("UPDATE drivy.school_opening_link SET created_at=now()-interval '9 days',expires_at=now()-interval '2 days' WHERE id=$1", [expired.data.codeId]);
  const refusedExpired = await openSchool(expired.code, 'late-person');
  expect(refusedExpired.json().code).toBe('OPENING_LINK_EXPIRED');
  const revoked = await issueCode(A, { displayName: 'Fiche révoquée' });
  expect((await revoke(A, revoked.data.codeId)).statusCode).toBe(200);
  const refusedRevoked = await openSchool(revoked.code, 'late-person');
  expect(refusedRevoked.json().code).toBe('OPENING_LINK_REVOKED');
  for (const refused of [refusedExpired, refusedRevoked]) {
    expect(refused.statusCode).toBeGreaterThanOrEqual(400);
    for (const secret of [expired.data.client.id, revoked.data.client.id, 'Auto-école des Lilas', 'Fiche révoquée', 'Camille Exemple']) expect(refused.body.includes(secret), secret).toBe(false);
  }
  expect(await count('school')).toBe(before); expect(await count('platform_client', 'school_id IS NOT NULL')).toBe(0);
  // Côté opérateur : états distincts, préparation inchangée, et un nouveau code redevient possible sur la même fiche.
  const detail = await getClient(expired.data.client.id);
  expect(detail).toMatchObject({ preparation: 'AWAITING_SCHOOL', latestCode: { state: 'EXPIRED' } }); expect(detail.codes[0].state).toBe('EXPIRED');
  expect((await getClient(revoked.data.client.id)).latestCode.state).toBe('REVOKED');
  expect((await api(A, 'GET', '/v1/platform/school-codes?state=EXPIRED')).json().data.items.map((item: { id: string }) => item.id)).toEqual([expired.data.codeId]);
  const renewed = await issueCode(A, { clientId: expired.data.client.id, displayName: undefined });
  expect(renewed.response.statusCode, renewed.response.body).toBe(201);
  expect(renewed.data.client.codes.map((item: { state: string }) => item.state).sort()).toEqual(['AVAILABLE', 'EXPIRED']);
  // Le nouveau code ouvre l'école de la même fiche ; l'ancien reste inutilisable.
  const opened = await openSchool(renewed.code, 'late-person');
  expect(opened.statusCode, opened.body).toBe(201);
  expect((await getClient(expired.data.client.id)).schoolId).toBe(opened.json().data.schoolId);
  expect((await openSchool(expired.code, 'other-person')).json().code).toBe('OPENING_LINK_EXPIRED');
  expect(await count('school')).toBe(before + 1);
  // Un autre compte reçoit le même refus sans rien apprendre de l'école ouverte.
  const taken = await openSchool(renewed.code, 'intruder');
  expect(taken.json().code).toBe('OPENING_LINK_USED');
  for (const secret of [opened.json().data.schoolId, 'École de recette', renewed.data.client.id]) expect(taken.body.includes(secret), secret).toBe(false);
  const preview = await api('intruder', 'POST', '/v1/school-openings/preview', { body: { token: renewed.code } });
  expect(preview.statusCode).toBe(409); expect(preview.body.includes(opened.json().data.schoolId)).toBe(false);
});

test('école pilote : rattachement explicite à une fiche, sans création, remise à zéro ni changement de ses données', async () => {
  const unattached = await api(A, 'GET', '/v1/platform/unattached-schools');
  expect(unattached.statusCode, unattached.body).toBe(200);
  const items = unattached.json().data.items as Array<Record<string, any>>;
  expect(items.map(item => item.id).sort()).toEqual([fixtureIds.schoolA, fixtureIds.schoolB].sort());
  expect(Object.keys(items[0]!).sort()).toEqual(['contactEmail', 'contactPhone', 'id', 'name', 'setup', 'status']);
  expect((await api(A, 'GET', '/v1/platform/unattached-schools?q=horizon')).json().data.items.map((item: { id: string }) => item.id)).toEqual([fixtureIds.schoolA]);
  expect((await api(A, 'GET', '/v1/platform/unattached-schools?q=100%25')).json().data.items).toEqual([]);
  const created = await createClient(A, { displayName: 'Horizon (pilote)' });
  const client = created.json().data;
  // Empreinte de toutes les tables hors plateforme avant et après : le rattachement n'écrit que la fiche.
  const fingerprint = async () => {
    const tables = (await pool.query<{ relname: string }>(`SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='drivy' AND c.relkind='r' AND c.relname NOT LIKE 'platform\\_%' AND c.relname<>'school_opening_link' ORDER BY 1`)).rows.map(row => row.relname);
    const result: Record<string, string | null> = {};
    for (const table of tables) result[table] = (await pool.query<{ digest: string | null }>(`SELECT md5(string_agg(t::text,'|' ORDER BY t::text)) AS digest FROM drivy."${table}" t`)).rows[0]!.digest;
    return result;
  };
  const beforeAccess = await api('demo-admin', 'GET', '/v1/me');
  expect(beforeAccess.statusCode).toBe(200);
  const before = await fingerprint();
  const attachBody = { operationId: randomUUID(), schoolId: fixtureIds.schoolA };
  const attached = await api(A, 'POST', `/v1/platform/clients/${client.id}/attach-school`, { body: attachBody, version: 1 });
  expect(attached.statusCode, attached.body).toBe(200);
  expect(attached.json().data).toMatchObject({ id: client.id, schoolId: fixtureIds.schoolA, preparation: 'ACTIVE', version: 2, link: { source: 'EXISTING_SCHOOL', issuedByName: null },
    school: { name: 'Auto-école Horizon · Démonstration', status: 'ACTIVE' }, commercial: { state: 'NOT_CONFIGURED', offer: null, dueDates: [] } });
  expect(await fingerprint()).toEqual(before);
  const afterAccess = await api('demo-admin', 'GET', '/v1/me');
  expect(afterAccess.statusCode).toBe(200);
  expect(afterAccess.json().data.memberships.map((member: { schoolId: string }) => member.schoolId).sort()).toEqual(beforeAccess.json().data.memberships.map((member: { schoolId: string }) => member.schoolId).sort());
  expect(await count('school')).toBe(2); expect(await count('school_opening_link')).toBe(0);
  const row = (await pool.query('SELECT * FROM drivy.platform_client WHERE id=$1', [client.id])).rows[0];
  expect(row).toMatchObject({ school_id: fixtureIds.schoolA, link_source: 'EXISTING_SCHOOL', school_linked_by: await operatorId(A), opened_via_link_id: null, first_admin_membership_id: null, commercial_state: 'NOT_CONFIGURED' });
  for (const hidden of ['Alice', 'Noé', 'Alex Moniteur', 'Camille Administration', 'Lou Monitrice']) expect(JSON.stringify(attached.json()).includes(hidden), hidden).toBe(false);
  // Rejeu identique, version périmée, école déjà reliée (à cette fiche ou à une autre), école inconnue.
  const replay = await api(A, 'POST', `/v1/platform/clients/${client.id}/attach-school`, { body: attachBody, version: 1 });
  expect(replay.statusCode).toBe(200); expect(replay.json().data.version).toBe(2);
  const another = (await createClient(A, { displayName: 'Autre fiche' })).json().data;
  const duplicate = await api(A, 'POST', `/v1/platform/clients/${another.id}/attach-school`, { body: { operationId: randomUUID(), schoolId: fixtureIds.schoolA }, version: 1 });
  expect(duplicate.statusCode).toBe(409); expect(duplicate.json().code).toBe('CLIENT_SCHOOL_ALREADY_LINKED');
  const second = await api(A, 'POST', `/v1/platform/clients/${client.id}/attach-school`, { body: { operationId: randomUUID(), schoolId: fixtureIds.schoolB }, version: 2 });
  expect(second.statusCode).toBe(409); expect(second.json().code).toBe('CLIENT_SCHOOL_LINKED');
  const stale = await api(A, 'POST', `/v1/platform/clients/${another.id}/attach-school`, { body: { operationId: randomUUID(), schoolId: fixtureIds.schoolB }, version: 5 });
  expect(stale.statusCode).toBe(412); expect(stale.json().code).toBe('VERSION_CONFLICT');
  expect((await api(A, 'POST', `/v1/platform/clients/${another.id}/attach-school`, { body: { operationId: randomUUID(), schoolId: randomUUID() }, version: 1 })).statusCode).toBe(404);
  expect((await api(A, 'POST', `/v1/platform/clients/${another.id}/attach-school`, { body: attachBody })).statusCode).toBe(428);
  // L'école reliée n'est plus proposée ; la fiche et son école se retrouvent par la recherche.
  expect((await api(A, 'GET', '/v1/platform/unattached-schools')).json().data.items.map((item: { id: string }) => item.id)).toEqual([fixtureIds.schoolB]);
  expect((await api(A, 'GET', '/v1/platform/clients?q=horizon')).json().data.items.map((item: { id: string }) => item.id)).toEqual([client.id]);
  expect((await api(A, 'GET', '/v1/platform/clients?preparation=ACTIVE')).json().data.total).toBe(1);
  expect((await api(A, 'GET', '/v1/platform/clients?preparation=AWAITING_SCHOOL')).json().data.total).toBe(1);
  // Journal : le rattachement porte l'école ; les refus de conflit la portent aussi.
  const attach = await journal("action='ATTACH_EXISTING_SCHOOL'");
  expect(attach.filter(entry => entry.result === 'SUCCESS')).toHaveLength(1);
  expect(attach.find(entry => entry.result === 'SUCCESS')).toMatchObject({ school_id: fixtureIds.schoolA, subject_id: client.id, actor_name: 'Camille Exemple' });
  expect(attach.filter(entry => entry.result === 'REFUSED').map(entry => entry.reason_code).sort()).toEqual(['CLIENT_SCHOOL_ALREADY_LINKED', 'CLIENT_SCHOOL_LINKED', 'VERSION_CONFLICT']);
  expect(attach.filter(entry => entry.result === 'REFUSED').every(entry => entry.school_id !== null)).toBe(true);
  // Une fiche créée directement avec son école, et l'ordre inverse : un code encore utilisable interdit le rattachement.
  const direct = await createClient(A, { displayName: 'Rivage (pilote)', schoolId: fixtureIds.schoolB });
  expect(direct.statusCode, direct.body).toBe(201); expect(direct.json().data).toMatchObject({ schoolId: fixtureIds.schoolB, preparation: 'ACTIVE', link: { source: 'EXISTING_SCHOOL' } });
  expect((await api(A, 'GET', '/v1/platform/unattached-schools')).json().data.items).toEqual([]);
});

test('un code encore utilisable réserve l’école de la fiche : rattacher une école existante est refusé jusqu’à sa révocation', async () => {
  const { data } = await issueCode(A);
  const refused = await api(A, 'POST', `/v1/platform/clients/${data.client.id}/attach-school`, { body: { operationId: randomUUID(), schoolId: fixtureIds.schoolA }, version: 1 });
  expect(refused.statusCode, refused.body).toBe(409); expect(refused.json().code).toBe('CLIENT_CODE_PENDING');
  expect((await getClient(data.client.id)).schoolId).toBeNull();
  expect((await journal("action='ATTACH_EXISTING_SCHOOL'")).map(entry => [entry.result, entry.reason_code])).toEqual([['REFUSED', 'CLIENT_CODE_PENDING']]);
  expect((await revoke(A, data.codeId)).statusCode).toBe(200);
  const attached = await api(A, 'POST', `/v1/platform/clients/${data.client.id}/attach-school`, { body: { operationId: randomUUID(), schoolId: fixtureIds.schoolA }, version: 1 });
  expect(attached.statusCode, attached.body).toBe(200);
  expect(attached.json().data).toMatchObject({ schoolId: fixtureIds.schoolA, preparation: 'ACTIVE' });
  expect(attached.json().data.codes.map((item: { state: string }) => item.state)).toEqual(['REVOKED']);
});

test('annuaire : pagination stable au-delà de 100 fiches, recherche, filtres et curseur lié à la demande', async () => {
  const operator = await operatorId(A);
  await pool.query(`INSERT INTO drivy.platform_client(id,display_name,created_by,created_at,updated_at)
    SELECT gen_random_uuid(),'Client '||lpad(g::text,3,'0'),$1,timestamptz '2026-01-01 00:00:00+00'+make_interval(secs=>(g/3)),timestamptz '2026-01-01 00:00:00+00'+make_interval(secs=>(g/3))
    FROM generate_series(1,130) g`, [operator]);
  await pool.query(`INSERT INTO drivy.platform_client(id,display_name,created_by) VALUES(gen_random_uuid(),'Remise 100%',$1),(gen_random_uuid(),'a_b',$1),(gen_random_uuid(),'axb',$1)`, [operator]);
  // Deux écoles pilotes déjà rattachées (la garde de la base réserve la liaison à un opérateur relu : on les insère déjà liées).
  await pool.query("UPDATE drivy.school SET status='DRAFT' WHERE id=$1", [fixtureIds.schoolB]);
  await pool.query(`INSERT INTO drivy.platform_client(id,display_name,created_by,school_id,link_source,school_linked_at,school_linked_by) VALUES
    (gen_random_uuid(),'Pilote actif',$1,$2,'EXISTING_SCHOOL',now(),$1),(gen_random_uuid(),'Pilote en préparation',$1,$3,'EXISTING_SCHOOL',now(),$1)`, [operator, fixtureIds.schoolA, fixtureIds.schoolB]);
  const collect = async (query: string, limit: number) => {
    const ids: string[] = []; let cursor: string | null = null, total: number | null = null, pages = 0;
    do {
      const response = await api(A, 'GET', `/v1/platform/clients?limit=${limit}${query}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`);
      expect(response.statusCode, response.body).toBe(200);
      const page = response.json().data; ids.push(...page.items.map((item: { id: string }) => item.id)); cursor = page.nextCursor; total = total ?? page.total; pages += 1;
      expect(page.total).toBe(total);
    } while (cursor && pages < 40);
    return { ids, total, pages };
  };
  for (const limit of [100, 40, 7]) {
    const { ids, total, pages } = await collect('', limit);
    expect(total, `limit ${limit}`).toBe(135); expect(ids.length, `limit ${limit}`).toBe(135); expect(new Set(ids).size, `limit ${limit}`).toBe(135);
    expect(pages).toBe(Math.ceil(135 / limit));
  }
  const all = (await collect('', 100)).ids;
  const expected = (await pool.query<{ id: string }>('SELECT id FROM drivy.platform_client ORDER BY created_at DESC,id DESC')).rows.map(row => row.id);
  expect(all).toEqual(expected);
  expect((await api(A, 'GET', '/v1/platform/clients?limit=101')).statusCode).toBe(400);
  // Recherche : sous-chaîne sans casse, caractères spéciaux littéraux.
  expect((await collect('&q=client%2005', 5)).total).toBe(10);
  expect((await collect('&q=CLIENT%20130', 5)).ids).toHaveLength(1);
  expect((await api(A, 'GET', '/v1/platform/clients?q=100%25')).json().data.items.map((item: { displayName: string }) => item.displayName)).toEqual(['Remise 100%']);
  expect((await api(A, 'GET', '/v1/platform/clients?q=a_b')).json().data.items.map((item: { displayName: string }) => item.displayName)).toEqual(['a_b']);
  expect((await api(A, 'GET', '/v1/platform/clients?q=introuvable')).json().data).toEqual({ items: [], total: 0, nextCursor: null });
  // Filtres de préparation, combinés à la recherche et à la pagination.
  expect((await collect('&preparation=ACTIVE', 3)).total).toBe(1);
  expect((await collect('&preparation=AWAITING_SCHOOL', 50)).total).toBe(133);
  expect((await collect('&preparation=IN_PREPARATION', 50)).total).toBe(1);
  expect((await collect('&preparation=ARCHIVED', 50)).total).toBe(0);
  expect((await api(A, 'GET', '/v1/platform/clients?preparation=ACTIVE&q=pilote')).json().data.items.map((item: { displayName: string }) => item.displayName)).toEqual(['Pilote actif']);
  expect((await api(A, 'GET', '/v1/platform/clients?preparation=ACTIVE&q=client')).json().data.total).toBe(0);
  expect((await api(A, 'GET', '/v1/platform/clients?preparation=IN_PREPARATION&q=pilote')).json().data.items.map((item: { displayName: string }) => item.displayName)).toEqual(['Pilote en préparation']);
  expect((await api(A, 'GET', '/v1/platform/clients?preparation=INCONNU')).statusCode).toBe(400);
  // Un curseur ne vaut que pour la demande et l'opérateur qui l'ont produit.
  const first = (await api(A, 'GET', '/v1/platform/clients?limit=10')).json().data;
  expect(first.nextCursor).toBeTruthy();
  for (const [subject, query] of [[A, 'limit=10&q=client'], [A, 'limit=20'], [B, 'limit=10']] as const) {
    const refused = await api(subject, 'GET', `/v1/platform/clients?${query}&cursor=${encodeURIComponent(first.nextCursor)}`);
    expect(refused.statusCode, `${subject} ${query}`).toBe(400); expect(refused.json().code).toBe('INVALID_CURSOR');
  }
  expect((await api(A, 'GET', '/v1/platform/clients?cursor=n-importe-quoi')).json().code).toBe('INVALID_CURSOR');
  // Même mécanique pour les codes : plus de cent, états filtrables, aucun doublon ni saut.
  const client = (await pool.query<{ id: string }>("SELECT id FROM drivy.platform_client WHERE display_name='Client 002'")).rows[0]!.id;
  await pool.query(`INSERT INTO drivy.school_opening_link(id,token_hash,reserved_school_id,reserved_membership_id,created_by_issuer,created_by_subject,create_operation_id,create_hash,created_at,expires_at,client_id,issued_by_operator_id)
    SELECT gen_random_uuid(),encode(sha256(convert_to('t'||g,'UTF8')),'hex'),gen_random_uuid(),gen_random_uuid(),$1,$2,gen_random_uuid(),encode(sha256(convert_to('h'||g,'UTF8')),'hex'),
      CASE WHEN g%4=0 THEN now()-interval '9 days' ELSE now()-make_interval(secs=>g) END,CASE WHEN g%4=0 THEN now()-interval '2 days' ELSE now()+interval '5 days' END,$3,$4
    FROM generate_series(1,120) g`, [issuer, A, client, operator]);
  const codes: string[] = []; let cursor: string | null = null, total: number | null = null;
  do {
    const response = await api(A, 'GET', `/v1/platform/school-codes?limit=50${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`);
    expect(response.statusCode, response.body).toBe(200);
    const page = response.json().data; codes.push(...page.items.map((item: { id: string }) => item.id)); cursor = page.nextCursor; total = page.total;
  } while (cursor);
  expect(total).toBe(120); expect(codes.length).toBe(120); expect(new Set(codes).size).toBe(120);
  expect((await api(A, 'GET', '/v1/platform/school-codes?state=EXPIRED&limit=100')).json().data.total).toBe(30);
  expect((await api(A, 'GET', '/v1/platform/school-codes?state=AVAILABLE&limit=100')).json().data.total).toBe(90);
  const forClient = (await api(A, 'GET', `/v1/platform/school-codes?clientId=${client}&limit=100`)).json().data;
  expect(forClient.total).toBe(120); expect(forClient.items).toHaveLength(100); expect(forClient.nextCursor).toBeTruthy();
  expect((await api(A, 'GET', `/v1/platform/school-codes?clientId=${randomUUID()}&limit=100`)).json().data).toEqual({ items: [], total: 0, nextCursor: null });
});

test('la base garde ses garde-fous quel que soit le service : rôle applicatif, fonctions à projection fixe, liaison immuable', async () => {
  const mine = (await createClient(A, { displayName: 'Garde-fous' })).json().data;
  const linked = (await createClient(A, { displayName: 'Liée', schoolId: fixtureIds.schoolA })).json().data;
  const [opA, opB] = [await operatorId(A), await operatorId(B)];
  // Lecture : un opérateur lit les fiches, un compte scolaire ou inconnu n'en voit aucune ; nul ne lit les tables scolaires.
  expect((await asApp(A, 'SELECT id FROM drivy.platform_client')).rowCount).toBe(2);
  for (const subject of ['demo-admin', 'demo-alice', 'stranger']) expect((await asApp(subject, 'SELECT id FROM drivy.platform_client')).rowCount, subject).toBe(0);
  for (const table of ['school', 'person', 'identity_link', 'membership']) expect((await asApp(A, `SELECT 1 FROM drivy.${table}`, [], { operator: true })).rowCount, table).toBe(0);
  // Les trois fonctions de lecture exigent un opérateur relu en base et n'exposent que leur projection.
  const calls = ['SELECT * FROM drivy.platform_client_overview(NULL,NULL,NULL,NULL,NULL,10)', 'SELECT * FROM drivy.platform_code_overview(NULL,NULL,NULL,NULL,NULL,10)',
    'SELECT * FROM drivy.platform_unattached_schools(NULL,10)'];
  for (const sql of calls) {
    for (const subject of ['demo-admin', 'stranger']) expect((await asApp(subject, sql)).error?.code, `${subject} ${sql}`).toBe('42501');
    expect((await asApp(A, sql)).error, sql).toBeUndefined();
  }
  const overview = await asApp(A, 'SELECT item FROM drivy.platform_client_overview($1,NULL,NULL,NULL,NULL,10)', [linked.id]);
  expect(Object.keys(overview.rows[0]!.item.school).sort()).toEqual(['contact_email', 'contact_phone', 'name', 'setup_completed_at', 'setup_done', 'setup_saved_at', 'setup_step', 'status']);
  // Écriture : ni suppression, ni état commercial, ni version, ni fiche au nom d'un autre, ni école imposée à la création.
  expect((await asApp(A, 'DELETE FROM drivy.platform_client')).error?.code).toBe('42501');
  expect((await asApp(A, "UPDATE drivy.platform_client SET commercial_state='ACTIVE'")).error?.code).toBe('42501');
  expect((await asApp(A, 'UPDATE drivy.platform_client SET version=99')).error?.code).toBe('42501');
  expect((await asApp(A, 'UPDATE drivy.platform_client SET created_by=$1', [opB])).error?.code).toBe('42501');
  expect((await asApp('stranger', "UPDATE drivy.platform_client SET display_name='x'")).rowCount).toBe(0);
  const insert = 'INSERT INTO drivy.platform_client(id,display_name,created_by) VALUES(gen_random_uuid(),$1,$2)';
  expect((await asApp(A, insert, ['Au nom de Jean', opB])).error?.code).toBe('42501');
  expect((await asApp('stranger', insert, ['Intrus', opA])).error?.code).toBe('42501');
  expect((await asApp(A, insert, ['Légitime', opA])).error).toBeUndefined();
  expect((await asApp(A, 'INSERT INTO drivy.platform_client(id,created_by,school_id) VALUES(gen_random_uuid(),$1,$2)', [opA, fixtureIds.schoolB])).error?.code).toBe('42501');
  // Une fois reliée, l'école, le premier ADMIN et l'émetteur ne changent plus, ni par un opérateur ni par le propriétaire.
  expect((await asApp(A, 'UPDATE drivy.platform_client SET school_id=$2 WHERE id=$1', [linked.id, fixtureIds.schoolB])).error?.code).toBe('23514');
  expect((await asApp(A, 'UPDATE drivy.platform_client SET school_id=NULL,link_source=NULL,school_linked_at=NULL,school_linked_by=NULL WHERE id=$1', [linked.id])).error?.code).toBe('23514');
  expect((await asApp(A, "UPDATE drivy.platform_client SET display_name='Renommée',updated_by=$2 WHERE id=$1", [linked.id, opA])).error).toBeUndefined();
  await expect(pool.query('DELETE FROM drivy.platform_client WHERE id=$1', [linked.id])).rejects.toMatchObject({ code: '23514' });
  await expect(pool.query("UPDATE drivy.platform_client SET created_at=now() WHERE id=$1", [mine.id])).rejects.toMatchObject({ code: '23514' });
  await expect(pool.query("UPDATE drivy.platform_client SET commercial_state='SUSPENDED' WHERE id=$1", [mine.id])).rejects.toMatchObject({ code: '23514' });
  // Rattacher une école existante se fait au nom de l'opérateur connecté, pas d'un collègue.
  const attach = 'UPDATE drivy.platform_client SET school_id=$2,link_source=\'EXISTING_SCHOOL\',school_linked_at=now(),school_linked_by=$3,updated_by=$4 WHERE id=$1';
  expect((await asApp(A, attach, [mine.id, fixtureIds.schoolB, opB, opA])).error?.code).toBe('23514');
  expect((await asApp(A, attach, [mine.id, fixtureIds.schoolB, opA, opB])).error?.code).toBe('42501');
  expect((await asApp(A, attach, [mine.id, fixtureIds.schoolB, opA, opA])).error).toBeUndefined();
  // Le lien d'ouverture : le service ne change ni la fiche rattachée, ni l'émetteur après coup.
  const { data } = await issueCode(A, { displayName: 'Lien' });
  // Les codes ne se lisent que par un opérateur relu en base ET dans le contexte d'ouverture ; un compte scolaire n'en voit aucun.
  expect((await asApp(A, 'SELECT 1 FROM drivy.school_opening_link')).rowCount).toBe(0);
  expect((await asApp('demo-admin', 'SELECT 1 FROM drivy.school_opening_link', [], { operator: true })).rowCount).toBe(0);
  expect((await asApp(A, 'SELECT 1 FROM drivy.school_opening_link', [], { operator: true })).rowCount).toBe(1);
  expect((await asApp(A, 'UPDATE drivy.school_opening_link SET client_id=NULL WHERE id=$1', [data.codeId], { operator: true })).error?.code).toBe('42501');
  expect((await asApp(A, 'UPDATE drivy.school_opening_link SET issued_by_operator_id=$2 WHERE id=$1', [data.codeId, opB], { operator: true })).error?.code).toBe('42501');
  const forged = 'INSERT INTO drivy.school_opening_link(id,token_hash,reserved_school_id,reserved_membership_id,created_by_issuer,created_by_subject,create_operation_id,create_hash,expires_at,issued_by_operator_id) VALUES(gen_random_uuid(),$1,gen_random_uuid(),gen_random_uuid(),$2,$3,gen_random_uuid(),$1,now()+interval \'1 day\',$4)';
  const hash = 'a'.repeat(64);
  expect((await asApp(A, forged, [hash, issuer, A, opB], { operator: true })).error?.code).toBe('42501');
  expect((await asApp(A, forged, [hash, issuer, A, opA], { operator: true })).error).toBeUndefined();
});

test('les tables de la plateforme et les liaisons restent sous RLS forcée, sans élargir les politiques scolaires', async () => {
  const rls = await pool.query<{ relname: string; relrowsecurity: boolean; relforcerowsecurity: boolean }>(
    "SELECT c.relname::text AS relname,relrowsecurity,relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND relkind='r' AND c.relname IN('platform_client','school_opening_link') ORDER BY 1");
  expect(rls.rows.map(row => row.relname)).toEqual(['platform_client', 'school_opening_link']);
  for (const row of rls.rows) expect([row.relrowsecurity, row.relforcerowsecurity], row.relname).toEqual([true, true]);
  const openFunctions = await pool.query<{ proname: string; acl: string | null }>(`SELECT p.proname::text AS proname,p.proacl::text AS acl FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='drivy' AND p.proname IN('platform_client_overview','platform_code_overview','platform_unattached_schools','platform_client_guard','platform_client_opened') ORDER BY 1`);
  expect(openFunctions.rows).toHaveLength(5);
  for (const row of openFunctions.rows) expect(/(^|[{,])=X/.test(row.acl ?? ''), `${row.proname} exécutable par PUBLIC`).toBe(false);
});
