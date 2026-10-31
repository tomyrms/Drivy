import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,type Call} from './support/harness.js';

/**
 * Cours collectifs : effet d'une validation (#82) sur ce qui existe déjà pour l'élève (#83 : #82 « inscription future »,
 * #40 « cesse les sollicitations »). Données synthétiques. Les séances passées sont obtenues en déplaçant les dates en base,
 * seule façon honnête sans horloge simulée.
 *
 * Comportement figé ici (règle : « aucune inscription annulée en silence ») : une validation n'annule aucune inscription
 * existante, même d'un type déjà validé ; elle retire en revanche l'élève des files d'attente de ce type et révoque la
 * proposition de place qu'il détenait. Reste à confirmer par le porteur : faut-il alerter le personnel quand une inscription
 * future porte sur un type déjà validé ?
 */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));await prepareSchool(pool);});
afterAll(async()=>{await app?.close();await pool?.end();});

const AWARENESS='0c0a5e00-0000-4000-8000-000000000001',FIRST_AID='0c0a5e00-0000-4000-8000-000000000002';
const at=(offset:number,hourUtc:number)=>{const d=new Date();d.setUTCDate(d.getUTCDate()+offset);d.setUTCHours(hourUtc,0,0,0);return d.toISOString();};
type Series={id:string;version:number;seatsTaken:number};
async function newType(){return (await call('POST','/course-types',{operationId:randomUUID(),title:`Type ${randomUUID()}`,description:''},null,'demo-admin')).json().data.id as string;}
async function published(typeId:string,offset:number,days:number,capacity=5):Promise<Series>{
 const created=await call('POST','/course-series',{operationId:randomUUID(),typeId,title:'Cours de recette',description:'',location:'Salle',conditions:'',teachingLanguage:null,
  responsibleMembershipId:id.adminMember,capacity,minParticipants:null,timeZone:'Europe/Zurich',
  occurrences:Array.from({length:days},(_,i)=>({startsAt:at(offset+i,8),endsAt:at(offset+i,11),instructorMembershipId:id.otherInstructorMember,attendanceRequired:true}))},null,'demo-admin');
 if(created.statusCode!==201)throw new Error(created.body);
 const res=await call('POST',`/course-series/${created.json().data.id}/publish`,{operationId:randomUUID()},created.json().data.version,'demo-admin');
 if(res.statusCode!==200)throw new Error(res.body);
 return res.json().data;
}
type Enrollment={id:string;version:number};
async function enroll(seriesId:string,subject:string){
 const res=await call('POST',`/course-series/${seriesId}/enroll`,{operationId:randomUUID()},null,subject);
 expect(res.statusCode,res.body).toBe(201);return res.json().data.me.enrollment as Enrollment;
}
/** Ramène toutes les séances dans le passé (la dernière finit hier au plus tard). */
const inThePast=(seriesId:string,offset:number,days:number)=>pool.query(`UPDATE drivy.course_occurrence SET starts_at=starts_at-make_interval(days=>$2),ends_at=ends_at-make_interval(days=>$2) WHERE series_id=$1`,[seriesId,offset+days]);
async function attendEverything(seriesId:string,enrollmentId:string){
 const sheet=(await call('GET',`/course-series/${seriesId}/sheet`,undefined,null,'demo-admin')).json().data;
 for(const occurrence of sheet.series.occurrences as {id:string}[]){
  const res=await call('PUT',`/course-enrollments/${enrollmentId}/attendance/${occurrence.id}`,{operationId:randomUUID(),status:'PRESENT',expectedVersion:null,note:null},null,'demo-admin');
  expect(res.statusCode,res.body).toBe(200);
 }
}
const validate=(enrollmentId:string)=>call('POST',`/course-enrollments/${enrollmentId}/validate`,{operationId:randomUUID(),note:null},null,'demo-admin');
/** Cours tenu et suivi par Alice, puis validé : renvoie la série passée et l'inscription. */
async function heldAndAttended(typeId:string,offset:number,validateNow:boolean){
 const held=await published(typeId,offset,2),enrollment=await enroll(held.id,'demo-alice');
 await inThePast(held.id,offset,2);await attendEverything(held.id,enrollment.id);
 if(validateNow){const res=await validate(enrollment.id);expect(res.statusCode,res.body).toBe(201);}
 return {held,enrollment};
}
const count=async(sql:string,values:unknown[])=>(await pool.query<{n:number}>(sql,values)).rows[0]!.n;
const learnerReservations=(seriesId:string,person:string)=>count(`SELECT count(*)::int AS n FROM drivy.reservation r JOIN drivy.course_occurrence o ON o.id=r.course_occurrence_id
 WHERE o.series_id=$1 AND r.resource_id=$2 AND r.course_enrollment_id IS NOT NULL AND r.active`,[seriesId,person]);

