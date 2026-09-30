import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import {Pool} from 'pg';
import {buildApp} from '../src/app.js';
import {expectContract,freshDatabase,harness,issuer,lessonBody,prepareCommercial,prepareSchool,slot,id,type Call} from './support/harness.js';

/**
 * Corrections de l'API du 29 septembre 2026 : retrait d'accès, cycle de vie, produits, permis, tampon, dates locales,
 * démarrage immédiat, noms de leçon, module GPS. Les tests s'enchaînent sur une même base (l'ordre compte).
 */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],token:Awaited<ReturnType<typeof harness>>['token'],base:string;
let school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
let bufferLesson:{id:string;version:number};
beforeAll(async()=>{pool=await freshDatabase();({call,app,token,base}=await harness(pool));});
afterAll(async()=>{await app?.close();await pool?.end();});

const today=new Date().toISOString().slice(0,10);
const zurichDate=(at=new Date())=>new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Zurich'}).format(at);
const zurichTime=(iso:string)=>new Intl.DateTimeFormat('en-GB',{timeZone:'Europe/Zurich',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(new Date(iso));
const audits=async(operationId:string)=>(await pool.query('SELECT action FROM drivy.audit_event WHERE operation_id=$1',[operationId])).rows.map(r=>r.action as string);
const capability=(body:{data:{capabilities:{capability:string;ready:boolean;blockers:{code:string}[]}[]}},name:string)=>body.data.capabilities.find(c=>c.capability===name)!;
const readiness=async()=>(await call('GET','/readiness',undefined,null,'demo-admin')).json();
const members=async()=>(await call('GET','/members',undefined,null,'demo-admin')).json().data.items as {id:string;version:number;status:string;roles:string[];accessEpoch:number}[];
const memberOf=async(memberId:string)=>(await members()).find(m=>m.id===memberId)!;
const trainingVersion=async(trainingId:string)=>(await call('GET',`/trainings/${trainingId}`,undefined,null,'demo-admin')).json().data.version as number;
const cancelLesson=(lesson:{id:string;version:number},subject='demo-admin')=>call('POST',`/lessons/${lesson.id}/cancel`,{operationId:randomUUID(),reasonCode:'OTHER',comment:'Recette'},lesson.version,subject);
const assign=async(memberId:string,trainingId:string)=>{
 const r=await call('POST',`/trainings/${trainingId}/assignments`,{operationId:randomUUID(),instructorMembershipId:memberId,validFrom:'2026-01-01T00:00:00Z'},null,'demo-admin');
 expect(r.statusCode,r.body).toBe(201);return r.json().data as {id:string;version:number};
};
const openRule=async(memberId:string,localStart='00:00',localEnd='23:00')=>{
 const r=await call('POST','/availability-rules',{operationId:randomUUID(),instructorMembershipId:memberId,weekdays:[1,2,3,4,5,6,7],localStart,localEnd,validFrom:today,validUntil:null},null,'demo-admin');
 expect(r.statusCode,r.body).toBe(201);return r.json().data as {id:string};
};
/** Une requête sous le rôle d'exécution, avec le contexte d'une personne : reproduit ce que ferait un bug d'application. */
async function asRuntime<T>(personId:string,membershipId:string,work:(db:import('pg').PoolClient)=>Promise<T>):Promise<T>{
 const db=await pool.connect();
 try{
  await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
  await db.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true),set_config('app.membership_id',$3,true)",[id.schoolA,personId,membershipId]);
  return await work(db);
 }finally{await db.query('ROLLBACK');db.release();}
}

describe('erreurs HTTP',()=>{
 it('les erreurs 4xx de Fastify restent des erreurs client, jamais un 503',async()=>{
  const authorization=`Bearer ${await token('demo-admin')}`;
  const send=(payload:string,type:string)=>app.inject({method:'POST',url:`${base}/lessons`,headers:{authorization,'content-type':type},payload});
  const large=await send(JSON.stringify({padding:'x'.repeat(20_000)}),'application/json');
  expect(large.statusCode).toBe(413);expect(large.json()).toMatchObject({status:413,code:'PAYLOAD_TOO_LARGE'});expect(large.headers['content-type']).toContain('application/problem+json');
  const broken=await send('{"operationId":','application/json');expect(broken.statusCode).toBe(400);expect(broken.json()).toMatchObject({status:400,code:'INVALID_REQUEST'});
  const media=await send('<a/>','application/xml');expect(media.statusCode).toBe(415);expect(media.json()).toMatchObject({status:415,code:'UNSUPPORTED_MEDIA_TYPE'});
  for(const response of [large,broken,media])expect(response.body).not.toMatch(/FST_ERR|Unexpected|stack|SyntaxError/);
 });
 it('une vraie panne reste un 503 sans détail interne',async()=>{
  const dead=new Pool({connectionString:'postgres://nobody:nothing@127.0.0.1:1/none',connectionTimeoutMillis:500});
  const down=buildApp({pool:dead,cursorSecret:'harness-test-secret-32-characters!!',verifyToken:async()=>({issuer,subject:'demo-admin'})});
  try{
   const r=await down.inject({method:'GET',url:'/v1/me'});expect(r.statusCode).toBe(503);expect(r.json().code).toBe('SERVICE_UNAVAILABLE');
   expect(r.body).not.toMatch(/ECONNREFUSED|nobody|127\.0\.0\.1/);
  }finally{await down.close();await dead.end();}
 });
});

describe('préparation de l’école (capacité CAN_PLAN_LESSON)',()=>{
 it('la capacité est calculée à partir des données réelles et liste ce qui manque',async()=>{
  let body=await readiness();await expectContract('SchoolReadinessEnvelopeV3',body);
  expect(capability(body,'CAN_PLAN_LESSON').ready).toBe(false);
  const codes=(b:typeof body)=>capability(b,'CAN_PLAN_LESSON').blockers.map(x=>x.code);
  expect(codes(body)).toEqual(expect.arrayContaining(['POLICY_REVIEW_REQUIRED','OFFERING_REQUIRED','AVAILABILITY_REQUIRED','COMMERCIAL_SETUP_REQUIRED','PROFILE_POLICY_NOT_READY']));
  expect(codes(body)).not.toContain('INSTRUCTOR_REQUIRED');
  school=await prepareSchool(pool);
  body=await readiness();expect(capability(body,'CAN_USE_WORKSPACE').ready).toBe(true);
  expect(codes(body)).toEqual(['AVAILABILITY_REQUIRED','COMMERCIAL_SETUP_REQUIRED']);
  commercial=await prepareCommercial(call);
  body=await readiness();await expectContract('SchoolReadinessEnvelopeV3',body);
  expect(capability(body,'CAN_PLAN_LESSON')).toMatchObject({ready:true,blockers:[]});
  expect(capability(body,'CAN_CAPTURE').ready).toBe(false);
 });
});

describe('prestations : seule la dernière version est réservable',()=>{
 it('une nouvelle version remplace l’ancienne, une version désactivée retire la prestation',async()=>{
  const c=await prepareCommercial(call);expect(c.product.current).toBe(true);
  const product=(extra:Record<string,unknown>={})=>({operationId:randomUUID(),productKey:'lesson-50',label:'Leçon 50 min',type:'INDIVIDUAL_LESSON',categoryCode:'B',siteId:null,durationMinutes:50,unitLabel:'leçon',unitPriceCents:9500,validFrom:today,validUntil:null,termsVersionId:c.terms.id,enabled:true,...extra});
  const v2=await call('POST','/service-products',product(),null,'demo-admin');expect(v2.statusCode,v2.body).toBe(201);
  expect(v2.json().data).toMatchObject({version:c.product.version+1,current:true,unitPriceCents:9500});
  const list=async(query='',subject='demo-instructor')=>(await call('GET',`/service-products${query}`,undefined,null,subject)).json().data.items as {id:string;current:boolean}[];
  const byId=Object.fromEntries((await list('?limit=100')).map(item=>[item.id,item]));
  expect(byId[c.product.id]!.current).toBe(false);expect(byId[v2.json().data.id]!.current).toBe(true);
  const onlyCurrent=await list('?current=true&limit=100');expect(onlyCurrent.every(item=>item.current)).toBe(true);expect(onlyCurrent.map(item=>item.id)).toContain(v2.json().data.id);expect(onlyCurrent.map(item=>item.id)).not.toContain(c.product.id);
  expect((await list('?current=false&limit=100')).map(item=>item.id)).toContain(c.product.id);
  expect((await call('GET','/service-products?current=peut-etre')).statusCode).toBe(400);
  // L'ancienne version n'est plus réservable ; la nouvelle l'est, à son prix.
  const refused=await call('POST','/lessons',lessonBody(c,school.policy,40));expect(refused.statusCode).toBe(422);expect(refused.json().code).toBe('COMMERCIAL_SELECTION_INVALID');
  const booked=await call('POST','/lessons',lessonBody({terms:c.terms,product:v2.json().data},school.policy,41,8,{agreedPriceCents:9500}));expect(booked.statusCode,booked.body).toBe(201);
  expect(booked.json().data.priceCentsSnapshot).toBe(9500);expect((await cancelLesson(booked.json().data)).statusCode).toBe(200);
  // Une version désactivée retire la prestation : les versions plus anciennes, encore actives, ne reprennent pas la main.
  const v3=await call('POST','/service-products',product({enabled:false}),null,'demo-admin');expect(v3.statusCode,v3.body).toBe(201);expect(v3.json().data.current).toBe(true);
  expect((await list('?current=true&limit=100')).map(item=>item.id)).toEqual([]);// invisible d'un moniteur sans CONFIGURE_CATALOG
  expect((await list('?current=true&limit=100','demo-admin')).map(item=>item.id)).toEqual([v3.json().data.id]);
  const stale=await call('POST','/lessons',lessonBody({terms:c.terms,product:v2.json().data},school.policy,42,8,{agreedPriceCents:9500}));expect(stale.json().code).toBe('COMMERCIAL_SELECTION_INVALID');
  expect(capability(await readiness(),'CAN_PLAN_LESSON').blockers.map(b=>b.code)).toContain('COMMERCIAL_SETUP_REQUIRED');
  // Retour à une prestation en vigueur pour la suite.
  commercial=await prepareCommercial(call);
  expect(capability(await readiness(),'CAN_PLAN_LESSON').ready).toBe(true);
 });
});

describe('contrôle du permis',()=>{
 it('l’administration et le moniteur affecté contrôlent sans habilitation, les autres non',async()=>{
  const route=`/trainings/${id.aliceTraining}/permit-checks`;
  const grants=(await pool.query('SELECT grants FROM drivy.membership WHERE id=ANY($1::uuid[])',[[id.instructorMember,id.otherInstructorMember]])).rows;expect(grants.every(row=>row.grants.length===0)).toBe(true);
  const body=(extra:Record<string,unknown>={})=>({operationId:randomUUID(),physicalSeen:true,categoryCode:'B',validUntil:null,decision:'APPROVED',reason:null,documentId:null,...extra});
  expect((await call('POST',route,body(),await trainingVersion(id.aliceTraining),'demo-other-instructor')).statusCode).toBe(404);
  expect((await call('POST',route,body(),await trainingVersion(id.aliceTraining),'demo-alice')).statusCode).toBe(403);
  const byInstructor=await call('POST',route,body({decision:'REJECTED',reason:'Original illisible'}),await trainingVersion(id.aliceTraining));
  expect(byInstructor.statusCode,byInstructor.body).toBe(200);expect(byInstructor.json().data.reviewerMembershipId).toBe(id.instructorMember);
  const byAdmin=await call('POST',route,body(),await trainingVersion(id.aliceTraining),'demo-admin');
  expect(byAdmin.statusCode,byAdmin.body).toBe(200);expect(byAdmin.json().data.reviewerMembershipId).toBe(id.adminMember);
  expect((await call('GET',route)).json().data.items.map((item:{decision:string})=>item.decision)).toEqual(['REJECTED','APPROVED']);
  expect((await call('GET',route,undefined,null,'demo-other-instructor')).statusCode).toBe(404);
 });
});

describe('noms affichés d’une leçon',()=>{
 it('élève et moniteur figurent dans toutes les projections de leçon',async()=>{
  const created=await call('POST','/lessons',lessonBody(commercial,school.policy,5));expect(created.statusCode,created.body).toBe(201);
  await expectContract('LessonEnvelope',created.json());
  const lesson=created.json().data;expect(lesson).toMatchObject({learnerDisplayName:'Alice Exemple',instructorDisplayName:'Alex Moniteur'});
  for(const subject of ['demo-instructor','demo-admin','demo-alice']){
   const one=await call('GET',`/lessons/${lesson.id}`,undefined,null,subject);expect(one.statusCode).toBe(200);
   expect(one.json().data).toMatchObject({learnerDisplayName:'Alice Exemple',instructorDisplayName:'Alex Moniteur'});
  }
  const page=await call('GET','/lessons?limit=100',undefined,null,'demo-alice');await expectContract('LessonPageEnvelope',page.json());
  expect(page.json().data.items.find((item:{id:string})=>item.id===lesson.id)).toMatchObject({learnerDisplayName:'Alice Exemple',instructorDisplayName:'Alex Moniteur'});
  const cancelled=await cancelLesson(lesson,'demo-instructor');expect(cancelled.statusCode,cancelled.body).toBe(200);
  expect(cancelled.json().data).toMatchObject({status:'CANCELLED',learnerDisplayName:'Alice Exemple',instructorDisplayName:'Alex Moniteur'});
 });
});

describe('démarrage immédiat d’une leçon (start-now)',()=>{
 it('le moniteur affecté démarre une leçon maintenant, prix et durée fixés par le serveur',async()=>{
  const body={operationId:randomUUID(),trainingId:id.aliceTraining};
  const before=Date.now();
  const started=await call('POST','/lessons/start-now',body);expect(started.statusCode,started.body).toBe(201);
  await expectContract('LessonEnvelope',started.json());const lesson=started.json().data;
  expect(started.headers.etag).toBe('"1"');
  expect(lesson).toMatchObject({status:'PLANNED',version:1,trainingId:id.aliceTraining,learnerId:id.aliceLearner,instructorMembershipId:id.instructorMember,meetingPoint:'À préciser',
   priceCentsSnapshot:9000,bufferMinutesSnapshot:0,timeZone:'Europe/Zurich',learnerDisplayName:'Alice Exemple',instructorDisplayName:'Alex Moniteur',
   commercialSelection:{mode:'UNIT_PRICE',serviceProductVersionId:commercial.product.id,quantity:1,entitlementLotId:null,acceptedTermsVersionId:commercial.terms.id}});
  const start=Date.parse(lesson.plannedStart);expect(start).toBeLessThanOrEqual(Date.now());expect(start).toBeGreaterThanOrEqual(before);
  expect(Date.parse(lesson.plannedEnd)-start).toBe(50*60_000);
  // Rejeu : même réponse, un seul audit, preuve lisible.
  expect((await call('POST','/lessons/start-now',body)).json().data).toEqual(lesson);expect(await audits(body.operationId)).toEqual(['LessonStartedNow']);
  expect((await call('GET',`/operations/${body.operationId}`)).json().data).toMatchObject({commandType:'START_LESSON_NOW',resourceType:'Lesson',resourceId:lesson.id});
  expect((await call('POST','/lessons/start-now',{...body,meetingPoint:'Ailleurs'})).json().code).toBe('IDEMPOTENCY_MISMATCH');
  // Les occupations restent contrôlées : pas de seconde leçon en même temps.
  const second=await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:id.aliceTraining});expect(second.statusCode).toBe(409);expect(second.json().code).toBe('SLOT_CONFLICT');expect(second.json().title).toContain('Planifie-la à un autre moment');
  // Droits : moniteur affecté seulement.
  expect((await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:id.aliceTraining},null,'demo-admin')).json().code).toBe('SETUP_ACCESS_REQUIRED');
  expect((await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:id.aliceTraining},null,'demo-alice')).statusCode).toBe(403);
  expect((await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:id.aliceTraining},null,'demo-other-instructor')).statusCode).toBe(404);
  expect((await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:randomUUID()})).statusCode).toBe(404);
  expect((await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:id.aliceTraining},null,'demo-instructor',{'idempotency-key':randomUUID()})).statusCode).toBe(400);
  expect((await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:id.aliceTraining,meetingPoint:''})).statusCode).toBe(400);
  expect((await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:id.aliceTraining,plannedStart:new Date().toISOString()})).statusCode).toBe(400);
  // Constat immédiat : la leçon a commencé, il n'y a pas d'attente de 15 minutes.
  const done=await call('POST',`/lessons/${lesson.id}/complete`,{operationId:randomUUID(),actualStart:new Date(Date.now()-30_000).toISOString(),actualEnd:new Date().toISOString(),workedOn:'Travail',anomalyReason:'Recette'},lesson.version);
  expect(done.statusCode,done.body).toBe(200);expect(done.json().data.lesson.status).toBe('COMPLETED');
 });
 it('refuse de démarrer sur une leçon planifiée qui commence pendant la durée de l’offre, sans nommer personne',async()=>{
  const planned=await call('POST','/lessons',lessonBody(commercial,school.policy,44));expect(planned.statusCode,planned.body).toBe(201);
  const lesson=planned.json().data;
  // La leçon planifiée commence dans 20 minutes : les 50 minutes d'une leçon immédiate la chevauchent.
  await pool.query(`UPDATE drivy.reservation SET during=tstzrange(now()+interval '20 minutes',now()+interval '70 minutes','[)') WHERE lesson_id=$1`,[lesson.id]);
  await pool.query(`UPDATE drivy.lesson SET planned_start=now()+interval '20 minutes',planned_end=now()+interval '70 minutes' WHERE id=$1`,[lesson.id]);
  try{
   const refused=await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:id.aliceTraining});
   expect(refused.statusCode,refused.body).toBe(409);expect(refused.json().code).toBe('SLOT_CONFLICT');
   expect(refused.json().title).toContain('Planifie-la à un autre moment');expect(refused.body).not.toContain('Alice');
  }finally{await cancelLesson(lesson,'demo-instructor');}
 });
 it('les ouvertures du moniteur ne s’appliquent pas à lui-même, avec un lieu de rendez-vous choisi',async()=>{
  await pool.query('UPDATE drivy.availability_rule SET removed_at=now() WHERE instructor_membership_id=$1 AND removed_at IS NULL',[id.instructorMember]);
  try{
   expect((await call('POST','/lessons',lessonBody(commercial,school.policy,43))).json().code).toBe('SLOT_UNAVAILABLE');
   const started=await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:id.aliceTraining,meetingPoint:'Parking de la gare'});
   expect(started.statusCode,started.body).toBe(201);expect(started.json().data.meetingPoint).toBe('Parking de la gare');
   expect((await cancelLesson(started.json().data,'demo-instructor')).statusCode).toBe(200);
  }finally{await pool.query('UPDATE drivy.availability_rule SET removed_at=NULL WHERE instructor_membership_id=$1',[id.instructorMember]);}
 });
});

