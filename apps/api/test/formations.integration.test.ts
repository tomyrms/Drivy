import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareCommercial,prepareSchool,lessonBody,moveToPast,id,type Call} from './support/harness.js';

/*
 * Formations et tarifs : lecture agrégée d'un permis et commandes composées (14 octobre 2026).
 * PostgreSQL réelle, requêtes sous drivy_app. Chaque scénario lit ensuite les références réellement enregistrées.
 */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);commercial=await prepareCommercial(call);});
afterAll(async()=>{await app?.close();await pool?.end();});

const admin='demo-admin';
const count=async(table:string,where='school_id=$1',values:unknown[]=[id.schoolA])=>(await pool.query(`SELECT count(*)::int AS n FROM drivy.${table} WHERE ${where}`,values)).rows[0].n as number;
const sheet=async(category:string,subject=admin)=>{const r=await call('GET',`/formations/sheet?category=${encodeURIComponent(category)}`,undefined,null,subject);expect(r.statusCode,r.body).toBe(200);return r.json().data;};
const programme=(body:Record<string,unknown>,subject=admin)=>call('POST','/formations/programmes',{operationId:randomUUID(),offeringKey:'category-b',...body},null,subject);
const tariff=(body:Record<string,unknown>,subject=admin)=>call('POST','/formations/tariffs',{operationId:randomUUID(),...body},null,subject);
const head=async(category='B',key='category-b')=>(await sheet(category)).programmes.find((item:{offeringKey:string})=>item.offeringKey===key);
const competencies=[{key:null,label:'Préparer la conduite',description:'Préparer le véhicule et son installation.'},{key:null,label:'Observer et anticiper',description:'Observer l’environnement.'}];
const procedure={procedureText:'Chaque leçon commence au lieu convenu et se termine par un bilan.',cancellationPolicyText:'Annulation sans frais jusqu’à 24 heures avant la leçon.',sourceUrls:[]};
const today=()=>new Date().toLocaleDateString('sv-SE',{timeZone:'Europe/Zurich'});
const shift=(days:number)=>{const date=new Date(`${today()}T12:00:00Z`);date.setUTCDate(date.getUTCDate()+days);return date.toISOString().slice(0,10);};
const lessonTariff=(extra:Record<string,unknown>={})=>({mode:'CREATE',categoryCode:'B',type:'INDIVIDUAL_LESSON',label:'Leçon 45 min',durationMinutes:45,unitLabel:'leçon',priceCents:7000,
 validFrom:today(),validUntil:null,enabled:true,termsText:'Conditions synthétiques de la leçon de 45 minutes.',...extra});
const newFormation=(extra:Record<string,unknown>={})=>({operationId:randomUUID(),categoryCode:'A',intent:'NEW',programmeLabel:null,competencies,procedure,
 source:{templateId:'pedagogy-a',templateVersion:'2026-10-13.2'},tariff:{label:'Leçon moto 50 min',durationMinutes:50,priceCents:9500,validFrom:today(),validUntil:null,termsText:'Conditions synthétiques moto.'},...extra});

