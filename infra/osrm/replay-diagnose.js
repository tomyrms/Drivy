// Read-only replay diagnostic (#89). Decryption and coordinates stay in CT114 memory; only numeric aggregates leave.
'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');
const OSRM = 'http://192.168.1.158:5000';

function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') return `{${Object.entries(value).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([k, v]) => `${JSON.stringify(k)}:${canonical(v)}`).join(',')}}`;
  return JSON.stringify(value);
}
function decrypt(capture, key) {
  const segments = new Map();
  for (const k of capture.chunks ?? []) {
    const b = Buffer.from(k.enc, 'hex'), d = crypto.createDecipheriv('aes-256-gcm', key, b.subarray(0, 12));
    d.setAuthTag(b.subarray(12, 28));
    d.setAAD(Buffer.from(canonical({ schoolId: capture.school_id, captureId: capture.id, segmentId: k.segment_id, chunkIndex: k.chunk_index, hash: k.content_hash })));
    const points = JSON.parse(Buffer.concat([d.update(b.subarray(28)), d.final()]).toString('utf8'));
    if (!segments.has(k.segment_id)) segments.set(k.segment_id, { index: k.segment_index, points: [] });
    segments.get(k.segment_id).points.push(...points);
  }
  return [...segments.entries()].sort((a, b) => a[1].index - b[1].index).map(([segmentId, s]) => ({ segmentId, points: s.points.sort((a, b) => a.sequence - b.sequence) }));
}
const q = values => {
  const s = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (!s.length) return { count: 0, p50: null, p90: null, max: null };
  const at = p => s[Math.floor(p * (s.length - 1))];
  return { count: s.length, p50: +at(.5).toFixed(2), p90: +at(.9).toFixed(2), max: +s.at(-1).toFixed(2) };
};
function matcherFor(api) {
  // Même transport que createMapMatcher (provider osrm), destination fixée, sans redirection.
  return async points => {
    const coordinates = points.map(p => `${p.longitude.toFixed(6)},${p.latitude.toFixed(6)}`).join(';');
    const seconds = points.map(p => Math.floor(p.timestampMs / 1000));
    const parameters = new URLSearchParams({ geometries: 'polyline6', overview: 'full', radiuses: points.map(p => p.radiusMeters).join(';') });
    if (seconds.every((v, i) => i === 0 || v > seconds[i - 1])) parameters.set('timestamps', seconds.join(';'));
    parameters.set('tidy', 'false'); parameters.set('gaps', 'ignore');
    const reply = await fetch(`${OSRM}/match/v1/driving/${coordinates}?${parameters}`, { method: 'GET', redirect: 'error', signal: AbortSignal.timeout(10000) });
    const body = await reply.json();
    matcherFor.stats.push({ code: body.code, n: points.length, conf: (body.matchings ?? []).map(m => m.confidence), placed: (body.tracepoints ?? []).filter(Boolean).length });
    if (['NoMatch', 'NoSegment', 'NoTrips'].includes(body.code)) return { matchings: [], tracepoints: points.map(() => null) };
    return { matchings: body.matchings.map(m => ({ confidence: m.confidence, geometry: api.decodePolyline(m.geometry) })),
      tracepoints: body.tracepoints.map(t => t ? { matchingIndex: t.matchings_index, latitude: t.location[1], longitude: t.location[0] } : null) };
  };
}
matcherFor.stats = [];

async function run(input) {
  const env = Object.fromEntries(fs.readFileSync('/etc/drivy-refonte/api.env', 'utf8').split('\n').filter(l => l.includes('=') && !l.startsWith('#')).map(l => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]));
  const key = Buffer.from(env.CAPTURE_ENCRYPTION_KEY_HEX, 'hex');
  const minimum = Number(env.MAP_MATCHING_MIN_CONFIDENCE ?? 0.5);
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', input.apiBundle)(require, mod, mod.exports);
  const api = mod.exports;
  const report = { minimumConfidence: minimum, captures: [] };
  for (const capture of input.data.captures) {
    const segments = decrypt(capture, key);
    const all = segments.flatMap(s => s.points);
    const selected = segments.map(s => api.selectTrack(s.points));
    const runs = selected.map(s => api.continuousRuns(s));
    const matcherPoints = runs.flat().map(r => api.matcherPoints(r));
    matcherFor.stats = [];
    const spans = await api.matchTrack(segments, matcherFor(api), minimum);
    const covered = new Set(); for (const sp of spans) for (const p of all) if (p.sequence >= sp.firstSequence && p.sequence <= sp.lastSequence) covered.add(sp.segmentId + ':' + p.sequence);
    const segmentIds = new Map(segments.map(s => [s.segmentId, s]));
    let coveredCount = 0; for (const sp of spans) coveredCount += segmentIds.get(sp.segmentId).points.filter(p => p.sequence >= sp.firstSequence && p.sequence <= sp.lastSequence).length;
    // Mouvement brut : vitesse paire à paire et précision annoncée.
    const pair = [], acc = all.map(p => p.accuracyMeters), speeds = all.map(p => p.speedMetersPerSecond ?? p.speed).filter(v => Number.isFinite(v) && v >= 0);
    for (const s of segments) for (let i = 1; i < s.points.length; i++) { const a = s.points[i-1], b = s.points[i], dt = (b.elapsedMs - a.elapsedMs) / 1000; if (dt > 0) pair.push(api.meters(a.latitude, a.longitude, b.latitude, b.longitude) / dt); }
    const intervals = []; for (const s of segments) for (let i = 1; i < s.points.length; i++) intervals.push((s.points[i].elapsedMs - s.points[i-1].elapsedMs) / 1000);
    const path = segments.reduce((sum, s) => { let d = 0; for (let i = 1; i < s.points.length; i++) d += api.meters(s.points[i-1].latitude, s.points[i-1].longitude, s.points[i].latitude, s.points[i].longitude); return sum + d; }, 0);
    report.captures.push({
      points: all.length, segments: segments.length, pathMetersRaw: Math.round(path),
      accuracyM: q(acc), intervalS: q(intervals), pairSpeedMs: q(pair), storedSpeedSamples: speeds.length, storedSpeedMs: q(speeds),
      accuracyOver30: acc.filter(a => a > 30).length,
      selectedPoints: selected.reduce((n, s) => n + s.length, 0), runs: runs.flat().length,
      runLengths: q(runs.flat().map(r => r.length)), matcherPoints: matcherPoints.reduce((n, p) => n + p.length, 0),
      matcherPointsPerRun: q(matcherPoints.map(p => p.length)), runsBelow2MatcherPoints: matcherPoints.filter(p => p.length < 2).length,
      batches: matcherFor.stats.length, codes: matcherFor.stats.reduce((o, s) => (o[s.code] = (o[s.code] ?? 0) + 1, o), {}),
      batchConfidence: q(matcherFor.stats.flatMap(s => s.conf)), placedShare: q(matcherFor.stats.map(s => s.placed / s.n)),
      spans: spans.length, spanConfidence: q(spans.map(s => s.confidence)), coveredPoints: coveredCount, coverageShare: all.length ? +(coveredCount / all.length).toFixed(3) : null,
    });
  }
  return report;
}
module.exports = { run };
