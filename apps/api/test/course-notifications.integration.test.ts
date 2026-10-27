import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,type Call} from './support/harness.js';
import {processPushBatch,pushConfig,type PushSender} from '../src/course-push.js';

/**
 * Notifications des cours (#43, #44, #40). Données synthétiques. L'envoi APNs réel est remplacé par un expéditeur de
 * test : sans clés Apple, aucune preuve de livraison réelle n'est revendiquée.
 */
let pool:Pool,worker:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));await prepareSchool(pool);
 worker=new Pool({connectionString:process.env.TEST_DATABASE_URL,options:'-c role=drivy_harness_migrator'});});
afterAll(async()=>{await app?.close();await worker?.end();await pool?.end();});

let cursor=10;
const at=(offset:number,hourUtc:number)=>{const d=new Date();d.setUTCDate(d.getUTCDate()+offset);d.setUTCHours(hourUtc,0,0,0);return d.toISOString();};
async function published(capacity=1,typeId?:string,minParticipants:number|null=null){
 const type=typeId??(await call('POST','/course-types',{operationId:randomUUID(),title:`Type ${randomUUID()}`,description:''},null,'demo-admin')).json().data.id;
 const start=cursor+=4;
 const draft=(await call('POST','/course-series',{operationId:randomUUID(),typeId:type,title:'Cours notifié',description:'',location:'',conditions:'',teachingLanguage:null,
  responsibleMembershipId:id.adminMember,capacity,minParticipants,timeZone:'Europe/Zurich',occurrences:[{startsAt:at(start,8),endsAt:at(start,11),instructorMembershipId:id.otherInstructorMember,attendanceRequired:true}]},null,'demo-admin')).json().data;
 const pub=(await call('POST',`/course-series/${draft.id}/publish`,{operationId:randomUUID()},draft.version,'demo-admin')).json().data;
 return {...pub,typeId:type} as {id:string;version:number;typeId:string};
}
const tick=()=>processPushBatch(worker,undefined);
const queued=async(person:string)=>(await pool.query<{category:string;dedupe_key:string;status:string}>('SELECT category,dedupe_key,status FROM drivy.push_notification WHERE person_id=$1 ORDER BY created_at',[person])).rows;
const device=(subject:string,token=randomUUID().replace(/-/g,'').repeat(2))=>call('PUT','/v1/me/push-devices',{token,environment:'SANDBOX'} as never,null,subject);

describe('valeurs de file par défaut (approuvées le 24 octobre 2026)',()=>{
 it('sans politique enregistrée : file active, échéance 12 h au plus et 2 h avant la séance',async()=>{
  const s=await published(1);
  const holder=(await call('POST',`/course-series/${s.id}/enroll`,{operationId:randomUUID()},null,'demo-alice')).json().data.me.enrollment;
  expect((await call('POST',`/course-series/${s.id}/waitlist`,{operationId:randomUUID()},null,'demo-bob')).statusCode).toBe(201);
  await call('POST',`/course-enrollments/${holder.id}/cancel`,{operationId:randomUUID()},holder.version,'demo-alice');
  const offer=(await call('GET',`/course-series/${s.id}/me`,undefined,null,'demo-bob')).json().data.me.offer;
  const remaining=Date.parse(offer.expiresAt)-Date.now();
  expect(remaining).toBeGreaterThan(11.9*3_600_000);expect(remaining).toBeLessThanOrEqual(12*3_600_000+5_000);
 });
});