describe('constat d’une leçon à venir (LESSON_NOT_STARTED)',()=>{
 it('refusé plus de 15 minutes avant le début prévu, accepté ensuite',async()=>{
  const created=await call('POST','/lessons',lessonBody(commercial,school.policy,6));expect(created.statusCode,created.body).toBe(201);const lesson=created.json().data;
  const complete=()=>call('POST',`/lessons/${lesson.id}/complete`,{operationId:randomUUID(),actualStart:new Date(Date.now()-600_000).toISOString(),actualEnd:new Date().toISOString(),workedOn:'Travail',anomalyReason:'Recette'},lesson.version);
  const early=await complete();expect(early.statusCode).toBe(422);expect(early.json().code).toBe('LESSON_NOT_STARTED');
  const reschedule=async(minutes:number)=>{
   await pool.query(`UPDATE drivy.reservation SET during=tstzrange(now()+make_interval(mins=>$2),now()+make_interval(mins=>$2+50),'[)') WHERE lesson_id=$1`,[lesson.id,minutes]);
   await pool.query(`UPDATE drivy.lesson SET planned_start=now()+make_interval(mins=>$2),planned_end=now()+make_interval(mins=>$2+50) WHERE id=$1`,[lesson.id,minutes]);
  };
  await reschedule(20);expect((await complete()).json().code).toBe('LESSON_NOT_STARTED');
  expect((await call('GET',`/lessons/${lesson.id}`)).json().data.status).toBe('PLANNED');
  await reschedule(10);const done=await complete();expect(done.statusCode,done.body).toBe(200);expect(done.json().data.lesson.status).toBe('COMPLETED');
 });
});

