import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {expectContract,freshDatabase,harness,prepareCommercial,prepareSchool,lessonBody,id,type Call} from './support/harness.js';

let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
let day=1;
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);commercial=await prepareCommercial(call);});
afterAll(async()=>{await app?.close();await pool?.end();});
async function plan(){const r=await call('POST','/lessons',lessonBody(commercial,school.policy,day++));expect(r.statusCode,r.body).toBe(201);return r.json().data;}
const audits=async(operationId:string)=>(await pool.query('SELECT count(*)::int AS n FROM drivy.audit_event WHERE operation_id=$1',[operationId])).rows[0].n;
const completeBody=(extra:Record<string,unknown>={})=>({operationId:randomUUID(),actualStart:new Date(Date.now()-3_600_000).toISOString(),actualEnd:new Date(Date.now()-600_000).toISOString(),workedOn:'Travail',observationText:'Constat',nextStep:'Suite',anomalyReason:'Permis non contrôlé (recette)',...extra});

describe('préparation et souhait (AP45–AP48)',()=>{
 it('préparation privée du moniteur désigné, souhait de l’élève, versions et droits',async()=>{
  const lesson=await plan();const route=`/lessons/${lesson.id}/preparation`;
  const prep=await call('GET',route);await expectContract('PreparationEnvelope',prep.json());expect(prep.statusCode,prep.body).toBe(200);expect(prep.json().data).toMatchObject({lessonId:lesson.id,version:1,goals:[],administrativeCheckNote:null,plannedWaypoints:[]});
  for(const subject of ['demo-admin','demo-alice','demo-other-instructor'])expect((await call('GET',route,undefined,null,subject)).statusCode).toBe(404);
  expect((await call('GET',route,undefined,null,'demo-foreign')).statusCode).toBe(403);// non-membre de l'école
  const body={operationId:randomUUID(),goals:[{label:'Insertion',competencyId:school.competency,context:'Autoroute'}],administrativeCheckNote:'Vérifier le permis',plannedWaypoints:[{id:randomUUID(),label:'Départ',latitude:46.99,longitude:6.93,note:null}]};
  expect((await call('PUT',route,body)).statusCode).toBe(428);
  expect((await call('PUT',route,body,2)).json().code).toBe('VERSION_CONFLICT');
  expect((await call('PUT',route,{...body,operationId:randomUUID(),goals:[{label:'X',competencyId:randomUUID()}]},1)).json().code).toBe('CURRICULUM_VERSION_MISMATCH');
  expect((await call('PUT',route,{...body,operationId:randomUUID(),goals:[{label:'a'},{label:'b'},{label:'c'},{label:'d'}]},1)).statusCode).toBe(400);
  expect((await call('PUT',route,body,1,'demo-admin')).statusCode).toBe(404);
  const saved=await call('PUT',route,body,1);expect(saved.statusCode,saved.body).toBe(200);expect(saved.json().data).toMatchObject({version:2,goals:body.goals,administrativeCheckNote:'Vérifier le permis'});
  expect((await call('PUT',route,body,1)).json().data).toEqual(saved.json().data);expect(await audits(body.operationId)).toBe(1);
  // Omettre les repères les conserve ; [] les vide.
  const kept=await call('PUT',route,{operationId:randomUUID(),goals:[]},2);expect(kept.json().data.plannedWaypoints).toHaveLength(1);
  expect((await call('PUT',route,{operationId:randomUUID(),goals:[],plannedWaypoints:[]},3)).json().data.plannedWaypoints).toEqual([]);
  expect((await call('GET',`/operations/${body.operationId}`)).json().data.resourceType).toBe('Preparation');
  // Souhait : écrit par l'élève seul, lu par le moniteur affecté.
  const wishRoute=`/trainings/${id.aliceTraining}/wish`;const wish=(await call('GET',wishRoute,undefined,null,'demo-alice')).json().data;expect(wish).toMatchObject({text:'',lessonId:null});
  const wishBody={operationId:randomUUID(),text:'Travailler les ronds-points',lessonId:lesson.id};
  expect((await call('PUT',wishRoute,wishBody,wish.version)).statusCode).toBe(404);
  expect((await call('PUT',wishRoute,wishBody,wish.version,'demo-bob')).statusCode).toBe(404);
  expect((await call('PUT',wishRoute,{...wishBody,operationId:randomUUID(),text:'x'.repeat(501)},wish.version,'demo-alice')).statusCode).toBe(400);
  expect((await call('PUT',wishRoute,{...wishBody,operationId:randomUUID(),lessonId:randomUUID()},wish.version,'demo-alice')).statusCode).toBe(404);
  const savedWish=await call('PUT',wishRoute,wishBody,wish.version,'demo-alice');await expectContract('WishEnvelope',savedWish.json());expect(savedWish.statusCode,savedWish.body).toBe(200);expect(savedWish.json().data).toMatchObject({text:'Travailler les ronds-points',lessonId:lesson.id,version:wish.version+1});
  expect((await call('GET',wishRoute)).json().data.text).toBe('Travailler les ronds-points');
  expect((await call('GET',wishRoute,undefined,null,'demo-admin')).statusCode).toBe(404);
  expect((await call('GET',`/operations/${wishBody.operationId}`,undefined,null,'demo-alice')).json().data.resourceType).toBe('Wish');
  // Après le résultat, la préparation est close.
  const done=await call('POST',`/lessons/${lesson.id}/complete`,completeBody(),lesson.version);expect(done.statusCode,done.body).toBe(200);
  expect((await call('PUT',route,{operationId:randomUUID(),goals:[]},4)).json().code).toBe('LESSON_CLOSED');
  expect((await call('PUT',wishRoute,{operationId:randomUUID(),text:'Suite',lessonId:lesson.id},wish.version+1,'demo-alice')).json().code).toBe('WISH_LESSON_INVALID');
 });
});

