import {createHash,randomUUID} from 'node:crypto';
import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {ApiError,notFound} from './errors.js';
import {canonical,checkIdempotency,checkVersion,requireVersion,schoolColumns,schoolCommand,schoolProjection,type SchoolRow,type CommandActor} from './commands.js';
import {readiness,recordSettings} from './school-setup.js';
import {cataloguePermission} from './lesson-setup.js';
import {planningReadiness} from './lessons.js';
import {missingProfileFieldsLateral} from './profile-completeness.js';
import {contentIssues,emptySetupContent,schoolSetupTemplates,setupContentSchema,setupSteps,templateVersion,type SetupContent,type SetupFormation,type SetupIssue} from './school-onboarding-model.js';

const empty=z.object({}).strict();
export const saveSetupDraftCommand=z.object({operationId:z.uuid(),currentStep:z.enum(setupSteps),content:setupContentSchema}).strict();
export const completeSetupDraftCommand=z.object({operationId:z.uuid(),expectedSchoolVersion:z.number().int().positive(),expectedConfigurationVersion:z.number().int().positive(),
  reviewDigest:z.string().regex(/^[a-f0-9]{64}$/),reviewAcknowledged:z.literal(true),activate:z.boolean()}).strict();
const previewQuery=z.object({activate:z.enum(['true','false']).transform(value=>value==='true')}).strict();
interface DraftRow {draft_version:number;draft_step:typeof setupSteps[number];draft_content:SetupContent|null;draft_updated_at:Date|null;draft_updated_by:string|null;draft_applied_at:Date|null;configured_by:string}
interface DataPolicyRow {version:number;notice_version_id:string;notice_text:string;retention_text:string;contact_email:string|null;approved_at:Date|null}
const dataPolicy=async(db:PoolClient,schoolId:string)=>(await db.query<DataPolicyRow>('SELECT * FROM drivy.school_data_policy WHERE school_id=$1 ORDER BY version DESC LIMIT 1',[schoolId])).rows[0];

async function draft(db:PoolClient,school:SchoolRow) {
  const row=(await db.query<DraftRow>('SELECT draft_version,draft_step,draft_content,draft_updated_at,draft_updated_by,draft_applied_at,configured_by FROM drivy.school_setup WHERE school_id=$1',[school.id])).rows[0];
  if(!row)throw new ApiError(409,'SETUP_NOT_INITIALIZED','La préparation de cette école doit être initialisée.');
  let content=row.draft_content;
  if(content===null) {
    content=emptySetupContent(school);
    const policy=await dataPolicy(db,school.id);
    if(policy?.approved_at)content.privacy={noticeText:policy.notice_text,retentionText:policy.retention_text,contactEmail:policy.contact_email??school.contactEmail,templateId:null,templateVersion:null};
    const profile=(await db.query<{fields:SetupContent['profile']['fields']}>('SELECT fields FROM drivy.profile_field_policy WHERE school_id=$1 AND status=\'PUBLISHED\' AND effective_from<=now() ORDER BY effective_from DESC LIMIT 1',[school.id])).rows[0];
    if(profile)content.profile.fields=profile.fields;
  }
  return {id:school.id,schoolId:school.id,version:row.draft_version,status:row.draft_applied_at?'APPLIED' as const:'DRAFT' as const,currentStep:row.draft_step,
    content,updatedAt:row.draft_updated_at?.toISOString()??null,updatedByMembershipId:row.draft_updated_by??row.configured_by,appliedAt:row.draft_applied_at?.toISOString()??null};
}
type Draft=Awaited<ReturnType<typeof draft>>;
interface NextAction {code:string;label:string;section:string;query?:{selection?:string;learner?:string;instructor?:string;from?:'formations';audience?:'learners'|'team'}}
const selected=(content:SetupContent,section:SetupContent['selectedSections'][number])=>content.selectedSections.includes(section);
const activeFormations=(content:SetupContent)=>selected(content,'CATALOGUE')?content.formations.filter(item=>item.apply):[];

