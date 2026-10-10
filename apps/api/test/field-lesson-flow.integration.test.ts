import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,prepareCommercial,lessonBody,moveToPast,id,type Call} from './support/harness.js';

let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
let school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
let day=50;
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);commercial=await prepareCommercial(call);});
afterAll(async()=>{await app?.close();await pool?.end();});
const training=async(subject='demo-instructor')=>(await call('GET',`/trainings/${id.aliceTraining}`,undefined,null,subject)).json().data;
async function planned(){const r=await call('POST','/lessons',lessonBody(commercial,school.policy,day++));expect(r.statusCode,r.body).toBe(201);await moveToPast(pool,r.json().data.id);return r.json().data;}
const completeBody=()=>({operationId:randomUUID(),actualStart:new Date(Date.now()-60_000).toISOString(),actualEnd:new Date().toISOString(),anomalyReason:'Recette synthétique sans contrôle de permis'});

describe('essai terrain : proposer seulement une formation que ce moniteur peut conduire',()=>{
 it('ADMIN voit les dossiers, mais seule une affectation personnelle autorise le départ',async()=>{
  expect((await training()).startNowBlockerCode).toBeNull();
  expect((await training('demo-admin')).startNowBlockerCode).toBe('INSTRUCTOR_REQUIRED');
  expect((await training('demo-alice')).startNowBlockerCode).toBe('INSTRUCTOR_REQUIRED');
  await pool.query("UPDATE drivy.membership SET roles=ARRAY['ADMIN','INSTRUCTOR'] WHERE id=$1",[id.adminMember]);
  try{
   expect((await training('demo-admin')).startNowBlockerCode).toBe('INSTRUCTOR_NOT_ASSIGNED');
   const all=await call('GET','/learners',undefined,null,'demo-admin');expect(all.json().data.items).toHaveLength(2);
   const own=await call('GET',`/learners?instructorMembershipId=${id.adminMember}`,undefined,null,'demo-admin');expect(own.json().data.items).toEqual([]);
   const assigned=await call('GET',`/learners?instructorMembershipId=${id.instructorMember}`,undefined,null,'demo-admin');expect(assigned.json().data.items.map((l:{id:string})=>l.id)).toEqual([id.aliceLearner]);
   const refused=await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:id.aliceTraining},null,'demo-admin');expect(refused.json().code).toBe('INSTRUCTOR_NOT_ASSIGNED');
   expect((await pool.query('SELECT count(*)::int AS n FROM drivy.instructor_assignment WHERE instructor_membership_id=$1',[id.adminMember])).rows[0].n).toBe(0);
   const page=await call('GET',`/trainings?learnerId=${id.aliceLearner}`,undefined,null,'demo-admin');expect(page.json().data.items[0].startNowBlockerCode).toBe('INSTRUCTOR_NOT_ASSIGNED');
  }finally{await pool.query("UPDATE drivy.membership SET roles=ARRAY['ADMIN'] WHERE id=$1",[id.adminMember]);}
 });
 it('la projection signale une affectation trop courte, une formation inactive et une offre désactivée',async()=>{
  await pool.query("UPDATE drivy.instructor_assignment SET valid_until=now()+interval '10 minutes' WHERE id=$1",[id.assignment]);
  try{expect((await training()).startNowBlockerCode).toBe('ASSIGNMENT_ENDS_BEFORE_LESSON_END');
   expect((await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:id.aliceTraining})).json().code).toBe('INSTRUCTOR_NOT_ASSIGNED');
  }finally{await pool.query('UPDATE drivy.instructor_assignment SET valid_until=NULL WHERE id=$1',[id.assignment]);}
  await pool.query("UPDATE drivy.training SET status='PAUSED' WHERE id=$1",[id.aliceTraining]);
  try{expect((await training()).startNowBlockerCode).toBe('TRAINING_NOT_ACTIVE');}finally{await pool.query("UPDATE drivy.training SET status='ACTIVE' WHERE id=$1",[id.aliceTraining]);}
  await pool.query('UPDATE drivy.offering_version SET enabled=false WHERE id=$1',[id.offeringA]);
  try{expect((await training()).startNowBlockerCode).toBe('OFFERING_NOT_READY');}finally{await pool.query('UPDATE drivy.offering_version SET enabled=true WHERE id=$1',[id.offeringA]);}
 });
 it('une affectation commencée pendant la minute courante permet le départ à son instant réel',async()=>{
  // L'ancien arrondi minute plaçait artificiellement le début avant l'affectation.
  if(Date.now()%60_000<20)await new Promise(resolve=>setTimeout(resolve,25));
  await pool.query("UPDATE drivy.instructor_assignment SET valid_from=date_trunc('minute',now())+interval '1 millisecond' WHERE id=$1",[id.assignment]);
  try{
   expect((await training()).startNowBlockerCode).toBeNull();
   const before=Date.now(),body={operationId:randomUUID(),trainingId:id.aliceTraining};
   const r=await call('POST','/lessons/start-now',body);expect(r.statusCode,r.body).toBe(201);
   expect(Date.parse(r.json().data.plannedStart)).toBeGreaterThanOrEqual(before);
   expect((await call('POST','/lessons/start-now',body)).json().data).toEqual(r.json().data);
   expect((await call('POST',`/lessons/${r.json().data.id}/cancel`,{operationId:randomUUID(),reasonCode:'OTHER'},r.json().data.version)).statusCode).toBe(200);
  }finally{await pool.query("UPDATE drivy.instructor_assignment SET valid_from='2026-01-01T00:00:00Z' WHERE id=$1",[id.assignment]);}
 });
});

