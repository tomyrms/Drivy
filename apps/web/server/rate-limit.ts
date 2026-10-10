/**
 * Fixed-window counter per key (the client address), in memory like the sessions.
 * Bounded: when the table is full of live windows, new keys are refused instead of growing it.
 */
export class RateLimiter {
  private readonly windows = new Map<string, { count: number; resetAt: number }>();
  constructor(private readonly limit: number, private readonly windowMs: number,
    private readonly clock: () => number = Date.now, private readonly capacity = 10_000) {}

  allow(key: string): boolean {
    const now = this.clock();
    let entry = this.windows.get(key);
    if (!entry || entry.resetAt <= now) {
      if (this.windows.size >= this.capacity) this.sweep(now);
      if (this.windows.size >= this.capacity) return false;
      entry = { count: 0, resetAt: now + this.windowMs };
      this.windows.set(key, entry);
    }
    entry.count++;
    return entry.count <= this.limit;
  }

  sweep(now: number = this.clock()): void {
    for (const [key, entry] of this.windows) if (entry.resetAt <= now) this.windows.delete(key);
  }
}
