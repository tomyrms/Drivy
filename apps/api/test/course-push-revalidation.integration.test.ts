import {randomUUID} from 'node:crypto';
import {afterEach,beforeEach,describe,expect,it} from 'vitest';
import {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,type Call} from './support/harness.js';
import {processPushBatch,type PushSender} from '../src/course-push.js';

/**
 * Régressions entre mise en attente et envoi : vraie PostgreSQL, routes métier réelles et données synthétiques.
 * Seules les dates sont déplacées en SQL. Le transport est un collecteur local, jamais une connexion APNs.
 * Chaque test recrée drivy_test via le harness : ne jamais utiliser une base de production.
 */
let pool:Pool,worker:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
beforeEach(async()=>{
 pool=await freshDatabase();({call,app}=await harness(pool));await prepareSchool(pool);
 // Le propriétaire non privilégié peut SET ROLE, contrairement à un test qui contournerait les ACL par superuser.
 worker=new Pool({connectionString:process.env.TEST_DATABASE_URL,options:'-c role=drivy_harness_migrator'});
});
afterEach(async()=>{await app?.close();await worker?.end();await pool?.end();});

type Series={id:string;version:number;typeId:string};
type Notification={id:string;category:string;dedupe_key:string;status:string;failure_code:string|null;attempts:number;sent_at:Date|null};
const at=(day:number,hour:number)=>{const date=new Date();date.setUTCDate(date.getUTCDate()+day);date.setUTCHours(hour,0,0,0);return date.toISOString();};
async function api(method:Parameters<Call>[0],route:string,body?:Record<string,unknown>,version:number|null=null,subject='demo-admin',status=200){
 const response=await call(method,route,body,version,subject);
 expect(response.statusCode,response.body).toBe(status);
 return response.json().data;
}
async function published(typeId?:string,day=10):Promise<Series>{
 typeId??=(await api('POST','/course-types',{operationId:randomUUID(),title:`Type synthétique ${randomUUID()}`,description:''},null,'demo-admin',201)).id;
 const draft=await api('POST','/course-series',{operationId:randomUUID(),typeId,title:'Cours synthétique',description:'',location:'',conditions:'',teachingLanguage:null,
  responsibleMembershipId:id.adminMember,capacity:5,minParticipants:null,timeZone:'Europe/Zurich',occurrences:[{startsAt:at(day,8),endsAt:at(day,11),instructorMembershipId:id.otherInstructorMember,attendanceRequired:true}]},null,'demo-admin',201);
 const series=await api('POST',`/course-series/${draft.id}/publish`,{operationId:randomUUID()},draft.version);
 return {...series,typeId};
}
async function followedSession(){
 const type=await api('POST','/course-types',{operationId:randomUUID(),title:`Suivi synthétique ${randomUUID()}`,description:''},null,'demo-admin',201);
 await api('PUT',`/v1/schools/${id.schoolA}/course-follows/me/${type.id}`,undefined,null,'demo-alice');
 return published(type.id);
}
async function enroll(series:Series){
 const data=await api('POST',`/course-series/${series.id}/enroll`,{operationId:randomUUID()},null,'demo-alice',201);
 series.version=data.series.version;
 return data.me.enrollment as {id:string;version:number};
}
async function registerDevice(){
 await api('PUT','/v1/me/push-devices',{token:'ab'.repeat(32),environment:'SANDBOX'},null,'demo-alice');
}
async function preferences(enabled:boolean){
 const previous=await api('GET','/v1/me/notification-preferences',undefined,null,'demo-alice');
 await api('PUT','/v1/me/notification-preferences',{courseOffers:enabled,courseReminders:enabled,courseChanges:enabled,courseStaffAlerts:enabled},previous.version,'demo-alice');
}
async function notifications(series:Series,category?:string){
 return (await pool.query<Notification>(`SELECT id,category,dedupe_key,status,failure_code,attempts,sent_at FROM drivy.push_notification
  WHERE person_id=$1 AND series_id=$2 AND ($3::text IS NULL OR category=$3) ORDER BY dedupe_key`,[id.alice,series.id,category??null])).rows;
}
async function pending(series:Series,category:string,count=1){
 expect(await processPushBatch(worker,undefined)).toBe(0);
 const rows=await notifications(series,category);
 expect(rows).toHaveLength(count);
 for(const row of rows)expect(row).toMatchObject({status:'PENDING',attempts:0,sent_at:null});
 return rows;
}
function transport(){
 const delivered:{category:string;seriesId:string;collapseId:string}[]=[];
 const sender:PushSender={send:async(_token,_environment,payload,_expiresAt,collapseId)=>{
  const message=payload as {category:string;seriesId:string};delivered.push({category:message.category,seriesId:message.seriesId,collapseId});return 'SENT';
 },close(){}};
 return {sender,delivered};
}
async function reminders(){
 const series=await published(),enrollment=await enroll(series);
 // Horloge SQL réelle : deux rappels dus sans attente ni mock global de Date.
 await pool.query("UPDATE drivy.course_occurrence SET starts_at=now()+interval '90 minutes',ends_at=now()+interval '3 hours' WHERE series_id=$1",[series.id]);
 await pending(series,'REMINDER',2);
 return {series,enrollment};
}
async function revalidate(notificationId:string){
 const db=await worker.connect();
 try{
  await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_course_worker');
  const result=await db.query<{allowed:boolean}>('SELECT drivy.course_push_revalidate($1::uuid) AS allowed',[notificationId]);
  await db.query('COMMIT');return result.rows[0]!.allowed;
 }catch(error){await db.query('ROLLBACK');throw error;}finally{db.release();}
}
async function expectSuppressed(series:Series,category:string,count=1){
 const rows=await notifications(series,category);expect(rows).toHaveLength(count);
 for(const row of rows){expect(['SKIPPED','EXPIRED']).toContain(row.status);expect(row).toMatchObject({attempts:0,sent_at:null});}
}

