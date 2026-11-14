import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { buildApp } from '../src/app.js';
import type { Identity } from '../src/auth.js';
import { moduleCodes } from '../src/entitlements-model.js';
import { ApiError } from '../src/errors.js';
import { fixtureIds as id, seedFixtures } from '../scripts/fixtures.js';
import { freshDatabase, issuer, prepareSchool, seedPlatformOperator } from './support/harness.js';

/**
 * R01-T03 (#455) sur PostgreSQL réelle : catalogue de modules, offres, attribution avec date d'effet, ajustements par école, droits relus
 * au serveur sur les écritures de la messagerie et des cours collectifs, transitions et garde-fous de la base.
 * Écrit sans être exécuté (règle du porteur : aucun test avant la fin de l'epic). Jeu d'essai synthétique ; aucune identité ni école réelle.
 * Jeton de recette : `Bearer <sujet>` ; les sujets `demo-*` viennent du jeu d'essai de l'API, `op-a` et `op-b` sont des opérateurs de plateforme.
 */
let pool: Pool, app: ReturnType<typeof buildApp>;
const A = 'op-a', B = 'op-b';
const verifyToken = async (header: string | undefined): Promise<Identity> => {
  if (!header?.startsWith('Bearer ')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  return { issuer, subject: header.slice(7) };
};
const people: Record<string, string> = { 'demo-admin': id.admin, 'demo-instructor': id.instructor, 'demo-alice': id.alice, 'demo-bob': id.bob };
const devices: Record<string, string> = { 'demo-admin': 'DEVICEG0001', 'demo-instructor': 'DEVICEA0001', 'demo-alice': 'DEVICEB0001', 'demo-bob': 'DEVICEC0001' };

beforeAll(async () => {
  pool = await freshDatabase();
  app = buildApp({ pool, verifyToken, cursorSecret: 'platform-offers-synthetic-secret-32-characters', messaging: { mode: 'qualification', schoolIds: [id.schoolA] } });
});
beforeEach(async () => {
  // Base remise à l'état de départ : jeu d'essai de l'API, école préparée, deux opérateurs, aucune fiche, offre ni attribution.
  await pool.query(`TRUNCATE drivy.person, drivy.school, drivy.platform_operator, drivy.platform_operation, drivy.platform_audit_event,
    drivy.platform_operator_invitation, drivy.platform_offer, drivy.platform_offer_assignment, drivy.platform_module_adjustment CASCADE`);
  await seedFixtures(pool, issuer);
  await seedPlatformOperator(pool, A, { displayName: 'Camille Exemple' });
  await seedPlatformOperator(pool, B, { displayName: 'Jean Exemple' });
  for (const [subject, device] of Object.entries(devices))
    await pool.query('INSERT INTO drivy.messaging_device(school_id,person_id,device_id,created_by_issuer,created_by_subject) VALUES($1,$2,$3,$4,$5)', [id.schoolA, people[subject], device, issuer, 'demo']);
  await prepareSchool(pool);
});
afterAll(async () => { await app?.close(); await pool?.end(); });

type Method = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
interface Options { body?: Record<string, unknown>; version?: number | null; headers?: Record<string, string> }
interface Reply { statusCode: number; body: string; json: () => any; headers: Record<string, unknown> }
const call = (subject: string | null, method: Method, url: string, options: Options = {}) => app.inject({
  method, url, headers: {
    ...(subject ? { authorization: `Bearer ${subject}` } : {}),
    ...(options.body?.operationId ? { 'idempotency-key': String(options.body.operationId) } : {}),
    ...(options.version ? { 'if-match': `"${options.version}"` } : {}), ...options.headers,
  },
  ...(options.body ? { payload: options.body } : {}),
}) as unknown as Promise<Reply>;
const schoolPath = (target: string) => `/v1/schools/${id.schoolA}${target}`;
const school = (subject: string, method: Method, target: string, options: Options = {}) => call(subject, method, schoolPath(target), options);

function expectProblem(response: Reply, status: number, code: string) {
  expect(response.statusCode, response.body).toBe(status);
  expect(response.json()).toMatchObject({ status, code, type: `urn:drivy:problem:${code.toLowerCase()}` });
  expect(Object.keys(response.json()).sort()).toEqual(['code', 'requestId', 'status', 'title', 'type']);
}
/** Le refus d'un module non accordé ne dit rien du commercial : ni tarif, ni essai, ni montant. */
function expectNotEntitled(response: Reply) {
  expectProblem(response, 403, 'MODULE_NOT_ENTITLED');
  expect(response.body).not.toMatch(/tarif|prix|essai|échéance|CHF|€/i);
}
const count = async (table: string, where = 'true') => Number((await pool.query<{ n: string }>(`SELECT count(*) AS n FROM drivy.${table} WHERE ${where}`)).rows[0]!.n);
const journal = async (where = 'true') => (await pool.query(`SELECT * FROM drivy.platform_audit_event WHERE ${where} ORDER BY occurred_at,id`)).rows;
const wait = (ms: number) => new Promise<void>(done => setTimeout(done, ms));

const fiche = { displayName: 'Auto-école des Lilas', contactName: 'Marie Exemple', contactEmail: 'marie@example.invalid', contactPhone: '+41 79 000 00 00',
  billingStreet: 'Rue Exemple 1', billingPostalCode: '1000', billingCity: 'Lausanne', billingCountry: 'Suisse', internalNotes: 'Relancer en janvier' };
const uniqueName = (label: string) => `${label} ${randomUUID().slice(0, 8)}`;
async function createOffer(name: string, modules: string[], as = A) {
  const response = await call(as, 'POST', '/v1/platform/offers', { body: { operationId: randomUUID(), name, modules } });
  expect(response.statusCode, response.body).toBe(201);
  return response.json().data as { id: string; name: string; modules: string[]; status: string; version: number; schoolsInForce: number };
}
/** Fiche d'école cliente reliée à l'école de recette : seule une fiche reliée porte des droits sur une école réelle. */
async function schoolClient(schoolId: string = id.schoolA) {
  const created = await call(A, 'POST', '/v1/platform/clients', { body: { operationId: randomUUID(), ...fiche, schoolId } });
  expect(created.statusCode, created.body).toBe(201);
  return created.json().data as { id: string };
}
async function rights(clientId: string, as = A) {
  const response = await call(as, 'GET', `/v1/platform/clients/${clientId}/entitlements`);
  expect(response.statusCode, response.body).toBe(200);
  return response.json().data;
}
const assign = (clientId: string, offerId: string, version: number, extra: Record<string, unknown> = {}, as = A) =>
  call(as, 'POST', `/v1/platform/clients/${clientId}/assignments`, { body: { operationId: randomUUID(), offerId, ...extra }, version });
async function assignNow(clientId: string, offerId: string, as = A) {
  const response = await assign(clientId, offerId, (await rights(clientId, as)).version, {}, as);
  expect(response.statusCode, response.body).toBe(201);
  return response.json().data;
}
const adjust = async (clientId: string, moduleCode: string, effect: 'GRANT' | 'REVOKE', reason: string, as = A) =>
  call(as, 'POST', `/v1/platform/clients/${clientId}/adjustments`, { body: { operationId: randomUUID(), moduleCode, effect, reason }, version: (await rights(clientId, as)).version });
/** Offre restreinte attribuée tout de suite à l'école de recette : le moyen simple d'obtenir « module non accordé ». */
async function restrictTo(modules: string[], label = 'Offre restreinte') {
  const client = await schoolClient();
  const offer = await createOffer(uniqueName(label), modules);
  await assignNow(client.id, offer.id);
  return { client, offer };
}
const entitledIn = (data: { modules: Array<{ code: string; entitled: boolean }> }, code: string) => data.modules.find(item => item.code === code)?.entitled;
const schoolView = async (subject = 'demo-alice', schoolId: string = id.schoolA) => call(subject, 'GET', `/v1/schools/${schoolId}/entitlements`);

/** Requête sous le rôle applicatif avec l'identité donnée : ce que la base laisse voir ou faire, quel que soit le service. */
async function asApp(subject: string, sql: string, params: unknown[] = []) {
  const db = await pool.connect();
  try {
    await db.query('BEGIN'); await db.query('SET LOCAL ROLE drivy_app');
    await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true)", [issuer, subject]);
    const result = await db.query(sql, params);
    return { rows: result.rows as Array<Record<string, any>>, rowCount: result.rowCount ?? 0, error: undefined as (Error & { code?: string }) | undefined };
  } catch (error) { return { rows: [], rowCount: 0, error: error as Error & { code?: string } }; }
  finally { await db.query('ROLLBACK').catch(() => undefined); db.release(); }
}
const ownerError = async (sql: string, params: unknown[] = []) => { try { await pool.query(sql, params); return undefined; } catch (error) { return error as Error & { code?: string }; } };

