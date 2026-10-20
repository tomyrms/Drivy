'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { quantiles, estimateMotion, splitRuns, numericReport, restrictedFetch, Predictor, simulateRun, evaluateCapture, createObservedMatcher } = require('./live-compare.js');

// Synthetic coordinates only. No captured fixture belongs in this file.
const point = (t, n = t, extras = {}) => ({ elapsedMs: t * 1000, sequence: t, latitude: n / 111195, longitude: 0, accuracyMeters: 4, ...extras });

test('quantiles report missing samples honestly', () => {
  assert.deepEqual(quantiles([]), { count: 0, mean: null, p50: null, p90: null, p95: null, p99: null, max: null });
  assert.equal(quantiles([1, 2, 3]).p50, 2);
  assert.equal(quantiles([1, 2, 3]).mean, 2);
});

test('Doppler substitute is causal, not a future position leak', () => {
  const points = [point(0), point(1), point(2), point(3, 9000)];
  assert.ok(Math.abs(estimateMotion(points, 2).speed - 1) < 0.001);
  assert.equal(estimateMotion(points, 0).speed, null);
  assert.ok(Math.abs(estimateMotion(points, 2).course) < 0.001);
});

test('a time gap or sequence gap splits measurement runs', () => {
  const runs = splitRuns([point(0), point(1), point(8, 8, { sequence: 2 }), point(9, 9, { sequence: 5 }), point(10, 10, { sequence: 6 })]);
  assert.deepEqual(runs.map(r => r.length), [2, 1, 2]);
});

test('outbound report rejects coordinates, IDs, raw messages and nonfinite values', () => {
  assert.doesNotThrow(() => numericReport({ captures: [{ points: 3, before: { errorM: quantiles([1, 2]) } }] }));
  for (const payload of [{ latitude: 47 }, { id: 42 }, { captures: [{ error: 'private URL' }] }, { points: NaN }]) {
    assert.throws(() => numericReport(payload));
  }
});

test('network wrapper allows only the named direct OSRM matcher with redirects disabled', async () => {
  let seen;
  const f = restrictedFetch(async (url, init) => { seen = { url, init }; return { ok: true }; });
  await f('http://192.168.1.158:5000/match/v1/driving/0,0;0,1?overview=full', { method: 'GET', redirect: 'follow' });
  assert.equal(seen.init.redirect, 'error');
  for (const url of ['https://example.com', 'http://192.168.1.158:5000/route/v1/driving/0,0', 'http://secret@192.168.1.158:5000/match/v1/driving/0,0', 'http://192.168.1.158:5001/match/v1/driving/0,0']) {
    await assert.rejects(f(url));
  }
});

test('road correction and clearing preserve displayed position and fix clock', () => {
  const p = new Predictor();
  p.receive(point(0), { speed: 10, course: 0 }, 0);
  const before = p.position(0.2);
  assert.equal(p.correct({ latitude: 0, longitude: 5 / 111195 }, 0.2), true);
  assert.ok(Math.abs(p.position(0.2).latitude - before.latitude) < 1e-10);
  assert.ok(Math.abs(p.position(0.2).longitude - before.longitude) < 1e-10);
  assert.equal(p.fix.at, 0);
  const beforeClear = p.position(0.4);
  p.clear(0.4);
  assert.ok(Math.abs(p.position(0.4).longitude - beforeClear.longitude) < 1e-10);
  assert.equal(p.fix.at, 0);
});

test('unavailable road matching leaves exactly the baseline predictor', () => {
  const points = [point(0), point(1), point(2), point(3)];
  const s = simulateRun(points, [], { deliveryMs: 100, additionalNetworkMs: 0 });
  assert.deepEqual(s.before.errorM, s.after.errorM);
  assert.equal(s.applied, 0);
  assert.ok(s.before.errorM.length > 0);
});

test('next acquisition invalidates response even before next durable delivery', () => {
  const points = [point(0), point(1), point(2), point(3)];
  const records = [{ index: 1, durationMs: 950, result: { status: 'MATCHED', confidence: 0.99, distanceMeters: 1, position: { latitude: points[1].latitude, longitude: 1 / 111195 } } }];
  const s = simulateRun(points, records, { deliveryMs: 100, additionalNetworkMs: 0 });
  assert.equal(s.applied, 0);
  assert.equal(s.stale, 1);
  assert.deepEqual(s.before.errorM, s.after.errorM);
});

