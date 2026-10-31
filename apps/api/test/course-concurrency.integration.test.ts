import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,prepareCommercial,lessonBody,id,type Call} from './support/harness.js';

/**
 * Cours collectifs : vraie concurrence (#83 : #38 capacité, #39 inscription et leçon sur le même créneau). Données synthétiques.
 *
 * Chaque commande métier prend d'abord le verrou de l'école (apps/api/src/commands.ts). Pour que deux requêtes partent
 * réellement ENSEMBLE, la recette retient ce verrou depuis une connexion à part, attend que les deux commandes y soient
 * suspendues, puis le relâche : les deux transactions sont alors en concurrence, le gagnant n'est pas prévisible et le test
 * n'en suppose aucun. Ce qui est vérifié : un seul gagnant, un refus explicite pour l'autre, aucune occupation d'agenda partielle.
 */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);commercial=await prepareCommercial(call);});
afterAll(async()=>{await app?.close();await pool?.end();});

const at=(offset:number,hourUtc:number)=>{const d=new Date();d.setUTCDate(d.getUTCDate()+offset);d.setUTCHours(hourUtc,0,0,0);return d.toISOString();};
type Series={id:string;version:number;occurrences:{startsAt:string;endsAt:string}[]};
/** Série publiée de `days` séances consécutives de 08:00 à 11:00 UTC, un type neuf, animée par le second moniteur. */
async function published(startOffset:number,days:number,capacity:number):Promise<Series>{
 const type=(await call('POST','/course-types',{operationId:randomUUID(),title:`Type ${randomUUID()}`,description:''},null,'demo-admin')).json().data.id;
 const occurrences=Array.from({length:days},(_,i)=>({startsAt:at(startOffset+i,8),endsAt:at(startOffset+i,11),instructorMembershipId:id.otherInstructorMember,attendanceRequired:true}));
 const created=await call('POST','/course-series',{operationId:randomUUID(),typeId:type,title:'Cours de recette',description:'',location:'Salle',conditions:'',teachingLanguage:null,
  responsibleMembershipId:id.adminMember,capacity,minParticipants:null,timeZone:'Europe/Zurich',occurrences},null,'demo-admin');
 if(created.statusCode!==201)throw new Error(created.body);
 const res=await call('POST',`/course-series/${created.json().data.id}/publish`,{operationId:randomUUID()},created.json().data.version,'demo-admin');
 if(res.statusCode!==200)throw new Error(res.body);
 return res.json().data;
}
const enroll=(seriesId:string,subject:string)=>call('POST',`/course-series/${seriesId}/enroll`,{operationId:randomUUID()},null,subject);
type Response=Awaited<ReturnType<Call>>;

/** Lance les commandes ensemble : le verrou d'école est retenu jusqu'à ce que toutes soient suspendues dessus. */
async function simultaneously(first:()=>ReturnType<Call>,second:()=>ReturnType<Call>):Promise<[Response,Response]>{
 const starts=[first,second];
 const blocker=await pool.connect();
 let pending:ReturnType<Call>[]=[];
 try{
  await blocker.query('BEGIN');
  await blocker.query('SELECT id FROM drivy.school WHERE id=$1 FOR UPDATE',[id.schoolA]);
  pending=starts.map(start=>start());
  const deadline=Date.now()+8_000;let waiting=0;
  while(Date.now()<deadline&&waiting<starts.length){
   waiting=(await pool.query<{n:number}>("SELECT count(*)::int AS n FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND pid<>pg_backend_pid()")).rows[0]!.n;
   if(waiting<starts.length)await new Promise(resolve=>setTimeout(resolve,10));
  }
  expect(waiting,'toutes les commandes attendent le même verrou avant de partir ensemble').toBe(starts.length);
 }finally{await blocker.query('COMMIT');blocker.release();}
 return Promise.all(pending) as Promise<[Response,Response]>;
}
/** Occupations actives de l'élève sur une fenêtre : une leçon vaut une ligne, un cours une ligne par séance. */
async function holdings(person:string,from:string,to:string){
 const rows=(await pool.query<{kind:'LESSON'|'COURSE';n:number}>(`SELECT CASE WHEN lesson_id IS NOT NULL THEN 'LESSON' ELSE 'COURSE' END AS kind,count(*)::int AS n FROM drivy.reservation
  WHERE school_id=$1 AND resource_id=$2 AND resource_role='LEARNER' AND active AND during && tstzrange($3::timestamptz,$4::timestamptz,'[)') GROUP BY 1`,[id.schoolA,person,from,to])).rows;
 return Object.fromEntries(rows.map(row=>[row.kind,row.n])) as {LESSON?:number;COURSE?:number};
}
const activeEnrollments=async(seriesId:string)=>(await pool.query<{n:number}>("SELECT count(*)::int AS n FROM drivy.course_enrollment WHERE series_id=$1 AND status='ACTIVE'",[seriesId])).rows[0]!.n;

