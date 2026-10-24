import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,type Call} from './support/harness.js';

/** Cours collectifs : appel (#42), règlements sur place (#81), validation (#82). Données synthétiques. Campagne de référence : #84. */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));await prepareSchool(pool);});
afterAll(async()=>{await app?.close();await pool?.end();});

let cursor=10;
const at=(offset:number,hourUtc:number)=>{const d=new Date();d.setUTCDate(d.getUTCDate()+offset);d.setUTCHours(hourUtc,0,0,0);return d.toISOString();};
/** Série publiée de deux séances obligatoires et une facultative, Alice inscrite, puis séances ramenées dans le passé. */
async function heldCourse(){
 const type=(await call('POST','/course-types',{operationId:randomUUID(),title:`Type ${randomUUID()}`,description:''},null,'demo-admin')).json().data;
 const start=cursor+=4;
 const occurrences=[0,1,2].map(i=>({startsAt:at(start+i,8),endsAt:at(start+i,11),instructorMembershipId:id.otherInstructorMember,attendanceRequired:i<2}));
 const draft=(await call('POST','/course-series',{operationId:randomUUID(),typeId:type.id,title:'Cours tenu',description:'',location:'',conditions:'',teachingLanguage:null,
  responsibleMembershipId:id.adminMember,capacity:5,minParticipants:null,timeZone:'Europe/Zurich',occurrences},null,'demo-admin')).json().data;
 const pub=(await call('POST',`/course-series/${draft.id}/publish`,{operationId:randomUUID()},draft.version,'demo-admin')).json().data;
 const enrolled=(await call('POST',`/course-series/${pub.id}/enroll`,{operationId:randomUUID()},null,'demo-alice')).json().data.me.enrollment;
 // Seule façon honnête d'obtenir des séances passées : déplacer les dates en base, sans horloge simulée.
 await pool.query(`UPDATE drivy.course_occurrence SET starts_at=starts_at-make_interval(days=>$2+1),ends_at=ends_at-make_interval(days=>$2+1) WHERE series_id=$1`,[pub.id,start+2]);
 const sheet=(await call('GET',`/course-series/${pub.id}/sheet`,undefined,null,'demo-admin')).json().data;
 return {seriesId:pub.id,typeId:type.id,enrollmentId:enrolled.id as string,occurrences:sheet.series.occurrences as {id:string;attendanceRequired:boolean}[]};
}
const mark=(c:{enrollmentId:string},occurrenceId:string,status:string,expectedVersion:number|null,subject='demo-admin',op=randomUUID())=>
 call('PUT',`/course-enrollments/${c.enrollmentId}/attendance/${occurrenceId}`,{operationId:op,status,expectedVersion,note:null},null,subject);
const row=(data:{rows:{enrollmentId:string}[]},enrollmentId:string)=>data.rows.find(r=>r.enrollmentId===enrollmentId) as any;

describe('#42 appel',()=>{
 it('feuille sans présence déduite ; saisie, correction versionnée, historique',async()=>{
  const c=await heldCourse();
  const first=(await call('GET',`/course-series/${c.seriesId}/sheet`,undefined,null,'demo-admin')).json().data;
  expect(row(first,c.enrollmentId).attendance.every((a:{status:string|null})=>a.status===null)).toBe(true);
  expect(row(first,c.enrollmentId).requirements).toEqual({required:2,present:0,missing:2});
  const op=randomUUID();
  const saved=await mark(c,c.occurrences[0]!.id,'ABSENT',null,'demo-admin',op);expect(saved.statusCode,saved.body).toBe(200);
  expect((await mark(c,c.occurrences[0]!.id,'ABSENT',null,'demo-admin',op)).statusCode).toBe(200);
  expect((await mark(c,c.occurrences[0]!.id,'PRESENT',null)).json().code).toBe('VERSION_CONFLICT');
  const fixed=(await mark(c,c.occurrences[0]!.id,'PRESENT',1)).json().data;
  expect(row(fixed,c.enrollmentId).attendance[0]).toMatchObject({status:'PRESENT',version:2});
  expect(row(fixed,c.enrollmentId).requirements).toEqual({required:2,present:1,missing:1});
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.course_attendance_history WHERE enrollment_id=$1',[c.enrollmentId])).rows[0].n).toBe(2);
 });
 it('formateur de la séance autorisé ; autre moniteur, élève, autre école refusés ; séance future refusée',async()=>{
  const c=await heldCourse();
  expect((await mark(c,c.occurrences[0]!.id,'PRESENT',null,'demo-other-instructor')).statusCode).toBe(200);
  expect((await mark(c,c.occurrences[1]!.id,'PRESENT',null,'demo-instructor')).statusCode).toBe(403);
  expect((await mark(c,c.occurrences[1]!.id,'PRESENT',null,'demo-alice')).statusCode).toBe(403);
  expect((await call('PUT',`/v1/schools/${id.schoolB}/course-enrollments/${c.enrollmentId}/attendance/${c.occurrences[1]!.id}`,{operationId:randomUUID(),status:'PRESENT',expectedVersion:null,note:null},null,'demo-foreign')).statusCode).toBe(403);
  await pool.query(`UPDATE drivy.course_occurrence SET starts_at=now()+interval '1 day',ends_at=now()+interval '1 day 2 hours' WHERE id=$1`,[c.occurrences[2]!.id]);
  expect((await mark(c,c.occurrences[2]!.id,'PRESENT',null)).json().code).toBe('COURSE_OCCURRENCE_NOT_STARTED');
 });
});

