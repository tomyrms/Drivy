import { Pool } from 'pg';
import { seedFixtures } from './fixtures.js';

if (process.env.NODE_ENV === 'production' || process.env.ALLOW_FIXTURES !== 'true') {
  throw new Error('Fixtures réservées au développement/test avec ALLOW_FIXTURES=true explicite.');
}
if (!process.env.MIGRATION_DATABASE_URL || !process.env.OIDC_ISSUER) throw new Error('MIGRATION_DATABASE_URL et OIDC_ISSUER sont obligatoires.');
const database = new URL(process.env.MIGRATION_DATABASE_URL).pathname.slice(1);
if (!/^drivy_(dev|test)$/.test(database)) throw new Error('Fixtures autorisées uniquement dans drivy_dev ou drivy_test.');
const pool = new Pool({ connectionString: process.env.MIGRATION_DATABASE_URL });
try {
  await seedFixtures(pool, process.env.OIDC_ISSUER);
  console.log('Fixtures fictives chargées. Aucun fournisseur OIDC ni compte réel créé.');
} finally { await pool.end(); }
