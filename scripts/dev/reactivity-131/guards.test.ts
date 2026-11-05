import assert from 'node:assert/strict';
import { verifyMetadataOnly, accessVerdictMatches, accessReason } from './guards.js';
const meta = {operationId:'31100000-0000-4000-8000-000000000001',schoolId:'31100000-0000-4000-8000-000000000002',kind:'updateMember',resourceId:'31100000-0000-4000-8000-000000000003',resourceVersion:1,createdAt:1000};
assert.equal(verifyMetadataOnly(JSON.stringify([meta])),1);
assert.equal(verifyMetadataOnly(null),0);
for(const text of [JSON.stringify([{...meta,reason:accessReason}]), JSON.stringify([{...meta,reason:accessReason}]).replaceAll('é','\\u00e9'), JSON.stringify([{...meta,operationId:accessReason}]), JSON.stringify([{...meta,body:{reason:accessReason}}])]) {
  assert.throws(()=>verifyMetadataOnly(text), /metadata/i, 'reject leaked body regardless of JSON Unicode encoding');
}
for(const text of ['{}','null','[null]','[[]]','broken']) assert.throws(()=>verifyMetadataOnly(text));
assert.equal(accessVerdictMatches({confirmed:false,phases:[],changed:false},'confirmed'),false,'response without store confirmation cannot pass');
assert.equal(accessVerdictMatches({confirmed:true,phases:[],changed:false},'confirmed'),true);
assert.equal(accessVerdictMatches({confirmed:false,phases:[{phase:'sending'}],changed:false},'lost'),false);
assert.equal(accessVerdictMatches({confirmed:false,phases:[{phase:'uncertain'}],changed:false},'lost'),true);
for(const expected of ['lost','refused','account'] as const) assert.equal(accessVerdictMatches({confirmed:true,phases:[],changed:true},expected),false);
console.log('PASS metadata negative witnesses and required store verdicts');
