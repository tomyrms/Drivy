import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import {Pool} from 'pg';
import {buildApp} from '../src/app.js';
import {expectContract,freshDatabase,harness,prepareCommercial,prepareSchool,lessonBody,moveToPast,id,type Call} from './support/harness.js';

let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
let day=1;
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);commercial=await prepareCommercial(call);});
afterAll(async()=>{await app?.close();await pool?.end();});
async function plan(){const r=await call('POST','/lessons',lessonBody(commercial,school.policy,day++));expect(r.statusCode,r.body).toBe(201);return r.json().data;}
async function complete(lesson:{id:string;version:number},extra:Record<string,unknown>={}){
 const r=await call('POST',`/lessons/${lesson.id}/complete`,{operationId:randomUUID(),actualStart:new Date(Date.now()-3_600_000).toISOString(),actualEnd:new Date(Date.now()-600_000).toISOString(),workedOn:'Travail',observationText:'Constat',nextStep:'Suite',anomalyReason:'Permis non contrôlé (recette)',...extra},lesson.version);
 expect(r.statusCode,r.body).toBe(200);return r.json().data;
}
async function publish(draftId:string,expectedPublicationVersion:number,extra:Record<string,unknown>={}){
 const draft=(await call('GET',`/report-drafts/${draftId}`)).json().data;
 const r=await call('POST',`/report-drafts/${draftId}/publish`,{operationId:randomUUID(),expectedPublicationVersion,captureSelection:null,textObservationSelection:[],...extra},draft.version);
 expect(r.statusCode,r.body).toBe(200);return r.json().data;
}
const lessonNow=async(lessonId:string,subject='demo-instructor')=>(await call('GET',`/lessons/${lessonId}`,undefined,null,subject)).json().data;
const audits=async(operationId:string)=>(await pool.query('SELECT count(*)::int AS n FROM drivy.audit_event WHERE operation_id=$1',[operationId])).rows[0].n;

describe('santé interne',()=>{
 it('liveness et readiness sans donnée ; refus des requêtes relayées par le proxy',async()=>{
  const live=await app.inject({method:'GET',url:'/health/live'});expect(live.statusCode).toBe(200);expect(live.json()).toEqual({status:'ok'});expect(live.headers['cache-control']).toBe('no-store');
  const ready=await app.inject({method:'GET',url:'/health/ready'});expect(ready.statusCode).toBe(200);expect(ready.json()).toEqual({status:'ready'});
  for(const header of ['x-forwarded-for','forwarded','x-forwarded-host'])expect((await app.inject({method:'GET',url:'/health/ready',headers:{[header]:'203.0.113.9'}})).statusCode).toBe(404);
  const broken=new Pool({connectionString:'postgres://nobody:nothing@127.0.0.1:1/none',connectionTimeoutMillis:500});
  const down=buildApp({pool:broken,cursorSecret:'harness-test-secret-32-characters!!',verifyToken:async()=>{throw new Error('unused');}});
  try{const r=await down.inject({method:'GET',url:'/health/ready'});expect(r.statusCode).toBe(503);expect(r.json()).toEqual({status:'unavailable'});expect(r.body).not.toMatch(/ECONNREFUSED|nobody|5432|127\.0\.0\.1/);}
  finally{await down.close();await broken.end();}
 });
});

