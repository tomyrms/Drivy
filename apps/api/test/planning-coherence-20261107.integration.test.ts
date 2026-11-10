import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareCommercial,prepareSchool,lessonBody,slot,id,type Call} from './support/harness.js';

/**
 * Lot A de l'audit du 7 novembre 2026 (#423, #424, #439, #444). PostgreSQL réelle, données synthétiques.
 * Les commandes d'une école se sérialisent sur le verrou de l'école (commands.ts) : la concurrence est donc rejouée comme
 * dans course-concurrency.integration.test.ts, en retenant ce verrou jusqu'à ce que les deux requêtes y soient suspendues.
 */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);commercial=await prepareCommercial(call);});
afterAll(async()=>{await app?.close();await pool?.end();});
const admin='demo-admin',staff='demo-instructor';
type Response=Awaited<ReturnType<Call>>;
const at=(offset:number,hourUtc:number,minute=0)=>{const d=new Date();d.setUTCDate(d.getUTCDate()+offset);d.setUTCHours(hourUtc,minute,0,0);return d.toISOString();};

let nextDay=200;
async function draft(occurrences:{day:number;from:number;to:number;instructor?:string}[]){
 const type=(await call('POST','/course-types',{operationId:randomUUID(),title:`Type ${randomUUID()}`,description:''},null,admin)).json().data.id;
 const created=await call('POST','/course-series',{operationId:randomUUID(),typeId:type,title:'Cours de recette',description:'',location:'Salle',conditions:'',teachingLanguage:null,
  responsibleMembershipId:id.adminMember,capacity:10,minParticipants:null,timeZone:'Europe/Zurich',
  occurrences:occurrences.map(o=>({startsAt:at(o.day,o.from),endsAt:at(o.day,o.to),instructorMembershipId:o.instructor??id.otherInstructorMember,attendanceRequired:true}))},null,admin);
 if(created.statusCode!==201)throw new Error(created.body);
 return created.json().data as {id:string;version:number;occurrences:{id:string;position:number;startsAt:string;endsAt:string}[]};
}
const publish=(series:{id:string;version:number})=>call('POST',`/course-series/${series.id}/publish`,{operationId:randomUUID()},series.version,admin);
const closure=(instructor:string,startsAt:string,endsAt:string)=>call('POST','/closures',{operationId:randomUUID(),instructorMembershipId:instructor,startsAt,endsAt,reason:'Congé de recette'},null,admin);
const closures=async(instructor:string)=>(await pool.query<{n:number}>('SELECT count(*)::int AS n FROM drivy.closure WHERE school_id=$1 AND instructor_membership_id=$2 AND removed_at IS NULL',[id.schoolA,instructor])).rows[0]!.n;
const seriesRow=async(seriesId:string)=>(await pool.query<{status:string;version:number}>('SELECT status,version FROM drivy.course_series WHERE id=$1',[seriesId])).rows[0]!;
const seriesHolds=async(seriesId:string)=>(await pool.query<{n:number}>('SELECT count(*)::int AS n FROM drivy.reservation r JOIN drivy.course_occurrence o ON o.id=r.course_occurrence_id WHERE o.series_id=$1 AND r.active',[seriesId])).rows[0]!.n;

async function simultaneously(first:()=>ReturnType<Call>,second:()=>ReturnType<Call>):Promise<[Response,Response]>{
 const starts=[first,second],blocker=await pool.connect();
 let pending:ReturnType<Call>[]=[];
 try{
  await blocker.query('BEGIN');await blocker.query('SELECT id FROM drivy.school WHERE id=$1 FOR UPDATE',[id.schoolA]);
  pending=starts.map(start=>start());
  const deadline=Date.now()+8_000;let waiting=0;
  while(Date.now()<deadline&&waiting<starts.length){
   waiting=(await pool.query<{n:number}>("SELECT count(*)::int AS n FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND pid<>pg_backend_pid()")).rows[0]!.n;
   if(waiting<starts.length)await new Promise(resolve=>setTimeout(resolve,10));
  }
  expect(waiting).toBe(starts.length);
 }finally{await blocker.query('COMMIT');blocker.release();}
 return Promise.all(pending) as Promise<[Response,Response]>;
}

