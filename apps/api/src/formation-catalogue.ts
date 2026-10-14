import {randomUUID} from 'node:crypto';
import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {checkIdempotency,schoolColumns,schoolCommand,type CommandActor,type SchoolRow} from './commands.js';
import {ApiError,notFound} from './errors.js';
import {recordSettings} from './school-setup.js';
import {cataloguePermission} from './lesson-setup.js';

/*
 * Formations et tarifs (14 octobre 2026). Un permis (category_code) organise la fiche ; un parcours est la chaîne
 * des versions d'un offering_key ; un tarif est la chaîne des versions d'un product_key. Les lignes restent insérées,
 * jamais réécrites : une inscription (training.offering_id), une leçon (policy_version_id, commercial_selection) ou un
 * bilan garde la version qu'il référence. Les commandes composées comparent les têtes exactes sous le verrou scolaire.
 */

const noControl=(value:string)=>!/[\u0000-\u001f\u007f]/.test(value);
const text=(max:number)=>z.string().trim().refine(value=>[...value].length>0&&[...value].length<=max&&noControl(value.replace(/[\n\r\t]/g,' ')));
const longText=(max:number)=>z.string().trim().refine(value=>[...value].length>0&&[...value].length<=max);
export const categoryCode=z.string().trim().min(1).max(30).refine(noControl);
const civil=z.iso.date();
const amount=z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);
const webURL=z.url().max(2048).refine(value=>{const url=new URL(value);return ['https:','http:'].includes(url.protocol)&&!url.username&&!url.password;});
export const competencyInput=z.object({key:z.string().trim().min(1).max(80).refine(noControl).nullable(),label:text(200),description:longText(4000)}).strict();
const competencies=z.array(competencyInput).min(1).max(200);
export const procedureInput=z.object({procedureText:longText(4000),cancellationPolicyText:longText(4000),sourceUrls:z.array(webURL).max(30)}).strict();
const programmeLabel=text(120);
export const productTypes=['INDIVIDUAL_LESSON','COLLECTIVE_COURSE','EXAM_SUPPORT','EXTERNAL_SERVICE'] as const;

export const updateProgrammeCommand=z.object({operationId:z.uuid(),offeringKey:z.string().min(1).max(80),expectedOfferingVersionId:z.uuid(),
 label:programmeLabel.nullable().optional(),enabled:z.boolean().optional(),defaultDurationMinutes:z.number().int().min(1).max(480).optional(),
 competencies:competencies.optional(),procedure:procedureInput.optional()}).strict()
 .refine(value=>['label','enabled','defaultDurationMinutes','competencies','procedure'].some(key=>key in value),{message:'Aucune rubrique à enregistrer.'});
const firstTariff=z.object({label:text(200),durationMinutes:z.number().int().min(1).max(480),priceCents:amount,validFrom:civil,validUntil:civil.nullable(),termsText:longText(20000)}).strict()
 .refine(value=>!value.validUntil||value.validUntil>=value.validFrom,{message:'Validité invalide.',path:['validUntil']});
export const createFormationCommand=z.object({operationId:z.uuid(),categoryCode,intent:z.enum(['NEW','ADDITIONAL_PROGRAMME']),programmeLabel:programmeLabel.nullable(),
 competencies,procedure:procedureInput,source:z.object({templateId:z.string().max(100).nullable(),templateVersion:z.string().max(40).nullable()}).strict().optional(),
 tariff:firstTariff}).strict().refine(value=>value.intent==='NEW'||value.programmeLabel!==null,{message:'Nom du parcours requis.',path:['programmeLabel']});
const tariffFields={type:z.enum(productTypes),label:text(200),durationMinutes:z.number().int().min(1).max(1440).nullable(),unitLabel:text(100),priceCents:amount,
 validUntil:civil.nullable(),enabled:z.boolean()};
const termsChoice=z.discriminatedUnion('mode',[z.object({mode:z.literal('KEEP')}).strict(),z.object({mode:z.literal('NEW'),termsText:longText(20000)}).strict()]);
export const saveTariffCommand=z.discriminatedUnion('mode',[
 z.object({operationId:z.uuid(),mode:z.literal('CREATE'),categoryCode:categoryCode.nullable(),...tariffFields,validFrom:civil,termsText:longText(20000)}).strict(),
 z.object({operationId:z.uuid(),mode:z.literal('UPDATE'),productKey:z.string().min(1).max(100),expectedProductVersionId:z.uuid(),...tariffFields,terms:termsChoice}).strict(),
]);
type ProgrammeCommand=z.infer<typeof updateProgrammeCommand>;
type FormationCommand=z.infer<typeof createFormationCommand>;
type TariffCommand=z.infer<typeof saveTariffCommand>;

/* ------------------------------------------------------------ Écritures communes (guide et fiche) */

