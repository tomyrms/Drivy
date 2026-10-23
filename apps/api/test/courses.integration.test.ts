import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,prepareCommercial,lessonBody,id,type Call} from './support/harness.js';

/**
 * Cours collectifs (#80 socle, #38 création et publication). Données synthétiques seulement.
 * Exécution différée à la campagne finale #84 (Validation finale · backlog).
 */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>;
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);});
afterAll(async()=>{await app?.close();await pool?.end();});

const AWARENESS='0c0a5e00-0000-4000-8000-000000000001';
const day=(offset:number,hourUtc:number)=>{const d=new Date();d.setUTCDate(d.getUTCDate()+offset);d.setUTCHours(hourUtc,0,0,0);return d.toISOString();};
const series=(extra:Record<string,unknown>={})=>({operationId:randomUUID(),typeId:AWARENESS,title:'Sensibilisation d’automne',description:'',location:'Salle 1',conditions:'',
 teachingLanguage:'fr',responsibleMembershipId:id.adminMember,capacity:12,minParticipants:null,timeZone:'Europe/Zurich',
 occurrences:[{startsAt:day(20,16),endsAt:day(20,20),instructorMembershipId:id.instructorMember,attendanceRequired:true},
  {startsAt:day(21,16),endsAt:day(21,20),instructorMembershipId:id.instructorMember,attendanceRequired:true}],...extra});
async function grant(member:string,grants:string[]){
 const current=(await call('GET','/members',undefined,null,'demo-admin')).json().data.items.find((item:{id:string})=>item.id===member);
 return call('PATCH',`/members/${member}`,{operationId:randomUUID(),roles:current.roles,grants,reason:'Recette des cours'},current.version,'demo-admin');
}