async function freshTraining(){
 const offering=randomUUID(),training=randomUUID();
 await pool.query(`INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version,enabled,curriculum_version_id,policy_version_id,default_duration_minutes,default_price_cents)
  VALUES($1,$2,$3,'B',1,true,$4,$5,50,9000)`,[offering,id.schoolA,`audit-${offering}`,school.curriculum,school.policy]);
 await pool.query(`INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on) VALUES($1,$2,$3,$4,$5,'ACTIVE',current_date)`,
  [training,id.schoolA,id.aliceLearner,offering,`audit-${offering}`]);
 await pool.query(`INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES($1,$2,$3,$4,now()-interval '1 day')`,
  [randomUUID(),id.schoolA,training,id.instructorMember]);
 return training;
}
const examBody=(day:number,escort?:{from:number;to:number},extra:Record<string,unknown>={})=>({operationId:randomUUID(),startsAt:slot(day,9).plannedStart,timeZone:'Europe/Zurich',location:'Centre d’examen (synthétique)',
 ...(escort?{escort:{instructorMembershipId:id.instructorMember,startsAt:at(day,escort.from),endsAt:at(day,escort.to)}}:{}),...extra});
const createExam=(training:string,day:number,escort?:{from:number;to:number})=>call('POST',`/trainings/${training}/exams`,{kind:'PRACTICAL',...examBody(day,escort)},null,staff);
const heldBy=async(examId:string)=>(await pool.query<{n:number}>('SELECT count(*)::int AS n FROM drivy.reservation WHERE exam_id=$1 AND active',[examId])).rows[0]!.n;
const examCount=async(training:string)=>(await pool.query<{n:number}>('SELECT count(*)::int AS n FROM drivy.exam WHERE training_id=$1',[training])).rows[0]!.n;

/** Exécute une requête avec la vraie identité d'une personne : rôle drivy_app (RLS appliquée) et contexte d'école/personne posés comme le fait commands.ts. */
async function asApp<T>(person:string,schoolId:string,sql:string,params:unknown[]=[]):Promise<T[]>{
 const client=await pool.connect();
 try{
  await client.query('BEGIN');await client.query('SET LOCAL ROLE drivy_app');
  await client.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true)",[schoolId,person]);
  return (await client.query(sql,params)).rows as T[];
 }finally{await client.query('ROLLBACK');client.release();}
}
const unavailable=(person:string,schoolId:string,instructor:string,from:string,to:string)=>
 asApp<{unavailable:boolean}>(person,schoolId,'SELECT drivy.instructor_unavailable($1,$2,$3::timestamptz,$4::timestamptz) AS unavailable',[id.schoolA,instructor,from,to]);

