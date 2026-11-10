import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Pool } from 'pg';
import { fixtureIds as id } from '../scripts/fixtures.js';
import { freshDatabase, harness, type Call } from './support/harness.js';
import { captureHarness } from './support/capture-harness.js';

/**
 * Identité partagée (#421) et génération des portraits (#450), sur PostgreSQL réel, avec des données synthétiques.
 * Alice est élève de l'école A et de l'école B ; demo-admin administre A, demo-instructor administre B.
 */
let pool: Pool, call: Call, close: () => Promise<void>, photoApp: Awaited<ReturnType<typeof captureHarness>>, jpeg: Buffer;
const schoolA = `/v1/schools/${id.schoolA}`, schoolB = `/v1/schools/${id.schoolB}`;
const dossierA = `${schoolA}/learners/${id.aliceLearner}`;
const aliceLearnerB = randomUUID();
const dossierB = `${schoolB}/learners/${aliceLearnerB}`;
let policyA = '', policyB = '';

beforeAll(async () => {
  pool = await freshDatabase(); const h = await harness(pool); call = h.call; close = () => h.app.close();
  photoApp = await captureHarness(pool);
  jpeg = await readFile(new URL('./fixtures/profile-128.jpg', import.meta.url));
  const noticeA = (await pool.query('SELECT notice_version_id FROM drivy.school_data_policy WHERE school_id=$1 AND approved_at IS NOT NULL ORDER BY version DESC LIMIT 1', [id.schoolA])).rows[0].notice_version_id;
  await pool.query("UPDATE drivy.person SET first_name='Alice',last_name='Exemple' WHERE id=$1", [id.alice]);
  const notice = randomUUID();
  await pool.query(`INSERT INTO drivy.school_data_policy(school_id,version,notice_text,retention_text,contact_email,approved_by,approved_at,notice_version_id) VALUES($1,2,'Notice synthétique','Conservation synthétique','recette@example.invalid',$2,now(),$3)`,
    [id.schoolB, id.instructorMemberB, notice]);
  const fields = JSON.stringify([{ field: 'firstName', requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION' }, { field: 'lastName', requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION' },
    { field: 'contactPhone', requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: 'LESSON_CONTACT' }]);
  await pool.query(`INSERT INTO drivy.profile_field_policy(school_id,status,effective_from,fields,notice_version_id,approved_by_membership_id,approved_at,created_by_membership_id)
    VALUES($1,'PUBLISHED',now()-interval '1 day',$2,$3,$4,now(),$4)`, [id.schoolA, fields, noticeA, id.adminMember]);
  policyB = (await pool.query(`INSERT INTO drivy.profile_field_policy(school_id,status,effective_from,fields,notice_version_id,approved_by_membership_id,approved_at,created_by_membership_id)
    VALUES($1,'PUBLISHED',now()-interval '1 day',$2,$3,$4,now(),$4) RETURNING id`, [id.schoolB, fields, notice, id.instructorMemberB])).rows[0].id;
  await pool.query("INSERT INTO drivy.membership(id,school_id,person_id,roles) VALUES($1,$2,$3,ARRAY['LEARNER'])", [randomUUID(), id.schoolB, id.alice]);
  await pool.query("INSERT INTO drivy.learner_profile(id,school_id,person_id,created_at) VALUES($1,$2,$3,'2026-01-01T00:00:00Z')", [aliceLearnerB, id.schoolB, id.alice]);
  policyA = (await call('GET', `${dossierA}/administrative-profile`, undefined, null, 'demo-admin')).json().data.policyVersionId;
});
afterAll(async () => { await close?.(); await photoApp?.app.close(); await pool?.end(); });

const adminRead = async (path: string, subject: string) => (await call('GET', `${path}/administrative-profile`, undefined, null, subject)).json().data as { version: number; contactPhone: string | null };
const adminWrite = (path: string, policy: string, body: Record<string, unknown>, version: number, subject: string, operationId = randomUUID()) =>
  call('PATCH', `${path}/administrative-profile`, { operationId, policyVersionId: policy, ...body }, version, subject);
const me = async (subject: string) => (await call('GET', '/v1/me/profile', undefined, null, subject)).json().data as
  { displayName: string; contactPhone: string | null; photoVersion: number | null; photoGeneration: number; version: number };
const saveMe = (body: Record<string, unknown>, version: number, subject: string) => call('PATCH', '/v1/me/profile', { displayName: 'Alice Exemple', ...body }, version, subject);
const phoneInDb = async () => (await pool.query('SELECT contact_phone FROM drivy.person WHERE id=$1', [id.alice])).rows[0].contact_phone as string | null;
async function photoCall(method: 'PUT' | 'DELETE' | 'GET', route: string, subject: string, version?: number, body?: Buffer) {
  const token = await photoApp.token(subject);
  return photoApp.app.inject({ method, url: route, headers: { authorization: `Bearer ${token}`, ...(version ? { 'if-match': `"${version}"` } : {}), ...(body ? { 'content-type': 'image/jpeg' } : {}) }, ...(body ? { payload: body } : {}) });
}
const meViaPhotoApp = async (subject: string) => (await photoCall('GET', '/v1/me/profile', subject)).json().data as { photoVersion: number | null; photoGeneration: number; version: number };

