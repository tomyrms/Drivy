import type { TrackPoint } from './capture-contracts.js';

/**
 * Recalage routier d'un trajet : logique pure, sans réseau ni base.
 *
 * Quatre couches restent distinctes. Les mesures (`TrackPoint`) ne sont jamais modifiées. La sélection
 * (`selectTrack`) écarte le bruit du capteur ; elle est la copie exacte du filtre d'affichage de l'app
 * (`SchoolCaptureDisplayRoute.Selector`), pour que les bornes d'un tronçon recalé désignent toujours une
 * mesure que l'app affiche. Le tronçon recalé (`MatchedSpan`) dit seulement « entre ces deux mesures, le
 * véhicule a très probablement suivi cette géométrie ». L'interpolation d'affichage reste dans l'app.
 */
export const TRACK_MATCHING_ALGORITHM_VERSION = 1;

export const selection = { maximumAccuracyMeters: 30, maximumSpeedMetersPerSecond: 50, maximumGapMs: 15_000, maximumJumpSlackMeters: 20, bridgeMs: 4_000 } as const;
/** Limite documentée de l'API Map Matching ; OSRM accepte la même taille. */
export const BATCH_SIZE = 100;
/** Les lots se recouvrent : chacun n'est retenu que loin de ses bords, où le recalage manque de contexte. */
export const BATCH_OVERLAP = 10;
export const MAXIMUM_BATCHES = 80;

export interface SelectedPoint { point: TrackPoint; startsFragment: boolean; heldUntilMs: number }
export interface MatcherPoint { sequence: number; latitude: number; longitude: number; timestampMs: number; radiusMeters: number }
export interface MatchedSpan { segmentId: string; firstSequence: number; lastSequence: number; confidence: number; geometry: string; anchors: [number, number][] }
export interface Tracepoint { matchingIndex: number; latitude: number; longitude: number }
export interface MatcherResult { matchings: { confidence: number; geometry: [number, number][] }[]; tracepoints: (Tracepoint | null)[] }

const EARTH_RADIUS = 6_371_008.8, RAD = Math.PI / 180;
export function meters(lat1: number, lon1: number, lat2: number, lon2: number): number {
  let dLon = lon2 - lon1;
  if (dLon > 180) dLon -= 360; else if (dLon < -180) dLon += 360;
  const x = dLon * RAD * Math.cos((lat1 + lat2) / 2 * RAD), y = (lat2 - lat1) * RAD;
  return Math.sqrt(x * x + y * y) * EARTH_RADIUS;
}
export function bearing(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const p1 = lat1 * RAD, p2 = lat2 * RAD, l = (lon2 - lon1) * RAD;
  return (Math.atan2(Math.sin(l) * Math.cos(p2), Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(l)) / RAD + 360) % 360;
}
function angleDelta(from: number, to: number): number {
  let delta = (to - from) % 360;
  if (delta > 180) delta -= 360; else if (delta <= -180) delta += 360;
  return delta;
}
/** Distance d'un point au segment qui relie deux autres. */
function deviation(a: TrackPoint, b: TrackPoint, p: TrackPoint): number {
  const scale = Math.cos(a.latitude * RAD) || 1, ax = a.longitude * scale, bx = b.longitude * scale, px = p.longitude * scale;
  const dx = bx - ax, dy = b.latitude - a.latitude, square = dx * dx + dy * dy;
  const t = square > 0 ? Math.max(0, Math.min(1, ((px - ax) * dx + (p.latitude - a.latitude) * dy) / square)) : 0;
  return meters(p.latitude, p.longitude, a.latitude + dy * t, (ax + dx * t) / scale);
}
const between = (a: TrackPoint, b: TrackPoint) => meters(a.latitude, a.longitude, b.latitude, b.longitude);
const heading = (a: TrackPoint, b: TrackPoint) => bearing(a.latitude, a.longitude, b.latitude, b.longitude);

