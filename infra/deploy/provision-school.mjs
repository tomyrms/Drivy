#!/usr/bin/env node
/**
 * Bootstrap opérateur, CT114 uniquement ; aucune API publique ni fixture.
 * Node24, pg de la release apps/api. Lire les fichiers privés, jamais les sourcer.
 * Usage root : node provision-school.mjs --apply --username luc
 *   --school-name 'Luc auto école' --contact-email <contact réel>
 *   --operator <opérateur> --authorization-reference <demande autorisée>
 *
 * État de reprise et journal opérationnel : /root/drivy-refonte-provision-<username>.json
 * Accès initial : /root/drivy-refonte-<username>-initial-password.txt, root0600.
 * Ni jeton, mot de passe, erreur SQL ni réponse fournisseur sur stdout/stderr.
 * Le journal local ne remplace pas le futur module métier AuditEvent.
 */
import { randomBytes, randomUUID } from 'node:crypto';
import { constants } from 'node:fs';
import { lstat, open, readFile, rename, unlink } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseEnv } from 'node:util';

export const issuer = 'https://drivy.shulker.ch/identity/realms/drivy';
const adminBase = 'http://127.0.0.1:8081/identity';
const databaseName = 'drivy_refonte';
const ownerName = 'drivy_refonte_owner';
const marker = 'drivyProvisioningOperationId';
const tableNames = ['identity_link', 'membership', 'person', 'school'];
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const require = createRequire(new URL('../../apps/api/package.json', import.meta.url));

