import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { basename, isAbsolute, join, relative } from 'node:path';
import { tmpdir } from 'node:os';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const scriptPath = 'scripts/ios/relay-qualification.sh';
const windowsBash = 'C:/Program Files/Git/bin/bash.exe';
const bash = process.platform === 'win32' && existsSync(windowsBash) ? windowsBash : 'bash';
const openssl = 'openssl';
const bashAvailable = spawnSync(bash, ['--version'], { encoding: 'utf8' }).status === 0;
const opensslAvailable = spawnSync(openssl, ['version'], { encoding: 'utf8' }).status === 0;

const CASE_PREFIX = 'drivy-relay-diag-';

function bashPath(value) {
  return value.replaceAll('\\', '/');
}

function createCaseRoot(label) {
  return realpathSync(mkdtempSync(join(tmpdir(), `${CASE_PREFIX}${label}-`)));
}

function discardCaseRoot(directory) {
  const resolved = realpathSync(directory);
  const temporaryBase = realpathSync(tmpdir());
  const inside = relative(temporaryBase, resolved);
  assert.ok(inside.length > 0 && !inside.startsWith('..') && !isAbsolute(inside),
            'nettoyage refusé hors de la racine temporaire');
  assert.ok(basename(resolved).startsWith(CASE_PREFIX), 'nettoyage refusé : racine inattendue');
  rmSync(resolved, { recursive: true, force: true });
}

function runOpenssl(cwd, args) {
  const result = spawnSync(openssl, args, { cwd, encoding: 'utf8', timeout: 60_000 });
  assert.equal(result.status, 0, `openssl ${args[0]} a échoué`);
}

function createCertificateAuthority(directory, stem, commonName) {
  writeFileSync(join(directory, `${stem}.cnf`), [
    '[req]',
    'distinguished_name = dn',
    'prompt = no',
    'x509_extensions = ca',
    '[dn]',
    `CN = ${commonName}`,
    '[ca]',
    'basicConstraints = critical,CA:true,pathlen:0',
    'keyUsage = critical,keyCertSign,cRLSign',
    'subjectKeyIdentifier = hash',
    ''
  ].join('\n'));
  runOpenssl(directory, ['req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-days', '2',
    '-config', `${stem}.cnf`, '-keyout', `${stem}.key`, '-out', `${stem}.crt`]);
}

function createServerCertificate(directory, authorityStem, subjectAltName) {
  writeFileSync(join(directory, 'server.cnf'), [
    '[req]',
    'distinguished_name = dn',
    'prompt = no',
    '[dn]',
    'CN = localhost',
    ''
  ].join('\n'));
  runOpenssl(directory, ['req', '-new', '-newkey', 'rsa:2048', '-nodes', '-sha256',
    '-config', 'server.cnf', '-keyout', 'server.key', '-out', 'server.csr']);
  writeFileSync(join(directory, 'server.ext'), [
    '[server]',
    'basicConstraints = critical,CA:false',
    'keyUsage = critical,digitalSignature,keyEncipherment',
    'extendedKeyUsage = serverAuth',
    `subjectAltName = ${subjectAltName}`,
    'subjectKeyIdentifier = hash',
    'authorityKeyIdentifier = keyid,issuer',
    ''
  ].join('\n'));
  runOpenssl(directory, ['x509', '-req', '-sha256', '-days', '2', '-in', 'server.csr',
    '-CA', `${authorityStem}.crt`, '-CAkey', `${authorityStem}.key`, '-CAcreateserial',
    '-extfile', 'server.ext', '-extensions', 'server', '-out', 'server.crt']);
}

const VERIFY_SNIPPET = `
set -u
source scripts/ios/relay-qualification.sh
relay_directory="$DRIVY_TEST_RELAY_DIR"
relay_probe_file="$DRIVY_TEST_PROBE_FILE"
: > "$relay_probe_file"
relay_verify_chain
status=$?
cat "$relay_probe_file"
exit "$status"
`;

function verifyChain(directory) {
  const probeFile = join(directory, 'relay-probe.txt');
  const result = spawnSync(bash, ['-c', VERIFY_SNIPPET], {
    cwd: root,
    encoding: 'utf8',
    timeout: 60_000,
    env: {
      ...process.env,
      DRIVY_TEST_RELAY_DIR: bashPath(directory),
      DRIVY_TEST_PROBE_FILE: bashPath(probeFile)
    }
  });
  const probe = existsSync(probeFile) ? readFileSync(probeFile, 'utf8') : '';
  return { ...result, probe };
}

function readMarkers(probe) {
  const markers = {};
  for (const line of probe.split(/\r?\n/).filter(Boolean)) {
    const match = /^mark=(chain|loopback_identity) value=(ok|ko) utc=\d\d:\d\d:\d\d$/.exec(line);
    assert.ok(match, `marqueur inattendu : ${line}`);
    markers[match[1]] = match[2];
  }
  return markers;
}

function assertNoLeak(result, directory, extra = []) {
  const output = `${result.stdout}${result.stderr}`;
  const forbidden = [
    directory,
    bashPath(directory),
    'BEGIN ',
    'PRIVATE KEY',
    'ca.crt',
    'ca.key',
    'server.crt',
    'server.key',
    'server.csr',
    'server.ext',
    'server.cnf',
    'Drivy Synthetic',
    ...extra
  ];
  for (const value of forbidden) {
    assert.equal(output.includes(value), false, `fuite interdite : ${value}`);
  }
}

test('les outils locaux requis sont disponibles', () => {
  assert.equal(bashAvailable, true, 'bash requis pour le test du harnais');
  assert.equal(opensslAvailable, true, 'openssl requis pour les certificats synthétiques');
});