describe('AP29/AP30 contrôle du permis',()=>{
 it('habilitation explicite, catégorie réelle, versions, avertissement de leçon et constat sans anomalie',async()=>{
  const lesson=await plan();expect(lesson.permitWarning).toBe(true);
  const route=`/trainings/${id.aliceTraining}/permit-checks`;
  expect((await call('GET',route,undefined,null,'demo-admin')).json().data).toEqual({items:[],nextCursor:null});
  expect((await call('GET',route,undefined,null,'demo-alice')).statusCode).toBe(200);
  expect((await call('GET',route)).statusCode).toBe(404);// moniteur sans permit_review
  expect((await call('GET',route,undefined,null,'demo-bob')).statusCode).toBe(404);
  expect((await call('GET',`/v1/schools/${id.schoolB}/trainings/${id.aliceTraining}/permit-checks`,undefined,null,'demo-foreign')).statusCode).toBe(404);
  const training=async()=>(await call('GET',`/trainings/${id.aliceTraining}`,undefined,null,'demo-admin')).json().data.version as number;
  const body={operationId:randomUUID(),physicalSeen:true,categoryCode:'B',validUntil:null,decision:'APPROVED',reason:null,documentId:null};
  expect((await call('POST',route,body,await training(),'demo-admin')).json().code).toBe('PERMIT_REVIEW_REQUIRED');
  expect((await call('POST',route,{...body,operationId:randomUUID()},await training())).json().code).toBe('PERMIT_REVIEW_REQUIRED');
  expect((await call('POST',route,{...body,operationId:randomUUID()},await training(),'demo-alice')).json().code).toBe('SETUP_ACCESS_REQUIRED');
  await pool.query(`UPDATE drivy.membership SET grants='{CONFIGURE_CATALOG,permit_review}' WHERE id=$1`,[id.adminMember]);
  const version=await training();
  expect((await call('POST',route,{...body,operationId:randomUUID()},null,'demo-admin')).statusCode).toBe(428);
  expect((await call('POST',route,{...body,operationId:randomUUID()},version+5,'demo-admin')).json().code).toBe('VERSION_CONFLICT');
  expect((await call('POST',route,{...body,operationId:randomUUID(),categoryCode:'A'},version,'demo-admin')).json().code).toBe('CATEGORY_MISMATCH');
  expect((await call('POST',route,{...body,operationId:randomUUID(),documentId:randomUUID()},version,'demo-admin')).json().code).toBe('DOCUMENT_NOT_READY');
  expect((await call('POST',route,{...body,operationId:randomUUID(),physicalSeen:false},version,'demo-admin')).statusCode).toBe(400);
  expect((await call('POST',route,{...body,operationId:randomUUID(),decision:'REJECTED',reason:'  '},version,'demo-admin')).statusCode).toBe(400);
  expect((await call('POST',route,{...body,operationId:randomUUID(),validUntil:'2020-01-01'},version,'demo-admin')).json().code).toBe('PERMIT_EXPIRED');
  const approved=await call('POST',route,body,version,'demo-admin');expect(approved.statusCode,approved.body).toBe(200);
  const check=approved.json().data;await expectContract('PermitCheckEnvelope',approved.json());
  expect(check).toMatchObject({trainingId:id.aliceTraining,decision:'APPROVED',physicalSeen:true,categoryCode:'B',validUntil:null,reviewerMembershipId:id.adminMember,isExpired:false,documentId:null,version:1});
  expect(await training()).toBe(version+1);
  const replay=await call('POST',route,body,version,'demo-admin');expect(replay.json().data).toEqual(check);expect(await audits(body.operationId)).toBe(1);
  expect((await call('POST',route,{...body,validUntil:'2099-01-01'},version,'demo-admin')).json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await call('POST',route,{...body,operationId:randomUUID()},version,'demo-admin')).json().code).toBe('VERSION_CONFLICT');
  expect((await call('GET',`/operations/${body.operationId}`,undefined,null,'demo-admin')).json().data.resourceType).toBe('PermitCheck');
  const learnerPage=await call('GET',route,undefined,null,'demo-alice');expect(learnerPage.json().data.items).toEqual([check]);await expectContract('PermitCheckPageEnvelope',learnerPage.json());
  // R07 : l'avertissement devient calculé ; le constat n'exige plus d'anomalie.
  expect((await lessonNow(lesson.id)).permitWarning).toBe(false);expect((await lessonNow(lesson.id,'demo-alice')).permitWarning).toBe(false);
  const done=await complete(lesson,{anomalyReason:null});expect(done.lesson.permitWarning).toBe(false);expect(done.lesson.status).toBe('COMPLETED');
  // Moniteur affecté habilité : un rejet motivé remplace la décision courante sans effacer l'historique.
  await pool.query(`UPDATE drivy.membership SET grants='{permit_review}' WHERE id=$1`,[id.instructorMember]);
  const rejected=await call('POST',route,{operationId:randomUUID(),physicalSeen:true,categoryCode:'B',decision:'REJECTED',reason:'Original illisible'},await training());
  expect(rejected.statusCode,rejected.body).toBe(200);expect(rejected.json().data.reviewerMembershipId).toBe(id.instructorMember);
  const next=await plan();expect(next.permitWarning).toBe(true);
  expect((await call('POST',`/lessons/${next.id}/complete`,{operationId:randomUUID(),actualStart:new Date(Date.now()-3_600_000).toISOString(),actualEnd:new Date(Date.now()-600_000).toISOString()},next.version)).json().code).toBe('ANOMALY_REASON_REQUIRED');
  // Une date de validité réelle antérieure à la leçon laisse l'avertissement.
  const soon=new Date(Date.now()+86_400_000).toISOString().slice(0,10);
  expect((await call('POST',route,{operationId:randomUUID(),physicalSeen:true,categoryCode:'B',validUntil:soon,decision:'APPROVED'},await training(),'demo-admin')).statusCode).toBe(200);
  expect((await lessonNow(next.id)).permitWarning).toBe(true);
  expect((await call('GET',route,undefined,null,'demo-admin')).json().data.items.map((c:{decision:string})=>c.decision)).toEqual(['APPROVED','REJECTED','APPROVED']);
  // Affectation retirée : l'habilitation du moniteur ne suffit plus.
  await pool.query(`UPDATE drivy.instructor_assignment SET valid_until=now()-interval '1 second' WHERE id=$1`,[id.assignment]);
  try{expect((await call('POST',route,{operationId:randomUUID(),physicalSeen:true,categoryCode:'B',decision:'APPROVED'},await training())).statusCode).toBe(404);}
  finally{await pool.query('UPDATE drivy.instructor_assignment SET valid_until=NULL WHERE id=$1',[id.assignment]);}
  const page1=await call('GET',`${route}?limit=2`,undefined,null,'demo-admin');expect(page1.json().data.items).toHaveLength(2);
  const page2=await call('GET',`${route}?limit=2&cursor=${encodeURIComponent(page1.json().data.nextCursor)}`,undefined,null,'demo-admin');expect(page2.json().data.items).toHaveLength(1);
  // Remise à un état d'approbation valide pour la suite.
  expect((await call('POST',route,{operationId:randomUUID(),physicalSeen:true,categoryCode:'B',validUntil:null,decision:'APPROVED'},await training(),'demo-admin')).statusCode).toBe(200);
 });
});

