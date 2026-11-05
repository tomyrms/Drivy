import { createServer, request as httpRequest, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import { request as httpsRequest } from 'node:https';
import { isIPv4, isIPv6, type Socket } from 'node:net';
import { z } from 'zod';
import { clientKey, RateLimiter } from './rate-limit.js';

/**
 * Narrow HTTP frontier for the DIRECT (non-BFF) recovery path of the identity provider.
 *
 * It is a separate entry point, never started by the current web app: installing it and replacing the Caddy refusal
 * is a distinct production operation. It only serves the exact reset-credentials path, limits each proven client
 * address before any transfer to the provider, and forwards the provider flow unchanged (cookies, status, Location).
 *
 * Scope of the counter: one local process, in memory, reset on restart. It is not a distributed or persistent limit.
 */

const RESET_SUFFIX = '/realms/';
const RESET_TAIL = '/login-actions/reset-credentials';
const CONFIG_ERROR = 'RECOVERY_GUARD_CONFIG_INVALID';
const UNAVAILABLE = 'La récupération est momentanément indisponible.';
const TOO_MANY = 'Trop de demandes. Patientez avant de réessayer.';
const REFUSED = 'Requête refusée.';
const NOT_FOUND = 'Introuvable.';
const METHOD = 'Méthode non autorisée.';
const TOO_LARGE = 'Requête trop volumineuse.';
const MEDIA = 'Type de contenu non pris en charge.';

export type RecoveryGuardConfig = {
  listenHost: string; listenPort: number;
  /** Fixed provider origin (`http(s)://host[:port]`), never taken from a request. */
  upstreamOrigin: string;
  /** Keycloak `http-relative-path`: `/` or a prefix such as `/identity`. */
  identityPath: string;
  realm: string;
  /** Host seen by browsers, used for the provider's generated URLs. */
  publicHost: string;
  publicScheme: 'http' | 'https';
  /** Explicit trusted proxy addresses (IP or CIDR). Empty means direct socket address only. */
  trustedProxies: string[];
  limit: number; windowMs: number; capacity: number;
  upstreamTimeoutMs: number; maxBodyBytes: number; maxResponseBytes: number;
  clock: () => number;
};

export type RecoveryGuard = {
  readonly routePath: string;
  readonly server: Server;
  listen(): Promise<{ host: string; port: number }>;
  close(): Promise<void>;
};

type Address = { family: 4 | 6; bytes: number[] };
type Range = { family: 4 | 6; prefix: number; bytes: number[] };

/** Expands a bare IPv6 text into bytes; embedded IPv4 is accepted, zone identifiers are already removed. */
function ipv6Bytes(text: string): number[] | undefined {
  let work = text;
  const tail = /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/.exec(work);
  if (tail) {
    const parts = tail[1]!.split('.').map(Number);
    if (parts.length !== 4 || parts.some(part => !Number.isInteger(part) || part < 0 || part > 255)) return undefined;
    work = `${work.slice(0, tail.index)}${((parts[0]! << 8) | parts[1]!).toString(16)}:${((parts[2]! << 8) | parts[3]!).toString(16)}`;
  }
  const halves = work.split('::');
  if (halves.length > 2) return undefined;
  const head = halves[0] ? halves[0]!.split(':') : [];
  const rest = halves.length === 2 && halves[1] ? halves[1]!.split(':') : [];
  const fill = halves.length === 2 ? 8 - head.length - rest.length : 0;
  if (halves.length === 1 ? head.length !== 8 : fill < 1) return undefined;
  const groups = [...head, ...Array<string>(fill).fill('0'), ...rest].map(group =>
    /^[0-9a-fA-F]{1,4}$/.test(group) ? parseInt(group, 16) : Number.NaN);
  return groups.length === 8 && groups.every(group => Number.isInteger(group) && group >= 0 && group <= 0xffff) ? groups : undefined;
}

function parseAddress(value: string): Address | undefined {
  const bare = value.split('%')[0]!.trim();
  if (!bare) return undefined;
  if (isIPv4(bare)) return { family:4, bytes:bare.split('.').map(Number) };
  if (!isIPv6(bare)) return undefined;
  const groups = ipv6Bytes(bare);
  return groups ? { family:6, bytes:groups.flatMap(group => [group >> 8, group & 0xff]) } : undefined;
}

/** A dual-stack socket may present `::ffff:a.b.c.d`; the limit and the range check both treat it as that IPv4. */
function asIPv4(address: Address): Address {
  if (address.family !== 6) return address;
  const bytes = address.bytes;
  if (bytes.slice(0, 10).every(byte => byte === 0) && bytes[10] === 0xff && bytes[11] === 0xff) return { family:4, bytes:bytes.slice(12) };
  return address;
}

function parseRange(text: string): Range | undefined {
  const parts = text.trim().split('/');
  if (parts.length > 2) return undefined;
  const address = parseAddress(parts[0] ?? '');
  if (!address) return undefined;
  const maximum = address.family === 4 ? 32 : 128;
  const prefix = parts.length === 2 ? Number(parts[1]) : maximum;
  if (!Number.isInteger(prefix) || prefix < 0 || prefix > maximum || parts[1] === '') return undefined;
  return { family:address.family, prefix, bytes:address.bytes };
}

function inRange(value: Address, range: Range): boolean {
  const address = asIPv4(value);
  if (address.family !== range.family) return false;
  const full = Math.floor(range.prefix / 8);
  for (let index = 0; index < full; index++) if (address.bytes[index] !== range.bytes[index]) return false;
  const bits = range.prefix % 8;
  if (bits === 0) return true;
  const mask = (0xff << (8 - bits)) & 0xff;
  return (address.bytes[full]! & mask) === (range.bytes[full]! & mask);
}

/** Validated address text, or undefined. Never guesses a default address. */
function normaliseAddress(value: string | undefined): string | undefined {
  if (value === undefined) return undefined;
  const bare = value.split('%')[0]!.trim();
  return parseAddress(bare) ? bare : undefined;
}

function headerText(value: string | string[] | undefined): string | undefined {
  if (value === undefined) return undefined;
  return Array.isArray(value) ? value.join(',') : value;
}

const LOOPBACK = new Set(['127.0.0.1', 'localhost', '::1', '::ffff:127.0.0.1']);
const HOST_PATTERN = /^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?(?::\d{1,5})?$/;
const REALM_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const PATH_SEGMENT = /^[A-Za-z0-9._~-]+$/;

export function recoveryGuardRoutePath(identityPath: string, realm: string): string {
  return `${identityPath === '/' ? '' : identityPath}${RESET_SUFFIX}${realm}${RESET_TAIL}`;
}

function assertIdentityPath(value: string): string {
  if (value.length > 128) throw new Error(CONFIG_ERROR);
  if (value === '/') return value;
  if (!value.startsWith('/') || value.endsWith('/') || value.includes('//') || value.includes('%') || value.includes('\\')) throw new Error(CONFIG_ERROR);
  const segments = value.slice(1).split('/');
  if (!segments.every(segment => PATH_SEGMENT.test(segment) && segment !== '.' && segment !== '..')) throw new Error(CONFIG_ERROR);
  return value;
}

function publicHostname(host: string): string {
  const withoutPort = host.includes(':') ? host.slice(0, host.lastIndexOf(':')) : host;
  return withoutPort.replace(/^\[(.*)\]$/, '$1').toLowerCase();
}

function parseConfig(env: NodeJS.ProcessEnv): RecoveryGuardConfig {
  const parsed = z.object({
    RECOVERY_GUARD_HOST: z.string().min(1).default('127.0.0.1'),
    RECOVERY_GUARD_PORT: z.coerce.number().int().min(1).max(65_535),
    RECOVERY_GUARD_UPSTREAM_ORIGIN: z.string().min(1),
    RECOVERY_GUARD_IDENTITY_PATH: z.string().default('/'),
    RECOVERY_GUARD_REALM: z.string().min(1),
    RECOVERY_GUARD_PUBLIC_HOST: z.string().min(1),
    RECOVERY_GUARD_PUBLIC_SCHEME: z.enum(['http', 'https']).default('https'),
    RECOVERY_GUARD_TRUSTED_PROXIES: z.string().default(''),
    RECOVERY_GUARD_LIMIT: z.coerce.number().int().min(1).max(600).default(30),
    RECOVERY_GUARD_WINDOW_MS: z.coerce.number().int().min(1_000).max(86_400_000).default(600_000),
    RECOVERY_GUARD_CAPACITY: z.coerce.number().int().min(1).max(100_000).default(4_096),
    RECOVERY_GUARD_UPSTREAM_TIMEOUT_MS: z.coerce.number().int().min(500).max(120_000).default(10_000),
    RECOVERY_GUARD_MAX_BODY_BYTES: z.coerce.number().int().min(256).max(1_048_576).default(16_384),
    RECOVERY_GUARD_MAX_RESPONSE_BYTES: z.coerce.number().int().min(4_096).max(16_777_216).default(1_048_576),
    RECOVERY_GUARD_ALLOW_NON_LOCAL: z.enum(['true', 'false']).default('false'),
  }).parse(env);

  if (!REALM_PATTERN.test(parsed.RECOVERY_GUARD_REALM)) throw new Error(CONFIG_ERROR);
  const identityPath = assertIdentityPath(parsed.RECOVERY_GUARD_IDENTITY_PATH);

  if (!HOST_PATTERN.test(parsed.RECOVERY_GUARD_PUBLIC_HOST)) throw new Error(CONFIG_ERROR);
  const publicPort = parsed.RECOVERY_GUARD_PUBLIC_HOST.includes(':')
    ? Number(parsed.RECOVERY_GUARD_PUBLIC_HOST.slice(parsed.RECOVERY_GUARD_PUBLIC_HOST.lastIndexOf(':') + 1)) : undefined;
  if (publicPort !== undefined && (!Number.isInteger(publicPort) || publicPort < 1 || publicPort > 65_535)) throw new Error(CONFIG_ERROR);
  if (parsed.RECOVERY_GUARD_PUBLIC_SCHEME === 'http' && !LOOPBACK.has(publicHostname(parsed.RECOVERY_GUARD_PUBLIC_HOST))) throw new Error(CONFIG_ERROR);

  const upstream = new URL(parsed.RECOVERY_GUARD_UPSTREAM_ORIGIN);
  if (!['http:', 'https:'].includes(upstream.protocol) || upstream.username || upstream.password ||
      upstream.search || upstream.hash || upstream.pathname !== '/') throw new Error(CONFIG_ERROR);

  if (!LOOPBACK.has(parsed.RECOVERY_GUARD_HOST.toLowerCase()) && parsed.RECOVERY_GUARD_ALLOW_NON_LOCAL !== 'true') throw new Error(CONFIG_ERROR);
  if (!parseAddress(parsed.RECOVERY_GUARD_HOST)) throw new Error(CONFIG_ERROR);

  const trustedProxies = parsed.RECOVERY_GUARD_TRUSTED_PROXIES.length === 0 ? []
    : parsed.RECOVERY_GUARD_TRUSTED_PROXIES.split(',').map(value => value.trim());
  if (trustedProxies.some(value => value.length === 0 || !parseRange(value))) throw new Error(CONFIG_ERROR);

  return {
    listenHost:parsed.RECOVERY_GUARD_HOST, listenPort:parsed.RECOVERY_GUARD_PORT,
    upstreamOrigin:upstream.origin, identityPath, realm:parsed.RECOVERY_GUARD_REALM,
    publicHost:parsed.RECOVERY_GUARD_PUBLIC_HOST, publicScheme:parsed.RECOVERY_GUARD_PUBLIC_SCHEME,
    trustedProxies, limit:parsed.RECOVERY_GUARD_LIMIT, windowMs:parsed.RECOVERY_GUARD_WINDOW_MS,
    capacity:parsed.RECOVERY_GUARD_CAPACITY, upstreamTimeoutMs:parsed.RECOVERY_GUARD_UPSTREAM_TIMEOUT_MS,
    maxBodyBytes:parsed.RECOVERY_GUARD_MAX_BODY_BYTES, maxResponseBytes:parsed.RECOVERY_GUARD_MAX_RESPONSE_BYTES,
    clock:Date.now,
  };
}

/** Explicit configuration only; any doubt fails closed with a code that carries no value. */
export function recoveryGuardConfig(env: NodeJS.ProcessEnv): RecoveryGuardConfig {
  try { return parseConfig(env); } catch { throw new Error(CONFIG_ERROR); }
}

class Refusal extends Error {
  constructor(readonly status: number, readonly text: string, readonly headers: Record<string, string> = {}) { super('RECOVERY_GUARD_REFUSED'); }
}

const COMMON_HEADERS = { 'cache-control':'no-store', pragma:'no-cache', 'x-content-type-options':'nosniff', 'referrer-policy':'no-referrer' } as const;
const FORWARDED_REQUEST_HEADERS = ['accept', 'accept-language', 'content-type', 'cookie', 'origin'] as const;
const FORWARDED_RESPONSE_HEADERS = ['content-type', 'content-language', 'location', 'set-cookie', 'cache-control', 'pragma',
  'content-security-policy', 'x-frame-options', 'x-content-type-options', 'referrer-policy', 'strict-transport-security',
  'x-xss-protection', 'x-robots-tag'] as const;

function sendText(response: ServerResponse, status: number, text: string, headers: Record<string, string> = {}): void {
  if (response.headersSent) { response.destroy(); return; }
  response.writeHead(status, { ...COMMON_HEADERS, 'content-type':'text/plain; charset=utf-8',
    'content-length':String(Buffer.byteLength(text)), ...headers });
  response.end(text);
}

function refusal(response: ServerResponse, error: Refusal): void {
  // A body that was never read must not be parsed as a new request on this socket.
  response.shouldKeepAlive = false;
  sendText(response, error.status, error.text, { connection:'close', ...error.headers });
}

async function readBody(request: IncomingMessage, limit: number): Promise<Buffer | undefined> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = chunk as Buffer;
    size += buffer.length;
    if (size > limit) return undefined;
    chunks.push(buffer);
  }
  return Buffer.concat(chunks);
}

