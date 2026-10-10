import { createRemoteJWKSet, errors, jwtVerify, type JWTVerifyGetKey } from 'jose';
import type { Config } from './config.js';
import { ApiError } from './errors.js';

export interface Identity { issuer: string; subject: string; verifiedEmail?: string; displayName?: string; authenticatedAt?: number }
export type TokenVerifier = (authorization: string | undefined) => Promise<Identity>;

/**
 * Les clés publiques du fournisseur d'identité n'ont pas pu être lues (délai, réseau, réponse HTTP non 200) : le jeton n'est pas en cause.
 * Répondre 401 ferait croire à l'app que la session est expirée et la déconnecterait pendant une simple panne ; 503 la fait réessayer.
 * Une clé inconnue, une signature ou une revendication invalide restent des 401.
 */
function identityProviderUnreachable(error: unknown): boolean {
  if (error instanceof errors.JWKSTimeout) return true;
  if (error instanceof errors.JOSEError) return error.code === 'ERR_JOSE_GENERIC';
  if (!(error instanceof Error)) return false;
  const cause = typeof error.cause === 'object' && error.cause !== null && 'code' in error.cause ? error.cause.code : undefined;
  return error.name === 'AbortError' || error.name === 'TimeoutError' || (error instanceof TypeError && error.message === 'fetch failed')
    || (typeof cause === 'string' && /^(E[A-Z_]+|UND_ERR_[A-Z_]+)$/.test(cause));
}

export function createTokenVerifier(config: Pick<Config, 'OIDC_ISSUER' | 'OIDC_AUDIENCE' | 'OIDC_JWKS_URL'>,
  resolver: JWTVerifyGetKey = createRemoteJWKSet(new URL(config.OIDC_JWKS_URL))): TokenVerifier {
  return async authorization => {
    const match = authorization?.match(/^Bearer ([A-Za-z0-9_.-]+)$/i);
    if (!match?.[1]) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
    try {
      const { payload } = await jwtVerify(match[1], resolver, {
        issuer: config.OIDC_ISSUER, audience: config.OIDC_AUDIENCE,
        algorithms: ['RS256', 'ES256'], requiredClaims: ['sub', 'iat', 'exp'], clockTolerance: 5
      });
      if (!payload.sub || !payload.iss) throw new Error('Identité incomplète');
      const email = typeof payload.email === 'string' ? payload.email.trim().normalize('NFC').toLowerCase() : undefined;
      const verifiedEmail = payload.email_verified === true && email && email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : undefined;
      const displayName = typeof payload.name === 'string' && payload.name.trim() && [...payload.name.trim()].length <= 200 ? payload.name.trim() : undefined;
      const authenticatedAt=typeof payload.auth_time==='number' && Number.isSafeInteger(payload.auth_time) && payload.auth_time>=0 && payload.auth_time<=Math.floor(Date.now()/1000)+5?payload.auth_time:undefined;
      return { issuer: payload.iss, subject: payload.sub, ...(verifiedEmail ? {verifiedEmail} : {}), ...(displayName ? {displayName} : {}),...(authenticatedAt!==undefined?{authenticatedAt}:{}) };
    } catch (error) {
      if (identityProviderUnreachable(error)) throw new ApiError(503, 'SERVICE_UNAVAILABLE', 'Service temporairement indisponible.');
      throw new ApiError(401, 'INVALID_SESSION', 'Session invalide ou expirée.');
    }
  };
}