describe('Identité partagée : version des projections modifiables (#421)', () => {
  it('une modification de Mon profil refuse le formulaire scolaire ouvert avant elle', async () => {
    const opened = await adminRead(dossierA, 'demo-admin');
    const mine = await me('demo-alice');
    expect((await saveMe({ contactPhone: '+41 79 000 00 01' }, mine.version, 'demo-alice')).statusCode).toBe(200);
    const stale = await adminWrite(dossierA, policyA, { contactPhone: '+41 79 000 00 02' }, opened.version, 'demo-admin');
    expect(stale.statusCode, stale.body).toBe(412); expect(stale.json().code).toBe('VERSION_CONFLICT');
    expect(await phoneInDb()).toBe('+41 79 000 00 01');
    // Après relecture, la correction voulue réussit.
    const reread = await adminRead(dossierA, 'demo-admin');
    expect(reread.contactPhone).toBe('+41 79 000 00 01'); expect(reread.version).toBeGreaterThan(opened.version);
    expect((await adminWrite(dossierA, policyA, { contactPhone: '+41 79 000 00 02' }, reread.version, 'demo-admin')).statusCode).toBe(200);
    expect(await phoneInDb()).toBe('+41 79 000 00 02');
  });

  it('la même règle vaut pour la route historique /learners/{id}', async () => {
    const opened = (await call('GET', dossierA, undefined, null, 'demo-admin')).json().data as { version: number };
    const mine = await me('demo-alice');
    expect((await saveMe({ contactPhone: '+41 79 000 00 03' }, mine.version, 'demo-alice')).statusCode).toBe(200);
    const stale = await call('PATCH', dossierA, { operationId: randomUUID(), contactPhone: '+41 79 000 00 04' }, opened.version, 'demo-admin');
    expect(stale.statusCode, stale.body).toBe(412);
    expect(await phoneInDb()).toBe('+41 79 000 00 03');
  });

  it('ordre inverse : Mon profil ouvert avant une correction scolaire est refusé', async () => {
    const mine = await me('demo-alice'), opened = await adminRead(dossierA, 'demo-admin');
    expect((await adminWrite(dossierA, policyA, { contactPhone: '+41 79 000 00 05' }, opened.version, 'demo-admin')).statusCode).toBe(200);
    const stale = await saveMe({ contactPhone: '+41 79 000 00 06' }, mine.version, 'demo-alice');
    expect(stale.statusCode, stale.body).toBe(412);
    expect(await phoneInDb()).toBe('+41 79 000 00 05');
  });

  it('deux écoles : la correction faite dans l’école A périme le dossier ouvert dans l’école B, et réciproquement', async () => {
    const openedA = await adminRead(dossierA, 'demo-admin'), openedB = await adminRead(dossierB, 'demo-instructor');
    expect((await adminWrite(dossierA, policyA, { contactPhone: '+41 79 000 00 07' }, openedA.version, 'demo-admin')).statusCode).toBe(200);
    const staleB = await adminWrite(dossierB, policyB, { contactPhone: '+41 79 000 00 08' }, openedB.version, 'demo-instructor');
    expect(staleB.statusCode, staleB.body).toBe(412);
    expect(await phoneInDb()).toBe('+41 79 000 00 07');
    const freshB = await adminRead(dossierB, 'demo-instructor');
    expect((await adminWrite(dossierB, policyB, { contactPhone: '+41 79 000 00 08' }, freshB.version, 'demo-instructor')).statusCode).toBe(200);
    // Sens inverse : A était ouvert avant la correction de B.
    const openedA2 = await adminRead(dossierA, 'demo-admin');
    const freshB2 = await adminRead(dossierB, 'demo-instructor');
    expect((await adminWrite(dossierB, policyB, { contactPhone: '+41 79 000 00 09' }, freshB2.version, 'demo-instructor')).statusCode).toBe(200);
    expect((await adminWrite(dossierA, policyA, { contactPhone: '+41 79 000 00 10' }, openedA2.version, 'demo-admin')).statusCode).toBe(412);
    expect(await phoneInDb()).toBe('+41 79 000 00 09');
  });

  it('sans modification concurrente, le dossier reste modifiable et la version avance d’un cran', async () => {
    const before = await adminRead(dossierA, 'demo-admin');
    const ok = await adminWrite(dossierA, policyA, { contactPhone: '+41 79 000 00 11' }, before.version, 'demo-admin');
    expect(ok.statusCode, ok.body).toBe(200); expect(ok.json().data.version).toBe(before.version + 1);
    expect((await adminRead(dossierA, 'demo-admin')).version).toBe(before.version + 1);
  });

  it('une modification sans effet sur l’identité (photo) ne périme pas le dossier ; un autre élève n’est jamais concerné', async () => {
    const opened = await adminRead(dossierA, 'demo-admin');
    const bobBefore = (await pool.query('SELECT version FROM drivy.learner_profile WHERE id=$1', [id.bobLearner])).rows[0].version;
    const mine = await meViaPhotoApp('demo-alice');
    expect((await photoCall('PUT', '/v1/me/profile/photo', 'demo-alice', mine.version, jpeg)).statusCode).toBe(200);
    expect((await adminRead(dossierA, 'demo-admin')).version).toBe(opened.version);
    const mineAfter = await me('demo-alice');
    expect((await saveMe({ contactPhone: '+41 79 000 00 12' }, mineAfter.version, 'demo-alice')).statusCode).toBe(200);
    expect((await pool.query('SELECT version FROM drivy.learner_profile WHERE id=$1', [id.bobLearner])).rows[0].version).toBe(bobBefore);
    const seen = await adminRead(dossierA, 'demo-admin');
    expect(seen.version).toBe(opened.version + 1);
  });

  it('droits inchangés : le moniteur affecté ne peut toujours écrire que le contact, et une école ne lit pas le dossier de l’autre', async () => {
    const opened = await adminRead(dossierA, 'demo-admin');
    const forbidden = await adminWrite(dossierA, policyA, { birthDate: '2000-01-01' }, opened.version, 'demo-instructor');
    expect(forbidden.statusCode).toBe(403); expect(forbidden.json().code).toBe('PROFILE_FIELD_FORBIDDEN');
    // L'administrateur de B n'obtient aucun accès au dossier de A via la version d'identité.
    expect([403, 404]).toContain((await call('GET', `${schoolA}/learners/${id.aliceLearner}/administrative-profile`, undefined, null, 'demo-foreign')).statusCode);
    expect((await call('GET', `${schoolB}/learners/${id.aliceLearner}/administrative-profile`, undefined, null, 'demo-instructor')).statusCode).toBe(404);
  });

  it('rejeu exact : même opération, même contenu → même réponse, sans réécriture ni nouvelle version, même si l’identité a bougé depuis', async () => {
    const opened = await adminRead(dossierA, 'demo-admin'), operationId = randomUUID();
    const first = await adminWrite(dossierA, policyA, { contactPhone: '+41 79 000 00 13' }, opened.version, 'demo-admin', operationId);
    expect(first.statusCode, first.body).toBe(200);
    const after = await adminRead(dossierA, 'demo-admin'), personVersion = (await pool.query('SELECT version FROM drivy.person WHERE id=$1', [id.alice])).rows[0].version;
    const mine = await me('demo-alice');
    expect((await saveMe({ contactPhone: '+41 79 000 00 14' }, mine.version, 'demo-alice')).statusCode).toBe(200);
    const replay = await adminWrite(dossierA, policyA, { contactPhone: '+41 79 000 00 13' }, opened.version, 'demo-admin', operationId);
    expect(replay.statusCode, replay.body).toBe(200); expect(replay.json().data).toEqual(first.json().data);
    expect(after.version).toBe(first.json().data.version);
    expect(await phoneInDb()).toBe('+41 79 000 00 14');
    expect((await pool.query('SELECT version FROM drivy.person WHERE id=$1', [id.alice])).rows[0].version).toBe(personVersion + 1);
    // Même opération avec un autre contenu : refus d'idempotence, pas d'écrasement.
    const mismatch = await adminWrite(dossierA, policyA, { contactPhone: '+41 79 000 00 15' }, opened.version, 'demo-admin', operationId);
    expect(mismatch.statusCode).toBe(409);
  });

  it('écritures simultanées avec la même version : une seule gagne, l’autre reçoit 412, sans interblocage', async () => {
    for (let round = 0; round < 3; round++) {
      const opened = await adminRead(dossierA, 'demo-admin'), openedB = await adminRead(dossierB, 'demo-instructor'), mine = await me('demo-alice');
      const results = await Promise.all([
        adminWrite(dossierA, policyA, { contactPhone: `+41 79 100 0${round}01` }, opened.version, 'demo-admin'),
        adminWrite(dossierB, policyB, { contactPhone: `+41 79 100 0${round}02` }, openedB.version, 'demo-instructor'),
        saveMe({ contactPhone: `+41 79 100 0${round}03` }, mine.version, 'demo-alice')]);
      const codes = results.map(r => r.statusCode).sort();
      // Au moins un succès ; aucun 5xx (interblocage, délai de verrou) ; tout perdant est un conflit de version explicite.
      expect(codes.filter(c => c === 200).length, results.map(r => r.body).join('|')).toBeGreaterThanOrEqual(1);
      for (const r of results) expect([200, 412]).toContain(r.statusCode);
    }
  });
});