// ---------------------------------------------------------------------------------------------------------------------------------
// Messagerie et cours : appels de recette (en-têtes de messagerie, octets chiffrés opaques, séries publiées).
// ---------------------------------------------------------------------------------------------------------------------------------
const messaging = `/v1/schools/${id.schoolA}/messaging`;
const mcall = (subject: string, method: Method, target: string, payload?: unknown) => {
  const headers = { authorization: `Bearer ${subject}`, 'x-drivy-expected-person-id': people[subject]!, 'x-drivy-expected-access-epoch': '1', 'x-drivy-device-id': devices[subject]! };
  if (payload === undefined) return app.inject({ method, url: `${messaging}${target}`, headers }) as unknown as Promise<Reply>;
  if (Buffer.isBuffer(payload)) return app.inject({ method, url: `${messaging}${target}`, headers: { ...headers, 'content-type': 'application/octet-stream' }, payload }) as unknown as Promise<Reply>;
  return app.inject({ method, url: `${messaging}${target}`, headers: { ...headers, 'content-type': 'application/json' }, payload: JSON.stringify(payload) }) as unknown as Promise<Reply>;
};
const cipherBytes = (size: number, seed = 7) => Buffer.from(Array.from({ length: size }, (_value, index) => (index * 31 + seed) % 256));
const messageBody = (extra: Record<string, unknown> = {}) => ({ clientMessageId: randomUUID(), expectedMembersEpoch: 0, ciphertext: { scheme: 'synthetic', keyId: 'fixture', payload: 'AAAA' }, ...extra });
const send = (subject: string, conversationId: string, body: Record<string, unknown>) => mcall(subject, 'POST', `/conversations/${conversationId}/messages`, body);
const messageRows = async () => count('messaging_message', `school_id='${id.schoolA}'`);
const thumbsUp = encodeURIComponent('👍');
async function openPrivate() {
  const opened = await mcall('demo-instructor', 'PUT', `/private/${id.alice}`);
  expect(opened.statusCode, opened.body).toBe(200);
  return opened.json().data.conversationId as string;
}
/** Une conversation déjà vivante : messages, sondage voté, réaction, épingle et deux médias (un joint, un seulement déposé). */
async function livingConversation() {
  const conversationId = await openPrivate();
  const first = await send('demo-instructor', conversationId, messageBody());
  expect(first.statusCode, first.body).toBe(200);
  const poll = await send('demo-alice', conversationId, messageBody({ poll: { optionCount: 3, multiple: false } }));
  expect(poll.statusCode, poll.body).toBe(200);
  const firstId = first.json().data.id as string, pollId = poll.json().data.id as string;
  const path = (messageId: string) => `/conversations/${conversationId}/messages/${messageId}`;
  expect((await mcall('demo-alice', 'PUT', `${path(firstId)}/reactions/${thumbsUp}`)).statusCode).toBe(200);
  expect((await mcall('demo-alice', 'PUT', `${path(firstId)}/pin`)).statusCode).toBe(200);
  expect((await mcall('demo-alice', 'PUT', `${path(pollId)}/poll/votes`, { optionIndexes: [0] })).statusCode).toBe(200);
  const attachedMedia = randomUUID(), bytes = cipherBytes(1024), pendingMedia = randomUUID();
  expect((await mcall('demo-instructor', 'PUT', `/conversations/${conversationId}/media/${attachedMedia}`, bytes)).statusCode).toBe(200);
  const withMedia = await send('demo-instructor', conversationId, messageBody({ media: { mediaId: attachedMedia, byteSize: bytes.length } }));
  expect(withMedia.statusCode, withMedia.body).toBe(200);
  expect((await mcall('demo-instructor', 'PUT', `/conversations/${conversationId}/media/${pendingMedia}`, cipherBytes(512, 3))).statusCode).toBe(200);
  return { conversationId, firstId, pollId, path, attachedMedia, pendingMedia, bytes };
}

const at = (offset: number, hourUtc: number) => { const date = new Date(); date.setUTCDate(date.getUTCDate() + offset); date.setUTCHours(hourUtc, 0, 0, 0); return date.toISOString(); };
async function publishedSeries(startOffset = 20) {
  const type = await school('demo-admin', 'POST', '/course-types', { body: { operationId: randomUUID(), title: `Type ${randomUUID()}`, description: '' } });
  expect(type.statusCode, type.body).toBe(201);
  const draft = await school('demo-admin', 'POST', '/course-series', { body: { operationId: randomUUID(), typeId: type.json().data.id, title: 'Cours de recette', description: '',
    location: 'Salle', conditions: '', teachingLanguage: null, responsibleMembershipId: id.adminMember, capacity: 10, minParticipants: null, timeZone: 'Europe/Zurich',
    occurrences: [{ startsAt: at(startOffset, 8), endsAt: at(startOffset, 11), instructorMembershipId: id.otherInstructorMember, attendanceRequired: true }] } });
  expect(draft.statusCode, draft.body).toBe(201);
  const published = await school('demo-admin', 'POST', `/course-series/${draft.json().data.id}/publish`, { body: { operationId: randomUUID() }, version: draft.json().data.version });
  expect(published.statusCode, published.body).toBe(200);
  return { typeId: type.json().data.id as string, seriesId: published.json().data.id as string };
}
const enroll = (seriesId: string, subject: string) => school(subject, 'POST', `/course-series/${seriesId}/enroll`, { body: { operationId: randomUUID() } });