describe('#82 validation et inscription future du même type',()=>{
 it('l’inscription future n’est pas annulée en silence : place, occupations et agenda restent, le personnel peut l’annuler avec un motif',async()=>{
  // Première session suivie puis validée ; la seconde session du même type, à venir, avait été prise une fois la première terminée.
  const first=await published(FIRST_AID,10,2),firstEnrollment=await enroll(first.id,'demo-alice');
  await inThePast(first.id,10,2);
  const future=await published(FIRST_AID,40,1),futureEnrollment=await enroll(future.id,'demo-alice');
  await attendEverything(first.id,firstEnrollment.id);
  const validated=await validate(firstEnrollment.id);expect(validated.statusCode,validated.body).toBe(201);

  const view=(await call('GET',`/course-series/${future.id}/me`,undefined,null,'demo-alice')).json().data;
  expect(view.me.state).toBe('ENROLLED');
  expect(view.me.enrollment).toMatchObject({id:futureEnrollment.id,status:'ACTIVE',canSelfCancel:true});
  expect(view.series.seatsTaken).toBe(1);
  expect(await learnerReservations(future.id,id.alice)).toBe(1);
  const mine=(await call('GET','/course-enrollments/me',undefined,null,'demo-alice')).json().data.items as {id:string;status:string}[];
  expect(mine.find(item=>item.id===futureEnrollment.id)?.status).toBe('ACTIVE');
  // Dossier : la validation et l'inscription future cohabitent ; la seconde garde ses propres exigences à zéro présence.
  const facts=(await call('GET',`/learners/${id.aliceLearner}/course-facts`,undefined,null,'demo-admin')).json().data;
  expect(facts.completions.map((c:{typeKey:string;seriesId:string})=>[c.typeKey,c.seriesId])).toEqual([['FIRST_AID',first.id]]);
  const upcoming=facts.enrollments.find((e:{seriesId:string})=>e.seriesId===future.id);
  expect(upcoming.requirements).toEqual({required:1,present:0,missing:1});
  // Annulation explicite par le personnel : motif exigé, place rendue, historique gardé.
  const cancelled=await call('POST',`/course-enrollments/${futureEnrollment.id}/staff-cancel`,{operationId:randomUUID(),reason:'Cours déjà validé'},futureEnrollment.version,'demo-admin');
  expect(cancelled.statusCode,cancelled.body).toBe(200);
  expect(cancelled.json().data).toMatchObject({status:'CANCELLED',cancelKind:'STAFF',cancelReason:'Cours déjà validé'});
  expect(await learnerReservations(future.id,id.alice)).toBe(0);
  expect((await call('GET',`/course-series/${future.id}`,undefined,null,'demo-admin')).json().data.seatsTaken).toBe(0);
  expect(await count('SELECT count(*)::int AS n FROM drivy.course_enrollment WHERE id=$1',[futureEnrollment.id])).toBe(1);
 });

 it('même suivie, l’inscription future d’un type déjà validé ne produit pas de seconde validation',async()=>{
  const first=await published(AWARENESS,60,2),firstEnrollment=await enroll(first.id,'demo-alice');
  await inThePast(first.id,60,2);
  const second=await published(AWARENESS,90,1),secondEnrollment=await enroll(second.id,'demo-alice');
  await attendEverything(first.id,firstEnrollment.id);
  expect((await validate(firstEnrollment.id)).statusCode).toBe(201);
  // La seconde session se tient ensuite et Alice y est présente : la validation du même type reste refusée.
  await inThePast(second.id,90,1);await attendEverything(second.id,secondEnrollment.id);
  const again=await validate(secondEnrollment.id);
  expect(again.statusCode).toBe(409);expect(again.json().code).toBe('COURSE_ALREADY_COMPLETED');
  expect(await count('SELECT count(*)::int AS n FROM drivy.course_completion WHERE learner_id=$1 AND type_id=$2 AND revoked_at IS NULL',[id.aliceLearner,AWARENESS])).toBe(1);
  // Les présences de la seconde session sont conservées : rien n'est effacé parce que la validation est refusée.
  expect(await count('SELECT count(*)::int AS n FROM drivy.course_attendance WHERE enrollment_id=$1',[secondEnrollment.id])).toBe(1);
 });
});