export function buildRecoveryDirectGuard(config: RecoveryGuardConfig): RecoveryGuard {
  const routePath = recoveryGuardRoutePath(config.identityPath, config.realm);
  const ranges = config.trustedProxies.map(parseRange);
  if (ranges.some(range => range === undefined)) throw new Error(CONFIG_ERROR);
  const upstream = new URL(config.upstreamOrigin);
  if (!['http:', 'https:'].includes(upstream.protocol) || upstream.pathname !== '/' || upstream.search || upstream.hash) throw new Error(CONFIG_ERROR);
  const upstreamHostname = upstream.hostname.replace(/^\[(.*)\]$/, '$1');
  const upstreamPort = upstream.port ? Number(upstream.port) : upstream.protocol === 'https:' ? 443 : 80;
  const limiter = new RateLimiter(config.limit, config.windowMs, config.clock, config.capacity);
  const forwardedPort = config.publicHost.includes(':') ? config.publicHost.slice(config.publicHost.lastIndexOf(':') + 1)
    : config.publicScheme === 'https' ? '443' : '80';
  const sockets = new Set<Socket>();

  /** Proof of the client address: socket in direct mode, trusted peer plus overwritten header in proxy mode. */
  const provenAddress = (request: IncomingMessage): string => {
    const peerText = normaliseAddress(request.socket.remoteAddress ?? undefined);
    if (!peerText) throw new Refusal(403, REFUSED);
    if (ranges.length === 0) return peerText;
    const peer = parseAddress(peerText);
    if (!peer || !ranges.some(range => range !== undefined && inRange(peer, range))) throw new Refusal(403, REFUSED);
    const forwarded = headerText(request.headers['x-forwarded-for']);
    if (!forwarded) throw new Refusal(403, REFUSED);
    const values = forwarded.split(',').map(value => value.trim());
    const last = values[values.length - 1];
    // Only the nearest hop value is used; an empty element means the chain is malformed.
    const address = values.some(value => value.length === 0) ? undefined : normaliseAddress(last);
    if (!address) throw new Refusal(403, REFUSED);
    return address;
  };

  const forward = (request: IncomingMessage, response: ServerResponse, method: string, query: string,
    address: string, body: Buffer): void => {
    let settled = false;
    let deadline: NodeJS.Timeout | undefined;
    const settle = (status: number, text: string) => {
      if (settled) return;
      settled = true;
      if (deadline !== undefined) clearTimeout(deadline);
      response.shouldKeepAlive = false;
      sendText(response, status, text, { connection:'close' });
    };
    const headers: Record<string, string> = {
      host:config.publicHost, 'x-forwarded-host':config.publicHost, 'x-forwarded-proto':config.publicScheme,
      'x-forwarded-port':forwardedPort, 'x-forwarded-for':address, 'cache-control':'no-store', connection:'close',
    };
    for (const name of FORWARDED_REQUEST_HEADERS) {
      const value = headerText(request.headers[name]);
      if (value !== undefined) headers[name] = value;
    }
    if (method === 'POST') headers['content-length'] = String(body.length);

    const outgoing = (upstream.protocol === 'https:' ? httpsRequest : httpRequest)({
      protocol:upstream.protocol, hostname:upstreamHostname, port:upstreamPort, method,
      path:`${routePath}${query.length > 0 ? `?${query}` : ''}`, headers, agent:false,
      timeout:config.upstreamTimeoutMs,
      ...(upstream.protocol === 'https:' ? { servername:upstreamHostname } : {}),
    });
    deadline = setTimeout(() => { outgoing.destroy(new Error('UPSTREAM_TIMEOUT')); }, config.upstreamTimeoutMs);
    deadline.unref();
    response.on('close', () => { if (!response.writableFinished) outgoing.destroy(new Error('CLIENT_CLOSED')); });

    outgoing.on('timeout', () => outgoing.destroy(new Error('UPSTREAM_TIMEOUT')));
    outgoing.on('error', () => settle(502, UNAVAILABLE));
    outgoing.on('response', incoming => {
      const status = incoming.statusCode ?? 502;
      const encoding = headerText(incoming.headers['content-encoding']);
      // A provider failure is reported once, generically: no upstream body, no automatic retry (especially not a POST).
      if (status >= 500 || (encoding !== undefined && encoding !== 'identity')) { incoming.destroy(); settle(502, UNAVAILABLE); return; }
      const chunks: Buffer[] = [];
      let size = 0;
      incoming.on('data', chunk => {
        const buffer = chunk as Buffer;
        size += buffer.length;
        if (size > config.maxResponseBytes) { incoming.destroy(); settle(502, UNAVAILABLE); return; }
        chunks.push(buffer);
      });
      incoming.on('error', () => settle(502, UNAVAILABLE));
      incoming.on('end', () => {
        if (settled) return;
        settled = true;
        if (deadline !== undefined) clearTimeout(deadline);
        const payload = Buffer.concat(chunks);
        const reply: Record<string, string | string[]> = { ...COMMON_HEADERS, 'content-length':String(payload.length) };
        for (const name of FORWARDED_RESPONSE_HEADERS) {
          const value = incoming.headers[name];
          if (value !== undefined) reply[name] = value;
        }
        reply['cache-control'] = 'no-store'; reply.pragma = 'no-cache';
        response.writeHead(status, reply);
        response.end(payload);
      });
    });
    outgoing.end(body);
  };

  const respond = async (request: IncomingMessage, response: ServerResponse): Promise<void> => {
    try {
      const method = request.method ?? '';
      if (method !== 'GET' && method !== 'POST') throw new Refusal(405, METHOD, { allow:'GET, POST' });

      const raw = request.url ?? '';
      if (raw.length > 4_096 || raw.includes('#')) throw new Refusal(404, NOT_FOUND);
      const separator = raw.indexOf('?');
      const rawPath = separator === -1 ? raw : raw.slice(0, separator);
      const query = separator === -1 ? '' : raw.slice(separator + 1);
      // Exact byte comparison: no decoding, no normalisation, no traversal, no absolute-form target.
      if (rawPath !== routePath) throw new Refusal(404, NOT_FOUND);
      if (/[^\u0021-\u007e]/.test(query)) throw new Refusal(400, REFUSED);

      const address = provenAddress(request);
      const key = clientKey(address);
      if (!limiter.allow(key)) {
        const wait = Math.max(1, limiter.retryAfterSeconds(key));
        throw new Refusal(429, TOO_MANY, { 'retry-after':String(wait) });
      }

      if (method === 'GET') {
        const declared = headerText(request.headers['content-length']);
        if (request.headers['transfer-encoding'] !== undefined || (declared !== undefined && declared !== '0')) throw new Refusal(400, REFUSED);
        forward(request, response, method, query, address, Buffer.alloc(0));
        return;
      }

      const media = headerText(request.headers['content-type']) ?? '';
      if (!/^application\/x-www-form-urlencoded(?:;\s*charset=utf-8)?$/i.test(media)) throw new Refusal(415, MEDIA);
      if (request.headers['content-encoding'] !== undefined) throw new Refusal(415, MEDIA);
      const declared = headerText(request.headers['content-length']);
      if (declared !== undefined) {
        const length = Number(declared);
        if (!Number.isInteger(length) || length < 0) throw new Refusal(400, REFUSED);
        if (length > config.maxBodyBytes) throw new Refusal(413, TOO_LARGE);
      }
      const body = await readBody(request, config.maxBodyBytes);
      if (body === undefined) throw new Refusal(413, TOO_LARGE);
      forward(request, response, method, query, address, body);
    } catch (error) {
      if (error instanceof Refusal) { refusal(response, error); return; }
      response.shouldKeepAlive = false;
      sendText(response, 502, UNAVAILABLE, { connection:'close' });
    }
  };

  const server = createServer({ requestTimeout:15_000, headersTimeout:10_000, keepAliveTimeout:5_000 },
    (request, response) => { void respond(request, response); });
  server.on('connection', socket => { sockets.add(socket); socket.on('close', () => sockets.delete(socket)); });

  return {
    routePath, server,
    async listen() {
      await new Promise<void>((resolve, reject) => {
        const failed = (error: Error) => { reject(error); };
        server.once('error', failed);
        server.listen(config.listenPort, config.listenHost, () => { server.off('error', failed); resolve(); });
      });
      const address = server.address();
      if (address === null || typeof address === 'string') throw new Error('RECOVERY_GUARD_LISTEN_FAILED');
      return { host:config.listenHost, port:address.port };
    },
    async close() {
      server.closeIdleConnections();
      server.closeAllConnections();
      for (const socket of sockets) socket.destroy();
      sockets.clear();
      await new Promise<void>(resolve => server.close(() => resolve()));
    },
  };
}
