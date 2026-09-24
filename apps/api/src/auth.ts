import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';
import type { Config } from './config.js';
import { ApiError } from './errors.js';

export interface Identity { issuer: string; subject: string }
export type TokenVerifier = (authorization: string | undefined) => Promise<Identity>;
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
      return { issuer: payload.iss, subject: payload.sub };
    } catch {
      throw new ApiError(401, 'INVALID_SESSION', 'Session invalide ou expirée.');
    }
  };
}