function demand(value, message) { if (!value) throw new Error(message); }
function text(value, max = 200) {
  demand(typeof value === 'string' && value.length > 0 && value.length <= max && !/[\u0000-\u001f\u007f]/u.test(value), 'Paramètre texte invalide.');
  return value;
}
export function parseArguments(args) {
  demand(args[0] === '--apply' && args.length === 11, 'Usage : --apply --username … --school-name … --contact-email … --operator … --authorization-reference …');
  const fields = {};
  for (let index = 1; index < args.length; index += 2) {
    const key = args[index];
    demand(['--username', '--school-name', '--contact-email', '--operator', '--authorization-reference'].includes(key) && !(key in fields), 'Paramètre inconnu ou répété.');
    fields[key] = text(args[index + 1], key === '--authorization-reference' ? 500 : 200);
  }
  demand(/^[a-z][a-z0-9-]{1,31}$/.test(fields['--username'] ?? ''), 'Identifiant invalide.');
  demand(/^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(fields['--contact-email'] ?? ''), 'Un contact email réel de l’école est requis.');
  return { username: fields['--username'], schoolName: fields['--school-name'], contactEmail: fields['--contact-email'],
    operator: fields['--operator'], authorizationReference: fields['--authorization-reference'] };
}
export function validateDatabaseURL(value) {
  const target = new URL(value);
  demand(['postgres:', 'postgresql:'].includes(target.protocol) && target.pathname === `/${databaseName}` && target.username === ownerName &&
    target.hostname === 'drivy-db.tailb60275.ts.net' && (target.port === '' || target.port === '5432') &&
    target.searchParams.get('sslmode') === 'verify-full' && target.searchParams.get('sslrootcert') === '/etc/drivy-refonte/db-ca.crt',
  'Le bootstrap exige la base drivy_refonte, son propriétaire et TLS verify-full vers la base privée attendue.');
  return value;
}
async function readPrivate(path) {
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const info = await handle.stat();
    demand(info.isFile() && info.uid === 0 && (info.mode & 0o077) === 0, 'Fichier de configuration ou de reprise non privé.');
    return await handle.readFile('utf8');
  } finally { await handle.close(); }
}
async function atomicPrivate(path, value, exclusive = false) {
  const directory = dirname(path);
  const parent = await lstat(directory);
  demand(parent.isDirectory() && !parent.isSymbolicLink() && parent.uid === 0 && (parent.mode & 0o077) === 0, 'Répertoire privé inattendu.');
  let exists = false;
  try {
    const info = await lstat(path); exists = true;
    demand(info.isFile() && !info.isSymbolicLink() && info.uid === 0 && (info.mode & 0o077) === 0, 'Destination privée invalide.');
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  demand(!exclusive || !exists, 'Destination déjà présente ; aucune réécriture.');
  const temporary = `${path}.${randomUUID()}.tmp`;
  const handle = await open(temporary, 'wx', 0o600);
  try { await handle.writeFile(value); await handle.sync(); }
  finally { await handle.close(); }
  await rename(temporary, path);
  const folder = await open(directory, 'r');
  try { await folder.sync(); } finally { await folder.close(); }
}
export function newOperation(input) {
  return { schemaVersion: 1, operationId: randomUUID(), issuer, ...input, personId: randomUUID(), schoolId: randomUUID(), membershipId: randomUUID(),
    subject: null, initialPassword: null, createdAt: new Date().toISOString(), phase: 'PREPARED', journal: [] };
}
export function validateOperation(state, input) {
  demand(state?.schemaVersion === 1 && state.issuer === issuer && ['operationId', 'personId', 'schoolId', 'membershipId'].every(key => uuid.test(state[key])) &&
    (state.subject === null || uuid.test(state.subject)) && (state.initialPassword === null || /^[A-Za-z0-9_-]{43}$/.test(state.initialPassword)) &&
    ['PREPARED', 'PROFILE_READY', 'PASSWORD_SAVED', 'IDENTITY_READY', 'DATABASE_COMMITTED', 'ACCESS_FILE_READY'].includes(state.phase) && Array.isArray(state.journal),
  'État de reprise invalide.');
  for (const [key, value] of Object.entries(input)) demand(state[key] === value, 'Les paramètres diffèrent de l’opération enregistrée.');
  return state;
}
async function checkpoint(state, event, save) {
  state.phase = event;
  state.journal.push({ at: new Date().toISOString(), event });
  await save(state);
}

/** Adaptateur injecté uniquement par les tests ; la CLI utilise adminBase constant. */
export function keycloakAdmin(base, username, password, realm = 'drivy', expectedIssuer = issuer) {
  const origin = new URL(base).origin;
  let accessToken;
  async function request(path, init = {}, authenticated = true) {
    const target = new URL(`${base}${path}`);
    demand(target.origin === origin, 'Origine administrative inattendue.');
    const headers = { 'Content-Type': 'application/json', ...init.headers };
    if (authenticated) headers.Authorization = `Bearer ${accessToken}`;
    let response;
    try { response = await fetch(target, { ...init, headers, redirect: 'manual', signal: AbortSignal.timeout(15_000) }); }
    catch { throw new Error('Fournisseur d’identité indisponible ; état de reprise conservé.'); }
    return response;
  }
  const prefix = `/admin/realms/${encodeURIComponent(realm)}`;
  return {
    async connect() {
      const discovery = await request(`/realms/${encodeURIComponent(realm)}/.well-known/openid-configuration`, {}, false);
      demand(discovery.ok && (await discovery.json()).issuer === expectedIssuer, 'Issuer fournisseur inattendu.');
      const token = await request('/realms/master/protocol/openid-connect/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ grant_type: 'password', client_id: 'admin-cli', username, password }) }, false);
      demand(token.ok, 'Connexion administrative refusée.');
      const payload = await token.json();
      demand(typeof payload.access_token === 'string', 'Réponse administrative invalide.');
      accessToken = payload.access_token;
    },
    async prepareProfile() {
      const response = await request(`${prefix}/users/profile`);
      demand(response.ok, 'Lecture du profil fournisseur refusée.');
      const profile = await response.json();
      demand(Array.isArray(profile.attributes), 'Profil fournisseur invalide.');
      const email = profile.attributes.find(attribute => attribute.name === 'email');
      demand(email, 'Attribut email attendu absent ; revue du profil nécessaire.');
      // Compte minimal demandé : username et mot de passe. Aucun nom/adresse inventé,
      // ni formulaire UPDATE_PROFILE imposé par les valeurs par défaut de Keycloak.
      for (const attribute of profile.attributes) {
        if (['email', 'firstName', 'lastName'].includes(attribute.name)) delete attribute.required;
      }
      const current = profile.attributes.find(attribute => attribute.name === marker);
      if (current) {
        demand(JSON.stringify(current.permissions?.view) === '["admin"]' && JSON.stringify(current.permissions?.edit) === '["admin"]' && current.multivalued !== true,
          'Marqueur d’opération déjà présent avec des permissions incompatibles.');
      } else {
        profile.attributes.push({ name: marker, displayName: 'Opération de provisionnement Drivy', permissions: { view: ['admin'], edit: ['admin'] }, multivalued: false });
      }
      const saved = await request(`${prefix}/users/profile`, { method: 'PUT', body: JSON.stringify(profile) });
      demand(saved.ok, 'Configuration du profil refusée.');
      const verifiedResponse = await request(`${prefix}/users/profile`);
      demand(verifiedResponse.ok, 'Vérification du profil refusée.');
      const verified = await verifiedResponse.json();
      const verifiedMarker = verified.attributes?.find(attribute => attribute.name === marker);
      demand(['email', 'firstName', 'lastName'].every(name => !verified.attributes?.find(attribute => attribute.name === name)?.required) &&
        JSON.stringify(verifiedMarker?.permissions?.view) === '["admin"]' && JSON.stringify(verifiedMarker?.permissions?.edit) === '["admin"]',
      'Profil fournisseur non conforme après mise à jour.');
    },
    async find(usernameToFind) {
      const response = await request(`${prefix}/users?username=${encodeURIComponent(usernameToFind)}&exact=true&briefRepresentation=false`);
      demand(response.ok, 'Recherche du compte refusée.');
      const users = await response.json();
      demand(Array.isArray(users) && users.length <= 1, 'Résultat de recherche ambigu.');
      return users[0] ?? null;
    },
    async create(state) {
      const response = await request(`${prefix}/users`, { method: 'POST', body: JSON.stringify({ username: state.username, enabled: true,
        requiredActions: ['UPDATE_PASSWORD'], attributes: { [marker]: [state.operationId] },
        credentials: [{ type: 'password', value: state.initialPassword, temporary: true }] }) });
      demand(response.status === 201, 'Création du compte non confirmée ; relancer avec le même état, sans réinitialiser de mot de passe.');
      const id = response.headers.get('location')?.split('/').at(-1);
      demand(uuid.test(id ?? ''), 'Identifiant fournisseur absent ; état de reprise conservé.');
      return id;
    }
  };
}
export async function ensureIdentity(state, admin, save) {
  await admin.connect();
  // Refuser un compte inconnu AVANT toute génération ou modification de mot de passe.
  let user = await admin.find(state.username);
  if (user) {
    demand(uuid.test(user.id) && user.username === state.username && user.attributes?.[marker]?.length === 1 &&
      user.attributes[marker][0] === state.operationId && (state.subject === null || state.subject === user.id),
    'Compte préexistant non attribuable à cette opération ; aucun lien ni mot de passe modifié.');
    demand(state.initialPassword !== null && user.enabled === true, 'Compte de reprise incomplet ou désactivé ; revue opérateur nécessaire.');
  } else {
    demand(state.subject === null, 'Compte fournisseur précédemment lié absent ; aucune recréation automatique.');
    await admin.prepareProfile();
    await checkpoint(state, 'PROFILE_READY', save);
    if (state.initialPassword === null) {
      state.initialPassword = randomBytes(32).toString('base64url');
      await checkpoint(state, 'PASSWORD_SAVED', save);
    }
    const createdId = await admin.create(state);
    user = await admin.find(state.username);
    demand(user?.id === createdId && user.enabled === true && user.username === state.username && user.attributes?.[marker]?.[0] === state.operationId &&
      user.requiredActions?.includes('UPDATE_PASSWORD'), 'Création fournisseur non vérifiable ; état conservé, aucun lien métier créé.');
  }
  state.subject = user.id;
  await checkpoint(state, 'IDENTITY_READY', save);
}

/** Transaction sans appel HTTP. Les quatre tables retrouvent FORCE RLS avant COMMIT. */
export async function provisionDatabase(pool, state) {
  demand(state.issuer === issuer && uuid.test(state.subject ?? ''), 'Identité vérifiée nécessaire avant le bootstrap métier.');
  const db = await pool.connect();
  let begun = false;
  try {
    const identity = await db.query(`SELECT current_database() AS database, current_user AS role, r.rolsuper, r.rolbypassrls
      FROM pg_roles r WHERE r.rolname=current_user`);
    demand(identity.rows[0]?.database === databaseName && identity.rows[0]?.role === ownerName && !identity.rows[0].rolsuper && !identity.rows[0].rolbypassrls,
      'Bootstrap réservé au propriétaire non privilégié de drivy_refonte.');
    await db.query('BEGIN'); begun = true;
    await db.query("SET LOCAL lock_timeout='5s'");
    await db.query("SET LOCAL statement_timeout='15s'");
    await db.query("SET LOCAL idle_in_transaction_session_timeout='20s'");
    // Verrouiller avant les vérifications de collisions ; ordre constant pour toutes les reprises.
    await db.query('LOCK TABLE drivy.identity_link,drivy.membership,drivy.person,drivy.school IN ACCESS EXCLUSIVE MODE');
    const protections = await db.query(`SELECT c.relname,c.relrowsecurity,c.relforcerowsecurity,pg_get_userbyid(c.relowner) AS owner
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND c.relname=ANY($1::text[])`, [tableNames]);
    demand(protections.rows.length === 4 && protections.rows.every(table => table.owner === ownerName && table.relrowsecurity && table.relforcerowsecurity),
      'Les quatre tables doivent appartenir au propriétaire et avoir ENABLE/FORCE RLS avant bootstrap.');
    for (const table of tableNames) await db.query(`ALTER TABLE drivy.${table} NO FORCE ROW LEVEL SECURITY`);
    const people = await db.query('SELECT id,display_name,status FROM drivy.person');
    const links = await db.query('SELECT issuer,subject,person_id FROM drivy.identity_link');
    const schools = await db.query('SELECT id,name,contact_email,status FROM drivy.school');
    const memberships = await db.query('SELECT id,school_id,person_id,status,roles,grants FROM drivy.membership');
    const empty = [people, links, schools, memberships].every(result => result.rowCount === 0);
    let outcome;
    if (empty) {
      await db.query('INSERT INTO drivy.person(id,display_name) VALUES ($1,$2)', [state.personId, state.username]);
      await db.query('INSERT INTO drivy.identity_link(issuer,subject,person_id) VALUES ($1,$2,$3)', [issuer, state.subject, state.personId]);
      await db.query("INSERT INTO drivy.school(id,name,status,contact_email) VALUES ($1,$2,'DRAFT',$3)", [state.schoolId, state.schoolName, state.contactEmail]);
      await db.query("INSERT INTO drivy.membership(id,school_id,person_id,roles) VALUES ($1,$2,$3,ARRAY['ADMIN']::text[])", [state.membershipId, state.schoolId, state.personId]);
      outcome = 'created';
    } else {
      const person = people.rows[0], link = links.rows[0], school = schools.rows[0], member = memberships.rows[0];
      demand([people, links, schools, memberships].every(result => result.rowCount === 1) &&
        person.id === state.personId && person.display_name === state.username && person.status === 'ACTIVE' &&
        link.issuer === issuer && link.subject === state.subject && link.person_id === state.personId &&
        school.id === state.schoolId && school.name === state.schoolName && school.contact_email === state.contactEmail && school.status === 'DRAFT' &&
        member.id === state.membershipId && member.school_id === state.schoolId && member.person_id === state.personId && member.status === 'ACTIVE' &&
        JSON.stringify(member.roles) === '["ADMIN"]' && member.grants.length === 0,
      'Base non vide ou état différent de cette opération ; aucune insertion ni correction automatique.');
      outcome = 'already-committed';
    }
    for (const table of tableNames) await db.query(`ALTER TABLE drivy.${table} FORCE ROW LEVEL SECURITY`);
    const final = await db.query(`SELECT bool_and(relrowsecurity AND relforcerowsecurity) AS protected FROM pg_class c
      JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND c.relname=ANY($1::text[])`, [tableNames]);
    demand(final.rows[0]?.protected === true, 'Protection RLS non rétablie ; transaction annulée.');
    await db.query('COMMIT'); begun = false;
    return outcome;
  } finally {
    if (begun) await db.query('ROLLBACK').catch(() => {});
    db.release();
  }
}

async function main() {
  demand(process.platform === 'linux' && process.getuid?.() === 0 && process.versions.node.split('.')[0] === '24', 'Exécuter sous Node24, comme root dans le conteneur applicatif.');
  process.umask(0o077);
  const input = parseArguments(process.argv.slice(2));
  const statePath = `/root/drivy-refonte-provision-${input.username}.json`;
  const accessPath = `/root/drivy-refonte-${input.username}-initial-password.txt`;
  const lockPath = `${statePath}.lock`;
  let lock;
  try {
    lock = await open(lockPath, 'wx', 0o600);
    await lock.writeFile(JSON.stringify({ pid: process.pid, createdAt: new Date().toISOString() })); await lock.sync();
    const migration = parseEnv(await readPrivate('/etc/drivy-refonte/migration.env'));
    const bootstrap = parseEnv(await readPrivate('/etc/drivy-refonte/identity-bootstrap.env'));
    const api = parseEnv(await readPrivate('/etc/drivy-refonte/api.env'));
    demand(api.OIDC_ISSUER === issuer, 'Issuer API différent de la cible autorisée.');
    const connectionString = validateDatabaseURL(migration.MIGRATION_DATABASE_URL);
    demand(bootstrap.KC_BOOTSTRAP_ADMIN_USERNAME === 'refonte-bootstrap' && bootstrap.KC_BOOTSTRAP_ADMIN_PASSWORD?.length >= 32, 'Bootstrap fournisseur absent ou inattendu.');
    let state;
    try { state = validateOperation(JSON.parse(await readPrivate(statePath)), input); }
    catch (error) {
      if (error.code !== 'ENOENT') throw error;
      state = newOperation(input);
      await atomicPrivate(statePath, JSON.stringify(state, null, 2) + '\n', true);
    }
    const save = current => atomicPrivate(statePath, JSON.stringify(current, null, 2) + '\n');
    const admin = keycloakAdmin(adminBase, bootstrap.KC_BOOTSTRAP_ADMIN_USERNAME, bootstrap.KC_BOOTSTRAP_ADMIN_PASSWORD);
    await ensureIdentity(state, admin, save);
    const { Pool } = require('pg');
    const pool = new Pool({ connectionString, max: 1, connectionTimeoutMillis: 10_000, application_name: 'drivy-controlled-initial-provision' });
    pool.on('error', () => {});
    try { await provisionDatabase(pool, state); } finally { await pool.end(); }
    await checkpoint(state, 'DATABASE_COMMITTED', save);
    const credentialText = `Drivy · accès initial\nIdentifiant : ${state.username}\nMot de passe temporaire : ${state.initialPassword}\nChangement obligatoire à la première connexion.\nCe fichier ne reflète pas les changements de mot de passe ultérieurs.\n`;
    try { demand(await readPrivate(accessPath) === credentialText, 'Fichier d’accès existant différent ; aucune réécriture.'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; await atomicPrivate(accessPath, credentialText, true); }
    await checkpoint(state, 'ACCESS_FILE_READY', save);
    console.log('Compte initial vérifié, école DRAFT et rôle ADMIN préparés ; aucun élève, formation ou mot de passe affiché.');
    console.log('Accès initial conservé dans le fichier root 0600 prévu ; journal opérationnel privé conservé.');
  } finally {
    if (lock) { await lock.close(); await unlink(lockPath).catch(() => {}); }
  }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { console.error('Provisionnement interrompu. État privé conservé ; reprendre avec les mêmes paramètres après vérification locale. Aucun secret affiché.'); process.exitCode = 1; });
}