describe('AP44 absence constatée',()=>{
 it('après la fin seulement, sans charge, droits relus, rejeu et concurrence par version',async()=>{
  const lesson=await plan();const body={operationId:randomUUID(),reason:'Élève absent au point de rendez-vous'};
  expect((await call('POST',`/lessons/${lesson.id}/no-show`,body,lesson.version)).json().code).toBe('LESSON_NOT_ENDED');
  expect(await audits(body.operationId)).toBe(0);
  await moveToPast(pool,lesson.id);
  expect((await call('POST',`/lessons/${lesson.id}/no-show`,{...body,operationId:randomUUID()},lesson.version,'demo-alice')).statusCode).toBe(403);
  expect((await call('POST',`/lessons/${lesson.id}/no-show`,{...body,operationId:randomUUID()},lesson.version,'demo-other-instructor')).statusCode).toBe(404);
  expect((await call('POST',`/lessons/${lesson.id}/no-show`,{...body,operationId:randomUUID()},lesson.version,'demo-foreign')).statusCode).toBe(404);
  expect((await call('POST',`/lessons/${lesson.id}/no-show`,{operationId:randomUUID(),reason:''},lesson.version)).statusCode).toBe(400);
  const [a,b]=await Promise.all([call('POST',`/lessons/${lesson.id}/no-show`,body,lesson.version),call('POST',`/lessons/${lesson.id}/no-show`,{...body,operationId:randomUUID()},lesson.version,'demo-admin')]);
  const codes=[a.statusCode,b.statusCode].sort();expect(codes).toEqual([200,412]);
  const winner=a.statusCode===200?a:b;const marked=winner.json().data;await expectContract('LessonEnvelope',winner.json());
  expect(marked).toMatchObject({status:'NO_SHOW',version:lesson.version+1,actualStart:null,actualEnd:null});expect(winner.headers.etag).toBe(`"${marked.version}"`);
  if(a.statusCode===200){expect((await call('POST',`/lessons/${lesson.id}/no-show`,body,lesson.version)).json().data).toEqual(marked);expect(await audits(body.operationId)).toBe(1);}
  expect((await call('POST',`/lessons/${lesson.id}/no-show`,{...body,operationId:randomUUID()},marked.version)).json().code).toBe('LESSON_CLOSED');
  const account=(await call('GET',`/lessons/${lesson.id}/account`,undefined,null,'demo-admin')).json().data;
  expect(account).toMatchObject({version:1,chargeCents:0,balanceCents:0,charges:[],payments:[]});
  expect((await call('POST',`/lessons/${lesson.id}/complete`,{operationId:randomUUID(),actualStart:new Date(Date.now()-3_600_000).toISOString(),actualEnd:new Date().toISOString()},marked.version)).json().code).toBe('LESSON_CLOSED');
  const events=(await pool.query("SELECT event_type FROM drivy.lesson_event_outbox WHERE lesson_id=$1 ORDER BY lesson_version",[lesson.id])).rows.map(r=>r.event_type);expect(events).toEqual(['LessonCreated','LessonNoShow']);
  if(a.statusCode===200)expect((await call('GET',`/operations/${body.operationId}`)).json().data).toMatchObject({resourceType:'Lesson',resourceVersion:marked.version});
  // Une annulation crée aussi un compte sans charge : aucune pénalité implicite.
  const other=await plan();const cancelled=await call('POST',`/lessons/${other.id}/cancel`,{operationId:randomUUID(),reasonCode:'LEARNER_REQUEST',comment:null},other.version);expect(cancelled.statusCode).toBe(200);
  expect((await call('GET',`/lessons/${other.id}/account`,undefined,null,'demo-admin')).json().data.chargeCents).toBe(0);
 });
 it('affectation retirée : le moniteur ne peut plus constater une absence',async()=>{
  const lesson=await plan();await moveToPast(pool,lesson.id);
  await pool.query(`UPDATE drivy.instructor_assignment SET valid_until=now()-interval '1 second' WHERE id=$1`,[id.assignment]);
  try{expect((await call('POST',`/lessons/${lesson.id}/no-show`,{operationId:randomUUID(),reason:'Absent'},lesson.version)).statusCode).toBe(404);}
  finally{await pool.query('UPDATE drivy.instructor_assignment SET valid_until=NULL WHERE id=$1',[id.assignment]);}
  expect((await call('POST',`/lessons/${lesson.id}/no-show`,{operationId:randomUUID(),reason:'Absent'},lesson.version,'demo-admin')).statusCode).toBe(200);
 });
});