describe('revalidation métier juste avant le transport',()=>{
 it.each(['REMINDER','NEW_SESSION'] as const)('%s PENDING puis préférences désactivées : SKIPPED PREFERENCE_DISABLED et aucun envoi',async category=>{
  await registerDevice();
  const series=category==='REMINDER'?(await reminders()).series:await followedSession();
  if(category==='NEW_SESSION')await pending(series,category);
  await preferences(false);
  const {sender,delivered}=transport();await processPushBatch(worker,sender);
  expect(delivered).toEqual([]);
  const rows=await notifications(series,category);expect(rows).toHaveLength(category==='REMINDER'?2:1);
  for(const row of rows)expect(row).toMatchObject({status:'SKIPPED',failure_code:'PREFERENCE_DISABLED',attempts:0,sent_at:null});
  // Réactiver ne ressuscite pas les annonces supprimées.
  await preferences(true);await processPushBatch(worker,sender);expect(delivered).toEqual([]);
 });

 it('NEW_SESSION PENDING puis désabonnement : aucune annonce, même avec un appareil actif',async()=>{
  await registerDevice();const series=await followedSession();await pending(series,'NEW_SESSION');
  await api('POST',`/v1/schools/${id.schoolA}/course-follows/me/${series.typeId}/unfollow`,undefined,null,'demo-alice');
  const {sender,delivered}=transport();await processPushBatch(worker,sender);
  expect(delivered).toEqual([]);await expectSuppressed(series,'NEW_SESSION');
 });

 it('NEW_SESSION PENDING puis validation du même type sur une autre série : aucune annonce',async()=>{
  await registerDevice();const series=await followedSession();await pending(series,'NEW_SESSION');
  // La validation passe par présence + commande métier, pas par un INSERT de completion.
  const held=await published(series.typeId,20),enrollment=await enroll(held);
  await pool.query("UPDATE drivy.course_occurrence SET starts_at=now()-interval '3 hours',ends_at=now()-interval '1 hour' WHERE series_id=$1",[held.id]);
  const sheet=await api('GET',`/course-series/${held.id}/sheet`);
  await api('PUT',`/course-enrollments/${enrollment.id}/attendance/${sheet.series.occurrences[0].id}`,{operationId:randomUUID(),status:'PRESENT',expectedVersion:null,note:null});
  await api('POST',`/course-enrollments/${enrollment.id}/validate`,{operationId:randomUUID(),note:null},null,'demo-admin',201);
  expect((await api('GET',`/course-series/${series.id}/me`,undefined,null,'demo-alice')).me.state).toBe('COMPLETED');
  const {sender,delivered}=transport();await processPushBatch(worker,sender);
  expect(delivered.filter(n=>n.category==='NEW_SESSION')).toEqual([]);await expectSuppressed(series,'NEW_SESSION');
 });

 it.each(['series','enrollment'] as const)('REMINDER PENDING puis annulation %s : rappels supprimés, CHANGE d’annulation envoyé',async kind=>{
  await registerDevice();const {series,enrollment}=await reminders();
  if(kind==='series')await api('POST',`/course-series/${series.id}/cancel`,{operationId:randomUUID(),reason:'Annulation synthétique'},series.version);
  else await api('POST',`/course-enrollments/${enrollment.id}/staff-cancel`,{operationId:randomUUID(),reason:'Annulation synthétique'},enrollment.version);
  const {sender,delivered}=transport();await processPushBatch(worker,sender);
  expect(delivered.filter(n=>n.category==='REMINDER')).toEqual([]);await expectSuppressed(series,'REMINDER',2);
  const cancellationPrefix=kind==='series'?'CourseSeriesCancelled:':'CourseEnrollmentCancelled:';
  const cancellations=(await notifications(series,'CHANGE')).filter(n=>n.dedupe_key.startsWith(cancellationPrefix));
  expect(cancellations).toHaveLength(1);expect(cancellations[0]).toMatchObject({status:'SENT',attempts:1});
  expect(cancellations[0]!.sent_at).not.toBeNull();
  expect(delivered.some(n=>n.category==='CHANGE'&&n.collapseId===cancellations[0]!.dedupe_key)).toBe(true);
 });

 it('annonce toujours admissible : envoi unique et état durable SENT',async()=>{
  await registerDevice();const series=await followedSession();await pending(series,'NEW_SESSION');
  const {sender,delivered}=transport();await processPushBatch(worker,sender);await processPushBatch(worker,sender);
  expect(delivered).toEqual([{category:'NEW_SESSION',seriesId:series.id,collapseId:`CourseSeriesPublished:${series.id}`}]);
  const rows=await notifications(series,'NEW_SESSION');expect(rows).toHaveLength(1);
  expect(rows[0]).toMatchObject({status:'SENT',attempts:1});expect(rows[0]!.sent_at).not.toBeNull();
 });
});

