import { readdir } from 'node:fs/promises';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Pool } from 'pg';
import { freshDatabase } from './support/harness.js';

describe('messaging migrations with the non-privileged integration owner', () => {
  let pool: Pool;
  beforeAll(async () => { pool = await freshDatabase(); });
  afterAll(async () => { await pool?.end(); });

  it('lets the constrained owner lock authorization rows without granting membership writes', async () => {
    const db = await pool.connect();
    try {
      await db.query('BEGIN');
      await db.query('SET LOCAL ROLE drivy_harness_migrator');
      const rows = await db.query<{ id: string }>('SELECT id FROM drivy.membership FOR SHARE');
      expect(rows.rowCount).toBeGreaterThan(0);
      await expect(db.query('UPDATE drivy.membership SET status=status WHERE id=$1', [rows.rows[0]!.id]))
        .rejects.toMatchObject({ code: '42501' });
    } finally { await db.query('ROLLBACK'); db.release(); }
  });

  it('applies every production migration including dated messaging revisions', async () => {
    const files = (await readdir(new URL('../migrations/', import.meta.url)))
      .filter(name => /^\d+[a-z]?_[a-z0-9_]+\.sql$/.test(name)).sort();
    const applied = await pool.query<{ name: string }>('SELECT name FROM public.drivy_migrations ORDER BY name');
    expect(applied.rows.map(row => row.name)).toEqual(files);
    const tables = await pool.query<{ relname: string; relrowsecurity: boolean; relforcerowsecurity: boolean }>(
      `SELECT relname,relrowsecurity,relforcerowsecurity FROM pg_class
       WHERE relnamespace='drivy'::regnamespace AND relname IN ('messaging_conversation','messaging_member_link','messaging_device') ORDER BY relname`);
    expect(tables.rows).toEqual(['messaging_conversation', 'messaging_device', 'messaging_member_link']
      .map(relname => ({ relname, relrowsecurity: true, relforcerowsecurity: true })));
    const owners = await pool.query<{ rolsuper: boolean; rolbypassrls: boolean }>(
      `SELECT r.rolsuper,r.rolbypassrls FROM pg_class c JOIN pg_roles r ON r.oid=c.relowner
       WHERE c.oid='drivy.messaging_conversation'::regclass`);
    expect(owners.rows).toEqual([{ rolsuper: false, rolbypassrls: false }]);
  });
});