describe('AP57 retrait d’un bilan publié',()=>{
 it('pointeur retiré, révisions conservées pour le moniteur, élève et progression recalculés, republication motivée',async()=>{
  const lesson=await plan();const done=await complete(lesson);
  const draft=done.draft;
  const saved=await call('PUT',`/report-drafts/${draft.id}`,{operationId:randomUUID(),workedOn:'Travail',observationText:'Constat',nextStep:'Suite',observations:[{competencyId:school.competency,level:'GUIDED',context:'Carrefour'}],attachmentIds:[]},draft.version);
  expect(saved.statusCode,saved.body).toBe(200);
  const revision=await publish(draft.id,0);
  expect((await call('GET',`/report-revisions/${revision.id}`,undefined,null,'demo-alice')).statusCode).toBe(200);
  expect((await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-alice')).json().data.items.some((i:{sourceRevisionId:string})=>i.sourceRevisionId===revision.id)).toBe(true);
  const current=await lessonNow(lesson.id);const body={operationId:randomUUID(),reason:'Bilan publié sur la mauvaise leçon'};
  const route=`/lessons/${lesson.id}/report-publication/withdraw`;
  // ADMIN seul et élève : aucun accès pédagogique, réponse identique à un objet hors périmètre.
  expect((await call('POST',route,body,current.version,'demo-admin')).statusCode).toBe(404);
  expect((await call('POST',route,body,current.version,'demo-alice')).statusCode).toBe(404);
  expect((await call('POST',route,body,current.version,'demo-other-instructor')).statusCode).toBe(404);
  expect((await call('POST',route,body,current.version-1)).json().code).toBe('VERSION_CONFLICT');
  expect((await call('POST',route,body)).statusCode).toBe(428);
  const withdrawn=await call('POST',route,body,current.version);expect(withdrawn.statusCode,withdrawn.body).toBe(200);expect(withdrawn.json().data).toEqual({operationId:body.operationId,accepted:true});await expectContract('AckEnvelope',withdrawn.json());
  expect((await call('POST',route,body,current.version)).json().data).toEqual({operationId:body.operationId,accepted:true});expect(await audits(body.operationId)).toBe(1);
  const after=await lessonNow(lesson.id);expect(after).toMatchObject({currentPublishedRevisionId:null,publicationVersion:2,version:current.version+1,status:'COMPLETED'});
  expect((await call('GET',`/report-revisions/${revision.id}`,undefined,null,'demo-alice')).statusCode).toBe(404);
  expect((await call('GET',`/lessons/${lesson.id}/reports`,undefined,null,'demo-alice')).json().data.items).toEqual([]);
  expect((await call('GET',`/report-revisions/${revision.id}`)).statusCode).toBe(200);
  expect((await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-alice')).json().data.items.some((i:{sourceRevisionId:string})=>i.sourceRevisionId===revision.id)).toBe(false);
  expect((await call('POST',route,{...body,operationId:randomUUID()},after.version)).json().code).toBe('NO_PUBLISHED_REPORT');
  expect((await call('GET',`/operations/${body.operationId}`)).json().data).toMatchObject({resourceType:'Lesson',resourceId:lesson.id,resourceVersion:after.version});
  // Republication : nouveau motif exigé, séquence suivante ; l'ancienne révision reste masquée pour l'élève.
  const rebased=(await call('GET',`/report-drafts/${draft.id}`)).json().data;expect(rebased.basePublicationVersion).toBe(2);
  expect((await call('POST',`/report-drafts/${draft.id}/publish`,{operationId:randomUUID(),expectedPublicationVersion:2,captureSelection:null,textObservationSelection:[]},rebased.version)).json().code).toBe('CORRECTION_REASON_REQUIRED');
  expect((await call('POST',`/report-drafts/${draft.id}/publish`,{operationId:randomUUID(),expectedPublicationVersion:1,captureSelection:null,textObservationSelection:[],correctionReason:'Republication'},rebased.version)).json().code).toBe('PUBLICATION_VERSION_CONFLICT');
  const republished=await publish(draft.id,2,{correctionReason:'Bilan relu et republié'});expect(republished.sequence).toBe(2);
  const learnerList=(await call('GET',`/lessons/${lesson.id}/reports`,undefined,null,'demo-alice')).json().data.items;expect(learnerList.map((r:{id:string})=>r.id)).toEqual([republished.id]);
  expect((await call('GET',`/lessons/${lesson.id}/reports`)).json().data.items).toHaveLength(2);
  expect((await lessonNow(lesson.id)).publicationVersion).toBe(3);
 });
});

describe('AP88/AP50 correction encadrée d’un résultat',()=>{
 it('approbation exacte et unique, contre-écriture, retrait du bilan, refus explicites',async()=>{
  const lesson=await plan();await moveToPast(pool,lesson.id);const done=await complete(lesson);
  await call('PUT',`/report-drafts/${done.draft.id}`,{operationId:randomUUID(),workedOn:'Travail',observationText:'Constat',nextStep:'Suite',observations:[],attachmentIds:[]},done.draft.version);
  const revision=await publish(done.draft.id,0);const current=await lessonNow(lesson.id);
  const account=(await call('GET',`/lessons/${lesson.id}/account`,undefined,null,'demo-admin')).json().data;expect(account).toMatchObject({version:1,chargeCents:9000});
  const proposal={targetStatus:'NO_SHOW',reason:'Constat saisi par erreur : élève absent',expectedAccountVersion:account.version,actualStart:null,actualEnd:null,futureBooking:null};
  const correct=(extra:Record<string,unknown>={})=>({operationId:randomUUID(),...proposal,pedagogicalApprovalId:null,...extra});
  const route=`/lessons/${lesson.id}/correct-outcome`;
  expect((await call('POST',route,correct(),current.version)).statusCode).toBe(403);// moniteur sans ADMIN
  expect((await call('POST',route,correct(),current.version,'demo-admin')).json().code).toBe('PEDAGOGICAL_APPROVAL_REQUIRED');
  expect((await call('POST',route,correct({targetStatus:'PLANNED'}),current.version,'demo-admin')).json().code).toBe('OUTCOME_CORRECTION_NOT_READY');
  expect((await call('POST',route,correct({targetStatus:'COMPLETED'}),current.version,'demo-admin')).json().code).toBe('OUTCOME_UNCHANGED');
  expect((await call('POST',route,correct({expectedAccountVersion:7}),current.version,'demo-admin')).json().code).toBe('ACCOUNT_VERSION_CONFLICT');
  // AP88
  const approvals=`/lessons/${lesson.id}/outcome-approvals`,approveBody={operationId:randomUUID(),proposal,expectedPublicationVersion:current.publicationVersion};
  expect((await call('POST',approvals,approveBody,current.version,'demo-admin')).statusCode).toBe(404);
  expect((await call('POST',approvals,approveBody,current.version,'demo-other-instructor')).statusCode).toBe(404);
  expect((await call('POST',approvals,{...approveBody,operationId:randomUUID(),expectedPublicationVersion:0},current.version)).json().code).toBe('PUBLICATION_VERSION_CONFLICT');
  expect((await call('POST',approvals,{...approveBody,operationId:randomUUID()},current.version-1)).json().code).toBe('VERSION_CONFLICT');
  const approved=await call('POST',approvals,approveBody,current.version);expect(approved.statusCode,approved.body).toBe(200);
  const approval=approved.json().data;await expectContract('OutcomeApprovalEnvelope',approved.json());
  expect(approval).toMatchObject({lessonId:lesson.id,lessonVersion:current.version,accountVersion:1,publicationVersion:current.publicationVersion,approvedByMembershipId:id.instructorMember,consumedAt:null,version:1});
  expect(approval.proposalHash).toMatch(/^[0-9a-f]{64}$/);expect(Date.parse(approval.expiresAt)-Date.now()).toBeLessThanOrEqual(600_000);
  expect((await call('POST',approvals,approveBody,current.version)).json().data).toEqual(approval);
  // Contenu différent de la proposition approuvée : refus sans effet.
  expect((await call('POST',route,correct({pedagogicalApprovalId:approval.id,reason:'Autre motif'}),current.version,'demo-admin')).json().code).toBe('APPROVAL_INVALID');
  expect((await call('POST',route,correct({pedagogicalApprovalId:randomUUID()}),current.version,'demo-admin')).json().code).toBe('APPROVAL_INVALID');
  const body=correct({pedagogicalApprovalId:approval.id});
  const corrected=await call('POST',route,body,current.version,'demo-admin');expect(corrected.statusCode,corrected.body).toBe(200);
  await expectContract('LessonEnvelope',corrected.json());const lessonAfter=corrected.json().data;expect(lessonAfter).toMatchObject({status:'NO_SHOW',actualStart:null,actualEnd:null,currentPublishedRevisionId:null,publicationVersion:current.publicationVersion+1,version:current.version+1});
  expect((await call('POST',route,body,current.version,'demo-admin')).json().data).toEqual(lessonAfter);expect(await audits(body.operationId)).toBe(1);
  const accountResponse=await call('GET',`/lessons/${lesson.id}/account`,undefined,null,'demo-admin');await expectContract('AccountEnvelope',accountResponse.json());const accountAfter=accountResponse.json().data;
  expect(accountAfter).toMatchObject({version:2,chargeCents:0,balanceCents:0});expect(accountAfter.charges.map((c:{kind:string;amountSignedCents:number})=>[c.kind,c.amountSignedCents])).toEqual([['INITIAL',9000],['REVERSAL',-9000]]);
  expect((await call('GET',`/report-revisions/${revision.id}`,undefined,null,'demo-alice')).statusCode).toBe(404);
  expect((await call('GET',`/report-revisions/${revision.id}`)).statusCode).toBe(200);
  const stored=(await pool.query('SELECT consumed_at,version FROM drivy.outcome_approval WHERE id=$1',[approval.id])).rows[0];expect(stored.version).toBe(2);expect(stored.consumed_at).not.toBeNull();
  const history=(await pool.query('SELECT from_status,to_status,previous_revision_id,reversed_charge_cents::int AS reversed FROM drivy.lesson_outcome_correction WHERE lesson_id=$1',[lesson.id])).rows;
  expect(history).toEqual([{from_status:'COMPLETED',to_status:'NO_SHOW',previous_revision_id:revision.id,reversed:9000}]);
  // Correction entre deux issues sans réalisation : pas d'approbation, pas de charge.
  const toCancel=await call('POST',route,{operationId:randomUUID(),targetStatus:'CANCELLED',reason:'Annulation prévenue en réalité',expectedAccountVersion:2,pedagogicalApprovalId:null},lessonAfter.version,'demo-admin');
  expect(toCancel.statusCode,toCancel.body).toBe(200);expect(toCancel.json().data.status).toBe('CANCELLED');
  expect((await call('GET',`/lessons/${lesson.id}/account`,undefined,null,'demo-admin')).json().data.version).toBe(2);
  // L'approbation consommée ne peut pas resservir.
  expect((await call('POST',route,correct({targetStatus:'NO_SHOW',expectedAccountVersion:2,pedagogicalApprovalId:approval.id}),toCancel.json().data.version,'demo-admin')).json().code).toBe('APPROVAL_INVALID');
  expect((await call('GET',`/operations/${body.operationId}`,undefined,null,'demo-admin')).json().data.resourceType).toBe('Lesson');
  expect((await call('GET',`/operations/${approveBody.operationId}`)).json().data.resourceType).toBe('OutcomeApproval');
  // Leçon encore planifiée : une correction est refusée.
  const planned=await plan();
  expect((await call('POST',`/lessons/${planned.id}/correct-outcome`,correct({expectedAccountVersion:1}),planned.version,'demo-admin')).json().code).toBe('LESSON_OUTCOME_CONFLICT');
 });
 it('un responsable qui approuve puis exécute doit se réauthentifier',async()=>{
  const own=await harness(pool,{reauthMaxAgeSeconds:30});
  await pool.query(`UPDATE drivy.membership SET roles='{ADMIN,INSTRUCTOR}' WHERE id=$1`,[id.adminMember]);
  await pool.query('INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES(gen_random_uuid(),$1,$2,$3,$4)',[id.schoolA,id.aliceTraining,id.adminMember,'2026-01-01T00:00:00Z']);
  try{
   await pool.query(`INSERT INTO drivy.availability_rule(school_id,instructor_membership_id,weekdays,local_start,local_end,valid_from) VALUES($1,$2,'{1,2,3,4,5,6,7}','06:00','22:00',current_date)`,[id.schoolA,id.adminMember]);
   const created=await own.call('POST','/lessons',lessonBody(commercial,school.policy,day++,8,{instructorMembershipId:id.adminMember}),null,'demo-admin');expect(created.statusCode,created.body).toBe(201);
   let lesson=created.json().data;await moveToPast(pool,lesson.id);
   const done=await own.call('POST',`/lessons/${lesson.id}/complete`,{operationId:randomUUID(),actualStart:new Date(Date.now()-3_600_000).toISOString(),actualEnd:new Date().toISOString(),workedOn:'T',observationText:'C',nextStep:'S'},lesson.version,'demo-admin');
   expect(done.statusCode,done.body).toBe(200);
   const draft=(await own.call('GET',`/report-drafts/${done.json().data.draft.id}`,undefined,null,'demo-admin')).json().data;
   expect((await own.call('POST',`/report-drafts/${draft.id}/publish`,{operationId:randomUUID(),expectedPublicationVersion:0,captureSelection:null,textObservationSelection:[]},draft.version,'demo-admin')).statusCode).toBe(200);
   lesson=(await own.call('GET',`/lessons/${lesson.id}`,undefined,null,'demo-admin')).json().data;
   const proposal={targetStatus:'CANCELLED',reason:'Leçon annulée en réalité',expectedAccountVersion:1};
   const approval=await own.call('POST',`/lessons/${lesson.id}/outcome-approvals`,{operationId:randomUUID(),proposal,expectedPublicationVersion:lesson.publicationVersion},lesson.version,'demo-admin');
   expect(approval.statusCode,approval.body).toBe(200);
   // Jeton émis 60 s après l'authentification : la réauthentification est exigée.
   const stale=await own.app.inject({method:'POST',url:`${own.base}/lessons/${lesson.id}/correct-outcome`,headers:{authorization:`Bearer ${await staleToken()}`,'idempotency-key':'00000000-0000-4000-8000-00000000abcd','if-match':`"${lesson.version}"`},payload:{operationId:'00000000-0000-4000-8000-00000000abcd',...proposal,pedagogicalApprovalId:approval.json().data.id}});
   expect(stale.json().code).toBe('REAUTH_REQUIRED');
   const ok=await own.call('POST',`/lessons/${lesson.id}/correct-outcome`,{operationId:randomUUID(),...proposal,pedagogicalApprovalId:approval.json().data.id},lesson.version,'demo-admin');
   expect(ok.statusCode,ok.body).toBe(200);expect(ok.json().data.status).toBe('CANCELLED');
   async function staleToken(){return own.token('demo-admin',Math.floor(Date.now()/1000)-60);}
  }finally{
   await pool.query(`UPDATE drivy.membership SET roles='{ADMIN}' WHERE id=$1`,[id.adminMember]);await own.app.close();
  }
 });
});
