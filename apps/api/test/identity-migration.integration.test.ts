import { createCipheriv, randomBytes } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { afterAll, beforeAll, expect, it } from 'vitest';
import { Pool } from 'pg';
import { migrate } from '../scripts/migrations.js';
import { fixtureIds as id } from '../scripts/fixtures.js';
import { canonicalCaptureJSON } from '../src/capture-crypto.js';
import { freshDatabase } from './support/harness.js';
import { captureHarness } from './support/capture-harness.js';

/**
 * Migration 20261107 sur une base synthétique peuplée au schéma antérieur : un portrait chiffré (génération 3, AAD à photo_version 3)
 * et un compte sans photo. La migration est appliquée sous le propriétaire non privilégié habituel du harnais.
 * La clé et le key_id sont ceux du captureHarness (valeurs de recette uniquement).
 */
const KEY = Buffer.alloc(32, 42), KEY_ID = 'synthetic-only', LEGACY_VERSION = 3;
let pool: Pool, owner: Pool, jpeg: Buffer, photoApp: Awaited<ReturnType<typeof captureHarness>>;

const aad = (personId: string, photoVersion: number) => Buffer.from(canonicalCaptureJSON({ personId, kind: 'profile-photo', photoVersion }));
function seal(image: Buffer, personId: string, photoVersion: number) {
  const nonce = randomBytes(12), cipher = createCipheriv('aes-256-gcm', KEY, nonce);
  cipher.setAAD(aad(personId, photoVersion));
  const ciphertext = Buffer.concat([cipher.update(image), cipher.final()]);
  return Buffer.concat([nonce, cipher.getAuthTag(), ciphertext]);
}
async function call(method: 'PUT' | 'DELETE' | 'GET', route: string, subject: string, version?: number, body?: Buffer) {
  const token = await photoApp.token(subject);
  return photoApp.app.inject({ method, url: route, headers: { authorization: `Bearer ${token}`, ...(version ? { 'if-match': `"${version}"` } : {}), ...(body ? { 'content-type': 'image/jpeg' } : {}) }, ...(body ? { payload: body } : {}) });
}
const profile = async (subject: string) => (await call('GET', '/v1/me/profile', subject)).json().data as { photoVersion: number | null; photoGeneration: number; version: number };

beforeAll(async () => {
  pool = await freshDatabase({ skipMigrations: /^20261107_identity_versions_photo_generation/ });
  jpeg = await readFile(new URL('./fixtures/profile-128.jpg', import.meta.url));
  // État antérieur : ni colonne photo_generation, ni garde.
  expect((await pool.query("SELECT 1 FROM information_schema.columns WHERE table_schema='drivy' AND table_name='person' AND column_name='photo_generation'")).rowCount).toBe(0);
  await pool.query('INSERT INTO drivy.person_photo(person_id,photo_version,key_id,encrypted_image,byte_size,width,height) VALUES($1,$2,$3,$4,$5,128,128)',
    [id.bob, LEGACY_VERSION, KEY_ID, seal(jpeg, id.bob, LEGACY_VERSION), jpeg.length]);
  await pool.query('UPDATE drivy.person SET photo_version=$2 WHERE id=$1', [id.bob, LEGACY_VERSION]);
  expect((await pool.query('SELECT photo_version FROM drivy.person WHERE id=ANY($1) ORDER BY photo_version', [[id.alice, id.bob]])).rows.map(r => r.photo_version)).toEqual([0, LEGACY_VERSION]);
  // Même propriétaire non privilégié que freshDatabase ; le registre déjà posé ne rejoue que la migration manquante.
  owner = new Pool({ connectionString: process.env.TEST_DATABASE_URL, options: '-c role=drivy_harness_migrator' });
  expect((await owner.query('SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user')).rows[0]).toEqual({ rolsuper: false, rolbypassrls: false });
  const before = (await pool.query('SELECT count(*)::int n FROM public.drivy_migrations')).rows[0].n;
  await migrate(owner);
  expect((await pool.query('SELECT count(*)::int n FROM public.drivy_migrations')).rows[0].n).toBe(before + 1);
  photoApp = await captureHarness(pool);
});
afterAll(async () => { await photoApp?.app.close(); await owner?.end(); await pool?.end(); });

