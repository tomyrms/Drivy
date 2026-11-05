import assert from 'node:assert/strict';
import { summarize } from './stats.js';
assert.deepEqual(summarize([10, 30, 20]), { n: 3, min: 10, median: 20, max: 30 });
assert.deepEqual(summarize([]), { status: 'NON_MESURÉ', reason: 'Aucun échantillon observé' });
assert.throws(() => summarize([NaN]));
console.log('PASS instrumentation statistics: empty is not zero, invalid is rejected');
