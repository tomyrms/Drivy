/** Tests opérateur explicites, uniquement PostgreSQL/Keycloak loopback du laboratoire.
 * node --test --import tsx scripts/dev/provision-school.test.mjs
 * Les rôles/base de test sont créés uniquement s'ils sont absents, puis supprimés.
 */
import assert from 'node:assert/strict';
import { randomBytes, createHash, randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { Pool } from 'pg';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { chromium } from '../../infra/dev/browser.ts';
import { migrate } from '../../apps/api/scripts/migrations.ts';
import { ensureIdentity, issuer, keycloakAdmin, newOperation, parseArguments, provisionDatabase, validateDatabaseURL } from '../../infra/deploy/provision-school.mjs';

const localOrigin = 'http://127.0.0.1:8081';
const localIssuer = `${localOrigin}/realms/drivy-dev`;
const callbackURI = 'ch.drivy.qualification:/oauth/callback';
const input = { username: `probe-bootstrap-${randomBytes(4).toString('hex')}`, schoolName: 'Luc auto école', contactEmail: 'luc@example.com',
  operator: 'test-local', authorizationReference: 'Test synthétique local explicite' };
const state = newOperation(input);
const tables = ['identity_link', 'membership', 'person', 'school'];

async function queryProtection(pool) {
  const result = await pool.query(`SELECT count(*)::int AS count,bool_and(relrowsecurity AND relforcerowsecurity) AS protected
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND c.relname=ANY($1::text[])`, [tables]);
  assert.ok(result.rows[0].count === 4 && result.rows[0].protected === true, 'FORCE RLS doit rester actif partout.');
}
async function loginWithRequiredPasswordChange(username, password, nextPassword) {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const context = await browser.newContext();
  let deliver = () => {};
  const callback = new Promise(resolve => { deliver = resolve; });
  let timer;
  try {
    await context.route('**/*', async route => {
      try {
        const target = new URL(route.request().url());
        if (target.origin !== localOrigin) return route.abort();
        if (route.request().method() === 'POST' && target.pathname.includes('/login-actions/')) {
          const response = await route.fetch({ maxRedirects: 0, timeout: 10_000 });
          const location = response.headers().location;
          if (response.status() === 302 && location?.startsWith(`${callbackURI}?`)) {
            await route.abort('aborted'); await response.dispose(); deliver(location); return;
          }
          return route.fulfill({ response });
        }
        return route.continue();
      } catch { deliver(null); await route.abort().catch(() => {}); }
    });
    const verifier = randomBytes(32).toString('base64url'), nonce = randomBytes(32).toString('base64url'), oauthState = randomUUID();
    const url = new URL(`${localIssuer}/protocol/openid-connect/auth`);
    url.search = new URLSearchParams({ client_id: 'drivy-apple', response_type: 'code', redirect_uri: callbackURI,
      scope: 'openid profile', state: oauthState, nonce, code_challenge: createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256' }).toString();
    const page = await context.newPage();
    await page.goto(url.href, { waitUntil: 'domcontentloaded' });
    await page.locator('input[name="username"]').fill(username);
    await page.locator('input[name="password"]').fill(password);
    await page.locator('input[type="submit"],button[type="submit"]').first().click({ noWaitAfter: true });
    await page.locator('input[name="password-new"]').waitFor({ timeout: 10_000 });
    await page.locator('input[name="password-new"]').fill(nextPassword);
    await page.locator('input[name="password-confirm"]').fill(nextPassword);
    await page.locator('input[type="submit"],button[type="submit"]').first().click({ noWaitAfter: true });
    const location = await Promise.race([callback, new Promise(resolve => { timer = setTimeout(() => resolve(null), 10_000); })]);
    assert.ok(typeof location === 'string', 'Retour OAuth attendu après le seul changement de mot de passe, sans UPDATE_PROFILE.');
    await page.goto('about:blank');
    const returned = new URL(location);
    assert.ok(returned.searchParams.get('state') === oauthState && returned.searchParams.get('iss') === localIssuer, 'Callback validé.');
    const response = await fetch(`${localIssuer}/protocol/openid-connect/token`, { method: 'POST', redirect: 'manual',
      body: new URLSearchParams({ grant_type: 'authorization_code', client_id: 'drivy-apple', redirect_uri: callbackURI,
        code: returned.searchParams.get('code'), code_verifier: verifier }) });
    assert.ok(response.ok, 'Échange PKCE du vrai fournisseur.');
    const tokens = await response.json();
    const jwks = createRemoteJWKSet(new URL(`${localIssuer}/protocol/openid-connect/certs`));
    const verified = await jwtVerify(tokens.id_token, jwks, { issuer: localIssuer, audience: 'drivy-apple' });
    assert.ok(verified.payload.nonce === nonce && verified.payload.sub === state.subject, 'Identité et nonce vérifiés sans divulguer les jetons.');
  } catch { throw new Error('Parcours navigateur de bootstrap refusé ; aucun formulaire ou jeton journalisé.'); }
  finally { if (timer) clearTimeout(timer); await context.close(); await browser.close(); }
}

test('Bootstrap contrôlé : vrai fournisseur et PostgreSQL isolés, reprise et RLS', async t => {
  const adminDatabase = new Pool({ connectionString: 'postgres://drivy_dev:local-development-only@127.0.0.1:55432/postgres' });
  let createdRole = false, createdDatabase = false, owner, databaseSuper;
  let identity;
  try {
    await t.test('garde-fous de cible et paramètres', () => {
      assert.equal(parseArguments(['--apply', '--username', 'luc', '--school-name', 'Luc auto école', '--contact-email', 'luc@example.com', '--operator', 'test', '--authorization-reference', 'test']).username, 'luc');
      assert.throws(() => validateDatabaseURL('postgres://drivy_refonte_owner:unused@127.0.0.1:55432/drivy_refonte'));
      assert.throws(() => validateDatabaseURL('postgres://drivy_refonte_owner:unused@drivy-db.tailb60275.ts.net/ancienne'));
      assert.throws(() => parseArguments(['--apply', '--username', '../other']));
    });
    const collisions = await adminDatabase.query("SELECT datname FROM pg_database WHERE datname='drivy_refonte'");
    const roles = await adminDatabase.query("SELECT rolname FROM pg_roles WHERE rolname='drivy_refonte_owner'");
    assert.ok(collisions.rowCount === 0 && roles.rowCount === 0, 'Refus de toucher à des objets préexistants.');
    // Mot de passe connu du seul laboratoire loopback, distinct de tout secret de déploiement.
    await adminDatabase.query("CREATE ROLE drivy_refonte_owner LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD 'local-development-only'"); createdRole = true;
    await adminDatabase.query('GRANT drivy_app TO drivy_refonte_owner WITH ADMIN OPTION');
    await adminDatabase.query('CREATE DATABASE drivy_refonte OWNER drivy_refonte_owner'); createdDatabase = true;
    owner = new Pool({ connectionString: 'postgres://drivy_refonte_owner:local-development-only@127.0.0.1:55432/drivy_refonte' });
    databaseSuper = new Pool({ connectionString: 'postgres://drivy_dev:local-development-only@127.0.0.1:55432/drivy_refonte' });
    await migrate(owner);
    const runtime = JSON.parse(await readFile(new URL('../../infra/dev/.state/runtime.json', import.meta.url), 'utf8'));
    identity = keycloakAdmin(localOrigin, runtime.adminUsername, runtime.adminPassword, 'drivy-dev', localIssuer);
    const saved = [];
    const save = async current => { saved.push(JSON.parse(JSON.stringify(current))); };
    await t.test('réponse de création IdP perdue : reprise sans changer le mot de passe', async () => {
      const ambiguous = { ...identity, create: async current => { await identity.create(current); throw new Error('Réponse perdue simulée'); } };
      await assert.rejects(() => ensureIdentity(state, ambiguous, save), /Réponse perdue simulée/);
      assert.ok(state.subject === null && state.initialPassword !== null && saved.some(item => item.phase === 'PASSWORD_SAVED'));
      const initialPassword = state.initialPassword;
      await ensureIdentity(state, identity, save);
      assert.ok(state.subject !== null && state.initialPassword === initialPassword, 'Subject réel réconcilié avec opération persistée.');
    });
    await t.test('compte déjà présent sans marqueur de cette opération : refus', async () => {
      const stranger = newOperation(input);
      await assert.rejects(() => ensureIdentity(stranger, identity, async () => {}), /Compte préexistant/);
      assert.equal(stranger.initialPassword, null);
    });
    await t.test('login réel sans email/prénom/nom : changement obligatoire, puis code PKCE', async () => {
      await loginWithRequiredPasswordChange(state.username, state.initialPassword, randomBytes(32).toString('base64url'));
      let resets = 0;
      await ensureIdentity(state, { ...identity, create: async () => { resets++; throw new Error('Création interdite'); } }, save);
      assert.equal(resets, 0);
    });
    await t.test('panne SQL après une insertion : rollback et FORCE RLS conservés', async () => {
      const failingPool = { connect: async () => {
        const db = await owner.connect();
        return { query: (query, values) => {
          if (typeof query === 'string' && query.startsWith('INSERT INTO drivy.identity_link')) throw new Error('Panne SQL simulée');
          return db.query(query, values);
        }, release: () => db.release() };
      } };
      await assert.rejects(() => provisionDatabase(failingPool, state), /Panne SQL simulée/);
      await queryProtection(owner);
      assert.equal((await databaseSuper.query('SELECT count(*)::int AS count FROM drivy.person')).rows[0].count, 0);
    });
    await t.test('première école DRAFT, reprise après commit perdu, aucune fixture créée', async () => {
      assert.equal(await provisionDatabase(owner, state), 'created');
      assert.equal(await provisionDatabase(owner, state), 'already-committed');
      await queryProtection(owner);
      assert.equal((await databaseSuper.query("SELECT count(*)::int AS count FROM drivy.school WHERE status='DRAFT'")).rows[0].count, 1);
      assert.equal((await databaseSuper.query('SELECT count(*)::int AS count FROM drivy.learner_profile')).rows[0].count, 0);
      assert.equal((await databaseSuper.query('SELECT count(*)::int AS count FROM drivy.training')).rows[0].count, 0);
    });
    await t.test('autre opération et autre issuer refusés, protections inchangées', async () => {
      await assert.rejects(() => provisionDatabase(owner, { ...state, schoolId: randomUUID() }), /Base non vide/);
      await assert.rejects(() => provisionDatabase(owner, { ...state, issuer: localIssuer }), /Identité vérifiée/);
      await queryProtection(owner);
    });
  } finally {
    await owner?.end(); await databaseSuper?.end();
    if (createdDatabase) await adminDatabase.query('DROP DATABASE drivy_refonte');
    if (createdRole) await adminDatabase.query('DROP ROLE drivy_refonte_owner');
    await adminDatabase.end();
    // Le compte sonde reste synthétique sur le fournisseur LOCAL et peut être inspecté.
    // Sa création ne touche jamais luc ou un fournisseur distant.
  }
});
