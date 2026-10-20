import { meters } from '../../apps/api/src/track-matching.ts';
import type { TrackPoint } from '../../apps/api/src/capture-contracts.ts';
export type Coordinate = [number, number];

export function travelDistances(total: number): number[] {
  if (!Number.isFinite(total) || total <= 0 || total > 100_000) throw new Error('INVALID_SYNTHETIC_LENGTH');
  const result: number[] = [];
  const middle = total / 2;
  for (let d = 0; d < middle; d += 11) result.push(d);
  // 21 mesures identiques à 1 Hz délimitent exactement 20 secondes immobiles.
  for (let s = 0; s <= 20; s++) result.push(middle);
  for (let d = middle + 11; d < total; d += 11) result.push(d);
  result.push(total);
  return result;
}

export function coveredPointCount(segments: { segmentId: string; points: { sequence: number }[] }[], spans: { segmentId: string; firstSequence: number; lastSequence: number }[]): number {
  const covered = new Set<string>();
  for (const segment of segments) {
    const ranges = spans.filter(span => span.segmentId === segment.segmentId);
    for (const point of segment.points) {
      if (ranges.some(span => point.sequence >= span.firstSequence && point.sequence <= span.lastSequence)) {
        covered.add(JSON.stringify([segment.segmentId, point.sequence]));
      }
    }
  }
  return covered.size;
}

/** Projection équirectangulaire locale, en mètres. Adaptée à ce trajet suisse, pas aux pôles/antiméridien. */
export function distanceToPolyline(point: Coordinate, line: Coordinate[]): number {
  if (!line.length) throw new Error('EMPTY_REFERENCE_LINE');
  if (line.length === 1) return meters(...point, ...line[0]!);
  const scale = Math.cos(point[0] * Math.PI / 180), radians = Math.PI / 180;
  let best = Infinity;
  for (let i = 1; i < line.length; i++) {
    const a = line[i - 1]!, b = line[i]!;
    const ax = (a[1] - point[1]) * scale, ay = a[0] - point[0];
    const dx = (b[1] - a[1]) * scale, dy = b[0] - a[0];
    const square = dx * dx + dy * dy;
    const t = square > 0 ? Math.max(0, Math.min(1, -(ax * dx + ay * dy) / square)) : 0;
    best = Math.min(best, Math.hypot(ax + t * dx, ay + t * dy) * radians * 6_371_008.8);
  }
  return best;
}

export function makeSyntheticTrace(line: Coordinate[]) {
  if (line.length < 2 || line.some(p => !p.every(Number.isFinite) || Math.abs(p[0]) > 90 || Math.abs(p[1]) > 180)) {
    throw new Error('INVALID_REFERENCE_LINE');
  }
  const cumulative = [0];
  for (let i = 1; i < line.length; i++) cumulative.push(cumulative[i - 1]! + meters(...line[i - 1]!, ...line[i]!));
  const total = cumulative.at(-1)!;
  const distances = travelDistances(total);
  let seed = 7, cursor = 1;
  const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296; };
  const gaussian = () => Math.sqrt(-2 * Math.log(random() || 1e-9)) * Math.cos(2 * Math.PI * random());
  const start = Date.parse('2026-01-01T10:00:00Z');
  const points: TrackPoint[] = distances.map((distance, sequence) => {
    while (cursor < line.length - 1 && cumulative[cursor]! < distance) cursor++;
    const a = line[cursor - 1]!, b = line[cursor]!;
    const length = cumulative[cursor]! - cumulative[cursor - 1]!;
    const fraction = length > 0 ? (distance - cumulative[cursor - 1]!) / length : 0;
    const lat = a[0] + (b[0] - a[0]) * fraction, lon = a[1] + (b[1] - a[1]) * fraction;
    return { sequence, elapsedMs: sequence * 1000, capturedAt: new Date(start + sequence * 1000).toISOString(),
      latitude: lat + gaussian() * 4 / 111_320,
      longitude: lon + gaussian() * 4 / (111_320 * Math.cos(lat * Math.PI / 180)), accuracyMeters: 5 };
  });
  return { points, distances, totalMeters: total };
}