describe('replanification et confirmations devenues fausses',()=>{
 const later=(_series:{id:string},day:number)=>({operationId:randomUUID(),occurrences:[{position:1,startsAt:at(day,8),endsAt:at(day,11),instructorMembershipId:id.otherInstructorMember}]});
 async function current(series:Series){return (await api('GET',`/course-series/${series.id}/sheet`)).series.version as number;}

 it('offre révoquée par replanification puis réémise : la nouvelle offre est notifiée',async()=>{
  await registerDevice();
  const type=(await api('POST','/course-types',{operationId:randomUUID(),title:`File ${randomUUID()}`,description:''},null,'demo-admin',201)).id;
  const draft=await api('POST','/course-series',{operationId:randomUUID(),typeId:type,title:'Cours file',description:'',location:'',conditions:'',teachingLanguage:null,
   responsibleMembershipId:id.adminMember,capacity:1,minParticipants:null,timeZone:'Europe/Zurich',occurrences:[{startsAt:at(10,8),endsAt:at(10,11),instructorMembershipId:id.otherInstructorMember,attendanceRequired:true}]},null,'demo-admin',201);
  const series={...(await api('POST',`/course-series/${draft.id}/publish`,{operationId:randomUUID()},draft.version)),typeId:type} as Series;
  const holder=(await api('POST',`/course-series/${series.id}/enroll`,{operationId:randomUUID()},null,'demo-bob',201)).me.enrollment;
  await api('POST',`/course-series/${series.id}/waitlist`,{operationId:randomUUID()},null,'demo-alice',201);
  await api('POST',`/course-enrollments/${holder.id}/cancel`,{operationId:randomUUID()},holder.version,'demo-bob');
  await pending(series,'OFFER');
  await api('POST',`/course-series/${series.id}/reschedule`,later(series,12),await current(series),'demo-admin');
  const {sender,delivered}=transport();await processPushBatch(worker,sender);
  // La place a bien été reproposée : sa notification doit partir, l'ancienne jamais.
  expect((await api('GET',`/course-series/${series.id}/me`,undefined,null,'demo-alice')).me.offer).not.toBeNull();
  expect(delivered.filter(n=>n.category==='OFFER')).toHaveLength(1);
  const offers=await notifications(series,'OFFER');
  expect(offers.filter(n=>n.status==='SENT')).toHaveLength(1);
  expect(offers.filter(n=>n.status==='PENDING')).toHaveLength(0);
 });

 it('rappel après replanification : nouveau rappel pour le nouvel horaire, ancien supprimé',async()=>{
  await registerDevice();const {series}=await reminders();
  const {sender,delivered}=transport();await processPushBatch(worker,sender);
  expect(delivered.filter(n=>n.category==='REMINDER')).toHaveLength(2);
  const moved=new Date(Date.now()+100*60_000);
  await api('POST',`/course-series/${series.id}/reschedule`,{operationId:randomUUID(),occurrences:[{position:1,startsAt:moved.toISOString(),endsAt:new Date(moved.getTime()+3_600_000).toISOString(),instructorMembershipId:id.otherInstructorMember}]},await current(series),'demo-admin');
  await processPushBatch(worker,sender);
  expect(delivered.filter(n=>n.category==='REMINDER')).toHaveLength(4);
 });

 it('inscription confirmée PENDING puis annulée avant envoi : pas de confirmation',async()=>{
  await registerDevice();const series=await published(),enrollment=await enroll(series);
  await pending(series,'CHANGE');
  await api('POST',`/course-enrollments/${enrollment.id}/staff-cancel`,{operationId:randomUUID(),reason:'Annulation synthétique'},enrollment.version);
  const {sender,delivered}=transport();await processPushBatch(worker,sender);
  const rows=await notifications(series,'CHANGE');
  expect(rows.find(n=>n.dedupe_key.startsWith('CourseEnrolled:'))).toMatchObject({status:'SKIPPED',failure_code:'EVENT_OBSOLETE'});
  expect(delivered.filter(n=>n.category==='CHANGE')).toHaveLength(1);
 });
});