describe('Photo : génération monotone distincte de la présence (#450)', () => {
  it('ajouter, retirer puis ajouter ne réutilise jamais une génération ; l’absence est représentée par photoVersion null', async () => {
    let profile = await meViaPhotoApp('demo-admin');
    expect(profile.photoVersion).toBeNull(); const base = profile.photoGeneration;
    expect(base).toBe(0);
    const first = await photoCall('PUT', '/v1/me/profile/photo', 'demo-admin', profile.version, jpeg);
    expect(first.statusCode, first.body).toBe(200); profile = first.json().data;
    expect(profile).toMatchObject({ photoVersion: base + 1, photoGeneration: base + 1 });
    const removed = await photoCall('DELETE', '/v1/me/profile/photo', 'demo-admin', profile.version);
    expect(removed.statusCode, removed.body).toBe(200); profile = removed.json().data;
    expect(profile).toMatchObject({ photoVersion: null, photoGeneration: base + 1 });
    expect((await photoCall('GET', `/v1/people/${id.admin}/photo`, 'demo-admin')).statusCode).toBe(404);
    const second = await photoCall('PUT', '/v1/me/profile/photo', 'demo-admin', profile.version, jpeg);
    expect(second.statusCode, second.body).toBe(200); profile = second.json().data;
    expect(profile).toMatchObject({ photoVersion: base + 2, photoGeneration: base + 2 });
    const image = await photoCall('GET', `/v1/people/${id.admin}/photo`, 'demo-admin');
    expect(image.statusCode).toBe(200); expect(image.headers.etag).toBe(`"photo-${base + 2}"`);
    // La base conserve la génération et la ligne chiffrée porte la nouvelle.
    expect((await pool.query('SELECT p.photo_version,p.photo_generation,f.photo_version AS stored FROM drivy.person p JOIN drivy.person_photo f ON f.person_id=p.id WHERE p.id=$1', [id.admin])).rows[0])
      .toEqual({ photo_version: base + 2, photo_generation: base + 2, stored: base + 2 });
  });

  it('un appareil resté sur l’ancienne génération voit l’absence puis la nouvelle photo, et son ancienne intention est refusée', async () => {
    const device = await meViaPhotoApp('demo-bob');
    const put = await photoCall('PUT', '/v1/me/profile/photo', 'demo-bob', device.version, jpeg);
    const a = put.json().data as { photoVersion: number; photoGeneration: number; version: number };
    // Appareil B retire puis remplace.
    const del = (await photoCall('DELETE', '/v1/me/profile/photo', 'demo-bob', a.version)).json().data;
    expect(await meViaPhotoApp('demo-bob')).toMatchObject({ photoVersion: null, photoGeneration: a.photoGeneration });
    const replaced = (await photoCall('PUT', '/v1/me/profile/photo', 'demo-bob', del.version, jpeg)).json().data;
    const seen = await meViaPhotoApp('demo-bob');
    expect(seen.photoVersion).not.toBe(a.photoVersion); expect(seen.photoGeneration).toBeGreaterThan(a.photoGeneration);
    expect(seen.photoVersion).toBe(replaced.photoVersion);
    // L'appareil A, avec sa version d'avant, ne peut ni remplacer ni retirer.
    for (const method of ['PUT', 'DELETE'] as const) {
      const stale = await photoCall(method, '/v1/me/profile/photo', 'demo-bob', a.version, method === 'PUT' ? jpeg : undefined);
      expect(stale.statusCode, stale.body).toBe(412);
    }
  });

  it('les portraits chiffrés existants restent lisibles : génération rattrapée sur photoVersion', async () => {
    // Un compte « migré » : photo_version déjà posé avec sa ligne chiffrée, génération égale (rattrapage de la migration).
    const row = (await pool.query('SELECT photo_version,photo_generation FROM drivy.person WHERE id=$1', [id.bob])).rows[0];
    expect(row.photo_generation).toBeGreaterThanOrEqual(row.photo_version);
    expect((await photoCall('GET', `/v1/people/${id.bob}/photo`, 'demo-bob')).statusCode).toBe(200);
    // Contrainte de base : la génération ne peut ni passer sous la version courante ni diminuer.
    await expect(pool.query('UPDATE drivy.person SET photo_generation=photo_version-1 WHERE id=$1', [id.bob])).rejects.toThrow();
    await expect(pool.query('UPDATE drivy.person SET photo_generation=photo_generation-1,photo_version=0 WHERE id=$1', [id.bob])).rejects.toThrow();
  });
});
