import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { qualificationConfig } from './messaging-relay-qualification.mts';

const base = {
  NODE_ENV: 'test', DRIVY_RELAY_ALLOW_RESET: '1',
  TEST_DATABASE_URL: 'postgresql://fixture:fixture@127.0.0.1:15432/drivy_test',
  DRIVY_RELAY_TLS_CERT: '/temporary/localhost.crt', DRIVY_RELAY_TLS_KEY: '/temporary/localhost.key'
};
test('accepts only explicit disposable loopback fixture configuration', () => {
  assert.equal(qualificationConfig(base).port, 18443);
});
for (const [name, changes] of [
  ['production mode', { NODE_ENV: 'production' }],
  ['missing reset opt-in', { DRIVY_RELAY_ALLOW_RESET: '' }],
  ['remote database', { TEST_DATABASE_URL: 'postgresql://fixture:fixture@db.example.invalid/drivy_test' }],
  ['wrong database', { TEST_DATABASE_URL: 'postgresql://fixture:fixture@localhost/production' }],
  ['host override parameter', { TEST_DATABASE_URL: 'postgresql://fixture:fixture@localhost/drivy_test?host=remote' }],
  ['TLS absent', { DRIVY_RELAY_TLS_CERT: '' }],
  ['invalid port', { DRIVY_RELAY_PORT: '0' }]
]) {
  test(`refuses ${name} without disclosing configuration`, () => {
    assert.throws(() => qualificationConfig({ ...base, ...changes }), /^Error: RELAY_QUALIFICATION_CONFIGURATION_REQUIRED$/);
  });
}

test('CLI fails closed without exposing supplied configuration', () => {
  const sentinel = 'SYNTHETIC_SENTINEL_NEVER_PRINT';
  const child = spawnSync(process.execPath,
    ['--import', 'tsx', fileURLToPath(new URL('./messaging-relay-qualification.mts', import.meta.url))],
    { encoding: 'utf8', timeout: 30_000, env: { ...process.env, NODE_ENV: 'production',
      DRIVY_RELAY_ALLOW_RESET: '1', TEST_DATABASE_URL: `postgresql://fixture:${sentinel}@127.0.0.1/drivy_test` } });
  assert.equal(child.status, 1);
  assert.equal(child.stdout, '');
  assert.equal(child.stderr.trim(), 'RELAY_QUALIFICATION_START_FAILED');
  assert.equal((child.stdout + child.stderr).includes(sentinel), false);
});
