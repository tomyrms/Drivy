import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,type Call} from './support/harness.js';
import {collapseIdFor,processPushBatch,type PushSender} from '../src/course-push.js';

/**
 * Lot G de l'audit du 10 novembre 2026 (#429 identité des notifications d'événement, #448 état d'envoi par destination).
 * PostgreSQL réelle, données synthétiques, transport APNs remplacé par un expéditeur scripté : aucune livraison réelle n'est
 * revendiquée. Le « redémarrage du service » est rejoué en refermant le Pool du service et en en ouvrant un nouveau :
 * l'état des destinations ne vit que dans la base. Le chemin messagerie est couvert dans messaging-push-multidevice-448.
 */
let pool:Pool,worker:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
const workerPool=()=>new Pool({connectionString:process.env.TEST_DATABASE_URL,options:'-c role=drivy_harness_migrator'});
beforeAll(async()=>{
 pool=await freshDatabase();({call,app}=await harness(pool));await prepareSchool(pool);worker=workerPool();
});
afterAll(async()=>{await app?.close();await worker?.end();await pool?.end();});
/** Arrêt normal du service puis démarrage d'un nouveau : plus aucune mémoire de processus. */
const restartWorker=async()=>{await worker.end();worker=workerPool();};

const at=(offset:number,hourUtc:number)=>{const d=new Date();d.setUTCDate(d.getUTCDate()+offset);d.setUTCHours(hourUtc,0,0,0);return d.toISOString();};
let cursor=10;
const schoolBase=(school:string)=>`/v1/schools/${school}`;
async function published(school:string=id.schoolA,instructorMembership:string=id.otherInstructorMember,admin:string='demo-admin',responsible:string=id.adminMember){
 const base=schoolBase(school);
 const type=(await call('POST',`${base}/course-types`,{operationId:randomUUID(),title:`Type ${randomUUID()}`,description:''},null,admin)).json().data.id;
 const start=cursor+=4;
 const created=await call('POST',`${base}/course-series`,{operationId:randomUUID(),typeId:type,title:'Cours notifié',description:'',location:'Salle',conditions:'',teachingLanguage:null,
  responsibleMembershipId:responsible,capacity:5,minParticipants:null,timeZone:'Europe/Zurich',
  occurrences:[{startsAt:at(start,8),endsAt:at(start,11),instructorMembershipId:instructorMembership,attendanceRequired:true}]},null,admin);
 if(created.statusCode!==201)throw new Error(created.body);
 const res=await call('POST',`${base}/course-series/${created.json().data.id}/publish`,{operationId:randomUUID()},created.json().data.version,admin);
 if(res.statusCode!==200)throw new Error(res.body);
 return {...res.json().data as {id:string;version:number},start,base,admin};
}
async function enroll(series:{id:string;base:string},subject:string){
 const res=await call('POST',`${series.base}/course-series/${series.id}/enroll`,{operationId:randomUUID()},null,subject);
 expect(res.statusCode,res.body).toBe(201);
}
const current=async(series:{id:string;base:string;admin?:string})=>(await call('GET',`${series.base}/course-series/${series.id}`,undefined,null,series.admin??'demo-admin')).json().data as {version:number};
async function cancel(series:{id:string;base:string;admin?:string}){
 const res=await call('POST',`${series.base}/course-series/${series.id}/cancel`,{operationId:randomUUID(),reason:'Recette'},(await current(series)).version,series.admin??'demo-admin');
 expect(res.statusCode,res.body).toBe(200);
}
async function reschedule(series:{id:string;base:string;start:number;admin?:string}){
 const res=await call('POST',`${series.base}/course-series/${series.id}/reschedule`,{operationId:randomUUID(),
  occurrences:[{position:1,startsAt:at(series.start+1,9),endsAt:at(series.start+1,12),instructorMembershipId:id.otherInstructorMember}]},(await current(series)).version,series.admin??'demo-admin');
 expect(res.statusCode,res.body).toBe(200);
}
const tick=async()=>{const db=await worker.connect();try{await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_course_worker');await db.query('SELECT drivy.course_notifications_tick()');await db.query('COMMIT');}finally{db.release();}};
type Row={id:string;dedupe_key:string;status:string;attempts:number;failure_code:string|null;school_id:string;available_at:Date;sent_at:Date|null};
const forPerson=async(person:string,like:string)=>(await pool.query<Row>('SELECT id,dedupe_key,status,attempts,failure_code,school_id,available_at,sent_at FROM drivy.push_notification WHERE person_id=$1 AND dedupe_key LIKE $2 ORDER BY created_at,dedupe_key',[person,like])).rows;
const eventVersions=async(type:string,series:string[])=>(await pool.query<{series_version:number}>('SELECT series_version FROM drivy.course_event_outbox WHERE event_type=$1 AND series_id=ANY($2::uuid[]) ORDER BY series_id',[type,series])).rows.map(row=>row.series_version);

describe('#429 une notification logique par événement distinct',()=>{
 it('deux séries annulées à la même version : deux notifications ; le rejeu du même événement n’en crée aucune de plus',async()=>{
  const a=await published(),b=await published();
  await enroll(a,'demo-alice');await enroll(b,'demo-alice');
  await cancel(a);await cancel(b);
  const versions=await eventVersions('CourseSeriesCancelled',[a.id,b.id]);
  expect(versions).toHaveLength(2);expect(versions[0]).toBe(versions[1]);
  await tick();
  const rows=await forPerson(id.alice,'CourseSeriesCancelled:%');
  expect(rows.map(row=>row.dedupe_key).sort()).toEqual([`CourseSeriesCancelled:${a.id}:${versions[0]}`,`CourseSeriesCancelled:${b.id}:${versions[0]}`].sort());
  // Rejeux : tick répété, puis événements remis « non traités » (reprise après incident) : même identité, donc même résultat.
  await tick();await pool.query("UPDATE drivy.course_event_outbox SET delivered_at=NULL WHERE event_type='CourseSeriesCancelled' AND series_id=ANY($1::uuid[])",[[a.id,b.id]]);
  await tick();await tick();
  expect(await forPerson(id.alice,'CourseSeriesCancelled:%')).toHaveLength(2);
 });
 it('deux séries replanifiées à la même version : deux notifications',async()=>{
  const a=await published(),b=await published();
  await enroll(a,'demo-alice');await enroll(b,'demo-alice');
  await reschedule(a);await reschedule(b);
  const versions=await eventVersions('CourseSeriesRescheduled',[a.id,b.id]);
  expect(versions[0]).toBe(versions[1]);
  await tick();await tick();
  const rows=(await forPerson(id.alice,'CourseSeriesRescheduled:%')).filter(row=>row.dedupe_key.includes(a.id)||row.dedupe_key.includes(b.id));
  expect(rows).toHaveLength(2);
  expect(new Set(rows.map(row=>row.dedupe_key)).size).toBe(2);
 });
 it('même personne autorisée dans deux écoles : une notification par école, chacune avec sa portée',async()=>{
  // Sacha est élève de l'école B ; elle devient aussi élève de l'école A (adhésion et dossier synthétiques).
  const membership=randomUUID(),learner=randomUUID();
  await pool.query("INSERT INTO drivy.membership(id,school_id,person_id,roles) VALUES($1,$2,$3,'{LEARNER}')",[membership,id.schoolA,id.foreign]);
  await pool.query("INSERT INTO drivy.learner_profile(id,school_id,person_id,created_at) VALUES($1,$2,$3,now())",[learner,id.schoolA,id.foreign]);
  await pool.query("UPDATE drivy.membership SET roles='{ADMIN,INSTRUCTOR}' WHERE id=$1",[id.instructorMemberB]);
  const inA=await published();
  const inB=await published(id.schoolB,id.instructorMemberB,'demo-instructor',id.instructorMemberB);
  await enroll(inA,'demo-foreign');await enroll(inB,'demo-foreign');
  await cancel(inA);await cancel(inB);
  const versions=await eventVersions('CourseSeriesCancelled',[inA.id,inB.id]);
  expect(versions[0]).toBe(versions[1]);
  await tick();
  const rows=await forPerson(id.foreign,'CourseSeriesCancelled:%');
  expect(rows.map(row=>row.school_id).sort()).toEqual([id.schoolA,id.schoolB].sort());
  expect(rows.find(row=>row.school_id===id.schoolA)!.dedupe_key).toContain(inA.id);
  expect(rows.find(row=>row.school_id===id.schoolB)!.dedupe_key).toContain(inB.id);
 });
 it('transition : une notification ancienne (clé type:version) n’est ni relue ni supprimée, et un événement distinct de même version n’est pas perdu',async()=>{
  const a=await published(),b=await published();
  await enroll(a,'demo-alice');await enroll(b,'demo-alice');
  await cancel(a);await tick();
  const [first]=await forPerson(id.alice,`CourseSeriesCancelled:${a.id}:%`);
  expect(first).toBeDefined();
  // État d'avant la migration : l'événement de a est traité, sa notification porte l'ancienne clé `type:version`.
  const legacyKey=`CourseSeriesCancelled:${(await eventVersions('CourseSeriesCancelled',[a.id]))[0]}`;
  await pool.query('UPDATE drivy.push_notification SET dedupe_key=$2 WHERE id=$1',[first!.id,legacyKey]);
  const before=(await pool.query<{n:number}>('SELECT count(*)::int AS n FROM drivy.push_notification')).rows[0]!.n;
  await tick();await tick();
  // Aucune réémission massive : les événements déjà traités ne sont pas rejoués.
  expect((await pool.query<{n:number}>('SELECT count(*)::int AS n FROM drivy.push_notification')).rows[0]!.n).toBe(before);
  expect(await forPerson(id.alice,legacyKey)).toHaveLength(1);
  // Un nouvel événement de même type et de même version (autre série) crée sa propre notification, sans heurter l'ancienne.
  await cancel(b);await tick();
  const fresh=await forPerson(id.alice,`CourseSeriesCancelled:${b.id}:%`);
  expect(fresh).toHaveLength(1);
  expect(await forPerson(id.alice,legacyKey)).toHaveLength(1);
 });
 it('l’identifiant de regroupement APNs reste unique même pour une clé longue',()=>{
  const longA=`CourseSeriesRescheduled:${randomUUID()}:12345`,longB=`CourseSeriesRescheduled:${randomUUID()}:12345`;
  expect(collapseIdFor('CourseEnrolled:x')).toBe('CourseEnrolled:x');
  expect(collapseIdFor(longA)).toHaveLength(64);
  expect(collapseIdFor(longA)).not.toBe(collapseIdFor(longB));
  expect(collapseIdFor(longA)).toBe(collapseIdFor(longA));
 });
});

describe('#448 chemin cours : état par destination',()=>{
 const token=(label:string)=>label.padEnd(64,'a').slice(0,64).replace(/[^0-9a-f]/g,'b');
 async function twoDevices(person=id.alice){
  await pool.query('UPDATE drivy.push_device SET revoked_at=now() WHERE person_id=$1 AND revoked_at IS NULL',[person]);
  const a=token(`a${randomUUID().replace(/-/g,'')}`),b=token(`b${randomUUID().replace(/-/g,'')}`);
  await pool.query("INSERT INTO drivy.push_device(person_id,platform,environment,token) VALUES($1,'IOS','SANDBOX',$2),($1,'IOS','SANDBOX',$3)",[person,a,b]);
  return {a,b};
 }
 /** Un seul événement notifiable : l'inscription confirmée de l'élève (CHANGE), isolée par série. */
 async function enrolled(){
  const series=await published();
  const devices=await twoDevices();
  await enroll(series,'demo-alice');
  return {series,...devices};
 }
 type Plan=Record<string,('SENT'|'INVALID_TOKEN'|'RETRY'|'THROW')[]>;
 function scripted(plan:Plan){
  const calls:string[]=[];
  const sender:PushSender={async send(device){
   calls.push(device);
   const results=plan[device]??['SENT'];const result=results[Math.min(calls.filter(call=>call===device).length-1,results.length-1)]!;
   if(result==='THROW')throw new Error('Transport interrompu (simulé)');
   return result;
  },close(){}};
  return {sender,calls,count:(device:string)=>calls.filter(call=>call===device).length};
 }
 const own=async(seriesId:string)=>(await pool.query<Row>("SELECT id,dedupe_key,status,attempts,failure_code,school_id,available_at,sent_at FROM drivy.push_notification WHERE person_id=$1 AND series_id=$2 AND category='CHANGE'",[id.alice,seriesId])).rows[0]!;
 const deliveries=async(notificationId:string)=>Object.fromEntries((await pool.query<{token:string;status:string;attempts:number;failure_code:string|null}>(
  'SELECT p.token,d.status,d.attempts,d.failure_code FROM drivy.push_delivery d JOIN drivy.push_device p ON p.id=d.device_id WHERE d.notification_id=$1',[notificationId])).rows.map(row=>[row.token,row]));
 const due=(notificationId:string)=>pool.query("UPDATE drivy.push_notification SET available_at=now()-interval '1 second' WHERE id=$1",[notificationId]);

 it('A acceptée, B en échec transitoire : après redémarrage du service, seule B est reprise',async()=>{
  const {series,a,b}=await enrolled();
  const first=scripted({[a]:['SENT'],[b]:['RETRY']});
  await processPushBatch(worker,first.sender);
  let n=await own(series.id);
  expect(n).toMatchObject({status:'PENDING',attempts:1,sent_at:null});
  expect(n.available_at.getTime()).toBeGreaterThan(Date.now());
  expect(await deliveries(n.id)).toMatchObject({[a]:{status:'SENT',attempts:1},[b]:{status:'PENDING',attempts:1,failure_code:'APNS_RETRY'}});
  await restartWorker();await due(n.id);
  const second=scripted({[a]:['SENT'],[b]:['SENT']});
  await processPushBatch(worker,second.sender);
  expect(second.calls).toEqual([b]);
  n=await own(series.id);
  expect(n).toMatchObject({status:'SENT',attempts:2});expect(n.sent_at).not.toBeNull();
  expect(await deliveries(n.id)).toMatchObject({[a]:{status:'SENT',attempts:1},[b]:{status:'SENT',attempts:2}});
  // Plus rien à reprendre : aucun appel supplémentaire.
  const third=scripted({});await processPushBatch(worker,third.sender);expect(third.calls).toEqual([]);
 });
 it('la notification n’est pas close tant qu’une destination garde une reprise valide, même si aucune n’a encore réussi',async()=>{
  const {series,a,b}=await enrolled();
  await processPushBatch(worker,scripted({[a]:['RETRY'],[b]:['RETRY']}).sender);
  const n=await own(series.id);
  expect(n.status).toBe('PENDING');
  expect(await deliveries(n.id)).toMatchObject({[a]:{status:'PENDING'},[b]:{status:'PENDING'}});
 });
 it('un jeton définitivement invalide ne bloque pas l’autre appareil et ne boucle pas',async()=>{
  const {series,a,b}=await enrolled();
  const run=scripted({[a]:['SENT'],[b]:['INVALID_TOKEN']});
  await processPushBatch(worker,run.sender);
  const n=await own(series.id);
  expect(n).toMatchObject({status:'SENT',attempts:1});
  expect(await deliveries(n.id)).toMatchObject({[a]:{status:'SENT'},[b]:{status:'REJECTED',failure_code:'INVALID_TOKEN'}});
  expect((await pool.query("SELECT revoked_at IS NOT NULL AS revoked FROM drivy.push_device WHERE token=$1",[b])).rows[0].revoked).toBe(true);
  const again=scripted({});await processPushBatch(worker,again.sender);expect(again.calls).toEqual([]);
 });
 it('reprise épuisée sur B : état terminal EXPIRED, A n’est jamais renvoyée, la notification se clôt',async()=>{
  const {series,a,b}=await enrolled();
  const run=scripted({[a]:['SENT'],[b]:['RETRY']});
  await processPushBatch(worker,run.sender);
  const id0=(await own(series.id)).id;
  for(let pass=2;pass<=5;pass++){await due(id0);await processPushBatch(worker,run.sender);}
  const n=await own(series.id);
  expect(n).toMatchObject({status:'SENT',attempts:5});
  expect(await deliveries(n.id)).toMatchObject({[a]:{status:'SENT',attempts:1},[b]:{status:'EXPIRED',attempts:5,failure_code:'RETRY_EXHAUSTED'}});
  expect(run.count(a)).toBe(1);expect(run.count(b)).toBe(5);
  await due(id0);await processPushBatch(worker,run.sender);
  expect(run.count(a)).toBe(1);expect(run.count(b)).toBe(5);
 });
 it('toutes les destinations épuisées sans succès : échec explicite',async()=>{
  const {series,a,b}=await enrolled();
  const run=scripted({[a]:['RETRY'],[b]:['RETRY']});
  await processPushBatch(worker,run.sender);
  const id0=(await own(series.id)).id;
  for(let pass=2;pass<=5;pass++){await due(id0);await processPushBatch(worker,run.sender);}
  expect(await own(series.id)).toMatchObject({status:'FAILED',attempts:5,failure_code:'APNS_UNAVAILABLE'});
 });
 it('un appareil révoqué entre deux passages est clos sans envoi',async()=>{
  const {series,a,b}=await enrolled();
  await processPushBatch(worker,scripted({[a]:['SENT'],[b]:['RETRY']}).sender);
  const n=await own(series.id);
  await pool.query('UPDATE drivy.push_device SET revoked_at=now() WHERE token=$1',[b]);
  await due(n.id);
  const run=scripted({});await processPushBatch(worker,run.sender);
  expect(run.calls).toEqual([]);
  expect(await deliveries(n.id)).toMatchObject({[b]:{status:'REVOKED',failure_code:'DEVICE_UNAVAILABLE'}});
  expect((await own(series.id)).status).toBe('SENT');
 });
 it('un appareil repris par une autre personne ne reçoit jamais l’alerte de l’ancienne',async()=>{
  const {series,a,b}=await enrolled();
  await processPushBatch(worker,scripted({[a]:['SENT'],[b]:['RETRY']}).sender);
  const n=await own(series.id);
  await pool.query('UPDATE drivy.push_device SET person_id=$2 WHERE token=$1',[b,id.bob]);
  await due(n.id);
  const run=scripted({});await processPushBatch(worker,run.sender);
  expect(run.calls).toEqual([]);
  expect(await deliveries(n.id)).toMatchObject({[b]:{status:'REVOKED'}});
 });
 it('préférence retirée entre deux passages : la relecture clôt la notification et ses destinations restantes',async()=>{
  const {series,a,b}=await enrolled();
  await processPushBatch(worker,scripted({[a]:['SENT'],[b]:['RETRY']}).sender);
  const n=await own(series.id);
  await pool.query('INSERT INTO drivy.notification_preference(person_id,course_changes) VALUES($1,false) ON CONFLICT(person_id) DO UPDATE SET course_changes=false',[id.alice]);
  await due(n.id);
  const run=scripted({});await processPushBatch(worker,run.sender);
  expect(run.calls).toEqual([]);
  expect(await own(series.id)).toMatchObject({status:'SKIPPED',failure_code:'PREFERENCE_DISABLED'});
  expect(await deliveries(n.id)).toMatchObject({[a]:{status:'SENT'},[b]:{status:'REVOKED',failure_code:'PREFERENCE_DISABLED'}});
  await pool.query('DELETE FROM drivy.notification_preference WHERE person_id=$1',[id.alice]);
 });
 it('échéance de la notification dépassée : la destination en attente devient EXPIRED',async()=>{
  const {series,a,b}=await enrolled();
  await processPushBatch(worker,scripted({[a]:['SENT'],[b]:['RETRY']}).sender);
  const n=await own(series.id);
  await pool.query("UPDATE drivy.push_notification SET valid_until=now()-interval '1 minute',available_at=now()-interval '1 second' WHERE id=$1",[n.id]);
  const run=scripted({});await processPushBatch(worker,run.sender);
  expect(run.calls).toEqual([]);
  expect((await own(series.id)).status).toBe('EXPIRED');
  expect(await deliveries(n.id)).toMatchObject({[b]:{status:'EXPIRED'}});
 });
 it('exception du transport après un appareil confirmé : le résultat acquis est conservé, seul l’autre est repris',async()=>{
  const {series,a,b}=await enrolled();
  // L'ordre des destinations n'est pas contractuel : le premier appel réussit, le second lève.
  const seen:string[]=[];
  const flaky:PushSender={async send(device){seen.push(device);if(seen.length===2)throw new Error('Transport interrompu (simulé)');return 'SENT';},close(){}};
  await expect(processPushBatch(worker,flaky)).rejects.toThrow('Transport interrompu');
  const n=await own(series.id);
  expect(n).toMatchObject({status:'PENDING',attempts:0});
  const [served,pending]=seen as [string,string];
  expect([served,pending].sort()).toEqual([a,b].sort());
  expect(await deliveries(n.id)).toMatchObject({[served]:{status:'SENT',attempts:1},[pending]:{status:'PENDING',attempts:0}});
  await restartWorker();
  const run=scripted({});await processPushBatch(worker,run.sender);
  expect(run.calls).toEqual([pending]);
  expect((await own(series.id)).status).toBe('SENT');
 });
 it('un appareil enregistré après le premier passage ne reçoit pas l’alerte ancienne',async()=>{
  const {series,a,b}=await enrolled();
  await processPushBatch(worker,scripted({[a]:['SENT'],[b]:['RETRY']}).sender);
  const n=await own(series.id);
  const late=token(`c${randomUUID().replace(/-/g,'')}`);
  await pool.query("INSERT INTO drivy.push_device(person_id,platform,environment,token) VALUES($1,'IOS','SANDBOX',$2)",[id.alice,late]);
  await due(n.id);
  const run=scripted({[b]:['SENT']});await processPushBatch(worker,run.sender);
  expect(run.calls).toEqual([b]);
  expect(run.count(late)).toBe(0);
 });
});
