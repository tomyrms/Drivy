'use strict';
// Read-only replay. Decryption and real coordinates are confined to CT114 memory.
// The exported helpers accept synthetic inputs for local tests. Never log their inputs.
const crypto = require('node:crypto');
const fs = require('node:fs');
const R = 6371008.8, RAD = Math.PI / 180;
const OSRM = 'http://192.168.1.158:5000';
const round = x => Number.isFinite(x) ? +x.toFixed(4) : null;
function quantiles(values) {
  const a = values.filter(Number.isFinite).sort((a, b) => a - b);
  const at = p => a.length ? round(a[Math.floor(p * (a.length - 1))]) : null;
  return { count: a.length, mean: a.length ? round(a.reduce((s, n) => s + n, 0) / a.length) : null,
    p50: at(0.5), p90: at(0.9), p95: at(0.95), p99: at(0.99), max: at(1) };
}
function offset(a, b) {
  let dl = b.longitude - a.longitude;
  if (dl > 180) dl -= 360;
  if (dl < -180) dl += 360;
  return { east: dl * RAD * R * Math.cos(a.latitude * RAD), north: (b.latitude - a.latitude) * RAD * R };
}
function move(a, v) {
  let longitude = a.longitude + v.east / (R * RAD * Math.max(0.01, Math.cos(a.latitude * RAD)));
  if (longitude > 180) longitude -= 360;
  if (longitude < -180) longitude += 360;
  return { latitude: Math.max(-90, Math.min(90, a.latitude + v.north / (R * RAD))), longitude };
}
function distance(a, b) {
  const dl = (b.longitude - a.longitude) * RAD, dp = (b.latitude - a.latitude) * RAD;
  const h = Math.sin(dp / 2) ** 2 + Math.cos(a.latitude * RAD) * Math.cos(b.latitude * RAD) * Math.sin(dl / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}
function estimateMotion(points, i) {
  // Causal two-second chord. Unlike stored coordinates, true Core Location Doppler is unavailable.
  if (!i) return { speed: null, course: null };
  let j = i - 1;
  while (j > 0 && points[i].elapsedMs - points[j].elapsedMs < 2000) j--;
  const dt = (points[i].elapsedMs - points[j].elapsedMs) / 1000;
  if (!(dt > 0)) return { speed: null, course: null };
  const v = offset(points[j], points[i]);
  return { speed: Math.hypot(v.east, v.north) / dt, course: (Math.atan2(v.east, v.north) / RAD + 360) % 360 };
}
function splitRuns(points) {
  const runs = [];
  for (const p of points) {
    const run = runs.at(-1), last = run?.at(-1);
    if (!last || p.elapsedMs <= last.elapsedMs || p.elapsedMs - last.elapsedMs > 4000 || p.sequence !== last.sequence + 1) runs.push([p]);
    else run.push(p);
  }
  return runs;
}
function restrictedFetch(fetcher = fetch) {
  return async (value, init = {}) => {
    const u = new URL(value);
    if (u.origin !== OSRM || u.username || u.password || u.hash || !u.pathname.startsWith('/match/v1/driving/') || (init.method && init.method !== 'GET')) throw new Error('NETWORK_REJECTED');
    return fetcher(u.href, { ...init, method: 'GET', redirect: 'error' });
  };
}
const REPORT_KEYS = new Set(`schemaVersion captures points segments runs durationS eligibleFixes skippedAccuracy initialMotionUnknown cadenceMs windowPoints maximumWindowAgeMs deliveryMs additionalNetworkMs frameHz numericalModelOnly dopplerEstimated groundTruthAvailable comparesCurrentPredictor requestCandidates requests scheduled applied coveredFixes coverageShare after before errorM eventJumpM frameStepM frameSpeedMs confidence correctionDistanceM osrmMs responseAgeMs requestAgeMs responseCount lowSpeed lowConfidence distance delay ambiguous missing provider invalid continuity unchanged insufficient turn rejected accepted notRequested resets count mean p50 p90 p99 max beforeOSRM afterOSRM failed matches selectedFailures noMatch tooSlow weakConfidence tooFar stale busy cancelled expired coverageSeconds coverageTimeShare frameCount correctionAgeMs sourceHashes api ios replay matchLatencyMs statusCounts configurations scenarioIndex requestIntervalMs durationMs unknownMotion motionRejected qualifyingWindows requestSkipped noVelocity sampleComparisons pairedFrames uncaughtErrors`.split(/\s+/));
function numericReport(value, key) {
  if (key === 'sourceHashes') {
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('UNSAFE_OUTPUT');
    for (const [name, hash] of Object.entries(value)) if (!['api', 'ios', 'replay'].includes(name) || !/^[0-9a-f]{64}$/.test(hash)) throw new Error('UNSAFE_OUTPUT');
    return value;
  }
  if (value === null || typeof value === 'boolean') return value;
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (Array.isArray(value)) { value.forEach(x => numericReport(x)); return value; }
  if (value && typeof value === 'object') {
    for (const [k, v] of Object.entries(value)) {
      if (!REPORT_KEYS.has(k)) throw new Error('UNSAFE_OUTPUT');
      numericReport(v, k);
    }
    return value;
  }
  throw new Error('UNSAFE_OUTPUT');
}
function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') return `{${Object.entries(value).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([k, v]) => `${JSON.stringify(k)}:${canonical(v)}`).join(',')}}`;
  return JSON.stringify(value);
}
function decryptCaptures(input, key) {
  if (!Array.isArray(input.captures) || input.captures.length !== 2) throw new Error('CAPTURE_COUNT');
  return input.captures.map(c => {
    const segments = new Map();
    for (const k of c.chunks ?? []) {
      const b = Buffer.from(k.enc, 'hex');
      const d = crypto.createDecipheriv('aes-256-gcm', key, b.subarray(0, 12));
      d.setAuthTag(b.subarray(12, 28));
      d.setAAD(Buffer.from(canonical({ schoolId: c.school_id, captureId: c.id, segmentId: k.segment_id, chunkIndex: k.chunk_index, hash: k.content_hash })));
      const points = JSON.parse(Buffer.concat([d.update(b.subarray(28)), d.final()]).toString('utf8'));
      if (!segments.has(k.segment_index)) segments.set(k.segment_index, []);
      segments.get(k.segment_index).push(...points);
    }
    return [...segments.entries()].sort(([a], [b]) => a - b).map(([, points]) => {
      points.sort((a, b) => a.sequence - b.sequence);
      for (const p of points) if (!Number.isFinite(p.latitude) || !Number.isFinite(p.longitude) || !Number.isFinite(p.elapsedMs) || !Number.isFinite(p.accuracyMeters) || !Number.isInteger(p.sequence)) throw new Error('INVALID_MEASUREMENT');
      return points;
    });
  });
}
// Numerical port of SchoolMapPredictor. The UI currently uses delivery time, not measuredAt.
class Predictor {
  constructor() { this.fix = null; this.velocity = { east: 0, north: 0 }; this.road = { east: 0, north: 0 }; this.correction = { east: 0, north: 0, at: 0 }; }
  position(t) {
    if (!this.fix) return null;
    const ahead = Math.min(1.6, Math.max(0, t - this.fix.at));
    const fade = Math.exp(-Math.max(0, t - this.correction.at) / 0.45);
    return move(this.fix, { east: this.velocity.east * ahead + this.road.east + this.correction.east * fade,
      north: this.velocity.north * ahead + this.road.north + this.correction.north * fade });
  }
  preserve(drawn, now) {
    this.correction = { east: 0, north: 0, at: now };
    if (drawn) this.correction = { ...offset(this.position(now), drawn), at: now };
  }
  receive(p, motion, now) {
    const drawn = this.position(now);
    this.velocity = motion.speed >= 0.6 && Number.isFinite(motion.speed) && Number.isFinite(motion.course)
      ? { east: motion.speed * Math.sin(motion.course * RAD), north: motion.speed * Math.cos(motion.course * RAD) } : { east: 0, north: 0 };
    this.fix = { latitude: p.latitude, longitude: p.longitude, at: now };
    this.road = { east: 0, north: 0 };
    this.correction = { east: 0, north: 0, at: now };
    if (drawn) {
      const c = offset(this.position(now), drawn);
      if (Math.hypot(c.east, c.north) <= 80) this.correction = { ...c, at: now };
    }
  }
  correct(p, now) {
    if (!this.fix) return false;
    const road = offset(this.fix, p);
    if (!Number.isFinite(road.east) || !Number.isFinite(road.north) || Math.hypot(road.east, road.north) > 20) return false;
    const drawn = this.position(now);
    this.road = road;
    this.preserve(drawn, now);
    return true;
  }
  clear(now) {
    if (!this.road.east && !this.road.north) return;
    const drawn = this.position(now);
    this.road = { east: 0, north: 0 };
    this.preserve(drawn, now);
  }
}
function simulateRun(points, records, config) {
  const before = new Predictor(), after = new Predictor();
  const metrics = () => ({ errorM: [], eventJumpM: [], frameStepM: [], frameSpeedMs: [] });
  const out = { before: metrics(), after: metrics(), applied: 0, stale: 0, delay: 0, distance: 0, coverageSeconds: 0, pairedFrames: 0, responseAgeMs: [] };
  if (!points.length) return out;
  const events = [], delivery = config.deliveryMs / 1000;
  points.forEach((p, index) => {
    events.push({ t: p.elapsedMs / 1000, type: 'acquire', index, order: 0 });
    events.push({ t: p.elapsedMs / 1000 + delivery, type: 'fix', index, order: 1 });
  });
  for (const record of records) if (record.result.status === 'MATCHED') {
    const t = points[record.index].elapsedMs / 1000 + delivery + (record.durationMs + config.additionalNetworkMs) / 1000;
    events.push({ t, type: 'response', record, order: 2 });
    events.push({ t: t + 2, type: 'expiry', record, order: 3 });
  }
  events.sort((a, b) => a.t - b.t || a.order - b.order);
  let ei = 0, latest = -1, current = -1, active = null, referenceIndex = 0, previous = null;
  const end = points.at(-1).elapsedMs / 1000, start = points[0].elapsedMs / 1000;
  const processEvent = event => {
    const t = event.t, a = before.position(t), b = after.position(t);
    if (event.type === 'acquire') { latest = event.index; active = null; after.clear(t); }
    if (event.type === 'fix') {
      const p = points[event.index];
      if (p.accuracyMeters <= 30) {
        const motion = estimateMotion(points, event.index);
        before.receive(p, motion, t); after.receive(p, motion, t); current = event.index;
      }
    }
    if (event.type === 'response') {
      const { index, result, durationMs } = event.record;
      out.responseAgeMs.push(durationMs + config.additionalNetworkMs);
      if (durationMs + config.additionalNetworkMs > 2000) out.delay++;
      else if (index !== latest || index !== current) out.stale++;
      else if (result.distanceMeters > Math.min(20, Math.max(5, points[index].accuracyMeters)) || distance(points[index], result.position) > Math.min(20, Math.max(5, points[index].accuracyMeters))) out.distance++;
      else if (after.correct(result.position, t)) { active = event.record; out.applied++; }
      else out.distance++;
    }
    if (event.type === 'expiry' && active === event.record) { active = null; after.clear(t); }
    if (a) out.before.eventJumpM.push(distance(a, before.position(t)));
    if (b) out.after.eventJumpM.push(distance(b, after.position(t)));
  };
  for (let frame = 0; start + frame / 60 <= end; frame++) {
    const t = start + frame / 60;
    while (ei < events.length && events[ei].t <= t) processEvent(events[ei++]);
    const a = before.position(t), b = after.position(t);
    if (!a || !b) continue;
    while (referenceIndex + 1 < points.length && points[referenceIndex + 1].elapsedMs / 1000 <= t) referenceIndex++;
    const lo = points[referenceIndex], hi = points[referenceIndex + 1] ?? lo;
    const fraction = hi === lo ? 0 : (t * 1000 - lo.elapsedMs) / (hi.elapsedMs - lo.elapsedMs);
    const v = offset(lo, hi), reference = move(lo, { east: v.east * fraction, north: v.north * fraction });
    // This is distance to interpolated GPS MEASUREMENTS, never a ground-truth error.
    out.before.errorM.push(distance(a, reference)); out.after.errorM.push(distance(b, reference));
    if (previous) {
      const da = distance(previous.a, a), db = distance(previous.b, b);
      out.before.frameStepM.push(da); out.after.frameStepM.push(db);
      out.before.frameSpeedMs.push(da * 60); out.after.frameSpeedMs.push(db * 60);
    }
    previous = { a, b };
    out.pairedFrames++;
    if (active) out.coverageSeconds += 1 / 60;
  }
  // Count late replies too, without adding extrapolated frames after the last measurement.
  while (ei < events.length) processEvent(events[ei++]);
  return out;
}
const rejectionCounts = () => ({ lowSpeed: 0, lowConfidence: 0, distance: 0, delay: 0, ambiguous: 0, missing: 0, provider: 0, invalid: 0, continuity: 0, insufficient: 0, turn: 0 });
function refusalReason(points, raw, called, durationMs) {
  // Diagnostic mirror only. Acceptance ALWAYS comes from the imported, unchanged matchLive.
  const last = points.at(-1), prev = points.at(-2);
  if (!called) {
    if (last.speed < 2 || (prev && distance(prev, last) / ((last.elapsedMs - prev.elapsedMs) / 1000) < 2)) return 'lowSpeed';
    let length = 0;
    for (let i = 1; i < points.length; i++) {
      const dt = (points[i].elapsedMs - points[i - 1].elapsedMs) / 1000, d = distance(points[i - 1], points[i]);
      if (dt > 5 || d / dt > 50) return 'continuity';
      length += d;
    }
    const net = distance(points[0], last);
    const direction = (a, b) => [(((b.longitude - a.longitude + 540) % 360) - 180) * Math.cos((a.latitude + b.latitude) * Math.PI / 360), b.latitude - a.latitude];
    const opposed = (a, b) => a[0] * b[0] + a[1] * b[1] < 0;
    for (let i = Math.max(2, points.length - 4); i < points.length; i++) {
      if (opposed(direction(points[i - 2], points[i - 1]), direction(points[i - 1], points[i]))) return 'turn';
    }
    if (opposed(direction(points[0], prev), direction(prev, last))) return 'turn';
    if (net < 10) return 'insufficient';
    if (net / length < 0.75) return 'turn';
    return 'invalid';
  }
  if (!raw) return durationMs >= 740 ? 'delay' : 'provider';
  if (['NoMatch', 'NoSegment'].includes(raw.code)) return 'missing';
  if (raw.code !== 'Ok' || !Array.isArray(raw.tracepoints) || !Array.isArray(raw.matchings) || raw.tracepoints.length !== points.length) return 'invalid';
  const tail = raw.tracepoints.at(-1);
  if (!tail) return 'missing';
  const matching = raw.matchings[tail.matchings_index];
  if (!matching || !Number.isFinite(matching.confidence)) return 'invalid';
  if (matching.confidence < 0.8) return 'lowConfidence';
  for (let i = 0; i < raw.tracepoints.length; i++) {
    const t = raw.tracepoints[i], p = points[i];
    if (!t) return 'missing';
    if (t.matchings_index !== tail.matchings_index || t.alternatives_count !== 0) return 'ambiguous';
    if (!Array.isArray(t.location)) return 'invalid';
    if (distance(p, { latitude: t.location[1], longitude: t.location[0] }) > Math.min(20, Math.max(5, p.accuracyMeters))) return 'distance';
  }
  return durationMs >= 740 ? 'delay' : 'invalid';
}
async function evaluateCapture(segments, api, config, matcher) {
  const result = {
    points: segments.reduce((n, p) => n + p.length, 0), segments: segments.length, runs: 0, durationS: 0,
    eligibleFixes: 0, skippedAccuracy: 0, initialMotionUnknown: 0, storedSpeedSamples: 0, storedCourseSamples: 0, requests: 0, accepted: 0,
    clientRejections: { lowSpeed: 0, insufficient: 0, cadence: 0, invalid: 0 }, apiRejections: rejectionCounts(),
    applied: 0, coveredFixes: 0, coverageShare: 0, coverageSeconds: 0, coverageTimeShare: 0,
    clientResponseRejections: { stale: 0, delay: 0, distance: 0 }, pairedFrames: 0
  };
  const samples = { osrmMs: [], matchLatencyMs: [], confidence: [], correctionDistanceM: [], responseAgeMs: [], speedMs: [], pairSpeedMs: [], accuracyM: [] };
  const diagnostic = { diagnosticOnly: true, calls: 0, tailAvailable: 0, fullWindows: 0, nonNullTracepoints: 0, sampledTracepoints: 0, failures: rejectionCounts(),
    transport: { http200: 0, http400: 0, http429: 0, http500: 0, httpOther: 0, notObserved: 0, networkError: 0, codeNoMatch: 0, codeNoSegment: 0, codeInvalidQuery: 0, codeOther: 0 } };
  const diagnosticSamples = { osrmMs: [], confidence: [], correctionDistanceM: [], maximumWindowDistanceM: [] };
  const stats = { before: { errorM: [], eventJumpM: [], frameStepM: [], frameSpeedMs: [] }, after: { errorM: [], eventJumpM: [], frameStepM: [], frameSpeedMs: [] } };
  for (const segment of segments) for (const points of splitRuns(segment)) {
    result.runs++;
    result.durationS += points.length ? (points.at(-1).elapsedMs - points[0].elapsedMs) / 1000 : 0;
    let window = [], lastRequestAt = -Infinity, lastDiagnosticAt = -Infinity;
    const records = [];
    for (let index = 0; index < points.length; index++) {
      const p = points[index], motion = estimateMotion(points, index);
      if (Number.isFinite(p.speedMetersPerSecond) || Number.isFinite(p.speed)) result.storedSpeedSamples++;
      if (Number.isFinite(p.courseDegrees) || Number.isFinite(p.course)) result.storedCourseSamples++;
      if (motion.speed !== null) samples.speedMs.push(motion.speed);
      samples.accuracyM.push(p.accuracyMeters);
      if (index) samples.pairSpeedMs.push(distance(points[index - 1], p) / ((p.elapsedMs - points[index - 1].elapsedMs) / 1000));
      if (motion.speed === null) result.initialMotionUnknown++;
      if (p.accuracyMeters > 30) { result.skippedAccuracy++; window = []; continue; }
      result.eligibleFixes++;
      if (motion.speed !== null && motion.speed > 100) { result.clientRejections.invalid++; window = []; continue; }
      const live = { sequence: p.sequence, elapsedMs: p.elapsedMs, capturedAt: p.capturedAt,
        latitude: p.latitude, longitude: p.longitude, accuracyMeters: p.accuracyMeters,
        ...(motion.speed !== null ? { speed: motion.speed } : {}) };
      window.push(live);
      window = window.filter(q => p.elapsedMs - q.elapsedMs <= 30000).slice(-20);
      const now = p.elapsedMs + config.deliveryMs;
      if (config.diagnosticOnly && window.length >= 3 && now - lastDiagnosticAt >= 2500) {
        lastDiagnosticAt = now;
        diagnostic.calls++;
        diagnostic.sampledTracepoints += window.length;
        if (motion.speed !== null && motion.speed < 2) diagnostic.failures.lowSpeed++;
        const started = performance.now();
        matcher.lastHTTPStatus = null; matcher.lastCode = null; matcher.lastNetworkError = false;
        try {
          // Counterfactual transport diagnostic only: deliberately bypasses client/API admission.
          // These responses NEVER enter records or either predictor.
          const raw = await matcher(window, AbortSignal.timeout(750));
          const traces = raw?.tracepoints, tail = Array.isArray(traces) ? traces.at(-1) : null;
          if (raw?.code !== 'Ok' || !Array.isArray(traces) || !Array.isArray(raw.matchings)) diagnostic.failures.missing++;
          else {
            diagnostic.nonNullTracepoints += traces.filter(Boolean).length;
            if (traces.length === window.length && traces.every(Boolean)) diagnostic.fullWindows++;
            else diagnostic.failures.missing++;
            if (tail && Number.isFinite(raw.matchings[tail.matchings_index]?.confidence)) {
              diagnostic.tailAvailable++;
              const confidence = raw.matchings[tail.matchings_index].confidence;
              diagnosticSamples.confidence.push(confidence);
              if (confidence < 0.8) diagnostic.failures.lowConfidence++;
              diagnosticSamples.correctionDistanceM.push(distance(p, { latitude: tail.location[1], longitude: tail.location[0] }));
              const ds = traces.map((t, i) => t && window[i] ? distance(window[i], { latitude: t.location[1], longitude: t.location[0] }) : null);
              const finite = ds.filter(Number.isFinite);
              if (finite.length) diagnosticSamples.maximumWindowDistanceM.push(Math.max(...finite));
              if (ds.some((d, i) => d !== null && d > Math.min(20, Math.max(5, window[i].accuracyMeters)))) diagnostic.failures.distance++;
              if (traces.some(t => t && (t.alternatives_count !== 0 || t.matchings_index !== tail.matchings_index))) diagnostic.failures.ambiguous++;
            }
          }
        } catch {
          diagnostic.failures[performance.now() - started >= 740 ? 'delay' : 'provider']++;
        } finally {
          diagnosticSamples.osrmMs.push(performance.now() - started);
          const s = matcher.lastHTTPStatus;
          diagnostic.transport[s === null ? 'notObserved' : s === 200 ? 'http200' : s === 400 ? 'http400' : s === 429 ? 'http429' : s >= 500 ? 'http500' : 'httpOther']++;
          if (matcher.lastNetworkError) diagnostic.transport.networkError++;
          if (matcher.lastCode) diagnostic.transport[matcher.lastCode === 'NoMatch' ? 'codeNoMatch' : matcher.lastCode === 'NoSegment' ? 'codeNoSegment' : matcher.lastCode === 'InvalidQuery' ? 'codeInvalidQuery' : 'codeOther']++;
        }
      }
      if (now - lastRequestAt < 2500) { result.clientRejections.cadence++; continue; }
      if (motion.speed !== null && motion.speed < 2) { result.clientRejections.lowSpeed++; continue; }
      if (window.length < 3) { result.clientRejections.insufficient++; continue; }
      // Only wall-clock epoch is shifted. Elapsed time and original capturedAt intervals stay intact.
      const shift = Date.now() - Date.parse(live.capturedAt);
      const request = { segmentId: '00000000-0000-4000-8000-000000000001', points: window.map(q => ({ ...q, capturedAt: new Date(Date.parse(q.capturedAt) + shift).toISOString() })) };
      const parsed = api.liveMatchRequest.safeParse(request);
      if (!parsed.success) { result.clientRejections.invalid++; continue; }
      lastRequestAt = now; result.requests++;
      let raw, called = false;
      const observed = async (ps, signal) => {
        called = true;
        const t = performance.now();
        try { raw = await matcher(ps, signal); return raw; }
        finally { samples.osrmMs.push(performance.now() - t); }
      };
      const started = performance.now();
      const response = await api.matchLive(parsed.data, observed);
      const durationMs = performance.now() - started;
      samples.matchLatencyMs.push(durationMs);
      if (response.status === 'MATCHED') {
        result.accepted++;
        samples.confidence.push(response.confidence);
        samples.correctionDistanceM.push(response.distanceMeters);
      } else result.apiRejections[refusalReason(request.points, raw, called, durationMs)]++;
      records.push({ index, result: response, durationMs });
    }
    const simulation = simulateRun(points, records, config);
    result.applied += simulation.applied;
    result.pairedFrames += simulation.pairedFrames;
    result.coverageSeconds += simulation.coverageSeconds;
    for (const key of ['stale', 'delay', 'distance']) result.clientResponseRejections[key] += simulation[key];
    samples.responseAgeMs.push(...simulation.responseAgeMs);
    for (const mode of ['before', 'after']) for (const key of Object.keys(stats[mode])) {
      // Avoid argument limits on long captures.
      for (const v of simulation[mode][key]) stats[mode][key].push(v);
    }
  }
  result.durationS = round(result.durationS);
  result.coveredFixes = result.applied;
  result.coverageShare = result.points ? round(result.coveredFixes / result.points) : null;
  result.coverageTimeShare = result.pairedFrames ? round(result.coverageSeconds / (result.pairedFrames / 60)) : null;
  result.coverageSeconds = round(result.coverageSeconds);
  for (const [key, values] of Object.entries(samples)) result[key] = quantiles(values);
  if (config.diagnosticOnly) result.diagnosticDirectOSRM = { ...diagnostic, ...Object.fromEntries(Object.entries(diagnosticSamples).map(([key, values]) => [key, quantiles(values)])) };
  for (const mode of ['before', 'after']) result[mode] = Object.fromEntries(Object.entries(stats[mode]).map(([key, values]) => [key, quantiles(values)]));
  return result;
}
function createObservedMatcher(api, fetcher = fetch) {
  let matcher;
  const observedFetch = async (url, init) => {
    let reply;
    try { reply = await fetcher(url, init); }
    catch { matcher.lastNetworkError = true; throw new Error('NETWORK_UNAVAILABLE'); }
    matcher.lastHTTPStatus = reply.status;
    if (!reply.ok) {
      // Inspect at most 64 KiB inside CT114, then keep only a whitelisted OSRM code.
      const reader = reply.clone().body?.getReader();
      if (reader) {
        try {
          const chunks = []; let size = 0;
          while (true) { const part = await reader.read(); if (part.done) break; size += part.value.length; if (size > 65536) break; chunks.push(part.value); }
          if (size <= 65536) {
            const code = JSON.parse(Buffer.concat(chunks).toString('utf8')).code;
            matcher.lastCode = ['NoMatch', 'NoSegment', 'InvalidQuery'].includes(code) ? code : 'Other';
          }
        } catch { matcher.lastCode = 'Other'; }
        finally { reader.cancel().catch(() => {}); }
      }
    }
    return reply;
  };
  matcher = api.createOSRMLiveMatcher(OSRM, restrictedFetch(observedFetch));
  return matcher;
}
async function run(input) {
  const env = Object.fromEntries(fs.readFileSync('/etc/drivy-refonte/api.env', 'utf8').split('\n').filter(l => l.includes('=') && !l.startsWith('#')).map(l => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]));
  const key = Buffer.from(env.CAPTURE_ENCRYPTION_KEY_HEX, 'hex');
  if (key.length !== 32) throw new Error('KEY_UNAVAILABLE');
  const captures = decryptCaptures(input.data, key);
  key.fill(0);
  const api = await import('data:text/javascript;base64,' + Buffer.from(input.apiBundle).toString('base64'));
  const config = { deliveryMs: 100, additionalNetworkMs: input.networkMs ?? 0, frameHz: 60, requestIntervalMs: 2500, windowPoints: 20, maximumWindowAgeMs: 30000, diagnosticOnly: input.diagnosticOnly === true };
  const report = { schemaVersion: 1, numericalModelOnly: true, dopplerEstimated: true, groundTruthAvailable: false,
    comparesCurrentPredictor: true, configurations: config, sourceHashes: input.sourceHashes, captures: [] };
  const matcher = createObservedMatcher(api);
  for (const segments of captures) report.captures.push(await evaluateCapture(segments, api, config, matcher));
  return numericReport(report);
}
for (const key of ['clientRejections', 'apiRejections', 'clientResponseRejections', 'cadence', 'speedMs', 'pairSpeedMs', 'accuracyM', 'diagnosticDirectOSRM', 'diagnosticOnly', 'calls', 'tailAvailable', 'fullWindows', 'nonNullTracepoints', 'sampledTracepoints', 'failures', 'maximumWindowDistanceM']) REPORT_KEYS.add(key);
for (const key of ['p95', 'storedSpeedSamples', 'storedCourseSamples']) REPORT_KEYS.add(key);
for (const key of ['transport', 'http200', 'http400', 'http429', 'http500', 'httpOther', 'notObserved', 'networkError', 'codeNoMatch', 'codeNoSegment', 'codeInvalidQuery', 'codeOther']) REPORT_KEYS.add(key);
module.exports = { quantiles, estimateMotion, splitRuns, numericReport, restrictedFetch, offset, move, distance, decryptCaptures, Predictor, simulateRun, evaluateCapture, createObservedMatcher, run };