describe('fonction étroite course_push_revalidate(uuid) réservée au worker',()=>{
 it('worker sans SELECT métier : fonction boolean SECURITY DEFINER, autorisée au worker mais pas à l’app',async()=>{
  const db=await worker.connect();
  try{
   await db.query('SET ROLE drivy_course_worker');
   expect((await db.query('SELECT current_user AS role')).rows[0].role).toBe('drivy_course_worker');
   for(const table of ['course_series','course_occurrence','course_enrollment','course_type_follow','course_completion','learner_profile','membership']){
    expect((await db.query('SELECT has_table_privilege(current_user,$1,\'SELECT\') AS allowed',[`drivy.${table}`])).rows[0].allowed,table).toBe(false);
    await expect(db.query(`SELECT * FROM drivy.${table} LIMIT 1`)).rejects.toMatchObject({code:'42501'});
   }
   const metadata=(await db.query(`SELECT p.prosecdef AS definer,p.prorettype='boolean'::regtype AS boolean_result,
    has_function_privilege('drivy_course_worker',p.oid,'EXECUTE') AS worker_execute,
    has_function_privilege('drivy_app',p.oid,'EXECUTE') AS app_execute
    FROM pg_proc p WHERE p.oid=to_regprocedure('drivy.course_push_revalidate(uuid)')`)).rows;
   expect(metadata).toEqual([{definer:true,boolean_result:true,worker_execute:true,app_execute:false}]);
  }finally{await db.query('RESET ROLE');db.release();}
  const series=await followedSession(),[notification]=await pending(series,'NEW_SESSION');
  expect(await revalidate(notification!.id)).toBe(true);
  expect((await notifications(series,'NEW_SESSION'))[0]).toMatchObject({status:'PENDING',attempts:0,sent_at:null});
 });

 it('false persiste SKIPPED PREFERENCE_DISABLED sans tick ni transport',async()=>{
  const series=await followedSession(),[notification]=await pending(series,'NEW_SESSION');await preferences(false);
  expect(await revalidate(notification!.id)).toBe(false);
  expect((await notifications(series,'NEW_SESSION'))[0]).toMatchObject({status:'SKIPPED',failure_code:'PREFERENCE_DISABLED',attempts:0,sent_at:null});
  expect(await revalidate(notification!.id)).toBe(false);
 });

 it('échéance dépassée : false persiste EXPIRED sans dépendre du tick précédent',async()=>{
  const {series}=await reminders(),rows=await notifications(series,'REMINDER');
  await pool.query("UPDATE drivy.push_notification SET valid_until=now()-interval '1 second' WHERE id=$1",[rows[0]!.id]);
  expect(await revalidate(rows[0]!.id)).toBe(false);
  expect((await notifications(series,'REMINDER')).find(n=>n.id===rows[0]!.id)).toMatchObject({status:'EXPIRED',attempts:0,sent_at:null});
 });

 it('identifiant inconnu ou notification déjà envoyée : false, sans réécrire SENT',async()=>{
  expect(await revalidate(randomUUID())).toBe(false);
  await registerDevice();const series=await followedSession(),[notification]=await pending(series,'NEW_SESSION');
  const {sender}=transport();await processPushBatch(worker,sender);
  const before=(await notifications(series,'NEW_SESSION'))[0];expect(before!.status).toBe('SENT');
  expect(await revalidate(notification!.id)).toBe(false);
  expect((await notifications(series,'NEW_SESSION'))[0]).toEqual(before);
 });
});
