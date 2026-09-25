import {readFile,readdir} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {Pool} from 'pg';
import {createLocalJWKSet,exportJWK,generateKeyPair,SignJWT} from 'jose';
import {Ajv2020} from 'ajv/dist/2020.js';
import {fullFormats} from 'ajv-formats/dist/formats.js';
import {parse} from 'yaml';
import {buildApp} from '../../src/app.js';
import {createTokenVerifier} from '../../src/auth.js';
import {fixtureIds as id,seedFixtures} from '../../scripts/fixtures.js';

/** Recette PostgreSQL réelle : schéma recréé, toutes les migrations sous un propriétaire non privilégié, requêtes sous drivy_app. */
export const issuer='https://harness-identity.example.invalid';
export async function freshDatabase(){
 const url=process.env.TEST_DATABASE_URL;if(!url||new URL(url).pathname!=='/drivy_test')throw new Error('Base de recette drivy_test requise.');
 const owner='drivy_harness_migrator',operator=new Pool({connectionString:url});
 try{
  for(const role of [owner,'drivy_app','drivy_invitation_mailer'])await operator.query(`DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='${role}') THEN CREATE ROLE ${role} NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT; END IF; END $$`);
  await operator.query(`GRANT CREATE ON DATABASE drivy_test TO ${owner}`);await operator.query(`GRANT drivy_app,drivy_invitation_mailer TO ${owner} WITH ADMIN OPTION`);
  await operator.query('DROP SCHEMA IF EXISTS drivy CASCADE');await operator.query('DROP TABLE IF EXISTS public.drivy_migrations');await operator.query(`GRANT USAGE,CREATE ON SCHEMA public TO ${owner}`);
 }finally{await operator.end();}
 const pool=new Pool({connectionString:url}),migration=new Pool({connectionString:url,options:`-c role=${owner}`});
 try{
  // Le registre reste cohérent avec le schéma : une suite suivante utilisant scripts/migrations.ts ne réapplique rien.
  await migration.query('CREATE TABLE public.drivy_migrations(name text PRIMARY KEY,sha256 text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now())');
  for(const name of (await readdir(new URL('../../migrations/',import.meta.url))).filter(n=>/^[0-9]{3}_.*\.sql$/.test(n)).sort()){
   const db=await migration.connect(),sql=await readFile(new URL(`../../migrations/${name}`,import.meta.url),'utf8');
   try{await db.query('BEGIN');await db.query(sql);await db.query('INSERT INTO public.drivy_migrations(name,sha256) VALUES($1,$2)',[name,createHash('sha256').update(sql).digest('hex')]);await db.query('COMMIT');}catch(e){await db.query('ROLLBACK');throw e;}finally{db.release();}
   if(name.startsWith('001_'))await seedFixtures(pool,issuer);
  }
 }finally{await migration.end();}
 return pool;
}
export type Call=(method:'GET'|'POST'|'PUT'|'PATCH',route:string,body?:Record<string,unknown>,version?:number|null,subject?:string,headers?:Record<string,string>)=>Promise<{statusCode:number;json:()=>any;headers:Record<string,unknown>;body:string}>;
export async function harness(pool:Pool,options:{reauthMaxAgeSeconds?:number}={}){
 const keys=await generateKeyPair('RS256'),key=await exportJWK(keys.publicKey);
 const app=buildApp({pool,cursorSecret:'harness-test-secret-32-characters!!',...options,verifyToken:createTokenVerifier({OIDC_ISSUER:issuer,OIDC_AUDIENCE:'drivy-api',OIDC_JWKS_URL:`${issuer}/jwks`},createLocalJWKSet({keys:[{...key,kid:'harness',alg:'RS256'}]}))});
 const base=`/v1/schools/${id.schoolA}`;
 const token=(subject:string,authTime=Math.floor(Date.now()/1000))=>new SignJWT({auth_time:authTime}).setProtectedHeader({alg:'RS256',kid:'harness'}).setIssuer(issuer).setSubject(subject).setAudience('drivy-api').setIssuedAt().setExpirationTime('5m').sign(keys.privateKey);
 const call:Call=async(method,route,body,version,subject='demo-instructor',headers={})=>{
  return app.inject({method,url:route.startsWith('/v1/')||route.startsWith('/health/')?route:`${base}${route}`,
   headers:{authorization:`Bearer ${await token(subject)}`,...(body?{'idempotency-key':String(body.operationId)}:{}),...(version?{'if-match':`"${version}"`}:{}),...headers},...(body?{payload:body}:{})}) as never;
 };
 return {app,call,base,token};
}