describe('filtre par moniteur (ADMIN et moniteur à la fois)',()=>{
 it('GET /lessons?instructorMembershipId= isole les leçons de l’appelant qui est aussi moniteur',async()=>{
  await pool.query("UPDATE drivy.membership SET roles='{ADMIN,INSTRUCTOR}' WHERE id=$1",[id.adminMember]);
  await pool.query("INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES(gen_random_uuid(),$1,$2,$3,'2026-01-01T00:00:00Z')",[id.schoolA,id.aliceTraining,id.adminMember]);
  try{
   await openRule(id.adminMember);
   const own=await call('POST','/lessons',lessonBody(commercial,school.policy,8,8,{instructorMembershipId:id.adminMember}),null,'demo-admin');expect(own.statusCode,own.body).toBe(201);
   const theirs=await call('POST','/lessons',lessonBody(commercial,school.policy,9,8),null,'demo-admin');expect(theirs.statusCode,theirs.body).toBe(201);
   const ids=async(query:string,subject='demo-admin')=>((await call('GET',`/lessons${query}`,undefined,null,subject)).json().data.items as {id:string}[]).map(item=>item.id);
   expect(await ids(`?instructorMembershipId=${id.adminMember}`)).toEqual([own.json().data.id]);
   expect(await ids(`?instructorMembershipId=${id.adminMember.toUpperCase()}`)).toEqual([own.json().data.id]);
   const others=await ids(`?instructorMembershipId=${id.instructorMember}&limit=100`);expect(others).toContain(theirs.json().data.id);expect(others).not.toContain(own.json().data.id);
   expect(await ids(`?instructorMembershipId=${id.instructorMember}&limit=100`,'demo-instructor')).toContain(theirs.json().data.id);
   expect((await call('GET',`/lessons?instructorMembershipId=pas-un-uuid`,undefined,null,'demo-admin')).statusCode).toBe(400);
   for(const lesson of [own.json().data,theirs.json().data])expect((await cancelLesson(lesson)).statusCode).toBe(200);
  }finally{
   await pool.query("UPDATE drivy.membership SET roles='{ADMIN}' WHERE id=$1",[id.adminMember]);
   await pool.query('UPDATE drivy.instructor_assignment SET valid_until=now() WHERE instructor_membership_id=$1',[id.adminMember]);
  }
 });
});

