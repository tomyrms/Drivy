// Aucune donnée de personne, aucun jeton et aucun appel tiers.
// Route génératrice OSRM : ce test vérifie la cohérence, pas la supériorité d'un moteur.
// node --import tsx infra/osrm/compare.mts http://127.0.0.1:15000
import { createHash } from 'node:crypto';
import { isIP } from 'node:net';
import { pathToFileURL } from 'node:url';
import { createMapMatcher, readMapMatchingConfig } from '../../apps/api/src/map-matching-client.ts';
import { decodePolyline, matchTrack, TRACK_MATCHING_ALGORITHM_VERSION, type MatcherPoint } from '../../apps/api/src/track-matching.ts';
import { coveredPointCount, distanceToPolyline, makeSyntheticTrace } from './synthetic.mts';

const via = [[6.9361, 46.9967], [6.9174, 46.9893], [6.8890, 46.9862], [6.8722, 46.9767]];
const rounded = (n: number) => Math.round(n * 1000) / 1000;
function quantile(values: number[], fraction: number) {
  const ordered = [...values].sort((a, b) => a - b);
  return ordered.length ? rounded(ordered[Math.min(ordered.length - 1, Math.floor(fraction * (ordered.length - 1)))]!) : null;
}

export async function benchmark(baseURL: string) {
  const config = readMapMatchingConfig({ MAP_MATCHING_PROVIDER: 'osrm', MAP_MATCHING_BASE_URL: baseURL })!;
  const host = new URL(config.baseURL).hostname;
  const parts = host.split('.').map(Number);
  const privateIPv4 = isIP(host) === 4 && (parts[0] === 127 || parts[0] === 10 ||
    (parts[0] === 192 && parts[1] === 168) || (parts[0] === 172 && parts[1]! >= 16 && parts[1]! <= 31));
  if (!privateIPv4 && !['localhost', '[::1]'].includes(host)) throw new Error('PRIVATE_ENGINE_REQUIRED');
  // Les URLs avec identifiants, requête ou fragment sont déjà refusées par le client applicatif.
  const reply = await fetch(`${config.baseURL}/route/v1/driving/${via.map(p => p.join(',')).join(';')}?overview=full&geometries=polyline6`,
    { signal: AbortSignal.timeout(10_000), redirect: 'error' });
  if (!reply.ok) throw new Error('ROUTE_HTTP_ERROR');
  const route = await reply.json() as { code?: string; routes?: { geometry?: string }[] };
  const encoded = route.routes?.[0]?.geometry;
  if (route.code !== 'Ok' || typeof encoded !== 'string' || encoded.length > 400_000) throw new Error('INVALID_ROUTE_RESPONSE');
  const line = decodePolyline(encoded);
  const { points, distances, totalMeters } = makeSyntheticTrace(line);
  const segments = [{ segmentId: '00000000-0000-4000-8000-000000000001', points }];
  const matcher = createMapMatcher(config), durations: number[] = [];
  const timed = async (part: MatcherPoint[]) => {
    const started = performance.now();
    try { return await matcher(part); } finally { durations.push(performance.now() - started); }
  };
  const started = performance.now();
  const spans = await matchTrack(segments, timed, config.minimumConfidence);
  const totalMs = rounded(performance.now() - started);
  const coveredPoints = coveredPointCount(segments, spans);
  // Écart orienté : sommets recalés vers l'intégralité de la polyligne génératrice.
  // Ce n'est ni une distance de Hausdorff, ni une vérité terrain, ni une métrique pondérée par longueur.
  const offsets = spans.flatMap(span => decodePolyline(span.geometry)).map(point => distanceToPolyline(point, line));
  return {
    schemaVersion: 1, synthetic: true, engine: 'osrm', referenceEngine: 'osrm', independentGroundTruth: false,
    matchingAlgorithmVersion: TRACK_MATCHING_ALGORITHM_VERSION,
    referencePolylineSha256: createHash('sha256').update(encoded).digest('hex'),
    seed: 7, noiseSigmaMeters: 4, nominalSpeedMetersPerSecond: 11, samplePeriodMs: 1000,
    stoppedSeconds: distances.filter((d, i) => i > 0 && d === distances[i - 1]).length,
    referenceLengthMeters: rounded(totalMeters), points: points.length, spans: spans.length,
    coveredPoints, coveredShare: rounded(coveredPoints / points.length),
    coverageDefinition: 'unique-existing-segment-sequence-in-span-ranges',
    confidence: spans.map(span => span.confidence), calls: durations.length, totalMs,
    callMsMedian: quantile(durations, 0.5), callMsP95: quantile(durations, 0.95),
    offsetDefinition: 'matched-vertices-to-reference-polyline-local-projection-meters',
    offsetMedianMeters: quantile(offsets, 0.5), offsetP95Meters: quantile(offsets, 0.95), offsetMaxMeters: quantile(offsets, 1)
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv.length !== 3) throw new Error('USAGE');
    console.log(JSON.stringify(await benchmark(process.argv[2]!), null, 2));
  } catch {
    // Ne jamais imprimer erreur brute, URL, corps HTTP ou environnement.
    console.error('Benchmark synthétique échoué. Vérifier le moteur privé et les paramètres.');
    process.exitCode = 1;
  }
}