// ---------------------------------------------------------------------------------------------------------------------------------
describe('catalogue et porte opérateur', () => {
  it('le catalogue ne présente que les modules livrés, identiques dans l’API, la base et le code', async () => {
    const response = await call(A, 'GET', '/v1/platform/modules');
    expect(response.statusCode, response.body).toBe(200);
    const items = response.json().data.items as Array<{ code: string; sortOrder: number }>;
    expect(items.map(item => item.code)).toEqual([...moduleCodes]);
    expect(items.map(item => item.sortOrder)).toEqual([1, 2]);
    expect((await pool.query('SELECT code FROM drivy.platform_module ORDER BY sort_order')).rows.map(row => row.code)).toEqual([...moduleCodes]);
  });

  it('un module inconnu n’entre ni dans une offre ni dans un ajustement', async () => {
    const response = await call(A, 'POST', '/v1/platform/offers', { body: { operationId: randomUUID(), name: uniqueName('Offre inconnue'), modules: ['PAYROLL'] } });
    expectProblem(response, 400, 'INVALID_REQUEST');
    expect(await count('platform_offer')).toBe(0);
    const client = await schoolClient();
    await assignNow(client.id, (await createOffer(uniqueName('Offre'), ['MESSAGING'])).id);
    const adjustment = await adjust(client.id, 'PAYROLL', 'GRANT', 'Module inexistant');
    expectProblem(adjustment, 400, 'INVALID_REQUEST');
    expect(await count('platform_module_adjustment')).toBe(0);
  });

  it('seul un opérateur actif entre : tout autre compte reçoit 403, un appel anonyme 401, et rien n’est écrit', async () => {
    await seedPlatformOperator(pool, 'op-former');
    await pool.query("UPDATE drivy.platform_operator SET status='REVOKED',revoked_at=now(),revoked_by=(SELECT id FROM drivy.platform_operator WHERE subject=$1) WHERE subject='op-former'", [A]);
    const offer = await createOffer(uniqueName('Offre porte'), ['MESSAGING']);
    const client = await schoolClient();
    const version = (await rights(client.id)).version as number;
    const someId = randomUUID();
    const routes: Array<[string, Method, string, Options]> = [
      ['catalogue', 'GET', '/v1/platform/modules', {}],
      ['offres', 'GET', '/v1/platform/offers', {}],
      ['droits', 'GET', `/v1/platform/clients/${client.id}/entitlements`, {}],
      ['aperçu', 'GET', `/v1/platform/clients/${client.id}/assignment-preview?offerId=${offer.id}`, {}],
      ['créer', 'POST', '/v1/platform/offers', { body: { operationId: randomUUID(), name: uniqueName('Offre fantôme'), modules: ['MESSAGING'] } }],
      ['modifier', 'PATCH', `/v1/platform/offers/${offer.id}`, { body: { operationId: randomUUID(), name: uniqueName('Autre nom') }, version: 1 }],
      ['archiver', 'POST', `/v1/platform/offers/${offer.id}/archive`, { body: { operationId: randomUUID() }, version: 1 }],
      ['restaurer', 'POST', `/v1/platform/offers/${offer.id}/restore`, { body: { operationId: randomUUID() }, version: 1 }],
      ['attribuer', 'POST', `/v1/platform/clients/${client.id}/assignments`, { body: { operationId: randomUUID(), offerId: offer.id }, version }],
      ['annuler', 'POST', `/v1/platform/clients/${client.id}/assignments/${someId}/cancel`, { body: { operationId: randomUUID() }, version }],
      ['ajuster', 'POST', `/v1/platform/clients/${client.id}/adjustments`, { body: { operationId: randomUUID(), moduleCode: 'MESSAGING', effect: 'GRANT', reason: 'Geste commercial' }, version }],
      ['lever', 'POST', `/v1/platform/clients/${client.id}/adjustments/${someId}/lift`, { body: { operationId: randomUUID(), reason: 'Fin du geste' }, version }],
    ];
    const before = { offers: await count('platform_offer'), assignments: await count('platform_offer_assignment'), adjustments: await count('platform_module_adjustment'), journal: (await journal()).length };
    for (const subject of ['demo-admin', 'demo-alice', 'op-former', 'op-stranger'])
      for (const [label, method, url, options] of routes) {
        const response = await call(subject, method, url, options);
        expect(response.statusCode, `${subject} ${label} : ${response.body}`).toBe(403);
        expect(response.json().code, `${subject} ${label}`).toBe('PLATFORM_OPERATOR_REQUIRED');
      }
    for (const [label, method, url, options] of routes) expect((await call(null, method, url, options)).statusCode, `anonyme ${label}`).toBe(401);
    expect({ offers: await count('platform_offer'), assignments: await count('platform_offer_assignment'), adjustments: await count('platform_module_adjustment'), journal: (await journal()).length }).toEqual(before);
  });
});

describe('offres : création, modification, archivage', () => {
  it('crée une offre, rejoue sans doublon, refuse un nom pris et un autre contenu sous la même opération', async () => {
    const body = { operationId: randomUUID(), name: '  Offre Essentiel ', modules: ['COLLECTIVE_COURSES', 'MESSAGING'] };
    const created = await call(A, 'POST', '/v1/platform/offers', { body });
    expect(created.statusCode, created.body).toBe(201);
    const offer = created.json().data;
    expect(offer).toMatchObject({ name: 'Offre Essentiel', modules: ['MESSAGING', 'COLLECTIVE_COURSES'], status: 'ACTIVE', version: 1, archivedAt: null, schoolsInForce: 0 });
    expect(Object.keys(offer).sort()).toEqual(['archivedAt', 'createdAt', 'id', 'modules', 'name', 'schoolsInForce', 'status', 'updatedAt', 'version']);
    const replay = await call(A, 'POST', '/v1/platform/offers', { body });
    expect([200, 201]).toContain(replay.statusCode);
    expect(replay.json().data.id).toBe(offer.id);
    expect(await count('platform_offer')).toBe(1);
    expectProblem(await call(A, 'POST', '/v1/platform/offers', { body: { ...body, name: 'Autre contenu' } }), 409, 'IDEMPOTENCY_MISMATCH');
    expectProblem(await call(B, 'POST', '/v1/platform/offers', { body: { operationId: randomUUID(), name: 'offre essentiel', modules: ['MESSAGING'] } }), 409, 'OFFER_NAME_TAKEN');
    expect(await count('platform_offer')).toBe(1);
    expect((await journal("action='CREATE_OFFER' AND result='REFUSED'")).map(entry => entry.reason_code)).toEqual(['OFFER_NAME_TAKEN']);
    // Une offre peut ne contenir aucun module (le socle seul), jamais deux fois le même.
    expect((await createOffer(uniqueName('Socle seul'), [])).modules).toEqual([]);
    expectProblem(await call(A, 'POST', '/v1/platform/offers', { body: { operationId: randomUUID(), name: uniqueName('Doublon'), modules: ['MESSAGING', 'MESSAGING'] } }), 400, 'INVALID_REQUEST');
  });

  it('modifie sous version attendue, refuse une version périmée ou absente, archive puis restaure', async () => {
    const offer = await createOffer(uniqueName('Offre à vivre'), ['MESSAGING']);
    const updated = await call(A, 'PATCH', `/v1/platform/offers/${offer.id}`, { body: { operationId: randomUUID(), modules: ['MESSAGING', 'COLLECTIVE_COURSES'] }, version: 1 });
    expect(updated.statusCode, updated.body).toBe(200);
    expect(updated.json().data).toMatchObject({ version: 2, modules: ['MESSAGING', 'COLLECTIVE_COURSES'] });
    expectProblem(await call(B, 'PATCH', `/v1/platform/offers/${offer.id}`, { body: { operationId: randomUUID(), name: uniqueName('Trop tard') }, version: 1 }), 412, 'VERSION_CONFLICT');
    expect((await call(B, 'PATCH', `/v1/platform/offers/${offer.id}`, { body: { operationId: randomUUID(), name: uniqueName('Sans version') } })).statusCode).toBe(428);
    expectProblem(await call(A, 'PATCH', `/v1/platform/offers/${offer.id}`, { body: { operationId: randomUUID() }, version: 2 }), 400, 'INVALID_REQUEST');
    expect((await pool.query('SELECT version FROM drivy.platform_offer WHERE id=$1', [offer.id])).rows[0]!.version).toBe(2);
    expectProblem(await call(A, 'POST', `/v1/platform/offers/${offer.id}/restore`, { body: { operationId: randomUUID() }, version: 2 }), 409, 'OFFER_NOT_ARCHIVED');
    const archived = await call(A, 'POST', `/v1/platform/offers/${offer.id}/archive`, { body: { operationId: randomUUID() }, version: 2 });
    expect(archived.statusCode, archived.body).toBe(200);
    expect(archived.json().data).toMatchObject({ status: 'ARCHIVED', version: 3 });
    expect(archived.json().data.archivedAt).not.toBeNull();
    expectProblem(await call(A, 'PATCH', `/v1/platform/offers/${offer.id}`, { body: { operationId: randomUUID(), name: uniqueName('Figée') }, version: 3 }), 409, 'OFFER_ARCHIVED');
    expectProblem(await call(A, 'POST', `/v1/platform/offers/${offer.id}/archive`, { body: { operationId: randomUUID() }, version: 3 }), 409, 'OFFER_ARCHIVED');
    const listed = async (status: string) => (await call(A, 'GET', `/v1/platform/offers?status=${status}`)).json().data.items.map((item: { id: string }) => item.id);
    expect(await listed('ARCHIVED')).toEqual([offer.id]);
    expect(await listed('ACTIVE')).not.toContain(offer.id);
    const restored = await call(A, 'POST', `/v1/platform/offers/${offer.id}/restore`, { body: { operationId: randomUUID() }, version: 3 });
    expect(restored.statusCode, restored.body).toBe(200);
    expect(restored.json().data).toMatchObject({ status: 'ACTIVE', version: 4, archivedAt: null });
    expect((await journal("result='SUCCESS'")).map(entry => entry.action)).toEqual(expect.arrayContaining(['CREATE_OFFER', 'UPDATE_OFFER', 'ARCHIVE_OFFER', 'RESTORE_OFFER']));
    expect(JSON.stringify(await journal())).not.toMatch(/token|secret|password|passphrase|authorization/i);
  });

  it('une offre archivée n’est plus attribuable, mais les écoles qui l’ont déjà gardent leurs droits', async () => {
    const { client, offer } = await restrictTo(['MESSAGING']);
    const archived = await call(A, 'POST', `/v1/platform/offers/${offer.id}/archive`, { body: { operationId: randomUUID() }, version: 1 });
    expect(archived.statusCode, archived.body).toBe(200);
    expect(archived.json().data.schoolsInForce).toBe(1);
    const view = await rights(client.id);
    expect(view.state).toBe('OFFER_ACTIVE');
    expect(view.offer.offerId).toBe(offer.id);
    expect(entitledIn(view, 'MESSAGING')).toBe(true);
    expectProblem(await assign(client.id, offer.id, view.version), 409, 'OFFER_ARCHIVED');
    expectProblem(await call(A, 'GET', `/v1/platform/clients/${client.id}/assignment-preview?offerId=${offer.id}`), 409, 'OFFER_ARCHIVED');
  });
});