describe('leçon et inscription sur le même créneau, réellement en parallèle',()=>{
 it.each([40,50,60,70])('cours de trois jours à partir de J+%i : un seul gagnant, jamais de double occupation ni d’inscription partielle',async offset=>{
  const series=await published(offset,3,10);
  // La leçon tombe sur la deuxième séance : 08:00 à 08:50 UTC contre 08:00 à 11:00 UTC.
  const lesson=lessonBody(commercial,school.policy,offset+1,8);
  const [lessonRes,enrollRes]=await simultaneously(()=>call('POST','/lessons',lesson,null,'demo-admin'),()=>enroll(series.id,'demo-alice'));
  expect([lessonRes.statusCode,enrollRes.statusCode].sort(),`leçon : ${lessonRes.body} · inscription : ${enrollRes.body}`).toEqual([201,409]);
  const held=await holdings(id.alice,series.occurrences[0]!.startsAt,series.occurrences[2]!.endsAt);
  const lessons=(await pool.query<{n:number}>("SELECT count(*)::int AS n FROM drivy.lesson WHERE school_id=$1 AND planned_start=$2 AND status='PLANNED'",[id.schoolA,lesson.plannedStart])).rows[0]!.n;
  const state=(await call('GET',`/course-series/${series.id}/me`,undefined,null,'demo-alice')).json().data.me.state;
  if(lessonRes.statusCode===201){
   expect(enrollRes.json().code).toBe('COURSE_SCHEDULE_CONFLICT');
   expect(held).toEqual({LESSON:1});          // la leçon seule : aucune des trois séances n'a été réservée
   expect(lessons).toBe(1);expect(await activeEnrollments(series.id)).toBe(0);expect(state).toBe('AVAILABLE');
  }else{
   expect(lessonRes.json().code).toBe('SLOT_CONFLICT');
   expect(held).toEqual({COURSE:3});          // les trois séances, aucune ligne de leçon
   expect(lessons).toBe(0);expect(await activeEnrollments(series.id)).toBe(1);expect(state).toBe('ENROLLED');
  }
 });
});

describe('autres courses sur un même cours',()=>{
 it('double appui d’une même élève avec deux opérations distinctes : une inscription, un refus explicite',async()=>{
  const series=await published(100,3,10);
  const [a,b]=await simultaneously(()=>enroll(series.id,'demo-alice'),()=>enroll(series.id,'demo-alice'));
  expect([a.statusCode,b.statusCode].sort(),`${a.body} · ${b.body}`).toEqual([201,409]);
  expect([a,b].find(r=>r.statusCode===409)!.json().code).toBe('COURSE_ALREADY_ENROLLED');
  expect(await activeEnrollments(series.id)).toBe(1);
  expect(await holdings(id.alice,series.occurrences[0]!.startsAt,series.occurrences[2]!.endsAt)).toEqual({COURSE:3});
 });
 it('réduction de capacité et dernière inscription simultanées : jamais plus de places prises que de capacité',async()=>{
  const series=await published(110,1,2);
  expect((await enroll(series.id,'demo-alice')).statusCode).toBe(201);
  const current=(await call('GET',`/course-series/${series.id}`,undefined,null,'demo-admin')).json().data;
  const [capacity,bob]=await simultaneously(
   ()=>call('POST',`/course-series/${series.id}/capacity`,{operationId:randomUUID(),capacity:1},current.version,'demo-admin'),
   ()=>enroll(series.id,'demo-bob'));
  // Un seul des deux aboutit : Bob entre (la réduction est alors refusée, version périmée ou places prises) ou la capacité
  // passe à 1 (et Bob trouve le cours complet). Les deux ensemble donneraient deux inscrits pour une place.
  expect(capacity.statusCode===200,`capacité : ${capacity.body}`).not.toBe(bob.statusCode===201);
  if(capacity.statusCode===200){expect(bob.statusCode).toBe(409);expect(bob.json().code).toBe('COURSE_FULL');}
  else{expect([409,412]).toContain(capacity.statusCode);expect(bob.statusCode).toBe(201);}
  const row=(await pool.query<{capacity:number;taken:number}>("SELECT capacity,(SELECT count(*)::int FROM drivy.course_enrollment WHERE series_id=s.id AND status='ACTIVE') AS taken FROM drivy.course_series s WHERE id=$1",[series.id])).rows[0]!;
  expect(row.taken).toBeLessThanOrEqual(row.capacity);
  expect(row).toEqual(capacity.statusCode===200?{capacity:1,taken:1}:{capacity:2,taken:2});
 });
});
