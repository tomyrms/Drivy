import { randomBytes, randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { Pool } from 'pg';
import { z } from 'zod';
import { chromium, type Browser } from '../../infra/dev/browser.js';
import { migrate } from '../../apps/api/scripts/migrations.js';
import { buildApp } from '../../apps/api/src/app.js';
import { createTokenVerifier } from '../../apps/api/src/auth.js';
import { buildWebApp } from '../../apps/web/server/app.js';
import { createIdentityProvider, type IdentityProvider } from '../../apps/web/server/oidc.js';
import { PostgresCommandStore } from '../../apps/web/server/command-store.js';
import { migrateCommands } from '../../apps/web/server/command-migrate.js';

// No database/host override: this recipe never resets another agent's database.
const databaseName = 'drivy_profiles_entry_test';
const apiOrigin = 'http://127.0.0.1:3005';
const webOrigin = 'http://127.0.0.1:3006';
const keycloakOrigin = 'http://127.0.0.1:8081';
const issuer = `${keycloakOrigin}/realms/drivy-dev`;
const labRuntime = 'C:/Users/jtoma/Documents/Projects/Drivy/infra/dev/.state/runtime.json';
const runId = randomUUID();
const schoolId = randomUUID();
const learnerId = randomUUID();
const schoolName = `École de recette Profils · ${runId.slice(0, 8)}`;
const output = new URL(`../../artifacts/web/profile-entry/${runId}/`, import.meta.url);
const notice = 'Notice synthétique : les informations saisies dans cette école de recette servent uniquement à vérifier le parcours de profil scolaire.';
const retention = 'Données synthétiques de recette supprimées à la fin de cette exécution. Aucun élève réel.';
const checks: string[] = [];
let stage = 'préparation';
function check(value: unknown, label: string): asserts value {
  stage = label;
  if (!value) throw new Error('Contrôle non satisfait');
  checks.push(label); console.log(`OK ${checks.length} · ${label}`);
}
async function loopbackFetch(url: string, init: RequestInit = {}) {
  const parsed = new URL(url);
  if (![keycloakOrigin, apiOrigin, webOrigin].includes(parsed.origin) || parsed.username || parsed.password) throw new Error('Origine interdite');
  return fetch(url, { ...init, redirect: 'error', signal: AbortSignal.timeout(15_000) });
}
type Probe = { role: 'ADMIN' | 'LEARNER' | 'INSTRUCTOR'; personId: string; memberId: string; username: string; password: string; email: string; subject?: string };
const probes: Probe[] = (['ADMIN', 'LEARNER', 'INSTRUCTOR'] as const).map(role => ({ role,
  personId: randomUUID(), memberId: randomUUID(), username: `profile-${runId}-${role.toLowerCase()}`,
  password: randomBytes(32).toString('base64url'), email: `profile-${runId}-${role.toLowerCase()}@example.invalid` }));
const administrator = probes[0]!;
const learner = probes[1]!;
const instructor = probes[2]!;
const object = z.record(z.string(), z.unknown());
const envelope = z.object({ data: object });

async function databaseConnection() {
  // Docker stdout remains in process memory; credentials are never logged or saved.
  const inspection = await promisify(execFile)('docker', ['inspect', 'drivy-g1d-postgres'], { windowsHide: true, maxBuffer: 1024 * 1024 });
  const containers = z.array(z.object({ Config: z.object({ Env: z.array(z.string()) }),
    NetworkSettings: z.object({ Ports: z.record(z.string(), z.array(z.object({ HostPort: z.string() })).nullable()) }) })).parse(JSON.parse(inspection.stdout));
  const container = containers[0];
  if (containers.length !== 1 || !container?.NetworkSettings.Ports['5432/tcp']?.some(port => port.HostPort === '55434')) throw new Error('Cluster de recette inattendu');
  const values = Object.fromEntries(container.Config.Env.map(entry => [entry.slice(0, entry.indexOf('=')), entry.slice(entry.indexOf('=') + 1)]));
  const credentials = z.object({ POSTGRES_USER: z.string().min(1), POSTGRES_PASSWORD: z.string().min(1) }).parse(values);
  return { host: '127.0.0.1', port: 55434, user: credentials.POSTGRES_USER, password: credentials.POSTGRES_PASSWORD, database: databaseName };
}

async function seedPrerequisites(pool: Pool) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const probe of probes) {
      await client.query('INSERT INTO drivy.person(id,display_name) VALUES($1,$2)', [probe.personId, `Compte sonde ${probe.role}`]);
      await client.query('INSERT INTO drivy.identity_link(issuer,subject,person_id) VALUES($1,$2,$3)', [issuer, probe.subject, probe.personId]);
    }
    await client.query("INSERT INTO drivy.school(id,name,status,contact_email) VALUES($1,$2,'ACTIVE','recette@example.invalid')", [schoolId, schoolName]);
    for (const probe of probes) await client.query('INSERT INTO drivy.membership(id,school_id,person_id,roles) VALUES($1,$2,$3,$4)', [probe.memberId, schoolId, probe.personId, [probe.role]]);
    await client.query("INSERT INTO drivy.learner_profile(id,school_id,person_id,display_name,profile_readiness) VALUES($1,$2,$3,'Compte élève de recette','MINIMAL')", [learnerId, schoolId, learner.personId]);
    // Assignment is a synthetic prerequisite; the profile flow creates no training.
    const offering = randomUUID(), training = randomUUID();
    await client.query("INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version) VALUES($1,$2,'recipe-b','B',1)", [offering, schoolId]);
    await client.query("INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on) VALUES($1,$2,$3,$4,'recipe-b','ACTIVE','2026-01-01')", [training, schoolId, learnerId, offering]);
    await client.query("INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES($1,$2,$3,$4,'2026-01-01T00:00:00Z')", [randomUUID(), schoolId, training, instructor.memberId]);
    await client.query('COMMIT');
  } catch (error) { await client.query('ROLLBACK'); throw error; }
  finally { client.release(); }
}

