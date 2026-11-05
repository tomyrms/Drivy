/**
 * Real Keycloak 26.7.4 + Mailpit qualification of the DIRECT recovery frontier.
 *
 * Opt-in only (`RECOVERY_DIRECT_GUARD_RECIPE=1`). Disposable containers, synthetic realm and accounts, loopback ports
 * inventoried before creation. The recipe reaches reset-credentials through the guard, never through the BFF, and keeps
 * no mail link, token, cookie, address or password in its artifacts: anonymous counters and categories only.
 */
import { randomBytes, randomUUID } from 'node:crypto';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer, request as httpRequest } from 'node:http';
import { connect } from 'node:net';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { buildRecoveryDirectGuard, recoveryGuardConfig, type RecoveryGuard } from '../../apps/web/server/recovery-direct-guard.js';

const RECIPE = 'RECOVERY_DIRECT_GUARD_RECIPE';
const REALM = 'drivy-guard-e2e';
const KNOWN_EMAIL = 'compte-garde@example.invalid';
const CLIENT_ID = 'drivy-web-e2e';
const ROUTE = `/realms/${REALM}/login-actions/reset-credentials`;
const CONDITIONAL = 'Si cette adresse correspond à un compte';
const ARTIFACT = new URL('../../artifacts/recovery-direct-guard-50/', import.meta.url);
const CONTAINER_KC = 'drivy-r50-guard-kc';
const CONTAINER_MAIL = 'drivy-r50-guard-mailpit';

const checks:string[] = [];
let stage = 'préparation';
const counts = { allowed:0, refusedAddress:0, refusedRoute:0, refusedLimit:0, unavailable:0, mails:0 };

type Reply = { status:number; headers:Record<string,string|string[]|undefined>; body:string; setCookie:string[] };

function fail(code:string):never { throw new Error(code); }
function assert(value:unknown, label:string):asserts value { stage = label; if (!value) fail('CHECK_FAILED'); checks.push(label); }
function sleep(ms:number) { return new Promise(done => setTimeout(done, ms)); }

function docker(args:string[], capture = false):Promise<string> {
  return new Promise((done, reject) => {
    const child = spawn('docker', args, { stdio:['ignore', capture ? 'pipe' : 'ignore', 'pipe'], windowsHide:true });
    const out:string[] = [];
    child.stdout?.on('data', chunk => out.push(String(chunk)));
    const timer = setTimeout(() => { child.kill(); reject(new Error('DOCKER_TIMEOUT')); }, 180_000);
    child.on('error', () => { clearTimeout(timer); reject(new Error('DOCKER_UNAVAILABLE')); });
    child.on('exit', code => { clearTimeout(timer); if (code === 0) done(out.join('')); else reject(new Error('DOCKER_FAILED')); });
  });
}

function portFree(port:number):Promise<boolean> {
  return new Promise(done => {
    const server = createServer();
    server.once('error', () => done(false));
    server.listen(port, '127.0.0.1', () => server.close(() => done(true)));
  });
}

function canConnect(port:number):Promise<boolean> {
  return new Promise(done => {
    const socket = connect({ host:'127.0.0.1', port });
    socket.once('connect', () => { socket.destroy(); done(true); });
    socket.once('error', () => done(false));
    socket.setTimeout(500, () => { socket.destroy(); done(false); });
  });
}

async function waitFor(url:string, timeoutMs:number):Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url, { redirect:'error', signal:AbortSignal.timeout(2_000) });
      if (response.status < 500) return;
    } catch { /* Service still starting or transient. */ }
    await sleep(500);
  }
  fail('SERVICE_START_TIMEOUT');
}

