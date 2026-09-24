import * as oidc from 'openid-client';
import type { WebConfig } from './config.js';
import type { LoginTransaction, Tokens } from './session.js';

export interface IdentityProvider {
  begin(): Promise<{ transaction: LoginTransaction; url: string }>;
  complete(url: URL, transaction: LoginTransaction): Promise<Tokens>;
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
      ...(typeof claims.email === 'string' ? { email: claims.email } : {}), emailVerified: claims.email_verified === true }
      : previous!.principal;
    const refreshToken = response.refresh_token ?? previous?.refreshToken;
    return { accessToken: response.access_token, expiresAt: Date.now() + response.expires_in * 1000,
      principal, ...(refreshToken ? { refreshToken } : {}) };
  };
  return {
    async begin() {
      const transaction = { state: oidc.randomState(), nonce: oidc.randomNonce(),
        verifier: oidc.randomPKCECodeVerifier(), expiresAt: Date.now() + 5 * 60_000 };
      const url = oidc.buildAuthorizationUrl(client, { redirect_uri: redirectUri,
        scope: 'openid profile email', response_type: 'code', prompt:'login', state: transaction.state, nonce: transaction.nonce,
        code_challenge: await oidc.calculatePKCECodeChallenge(transaction.verifier), code_challenge_method: 'S256' });
      return { transaction, url: url.href };
    },
    async complete(url, transaction) {
      return tokensFrom(await oidc.authorizationCodeGrant(client,url,{ expectedState: transaction.state,
        expectedNonce: transaction.nonce, pkceCodeVerifier: transaction.verifier, idTokenExpected: true }));
    },
    async refresh(tokens) {
      if (!tokens.refreshToken) throw new Error('Session expirée.');
      return tokensFrom(await oidc.refreshTokenGrant(client,tokens.refreshToken),tokens);
    },
    async revoke(tokens) { if (tokens.refreshToken) await oidc.tokenRevocation(client,tokens.refreshToken,{ token_type_hint: 'refresh_token' }); }
  };
}
