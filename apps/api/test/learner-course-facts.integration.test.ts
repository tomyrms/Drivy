import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,type Call} from './support/harness.js';

let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));await prepareSchool(pool);});
afterAll(async()=>{await app?.close();await pool?.end();});
const path=`/learners/${id.aliceLearner}/course-facts`;
const read=(subject='demo-admin',route=path)=>call('GET',route,undefined,null,subject);
let offset=20;
const at=(day:number,hour:number)=>{const value=new Date();value.setUTCDate(value.getUTCDate()+day);value.setUTCHours(hour,0,0,0);return value.toISOString();};
async function heldCourse(typeId:string){
 const day=offset+=4;
 const draft=await call('POST','/course-series',{operationId:randomUUID(),typeId,title:'Recette synthétique',description:'',location:'',conditions:'',teachingLanguage:null,
  responsibleMembershipId:id.adminMember,capacity:5,minParticipants:null,timeZone:'Europe/Zurich',occurrences:[0,1].map(index=>({startsAt:at(day+index,8),endsAt:at(day+index,10),instructorMembershipId:id.otherInstructorMember,attendanceRequired:true}))},null,'demo-admin');
 expect(draft.statusCode,draft.body).toBe(201);
 const series=draft.json().data;
 const publication=await call('POST',`/course-series/${series.id}/publish`,{operationId:randomUUID()},series.version,'demo-admin');expect(publication.statusCode,publication.body).toBe(200);
 const enrolled=await call('POST',`/course-series/${series.id}/enroll`,{operationId:randomUUID()},null,'demo-alice');expect(enrolled.statusCode,enrolled.body).toBe(201);
 await pool.query('UPDATE drivy.course_occurrence SET starts_at=starts_at-make_interval(days=>$2+2),ends_at=ends_at-make_interval(days=>$2+2) WHERE series_id=$1',[series.id,day]);
 return {seriesId:series.id as string,enrollmentId:enrolled.json().data.me.enrollment.id as string,occurrences:series.occurrences as {id:string}[]};
}
async function mark(course:Awaited<ReturnType<typeof heldCourse>>,index:number){
 const response=await call('PUT',`/course-enrollments/${course.enrollmentId}/attendance/${course.occurrences[index]!.id}`,{operationId:randomUUID(),status:'PRESENT',expectedVersion:null,note:null},null,'demo-admin');
 expect(response.statusCode,response.body).toBe(200);
}
async function validate(course:Awaited<ReturnType<typeof heldCourse>>){
 const response=await call('POST',`/course-enrollments/${course.enrollmentId}/validate`,{operationId:randomUUID(),note:'Validation interne synthétique, sans certificat'},null,'demo-admin');
 expect(response.statusCode,response.body).toBe(201);
 return response.json().data.rows.find((item:{enrollmentId:string})=>item.enrollmentId===course.enrollmentId).completion.id as string;
}

describe('S10 : faits internes des cours dans le dossier élève',()=>{
 it('distingue une lecture vide réussie, un droit refusé et un dossier hors périmètre',async()=>{
  const result=await read();expect(result.statusCode,result.body).toBe(200);
  expect(result.json().data).toEqual({schoolId:id.schoolA,learnerId:id.aliceLearner,completions:[],enrollments:[]});
  expect((await read('demo-alice')).json().data).toEqual(result.json().data);
  expect((await read('demo-instructor')).statusCode).toBe(403);
  expect((await read('demo-bob')).statusCode).toBe(404);
  expect((await read('demo-admin',`/learners/${randomUUID()}/course-facts`)).statusCode).toBe(404);
  expect((await read('demo-foreign')).statusCode).toBe(403);
  expect((await read('demo-foreign',`/v1/schools/${id.schoolB}${path}`)).statusCode).toBe(404);
  expect((await read('demo-admin',`${path}?all=1`)).statusCode).toBe(400);
 });
 it('relit les droits au serveur et garde l’accès au dossier requis',async()=>{
  await pool.query("UPDATE drivy.membership SET grants='{MANAGE_COURSES}' WHERE id=ANY($1::uuid[])",[[id.instructorMember,id.otherInstructorMember]]);
  expect((await read('demo-instructor')).statusCode).toBe(200);
  expect((await read('demo-other-instructor')).statusCode).toBe(404);
  await pool.query("UPDATE drivy.membership SET grants='{}' WHERE id=ANY($1::uuid[])",[[id.instructorMember,id.otherInstructorMember]]);
  expect((await read('demo-instructor')).statusCode).toBe(403);
 });
 it('sépare présence, validation interne datée et retrait sans fabriquer une attestation',async()=>{
  const type=(await pool.query("SELECT id FROM drivy.course_type WHERE stable_key='AWARENESS'")).rows[0].id as string;
  const course=await heldCourse(type);
  await mark(course,0);
  const presence=(await read()).json().data;
  expect(presence.completions).toEqual([]);
  expect(presence.enrollments).toHaveLength(1);
  expect(presence.enrollments[0]).toMatchObject({enrollmentId:course.enrollmentId,typeKey:'AWARENESS',requirements:{required:2,present:1,missing:1}});
  await mark(course,1);
  expect((await read()).json().data.completions).toEqual([]);
  const completionId=await validate(course);
  const stored=(await pool.query('SELECT validated_at FROM drivy.course_completion WHERE id=$1',[completionId])).rows[0];
  const facts=(await read('demo-alice')).json().data;
  expect(facts.completions).toEqual([{id:completionId,typeKey:'AWARENESS',validatedAt:stored.validated_at.toISOString(),seriesId:course.seriesId}]);
  expect(JSON.stringify(facts)).not.toMatch(/completedOn|certificate|note|amountCents|personId|displayName/);
  const revoked=await call('POST',`/course-completions/${completionId}/revoke`,{operationId:randomUUID(),reason:'Correction synthétique'},null,'demo-admin');expect(revoked.statusCode,revoked.body).toBe(200);
  const after=(await read()).json().data;
  expect(after.completions).toEqual([]);expect(after.enrollments[0].requirements).toEqual({required:2,present:2,missing:0});
 });
 it('reconnaît les premiers secours par stableKey et ignore un cours personnalisé homonyme',async()=>{
  const type=(await pool.query("SELECT id FROM drivy.course_type WHERE stable_key='FIRST_AID'")).rows[0].id as string;
  const course=await heldCourse(type);await mark(course,0);await mark(course,1);await validate(course);
  const custom=await call('POST','/course-types',{operationId:randomUUID(),title:'Premiers secours',description:'Homonyme synthétique'},null,'demo-admin');expect(custom.statusCode,custom.body).toBe(201);
  const other=await heldCourse(custom.json().data.id);await mark(other,0);await mark(other,1);await validate(other);
  const data=(await read()).json().data;
  expect(data.completions.map((item:{typeKey:string})=>item.typeKey)).toEqual(['FIRST_AID']);
  expect(data.enrollments.map((item:{seriesId:string})=>item.seriesId)).not.toContain(other.seriesId);
  expect(data.enrollments.find((item:{seriesId:string})=>item.seriesId===course.seriesId)?.typeKey).toBe('FIRST_AID');
 });
});
