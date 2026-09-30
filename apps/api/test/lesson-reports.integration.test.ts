import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {expectContract,freshDatabase,harness,prepareCommercial,prepareSchool,lessonBody,moveToPast,id,type Call} from './support/harness.js';

let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
let day=1;
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);commercial=await prepareCommercial(call);});
afterAll(async()=>{await app?.close();await pool?.end();});
// Le constat n'est possible qu'à partir de 15 minutes avant le début prévu (LESSON_NOT_STARTED) : la leçon est ramenée dans le passé.
async function plan(){const r=await call('POST','/lessons',lessonBody(commercial,school.policy,day++));expect(r.statusCode,r.body).toBe(201);await moveToPast(pool,r.json().data.id);return r.json().data;}
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
 it('progression : chaque leçon suivante reprend les niveaux précédents et ne remplace que les compétences notées',async()=>{
  const at=(minutes:number)=>new Date(Date.now()-minutes*60_000).toISOString();
  const finish=async(end:number,observations:{competencyId:string;level:string;context:string}[])=>{
   const lesson=await plan();
   const done=await call('POST',`/lessons/${lesson.id}/complete`,completeBody({actualStart:at(end+30),actualEnd:at(end)}),lesson.version);expect(done.statusCode,done.body).toBe(200);
   const saved=await call('PUT',`/report-drafts/${done.json().data.draft.id}`,{operationId:randomUUID(),workedOn:'Travail',observationText:'',nextStep:'',observations,attachmentIds:[]},done.json().data.draft.version);
   expect(saved.statusCode,saved.body).toBe(200);return lesson.id as string;
  };
  const progressOf=async(subject:string)=>{const r=await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,subject);expect(r.statusCode,r.body).toBe(200);return r.json().data as {items:{competencyId:string;level:string;sourceLessonId:string}[];unobservedCompetencyIds:string[]};};
  const first=await finish(120,[{competencyId:school.competency,level:'DISCOVERING',context:'Leçon 1'},{competencyId:school.competency2,level:'GUIDED',context:'Leçon 1'}]);
  const second=await finish(60,[{competencyId:school.competency,level:'INDEPENDENT',context:'Leçon 2'}]);
  for(const subject of ['demo-alice','demo-instructor','demo-admin']){
   const progress=await progressOf(subject);
   expect(progress.items.find(i=>i.competencyId===school.competency),subject).toMatchObject({level:'INDEPENDENT',sourceLessonId:second});
   expect(progress.items.find(i=>i.competencyId===school.competency2),subject).toMatchObject({level:'GUIDED',sourceLessonId:first});
   expect(progress.unobservedCompetencyIds,subject).toEqual([]);
  }
  // Un bilan ancien saisi en retard ne remplace pas un niveau plus récent.
  const late=await finish(180,[{competencyId:school.competency,level:'GUIDED',context:'Rattrapage'}]);
  expect((await progressOf('demo-admin')).items.find(i=>i.competencyId===school.competency)).toMatchObject({level:'INDEPENDENT',sourceLessonId:second});
  // L'administration ne lit pas la progression d'une formation d'une autre école, ni un élève sans droit.
  expect((await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-bob')).statusCode).toBe(404);
  expect((await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-foreign')).statusCode).toBe(403);
  // Un bilan passé en privé ne compte plus dans la progression. Les trois leçons sont retirées : la formation partage sa base avec
  // les tests suivants, qui attendent une progression issue de leur seule leçon.
  for(const lessonId of [first,second,late]){
   const hidden=await call('PUT',`/lessons/${lessonId}/sharing`,{operationId:randomUUID(),reportPrivate:true,captureHidden:false,privateObservationIds:[]},1);
   expect(hidden.statusCode,hidden.body).toBe(200);
  }
  for(const subject of ['demo-alice','demo-admin'])expect((await progressOf(subject)).items,subject).toEqual([]);
 });
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
  // L'administration de l'école relit la progression (lecture seule), sans ouvrir les bilans ni les brouillons.
  const adminProgress=await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,'demo-admin');expect(adminProgress.statusCode,adminProgress.body).toBe(200);
  expect(adminProgress.json().data.items).toEqual(progress.items);expect(adminProgress.json().data.unobservedCompetencyIds).toEqual(progress.unobservedCompetencyIds);
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
 it('retour arrière d’un niveau saisi par erreur : bilan en cours ou bilan passé, révision conservée, progression recalculée',async()=>{
  const at=(minutes:number)=>new Date(Date.now()-minutes*60_000).toISOString();
  const finish=async(end:number)=>{
   const lesson=await plan();
   const done=await call('POST',`/lessons/${lesson.id}/complete`,completeBody({actualStart:at(end+30),actualEnd:at(end),workedOn:'',observationText:'',nextStep:''}),lesson.version);expect(done.statusCode,done.body).toBe(200);
   return {lessonId:lesson.id as string,draftRoute:`/report-drafts/${done.json().data.draft.id}`,version:done.json().data.draft.version as number};
  };
  const save=async(entry:{draftRoute:string;version:number},workedOn:string,observations:{competencyId:string;level:string;context:string}[])=>{
   const r=await call('PUT',entry.draftRoute,{operationId:randomUUID(),workedOn,observationText:'',nextStep:'',observations,attachmentIds:[]},entry.version);
   expect(r.statusCode,r.body).toBe(200);entry.version=r.json().data.version;return r.json().data;
  };
  const levelOf=async(subject='demo-alice')=>{
   const r=await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,subject);expect(r.statusCode,r.body).toBe(200);
   return (r.json().data.items as {competencyId:string;level:string;sourceLessonId:string}[]).find(i=>i.competencyId===school.competency);
  };
  const revisions=async(lessonId:string,subject='demo-alice')=>(await call('GET',`/lessons/${lessonId}/reports`,undefined,null,subject)).json().data.items as {sequence:number;observations:{competencyId:string}[]}[];
  const older=await finish(120),recent=await finish(60);
  await save(older,'Travail',[{competencyId:school.competency,level:'GUIDED',context:'Leçon 1'}]);
  await save(recent,'Travail',[{competencyId:school.competency,level:'INDEPENDENT',context:'Leçon 2'}]);
  expect(await levelOf()).toMatchObject({level:'INDEPENDENT',sourceLessonId:recent.lessonId});
  // Bilan en cours : la compétence retirée du bilan, la progression retombe sur le niveau de la leçon précédente.
  await save(recent,'Travail',[]);
  expect(await levelOf()).toMatchObject({level:'GUIDED',sourceLessonId:older.lessonId});
  expect(await levelOf('demo-admin')).toMatchObject({level:'GUIDED',sourceLessonId:older.lessonId});
  // Aucun effacement silencieux : la révision qui portait l'erreur reste lisible, la nouvelle est motivée.
  const trace=await revisions(recent.lessonId);
  expect(trace.map(r=>r.sequence)).toEqual([1,2]);expect(trace[0]!.observations).toHaveLength(1);expect(trace[1]!.observations).toEqual([]);
  // Bilan passé : le même geste corrige une leçon plus ancienne et plus aucun niveau ne subsiste.
  await save(older,'Travail',[]);
  expect(await levelOf()).toBeUndefined();
  expect((await revisions(older.lessonId)).map(r=>r.sequence)).toEqual([1,2]);
  // Le niveau peut être ressaisi ensuite, sans doublon.
  await save(older,'Travail',[{competencyId:school.competency,level:'DISCOVERING',context:'Leçon 1'}]);
  expect(await levelOf()).toMatchObject({level:'DISCOVERING',sourceLessonId:older.lessonId});
  // Un bilan entièrement vidé est retiré pour l'élève ; ses révisions restent conservées pour le moniteur.
  await save(older,'',[]);
  expect(await levelOf()).toBeUndefined();expect(await revisions(older.lessonId)).toEqual([]);
  expect(await revisions(older.lessonId,'demo-instructor')).toHaveLength(3);
  // Droits relus au serveur : ni l'élève ni un autre moniteur ne modifient le bilan.
  for(const subject of ['demo-alice','demo-other-instructor']){
   const refused=await call('PUT',recent.draftRoute,{operationId:randomUUID(),workedOn:'x',observationText:'',nextStep:'',observations:[],attachmentIds:[]},recent.version,subject);
   expect([403,404],subject).toContain(refused.statusCode);
  }
  // Nettoyage : la formation est partagée avec les tests suivants.
  const hidden=await call('PUT',`/lessons/${recent.lessonId}/sharing`,{operationId:randomUUID(),reportPrivate:true,captureHidden:false,privateObservationIds:[]},1);
  expect(hidden.statusCode,hidden.body).toBe(200);
 });
});