describe('tampon entre deux leçons',()=>{
 it('le tampon ne prolonge pas l’ouverture : une leçon peut finir à l’heure de fermeture',async()=>{
  await pool.query("INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES(gen_random_uuid(),$1,$2,$3,'2026-01-01T00:00:00Z')",[id.schoolA,id.aliceTraining,id.otherInstructorMember]);
  const body=lessonBody(commercial,school.policy,20,8,{instructorMembershipId:id.otherInstructorMember,bufferMinutes:10});
  const rule=await call('POST','/availability-rules',{operationId:randomUUID(),instructorMembershipId:id.otherInstructorMember,weekdays:[1,2,3,4,5,6,7],localStart:'00:00',localEnd:zurichTime(body.plannedEnd),validFrom:today,validUntil:null},null,'demo-other-instructor');
  expect(rule.statusCode,rule.body).toBe(201);
  const created=await call('POST','/lessons',body,null,'demo-other-instructor');expect(created.statusCode,created.body).toBe(201);
  expect(created.json().data.bufferMinutesSnapshot).toBe(10);bufferLesson=created.json().data;
  // Une leçon qui dépasserait réellement la fermeture reste refusée.
  const beyond=lessonBody(commercial,school.policy,20,8,{...slot(20,8,30),instructorMembershipId:id.otherInstructorMember,bufferMinutes:10});
  expect((await call('POST','/lessons',beyond,null,'demo-other-instructor')).json().code).toBe('SLOT_UNAVAILABLE');
  // Le tampon sépare toujours deux leçons.
  const rule2=await openRule(id.otherInstructorMember);expect(rule2.id).toBeTruthy();
  const tooClose=lessonBody(commercial,school.policy,20,8,{...slot(20,8,55),instructorMembershipId:id.otherInstructorMember,bufferMinutes:10});
  expect((await call('POST','/lessons',tooClose,null,'demo-other-instructor')).json().code).toBe('SLOT_CONFLICT');
 });
});

describe('fin d’une affectation',()=>{
 it('ADMIN, If-Match, moniteur privé d’accès, leçons à venir rendues, rejeu et audit',async()=>{
  const assignment=await assign(id.otherInstructorMember,id.bobTraining);
  const lesson=await call('POST','/lessons',lessonBody(commercial,school.policy,21,8,{trainingId:id.bobTraining,instructorMembershipId:id.otherInstructorMember,bufferMinutes:0}),null,'demo-admin');
  expect(lesson.statusCode,lesson.body).toBe(201);
  const route=`/trainings/${id.bobTraining}/assignments/${assignment.id}/end`,body={operationId:randomUUID(),reason:'Changement de moniteur'};
  expect((await call('POST',route,body,null,'demo-admin')).statusCode).toBe(428);
  expect((await call('POST',route,{...body,operationId:randomUUID()},assignment.version+4,'demo-admin')).json().code).toBe('VERSION_CONFLICT');
  expect((await call('POST',route,{...body,operationId:randomUUID()},assignment.version,'demo-instructor')).statusCode).toBe(403);
  expect((await call('POST',route,{...body,operationId:randomUUID()},assignment.version,'demo-alice')).statusCode).toBe(403);
  expect((await call('POST',`/trainings/${id.bobTraining}/assignments/${randomUUID()}/end`,{...body,operationId:randomUUID()},1,'demo-admin')).statusCode).toBe(404);
  expect((await call('POST',route,{...body,operationId:randomUUID(),extra:true},assignment.version,'demo-admin')).statusCode).toBe(400);
  const epoch=(await memberOf(id.otherInstructorMember)).accessEpoch;
  const ended=await call('POST',route,body,assignment.version,'demo-admin');expect(ended.statusCode,ended.body).toBe(200);
  expect(ended.json().data).toMatchObject({id:assignment.id,trainingId:id.bobTraining,instructorMembershipId:id.otherInstructorMember,version:assignment.version+1,plannedLessonCount:1});
  expect(Date.parse(ended.json().data.validUntil)).toBeLessThanOrEqual(Date.now());expect(ended.headers.etag).toBe(`"${assignment.version+1}"`);
  expect((await call('POST',route,body,assignment.version,'demo-admin')).json().data).toEqual(ended.json().data);expect(await audits(body.operationId)).toEqual(['AssignmentEnded']);
  expect((await call('GET',`/operations/${body.operationId}`,undefined,null,'demo-admin')).json().data).toMatchObject({commandType:'END_ASSIGNMENT',resourceType:'Assignment',resourceId:assignment.id});
  expect((await memberOf(id.otherInstructorMember)).accessEpoch).toBe(epoch+1);
  expect((await call('GET',`/trainings/${id.bobTraining}`,undefined,null,'demo-other-instructor')).statusCode).toBe(404);
  expect((await call('GET',`/lessons/${lesson.json().data.id}`,undefined,null,'demo-other-instructor')).statusCode).toBe(404);
  expect((await call('POST',route,{...body,operationId:randomUUID()},assignment.version+1,'demo-admin')).json().code).toBe('ASSIGNMENT_ALREADY_ENDED');
  // L'ADMIN garde la main sur la leçon laissée sans moniteur affecté.
  expect((await cancelLesson(lesson.json().data)).statusCode).toBe(200);
  // Une affectation qui n'a pas commencé se termine aussi, sans jamais devenir valide.
  const future=await call('POST',`/trainings/${id.bobTraining}/assignments`,{operationId:randomUUID(),instructorMembershipId:id.otherInstructorMember,validFrom:new Date(Date.now()+86_400_000).toISOString()},null,'demo-admin');expect(future.statusCode,future.body).toBe(201);
  const cancelledFuture=await call('POST',`/trainings/${id.bobTraining}/assignments/${future.json().data.id}/end`,{operationId:randomUUID()},1,'demo-admin');expect(cancelledFuture.statusCode,cancelledFuture.body).toBe(200);
  expect(cancelledFuture.json().data.validUntil).toBe(cancelledFuture.json().data.validFrom);
  const futureId=future.json().data.id as string;
  expect((await pool.query(`SELECT valid_from<=valid_from+interval '0.5 second' AND valid_until>valid_from+interval '0.5 second' AS opens FROM drivy.instructor_assignment WHERE id=$1`,[futureId])).rows[0].opens).toBe(false);
  expect((await call('POST',`/trainings/${id.bobTraining}/assignments/${futureId}/end`,{operationId:randomUUID()},2,'demo-admin')).json().code).toBe('ASSIGNMENT_ALREADY_ENDED');
 });
});

