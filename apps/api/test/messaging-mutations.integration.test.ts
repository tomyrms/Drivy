import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { freshDatabase } from './support/harness.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { registerMessaging } from '../src/messaging-routes.js';
import { registerSchoolSetup } from '../src/school-setup.js';
import { lockCommandOperation } from '../src/commands.js';
import { ApiError } from '../src/errors.js';

const url=process.env.TEST_DATABASE_URL;
if(!url||new URL(url).pathname!=='/drivy_test')throw new Error('Base synthétique drivy_test obligatoire.');
const issuer='https://messaging-mutations.test.invalid',pool=new Pool({connectionString:url,max:8}),app=Fastify();
const verifyToken=async(authorization:string|undefined)=>{
  if(!authorization?.startsWith('Bearer demo-'))throw new ApiError(401,'AUTHENTICATION_REQUIRED','Connexion requise.');
  return {issuer,subject:authorization.slice(7)};
};
app.setErrorHandler((error,_request,reply)=>reply.status(error instanceof ApiError?error.status:400).send({code:error instanceof ApiError?error.code:'INVALID_REQUEST'}));
registerMessaging(app,{pool,verifyToken,mode:'test-synthetic'}); registerSchoolSetup(app,{pool,verifyToken});
const path=`/v1/schools/${id.schoolA}/messaging`,subjects:Record<string,string>={'demo-alice':id.alice,'demo-instructor':id.instructor,'demo-admin':id.admin};
type Method='GET'|'POST'|'PUT'|'DELETE';
const call=(method:Method,target:string,body?:object,key?:string,subject='demo-alice',epoch='1')=>app.inject({method,url:target,
  headers:{authorization:`Bearer ${subject}`,'x-drivy-expected-person-id':subjects[subject]!,'x-drivy-expected-access-epoch':epoch,
    ...(key?{'idempotency-key':key}:{})},...(body?{payload:body}:{})});
async function fixture(poll=false) {
  const conversationId=(await call('PUT',`${path}/private/${id.instructor}`)).json().data.conversationId as string;
  const response=await call('POST',`${path}/conversations/${conversationId}/messages`,{clientMessageId:randomUUID(),expectedMembersEpoch:0,
    ciphertext:{scheme:'synthetic',keyId:'fixture',payload:'AAAA'},...(poll?{poll:{optionCount:3,multiple:false}}:{})});
  expect(response.statusCode,response.body).toBe(200);
  const messageId=response.json().data.id as string;
  return {conversationId,messageId,messagePath:`${path}/conversations/${conversationId}/messages/${messageId}`};
}
beforeAll(async()=>{const database=await freshDatabase();await database.end();});
beforeEach(async()=>{await pool.query('TRUNCATE drivy.person,drivy.school CASCADE');await seedFixtures(pool,issuer);});
afterAll(async()=>{await app.close();await pool.end();});