describe('attribution à une école, date d’effet et aperçu', () => {
  it('une école sans offre garde son périmètre ; l’aperçu ne compte que des volumes et n’écrit rien', async () => {
    const client = await schoolClient();
    const view = await rights(client.id);
    expect(view).toMatchObject({ state: 'NOT_CONFIGURED', offer: null, scheduledOffer: null, nextChangeAt: null });
    expect(view.modules.map((item: { code: string; entitled: boolean }) => [item.code, item.entitled])).toEqual([['MESSAGING', true], ['COLLECTIVE_COURSES', true]]);
    const { seriesId } = await publishedSeries();
    expect((await enroll(seriesId, 'demo-alice')).statusCode).toBe(201);
    await openPrivate();
    const light = await createOffer(uniqueName('Offre légère'), ['MESSAGING']);
    const before = { assignments: await count('platform_offer_assignment'), journal: (await journal()).length, commercial: (await pool.query('SELECT commercial_state FROM drivy.platform_client WHERE id=$1', [client.id])).rows[0] };
    const preview = await call(A, 'GET', `/v1/platform/clients/${client.id}/assignment-preview?offerId=${light.id}`);
    expect(preview.statusCode, preview.body).toBe(200);
    const data = preview.json().data;
    expect(data).toMatchObject({ immediate: true, effectiveAt: null, replacesScheduled: null, endingAdjustments: [], version: view.version });
    expect(data.modules).toEqual([
      { code: 'MESSAGING', before: true, after: true, kind: 'KEEPS', existing: null },
      { code: 'COLLECTIVE_COURSES', before: true, after: false, kind: 'LOSES', existing: { publishedSeries: 1, activeEnrollments: 1, upcomingSessions: 1 } },
    ]);
    // Aucun nom, aucune adresse, aucun message : des nombres seulement.
    expect(preview.body).not.toMatch(/Alice|Exemple|@|Cours de recette/);
    expect({ assignments: await count('platform_offer_assignment'), journal: (await journal()).length, commercial: (await pool.query('SELECT commercial_state FROM drivy.platform_client WHERE id=$1', [client.id])).rows[0] }).toEqual(before);
    expect((await assign(client.id, light.id, view.version)).statusCode).toBe(201);
    expect((await pool.query('SELECT commercial_state FROM drivy.platform_client WHERE id=$1', [client.id])).rows[0]).toEqual(before.commercial);
  });

  it('attribue tout de suite, rejoue sans doublon, refuse une version périmée et journalise le refus', async () => {
    const client = await schoolClient();
    const offer = await createOffer(uniqueName('Offre complète'), ['MESSAGING', 'COLLECTIVE_COURSES']);
    const version = (await rights(client.id)).version as number;
    const body = { operationId: randomUUID(), offerId: offer.id };
    const first = await call(A, 'POST', `/v1/platform/clients/${client.id}/assignments`, { body, version });
    expect(first.statusCode, first.body).toBe(201);
    const view = first.json().data;
    expect(view).toMatchObject({ state: 'OFFER_ACTIVE', scheduledOffer: null, version: version + 1 });
    expect(view.offer).toMatchObject({ offerId: offer.id, name: offer.name, modules: ['MESSAGING', 'COLLECTIVE_COURSES'] });
    expect(view.assignments).toHaveLength(1);
    expect(view.assignments[0]).toMatchObject({ phase: 'IN_FORCE', offerName: offer.name, createdByName: 'Camille Exemple' });
    const replay = await call(A, 'POST', `/v1/platform/clients/${client.id}/assignments`, { body, version });
    expect([200, 201]).toContain(replay.statusCode);
    expect(await count('platform_offer_assignment')).toBe(1);
    expectProblem(await assign(client.id, offer.id, version, {}, B), 412, 'VERSION_CONFLICT');
    expect((await assign(client.id, offer.id, version, {}, B)).statusCode).toBe(412);
    expect(await count('platform_offer_assignment')).toBe(1);
    expect((await journal("action='ASSIGN_OFFER' AND result='REFUSED'")).map(entry => entry.reason_code)).toContain('VERSION_CONFLICT');
    expect((await journal("action='ASSIGN_OFFER' AND result='SUCCESS'"))).toHaveLength(1);
    const listed = (await call(A, 'GET', '/v1/platform/offers')).json().data.items.find((item: { id: string }) => item.id === offer.id);
    expect(listed.schoolsInForce).toBe(1);
  });

  it('modifier une offre ne change jamais une école déjà attribuée : l’attribution garde son instantané', async () => {
    const { client, offer } = await restrictTo(['MESSAGING']);
    const updated = await call(A, 'PATCH', `/v1/platform/offers/${offer.id}`, { body: { operationId: randomUUID(), modules: ['MESSAGING', 'COLLECTIVE_COURSES'] }, version: 1 });
    expect(updated.statusCode, updated.body).toBe(200);
    const view = await rights(client.id);
    expect(view.offer.modules).toEqual(['MESSAGING']);
    expect(entitledIn(view, 'COLLECTIVE_COURSES')).toBe(false);
    expect(entitledIn((await schoolView()).json().data, 'COLLECTIVE_COURSES')).toBe(false);
  });

  it('refuse une date d’effet passée ou trop lointaine, programme, remplace la programmée et l’annule', async () => {
    const full = await createOffer(uniqueName('Offre complète'), ['MESSAGING', 'COLLECTIVE_COURSES']);
    const light = await createOffer(uniqueName('Offre légère'), ['MESSAGING']);
    const client = await schoolClient();
    await assignNow(client.id, full.id);
    const day = 86_400_000;
    const version = async () => (await rights(client.id)).version as number;
    expectProblem(await assign(client.id, light.id, await version(), { effectiveAt: new Date(Date.now() - 60_000).toISOString() }), 409, 'EFFECTIVE_DATE_PAST');
    expectProblem(await assign(client.id, light.id, await version(), { effectiveAt: new Date(Date.now() + 400 * day).toISOString() }), 400, 'INVALID_REQUEST');
    expect(await count('platform_offer_assignment')).toBe(1);
    const firstDate = new Date(Date.now() + 10 * day).toISOString(), secondDate = new Date(Date.now() + 20 * day).toISOString();
    const preview = await call(A, 'GET', `/v1/platform/clients/${client.id}/assignment-preview?offerId=${light.id}&effectiveAt=${encodeURIComponent(firstDate)}`);
    expect(preview.json().data).toMatchObject({ immediate: false, replacesScheduled: null });
    const scheduled = await assign(client.id, light.id, await version(), { effectiveAt: firstDate });
    expect(scheduled.statusCode, scheduled.body).toBe(201);
    expect(scheduled.json().data.scheduledOffer).toMatchObject({ offerId: light.id });
    expect(Date.parse(scheduled.json().data.nextChangeAt)).toBe(Date.parse(firstDate));
    // Rien ne change avant la date : l'école garde l'offre complète.
    expect(entitledIn((await schoolView()).json().data, 'COLLECTIVE_COURSES')).toBe(true);
    const replacing = await call(A, 'GET', `/v1/platform/clients/${client.id}/assignment-preview?offerId=${full.id}&effectiveAt=${encodeURIComponent(secondDate)}`);
    expect(replacing.json().data.replacesScheduled).toMatchObject({ offerId: light.id });
    const second = await assign(client.id, full.id, await version(), { effectiveAt: secondDate });
    expect(second.statusCode, second.body).toBe(201);
    const phases = (second.json().data.assignments as Array<{ offerId: string; phase: string }>).map(item => [item.offerId, item.phase]);
    expect(phases).toEqual(expect.arrayContaining([[light.id, 'CANCELLED'], [full.id, 'SCHEDULED'], [full.id, 'IN_FORCE']]));
    expect(await count('platform_offer_assignment', "status='ACTIVE'")).toBe(2);
    const pending = (second.json().data.assignments as Array<{ id: string; phase: string }>).find(item => item.phase === 'SCHEDULED')!;
    const cancelled = await call(A, 'POST', `/v1/platform/clients/${client.id}/assignments/${pending.id}/cancel`, { body: { operationId: randomUUID() }, version: await version() });
    expect(cancelled.statusCode, cancelled.body).toBe(200);
    expect(cancelled.json().data.scheduledOffer).toBeNull();
    expect(cancelled.json().data.nextChangeAt).toBeNull();
    expectProblem(await call(A, 'POST', `/v1/platform/clients/${client.id}/assignments/${pending.id}/cancel`, { body: { operationId: randomUUID() }, version: await version() }), 409, 'ASSIGNMENT_NOT_PENDING');
    // L'attribution en vigueur ne s'annule pas, on en attribue une autre ; et rien n'a été supprimé.
    const inForce = (await rights(client.id)).assignments.find((item: { phase: string }) => item.phase === 'IN_FORCE');
    expectProblem(await call(A, 'POST', `/v1/platform/clients/${client.id}/assignments/${inForce.id}/cancel`, { body: { operationId: randomUUID() }, version: await version() }), 409, 'ASSIGNMENT_NOT_PENDING');
    expect(await count('platform_offer_assignment')).toBe(3);
  });

  it('une attribution programmée prend effet seule à sa date, sans action de l’école ni de l’équipe', async () => {
    const full = await createOffer(uniqueName('Offre complète'), ['MESSAGING', 'COLLECTIVE_COURSES']);
    const light = await createOffer(uniqueName('Offre légère'), ['MESSAGING']);
    const client = await schoolClient();
    await assignNow(client.id, full.id);
    const { seriesId } = await publishedSeries();
    const enrolled = await enroll(seriesId, 'demo-alice');
    expect(enrolled.statusCode, enrolled.body).toBe(201);
    const scheduled = await assign(client.id, light.id, (await rights(client.id)).version, { effectiveAt: new Date(Date.now() + 3000).toISOString() });
    expect(scheduled.statusCode, scheduled.body).toBe(201);
    expect(entitledIn((await schoolView()).json().data, 'COLLECTIVE_COURSES')).toBe(true);
    await wait(4000);
    const view = await rights(client.id);
    expect(view.offer.offerId).toBe(light.id);
    expect(view.scheduledOffer).toBeNull();
    expect(view.assignments.map((item: { phase: string }) => item.phase).sort()).toEqual(['IN_FORCE', 'SUPERSEDED']);
    const entitlements = (await schoolView()).json().data;
    expect(entitledIn(entitlements, 'MESSAGING')).toBe(true);
    expect(entitledIn(entitlements, 'COLLECTIVE_COURSES')).toBe(false);
    // Le nouvel usage est refusé dès la date atteinte ; l'inscription déjà prise reste lisible.
    expectNotEntitled(await enroll(seriesId, 'demo-bob'));
    const me = await school('demo-alice', 'GET', `/course-series/${seriesId}/me`);
    expect(me.statusCode, me.body).toBe(200);
    expect(me.json().data.me.state).toBe('ENROLLED');
  }, 30_000);
});