describe('cycle de vie d’une formation',()=>{
 it('transitions autorisées, leçons à venir, date de clôture du fuseau de l’école, réouverture',async()=>{
  await assign(id.instructorMember,id.bobTraining);
  const created=await call('POST','/lessons',lessonBody(commercial,school.policy,22,8,{trainingId:id.bobTraining}));expect(created.statusCode,created.body).toBe(201);const lesson=created.json().data;
  const route=`/trainings/${id.bobTraining}/transition`;
  const move=async(targetStatus:string,subject='demo-admin',extra:Record<string,unknown>={})=>call('POST',route,{operationId:randomUUID(),targetStatus,reason:'Décision de l’école',...extra},await trainingVersion(id.bobTraining),subject);
  expect((await call('POST',route,{operationId:randomUUID(),targetStatus:'PAUSED',reason:'x'},null,'demo-admin')).statusCode).toBe(428);
  expect((await move('PAUSED','demo-instructor')).statusCode).toBe(403);
  expect((await move('PAUSED','demo-alice')).statusCode).toBe(403);
  expect((await move('TERMINE')).statusCode).toBe(400);
  expect((await move('PAUSED','demo-admin',{reason:''})).statusCode).toBe(400);
  expect((await call('POST',route,{operationId:randomUUID(),targetStatus:'PAUSED',reason:'x'},99,'demo-admin')).json().code).toBe('VERSION_CONFLICT');
  expect((await move('ACTIVE')).json().code).toBe('TRAINING_STATUS_UNCHANGED');
  for(const target of ['COMPLETED','CANCELLED']){const refused=await move(target);expect(refused.statusCode).toBe(409);expect(refused.json().code).toBe('TRAINING_HAS_PLANNED_LESSONS');}
  // Pause : réversible, les leçons déjà planifiées restent ; plus de nouvelle leçon.
  const paused=await move('PAUSED');expect(paused.statusCode,paused.body).toBe(200);
  expect(paused.json().data).toMatchObject({id:id.bobTraining,status:'PAUSED',closedOn:null,plannedLessonCount:1});
  expect((await call('POST','/lessons',lessonBody(commercial,school.policy,23,8,{trainingId:id.bobTraining}))).json().code).toBe('TRAINING_NOT_ACTIVE');
  expect((await move('ACTIVE')).json().data.status).toBe('ACTIVE');
  expect((await cancelLesson(lesson)).statusCode).toBe(200);
  const closeOperation=randomUUID(),version=await trainingVersion(id.bobTraining);
  const completed=await call('POST',route,{operationId:closeOperation,targetStatus:'COMPLETED',reason:'Permis obtenu'},version,'demo-admin');expect(completed.statusCode,completed.body).toBe(200);
  expect(completed.json().data).toMatchObject({status:'COMPLETED',closedOn:zurichDate(),version:version+1,plannedLessonCount:0});expect(completed.headers.etag).toBe(`"${version+1}"`);
  expect((await call('POST',route,{operationId:closeOperation,targetStatus:'COMPLETED',reason:'Permis obtenu'},version,'demo-admin')).json().data).toEqual(completed.json().data);
  expect(await audits(closeOperation)).toEqual(['TrainingStatusChanged']);
  expect((await pool.query('SELECT reason FROM drivy.audit_event WHERE operation_id=$1',[closeOperation])).rows[0].reason).toBe('Permis obtenu');
  expect((await call('GET',`/operations/${closeOperation}`,undefined,null,'demo-admin')).json().data).toMatchObject({commandType:'TRANSITION_TRAINING',resourceType:'Training'});
  // Un état final ne mène ni à la pause ni à l'autre état final ; il rouvre vers ACTIVE seulement.
  for(const target of ['PAUSED','CANCELLED']){const refused=await move(target);expect(refused.statusCode).toBe(409);expect(refused.json().code).toBe('TRAINING_TRANSITION_INVALID');}
  expect((await move('COMPLETED')).json().code).toBe('TRAINING_STATUS_UNCHANGED');
  const reopened=await move('ACTIVE');expect(reopened.statusCode,reopened.body).toBe(200);expect(reopened.json().data).toMatchObject({status:'ACTIVE',closedOn:null});
  // Annulation, puis réouverture refusée si l'élève a une autre formation de la même offre.
  const cancelled=await move('CANCELLED');expect(cancelled.statusCode,cancelled.body).toBe(200);expect(cancelled.json().data).toMatchObject({status:'CANCELLED',closedOn:zurichDate()});
  const second=await call('POST','/trainings',{operationId:randomUUID(),learnerId:id.bobLearner,offeringId:id.offeringA},null,'demo-admin');expect(second.statusCode,second.body).toBe(201);
  expect((await move('ACTIVE')).json().code).toBe('ACTIVE_TRAINING_EXISTS');
  const closed=await call('POST',`/trainings/${second.json().data.id}/transition`,{operationId:randomUUID(),targetStatus:'CANCELLED',reason:'Doublon'},second.json().data.version,'demo-admin');expect(closed.statusCode,closed.body).toBe(200);
  // Lecture par l'élève : l'état est visible, l'historique aussi.
  expect((await call('GET',`/trainings/${id.bobTraining}`,undefined,null,'demo-bob')).json().data).toMatchObject({status:'CANCELLED'});
 });
 it('la base refuse à un autre rôle de changer le statut d’une formation',async()=>{
  const instructorPerson=id.instructor;
  await asRuntime(instructorPerson,id.instructorMember,async db=>{
   // La version seule reste modifiable (contrôle du permis) ; le statut ne l'est pas.
   expect((await db.query('UPDATE drivy.training SET version=version+1 WHERE id=$1',[id.aliceTraining])).rowCount).toBe(1);
  });
  await expect(asRuntime(instructorPerson,id.instructorMember,db=>db.query("UPDATE drivy.training SET status='PAUSED' WHERE id=$1",[id.aliceTraining]))).rejects.toThrow(/training_lifecycle_admin_only/);
  await expect(asRuntime(instructorPerson,id.instructorMember,db=>db.query("UPDATE drivy.training SET closed_on=current_date WHERE id=$1",[id.aliceTraining]))).rejects.toThrow(/training_lifecycle_admin_only/);
  await expect(asRuntime(instructorPerson,id.instructorMember,db=>db.query('UPDATE drivy.learner_profile SET archived_at=now() WHERE id=$1',[id.aliceLearner]))).rejects.toThrow();
  expect((await asRuntime(id.alice,id.aliceMember,db=>db.query('UPDATE drivy.instructor_assignment SET valid_until=now() WHERE id=$1',[id.assignment]))).rowCount).toBe(0);
  expect((await pool.query('SELECT valid_until FROM drivy.instructor_assignment WHERE id=$1',[id.assignment])).rows[0].valid_until).toBeNull();
 });
});

