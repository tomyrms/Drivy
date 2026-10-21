import { readFile } from 'node:fs/promises';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Pool } from 'pg';
import { fixtureIds as id } from '../scripts/fixtures.js';
import { cleanJpeg } from '../src/profile-photo.js';
import { freshDatabase, harness, type Call } from './support/harness.js';
import { captureHarness } from './support/capture-harness.js';

let pool: Pool, call: Call, close: () => Promise<void>, photoApp: Awaited<ReturnType<typeof captureHarness>>, jpeg: Buffer;
beforeAll(async () => {
  pool = await freshDatabase(); const h = await harness(pool); call = h.call; close = () => h.app.close();
  photoApp = await captureHarness(pool);
  jpeg = await readFile(new URL('./fixtures/profile-128.jpg', import.meta.url));
});
afterAll(async () => { await close?.(); await photoApp?.app.close(); await pool?.end(); });

const me = async (subject: string) => (await call('GET', '/v1/me/profile', undefined, null, subject)).json().data as
  { personId: string; displayName: string; firstName: string | null; lastName: string | null; contactPhone: string | null; photoVersion: number | null; version: number };
const save = (body: Record<string, unknown>, version: number | null, subject: string) => call('PATCH', '/v1/me/profile', body, version, subject);
/** EXIF synthétique avec une fausse position : il doit disparaître du fichier stocké. */
const withExif = (image: Buffer) => {
  const payload = Buffer.concat([Buffer.from('Exif\u0000\u0000', 'latin1'), Buffer.from('GPS-46.9999-6.9999-SYNTHETIQUE', 'latin1')]);
  const segment = Buffer.concat([Buffer.from([0xff, 0xe1]), Buffer.from([(payload.length + 2) >> 8, (payload.length + 2) & 0xff]), payload]);
  return Buffer.concat([image.subarray(0, 2), segment, image.subarray(2)]);
};
async function photoCall(method: 'PUT' | 'DELETE' | 'GET', route: string, subject: string, version?: number, body?: Buffer) {
  const token = await photoApp.token(subject);
  return photoApp.app.inject({ method, url: route, headers: { authorization: `Bearer ${token}`, ...(version ? { 'if-match': `"${version}"` } : {}),
    ...(body ? { 'content-type': 'image/jpeg' } : {}) }, ...(body ? { payload: body } : {}) });
}

describe('Profil personnel complet (#64)', () => {
  it('un moniteur et un administrateur modifient tout leur profil, sans dossier élève', async () => {
    for (const subject of ['demo-instructor', 'demo-admin']) {
      const before = await me(subject);
      const response = await save({ displayName: '  Nom choisi  ', firstName: ' Prénom ', lastName: 'Famille', contactPhone: '+41 79 000 00 00' }, before.version, subject);
      expect(response.statusCode, response.body).toBe(200);
      expect(response.json().data).toMatchObject({ personId: before.personId, displayName: 'Nom choisi', firstName: 'Prénom', lastName: 'Famille',
        contactPhone: '+41 79 000 00 00', version: before.version + 1 });
      expect(await me(subject)).toMatchObject({ displayName: 'Nom choisi', firstName: 'Prénom', version: before.version + 1 });
      expect((await call('GET', '/v1/me', undefined, null, subject)).json().data.displayName).toBe('Nom choisi');
      // Champ vidé : il redevient absent.
      const cleared = await save({ displayName: 'Nom choisi', contactPhone: '' }, before.version + 1, subject);
      expect(cleared.json().data).toMatchObject({ contactPhone: null, firstName: 'Prénom' });
    }
  });

  it('un renvoi identique après une réponse perdue ne crée pas de conflit', async () => {
    const before = await me('demo-instructor'), body = { displayName: 'Nom rejoué', firstName: 'Alex' };
    expect((await save(body, before.version, 'demo-instructor')).statusCode).toBe(200);
    const replay = await save(body, before.version, 'demo-instructor');
    expect(replay.statusCode, replay.body).toBe(200);
    expect(replay.json().data.version).toBe(before.version + 1);
  });

  it('refuse une version périmée, une version absente et des valeurs invalides', async () => {
    const before = await me('demo-admin');
    expect((await save({ displayName: 'Autre nom' }, before.version + 5, 'demo-admin')).json().code).toBe('VERSION_CONFLICT');
    expect((await save({ displayName: 'Autre nom' }, null, 'demo-admin')).statusCode).toBe(428);
    for (const bad of [{ displayName: '' }, { displayName: 'x'.repeat(201) }, { displayName: 'Nom\u0007' }, { displayName: 'Ok', contactPhone: 'abc' },
      { displayName: 'Ok', firstName: 'x'.repeat(151) }, { displayName: 'Ok', roles: ['ADMIN'] }])
      expect((await save(bad, before.version, 'demo-admin')).statusCode).toBe(400);
    expect(await me('demo-admin')).toEqual(before);
  });

  it('ne modifie que la personne connectée, ni ses rôles ni les autres comptes', async () => {
    const other = await me('demo-admin');
    const roles = (await pool.query('SELECT roles,version FROM drivy.membership WHERE id=$1', [id.instructorMember])).rows[0];
    const before = await me('demo-instructor');
    expect((await save({ displayName: 'Seulement moi' }, before.version, 'demo-instructor')).statusCode).toBe(200);
    expect(await me('demo-admin')).toEqual(other);
    expect((await pool.query('SELECT roles,version FROM drivy.membership WHERE id=$1', [id.instructorMember])).rows[0]).toEqual(roles);
  });

  it('la base refuse une écriture hors de la route du profil personnel ou sur une autre personne', async () => {
    const db = await pool.connect();
    try {
      await db.query('BEGIN'); await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.person_id',$1,true)", [id.instructor]);
      await db.query('SAVEPOINT direct');
      await expect(db.query("UPDATE drivy.person SET display_name='Contournement' WHERE id=$1", [id.instructor])).rejects.toThrow(/row-level security/);
      await db.query('ROLLBACK TO SAVEPOINT direct');
      await db.query("SELECT set_config('app.self_profile','true',true)");
      expect((await db.query("UPDATE drivy.person SET display_name='Autrui' WHERE id=$1", [id.admin])).rowCount).toBe(0);
      await db.query('SAVEPOINT photo');
      await expect(db.query("INSERT INTO drivy.person_photo(person_id,photo_version,key_id,encrypted_image,byte_size,width,height) VALUES($1,1,'k',decode(repeat('ab',40),'hex'),1,64,64)", [id.admin])).rejects.toThrow(/row-level security/);
      await db.query('ROLLBACK TO SAVEPOINT photo');
    } finally { await db.query('ROLLBACK'); db.release(); }
  });
});