async function cleanupOwnRows(pool: Pool) {
  const client = await pool.connect();
  try {
    if ((await client.query('SELECT current_database() AS name')).rows[0]?.name !== databaseName) throw new Error('Nettoyage hors base dédiée');
    await client.query('BEGIN');
    // Constant identifiers, every DELETE bound to this run's random UUIDs. No TRUNCATE/DROP.
    await client.query('DELETE FROM drivy_web.profile_command WHERE school_id=$1 AND person_id=ANY($2::uuid[]) AND issuer=$3', [schoolId, probes.map(probe => probe.personId), issuer]);
    for (const table of ['audit_event', 'operation', 'onboarding_progress', 'instructor_assignment', 'training',
      'learner_profile', 'offering_version', 'profile_field_policy', 'school_setup', 'school_settings_version', 'school_data_policy', 'membership']) {
      await client.query(`DELETE FROM drivy.${table} WHERE school_id=$1`, [schoolId]);
    }
    await client.query('DELETE FROM drivy.school WHERE id=$1', [schoolId]);
    await client.query('DELETE FROM drivy.identity_link WHERE person_id=ANY($1::uuid[]) AND issuer=$2', [probes.map(probe => probe.personId), issuer]);
    await client.query('DELETE FROM drivy.person WHERE id=ANY($1::uuid[])', [probes.map(probe => probe.personId)]);
    await client.query('COMMIT');
  } catch (error) { await client.query('ROLLBACK'); throw error; }
  finally { client.release(); }
}