describe('archivage d’un dossier élève',()=>{
 it('ADMIN, formations closes, historique lisible, plus de nouvelle formation ni de leçon',async()=>{
  const route=`/learners/${id.bobLearner}/archive`;
  const learner=async()=>(await call('GET',`/learners/${id.bobLearner}`,undefined,null,'demo-admin')).json().data as {version:number;archivedAt:string|null};
  const body=()=>({operationId:randomUUID(),reason:'Fin de formation'});
  expect((await call('POST',route,body(),null,'demo-admin')).statusCode).toBe(428);
  expect((await call('POST',route,body(),(await learner()).version+3,'demo-admin')).json().code).toBe('VERSION_CONFLICT');
  expect((await call('POST',route,body(),(await learner()).version,'demo-instructor')).statusCode).toBe(403);
  expect((await call('POST',route,{operationId:randomUUID()},(await learner()).version,'demo-admin')).statusCode).toBe(400);
  // Un dossier avec une formation en cours ne s'archive pas.
  const open=await call('POST',`/learners/${id.aliceLearner}/archive`,body(),(await call('GET',`/learners/${id.aliceLearner}`,undefined,null,'demo-admin')).json().data.version,'demo-admin');
  expect(open.statusCode).toBe(409);expect(open.json().code).toBe('LEARNER_HAS_OPEN_TRAININGS');
  const before=await learner();expect(before.archivedAt).toBeNull();
  const op=body(),archived=await call('POST',route,op,before.version,'demo-admin');expect(archived.statusCode,archived.body).toBe(200);
  expect(archived.json().data).toMatchObject({id:id.bobLearner,version:before.version+1});expect(archived.json().data.archivedAt).not.toBeNull();expect(archived.headers.etag).toBe(`"${before.version+1}"`);
  expect((await call('POST',route,op,before.version,'demo-admin')).json().data).toEqual(archived.json().data);expect(await audits(op.operationId)).toEqual(['LearnerArchived']);
  expect((await call('GET',`/operations/${op.operationId}`,undefined,null,'demo-admin')).json().data).toMatchObject({commandType:'ARCHIVE_LEARNER',resourceType:'Learner',resourceId:id.bobLearner});
  expect((await call('POST',route,body(),before.version+1,'demo-admin')).json().code).toBe('LEARNER_ALREADY_ARCHIVED');
  // L'historique reste lisible ; l'archivage sort le dossier de la liste courante.
  const archivedIds=(await call('GET','/learners?status=ARCHIVED&limit=100',undefined,null,'demo-admin')).json().data.items.map((item:{id:string})=>item.id);expect(archivedIds).toEqual([id.bobLearner]);
  expect((await call('GET','/learners?limit=100',undefined,null,'demo-admin')).json().data.items.map((item:{id:string})=>item.id)).not.toContain(id.bobLearner);
  expect((await call('GET',`/trainings/${id.bobTraining}`,undefined,null,'demo-bob')).statusCode).toBe(200);
  expect((await call('GET','/lessons?limit=100',undefined,null,'demo-bob')).json().data.items.length).toBeGreaterThan(0);
  // Plus de nouvelle formation, plus de réouverture, plus de leçon.
  expect((await call('POST','/trainings',{operationId:randomUUID(),learnerId:id.bobLearner,offeringId:id.offeringA},null,'demo-admin')).json().code).toBe('LEARNER_ARCHIVED');
  expect((await call('POST',`/trainings/${id.bobTraining}/transition`,{operationId:randomUUID(),targetStatus:'ACTIVE',reason:'Erreur'},await trainingVersion(id.bobTraining),'demo-admin')).json().code).toBe('LEARNER_ARCHIVED');
  expect((await call('POST','/lessons',lessonBody(commercial,school.policy,24,8,{trainingId:id.bobTraining}))).json().code).toMatch(/TRAINING_NOT_ACTIVE|NOT_FOUND/);
 });
});

describe('restauration d’un dossier élève',()=>{
 it('ADMIN, version et motif requis, état visible, rejeu sans doublon ; les formations ne sont pas rouvertes',async()=>{
  const route=`/learners/${id.bobLearner}/restore`,body={operationId:randomUUID(),reason:'Reprise de formation'};
  const previous=(await call('GET',`/learners/${id.bobLearner}`,undefined,null,'demo-admin')).json().data;
  expect(previous.archivedAt).not.toBeNull();
  expect((await call('POST',route,body,previous.version,'demo-instructor')).statusCode).toBe(403);
  expect((await call('POST',route,body,previous.version,'demo-bob')).statusCode).toBe(403);
  expect((await call('POST',route,body,previous.version+1,'demo-admin')).statusCode).toBe(412);
  const restored=await call('POST',route,body,previous.version,'demo-admin');expect(restored.statusCode,restored.body).toBe(200);
  expect(restored.json().data).toMatchObject({id:id.bobLearner,archivedAt:null,version:previous.version+1});
  expect((await call('POST',route,body,previous.version,'demo-admin')).json().data).toEqual(restored.json().data);
  expect(await audits(body.operationId)).toEqual(['LearnerRestored']);
  expect((await call('GET',`/operations/${body.operationId}`,undefined,null,'demo-admin')).json().data.commandType).toBe('RESTORE_LEARNER');
  expect((await call('GET',`/trainings/${id.bobTraining}`,undefined,null,'demo-admin')).json().data.status).toBe('CANCELLED');
  expect((await call('POST',route,{...body,operationId:randomUUID()},previous.version+1,'demo-admin')).json().code).toBe('LEARNER_NOT_ARCHIVED');
 });
});