describe('#43 tick : expiration autonome, ciblage, rappels, minimum',()=>{
 it('une proposition échue passe au suivant sans action d’utilisateur ; seul le destinataire est notifié',async()=>{
  const s=await published(1);
  const holder=(await call('POST',`/course-series/${s.id}/enroll`,{operationId:randomUUID()},null,'demo-alice')).json().data.me.enrollment;
  await call('POST',`/course-series/${s.id}/waitlist`,{operationId:randomUUID()},null,'demo-bob');
  await call('POST',`/course-enrollments/${holder.id}/cancel`,{operationId:randomUUID()},holder.version,'demo-alice');
  await call('POST',`/course-series/${s.id}/waitlist`,{operationId:randomUUID()},null,'demo-alice').catch(()=>undefined);
  await tick();
  const offersOf=async(person:string)=>(await pool.query<{status:string}>("SELECT status FROM drivy.push_notification WHERE person_id=$1 AND category='OFFER' AND series_id=$2",[person,s.id])).rows;
  expect(await offersOf(id.bob)).toHaveLength(1);
  expect(await offersOf(id.alice)).toHaveLength(0);
  // Échéance dépassée : expiration par le service, notification périmée jamais envoyée.
  await pool.query("UPDATE drivy.course_seat_offer SET offered_at=now()-interval '13 hours',expires_at=now()-interval '1 minute' WHERE series_id=$1 AND status='ACTIVE'",[s.id]);
  await tick();
  expect((await pool.query("SELECT status FROM drivy.course_seat_offer WHERE series_id=$1 ORDER BY offered_at LIMIT 1",[s.id])).rows[0].status).toBe('EXPIRED');
  expect((await offersOf(id.bob))[0]!.status).toBe('EXPIRED');
 });
 it('rappels 24 h et 2 h une seule fois, alerte de minimum au responsable, sans annulation automatique',async()=>{
  const s=await published(5,undefined,3);
  await call('POST',`/course-series/${s.id}/enroll`,{operationId:randomUUID()},null,'demo-alice');
  await pool.query("UPDATE drivy.course_occurrence SET starts_at=now()+interval '90 minutes',ends_at=now()+interval '3 hours' WHERE series_id=$1",[s.id]);
  await tick();await tick();
  const reminders=(await queued(id.alice)).filter(n=>n.category==='REMINDER');
  expect(reminders.map(n=>n.dedupe_key.split(':')[1]).sort()).toEqual(['H2','H24']);
  expect((await queued(id.admin)).filter(n=>n.category==='STAFF')).toHaveLength(1);
  expect((await pool.query('SELECT status FROM drivy.course_series WHERE id=$1',[s.id])).rows[0].status).toBe('PUBLISHED');
 });
});

describe('#44 préférences et #40 abonnement',()=>{
 it.each([false,true])('deux appareils sur la même version : une seule écriture, ligne existante=%s',async(existing)=>{
  await pool.query('DELETE FROM drivy.notification_preference WHERE person_id=$1',[id.bob]);
  const initial={courseOffers:true,courseReminders:true,courseChanges:true,courseStaffAlerts:true};
  if(existing)expect((await call('PUT','/v1/me/notification-preferences',initial as never,1,'demo-bob')).statusCode).toBe(200);
  const before=(await call('GET','/v1/me/notification-preferences',undefined,null,'demo-bob')).json().data;
  const choices=[{...initial,courseOffers:false},{...initial,courseReminders:false}];
  // Hold the owner so both API transactions have reached the same contention point.
  const blocker=await pool.connect();await blocker.query('BEGIN');
  await blocker.query('SELECT id FROM drivy.person WHERE id=$1 FOR UPDATE',[id.bob]);
  const requests=choices.map(body=>call('PUT','/v1/me/notification-preferences',body as never,before.version,'demo-bob'));
  try{
   // Both route transactions must wait for the owner's lock before reading the preference version.
   const deadline=Date.now()+5_000;
   while(Date.now()<deadline){
    const waiting=await pool.query<{n:number}>(`SELECT count(*)::int AS n FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%drivy.person%FOR UPDATE%'`);
    if(waiting.rows[0]!.n>=2)break;
    await new Promise(resolve=>setTimeout(resolve,10));
   }
  }finally{await blocker.query('COMMIT');blocker.release();}
  const results=await Promise.all(requests);
  expect(results.map(result=>result.statusCode).sort()).toEqual([200,412]);
  const winner=results.findIndex(result=>result.statusCode===200);
  const after=(await call('GET','/v1/me/notification-preferences',undefined,null,'demo-bob')).json().data;
  expect(after).toEqual({...choices[winner],version:before.version+1});
  // Preserve the default fixture for the following notification targeting scenarios.
  expect((await call('PUT','/v1/me/notification-preferences',initial as never,after.version,'demo-bob')).statusCode).toBe(200);
 });
 it('préférence désactivée : aucune notification de cette catégorie, l’information reste consultable',async()=>{
  const prefs=await call('GET','/v1/me/notification-preferences',undefined,null,'demo-bob');
  expect(prefs.json().data).toMatchObject({courseOffers:true,courseReminders:true});
  const saved=await call('PUT','/v1/me/notification-preferences',{courseOffers:true,courseReminders:false,courseChanges:true,courseStaffAlerts:true} as never,prefs.json().data.version,'demo-bob');
  expect(saved.statusCode,saved.body).toBe(200);
  expect((await call('PUT','/v1/me/notification-preferences',{courseOffers:true,courseReminders:true,courseChanges:true,courseStaffAlerts:true} as never,prefs.json().data.version,'demo-bob')).statusCode).toBe(412);
  const s=await published(5);
  await call('POST',`/course-series/${s.id}/enroll`,{operationId:randomUUID()},null,'demo-bob');
  await pool.query("UPDATE drivy.course_occurrence SET starts_at=now()+interval '90 minutes',ends_at=now()+interval '3 hours' WHERE series_id=$1",[s.id]);
  await tick();
  expect((await queued(id.bob)).some(n=>n.category==='REMINDER')).toBe(false);
  expect((await call('GET',`/course-series/${s.id}/me`,undefined,null,'demo-bob')).json().data.me.state).toBe('ENROLLED');
 });
 it('nouvelle session : seulement aux abonnés, révocable, sans inscription ni file',async()=>{
  const type=(await call('POST','/course-types',{operationId:randomUUID(),title:`Suivi ${randomUUID()}`,description:''},null,'demo-admin')).json().data.id;
  expect((await call('PUT',`/course-follows/me/${type}`.replace('/course','/v1/schools/'+id.schoolA+'/course'),undefined,null,'demo-alice')).statusCode).toBe(200);
  const s=await published(5,type);
  await tick();
  expect((await queued(id.alice)).filter(n=>n.category==='NEW_SESSION').map(n=>n.dedupe_key)).toEqual([`CourseSeriesPublished:${s.id}`]);
  expect((await queued(id.bob)).some(n=>n.dedupe_key===`CourseSeriesPublished:${s.id}`)).toBe(false);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.course_enrollment WHERE series_id=$1',[s.id])).rows[0].n).toBe(0);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.course_waitlist_entry WHERE series_id=$1',[s.id])).rows[0].n).toBe(0);
  await call('POST',`/v1/schools/${id.schoolA}/course-follows/me/${type}/unfollow`,undefined,null,'demo-alice');
  await published(5,type);await tick();
  expect((await queued(id.alice)).filter(n=>n.category==='NEW_SESSION')).toHaveLength(1);
 });
});