it('le rattrapage fixe photo_generation sur photo_version et ne touche pas au portrait chiffré', async () => {
  const rows = (await pool.query('SELECT id,photo_version,photo_generation FROM drivy.person WHERE id=ANY($1) ORDER BY photo_version', [[id.alice, id.bob]])).rows;
  expect(rows).toEqual([{ id: id.alice, photo_version: 0, photo_generation: 0 }, { id: id.bob, photo_version: LEGACY_VERSION, photo_generation: LEGACY_VERSION }]);
  expect((await pool.query('SELECT photo_version,key_id FROM drivy.person_photo WHERE person_id=$1', [id.bob])).rows).toEqual([{ photo_version: LEGACY_VERSION, key_id: KEY_ID }]);
});

it('le portrait chiffré avant migration reste déchiffrable (AAD intacte) ; l’absence reste une absence', async () => {
  const bob = await call('GET', `/v1/people/${id.bob}/photo`, 'demo-bob');
  expect(bob.statusCode).toBe(200); expect(bob.headers.etag).toBe(`"photo-${LEGACY_VERSION}"`);
  expect(Buffer.compare(bob.rawPayload, jpeg)).toBe(0); // contenu déchiffré identique à celui scellé avant la migration
  expect(await profile('demo-bob')).toMatchObject({ photoVersion: LEGACY_VERSION, photoGeneration: LEGACY_VERSION });
  expect(await profile('demo-alice')).toMatchObject({ photoVersion: null, photoGeneration: 0 });
  expect((await call('GET', `/v1/people/${id.alice}/photo`, 'demo-alice')).statusCode).toBe(404);
});

it('après migration, retrait puis remplacement avancent la génération sans jamais la réutiliser (portrait migré et compte sans photo)', async () => {
  // Compte migré : 3 → retrait (null, génération 3) → remplacement (4, jamais 1 ni 3).
  let bob = await profile('demo-bob');
  const removed = await call('DELETE', '/v1/me/profile/photo', 'demo-bob', bob.version);
  expect(removed.statusCode, removed.body).toBe(200);
  expect(removed.json().data).toMatchObject({ photoVersion: null, photoGeneration: LEGACY_VERSION });
  expect((await call('GET', `/v1/people/${id.bob}/photo`, 'demo-bob')).statusCode).toBe(404);
  const replaced = await call('PUT', '/v1/me/profile/photo', 'demo-bob', removed.json().data.version, jpeg);
  expect(replaced.statusCode, replaced.body).toBe(200);
  expect(replaced.json().data).toMatchObject({ photoVersion: LEGACY_VERSION + 1, photoGeneration: LEGACY_VERSION + 1 });
  expect((await call('GET', `/v1/people/${id.bob}/photo`, 'demo-bob')).headers.etag).toBe(`"photo-${LEGACY_VERSION + 1}"`);
  // Compte sans photo : 0 → 1 → retrait (null, 1) → 2.
  let alice = await profile('demo-alice');
  const first = await call('PUT', '/v1/me/profile/photo', 'demo-alice', alice.version, jpeg);
  expect(first.json().data).toMatchObject({ photoVersion: 1, photoGeneration: 1 });
  const gone = await call('DELETE', '/v1/me/profile/photo', 'demo-alice', first.json().data.version);
  expect(gone.json().data).toMatchObject({ photoVersion: null, photoGeneration: 1 });
  const again = await call('PUT', '/v1/me/profile/photo', 'demo-alice', gone.json().data.version, jpeg);
  expect(again.json().data).toMatchObject({ photoVersion: 2, photoGeneration: 2 });
  bob = await profile('demo-bob'); alice = await profile('demo-alice');
  expect([bob.photoGeneration, alice.photoGeneration]).toEqual([LEGACY_VERSION + 1, 2]);
});
