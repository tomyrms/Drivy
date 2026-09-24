import { Pool } from 'pg';
import { migrate } from './migrations.js';

if (!process.env.MIGRATION_DATABASE_URL) throw new Error('MIGRATION_DATABASE_URL est obligatoire ; aucune base implicite.');
const pool = new Pool({ connectionString: process.env.MIGRATION_DATABASE_URL });
try { await migrate(pool); console.log('Migrations Drivy appliquées et empreintes vérifiées.'); }
finally { await pool.end(); }