describe('envoi : appareils, échecs, jetons invalides',()=>{
 it('jeton jamais relu par l’app ; échec retenté puis abandonné ; jeton invalide révoqué ; aucun appareil = ignoré',async()=>{
  const token='ab'.repeat(32);
  expect((await device('demo-alice',token)).statusCode).toBe(200);
  await expect(pool.query("SET ROLE drivy_app; SELECT token FROM drivy.push_device")).rejects.toThrow();
  await pool.query('RESET ROLE');
  await pool.query(`INSERT INTO drivy.push_notification(person_id,school_id,category,dedupe_key,title,body) VALUES($1,$2,'CHANGE','test:retry','T','B'),($3,$2,'CHANGE','test:nodevice','T','B')`,[id.alice,id.schoolA,id.bob]);
  let result:'RETRY'|'INVALID_TOKEN'|'SENT'='RETRY';
  const sender:PushSender={send:async()=>result,close(){}};
  await processPushBatch(worker,sender);
  expect((await pool.query("SELECT status,attempts FROM drivy.push_notification WHERE dedupe_key='test:retry'")).rows[0]).toMatchObject({status:'PENDING',attempts:1});
  expect((await pool.query("SELECT status FROM drivy.push_notification WHERE dedupe_key='test:nodevice'")).rows[0].status).toBe('SKIPPED');
  result='INVALID_TOKEN';
  await pool.query("UPDATE drivy.push_notification SET available_at=now() WHERE dedupe_key='test:retry'");
  await processPushBatch(worker,sender);
  expect((await pool.query('SELECT revoked_at FROM drivy.push_device WHERE token=$1',[token])).rows[0].revoked_at).not.toBeNull();
  expect((await pool.query("SELECT status FROM drivy.push_notification WHERE dedupe_key='test:retry'")).rows[0].status).toBe('FAILED');
 });
 it('configuration APNs incomplète refusée ; absente = pas d’envoi',()=>{
  expect(pushConfig({})).toBeUndefined();
  expect(()=>pushConfig({APNS_KEY_ID:'ABC'})).toThrow();
 });
});