/** Raw HTTP client: the guard is reached through its listening socket, with explicit proxy headers. */
function send(port:number, path:string, options:{ method?:string; headers?:Record<string,string>; body?:string } = {}):Promise<Reply> {
  return new Promise((done, reject) => {
    const method = options.method ?? 'GET';
    const payload = options.body;
    const request = httpRequest({ host:'127.0.0.1', port, path, method, agent:false,
      headers:{ host:`127.0.0.1:${port}`, connection:'close',
        ...(payload === undefined ? {} : { 'content-length':String(Buffer.byteLength(payload)) }), ...options.headers } },
    response => {
      const chunks:Buffer[] = [];
      response.on('data', chunk => chunks.push(chunk as Buffer));
      response.on('end', () => done({ status:response.statusCode ?? 0, headers:{...response.headers},
        body:Buffer.concat(chunks).toString('utf8'), setCookie:response.headers['set-cookie'] ?? [] }));
    });
    request.setTimeout(15_000, () => request.destroy(new Error('CLIENT_TIMEOUT')));
    request.on('error', reject);
    request.end(payload);
  });
}

type Jar = Map<string,string>;
const cookieHeader = (jar:Jar) => [...jar.entries()].map(([name, value]) => `${name}=${value}`).join('; ');
function absorb(jar:Jar, reply:Reply) {
  for (const cookie of reply.setCookie) {
    const pair = cookie.split(';')[0] ?? '';
    const index = pair.indexOf('=');
    if (index > 0) jar.set(pair.slice(0, index), pair.slice(index + 1));
  }
}
const decode = (text:string) => text.replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
function feedback(body:string):string {
  const match = /class="[^"]*kc-feedback-text[^"]*"[^>]*>([\s\S]*?)<\/(?:span|div|li|p)>/i.exec(body);
  if (!match) fail('FEEDBACK_NOT_FOUND');
  return decode(match[1]!.replace(/<[^>]*>/g, '')).replace(/\s+/g, ' ').trim();
}
function formAction(body:string, guardOrigin:string):URL {
  const match = /<form[^>]+action="([^"]+)"/i.exec(body);
  if (!match) fail('RESET_FORM_NOT_FOUND');
  const target = new URL(decode(match[1]!), guardOrigin);
  // The provider must address its own public frontier: an external action would bypass the guard.
  if (target.origin !== guardOrigin) fail('RESET_FORM_OFF_FRONTIER');
  return target;
}

/** One browser-like session on the frontier: GET the form, POST the username, follow the provider's own redirect. */
async function resetFlow(port:number, jar:Jar, username:string, headers:Record<string,string> = {}):Promise<{ reply:Reply; requests:number }> {
  const origin = `http://127.0.0.1:${port}`;
  let requests = 0;
  const call = async (path:string, options:{ method?:string; headers?:Record<string,string>; body?:string } = {}) => {
    requests++;
    return send(port, path, options);
  };
  const page = await call(`${ROUTE}?client_id=${encodeURIComponent(CLIENT_ID)}&ui_locales=fr`, { headers });
  absorb(jar, page);
  if (page.status !== 200) return { reply:page, requests };
  const action = formAction(page.body, origin);
  let current = await call(`${action.pathname}${action.search}`, { method:'POST', headers:{ ...headers,
    'content-type':'application/x-www-form-urlencoded', cookie:cookieHeader(jar) }, body:`username=${encodeURIComponent(username)}` });
  absorb(jar, current);
  for (let hop = 0; hop < 5 && [301, 302, 303, 307, 308].includes(current.status); hop++) {
    const location = current.headers.location;
    if (typeof location !== 'string' || location.length === 0) break;
    const next = new URL(location, origin);
    if (next.origin !== origin) fail('REDIRECT_OFF_FRONTIER');
    current = await call(`${next.pathname}${next.search}`, { headers:{ ...headers, cookie:cookieHeader(jar) } });
    absorb(jar, current);
  }
  return { reply:current, requests };
}

async function mailTotal(mailpitHttp:string):Promise<number> {
  const response = await fetch(`${mailpitHttp}/api/v1/messages`, { signal:AbortSignal.timeout(5_000) });
  if (!response.ok) fail('MAILPIT_UNAVAILABLE');
  return (await response.json() as { total:number }).total;
}

