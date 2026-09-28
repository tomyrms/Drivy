import { Pool } from 'pg';
import { buildApp } from './app.js';
import { createTokenVerifier } from './auth.js';
import { readConfig } from './config.js';
import { invitationMailConfig } from './invitation-mail.js';
import { readCaptureConfig } from './capture-crypto.js';

const config = readConfig();
const pool = new Pool({ connectionString: config.DATABASE_URL, max: 10, connectionTimeoutMillis: 5000, statement_timeout: 5000 });
try {
  const role = await pool.query<{ rolsuper: boolean; rolbypassrls: boolean }>('SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user');
  const applicationRole = await pool.query<{ rolsuper: boolean; rolbypassrls: boolean }>("SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname='drivy_app'");
  if (!applicationRole.rows[0] || applicationRole.rows[0].rolsuper || applicationRole.rows[0].rolbypassrls) {
    throw new Error('Le rôle drivy_app est absent ou peut contourner la RLS.');
  }
  if (config.NODE_ENV === 'production' && (!role.rows[0] || role.rows[0].rolsuper || role.rows[0].rolbypassrls)) {
    throw new Error('La connexion de production doit utiliser un rôle sans superuser/BYPASSRLS.');
  }
  const invitationMail=invitationMailConfig();
  const capture=readCaptureConfig();
  const app = buildApp({ pool, verifyToken: createTokenVerifier(config), cursorSecret: config.CURSOR_SECRET, reauthMaxAgeSeconds:config.REAUTH_MAX_AGE_SECONDS,logger: true,...(invitationMail?{invitationMail}:{}),...(capture?{capture}:{}) });
  const shutdown = async () => { await app.close(); await pool.end(); };
  process.once('SIGINT', () => { void shutdown(); });
  process.once('SIGTERM', () => { void shutdown(); });
  await app.listen({ host: config.HOST, port: config.PORT });
} catch {
  await pool.end();
  console.error('Démarrage API impossible. Vérifier configuration, identité et base de données.');
  process.exitCode = 1;
}