describe('ajustement par école : motif, auteur, historique', () => {
  it('exige une offre en vigueur, refuse l’inutile et le doublon, accorde, retire, lève et refait sans rien effacer', async () => {
    const client = await schoolClient();
    expectProblem(await adjust(client.id, 'MESSAGING', 'REVOKE', 'Essai sans offre'), 409, 'ADJUSTMENT_REQUIRES_OFFER');
    const light = await createOffer(uniqueName('Offre légère'), ['MESSAGING']);
    await assignNow(client.id, light.id);
    expectProblem(await adjust(client.id, 'MESSAGING', 'GRANT', 'Déjà dans l’offre'), 409, 'ADJUSTMENT_NO_EFFECT');
    expectProblem(await adjust(client.id, 'COLLECTIVE_COURSES', 'REVOKE', 'Déjà hors de l’offre'), 409, 'ADJUSTMENT_NO_EFFECT');
    expectProblem(await adjust(client.id, 'COLLECTIVE_COURSES', 'GRANT', 'ok'), 400, 'INVALID_REQUEST');
    expect(await count('platform_module_adjustment')).toBe(0);
    const reason = 'Geste commercial convenu avec la direction';
    const granted = await adjust(client.id, 'COLLECTIVE_COURSES', 'GRANT', reason);
    expect(granted.statusCode, granted.body).toBe(201);
    const courses = granted.json().data.modules.find((item: { code: string }) => item.code === 'COLLECTIVE_COURSES');
    expect(courses).toMatchObject({ inOffer: false, entitled: true });
    expect(courses.adjustment).toMatchObject({ effect: 'GRANT', reason, createdByName: 'Camille Exemple' });
    expect(entitledIn((await schoolView()).json().data, 'COLLECTIVE_COURSES')).toBe(true);
    expectProblem(await adjust(client.id, 'COLLECTIVE_COURSES', 'GRANT', 'Deuxième geste'), 409, 'ADJUSTMENT_ACTIVE');
    const adjustmentId = granted.json().data.adjustments[0].id as string;
    const lifted = await call(B, 'POST', `/v1/platform/clients/${client.id}/adjustments/${adjustmentId}/lift`, { body: { operationId: randomUUID(), reason: 'Fin de la période convenue' }, version: (await rights(client.id)).version });
    expect(lifted.statusCode, lifted.body).toBe(200);
    expect(entitledIn(lifted.json().data, 'COLLECTIVE_COURSES')).toBe(false);
    expect(lifted.json().data.adjustments[0]).toMatchObject({ phase: 'LIFTED', liftedByName: 'Jean Exemple', liftReason: 'Fin de la période convenue', createdByName: 'Camille Exemple' });
    expectProblem(await call(A, 'POST', `/v1/platform/clients/${client.id}/adjustments/${adjustmentId}/lift`, { body: { operationId: randomUUID(), reason: 'Deuxième levée' }, version: (await rights(client.id)).version }), 409, 'ADJUSTMENT_NOT_ACTIVE');
    expect(entitledIn((await schoolView()).json().data, 'COLLECTIVE_COURSES')).toBe(false);
    // Un retrait ciblé : la messagerie sort de l'école tandis que le reste de l'offre demeure.
    const full = await createOffer(uniqueName('Offre complète'), ['MESSAGING', 'COLLECTIVE_COURSES']);
    await assignNow(client.id, full.id);
    const revoked = await adjust(client.id, 'MESSAGING', 'REVOKE', 'Suspension convenue de la messagerie');
    expect(revoked.statusCode, revoked.body).toBe(201);
    const afterRevoke = (await schoolView()).json().data;
    expect([entitledIn(afterRevoke, 'MESSAGING'), entitledIn(afterRevoke, 'COLLECTIVE_COURSES')]).toEqual([false, true]);
    // Une nouvelle attribution met fin à l'ajustement sans le supprimer : il reste dans l'historique.
    await assignNow(client.id, light.id);
    const ended = await rights(client.id);
    expect(ended.adjustments.map((item: { phase: string }) => item.phase).sort()).toEqual(['ENDED', 'LIFTED']);
    expect(entitledIn(ended, 'MESSAGING')).toBe(true);
    expect(await count('platform_module_adjustment')).toBe(2);
    expect(await count('platform_offer_assignment')).toBe(3);
    // Le journal garde l'identité et l'effet de chaque geste, jamais le motif écrit.
    expect((await journal("result='SUCCESS' AND action IN ('ADJUST_SCHOOL_MODULE','LIFT_MODULE_ADJUSTMENT')")).map(entry => entry.action)).toEqual(['ADJUST_SCHOOL_MODULE', 'LIFT_MODULE_ADJUSTMENT', 'ADJUST_SCHOOL_MODULE']);
    const everything = JSON.stringify(await journal());
    for (const secretReason of [reason, 'Fin de la période convenue', 'Suspension convenue de la messagerie']) expect(everything).not.toContain(secretReason);
  });
});