describe('#423 un collègue non administrateur ne voit pas le congé, mais en subit le refus',()=>{
 it('la publication d’un cours par un moniteur MANAGE_COURSES est refusée pour le congé d’un collègue',async()=>{
  await pool.query("UPDATE drivy.membership SET grants=ARRAY['MANAGE_COURSES'] WHERE id=$1",[id.instructorMember]);
  const day=nextDay++,series=await draft([{day,from:9,to:10}]);
  expect((await closure(id.otherInstructorMember,at(day,8),at(day,17))).statusCode).toBe(201);
  // Preuve de portée : ce moniteur ne lit aucune ligne de congé de son collègue (lecture générale inchangée).
  expect(await asApp(id.instructor,id.schoolA,'SELECT 1 FROM drivy.closure WHERE instructor_membership_id=$1',[id.otherInstructorMember])).toHaveLength(0);
  const res=await call('POST',`/course-series/${series.id}/publish`,{operationId:randomUUID()},series.version,staff);
  expect(res.statusCode,res.body).toBe(409);expect(res.json().code).toBe('COURSE_INSTRUCTOR_CLOSED');
  expect(await seriesRow(series.id)).toEqual({status:'DRAFT',version:series.version});expect(await seriesHolds(series.id)).toBe(0);
  // Sans congé sur ce créneau, le même moniteur publie normalement.
  const free=await draft([{day:nextDay++,from:9,to:10}]);
  expect((await call('POST',`/course-series/${free.id}/publish`,{operationId:randomUUID()},free.version,staff)).statusCode).toBe(200);
 });
 it('la replanification par ce moniteur est refusée de la même façon',async()=>{
  const day=nextDay++,other=nextDay++,series=await draft([{day,from:9,to:10}]);
  const published=(await call('POST',`/course-series/${series.id}/publish`,{operationId:randomUUID()},series.version,staff)).json().data;
  expect((await closure(id.otherInstructorMember,at(other,8),at(other,17))).statusCode).toBe(201);
  const moved=await call('POST',`/course-series/${series.id}/reschedule`,{operationId:randomUUID(),occurrences:[{position:1,startsAt:at(other,9),endsAt:at(other,10),instructorMembershipId:id.otherInstructorMember}]},published.version,staff);
  expect(moved.statusCode,moved.body).toBe(409);expect(moved.json().code).toBe('COURSE_INSTRUCTOR_CLOSED');
  expect(await seriesRow(series.id)).toEqual({status:'PUBLISHED',version:published.version});
 });
 it('un accompagnateur affecté, en congé, est refusé à la création, à la modification et au report par un autre moniteur',async()=>{
  const training=await freshTraining(),day=nextDay++,other=nextDay++;
  await pool.query(`INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES($1,$2,$3,$4,now()-interval '1 day')`,[randomUUID(),id.schoolA,training,id.otherInstructorMember]);
  expect((await closure(id.otherInstructorMember,at(day,8),at(day,17))).statusCode).toBe(201);
  const withOther=(d:number,extra:Record<string,unknown>={})=>({...examBody(d,undefined,extra),escort:{instructorMembershipId:id.otherInstructorMember,startsAt:at(d,9),endsAt:at(d,11)}});
  const refused=await call('POST',`/trainings/${training}/exams`,{kind:'PRACTICAL',...withOther(day)},null,staff);
  expect(refused.statusCode,refused.body).toBe(409);expect(refused.json().code).toBe('EXAM_ESCORT_CONFLICT');expect(await examCount(training)).toBe(0);
  const plain=await createExam(training,day);expect(plain.statusCode,plain.body).toBe(201);const exam=plain.json().data.exams[0];
  const update=await call('POST',`/exams/${exam.id}/update`,withOther(day,{reason:''}),exam.version,staff);
  expect(update.statusCode,update.body).toBe(409);expect(update.json().code).toBe('EXAM_ESCORT_CONFLICT');expect(await heldBy(exam.id)).toBe(0);
  const postpone=await call('POST',`/exams/${exam.id}/postpone`,{...withOther(day),reason:'Report'},exam.version,staff);
  expect(postpone.statusCode,postpone.body).toBe(409);expect(postpone.json().code).toBe('EXAM_ESCORT_CONFLICT');
  expect((await pool.query("SELECT status FROM drivy.exam WHERE id=$1",[exam.id])).rows[0].status).toBe('SCHEDULED');
  // Hors congé, le même accompagnateur est accepté.
  const ok=await call('POST',`/exams/${exam.id}/update`,withOther(other,{reason:''}),exam.version,staff);expect(ok.statusCode,ok.body).toBe(200);
 });
 it('la fonction répond oui/non au personnel de l’école et ne dit rien à un autre appelant',async()=>{
  const day=nextDay++;
  expect((await closure(id.otherInstructorMember,at(day,8),at(day,17))).statusCode).toBe(201);
  const [from,to]=[at(day,9),at(day,10)];
  expect((await unavailable(id.instructor,id.schoolA,id.otherInstructorMember,from,to))[0]!.unavailable).toBe(true);
  expect((await unavailable(id.instructor,id.schoolA,id.otherInstructorMember,at(day,17),at(day,18)))[0]!.unavailable).toBe(false);
  expect((await unavailable(id.instructor,id.schoolA,id.adminMember,from,to))[0]!.unavailable).toBe(false);
  // Élève de l'école, personne d'une autre école (contexte B ou contexte A), personne inconnue : refus sans réponse.
  await expect(unavailable(id.alice,id.schoolA,id.otherInstructorMember,from,to)).rejects.toThrow(/ACCESS_DENIED/);
  await expect(unavailable(id.foreign,id.schoolB,id.otherInstructorMember,from,to)).rejects.toThrow(/ACCESS_DENIED/);
  await expect(unavailable(id.foreign,id.schoolA,id.otherInstructorMember,from,to)).rejects.toThrow(/ACCESS_DENIED/);
  await expect(unavailable(randomUUID(),id.schoolA,id.otherInstructorMember,from,to)).rejects.toThrow(/ACCESS_DENIED/);
 });
});

