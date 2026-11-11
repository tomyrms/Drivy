/**
 * Paliers d'attente d'une demande suivie (#106 : 5 s et 10 s, seuils indicatifs de #105).
 * Ils ne décrivent que la durée écoulée : aucun palier n'est un refus ni un échec, et la demande reste suivie.
 */
export const pendingThresholdMs = 5_000;
export const slowThresholdMs = 10_000;

export type WaitTier = 'action' | 'pending' | 'slow';

export function waitTier(elapsedMs: number): WaitTier {
  if (elapsedMs >= slowThresholdMs) return 'slow';
  if (elapsedMs >= pendingThresholdMs) return 'pending';
  return 'action';
}

/** Délai avant le prochain palier, ou null une fois le dernier atteint. */
export function nextTierDelayMs(elapsedMs: number): number | null {
  if (elapsedMs < pendingThresholdMs) return pendingThresholdMs - elapsedMs;
  if (elapsedMs < slowThresholdMs) return slowThresholdMs - elapsedMs;
  return null;
}

/** Une ligne par palier ; rien avant 5 s. */
export function waitText(tier: WaitTier): string | null {
  if (tier === 'pending') return 'La demande est en cours.';
  if (tier === 'slow') return 'La réponse tarde. Vous pouvez continuer : le résultat reste suivi.';
  return null;
}
