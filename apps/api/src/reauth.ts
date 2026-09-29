import { z } from 'zod';
import type { Identity } from './auth.js';
import { ApiError } from './errors.js';

/** Âge maximal (secondes) de l'authentification pour un changement d'accès ; 300 s par défaut, borné à 30–900 s. */
export const reauthAge = (seconds: number | undefined) => z.number().int().min(30).max(900).parse(seconds ?? 300);

/** Un changement d'accès exige une authentification récente signée par le fournisseur d'identité (claim auth_time). */
export function reauthenticate(identity: Identity, age: number) {
  const now = Math.floor(Date.now() / 1000);
  if (identity.authenticatedAt === undefined || identity.authenticatedAt > now + 5 || now - identity.authenticatedAt > age) {
    throw new ApiError(401, 'REAUTH_REQUIRED', 'Reconnectez-vous pour confirmer ce changement d’accès.');
  }
}