export interface CompetencyRow {key:string;label:string;description:string;sortOrder:number}
/** Identifiants techniques : ceux des éléments repris sont conservés, les nouveaux sont générés et distincts. */
export function keyedCompetencies(items:readonly {key:string|null;label:string;description:string}[],allowed:ReadonlySet<string>|null):CompetencyRow[] {
 const taken=new Set(items.flatMap(item=>item.key?[item.key]:[]));
 if(taken.size!==items.filter(item=>item.key).length)throw new ApiError(422,'COMPETENCY_KEY_DUPLICATED','Une compétence figure deux fois.');
 if(allowed)for(const key of taken)if(!allowed.has(key))throw new ApiError(422,'COMPETENCY_KEY_UNKNOWN','Une compétence reprise n’appartient pas à ce parcours. Rechargez la fiche.');
 return items.map((item,index)=>{
  let key=item.key;
  while(!key||(!item.key&&taken.has(key)))key=`competence-${randomUUID().slice(0,8)}`;
  taken.add(key);return {key,label:item.label,description:item.description,sortOrder:index*10};
 });
}
export async function insertCurriculum(db:PoolClient,schoolId:string,membershipId:string,category:string,items:readonly CompetencyRow[],reason=''){
 const id=(await db.query<{id:string}>(`INSERT INTO drivy.curriculum_version(school_id,category_code,revision,approved,approval_reason,created_by,approved_at)
  SELECT $1,$2,coalesce(max(revision),0)+1,true,$3,$4,now() FROM drivy.curriculum_version WHERE school_id=$1 AND category_code=$2 RETURNING id`,[schoolId,category,reason,membershipId])).rows[0]!.id;
 for(const c of items)await db.query('INSERT INTO drivy.competency_definition(school_id,curriculum_version_id,stable_key,label,description,sort_order) VALUES($1,$2,$3,$4,$5,$6)',[schoolId,id,c.key,c.label,c.description,c.sortOrder]);
 return id;
}
export async function insertProcedure(db:PoolClient,schoolId:string,membershipId:string,category:string,value:{procedureText:string;cancellationPolicyText:string;sourceUrls:readonly string[]},reason=''){
 return (await db.query<{id:string}>(`INSERT INTO drivy.school_policy_version(school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at)
  SELECT $1,$2,coalesce(max(version),0)+1,$3,$4,$5,true,$6,$7,now() FROM drivy.school_policy_version WHERE school_id=$1 AND category_code=$2 RETURNING id`,
  [schoolId,category,value.procedureText,value.cancellationPolicyText,[...value.sourceUrls],reason,membershipId])).rows[0]!.id;
}
export interface OfferingValues {offeringKey:string;categoryCode:string;enabled:boolean;curriculumVersionId:string;policyVersionId:string;defaultDurationMinutes:number;defaultPriceCents:number|string;label:string|null}
export async function insertOffering(db:PoolClient,schoolId:string,value:OfferingValues){
 return (await db.query<{id:string;version:number}>(`INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version,enabled,curriculum_version_id,policy_version_id,default_duration_minutes,default_price_cents,label)
  SELECT $1,$2,$3,$4,coalesce(max(version),0)+1,$5,$6,$7,$8,$9,$10 FROM drivy.offering_version WHERE school_id=$2 AND offering_key=$3 RETURNING id,version`,
  [randomUUID(),schoolId,value.offeringKey,value.categoryCode,value.enabled,value.curriculumVersionId,value.policyVersionId,value.defaultDurationMinutes,value.defaultPriceCents,value.label])).rows[0]!;
}
export async function insertTerms(db:PoolClient,schoolId:string,membershipId:string,value:{label:string;termsText:string;validFrom:string},reason=''){
 return (await db.query<{id:string}>(`INSERT INTO drivy.commercial_terms_version(school_id,version,label,terms_text,valid_from,valid_until,approved,approval_reason,approved_by,approved_at,created_by)
  SELECT $1,coalesce(max(version),0)+1,$2,$3,$4,NULL,true,$5,$6,now(),$6 FROM drivy.commercial_terms_version WHERE school_id=$1 RETURNING id`,
  [schoolId,value.label.slice(0,200),value.termsText,value.validFrom,reason,membershipId])).rows[0]!.id;
}
export interface ProductValues {productKey:string;label:string;type:typeof productTypes[number];categoryCode:string|null;durationMinutes:number|null;unitLabel:string;unitPriceCents:number|string;validFrom:string;validUntil:string|null;termsVersionId:string;enabled:boolean}
export async function insertProduct(db:PoolClient,schoolId:string,value:ProductValues){
 return (await db.query<{id:string;version:number}>(`INSERT INTO drivy.service_product_version(school_id,version,product_key,label,type,category_code,site_id,duration_minutes,unit_label,unit_price_cents,valid_from,valid_until,terms_version_id,enabled)
  SELECT $1,coalesce(max(version),0)+1,$2,$3,$4,$5,NULL,$6,$7,$8,$9,$10,$11,$12 FROM drivy.service_product_version WHERE school_id=$1 AND product_key=$2 RETURNING id,version`,
  [schoolId,value.productKey,value.label,value.type,value.categoryCode,value.durationMinutes,value.unitLabel,value.unitPriceCents,value.validFrom,value.validUntil,value.termsVersionId,value.enabled])).rows[0]!;
}
/** Même effet que les routes de catalogue historiques : version et instantané de configuration de l'école. */
export async function configurationChanged(db:PoolClient,schoolId:string,membershipId:string){
 const school=(await db.query<SchoolRow>(`UPDATE drivy.school SET version=version+1,configuration_version=configuration_version+1 WHERE id=$1 RETURNING ${schoolColumns}`,[schoolId])).rows[0]!;
 await recordSettings(db,school,membershipId);
}
export const schoolToday=async(db:PoolClient,schoolId:string)=>(await db.query<{today:string}>(`SELECT to_char((now() AT TIME ZONE time_zone)::date,'YYYY-MM-DD') AS today FROM drivy.school WHERE id=$1`,[schoolId])).rows[0]!.today;

/**
 * Une nouvelle version d'un tarif retire immédiatement la précédente (drivy.service_product_current choisit la version
 * maximale). Programmer une version future d'un tarif déjà applicable créerait un intervalle sans tarif : refusé.
 */
export async function ensureNoTariffGap(db:PoolClient,schoolId:string,productKey:string,validFrom:string){
 const row=(await db.query<{applicable:boolean;today:string}>(`SELECT s.enabled AND s.valid_from<=d.today AND (s.valid_until IS NULL OR s.valid_until>=d.today) AND t.approved
   AND t.valid_from<=d.today AND (t.valid_until IS NULL OR t.valid_until>=d.today) AS applicable,to_char(d.today,'YYYY-MM-DD') AS today
  FROM drivy.service_product_version s JOIN drivy.commercial_terms_version t ON t.school_id=s.school_id AND t.id=s.terms_version_id
  CROSS JOIN (SELECT (now() AT TIME ZONE time_zone)::date AS today FROM drivy.school WHERE id=$1) d
  WHERE s.school_id=$1 AND s.product_key=$2 ORDER BY s.version DESC LIMIT 1`,[schoolId,productKey])).rows[0];
 if(row?.applicable&&validFrom>row.today)throw new ApiError(422,'TARIFF_SCHEDULING_UNSUPPORTED','Une modification de tarif s’applique dès aujourd’hui : une date future laisserait ce tarif sans prix applicable.');
}

/* ------------------------------------------------------------ Lectures */

interface HeadRow {id:string;offeringKey:string;categoryCode:string;version:number;enabled:boolean;label:string|null;curriculumVersionId:string|null;policyVersionId:string|null;
 defaultDurationMinutes:number|null;defaultPriceCents:string|null;createdAt:Date;curriculumApproved:boolean|null;policyApproved:boolean|null}
interface ProductRow {id:string;productKey:string;version:number;label:string;type:typeof productTypes[number];categoryCode:string|null;durationMinutes:number|null;unitLabel:string;
 unitPriceCents:string;validFrom:string;validUntil:string|null;termsVersionId:string;enabled:boolean;createdAt:Date}