describe('lecture agrégée',()=>{
 it('liste des permis, fiche complète et accès réservé à l’administration',async()=>{
  const list=await call('GET','/formations',undefined,null,admin);expect(list.statusCode,list.body).toBe(200);
  expect(list.json().data.categories).toEqual([{categoryCode:'B',state:'READY',issues:[],programmeCount:1,tariffCount:1,activeTrainings:2,lessonDurations:[50],competencyCounts:[2],
   lessonTariffs:[{label:'Leçon 50 min',durationMinutes:50,unitPriceCents:9000,unitLabel:'leçon',upcoming:false}]}]);
  const data=await sheet('B');
  expect(data).toMatchObject({categoryCode:'B',state:'READY',canConfigureCatalog:true});
  expect(data.programmes).toHaveLength(1);
  expect(data.programmes[0]).toMatchObject({offeringKey:'category-b',head:{id:id.offeringA,version:1,enabled:true,ready:true,label:null},enrollments:{current:2,previous:0}});
  expect(data.programmes[0].curriculum.competencies.map((item:{key:string})=>item.key)).toEqual(['look','lane']);
  expect(data.programmes[0].procedure.procedureText).toBe('Recette uniquement');
  expect(data.tariffs).toHaveLength(1);expect(data.tariffs[0]).toMatchObject({productKey:'lesson-50',status:'OFFERED',termsSharedWith:0,head:{unitPriceCents:9000}});
  for(const subject of ['demo-instructor','demo-alice'])expect((await call('GET','/formations/sheet?category=B',undefined,null,subject)).statusCode).toBe(403);
  expect((await call('GET','/formations/sheet?category=Z',undefined,null,admin)).statusCode).toBe(404);
  expect((await call('GET',`/v1/schools/${id.schoolB}/formations/sheet?category=B`,undefined,null,admin)).statusCode).toBe(403);
 });

 it('référence hors première page : la fiche ne dépend pas d’une liste complète du catalogue',async()=>{
  // Plus de 1 000 versions d'autres tarifs, créées avant le tarif lu : readAll (10 pages de 100) n'atteindrait pas la référence.
  await pool.query(`INSERT INTO drivy.service_product_version(school_id,version,product_key,label,type,category_code,site_id,duration_minutes,unit_label,unit_price_cents,valid_from,valid_until,terms_version_id,enabled,created_at)
   SELECT $1,1,'bulk-'||g,'Archive '||g,'EXTERNAL_SERVICE',NULL,NULL,NULL,'unité',100,'2026-01-01',NULL,$2,true,now()-interval '1 day' FROM generate_series(1,1100) g`,[id.schoolA,commercial.terms.id]);
  const later=await tariff(lessonTariff({label:'Leçon tardive',durationMinutes:100,priceCents:15000}));expect(later.statusCode,later.body).toBe(201);
  const data=await sheet('B');expect(data.tariffs.map((item:{head:{id:string}})=>item.head.id)).toContain(later.json().data.id);
  const ref=await call('GET',`/formations/references/${later.json().data.id}`,undefined,null,admin);expect(ref.statusCode,ref.body).toBe(200);
  expect(ref.json().data).toMatchObject({kind:'TARIFF',categoryCode:'B',current:true});
  const uncategorized=await call('GET','/formations/uncategorized-tariffs',undefined,null,admin);expect(uncategorized.json().data.tariffs.length).toBe(1100);
  expect((await call('GET','/formations/terms',undefined,null,admin)).json().data.items.find((item:{id:string})=>item.id===commercial.terms.id)).toMatchObject({currentTariffs:1101});
  await pool.query("DELETE FROM drivy.service_product_version WHERE school_id=$1 AND product_key LIKE 'bulk-%'",[id.schoolA]);
  // Retrait du tarif tardif : une nouvelle version désactivée, jamais une suppression.
  const removed=await tariff({mode:'UPDATE',productKey:later.json().data.productKey,expectedProductVersionId:later.json().data.id,type:'INDIVIDUAL_LESSON',label:'Leçon tardive',durationMinutes:100,unitLabel:'leçon',priceCents:15000,validUntil:null,enabled:false,terms:{mode:'KEEP'}});
  expect(removed.statusCode,removed.body).toBe(201);
 });
});