describe('#40 validation et sollicitations de la file',()=>{
 it('élève en attente : retirée de la file à la validation, aucune proposition quand la place se libère',async()=>{
  const type=await newType();
  const held=await heldAndAttended(type,120,false);
  const target=await published(type,150,1,1),holder=await enroll(target.id,'demo-bob');
  expect((await call('POST',`/course-series/${target.id}/waitlist`,{operationId:randomUUID()},null,'demo-alice')).statusCode).toBe(201);
  expect(await count("SELECT count(*)::int AS n FROM drivy.course_waitlist_entry WHERE series_id=$1 AND status='WAITING'",[target.id])).toBe(1);

  expect((await validate(held.enrollment.id)).statusCode).toBe(201);
  expect(await count("SELECT count(*)::int AS n FROM drivy.course_waitlist_entry WHERE series_id=$1 AND learner_id=$2 AND status='REMOVED'",[target.id,id.aliceLearner])).toBe(1);
  expect((await call('GET',`/course-series/${target.id}/me`,undefined,null,'demo-alice')).json().data.me.state).toBe('COMPLETED');
  const roster=(await call('GET',`/course-series/${target.id}/enrollments`,undefined,null,'demo-admin')).json().data;
  expect(roster.waitlist).toEqual([]);

  // Bob libère la place : personne n'est en attente, donc aucune proposition n'est créée pour Alice.
  expect((await call('POST',`/course-enrollments/${holder.id}/cancel`,{operationId:randomUUID()},holder.version,'demo-bob')).statusCode).toBe(200);
  expect(await count('SELECT count(*)::int AS n FROM drivy.course_seat_offer WHERE series_id=$1',[target.id])).toBe(0);
  expect((await call('GET',`/course-series/${target.id}`,undefined,null,'demo-admin')).json().data.seatsTaken).toBe(0);
 });

 it('proposition en cours : révoquée à la validation, refusée à l’acceptation, la place revient au suivant',async()=>{
  const type=await newType();
  const held=await heldAndAttended(type,170,false);
  const target=await published(type,200,1,1),holder=await enroll(target.id,'demo-bob');
  expect((await call('POST',`/course-series/${target.id}/waitlist`,{operationId:randomUUID()},null,'demo-alice')).statusCode).toBe(201);
  expect((await call('POST',`/course-enrollments/${holder.id}/cancel`,{operationId:randomUUID()},holder.version,'demo-bob')).statusCode).toBe(200);
  const offered=(await call('GET',`/course-series/${target.id}/me`,undefined,null,'demo-alice')).json().data;
  expect(offered.me.state).toBe('OFFERED');expect(offered.series.seatsTaken).toBe(1);
  const offerId=offered.me.offer.id as string;

  expect((await validate(held.enrollment.id)).statusCode).toBe(201);
  expect((await pool.query<{status:string}>('SELECT status FROM drivy.course_seat_offer WHERE id=$1',[offerId])).rows[0]!.status).toBe('REVOKED');
  expect((await call('GET',`/course-series/${target.id}`,undefined,null,'demo-admin')).json().data.seatsTaken).toBe(0);
  expect((await call('GET',`/course-series/${target.id}/me`,undefined,null,'demo-alice')).json().data.me.state).toBe('COMPLETED');
  const late=await call('POST',`/course-offers/${offerId}/accept`,{operationId:randomUUID()},null,'demo-alice');
  expect(late.statusCode,late.body).toBe(409);expect(late.json().code).toBe('COURSE_ALREADY_COMPLETED');
  expect(await count('SELECT count(*)::int AS n FROM drivy.course_enrollment WHERE series_id=$1 AND learner_id=$2',[target.id,id.aliceLearner])).toBe(0);
  // La place n'est pas bloquée par la proposition retirée : Bob, qui l'avait libérée, peut la reprendre.
  const back=await call('POST',`/course-series/${target.id}/enroll`,{operationId:randomUUID()},null,'demo-bob');
  expect(back.statusCode,back.body).toBe(201);expect(back.json().data.me.state).toBe('ENROLLED');
 });
});
