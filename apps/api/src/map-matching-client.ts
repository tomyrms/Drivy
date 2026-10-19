import { z } from 'zod';
import { decodePolyline, type MatcherPoint, type MatcherResult } from './track-matching.js';

/**
 * Moteur de recalage routier. Deux fournisseurs parlent le même format : Mapbox Map Matching (jeton) et un
 * OSRM auto-hébergé (aucun jeton, aucune position ne quitte l'hébergement). Changer de moteur ne touche que ce fichier.
 * Ni l'URL (elle porte le jeton), ni une coordonnée, ni le corps d'une réponse ne sont jamais journalisés.
 */
export interface MapMatchingConfig { provider: 'mapbox' | 'osrm'; baseURL: string; accessToken?: string; minimumConfidence: number; timeoutMs: number }
export type MapMatchingFailure = 'RATE_LIMITED' | 'PROVIDER_REFUSED' | 'PROVIDER_UNAVAILABLE' | 'INVALID_RESPONSE';
export class MapMatchingError extends Error { constructor(readonly failure: MapMatchingFailure) { super(failure); this.name = 'MapMatchingError'; } }
export type MapMatcher = (points: MatcherPoint[]) => Promise<MatcherResult>;

/** Configuration absente : aucun recalage, le trajet mesuré reste le seul tracé. Partielle ou invalide : refus de démarrer. */
export function readMapMatchingConfig(env: NodeJS.ProcessEnv = process.env): MapMatchingConfig | undefined {
  const names = ['MAP_MATCHING_PROVIDER', 'MAP_MATCHING_BASE_URL', 'MAP_MATCHING_ACCESS_TOKEN'];
  if (names.every(name => !env[name])) return undefined;
  try {
    const provider = z.enum(['mapbox', 'osrm']).parse(env.MAP_MATCHING_PROVIDER);
    const baseURL = z.url().parse(env.MAP_MATCHING_BASE_URL ?? (provider === 'mapbox' ? 'https://api.mapbox.com' : undefined)), url = new URL(baseURL);
    if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error();
    // Un moteur distant reçoit des positions : jamais en clair hors de l'hébergement.
    if (url.protocol === 'http:' && !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname) && !/^(10|192\.168|172\.(1[6-9]|2\d|3[01]))\./.test(url.hostname)) throw new Error();
    const accessToken = provider === 'mapbox' ? z.string().regex(/^[A-Za-z0-9._-]{20,400}$/).parse(env.MAP_MATCHING_ACCESS_TOKEN) : undefined;
    return { provider, baseURL: baseURL.replace(/\/+$/, ''), ...(accessToken ? { accessToken } : {}),
      minimumConfidence: z.coerce.number().min(0).max(1).default(0.5).parse(env.MAP_MATCHING_MIN_CONFIDENCE),
      timeoutMs: z.coerce.number().int().min(1000).max(30_000).default(10_000).parse(env.MAP_MATCHING_TIMEOUT_MS) };
  } catch { throw new Error('Configuration du recalage routier invalide ; aucun secret n’est affiché.'); }
}

const response = z.object({
  code: z.string().max(60),
  matchings: z.array(z.object({ confidence: z.number().min(0).max(1), geometry: z.string().max(400_000) })).max(200).optional(),
  tracepoints: z.array(z.object({ matchings_index: z.number().int().min(0), location: z.tuple([z.number().min(-180).max(180), z.number().min(-90).max(90)]) }).nullable()).max(200).optional()
});

export function createMapMatcher(config: MapMatchingConfig, fetcher: typeof fetch = fetch): MapMatcher {
  return async points => {
    const coordinates = points.map(p => `${p.longitude.toFixed(6)},${p.latitude.toFixed(6)}`).join(';');
    const seconds = points.map(p => Math.floor(p.timestampMs / 1000));
    const parameters = new URLSearchParams({ geometries: 'polyline6', overview: 'full', radiuses: points.map(p => p.radiusMeters).join(';') });
    // Des horodatages qui n'avancent pas font refuser tout le lot : ils sont alors omis, le moteur s'en passe.
    if (seconds.every((value, index) => index === 0 || value > seconds[index - 1]!)) parameters.set('timestamps', seconds.join(';'));
    let url: string, init: RequestInit;
    if (config.provider === 'mapbox') {
      parameters.set('tidy', 'false');
      url = `${config.baseURL}/matching/v5/mapbox/driving?access_token=${encodeURIComponent(config.accessToken ?? '')}`;
      init = { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: `coordinates=${encodeURIComponent(coordinates)}&${parameters.toString()}` };
    } else {
      parameters.set('tidy', 'false'); parameters.set('gaps', 'ignore');
      url = `${config.baseURL}/match/v1/driving/${coordinates}?${parameters.toString()}`;
      init = { method: 'GET' };
    }
    let reply: Response;
    try { reply = await fetcher(url, { ...init, signal: AbortSignal.timeout(config.timeoutMs), redirect: 'error' }); }
    catch { throw new MapMatchingError('PROVIDER_UNAVAILABLE'); }
    if (reply.status === 429) throw new MapMatchingError('RATE_LIMITED');
    if (reply.status >= 500) throw new MapMatchingError('PROVIDER_UNAVAILABLE');
    let body: z.infer<typeof response>;
    try { body = response.parse(await reply.json()); } catch { throw new MapMatchingError(reply.ok ? 'INVALID_RESPONSE' : 'PROVIDER_REFUSED'); }
    // « Aucune route » est un résultat : ces mesures restent tracées telles quelles.
    if (['NoMatch', 'NoSegment', 'NoTrips'].includes(body.code)) return { matchings: [], tracepoints: points.map(() => null) };
    if (!reply.ok || body.code !== 'Ok') throw new MapMatchingError('PROVIDER_REFUSED');
    const tracepoints = body.tracepoints ?? [];
    if (tracepoints.length !== points.length) throw new MapMatchingError('INVALID_RESPONSE');
    const matchings = (body.matchings ?? []).map(matching => ({ confidence: matching.confidence, geometry: decodePolyline(matching.geometry) }));
    // Une géométrie illisible n'est pas une absence de route : elle ne doit jamais devenir un résultat « aucune route ».
    if (matchings.some(matching => matching.geometry.length < 2)) throw new MapMatchingError('INVALID_RESPONSE');
    return {
      matchings,
      tracepoints: tracepoints.map(trace => trace ? { matchingIndex: trace.matchings_index, latitude: trace.location[1], longitude: trace.location[0] } : null)
    };
  };
}