/** Contexte scolaire synthétique minimal pour planifier : textes approuvés, politique publiée, identités complètes. */
export async function prepareSchool(pool:Pool){
 const policy=randomUUID(),curriculum=randomUUID(),competency=randomUUID(),competency2=randomUUID(),notice=randomUUID();
 await pool.query(`INSERT INTO drivy.school_policy_version(id,school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,'Recette uniquement','Recette uniquement','{}',true,'Synthétique',$3,now())`,[policy,id.schoolA,id.adminMember]);
 await pool.query(`INSERT INTO drivy.curriculum_version(id,school_id,category_code,revision,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,true,'Recette synthétique',$3,now())`,[curriculum,id.schoolA,id.adminMember]);
 await pool.query(`INSERT INTO drivy.competency_definition(id,school_id,curriculum_version_id,stable_key,label,description,sort_order) VALUES($1,$3,$4,'look','Observation','Synthétique',0),($2,$3,$4,'lane','Placement','Synthétique',1)`,[competency,competency2,id.schoolA,curriculum]);
 await pool.query(`UPDATE drivy.offering_version SET curriculum_version_id=$2,policy_version_id=$3,default_duration_minutes=50,default_price_cents=9000,enabled=true WHERE id=$1`,[id.offeringA,curriculum,policy]);
 await pool.query(`INSERT INTO drivy.school_data_policy(school_id,version,notice_text,retention_text,contact_email,approved_by,approved_at,notice_version_id) VALUES($1,2,'Notice synthétique','Conservation synthétique','recette@example.invalid',$2,now(),$3)`,[id.schoolA,id.adminMember,notice]);
 await pool.query(`INSERT INTO drivy.profile_field_policy(school_id,status,effective_from,fields,notice_version_id,approved_by_membership_id,approved_at,created_by_membership_id)
  VALUES($1,'PUBLISHED',now()-interval '1 day',$2,$3,$4,now(),$4)`,[id.schoolA,JSON.stringify([{field:'firstName',requirement:'REQUIRED',stage:'JOIN',purposeCode:'IDENTIFICATION'},{field:'lastName',requirement:'REQUIRED',stage:'JOIN',purposeCode:'IDENTIFICATION'}]),notice,id.adminMember]);
 await pool.query(`UPDATE drivy.learner_profile SET first_name='Alice',last_name='Exemple' WHERE id=$1`,[id.aliceLearner]);
 await pool.query(`UPDATE drivy.learner_profile SET first_name='Noé',last_name='Exemple' WHERE id=$1`,[id.bobLearner]);
 await pool.query(`UPDATE drivy.membership SET grants='{CONFIGURE_CATALOG}' WHERE id=$1`,[id.adminMember]);
 return {policy,curriculum,competency,competency2,notice};
}
/** Conditions et prestation créées par les routes réelles (extension commercial-terms, AP101). */
export async function prepareCommercial(call:Call){
 const today=new Date().toISOString().slice(0,10);
 const terms=await call('POST','/commercial-terms',{operationId:randomUUID(),label:'Conditions de recette',termsText:'Texte synthétique',validFrom:today,validUntil:null,approved:true,approvalReason:'Relu pour recette'},null,'demo-admin');
 if(terms.statusCode!==201)throw new Error(terms.body);
 const product=await call('POST','/service-products',{operationId:randomUUID(),productKey:'lesson-50',label:'Leçon 50 min',type:'INDIVIDUAL_LESSON',categoryCode:'B',siteId:null,durationMinutes:50,unitLabel:'leçon',unitPriceCents:9000,validFrom:today,validUntil:null,termsVersionId:terms.json().data.id,enabled:true},null,'demo-admin');
 if(product.statusCode!==201)throw new Error(product.body);
 const rule=await call('POST','/availability-rules',{operationId:randomUUID(),instructorMembershipId:id.instructorMember,weekdays:[1,2,3,4,5,6,7],localStart:'06:00',localEnd:'22:00',validFrom:today,validUntil:null});
 if(rule.statusCode!==201)throw new Error(rule.body);
 return {terms:terms.json().data,product:product.json().data,rule:rule.json().data};
}
/** Créneau futur (jour J+offset, 50 minutes) dans la même journée locale de l'école. */
export function slot(dayOffset:number,hourUtc=8,minute=0){
 const start=new Date();start.setUTCDate(start.getUTCDate()+dayOffset);start.setUTCHours(hourUtc,minute,0,0);
 return {plannedStart:start.toISOString(),plannedEnd:new Date(start.getTime()+50*60_000).toISOString()};
}
export function lessonBody(commercial:{terms:{id:string};product:{id:string}},policyVersionId:string,dayOffset=1,hourUtc=8,extra:Record<string,unknown>={}){
 return {operationId:randomUUID(),trainingId:id.aliceTraining,...slot(dayOffset,hourUtc),timeZone:'Europe/Zurich',meetingPoint:'Gare (synthétique)',instructorMembershipId:id.instructorMember,
  agreedPriceCents:9000,bufferMinutes:10,policyVersionId,commercialSelection:{mode:'UNIT_PRICE',serviceProductVersionId:commercial.product.id,quantity:1,entitlementLotId:null,acceptedTermsVersionId:commercial.terms.id},...extra};
}
/** Déplace dans le passé un rendez-vous créé par AP40 : seule façon honnête d'obtenir une leçon terminée sans horloge simulée. */
let pastSlot=0;
export async function moveToPast(pool:Pool,lessonId:string,hoursAgo=2+(pastSlot++)){
 await pool.query(`UPDATE drivy.reservation SET during=tstzrange(now()-make_interval(hours=>$2),now()-make_interval(hours=>$2)+interval '50 minutes','[)') WHERE lesson_id=$1`,[lessonId,hoursAgo]);
 await pool.query(`UPDATE drivy.lesson SET planned_start=now()-make_interval(hours=>$2),planned_end=now()-make_interval(hours=>$2)+interval '50 minutes' WHERE id=$1`,[lessonId,hoursAgo]);
}
export {id};

let ajv:Ajv2020|undefined;
/** Valide une réponse complète (enveloppe comprise) contre le schéma canonique OpenAPI 3.11.0, sans le modifier. */
export async function expectContract(schema:string,body:unknown){
 if(!ajv){
  const document=parse(await readFile(new URL('../../../../Drivy_Conception_v3_17_2026-09-20/04-technique/openapi.yaml',import.meta.url),'utf8')) as {components:object};
  ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});ajv.addSchema({$id:'drivy-contract',components:document.components});
 }
 const validate=ajv.getSchema(`drivy-contract#/components/schemas/${schema}`);if(!validate)throw new Error(`Schéma inconnu ${schema}`);
 if(!validate(body))throw new Error(`${schema} : ${JSON.stringify(validate.errors)}`);
}