interface TermsRow {id:string;version:number;label:string;termsText:string;validFrom:string;validUntil:string|null;approved:boolean;createdAt:Date}
type TariffStatus='OFFERED'|'DISABLED'|'NOT_YET'|'ENDED'|'TERMS_NOT_APPROVED'|'TERMS_EXPIRED'|'TERMS_NOT_YET';
const productColumns=`s.id,s.product_key AS "productKey",s.version,s.label,s.type,s.category_code AS "categoryCode",s.duration_minutes AS "durationMinutes",s.unit_label AS "unitLabel",
 s.unit_price_cents AS "unitPriceCents",to_char(s.valid_from,'YYYY-MM-DD') AS "validFrom",to_char(s.valid_until,'YYYY-MM-DD') AS "validUntil",s.terms_version_id AS "termsVersionId",s.enabled,s.created_at AS "createdAt"`;
const termsColumns=`t.id,t.version,t.label,t.terms_text AS "termsText",to_char(t.valid_from,'YYYY-MM-DD') AS "validFrom",to_char(t.valid_until,'YYYY-MM-DD') AS "validUntil",t.approved,t.created_at AS "createdAt"`;

const offeringSelect=`SELECT o.id,o.offering_key AS "offeringKey",o.category_code AS "categoryCode",o.version,o.enabled,o.label,o.curriculum_version_id AS "curriculumVersionId",
 o.policy_version_id AS "policyVersionId",o.default_duration_minutes AS "defaultDurationMinutes",o.default_price_cents AS "defaultPriceCents",o.created_at AS "createdAt",
 c.approved AS "curriculumApproved",p.approved AS "policyApproved"
 FROM drivy.offering_version o LEFT JOIN drivy.curriculum_version c ON c.school_id=o.school_id AND c.id=o.curriculum_version_id
 LEFT JOIN drivy.school_policy_version p ON p.school_id=o.school_id AND p.id=o.policy_version_id`;
async function heads(db:PoolClient,schoolId:string,category?:string){
 return (await db.query<HeadRow>(`${offeringSelect} WHERE o.school_id=$1 AND ($2::text IS NULL OR o.category_code=$2) AND o.version=(SELECT max(v.version) FROM drivy.offering_version v WHERE v.school_id=o.school_id AND v.offering_key=o.offering_key)
  ORDER BY o.category_code,o.created_at,o.offering_key`,[schoolId,category??null])).rows;
}
/** Têtes réelles des tarifs (service_product_current lit aussi les versions qu'un ADMIN sans CONFIGURE_CATALOG ne voit pas). */
async function productHeads(db:PoolClient,schoolId:string,scope:{category?:string;uncategorized?:boolean}={}){
 return (await db.query<ProductRow>(`SELECT ${productColumns} FROM drivy.service_product_version s WHERE s.school_id=$1 AND drivy.service_product_current(s.id)
  AND ($2::text IS NULL OR s.category_code=$2) AND (NOT $3::boolean OR s.category_code IS NULL) ORDER BY s.category_code NULLS FIRST,s.created_at,s.product_key`,
  [schoolId,scope.category??null,scope.uncategorized??false])).rows;
}
async function termsById(db:PoolClient,schoolId:string,ids:readonly string[]){
 const rows=(await db.query<TermsRow>(`SELECT ${termsColumns} FROM drivy.commercial_terms_version t WHERE t.school_id=$1 AND t.id=ANY($2::uuid[])`,[schoolId,[...new Set(ids)]])).rows;
 return new Map(rows.map(row=>[row.id,row]));
}
function tariffStatus(product:ProductRow,terms:TermsRow|undefined,today:string):TariffStatus {
 if(!product.enabled)return 'DISABLED';
 if(product.validUntil!==null&&product.validUntil<today)return 'ENDED';
 if(!terms||!terms.approved)return 'TERMS_NOT_APPROVED';
 if(terms.validUntil!==null&&terms.validUntil<today)return 'TERMS_EXPIRED';
 if(product.validFrom>today)return 'NOT_YET';
 if(terms.validFrom>today)return 'TERMS_NOT_YET';
 return 'OFFERED';
}
const programmeReady=(head:HeadRow)=>head.enabled&&head.curriculumApproved===true&&head.policyApproved===true;
const programmeComplete=(head:HeadRow)=>head.curriculumApproved===true&&head.policyApproved===true&&head.defaultDurationMinutes!==null&&head.defaultPriceCents!==null;
/** Seuls les états utiles : à compléter (programme ou tarif de leçon manquant) ou non proposée (tous les parcours retirés). */
function categoryState(programmes:readonly HeadRow[],tariffs:readonly {product:ProductRow;status:TariffStatus}[]){
 const issues:string[]=[];
 if(!programmes.length)issues.push('PROGRAMME_REQUIRED');
 else if(programmes.some(head=>!programmeComplete(head)))issues.push('PROGRAMME_INCOMPLETE');
 const lesson=tariffs.some(item=>item.product.type==='INDIVIDUAL_LESSON'&&['OFFERED','NOT_YET','TERMS_NOT_YET'].includes(item.status));
 if(!lesson)issues.push('LESSON_TARIFF_REQUIRED');
 const offered=programmes.some(programmeReady);
 const state=programmes.length&&!offered&&programmes.every(programmeComplete)?'NOT_OFFERED' as const:issues.length?'INCOMPLETE' as const:'READY' as const;
 return {state,issues};
}
async function commercialAccess(db:PoolClient,schoolId:string){return (await db.query<{ok:boolean}>('SELECT drivy.lesson_catalogue_manage($1) AS ok',[schoolId])).rows[0]?.ok===true;}