describe('programme d’un parcours',()=>{
 it('compétences et règles : nouvelles versions rattachées en une opération, inscriptions existantes inchangées',async()=>{
  // Une leçon et un bilan existants sur le programme initial.
  const lesson=await call('POST','/lessons',lessonBody(commercial,school.policy,2,8));expect(lesson.statusCode,lesson.body).toBe(201);
  await moveToPast(pool,lesson.json().data.id);
  const done=await call('POST',`/lessons/${lesson.json().data.id}/complete`,{operationId:randomUUID(),actualStart:new Date(Date.now()-7_200_000).toISOString(),actualEnd:new Date(Date.now()-5_400_000).toISOString(),
   workedOn:'Travail',observationText:'Constat',nextStep:'Suite',anomalyReason:'Permis non contrôlé (recette)'},lesson.json().data.version);
  expect(done.statusCode,done.body).toBe(200);
  const draft=done.json().data.draft,observations=[{competencyId:school.competency,level:'GUIDED',context:'Avant la modification'}];
  const saved=await call('PUT',`/report-drafts/${draft.id}`,{operationId:randomUUID(),workedOn:'Travail',observationText:'',nextStep:'',observations,attachmentIds:[]},draft.version);
  expect(saved.statusCode,saved.body).toBe(200);
  const before={curricula:await count('curriculum_version'),policies:await count('school_policy_version'),offerings:await count('offering_version'),configuration:(await pool.query('SELECT configuration_version FROM drivy.school WHERE id=$1',[id.schoolA])).rows[0].configuration_version};
  const changed=[{key:'look',label:'Observation',description:'Synthétique'},{key:null,label:'Intersections',description:'Franchir les intersections.'}];
  const updated=await programme({expectedOfferingVersionId:id.offeringA,competencies:changed,procedure:{...procedure}});
  expect(updated.statusCode,updated.body).toBe(201);
  const result=updated.json().data;expect(result).toMatchObject({version:2,previousOfferingVersionId:id.offeringA,changed:['competencies','procedure']});
  expect(await count('curriculum_version')).toBe(before.curricula+1);expect(await count('school_policy_version')).toBe(before.policies+1);expect(await count('offering_version')).toBe(before.offerings+1);
  expect((await pool.query('SELECT configuration_version FROM drivy.school WHERE id=$1',[id.schoolA])).rows[0].configuration_version).toBe(before.configuration+1);
  // Rechargement : la fiche relit exactement les références enregistrées.
  const reread=await head();
  expect(reread.head).toMatchObject({id:result.id,version:2});expect(reread.curriculum.id).toBe(result.curriculumVersionId);expect(reread.procedure.id).toBe(result.policyVersionId);
  expect(reread.curriculum.competencies.map((item:{key:string;label:string})=>[item.key,item.label])).toEqual([['look','Observation'],[expect.stringMatching(/^competence-/),'Intersections']]);
  expect(reread.procedure).toMatchObject(procedure);expect(reread.enrollments).toEqual({current:0,previous:2});
  expect(reread.history.map((item:{version:number;trainings:number})=>[item.version,item.trainings])).toEqual([[2,0],[1,2]]);
  // L'élève inscrit garde son programme et sa procédure, y compris pour une nouvelle leçon.
  const training=(await pool.query('SELECT offering_id FROM drivy.training WHERE id=$1',[id.aliceTraining])).rows[0];expect(training.offering_id).toBe(id.offeringA);
  const progress=(await call('GET',`/trainings/${id.aliceTraining}/progress`,undefined,null,admin)).json().data;
  expect([...progress.unobservedCompetencyIds,...progress.items.map((item:{competencyId:string})=>item.competencyId)].sort()).toEqual([school.competency,school.competency2].sort());
  const nextLesson=await call('POST','/lessons',lessonBody(commercial,school.policy,3,8));expect(nextLesson.statusCode,nextLesson.body).toBe(201);
  expect(nextLesson.json().data.policyVersionId??(await pool.query('SELECT policy_version_id FROM drivy.lesson WHERE id=$1',[nextLesson.json().data.id])).rows[0].policy_version_id).toBe(school.policy);
  expect((await call('POST','/lessons',lessonBody(commercial,result.policyVersionId,4,8))).json().code).toBe('SCHOOL_POLICY_CHANGED');
  // Le bilan existant conserve ses observations ; le programme de l'élève reste le référentiel initial.
  const kept=await call('GET',`/report-drafts/${draft.id}`);expect(kept.json().data.observations).toEqual(observations);
  const newCompetency=reread.curriculum.competencies[1].id;
  expect((await call('PUT',`/report-drafts/${draft.id}`,{operationId:randomUUID(),workedOn:'Travail',observationText:'',nextStep:'',observations:[{competencyId:newCompetency,level:'GUIDED',context:'x'}],attachmentIds:[]},saved.json().data.version)).json().code).toBe('CURRICULUM_VERSION_MISMATCH');
  // Une nouvelle inscription utilise la nouvelle version ; l'ancienne n'est plus proposée.
  await pool.query("UPDATE drivy.training SET status='CANCELLED',closed_on=current_date WHERE id=$1",[id.bobTraining]);
  expect((await call('POST','/trainings',{operationId:randomUUID(),learnerId:id.bobLearner,offeringId:id.offeringA},null,admin)).json().code).toBe('OFFERING_NOT_READY');
  const enrolled=await call('POST','/trainings',{operationId:randomUUID(),learnerId:id.bobLearner,offeringId:result.id},null,admin);expect(enrolled.statusCode,enrolled.body).toBe(201);
  const bobProgress=(await call('GET',`/trainings/${enrolled.json().data.id}/progress`,undefined,null,admin)).json().data;
  expect(bobProgress.unobservedCompetencyIds.sort()).toEqual(reread.curriculum.competencies.map((item:{id:string})=>item.id).sort());
 });

 it('aucune version superflue, conflit explicite, reprise idempotente et AP72',async()=>{
  const current=await head(),expected=current.head.id;
  const same=current.curriculum.competencies.map((item:{key:string;label:string;description:string})=>({key:item.key,label:item.label,description:item.description}));
  const versions=async()=>[await count('curriculum_version'),await count('school_policy_version'),await count('offering_version')];
  const before=await versions();
  const unchanged=await programme({expectedOfferingVersionId:expected,competencies:same,procedure:{procedureText:current.procedure.procedureText,cancellationPolicyText:current.procedure.cancellationPolicyText,sourceUrls:current.procedure.sourceUrls}});
  expect(unchanged.statusCode).toBe(409);expect(unchanged.json().code).toBe('FORMATION_UNCHANGED');expect(await versions()).toEqual(before);
  // Deux administrations partent de la même tête : une seule écriture, l'autre reçoit un conflit sans effet.
  const [first,second]=await Promise.all([programme({expectedOfferingVersionId:expected,defaultDurationMinutes:55}),programme({expectedOfferingVersionId:expected,defaultDurationMinutes:60})]);
  const statuses=[first.statusCode,second.statusCode].sort();expect(statuses).toEqual([201,409]);
  expect([first,second].find(item=>item.statusCode===409)!.json().code).toBe('FORMATION_CHANGED');
  expect(await versions()).toEqual([before[0],before[1],before[2]!+1]);
  // Réponse perdue après commit : le renvoi de la même opération retrouve le résultat, sans second effet.
  const operationId=randomUUID(),latest=(await head()).head.id,body={operationId,offeringKey:'category-b',expectedOfferingVersionId:latest,label:'Parcours principal'};
  const sent=await call('POST','/formations/programmes',body,null,admin);expect(sent.statusCode,sent.body).toBe(201);
  const again=await call('POST','/formations/programmes',body,null,admin);expect(again.statusCode).toBe(201);expect(again.json().data).toEqual(sent.json().data);
  expect(await count('operation','operation_id=$1',[operationId])).toBe(1);expect(await count('audit_event','operation_id=$1',[operationId])).toBe(1);
  const receipt=await call('GET',`/operations/${operationId}`,undefined,null,admin);expect(receipt.statusCode,receipt.body).toBe(200);
  expect(receipt.json().data).toMatchObject({operationId,commandType:'UPDATE_FORMATION_PROGRAMME',resourceType:'Offering',resourceId:sent.json().data.id,resourceVersion:sent.json().data.version});
  expect((await call('POST','/formations/programmes',{...body,label:'Autre nom'},null,admin)).json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await head()).head.label).toBe('Parcours principal');
 });

 it('échec injecté au milieu de l’écriture : rien n’est conservé',async()=>{
  await pool.query(`CREATE FUNCTION drivy.fail_injected_offering() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.label='Échec injecté' THEN RAISE EXCEPTION 'échec injecté'; END IF; RETURN NEW; END $$`);
  await pool.query('CREATE TRIGGER fail_injected BEFORE INSERT ON drivy.offering_version FOR EACH ROW EXECUTE FUNCTION drivy.fail_injected_offering()');
  try {
   const current=await head(),before=[await count('curriculum_version'),await count('competency_definition'),await count('school_policy_version'),await count('offering_version'),await count('operation'),await count('audit_event'),await count('school_settings_version')];
   const config=(await pool.query('SELECT version,configuration_version FROM drivy.school WHERE id=$1',[id.schoolA])).rows[0];
   const failed=await programme({expectedOfferingVersionId:current.head.id,label:'Échec injecté',competencies:[...competencies],procedure:{...procedure,procedureText:'Nouveau déroulement jamais conservé.'}});
   expect(failed.statusCode).toBeGreaterThanOrEqual(500);
   expect([await count('curriculum_version'),await count('competency_definition'),await count('school_policy_version'),await count('offering_version'),await count('operation'),await count('audit_event'),await count('school_settings_version')]).toEqual(before);
   expect((await pool.query('SELECT version,configuration_version FROM drivy.school WHERE id=$1',[id.schoolA])).rows[0]).toEqual(config);
   expect((await head()).head.id).toBe(current.head.id);
  } finally {await pool.query('DROP TRIGGER fail_injected ON drivy.offering_version');await pool.query('DROP FUNCTION drivy.fail_injected_offering()');}
 });

 it('droits relus au commit et références d’une autre école refusées',async()=>{
  const current=await head();
  expect((await programme({expectedOfferingVersionId:current.head.id,defaultDurationMinutes:40},'demo-instructor')).json().code).toBe('SETUP_ACCESS_REQUIRED');
  expect((await programme({expectedOfferingVersionId:id.offeringB,defaultDurationMinutes:40})).statusCode).toBe(404);
  expect((await programme({offeringKey:'inconnue',expectedOfferingVersionId:current.head.id,defaultDurationMinutes:40})).statusCode).toBe(404);
  expect([403,404]).toContain((await call('POST',`/v1/schools/${id.schoolB}/formations/programmes`,{operationId:randomUUID(),offeringKey:'category-b',expectedOfferingVersionId:id.offeringB,defaultDurationMinutes:40},null,admin)).statusCode);
  expect((await programme({expectedOfferingVersionId:current.head.id,competencies:[{key:'inventee',label:'X',description:'Y'}]})).json().code).toBe('COMPETENCY_KEY_UNKNOWN');
  expect((await programme({expectedOfferingVersionId:current.head.id})).statusCode).toBe(400);
  // Le droit commercial retiré entre la lecture et l'enregistrement : refus, aucune écriture.
  const opened=await sheet('B'),target=opened.tariffs.find((item:{productKey:string})=>item.productKey==='lesson-50');
  await pool.query("UPDATE drivy.membership SET grants='{}' WHERE id=$1",[id.adminMember]);
  try {
   const refused=await tariff({mode:'UPDATE',productKey:'lesson-50',expectedProductVersionId:target.head.id,type:'INDIVIDUAL_LESSON',label:target.head.label,durationMinutes:50,unitLabel:'leçon',priceCents:9900,validUntil:null,enabled:true,terms:{mode:'KEEP'}});
   expect(refused.statusCode).toBe(403);expect(await count('service_product_version','school_id=$1 AND product_key=$2',[id.schoolA,'lesson-50'])).toBe(1);
   expect((await call('POST','/formations',newFormation(),null,admin)).statusCode).toBe(403);
   expect((await sheet('B')).canConfigureCatalog).toBe(false);
  } finally {await pool.query("UPDATE drivy.membership SET grants='{CONFIGURE_CATALOG}' WHERE id=$1",[id.adminMember]);}
 });
});