describe('formation créée par un moniteur',()=>{
 it('le moniteur créateur est affecté dans la même transaction ; l’ADMIN choisit',async()=>{
  const offering=async(offeringKey:string)=>{
   const r=await call('POST','/offerings',{operationId:randomUUID(),offeringKey,categoryCode:'B',curriculumVersionId:school.curriculum,policyVersionId:school.policy,enabled:true,defaultDurationMinutes:50,defaultPriceCents:9000},null,'demo-admin');
   expect(r.statusCode,r.body).toBe(201);return r.json().data.id as string;
  };
  const [second,third,fourth]=[await offering('permis-b-2'),await offering('permis-b-3'),await offering('permis-b-4')];
  const train=(offeringId:string,subject:string,extra:Record<string,unknown>={})=>call('POST','/trainings',{operationId:randomUUID(),learnerId:id.aliceLearner,offeringId,...extra},null,subject);
  const byInstructor=await train(second,'demo-instructor');expect(byInstructor.statusCode,byInstructor.body).toBe(201);
  expect((await call('GET',`/trainings/${byInstructor.json().data.id}`)).statusCode).toBe(200);
  const assigned=(await call('GET',`/trainings/${byInstructor.json().data.id}/assignments`)).json().data.items;
  expect(assigned).toHaveLength(1);expect(assigned[0]).toMatchObject({instructorMembershipId:id.instructorMember,validUntil:null});
  expect((await audits(byInstructor.json().data.id)).length).toBe(0);// l'audit est indexé par opération : l'affectation ne crée pas d'opération propre
  // Refus explicite : le moniteur crée sans s'affecter ; il ne voit pas la formation.
  const optOut=await train(third,'demo-instructor',{assignCreator:false});expect(optOut.statusCode,optOut.body).toBe(201);
  expect((await call('GET',`/trainings/${optOut.json().data.id}`)).statusCode).toBe(404);
  // ADMIN seul : aucune affectation automatique ; s'affecter sans être moniteur est refusé.
  const byAdmin=await train(fourth,'demo-admin');expect(byAdmin.statusCode,byAdmin.body).toBe(201);
  expect((await call('GET',`/trainings/${byAdmin.json().data.id}/assignments`,undefined,null,'demo-admin')).json().data.items).toEqual([]);
  expect((await train(fourth,'demo-admin',{assignCreator:true})).json().code).toBe('INSTRUCTOR_REQUIRED');
 });
});

describe('retrait d’accès d’un membre',()=>{
 it('ADMIN seulement, réauthentification, jamais le dernier ADMIN ni soi-même',async()=>{
  const other=id.otherInstructorMember,route=(memberId:string)=>`/members/${memberId}/deactivate`;
  const body=()=>({operationId:randomUUID(),reason:'Départ de l’école'});
  const target=await memberOf(other);
  expect((await call('POST',route(other),body(),null,'demo-admin')).statusCode).toBe(428);
  expect((await call('POST',route(other),body(),target.version+5,'demo-admin')).json().code).toBe('VERSION_CONFLICT');
  expect((await call('POST',route(other),body(),target.version,'demo-instructor')).statusCode).toBe(403);
  expect((await call('POST',route(other),body(),target.version,'demo-alice')).statusCode).toBe(403);
  expect((await call('POST',route(randomUUID()),body(),1,'demo-admin')).statusCode).toBe(404);
  expect((await call('POST',route(other),{operationId:randomUUID()},target.version,'demo-admin')).statusCode).toBe(400);
  const op=randomUUID(),stale=await app.inject({method:'POST',url:`${base}${route(other)}`,headers:{authorization:`Bearer ${await token('demo-admin',Math.floor(Date.now()/1000)-3600)}`,'idempotency-key':op,'if-match':`"${target.version}"`},payload:{operationId:op,reason:'Test'}});
  expect(stale.statusCode).toBe(401);expect(stale.json().code).toBe('REAUTH_REQUIRED');
  // Le seul ADMIN ne se retire pas ; avec un second ADMIN, il demande à l'autre.
  const admin=await memberOf(id.adminMember);
  const sole=await call('POST',route(id.adminMember),body(),admin.version,'demo-admin');expect(sole.statusCode).toBe(409);expect(sole.json().code).toBe('LAST_ADMIN');
  await pool.query("UPDATE drivy.membership SET roles='{ADMIN,INSTRUCTOR}' WHERE id=$1",[other]);
  const self=await call('POST',route(id.adminMember),body(),admin.version,'demo-admin');expect(self.statusCode).toBe(409);expect(self.json().code).toBe('CANNOT_DEACTIVATE_SELF');
  // Retrait d'un ADMIN par l'autre ADMIN : affectations terminées, leçons à venir rendues, accès coupé.
  const before=await memberOf(other),epoch=before.accessEpoch,done=await call('POST',route(other),{operationId:op,reason:'Départ de l’école'},before.version,'demo-admin');
  expect(done.statusCode,done.body).toBe(200);
  expect(done.json().data).toMatchObject({id:other,status:'REVOKED',version:before.version+1,accessEpoch:epoch+1,endedAssignmentCount:1,plannedLessonCount:1});
  expect(done.headers.etag).toBe(`"${before.version+1}"`);
  expect((await call('POST',route(other),{operationId:op,reason:'Départ de l’école'},before.version,'demo-admin')).json().data).toEqual(done.json().data);
  expect(await audits(op)).toEqual(['MembershipDeactivated']);expect((await pool.query('SELECT reason FROM drivy.audit_event WHERE operation_id=$1',[op])).rows[0].reason).toBe('Départ de l’école');
  expect((await call('GET',`/operations/${op}`,undefined,null,'demo-admin')).json().data).toMatchObject({commandType:'DEACTIVATE_MEMBER',resourceType:'Member',resourceId:other});
  expect((await memberOf(other)).status).toBe('REVOKED');
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.instructor_assignment WHERE instructor_membership_id=$1 AND (valid_until IS NULL OR (valid_until>now() AND valid_until>valid_from))',[other])).rows[0].n).toBe(0);
  expect((await call('GET','/lessons',undefined,null,'demo-other-instructor')).statusCode).toBe(403);
  expect((await call('GET','/v1/me',undefined,null,'demo-other-instructor')).json().data.memberships).toEqual([]);
  expect((await call('POST',route(other),body(),before.version+1,'demo-admin')).json().code).toBe('MEMBER_ALREADY_DEACTIVATED');
  // Le moniteur retiré ne peut plus ni planifier ni créer de formation ; l'ADMIN règle la leçon restée à venir.
  expect((await call('POST','/lessons',bufferLessonBody(),null,'demo-other-instructor')).statusCode).toBe(404);
  expect((await cancelLesson(bufferLesson)).statusCode).toBe(200);
  await pool.query("UPDATE drivy.membership SET roles='{ADMIN}' WHERE id=$1",[id.adminMember]);
 });
});

