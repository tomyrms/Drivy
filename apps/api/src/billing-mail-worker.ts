import { Pool } from 'pg';
import { setTimeout } from 'node:timers/promises';
import { billingMailConfig, deliverOneInvoice } from './billing-mail.js';
import { guardPool } from './database.js';

/** Service d'envoi des factures (R01-T07, #459). Rôle sans droit de table ; aucun contenu ni adresse dans ses journaux. */
async function run() {
  const config = billingMailConfig();
  if (!config || !process.env.BILLING_MAIL_DATABASE_URL) throw new Error('Configuration absente.');
  const pool = guardPool(new Pool({ connectionString: process.env.BILLING_MAIL_DATABASE_URL, max: 2, connectionTimeoutMillis: 5000 }));
  try {
    const privileges = await pool.query<{ rolsuper: boolean; rolbypassrls: boolean }>(
      "SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user OR rolname='drivy_billing_mailer'");
    if (privileges.rows.length !== 2 || privileges.rows.some(row => row.rolsuper || row.rolbypassrls)) throw new Error('Rôle non autorisé.');
    let stopping = false;
    process.on('SIGTERM', () => { stopping = true; });
    process.on('SIGINT', () => { stopping = true; });
    while (!stopping) {
      try {
        const processed = await deliverOneInvoice(pool, config);
        if (!processed) await setTimeout(1000);
      } catch {
        process.stderr.write('Worker factures : traitement temporairement indisponible.\n');
        await setTimeout(5000);
      }
    }
  } finally {
    await pool.end();
  }
}

try {
  await run();
} catch {
  process.stderr.write('Worker factures : démarrage impossible, vérifier configuration et droits.\n');
  process.exitCode = 1;
}
