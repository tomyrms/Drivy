export type ReadState<T> = {
  status: 'loading' | 'ready' | 'error';
  data: T | undefined;
  error: string | null;
  /** The read failed because the session ended: retrying is useless, signing in again is the way out. */
  needsLogin?: boolean;
};
export type ScopedReadState<T> = ReadState<T> & { scope: string };

/** Data can survive a refresh, never a change of the resource being displayed. */
export function readStateFor<T>(state: ScopedReadState<T>, scope: string): ReadState<T> {
  return state.scope === scope ? state : { status: 'loading', data: undefined, error: null };
}

/**
 * State after a failed read. A refusal or a missing resource (401, 403, 404) hides what was shown before;
 * any other failure keeps it, flagged as possibly stale by the caller.
 */
export function failedReadState<T>(previous: ScopedReadState<T>, scope: string, failure: { status?: number }, message: string): ScopedReadState<T> {
  const status = failure.status ?? 0;
  return {
    scope, status: 'error', error: message,
    data: [401, 403, 404].includes(status) ? undefined : readStateFor(previous, scope).data,
    ...(status === 401 ? { needsLogin: true } : {}),
  };
}

type CachedRead = { value: unknown; readAt: number; touchedAt: number; bytes: number };

/** Memory only, owned by one authenticated access scope. Explicit resource keys prevent accidental cache aliases. */
export class ScopedReadCache {
  private readonly values = new Map<string, CachedRead>();
  private readonly requests = new Map<string, Promise<unknown>>();
  private generation = 0;
  constructor(private readonly limit = 40, private readonly maximumAge = 120_000, private readonly now = Date.now) {}

  peek<T>(key: string): { value: T; readAt: number } | undefined {
    const entry = this.values.get(key);
    if (!entry) return undefined;
    if (this.now() - entry.readAt > this.maximumAge) { this.values.delete(key); return undefined; }
    entry.touchedAt = this.now();
    return { value: entry.value as T, readAt: entry.readAt };
  }

  read<T>(key: string, loader: () => Promise<T>): Promise<T> {
    const active = this.requests.get(key);
    if (active) return active as Promise<T>;
    const generation = this.generation;
    const request = Promise.resolve().then(loader).then(value => {
      if (generation === this.generation && this.requests.get(key) === request) {
        // Bound stored JSON projections too: no accidental cache of a complete track/photo collection.
        let bytes = Infinity;
        try { bytes = JSON.stringify(value).length * 2; } catch { /* Non-JSON data is not cached. */ }
        if (bytes <= 1_048_576) this.values.set(key, { value, readAt: this.now(), touchedAt: this.now(), bytes });
        else this.values.delete(key);
        while (this.values.size > this.limit || [...this.values.values()].reduce((sum, item) => sum + item.bytes, 0) > 4_194_304) {
          const oldest = [...this.values].sort((a, b) => a[1].touchedAt - b[1].touchedAt)[0];
          if (oldest) this.values.delete(oldest[0]); else break;
        }
      }
      return value;
    }, error => {
      if (generation === this.generation && this.requests.get(key) === request
        && [401, 403, 404].includes((error as { status?: number } | null)?.status ?? 0)) this.values.delete(key);
      throw error;
    }).finally(() => { if (this.requests.get(key) === request) this.requests.delete(key); });
    this.requests.set(key, request);
    return request;
  }

  invalidate(key?: string) {
    if (key !== undefined) { this.values.delete(key); this.requests.delete(key); }
    else { this.generation++; this.values.clear(); this.requests.clear(); }
  }
}
