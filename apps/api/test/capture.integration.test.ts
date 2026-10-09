import {it} from 'vitest';
import {Pool} from 'pg';import{readFile,readdir}from'node:fs/promises';import{createHash,randomUUID}from'node:crypto';import{generateKeyPair,exportJWK,createLocalJWKSet,SignJWT,jwtVerify,importJWK}from'jose';import assert from'node:assert/strict';
import {buildApp}from'../src/app.js';import{createTokenVerifier}from'../src/auth.js';import{fixtureIds as id,seedFixtures}from'../scripts/fixtures.js';import{trackContentHash,type CaptureConfig}from'../src/capture-crypto.js';
it('capture privée : autorité, lots hors ordre, arrêt durable et bornes',async()=>{
const url=process.env.TEST_DATABASE_URL;if(!url||new URL(url).pathname!=='/drivy_test')throw new Error('Base de recette drivy_test requise.');const database='drivy_test',issuer='https://capture-identity.example.invalid',owner='drivy_capture_migrator';
const operator=new Pool({connectionString:url});

for(const role of [owner,'drivy_app','drivy_invitation_mailer'])await operator.query(`DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='${role}') THEN CREATE ROLE ${role} NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT; END IF; END $$`);
assert.deepEqual((await operator.query('SELECT rolsuper,rolbypassrls,rolcreaterole FROM pg_roles WHERE rolname=$1',[owner])).rows[0],{rolsuper:false,rolbypassrls:false,rolcreaterole:false});
await operator.query(`GRANT CREATE ON DATABASE ${database} TO ${owner}`);await operator.query(`GRANT drivy_app,drivy_invitation_mailer TO ${owner} WITH ADMIN OPTION`);await operator.end();
const pool=new Pool({connectionString:url}),migration=new Pool({connectionString:url,options:`-c role=${owner}`});
await pool.query('DROP SCHEMA IF EXISTS drivy CASCADE');await pool.query('DROP TABLE IF EXISTS public.drivy_migrations');await pool.query(`GRANT USAGE,CREATE ON SCHEMA public TO ${owner}`);
await migration.query('CREATE TABLE public.drivy_migrations(name text PRIMARY KEY,sha256 text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now())');
for(const name of(await readdir(new URL('../migrations/',import.meta.url))).filter(n=>/^[0-9]{3}_.*\.sql$/.test(n)).sort()){
 const db=await migration.connect(),sql=await readFile(new URL(`../migrations/${name}`,import.meta.url),'utf8');try{await db.query('BEGIN');await db.query(sql);await db.query('INSERT INTO public.drivy_migrations(name,sha256) VALUES($1,$2)',[name,createHash('sha256').update(sql).digest('hex')]);await db.query('COMMIT');}catch(e){await db.query('ROLLBACK');throw e;}finally{db.release();}if(name.startsWith('001_'))await seedFixtures(pool,issuer);
}
const rls=await pool.query("SELECT count(*)::int AS n,count(*) FILTER(WHERE relrowsecurity AND relforcerowsecurity)::int AS forced,array_agg(c.relname::text ORDER BY c.relname) AS tables FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND relkind='r'");assert.equal(rls.rows[0].n,rls.rows[0].forced);
const policy=randomUUID(),notice=randomUUID(),lesson=randomUUID();
await pool.query(`INSERT INTO drivy.school_policy_version(id,school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,'Recette uniquement','Recette uniquement','{}',true,'Synthétique',$3,now())`,[policy,id.schoolA,id.adminMember]);
await pool.query(`INSERT INTO drivy.school_data_policy(school_id,version,notice_text,retention_text,contact_email,approved_by,approved_at,notice_version_id) VALUES($1,2,'Notice synthétique locale','Conservation synthétique locale','capture@example.invalid',$2,now(),$3)`,[id.schoolA,id.adminMember,notice]);
await pool.query(`UPDATE drivy.school SET modules=jsonb_set(modules,'{gpsEnabled}','true') WHERE id=$1`,[id.schoolA]);
await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection) VALUES($1,$2,$3,$4,$5,$6,now()-interval '1 minute',now()+interval '45 minutes','Europe/Zurich','Recette synthétique',1000,0,$7,'{"mode":"UNIT_PRICE"}')`,[lesson,id.schoolA,id.aliceTraining,id.aliceLearner,id.alice,id.instructorMember,policy]);
const oidc=await generateKeyPair('RS256'),key=await exportJWK(oidc.publicKey),signing=await generateKeyPair('EdDSA',{extractable:true});
const config:CaptureConfig={encryptionKey:Buffer.alloc(32,42),encryptionKeyId:'synthetic-only',signingKey:{...await exportJWK(signing.privateKey),kid:'synthetic-only'},issuer:'https://capture-api.example.invalid',profiles:[{version:'SYNTHETIC-TEST-ONLY',platform:'IOS',deviceClass:'PHONE',modelCode:'TEST',osVersion:'TEST',appBuild:'TEST',expiresAt:new Date(Date.now()+86400000).toISOString(),maxSampleAgeSeconds:5,maxHorizontalAccuracyMeters:50,minimumFreeBytes:1,requireBackground:true,requirePreciseLocation:true},
 {version:'TRIAL-WILDCARD',platform:'IOS',deviceClass:'PHONE',modelCode:'iPhone15,3',osVersion:'26.*',appBuild:'*',expiresAt:new Date(Date.now()+86400000).toISOString(),maxSampleAgeSeconds:5,maxHorizontalAccuracyMeters:50,minimumFreeBytes:1,requireBackground:true,requirePreciseLocation:true}],uploadHours:72};
const app=buildApp({pool,cursorSecret:'capture-test-secret-32-characters',capture:config,verifyToken:createTokenVerifier({OIDC_ISSUER:issuer,OIDC_AUDIENCE:'drivy-api',OIDC_JWKS_URL:`${issuer}/jwks`},createLocalJWKSet({keys:[{...key,kid:'capture',alg:'RS256'}]}))});
const base=`/v1/schools/${id.schoolA}`;
async function call(method:'GET'|'POST'|'PUT',route:string,body?:any,version?:number,subject='demo-instructor'){
 const token=await new SignJWT({}).setProtectedHeader({alg:'RS256',kid:'capture'}).setIssuer(issuer).setSubject(subject).setAudience('drivy-api').setIssuedAt().setExpirationTime('5m').sign(oidc.privateKey);
 const result=await app.inject({method,url:route.startsWith('/v1')?route:`${base}${route}`,headers:{authorization:`Bearer ${token}`,...(body?{'idempotency-key':body.operationId}:{}),...(version?{'if-match':`"${version}"`}:{})},...(body?{payload:body}:{})});
 return result;
}
try{
 const pub=(await call('GET','/v1/capture-keys')).json().data.keys[0];assert.equal(pub.d,undefined);
 const device=randomUUID(),aBody={operationId:randomUUID(),platform:'IOS',deviceClass:'PHONE',modelCode:'TEST',osVersion:'TEST',appBuild:'TEST',permission:'BACKGROUND',preciseLocation:true,sampleAgeSeconds:0,horizontalAccuracyMeters:5,freeBytes:null,networkAvailable:true};
 let a=await call('POST',`/devices/${device}/assessments`,aBody);assert.equal(a.statusCode,201,JSON.stringify(a.json()));assert.equal(a.json().data.status,'QUALIFIED');
 const unknown=await call('POST',`/devices/${device}/assessments`,{...aBody,operationId:randomUUID(),modelCode:'UNKNOWN'});assert.equal(unknown.json().data.status,'NEEDS_CHECK');
 assert.equal((await call('GET',`/devices/${device}/assessments/${a.json().data.id}`)).json().code,'DEVICE_ASSESSMENT_SUPERSEDED');
 // Profil d'essai : toutes les versions 26.x du système et tous les builds de l'app, pour ce seul modèle.
 const trialDevice=randomUUID(),trial={...aBody,modelCode:'iPhone15,3',osVersion:'26.0.1',appBuild:'57'};
 const trialOk=await call('POST',`/devices/${trialDevice}/assessments`,{...trial,operationId:randomUUID()});assert.equal(trialOk.json().data.status,'QUALIFIED');assert.equal(trialOk.json().data.qualificationProfileVersion,'TRIAL-WILDCARD');
 assert.equal((await call('POST',`/devices/${trialDevice}/assessments`,{...trial,operationId:randomUUID(),osVersion:'25.4'})).json().data.status,'NEEDS_CHECK');
 assert.equal((await call('POST',`/devices/${trialDevice}/assessments`,{...trial,operationId:randomUUID(),osVersion:'260.1'})).json().data.status,'NEEDS_CHECK');
 assert.equal((await call('POST',`/devices/${trialDevice}/assessments`,{...trial,operationId:randomUUID(),modelCode:'iPhone16,1'})).json().data.status,'NEEDS_CHECK');
 a=await call('POST',`/devices/${device}/assessments`,{...aBody,operationId:randomUUID()});assert.equal(a.json().data.status,'QUALIFIED');
 const choice=await call('POST',`/learners/${id.aliceLearner}/recording-choice`,{operationId:randomUUID(),lessonId:lesson,status:'ALLOWED',noticeVersionId:notice,source:'SELF'},undefined,'demo-alice');assert.equal(choice.statusCode,200,JSON.stringify(choice.json()));
 const startBody={operationId:randomUUID(),deviceId:device,choiceId:choice.json().data.id,choiceVersion:choice.json().data.version,noticeVersionId:notice,explicitStartConfirmed:true,deviceAssessmentId:a.json().data.id};
 const rejected=await call('POST',`/lessons/${lesson}/captures`,{...startBody,operationId:randomUUID(),choiceVersion:choice.json().data.version+1},1);
 assert.equal(rejected.json().code,'RECORDING_CHOICE_CHANGED');assert.equal((await call('GET',`/lessons/${lesson}`)).json().data.actualStart,null);
 const start=await call('POST',`/lessons/${lesson}/captures`,startBody,1);assert.equal(start.statusCode,201,JSON.stringify(start.json()));const authorization=start.json().data,capture=authorization.capture;
 assert.equal((await call('POST',`/lessons/${lesson}/captures`,startBody,1)).json().data.capture.id,capture.id);
 const startedLesson=(await call('GET',`/lessons/${lesson}`)).json().data;
 assert.equal(startedLesson.actualStart,capture.authorizedAt);assert.equal(startedLesson.version,2);assert.equal(startedLesson.status,'PLANNED');
 const claims=await jwtVerify(authorization.signedCaptureAuthorization,await importJWK(pub,'EdDSA'),{issuer:config.issuer,audience:'drivy-native-capture'});assert.equal(claims.payload.scope,'capture:collect');
 assert.equal((await call('POST',`/lessons/${lesson}/captures`,{...startBody,operationId:randomUUID()},2)).json().code,'CAPTURE_ALREADY_ACTIVE');
 await new Promise(r=>setTimeout(r,40));const segment=randomUUID(),started=Date.parse(capture.authorizedAt)+1;
 const points=[0,1,2].map(sequence=>({sequence,elapsedMs:sequence+1,capturedAt:new Date(started+sequence+1).toISOString(),latitude:46.99+sequence/100000,longitude:6.9,accuracyMeters:5}));
 const content={segmentIndex:0,segmentStartedAt:new Date(started).toISOString(),segmentStartReason:'START' as const,points:points.slice(0,2)};const chunk={operationId:randomUUID(),...content,contentHash:trackContentHash(content),signedUploadAuthorization:authorization.signedUploadAuthorization};
 const laterContent={...content,points:points.slice(2)},laterChunk={...chunk,...laterContent,operationId:randomUUID(),contentHash:trackContentHash(laterContent)};
 const later=await call('PUT',`/captures/${capture.id}/segments/${segment}/chunks/1`,laterChunk);assert.equal(later.statusCode,200,JSON.stringify(later.json()));
 const upload=await call('PUT',`/captures/${capture.id}/segments/${segment}/chunks/0`,chunk);assert.equal(upload.statusCode,200,JSON.stringify(upload.json()));assert.equal(upload.json().data.duplicate,false);
 assert.equal((await call('PUT',`/captures/${capture.id}/segments/${segment}/chunks/0`,chunk)).json().data.duplicate,true);
 assert.equal((await call('PUT',`/captures/${capture.id}/segments/${segment}/chunks/0`,{...chunk,operationId:randomUUID()})).json().data.duplicate,true);
 const ciphertext=(await pool.query('SELECT encrypted_points FROM drivy.capture_chunk WHERE capture_id=$1',[capture.id])).rows[0].encrypted_points as Buffer;assert(!ciphertext.includes(Buffer.from('latitude')));
 // L'élève ne lit rien avant la fin de la leçon ; l'administration lit tous les trajets de l'école (décision du 28 septembre 2026), en lecture seule.
 assert.equal((await call('GET',`/captures/${capture.id}`,undefined,undefined,'demo-alice')).statusCode,404);
 const adminRead=await call('GET',`/captures/${capture.id}`,undefined,undefined,'demo-admin');assert.equal(adminRead.statusCode,200,JSON.stringify(adminRead.json()));assert.equal(adminRead.json().data.id,capture.id);
 const manifest=[{segmentId:segment,segmentIndex:0,expectedChunkIndices:[0,1],expectedPointCount:3,lastSequence:2,endReason:'STOP'}];
 const stop=await call('POST',`/captures/${capture.id}/stop`,{operationId:randomUUID(),stoppedAt:new Date().toISOString(),reason:'USER_STOP',segments:manifest,localCollectorStopped:true});assert.equal(stop.statusCode,200,JSON.stringify(stop.json()));
 const finalized=await call('POST',`/captures/${capture.id}/finalize`,{operationId:randomUUID(),segments:manifest,allowPartial:false},stop.json().data.version);assert.equal(finalized.statusCode,200,JSON.stringify(finalized.json()));assert.equal(finalized.json().data.syncState,'SYNCED');
 const page=await call('GET',`/captures/${capture.id}/replay?limit=2`);assert.equal(page.statusCode,200);assert.equal(page.json().data.segments[0].points.length,2);assert.equal(page.json().data.segments[0].continuesOnNextPage,true);
 const next=await call('GET',`/captures/${capture.id}/replay?limit=2&cursor=${encodeURIComponent(page.json().data.nextCursor)}`);assert.equal(next.json().data.segments[0].points.length,1);assert.equal(next.json().data.segments[0].continuesFromPreviousPage,true);
 // Partage automatique : l'élève lit le trajet d'une leçon réalisée, sauf si le moniteur le masque.
 assert.deepEqual((await call('GET',`/lessons/${lesson}/captures`,undefined,undefined,'demo-alice')).json().data.items,[]);
 assert.equal((await call('GET',`/captures/${capture.id}/replay`,undefined,undefined,'demo-alice')).statusCode,404);
 assert.deepEqual((await call('GET',`/lessons/${lesson}/captures`)).json().data.items.map((c:any)=>c.id),[capture.id]);
 await pool.query("UPDATE drivy.lesson SET status='COMPLETED',actual_start=now()-interval '2 minutes',actual_end=now()-interval '1 minute' WHERE id=$1",[lesson]);
 try{
  assert.deepEqual((await call('GET',`/lessons/${lesson}/captures`,undefined,undefined,'demo-alice')).json().data.items.map((c:any)=>c.id),[capture.id]);
  const learnerReplay=await call('GET',`/captures/${capture.id}/replay?limit=10`,undefined,undefined,'demo-alice');assert.equal(learnerReplay.statusCode,200,JSON.stringify(learnerReplay.json()));
  assert.equal(learnerReplay.json().data.segments[0].points.length,3);
  assert.equal((await call('GET',`/captures/${capture.id}/replay`,undefined,undefined,'demo-bob')).statusCode,404);
  assert.equal((await call('GET',`/captures/${capture.id}/replay?limit=10`,undefined,undefined,'demo-admin')).statusCode,200);
  const sharing=(await call('GET',`/lessons/${lesson}/sharing`)).json().data;assert.equal(sharing.captureHidden,false);
  const hide=await call('PUT',`/lessons/${lesson}/sharing`,{operationId:randomUUID(),reportPrivate:false,captureHidden:true,privateObservationIds:[]},sharing.version);assert.equal(hide.statusCode,200,JSON.stringify(hide.json()));
  assert.deepEqual((await call('GET',`/lessons/${lesson}/captures`,undefined,undefined,'demo-alice')).json().data.items,[]);
  assert.equal((await call('GET',`/captures/${capture.id}/replay`,undefined,undefined,'demo-alice')).statusCode,404);
  assert.equal((await call('GET',`/captures/${capture.id}/replay`)).statusCode,200);
  const show=await call('PUT',`/lessons/${lesson}/sharing`,{operationId:randomUUID(),reportPrivate:false,captureHidden:false,privateObservationIds:[]},hide.json().data.version);assert.equal(show.statusCode,200);
 }finally{await pool.query("UPDATE drivy.lesson SET status='PLANNED',actual_start=$2,actual_end=NULL WHERE id=$1",[lesson,startedLesson.actualStart]);}
 const proof=await call('GET',`/operations/${startBody.operationId}`);assert.equal(proof.statusCode,200,JSON.stringify(proof.json()));assert.equal(proof.json().data.resourceType,'CaptureSession');
 const stored=(await pool.query('SELECT response_data FROM drivy.operation WHERE operation_id=$1',[startBody.operationId])).rows[0];assert(!JSON.stringify(stored).includes('signedCaptureAuthorization'));
 // Une borne resserrée purge le lot entier touché, sans réactiver ni dupliquer son identité.
 const earlier=await call('POST',`/captures/${capture.id}/stop`,{operationId:randomUUID(),stoppedAt:points[2]!.capturedAt,reason:'USER_STOP',segments:manifest,localCollectorStopped:true});assert.equal(earlier.statusCode,200);assert.equal(earlier.json().data.syncState,'PARTIAL');assert.equal((await pool.query('SELECT encrypted_points FROM drivy.capture_chunk WHERE capture_id=$1 AND chunk_index=1',[capture.id])).rows[0].encrypted_points,null);
 // Un départ explicite demeure valide même si l'ancien créneau est dépassé (reprise GPS).
 await pool.query("UPDATE drivy.lesson SET planned_start=now()-interval '3 hours',planned_end=now()-interval '2 hours' WHERE id=$1",[lesson]);
 const nextCapture=await call('POST',`/lessons/${lesson}/captures`,{...startBody,operationId:randomUUID()},2);assert.equal(nextCapture.statusCode,201,JSON.stringify(nextCapture.json()));
 assert.equal((await call('GET',`/lessons/${lesson}`)).json().data.actualStart,startedLesson.actualStart);
 const refuse=await call('POST',`/learners/${id.aliceLearner}/recording-choice`,{operationId:randomUUID(),lessonId:lesson,status:'REFUSED',noticeVersionId:notice,source:'SELF'},undefined,'demo-alice');assert.equal(refuse.statusCode,200);
 assert.equal((await call('GET',`/captures/${nextCapture.json().data.capture.id}`)).json().data.captureState,'REVOKED');
 assert.equal((await call('POST',`/learners/${id.aliceLearner}/recording-choice`,{operationId:randomUUID(),lessonId:lesson,status:'ALLOWED',noticeVersionId:notice,source:'RECORDED_VERBAL'})).json().code,'RECORDING_CHOICE_PROTECTED');
 // Réparation historique GPS sous le propriétaire non privilégié, même avec FORCE RLS sur capture_session.
 await pool.query('UPDATE drivy.lesson SET actual_start=NULL WHERE id=$1',[lesson]);
 const migrationText=await readFile(new URL('../migrations/023_explicit_lesson_start.sql',import.meta.url),'utf8');
 const repair=migrationText.slice(migrationText.indexOf('ALTER TABLE drivy.lesson NO FORCE'),migrationText.indexOf('-- Un rendez-vous dépassé'));
 const repairDB=await migration.connect();
 try{await repairDB.query('BEGIN');await repairDB.query(repair);await repairDB.query('COMMIT');}
 catch(error){await repairDB.query('ROLLBACK');throw error;}finally{repairDB.release();}
 const repaired=(await call('GET',`/lessons/${lesson}`)).json().data;
 assert.equal(repaired.actualStart,capture.authorizedAt);assert.equal(repaired.version,3);
 assert.equal((await pool.query("SELECT bool_and(relforcerowsecurity) AS forced FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND relkind='r'")).rows[0].forced,true);
 assert.equal(rls.rows[0].forced,45);assert(rls.rows[0].tables.includes('planning_defaults'));
}finally{await app.close();await migration.end();await pool.end();}

});