describe('vue de l’école : les droits seuls', () => {
  it('rend l’état et les modules sans offre, motif ni auteur ; ETag ; no-store ; réservée aux membres', async () => {
    const { client } = await restrictTo(['MESSAGING', 'COLLECTIVE_COURSES']);
    expect((await adjust(client.id, 'MESSAGING', 'REVOKE', 'Suspension convenue de la messagerie')).statusCode).toBe(201);
    const operatorView = await rights(client.id);
    for (const subject of ['demo-alice', 'demo-instructor', 'demo-admin']) {
      const response = await schoolView(subject);
      expect(response.statusCode, response.body).toBe(200);
      const data = response.json().data;
      expect(Object.keys(data).sort()).toEqual(['computedAt', 'modules', 'nextChangeAt', 'state', 'version']);
      expect(data).toMatchObject({ state: 'OFFER_ACTIVE', version: operatorView.version, nextChangeAt: null });
      expect(data.modules).toEqual([{ code: 'MESSAGING', entitled: false }, { code: 'COLLECTIVE_COURSES', entitled: true }]);
      expect(response.headers['cache-control']).toBe('no-store');
      expect(response.headers.etag).toBe(`"${data.version}"`);
      expect(response.body).not.toMatch(/offer|offre|reason|motif|Suspension|Camille|createdBy|adjust|assignment/i);
    }
    expectProblem(await schoolView('demo-foreign'), 403, 'ACCESS_DENIED');
    expect((await call(null, 'GET', `/v1/schools/${id.schoolA}/entitlements`)).statusCode).toBe(401);
  });

  it('une école sans fiche garde son périmètre d’aujourd’hui, et une autre école n’est pas touchée', async () => {
    await restrictTo(['MESSAGING']);
    const other = await schoolView('demo-foreign', id.schoolB);
    expect(other.statusCode, other.body).toBe(200);
    expect(other.json().data).toMatchObject({ state: 'NOT_CONFIGURED', nextChangeAt: null });
    expect(other.json().data.modules).toEqual([{ code: 'MESSAGING', entitled: true }, { code: 'COLLECTIVE_COURSES', entitled: true }]);
    expect(entitledIn((await schoolView()).json().data, 'COLLECTIVE_COURSES')).toBe(false);
  });

  it('l’école ne peut ni s’accorder un module ni lire les droits d’une autre', async () => {
    const { client } = await restrictTo(['MESSAGING']);
    const attempts: Array<[Method, string, Options]> = [
      ['POST', `/v1/platform/clients/${client.id}/adjustments`, { body: { operationId: randomUUID(), moduleCode: 'COLLECTIVE_COURSES', effect: 'GRANT', reason: 'Je me l’accorde' }, version: 2 }],
      ['POST', `/v1/platform/clients/${client.id}/assignments`, { body: { operationId: randomUUID(), offerId: randomUUID() }, version: 2 }],
      ['GET', `/v1/platform/clients/${client.id}/entitlements`, {}],
    ];
    for (const [method, url, options] of attempts) expectProblem(await call('demo-admin', method, url, options), 403, 'PLATFORM_OPERATOR_REQUIRED');
    expect(entitledIn((await schoolView('demo-admin')).json().data, 'COLLECTIVE_COURSES')).toBe(false);
    expect(await count('platform_module_adjustment')).toBe(0);
  });
});

