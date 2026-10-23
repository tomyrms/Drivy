import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { rollbackQuietly, withActor } from './database.js';
import { notFound } from './errors.js';
import { uuid, type CaptureRow, type ChunkRow, type TrackPoint } from './capture-contracts.js';
import { canonicalCaptureJSON, chunkAAD, decryptPoints, type CaptureConfig } from './capture-crypto.js';
import { MapMatchingError, type MapMatcher, type MapMatchingConfig } from './map-matching-client.js';
import { matchTrack, TRACK_MATCHING_ALGORITHM_VERSION, type MatchedSpan } from './track-matching.js';

/**
 * Extension hors contrat canonique : `GET …/captures/:captureId/matched-route`.
 *
 * Le replay (`…/replay`) n'est pas modifié et ne dépend jamais de cette route : elle ajoute une couche, calculée
 * une fois par trajet, à la première lecture par un compte qui a le droit de lire ce trajet. La réponse ne
 * bloque pas sur le calcul. Les trois statuts historiques restent compatibles ; `reason` distingue les
 * attentes, l'absence de correspondance et les erreurs, `retryAfterSeconds` espace les lectures suivantes.
 * Aucune position, URL ou réponse du moteur n'est journalisée : seul un code d'échec est conservé.
 */
const LEASE_SECONDS = 180;
interface RouteRow { reconstruction_version: number; algorithm_version: number; status: 'PROCESSING' | 'READY' | 'EMPTY' | 'FAILED'; attempts: number; lease_until: Date | null; retry_after: Date | null; failure_code: string | null; provider: string | null; encrypted_route: Buffer | null; key_id: string | null }
const failureReasons = ['PROVIDER_UNAVAILABLE', 'RATE_LIMITED', 'PROVIDER_REFUSED', 'INVALID_RESPONSE', 'MATCHING_FAILED', 'ROUTE_TOO_LARGE'] as const;
type FailureReason = typeof failureReasons[number];
type RouteReason = FailureReason | 'WAITING_FOR_SYNC' | 'PROCESSING' | 'MATCHED' | 'NO_RELIABLE_MATCH' | 'MATCHING_DISABLED' | 'CACHE_UNREADABLE';
// Ne jamais exposer une valeur arbitraire de la base comme diagnostic public.
const publicFailure = (code: string | null): FailureReason => failureReasons.find(reason => reason === code) ?? 'MATCHING_FAILED';
const retryDelay = (at: Date | null): number => Math.max(1, Math.min(604800, Math.ceil(((at?.getTime() ?? Date.now()) - Date.now()) / 1000)));
const availability = (reason: RouteReason, retryAfterSeconds: number | null = null) => ({ reason, retryAfterSeconds });
const stored = z.object({ spans: z.array(z.object({ segmentId: uuid, firstSequence: z.number().int().min(0), lastSequence: z.number().int().min(0), confidence: z.number().min(0).max(1), geometry: z.string().min(1).max(400_000), anchors: z.array(z.tuple([z.number().int().min(0), z.number().min(0)])).min(2).max(20_000) }).strict()).max(2000) }).strict();

const routeAAD = (row: CaptureRow, algorithm: number) => Buffer.from(canonicalCaptureJSON({ schoolId: row.school_id, captureId: row.id, kind: 'matched-route', reconstructionVersion: row.reconstruction_version, algorithmVersion: algorithm }));
export function encryptRoute(config: CaptureConfig, spans: MatchedSpan[], aad: Buffer): Buffer {
  const nonce = randomBytes(12), cipher = createCipheriv('aes-256-gcm', config.encryptionKey, nonce);
  cipher.setAAD(aad);
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify({ spans }), 'utf8'), cipher.final()]);
  return Buffer.concat([nonce, cipher.getAuthTag(), ciphertext]);
}
function decryptRoute(config: CaptureConfig, encrypted: Buffer, keyId: string, aad: Buffer): MatchedSpan[] | undefined {
  if (keyId !== config.encryptionKeyId) return undefined;
  try {
    const decipher = createDecipheriv('aes-256-gcm', config.encryptionKey, encrypted.subarray(0, 12));
    decipher.setAuthTag(encrypted.subarray(12, 28)); decipher.setAAD(aad);
    return stored.parse(JSON.parse(Buffer.concat([decipher.update(encrypted.subarray(28)), decipher.final()]).toString('utf8'))).spans;
  } catch { return undefined; }
}

