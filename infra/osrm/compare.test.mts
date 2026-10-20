import assert from 'node:assert/strict';
import { test } from 'node:test';
import { coveredPointCount, distanceToPolyline, travelDistances, makeSyntheticTrace } from './synthetic.mts';
import { benchmark } from './compare.mts';

test('un arrêt de vingt secondes a lieu une fois, même si le pas ne tombe pas au milieu', () => {
  const distances = travelDistances(1003);
  const held = distances.filter((d, i) => i > 0 && d === distances[i - 1]);
  assert.equal(held.length, 20);
  assert.equal(new Set(held).size, 1);
  assert.equal(held[0], 501.5);
  assert.equal(distances[0], 0);
  assert.equal(distances.at(-1), 1003);
  assert.ok(distances.every((d, i) => i === 0 || d >= distances[i - 1]!));
});

test('la couverture compte les mesures existantes une fois par segment, sans remplir les trous', () => {
  const segments = [{ segmentId: 'a', points: [0, 1, 2, 4, 8].map(sequence => ({ sequence })) },
    { segmentId: 'b', points: [{ sequence: 1 }] }];
  const spans = [{ segmentId: 'a', firstSequence: 0, lastSequence: 2 },
    { segmentId: 'a', firstSequence: 2, lastSequence: 4 },
    { segmentId: 'b', firstSequence: 1, lastSequence: 1 },
    { segmentId: 'unknown', firstSequence: 0, lastSequence: 99 }];
  assert.equal(coveredPointCount(segments, spans), 5);
  assert.equal(coveredPointCount(segments, []), 0);
});

test('la distance est projetée sur les segments et non sur les seuls sommets', () => {
  assert.ok(distanceToPolyline([47, 7.0005], [[47, 7], [47, 7.001]]) < 0.001);
  const offset = distanceToPolyline([47.0001, 7.0005], [[47, 7], [47, 7.001]]);
  assert.ok(offset > 11 && offset < 11.2);
  assert.ok(distanceToPolyline([47, 7.002], [[47, 7], [47, 7.001]]) > 75);
  assert.equal(distanceToPolyline([47, 7], [[47, 7], [47, 7]]), 0);
});

test('génération déterministe, horodatages progressifs et aucune mutation de la référence', () => {
  const line: [number, number][] = [[47, 7], [47, 7.01]];
  const copy = structuredClone(line), first = makeSyntheticTrace(line), second = makeSyntheticTrace(line);
  assert.deepEqual(first, second);
  assert.deepEqual(line, copy);
  assert.ok(first.points.every((p, i) => p.sequence === i && p.elapsedMs === i * 1000));
  assert.equal(first.distances.filter((d, i) => i > 0 && d === first.distances[i - 1]).length, 20);
});

test('références vides ou dégénérées refusées au lieu de boucler', () => {
  for (const length of [0, -1, NaN, Infinity, 100_001]) assert.throws(() => travelDistances(length));
  assert.throws(() => makeSyntheticTrace([]));
  assert.throws(() => makeSyntheticTrace([[47, 7], [47, 7]]));
  assert.throws(() => distanceToPolyline([47, 7], []));
});

test('aucun accès à un moteur public ni URL contenant un secret', async () => {
  await assert.rejects(benchmark('https://example.org'), /PRIVATE_ENGINE_REQUIRED/);
  await assert.rejects(benchmark('http://127.0.0.1:5000?token=not-a-real-token'));
  await assert.rejects(benchmark('http://user:password@127.0.0.1:5000'));
});