/** Même politique, mêmes seuils et même ordre de décisions que l'app. Toute évolution se fait des deux côtés. */
export function selectTrack(source: TrackPoint[], maximumGapMs: number = selection.maximumGapMs): SelectedPoint[] {
  const ordered = [...source].sort((a, b) => a.sequence - b.sequence), samples: SelectedPoint[] = [];
  let previous: { sequence: number; elapsedMs: number } | undefined;
  let forcedGap = true, rejected = false, moving = false, lastBearing: number | undefined;
  const start = (point: TrackPoint) => { samples.push({ point, startsFragment: true, heldUntilMs: point.elapsedMs }); forcedGap = false; rejected = false; moving = false; lastBearing = undefined; };
  const accept = (point: TrackPoint, anchor: SelectedPoint) => {
    const span = point.elapsedMs - anchor.heldUntilMs, starts = forcedGap || span > maximumGapMs || (rejected && span > selection.bridgeMs);
    samples.push({ point, startsFragment: starts, heldUntilMs: point.elapsedMs });
    if (starts) { moving = false; lastBearing = undefined; }
    else { moving = span > 0 && between(anchor.point, point) / (span / 1000) >= 1; lastBearing = heading(anchor.point, point); }
    forcedGap = false; rejected = false;
  };
  const isSpike = (before: SelectedPoint, spike: TrackPoint, after: TrackPoint) => {
    const seconds = (after.elapsedMs - before.heldUntilMs) / 1000;
    if (!(seconds > 0 && seconds <= 4)) return false;
    // Loin de la ligne qui relie ses deux voisines, pour un détour au moins double du chemin direct.
    const leg = Math.max(12, 2.5 * spike.accuracyMeters);
    return deviation(before.point, after, spike) >= leg && between(before.point, spike) + between(spike, after) >= 2 * between(before.point, after);
  };
  for (const point of ordered) {
    const prior = previous;
    previous = { sequence: point.sequence, elapsedMs: point.elapsedMs };
    const silence = !prior || (point.sequence > prior.sequence && point.elapsedMs > prior.elapsedMs && point.elapsedMs - prior.elapsedMs > maximumGapMs);
    const valid = point.sequence >= 0 && point.elapsedMs >= 0 && Number.isFinite(point.latitude) && Number.isFinite(point.longitude)
      && Math.abs(point.latitude) <= 90 && Math.abs(point.longitude) <= 180 && Number.isFinite(point.accuracyMeters)
      && point.accuracyMeters >= 0 && point.accuracyMeters <= selection.maximumAccuracyMeters;
    if (!valid) { rejected = true; continue; }
    if (prior) {
      if (!(point.sequence > prior.sequence && point.elapsedMs > prior.elapsedMs)) { forcedGap = true; continue; }
      if (point.sequence !== prior.sequence + 1) forcedGap = true;
    }
    const retained = samples.at(-1);
    if (!retained) { start(point); continue; }
    const seconds = (point.elapsedMs - retained.heldUntilMs) / 1000;
    if (!(seconds > 0)) { forcedGap = true; continue; }
    if (silence) { start(point); continue; }
    const distance = between(retained.point, point);
    const slack = Math.min(selection.maximumJumpSlackMeters, retained.point.accuracyMeters + point.accuracyMeters);
    if (Math.max(0, distance - slack) / seconds > selection.maximumSpeedMetersPerSecond) { rejected = true; continue; }
    const radius = Math.max(3, Math.min(15, Math.max(retained.point.accuracyMeters, point.accuracyMeters)));
    if (distance < radius) {
      const continues = moving && distance >= 1.5 && distance / seconds >= 1
        && lastBearing !== undefined && Math.abs(angleDelta(lastBearing, heading(retained.point, point))) <= 60;
      if (!continues) { moving = false; retained.heldUntilMs = point.elapsedMs; rejected = false; continue; }
    }
    const before = samples.at(-2);
    if (before && !forcedGap && !rejected && !retained.startsFragment && retained.heldUntilMs === retained.point.elapsedMs && isSpike(before, retained.point, point)) {
      samples.pop(); rejected = true; moving = false; lastBearing = undefined;
      accept(point, before);
      continue;
    }
    accept(point, retained);
  }
  return samples;
}

/** Suites continues de mesures retenues : un recalage ne traverse jamais une lacune. */
export function continuousRuns(samples: SelectedPoint[]): SelectedPoint[][] {
  const runs: SelectedPoint[][] = [];
  for (const sample of samples) { if (sample.startsFragment || !runs.length) runs.push([]); runs.at(-1)!.push(sample); }
  return runs;
}

/**
 * Points confiés au moteur : les extrémités, les arrêts (ils rythment la lecture) et un point tous les
 * vingt mètres au moins, jamais deux dans la même seconde. Le reste des mesures se replace entre eux.
 */