describe('reçus de mutations messagerie après arrêt et reprise',()=>{
  it.each(['reaction','pin','vote'] as const)('A confirmé, B confirmé, ancien A tardif ne réapplique pas %s',async kind=>{
    const f=await fixture(kind==='vote'),a=randomUUID(),b=randomUUID();
    const target=f.messagePath+(kind==='reaction'?'/reactions/'+encodeURIComponent('👍'):kind==='pin'?'/pin':'/poll/votes');
    const first=await call('PUT',target,kind==='vote'?{optionIndexes:[0]}:undefined,a);
    expect(first.statusCode,first.body).toBe(200);expect(first.json().mutationReceipt).toEqual({operationId:a});
    const second=await call(kind==='vote'?'PUT':'DELETE',target,kind==='vote'?{optionIndexes:[1]}:undefined,b);
    expect(second.statusCode,second.body).toBe(200);
    const delayed=await call('PUT',target,kind==='vote'?{optionIndexes:[0]}:undefined,a);
    expect(delayed.statusCode,delayed.body).toBe(200);expect(delayed.json().data).toEqual(first.json().data);
    const message=(await call('GET',`${path}/conversations/${f.conversationId}/messages`)).json().data.items[0];
    if(kind==='reaction')expect(message.reactions).toEqual([]);
    if(kind==='pin')expect(message.pinned).toBe(false);
    if(kind==='vote')expect(message.poll.votes).toEqual([{optionIndex:1,personIds:[id.alice]}]);
    const receipts=await pool.query('SELECT count(*)::int AS n FROM drivy.operation WHERE actor_person_id=$1 AND operation_id=ANY($2::uuid[])',[id.alice,[a,b]]);
    expect(receipts.rows[0].n).toBe(2);
    const audit=await pool.query('SELECT count(*)::int AS n FROM drivy.audit_event WHERE actor_person_id=$1 AND operation_id=ANY($2::uuid[])',[id.alice,[a,b]]);
    expect(audit.rows[0].n).toBe(2);
  });
  it('deux A simultanés attendent la même clé, puis A tardif ne peut annuler B',async()=>{
    const f=await fixture(),a=randomUUID(),target=f.messagePath+'/reactions/'+encodeURIComponent('👍');
    const blocker=await pool.connect();await blocker.query('BEGIN');await lockCommandOperation(blocker,id.alice,a);
    const first=call('PUT',target,undefined,a),retry=call('PUT',target,undefined,a);
    try {
      let waiting=0;const deadline=Date.now()+3000;
      while(Date.now()<deadline){
        const result=await pool.query<{n:number}>("SELECT count(*)::int AS n FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%pg_advisory_xact_lock%'");
        waiting=result.rows[0]!.n;if(waiting>=2)break;
        await new Promise(done=>setTimeout(done,10));
      }
      expect(waiting).toBeGreaterThanOrEqual(2);
    } finally {await blocker.query('COMMIT');blocker.release();}
    for(const response of await Promise.all([first,retry]))expect(response.statusCode,response.body).toBe(200);
    expect((await call('DELETE',target,undefined,randomUUID())).statusCode).toBe(200);
    expect((await call('PUT',target,undefined,a)).statusCode).toBe(200);
    expect((await pool.query('SELECT count(*)::int AS n FROM drivy.messaging_reaction WHERE message_id=$1',[f.messageId])).rows[0].n).toBe(0);
    expect((await pool.query('SELECT count(*)::int AS n FROM drivy.operation WHERE operation_id=$1',[a])).rows[0].n).toBe(1);
  });
  it('lie la clé au contenu, à la route et à la personne, valide le format',async()=>{
    const f=await fixture(true),a=randomUUID(),votes=f.messagePath+'/poll/votes';
    expect((await call('PUT',votes,{optionIndexes:[0]},a)).statusCode).toBe(200);
    expect((await call('PUT',votes,{optionIndexes:[1]},a)).json().code).toBe('IDEMPOTENCY_MISMATCH');
    expect((await call('PUT',f.messagePath+'/pin',undefined,a)).json().code).toBe('IDEMPOTENCY_MISMATCH');
    expect((await call('PUT',votes,{optionIndexes:[1]},'invalid-key')).statusCode).toBe(400);
    // The same UUID from another actor is independent and cannot return Alice's receipt or vote.
    const other=await call('PUT',votes,{optionIndexes:[2]},a,'demo-instructor');
    expect(other.statusCode,other.body).toBe(200);expect(other.json().data.optionIndexes).toEqual([2]);
  });
  it.each(['me','everyone'] as const)('rejoue suppression %s, expose AP72 à son auteur et relit accès',async scope=>{
    const f=await fixture(),a=randomUUID(),target=f.messagePath+'?scope='+scope;
    const first=await call('DELETE',target,undefined,a);
    expect(first.statusCode,first.body).toBe(200);
    expect((await call('DELETE',target,undefined,a)).json().data).toEqual(first.json().data);
    const receipt=await call('GET',`/v1/schools/${id.schoolA}/operations/${a}`);
    expect(receipt.statusCode,receipt.body).toBe(200);expect(receipt.json().data.operationId).toBe(a);
    expect((await call('GET',`/v1/schools/${id.schoolA}/operations/${a}`,undefined,undefined,'demo-instructor')).statusCode).toBe(404);
    await pool.query('UPDATE drivy.membership SET access_epoch=access_epoch+1 WHERE id=$1',[id.aliceMember]);
    expect((await call('DELETE',target,undefined,a)).statusCode).toBe(403);
  });
  it('conserve anciens clients sans clé et ne leur annonce pas de reçu',async()=>{
    const f=await fixture(),target=f.messagePath+'/reactions/'+encodeURIComponent('👍');
    const response=await call('PUT',target);
    expect(response.statusCode,response.body).toBe(200);expect(response.json().mutationReceipt).toBeUndefined();
    expect((await pool.query('SELECT count(*)::int AS n FROM drivy.operation WHERE command_type LIKE $1',['MESSAGING_%'])).rows[0].n).toBe(0);
  });
  it('ne révèle pas le reçu privé dans l’audit scolaire d’un administrateur',async()=>{
    const f=await fixture(),operationId=randomUUID();
    expect((await call('PUT',f.messagePath+'/pin',undefined,operationId)).statusCode).toBe(200);
    const db=await pool.connect();
    try {
      await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true),set_config('app.membership_id',$3,true)",[id.schoolA,id.admin,id.adminMember]);
      expect((await db.query('SELECT 1 FROM drivy.audit_event WHERE operation_id=$1',[operationId])).rowCount).toBe(0);
      await db.query("SELECT set_config('app.person_id',$1,true),set_config('app.membership_id',$2,true)",[id.alice,id.aliceMember]);
      expect((await db.query('SELECT 1 FROM drivy.audit_event WHERE operation_id=$1',[operationId])).rowCount).toBe(1);
    } finally {await db.query('ROLLBACK');db.release();}
  });
});
