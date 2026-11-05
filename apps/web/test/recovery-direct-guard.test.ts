import { createServer, request as httpRequest, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import { afterEach, describe, expect, it } from 'vitest';
import {
  buildRecoveryDirectGuard, recoveryGuardConfig, recoveryGuardRoutePath, type RecoveryGuard,
  type RecoveryGuardConfig,
} from '../server/recovery-direct-guard.js';

const ROUTE = '/realms/drivy/login-actions/reset-credentials';
const cleanups: Array<() => Promise<void>> = [];
const onClose = (close: () => Promise<void>) => { cleanups.push(close); };

afterEach(async () => { while (cleanups.length) await cleanups.pop()!(); });

function config(overrides: Partial<RecoveryGuardConfig> = {}): RecoveryGuardConfig {
  return { listenHost:'127.0.0.1', listenPort:0, upstreamOrigin:'http://127.0.0.1:1', identityPath:'/',
    realm:'drivy', publicHost:'identity.example', publicScheme:'https', trustedProxies:[],
    limit:30, windowMs:600_000, capacity:4096, upstreamTimeoutMs:2_000, maxBodyBytes:16_384,
    maxResponseBytes:262_144, clock:Date.now, ...overrides };
}

type Recorded = { method:string; url:string; headers:Record<string,string|string[]|undefined>; body:string };
type Upstream = { origin:string; seen:Recorded[]; close:()=>Promise<void>; server:Server };

/** Real upstream HTTP server: the guard is exercised through its listening socket, never through a stub function. */
async function upstream(handler?: (request:IncomingMessage, response:ServerResponse, body:string) => void): Promise<Upstream> {
  const seen:Recorded[] = [];
  const server = createServer((request, response) => {
    const chunks:Buffer[] = [];
    request.on('data', chunk => chunks.push(chunk as Buffer));
    request.on('end', () => {
      const body = Buffer.concat(chunks).toString('utf8');
      seen.push({ method:request.method ?? '', url:request.url ?? '', headers:{...request.headers}, body });
      if (handler) handler(request, response, body);
      else { response.writeHead(200, { 'content-type':'text/html; charset=utf-8' }); response.end('<html>form</html>'); }
    });
  });
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
  onClose(() => new Promise<void>(resolve => server.close(() => resolve())));
  const address = server.address();
  if (address === null || typeof address === 'string') throw new Error('UPSTREAM_LISTEN_FAILED');
  return { origin:`http://127.0.0.1:${address.port}`, seen, server,
    close:() => new Promise<void>(resolve => server.close(() => resolve())) };
}

type Reply = { status:number; headers:Record<string,string|string[]|undefined>; body:string };
/** Raw HTTP client: lets a test forge Host, Forwarded or absolute-form targets that fetch() would normalize away. */
function send(port:number, path:string, options:{method?:string; headers?:Record<string,string>; body?:string} = {}): Promise<Reply> {
  return new Promise((resolve, reject) => {
    const request = httpRequest({ host:'127.0.0.1', port, path, method:options.method ?? 'GET', agent:false,
      headers:{ host:`127.0.0.1:${port}`, ...(options.body === undefined ? {} : { 'content-length':String(Buffer.byteLength(options.body)) }), ...options.headers } },
    response => {
      const chunks:Buffer[] = [];
      response.on('data', chunk => chunks.push(chunk as Buffer));
      response.on('end', () => resolve({ status:response.statusCode ?? 0, headers:{...response.headers}, body:Buffer.concat(chunks).toString('utf8') }));
    });
    request.on('error', reject);
    request.end(options.body);
  });
}

async function guard(upstreamOrigin:string, overrides:Partial<RecoveryGuardConfig> = {}): Promise<{ guard:RecoveryGuard; port:number }> {
  const instance = buildRecoveryDirectGuard(config({ upstreamOrigin, ...overrides }));
  onClose(() => instance.close());
  const { port } = await instance.listen();
  return { guard:instance, port };
}

describe('garde directe de récupération : configuration échoue fermée', () => {
  const valid = { RECOVERY_GUARD_PORT:'8082', RECOVERY_GUARD_UPSTREAM_ORIGIN:'http://127.0.0.1:8081',
    RECOVERY_GUARD_REALM:'drivy', RECOVERY_GUARD_PUBLIC_HOST:'drivy.example' } as NodeJS.ProcessEnv;
  it('applique les valeurs sûres par défaut', () => {
    const parsed = recoveryGuardConfig(valid);
    expect(parsed.listenHost).toBe('127.0.0.1'); expect(parsed.listenPort).toBe(8082);
    expect(parsed.identityPath).toBe('/'); expect(parsed.publicScheme).toBe('https');
    expect(parsed.trustedProxies).toEqual([]); expect(parsed.limit).toBe(30);
    expect(parsed.windowMs).toBe(600_000); expect(parsed.capacity).toBe(4096);
    expect(recoveryGuardRoutePath(parsed.identityPath, parsed.realm)).toBe(ROUTE);
  });
  it.each([
    ['port absent', { RECOVERY_GUARD_PORT:undefined }],
    ['origine amont avec chemin', { RECOVERY_GUARD_UPSTREAM_ORIGIN:'http://127.0.0.1:8081/identity' }],
    ['origine amont avec requête', { RECOVERY_GUARD_UPSTREAM_ORIGIN:'http://127.0.0.1:8081/?x=1' }],
    ['origine amont avec identifiants', { RECOVERY_GUARD_UPSTREAM_ORIGIN:'http://user:pass@127.0.0.1:8081' }],
    ['origine amont non HTTP', { RECOVERY_GUARD_UPSTREAM_ORIGIN:'file:///etc/passwd' }],
    ['realm traversant', { RECOVERY_GUARD_REALM:'../master' }],
    ['realm vide', { RECOVERY_GUARD_REALM:'' }],
    ['chemin d’identité relatif', { RECOVERY_GUARD_IDENTITY_PATH:'identity' }],
    ['chemin d’identité terminé par une barre', { RECOVERY_GUARD_IDENTITY_PATH:'/identity/' }],
    ['chemin d’identité traversant', { RECOVERY_GUARD_IDENTITY_PATH:'/identity/..' }],
    ['hôte public injecté', { RECOVERY_GUARD_PUBLIC_HOST:'drivy.example\r\nX-Forwarded-For: 1.2.3.4' }],
    ['hôte public avec chemin', { RECOVERY_GUARD_PUBLIC_HOST:'drivy.example/identity' }],
    ['hôte public avec espace', { RECOVERY_GUARD_PUBLIC_HOST:'drivy example' }],
    ['pair de confiance invalide', { RECOVERY_GUARD_TRUSTED_PROXIES:'192.168.0.0/33' }],
    ['pair de confiance vide', { RECOVERY_GUARD_TRUSTED_PROXIES:'10.0.0.0/8,' }],
    ['seuil nul', { RECOVERY_GUARD_LIMIT:'0' }],
    ['fenêtre nulle', { RECOVERY_GUARD_WINDOW_MS:'0' }],
    ['capacité nulle', { RECOVERY_GUARD_CAPACITY:'0' }],
    ['délai nul', { RECOVERY_GUARD_UPSTREAM_TIMEOUT_MS:'0' }],
    ['corps nul', { RECOVERY_GUARD_MAX_BODY_BYTES:'0' }],
    ['réponse nulle', { RECOVERY_GUARD_MAX_RESPONSE_BYTES:'0' }],
    ['écoute non locale sans accord', { RECOVERY_GUARD_HOST:'0.0.0.0' }],
    ['schéma clair public', { RECOVERY_GUARD_PUBLIC_SCHEME:'http' }],
  ])('refuse %s', (_label, patch) => {
    const env = { ...valid } as Record<string, string | undefined>;
    for (const [key, value] of Object.entries(patch)) { if (value === undefined) delete env[key]; else env[key] = value; }
    expect(() => recoveryGuardConfig(env as NodeJS.ProcessEnv)).toThrow('RECOVERY_GUARD_CONFIG_INVALID');
  });
  it('accepte une écoute privée explicitement confirmée et un schéma clair limité au loopback', () => {
    const parsed = recoveryGuardConfig({ ...valid, RECOVERY_GUARD_HOST:'192.0.2.10', RECOVERY_GUARD_ALLOW_NON_LOCAL:'true',
      RECOVERY_GUARD_PUBLIC_SCHEME:'http', RECOVERY_GUARD_PUBLIC_HOST:'127.0.0.1:8082' });
    expect(parsed.listenHost).toBe('192.0.2.10'); expect(parsed.publicScheme).toBe('http');
  });
  it('compose le chemin exact avec le préfixe d’identité', () => {
    expect(recoveryGuardRoutePath('/identity', 'drivy')).toBe(`/identity${ROUTE}`);
  });
});

describe('garde directe de récupération : frontière HTTP réelle', () => {
  it('laisse passer trente requêtes puis refuse la suivante sans transfert, en conservant le flux amont', async () => {
    const target = await upstream();
    const { port } = await guard(target.origin, { limit:30 });
    for (let index = 0; index < 30; index++) expect((await send(port, `${ROUTE}?client_id=drivy-web`)).status).toBe(200);
    const refused = await send(port, `${ROUTE}?client_id=drivy-web`);
    expect(refused.status).toBe(429);
    expect(Number(refused.headers['retry-after'])).toBeGreaterThan(0);
    expect(Number(refused.headers['retry-after'])).toBeLessThanOrEqual(600);
    expect(target.seen).toHaveLength(30);
    expect(target.seen[0]!.url).toBe(`${ROUTE}?client_id=drivy-web`);
    expect(refused.headers['cache-control']).toBe('no-store');
  });

  it('partage le compteur entre GET et POST et refuse avant tout transfert', async () => {
    const target = await upstream();
    const { port } = await guard(target.origin, { limit:2 });
    expect((await send(port, `${ROUTE}?client_id=drivy-web`)).status).toBe(200);
    expect((await send(port, ROUTE, { method:'POST', headers:{ 'content-type':'application/x-www-form-urlencoded' }, body:'username=synthetic%40example.invalid' })).status).toBe(200);
    expect((await send(port, ROUTE, { method:'POST', headers:{ 'content-type':'application/x-www-form-urlencoded' }, body:'username=other%40example.invalid' })).status).toBe(429);
    expect(target.seen).toHaveLength(2);
    expect(target.seen[1]!.body).toBe('username=synthetic%40example.invalid');
  });

  it('tient chaque adresse prouvée séparément et normalise IPv6 et IPv4 projetée', async () => {
    const target = await upstream();
    const { port } = await guard(target.origin, { limit:1, trustedProxies:['127.0.0.1'] });
    const as = (forwarded:string, headers:Record<string,string> = {}) => send(port, ROUTE, { headers:{ 'x-forwarded-for':forwarded, ...headers } });
    expect((await as('198.51.100.7')).status).toBe(200);
    expect((await as('198.51.100.7')).status).toBe(429);
    expect((await as('198.51.100.8')).status).toBe(200);
    expect((await as('2001:db8:0:1::1')).status).toBe(200);
    expect((await as('2001:db8:0:1:ffff::2')).status).toBe(429);
    expect((await as('2001:db8:0:2::1')).status).toBe(200);
    expect((await as('::ffff:198.51.100.9')).status).toBe(200);
    expect((await as('198.51.100.9')).status).toBe(429);
    expect(target.seen).toHaveLength(5);
  });

  it('ignore les en-têtes forgés hors du pair de confiance et refuse un pair non autorisé', async () => {
    const target = await upstream();
    const direct = await guard(target.origin, { limit:1 });
    expect((await send(direct.port, ROUTE, { headers:{ 'x-forwarded-for':'198.51.100.1' } })).status).toBe(200);
    expect((await send(direct.port, ROUTE, { headers:{ 'x-forwarded-for':'198.51.100.2', 'x-real-ip':'198.51.100.3',
      forwarded:'for=198.51.100.4', 'x-original-forwarded-for':'198.51.100.5' } })).status).toBe(429);
    expect(target.seen).toHaveLength(1);

    const proxied = await guard(target.origin, { limit:1, trustedProxies:['127.0.0.1'] });
    expect((await send(proxied.port, ROUTE, { headers:{ 'x-forwarded-for':'198.51.100.1' } })).status).toBe(200);
    expect((await send(proxied.port, ROUTE, { headers:{ 'x-forwarded-for':'198.51.100.1', 'x-real-ip':'198.51.100.3',
      forwarded:'for=198.51.100.4', 'x-original-forwarded-for':'198.51.100.5' } })).status).toBe(429);
    expect((await send(proxied.port, ROUTE, { headers:{ 'x-forwarded-for':'198.51.100.2' } })).status).toBe(200);

    const untrusted = await guard(target.origin, { limit:1, trustedProxies:['192.0.2.7'] });
    expect((await send(untrusted.port, ROUTE, { headers:{ 'x-forwarded-for':'198.51.100.1' } })).status).toBe(403);
    expect((await send(untrusted.port, ROUTE, { headers:{ 'x-forwarded-for':'198.51.100.1', 'x-real-ip':'198.51.100.1' } })).status).toBe(403);
    expect(target.seen).toHaveLength(3);
  });

  it('refuse une adresse absente ou invalide plutôt que de deviner', async () => {
    const target = await upstream();
    const { port } = await guard(target.origin, { limit:10, trustedProxies:['127.0.0.1'] });
    for (const value of ['', 'unknown', '198.51.100.1:443', '[2001:db8::1]', '198.51.100.1, 198.51.100.2, '])
      expect((await send(port, ROUTE, { headers:{ 'x-forwarded-for':value } })).status).toBe(403);
    expect((await send(port, ROUTE)).status).toBe(403);
    expect(target.seen).toHaveLength(0);
  });

  it('expire avec l’horloge injectée et reprend sans attendre dix minutes', async () => {
    const target = await upstream();
    let now = 0;
    const { port } = await guard(target.origin, { limit:2, windowMs:60_000, clock:() => now });
    expect((await send(port, ROUTE)).status).toBe(200);
    expect((await send(port, ROUTE)).status).toBe(200);
    const refused = await send(port, ROUTE);
    expect(refused.status).toBe(429); expect(refused.headers['retry-after']).toBe('60');
    now = 30_000;
    expect((await send(port, ROUTE)).headers['retry-after']).toBe('30');
    now = 60_001;
    expect((await send(port, ROUTE)).status).toBe(200);
    expect(target.seen).toHaveLength(3);
  });

  it('refuse fermé quand la table bornée est saturée et la libère par le balayage', async () => {
    const target = await upstream();
    let now = 0;
    const proxied = await guard(target.origin, { limit:10, windowMs:1_000, capacity:1, trustedProxies:['127.0.0.1'], clock:() => now });
    expect((await send(proxied.port, ROUTE, { headers:{ 'x-forwarded-for':'198.51.100.1' } })).status).toBe(200);
    expect((await send(proxied.port, ROUTE, { headers:{ 'x-forwarded-for':'198.51.100.2' } })).status).toBe(429);
    now = 1_001;
    expect((await send(proxied.port, ROUTE, { headers:{ 'x-forwarded-for':'198.51.100.2' } })).status).toBe(200);
    expect(target.seen).toHaveLength(2);
  });

  it('refuse localement les routes, méthodes et types hors périmètre sans atteindre l’amont', async () => {
    const target = await upstream();
    const { port } = await guard(target.origin, { limit:100 });
    const refused = [
      ['GET', `${ROUTE}/`], ['GET', `${ROUTE}/..`], ['GET', `${ROUTE}/%2e%2e/authenticate`], ['GET', `${ROUTE}x`],
      ['GET', '/realms/master/login-actions/reset-credentials'], ['GET', '/realms/drivy/login-actions/authenticate'],
      ['GET', `http://evil.example${ROUTE}`], ['GET', `//evil.example${ROUTE}`], ['GET', '/'],
    ] as const;
    for (const [method, path] of refused) expect((await send(port, path, { method })).status).toBe(404);
    for (const method of ['PUT', 'DELETE', 'PATCH', 'HEAD']) {
      const reply = await send(port, ROUTE, { method });
      expect(reply.status).toBe(405); expect(reply.headers.allow).toBe('GET, POST');
    }
    expect((await send(port, ROUTE, { method:'POST', headers:{ 'content-type':'text/plain' }, body:'username=x' })).status).toBe(415);
    expect((await send(port, ROUTE, { method:'POST', headers:{ 'content-type':'application/json' }, body:'{"username":"x"}' })).status).toBe(415);
    expect((await send(port, ROUTE, { method:'GET', body:'username=x' })).status).toBe(400);
    expect((await send(port, ROUTE, { method:'POST', headers:{ 'content-type':'application/x-www-form-urlencoded' },
      body:'username=' + 'a'.repeat(64) }, )).status).toBe(200);
    expect((await send(port, ROUTE, { method:'POST', headers:{ 'content-type':'application/x-www-form-urlencoded' },
      body:'username=' + 'a'.repeat(20_000) })).status).toBe(413);
    expect(target.seen).toHaveLength(1);
  });

  it('fixe l’amont, ne relaie que les en-têtes nécessaires et présente l’URL publique de Keycloak', async () => {
    const target = await upstream();
    const { port } = await guard(target.origin, { limit:10, publicHost:'drivy.shulker.ch', publicScheme:'https' });
    const reply = await send(port, `${ROUTE}?client_id=drivy-web&ui_locales=fr`, { headers:{
      host:'evil.example', cookie:'AUTH_SESSION_ID=synthetic', accept:'text/html', origin:'https://drivy.shulker.ch',
      'x-forwarded-for':'198.51.100.1', 'x-real-ip':'198.51.100.2', forwarded:'for=198.51.100.3', 'x-original-forwarded-for':'198.51.100.4',
      authorization:'Bearer synthetic', referer:'https://evil.example/?token=synthetic' } });
    expect(reply.status).toBe(200);
    const seen = target.seen[0]!;
    expect(seen.url).toBe(`${ROUTE}?client_id=drivy-web&ui_locales=fr`);
    expect(seen.headers.host).toBe('drivy.shulker.ch');
    expect(seen.headers['x-forwarded-host']).toBe('drivy.shulker.ch');
    expect(seen.headers['x-forwarded-proto']).toBe('https');
    expect(seen.headers['x-forwarded-port']).toBe('443');
    expect(seen.headers['x-forwarded-for']).not.toBe('198.51.100.1');
    expect(seen.headers['x-real-ip']).toBeUndefined();
    expect(seen.headers.forwarded).toBeUndefined();
    expect(seen.headers['x-original-forwarded-for']).toBeUndefined();
    expect(seen.headers.authorization).toBeUndefined();
    expect(seen.headers.referer).toBeUndefined();
    expect(seen.headers.cookie).toBe('AUTH_SESSION_ID=synthetic');
    expect(seen.headers.origin).toBe('https://drivy.shulker.ch');
    expect(seen.headers['cache-control']).toBe('no-store');
  });

  it('préserve statut, cookies et Location utiles, et n’ajoute aucune session', async () => {
    const target = await upstream((_request, response) => {
      response.writeHead(303, { location:'/realms/drivy/login-actions/reset-credentials?execution=1',
        'set-cookie':['AUTH_SESSION_ID=synthetic; Path=/realms/drivy/; HttpOnly', 'KC_RESTART=synthetic; Path=/; HttpOnly'],
        'content-type':'text/plain', 'x-powered-by':'keycloak' });
      response.end('redirect');
    });
    const { port } = await guard(target.origin);
    const reply = await send(port, ROUTE);
    expect(reply.status).toBe(303);
    expect(reply.headers.location).toBe('/realms/drivy/login-actions/reset-credentials?execution=1');
    expect(reply.headers['set-cookie']).toEqual(['AUTH_SESSION_ID=synthetic; Path=/realms/drivy/; HttpOnly', 'KC_RESTART=synthetic; Path=/; HttpOnly']);
    expect(reply.headers['x-powered-by']).toBeUndefined();
    expect(reply.headers['cache-control']).toBe('no-store');
  });

  it('répond de façon générique et identique quand le fournisseur échoue, sans divulguer de compte', async () => {
    const broken = createServer((request, response) => { request.socket.destroy(); void response; });
    await new Promise<void>(resolve => broken.listen(0, '127.0.0.1', resolve));
    onClose(() => new Promise<void>(resolve => broken.close(() => resolve())));
    const address = broken.address();
    if (address === null || typeof address === 'string') throw new Error('BROKEN_LISTEN_FAILED');
    const { port } = await guard(`http://127.0.0.1:${address.port}`);
    const first = await send(port, ROUTE, { method:'POST', headers:{ 'content-type':'application/x-www-form-urlencoded' }, body:'username=first%40example.invalid' });
    const second = await send(port, ROUTE, { method:'POST', headers:{ 'content-type':'application/x-www-form-urlencoded' }, body:'username=second%40example.invalid' });
    expect(first.status).toBe(502); expect(second.status).toBe(502);
    expect(first.body).toBe(second.body);
    expect(first.body).toContain('momentanément indisponible');
    expect(first.body).not.toContain('@');
    expect(first.headers['retry-after']).toBeUndefined();
  });

  it('borne le délai, la taille de réponse et ne réessaie jamais un POST', async () => {
    const silent = createServer(() => { /* never answers */ });
    await new Promise<void>(resolve => silent.listen(0, '127.0.0.1', resolve));
    onClose(() => new Promise<void>(resolve => silent.close(() => resolve())));
    const silentAddress = silent.address();
    if (silentAddress === null || typeof silentAddress === 'string') throw new Error('SILENT_LISTEN_FAILED');
    const slow = await guard(`http://127.0.0.1:${silentAddress.port}`, { upstreamTimeoutMs:250, limit:10 });
    const started = Date.now();
    expect((await send(slow.port, ROUTE)).status).toBe(502);
    expect(Date.now() - started).toBeLessThan(3_000);

    const huge = await upstream((_request, response) => { response.writeHead(200, { 'content-type':'text/html' }); response.end('x'.repeat(2_000)); });
    const bounded = await guard(huge.origin, { maxResponseBytes:1_024, limit:10 });
    expect((await send(bounded.port, ROUTE)).status).toBe(502);

    let calls = 0;
    const flaky = await upstream((_request, response) => { calls++; response.writeHead(500, { 'content-type':'text/plain' }); response.end('internal'); });
    const single = await guard(flaky.origin, { limit:10 });
    const reply = await send(single.port, ROUTE, { method:'POST', headers:{ 'content-type':'application/x-www-form-urlencoded' }, body:'username=x' });
    expect(reply.status).toBe(502); expect(reply.body).not.toContain('internal'); expect(calls).toBe(1);
  });
});