describe('#423 congés, cours et accompagnements d’examen',()=>{
 it('un congé couvrant le cours refuse la publication sans rien occuper',async()=>{
  const day=nextDay++,series=await draft([{day,from:9,to:10}]);
  expect((await closure(id.otherInstructorMember,at(day,8),at(day,17))).statusCode).toBe(201);
  const res=await publish(series);expect(res.statusCode,res.body).toBe(409);
  expect(await seriesRow(series.id)).toEqual({status:'DRAFT',version:series.version});expect(await seriesHolds(series.id)).toBe(0);
 });
 it('un congé refuse aussi la replanification d’un cours publié, sans effet partiel',async()=>{
  const day=nextDay++,other=nextDay++,series=await draft([{day,from:9,to:10}]);
  const published=(await publish(series)).json().data;
  expect((await closure(id.otherInstructorMember,at(other,8),at(other,17))).statusCode).toBe(201);
  const moved=await call('POST',`/course-series/${series.id}/reschedule`,{operationId:randomUUID(),occurrences:[{position:1,startsAt:at(other,9),endsAt:at(other,10),instructorMembershipId:id.otherInstructorMember}]},published.version,admin);
  expect(moved.statusCode,moved.body).toBe(409);
  expect(await seriesRow(series.id)).toEqual({status:'PUBLISHED',version:published.version});
  const o=(await pool.query<{starts_at:Date}>('SELECT starts_at FROM drivy.course_occurrence WHERE series_id=$1',[series.id])).rows[0]!;
  expect(o.starts_at.toISOString()).toBe(at(day,9));expect(await seriesHolds(series.id)).toBe(1);
 });
 it('un congé refuse de réserver ou de déplacer l’accompagnement d’un examen',async()=>{
  const training=await freshTraining(),day=nextDay++,other=nextDay++;
  expect((await closure(id.instructorMember,at(day,8),at(day,17))).statusCode).toBe(201);
  const refused=await createExam(training,day,{from:9,to:11});expect(refused.statusCode,refused.body).toBe(409);expect(await examCount(training)).toBe(0);
  // Examen sans accompagnement pendant le congé : permis ; lui ajouter ensuite l'accompagnement est refusé.
  const plain=await createExam(training,day);expect(plain.statusCode,plain.body).toBe(201);
  const exam=plain.json().data.exams[0];
  const withEscort=await call('POST',`/exams/${exam.id}/update`,examBody(day,{from:9,to:11},{reason:''}),exam.version,staff);
  expect(withEscort.statusCode,withEscort.body).toBe(409);expect(await heldBy(exam.id)).toBe(0);
  // Déplacer l'accompagnement d'un examen existant sur le congé est refusé et garde l'ancienne occupation.
  const good=await call('POST',`/exams/${exam.id}/update`,examBody(other,{from:9,to:11},{reason:''}),exam.version,staff);expect(good.statusCode,good.body).toBe(200);
  const v=good.json().data.exams.find((e:{id:string})=>e.id===exam.id).version;
  const back=await call('POST',`/exams/${exam.id}/update`,examBody(day,{from:10,to:12},{reason:''}),v,staff);expect(back.statusCode,back.body).toBe(409);
  expect(await heldBy(exam.id)).toBe(1);
 });
 it('un congé sur un cours publié ou un accompagnement existant est refusé, sans congé créé',async()=>{
  const day=nextDay++,series=await draft([{day,from:9,to:10}]);await publish(series);
  const closuresBefore=await closures(id.otherInstructorMember),examClosuresBefore=await closures(id.instructorMember);
  const refused=await closure(id.otherInstructorMember,at(day,8),at(day,17));expect(refused.statusCode,refused.body).toBe(409);expect(refused.json().code).toBe('EXISTING_BOOKINGS');
  expect(await closures(id.otherInstructorMember)).toBe(closuresBefore);
  const training=await freshTraining(),examDay=nextDay++;expect((await createExam(training,examDay,{from:9,to:11})).statusCode).toBe(201);
  const second=await closure(id.instructorMember,at(examDay,10),at(examDay,12));expect(second.statusCode,second.body).toBe(409);expect(second.json().code).toBe('EXISTING_BOOKINGS');
  expect(await closures(id.instructorMember)).toBe(examClosuresBefore);
 });
 it('créneaux adjacents et cours hors congé restent possibles',async()=>{
  const day=nextDay++,series=await draft([{day,from:9,to:10}]);
  expect((await closure(id.otherInstructorMember,at(day,10),at(day,17))).statusCode).toBe(201);
  expect((await publish(series)).statusCode).toBe(200);
  const earlier=await draft([{day,from:7,to:8,instructor:id.otherInstructorMember}]);
  // Congé 10h–17h puis cours 17h–18h : la fin du congé est exclusive.
  const later=await draft([{day,from:17,to:18}]);
  expect((await publish(earlier)).statusCode).toBe(200);expect((await publish(later)).statusCode).toBe(200);
  const training=await freshTraining(),examDay=nextDay++;
  expect((await closure(id.instructorMember,at(examDay,12),at(examDay,18))).statusCode).toBe(201);
  expect((await createExam(training,examDay,{from:9,to:12})).statusCode).toBe(201);
  const adjacentClosure=await closure(id.instructorMember,at(examDay,8),at(examDay,9));expect(adjacentClosure.statusCode,adjacentClosure.body).toBe(201);
 });
 it('congé et publication simultanés : un seul réussit, aucune occupation partielle',async()=>{
  const day=nextDay++,series=await draft([{day,from:9,to:10}]);
  const [a,b]=await simultaneously(()=>closure(id.otherInstructorMember,at(day,8),at(day,17)),()=>publish(series));
  expect([a.statusCode===201,b.statusCode===200].filter(Boolean)).toHaveLength(1);
  const loser=a.statusCode===201?b:a;expect(loser.statusCode).toBe(409);
  if(a.statusCode===201){expect(await seriesRow(series.id)).toEqual({status:'DRAFT',version:series.version});expect(await seriesHolds(series.id)).toBe(0);}
  else{expect((await seriesRow(series.id)).status).toBe('PUBLISHED');expect(await seriesHolds(series.id)).toBe(1);expect(a.json().code).toBe('EXISTING_BOOKINGS');}
 });
 it('congé et accompagnement d’examen simultanés : un seul réussit',async()=>{
  const training=await freshTraining(),day=nextDay++;
  const [a,b]=await simultaneously(()=>closure(id.instructorMember,at(day,8),at(day,17)),()=>createExam(training,day,{from:9,to:11}));
  expect([a.statusCode===201,b.statusCode===201].filter(Boolean)).toHaveLength(1);
  if(a.statusCode===201)expect(await examCount(training)).toBe(0);
 });
});