async function formationList(db:PoolClient,schoolId:string){
 const today=await schoolToday(db,schoolId),[programmes,products]=[await heads(db,schoolId),await productHeads(db,schoolId)];
 const terms=await termsById(db,schoolId,products.map(item=>item.termsVersionId));
 const extra=(await db.query<{category_code:string}>(`SELECT category_code FROM drivy.curriculum_version WHERE school_id=$1 UNION SELECT category_code FROM drivy.school_policy_version WHERE school_id=$1`,[schoolId])).rows;
 const learners=(await db.query<{category_code:string;count:string}>(`SELECT o.category_code,count(*) FROM drivy.training t JOIN drivy.offering_version o ON o.school_id=t.school_id AND o.id=t.offering_id
  WHERE t.school_id=$1 AND t.status IN('ACTIVE','PAUSED') GROUP BY o.category_code`,[schoolId])).rows;
 const categories=[...new Set([...programmes.map(item=>item.categoryCode),...products.flatMap(item=>item.categoryCode?[item.categoryCode]:[]),...extra.map(item=>item.category_code)])].sort((a,b)=>a.localeCompare(b,'fr'));
 const tariffs=products.map(product=>({product,status:tariffStatus(product,terms.get(product.termsVersionId),today)}));
 return {today,canConfigureCatalog:await commercialAccess(db,schoolId),categories:categories.map(code=>{
  const own=programmes.filter(item=>item.categoryCode===code),prices=tariffs.filter(item=>item.product.categoryCode===code);
  return {categoryCode:code,...categoryState(own,prices),programmeCount:own.length,tariffCount:prices.length,activeTrainings:Number(learners.find(item=>item.category_code===code)?.count??0)};
 }),uncategorizedTariffCount:tariffs.filter(item=>item.product.categoryCode===null).length};
}

const curriculumContent=async(db:PoolClient,schoolId:string,id:string)=>{
 const row=(await db.query<{id:string;revision:number;approved:boolean;categoryCode:string;createdAt:Date}>(`SELECT id,revision,approved,category_code AS "categoryCode",created_at AS "createdAt" FROM drivy.curriculum_version WHERE school_id=$1 AND id=$2`,[schoolId,id])).rows[0];
 if(!row)return null;
 const items=(await db.query<{id:string;key:string;label:string;description:string;sortOrder:number}>(`SELECT id,stable_key AS key,label,description,sort_order AS "sortOrder" FROM drivy.competency_definition WHERE curriculum_version_id=$1 ORDER BY sort_order,id`,[id])).rows;
 // Libellés enregistrés tels quels : la fiche les modifie, l'alias d'affichage terrain ne s'applique pas ici.
 return {...row,competencies:items};
};
const procedureContent=async(db:PoolClient,schoolId:string,id:string)=>(await db.query<{id:string;version:number;approved:boolean;categoryCode:string;createdAt:Date;procedureText:string;cancellationPolicyText:string;sourceUrls:string[]}>(
 `SELECT id,version,approved,category_code AS "categoryCode",created_at AS "createdAt",procedure_text AS "procedureText",cancellation_policy_text AS "cancellationPolicyText",source_urls AS "sourceUrls"
  FROM drivy.school_policy_version WHERE school_id=$1 AND id=$2`,[schoolId,id])).rows[0]??null;
const publicHead=(head:HeadRow)=>({id:head.id,version:head.version,enabled:head.enabled,label:head.label,defaultDurationMinutes:head.defaultDurationMinutes,
 hasReferencePrice:head.defaultPriceCents!==null,createdAt:head.createdAt.toISOString(),ready:programmeReady(head),complete:programmeComplete(head)});
const publicProduct=(row:ProductRow)=>({...row,unitPriceCents:Number(row.unitPriceCents),createdAt:row.createdAt.toISOString()});
const publicTerms=(row:TermsRow)=>({...row,createdAt:row.createdAt.toISOString()});

async function formationSheet(db:PoolClient,schoolId:string,category:string){
 const today=await schoolToday(db,schoolId),own=await heads(db,schoolId,category),products=await productHeads(db,schoolId,{category});
 const known=(await db.query(`SELECT 1 FROM drivy.curriculum_version WHERE school_id=$1 AND category_code=$2 UNION ALL SELECT 1 FROM drivy.school_policy_version WHERE school_id=$1 AND category_code=$2 LIMIT 1`,[schoolId,category])).rowCount;
 if(!own.length&&!products.length&&!known)throw notFound();
 const allHeads=await heads(db,schoolId);
 const programmes=[];
 for(const head of own){
  const versions=(await db.query<{id:string;version:number;enabled:boolean;label:string|null;curriculumVersionId:string|null;policyVersionId:string|null;defaultDurationMinutes:number|null;createdAt:Date;
   curriculumRevision:number|null;policyVersion:number|null;trainings:string}>(`SELECT o.id,o.version,o.enabled,o.label,o.curriculum_version_id AS "curriculumVersionId",o.policy_version_id AS "policyVersionId",
   o.default_duration_minutes AS "defaultDurationMinutes",o.created_at AS "createdAt",c.revision AS "curriculumRevision",p.version AS "policyVersion",
   (SELECT count(*) FROM drivy.training t WHERE t.school_id=o.school_id AND t.offering_id=o.id AND t.status IN('ACTIVE','PAUSED')) AS trainings
   FROM drivy.offering_version o LEFT JOIN drivy.curriculum_version c ON c.school_id=o.school_id AND c.id=o.curriculum_version_id
   LEFT JOIN drivy.school_policy_version p ON p.school_id=o.school_id AND p.id=o.policy_version_id
   WHERE o.school_id=$1 AND o.offering_key=$2 ORDER BY o.version DESC LIMIT 101`,[schoolId,head.offeringKey])).rows;
  const counts=versions.map(item=>Number(item.trainings));
  programmes.push({offeringKey:head.offeringKey,head:publicHead(head),
   curriculum:head.curriculumVersionId?await curriculumContent(db,schoolId,head.curriculumVersionId):null,
   procedure:head.policyVersionId?await procedureContent(db,schoolId,head.policyVersionId):null,
   enrollments:{current:counts[0]??0,previous:counts.slice(1).reduce((sum,value)=>sum+value,0)},
   sharedCurriculumWith:head.curriculumVersionId?allHeads.filter(other=>other.offeringKey!==head.offeringKey&&other.curriculumVersionId===head.curriculumVersionId).map(other=>other.offeringKey):[],
   sharedProcedureWith:head.policyVersionId?allHeads.filter(other=>other.offeringKey!==head.offeringKey&&other.policyVersionId===head.policyVersionId).map(other=>other.offeringKey):[],
   history:versions.slice(0,100).map(item=>({...item,trainings:Number(item.trainings),createdAt:item.createdAt.toISOString()})),historyTruncated:versions.length>100});
 }
 const terms=await termsById(db,schoolId,products.map(item=>item.termsVersionId));
 const usage=(await db.query<{terms_version_id:string;count:string}>(`SELECT s.terms_version_id,count(*) FROM drivy.service_product_version s WHERE s.school_id=$1 AND drivy.service_product_current(s.id)
  AND s.terms_version_id=ANY($2::uuid[]) GROUP BY s.terms_version_id`,[schoolId,[...terms.keys()]])).rows;
 const tariffs=[];
 for(const product of products){
  const history=(await db.query<ProductRow>(`SELECT ${productColumns} FROM drivy.service_product_version s WHERE s.school_id=$1 AND s.product_key=$2 ORDER BY s.version DESC LIMIT 101`,[schoolId,product.productKey])).rows;
  const own=terms.get(product.termsVersionId);
  tariffs.push({productKey:product.productKey,head:publicProduct(product),terms:own?publicTerms(own):null,status:tariffStatus(product,own,today),
   termsSharedWith:Math.max(0,Number(usage.find(item=>item.terms_version_id===product.termsVersionId)?.count??1)-1),
   history:history.slice(0,100).map(publicProduct),historyTruncated:history.length>100});
 }
 const unattached=async(table:'curriculum_version'|'school_policy_version',column:'curriculum_version_id'|'policy_version_id')=>(await db.query<{id:string;number:number;createdAt:Date}>(
  `SELECT x.id,${table==='curriculum_version'?'x.revision':'x.version'} AS number,x.created_at AS "createdAt" FROM drivy.${table} x WHERE x.school_id=$1 AND x.category_code=$2
   AND NOT EXISTS(SELECT 1 FROM drivy.offering_version o WHERE o.school_id=x.school_id AND o.${column}=x.id) ORDER BY x.created_at DESC LIMIT 50`,[schoolId,category])).rows
  .map(row=>({id:row.id,number:row.number,createdAt:row.createdAt.toISOString()}));
 return {categoryCode:category,today,canConfigureCatalog:await commercialAccess(db,schoolId),
  ...categoryState(own,tariffs.map(item=>({product:products.find(product=>product.productKey===item.productKey)!,status:item.status}))),
  programmes,tariffs,unattached:{curricula:await unattached('curriculum_version','curriculum_version_id'),procedures:await unattached('school_policy_version','policy_version_id')}};
}