describe('Photo de profil (#64)', () => {
  it('le nettoyage retire EXIF et refuse ce qui n’est pas un JPEG valable', () => {
    const cleaned = cleanJpeg(withExif(jpeg));
    expect(cleaned).toBeDefined();
    expect(cleaned!.width).toBe(128); expect(cleaned!.height).toBe(128);
    expect(cleaned!.data.includes(Buffer.from('GPS-46.9999', 'latin1'))).toBe(false);
    expect(cleaned!.data.includes(Buffer.from('Exif', 'latin1'))).toBe(false);
    expect(cleanJpeg(Buffer.from('pas une image'))).toBeUndefined();
    expect(cleanJpeg(jpeg.subarray(0, jpeg.length - 10))).toBeUndefined();
  });

  it('envoie, relit, remplace puis retire sa photo ; un membre de la même école la voit, une autre école non', async () => {
    let profile = (await photoCall('GET', '/v1/me/profile', 'demo-instructor')).json().data;
    const sent = await photoCall('PUT', '/v1/me/profile/photo', 'demo-instructor', profile.version, withExif(jpeg));
    expect(sent.statusCode, sent.body).toBe(200);
    profile = sent.json().data; expect(profile.photoVersion).toBe(1);
    const own = await photoCall('GET', `/v1/people/${profile.personId}/photo`, 'demo-instructor');
    expect(own.statusCode).toBe(200); expect(own.headers['content-type']).toBe('image/jpeg');
    expect(own.rawPayload.includes(Buffer.from('GPS-46.9999', 'latin1'))).toBe(false);
    expect((await pool.query('SELECT encrypted_image FROM drivy.person_photo WHERE person_id=$1', [profile.personId])).rows[0].encrypted_image.includes(own.rawPayload.subarray(2, 40))).toBe(false);
    expect((await photoCall('GET', `/v1/people/${profile.personId}/photo`, 'demo-alice')).statusCode).toBe(200);
    expect((await photoCall('GET', `/v1/people/${profile.personId}/photo`, 'demo-admin')).statusCode).toBe(200);
    // Une personne sans école commune ne voit pas la photo : demo-foreign (école B) face à Alice (école A).
    let alice = (await photoCall('GET', '/v1/me/profile', 'demo-alice')).json().data;
    alice = (await photoCall('PUT', '/v1/me/profile/photo', 'demo-alice', alice.version, jpeg)).json().data;
    expect(alice.photoVersion).toBe(1);
    expect((await photoCall('GET', `/v1/people/${alice.personId}/photo`, 'demo-foreign')).statusCode).toBe(404);
    expect((await photoCall('GET', `/v1/people/${alice.personId}/photo`, 'demo-instructor')).statusCode).toBe(200);
    expect((await photoCall('PUT', '/v1/me/profile/photo', 'demo-instructor', profile.version - 1 || 99, jpeg)).json().code).toBe('VERSION_CONFLICT');
    expect((await photoCall('PUT', '/v1/me/profile/photo', 'demo-instructor', profile.version, Buffer.from('pas une image'))).statusCode).toBe(422);
    const replaced = await photoCall('PUT', '/v1/me/profile/photo', 'demo-instructor', profile.version, jpeg);
    expect(replaced.json().data.photoVersion).toBe(2); profile = replaced.json().data;
    const removed = await photoCall('DELETE', '/v1/me/profile/photo', 'demo-instructor', profile.version);
    expect(removed.statusCode, removed.body).toBe(200); expect(removed.json().data.photoVersion).toBeNull();
    expect((await photoCall('GET', `/v1/people/${profile.personId}/photo`, 'demo-instructor')).statusCode).toBe(404);
    // Retirer une photo déjà retirée ne change rien.
    expect((await photoCall('DELETE', '/v1/me/profile/photo', 'demo-instructor', removed.json().data.version)).json().data.version).toBe(removed.json().data.version);
  });
});