/** Nouvel essai de plus en plus espacé ; après cinq échecs, une journée entière. */
const retrySeconds = (attempts: number, failure: string) => failure === 'RATE_LIMITED' ? 120 : attempts >= 5 ? 86_400 : Math.min(3600, 60 * attempts * attempts);

export function registerMatchedRoutes(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier; capture?: CaptureConfig; mapMatching?: Pick<MapMatchingConfig, 'provider' | 'minimumConfidence'>; mapMatcher?: MapMatcher }) {
  const param = (r: FastifyRequest, key: string) => uuid.parse(z.record(z.string(), z.string()).parse(r.params)[key]);
  const running = new Set<Promise<void>>();
  // L'arrêt du service attend les calculs en cours : aucun bail ne reste pris sans raison.
  app.addHook('onClose', async () => { await Promise.allSettled([...running]); });

  async function system<T>(work: (query: Pool['query']) => Promise<T>): Promise<T> {
    const db = await options.pool.connect();
    let broken = false;
    try {
      await db.query('BEGIN'); await db.query('SET LOCAL ROLE drivy_app');
      const value = await work(db.query.bind(db) as Pool['query']);
      await db.query('COMMIT');
      return value;
    } catch (error) { broken = !(await rollbackQuietly(db)); throw error; } finally { db.release(broken); }
  }

  async function compute(row: CaptureRow, lease: string, attempts: number, segments: { segmentId: string; points: TrackPoint[] }[]) {
    const config = options.capture!, matching = options.mapMatching!, matcher = options.mapMatcher!;
    const finish = (outcome: 'READY' | 'EMPTY' | 'FAILED', route: Buffer | null, spans: number, failure: string | null) =>
      system(query => query('SELECT drivy.complete_matched_route($1,$2,$3,$4,$5,$6,$7,$8,$9)', [row.id, lease, outcome, route, route ? config.encryptionKeyId : null, spans, matching.provider, failure, failure ? retrySeconds(attempts, failure) : null]));
    try {
      const spans = await matchTrack(segments, matcher, matching.minimumConfidence);
      if (!spans.length) { await finish('EMPTY', null, 0, null); return; }
      const encrypted = encryptRoute(config, spans, routeAAD(row, TRACK_MATCHING_ALGORITHM_VERSION));
      if (encrypted.length > 4_194_304) { await finish('FAILED', null, 0, 'ROUTE_TOO_LARGE'); return; }
      await finish('READY', encrypted, spans.length, null);
    } catch (error) {
      // Seul un code est conservé : ni message, ni URL, ni coordonnée.
      const failure = error instanceof MapMatchingError ? error.failure : 'MATCHING_FAILED';
      try { await finish('FAILED', null, 0, failure); } catch { /* le bail expirera ; la prochaine lecture reprendra le calcul */ }
    }
  }

  app.get('/v1/schools/:schoolId/captures/:captureId/matched-route', async r => {
    z.object({}).strict().parse(r.query);
    const schoolId = param(r, 'schoolId'), captureId = param(r, 'captureId');
    // Mapbox reste un client de comparaison synthétique, jamais un moteur de trajet réel.
    const enabled = !!(options.capture && options.mapMatching?.provider === 'osrm' && options.mapMatcher);
    const read = await withActor(options.pool, await options.verifyToken(r.headers.authorization), schoolId, async db => {
      const row = (await db.query<CaptureRow>('SELECT * FROM drivy.capture_session WHERE school_id=$1 AND id=$2', [schoolId, captureId])).rows[0];
      // Mêmes droits que le replay privé : sans accès au trajet, ni la couche ni son état n'existent.
      if (!row || row.publication_state !== 'PRIVATE') throw notFound();
      const route = (await db.query<RouteRow>('SELECT * FROM drivy.capture_matched_route WHERE capture_id=$1', [row.id])).rows[0];
      // Le fournisseur fait partie de l'identité du calcul, y compris EMPTY, FAILED et PROCESSING.
      // Sans moteur actif, aucun ancien cache n'est servi. Un ancien bail sans provider n'est pas repris.
      const current = enabled && route && route.provider === options.mapMatching?.provider
        && route.reconstruction_version === row.reconstruction_version
        && route.algorithm_version === TRACK_MATCHING_ALGORITHM_VERSION ? route : undefined;
      if (current?.status === 'READY' && options.capture && current.encrypted_route && current.key_id) {
        const spans = decryptRoute(options.capture, current.encrypted_route, current.key_id, routeAAD(row, TRACK_MATCHING_ALGORITHM_VERSION));
        if (spans) return { row, status: 'READY' as const, provider: current.provider, spans, ...availability(spans.length ? 'MATCHED' : 'NO_RELIABLE_MATCH') };
      }
      if (current?.status === 'READY') return { row, status: 'UNAVAILABLE' as const, provider: null, spans: [] as MatchedSpan[], ...availability('CACHE_UNREADABLE') };
      if (current?.status === 'EMPTY') return { row, status: 'READY' as const, provider: current.provider, spans: [] as MatchedSpan[], ...availability('NO_RELIABLE_MATCH') };
      if (current?.status === 'PROCESSING' && current.lease_until && current.lease_until.getTime() > Date.now()) return { row, status: 'PENDING' as const, provider: null, spans: [] as MatchedSpan[], ...availability('PROCESSING', 3) };
      const due = !current || current.status === 'PROCESSING' || (current.status === 'FAILED' && (!current.retry_after || current.retry_after.getTime() <= Date.now()));
      if (!enabled) return { row, status: 'UNAVAILABLE' as const, provider: null, spans: [] as MatchedSpan[], ...availability('MATCHING_DISABLED') };
      if (!row.finalized_at || !['SYNCED', 'PARTIAL'].includes(row.sync_state)) return { row, status: 'UNAVAILABLE' as const, provider: null, spans: [] as MatchedSpan[], ...availability('WAITING_FOR_SYNC', 5) };
      if (!due) return { row, status: 'UNAVAILABLE' as const, provider: null, spans: [] as MatchedSpan[], ...availability(publicFailure(current?.failure_code ?? null), retryDelay(current?.retry_after ?? null)) };
      // Les mesures sont relues ici, avec les droits du compte ; le calcul se fait ensuite hors transaction.
      const chunks = (await db.query<ChunkRow>('SELECT * FROM drivy.capture_chunk WHERE school_id=$1 AND capture_id=$2 AND encrypted_points IS NOT NULL ORDER BY segment_index,first_sequence', [row.school_id, row.id])).rows;
      const segments: { segmentId: string; points: TrackPoint[] }[] = [];
      for (const chunk of chunks) {
        const points = decryptPoints(options.capture!, chunk.encrypted_points!, chunk.key_id, chunkAAD(chunk.school_id, chunk.capture_id, chunk.segment_id, chunk.chunk_index, chunk.content_hash));
        const last = segments.at(-1);
        if (last?.segmentId === chunk.segment_id) last.points.push(...points); else segments.push({ segmentId: chunk.segment_id, points: [...points] });
      }
      return { row, status: 'START' as const, provider: null, spans: [] as MatchedSpan[], segments, attempts: (current?.attempts ?? 0) + 1, ...availability('PROCESSING', 3) };
    });
    let status: 'READY' | 'PENDING' | 'UNAVAILABLE' = read.status === 'START' ? 'UNAVAILABLE' : read.status;
    if (read.status === 'START') {
      const lease = await system(async query => (await query<{ lease: string | null }>('SELECT drivy.claim_matched_route($1,$2,$3,$4,$5) AS lease', [read.row.id, read.row.reconstruction_version, TRACK_MATCHING_ALGORITHM_VERSION, LEASE_SECONDS, options.mapMatching!.provider])).rows[0]?.lease ?? null);
      // Sans bail, un autre appel calcule déjà ou vient de finir : le client relira.
      status = 'PENDING';
      if (lease) {
        const job: Promise<void> = compute(read.row, lease, read.attempts, read.segments).finally(() => { running.delete(job); });
        running.add(job);
      }
    }
    return { data: { captureId, status, reason: read.reason, retryAfterSeconds: read.retryAfterSeconds, provider: status === 'READY' ? read.provider : null, algorithmVersion: TRACK_MATCHING_ALGORITHM_VERSION, reconstructionVersion: read.row.reconstruction_version, spans: status === 'READY' ? read.spans : [], generatedAt: new Date().toISOString() }, requestId: r.id, serverTime: new Date().toISOString() };
  });
}