async function uncategorizedTariffs(db:PoolClient,schoolId:string){
 const today=await schoolToday(db,schoolId),products=await productHeads(db,schoolId,{uncategorized:true}),terms=await termsById(db,schoolId,products.map(item=>item.termsVersionId));
 const tariffs=[];
 for(const product of products){
  const history=(await db.query<ProductRow>(`SELECT ${productColumns} FROM drivy.service_product_version s WHERE s.school_id=$1 AND s.product_key=$2 ORDER BY s.version DESC LIMIT 101`,[schoolId,product.productKey])).rows;
  const own=terms.get(product.termsVersionId);
  tariffs.push({productKey:product.productKey,head:publicProduct(product),terms:own?publicTerms(own):null,status:tariffStatus(product,own,today),termsSharedWith:0,
   history:history.slice(0,100).map(publicProduct),historyTruncated:history.length>100});
 }
 const usage=(await db.query<{terms_version_id:string;count:string}>(`SELECT s.terms_version_id,count(*) FROM drivy.service_product_version s WHERE s.school_id=$1 AND drivy.service_product_current(s.id)
  AND s.terms_version_id=ANY($2::uuid[]) GROUP BY s.terms_version_id`,[schoolId,[...terms.keys()]])).rows;
 for(const tariff of tariffs)tariff.termsSharedWith=Math.max(0,Number(usage.find(item=>item.terms_version_id===tariff.head.termsVersionId)?.count??1)-1);
 return {today,canConfigureCatalog:await commercialAccess(db,schoolId),tariffs};
}

/** Une ancienne URL retrouve la version exacte qu'elle désigne, avec ses usages réels ; aucune fiche n'est choisie à sa place. */
async function reference(db:PoolClient,schoolId:string,id:string){
 const today=await schoolToday(db,schoolId);
 const offering=(await db.query<HeadRow>(`${offeringSelect} WHERE o.school_id=$1 AND o.id=$2`,[schoolId,id])).rows[0];
 const programmesUsing=async(column:'curriculum_version_id'|'policy_version_id')=>(await db.query<{offeringKey:string;categoryCode:string;label:string|null;headId:string;current:boolean}>(
  `SELECT DISTINCT ON (o.offering_key) o.offering_key AS "offeringKey",o.category_code AS "categoryCode",h.label,h.id AS "headId",h.${column}=$2 AS current
   FROM drivy.offering_version o JOIN drivy.offering_version h ON h.school_id=o.school_id AND h.offering_key=o.offering_key
    AND h.version=(SELECT max(v.version) FROM drivy.offering_version v WHERE v.school_id=o.school_id AND v.offering_key=o.offering_key)
   WHERE o.school_id=$1 AND o.${column}=$2 ORDER BY o.offering_key`,[schoolId,id])).rows;
 if(offering){
  const head=(await db.query<{id:string;label:string|null}>(`SELECT id,label FROM drivy.offering_version WHERE school_id=$1 AND offering_key=$2 ORDER BY version DESC LIMIT 1`,[schoolId,offering.offeringKey])).rows[0]!;
  return {kind:'OFFERING' as const,id,categoryCode:offering.categoryCode,current:head.id===id,offeringKey:offering.offeringKey,headId:head.id,
   programmes:[{offeringKey:offering.offeringKey,categoryCode:offering.categoryCode,label:head.label,headId:head.id,current:head.id===id}],
   offering:{...publicHead(offering),curriculumVersionId:offering.curriculumVersionId,policyVersionId:offering.policyVersionId},
   curriculum:offering.curriculumVersionId?await curriculumContent(db,schoolId,offering.curriculumVersionId):null,
   procedure:offering.policyVersionId?await procedureContent(db,schoolId,offering.policyVersionId):null};
 }
 const curriculum=await curriculumContent(db,schoolId,id);
 if(curriculum){const programmes=await programmesUsing('curriculum_version_id');return {kind:'CURRICULUM' as const,id,categoryCode:curriculum.categoryCode,current:programmes.some(item=>item.current),programmes,curriculum};}
 const procedure=await procedureContent(db,schoolId,id);
 if(procedure){const programmes=await programmesUsing('policy_version_id');return {kind:'PROCEDURE' as const,id,categoryCode:procedure.categoryCode,current:programmes.some(item=>item.current),programmes,procedure};}
 const product=(await db.query<ProductRow>(`SELECT ${productColumns} FROM drivy.service_product_version s WHERE s.school_id=$1 AND s.id=$2`,[schoolId,id])).rows[0];
 if(product){
  const head=(await db.query<{id:string}>(`SELECT s.id FROM drivy.service_product_version s WHERE s.school_id=$1 AND s.product_key=$2 AND drivy.service_product_current(s.id)`,[schoolId,product.productKey])).rows[0];
  const terms=(await termsById(db,schoolId,[product.termsVersionId])).get(product.termsVersionId);
  return {kind:'TARIFF' as const,id,categoryCode:product.categoryCode,current:head?.id===id,productKey:product.productKey,headId:head?.id??null,
   tariff:publicProduct(product),terms:terms?publicTerms(terms):null,status:tariffStatus(product,terms,today),programmes:[]};
 }
 const terms=(await termsById(db,schoolId,[id])).get(id);
 if(terms){
  const users=(await db.query<ProductRow&{current:boolean}>(`SELECT ${productColumns},drivy.service_product_current(s.id) AS current FROM drivy.service_product_version s
   WHERE s.school_id=$1 AND s.terms_version_id=$2 ORDER BY s.category_code NULLS FIRST,s.product_key,s.version DESC LIMIT 200`,[schoolId,id])).rows;
  return {kind:'TERMS' as const,id,categoryCode:null,current:users.some(item=>item.current),terms:publicTerms(terms),programmes:[],
   usedBy:users.map(item=>({...publicProduct(item),current:item.current}))};
 }
 throw notFound();
}