function bufferLessonBody(){return lessonBody(commercial,school.policy,25,8,{instructorMembershipId:id.otherInstructorMember});}

describe('module GPS de l’école',()=>{
 it('ADMIN, If-Match, réauthentification, audit ; les autres modules ne bougent pas',async()=>{
  const read=async()=>(await call('GET','',undefined,null,'demo-admin')).json().data as {version:number;configurationVersion:number;modules:Record<string,boolean>};
  const first=await read();expect(first.modules.gpsEnabled).toBe(false);
  expect(capability(await readiness(),'CAN_CAPTURE').blockers.map(b=>b.code)).toContain('GPS_MODULE_DISABLED');
  const body=(gpsEnabled:boolean)=>({operationId:randomUUID(),gpsEnabled});
  expect((await call('PUT','/modules',body(true),null,'demo-admin')).statusCode).toBe(428);
  expect((await call('PUT','/modules',body(true),first.version+3,'demo-admin')).json().code).toBe('VERSION_CONFLICT');
  expect((await call('PUT','/modules',body(true),first.version,'demo-instructor')).statusCode).toBe(403);
  expect((await call('PUT','/modules',{operationId:randomUUID(),gpsEnabled:true,packsEnabled:true},first.version,'demo-admin')).statusCode).toBe(400);
  const op=randomUUID(),stale=await app.inject({method:'PUT',url:`${base}/modules`,headers:{authorization:`Bearer ${await token('demo-admin',Math.floor(Date.now()/1000)-3600)}`,'idempotency-key':op,'if-match':`"${first.version}"`},payload:{operationId:op,gpsEnabled:true}});
  expect(stale.statusCode).toBe(401);expect(stale.json().code).toBe('REAUTH_REQUIRED');
  const enabled=await call('PUT','/modules',{operationId:op,gpsEnabled:true},first.version,'demo-admin');expect(enabled.statusCode,enabled.body).toBe(200);
  await expectContract('SchoolEnvelope',enabled.json());
  expect(enabled.json().data).toMatchObject({version:first.version+1,configurationVersion:first.configurationVersion+1,modules:{...first.modules,gpsEnabled:true}});
  expect(enabled.headers.etag).toBe(`"${first.version+1}"`);
  expect((await call('PUT','/modules',{operationId:op,gpsEnabled:true},first.version,'demo-admin')).json().data).toEqual(enabled.json().data);expect(await audits(op)).toEqual(['SchoolModulesUpdated']);
  expect((await call('GET',`/operations/${op}`,undefined,null,'demo-admin')).json().data).toMatchObject({commandType:'UPDATE_SCHOOL_MODULES',resourceType:'School',resourceId:id.schoolA});
  expect((await pool.query("SELECT settings->'modules'->>'gpsEnabled' AS gps FROM drivy.school_settings_version WHERE school_id=$1 AND version=$2",[id.schoolA,first.configurationVersion+1])).rows[0].gps).toBe('true');
  expect((await call('PUT','/modules',body(true),first.version+1,'demo-admin')).json().code).toBe('MODULE_UNCHANGED');
  expect(capability(await readiness(),'CAN_CAPTURE').blockers.map(b=>b.code)).toContain('DEVICE_REQUIRED');
  const disabled=await call('PUT','/modules',body(false),first.version+1,'demo-admin');expect(disabled.statusCode,disabled.body).toBe(200);expect(disabled.json().data.modules.gpsEnabled).toBe(false);
 });
});

describe('dates civiles dans le fuseau de l’école',()=>{
 it('les prérequis de planification lisent la date du fuseau de l’école, pas la date du serveur',async()=>{
  const utc=new Date().toISOString().slice(0,10);
  const localDate=(zone:string)=>new Intl.DateTimeFormat('en-CA',{timeZone:zone}).format(new Date());
  // À tout instant, l'un de ces deux fuseaux est un autre jour civil que UTC.
  const zone=['Pacific/Kiritimati','Pacific/Pago_Pago'].find(candidate=>localDate(candidate)!==utc)!;
  const local=localDate(zone),day=local<utc?local:utc;
  const previous=(await pool.query('UPDATE drivy.availability_rule SET removed_at=now() WHERE instructor_membership_id=$1 AND removed_at IS NULL RETURNING id',[id.instructorMember])).rows.map(r=>r.id as string);
  const rule=await call('POST','/availability-rules',{operationId:randomUUID(),instructorMembershipId:id.instructorMember,weekdays:[1,2,3,4,5,6,7],localStart:'08:00',localEnd:'12:00',validFrom:day,validUntil:day},null,'demo-admin');
  expect(rule.statusCode,rule.body).toBe(201);
  try{
   await pool.query('UPDATE drivy.school SET time_zone=$2 WHERE id=$1',[id.schoolA,zone]);
   const blockers=async()=>((await call('GET',`/learners/${id.aliceLearner}/action-readiness?action=PLAN_LESSON&resourceId=${id.aliceTraining}`,undefined,null,'demo-admin')).json().data.blockers as {code:string}[]).map(b=>b.code);
   const school=async()=>capability(await readiness(),'CAN_PLAN_LESSON').blockers.map(b=>b.code);
   if(local>utc){
    // Le fuseau est en avance : la plage qui se termine « aujourd'hui UTC » est déjà échue pour l'école.
    expect(await blockers()).toContain('AVAILABILITY_REQUIRED');expect(await school()).toContain('AVAILABILITY_REQUIRED');
   }else{
    // Le fuseau est en retard : la plage qui se termine « hier UTC » court encore pour l'école.
    expect(await blockers()).toEqual([]);expect(await school()).not.toContain('AVAILABILITY_REQUIRED');
   }
  }finally{
   await pool.query('UPDATE drivy.school SET time_zone=$2 WHERE id=$1',[id.schoolA,'Europe/Zurich']);
   await pool.query('UPDATE drivy.availability_rule SET removed_at=now() WHERE id=$1',[rule.json().data.id]);
   await pool.query('UPDATE drivy.availability_rule SET removed_at=NULL WHERE id=ANY($1::uuid[])',[previous]);
  }
 });
});
