import { buildRecoveryDirectGuard, recoveryGuardConfig } from './recovery-direct-guard.js';

/**
 * Separate entry point of the direct recovery frontier. The current web application never starts it: installing it and
 * replacing the Caddy refusal stays a distinct, reviewed production operation.
 */
try {
  const guard = buildRecoveryDirectGuard(recoveryGuardConfig(process.env));
  const stop = async () => { await guard.close(); process.exit(0); };
  process.on('SIGINT', stop); process.on('SIGTERM', stop);
  const { host, port } = await guard.listen();
  process.stdout.write(`Garde de récupération directe en écoute sur ${host}:${port}, chemin ${guard.routePath}.\n`);
} catch {
  process.stderr.write('Démarrage de la garde interrompu. Vérifier la configuration privée.\n');
  process.exit(1);
}
