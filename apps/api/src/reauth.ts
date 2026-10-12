import { z } from 'zod';
import type { Identity } from './auth.js';
import { ApiError } from './errors.js';

/** Âge maximal (secondes) de l'authentification pour un changement d'accès ; 300 s par défaut, borné à 30–900 s. */
export const reauthAge = (seconds: number | undefined) => z.number().int().min(30).max(900).parse(seconds ?? 300);

/** Un changement d'accès exige une authentification récente signée par le fournisseur d'identité (claim auth_time).
 * Un auth_time absent, trop ancien ou dans le futur (au-delà de 5 s de dérive) est refusé. Seul le message varie selon l'action. */
export function reauthenticate(identity: Identity, age: number, message = 'Reconnectez-vous pour confirmer ce changement d’accès.') {
  const now = Math.floor(Date.now() / 1000);
  if (identity.authenticatedAt === undefined || identity.authenticatedAt > now + 5 || now - identity.authenticatedAt > age) {
    throw new ApiError(401, 'REAUTH_REQUIRED', message);
  }
}