async function waitForMail(mailpitHttp:string, previous:number):Promise<number> {
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    const total = await mailTotal(mailpitHttp);
    if (total > previous) return total;
    await sleep(200);
  }
  fail('MAIL_NOT_RECEIVED');
}

async function quiet(mailpitHttp:string, ms = 1_500):Promise<number> {
  await sleep(ms);
  return mailTotal(mailpitHttp);
}

async function pickPorts(candidates:number[], count:number, inventory:string):Promise<number[]> {
  const free:number[] = [];
  for (const port of candidates) {
    if (inventory.includes(`:${port}->`) || await canConnect(port) || !(await portFree(port))) continue;
    free.push(port);
    if (free.length === count) return free;
  }
  return fail('LOOPBACK_PORT_UNAVAILABLE');
}

async function main() {
  if (process.env[RECIPE] !== '1') {
    process.stdout.write(`Recette non exécutée : définir ${RECIPE}=1 pour créer des conteneurs jetables.\n`);
    process.exit(2);
  }
  if (Number(process.versions.node.split('.')[0]) !== 24) {
    process.stdout.write(`Recette non exécutée : Node 24 requis (présent ${process.versions.node}).\n`);
    process.exit(2);
  }
  await docker(['version','--format','{{.Server.Version}}']).catch(() => fail('DOCKER_UNAVAILABLE'));
  const compose = await readFile(new URL('../../infra/dev/compose.yaml', import.meta.url), 'utf8');
  const keycloakImage = /image:\s*(quay\.io\/keycloak\/keycloak:[^\s]+)/.exec(compose)?.[1];
  const mailpitImage = /image:\s*(axllent\/mailpit:[^\s]+)/.exec(compose)?.[1];
  if (!keycloakImage || !mailpitImage || !keycloakImage.includes('26.7.4@sha256:') || !mailpitImage.includes('@sha256:')) fail('PINNED_IMAGE_MISSING');
  for (const image of [keycloakImage, mailpitImage]) {
    if (!image.includes((await docker(['image','inspect','--format','{{.Id}}', image])).trim())) fail('IMAGE_DIGEST_MISMATCH');
  }

  // Inventory before creation: name and port collisions are refused, never cleaned by this recipe.
  const before = await docker(['ps','-a','--format','{{.Names}}|{{.Ports}}'], true);
  if (before.includes(CONTAINER_KC) || before.includes(CONTAINER_MAIL)) fail('CONTAINER_NAME_IN_USE');
  const [keycloakPort] = await pickPorts([18081, 18082, 18083], 1, before);
  const [smtpPort] = await pickPorts([18025, 18027], 1, before);
  const [httpPort] = await pickPorts([18026, 18028], 1, before);
  const guardPorts = await pickPorts([18090, 18091, 18092, 18093, 18094, 18095], 4, before);

  const keycloak = `http://127.0.0.1:${keycloakPort}`;
  const mailpitHttp = `http://127.0.0.1:${httpPort}`;
  const guards:RecoveryGuard[] = [];
  let kcCreated = false, mailCreated = false;
  let envPath:string | undefined;
  let adminPassword = '';
  try {
    stage = 'conteneurs jetables sur ports loopback inventoriés';
    await docker(['run','--detach','--rm','--name',CONTAINER_MAIL,'--publish',`127.0.0.1:${smtpPort}:1025`,
      '--publish',`127.0.0.1:${httpPort}:8025`,'--env','MP_MAX_MESSAGES=50',mailpitImage]);
    mailCreated = true;
    await waitFor(`${mailpitHttp}/api/v1/messages`, 30_000);

    adminPassword = randomBytes(24).toString('base64url');
    const knownPassword = randomBytes(24).toString('base64url');
    envPath = resolve(tmpdir(), `drivy-r50-guard-${randomUUID()}.env`);
    await writeFile(envPath, [
      'KC_BOOTSTRAP_ADMIN_USERNAME=drivy-recipe-admin', `KC_BOOTSTRAP_ADMIN_PASSWORD=${adminPassword}`,
      `KC_HOSTNAME=http://127.0.0.1:${guardPorts[0]}`, 'KC_HTTP_ENABLED=true', 'KC_LOG_LEVEL=warn',
      'KC_PROXY_HEADERS=xforwarded',
    ].join('\n'), { mode:0o600 });
    await docker(['run','--detach','--rm','--name',CONTAINER_KC,'--env-file',envPath,
      '--publish',`127.0.0.1:${keycloakPort}:8080`,'--add-host','host.docker.internal:host-gateway',
      '--mount',`type=bind,source=${fileURLToPath(new URL('../../infra/identity/themes/drivy/', import.meta.url))},target=/opt/keycloak/themes/drivy,readonly`,
      keycloakImage,'start-dev']);
    kcCreated = true;
    await waitFor(`${keycloak}/realms/master/.well-known/openid-configuration`, 120_000);

    const token = await fetch(`${keycloak}/realms/master/protocol/openid-connect/token`, { method:'POST',
      headers:{ 'content-type':'application/x-www-form-urlencoded' },
      body:new URLSearchParams({ client_id:'admin-cli', grant_type:'password', username:'drivy-recipe-admin', password:adminPassword }) });
    if (!token.ok) fail('ADMIN_UNAVAILABLE');
    const access = (await token.json() as { access_token?:string }).access_token;
    if (!access) fail('ADMIN_UNAVAILABLE');
    const admin = { Authorization:`Bearer ${access}`, 'Content-Type':'application/json' };

    stage = 'realm et utilisateurs synthétiques créés par la recette';
    const realmBody = {
      realm:REALM, enabled:true, sslRequired:'none', registrationAllowed:false, resetPasswordAllowed:true,
      loginTheme:'drivy', internationalizationEnabled:true, supportedLocales:['fr','en'], defaultLocale:'fr',
      smtpServer:{ host:'host.docker.internal', port:String(smtpPort), from:'identity@drivy.example.invalid',
        ssl:'false', starttls:'false', auth:'false' },
      clients:[{ clientId:CLIENT_ID, publicClient:true, enabled:true, standardFlowEnabled:true, directAccessGrantsEnabled:true,
        implicitFlowEnabled:false, serviceAccountsEnabled:false, redirectUris:['http://127.0.0.1/app/bff/callback'], webOrigins:[],
        protocolMappers:[{ name:'drivy-api-audience', protocol:'openid-connect', protocolMapper:'oidc-audience-mapper',
          consentRequired:false, config:{ 'included.custom.audience':'drivy-api', 'id.token.claim':'false',
            'access.token.claim':'true', 'introspection.token.claim':'true' } }] }],
      users:[{ username:'compte-garde', email:KNOWN_EMAIL, emailVerified:true, enabled:true,
        firstName:'Compte', lastName:'Synthétique', credentials:[{ type:'password', value:knownPassword, temporary:false }] }],
    };
    const created = await fetch(`${keycloak}/admin/realms`, { method:'POST', headers:admin, body:JSON.stringify(realmBody) });
    if (created.status !== 201) fail('REALM_CREATE_FAILED');

    const knownUser = await fetch(`${keycloak}/admin/realms/${REALM}/users?email=${encodeURIComponent(KNOWN_EMAIL)}&exact=true`, { headers:admin });
    const knownUsers = await knownUser.json() as { id?:string }[];
    if (!knownUser.ok || knownUsers.length !== 1 || !knownUsers[0]?.id) fail('SYNTHETIC_IDENTITY_MISSING');
    const knownId = knownUsers[0].id;

    const makeGuard = async (port:number, overrides:Record<string,string> = {}) => {
      const config = recoveryGuardConfig({ ...process.env, RECOVERY_GUARD_HOST:'127.0.0.1', RECOVERY_GUARD_PORT:String(port),
        RECOVERY_GUARD_UPSTREAM_ORIGIN:keycloak, RECOVERY_GUARD_IDENTITY_PATH:'/', RECOVERY_GUARD_REALM:REALM,
        RECOVERY_GUARD_PUBLIC_HOST:`127.0.0.1:${port}`, RECOVERY_GUARD_PUBLIC_SCHEME:'http',
        RECOVERY_GUARD_TRUSTED_PROXIES:'127.0.0.1', ...overrides });
      const guard = buildRecoveryDirectGuard(config);
      guards.push(guard);
      await guard.listen();
      return port;
    };
    const proxied = (forwarded:string, extra:Record<string,string> = {}) => ({ 'x-forwarded-for':forwarded, ...extra });
    const pagePath = `${ROUTE}?client_id=${encodeURIComponent(CLIENT_ID)}&ui_locales=fr`;

    const mainPort = await makeGuard(guardPorts[0]!);
    const clientA = '198.51.100.1', clientB = '198.51.100.10';
    let mails = await mailTotal(mailpitHttp);
    const mailBefore = mails;
    let mainRequests = 0;

    stage = 'GET et POST atteignent réellement le flux de récupération';
    const jarKnown:Jar = new Map();
    const page = await send(mainPort, pagePath, { headers:proxied(clientA) });
    mainRequests++;
    absorb(jarKnown, page);
    assert(page.status === 200 && page.body.includes('name="username"'),
      'GET : la frontière directe rend le formulaire de récupération du fournisseur (200, champ username)');
    assert(page.setCookie.some(cookie => /^AUTH_SESSION_ID=/.test(cookie)) && page.setCookie.every(cookie => !/^__Host-drivy|^drivy-/.test(cookie)),
      'La session du parcours appartient au fournisseur : cookie de flux Keycloak, aucune session Drivy');

    const known = await resetFlow(mainPort, jarKnown, KNOWN_EMAIL, proxied(clientA));
    mainRequests += known.requests;
    assert(known.reply.status === 200 && known.reply.body.includes(CONDITIONAL),
      'POST : une adresse connue reçoit la réponse conditionnelle du thème, sans confirmation d’envoi');
    mails = await waitForMail(mailpitHttp, mails);
    assert(mails === mailBefore + 1, 'Un courrier synthétique réel arrive dans Mailpit après le POST autorisé');
    counts.mails = mails - mailBefore;

    stage = 'adresse inconnue : réponse uniforme et aucun courrier';
    const jarUnknown:Jar = new Map();
    const unknown = await resetFlow(mainPort, jarUnknown, `absent-${randomBytes(6).toString('hex')}@example.invalid`, proxied(clientA));
    mainRequests += unknown.requests;
    assert(unknown.reply.status === 200 && feedback(unknown.reply.body) === feedback(known.reply.body),
      'Adresse connue et adresse inconnue : même statut et même phrase conditionnelle, mot pour mot');
    const afterUnknown = await quiet(mailpitHttp);
    assert(afterUnknown === mails, 'Une adresse inconnue ne produit aucun courrier supplémentaire');

    stage = 'seuil partagé GET/POST de la politique par défaut, refus avant transfert';
    assert(mainRequests < 30, 'Le parcours de recette consomme moins que le seuil de la politique');
    for (let index = mainRequests; index < 30; index++) {
      const allowed = await send(mainPort, pagePath, { headers:proxied(clientA) });
      mainRequests++;
      if (allowed.status !== 200) fail('THRESHOLD_EARLY');
    }
    assert(mainRequests === 30, 'Les trente requêtes GET/POST de la fenêtre sont autorisées, sans refus anticipé');
    counts.allowed += mainRequests;
    const refused = await send(mainPort, ROUTE, { method:'POST', headers:{ ...proxied(clientA),
      'content-type':'application/x-www-form-urlencoded' }, body:`username=${encodeURIComponent(KNOWN_EMAIL)}` });
    assert(refused.status === 429 && Number(refused.headers['retry-after']) > 0 && Number(refused.headers['retry-after']) <= 600,
      'La trente-et-unième requête, un POST, est refusée localement (429) avec une attente utile en Retry-After');
    counts.refusedLimit++;
    assert(!refused.body.includes('@') && !/compte|adresse|existe/i.test(refused.body),
      'Le refus ne décrit aucun compte et ne contient aucune adresse');
    const afterRefusal = await quiet(mailpitHttp);
    assert(afterRefusal === mails, 'Aucun courrier supplémentaire n’est émis après le refus 429');

    stage = 'adresse distincte indépendante du même compteur';
    const jarSecond:Jar = new Map();
    const second = await resetFlow(mainPort, jarSecond, KNOWN_EMAIL, proxied(clientB));
    assert(second.reply.status === 200, 'Une seconde adresse prouvée dispose de son propre budget');
    counts.allowed += second.requests;
    mails = await waitForMail(mailpitHttp, mails);
    assert(mails === mailBefore + 2, 'La seconde adresse autorisée produit son propre courrier');
    counts.mails = mails - mailBefore;

    stage = 'contournement par en-tête refusé';
    const headerPort = await makeGuard(guardPorts[1]!, { RECOVERY_GUARD_LIMIT:'1' });
    const forged = { Forwarded:'for=198.51.100.21', 'X-Real-IP':'198.51.100.22', 'X-Original-Forwarded-For':'198.51.100.23' };
    const first = await send(headerPort, pagePath, { headers:proxied('198.51.100.20', forged) });
    const forgedAgain = await send(headerPort, pagePath, { headers:proxied('198.51.100.20', forged) });
    const otherAddress = await send(headerPort, pagePath, { headers:proxied('198.51.100.24') });
    assert(first.status === 200 && forgedAgain.status === 429 && otherAddress.status === 200,
      'Forwarded, X-Real-IP et X-Original-Forwarded-For ne changent pas la clé ; seule l’adresse transmise par le pair compte');
    counts.allowed += 2; counts.refusedLimit++;

    stage = 'pair non configuré et adresse absente';
    const untrustedPort = await makeGuard(guardPorts[2]!, { RECOVERY_GUARD_TRUSTED_PROXIES:'192.0.2.99' });
    const untrusted = await send(untrustedPort, pagePath, { headers:proxied('198.51.100.30') });
    const noAddress = await send(headerPort, pagePath);
    assert(untrusted.status === 403 && noAddress.status === 403,
      'Un pair non configuré et une adresse absente sont refusés fermés');
    assert((await quiet(mailpitHttp, 500)) === mails, 'Le pair non autorisé n’émet aucun courrier');
    counts.refusedAddress += 2;

    stage = 'route hors périmètre refusée localement';
    const outside = await send(untrustedPort, `/realms/${REALM}/login-actions/authenticate?client_id=${encodeURIComponent(CLIENT_ID)}`,
      { headers:proxied('198.51.100.30') });
    const traversal = await send(mainPort, `/realms/${REALM}/login-actions/reset-credentials/../authenticate`, { headers:proxied(clientB) });
    assert(outside.status === 404 && traversal.status === 404, 'Une autre action Keycloak et une traversée de chemin sont refusées localement');
    counts.refusedRoute += 2;

    stage = 'fenêtre courte contrôlée : refus puis reprise';
    const windowPort = await makeGuard(guardPorts[3]!, { RECOVERY_GUARD_LIMIT:'2', RECOVERY_GUARD_WINDOW_MS:'3000' });
    assert((await send(windowPort, pagePath, { headers:proxied('198.51.100.40') })).status === 200, 'Fenêtre courte : première requête autorisée');
    assert((await send(windowPort, pagePath, { headers:proxied('198.51.100.40') })).status === 200, 'Fenêtre courte : deuxième requête autorisée');
    const windowRefusal = await send(windowPort, pagePath, { headers:proxied('198.51.100.40') });
    assert(windowRefusal.status === 429 && Number(windowRefusal.headers['retry-after']) > 0 && Number(windowRefusal.headers['retry-after']) <= 3,
      'Fenêtre courte : seuil atteint, refus immédiat');
    counts.refusedLimit++;
    await sleep(3_200);
    assert((await send(windowPort, pagePath, { headers:proxied('198.51.100.40') })).status === 200,
      'Après expiration de la fenêtre contrôlée, la même adresse reprend sans attendre dix minutes');

    stage = 'mot de passe et identité toujours gérés par Keycloak';
    const grant = await fetch(`${keycloak}/realms/${REALM}/protocol/openid-connect/token`, { method:'POST',
      headers:{ 'content-type':'application/x-www-form-urlencoded' },
      body:new URLSearchParams({ client_id:CLIENT_ID, grant_type:'password', scope:'openid profile email',
        username:KNOWN_EMAIL, password:knownPassword }) });
    assert(grant.ok, 'Le mot de passe synthétique reste inchangé et vérifié par Keycloak');
    const identity = await fetch(`${keycloak}/admin/realms/${REALM}/users/${knownId}`, { headers:admin });
    const identityBody = await identity.json() as { id?:string; emailVerified?:boolean; email?:string };
    assert(identity.ok && identityBody.id === knownId && identityBody.emailVerified === true && identityBody.email === KNOWN_EMAIL,
      'L’identité OIDC reste la même personne vérifiée : la garde ne crée ni ne modifie aucun compte');

    stage = 'artefact anonyme';
    await mkdir(ARTIFACT, { recursive:true });
    const artifactLabel = 'L’artefact ne contient ni adresse, ni lien, ni jeton, ni cookie, ni mot de passe';
    const labels = [...checks, artifactLabel];
    const result = { status:'PASSED', generatedAt:new Date().toISOString(), node:process.versions.node,
      images:{ keycloak:keycloakImage.split('@')[1] ?? '', mailpit:mailpitImage.split('@')[1] ?? '' },
      ports:{ keycloak:keycloakPort, mailpitSmtp:smtpPort, mailpitHttp:httpPort, guard:guardPorts[0] },
      counts, checks:labels.length, labels };
    const serialized = `${JSON.stringify(result, null, 2)}\n`;
    if (/eyJ|@|set-cookie|bearer|https?:\/\/|session_code|action-token|password/i.test(serialized)) fail('ARTIFACT_IMPURE');
    await writeFile(new URL('result.json', ARTIFACT), serialized);
    checks.push(artifactLabel);
    process.stdout.write(`${checks.length} contrôles réussis.\n`);
  } finally {
    if (kcCreated) {
      try {
        const token = await fetch(`${keycloak}/realms/master/protocol/openid-connect/token`, { method:'POST',
          headers:{ 'content-type':'application/x-www-form-urlencoded' },
          body:new URLSearchParams({ client_id:'admin-cli', grant_type:'password', username:'drivy-recipe-admin', password:adminPassword }) });
        if (token.ok) {
          const access = (await token.json() as { access_token?:string }).access_token;
          if (access) await fetch(`${keycloak}/admin/realms/${REALM}`, { method:'DELETE', headers:{ Authorization:`Bearer ${access}` } });
        }
      } catch { /* The disposable container is the real boundary; realm deletion is best effort. */ }
      await docker(['rm','--force',CONTAINER_KC]).catch(() => undefined);
    }
    if (mailCreated) await docker(['rm','--force',CONTAINER_MAIL]).catch(() => undefined);
    for (const guard of guards.reverse()) await guard.close().catch(() => undefined);
    if (envPath) await rm(envPath, { force:true }).catch(() => undefined);
    const after = await docker(['ps','-a','--format','{{.Names}}'], true).catch(() => '');
    if (after.includes(CONTAINER_KC) || after.includes(CONTAINER_MAIL))
      process.stderr.write('Nettoyage incomplet : un conteneur de recette subsiste.\n');
  }
}

main().catch(error => {
  process.stderr.write(`Recette interrompue à l’étape « ${stage} » : ${(error as Error).message}\n`);
  process.exit(1);
});