async function review(db:PoolClient,school:SchoolRow,current:Draft,activate:boolean) {
  const content=current.content,issues:SetupIssue[]=contentIssues(content);
  const issue=(field:string,code:string,message:string)=>issues.push({field,code,message});
  if(current.status==='APPLIED')issue('review','SETUP_DRAFT_ALREADY_APPLIED','Cette version a déjà été appliquée. Enregistrez vos nouveaux choix avant de les confirmer.');
  if(school.status==='ARCHIVED')issue('review','SCHOOL_ARCHIVED','Cette école est archivée.');
  if(activate&&school.status!=='DRAFT')issue('review','SCHOOL_ALREADY_ACTIVE','Cette école est déjà active. Utilisez la modification de configuration.');
  if(!activate&&school.status==='DRAFT')issue('review','SETUP_ACTIVATION_REQUIRED','Confirmez l’activation pour appliquer la préparation initiale.');
  if(!activate&&content.selectedSections.length===0)issue('review','SETUP_SECTION_REQUIRED','Choisissez les éléments à appliquer.');
  if(selected(content,'IDENTITY')&&school.status==='ACTIVE'&&content.identity.timeZone!==school.timeZone)issue('identity.timeZone','CONFIG_IMPACT_REVIEW_REQUIRED','Le changement de fuseau d’une école active nécessite une analyse d’impact.');
  const currentPolicy=await dataPolicy(db,school.id);
  if((activate||selected(content,'PROFILE'))&&!selected(content,'PRIVACY')&&!currentPolicy?.approved_at)issue('privacy','POLICY_REVIEW_REQUIRED','Préparez et adoptez les textes de confidentialité.');
  if(activate&&!selected(content,'IDENTITY')) {
    const identityIssues=contentIssues({...content,selectedSections:['IDENTITY'],identity:{name:school.name,timeZone:school.timeZone,contactEmail:school.contactEmail,contactPhone:school.contactPhone}});
    issues.push(...identityIssues);
  }
  const formations=activeFormations(content),references:unknown[]=[];
  if(formations.length) {
    const permitted=(await db.query<{ok:boolean}>('SELECT drivy.lesson_catalogue_manage($1) AS ok',[school.id])).rows[0]?.ok;
    if(!permitted)issue('formations','CATALOGUE_ACCESS_REQUIRED','L’autorisation de configurer les prestations et tarifs est nécessaire.');
    for(const item of formations) {
      if(item.existingOfferingId) {
        const row=(await db.query<{id:string;category_code:string;ready:boolean}>(`SELECT id,category_code,drivy.catalogue_offering_ready(id) AS ready FROM drivy.offering_version WHERE school_id=$1 AND id=$2`,[school.id,item.existingOfferingId])).rows[0];
        references.push(row??{missing:item.existingOfferingId});
        if(!row||!row.ready||row.category_code!==item.categoryCode)issue(`formations.${content.formations.indexOf(item)}.existingOfferingId`,'OFFERING_NOT_READY','Choisissez une formation active et approuvée de ce permis.');
      }
      const alreadyApplied=(await db.query<{used:boolean}>(`SELECT EXISTS(SELECT 1 FROM drivy.service_product_version WHERE school_id=$1 AND product_key=$2)
        OR ($3::boolean AND EXISTS(SELECT 1 FROM drivy.offering_version WHERE school_id=$1 AND offering_key=$2)) AS used`,[school.id,`setup-${item.id}`,item.existingOfferingId===null])).rows[0]!.used;
      if(alreadyApplied)issue(`formations.${content.formations.indexOf(item)}.id`,'SETUP_ITEM_ALREADY_APPLIED','Cette prestation a déjà été créée. Préparez un nouveau tarif pour continuer.');
    }
  }
  const effects:string[]=[];
  if(selected(content,'PRIVACY')&&school.status==='ACTIVE') {
    const impact=(await db.query<{gps_agreements:number;active_captures:number}>('SELECT * FROM drivy.data_policy_change_impact($1)',[school.id])).rows[0];
    effects.push(`L’adoption rendra caducs ${impact?.gps_agreements??0} accord(s) GPS sur les textes actuels et interrompra ${impact?.active_captures??0} trajet(s) en cours. Un nouvel accord GPS sera nécessaire pour les prochains trajets.`);
  }
  const state={schoolId:school.id,draftVersion:current.version,schoolVersion:school.version,configurationVersion:school.configurationVersion,activate,
    selectedSections:content.selectedSections,content};
  const reviewDigest=createHash('sha256').update(canonical({...state,currentPolicy:currentPolicy?.notice_version_id??null,references,templateVersion,effects})).digest('hex');
  return {...state,reviewDigest,ready:issues.length===0,issues,effects};
}

