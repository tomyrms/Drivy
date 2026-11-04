import { Pool } from 'pg';

/**
 * Purge manuelle des dépôts orphelins (#97, T1). Aucune planification, aucune durée de conservation par défaut.
 * La fonction SQL de maintenance n'est exécutable que par le rôle propriétaire : ce script utilise donc
 * MIGRATION_DATABASE_URL, jamais le rôle applicatif.
 *
 * Sans --apply, le script ne fait qu'un compte (simulation). --cutoff est obligatoire et explicite.
 * Une cible non locale est refusée sauf --allow-remote-target explicite : la recette ne doit pas purger ailleurs.
 */
const args = process.argv.slice(2);
if (args.includes('--help') || args.includes('-h')) {
  console.log('Usage : purge-messaging-media --cutoff <ISO-8601> [--apply] [--allow-remote-target]');
  console.log('  --cutoff               horodatage explicite : seuls les dépôts antérieurs sont éligibles (obligatoire).');
  console.log('  --apply                applique la purge ; sans ce drapeau, seule une simulation est affichée.');
  console.log('  --allow-remote-target  autorise une cible non locale (jamais pendant la recette locale).');
  process.exit(0);
}
function option(name: string): string | undefined {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}
const cutoffText = option('--cutoff');
const apply = args.includes('--apply');
const allowRemoteTarget = args.includes('--allow-remote-target');
const url = process.env.MIGRATION_DATABASE_URL;
if (!cutoffText || !url) {
  console.error('Refus : --cutoff explicite et MIGRATION_DATABASE_URL sont obligatoires ; aucune base implicite.');
  process.exit(2);
}
const cutoff = new Date(cutoffText);
if (Number.isNaN(cutoff.getTime())) {
  console.error('Refus : --cutoff doit être un horodatage ISO-8601 valide.');
  process.exit(2);
}
const host = new URL(url).hostname;
const loopback = ['127.0.0.1', '::1', 'localhost', '[::1]'].includes(host);
if (!loopback && !allowRemoteTarget) {
  console.error('Refus : cible non locale ; --allow-remote-target est exigé explicitement hors recette locale.');
  process.exit(2);
}
const pool = new Pool({ connectionString: url });
try {
  if (!apply) {
    const count = await pool.query<{ count: number }>(`SELECT count(*)::int AS count FROM drivy.messaging_media
      WHERE message_id IS NULL AND ciphertext IS NOT NULL AND created_at < $1`, [cutoff]);
    console.log(`Simulation : ${count.rows[0]?.count ?? 0} dépôt(s) orphelin(s) antérieur(s) à ${cutoff.toISOString()}. Aucune écriture.`);
  } else {
    const result = await pool.query<{ purged: number }>('SELECT drivy.messaging_purge_orphan_media($1) AS purged', [cutoff]);
    console.log(`Purge appliquée : ${result.rows[0]?.purged ?? 0} dépôt(s) orphelin(s) purgé(s) avant ${cutoff.toISOString()}.`);
  }
} catch (error) {
  // Diagnostic borné : aucun identifiant de média, aucune taille, aucun octet.
  const code = typeof error === 'object' && error !== null && 'code' in error ? String(error.code) : 'inconnu';
  console.error(`Échec de la purge manuelle (code ${code}).`);
  process.exitCode = 1;
} finally {
  await pool.end();
}