test('le script de relais reste syntaxiquement valide', () => {
  const result = spawnSync(bash, ['-n', scriptPath], { cwd: root, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
});

test('aucun contournement TLS ni nouvelle confiance générale', () => {
  const script = readFileSync(fileURLToPath(new URL(`../../${scriptPath}`, import.meta.url)), 'utf8');
  assert.equal(/NODE_TLS_REJECT_UNAUTHORIZED/.test(script), false);
  assert.equal(/--insecure/.test(script), false);
  assert.equal(/curl[^\n]*\s-k\b/.test(script), false);
  assert.match(script, /xcrun simctl keychain "\$1" add-root-cert "\$relay_directory\/ca\.crt"/);
  assert.match(script, /relay_verify_chain \|\| return 1/);
  assert.match(script, /-verify_hostname localhost/);
  assert.match(script, /-verify_ip 127\.0\.0\.1/);
});

test('chaîne valide et identité loopback exacte réussissent sans fuite', () => {
  const directory = createCaseRoot('valid');
  try {
    createCertificateAuthority(directory, 'ca', 'Drivy Synthetic Test CA');
    createServerCertificate(directory, 'ca', 'DNS:localhost,IP:127.0.0.1');
    const result = verifyChain(directory);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, '');
    assert.deepEqual(readMarkers(result.probe), { chain: 'ok', loopback_identity: 'ok' });
    assertNoLeak(result, directory);
  } finally {
    discardCaseRoot(directory);
  }
});

test('un SAN localhost.evil ne satisfait pas le nom exact', () => {
  const directory = createCaseRoot('hostname-near-miss');
  try {
    createCertificateAuthority(directory, 'ca', 'Drivy Synthetic Test CA');
    createServerCertificate(directory, 'ca', 'DNS:localhost.evil,IP:127.0.0.1');
    const result = verifyChain(directory);
    assert.equal(result.status, 1);
    assert.equal(result.stderr.trim(), 'RELAY_TLS_CHAIN_INVALID');
    assert.deepEqual(readMarkers(result.probe), { chain: 'ok', loopback_identity: 'ko' });
    assertNoLeak(result, directory, ['localhost.evil']);
  } finally {
    discardCaseRoot(directory);
  }
});

test('un SAN 127.0.0.10 ne satisfait pas l IP exacte', () => {
  const directory = createCaseRoot('ip-near-miss');
  try {
    createCertificateAuthority(directory, 'ca', 'Drivy Synthetic Test CA');
    createServerCertificate(directory, 'ca', 'DNS:localhost,IP:127.0.0.10');
    const result = verifyChain(directory);
    assert.equal(result.status, 1);
    assert.equal(result.stderr.trim(), 'RELAY_TLS_CHAIN_INVALID');
    assert.deepEqual(readMarkers(result.probe), { chain: 'ok', loopback_identity: 'ko' });
    assertNoLeak(result, directory, ['127.0.0.10']);
  } finally {
    discardCaseRoot(directory);
  }
});

test('un certificat signé par une autre autorité est refusé', () => {
  const directory = createCaseRoot('wrong-chain');
  try {
    createCertificateAuthority(directory, 'ca', 'Drivy Synthetic Test CA');
    createCertificateAuthority(directory, 'other-ca', 'Drivy Synthetic Other CA');
    createServerCertificate(directory, 'other-ca', 'DNS:localhost,IP:127.0.0.1');
    const result = verifyChain(directory);
    assert.equal(result.status, 1);
    assert.equal(result.stderr.trim(), 'RELAY_TLS_CHAIN_INVALID');
    assert.deepEqual(readMarkers(result.probe), { chain: 'ko', loopback_identity: 'ko' });
    assertNoLeak(result, directory);
  } finally {
    discardCaseRoot(directory);
  }
});

test('absence de preuve échoue honnêtement sans exposer de chemin', () => {
  const directory = createCaseRoot('absent');
  try {
    const result = verifyChain(directory);
    assert.equal(result.status, 1);
    assert.equal(result.stderr.trim(), 'RELAY_TLS_CHAIN_INVALID');
    assert.deepEqual(readMarkers(result.probe), { chain: 'ko', loopback_identity: 'ko' });
    assertNoLeak(result, directory);
  } finally {
    discardCaseRoot(directory);
  }
});

test('les marqueurs restent un vocabulaire fermé', () => {
  const directory = createCaseRoot('markers');
  try {
    const probeFile = join(directory, 'relay-probe.txt');
    const result = spawnSync(bash, ['-c', `
set -u
source scripts/ios/relay-qualification.sh
relay_probe_file="$DRIVY_TEST_PROBE_FILE"
relay_mark chain ok
relay_mark 'subject=CN=SENTINEL_TOKEN' 'value with space'
relay_mark loopback_identity ko
cat "$relay_probe_file"
`], {
      cwd: root,
      encoding: 'utf8',
      timeout: 30_000,
      env: { ...process.env, DRIVY_TEST_PROBE_FILE: bashPath(probeFile) }
    });
    assert.equal(result.status, 0, result.stderr);
    const lines = result.stdout.trim().split('\n');
    assert.equal(lines.length, 2, result.stdout);
    for (const line of lines) {
      assert.match(line, /^mark=(chain|loopback_identity) value=(ok|ko) utc=\d\d:\d\d:\d\d$/);
    }
    assert.equal(result.stdout.includes('SENTINEL_TOKEN'), false);
  } finally {
    discardCaseRoot(directory);
  }
});