async function termsList(db:PoolClient,schoolId:string){
 const rows=(await db.query<TermsRow&{tariffs:string;currentTariffs:string}>(`SELECT ${termsColumns},
  (SELECT count(DISTINCT s.product_key) FROM drivy.service_product_version s WHERE s.school_id=t.school_id AND s.terms_version_id=t.id) AS tariffs,
  (SELECT count(*) FROM drivy.service_product_version s WHERE s.school_id=t.school_id AND s.terms_version_id=t.id AND drivy.service_product_current(s.id)) AS "currentTariffs"
  FROM drivy.commercial_terms_version t WHERE t.school_id=$1 ORDER BY t.version DESC LIMIT 501`,[schoolId])).rows;
 return {items:rows.slice(0,500).map(row=>({...publicTerms(row),tariffs:Number(row.tariffs),currentTariffs:Number(row.currentTariffs)})),truncated:rows.length>500};
}

/* ------------------------------------------------------------ Commandes composées */

async function lockedHead(db:PoolClient,schoolId:string,offeringKey:string){
 const head=(await db.query<HeadRow>(`${offeringSelect} WHERE o.school_id=$1 AND o.offering_key=$2 ORDER BY o.version DESC LIMIT 1`,[schoolId,offeringKey])).rows[0];
 if(!head)throw notFound();return head;
}
const sameCompetencies=(left:readonly CompetencyRow[],right:readonly {key:string;label:string;description:string}[])=>left.length===right.length&&left.every((item,index)=>
 item.key===right[index]!.key&&item.label===right[index]!.label&&item.description===right[index]!.description);

async function updateProgramme(db:PoolClient,actor:CommandActor,school:SchoolRow,body:ProgrammeCommand){
 const head=await lockedHead(db,school.id,body.offeringKey);
 if(head.id!==body.expectedOfferingVersionId){
  if(!(await db.query('SELECT 1 FROM drivy.offering_version WHERE school_id=$1 AND id=$2 AND offering_key=$3',[school.id,body.expectedOfferingVersionId,body.offeringKey])).rowCount)throw notFound();
  throw new ApiError(409,'FORMATION_CHANGED','Ce parcours a été modifié entre-temps. Vos saisies sont conservées : rechargez la fiche avant d’enregistrer.');
 }
 const changed:string[]=[];
 let curriculumVersionId=head.curriculumVersionId,policyVersionId=head.policyVersionId;
 if(body.competencies){
  const current=head.curriculumVersionId?await curriculumContent(db,school.id,head.curriculumVersionId):null;
  const rows=keyedCompetencies(body.competencies,new Set(current?.competencies.map(item=>item.key)??[]));
  if(!current||!current.approved||!sameCompetencies(rows,current.competencies)){curriculumVersionId=await insertCurriculum(db,school.id,actor.membershipId,head.categoryCode,rows);changed.push('competencies');}
 }
 if(body.procedure){
  const current=head.policyVersionId?await procedureContent(db,school.id,head.policyVersionId):null;
  const same=current&&current.approved&&current.procedureText===body.procedure.procedureText&&current.cancellationPolicyText===body.procedure.cancellationPolicyText
   &&current.sourceUrls.length===body.procedure.sourceUrls.length&&current.sourceUrls.every((value,index)=>value===body.procedure!.sourceUrls[index]);
  if(!same){policyVersionId=await insertProcedure(db,school.id,actor.membershipId,head.categoryCode,body.procedure);changed.push('procedure');}
 }
 const label=body.label===undefined?head.label:body.label;if(label!==head.label)changed.push('label');
 const enabled=body.enabled??head.enabled;if(enabled!==head.enabled)changed.push('enabled');
 const duration=body.defaultDurationMinutes??head.defaultDurationMinutes;if(duration!==head.defaultDurationMinutes)changed.push('defaultDurationMinutes');
 if(!changed.length)throw new ApiError(409,'FORMATION_UNCHANGED','Aucune modification à enregistrer.');
 if(!curriculumVersionId||!policyVersionId)throw new ApiError(409,'PROGRAMME_INCOMPLETE','Enregistrez aussi les compétences et les règles de ce parcours pour le compléter.');
 if(duration===null)throw new ApiError(409,'PROGRAMME_INCOMPLETE','Indiquez la durée habituelle d’une leçon de ce parcours.');
 // Ancien parcours sans prix de référence : aucun prix n'est fabriqué pour le compléter.
 if(head.defaultPriceCents===null)throw new ApiError(409,'PROGRAMME_REFERENCE_PRICE_MISSING','Ce parcours ancien n’a pas de prix de référence. Préparez-le de nouveau avec « Ajouter une formation ».');
 if(enabled){
  const refs=(await db.query<{ok:boolean}>('SELECT c.approved AND p.approved AS ok FROM drivy.curriculum_version c JOIN drivy.school_policy_version p ON p.school_id=c.school_id WHERE c.school_id=$1 AND c.id=$2 AND p.id=$3',[school.id,curriculumVersionId,policyVersionId])).rows[0];
  if(!refs?.ok)throw new ApiError(409,'OFFERING_NOT_READY','Enregistrez les compétences et les règles pour proposer ce parcours.');
 }
 if(label!==null&&label!==head.label&&(await db.query(`SELECT 1 FROM drivy.offering_version o WHERE o.school_id=$1 AND o.category_code=$2 AND o.offering_key<>$3 AND lower(o.label)=lower($4)
  AND o.version=(SELECT max(v.version) FROM drivy.offering_version v WHERE v.school_id=o.school_id AND v.offering_key=o.offering_key)`,[school.id,head.categoryCode,head.offeringKey,label])).rowCount)
  throw new ApiError(409,'PROGRAMME_LABEL_TAKEN','Un autre parcours de ce permis porte déjà ce nom.');
 const created=await insertOffering(db,school.id,{offeringKey:head.offeringKey,categoryCode:head.categoryCode,enabled,curriculumVersionId,policyVersionId,defaultDurationMinutes:duration,defaultPriceCents:head.defaultPriceCents,label});
 await configurationChanged(db,school.id,actor.membershipId);
 return {data:{id:created.id,schoolId:school.id,version:created.version,offeringKey:head.offeringKey,categoryCode:head.categoryCode,previousOfferingVersionId:head.id,curriculumVersionId,policyVersionId,changed},
  action:'FormationProgrammeUpdated',resourceType:'Offering',resourceId:created.id,changedFields:changed};
}

