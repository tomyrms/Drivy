import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const project = 'drivy-messaging-synthetic';
const marker = 'drivy-messaging-fixtures-only-v1';
const image = 'postgres:17-alpine@sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24';
const args = process.argv.slice(2);
const commands = ['up', 'seed', 'backup', 'restore', 'stop'];
const env = { ...process.env, COMPOSE_DISABLE_ENV_FILE: '1' };
// Aucune surcharge de compose, URL DB ou contexte par variables ambiantes.
for (const key of Object.keys(env)) {
  if (key.startsWith('COMPOSE_') && key !== 'COMPOSE_DISABLE_ENV_FILE') delete env[key];
}
const compose = ['compose', '--project-name', project, '--project-directory', root,
  '--file', fileURLToPath(new URL('compose.yaml', import.meta.url)), '--profile', 'restore'];

function run(program, arguments_, input) {
  const result = spawnSync(program, arguments_, {
    cwd: root, env, input, maxBuffer: 64 * 1024 * 1024, timeout: 120000,
    windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'],
  });
  if (result.error || result.status !== 0) {
    // Pas de stderr brut : erreurs SQL et diagnostics peuvent contenir des valeurs.
    throw new Error('Commande interrompue. Sortie détaillée volontairement masquée.');
  }
  return result.stdout;
}
function docker(arguments_, input) { return run('docker', [...compose, ...arguments_], input); }
function exec(service, arguments_, input) { return docker(['exec', '-T', service, ...arguments_], input); }
function sql(service, database, statement) {
  return exec(service, ['psql', '-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1',
    '-U', 'drivy_fixture', '-d', database, '-c', statement]).toString().trim();
}
function assertMarker(service, database) {
  if (sql(service, database, 'SELECT label FROM synthetic_environment.marker') !== marker) {
    throw new Error('Marqueur synthétique absent.');
  }
}
function hash(bytes) { return createHash('sha256').update(bytes).digest('hex'); }

try {
  if (process.versions.node.split('.')[0] !== '24') {
    throw new Error('Node 24 requis, conformément au package.json du dépôt.');
  }
  if (args.length !== 2 || !commands.includes(args[0]) || args[1] !== '--synthetic-only') {
    throw new Error('Usage : node environment.mjs up|seed|backup|restore|stop --synthetic-only');
  }
  if (process.env.NODE_ENV === 'production' || process.env.DOCKER_HOST || process.env.DOCKER_CONTEXT) {
    throw new Error('Production et surcharges Docker interdites.');
  }
  const contexts = JSON.parse(run('docker', ['context', 'inspect']).toString());
  const context = contexts[0];
  const endpoint = context?.Endpoints?.docker?.Host ?? '';
  const localEndpoint = endpoint.startsWith('unix:///') || endpoint.startsWith('npipe:////./pipe/');
  if (contexts.length !== 1 || !localEndpoint) {
    throw new Error('Seul un moteur Docker local via pipe/socket est autorisé.');
  }
  // Figer le contexte inspecté pour éviter un changement concurrent du contexte courant.
  compose.unshift('--context', context.Name);
  const command = args[0];
  if (command === 'up') {
    docker(['up', '-d', '--wait', '--no-build', '--pull', 'never', 'fixtures']);
    assertMarker('fixtures', 'drivy_test');
  } else if (command === 'seed') {
    assertMarker('fixtures', 'drivy_test');
    run(process.execPath, [fileURLToPath(new URL('seed.mjs', import.meta.url)), '--synthetic-only']);
  } else if (command === 'backup') {
    assertMarker('fixtures', 'drivy_test');
    const directory = new URL('.state/', import.meta.url);
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    const archivePath = new URL('snapshot.dump', directory);
    const manifestPath = new URL('snapshot.json', directory);
    if (existsSync(archivePath) || existsSync(manifestPath)) throw new Error('Sauvegarde déjà présente, aucun écrasement autorisé.');
    const bytes = exec('fixtures', ['pg_dump', '-U', 'drivy_fixture', '-d', 'drivy_test',
      '--format=custom', '--no-owner', '--no-acl']);
    // Archive locale NON chiffrée, exclusivement synthétique. Jamais de fallback de production.
    writeFileSync(archivePath, bytes, { flag: 'wx', mode: 0o600 });
    writeFileSync(manifestPath, JSON.stringify({
      schema: 1, marker, image, database: 'drivy_test', syntheticOnly: true,
      encrypted: false, sha256: hash(bytes), bytes: bytes.length,
      createdAt: new Date().toISOString(),
    }, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
  } else if (command === 'restore') {
    const bytes = readFileSync(new URL('.state/snapshot.dump', import.meta.url));
    const manifest = JSON.parse(readFileSync(new URL('.state/snapshot.json', import.meta.url), 'utf8'));
    if (manifest.schema !== 1 || manifest.marker !== marker || manifest.image !== image ||
        manifest.database !== 'drivy_test' || manifest.syntheticOnly !== true ||
        manifest.encrypted !== false || manifest.sha256 !== hash(bytes) || manifest.bytes !== bytes.length) {
      throw new Error('Archive ou manifeste incompatible.');
    }
    docker(['up', '-d', '--wait', '--no-build', '--pull', 'never', 'restore']);
    // createdb échoue si la cible existe : pas de DROP, --clean ou écrasement.
    exec('restore', ['createdb', '-U', 'drivy_fixture', 'drivy_restore']);
    exec('restore', ['pg_restore', '-U', 'drivy_fixture', '-d', 'drivy_restore',
      '--exit-on-error', '--single-transaction', '--no-owner', '--no-acl'], bytes);
    assertMarker('restore', 'drivy_restore');
    // La cible ne dispose d'aucun réseau ni port publié. Ne jamais la rouvrir aux utilisateurs.
  } else if (command === 'stop') {
    docker(['stop', 'fixtures', 'restore']);
  }
  console.log(`Opération synthétique ${command} terminée. Aucun résultat de recette revendiqué.`);
} catch (error) {
  console.error(error instanceof Error ? error.message : 'Opération synthétique interrompue.');
  process.exitCode = 1;
}