describe('#81 règlement sur place',()=>{
 it('payé ne coche rien ; annulation avec motif, preuve conservée ; droits',async()=>{
  const c=await heldCourse();
  expect((await call('POST',`/course-enrollments/${c.enrollmentId}/payments`,{operationId:randomUUID(),amountCents:12000,note:null})).statusCode).toBe(403);
  expect((await call('POST',`/course-enrollments/${c.enrollmentId}/payments`,{operationId:randomUUID(),amountCents:12000,note:null},null,'demo-alice')).statusCode).toBe(403);
  const op=randomUUID();
  const paid=await call('POST',`/course-enrollments/${c.enrollmentId}/payments`,{operationId:op,amountCents:12000,note:'Espèces'},null,'demo-admin');
  expect(paid.statusCode,paid.body).toBe(201);
  expect((await call('POST',`/course-enrollments/${c.enrollmentId}/payments`,{operationId:op,amountCents:12000,note:'Espèces'},null,'demo-admin')).statusCode).toBe(201);
  const r=row(paid.json().data,c.enrollmentId);
  expect(r.payments).toHaveLength(1);
  expect(r.attendance.every((a:{status:string|null})=>a.status===null)).toBe(true);
  expect(r.completion).toBeNull();
  expect((await call('POST',`/course-enrollments/${c.enrollmentId}/validate`,{operationId:randomUUID(),note:null},null,'demo-admin')).json().code).toBe('COURSE_REQUIREMENTS_MISSING');
  const voided=await call('POST',`/course-payments/${r.payments[0].id}/void`,{operationId:randomUUID(),reason:'Erreur de saisie'},null,'demo-admin');
  expect(row(voided.json().data,c.enrollmentId).payments[0]).toMatchObject({voidReason:'Erreur de saisie'});
  expect((await call('POST',`/course-payments/${r.payments[0].id}/void`,{operationId:randomUUID(),reason:'Bis'},null,'demo-admin')).json().code).toBe('COURSE_PAYMENT_VOIDED');
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.course_payment_record WHERE enrollment_id=$1',[c.enrollmentId])).rows[0].n).toBe(1);
 });
});

describe('#82 validation',()=>{
 it('validée seulement après les séances obligatoires, par une personne habilitée ; bloque une nouvelle inscription ; retrait tracé',async()=>{
  const c=await heldCourse();
  await mark(c,c.occurrences[0]!.id,'PRESENT',null);
  expect((await call('POST',`/course-enrollments/${c.enrollmentId}/validate`,{operationId:randomUUID(),note:null},null,'demo-admin')).json().code).toBe('COURSE_REQUIREMENTS_MISSING');
  await mark(c,c.occurrences[1]!.id,'PRESENT',null);
  expect((await call('POST',`/course-enrollments/${c.enrollmentId}/validate`,{operationId:randomUUID(),note:null},null,'demo-other-instructor')).statusCode).toBe(403);
  const ok=await call('POST',`/course-enrollments/${c.enrollmentId}/validate`,{operationId:randomUUID(),note:'Deux jours suivis'},null,'demo-admin');
  expect(ok.statusCode,ok.body).toBe(201);
  const completion=row(ok.json().data,c.enrollmentId).completion;expect(completion).toBeTruthy();
  expect((await call('POST',`/course-enrollments/${c.enrollmentId}/validate`,{operationId:randomUUID(),note:null},null,'demo-admin')).json().code).toBe('COURSE_ALREADY_COMPLETED');
  const progress=(await call('GET','/course-progress/me',undefined,null,'demo-alice')).json().data;
  expect(progress.completions.map((x:{typeId:string})=>x.typeId)).toContain(c.typeId);
  expect(JSON.stringify(progress)).not.toContain('amountCents');
  // Nouvelle série du même type : « Déjà effectué ».
  const draft=(await call('POST','/course-series',{operationId:randomUUID(),typeId:c.typeId,title:'Session suivante',description:'',location:'',conditions:'',teachingLanguage:null,
   responsibleMembershipId:id.adminMember,capacity:5,minParticipants:null,timeZone:'Europe/Zurich',occurrences:[{startsAt:at(cursor+=4,8),endsAt:at(cursor,11),instructorMembershipId:id.otherInstructorMember,attendanceRequired:true}]},null,'demo-admin')).json().data;
  const pub=(await call('POST',`/course-series/${draft.id}/publish`,{operationId:randomUUID()},draft.version,'demo-admin')).json().data;
  expect((await call('POST',`/course-series/${pub.id}/enroll`,{operationId:randomUUID()},null,'demo-alice')).json().code).toBe('COURSE_ALREADY_COMPLETED');
  // Retrait avec motif : l'élève peut de nouveau s'inscrire ; l'historique reste.
  expect((await call('POST',`/course-completions/${completion.id}/revoke`,{operationId:randomUUID(),reason:''},null,'demo-admin')).statusCode).toBe(400);
  expect((await call('POST',`/course-completions/${completion.id}/revoke`,{operationId:randomUUID(),reason:'Saisie erronée'},null,'demo-admin')).statusCode).toBe(200);
  expect((await call('POST',`/course-series/${pub.id}/enroll`,{operationId:randomUUID()},null,'demo-alice')).statusCode).toBe(201);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.course_completion WHERE learner_id=$1 AND type_id=$2',[id.aliceLearner,c.typeId])).rows[0].n).toBe(1);
 });
 it('validations concurrentes : une seule',async()=>{
  const c=await heldCourse();
  await mark(c,c.occurrences[0]!.id,'PRESENT',null);await mark(c,c.occurrences[1]!.id,'PRESENT',null);
  const results=await Promise.all([0,1].map(()=>call('POST',`/course-enrollments/${c.enrollmentId}/validate`,{operationId:randomUUID(),note:null},null,'demo-admin')));
  expect(results.map(r=>r.statusCode).sort()).toEqual([201,409]);
 });
});
