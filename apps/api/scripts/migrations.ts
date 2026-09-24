import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import type { Pool } from 'pg';

export async function migrate(pool: Pool): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query('SELECT pg_advisory_lock(172936,1)');
    await client.query('CREATE TABLE IF NOT EXISTS public.drivy_migrations (name text PRIMARY KEY, sha256 text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())');
    const dir = new URL('../migrations/', import.meta.url);
    const names = (await readdir(dir)).filter(name => /^\d+_[a-z0-9_]+\.sql$/.test(name)).sort();
    for (const name of names) {
      const sql = await readFile(new URL(name, dir), 'utf8');
      const hash = createHash('sha256').update(sql).digest('hex');
      const applied = await client.query<{ sha256: string }>('SELECT sha256 FROM public.drivy_migrations WHERE name=$1', [name]);
      if (applied.rows[0]) {
        if (applied.rows[0].sha256 !== hash) throw new Error(`Migration déjà appliquée modifiée : ${name}`);
        continue;
      }
      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query('INSERT INTO public.drivy_migrations(name,sha256) VALUES ($1,$2)', [name, hash]);
        await client.query('COMMIT');
      } catch (error) { await client.query('ROLLBACK'); throw error; }
    }
  } finally { await client.query('SELECT pg_advisory_unlock(172936,1)'); client.release(); }
}