describe('#439 replanification : bijection des positions',()=>{
 const rows=async(seriesId:string)=>(await pool.query(`SELECT o.position,o.starts_at,o.ends_at,(SELECT count(*)::int FROM drivy.reservation r WHERE r.course_occurrence_id=o.id AND r.active) AS held
  FROM drivy.course_occurrence o WHERE o.series_id=$1 ORDER BY o.position`,[seriesId])).rows;
 const state=async(seriesId:string)=>({rows:await rows(seriesId),series:await seriesRow(seriesId),
  outbox:(await pool.query<{n:number}>('SELECT count(*)::int AS n FROM drivy.course_event_outbox WHERE series_id=$1',[seriesId])).rows[0]!.n});
 const change=(position:number,day:number,hour=9)=>({position,startsAt:at(day,hour),endsAt:at(day,hour+1),instructorMembershipId:id.otherInstructorMember});
 async function published(){
  const a=nextDay++,b=nextDay++,series=await draft([{day:a,from:9,to:10},{day:b,from:9,to:10}]);
  const res=(await publish(series)).json().data;return {id:series.id,version:res.version as number,a,b};
 }
 const resched=(s:{id:string;version:number},occurrences:unknown[])=>call('POST',`/course-series/${s.id}/reschedule`,{operationId:randomUUID(),occurrences},s.version,admin);
 it('refuse une position répétée, manquante ou inconnue de même longueur, sans aucune mutation',async()=>{
  const s=await published(),before=await state(s.id);
  for(const occurrences of [[change(1,nextDay++),change(1,nextDay++)],[change(1,nextDay++),change(3,nextDay++)],[change(2,nextDay++),change(2,nextDay++)]]){
   const res=await resched(s,occurrences);expect(res.statusCode,res.body).toBeGreaterThanOrEqual(400);expect(res.statusCode).toBeLessThan(500);expect(res.json().code,res.body).toMatch(/^(COURSE_POSITIONS_MISMATCH|INVALID_REQUEST)$/);
   expect(await state(s.id)).toEqual(before);
  }
  expect((await pool.query("SELECT count(*)::int AS n FROM drivy.course_occurrence WHERE series_id=$1 AND starts_at>now()+interval '50 years'",[s.id])).rows[0].n).toBe(0);
 });
 it('la fonction SQL refuse elle-même une bijection fausse',async()=>{
  const s=await published(),before=await state(s.id);
  const db=await pool.connect();
  try{
   const asAdmin=async()=>{
    await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
    await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.school_id',$3,true)",['https://harness-identity.example.invalid','demo-admin',id.schoolA]);
    const person=(await db.query('SELECT person_id FROM drivy.identity_link WHERE subject=$1',['demo-admin'])).rows[0].person_id;
    await db.query("SELECT set_config('app.person_id',$1,true)",[person]);
   };
   // Témoin : avec ce même contexte (droits, école, série, état publié, première séance à venir), une bijection correcte est acceptée,
   // donc les refus ci-dessous ne viennent pas de la portée mais bien de la vérification des positions.
   await asAdmin();
   await expect(db.query('SELECT drivy.course_reschedule($1,$2::jsonb)',[s.id,JSON.stringify([change(1,nextDay++),change(2,nextDay++)])])).resolves.toBeDefined();
   await db.query('ROLLBACK');
   for(const changes of [[change(1,nextDay++),change(1,nextDay++)],[change(1,nextDay++),change(7,nextDay++)],[{startsAt:at(nextDay++,9),endsAt:at(nextDay++,10),instructorMembershipId:id.otherInstructorMember},change(2,nextDay++)]]){
    await asAdmin();
    await expect(db.query('SELECT drivy.course_reschedule($1,$2::jsonb)',[s.id,JSON.stringify(changes)])).rejects.toMatchObject({code:'P0001',message:'COURSE_POSITIONS_MISMATCH'});
    await db.query('ROLLBACK');
   }
  }finally{db.release();}
  expect(await state(s.id)).toEqual(before);
 });
 it('un échange de dates entre deux séances réussit atomiquement',async()=>{
  const s=await published();
  const res=await resched(s,[change(1,s.b),change(2,s.a)]);expect(res.statusCode,res.body).toBe(200);
  const now=await rows(s.id);expect(now[0].starts_at.toISOString()).toBe(at(s.b,9));expect(now[1].starts_at.toISOString()).toBe(at(s.a,9));
  expect(now.map(r=>r.held)).toEqual([1,1]);
 });
});

