import type { NavigationQuery } from './route.js';

/** A contextual link always wins over an unsent form from another formation. */
export function resumableDraft<T>(cached: unknown, query: NavigationQuery = {}): T | null {
  if (query.selection || !cached || typeof cached !== 'object') return null;
  const category = 'categoryCode' in cached ? cached.categoryCode : null;
  if (query.category && typeof category === 'string' && category.trim() !== query.category) return null;
  return cached as T;
}

export interface DraftRebase<T> {
  /** Brouillon à garder : champs serveur seuls adoptés, champs locaux seuls conservés. */
  readonly value: T;
  /** Chemins des champs changés des deux côtés différemment ; leur valeur locale est conservée. */
  readonly conflicts: readonly string[];
}

const isRecord = (value: unknown): value is Record<string, unknown> => {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
};

const same = (left: unknown, right: unknown): boolean => JSON.stringify(left) === JSON.stringify(right);

/**
 * Fusionne une confirmation serveur avec la saisie locale postérieure à l'envoi (#106, L3).
 * `sent` est le brouillon remis, `confirmed` la réponse de l'école, `current` la dernière saisie.
 * Un champ non retouché localement prend la valeur confirmée (normalisation ou changement externe) ;
 * un champ retouché seulement localement reste local ; un champ changé des deux côtés différemment
 * conserve la valeur locale et son chemin est signalé. Les objets sont fusionnés récursivement ; un
 * tableau modifié des deux côtés reste local et conflictuel, jamais réordonné au hasard.
 */
export function rebaseConfirmedDraft<T>(sent: T, confirmed: T, current: T): DraftRebase<T> {
  const conflicts: string[] = [];
  const merge = (sentValue: unknown, confirmedValue: unknown, currentValue: unknown, path: string): unknown => {
    if (same(currentValue, sentValue)) return confirmedValue;
    if (same(confirmedValue, sentValue)) return currentValue;
    if (same(currentValue, confirmedValue)) return confirmedValue;
    if (isRecord(sentValue) && isRecord(confirmedValue) && isRecord(currentValue)) {
      const merged: Record<string, unknown> = {};
      const keys = new Set([...Object.keys(sentValue), ...Object.keys(confirmedValue), ...Object.keys(currentValue)]);
      for (const key of keys) {
        const value = merge(sentValue[key], confirmedValue[key], currentValue[key], path ? `${path}.${key}` : key);
        if (value !== undefined) merged[key] = value;
      }
      return merged;
    }
    conflicts.push(path || '$');
    return currentValue;
  };
  return { value: merge(sent, confirmed, current, '') as T, conflicts };
}