describe('cours collectifs : socle et publication',()=>{
 it('expose les deux types prédéfinis et le délai de 24 h par défaut',async()=>{
  const res=await call('GET','/course-catalogue',undefined,null,'demo-admin');expect(res.statusCode).toBe(200);
  const data=res.json().data;
  expect(data.types.filter((t:{predefined:boolean})=>t.predefined).map((t:{stableKey:string})=>t.stableKey).sort()).toEqual(['AWARENESS','FIRST_AID']);
  expect(data.policy).toEqual({version:1,selfCancelHours:24,offerResponseMinutes:null});
  expect(data.canManage).toBe(true);
 });
 it('refuse la gestion au moniteur sans droit, y compris par appel direct, puis l’accorde avec MANAGE_COURSES',async()=>{
  expect((await call('GET','/course-catalogue')).json().data.canManage).toBe(false);
  const denied=await call('POST','/course-series',series());expect(denied.statusCode).toBe(403);expect(denied.json().code).toBe('COURSE_ACCESS_REQUIRED');
  expect((await call('POST','/course-types',{operationId:randomUUID(),title:'Atelier',description:''})).statusCode).toBe(403);
  expect((await grant(id.instructorMember,['MANAGE_COURSES'])).statusCode).toBe(200);
  const created=await call('POST','/course-series',series());expect(created.statusCode,created.body).toBe(201);
  expect(created.json().data.status).toBe('DRAFT');
  await grant(id.instructorMember,[]);
 });
 it('un élève ne voit pas les brouillons et ne crée rien',async()=>{
  const draft=(await call('POST','/course-series',series(),null,'demo-admin')).json().data;
  expect((await call('GET',`/course-series/${draft.id}`,undefined,null,'demo-alice')).statusCode).toBe(404);
  expect((await call('GET','/course-series',undefined,null,'demo-alice')).json().data.items.some((s:{id:string})=>s.id===draft.id)).toBe(false);
  expect((await call('POST','/course-series',series(),null,'demo-alice')).statusCode).toBe(403);
 });
 it('isole les écoles',async()=>{
  const draft=(await call('POST','/course-series',series(),null,'demo-admin')).json().data;
  const other=await call('GET',`/v1/schools/${id.schoolB}/course-series/${draft.id}`,undefined,null,'demo-instructor');
  expect(other.statusCode).toBe(404);
 });
 it('brouillon modifiable puis publication visible par l’élève, sans inscription créée, idempotente',async()=>{
  const draft=(await call('POST','/course-series',series(),null,'demo-admin')).json().data;
  const edited=await call('PUT',`/course-series/${draft.id}`,series({title:'Sensibilisation · groupe B',capacity:10}),draft.version,'demo-admin');
  expect(edited.statusCode).toBe(200);expect(edited.json().data.title).toBe('Sensibilisation · groupe B');
  const op=randomUUID();
  const published=await call('POST',`/course-series/${draft.id}/publish`,{operationId:op},edited.json().data.version,'demo-admin',{'idempotency-key':op});
  expect(published.statusCode).toBe(200);
  const data=published.json().data;
  expect(data).toMatchObject({status:'PUBLISHED',capacity:10,seatsTaken:0,remainingSeats:10,selfCancelHours:24,policyVersion:1,totalMinutes:480});
  expect(Date.parse(data.selfCancellationDeadline)).toBe(Date.parse(data.firstStartsAt)-24*3_600_000);
  const replay=await call('POST',`/course-series/${draft.id}/publish`,{operationId:op},edited.json().data.version,'demo-admin',{'idempotency-key':op});
  expect(replay.statusCode).toBe(200);expect(replay.json().data.version).toBe(data.version);
  expect((await call('GET',`/course-series/${draft.id}`,undefined,null,'demo-alice')).json().data.occurrences).toHaveLength(2);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.course_enrollment WHERE series_id=$1',[draft.id])).rows[0].n).toBe(0);
  expect((await call('PUT',`/course-series/${draft.id}`,series(),data.version,'demo-admin')).json().code).toBe('COURSE_NOT_DRAFT');
 });
 it('refuse horaires invalides, chevauchements internes et passé',async()=>{
  const bad=await call('POST','/course-series',series({occurrences:[{startsAt:day(22,18),endsAt:day(22,16),instructorMembershipId:id.instructorMember,attendanceRequired:true}]}),null,'demo-admin');
  expect(bad.json().code).toBe('INVALID_INTERVAL');
  const overlap=await call('POST','/course-series',series({occurrences:[{startsAt:day(23,16),endsAt:day(23,20),instructorMembershipId:id.instructorMember,attendanceRequired:true},
   {startsAt:day(23,18),endsAt:day(23,21),instructorMembershipId:id.otherInstructorMember,attendanceRequired:false}]}),null,'demo-admin');
  expect(overlap.json().code).toBe('COURSE_OCCURRENCES_OVERLAP');
  const past=(await call('POST','/course-series',series({occurrences:[{startsAt:day(-1,8),endsAt:day(-1,10),instructorMembershipId:id.instructorMember,attendanceRequired:true}]}),null,'demo-admin')).json().data;
  expect((await call('POST',`/course-series/${past.id}/publish`,{operationId:randomUUID()},past.version,'demo-admin')).json().code).toBe('COURSE_IN_PAST');
 });
 it('bloque le conflit formateur avec un autre cours et avec une leçon, dans les deux sens, en gardant le brouillon',async()=>{
  const slot={startsAt:day(30,9),endsAt:day(30,12),instructorMembershipId:id.otherInstructorMember,attendanceRequired:true};
  const first=(await call('POST','/course-series',series({occurrences:[slot]}),null,'demo-admin')).json().data;
  expect((await call('POST',`/course-series/${first.id}/publish`,{operationId:randomUUID()},first.version,'demo-admin')).statusCode).toBe(200);
  const second=(await call('POST','/course-series',series({occurrences:[slot]}),null,'demo-admin')).json().data;
  const conflict=await call('POST',`/course-series/${second.id}/publish`,{operationId:randomUUID()},second.version,'demo-admin');
  expect(conflict.statusCode).toBe(409);expect(conflict.json().code).toBe('COURSE_INSTRUCTOR_CONFLICT');
  expect((await call('GET',`/course-series/${second.id}`,undefined,null,'demo-admin')).json().data.status).toBe('DRAFT');
  // Formateurs différents en parallèle : autorisé.
  const parallel=(await call('POST','/course-series',series({occurrences:[{...slot,instructorMembershipId:id.instructorMember}]}),null,'demo-admin')).json().data;
  expect((await call('POST',`/course-series/${parallel.id}/publish`,{operationId:randomUUID()},parallel.version,'demo-admin')).statusCode).toBe(200);
  // Leçon après cours : la même exclusion refuse la leçon du moniteur déjà en cours.
  const commercial=await prepareCommercial(call);
  const lesson=lessonBody(commercial,school.policy,30,9);
  const refused=await call('POST','/lessons',{...lesson,instructorMembershipId:id.instructorMember},null,'demo-admin');
  expect(refused.statusCode).toBe(409);
 });
 it('publications concurrentes sur le même créneau : une seule réussit',async()=>{
  const slot={startsAt:day(40,9),endsAt:day(40,11),instructorMembershipId:id.otherInstructorMember,attendanceRequired:true};
  const a=(await call('POST','/course-series',series({occurrences:[slot]}),null,'demo-admin')).json().data;
  const b=(await call('POST','/course-series',series({occurrences:[slot]}),null,'demo-admin')).json().data;
  const results=await Promise.all([a,b].map(s=>call('POST',`/course-series/${s.id}/publish`,{operationId:randomUUID()},s.version,'demo-admin')));
  expect(results.map(r=>r.statusCode).sort()).toEqual([200,409]);
 });
 it('capacité : jamais sous les places prises (inscriptions et propositions actives)',async()=>{
  const s=(await call('POST','/course-series',series({occurrences:[{startsAt:day(50,9),endsAt:day(50,11),instructorMembershipId:id.instructorMember,attendanceRequired:true}]}),null,'demo-admin')).json().data;
  const pub=(await call('POST',`/course-series/${s.id}/publish`,{operationId:randomUUID()},s.version,'demo-admin')).json().data;
  // Fixture synthétique directe (les commandes d'inscription et de file arrivent avec #39/#40) : une inscription et une proposition.
  await pool.query(`INSERT INTO drivy.course_enrollment(school_id,series_id,learner_id,source,policy_version,self_cancel_hours,self_cancel_deadline,created_by)
   VALUES($1,$2,$3,'STAFF',1,24,$4,$5)`,[id.schoolA,s.id,id.aliceLearner,pub.selfCancellationDeadline,id.adminMember]);
  const entry=(await pool.query(`INSERT INTO drivy.course_waitlist_entry(school_id,series_id,learner_id,status) VALUES($1,$2,$3,'OFFERED') RETURNING id`,[id.schoolA,s.id,id.bobLearner])).rows[0].id;
  await pool.query(`INSERT INTO drivy.course_seat_offer(school_id,series_id,entry_id,expires_at) VALUES($1,$2,$3,now()+interval '1 hour')`,[id.schoolA,s.id,entry]);
  const read=(await call('GET',`/course-series/${s.id}`,undefined,null,'demo-admin')).json().data;
  expect(read).toMatchObject({seatsTaken:2,remainingSeats:10});
  const below=await call('POST',`/course-series/${s.id}/capacity`,{operationId:randomUUID(),capacity:1},read.version,'demo-admin');
  expect(below.json().code).toBe('COURSE_CAPACITY_BELOW_TAKEN');
  expect((await call('POST',`/course-series/${s.id}/capacity`,{operationId:randomUUID(),capacity:2},read.version,'demo-admin')).json().data.remainingSeats).toBe(0);
  // Une proposition échue ne retient plus de place.
  await pool.query(`UPDATE drivy.course_seat_offer SET offered_at=now()-interval '2 hours',expires_at=now()-interval '1 minute' WHERE entry_id=$1`,[entry]);
  expect((await call('GET',`/course-series/${s.id}`,undefined,null,'demo-admin')).json().data.seatsTaken).toBe(1);
 });
 it('type personnalisé : renommer garde l’identité et les séries liées ; prédéfini non modifiable ; nom unique',async()=>{
  const type=(await call('POST','/course-types',{operationId:randomUUID(),title:'Atelier écoconduite',description:'Deux heures'},null,'demo-admin')).json().data;
  expect((await call('POST','/course-types',{operationId:randomUUID(),title:'atelier écoconduite ',description:''},null,'demo-admin')).json().code).toBe('COURSE_TYPE_EXISTS');
  const s=(await call('POST','/course-series',series({typeId:type.id}),null,'demo-admin')).json().data;
  const renamed=await call('PATCH',`/course-types/${type.id}`,{operationId:randomUUID(),title:'Écoconduite',description:'Deux heures'},type.version,'demo-admin');
  expect(renamed.json().data).toMatchObject({id:type.id,title:'Écoconduite',version:2});
  expect((await call('GET',`/course-series/${s.id}`,undefined,null,'demo-admin')).json().data).toMatchObject({typeId:type.id,typeTitle:'Écoconduite'});
  expect((await call('PATCH',`/course-types/${AWARENESS}`,{operationId:randomUUID(),title:'X',description:''},1,'demo-admin')).json().code).toBe('COURSE_TYPE_PREDEFINED');
 });
 it('politique d’annulation versionnée : nouvelle valeur pour les nouvelles séries, publiées inchangées',async()=>{
  const old=(await call('POST','/course-series',series({occurrences:[{startsAt:day(60,9),endsAt:day(60,11),instructorMembershipId:id.instructorMember,attendanceRequired:true}]}),null,'demo-admin')).json().data;
  const pub=(await call('POST',`/course-series/${old.id}/publish`,{operationId:randomUUID()},old.version,'demo-admin')).json().data;
  const saved=await call('PUT','/course-policy',{operationId:randomUUID(),selfCancelHours:48,offerResponseMinutes:null},1,'demo-admin');
  expect(saved.json().data,saved.body).toEqual({version:2,selfCancelHours:48,offerResponseMinutes:null});
  expect((await call('GET',`/course-series/${pub.id}`,undefined,null,'demo-admin')).json().data).toMatchObject({selfCancelHours:24,policyVersion:1});
  expect((await call('POST','/course-series',series(),null,'demo-admin')).json().data).toMatchObject({selfCancelHours:48,policyVersion:2});
  expect((await call('PUT','/course-policy',{operationId:randomUUID(),selfCancelHours:12,offerResponseMinutes:null},1,'demo-admin')).statusCode).toBe(412);
 });
});