describe('#424 révision de programme et règles d’annulation',()=>{
 const rules={cancellationHours:24,lateAction:'CONTACT'};
 const sheetHead=async()=>{const r=await call('GET','/formations/sheet?category=B',undefined,null,admin);expect(r.statusCode,r.body).toBe(200);return r.json().data.programmes.find((p:{offeringKey:string})=>p.offeringKey==='category-b');};
 const revise=(expected:string,procedure:Record<string,unknown>)=>call('POST','/formations/programmes',{operationId:randomUUID(),offeringKey:'category-b',expectedOfferingVersionId:expected,procedure},null,admin);
 const policyOf=async(offeringId:string)=>(await pool.query<{id:string;cancellation_rules:unknown;cancellation_policy_text:string;procedure_text:string}>(
  `SELECT p.id,p.cancellation_rules,p.cancellation_policy_text,p.procedure_text FROM drivy.offering_version o JOIN drivy.school_policy_version p ON p.id=o.policy_version_id WHERE o.id=$1`,[offeringId])).rows[0]!;
 it('conserve les règles quand seule la procédure change, exige une décision quand l’annulation change',async()=>{
  await pool.query('UPDATE drivy.school_policy_version SET cancellation_rules=$2 WHERE id=$1',[school.policy,JSON.stringify(rules)]);
  const first=await sheetHead();
  expect(first.procedure.cancellationRules).toEqual(rules);
  const current=first.procedure,old=await policyOf(first.head.id);
  const kept=await revise(first.head.id,{procedureText:'Nouveau déroulement.',cancellationPolicyText:current.cancellationPolicyText,sourceUrls:current.sourceUrls});
  expect(kept.statusCode,kept.body).toBe(201);
  const next=await policyOf(kept.json().data.id);
  expect(next.id).not.toBe(old.id);expect(next.cancellation_rules).toEqual(rules);expect(next.cancellation_policy_text).toBe(old.cancellation_policy_text);
  // L'ancienne version n'est pas réécrite.
  expect((await pool.query('SELECT cancellation_rules FROM drivy.school_policy_version WHERE id=$1',[old.id])).rows[0].cancellation_rules).toEqual(rules);
  // Texte d'annulation modifié sans décision sur les règles : refusé, rien d'écrit.
  const head=(await sheetHead()).head.id;
  const count=async()=>(await pool.query('SELECT count(*)::int AS n FROM drivy.school_policy_version WHERE school_id=$1',[id.schoolA])).rows[0].n;
  const before=await count();
  const silent=await revise(head,{procedureText:'Nouveau déroulement.',cancellationPolicyText:'Annulation sans frais jusqu’à 48 heures avant la leçon.',sourceUrls:[]});
  expect(silent.statusCode,silent.body).toBe(422);expect(silent.json().code).toBe('CANCELLATION_RULES_DECISION_REQUIRED');expect(await count()).toBe(before);
  // Décision explicite : nouvelles règles, puis retrait explicite.
  const changed=await revise(head,{procedureText:'Nouveau déroulement.',cancellationPolicyText:'Annulation sans frais jusqu’à 48 heures avant la leçon.',sourceUrls:[],cancellationRules:{cancellationHours:48,lateAction:'NO_FEE'}});
  expect(changed.statusCode,changed.body).toBe(201);expect((await policyOf(changed.json().data.id)).cancellation_rules).toEqual({cancellationHours:48,lateAction:'NO_FEE'});
  const removed=await revise(changed.json().data.id,{procedureText:'Nouveau déroulement.',cancellationPolicyText:'Annulation sans frais jusqu’à 48 heures avant la leçon.',sourceUrls:[],cancellationRules:null});
  expect(removed.statusCode,removed.body).toBe(201);expect((await policyOf(removed.json().data.id)).cancellation_rules).toBeNull();
 });
 it('relecture puis sauvegarde avec une précision au texte ne transforme jamais une règle en NULL',async()=>{
  await pool.query('UPDATE drivy.school_policy_version SET cancellation_rules=$2 WHERE id=(SELECT policy_version_id FROM drivy.offering_version WHERE id=$1)',[(await sheetHead()).head.id,JSON.stringify(rules)]);
  const loaded=(await sheetHead()),p=loaded.procedure;
  const res=await revise(loaded.head.id,{procedureText:`${p.procedureText} Précision.`,cancellationPolicyText:p.cancellationPolicyText,sourceUrls:p.sourceUrls,cancellationRules:p.cancellationRules});
  expect(res.statusCode,res.body).toBe(201);expect((await policyOf(res.json().data.id)).cancellation_rules).toEqual(rules);
 });
 const policyCount=async()=>(await pool.query('SELECT count(*)::int AS n FROM drivy.school_policy_version WHERE school_id=$1',[id.schoolA])).rows[0].n;
 const offeringCount=async()=>(await pool.query('SELECT count(*)::int AS n FROM drivy.offering_version WHERE school_id=$1',[id.schoolA])).rows[0].n;
 it('relecture puis sauvegarde strictement identique : FORMATION_UNCHANGED, aucune version de plus (ordre des clés JSONB compris)',async()=>{
  await pool.query('UPDATE drivy.school_policy_version SET cancellation_rules=$2 WHERE id=(SELECT policy_version_id FROM drivy.offering_version WHERE id=$1)',[(await sheetHead()).head.id,JSON.stringify(rules)]);
  const loaded=await sheetHead(),p=loaded.procedure;
  // Le DTO relu tel quel (clés dans l'ordre rendu par JSONB, lateAction avant cancellationHours) puis le même contenu dans l'ordre inverse.
  expect(Object.keys(p.cancellationRules)).toContain('lateAction');
  const reread={procedureText:p.procedureText,cancellationPolicyText:p.cancellationPolicyText,sourceUrls:p.sourceUrls,cancellationRules:p.cancellationRules};
  const reordered={...reread,cancellationRules:{cancellationHours:p.cancellationRules.cancellationHours,lateAction:p.cancellationRules.lateAction}};
  const omitted={procedureText:p.procedureText,cancellationPolicyText:p.cancellationPolicyText,sourceUrls:p.sourceUrls};
  const policies=await policyCount(),offerings=await offeringCount();
  for(const procedure of [reread,reordered,omitted]){
   const res=await revise(loaded.head.id,procedure);
   expect(res.statusCode,res.body).toBe(409);expect(res.json().code).toBe('FORMATION_UNCHANGED');
  }
  expect(await policyCount()).toBe(policies);expect(await offeringCount()).toBe(offerings);
  expect((await sheetHead()).head.id).toBe(loaded.head.id);
 });
 it('un élève rattaché au programme révisé conserve l’échéance de 24 h et la qualification hors délai',async()=>{
  await pool.query('UPDATE drivy.school_policy_version SET cancellation_rules=$2 WHERE id=(SELECT policy_version_id FROM drivy.offering_version WHERE id=$1)',[(await sheetHead()).head.id,JSON.stringify(rules)]);
  const loaded=await sheetHead(),p=loaded.procedure;
  const revised=await revise(loaded.head.id,{procedureText:`${p.procedureText} Révision.`,cancellationPolicyText:p.cancellationPolicyText,sourceUrls:p.sourceUrls});
  expect(revised.statusCode,revised.body).toBe(201);
  const offering=revised.json().data.id as string,policy=(await policyOf(offering)).id;
  const training=randomUUID();
  // Un seul parcours actif par élève et programme : l'ancien parcours de l'élève d'essai est clos pour rattacher un nouveau parcours au programme révisé.
  await pool.query("UPDATE drivy.training SET status='COMPLETED' WHERE learner_id=$1 AND offering_key='category-b' AND status IN ('ACTIVE','PAUSED')",[id.bobLearner]);
  await pool.query(`INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on) VALUES($1,$2,$3,$4,'category-b','ACTIVE',current_date)`,[training,id.schoolA,id.bobLearner,offering]);
  await pool.query(`INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES($1,$2,$3,$4,now()-interval '1 day')`,[randomUUID(),id.schoolA,training,id.instructorMember]);
  const plan=async()=>{const r=await call('POST','/lessons',lessonBody(commercial,policy,nextDay++,8,{trainingId:training}),null,staff);expect(r.statusCode,r.body).toBe(201);return r.json().data;};
  const ask=(lessonId:string)=>call('POST',`/lessons/${lessonId}/change-requests`,{operationId:randomUUID(),kind:'CANCEL',note:''},null,'demo-bob');
  const far=await plan();
  const read=async(lessonId:string)=>(await call('GET',`/lessons/${lessonId}/change-requests`,undefined,null,'demo-bob')).json().data;
  expect((await read(far.id)).conditions).toMatchObject({cancellationHours:24,lateAction:'CONTACT',late:false,policyVersionId:policy});
  expect(Date.parse((await read(far.id)).conditions.deadlineAt)).toBe(Date.parse(far.plannedStart)-24*3_600_000);
  const near=await plan();await pool.query("UPDATE drivy.lesson SET planned_start=now()+interval '3 hours',planned_end=now()+interval '4 hours' WHERE id=$1",[near.id]);
  expect((await read(near.id)).conditions).toMatchObject({cancellationHours:24,late:true,canRequest:true});
  const late=await ask(near.id);expect(late.statusCode,late.body).toBe(201);
  expect(late.json().data.requests[0]).toMatchObject({late:true,cancellationHours:24,status:'PENDING',policyVersionId:policy});
 });
});

