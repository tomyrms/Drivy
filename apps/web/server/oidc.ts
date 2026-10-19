import * as oidc from 'openid-client';
import type { WebConfig } from './config.js';
import type { LoginTransaction, Principal, Tokens } from './session.js';

/** Only the provider's verified auth_time counts. Issuance/refresh times cannot replace authentication. */
export function recentAuthentication(principal: Principal, now: number, maxAgeSeconds: number): boolean {
  const time = principal.authenticatedAt, seconds = Math.floor(now / 1000);
  return typeof time === 'number' && Number.isSafeInteger(time) && time >= 0 && time <= seconds + 5 && seconds - time <= maxAgeSeconds;
}

/** The identity provider could not be reached: the session is not at fault and must survive the outage. */
export class IdentityUnavailable extends Error { constructor() { super('IDENTITY_UNAVAILABLE'); } }
/** The identity provider refused the e-mail and password (or the account is locked for a while): nothing else is told. */
export class InvalidCredentials extends Error { constructor() { super('INVALID_CREDENTIALS'); } }

/**
 * True only for a transport failure or a 5xx of the identity provider (network error, timeout, server error).
 * A refusal of the refresh token (`invalid_grant` and any other 4xx) is a real end of session and stays false.
 */
export function identityUnreachable(error: unknown): boolean {
  for (let current: unknown = error, depth = 0; current !== null && typeof current === 'object' && depth < 5; depth += 1) {
    const item = current as { name?: unknown; message?: unknown; code?: unknown; status?: unknown; cause?: unknown };
    if (item.name === 'AbortError' || item.name === 'TimeoutError' || item.code === 'OAUTH_TIMEOUT') return true;
    if (current instanceof TypeError && item.message === 'fetch failed') return true;
    if (typeof item.code === 'string' && /^(E[A-Z_]+|UND_ERR_[A-Z_]+)$/.test(item.code)) return true;
    if (typeof item.status === 'number' && item.status >= 500 && item.status <= 599) return true;
    current = item.cause;
  }
  return false;
}

export interface IdentityProvider {
  /** `reauthenticate` forces the identity provider to ask for the credentials again (step-up, or right after a sign-out). */
  begin(options?: { reauthenticate?: boolean }): Promise<{ transaction: LoginTransaction; url: string }>;
  complete(url: URL, transaction: LoginTransaction): Promise<Tokens>;
  /** Sign-in with the form of this origin: the password goes to the identity provider and is never kept. */
  password(username: string, password: string): Promise<Tokens>;
  refresh(tokens: Tokens): Promise<Tokens>;
  revoke(tokens: Tokens): Promise<void>;
}

export async function createIdentityProvider(config: WebConfig): Promise<IdentityProvider> {
  const client = await oidc.discovery(new URL(config.issuer), config.clientId,
    { client_secret: config.clientSecret }, oidc.ClientSecretBasic(config.clientSecret),
    { timeout: 10, execute: [oidc.enableNonRepudiationChecks,...(config.development ? [oidc.allowInsecureRequests] : [])] });
  const metadata = client.serverMetadata();
  // A discovered provider cannot redirect tokens to a clear-text or unrelated endpoint.
  for (const endpoint of [metadata.authorization_endpoint,metadata.token_endpoint,metadata.jwks_uri,metadata.revocation_endpoint]) {
    if (!endpoint) continue;
    const url = new URL(endpoint);
    if (url.origin !== new URL(config.issuer).origin || url.username || url.password || url.hash) {
      throw new Error('Point OIDC hors origine configurée.');
    }
  }
  const redirectUri = `${config.origin}/app/bff/callback`;
  const tokensFrom = (response: oidc.TokenEndpointResponse & oidc.TokenEndpointResponseHelpers,
    previous?: Tokens): Tokens => {
    const claims = response.claims();
    if (!previous && (!claims || typeof claims.sub !== 'string')) throw new Error('Identité absente.');
    if (claims && previous && claims.sub !== previous.principal.subject) throw new Error('Identité différente.');
    if (response.token_type.toLowerCase() !== 'bearer' || !response.access_token || !response.expires_in || response.expires_in <= 0) {
      throw new Error('Jeton incomplet.');
    }
    const principal = claims ? { subject: claims.sub,
      displayName: typeof claims.name === 'string' ? claims.name : typeof claims.preferred_username === 'string' ? claims.preferred_username : 'Mon compte',
      ...(typeof claims.email === 'string' ? { email: claims.email } : {}), emailVerified: claims.email_verified === true,
      ...(typeof claims.auth_time === 'number' && Number.isSafeInteger(claims.auth_time) && claims.auth_time >= 0 ? { authenticatedAt: claims.auth_time } : {}) }
      : previous!.principal;
    const refreshToken = response.refresh_token ?? previous?.refreshToken;
    return { accessToken: response.access_token, expiresAt: Date.now() + response.expires_in * 1000,
      principal, ...(refreshToken ? { refreshToken } : {}) };
  };
  return {
    async begin(options) {
      const transaction = { state: oidc.randomState(), nonce: oidc.randomNonce(),
        verifier: oidc.randomPKCECodeVerifier(), expiresAt: Date.now() + 5 * 60_000 };
      const url = oidc.buildAuthorizationUrl(client, { redirect_uri: redirectUri,
        scope: 'openid profile email', response_type: 'code', ...(options?.reauthenticate ? { prompt: 'login', max_age: '0' } : {}), state: transaction.state, nonce: transaction.nonce,
        code_challenge: await oidc.calculatePKCECodeChallenge(transaction.verifier), code_challenge_method: 'S256' });
      return { transaction, url: url.href };
    },
    async complete(url, transaction) {
      return tokensFrom(await oidc.authorizationCodeGrant(client,url,{ expectedState: transaction.state,
        expectedNonce: transaction.nonce, pkceCodeVerifier: transaction.verifier, idTokenExpected: true }));
    },
    async password(username, password) {
      try { return tokensFrom(await oidc.genericGrantRequest(client,'password',{ username, password, scope: 'openid profile email' })); }
      catch (error) {
        if (identityUnreachable(error)) throw new IdentityUnavailable();
        const code = (error as { error?: unknown }).error;
        if (code === 'invalid_grant') throw new InvalidCredentials();
        throw error;
      }
    },
    async refresh(tokens) {
      if (!tokens.refreshToken) throw new Error('Session expirée.');
      try { return tokensFrom(await oidc.refreshTokenGrant(client,tokens.refreshToken),tokens); }
      catch (error) { throw identityUnreachable(error) ? new IdentityUnavailable() : error; }
    },
    async revoke(tokens) { if (tokens.refreshToken) await oidc.tokenRevocation(client,tokens.refreshToken,{ token_type_hint: 'refresh_token' }); }
  };
}
