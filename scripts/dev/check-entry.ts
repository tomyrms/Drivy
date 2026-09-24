import { randomBytes, randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { Pool } from 'pg';
import { z } from 'zod';
import { chromium, type Browser } from '../../infra/dev/browser.js';
import { migrate } from '../../apps/api/scripts/migrations.js';
import { fixtureIds, seedFixtures } from '../../apps/api/scripts/fixtures.js';
import { buildApp } from '../../apps/api/src/app.js';
import { createTokenVerifier } from '../../apps/api/src/auth.js';
import { deliverOneInvitation, type InvitationMailConfig } from '../../apps/api/src/invitation-mail.js';
import { buildWebApp } from '../../apps/web/server/app.js';
import { createIdentityProvider, type IdentityProvider } from '../../apps/web/server/oidc.js';
import { apiOrigin, audience, databaseUrl, issuer, keycloakOrigin, loadAccounts, loadRuntime, localFetch, secretFile, stateDirectory } from './shared.js';

// This harness intentionally has no DATABASE_URL override. All destructive SQL is
// restricted to this exact disposable database on the local development cluster.
const databaseName = 'drivy_entry_test';
const webOrigin = 'http://127.0.0.1:3002';
const mailOrigin = 'http://127.0.0.1:8025';
const notice = 'Notice synthétique de recette locale : votre école utilise ces données pour votre rattachement et votre suivi pédagogique.';
const retention = 'Politique synthétique de recette : données de test supprimables avec la base isolée, sans données réelles.';
const schoolName = 'Auto-école Horizon · Démonstration';
let stage = 'préparation';
const checks: string[] = [];
function assert(value: unknown, name: string): asserts value {
  stage = name;
  if (!value) throw new Error('Contrôle non satisfait');
  checks.push(name);
  console.log(`OK ${checks.length} · ${name}`);
}
function guardDatabase(url: URL, expected: string) {
  if (url.protocol !== 'postgres:' || url.hostname !== '127.0.0.1' || url.port !== '55432' ||
      url.pathname !== `/${expected}` || url.search || url.hash || expected !== databaseName && expected !== 'drivy_dev') {
    throw new Error('Base de recette non autorisée');
  }
}
const messageSchema = z.object({ ID: z.string().regex(/^[a-zA-Z0-9-]+$/), MessageID: z.string(),
  To: z.array(z.object({ Address: z.string() })) });
type Message = z.infer<typeof messageSchema>;
async function ownMail(email: string, matches: (message: Message) => boolean): Promise<{ id: string; text: string }> {
  // No mailbox purge, no message from another recipient is opened.
  for (let attempt = 0; attempt < 40; attempt++) {
    const response = await fetch(`${mailOrigin}/api/v1/messages?limit=500`, { signal: AbortSignal.timeout(5_000), redirect: 'error' });
    if (!response.ok) throw new Error('Boîte locale indisponible');
    const list = z.object({ messages: z.array(messageSchema) }).parse(await response.json());
    const message = list.messages.find(item => item.To.some(to => to.Address === email) && matches(item));
    if (message) {
      const detail = await fetch(`${mailOrigin}/api/v1/message/${message.ID}`, { signal: AbortSignal.timeout(5_000), redirect: 'error' });
      if (!detail.ok) throw new Error('Message local indisponible');
      return { id: message.ID, text: z.object({ Text: z.string() }).parse(await detail.json()).Text };
    }
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  throw new Error('Message attendu absent');
}
function mailLink(text: string, origin: string, path: string): URL {
  const candidates = text.match(/https?:\/\/[^\s<>]+/g) ?? [];
  const links = candidates.map(value => new URL(value)).filter(url => url.origin === origin && url.pathname === path);
  if (links.length !== 1 || links[0]!.username || links[0]!.password) throw new Error('Lien SMTP inattendu');
  return links[0]!;
}

async function main() {
  await secretFile('entry-check-result.json', { completed: false, startedAt: new Date().toISOString(), database: databaseName });
  const runtime = await loadRuntime();
  const adminAccount = (await loadAccounts()).find(account => account.username === 'demo-admin');
  if (!adminAccount || adminAccount.personId !== fixtureIds.admin) throw new Error('Fixture administrative non reconnue');
  const saved = z.object({ clientSecret: z.string().min(32), outboxKey: z.string().regex(/^[0-9a-f]{64}$/) }).strict()
    .parse(JSON.parse(await readFile(new URL('web-runtime.json', stateDirectory), 'utf8')));
  const devURL = new URL(databaseUrl); guardDatabase(devURL, 'drivy_dev');
  const testURL = new URL(devURL); testURL.pathname = `/${databaseName}`; guardDatabase(testURL, databaseName);
  const operator = new Pool({ connectionString: devURL.href });
  try {
    stage = 'création éventuelle de la base isolée';
    if (!(await operator.query('SELECT 1 FROM pg_database WHERE datname=$1', [databaseName])).rowCount) {
      // Constant SQL identifier; never interpolate a user/environment argument here.
      await operator.query('CREATE DATABASE drivy_entry_test');
    }
  } finally { await operator.end(); }
  const pool = new Pool({ connectionString: testURL.href });
  let browser: Browser | undefined;
  let api: ReturnType<typeof buildApp> | undefined;
  let web: Awaited<ReturnType<typeof buildWebApp>> | undefined;
  let subject: string | undefined;
  let adminToken: string | undefined;
  let cleanupOK = true;
  let keycloakAdmin = '';
  let evidence: Record<string, unknown> | undefined;
  const username = `entry-${randomUUID()}`;
  const email = `${username}@example.invalid`;
  const password = randomBytes(32).toString('base64url');
  const ownMessageIDs = new Set<string>();
  const admin = (path: string, init: RequestInit = {}) => localFetch(`${keycloakOrigin}/admin/realms/drivy-dev/${path}`, {
    ...init, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${keycloakAdmin}` }
  });
  try {
    stage = 'migration puis réinitialisation de la seule base de recette';
    guardDatabase(testURL, databaseName);
    if ((await pool.query('SELECT current_database() AS name')).rows[0]?.name !== databaseName) throw new Error('Mauvaise base');
    await migrate(pool);
    await pool.query('TRUNCATE drivy.person,drivy.school CASCADE');
    await seedFixtures(pool, issuer);
    // Fake fixture subjects are not identities usable in this integration test.
    await pool.query('DELETE FROM drivy.identity_link');
    await pool.query('INSERT INTO drivy.identity_link(issuer,subject,person_id) VALUES($1,$2,$3)', [issuer, adminAccount.subject, fixtureIds.admin]);
    assert((await pool.query('SELECT count(*)::int AS count FROM drivy.identity_link')).rows[0]?.count === 1,
      'Base isolée : seul le compte administrateur réel est lié aux fixtures');

    stage = 'administration locale et création du seul utilisateur éphémère';
    const auth = await localFetch(`${keycloakOrigin}/realms/master/protocol/openid-connect/token`, {
      method: 'POST', body: new URLSearchParams({ grant_type: 'password', client_id: 'admin-cli', username: runtime.adminUsername, password: runtime.adminPassword })
    });
    if (!auth.ok) throw new Error('Administration locale refusée');
    keycloakAdmin = z.object({ access_token: z.string() }).parse(await auth.json()).access_token;
    const created = await admin('users', { method: 'POST', body: JSON.stringify({ username, email, emailVerified: false,
      firstName: 'Recette', lastName: 'Invitation', enabled: true, requiredActions: ['VERIFY_EMAIL'],
      credentials: [{ type: 'password', value: password, temporary: false }] }) });
    if (created.status !== 201) throw new Error('Création locale refusée');
    subject = z.uuid().parse(created.headers.get('location')?.split('/').at(-1));
    const initialUser = z.object({ emailVerified: z.literal(false), requiredActions: z.array(z.string()) }).parse(await (await admin(`users/${subject}`)).json());
    assert(initialUser.requiredActions.includes('VERIFY_EMAIL'), 'Identité invitée créée non vérifiée, sans contournement de VERIFY_EMAIL');
    const config = { origin: webOrigin, apiBaseURL: apiOrigin, issuer, clientId: 'drivy-web', clientSecret: saved.clientSecret,
      development: true, host: '127.0.0.1', port: 3002 };
    const provider = await createIdentityProvider(config);
    // Test-only observer in this server process. No token is returned to the UI,
    // written to disk, captured in screenshots or printed on failure.
    const identity: IdentityProvider = { ...provider, async complete(url, transaction) {
      const tokens = await provider.complete(url, transaction);
      if (tokens.principal.subject === adminAccount.subject) adminToken = tokens.accessToken;
      return tokens;
    } };
    const mail: InvitationMailConfig = { webURL: `${webOrigin}/app/invitation`, encryptionKey: saved.outboxKey,
      host: '127.0.0.1', port: 1025, secure: false, requireTLS: false, from: 'no-reply@drivy.example.invalid' };
    api = buildApp({ pool, verifyToken: createTokenVerifier({ OIDC_ISSUER: issuer, OIDC_AUDIENCE: audience,
      OIDC_JWKS_URL: `${issuer}/protocol/openid-connect/certs` }), cursorSecret: runtime.cursorSecret, invitationMail: mail });
    web = await buildWebApp({ config, identity, staticRoot: fileURLToPath(new URL('../../apps/web/dist/client/', import.meta.url)) });
    stage = 'démarrage des services loopback réservés';
    await api.listen({ host: '127.0.0.1', port: 3001 }); await web.listen({ host: '127.0.0.1', port: 3002 });
    browser = await chromium.launch({ channel: z.enum(['msedge', 'chrome']).parse(process.env.DRIVY_BROWSER_CHANNEL ?? 'msedge'), headless: true });
    const newContext = async () => {
      const context = await browser!.newContext();
      await context.route('**/*', route => [webOrigin, keycloakOrigin].includes(new URL(route.request().url()).origin) ? route.continue() : route.abort());
      context.setDefaultTimeout(15_000);
      return context;
    };
    const adminContext = await newContext(); const adminPage = await adminContext.newPage();
    stage = 'connexion administrative réelle par le formulaire OIDC';
    await adminPage.goto(`${webOrigin}/app`); await adminPage.getByRole('button', { name: 'Se connecter', exact: true }).click();
    await adminPage.waitForURL(url => url.origin === keycloakOrigin);
    assert(new URL(adminPage.url()).searchParams.get('code_challenge_method') === 'S256', 'Authentification administrative par code PKCE S256');
    await adminPage.locator('input[name="username"]').fill(adminAccount.username);
    await adminPage.locator('input[name="password"]').fill(adminAccount.password);
    await adminPage.locator('input[type="submit"],button[type="submit"]').first().click();
    await adminPage.getByRole('heading', { name: schoolName, exact: true }).waitFor();
    assert(adminToken, 'Compte administrateur connecté via React, Keycloak et BFF');
    const command = (path: string, body: Record<string, unknown>, method: string, version?: number) => localFetch(`${apiOrigin}${path}`, {
      method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${adminToken}`,
        'Idempotency-Key': String(body.operationId), ...(version ? { 'If-Match': `"${version}"` } : {}) }, body: JSON.stringify(body)
    });
    stage = 'adoption explicite de la notice synthétique par API authentifiée';
    const adopted = await command(`/v1/schools/${fixtureIds.schoolA}/data-policy`, {
      operationId: randomUUID(), noticeText: notice, retentionText: retention, contactEmail: 'contact@example.invalid', reviewAcknowledged: true
    }, 'PUT', 1);
    assert(adopted.status === 200, 'Notice locale adoptée par la commande authentifiée et versionnée');
    stage = 'invitation AP11 authentifiée';
    const invited = await command(`/v1/schools/${fixtureIds.schoolA}/invitations`, { operationId: randomUUID(), email, roles: ['LEARNER'] }, 'POST');
    assert(invited.status === 201, 'Invitation élève créée par AP11 avec idempotence');
    const invitationID = z.object({ data: z.object({ id: z.uuid() }) }).parse(await invited.json()).data.id;
    adminToken = undefined;
    const outbox = (await pool.query<{ id: string }>('SELECT id FROM drivy.invitation_mail WHERE invitation_id=$1', [invitationID])).rows[0];
    if (!outbox) throw new Error('Outbox absente');
    stage = 'livraison SMTP réelle de l’invitation';
    await deliverOneInvitation(pool, mail);
    const invitationMail = await ownMail(email, message => message.MessageID.includes(outbox.id)); ownMessageIDs.add(invitationMail.id);
    const invitationURL = mailLink(invitationMail.text, webOrigin, '/app/invitation');
    assert(/^#token=[A-Za-z0-9_-]{43}$/.test(invitationURL.hash), 'Lien reçu par SMTP avec jeton dans le fragment uniquement');
    const sent = (await pool.query('SELECT status,payload FROM drivy.invitation_mail WHERE id=$1', [outbox.id])).rows[0];
    assert(sent?.status === 'SENT' && sent.payload === null, 'Acceptation SMTP constatée et charge chiffrée de l’outbox effacée');

    const context = await newContext(); const page = await context.newPage();
    stage = 'connexion initiale de l’identité non liée';
    await page.goto(`${webOrigin}/app`); await page.getByRole('button', { name: 'Se connecter', exact: true }).click();
    await page.locator('input[name="username"]').fill(username); await page.locator('input[name="password"]').fill(password);
    await page.locator('input[type="submit"],button[type="submit"]').first().click();
    stage = 'réception du vrai courrier VERIFY_EMAIL';
    const verification = await ownMail(email, message => !message.MessageID.includes(outbox.id)); ownMessageIDs.add(verification.id);
    const verificationURL = mailLink(verification.text, keycloakOrigin, '/realms/drivy-dev/login-actions/action-token');
    assert(new URL(page.url()).origin === keycloakOrigin, 'Le fournisseur retient la connexion avant vérification de l’adresse');
    stage = 'ouverture du vrai lien de vérification reçu par SMTP';
    await page.goto(verificationURL.href);
    // Same browser/authentication session allows Keycloak to resume the OIDC flow.
    await page.waitForURL(url => url.origin === webOrigin, { timeout: 20_000 });
    await page.getByRole('heading', { name: 'Votre école n’apparaît pas encore', exact: true }).waitFor();
    const verified = await context.request.get(`${webOrigin}/app/bff/session`);
    const session = z.object({ authenticated: z.boolean(), user: z.object({ emailVerified: z.boolean() }) }).parse(await verified.json());
    assert(session.authenticated && session.user.emailVerified, 'Adresse réellement vérifiée par le lien SMTP puis callback OIDC');
    assert((await context.request.get(`${webOrigin}/app/bff/me`)).status() === 403 &&
      (await pool.query('SELECT 1 FROM drivy.identity_link WHERE issuer=$1 AND subject=$2', [issuer, subject])).rowCount === 0,
      'Connexion seule : aucune Person ni école créée pour la nouvelle identité');

    stage = 'ouverture du lien réel d’invitation et aperçu';
    await page.goto(invitationURL.href);
    await page.getByRole('heading', { name: schoolName, exact: true }).waitFor();
    assert(new URL(page.url()).hash === '', 'Fragment d’invitation retiré de la barre d’adresse');
    assert(await page.getByText(notice, { exact: true }).isVisible() && await page.getByText(retention, { exact: true }).isVisible() &&
      await page.locator('.invitation-facts').getByText('Élève', { exact: true }).isVisible(), 'Aperçu : école, rôle et notice réellement adoptée');
    assert(await page.getByRole('button', { name: 'Rejoindre cette école', exact: true }).isDisabled() &&
      (await pool.query('SELECT 1 FROM drivy.identity_link WHERE issuer=$1 AND subject=$2', [issuer, subject])).rowCount === 0,
      'Lire l’aperçu ne crée aucun rattachement et exige une confirmation explicite');
    stage = 'acceptation explicite depuis React';
    await page.getByRole('checkbox').check();
    await page.getByRole('button', { name: 'Rejoindre cette école', exact: true }).click();
    await page.getByText(`Vous avez rejoint ${schoolName}`, { exact: true }).waitFor();
    await page.getByRole('heading', { name: schoolName, exact: true }).waitFor();
    assert(true, 'Acceptation explicite confirmée et école affichée dans le compte');
    const meResponse = await context.request.get(`${webOrigin}/app/bff/me`);
    const me = z.object({ data: z.object({ personId: z.uuid(), memberships: z.array(z.object({ schoolId: z.uuid(), roles: z.array(z.string()) })) }) }).parse(await meResponse.json());
    assert(meResponse.status() === 200 && me.data.memberships.length === 1 && me.data.memberships[0]!.schoolId === fixtureIds.schoolA &&
      JSON.stringify(me.data.memberships[0]!.roles) === JSON.stringify(['LEARNER']), 'Relecture BFF/API : une école et uniquement le rôle élève');
    const personID = me.data.personId;
    const counts = (await pool.query(`SELECT
      (SELECT count(*)::int FROM drivy.identity_link WHERE issuer=$1 AND subject=$2 AND person_id=$3) AS identities,
      (SELECT count(*)::int FROM drivy.membership WHERE person_id=$3) AS memberships,
      (SELECT count(*)::int FROM drivy.learner_profile WHERE person_id=$3 AND school_id=$4 AND profile_readiness='MINIMAL') AS learners,
      (SELECT count(*)::int FROM drivy.training t JOIN drivy.learner_profile l ON l.id=t.learner_id WHERE l.person_id=$3) AS trainings`,
      [issuer, subject, personID, fixtureIds.schoolA])).rows[0];
    assert(counts.identities === 1 && counts.memberships === 1 && counts.learners === 1 && counts.trainings === 0,
      'SQL : un IdentityLink, un Membership, un profil élève minimal et aucune formation');
    stage = 'relecture après rechargement du navigateur';
    await page.reload(); await page.getByRole('heading', { name: schoolName, exact: true }).waitFor();
    assert(await page.evaluate(() => localStorage.length === 0 && sessionStorage.length === 0), 'École retrouvée après rechargement sans stockage navigateur');
    evidence = { checkedAt: new Date().toISOString(), browser: browser.version(), database: databaseName,
      checks, passed: checks.length, sql: counts, scope: 'F02 local réel : navigateur, Keycloak, vérification email SMTP, BFF, API, PostgreSQL. Aucun scénario canonique entier promu par analogie.' };
  } finally {
    adminToken = undefined;
    const closed = await Promise.allSettled([browser?.close(), web?.close(), api?.close(), pool.end()]);
    if (closed.some(result => result.status === 'rejected')) cleanupOK = false;
    // Cleanup only the UUID created in this invocation, never fixtures or other users.
    if (subject) {
      try { const removed = await admin(`users/${subject}`, { method: 'DELETE' }); cleanupOK = removed.status === 204 || removed.status === 404; }
      catch { cleanupOK = false; }
    }
    // Delete only messages already identified as belonging to our unique recipient.
    if (ownMessageIDs.size > 0) {
      // Mailpit DELETE /messages WITHOUT IDs would delete the whole inbox.
      // The non-empty guard and explicit IDs are therefore mandatory.
      try { const removed = await fetch(`${mailOrigin}/api/v1/messages`, { method: 'DELETE',
        headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ IDs: [...ownMessageIDs] }),
        signal: AbortSignal.timeout(5_000), redirect: 'error' });
        if (!removed.ok) cleanupOK = false;
      } catch { cleanupOK = false; }
    }
    if (!cleanupOK) { stage = 'nettoyage ciblé de l’identité et des messages de recette'; throw new Error('Nettoyage incomplet'); }
  }
  if (!evidence) throw new Error('Preuve absente');
  await secretFile('entry-check-result.json', { ...evidence, completed: true, cleanup: 'Identité éphémère et messages SMTP de cette invocation supprimés.' });
  console.log(`${checks.length} contrôles F02 réels réussis. Identité éphémère et courriers de cette recette supprimés ; base isolée conservée pour inspection locale.`);
}
main().catch(() => { console.error(`Recette F02 interrompue : ${stage}. Aucun identifiant, e-mail, mot de passe ou jeton journalisé.`); process.exitCode = 1; });