describe('#444 transitions de formation et examens futurs',()=>{
 const transition=(training:string,targetStatus:string,version:number)=>call('POST',`/trainings/${training}/transition`,{operationId:randomUUID(),targetStatus,reason:'Recette'},version,admin);
 const trainingVersion=async(training:string)=>(await pool.query<{version:number;status:string}>('SELECT version,status FROM drivy.training WHERE id=$1',[training])).rows[0]!;
 for(const target of ['PAUSED','COMPLETED','CANCELLED']){
  it(`${target} : l’examen futur et son accompagnement restent corrigeables sans réactiver la formation`,async()=>{
   const training=await freshTraining(),day=nextDay++,other=nextDay++;
   const created=await createExam(training,day,{from:9,to:11});expect(created.statusCode,created.body).toBe(201);const exam=created.json().data.exams[0];
   const t=await trainingVersion(training);
   const res=await transition(training,target,t.version);expect(res.statusCode,res.body).toBe(200);
   expect(res.json().data.scheduledExamCount).toBe(1);
   expect((await trainingVersion(training)).status).toBe(target);
   // Retirer l'accompagnement : l'examen est conservé, l'ancienne réservation est libérée, rien n'est inventé.
   const removed=await call('POST',`/exams/${exam.id}/update`,examBody(day,undefined,{reason:'Accompagnement retiré'}),exam.version,staff);
   expect(removed.statusCode,removed.body).toBe(200);expect(await heldBy(exam.id)).toBe(0);
   const row=(await pool.query('SELECT status,result_note FROM drivy.exam WHERE id=$1',[exam.id])).rows[0];expect(row).toEqual({status:'SCHEDULED',result_note:''});
   expect((await pool.query('SELECT count(*)::int AS n FROM drivy.reservation WHERE exam_id=$1 AND NOT active',[exam.id])).rows[0].n).toBe(1);
   // Déplacer l'examen reste possible ; en créer un nouveau reste réservé à une formation active.
   const v=removed.json().data.exams.find((e:{id:string})=>e.id===exam.id).version;
   const moved=await call('POST',`/exams/${exam.id}/update`,examBody(other,{from:9,to:11},{reason:''}),v,staff);expect(moved.statusCode,moved.body).toBe(200);expect(await heldBy(exam.id)).toBe(1);
   const fresh=await call('POST',`/trainings/${training}/exams`,{kind:'THEORY',...examBody(nextDay++)},null,staff);expect(fresh.statusCode).toBe(422);expect(fresh.json().code).toBe('TRAINING_NOT_ACTIVE');
  });
 }
 it('une formation sans examen futur garde son parcours normal',async()=>{
  const training=await freshTraining(),t=await trainingVersion(training);
  const res=await transition(training,'COMPLETED',t.version);expect(res.statusCode,res.body).toBe(200);expect(res.json().data.scheduledExamCount).toBe(0);
 });
});
