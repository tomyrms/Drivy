import { ApiError } from './errors.js';

/**
 * Fenêtre glissante des échecs par identité OIDC (émetteur + sujet), en mémoire du processus.
 * Un code d'invitation est court : sans ce frein, un compte quelconque pourrait les essayer en série.
 * Le compteur ne contient que des horodatages, jamais de code, de jeton ni de donnée de personne.
 */
export class AttemptLimiter {
  private readonly failures = new Map<string, number[]>();
  constructor(private readonly max = 10, private readonly windowMs = 15 * 60_000, private readonly now: () => number = Date.now) {}
  private recent(key: string): number[] {
    const limit = this.now() - this.windowMs;
    const kept = (this.failures.get(key) ?? []).filter(at => at > limit);
    if (kept.length) this.failures.set(key, kept); else this.failures.delete(key);
    return kept;
  }
  static key(issuer: string, subject: string) { return JSON.stringify([issuer, subject]); }
  /** Refuse (429) tant que la limite d'échecs récents est atteinte ; ne consomme rien. */
  check(key: string) {
    if (this.recent(key).length >= this.max) throw new ApiError(429, 'INVITATION_CODE_ATTEMPTS', 'Trop de codes refusés. Réessayez dans quelques minutes.');
  }
  fail(key: string) { this.failures.set(key, [...this.recent(key), this.now()]); }
  /** Purge les identités dont tous les échecs sont sortis de la fenêtre (appelé de temps en temps pour borner la mémoire). */
  sweep() { for (const key of [...this.failures.keys()]) this.recent(key); }
  get size() { return this.failures.size; }
}