export function matcherPoints(run: SelectedPoint[]): MatcherPoint[] {
  const kept: MatcherPoint[] = [];
  let last: SelectedPoint | undefined;
  run.forEach((sample, index) => {
    const edge = index === 0 || index === run.length - 1, held = sample.heldUntilMs - sample.point.elapsedMs >= 3_000;
    if (last && !edge) {
      if (sample.point.elapsedMs - last.point.elapsedMs < 1_000) return;
      if (!held && between(last.point, sample.point) < 20) return;
    }
    if (last && sample.point.elapsedMs - last.point.elapsedMs < 1_000) kept.pop();
    kept.push({ sequence: sample.point.sequence, latitude: sample.point.latitude, longitude: sample.point.longitude,
      timestampMs: Date.parse(sample.point.capturedAt), radiusMeters: Math.max(10, Math.min(40, Math.round(sample.point.accuracyMeters) + 10)) });
    last = sample;
  });
  return kept;
}

/** Lots d'au plus cent points qui se recouvrent ; `from`/`to` bornent la part retenue de chacun, et deux lots voisins partagent leur point de raccord. */
export function batches(count: number, size = BATCH_SIZE, overlap = BATCH_OVERLAP): { start: number; end: number; from: number; to: number }[] {
  if (count < 2) return [];
  const result: { start: number; end: number; from: number; to: number }[] = [];
  let start = 0;
  for (;;) {
    const end = Math.min(count, start + size), last = end === count;
    result.push({ start, end, from: start === 0 ? 0 : start + Math.floor(overlap / 2), to: last ? count - 1 : end - Math.floor(overlap / 2) });
    if (last) break;
    start = end - overlap;
  }
  return result;
}

export function encodePolyline(points: [number, number][], precision = 6): string {
  const factor = 10 ** precision;
  let output = '', previousLat = 0, previousLon = 0;
  const write = (value: number) => {
    let v = value < 0 ? ~(value << 1) : value << 1;
    while (v >= 0x20) { output += String.fromCharCode((0x20 | (v & 0x1f)) + 63); v >>>= 5; }
    output += String.fromCharCode(v + 63);
  };
  for (const [lat, lon] of points) {
    const a = Math.round(lat * factor), b = Math.round(lon * factor);
    write(a - previousLat); write(b - previousLon); previousLat = a; previousLon = b;
  }
  return output;
}
export function decodePolyline(text: string, precision = 6): [number, number][] {
  const factor = 10 ** precision, result: [number, number][] = [];
  let index = 0, lat = 0, lon = 0;
  const read = (): number | undefined => {
    let shift = 0, value = 0;
    while (index < text.length) {
      const byte = text.charCodeAt(index++) - 63;
      if (byte < 0 || shift > 30) return undefined;
      value |= (byte & 0x1f) << shift; shift += 5;
      if (byte < 0x20) return value & 1 ? ~(value >> 1) : value >> 1;
    }
    return undefined;
  };
  while (index < text.length) {
    const a = read(), b = read();
    if (a === undefined || b === undefined) return [];
    lat += a; lon += b;
    if (Math.abs(lat / factor) > 90 || Math.abs(lon / factor) > 180) return [];
    result.push([lat / factor, lon / factor]);
  }
  return result;
}

function cumulativeLengths(line: [number, number][]): number[] {
  const out = [0];
  for (let i = 1; i < line.length; i++) out.push(out[i - 1]! + meters(line[i - 1]![0], line[i - 1]![1], line[i]![0], line[i]![1]));
  return out;
}
/** Distance le long de la ligne du point le plus proche, cherchée vers l'avant depuis `fromMeters`. */
function project(line: [number, number][], cumulative: number[], lat: number, lon: number, fromMeters: number): { along: number; offset: number } {
  let best = { along: fromMeters, offset: Infinity };
  for (let i = 1; i < line.length; i++) {
    if (cumulative[i]! < fromMeters) continue;
    const [aLat, aLon] = line[i - 1]!, [bLat, bLon] = line[i]!, length = cumulative[i]! - cumulative[i - 1]!;
    const scale = Math.cos(aLat * RAD), ax = aLon * scale, bx = bLon * scale, px = lon * scale;
    const dx = bx - ax, dy = bLat - aLat, square = dx * dx + dy * dy;
    const t = square > 0 ? Math.max(0, Math.min(1, ((px - ax) * dx + (lat - aLat) * dy) / square)) : 0;
    const along = Math.max(fromMeters, cumulative[i - 1]! + length * t);
    const offset = meters(lat, lon, aLat + (bLat - aLat) * t, aLon + (bLon - aLon) * t);
    // Le point recalé est sur la ligne : la première rencontre nette est la bonne, y compris quand la route repasse au même endroit.
    if (offset < 2) return { along, offset };
    if (offset < best.offset) best = { along, offset };
  }
  return best;
}
function slice(line: [number, number][], cumulative: number[], from: number, to: number): [number, number][] {
  const at = (distance: number): [number, number] => {
    let i = 1;
    while (i < line.length - 1 && cumulative[i]! < distance) i++;
    const length = cumulative[i]! - cumulative[i - 1]!, t = length > 0 ? Math.max(0, Math.min(1, (distance - cumulative[i - 1]!) / length)) : 0;
    return [line[i - 1]![0] + (line[i]![0] - line[i - 1]![0]) * t, line[i - 1]![1] + (line[i]![1] - line[i - 1]![1]) * t];
  };
  const out: [number, number][] = [at(from)];
  for (let i = 1; i < line.length - 1; i++) if (cumulative[i]! > from && cumulative[i]! < to) out.push(line[i]!);
  out.push(at(to));
  return out;
}

