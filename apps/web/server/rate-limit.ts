import { isIPv4, isIPv6 } from 'node:net';

/** Expands a valid IPv6 text (zone already removed) into its eight 16-bit groups. Embedded IPv4 is accepted. */
function ipv6Groups(address: string): number[] | undefined {
  let text = address;
  const tail = /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/.exec(text);
  if (tail) {
    const parts = tail[1]!.split('.').map(Number);
    text = `${text.slice(0, tail.index)}${((parts[0]! << 8) | parts[1]!).toString(16)}:${((parts[2]! << 8) | parts[3]!).toString(16)}`;
  }
  const halves = text.split('::');
  if (halves.length > 2) return undefined;
  const head = halves[0] ? halves[0].split(':') : [];
  const rest = halves.length === 2 && halves[1] ? halves[1].split(':') : [];
  const fill = halves.length === 2 ? 8 - head.length - rest.length : 0;
  if (halves.length === 1 ? head.length !== 8 : fill < 1) return undefined;
  const groups = [...head, ...Array<string>(fill).fill('0'), ...rest].map(group => parseInt(group, 16));
  return groups.length === 8 && groups.every(group => Number.isInteger(group) && group >= 0 && group <= 0xffff) ? groups : undefined;
}

/**
 * Key of the per-address limit. An IPv6 client is keyed by its /64 prefix (one subscriber owns the whole prefix);
 * an IPv4-mapped address (`::ffff:a.b.c.d`) is keyed as the IPv4 address; any other IPv4 address is unchanged.
 */
export function clientKey(ip: string): string {
  const bare = ip.split('%')[0]!;
  if (isIPv4(bare)) return bare;
  if (!isIPv6(bare)) return ip;
  const groups = ipv6Groups(bare);
  if (!groups) return ip;
  if (groups.slice(0, 5).every(group => group === 0) && groups[5] === 0xffff) {
    return [groups[6]! >> 8, groups[6]! & 0xff, groups[7]! >> 8, groups[7]! & 0xff].join('.');
  }
  return `${groups.slice(0, 4).map(group => group.toString(16)).join(':')}::/64`;
}

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