describe('bilan facultatif et fin de leçon unique',()=>{
 it('termine sans texte et rejoue la même complétion sans charge, brouillon ou événement supplémentaire',async()=>{
  const lesson=await planned(),body=completeBody(),route=`/lessons/${lesson.id}/complete`;
  const [a,b]=await Promise.all([call('POST',route,body,lesson.version),call('POST',route,body,lesson.version)]);
  expect(a.statusCode,a.body).toBe(200);expect(b.statusCode,b.body).toBe(200);expect(b.json().data).toEqual(a.json().data);
  expect(a.json().data.lesson).toMatchObject({status:'COMPLETED',actualStart:body.actualStart,actualEnd:body.actualEnd});
  expect(a.json().data.draft).toMatchObject({workedOn:'',observationText:'',nextStep:'',observations:[]});
  const count=(table:string,where:string,value:string)=>pool.query(`SELECT count(*)::int AS n FROM drivy.${table} WHERE ${where}=$1`,[value]);
  expect((await count('report_draft','lesson_id',lesson.id)).rows[0].n).toBe(1);
  expect((await count('charge_entry','operation_id',body.operationId)).rows[0].n).toBe(1);
  expect((await count('audit_event','operation_id',body.operationId)).rows[0].n).toBe(1);
  expect((await count('lesson_event_outbox','operation_id',body.operationId)).rows[0].n).toBe(1);
  const draft=a.json().data.draft,draftRoute=`/report-drafts/${draft.id}`,save={operationId:randomUUID()};
  const saved=await call('PUT',draftRoute,save,draft.version);expect(saved.statusCode,saved.body).toBe(200);
  expect(saved.json().data).toMatchObject({workedOn:'',observationText:'',nextStep:'',observations:[],attachmentIds:[]});
  expect((await call('PUT',draftRoute,save,draft.version)).json().data).toEqual(saved.json().data);
  // L'ancienne publication explicite reste compatible, même avec un bilan entièrement vide.
  const published=await call('POST',`${draftRoute}/publish`,{operationId:randomUUID(),expectedPublicationVersion:saved.json().data.basePublicationVersion,captureSelection:null,textObservationSelection:[]},saved.json().data.version);
  expect(published.statusCode,published.body).toBe(200);expect(published.json().data).toMatchObject({workedOn:'',observationText:'',nextStep:'',observations:[]});
  expect((await call('GET',`/report-revisions/${published.json().data.id}`,undefined,null,'demo-alice')).statusCode).toBe(200);
 });
 it('accepte une appréciation sans commentaire et présente Anticipation sans modifier le référentiel',async()=>{
  await pool.query("UPDATE drivy.competency_definition SET label='Anticipation et partage de la route' WHERE id=$1",[school.competency]);
  const curricula=await call('GET','/curricula');expect(curricula.json().data.items[0].competencies.find((c:{id:string})=>c.id===school.competency).label).toBe('Anticipation');
  const lesson=await planned(),completed=await call('POST',`/lessons/${lesson.id}/complete`,completeBody(),lesson.version);expect(completed.statusCode,completed.body).toBe(200);
  const draft=completed.json().data.draft;
  const saved=await call('PUT',`/report-drafts/${draft.id}`,{operationId:randomUUID(),observations:[{competencyId:school.competency,level:'GUIDED'}]},draft.version);
  expect(saved.statusCode,saved.body).toBe(200);expect(saved.json().data.observations[0]).toMatchObject({level:'GUIDED',context:''});
  const progress=await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-alice');expect(progress.statusCode,progress.body).toBe(200);
  expect(progress.json().data.items[0]).toMatchObject({label:'Anticipation',context:'',level:'GUIDED'});
  expect((await pool.query('SELECT label FROM drivy.competency_definition WHERE id=$1',[school.competency])).rows[0].label).toBe('Anticipation et partage de la route');
 });
});

describe('choix GPS général réutilisable et droits conservés',()=>{
 it('le moniteur affecté note une fois le choix, réutilisé par deux leçons sans remplacer un refus de l’élève',async()=>{
  const first=await planned(),second=await planned(),route=`/learners/${id.aliceLearner}/recording-choice`;
  const body={operationId:randomUUID(),lessonId:null,status:'ALLOWED',noticeVersionId:school.notice,source:'RECORDED_VERBAL'};
  expect((await call('POST',route,{...body,operationId:randomUUID()},null,'demo-admin')).statusCode).toBe(404);
  expect((await call('POST',route,{...body,operationId:randomUUID()},null,'demo-other-instructor')).statusCode).toBe(404);
  const choice=await call('POST',route,body);expect(choice.statusCode,choice.body).toBe(200);expect(choice.json().data.lessonId).toBeNull();
  for(const lesson of [first,second])expect((await call('GET',`${route}?lessonId=${lesson.id}`)).json().data.id).toBe(choice.json().data.id);
  expect((await call('POST',route,body)).json().data).toEqual(choice.json().data);
  const refused=await call('POST',route,{...body,operationId:randomUUID(),status:'REFUSED',source:'SELF'},null,'demo-alice');expect(refused.statusCode,refused.body).toBe(200);
  expect((await call('POST',route,{...body,operationId:randomUUID()})).json().code).toBe('RECORDING_CHOICE_PROTECTED');
  expect((await call('GET',`${route}?lessonId=${second.id}`)).json().data.status).toBe('REFUSED');
  expect((await call('POST',route,{...body,operationId:randomUUID(),noticeVersionId:randomUUID()})).json().code).toBe('RECORDING_NOTICE_CHANGED');
 });
});
