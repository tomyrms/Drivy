import type { NavigationQuery } from './route.js';

/** A contextual link always wins over an unsent form from another formation. */
export function resumableDraft<T>(cached: unknown, query: NavigationQuery = {}): T | null {
  if (query.selection || !cached || typeof cached !== 'object') return null;
  const category = 'categoryCode' in cached ? cached.categoryCode : null;
  if (query.category && typeof category === 'string' && category.trim() !== query.category) return null;
  return cached as T;
}
