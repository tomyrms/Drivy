import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from 'jose';
import { buildApp } from '../src/app.js';
import { createTokenVerifier } from '../src/auth.js';
import { migrate } from '../scripts/migrations.js';
import { fixtureIds as id, seedFixtures } from '../scripts/fixtures.js';

const url = process.env.TEST_DATABASE_URL;
if (!url || new URL(url).pathname !== '/drivy_test') {
  throw new Error('TEST_DATABASE_URL doit cibler drivy_test.');
}
const issuer = 'https://identity.test.invalid';
const pool = new Pool({connectionString: url, max: 5, connectionTimeoutMillis: 5000});
let app: ReturnType<typeof buildApp>;
let keys: Awaited<ReturnType<typeof generateKeyPair>>;

beforeAll(async () => {
  await migrate(pool);
  keys = await generateKeyPair('RS256');
  const key = await exportJWK(keys.publicKey);
  const verifyToken = createTokenVerifier({OIDC_ISSUER: issuer,OIDC_AUDIENCE:'drivy-api',OIDC_JWKS_URL:`${issuer}/jwks`},
    createLocalJWKSet({keys:[{...key,kid:'integration',alg:'RS256'}]}));
  app = buildApp({pool,verifyToken,cursorSecret:'secret-test-32-caracteres-minimum',logger:true});
});
beforeEach(async () => {
  await pool.query('TRUNCATE drivy.person,drivy.school CASCADE');
  await seedFixtures(pool,issuer);
});
afterAll(async () => { await app?.close(); await pool.end(); });

async function token(subject: string) {
  return new SignJWT({}).setProtectedHeader({alg:'RS256',kid:'integration'}).setSubject(subject)
    .setIssuer(issuer).setAudience('drivy-api').setIssuedAt().setExpirationTime('5m').sign(keys.privateKey);
}
async function patch(subject: string, name: string, version: number, operationId = randomUUID()) {
  return app.inject({method:'PATCH',url:'/v1/me',headers:{authorization:`Bearer ${await token(subject)}`,
    'if-match':`"${version}"`, 'idempotency-key':operationId},payload:{operationId,displayName:name}});
}
async function me(subject: string) {
  return app.inject({method:'GET',url:'/v1/me',headers:{authorization:`Bearer ${await token(subject)}`}});
}

describe('#64 · modification du compte personnel', () => {
  it('moniteur sans dossier LEARNER : nom public modifié sans toucher aux appartenances ou à Keycloak', async () => {
    const before = (await me('demo-instructor')).json().data;
    expect(before.personId).toBe(id.instructor);
    const receipt = await patch('demo-instructor', 'Nouveau Moniteur', before.version);
    expect(receipt.statusCode,receipt.body).toBe(200);
    expect(receipt.headers.etag).toBe(`"${before.version+1}"`);
    expect(receipt.json().data).toMatchObject({personId:id.instructor,displayName:'Nouveau Moniteur',version:before.version+1});
    const after = (await me('demo-instructor')).json().data;
    expect(after.displayName).toBe('Nouveau Moniteur');
    expect(after.memberships).toEqual(before.memberships);
    const untouched = await pool.query('SELECT count(*)::int AS count FROM drivy.learner_profile WHERE person_id=$1',[id.instructor]);
    expect(untouched.rows[0].count).toBe(0);
  });
  it('admin et élève modifient chacun leur compte, pas celui des autres', async () => {
    const admin = (await me('demo-admin')).json().data;
    const alice = (await me('demo-alice')).json().data;
    expect((await patch('demo-admin','Compte Administration',admin.version)).statusCode).toBe(200);
    expect((await patch('demo-alice','Compte Élève',alice.version)).statusCode).toBe(200);
    expect((await me('demo-admin')).json().data.displayName).toBe('Compte Administration');
    expect((await me('demo-alice')).json().data.displayName).toBe('Compte Élève');
    expect((await me('demo-instructor')).json().data.displayName).not.toBe('Compte Administration');
  });
  it('versions concurrentes, saisie invalide et rejeu idempotent', async () => {
    const before = (await me('demo-instructor')).json().data;
    const operationId = randomUUID();
    const original = await patch('demo-instructor','Compte Mise à jour',before.version,operationId);
    expect(original.statusCode).toBe(200);
    const retry = await patch('demo-instructor','Compte Mise à jour',before.version,operationId);
    expect(retry.statusCode).toBe(200);
    expect(retry.json().data).toEqual(original.json().data);
    expect((await me('demo-instructor')).json().data.version).toBe(before.version+1);
    expect((await patch('demo-instructor','Un autre nom',before.version,operationId)).statusCode).toBe(409);
    expect((await patch('demo-instructor','Un autre nom',before.version)).statusCode).toBe(412);
    expect((await patch('demo-instructor','',before.version+1)).statusCode).toBe(400);
    expect((await me('demo-instructor')).json().data.displayName).toBe('Compte Mise à jour');
  });
});
