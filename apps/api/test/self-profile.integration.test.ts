import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Pool } from 'pg';
import { fixtureIds as id } from '../scripts/fixtures.js';
import { freshDatabase, harness, type Call } from './support/harness.js';

let pool: Pool, call: Call, close: () => Promise<void>;
beforeAll(async () => { pool = await freshDatabase(); const h = await harness(pool); call = h.call; close = () => h.app.close(); });
afterAll(async () => { await close?.(); await pool?.end(); });

const me = async (subject: string) => (await call('GET', '/v1/me', undefined, null, subject)).json().data as { personId: string; displayName: string; version: number };
const rename = (displayName: unknown, version: number | null, subject: string) =>
  call('PATCH', '/v1/me/profile', { displayName } as Record<string, unknown>, version, subject);

describe('Profil personnel (#64)', () => {
  it('un moniteur et un administrateur renomment leur propre compte, sans dossier élève', async () => {
    for (const subject of ['demo-instructor', 'demo-admin']) {
      const before = await me(subject);
      const response = await rename('  Nom choisi  ', before.version, subject);
      expect(response.statusCode, response.body).toBe(200);
      expect(response.json().data).toEqual({ personId: before.personId, displayName: 'Nom choisi', version: before.version + 1 });
      expect(response.headers.etag).toBe(`"${before.version + 1}"`);
      expect(await me(subject)).toMatchObject({ displayName: 'Nom choisi', version: before.version + 1 });
    }
  });

  it('un renvoi après une réponse perdue retrouve le nom déjà enregistré sans conflit', async () => {
    const before = await me('demo-instructor');
    expect((await rename('Nom rejoué', before.version, 'demo-instructor')).statusCode).toBe(200);
    const replay = await rename('Nom rejoué', before.version, 'demo-instructor');
    expect(replay.statusCode, replay.body).toBe(200);
    expect(replay.json().data.version).toBe(before.version + 1);
  });

  it('refuse une version périmée, une version absente et un nom invalide', async () => {
    const before = await me('demo-admin');
    expect((await rename('Autre nom', before.version - 1 || 99, 'demo-admin')).json().code).toBe('VERSION_CONFLICT');
    expect((await rename('Autre nom', null, 'demo-admin')).statusCode).toBe(428);
    for (const bad of ['', '   ', 'x'.repeat(201), 'Nom\u0007', 42]) expect((await rename(bad, before.version, 'demo-admin')).statusCode).toBe(400);
    expect(await me('demo-admin')).toMatchObject({ displayName: before.displayName, version: before.version });
  });

  it('ne modifie que la personne connectée, ni ses rôles ni les autres comptes', async () => {
    const other = await me('demo-admin');
    const roles = (await pool.query('SELECT roles,version FROM drivy.membership WHERE id=$1', [id.instructorMember])).rows[0];
    const before = await me('demo-instructor');
    expect((await rename('Seulement moi', before.version, 'demo-instructor')).statusCode).toBe(200);
    expect(await me('demo-admin')).toEqual(other);
    expect((await pool.query('SELECT roles,version FROM drivy.membership WHERE id=$1', [id.instructorMember])).rows[0]).toEqual(roles);
  });

  it('la base refuse un renommage hors de la route du profil personnel', async () => {
    const db = await pool.connect();
    try {
      await db.query('BEGIN'); await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.person_id',$1,true)", [id.instructor]);
      // Sans la route du profil, la base refuse l'écriture (politique d'accès 002 : WITH CHECK false).
      await db.query('SAVEPOINT direct');
      await expect(db.query("UPDATE drivy.person SET display_name='Contournement' WHERE id=$1", [id.instructor])).rejects.toThrow(/row-level security/);
      await db.query('ROLLBACK TO SAVEPOINT direct');
      await db.query("SELECT set_config('app.self_profile','true',true)");
      // Même avec la route, le compte d'une autre personne reste invisible et intouché.
      expect((await db.query("UPDATE drivy.person SET display_name='Autrui' WHERE id=$1", [id.admin])).rowCount).toBe(0);
      expect((await db.query("UPDATE drivy.person SET display_name='Moi' WHERE id=$1", [id.instructor])).rowCount).toBe(1);
    } finally { await db.query('ROLLBACK'); db.release(); }
  });
});