test('road suggestion expires two seconds from send, not from response arrival', () => {
  const points = [point(0, 0), point(1, 10), point(4, 40)];
  const records = [{ index: 1, durationMs: 1000, result: { status: 'MATCHED', confidence: 0.99, distanceMeters: 1,
    position: { latitude: points[1].latitude, longitude: 1 / 111195 } } }];
  const s = simulateRun(points, records, { deliveryMs: 100, additionalNetworkMs: 0 });
  assert.equal(s.applied, 1);
  // Sent at 1.1s, received at 2.1s, expires at 3.1s. Next acquisition is only at 4s.
  assert.ok(s.coverageSeconds >= 0.98 && s.coverageSeconds <= 1.02);
});

test('real API function and numerical predictor produce anonymous, finite aggregates', async () => {
  const esbuild = require('esbuild');
  const bundle = esbuild.buildSync({ entryPoints: ['apps/api/src/live-matching.ts'], bundle: true, write: false, platform: 'node', format: 'esm', logLevel: 'silent' }).outputFiles[0].text;
  const api = await import('data:text/javascript;base64,' + Buffer.from(bundle).toString('base64'));
  const points = Array.from({ length: 15 }, (_, i) => point(i, i * 12, { capturedAt: new Date(1700000000000 + i * 1000).toISOString() }));
  const noMatch = createObservedMatcher(api, async () => new Response(JSON.stringify({ code: 'NoMatch', message: 'not exported' }), { status: 400 }));
  await assert.rejects(noMatch(points.slice(0, 3), AbortSignal.timeout(1000)));
  assert.equal(noMatch.lastHTTPStatus, 400);
  assert.equal(noMatch.lastCode, 'NoMatch');
  assert.notEqual(noMatch.lastNetworkError, true);
  const unknownCode = createObservedMatcher(api, async () => new Response(JSON.stringify({ code: 'private content' }), { status: 400 }));
  await assert.rejects(unknownCode(points.slice(0, 3), AbortSignal.timeout(1000)));
  assert.equal(unknownCode.lastCode, 'Other');
  const matcher = async ps => ({ code: 'Ok', matchings: [{ confidence: 0.99 }], tracepoints: ps.map(p => ({ location: [1 / 111195, p.latitude], matchings_index: 0, alternatives_count: 0 })) });
  const config = { deliveryMs: 100, additionalNetworkMs: 0 };
  const report = await evaluateCapture([points], api, config, matcher);
  numericReport({ captures: [report] });
  assert.equal(report.requests, 5);
  assert.equal(report.accepted, 5);
  assert.equal(report.applied, 5);
  assert.equal(report.after.eventJumpM.max, 0);
  assert.ok(report.coverageTimeShare > 0);
  const delayed = await evaluateCapture([points], api, { ...config, additionalNetworkMs: 2100 }, matcher);
  assert.equal(delayed.applied, 0);
  assert.equal(delayed.clientResponseRejections.delay, 5);
  assert.deepEqual(delayed.before.errorM, delayed.after.errorM);
  const weak = await evaluateCapture([points], api, config, async ps => ({ ...(await matcher(ps)), matchings: [{ confidence: 0.5 }] }));
  assert.equal(weak.apiRejections.lowConfidence, 5);
  assert.equal(weak.accepted, 0);
  assert.deepEqual(weak.before.errorM, weak.after.errorM);
  const slow = points.map((p, i) => ({ ...p, latitude: i / 111195 }));
  const diagnostic = await evaluateCapture([slow], api, { ...config, diagnosticOnly: true }, matcher);
  numericReport({ captures: [diagnostic] });
  assert.equal(diagnostic.requests, 0);
  assert.equal(diagnostic.applied, 0);
  assert.equal(diagnostic.diagnosticDirectOSRM.calls, 5);
  assert.equal(diagnostic.diagnosticDirectOSRM.failures.lowSpeed, 5);
  assert.deepEqual(diagnostic.before.errorM, diagnostic.after.errorM);
  const turnPoints = points.map(p => ({ ...p }));
  turnPoints[14].latitude = 138 / 111195;
  const turn = await evaluateCapture([turnPoints], api, config, matcher);
  assert.equal(turn.accepted, 4);
  assert.equal(turn.apiRejections.turn, 1);
});
