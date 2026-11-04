import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const scriptPath = 'scripts/ios/relay-qualification.sh';
const windowsBash = 'C:/Program Files/Git/bin/bash.exe';
const bash = process.platform === 'win32' && existsSync(windowsBash) ? windowsBash : 'bash';
const hasBash = spawnSync(bash, ['--version'], { encoding: 'utf8' }).status === 0;
const skip = hasBash ? false : 'bash absent de cet hôte';

function runBash(source) {
  return spawnSync(bash, ['-c', source], { cwd: root, encoding: 'utf8', timeout: 20_000 });
}

test('le script de relais reste syntaxiquement valide', { skip }, () => {
  const result = spawnSync(bash, ['-n', scriptPath], { cwd: root, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
});

test('la preuve de chaîne vérifie les certificats générés de ce run', { skip }, () => {
  const script = readFileSync(fileURLToPath(new URL(`../../${scriptPath}`, import.meta.url)), 'utf8');
  assert.match(script, /relay_verify_chain\(\)/);
  assert.match(script, /openssl verify -CAfile "\$relay_directory\/ca\.crt" "\$relay_directory\/server\.crt"/);
  assert.match(script, /relay_mark chain "\$chain"/);
  assert.match(script, /relay_mark loopback_identity "\$identity"/);
  assert.match(script, /if \[\[ "\$chain" != ok \|\| "\$identity" != ok \]\]; then[\s\S]*?return 1/);
  assert.match(script, /relay_verify_chain \|\| return 1/);
});

test('les marqueurs restent un vocabulaire fermé', { skip }, () => {
  const result = runBash(`
set -u
source scripts/ios/relay-qualification.sh
relay_probe_file="$PWD/artifacts/relais-diagnostic-78/markers-$$.txt"
: > "$relay_probe_file"
relay_mark chain ok
relay_mark 'subject=CN=SENTINEL_TOKEN' 'value with space'
relay_mark loopback_identity ko
cat "$relay_probe_file"
rm -f "$relay_probe_file"
`);
  assert.equal(result.status, 0, result.stderr);
  const lines = result.stdout.trim().split('\n');
  assert.equal(lines.length, 2, result.stdout);
  for (const line of lines) {
    assert.match(line, /^mark=(chain|loopback_identity) value=(ok|ko) utc=\d\d:\d\d:\d\d$/);
  }
  assert.equal(result.stdout.includes('SENTINEL_TOKEN'), false);
});

test('une preuve absente échoue honnêtement sans exposer de chemin', { skip }, () => {
  const result = runBash(`
set -u
source scripts/ios/relay-qualification.sh
relay_probe_file="$PWD/artifacts/relais-diagnostic-78/verify-$$.txt"
relay_directory="$PWD/artifacts/relais-diagnostic-78/absent-$$"
mkdir -p "$relay_directory"
: > "$relay_probe_file"
relay_verify_chain
status=$?
cat "$relay_probe_file"
rm -rf "$relay_directory" "$relay_probe_file"
exit "$status"
`);
  assert.equal(result.status, 1);
  assert.match(result.stdout, /^mark=chain value=ko /m);
  assert.match(result.stdout, /^mark=loopback_identity value=ko /m);
  assert.equal(result.stderr.trim(), 'RELAY_TLS_CHAIN_INVALID');
  assert.equal(result.stderr.includes(root), false);
  assert.equal(result.stdout.includes(root), false);
});

test('aucun contournement TLS ni nouvelle confiance générale', () => {
  const script = readFileSync(fileURLToPath(new URL(`../../${scriptPath}`, import.meta.url)), 'utf8');
  assert.equal(/NODE_TLS_REJECT_UNAUTHORIZED/.test(script), false);
  assert.equal(/--insecure/.test(script), false);
  assert.equal(/curl[^\n]*\s-k\b/.test(script), false);
  assert.match(script, /xcrun simctl keychain "\$1" add-root-cert "\$relay_directory\/ca\.crt"/);
});

test('la fonction de chaîne redirige les sorties brutes des certificats', { skip }, () => {
  const script = readFileSync(fileURLToPath(new URL(`../../${scriptPath}`, import.meta.url)), 'utf8');
  const start = script.indexOf('relay_verify_chain() {');
  assert.notEqual(start, -1);
  const end = script.indexOf('\n}', start);
  assert.notEqual(end, -1);
  const block = script.slice(start, end);
  for (const line of block.split('\n').filter((value) => value.includes('openssl '))) {
    assert.match(line, /2>\/dev\/null|> \/dev\/null 2>&1/);
  }
  assert.equal(block.includes('echo "$relay_directory'), false);
  assert.equal(block.includes('echo "$subject'), false);
});
