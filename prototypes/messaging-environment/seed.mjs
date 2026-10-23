// Node 24 natif : les deux helpers TS existants ne contiennent que des types effaçables.
import { createRequire } from 'node:module';
import { migrate } from '../../apps/api/scripts/migrations.ts';
import { seedFixtures } from '../../apps/api/scripts/fixtures.ts';

if (process.versions.node.split('.')[0] !== '24' ||
    process.argv.slice(2).join(' ') !== '--synthetic-only' || process.env.NODE_ENV === 'production') {
  throw new Error('Confirmation synthétique explicite obligatoire.');
}
// Ne lire aucune URL de base ambiante : port et base exclusivement dédiés.
const require = createRequire(new URL('../../apps/api/package.json', import.meta.url));
const { Pool } = require('pg');
const pool = new Pool({
  connectionString: 'postgresql://drivy_fixture:synthetic-public-fixture-only@127.0.0.1:55468/drivy_test',
  max: 1,
  connectionTimeoutMillis: 5000,
});
try {
  const result = await pool.query('SELECT label FROM synthetic_environment.marker');
  if (result.rows.length !== 1 || result.rows[0].label !== 'drivy-messaging-fixtures-only-v1') {
    throw new Error('Marqueur synthétique absent.');
  }
  await migrate(pool);
  // Pas de TRUNCATE ni de reset : helpers existants, aucun test lancé.
  await seedFixtures(pool, 'https://messaging.test.invalid');
  console.log('Migrations et fixtures synthétiques chargées. Aucun scénario exécuté.');
} catch {
  console.error('Préparation synthétique interrompue. Aucun détail SQL ou contenu affiché.');
  process.exitCode = 1;
} finally {
  await pool.end();
}