/**
 * Tronçons retenus d'un lot. Un point que le moteur n'a pas placé, placé trop loin de sa mesure ou placé
 * sans confiance n'est jamais forcé sur une route : le tronçon s'arrête avant lui et la mesure reste tracée.
 */
export function spansFromBatch(segmentId: string, points: MatcherPoint[], result: MatcherResult, keep: { from: number; to: number }, minimumConfidence: number): MatchedSpan[] {
  if (result.tracepoints.length !== points.length) return [];
  const spans: MatchedSpan[] = [];
  result.matchings.forEach((matching, matchingIndex) => {
    if (!(matching.confidence >= minimumConfidence) || matching.geometry.length < 2) return;
    const cumulative = cumulativeLengths(matching.geometry), total = cumulative.at(-1)!;
    if (!(total > 0)) return;
    let cursor = 0, group: { sequence: number; along: number }[] = [];
    const flush = () => {
      if (group.length >= 2) {
        const from = group[0]!.along, to = group.at(-1)!.along;
        if (to - from >= 5) spans.push({ segmentId, firstSequence: group[0]!.sequence, lastSequence: group.at(-1)!.sequence, confidence: Math.round(matching.confidence * 1000) / 1000,
          geometry: encodePolyline(slice(matching.geometry, cumulative, from, to)), anchors: group.map(a => [a.sequence, Math.round((a.along - from) * 10) / 10] as [number, number]) });
      }
      group = [];
    };
    for (let i = 0; i < points.length; i++) {
      const trace = result.tracepoints[i], point = points[i]!;
      if (!trace || trace.matchingIndex !== matchingIndex) { flush(); continue; }
      const placed = project(matching.geometry, cumulative, trace.latitude, trace.longitude, cursor);
      const drift = meters(point.latitude, point.longitude, trace.latitude, trace.longitude);
      if (placed.offset > 15 || drift > point.radiusMeters + 10) { flush(); continue; }
      cursor = placed.along;
      if (i < keep.from || i > keep.to) { if (i > keep.to) flush(); continue; }
      group.push({ sequence: point.sequence, along: placed.along });
    }
    flush();
  });
  return spans.sort((a, b) => a.firstSequence - b.firstSequence);
}

/** Tronçons d'un même segment, dans l'ordre, sans chevauchement : le plus confiant l'emporte sur une plage disputée. */
export function mergeSpans(spans: MatchedSpan[]): MatchedSpan[] {
  const ordered = [...spans].sort((a, b) => a.segmentId === b.segmentId ? a.firstSequence - b.firstSequence : a.segmentId < b.segmentId ? -1 : 1), out: MatchedSpan[] = [];
  for (const span of ordered) {
    const last = out.at(-1);
    if (last && last.segmentId === span.segmentId && span.firstSequence < last.lastSequence) { if (span.confidence > last.confidence) out[out.length - 1] = span; continue; }
    out.push(span);
  }
  return out;
}

/**
 * Recale tout un trajet : chaque suite continue de mesures retenues, lot par lot, l'un après l'autre.
 * Au-delà de `MAXIMUM_BATCHES` lots, la suite du trajet reste tracée par ses mesures.
 */
export async function matchTrack(segments: { segmentId: string; points: TrackPoint[] }[], matcher: (points: MatcherPoint[]) => Promise<MatcherResult>, minimumConfidence: number): Promise<MatchedSpan[]> {
  const spans: MatchedSpan[] = [];
  let used = 0;
  for (const segment of segments) {
    for (const run of continuousRuns(selectTrack(segment.points))) {
      const points = matcherPoints(run);
      for (const batch of batches(points.length)) {
        if (++used > MAXIMUM_BATCHES) return mergeSpans(spans);
        const part = points.slice(batch.start, batch.end);
        spans.push(...spansFromBatch(segment.segmentId, part, await matcher(part), { from: batch.from - batch.start, to: batch.to - batch.start }, minimumConfidence));
      }
    }
  }
  return mergeSpans(spans);
}