describe('messagerie : le droit est relu au serveur sur tout nouvel usage', () => {
  it('sans le module : plus rien de nouveau, mais l’historique et les engagements en cours restent', async () => {
    const live = await livingConversation();
    const rowsBefore = await messageRows();
    const media = await pool.query("SELECT count(*)::int AS n FROM drivy.messaging_media WHERE school_id=$1", [id.schoolA]);
    const replayBody = messageBody();
    expect((await send('demo-instructor', live.conversationId, replayBody)).statusCode).toBe(200);
    const rowsWithReplayTarget = await messageRows();
    await restrictTo(['COLLECTIVE_COURSES'], 'Offre sans messagerie');

    // Refusé : tout nouvel usage, avec un refus uniforme et sans écriture.
    expectNotEntitled(await send('demo-instructor', live.conversationId, messageBody()));
    expectNotEntitled(await send('demo-alice', live.conversationId, messageBody({ poll: { optionCount: 3, multiple: false } })));
    expectNotEntitled(await mcall('demo-instructor', 'PUT', `${live.path(live.firstId)}/reactions/${encodeURIComponent('❤️')}`));
    expectNotEntitled(await mcall('demo-instructor', 'PUT', `${live.path(live.firstId)}/pin`));
    expectNotEntitled(await mcall('demo-alice', 'DELETE', `${live.path(live.firstId)}/pin`));
    expectNotEntitled(await mcall('demo-alice', 'PUT', `${live.path(live.pollId)}/poll/votes`, { optionIndexes: [1] }));
    expectNotEntitled(await mcall('demo-alice', 'POST', `${live.path(live.pollId)}/poll/close`));
    expectNotEntitled(await mcall('demo-instructor', 'PUT', `/conversations/${live.conversationId}/media/${randomUUID()}`, cipherBytes(256, 5)));
    expect(await messageRows()).toBe(rowsWithReplayTarget);
    expect((await pool.query('SELECT count(*)::int AS n FROM drivy.messaging_media WHERE school_id=$1', [id.schoolA])).rows[0]!.n).toBe(media.rows[0]!.n);

    // Permis : lire l'historique (désormais en lecture seule), rejouer un envoi déjà accepté, retirer, quitter, annuler, télécharger.
    const history = await mcall('demo-alice', 'GET', `/conversations/${live.conversationId}/messages`);
    expect(history.statusCode, history.body).toBe(200);
    expect(history.json().data.items).toHaveLength(rowsWithReplayTarget);
    expect(history.json().data.access.canWrite).toBe(false);
    const replay = await send('demo-instructor', live.conversationId, replayBody);
    expect(replay.statusCode, replay.body).toBe(200);
    expect(await messageRows()).toBe(rowsWithReplayTarget);
    expect((await mcall('demo-alice', 'DELETE', `${live.path(live.firstId)}/reactions/${thumbsUp}`)).statusCode).toBe(200);
    expect((await mcall('demo-alice', 'PUT', `${live.path(live.pollId)}/poll/votes`, { optionIndexes: [] })).statusCode).toBe(200);
    expect((await mcall('demo-alice', 'PUT', `/conversations/${live.conversationId}/read-state`, { lastReadSequence: 1 })).statusCode).toBe(200);
    const downloaded = await mcall('demo-alice', 'GET', `/conversations/${live.conversationId}/media/${live.attachedMedia}`);
    expect(downloaded.statusCode, downloaded.body).toBe(200);
    expect((await mcall('demo-instructor', 'DELETE', `/conversations/${live.conversationId}/media/${live.pendingMedia}`)).statusCode).toBe(200);
    expect((await mcall('demo-instructor', 'DELETE', `${live.path(live.firstId)}?scope=me`)).statusCode).toBe(200);
    expect(rowsBefore).toBeGreaterThan(0);
  }, 30_000);

  it('sans le module, aucune conversation nouvelle ; une conversation déjà ouverte se retrouve en lecture', async () => {
    const conversationId = await openPrivate();
    expect((await send('demo-instructor', conversationId, messageBody())).statusCode).toBe(200);
    await restrictTo(['COLLECTIVE_COURSES'], 'Offre sans messagerie');
    const again = await mcall('demo-instructor', 'PUT', `/private/${id.alice}`);
    expect(again.statusCode, again.body).toBe(200);
    expect(again.json().data.conversationId).toBe(conversationId);
    const general = await mcall('demo-admin', 'PUT', '/general');
    expectNotEntitled(general);
    expect(await count('messaging_conversation', "kind='GENERAL'")).toBe(0);
    const listed = await mcall('demo-instructor', 'GET', '/conversations');
    expect(listed.statusCode, listed.body).toBe(200);
  });

  it('retrait puis réactivation sans perte : la même conversation, le même historique, l’envoi reprend', async () => {
    const live = await livingConversation();
    const rows = await messageRows();
    const { client } = await restrictTo(['COLLECTIVE_COURSES'], 'Offre sans messagerie');
    expectNotEntitled(await send('demo-instructor', live.conversationId, messageBody()));
    const full = await createOffer(uniqueName('Offre complète'), ['MESSAGING', 'COLLECTIVE_COURSES']);
    await assignNow(client.id, full.id);
    expect(entitledIn((await schoolView()).json().data, 'MESSAGING')).toBe(true);
    const resumed = await send('demo-instructor', live.conversationId, messageBody());
    expect(resumed.statusCode, resumed.body).toBe(200);
    expect(await messageRows()).toBe(rows + 1);
    const history = await mcall('demo-alice', 'GET', `/conversations/${live.conversationId}/messages`);
    expect(history.json().data.items).toHaveLength(rows + 1);
    expect(history.json().data.access.canWrite).toBe(true);
    expect((await mcall('demo-instructor', 'PUT', `/private/${id.alice}`)).json().data.conversationId).toBe(live.conversationId);
    // Rien n'a été supprimé par les deux changements d'offre : trois attributions, deux en historique.
    expect(await count('platform_offer_assignment')).toBe(2);
    expect((await rights(client.id)).assignments.map((item: { phase: string }) => item.phase).sort()).toEqual(['IN_FORCE', 'SUPERSEDED']);
  }, 30_000);
});

describe('cours collectifs : le droit est relu au serveur sur toute gestion et toute nouvelle inscription', () => {
  it('sans le module : plus de gestion ni d’inscription, mais lecture, annulations et engagements restent', async () => {
    const { typeId, seriesId } = await publishedSeries();
    const enrolled = await enroll(seriesId, 'demo-alice');
    expect(enrolled.statusCode, enrolled.body).toBe(201);
    const enrollment = enrolled.json().data.me.enrollment as { id: string; version: number };
    const policyVersion = (await school('demo-admin', 'GET', '/course-catalogue')).json().data.policy.version as number;
    const rows = { types: await count('course_type'), series: await count('course_series'), enrollments: await count('course_enrollment') };
    const { client } = await restrictTo(['MESSAGING'], 'Offre sans cours');

    // Refusé : gestion (types, séries, politique) et nouvel usage (inscription, liste d'attente, inscription par le personnel).
    expectNotEntitled(await school('demo-admin', 'POST', '/course-types', { body: { operationId: randomUUID(), title: `Type ${randomUUID()}`, description: '' } }));
    expectNotEntitled(await school('demo-admin', 'POST', '/course-series', { body: { operationId: randomUUID(), typeId, title: 'Cours refusé', description: '', location: 'Salle', conditions: '',
      teachingLanguage: null, responsibleMembershipId: id.adminMember, capacity: 10, minParticipants: null, timeZone: 'Europe/Zurich',
      occurrences: [{ startsAt: at(40, 8), endsAt: at(40, 11), instructorMembershipId: id.otherInstructorMember, attendanceRequired: true }] } }));
    expectNotEntitled(await school('demo-admin', 'PUT', '/course-policy', { body: { operationId: randomUUID(), selfCancelHours: 12, offerResponseMinutes: null }, version: policyVersion }));
    expectNotEntitled(await enroll(seriesId, 'demo-bob'));
    expectNotEntitled(await school('demo-bob', 'POST', `/course-series/${seriesId}/waitlist`, { body: { operationId: randomUUID() } }));
    expectNotEntitled(await school('demo-admin', 'POST', `/course-series/${seriesId}/enrollments`, { body: { operationId: randomUUID(), learnerId: id.bobLearner } }));
    expect({ types: await count('course_type'), series: await count('course_series'), enrollments: await count('course_enrollment') }).toEqual(rows);

    // Permis : lire le catalogue, la série et son état personnel, puis terminer les engagements pris.
    expect((await school('demo-admin', 'GET', '/course-catalogue')).statusCode).toBe(200);
    const series = await school('demo-admin', 'GET', `/course-series/${seriesId}`);
    expect(series.statusCode, series.body).toBe(200);
    const me = await school('demo-alice', 'GET', `/course-series/${seriesId}/me`);
    expect(me.statusCode, me.body).toBe(200);
    expect(me.json().data.me.state).toBe('ENROLLED');
    const cancelled = await school('demo-alice', 'POST', `/course-enrollments/${enrollment.id}/cancel`, { body: { operationId: randomUUID() }, version: enrollment.version });
    expect(cancelled.statusCode, cancelled.body).toBe(200);
    const current = await school('demo-admin', 'GET', `/course-series/${seriesId}`);
    const closed = await school('demo-admin', 'POST', `/course-series/${seriesId}/cancel`, { body: { operationId: randomUUID(), reason: 'Annulation de recette' }, version: current.json().data.version });
    expect(closed.statusCode, closed.body).toBe(200);
    expect(await count('course_series', "status='CANCELLED'")).toBe(1);

    // Réactivation sans perte : tout ce qui existait est encore là, la gestion reprend.
    const full = await createOffer(uniqueName('Offre complète'), ['MESSAGING', 'COLLECTIVE_COURSES']);
    await assignNow(client.id, full.id);
    expect(await count('course_enrollment')).toBe(rows.enrollments);
    expect(await count('course_series')).toBe(rows.series);
    const resumed = await school('demo-admin', 'POST', '/course-types', { body: { operationId: randomUUID(), title: `Type ${randomUUID()}`, description: '' } });
    expect(resumed.statusCode, resumed.body).toBe(201);
    expect(await count('course_type')).toBe(rows.types + 1);
  }, 30_000);
});