describe('constat, bilan, progression et compte (AP49, AP52–AP56, AP58, AP65)',()=>{
 it('constat atomique avec charge unique, brouillon privé, publication, lecture élève, correction et progression',async()=>{
  const lesson=await plan();const route=`/lessons/${lesson.id}/complete`;
  expect((await call('POST',route,completeBody({anomalyReason:null}),lesson.version)).json().code).toBe('ANOMALY_REASON_REQUIRED');
  expect((await call('POST',route,completeBody({actualEnd:new Date(Date.now()-7_200_000).toISOString()}),lesson.version)).json().code).toBe('INVALID_ACTUAL_INTERVAL');
  expect((await call('POST',route,completeBody({actualEnd:new Date(Date.now()+3_600_000).toISOString()}),lesson.version)).json().code).toBe('INVALID_ACTUAL_INTERVAL');
  expect((await call('POST',route,completeBody(),lesson.version,'demo-admin')).statusCode).toBe(404);
  expect((await call('POST',route,completeBody(),lesson.version,'demo-other-instructor')).statusCode).toBe(404);
  const body=completeBody();
  const [a,b]=await Promise.all([call('POST',route,body,lesson.version),call('POST',route,body,lesson.version)]);
  expect(a.statusCode,a.body).toBe(200);expect(b.json().data).toEqual(a.json().data);expect(await audits(body.operationId)).toBe(1);
  await expectContract('CompletionResultEnvelope',a.json());const result=a.json().data;expect(Object.keys(result).sort()).toEqual(['account','draft','lesson']);
  expect(result.lesson).toMatchObject({status:'COMPLETED',version:2,actualStart:body.actualStart,actualEnd:body.actualEnd});
  expect(result.draft).toMatchObject({lessonId:lesson.id,authorMembershipId:id.instructorMember,basePublicationVersion:0,workedOn:'Travail',attachmentIds:[],geoObservationIds:[]});
  expect(result.account).toMatchObject({plannedPriceCents:9000,chargeCents:9000,netReceivedCents:0,balanceCents:9000,payments:[]});
  expect((await pool.query("SELECT count(*)::int AS n FROM drivy.charge_entry WHERE operation_id=$1",[body.operationId])).rows[0].n).toBe(1);
  expect((await call('POST',route,completeBody(),2)).json().code).toBe('LESSON_CLOSED');
  expect((await call('POST',`/lessons/${lesson.id}/cancel`,{operationId:randomUUID(),reasonCode:'OTHER'},2)).json().code).toBe('LESSON_CLOSED');
  // AP65 : lecture du compte selon le périmètre (ADMIN, élève, moniteur de la leçon).
  await expectContract('AccountEnvelope',(await call('GET',`/lessons/${lesson.id}/account`,undefined,null,'demo-alice')).json());
  await expectContract('ReportRevisionPageEnvelope',(await call('GET',`/lessons/${lesson.id}/reports`,undefined,null,'demo-alice')).json());
  for(const subject of ['demo-admin','demo-alice','demo-instructor'])expect((await call('GET',`/lessons/${lesson.id}/account`,undefined,null,subject)).json().data.chargeCents).toBe(9000);
  for(const subject of ['demo-bob','demo-other-instructor'])expect((await call('GET',`/lessons/${lesson.id}/account`,undefined,null,subject)).statusCode).toBe(404);
  // Reprise du brouillon (extension) : auteur seulement.
  const drafts=await call('GET',`/lessons/${lesson.id}/report-drafts`);expect(drafts.json().data.items.map((d:{id:string})=>d.id)).toEqual([result.draft.id]);
  for(const subject of ['demo-admin','demo-alice'])expect((await call('GET',`/lessons/${lesson.id}/report-drafts`,undefined,null,subject)).statusCode).toBe(404);
  // AP52/AP53 : brouillon privé.
  const draftRoute=`/report-drafts/${result.draft.id}`;
  for(const subject of ['demo-admin','demo-alice','demo-other-instructor'])expect((await call('GET',draftRoute,undefined,null,subject)).statusCode).toBe(404);
  const save={operationId:randomUUID(),workedOn:'Insertion',observationText:'Bonne observation',nextStep:'Autoroute',observations:[{competencyId:school.competency,level:'GUIDED',context:'Carrefour'}],attachmentIds:[]};
  expect((await call('PUT',draftRoute,{...save,attachmentIds:[randomUUID()]},result.draft.version)).json().code).toBe('ATTACHMENT_NOT_READY');
  expect((await call('PUT',draftRoute,{...save,operationId:randomUUID(),observations:[{competencyId:randomUUID(),level:'GUIDED',context:'x'}]},result.draft.version)).json().code).toBe('CURRICULUM_VERSION_MISMATCH');
  expect((await call('PUT',draftRoute,{...save,operationId:randomUUID(),observations:[save.observations[0],save.observations[0]]},result.draft.version)).statusCode).toBe(400);
  expect((await call('PUT',draftRoute,save,result.draft.version+1)).json().code).toBe('VERSION_CONFLICT');
  const saved=await call('PUT',draftRoute,save,result.draft.version);expect(saved.statusCode,saved.body).toBe(200);await expectContract('ReportDraftEnvelope',saved.json());const draft=saved.json().data;
  expect((await call('PUT',draftRoute,save,result.draft.version)).json().data).toEqual(draft);
  // AP54 : publication explicite ; sélections non livrées refusées.
  const publish={operationId:randomUUID(),expectedPublicationVersion:0,captureSelection:null,textObservationSelection:[]};
  expect((await call('POST',`${draftRoute}/publish`,{...publish,textObservationSelection:[{observationId:randomUUID(),version:1}]},draft.version)).json().code).toBe('OBSERVATION_PUBLICATION_NOT_READY');
  expect((await call('POST',`${draftRoute}/publish`,{...publish,operationId:randomUUID(),expectedPublicationVersion:1},draft.version)).json().code).toBe('PUBLICATION_VERSION_CONFLICT');
  expect((await call('POST',`${draftRoute}/publish`,{...publish,operationId:randomUUID(),excludePendingAttachmentIds:[randomUUID()]},draft.version)).json().code).toBe('ATTACHMENT_SELECTION_INVALID');
  expect((await call('GET',`/lessons/${lesson.id}/reports`,undefined,null,'demo-alice')).json().data.items).toEqual([]);
  const published=await call('POST',`${draftRoute}/publish`,publish,draft.version);expect(published.statusCode,published.body).toBe(200);
  await expectContract('ReportRevisionEnvelope',published.json());const revision=published.json().data;expect(revision).toMatchObject({lessonId:lesson.id,sequence:1,version:1,correctionReason:null,capturePublication:null,textObservations:[],attachmentIds:[]});
  expect((await call('POST',`${draftRoute}/publish`,publish,draft.version)).json().data).toEqual(revision);
  expect((await call('GET',`/operations/${publish.operationId}`)).json().data).toMatchObject({resourceType:'ReportRevision',resourceId:revision.id});
  // AP55/AP56 : lecture élève et moniteurs affectés ; ADMIN seul et autre élève exclus.
  expect((await call('GET',`/report-revisions/${revision.id}`,undefined,null,'demo-alice')).json().data.workedOn).toBe('Insertion');
  for(const subject of ['demo-admin','demo-bob','demo-other-instructor'])expect((await call('GET',`/report-revisions/${revision.id}`,undefined,null,subject)).statusCode).toBe(404);
  expect((await call('GET',`/lessons/${lesson.id}/reports`,undefined,null,'demo-admin')).statusCode).toBe(404);
  await pool.query("INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES(gen_random_uuid(),$1,$2,$3,'2026-01-01T00:00:00Z')",[id.schoolA,id.aliceTraining,id.otherInstructorMember]);
  expect((await call('GET',`/report-revisions/${revision.id}`,undefined,null,'demo-other-instructor')).statusCode).toBe(200);
  expect((await call('GET',draftRoute,undefined,null,'demo-other-instructor')).statusCode).toBe(404);
  // AP58 : progression publiée seulement.
  const progressResponse=await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-alice');await expectContract('ProgressEnvelope',progressResponse.json());const progress=progressResponse.json().data;
  expect(progress.items).toEqual([expect.objectContaining({competencyId:school.competency,level:'GUIDED',sourceLessonId:lesson.id,sourceRevisionId:revision.id})]);
  expect(progress.unobservedCompetencyIds).toEqual([school.competency2]);
  expect((await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-admin')).statusCode).toBe(404);
  expect((await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-bob')).statusCode).toBe(404);
  // Correction : nouvelle révision motivée ; la précédente reste immuable ; la projection suit la révision courante.
  const current=(await call('GET',draftRoute)).json().data;expect(current.basePublicationVersion).toBe(1);
  await call('PUT',draftRoute,{...save,operationId:randomUUID(),observations:[{competencyId:school.competency,level:'INDEPENDENT',context:'Carrefour'}]},current.version);
  const corrected=(await call('GET',draftRoute)).json().data;
  expect((await call('POST',`${draftRoute}/publish`,{...publish,operationId:randomUUID(),expectedPublicationVersion:1},corrected.version)).json().code).toBe('CORRECTION_REASON_REQUIRED');
  const second=await call('POST',`${draftRoute}/publish`,{...publish,operationId:randomUUID(),expectedPublicationVersion:1,correctionReason:'Niveau réévalué'},corrected.version);
  expect(second.statusCode,second.body).toBe(200);expect(second.json().data).toMatchObject({sequence:2,correctionReason:'Niveau réévalué'});
  expect((await call('GET',`/report-revisions/${revision.id}`,undefined,null,'demo-alice')).json().data.observations[0].level).toBe('GUIDED');
  expect((await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-alice')).json().data.items[0]).toMatchObject({level:'INDEPENDENT',sourceRevisionId:second.json().data.id});
  expect((await call('GET',`/lessons/${lesson.id}/reports`,undefined,null,'demo-alice')).json().data.items).toHaveLength(2);
  // Affectation retirée : le moniteur ne reprend plus ni brouillon ni publication.
  await pool.query(`UPDATE drivy.instructor_assignment SET valid_until=now()-interval '1 second' WHERE id=$1`,[id.assignment]);
  try{
   expect((await call('GET',draftRoute)).statusCode).toBe(404);
   expect((await call('GET',`/lessons/${lesson.id}/report-drafts`)).statusCode).toBe(404);
   expect((await call('GET',`/operations/${publish.operationId}`)).statusCode).toBe(404);
  }finally{await pool.query('UPDATE drivy.instructor_assignment SET valid_until=NULL WHERE id=$1',[id.assignment]);}
  const rows=(await pool.query('SELECT sequence,worked_on FROM drivy.report_revision WHERE lesson_id=$1 ORDER BY sequence',[lesson.id])).rows;expect(rows.map(r=>r.sequence)).toEqual([1,2]);
  // Le runtime ne peut pas réécrire une révision ni une charge.
  const db=await pool.connect();
  try{
   await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
   await expect(db.query("UPDATE drivy.report_revision SET worked_on='altéré' WHERE lesson_id=$1",[lesson.id])).rejects.toThrow();
  }finally{await db.query('ROLLBACK');db.release();}
 });
 it('un ENTITLEMENT reste refusé sans effet partiel',async()=>{
  const lesson=await plan();
  await pool.query(`UPDATE drivy.lesson SET commercial_selection=jsonb_set(commercial_selection,'{mode}','"ENTITLEMENT"') WHERE id=$1`,[lesson.id]);
  const r=await call('POST',`/lessons/${lesson.id}/complete`,completeBody(),lesson.version);expect(r.json().code).toBe('ENTITLEMENT_NOT_READY');
  expect((await call('GET',`/lessons/${lesson.id}`)).json().data.status).toBe('PLANNED');
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.report_draft WHERE lesson_id=$1',[lesson.id])).rows[0].n).toBe(0);
 });
});