/** Versions nouvelles uniquement : les références des engagements précédents restent intactes. */
async function publishFormation(db:PoolClient,school:SchoolRow,actor:CommandActor,item:SetupFormation,reason:string) {
  let offeringId=item.existingOfferingId;
  if(offeringId===null) {
    const curriculumId=(await db.query<{id:string}>(`INSERT INTO drivy.curriculum_version(school_id,category_code,revision,approved,approval_reason,created_by,approved_at)
      SELECT $1,$2,coalesce(max(revision),0)+1,true,$3,$4,now() FROM drivy.curriculum_version WHERE school_id=$1 AND category_code=$2 RETURNING id`,[school.id,item.categoryCode,reason,actor.membershipId])).rows[0]!.id;
    for(const c of item.competencies)await db.query('INSERT INTO drivy.competency_definition(school_id,curriculum_version_id,stable_key,label,description,sort_order) VALUES($1,$2,$3,$4,$5,$6)',[school.id,curriculumId,c.key,c.label,c.description,c.sortOrder]);
    const policyId=(await db.query<{id:string}>(`INSERT INTO drivy.school_policy_version(school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at)
      SELECT $1,$2,coalesce(max(version),0)+1,$3,$4,$5,true,$6,$7,now() FROM drivy.school_policy_version WHERE school_id=$1 AND category_code=$2 RETURNING id`,[school.id,item.categoryCode,item.procedureText,item.cancellationPolicyText,item.sourceUrls,reason,actor.membershipId])).rows[0]!.id;
    offeringId=(await db.query<{id:string}>(`INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version,enabled,curriculum_version_id,policy_version_id,default_duration_minutes,default_price_cents)
      VALUES($1,$2,$3,$4,1,true,$5,$6,$7,$8) RETURNING id`,[randomUUID(),school.id,`setup-${item.id}`,item.categoryCode,curriculumId,policyId,item.durationMinutes,item.priceCents])).rows[0]!.id;
  }
  const termsId=(await db.query<{id:string}>(`INSERT INTO drivy.commercial_terms_version(school_id,version,label,terms_text,valid_from,valid_until,approved,approval_reason,approved_by,approved_at,created_by)
    SELECT $1,coalesce(max(version),0)+1,$2,$3,$4,NULL,true,$5,$6,now(),$6 FROM drivy.commercial_terms_version WHERE school_id=$1 RETURNING id`,[school.id,`Conditions · ${item.label}`.slice(0,200),item.termsText,item.validFrom,reason,actor.membershipId])).rows[0]!.id;
  const productId=(await db.query<{id:string}>(`INSERT INTO drivy.service_product_version(school_id,version,product_key,label,type,category_code,site_id,duration_minutes,unit_label,unit_price_cents,valid_from,valid_until,terms_version_id,enabled)
    SELECT $1,coalesce(max(version),0)+1,$2,$3,'INDIVIDUAL_LESSON',$4,NULL,$5,'leçon',$6,$7,NULL,$8,true FROM drivy.service_product_version WHERE school_id=$1 AND product_key=$2 RETURNING id`,[school.id,`setup-${item.id}`,item.label,item.categoryCode,item.durationMinutes,item.priceCents,item.validFrom,termsId])).rows[0]!.id;
  return {offeringId,productId,termsId};
}

/** Cible réelle ayant franchi les étapes précédant ce blocage, avec les mêmes droits que planningReadiness. */
async function learnerPreparationTarget(db:PoolClient,schoolId:string,learnerId:string,requireAvailability:boolean) {
  return (await db.query<{offering_id:string;instructor_membership_id:string}>(`SELECT t.offering_id,a.instructor_membership_id
    FROM drivy.training t JOIN drivy.school sc ON sc.id=t.school_id
    JOIN drivy.offering_version o ON o.school_id=t.school_id AND o.id=t.offering_id
    JOIN drivy.school_policy_version p ON p.school_id=o.school_id AND p.id=o.policy_version_id
    JOIN drivy.instructor_assignment a ON a.school_id=t.school_id AND a.training_id=t.id
    WHERE t.school_id=$1 AND t.learner_id=$2 AND t.status='ACTIVE' AND drivy.lesson_learner_active(t.id)
      AND o.enabled AND p.approved AND drivy.catalogue_training_visible(t.id)
      AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())
      AND drivy.lesson_instructor_manage(t.school_id,a.instructor_membership_id)
      AND (NOT $3::boolean OR EXISTS(SELECT 1 FROM drivy.availability_rule r WHERE r.school_id=a.school_id
        AND r.instructor_membership_id=a.instructor_membership_id AND r.removed_at IS NULL
        AND (r.valid_until IS NULL OR r.valid_until>=(now() AT TIME ZONE sc.time_zone)::date)))
    ORDER BY t.created_at,t.id,a.valid_from DESC,a.id LIMIT 1`,[schoolId,learnerId,requireAvailability])).rows[0];
}