async function main() {
  await mkdir(output, { recursive: true });
  const evidence: Record<string, unknown> = { completed: false, runId, database: databaseName, startedAt: new Date().toISOString(), checks };
  const persistEvidence = () => writeFile(new URL('result.json', output), JSON.stringify(evidence, null, 2));
  await persistEvidence();
  const runtime = z.object({ adminUsername: z.literal('drivy-local-bootstrap'), adminPassword: z.string().min(32) })
    .parse(JSON.parse(await readFile(labRuntime, 'utf8')));
  const connection = await databaseConnection();
  const operator = new Pool({ ...connection, database: 'postgres' });
  try {
    if (!(await operator.query('SELECT 1 FROM pg_database WHERE datname=$1', [databaseName])).rowCount) await operator.query('CREATE DATABASE drivy_profiles_entry_test');
  } finally { await operator.end(); }
  const pool = new Pool(connection);
  let browser: Browser | undefined;
  let api: ReturnType<typeof buildApp> | undefined;
  let web: Awaited<ReturnType<typeof buildWebApp>> | undefined;
  let keycloakAdmin = '', adminExpiresAt = 0, clientUUID: string | undefined, cleanupOK = true, seeded = false;
  const tokens = new Map<string, string>();
  const clientId = `profile-recipe-${runId}`;
  const clientSecret = randomBytes(32).toString('base64url');
  const admin = async (path: string, init: RequestInit = {}) => {
    if (Date.now() >= adminExpiresAt) {
      const login = await loopbackFetch(`${keycloakOrigin}/realms/master/protocol/openid-connect/token`, { method: 'POST',
        body: new URLSearchParams({ grant_type: 'password', client_id: 'admin-cli', username: runtime.adminUsername, password: runtime.adminPassword }) });
      if (!login.ok) throw new Error('Administration locale indisponible');
      const token = z.object({ access_token: z.string(), expires_in: z.number().positive() }).parse(await login.json());
      keycloakAdmin = token.access_token; adminExpiresAt = Date.now() + Math.max(1, token.expires_in - 15) * 1000;
    }
    return loopbackFetch(`${keycloakOrigin}/admin/realms/drivy-dev/${path}`, {
      ...init, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${keycloakAdmin}` } });
  };
  const apiCall = async (probe: Probe, path: string, body?: Record<string, unknown>, method = 'GET', version?: number) => {
    const token = probe.subject && tokens.get(probe.subject);
    if (!token) throw new Error('Connexion réelle absente');
    return loopbackFetch(`${apiOrigin}/v1/${path}`, { method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
      ...(body?.operationId ? { 'Idempotency-Key': String(body.operationId) } : {}), ...(version ? { 'If-Match': `"${version}"` } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}) });
  };
  const apiData = async (probe: Probe, path: string) => {
    const response = await apiCall(probe, path); if (!response.ok) throw new Error('Lecture API refusée');
    return envelope.parse(await response.json()).data;
  };
  try {
    stage = 'migrations dans la base dédiée';
    check((await pool.query('SELECT current_database() AS name')).rows[0]?.name === databaseName, 'base dédiée reconnue');
    await migrate(pool);
    await pool.query(await readFile(new URL('../../apps/web/scripts/prepare-command-roles.sql', import.meta.url), 'utf8'));
    await migrateCommands(pool);
    stage = 'authentification de provisionnement Keycloak local';
    const newClient = await admin('clients', { method: 'POST', body: JSON.stringify({ clientId, name: 'Recette temporaire Profils',
      enabled: true, protocol: 'openid-connect', clientAuthenticatorType: 'client-secret', secret: clientSecret,
      publicClient: false, standardFlowEnabled: true, directAccessGrantsEnabled: false, implicitFlowEnabled: false,
      serviceAccountsEnabled: false, fullScopeAllowed: false, redirectUris: [`${webOrigin}/app/bff/callback`], webOrigins: [],
      attributes: { 'pkce.code.challenge.method': 'S256' }, defaultClientScopes: ['basic', 'profile', 'email'], optionalClientScopes: [],
      protocolMappers: [{ name: 'drivy-api-audience', protocol: 'openid-connect', protocolMapper: 'oidc-audience-mapper', consentRequired: false,
        config: { 'included.custom.audience': 'drivy-api', 'id.token.claim': 'false', 'access.token.claim': 'true', 'introspection.token.claim': 'true' } }] }) });
    if (!newClient.ok) throw new Error('Client temporaire refusé');
    clientUUID = z.uuid().parse(newClient.headers.get('location')?.split('/').pop());
    for (const probe of probes) {
      const created = await admin('users', { method: 'POST', body: JSON.stringify({ username: probe.username, email: probe.email,
        enabled: true, emailVerified: true, firstName: 'Compte', lastName: `Sonde ${probe.role}`, requiredActions: [],
        credentials: [{ type: 'password', value: probe.password, temporary: false }] }) });
      if (!created.ok) throw new Error('Compte de sonde refusé');
      probe.subject = z.uuid().parse(created.headers.get('location')?.split('/').pop());
    }
    await seedPrerequisites(pool); seeded = true;
    const config = { origin: webOrigin, apiBaseURL: apiOrigin, issuer, clientId, clientSecret, development: true, host: '127.0.0.1', port: 3006 };
    const provider = await createIdentityProvider(config);
    // Observe real login tokens only inside this server process for prerequisite/permission probes.
    const identity: IdentityProvider = { ...provider, async complete(url, transaction) {
      const result = await provider.complete(url, transaction); tokens.set(result.principal.subject, result.accessToken); return result;
    } };
    const keyring = { activeKeyId: 'recipe-v1', keys: { 'recipe-v1': randomBytes(32).toString('hex') } };
    const startWeb = async () => {
      web = await buildWebApp({ config, identity, commandStore: new PostgresCommandStore(pool, keyring),
        staticRoot: fileURLToPath(new URL('../../apps/web/dist/client/', import.meta.url)) });
      await web.listen({ host: '127.0.0.1', port: 3006 });
    };
    api = buildApp({ pool, verifyToken: createTokenVerifier({ OIDC_ISSUER: issuer, OIDC_AUDIENCE: 'drivy-api',
      OIDC_JWKS_URL: `${issuer}/protocol/openid-connect/certs` }), cursorSecret: randomBytes(32).toString('base64url') });
    await api.listen({ host: '127.0.0.1', port: 3005 }); await startWeb();
    browser = await chromium.launch({ channel: 'msedge', headless: true });
    type Page = Awaited<ReturnType<Browser['newPage']>>;
    const newPage = async () => {
      const context = await browser!.newContext({ locale: 'fr-CH', timezoneId: 'Europe/Zurich', viewport: { width: 1280, height: 1000 } });
      await context.route('**/*', route => [webOrigin, keycloakOrigin].includes(new URL(route.request().url()).origin) ? route.continue() : route.abort());
      context.setDefaultTimeout(20_000); return context.newPage();
    };
    const signIn = async (page: Page, probe: Probe) => {
      await page.goto(`${webOrigin}/app/`); await page.getByRole('button', { name: 'Se connecter', exact: true }).click();
      await page.locator('input[name="username"]').fill(probe.username); await page.locator('input[name="password"]').fill(probe.password);
      await page.locator('input[type="submit"],button[type="submit"]').click();
      await page.getByRole('heading', { name: 'Vos écoles', exact: true }).waitFor();
      check(!!probe.subject && tokens.has(probe.subject), `connexion Edge → Keycloak → BFF réelle : ${probe.role}`);
    };
    const openSchool = async (page: Page) => {
      await page.getByRole('button', { name: 'Ouvrir l’école', exact: true }).click();
      await page.getByRole('heading', { name: schoolName, exact: true }).waitFor();
      await page.getByRole('heading', { name: 'Dossiers accessibles', exact: true }).waitFor();
    };
    const openProfile = async (page: Page) => {
      await page.getByRole('button', { name: 'Ouvrir le profil', exact: true }).click();
      await page.getByRole('heading', { name: 'Profil scolaire · Compte élève de recette', exact: true }).waitFor();
    };
    const confirm = async (page: Page, publication = false) => {
      const review = page.locator('.command-review'); await review.waitFor();
      check(!await review.getByRole('checkbox').isChecked(), 'confirmation explicite jamais précochée');
      await review.getByRole('checkbox').check(); await review.getByRole('button', { name: 'Confirmer la demande', exact: true }).click();
      await page.getByText(publication ? 'Publication confirmée par l’école.' : 'Enregistrement confirmé par l’école.', { exact: true }).waitFor();
    };
    const bff = async (page: Page, path: string, body?: unknown) => page.evaluate(async ({ path, body }) => {
      const session = await fetch('/app/bff/session').then(response => response.json()) as { csrfToken: string };
      const response = await fetch(`/app/bff/${path}`, { method: body ? 'POST' : 'GET',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': session.csrfToken }, ...(body ? { body: JSON.stringify(body) } : {}) });
      return { status: response.status, body: await response.json() as Record<string, unknown> };
    }, { path, body });

    stage = 'adoption réelle de la notice préalable';
    const adminPage = await newPage(); await signIn(adminPage, administrator);
    const baseline = await apiData(administrator, `schools/${schoolId}/data-policy`);
    const adopted = await apiCall(administrator, `schools/${schoolId}/data-policy`, { operationId: randomUUID(),
      noticeText: notice, retentionText: retention, contactEmail: 'recette@example.invalid', reviewAcknowledged: true }, 'PUT', z.number().parse(baseline.version));
    check(adopted.status === 200, 'notice synthétique adoptée par la vraie commande API ADMIN');
    const adoptedNotice = envelope.parse(await adopted.json()).data;
    stage = 'création explicite de la politique dans Edge';
    await openSchool(adminPage); await adminPage.getByRole('button', { name: 'Politique des champs', exact: true }).click();
    await adminPage.getByRole('heading', { name: 'Préparer une nouvelle politique' }).waitFor();
    const effective = new Date(Date.now() - 120_000);
    const localEffective = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Zurich', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(effective).replace(' ', 'T');
    await adminPage.getByLabel('Date et heure d’effet, dans le fuseau de cet appareil', { exact: true }).fill(localEffective);
    for (const [label, purpose] of [['Prénom', 'IDENTIFICATION'], ['Nom', 'IDENTIFICATION'], ['E-mail de contact', 'LESSON_CONTACT'],
      ['Téléphone de contact', 'LESSON_CONTACT'], ['Date de naissance', 'COURSE_ELIGIBILITY'], ['Adresse postale', 'POSTAL_CONTACT']] as const) {
      const field = adminPage.getByRole('group', { name: label, exact: true });
      if (!['Prénom', 'Nom'].includes(label)) { await field.getByRole('checkbox').check(); await field.getByLabel('Finalité', { exact: true }).selectOption(purpose); }
      await field.getByLabel('Pourquoi cette information est utile', { exact: true }).fill(`Recette synthétique : vérifier explicitement le champ ${label}.`);
    }
    await adminPage.getByLabel('J’ai relu les finalités, les stades et les conséquences de ces demandes pour les élèves.', { exact: true }).check();
    await adminPage.getByRole('button', { name: 'Relire le brouillon de politique', exact: true }).click();
    await confirm(adminPage);
    check((await pool.query('SELECT status,notice_version_id FROM drivy.profile_field_policy WHERE school_id=$1', [schoolId])).rows[0]?.status === 'DRAFT', 'création conserve un brouillon sans publication automatique');
    await adminPage.getByRole('button', { name: 'Relire la publication', exact: true }).click();
    await confirm(adminPage, true);
    const policy = (await pool.query('SELECT id,status,notice_version_id FROM drivy.profile_field_policy WHERE school_id=$1', [schoolId])).rows[0];
    check(policy?.status === 'PUBLISHED' && policy.notice_version_id === adoptedNotice.noticeVersionId, 'politique publiée avec la notice adoptée exacte');
    await adminPage.screenshot({ path: fileURLToPath(new URL('01-policy-published.png', output)), fullPage: true });

    stage = 'saisie volontaire du profil élève';
    const learnerPage = await newPage(); await signIn(learnerPage, learner); await openSchool(learnerPage); await openProfile(learnerPage);
    check(await learnerPage.getByLabel(/^Prénom/).inputValue() === '' && await learnerPage.getByLabel(/^Nom/).inputValue() === '', 'noms administratifs initialement vides, jamais déduits du compte OIDC');
    await learnerPage.getByLabel(/^Prénom/).fill('Élise'); await learnerPage.getByLabel(/^Nom/).fill('Sonde');
    await learnerPage.getByLabel(/^E-mail de contact/).fill('elise.sonde@example.invalid');
    await learnerPage.getByLabel(/^Téléphone de contact/).fill('+41 79 000 00 01');
    await learnerPage.getByLabel(/^Date de naissance/).fill('2000-04-12');
    await learnerPage.getByLabel('Rue et numéro', { exact: true }).fill('Rue de la Recette 1');
    await learnerPage.getByLabel('Code postal', { exact: true }).fill('1000'); await learnerPage.getByLabel('Localité', { exact: true }).fill('Lausanne');
    await learnerPage.getByLabel('Pays (code à deux lettres)', { exact: true }).fill('CH');
    await learnerPage.getByRole('button', { name: 'Relire les modifications', exact: true }).click(); await confirm(learnerPage);
    const initialProfile = await apiData(learner, `schools/${schoolId}/learners/${learnerId}/administrative-profile`);
    check(initialProfile.firstName === 'Élise' && initialProfile.lastName === 'Sonde' && initialProfile.contactEmail === 'elise.sonde@example.invalid' && initialProfile.birthDate === '2000-04-12' && initialProfile.entrySource === 'SELF', 'relecture API des valeurs saisies par l’élève');
    check(initialProfile.id !== learnerId, 'identité AdministrativeProfile distincte du dossier Learner');
    await learnerPage.screenshot({ path: fileURLToPath(new URL('02-learner-saved.png', output)), fullPage: true });

    stage = 'permissions du moniteur affecté';
    const instructorPage = await newPage(); await signIn(instructorPage, instructor); await openSchool(instructorPage); await openProfile(instructorPage);
    check(await instructorPage.getByLabel(/^Prénom/).isDisabled() && await instructorPage.getByLabel(/^Nom/).isDisabled() &&
      await instructorPage.getByLabel(/^Date de naissance/).count() === 0 && await instructorPage.getByRole('group', { name: 'Adresse postale', exact: true }).count() === 0, 'moniteur : noms non modifiables, naissance et adresse absentes de l’écran');
    const projection = await apiData(instructor, `schools/${schoolId}/learners/${learnerId}/administrative-profile`);
    check(!('birthDate' in projection) && !('postalAddress' in projection) && !('profilePhotoDocumentId' in projection), 'API moniteur omet les champs protégés');
    const forged = await bff(instructorPage, 'profile-command/prepare', { kind: 'PROFILE', schoolId, learnerId,
      expectedVersion: projection.version, payload: { policyVersionId: policy.id, birthDate: '2001-01-01' } });
    check(forged.status === 403 && forged.body.code === 'PROFILE_FIELD_FORBIDDEN', 'BFF refuse une demande forgée de naissance par le moniteur');
    for (const field of [{ birthDate: '2001-01-01' }, { postalAddress: { line1: 'Autre adresse', line2: null, postalCode: '9999', locality: 'Sonde', countryCode: 'CH' } }]) {
      const response = await apiCall(instructor, `schools/${schoolId}/learners/${learnerId}/administrative-profile`,
        { operationId: randomUUID(), policyVersionId: policy.id, ...field }, 'PATCH', z.number().parse(projection.version));
      const rejected = object.parse(await response.json());
      check(response.status === 403 && rejected.code === 'PROFILE_FIELD_FORBIDDEN', `API refuse le champ protégé ${Object.keys(field)[0]}`);
    }
    await instructorPage.getByLabel(/^Téléphone de contact/).fill('+41 79 000 00 02');
    await instructorPage.getByRole('button', { name: 'Relire les modifications', exact: true }).click();
    await instructorPage.locator('.command-review').waitFor();
    // Inspect only metadata in PostgreSQL: a second GET of the review endpoint could rotate its confirmation.
    const beforeRestart = (await pool.query('SELECT operation_id AS "operationId",state,sealed FROM drivy_web.profile_command WHERE school_id=$1 AND person_id=$2 ORDER BY created_at DESC LIMIT 1', [schoolId, instructor.personId])).rows[0];
    check(beforeRestart.state === 'PREPARED', 'demande de contact préparée avant confirmation');
    check(Buffer.isBuffer(beforeRestart.sealed) && !beforeRestart.sealed.includes(Buffer.from('+41 79 000 00 02')), 'charge utile du brouillon chiffrée dans PostgreSQL');
    // Destroy the BFF (including its memory sessions), construct a fresh store, log in again.
    await web!.close(); web = undefined; await startWeb();
    await instructorPage.close(); const recoveredPage = await newPage(); await signIn(recoveredPage, instructor); await openSchool(recoveredPage);
    await recoveredPage.locator('.command-review').waitFor();
    const afterRestart = (await pool.query('SELECT operation_id AS "operationId",state FROM drivy_web.profile_command WHERE school_id=$1 AND person_id=$2 ORDER BY created_at DESC LIMIT 1', [schoolId, instructor.personId])).rows[0];
    check(afterRestart.operationId === beforeRestart.operationId && afterRestart.state === 'PREPARED', 'reconnexion après redémarrage BFF retrouve la même intention durable');
    await confirm(recoveredPage);
    const receipt = await apiData(instructor, `schools/${schoolId}/operations/${beforeRestart.operationId}`);
    check(receipt.commandType === 'UPDATE_ADMINISTRATIVE_PROFILE' && receipt.resourceId === initialProfile.id, 'preuve AP72 associe la commande au véritable identifiant du profil');
    const after = await apiData(learner, `schools/${schoolId}/learners/${learnerId}/administrative-profile`);
    check(after.version === z.number().parse(initialProfile.version) + 1 && after.contactPhone === '+41 79 000 00 02' && after.firstName === initialProfile.firstName && after.lastName === initialProfile.lastName &&
      after.birthDate === initialProfile.birthDate && JSON.stringify(after.postalAddress) === JSON.stringify(initialProfile.postalAddress) && after.entrySource === 'STAFF_ASSISTED', 'contact corrigé, noms et champs protégés conservés, provenance accompagnée');
    await recoveredPage.screenshot({ path: fileURLToPath(new URL('03-instructor-contact-saved.png', output)), fullPage: true });
    // Learner's old browser session expired at restart, so reauthenticate before UI reread.
    const rereadPage = await newPage(); await signIn(rereadPage, learner); await openSchool(rereadPage); await openProfile(rereadPage);
    check(await rereadPage.getByLabel(/^Téléphone de contact/).inputValue() === '+41 79 000 00 02' &&
      await rereadPage.getByLabel(/^Date de naissance/).inputValue() === '2000-04-12' &&
      await rereadPage.getByLabel('Rue et numéro', { exact: true }).inputValue() === 'Rue de la Recette 1', 'élève reconnecté relit les mêmes données dans Edge');
    evidence.completed = true; evidence.finishedAt = new Date().toISOString();
  } finally {
    const failureStage = stage;
    await browser?.close().catch(() => { cleanupOK = false; });
    await web?.close().catch(() => { cleanupOK = false; });
    await api?.close().catch(() => { cleanupOK = false; });
    if (seeded) await cleanupOwnRows(pool).catch(() => { cleanupOK = false; });
    for (const probe of probes) if (probe.subject) {
      try { if (!(await admin(`users/${probe.subject}`, { method: 'DELETE' })).ok) cleanupOK = false; } catch { cleanupOK = false; }
    }
    if (clientUUID) { try { if (!(await admin(`clients/${clientUUID}`, { method: 'DELETE' })).ok) cleanupOK = false; } catch { cleanupOK = false; } }
    tokens.clear(); await pool.end();
    evidence.cleanupOK = cleanupOK; evidence.stage = failureStage;
    if (!cleanupOK) evidence.completed = false;
    await persistEvidence();
    if (!cleanupOK) { stage = 'nettoyage ciblé incomplet'; throw new Error('Nettoyage incomplet'); }
  }
  console.log(`Recette Profils réussie : ${checks.length} contrôles, comptes et données de sonde supprimés. Preuves : artifacts/web/profile-entry/${runId}/result.json`);
}
main().catch((error: unknown) => {
  const source = error instanceof Error ? error.stack?.match(/check-profile-entry\.ts:\d+:\d+/)?.[0] : undefined;
  console.error(`Recette Profils interrompue à l’étape : ${stage}.${source ? ` Source : ${source}.` : ''} Aucun secret affiché ; consulter le résultat de ce run.`);
  process.exitCode = 1;
});