async function createFormation(db:PoolClient,actor:CommandActor,school:SchoolRow,body:FormationCommand){
 await cataloguePermission(db,school.id);
 const existing=(await db.query<{offering_key:string;label:string|null}>(`SELECT o.offering_key,o.label FROM drivy.offering_version o WHERE o.school_id=$1 AND o.category_code=$2
  AND o.version=(SELECT max(v.version) FROM drivy.offering_version v WHERE v.school_id=o.school_id AND v.offering_key=o.offering_key)`,[school.id,body.categoryCode])).rows;
 if(body.intent==='NEW'&&existing.length)throw new ApiError(409,'FORMATION_ALREADY_EXISTS','Ce permis est déjà préparé. Ouvrez sa fiche, ou ajoutez explicitement un autre parcours.');
 if(body.intent==='ADDITIONAL_PROGRAMME'&&!existing.length)throw new ApiError(409,'FORMATION_NOT_FOUND','Ce permis n’a pas encore de parcours : préparez-le d’abord.');
 if(body.programmeLabel&&existing.some(item=>item.label?.toLowerCase()===body.programmeLabel!.toLowerCase()))throw new ApiError(409,'PROGRAMME_LABEL_TAKEN','Un autre parcours de ce permis porte déjà ce nom.');
 const reason=body.source?.templateId?`Proposition Drivy ${body.source.templateId} ${body.source.templateVersion??''} relue et adaptée`.trim():'';
 const curriculumVersionId=await insertCurriculum(db,school.id,actor.membershipId,body.categoryCode,keyedCompetencies(body.competencies,null),reason);
 const policyVersionId=await insertProcedure(db,school.id,actor.membershipId,body.categoryCode,body.procedure,reason);
 const offeringKey=`formation-${randomUUID()}`,productKey=`tarif-${randomUUID()}`;
 const offering=await insertOffering(db,school.id,{offeringKey,categoryCode:body.categoryCode,enabled:true,curriculumVersionId,policyVersionId,
  defaultDurationMinutes:body.tariff.durationMinutes,defaultPriceCents:body.tariff.priceCents,label:body.programmeLabel});
 const termsVersionId=await insertTerms(db,school.id,actor.membershipId,{label:`Conditions · ${body.tariff.label}`,termsText:body.tariff.termsText,validFrom:body.tariff.validFrom});
 const product=await insertProduct(db,school.id,{productKey,label:body.tariff.label,type:'INDIVIDUAL_LESSON',categoryCode:body.categoryCode,durationMinutes:body.tariff.durationMinutes,
  unitLabel:'leçon',unitPriceCents:body.tariff.priceCents,validFrom:body.tariff.validFrom,validUntil:body.tariff.validUntil,termsVersionId,enabled:true});
 await configurationChanged(db,school.id,actor.membershipId);
 return {data:{id:offering.id,schoolId:school.id,version:offering.version,categoryCode:body.categoryCode,offeringKey,curriculumVersionId,policyVersionId,productId:product.id,termsVersionId},
  action:'FormationCreated',resourceType:'Offering',resourceId:offering.id,changedFields:['competencies','procedure','offering','tariff','terms'],...(reason?{reason}:{})};
}