async function nextActions(db:PoolClient,school:SchoolRow) {
  const state=await readiness(db,school),planning=state.capabilities.find(item=>item.capability==='CAN_PLAN_LESSON')!;
  const mapping:Record<string,{label:string;section:string;order:number}>={
    SCHOOL_IDENTITY_REQUIRED:{label:'Compléter les coordonnées de l’école',section:'configuration',order:0},
    INVALID_TIME_ZONE:{label:'Confirmer le fuseau de l’école',section:'configuration',order:0},
    SCHOOL_CONTACT_REQUIRED:{label:'Compléter le contact de l’école',section:'configuration',order:0},
    POLICY_REVIEW_REQUIRED:{label:'Préparer les textes de confidentialité',section:'confidentialite',order:1},
    SCHOOL_NOT_ACTIVE:{label:'Reprendre la préparation de l’école',section:'apercu',order:2},
    SCHOOL_ARCHIVED:{label:'Consulter l’état de l’école',section:'configuration',order:2},
    PROFILE_POLICY_NOT_READY:{label:'Confirmer les informations demandées aux élèves',section:'champs-profil',order:3},
    OFFERING_REQUIRED:{label:'Préparer une formation',section:'formations',order:4},
    COMMERCIAL_SETUP_REQUIRED:{label:'Ajouter le tarif d’une leçon',section:'prestations',order:5},
    INSTRUCTOR_REQUIRED:{label:'Ajouter un moniteur actif',section:'equipe',order:6},
    AVAILABILITY_REQUIRED:{label:'Définir les disponibilités du moniteur',section:'disponibilites',order:7}
  };
  const seen=new Set<string>();
  const actions:NextAction[]=planning.blockers.filter(item=>{if(seen.has(item.code))return false;seen.add(item.code);return true;})
    .sort((a,b)=>(mapping[a.code]?.order??99)-(mapping[b.code]?.order??99))
    .map(item=>({code:item.code,label:mapping[item.code]?.label??item.message,section:mapping[item.code]?.section??'apercu'}));
  // Une école déjà utilisée ne revient jamais à « votre premier élève ». Les blocages courants restent utiles.
  const used=(await db.query('SELECT id FROM drivy.lesson WHERE school_id=$1 LIMIT 1',[school.id])).rowCount!==0;
  if(planning.ready&&!used) {
    const learner=(await db.query<{id:string;missing:string[]}>(`SELECT l.id,mp.fields AS missing FROM drivy.learner_profile l
      JOIN drivy.membership m ON m.school_id=l.school_id AND m.person_id=l.person_id AND m.status='ACTIVE' AND 'LEARNER'=ANY(m.roles)
      JOIN drivy.person p ON p.id=m.person_id AND p.status='ACTIVE' ${missingProfileFieldsLateral('l')}
      WHERE l.school_id=$1 AND l.archived_at IS NULL
      ORDER BY (cardinality(mp.fields)=0) DESC,EXISTS(SELECT 1 FROM drivy.training t JOIN drivy.instructor_assignment a ON a.school_id=t.school_id AND a.training_id=t.id
        WHERE t.school_id=l.school_id AND t.learner_id=l.id AND t.status='ACTIVE' AND a.valid_from<=now() AND (a.valid_until IS NULL OR a.valid_until>now())) DESC,l.created_at,l.id LIMIT 1`,[school.id])).rows[0];
    if(!learner) {
      const pending=(await db.query("SELECT id FROM drivy.invitation WHERE school_id=$1 AND status='PENDING' AND expires_at>now() AND 'LEARNER'=ANY(roles) LIMIT 1",[school.id])).rowCount!==0;
      actions.push({code:pending?'LEARNER_INVITATION_PENDING':'FIRST_LEARNER_REQUIRED',label:pending?'Consulter l’invitation en attente':'Inviter votre premier élève',section:'invitations',query:{audience:'learners'}});
    } else if(learner.missing.length)actions.push({code:'PROFILE_ACTION_REQUIRED',label:'Compléter le dossier de l’élève',section:'eleves',query:{selection:learner.id}});
    else {
      const blockers=await planningReadiness(db,school.id,learner.id,undefined,['ADMIN']);
      const blocker=blockers[0];
      if(blocker?.code==='AVAILABILITY_REQUIRED'||blocker?.code==='COMMERCIAL_SETUP_REQUIRED') {
        const target=await learnerPreparationTarget(db,school.id,learner.id,blocker.code==='COMMERCIAL_SETUP_REQUIRED');
        if(blocker.code==='AVAILABILITY_REQUIRED')actions.push({code:blocker.code,label:'Définir les disponibilités du moniteur affecté',section:'disponibilites',...(target?{query:{instructor:target.instructor_membership_id}}:{})});
        else actions.push({code:blocker.code,label:'Ajouter un tarif pour la formation de l’élève',section:'apercu',query:{from:'formations',...(target?{selection:target.offering_id}:{})}});
      } else if(blocker)actions.push({code:blocker.code,label:blocker.code==='TRAINING_NOT_ACTIVE'?'Ouvrir la formation de l’élève':blocker.code==='INSTRUCTOR_NOT_ASSIGNED'?'Affecter un moniteur à la formation':'Préparer la formation de l’élève',section:'eleves',query:{selection:learner.id}});
      else actions.push({code:'PLAN_FIRST_LESSON',label:'Planifier dans l’app Drivy',section:'eleves',query:{selection:learner.id}});
    }
  }
  return {schoolId:school.id,actions,planningReady:planning.ready};
}

