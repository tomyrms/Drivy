import {it} from 'vitest';
import {Pool} from 'pg';import{readFile,readdir}from'node:fs/promises';import{randomUUID}from'node:crypto';import{generateKeyPair,exportJWK,createLocalJWKSet,SignJWT}from'jose';import assert from'node:assert/strict';
import {buildApp}from'../src/app.js';import{createTokenVerifier}from'../src/auth.js';import{fixtureIds as id,seedFixtures}from'../scripts/fixtures.js';import{trackContentHash,type CaptureConfig}from'../src/capture-crypto.js';
it('observations privées : sans GPS, ancre acquittée, constat et retrait atomiques',async()=>{
const input=process.env.TEST_DATABASE_URL;if(!input||!['/drivy_test','/drivy_observation_test'].includes(new URL(input).pathname))throw new Error('Base de recette explicite requise.');
const database='drivy_observation_test',issuer='https://capture-identity.example.invalid',owner='drivy_observation_migrator';
const operator=new Pool({connectionString:input});
// Base réservée à ce test : les autres recettes du même cluster ne sont pas réinitialisées.
if(!(await operator.query('SELECT 1 FROM pg_database WHERE datname=$1',[database])).rowCount)await operator.query(`CREATE DATABASE ${database} ENCODING 'UTF8' TEMPLATE template0`);
const targetURL=new URL(input);targetURL.pathname=`/${database}`;const url=targetURL.toString();

for(const role of [owner,'drivy_app','drivy_invitation_mailer'])await operator.query(`DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='${role}') THEN CREATE ROLE ${role} NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT; END IF; END $$`);
assert.deepEqual((await operator.query('SELECT rolsuper,rolbypassrls,rolcreaterole FROM pg_roles WHERE rolname=$1',[owner])).rows[0],{rolsuper:false,rolbypassrls:false,rolcreaterole:false});
await operator.query(`GRANT CREATE ON DATABASE ${database} TO ${owner}`);await operator.query(`GRANT drivy_app,drivy_invitation_mailer TO ${owner} WITH ADMIN OPTION`);await operator.end();
const pool=new Pool({connectionString:url}),migration=new Pool({connectionString:url,options:`-c role=${owner}`});
await pool.query('DROP SCHEMA IF EXISTS drivy CASCADE');await pool.query('DROP TABLE IF EXISTS public.drivy_migrations');await pool.query(`GRANT USAGE,CREATE ON SCHEMA public TO ${owner}`);
for(const name of(await readdir(new URL('../migrations/',import.meta.url))).filter(n=>/^[0-9]{3}_.*\.sql$/.test(n)).sort()){
 const db=await migration.connect();try{await db.query('BEGIN');await db.query(await readFile(new URL(`../migrations/${name}`,import.meta.url),'utf8'));await db.query('COMMIT');}catch(e){await db.query('ROLLBACK');throw e;}finally{db.release();}if(name.startsWith('001_'))await seedFixtures(pool,issuer);
}
const rls=await pool.query("SELECT count(*)::int AS n,count(*) FILTER(WHERE relrowsecurity AND relforcerowsecurity)::int AS forced FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND relkind='r'");assert.equal(rls.rows[0].n,rls.rows[0].forced);
const policy=randomUUID(),notice=randomUUID(),lesson=randomUUID();
await pool.query(`INSERT INTO drivy.school_policy_version(id,school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,'Recette uniquement','Recette uniquement','{}',true,'Synthétique',$3,now())`,[policy,id.schoolA,id.adminMember]);
await pool.query(`INSERT INTO drivy.school_data_policy(school_id,version,notice_text,retention_text,contact_email,approved_by,approved_at,notice_version_id) VALUES($1,2,'Notice synthétique locale','Conservation synthétique locale','capture@example.invalid',$2,now(),$3)`,[id.schoolA,id.adminMember,notice]);
await pool.query(`UPDATE drivy.school SET modules=jsonb_set(modules,'{gpsEnabled}','true') WHERE id=$1`,[id.schoolA]);
await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection) VALUES($1,$2,$3,$4,$5,$6,now()-interval '1 minute',now()+interval '45 minutes','Europe/Zurich','Recette synthétique',1000,0,$7,'{"mode":"UNIT_PRICE"}')`,[lesson,id.schoolA,id.aliceTraining,id.aliceLearner,id.alice,id.instructorMember,policy]);
const oidc=await generateKeyPair('RS256'),key=await exportJWK(oidc.publicKey),signing=await generateKeyPair('EdDSA',{extractable:true});
const config:CaptureConfig={encryptionKey:Buffer.alloc(32,42),encryptionKeyId:'synthetic-only',signingKey:{...await exportJWK(signing.privateKey),kid:'synthetic-only'},issuer:'https://capture-api.example.invalid',profiles:[{version:'SYNTHETIC-TEST-ONLY',platform:'IOS',deviceClass:'PHONE',modelCode:'TEST',osVersion:'TEST',appBuild:'TEST',expiresAt:new Date(Date.now()+86400000).toISOString(),maxSampleAgeSeconds:5,maxHorizontalAccuracyMeters:50,minimumFreeBytes:1,requireBackground:true,requirePreciseLocation:true}],uploadHours:72};
const app=buildApp({pool,cursorSecret:'capture-test-secret-32-characters',capture:config,verifyToken:createTokenVerifier({OIDC_ISSUER:issuer,OIDC_AUDIENCE:'drivy-api',OIDC_JWKS_URL:`${issuer}/jwks`},createLocalJWKSet({keys:[{...key,kid:'capture',alg:'RS256'}]}))});
const base=`/v1/schools/${id.schoolA}`;
async function call(method:'GET'|'POST'|'PUT',route:string,body?:any,version?:number,subject='demo-instructor'){
 const token=await new SignJWT({}).setProtectedHeader({alg:'RS256',kid:'capture'}).setIssuer(issuer).setSubject(subject).setAudience('drivy-api').setIssuedAt().setExpirationTime('5m').sign(oidc.privateKey);
 const result=await app.inject({method,url:route.startsWith('/v1')?route:`${base}${route}`,headers:{authorization:`Bearer ${token}`,...(body?{'idempotency-key':body.operationId}:{}),...(version?{'if-match':`"${version}"`}:{})},...(body?{payload:body}:{})});
 return result;
}
try{
 const curriculum=randomUUID(),competency=randomUUID();
 await pool.query(`INSERT INTO drivy.curriculum_version(id,school_id,category_code,revision,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,true,'Recette synthétique',$3,now())`,[curriculum,id.schoolA,id.adminMember]);
 await pool.query(`INSERT INTO drivy.competency_definition(id,school_id,curriculum_version_id,stable_key,label,description,sort_order) VALUES($1,$2,$3,'observation','Observation','Recette synthétique',0)`,[competency,id.schoolA,curriculum]);
 await pool.query('UPDATE drivy.offering_version SET curriculum_version_id=$2 WHERE id=$1',[id.offeringA,curriculum]);
 const route=`/lessons/${lesson}/geo-observations`,body={operationId:randomUUID(),draftId:null,captureId:null,segmentId:null,pointSequence:null,competencyId:null,text:'Moment synthétique à revoir',origin:'LIVE',observedAt:new Date().toISOString(),eventKind:'MARKER',eventStatus:null};
 const [first,replay]=await Promise.all([call('POST',route,body),call('POST',route,body)]);assert.equal(first.statusCode,201,JSON.stringify(first.json()));assert.equal(replay.json().data.id,first.json().data.id);
 const marker=first.json().data;assert.equal(marker.draftId,null);assert.equal(marker.authorMembershipId,id.instructorMember);
 assert.equal((await pool.query('SELECT count(*)::int AS n FROM drivy.audit_event WHERE operation_id=$1',[body.operationId])).rows[0].n,1);
 for(const subject of ['demo-admin','demo-alice','demo-other-instructor'])assert.equal((await call('GET',route,undefined,undefined,subject)).statusCode,404);
 const qualified={...body,operationId:randomUUID(),competencyId:competency,eventKind:'QUALIFIED',eventStatus:'POSITIVE',text:'Thème choisi explicitement'};
 const updated=await call('PUT',`/geo-observations/${marker.id}`,qualified,1);assert.equal(updated.statusCode,200,JSON.stringify(updated.json()));assert.equal(updated.json().data.version,2);
 const invalid={...qualified,operationId:randomUUID(),competencyId:randomUUID()};assert.equal((await call('POST',route,invalid)).json().code,'CURRICULUM_VERSION_MISMATCH');assert.equal((await call('GET',`/operations/${invalid.operationId}`)).statusCode,404);
 const device=randomUUID();
 const assessment=await call('POST',`/devices/${device}/assessments`,{operationId:randomUUID(),platform:'IOS',deviceClass:'PHONE',modelCode:'TEST',osVersion:'TEST',appBuild:'TEST',permission:'BACKGROUND',preciseLocation:true,sampleAgeSeconds:0,horizontalAccuracyMeters:5,freeBytes:null,networkAvailable:true});assert.equal(assessment.statusCode,201);
 const choice=await call('POST',`/learners/${id.aliceLearner}/recording-choice`,{operationId:randomUUID(),lessonId:lesson,status:'ALLOWED',noticeVersionId:notice,source:'SELF'},undefined,'demo-alice');assert.equal(choice.statusCode,200);
 const start=await call('POST',`/lessons/${lesson}/captures`,{operationId:randomUUID(),deviceId:device,choiceId:choice.json().data.id,choiceVersion:choice.json().data.version,noticeVersionId:notice,explicitStartConfirmed:true,deviceAssessmentId:assessment.json().data.id},1);assert.equal(start.statusCode,201,JSON.stringify(start.json()));
 const authorization=start.json().data,capture=authorization.capture,segment=randomUUID(),started=Date.parse(capture.authorizedAt)+1;
 await new Promise(r=>setTimeout(r,30));
 const anchored={...body,operationId:randomUUID(),observedAt:new Date().toISOString(),captureId:capture.id,segmentId:segment,pointSequence:0};
 assert.equal((await call('POST',route,anchored)).json().code,'ANCHOR_NOT_READY');assert.equal((await call('GET',`/operations/${anchored.operationId}`)).statusCode,404);
 const content={segmentIndex:0,segmentStartedAt:new Date(started).toISOString(),segmentStartReason:'START' as const,points:[{sequence:0,elapsedMs:1,capturedAt:new Date(started+1).toISOString(),latitude:46.99,longitude:6.9,accuracyMeters:5}]};
 const chunk={operationId:randomUUID(),...content,contentHash:trackContentHash(content),signedUploadAuthorization:authorization.signedUploadAuthorization};
 assert.equal((await call('PUT',`/captures/${capture.id}/segments/${segment}/chunks/0`,chunk)).statusCode,200);
 const accepted=await call('POST',route,anchored);assert.equal(accepted.statusCode,201,JSON.stringify(accepted.json()));
 const replayPage=await call('GET',`/captures/${capture.id}/replay`);assert.equal(replayPage.statusCode,200);assert.deepEqual(replayPage.json().data.observations.map((o:any)=>o.id),[accepted.json().data.id]);
 const completed=await call('POST',`/lessons/${lesson}/complete`,{operationId:randomUUID(),actualStart:new Date(Date.now()-60000).toISOString(),actualEnd:new Date().toISOString(),workedOn:'Travail synthétique',observationText:'Constat synthétique',nextStep:'Suite synthétique',anomalyReason:'Recette locale'},1);
 assert.equal(completed.statusCode,200,JSON.stringify(completed.json()));const draft=completed.json().data.draft;
 assert.deepEqual(new Set(draft.geoObservationIds),new Set([marker.id,accepted.json().data.id]));
 let page=await call('GET',route);assert(page.json().data.items.every((o:any)=>o.draftId===draft.id));assert.equal(page.json().data.items.find((o:any)=>o.id===marker.id).version,3);
 assert.equal((await call('PUT',`/geo-observations/${marker.id}`,{...qualified,operationId:randomUUID()},2)).json().code,'VERSION_CONFLICT');
 // La destruction du lot supprime aussi l'ancre et invalide la version relue du brouillon.
 await pool.query('UPDATE drivy.capture_chunk SET encrypted_points=NULL WHERE capture_id=$1',[capture.id]);
 page=await call('GET',route);const unanchored=page.json().data.items.find((o:any)=>o.id===accepted.json().data.id);assert.equal(unanchored.captureId,null);assert.equal(unanchored.version,3);
 assert.deepEqual((await call('GET',`/captures/${capture.id}/replay`)).json().data.observations,[]);
 const recovered=await call('POST',route,anchored);assert.equal(recovered.json().data.captureId,null);
 const late=await call('POST',route,{...body,operationId:randomUUID()});assert.equal(late.statusCode,201);assert.equal(late.json().data.draftId,draft.id);
 const remove={operationId:randomUUID(),reason:'Retrait explicite de recette'};const removed=await call('POST',`/geo-observations/${late.json().data.id}/remove`,remove,1);assert.equal(removed.statusCode,200);assert.equal(removed.json().data.accepted,true);
 assert.equal((await call('POST',`/geo-observations/${late.json().data.id}/remove`,remove,1)).json().data.accepted,true);
 const tombstone=(await pool.query('SELECT text,capture_id,removed_at FROM drivy.geo_observation WHERE id=$1',[late.json().data.id])).rows[0];assert.equal(tombstone.text,null);assert.equal(tombstone.capture_id,null);assert(tombstone.removed_at);
 assert.equal((await call('GET',`/operations/${remove.operationId}`)).json().data.resourceType,'GeoObservation');
 const current=(await call('GET',`/report-drafts/${draft.id}`)).json().data;
 const published=await call('POST',`/report-drafts/${draft.id}/publish`,{operationId:randomUUID(),expectedPublicationVersion:0,captureSelection:null,textObservationSelection:[]},current.version);assert.equal(published.statusCode,200,JSON.stringify(published.json()));
 assert.equal((await call('POST',route,{...body,operationId:randomUUID()})).json().code,'OBSERVATION_REVIEW_REQUIRED');
 assert.equal((await call('GET',route,undefined,undefined,'demo-alice')).statusCode,404);
 const learnerReport=await call('GET',`/report-revisions/${published.json().data.id}`,undefined,undefined,'demo-alice');assert.equal(learnerReport.statusCode,200);assert.deepEqual(learnerReport.json().data.textObservations,[]);
 assert.equal(rls.rows[0].forced,44);
}finally{await app.close();await migration.end();await pool.end();}
});
