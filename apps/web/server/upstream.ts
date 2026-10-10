import { isUUID, matchSchoolRoute, type SchoolMethod } from './school-routes.js';

export type ApiResult = { status: number; body: unknown };
export type ApiGateway = (path: string, accessToken: string, body?: unknown) => Promise<ApiResult>;

export type SchoolRequest = {
  method: SchoolMethod; path: string; query: string; body?: unknown;
  idempotencyKey?: string; ifMatch?: string;
};
export type SchoolResult = ApiResult & { etag?: string };
export type SchoolGateway = (request: SchoolRequest, accessToken: string) => Promise<SchoolResult>;

const strongVersion = /^"[1-9][0-9]{0,9}"$/;

async function readJSON(response: Response, limit: number): Promise<unknown> {
  if (!response.body) throw new Error('Réponse API absente.');
  const chunks: Uint8Array[] = []; let size = 0;
  for await (const chunk of response.body) {
    size += chunk.byteLength;
    if (size > limit) throw new Error('Réponse API trop grande.');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown;
}

export function createGateway(baseURL: string): ApiGateway {
  return async (path, accessToken, body) => {
    if (!['/v1/me','/v1/invitations/preview','/v1/invitations/accept'].includes(path)) throw new Error('Route API non autorisée.');
    const response = await fetch(baseURL + path, {
      method: body === undefined ? 'GET' : 'POST', redirect: 'error', signal: AbortSignal.timeout(15_000),
      headers: { Authorization: `Bearer ${accessToken}`, Accept: 'application/json',
        ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
        ...(path === '/v1/invitations/accept' && typeof body === 'object' && body !== null && 'operationId' in body
          ? { 'Idempotency-Key': String(body.operationId) } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) })
    });
    return { status: response.status, body: await readJSON(response, 1024 * 1024) };
  };
}

/**
 * School management relay. The allowlist is checked again here so that no caller can
 * reach another API path with the user's token; only Authorization, Accept, Content-Type,
 * Idempotency-Key and If-Match leave this process. Redirects are refused.
 */
export function createSchoolGateway(baseURL: string): SchoolGateway {
  return async (request, accessToken) => {
    const match = matchSchoolRoute(request.method, request.path.replace(/^\/v1/, ''), request.query);
    if (!match || match.path !== request.path || match.query !== request.query) throw new Error('Route API non autorisée.');
    const write = request.method !== 'GET';
    if (write && (request.body === undefined || !isUUID(request.idempotencyKey))) throw new Error('Commande incomplète.');
    if (request.ifMatch !== undefined && !strongVersion.test(request.ifMatch)) throw new Error('Version invalide.');
    const response = await fetch(baseURL + match.path + match.query, {
      method: request.method, redirect: 'error', signal: AbortSignal.timeout(20_000),
      headers: { Authorization: `Bearer ${accessToken}`, Accept: 'application/json, application/problem+json', 'Cache-Control': 'no-store',
        ...(write ? { 'Content-Type': 'application/json', 'Idempotency-Key': request.idempotencyKey! } : {}),
        ...(request.ifMatch ? { 'If-Match': request.ifMatch } : {}) },
      ...(write ? { body: JSON.stringify(request.body) } : {}),
    });
    const etag = response.headers.get('etag');
    const body = await readJSON(response, 2 * 1024 * 1024);
    return { status: response.status, body, ...(etag && strongVersion.test(etag) ? { etag } : {}) };
  };
}
