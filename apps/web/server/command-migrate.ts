import {createHash} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {realpathSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {Pool} from 'pg';

export async function migrateCommands(pool:Pool) {
  const db=await pool.connect();
  try {
    await db.query('SELECT pg_advisory_lock(179027,4)');
    await db.query('CREATE SCHEMA IF NOT EXISTS drivy_web');
    await db.query('CREATE TABLE IF NOT EXISTS drivy_web.migrations(name text PRIMARY KEY,sha256 text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now())');
    const directory=new URL(import.meta.url.includes('/dist/')?'../../migrations/':'../migrations/',import.meta.url);
    for(const name of (await readdir(directory)).filter(name=>/^\d+_[a-z0-9_]+\.sql$/.test(name)).sort()) {
      const sql=await readFile(new URL(name,directory),'utf8');const hash=createHash('sha256').update(sql).digest('hex');
      const known=(await db.query<{sha256:string}>('SELECT sha256 FROM drivy_web.migrations WHERE name=$1',[name])).rows[0];
      if(known){if(known.sha256!==hash)throw new Error('Migration web modifiée après application');continue;}
      await db.query('BEGIN');
      try{await db.query(sql);await db.query('INSERT INTO drivy_web.migrations(name,sha256) VALUES($1,$2)',[name,hash]);await db.query('COMMIT');}
      catch(error){await db.query('ROLLBACK');throw error;}
    }
  } finally {await db.query('SELECT pg_advisory_unlock(179027,4)');db.release();}
}
async function main(){
  if(!process.env.WEB_COMMAND_MIGRATION_DATABASE_URL)throw new Error('Configuration de migration absente');
  const pool=new Pool({connectionString:process.env.WEB_COMMAND_MIGRATION_DATABASE_URL});
  try{await migrateCommands(pool);process.stdout.write('Migrations du journal web appliquées et empreintes vérifiées.\n');}finally{await pool.end();}
}
if(process.argv[1]&&realpathSync(process.argv[1])===fileURLToPath(import.meta.url)) {
  main().catch(()=>{process.stderr.write('Migration du journal web interrompue. Vérifier les rôles et la configuration privée.\n');process.exitCode=1;});
}