export function registerSchoolOnboarding(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;mapMatching?:{provider:'mapbox'|'osrm'}|undefined}) {
  const path='/v1/schools/:schoolId/setup-draft';
  const schoolId=(request:FastifyRequest)=>z.object({schoolId:z.uuid()}).parse(request.params).schoolId;
  const envelope=(data:unknown,request:FastifyRequest)=>({data,requestId:request.id,serverTime:new Date().toISOString()});
  const read=async<T>(request:FastifyRequest,work:(db:PoolClient,school:SchoolRow)=>Promise<T>)=>withActor(options.pool,await options.verifyToken(request.headers.authorization),schoolId(request),async(db,_actor,member)=>{
    if(!member?.roles.includes('ADMIN'))throw new ApiError(403,'SETUP_ACCESS_REQUIRED','La préparation est réservée à l’administration de l’école.');
    const school=(await db.query<SchoolRow>(`SELECT ${schoolColumns} FROM drivy.school WHERE id=$1`,[schoolId(request)])).rows[0];
    if(!school)throw notFound();return work(db,school);
  });
  app.get(path,async(request,reply)=>{empty.parse(request.query);const data=await read(request,draft);reply.header('ETag',`"${data.version}"`);return envelope(data,request);});
  app.get(`${path}/templates`,async request=>{empty.parse(request.query);return envelope(await read(request,async()=>
    // Le portail insère les coordonnées du brouillon au moment de choisir la proposition.
    schoolSetupTemplates({schoolName:'[Nom de l’école]',contactEmail:'[contact données]',mapMatchingProvider:options.mapMatching?.provider})),request);});
  app.get(`${path}/next-actions`,async request=>{empty.parse(request.query);return envelope(await read(request,nextActions),request);});
  app.get(`${path}/preview`,async request=>{const {activate}=previewQuery.parse(request.query);return envelope(await read(request,async(db,school)=>review(db,school,await draft(db,school),activate)),request);});
  app.put(path,{bodyLimit:1_000_000},async(request,reply)=>{
    empty.parse(request.query);const body=saveSetupDraftCommand.parse(request.body),id=schoolId(request),expected=requireVersion(request.headers['if-match']);
    checkIdempotency(request.headers['idempotency-key'],body.operationId);
    const data=await schoolCommand(options.pool,await options.verifyToken(request.headers.authorization),id,'SAVE_SCHOOL_SETUP_DRAFT',body,expected,async(db,actor,school)=>{
      const previous=await draft(db,school);checkVersion(previous.version,expected);
      await db.query(`UPDATE drivy.school_setup SET draft_version=draft_version+1,draft_step=$2,draft_content=$3,draft_updated_at=now(),draft_updated_by=$4,draft_applied_at=NULL WHERE school_id=$1`,[id,body.currentStep,JSON.stringify(body.content),actor.membershipId]);
      return {data:await draft(db,school),action:'SchoolSetupDraftSaved',resourceType:'SchoolSetupDraft',resourceId:id,changedFields:['draftContent','draftStep']};
    });reply.header('ETag',`"${data.version}"`);return envelope(data,request);
  });
  app.post(`${path}/complete`,async(request,reply)=>{
    empty.parse(request.query);const body=completeSetupDraftCommand.parse(request.body),id=schoolId(request),expected=requireVersion(request.headers['if-match']);
    checkIdempotency(request.headers['idempotency-key'],body.operationId);
    const data=await schoolCommand(options.pool,await options.verifyToken(request.headers.authorization),id,'APPLY_SCHOOL_SETUP_DRAFT',body,expected,async(db,actor,school)=>{
      const current=await draft(db,school);checkVersion(current.version,expected);checkVersion(school.version,body.expectedSchoolVersion);checkVersion(school.configurationVersion,body.expectedConfigurationVersion);
      const preview=await review(db,school,current,body.activate);
      if(preview.reviewDigest!==body.reviewDigest)throw new ApiError(409,'SETUP_REVIEW_CHANGED','Le contenu ou ses références ont changé. Relisez le résumé.');
      if(!preview.ready)throw new ApiError(409,preview.issues[0]?.code??'SETUP_INCOMPLETE',preview.issues[0]?.message??'Complétez les étapes indiquées.');
      const content=current.content,formations=activeFormations(content),reason=body.activate?'Première configuration de l’école':'Configuration explicitement relue dans le portail';
      if(formations.length)await cataloguePermission(db,id);
      if(selected(content,'IDENTITY'))await db.query('UPDATE drivy.school SET name=$2,time_zone=$3,contact_email=$4,contact_phone=$5 WHERE id=$1',[id,content.identity.name,content.identity.timeZone,content.identity.contactEmail,content.identity.contactPhone]);
      let policy=await dataPolicy(db,id);
      if(selected(content,'PRIVACY')) {
        const p=content.privacy;
        policy=(await db.query<DataPolicyRow>(`INSERT INTO drivy.school_data_policy(school_id,version,notice_text,retention_text,contact_email,approved_by,approved_at)
          VALUES($1,$2,$3,$4,$5,$6,now()) RETURNING *`,[id,(policy?.version??0)+1,p.noticeText,p.retentionText,p.contactEmail,actor.membershipId])).rows[0]!;
      }
      let profilePolicyId:string|null=null;
      if(selected(content,'PROFILE')) {
        profilePolicyId=(await db.query<{id:string}>(`INSERT INTO drivy.profile_field_policy(school_id,effective_from,fields,notice_version_id,created_by_membership_id)
          VALUES($1,statement_timestamp(),$2,$3,$4) RETURNING id`,[id,JSON.stringify(content.profile.fields),policy!.notice_version_id,actor.membershipId])).rows[0]!.id;
        await db.query("UPDATE drivy.profile_field_policy SET status='PUBLISHED',version=version+1,approved_at=now(),approved_by_membership_id=$2 WHERE id=$1",[profilePolicyId,actor.membershipId]);
      }
      const published=[];
      for(const formation of formations)published.push(await publishFormation(db,school,actor,formation,reason));
      const updated=(await db.query<SchoolRow>(`UPDATE drivy.school SET version=version+1,configuration_version=configuration_version+1 WHERE id=$1 RETURNING ${schoolColumns}`,[id])).rows[0]!;
      await recordSettings(db,updated,actor.membershipId,profilePolicyId??undefined);
      if(body.activate) {
        const ready=await readiness(db,updated);
        if(!ready.activationReady)throw new ApiError(409,'SETUP_INCOMPLETE','La configuration ne permet pas encore l’activation.');
        await db.query("UPDATE drivy.school SET status='ACTIVE' WHERE id=$1",[id]);updated.status='ACTIVE';
        await db.query("UPDATE drivy.school_setup SET completed_at=now(),current_step='REVIEW',version=version+1,configured_by=$2,last_saved_at=now() WHERE school_id=$1",[id,actor.membershipId]);
      }
      await db.query(`UPDATE drivy.school_setup SET draft_version=draft_version+1,draft_step='REVIEW',draft_applied_at=now(),draft_updated_at=now(),draft_updated_by=$2 WHERE school_id=$1`,[id,actor.membershipId]);
      const updatedDraft=await draft(db,updated);
      const result={id,schoolId:id,version:updatedDraft.version,draft:updatedDraft,school:schoolProjection(updated),applied:{policyVersionId:selected(content,'PRIVACY')?policy!.notice_version_id:null,profilePolicyId,
        offeringIds:published.map(item=>item.offeringId),productIds:published.map(item=>item.productId),termsIds:published.map(item=>item.termsId)}};
      return {data:result,action:'SchoolSetupDraftApplied',resourceType:'SchoolSetupDraft',resourceId:id,changedFields:content.selectedSections,reason};
    });reply.header('ETag',`"${data.version}"`);return envelope(data,request);
  });
}
