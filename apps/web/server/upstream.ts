export type ApiResult = { status: number; body: unknown };
export type ApiGateway = (path: string, accessToken: string, body?: unknown) => Promise<ApiResult>;

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
    if (!response.body) throw new Error('Réponse API absente.');
    const chunks: Uint8Array[] = []; let size = 0;
    for await (const chunk of response.body) {
      size += chunk.byteLength;
      if (size > 1024 * 1024) throw new Error('Réponse API trop grande.');
      chunks.push(chunk);
    }
    return { status: response.status, body: JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown };
  };
}