describe('tarifs et conditions',()=>{
 it('prix modifié : la réservation existante garde son prix et ses conditions, les suivantes utilisent la nouvelle version',async()=>{
  const lesson=await call('POST','/lessons',lessonBody(commercial,school.policy,5,8));expect(lesson.statusCode,lesson.body).toBe(201);
  const current=(await sheet('B')).tariffs.find((item:{productKey:string})=>item.productKey==='lesson-50');
  const raised=await tariff({mode:'UPDATE',productKey:'lesson-50',expectedProductVersionId:current.head.id,type:'INDIVIDUAL_LESSON',label:'Leçon 50 min',durationMinutes:50,unitLabel:'leçon',priceCents:9500,validUntil:null,enabled:true,terms:{mode:'KEEP'}});
  expect(raised.statusCode,raised.body).toBe(201);expect(raised.json().data).toMatchObject({version:2,termsVersionId:commercial.terms.id,changed:['unitPriceCents'],previousProductVersionId:commercial.product.id});
  const stored=(await pool.query('SELECT price_cents_snapshot,commercial_selection FROM drivy.lesson WHERE id=$1',[lesson.json().data.id])).rows[0];
  expect(stored).toEqual({price_cents_snapshot:'9000',commercial_selection:expect.objectContaining({serviceProductVersionId:commercial.product.id,acceptedTermsVersionId:commercial.terms.id})});
  expect((await call('POST','/lessons',lessonBody(commercial,school.policy,6,8))).json().code).toBe('COMMERCIAL_SELECTION_INVALID');
  const next=await call('POST','/lessons',lessonBody({terms:commercial.terms,product:{id:raised.json().data.id}},school.policy,6,8,{agreedPriceCents:9500}));expect(next.statusCode,next.body).toBe(201);
  const reread=(await sheet('B')).tariffs.find((item:{productKey:string})=>item.productKey==='lesson-50');
  expect(reread.head).toMatchObject({id:raised.json().data.id,version:2,unitPriceCents:9500,validFrom:today()});
  expect(reread.history.map((item:{version:number;unitPriceCents:number})=>[item.version,item.unitPriceCents])).toEqual([[2,9500],[1,9000]]);
  // Aucun changement : aucune version.
  expect((await tariff({mode:'UPDATE',productKey:'lesson-50',expectedProductVersionId:reread.head.id,type:'INDIVIDUAL_LESSON',label:'Leçon 50 min',durationMinutes:50,unitLabel:'leçon',priceCents:9500,validUntil:null,enabled:true,terms:{mode:'NEW',termsText:'Texte synthétique'}})).json().code).toBe('TARIFF_UNCHANGED');
  // Ancienne tête : conflit explicite.
  expect((await tariff({mode:'UPDATE',productKey:'lesson-50',expectedProductVersionId:commercial.product.id,type:'INDIVIDUAL_LESSON',label:'Leçon 50 min',durationMinutes:50,unitLabel:'leçon',priceCents:9600,validUntil:null,enabled:true,terms:{mode:'KEEP'}})).json().code).toBe('TARIFF_CHANGED');
 });

 it('conditions partagées : modifier celles d’un tarif crée une référence pour ce seul tarif',async()=>{
  const shared=await call('POST','/service-products',{operationId:randomUUID(),productKey:'exam-b',label:'Accompagnement examen',type:'EXAM_SUPPORT',categoryCode:'B',siteId:null,durationMinutes:90,unitLabel:'accompagnement',
   unitPriceCents:12000,validFrom:today(),validUntil:null,termsVersionId:commercial.terms.id,enabled:true},null,admin);expect(shared.statusCode,shared.body).toBe(201);
  let data=await sheet('B');const lessonTariff50=data.tariffs.find((item:{productKey:string})=>item.productKey==='lesson-50');
  expect(lessonTariff50.termsSharedWith).toBe(1);expect(data.tariffs.find((item:{productKey:string})=>item.productKey==='exam-b').termsSharedWith).toBe(1);
  const updated=await tariff({mode:'UPDATE',productKey:'lesson-50',expectedProductVersionId:lessonTariff50.head.id,type:'INDIVIDUAL_LESSON',label:'Leçon 50 min',durationMinutes:50,unitLabel:'leçon',priceCents:9500,validUntil:null,enabled:true,
   terms:{mode:'NEW',termsText:'Nouvelles conditions propres à la leçon de 50 minutes.'}});
  expect(updated.statusCode,updated.body).toBe(201);expect(updated.json().data.changed).toEqual(['terms']);expect(updated.json().data.termsVersionId).not.toBe(commercial.terms.id);
  data=await sheet('B');
  expect(data.tariffs.find((item:{productKey:string})=>item.productKey==='exam-b')).toMatchObject({head:{termsVersionId:commercial.terms.id},termsSharedWith:0});
  expect(data.tariffs.find((item:{productKey:string})=>item.productKey==='lesson-50')).toMatchObject({terms:{termsText:'Nouvelles conditions propres à la leçon de 50 minutes.',validFrom:today()},termsSharedWith:0});
  const terms=await call('GET',`/formations/references/${commercial.terms.id}`,undefined,null,admin);
  expect(terms.json().data).toMatchObject({kind:'TERMS',current:true});expect(terms.json().data.usedBy.map((item:{productKey:string;current:boolean})=>[item.productKey,item.current])).toEqual([['exam-b',true],['lesson-50',false],['lesson-50',false]]);
 });

 it('ajout d’un tarif depuis la fiche : aucune formation créée ni texte scolaire réadopté',async()=>{
  const before={offerings:await count('offering_version'),dataPolicies:await count('school_data_policy'),profiles:await count('profile_field_policy'),
   school:(await pool.query('SELECT status,name,configuration_version FROM drivy.school WHERE id=$1',[id.schoolA])).rows[0],setup:(await pool.query('SELECT draft_version,draft_content FROM drivy.school_setup WHERE school_id=$1',[id.schoolA])).rows[0]};
  const created=await tariff(lessonTariff());expect(created.statusCode,created.body).toBe(201);
  expect(await count('offering_version')).toBe(before.offerings);expect(await count('school_data_policy')).toBe(before.dataPolicies);expect(await count('profile_field_policy')).toBe(before.profiles);
  expect((await pool.query('SELECT status,name,configuration_version FROM drivy.school WHERE id=$1',[id.schoolA])).rows[0]).toEqual(before.school);
  expect((await pool.query('SELECT draft_version,draft_content FROM drivy.school_setup WHERE school_id=$1',[id.schoolA])).rows[0]).toEqual(before.setup);
  const row=(await sheet('B')).tariffs.find((item:{head:{id:string}})=>item.head.id===created.json().data.id);
  expect(row).toMatchObject({status:'OFFERED',head:{label:'Leçon 45 min',durationMinutes:45,unitPriceCents:7000,categoryCode:'B'},terms:{termsText:'Conditions synthétiques de la leçon de 45 minutes.'}});
  // Prix absent refusé, prix zéro conservé tel quel.
  expect((await tariff(lessonTariff({priceCents:null}))).statusCode).toBe(400);
  const free=await tariff(lessonTariff({label:'Leçon d’essai offerte',priceCents:0}));expect(free.statusCode,free.body).toBe(201);
  expect((await pool.query('SELECT unit_price_cents FROM drivy.service_product_version WHERE id=$1',[free.json().data.id])).rows[0].unit_price_cents).toBe('0');
  expect((await tariff(lessonTariff({categoryCode:null}))).json().code).toBe('INVALID_SERVICE_PRODUCT');
  expect((await tariff(lessonTariff({categoryCode:'Z'}))).statusCode).toBe(404);
  // Prestation sans permis.
  const other=await tariff({mode:'CREATE',categoryCode:null,type:'EXTERNAL_SERVICE',label:'Cours de premiers secours',durationMinutes:null,unitLabel:'cours',priceCents:15000,validFrom:today(),validUntil:null,enabled:true,termsText:'Conditions du cours.'});
  expect(other.statusCode,other.body).toBe(201);
  expect((await call('GET','/formations/uncategorized-tariffs',undefined,null,admin)).json().data.tariffs.map((item:{head:{label:string}})=>item.head.label)).toEqual(['Cours de premiers secours']);
 });

 it('désactivation, conditions expirées et dates futures',async()=>{
  const created=(await tariff(lessonTariff({label:'Leçon 90 min',durationMinutes:90,priceCents:13000}))).json().data;
  const disabled=await tariff({mode:'UPDATE',productKey:created.productKey,expectedProductVersionId:created.id,type:'INDIVIDUAL_LESSON',label:'Leçon 90 min',durationMinutes:90,unitLabel:'leçon',priceCents:13000,validUntil:null,enabled:false,terms:{mode:'KEEP'}});
  expect(disabled.statusCode,disabled.body).toBe(201);
  const row=(await sheet('B')).tariffs.find((item:{productKey:string})=>item.productKey===created.productKey);expect(row).toMatchObject({status:'DISABLED',head:{version:2,enabled:false}});
  // L'ancienne version active n'est jamais ressuscitée par la planification.
  expect((await pool.query('SELECT drivy.service_product_current($1) AS current',[created.id])).rows[0].current).toBe(false);
  // Conditions expirées.
  const expired=await call('POST','/commercial-terms',{operationId:randomUUID(),label:'Anciennes conditions',termsText:'Conditions échues.',validFrom:shift(-30),validUntil:shift(-1),approved:true},null,admin);expect(expired.statusCode,expired.body).toBe(201);
  const old=await call('POST','/service-products',{operationId:randomUUID(),productKey:'old-terms',label:'Leçon ancienne',type:'INDIVIDUAL_LESSON',categoryCode:'B',siteId:null,durationMinutes:50,unitLabel:'leçon',unitPriceCents:8000,validFrom:shift(-30),validUntil:null,termsVersionId:expired.json().data.id,enabled:true},null,admin);
  expect(old.statusCode,old.body).toBe(201);
  expect((await sheet('B')).tariffs.find((item:{productKey:string})=>item.productKey==='old-terms').status).toBe('TERMS_EXPIRED');
  // Les modifier crée des conditions applicables dès aujourd'hui, même si le texte est identique.
  const renewed=await tariff({mode:'UPDATE',productKey:'old-terms',expectedProductVersionId:old.json().data.id,type:'INDIVIDUAL_LESSON',label:'Leçon ancienne',durationMinutes:50,unitLabel:'leçon',priceCents:8000,validUntil:null,enabled:true,terms:{mode:'NEW',termsText:'Conditions échues.'}});
  expect(renewed.statusCode,renewed.body).toBe(201);expect((await sheet('B')).tariffs.find((item:{productKey:string})=>item.productKey==='old-terms').status).toBe('OFFERED');
  // Date future : un nouveau tarif est annoncé, une version future d'un tarif applicable est refusée.
  const future=await tariff(lessonTariff({label:'Leçon été',durationMinutes:60,priceCents:10000,validFrom:shift(10)}));expect(future.statusCode,future.body).toBe(201);
  expect((await sheet('B')).tariffs.find((item:{head:{id:string}})=>item.head.id===future.json().data.id).status).toBe('NOT_YET');
  const later=await tariff({mode:'UPDATE',productKey:future.json().data.productKey,expectedProductVersionId:future.json().data.id,type:'INDIVIDUAL_LESSON',label:'Leçon été',durationMinutes:60,unitLabel:'leçon',priceCents:10500,validUntil:null,enabled:true,terms:{mode:'KEEP'}});
  expect(later.statusCode,later.body).toBe(201);expect((await sheet('B')).tariffs.find((item:{head:{id:string}})=>item.head.id===later.json().data.id).head.validFrom).toBe(shift(10));
  const gap=await call('POST','/service-products',{operationId:randomUUID(),productKey:'old-terms',label:'Leçon ancienne',type:'INDIVIDUAL_LESSON',categoryCode:'B',siteId:null,durationMinutes:50,unitLabel:'leçon',unitPriceCents:9000,validFrom:shift(5),validUntil:null,termsVersionId:renewed.json().data.termsVersionId,enabled:true},null,admin);
  expect(gap.json().code).toBe('TARIFF_SCHEDULING_UNSUPPORTED');
  expect((await tariff(lessonTariff({validUntil:shift(-1),validFrom:shift(-5)}))).json().code).toBe('INVALID_INTERVAL');
 });
});