interface TariffResult {id:string;schoolId:string;version:number;productKey:string;categoryCode:string|null;termsVersionId:string;changed:string[];previousProductVersionId?:string}
async function saveTariff(db:PoolClient,actor:CommandActor,school:SchoolRow,body:TariffCommand):Promise<{data:TariffResult;action:string;resourceType:string;resourceId:string;changedFields:string[]}>{
 await cataloguePermission(db,school.id);
 const today=await schoolToday(db,school.id);
 if(body.validUntil!==null&&body.validUntil<today&&body.enabled)throw new ApiError(422,'INVALID_INTERVAL','La fin de validité est déjà passée.');
 if(body.type==='INDIVIDUAL_LESSON'&&(body.durationMinutes===null||body.durationMinutes>480))throw new ApiError(422,'INVALID_SERVICE_PRODUCT','Une leçon exige une durée de 1 à 480 minutes.');
 if(body.mode==='CREATE'){
  if(body.type==='INDIVIDUAL_LESSON'&&body.categoryCode===null)throw new ApiError(422,'INVALID_SERVICE_PRODUCT','Une leçon se rattache à un permis.');
  if(body.categoryCode!==null&&!(await db.query('SELECT 1 FROM drivy.offering_version WHERE school_id=$1 AND category_code=$2 LIMIT 1',[school.id,body.categoryCode])).rowCount)throw notFound();
  if(body.validUntil!==null&&body.validUntil<body.validFrom)throw new ApiError(422,'INVALID_INTERVAL','La fin de validité précède le début.');
  const productKey=`tarif-${randomUUID()}`;
  const termsVersionId=await insertTerms(db,school.id,actor.membershipId,{label:`Conditions · ${body.label}`,termsText:body.termsText,validFrom:body.validFrom});
  const product=await insertProduct(db,school.id,{productKey,label:body.label,type:body.type,categoryCode:body.categoryCode,durationMinutes:body.durationMinutes,
   unitLabel:body.unitLabel,unitPriceCents:body.priceCents,validFrom:body.validFrom,validUntil:body.validUntil,termsVersionId,enabled:body.enabled});
  return {data:{id:product.id,schoolId:school.id,version:product.version,productKey,
   categoryCode:body.categoryCode,termsVersionId,changed:['created']},action:'TariffCreated',resourceType:'ServiceProductVersion',resourceId:product.id,changedFields:['label','type','durationMinutes','unitPriceCents','validFrom','validUntil','termsVersionId','enabled']};
 }
 const head=(await db.query<ProductRow>(`SELECT ${productColumns} FROM drivy.service_product_version s WHERE s.school_id=$1 AND s.product_key=$2 AND drivy.service_product_current(s.id)`,[school.id,body.productKey])).rows[0];
 if(!head)throw notFound();
 if(head.id!==body.expectedProductVersionId){
  if(!(await db.query('SELECT 1 FROM drivy.service_product_version WHERE school_id=$1 AND id=$2 AND product_key=$3',[school.id,body.expectedProductVersionId,body.productKey])).rowCount)throw notFound();
  throw new ApiError(409,'TARIFF_CHANGED','Ce tarif a été modifié entre-temps. Vos saisies sont conservées : rechargez la fiche avant d’enregistrer.');
 }
 if(body.type==='INDIVIDUAL_LESSON'&&head.categoryCode===null)throw new ApiError(422,'INVALID_SERVICE_PRODUCT','Une leçon se rattache à un permis.');
 // Application immédiate : la nouvelle version vaut dès aujourd'hui, ou dès la date déjà prévue si le tarif n'a pas encore commencé.
 const validFrom=head.validFrom>today?head.validFrom:today;
 if(body.validUntil!==null&&body.validUntil<validFrom)throw new ApiError(422,'INVALID_INTERVAL','La fin de validité précède le début.');
 const changed=[
  ...(body.label!==head.label?['label']:[]),...(body.type!==head.type?['type']:[]),...(body.durationMinutes!==head.durationMinutes?['durationMinutes']:[]),
  ...(body.unitLabel!==head.unitLabel?['unitLabel']:[]),...(String(body.priceCents)!==String(head.unitPriceCents)?['unitPriceCents']:[]),
  ...(body.validUntil!==head.validUntil?['validUntil']:[]),...(body.enabled!==head.enabled?['enabled']:[])];
 let termsVersionId=head.termsVersionId;
 if(body.terms.mode==='NEW'){
  const current=(await termsById(db,school.id,[head.termsVersionId])).get(head.termsVersionId);
  if(!current||current.termsText!==body.terms.termsText||!current.approved||(current.validUntil!==null&&current.validUntil<today)){
   termsVersionId=await insertTerms(db,school.id,actor.membershipId,{label:`Conditions · ${body.label}`,termsText:body.terms.termsText,validFrom:validFrom});changed.push('terms');
  }
 }
 if(!changed.length)throw new ApiError(409,'TARIFF_UNCHANGED','Aucune modification à enregistrer.');
 const product=await insertProduct(db,school.id,{productKey:head.productKey,label:body.label,type:body.type,categoryCode:head.categoryCode,durationMinutes:body.durationMinutes,unitLabel:body.unitLabel,
  unitPriceCents:body.priceCents,validFrom,validUntil:body.validUntil,termsVersionId,enabled:body.enabled});
 return {data:{id:product.id,schoolId:school.id,version:product.version,productKey:head.productKey,categoryCode:head.categoryCode,previousProductVersionId:head.id,termsVersionId,changed},
  action:'TariffUpdated',resourceType:'ServiceProductVersion',resourceId:product.id,changedFields:changed};
}

export function registerFormations(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier}){
 const base='/v1/schools/:schoolId/formations';
 const schoolID=(request:FastifyRequest)=>z.object({schoolId:z.uuid()}).parse(request.params).schoolId;
 const envelope=(data:unknown,request:FastifyRequest)=>({data,requestId:request.id,serverTime:new Date().toISOString()});
 const read=async<T>(request:FastifyRequest,work:(db:PoolClient,schoolId:string)=>Promise<T>)=>{
  const schoolId=schoolID(request);
  return withActor(options.pool,await options.verifyToken(request.headers.authorization),schoolId,async(db,_actor,member)=>{
   if(!member?.roles.includes('ADMIN'))throw new ApiError(403,'SETUP_ACCESS_REQUIRED','Les formations et tarifs sont gérés par l’administration de l’école.');
   return work(db,schoolId);
  });
 };
 const empty=z.object({}).strict();
 app.get(base,async request=>{empty.parse(request.query);return envelope(await read(request,formationList),request);});
 app.get(`${base}/sheet`,async request=>{const {category}=z.object({category:categoryCode}).strict().parse(request.query);return envelope(await read(request,(db,schoolId)=>formationSheet(db,schoolId,category)),request);});
 app.get(`${base}/uncategorized-tariffs`,async request=>{empty.parse(request.query);return envelope(await read(request,uncategorizedTariffs),request);});
 app.get(`${base}/terms`,async request=>{empty.parse(request.query);return envelope(await read(request,termsList),request);});
 app.get(`${base}/references/:referenceId`,async request=>{empty.parse(request.query);const {referenceId}=z.object({schoolId:z.uuid(),referenceId:z.uuid()}).parse(request.params);
  return envelope(await read(request,(db,schoolId)=>reference(db,schoolId,referenceId)),request);});
 const command=<B extends {operationId:string},T>(path:string,type:string,schema:z.ZodType<B>,work:(db:PoolClient,actor:CommandActor,school:SchoolRow,body:B)=>Promise<{data:T&{id:string;version:number};action:string;resourceType:string;resourceId:string;changedFields:string[];reason?:string}>,limit:number)=>
  app.post(path,{bodyLimit:limit},async(request,reply)=>{
   empty.parse(request.query);const body=schema.parse(request.body);checkIdempotency(request.headers['idempotency-key'],body.operationId);const schoolId=schoolID(request);
   const data=await schoolCommand(options.pool,await options.verifyToken(request.headers.authorization),schoolId,type,body,null,(db,actor,school)=>work(db,actor,school,body));
   reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,request);
  });
 command(`${base}/programmes`,'UPDATE_FORMATION_PROGRAMME',updateProgrammeCommand,updateProgramme,1_000_000);
 command(base,'CREATE_FORMATION',createFormationCommand,createFormation,1_000_000);
 command(`${base}/tariffs`,'SAVE_TARIFF',saveTariffCommand,saveTariff,100_000);
}
