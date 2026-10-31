import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,type Call} from './support/harness.js';
import {processPushBatch,type PushSender} from '../src/course-push.js';

/**
 * Cours collectifs : un push refusé, absent ou en échec ne touche ni la confirmation visible, ni l'inscription, ni la place
 * proposée (#83 : #39 « push refusé », #40 « panne de livraison sans fausse lecture ni inscription cachée »).
 * Données synthétiques. L'envoi APNs réel est remplacé par un expéditeur local : aucune livraison réelle n'est revendiquée.
 */
let pool:Pool,worker:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
beforeAll(async()=>{
 pool=await freshDatabase();({call,app}=await harness(pool));await prepareSchool(pool);
 worker=new Pool({connectionString:process.env.TEST_DATABASE_URL,options:'-c role=drivy_harness_migrator'});
});
afterAll(async()=>{await app?.close();await worker?.end();await pool?.end();});

const at=(offset:number,hourUtc:number)=>{const d=new Date();d.setUTCDate(d.getUTCDate()+offset);d.setUTCHours(hourUtc,0,0,0);return d.toISOString();};
let cursor=10;
async function published(capacity=5){
 const type=(await call('POST','/course-types',{operationId:randomUUID(),title:`Type ${randomUUID()}`,description:''},null,'demo-admin')).json().data.id;
 const start=cursor+=4;
 const created=await call('POST','/course-series',{operationId:randomUUID(),typeId:type,title:'Cours notifié',description:'',location:'Salle',conditions:'',teachingLanguage:null,
  responsibleMembershipId:id.adminMember,capacity,minParticipants:null,timeZone:'Europe/Zurich',
  occurrences:[{startsAt:at(start,8),endsAt:at(start,11),instructorMembershipId:id.otherInstructorMember,attendanceRequired:true}]},null,'demo-admin');
 if(created.statusCode!==201)throw new Error(created.body);
 const res=await call('POST',`/course-series/${created.json().data.id}/publish`,{operationId:randomUUID()},created.json().data.version,'demo-admin');
 if(res.statusCode!==200)throw new Error(res.body);
 return res.json().data as {id:string;version:number};
}
/** Un seul appareil actif par élève et par essai : les autres sont révoqués, pour que « aucun appareil » soit vrai quand on le prétend. */
const registerDevice=async(subject:string,person:string)=>{
 await pool.query('UPDATE drivy.push_device SET revoked_at=now() WHERE person_id=$1 AND revoked_at IS NULL',[person]);
 const res=await call('PUT','/v1/me/push-devices',{token:randomUUID().replace(/-/g,'').repeat(2),environment:'SANDBOX'},null,subject);
 expect(res.statusCode,res.body).toBe(200);
};
const answering=(result:'SENT'|'INVALID_TOKEN'|'RETRY'):PushSender=>({send:async()=>result,close(){}});
const unreachable:PushSender={send:async()=>{throw new Error('APNs injoignable (simulé)');},close(){}};
type Row={status:string;attempts:number;failure_code:string|null;sent_at:Date|null;available_at:Date};
const notification=async(person:string,seriesId:string,category:string)=>{
 const rows=(await pool.query<Row>('SELECT status,attempts,failure_code,sent_at,available_at FROM drivy.push_notification WHERE person_id=$1 AND series_id=$2 AND category=$3',[person,seriesId,category])).rows;
 expect(rows,`notification ${category} de la série`).toHaveLength(1);return rows[0]!;
};
const activeEnrollments=async(seriesId:string)=>(await pool.query<{n:number}>("SELECT count(*)::int AS n FROM drivy.course_enrollment WHERE series_id=$1 AND status='ACTIVE'",[seriesId])).rows[0]!.n;
const learnerReservations=async(seriesId:string,person:string)=>(await pool.query<{n:number}>(`SELECT count(*)::int AS n FROM drivy.reservation r JOIN drivy.course_occurrence o ON o.id=r.course_occurrence_id
 WHERE o.series_id=$1 AND r.resource_id=$2 AND r.course_enrollment_id IS NOT NULL AND r.active`,[seriesId,person])).rows[0]!.n;

/** Inscription faite, puis tentative d'envoi : tout ce que l'élève voit doit rester identique. */
async function enrolled(withDevice:boolean){
 const series=await published();
 if(withDevice)await registerDevice('demo-alice',id.alice);
 else await pool.query('UPDATE drivy.push_device SET revoked_at=now() WHERE person_id=$1 AND revoked_at IS NULL',[id.alice]);
 const operationId=randomUUID();
 const res=await call('POST',`/course-series/${series.id}/enroll`,{operationId},null,'demo-alice');
 expect(res.statusCode,res.body).toBe(201);
 return {series,operationId,enrollment:res.json().data.me.enrollment as {id:string;version:number}};
}
async function expectConfirmed(context:Awaited<ReturnType<typeof enrolled>>){
 const view=(await call('GET',`/course-series/${context.series.id}/me`,undefined,null,'demo-alice')).json().data;
 expect(view.me.state).toBe('ENROLLED');
 expect(view.me.enrollment).toMatchObject({id:context.enrollment.id,status:'ACTIVE',canSelfCancel:true});
 expect(view.series.seatsTaken).toBe(1);
 expect(await activeEnrollments(context.series.id)).toBe(1);
 expect(await learnerReservations(context.series.id,id.alice)).toBe(1);
 // Le rejeu de la commande (réponse perdue côté app) rend la même inscription, sans doublon.
 const replay=await call('POST',`/course-series/${context.series.id}/enroll`,{operationId:context.operationId},null,'demo-alice');
 expect(replay.statusCode).toBe(201);expect(replay.json().data.me.enrollment.id).toBe(context.enrollment.id);
 expect(await activeEnrollments(context.series.id)).toBe(1);
}