describe('création d’une formation',()=>{
 it('assistant : création complète, rechargement, doublon refusé, parcours supplémentaire explicite',async()=>{
  const before={dataPolicies:await count('school_data_policy'),profiles:await count('profile_field_policy'),status:(await pool.query('SELECT status FROM drivy.school WHERE id=$1',[id.schoolA])).rows[0].status};
  expect((await call('POST','/formations',{...newFormation(),tariff:{...newFormation().tariff,priceCents:null}},null,admin)).statusCode).toBe(400);
  const body=newFormation(),created=await call('POST','/formations',body,null,admin);expect(created.statusCode,created.body).toBe(201);
  expect(await count('school_data_policy')).toBe(before.dataPolicies);expect(await count('profile_field_policy')).toBe(before.profiles);
  expect((await pool.query('SELECT status FROM drivy.school WHERE id=$1',[id.schoolA])).rows[0].status).toBe(before.status);
  const data=await sheet('A');expect(data.state).toBe('READY');
  expect(data.programmes).toHaveLength(1);
  expect(data.programmes[0]).toMatchObject({offeringKey:created.json().data.offeringKey,head:{id:created.json().data.id,enabled:true,defaultDurationMinutes:50,label:null}});
  expect(data.programmes[0].curriculum.competencies.map((item:{label:string;description:string})=>[item.label,item.description])).toEqual(competencies.map(item=>[item.label,item.description]));
  expect(data.programmes[0].procedure).toMatchObject(procedure);
  expect(data.tariffs).toEqual([expect.objectContaining({head:expect.objectContaining({id:created.json().data.productId,unitPriceCents:9500,durationMinutes:50,type:'INDIVIDUAL_LESSON'}),
   terms:expect.objectContaining({id:created.json().data.termsVersionId,termsText:'Conditions synthétiques moto.'}),status:'OFFERED'})]);
  expect((await pool.query('SELECT reason FROM drivy.audit_event WHERE operation_id=$1',[body.operationId])).rows[0].reason).toBe('Proposition Drivy pedagogy-a 2026-10-13.2 relue et adaptée');
  // Rejeu : un seul effet.
  expect((await call('POST','/formations',body,null,admin)).json().data).toEqual(created.json().data);expect(await count('offering_version','school_id=$1 AND category_code=$2',[id.schoolA,'A'])).toBe(1);
  expect((await call('POST','/formations',newFormation(),null,admin)).json().code).toBe('FORMATION_ALREADY_EXISTS');
  expect((await call('POST','/formations',newFormation({intent:'ADDITIONAL_PROGRAMME'}),null,admin)).statusCode).toBe(400);
  const additional=await call('POST','/formations',newFormation({intent:'ADDITIONAL_PROGRAMME',programmeLabel:'Parcours accéléré',tariff:{...newFormation().tariff,label:'Leçon intensive 90 min',durationMinutes:90,priceCents:16000}}),null,admin);
  expect(additional.statusCode,additional.body).toBe(201);
  expect((await call('POST','/formations',newFormation({intent:'ADDITIONAL_PROGRAMME',programmeLabel:'parcours ACCÉLÉRÉ'}),null,admin)).json().code).toBe('PROGRAMME_LABEL_TAKEN');
  expect((await call('POST','/formations',newFormation({categoryCode:'C',intent:'ADDITIONAL_PROGRAMME',programmeLabel:'Seul'}),null,admin)).json().code).toBe('FORMATION_NOT_FOUND');
  const both=await sheet('A');expect(both.programmes.map((item:{head:{label:string|null}})=>item.head.label)).toEqual([null,'Parcours accéléré']);
  // Les tarifs restent rattachés au permis : les deux sont visibles une fois, sans rattachement exclusif à un parcours.
  expect(both.tariffs.map((item:{head:{label:string}})=>item.head.label).sort()).toEqual(['Leçon intensive 90 min','Leçon moto 50 min']);
  // Un même élève inscrit à deux permis.
  const enrolled=await call('POST','/trainings',{operationId:randomUUID(),learnerId:id.aliceLearner,offeringId:created.json().data.id},null,admin);expect(enrolled.statusCode,enrolled.body).toBe(201);
  expect((await sheet('A')).programmes[0].enrollments.current).toBe(1);
  expect((await pool.query("SELECT count(*)::int AS n FROM drivy.training WHERE learner_id=$1 AND status IN('ACTIVE','PAUSED')",[id.aliceLearner])).rows[0].n).toBe(2);
  const list=(await call('GET','/formations',undefined,null,admin)).json().data;
  expect(list.categories.map((item:{categoryCode:string;programmeCount:number})=>[item.categoryCode,item.programmeCount])).toEqual([['A',2],['B',1]]);
 });

 it('anciennes références : version exacte, parcours d’usage et éléments non rattachés',async()=>{
  const data=await sheet('B'),current=data.programmes[0];
  const offering=(await call('GET',`/formations/references/${id.offeringA}`,undefined,null,admin)).json().data;
  expect(offering).toMatchObject({kind:'OFFERING',categoryCode:'B',current:false,offeringKey:'category-b',headId:current.head.id,offering:{version:1}});
  expect(offering.curriculum.id).toBe(school.curriculum);
  const curriculum=(await call('GET',`/formations/references/${school.curriculum}`,undefined,null,admin)).json().data;
  expect(curriculum).toMatchObject({kind:'CURRICULUM',current:false,programmes:[{offeringKey:'category-b',current:false}]});
  const procedureRef=(await call('GET',`/formations/references/${school.policy}`,undefined,null,admin)).json().data;expect(procedureRef).toMatchObject({kind:'PROCEDURE',current:false});
  const productRef=(await call('GET',`/formations/references/${commercial.product.id}`,undefined,null,admin)).json().data;expect(productRef).toMatchObject({kind:'TARIFF',current:false,productKey:'lesson-50',tariff:{unitPriceCents:9000}});
  // Référentiel non rattaché (créé hors parcours par l'ancienne route) : retrouvable, sans fiche choisie à sa place.
  const loose=await call('POST','/curricula',{operationId:randomUUID(),categoryCode:'B',approved:false,competencies:[{key:'x',label:'Brouillon',description:'Jamais rattaché.',sortOrder:0}]},null,admin);
  expect(loose.statusCode,loose.body).toBe(201);
  expect((await sheet('B')).unattached.curricula.map((item:{id:string})=>item.id)).toContain(loose.json().data.id);
  expect((await call('GET',`/formations/references/${loose.json().data.id}`,undefined,null,admin)).json().data).toMatchObject({kind:'CURRICULUM',current:false,programmes:[]});
  expect((await call('GET',`/formations/references/${randomUUID()}`,undefined,null,admin)).statusCode).toBe(404);
  expect((await call('GET',`/formations/references/${id.offeringB}`,undefined,null,admin)).statusCode).toBe(404);
 });
});
