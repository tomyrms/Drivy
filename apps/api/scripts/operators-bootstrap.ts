import { Pool } from 'pg';
import { bootstrapPlatformOperators, readBootstrapEntries } from '../src/platform-bootstrap.js';

// Mise en service des premiers opérateurs de la plateforme. Procédure : docs/implementation/console-operateurs-20261113.md.
// Aucune identité n'est lue d'un fichier du dépôt : seulement de l'environnement privé de l'exploitation.
if (!process.env.MIGRATION_DATABASE_URL) throw new Error('MIGRATION_DATABASE_URL est obligatoire ; aucune base implicite.');
const legacyOpeningOperators = process.argv.includes('--legacy-opening-operators');
const entries = readBootstrapEntries(process.env, { legacyOpeningOperators });
const pool = new Pool({ connectionString: process.env.MIGRATION_DATABASE_URL });
try {
  const report = await bootstrapPlatformOperators(pool, entries);
  console.log(`Opérateurs de la plateforme : ${report.added} ajouté(s), ${report.alreadyActive} déjà actif(s).`);
} finally { await pool.end(); }