describe('#39 confirmation d’inscription : le push n’en est jamais la condition',()=>{
 it.each([
  {name:'envoi réussi (témoin)',device:true,sender:answering('SENT'),expected:{status:'SENT',attempts:1,failure_code:null}},
  {name:'aucun appareil enregistré (autorisation des notifications refusée sur l’iPhone)',device:false,sender:answering('SENT'),expected:{status:'SKIPPED',attempts:0,failure_code:'NO_DEVICE'}},
  {name:'jeton refusé par APNs (INVALID_TOKEN)',device:true,sender:answering('INVALID_TOKEN'),expected:{status:'FAILED',attempts:1,failure_code:'NO_VALID_DEVICE'}},
 ])('$name : inscription confirmée, état « Inscrit » et occupations intacts',async({device,sender,expected})=>{
  const context=await enrolled(device);
  await processPushBatch(worker,sender);
  expect(await notification(id.alice,context.series.id,'CHANGE')).toMatchObject(expected);
  await expectConfirmed(context);
 });

 it('un jeton refusé est révoqué, mais le compte et l’inscription restent',async()=>{
  const context=await enrolled(true);
  await processPushBatch(worker,answering('INVALID_TOKEN'));
  const devices=(await pool.query<{revoked_at:Date|null}>('SELECT revoked_at FROM drivy.push_device WHERE person_id=$1',[id.alice])).rows;
  expect(devices.length).toBeGreaterThan(0);expect(devices.every(device=>device.revoked_at!==null)).toBe(true);
  await expectConfirmed(context);
 });

 it('APNs indisponible : quatre reprises espacées, puis abandon ; la confirmation ne change à aucune étape',async()=>{
  const context=await enrolled(true);
  await processPushBatch(worker,answering('RETRY'));
  let row=await notification(id.alice,context.series.id,'CHANGE');
  expect(row).toMatchObject({status:'PENDING',attempts:1,sent_at:null});
  expect(row.available_at.getTime()).toBeGreaterThan(Date.now());
  await expectConfirmed(context);
  for(let pass=2;pass<=5;pass++){
   await pool.query("UPDATE drivy.push_notification SET available_at=now() WHERE person_id=$1 AND series_id=$2 AND category='CHANGE'",[id.alice,context.series.id]);
   await processPushBatch(worker,answering('RETRY'));
  }
  row=await notification(id.alice,context.series.id,'CHANGE');
  expect(row).toMatchObject({status:'FAILED',attempts:5,failure_code:'APNS_UNAVAILABLE',sent_at:null});
  await expectConfirmed(context);
 });

 it('service d’envoi qui lève une exception : le passage est annulé, la notification reste à envoyer, l’inscription est intacte',async()=>{
  const context=await enrolled(true);
  await expect(processPushBatch(worker,unreachable)).rejects.toThrow('APNs injoignable');
  expect(await notification(id.alice,context.series.id,'CHANGE')).toMatchObject({status:'PENDING',attempts:0,sent_at:null});
  await expectConfirmed(context);
 });
});

describe('#40 proposition de place : visible et acceptable sans push',()=>{
 it.each([
  {name:'jeton refusé',sender:answering('INVALID_TOKEN'),expected:{status:'FAILED',failure_code:'NO_VALID_DEVICE'}},
  {name:'APNs indisponible',sender:answering('RETRY'),expected:{status:'PENDING',failure_code:null}},
 ])('$name : la proposition reste visible, aucune inscription cachée, l’acceptation aboutit',async({sender,expected})=>{
  const series=await published(1);
  const holder=(await call('POST',`/course-series/${series.id}/enroll`,{operationId:randomUUID()},null,'demo-alice')).json().data.me.enrollment;
  expect((await call('POST',`/course-series/${series.id}/waitlist`,{operationId:randomUUID()},null,'demo-bob')).statusCode).toBe(201);
  await registerDevice('demo-bob',id.bob);
  expect((await call('POST',`/course-enrollments/${holder.id}/cancel`,{operationId:randomUUID()},holder.version,'demo-alice')).statusCode).toBe(200);
  await processPushBatch(worker,sender);
  const offerNotification=await notification(id.bob,series.id,'OFFER');
  expect(offerNotification).toMatchObject(expected);expect(offerNotification.sent_at).toBeNull();   // jamais marquée envoyée à tort
  // Lue dans l'app : proposition présente, place retenue pour elle seule, pas d'inscription tant qu'elle n'a pas répondu.
  const view=(await call('GET',`/course-series/${series.id}/me`,undefined,null,'demo-bob')).json().data;
  expect(view.me.state).toBe('OFFERED');expect(view.me.offer.id).toBeTruthy();expect(view.series.seatsTaken).toBe(1);
  expect((await pool.query<{n:number}>('SELECT count(*)::int AS n FROM drivy.course_enrollment WHERE series_id=$1 AND learner_id=$2',[series.id,id.bobLearner])).rows[0]!.n).toBe(0);
  const accepted=await call('POST',`/course-offers/${view.me.offer.id}/accept`,{operationId:randomUUID()},null,'demo-bob');
  expect(accepted.statusCode,accepted.body).toBe(201);expect(accepted.json().data.me.state).toBe('ENROLLED');
  expect(await activeEnrollments(series.id)).toBe(1);
  // L'échec de livraison n'est pas rejoué comme un succès après l'acceptation.
  expect((await notification(id.bob,series.id,'OFFER')).sent_at).toBeNull();
 });
});
