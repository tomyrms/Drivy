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
  for(const subject of ['demo-admin','demo-other-instructor'])expect((await call('GET',route,undefined,null,subject)).statusCode).toBe(404);
  expect((await call('GET',route,undefined,null,'demo-foreign')).statusCode).toBe(403);// non-membre de l'école
  const body={operationId:randomUUID(),goals:[{label:'Insertion',competencyId:school.competency,context:'Autoroute'}],administrativeCheckNote:'Vérifier le permis',plannedWaypoints:[{id:randomUUID(),label:'Départ',latitude:46.99,longitude:6.93,note:null}]};
  expect((await call('PUT',route,body)).statusCode).toBe(428);
  expect((await call('PUT',route,body,2)).json().code).toBe('VERSION_CONFLICT');
  expect((await call('PUT',route,{...body,operationId:randomUUID(),goals:[{label:'X',competencyId:randomUUID()}]},1)).json().code).toBe('CURRICULUM_VERSION_MISMATCH');
  expect((await call('PUT',route,{...body,operationId:randomUUID(),goals:[{label:'a'},{label:'b'},{label:'c'},{label:'d'}]},1)).statusCode).toBe(400);
  expect((await call('PUT',route,body,1,'demo-admin')).statusCode).toBe(404);
  const saved=await call('PUT',route,body,1);expect(saved.statusCode,saved.body).toBe(200);expect(saved.json().data).toMatchObject({version:2,goals:body.goals,administrativeCheckNote:'Vérifier le permis'});
  expect((await call('PUT',route,body,1)).json().data).toEqual(saved.json().data);expect(await audits(body.operationId)).toBe(1);
  // Objectifs partagés avec l'élève ; la note administrative reste au moniteur.
  const learnerPreparation=await call('GET',route,undefined,null,'demo-alice');expect(learnerPreparation.statusCode).toBe(200);await expectContract('PreparationEnvelope',learnerPreparation.json());
  expect(learnerPreparation.json().data).toMatchObject({goals:body.goals,administrativeCheckNote:null});
  expect((await call('GET',route,undefined,null,'demo-bob')).statusCode).toBe(404);
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
 it('constat atomique avec charge unique, bilan partagé automatiquement, lecture élève, bilan privé et progression',async()=>{
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
  // Constat avec texte : le bilan est aussitôt lisible par l'élève (partage automatique du 28 septembre 2026).
  expect(result.lesson).toMatchObject({status:'COMPLETED',version:3,publicationVersion:1,actualStart:body.actualStart,actualEnd:body.actualEnd});expect(a.headers.etag).toBe('"3"');
  expect(result.draft).toMatchObject({lessonId:lesson.id,authorMembershipId:id.instructorMember,basePublicationVersion:1,workedOn:'Travail',attachmentIds:[],geoObservationIds:[]});
  expect(result.account).toMatchObject({plannedPriceCents:9000,chargeCents:9000,netReceivedCents:0,balanceCents:9000,payments:[]});
  expect((await pool.query("SELECT count(*)::int AS n FROM drivy.charge_entry WHERE operation_id=$1",[body.operationId])).rows[0].n).toBe(1);
  expect((await call('POST',route,completeBody(),3)).json().code).toBe('LESSON_CLOSED');
  expect((await call('POST',`/lessons/${lesson.id}/cancel`,{operationId:randomUUID(),reasonCode:'OTHER'},3)).json().code).toBe('LESSON_CLOSED');
  // AP65 : lecture du compte selon le périmètre (ADMIN, élève, moniteur de la leçon).
  await expectContract('AccountEnvelope',(await call('GET',`/lessons/${lesson.id}/account`,undefined,null,'demo-alice')).json());
  for(const subject of ['demo-admin','demo-alice','demo-instructor'])expect((await call('GET',`/lessons/${lesson.id}/account`,undefined,null,subject)).json().data.chargeCents).toBe(9000);
  for(const subject of ['demo-bob','demo-other-instructor'])expect((await call('GET',`/lessons/${lesson.id}/account`,undefined,null,subject)).statusCode).toBe(404);
  const firstPage=await call('GET',`/lessons/${lesson.id}/reports`,undefined,null,'demo-alice');await expectContract('ReportRevisionPageEnvelope',firstPage.json());
  expect(firstPage.json().data.items).toEqual([expect.objectContaining({sequence:1,workedOn:'Travail',correctionReason:null})]);
  // Reprise du brouillon (extension) : auteur seulement.
  const drafts=await call('GET',`/lessons/${lesson.id}/report-drafts`);expect(drafts.json().data.items.map((d:{id:string})=>d.id)).toEqual([result.draft.id]);
  for(const subject of ['demo-admin','demo-alice'])expect((await call('GET',`/lessons/${lesson.id}/report-drafts`,undefined,null,subject)).statusCode).toBe(404);
  // AP52 : le brouillon reste celui de l'auteur ; chaque enregistrement devient la révision lue par l'élève.
  const draftRoute=`/report-drafts/${result.draft.id}`;
  for(const subject of ['demo-admin','demo-alice','demo-other-instructor'])expect((await call('GET',draftRoute,undefined,null,subject)).statusCode).toBe(404);
  const save={operationId:randomUUID(),workedOn:'Insertion',observationText:'Bonne observation',nextStep:'Autoroute',observations:[{competencyId:school.competency,level:'GUIDED',context:'Carrefour'}],attachmentIds:[]};
  expect((await call('PUT',draftRoute,{...save,attachmentIds:[randomUUID()]},result.draft.version)).json().code).toBe('ATTACHMENT_NOT_READY');
  expect((await call('PUT',draftRoute,{...save,operationId:randomUUID(),observations:[{competencyId:randomUUID(),level:'GUIDED',context:'x'}]},result.draft.version)).json().code).toBe('CURRICULUM_VERSION_MISMATCH');
  expect((await call('PUT',draftRoute,{...save,operationId:randomUUID(),observations:[save.observations[0],save.observations[0]]},result.draft.version)).statusCode).toBe(400);
  expect((await call('PUT',draftRoute,save,result.draft.version+1)).json().code).toBe('VERSION_CONFLICT');
  const saved=await call('PUT',draftRoute,save,result.draft.version);expect(saved.statusCode,saved.body).toBe(200);await expectContract('ReportDraftEnvelope',saved.json());const draft=saved.json().data;
  expect(draft.basePublicationVersion).toBe(2);expect((await call('PUT',draftRoute,save,result.draft.version)).json().data).toEqual(draft);
  // Même contenu : aucune révision supplémentaire.
  const same=await call('PUT',draftRoute,{...save,operationId:randomUUID()},draft.version);expect(same.statusCode,same.body).toBe(200);expect(same.json().data.basePublicationVersion).toBe(2);
  const learnerItems=(await call('GET',`/lessons/${lesson.id}/reports`,undefined,null,'demo-alice')).json().data.items;
  expect(learnerItems.map((r:{sequence:number})=>r.sequence)).toEqual([1,2]);const revision=learnerItems[1];
  expect(revision).toMatchObject({workedOn:'Insertion',correctionReason:'Bilan mis à jour par le moniteur.',capturePublication:null,textObservations:[],attachmentIds:[]});
  // AP54 : les sélections d'observations ou de trajet restent refusées sur la publication explicite.
  expect((await call('POST',`${draftRoute}/publish`,{operationId:randomUUID(),expectedPublicationVersion:2,captureSelection:null,textObservationSelection:[{observationId:randomUUID(),version:1}],correctionReason:'x'},same.json().data.version)).json().code).toBe('OBSERVATION_PUBLICATION_NOT_READY');
  // AP55/AP56 : lecture élève et moniteurs affectés ; ADMIN seul et autre élève exclus.
  expect((await call('GET',`/report-revisions/${revision.id}`,undefined,null,'demo-alice')).json().data.workedOn).toBe('Insertion');
  for(const subject of ['demo-admin','demo-bob','demo-other-instructor'])expect((await call('GET',`/report-revisions/${revision.id}`,undefined,null,subject)).statusCode).toBe(404);
  expect((await call('GET',`/lessons/${lesson.id}/reports`,undefined,null,'demo-admin')).statusCode).toBe(404);
  await pool.query("INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES(gen_random_uuid(),$1,$2,$3,'2026-01-01T00:00:00Z')",[id.schoolA,id.aliceTraining,id.otherInstructorMember]);
  expect((await call('GET',`/report-revisions/${revision.id}`,undefined,null,'demo-other-instructor')).statusCode).toBe(200);
  expect((await call('GET',draftRoute,undefined,null,'demo-other-instructor')).statusCode).toBe(404);
  // AP58 : progression issue du bilan partagé.
  const progressResponse=await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-alice');await expectContract('ProgressEnvelope',progressResponse.json());const progress=progressResponse.json().data;
  expect(progress.items).toEqual([expect.objectContaining({competencyId:school.competency,level:'GUIDED',sourceLessonId:lesson.id,sourceRevisionId:revision.id})]);
  expect(progress.unobservedCompetencyIds).toEqual([school.competency2]);
  expect((await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-admin')).statusCode).toBe(404);
  expect((await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-bob')).statusCode).toBe(404);
  // Bilan privé (extension de partage) : l'élève ne le lit plus, ni la progression qui en découle ; tout est conservé.
  const sharingRoute=`/lessons/${lesson.id}/sharing`;
  expect((await call('GET',sharingRoute)).json().data).toEqual({lessonId:lesson.id,schoolId:id.schoolA,version:1,reportPrivate:false,captureHidden:false,privateObservationIds:[]});
  for(const subject of ['demo-alice','demo-admin','demo-other-instructor'])expect((await call('GET',sharingRoute,undefined,null,subject)).statusCode).toBe(404);
  const privateBody={operationId:randomUUID(),reportPrivate:true,captureHidden:false,privateObservationIds:[] as string[]};
  expect((await call('PUT',sharingRoute,privateBody)).statusCode).toBe(428);
  expect((await call('PUT',sharingRoute,privateBody,1,'demo-alice')).statusCode).toBe(403);
  expect((await call('PUT',sharingRoute,{...privateBody,operationId:randomUUID()},1,'demo-other-instructor')).statusCode).toBe(404);
  expect((await call('PUT',sharingRoute,{...privateBody,operationId:randomUUID(),privateObservationIds:[randomUUID()]},1)).json().code).toBe('OBSERVATION_NOT_IN_LESSON');
  const hidden=await call('PUT',sharingRoute,privateBody,1);expect(hidden.statusCode,hidden.body).toBe(200);expect(hidden.json().data).toMatchObject({version:2,reportPrivate:true});expect(hidden.headers.etag).toBe('"2"');
  expect((await call('PUT',sharingRoute,privateBody,1)).json().data).toEqual(hidden.json().data);expect(await audits(privateBody.operationId)).toBe(1);
  expect((await call('PUT',sharingRoute,{...privateBody,operationId:randomUUID()},1)).json().code).toBe('VERSION_CONFLICT');
  expect((await call('GET',`/operations/${privateBody.operationId}`)).json().data).toMatchObject({resourceType:'LessonSharing',resourceId:lesson.id,resourceVersion:2});
  expect((await call('GET',`/lessons/${lesson.id}/reports`,undefined,null,'demo-alice')).json().data.items).toEqual([]);
  expect((await call('GET',`/report-revisions/${revision.id}`,undefined,null,'demo-alice')).statusCode).toBe(404);
  expect((await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-alice')).json().data.items).toEqual([]);
  // Enregistrer pendant que le bilan est privé ne le partage pas.
  const privateDraft=(await call('GET',draftRoute)).json().data;
  expect((await call('PUT',draftRoute,{...save,operationId:randomUUID(),observations:[{competencyId:school.competency,level:'INDEPENDENT',context:'Carrefour'}]},privateDraft.version)).statusCode).toBe(200);
  expect((await call('GET',`/lessons/${lesson.id}/reports`,undefined,null,'demo-alice')).json().data.items).toEqual([]);
  // Repartager : la version courante du brouillon devient une nouvelle révision ; les anciennes restent masquées pour l'élève.
  const shared=await call('PUT',sharingRoute,{...privateBody,operationId:randomUUID(),reportPrivate:false},2);expect(shared.statusCode,shared.body).toBe(200);expect(shared.json().data.reportPrivate).toBe(false);
  const again=(await call('GET',`/lessons/${lesson.id}/reports`,undefined,null,'demo-alice')).json().data.items;expect(again.map((r:{sequence:number})=>r.sequence)).toEqual([3]);
  expect((await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-alice')).json().data.items[0]).toMatchObject({level:'INDEPENDENT',sourceRevisionId:again[0].id});
  expect((await call('GET',`/lessons/${lesson.id}/reports`)).json().data.items).toHaveLength(3);
  // Affectation retirée : le moniteur ne reprend plus ni brouillon ni partage.
  await pool.query(`UPDATE drivy.instructor_assignment SET valid_until=now()-interval '1 second' WHERE id=$1`,[id.assignment]);
  try{
   expect((await call('GET',draftRoute)).statusCode).toBe(404);
   expect((await call('GET',`/lessons/${lesson.id}/report-drafts`)).statusCode).toBe(404);
   expect((await call('GET',sharingRoute)).statusCode).toBe(404);
   expect((await call('GET',`/operations/${privateBody.operationId}`)).statusCode).toBe(404);
  }finally{await pool.query('UPDATE drivy.instructor_assignment SET valid_until=NULL WHERE id=$1',[id.assignment]);}
  const rows=(await pool.query('SELECT sequence FROM drivy.report_revision WHERE lesson_id=$1 ORDER BY sequence',[lesson.id])).rows;expect(rows.map(r=>r.sequence)).toEqual([1,2,3]);
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