describe('garde-fous de la base', () => {
  it('rien ne se supprime ni ne se réécrit : offres, attributions, ajustements et catalogue', async () => {
    const { client, offer } = await restrictTo(['MESSAGING']);
    const adjustment = await adjust(client.id, 'COLLECTIVE_COURSES', 'GRANT', 'Geste commercial convenu');
    expect(adjustment.statusCode, adjustment.body).toBe(201);
    const adjustmentId = adjustment.json().data.adjustments[0].id as string;
    const assignmentId = (await rights(client.id)).assignments[0].id as string;
    const operator = (await pool.query<{ id: string }>('SELECT id FROM drivy.platform_operator WHERE subject=$1', [A])).rows[0]!.id;
    const otherOperator = (await pool.query<{ id: string }>('SELECT id FROM drivy.platform_operator WHERE subject=$1', [B])).rows[0]!.id;
    const refusals: Array<[string, string, unknown[]]> = [
      ['offre supprimée', 'DELETE FROM drivy.platform_offer WHERE id=$1', [offer.id]],
      ['auteur d’une offre réécrit', 'UPDATE drivy.platform_offer SET created_by=$2 WHERE id=$1', [offer.id, otherOperator]],
      ['module inconnu dans une offre', "UPDATE drivy.platform_offer SET modules='{PAYROLL}' WHERE id=$1", [offer.id]],
      ['attribution supprimée', 'DELETE FROM drivy.platform_offer_assignment WHERE id=$1', [assignmentId]],
      ['instantané réécrit', "UPDATE drivy.platform_offer_assignment SET offer_name='Autre nom' WHERE id=$1", [assignmentId]],
      ['attribution en vigueur annulée', "UPDATE drivy.platform_offer_assignment SET status='CANCELLED',cancelled_at=now(),cancelled_by=$2 WHERE id=$1", [assignmentId, operator]],
      ['ajustement supprimé', 'DELETE FROM drivy.platform_module_adjustment WHERE id=$1', [adjustmentId]],
      ['motif réécrit', "UPDATE drivy.platform_module_adjustment SET reason='Autre motif' WHERE id=$1", [adjustmentId]],
      ['module du catalogue supprimé', "DELETE FROM drivy.platform_module WHERE code='MESSAGING'", []],
      ['module du catalogue réordonné', "UPDATE drivy.platform_module SET sort_order=9 WHERE code='MESSAGING'", []],
    ];
    for (const [label, sql, params] of refusals) expect((await ownerError(sql, params))?.code, label).toBe('23514');
    // Une attribution ne remonte pas dans le passé et ne copie qu'une offre active avec ses modules exacts.
    const insert = `INSERT INTO drivy.platform_offer_assignment(id,client_id,offer_id,offer_name,modules,effective_at,created_by) VALUES($1,$2,$3,$4,$5::text[],$6,$7)`;
    expect((await ownerError(insert, [randomUUID(), client.id, offer.id, offer.name, offer.modules, new Date(Date.now() - 3_600_000).toISOString(), operator]))?.code).toBe('23514');
    expect((await ownerError(insert, [randomUUID(), client.id, offer.id, 'Autre nom', offer.modules, new Date(Date.now() + 3_600_000).toISOString(), operator]))?.code).toBe('23514');
    expect(await count('platform_offer')).toBe(1);
    expect(await count('platform_offer_assignment')).toBe(1);
    expect(await count('platform_module_adjustment')).toBe(1);
    expect(await count('platform_module')).toBe(2);
  });

  it('sous le rôle applicatif : rien sans opérateur, ni suppression, ni réécriture, ni écriture directe', async () => {
    const { client, offer } = await restrictTo(['MESSAGING']);
    const tables = ['platform_module', 'platform_offer', 'platform_offer_assignment'];
    for (const table of tables) {
      expect((await asApp('demo-admin', `SELECT 1 FROM drivy.${table}`)).rowCount, table).toBe(0);
      expect((await asApp('op-stranger', `SELECT 1 FROM drivy.${table}`)).rowCount, table).toBe(0);
      expect((await asApp(A, `SELECT 1 FROM drivy.${table}`)).rowCount, table).toBeGreaterThan(0);
    }
    expect((await asApp('demo-admin', 'SELECT 1 FROM drivy.platform_module_adjustment')).rowCount).toBe(0);
    const operator = (await pool.query<{ id: string }>('SELECT id FROM drivy.platform_operator WHERE subject=$1', [A])).rows[0]!.id;
    const insertOffer = "INSERT INTO drivy.platform_offer(id,name,modules,created_by) VALUES($1,'Offre forgée','{}',$2)";
    expect((await asApp('demo-admin', insertOffer, [randomUUID(), operator])).error?.code).toBe('42501');
    expect((await asApp('op-stranger', insertOffer, [randomUUID(), operator])).error?.code).toBe('42501');
    expect((await asApp(A, 'DELETE FROM drivy.platform_offer')).error?.code).toBe('42501');
    expect((await asApp(A, 'DELETE FROM drivy.platform_offer_assignment')).error?.code).toBe('42501');
    expect((await asApp(A, 'DELETE FROM drivy.platform_module_adjustment')).error?.code).toBe('42501');
    expect((await asApp(A, "UPDATE drivy.platform_module SET sort_order=9")).error?.code).toBe('42501');
    expect((await asApp(A, 'UPDATE drivy.platform_offer SET created_by=$2 WHERE id=$1', [offer.id, operator])).error?.code).toBe('42501');
    expect((await asApp(A, "UPDATE drivy.platform_offer_assignment SET offer_name='Autre'")).error?.code).toBe('42501');
    expect((await asApp(A, 'UPDATE drivy.platform_client SET commercial_state=commercial_state WHERE id=$1', [client.id])).error?.code).toBe('42501');
    // Les fonctions de lecture exigent un opérateur : une école ne peut pas lire les droits d'une fiche par la base.
    expect((await asApp('demo-admin', 'SELECT drivy.platform_client_entitlements($1)', [client.id])).error?.code).toBe('42501');
    expect((await asApp('demo-admin', 'SELECT drivy.platform_module_usage($1)', [client.id])).error?.code).toBe('42501');
    expect((await asApp('demo-admin', 'SELECT drivy.platform_offer_overview(NULL,NULL)')).error?.code).toBe('42501');
  });

  it('toutes les tables d’offres sont sous RLS forcée', async () => {
    const rls = await pool.query<{ relname: string; relrowsecurity: boolean; relforcerowsecurity: boolean }>(
      "SELECT c.relname::text AS relname,relrowsecurity,relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND relkind='r' AND c.relname IN ('platform_module','platform_offer','platform_offer_assignment','platform_module_adjustment') ORDER BY 1");
    expect(rls.rows.map(row => row.relname)).toEqual(['platform_module', 'platform_module_adjustment', 'platform_offer', 'platform_offer_assignment']);
    for (const row of rls.rows) expect([row.relrowsecurity, row.relforcerowsecurity], row.relname).toEqual([true, true]);
  });
});
