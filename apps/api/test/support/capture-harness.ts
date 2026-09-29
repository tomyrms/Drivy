import {randomUUID} from 'node:crypto';
import {createLocalJWKSet,exportJWK,generateKeyPair,SignJWT} from 'jose';
import type {Pool} from 'pg';
import {buildApp} from '../../src/app.js';
import {createTokenVerifier} from '../../src/auth.js';
import {trackContentHash,type CaptureConfig} from '../../src/capture-crypto.js';
import {id,issuer} from './harness.js';

/** Trajets de recette sur PostgreSQL réel : école GPS activée, notice adoptée, appareil qualifié par un profil synthétique. */
export async function captureHarness(pool:Pool){
 const oidc=await generateKeyPair('RS256'),key=await exportJWK(oidc.publicKey),signing=await generateKeyPair('EdDSA',{extractable:true});
 const config:CaptureConfig={encryptionKey:Buffer.alloc(32,42),encryptionKeyId:'synthetic-only',signingKey:{...await exportJWK(signing.privateKey),kid:'synthetic-only'},issuer:'https://capture-api.example.invalid',
  profiles:[{version:'SYNTHETIC-TEST-ONLY',platform:'IOS',deviceClass:'PHONE',modelCode:'TEST',osVersion:'TEST',appBuild:'TEST',expiresAt:new Date(Date.now()+86400000).toISOString(),maxSampleAgeSeconds:5,maxHorizontalAccuracyMeters:50,minimumFreeBytes:1,requireBackground:true,requirePreciseLocation:true}],uploadHours:72};
 const app=buildApp({pool,cursorSecret:'capture-harness-secret-32-characters',capture:config,verifyToken:createTokenVerifier({OIDC_ISSUER:issuer,OIDC_AUDIENCE:'drivy-api',OIDC_JWKS_URL:`${issuer}/jwks`},createLocalJWKSet({keys:[{...key,kid:'capture',alg:'RS256'}]}))});
 const base=`/v1/schools/${id.schoolA}`;
 async function call(method:'GET'|'POST'|'PUT',route:string,body?:any,version?:number,subject='demo-instructor'){
  const token=await new SignJWT({}).setProtectedHeader({alg:'RS256',kid:'capture'}).setIssuer(issuer).setSubject(subject).setAudience('drivy-api').setIssuedAt().setExpirationTime('5m').sign(oidc.privateKey);
  return app.inject({method,url:route.startsWith('/v1')?route:`${base}${route}`,headers:{authorization:`Bearer ${token}`,...(body?{'idempotency-key':body.operationId}:{}),...(version?{'if-match':`"${version}"`}:{})},...(body?{payload:body}:{})});
 }
 const policy=randomUUID(),notice=randomUUID();
 await pool.query(`INSERT INTO drivy.school_policy_version(id,school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,'Recette uniquement','Recette uniquement','{}',true,'Synthétique',$3,now())`,[policy,id.schoolA,id.adminMember]);
 await pool.query(`INSERT INTO drivy.school_data_policy(school_id,version,notice_text,retention_text,contact_email,approved_by,approved_at,notice_version_id) VALUES($1,2,'Notice synthétique locale','Conservation synthétique locale','capture@example.invalid',$2,now(),$3)`,[id.schoolA,id.adminMember,notice]);
 await pool.query(`UPDATE drivy.school SET modules=jsonb_set(modules,'{gpsEnabled}','true') WHERE id=$1`,[id.schoolA]);

 interface Party {instructorSubject:string;instructorMember:string;learnerSubject:string;learnerId:string;learnerPerson:string;trainingId:string}
 /** Leçon en cours (début il y a une minute) puis capture autorisée : diagnostic, choix de l'élève, démarrage explicite. */
 async function startTrip(party:Party){
  const lesson=randomUUID(),device=randomUUID();
  await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection) VALUES($1,$2,$3,$4,$5,$6,now()-interval '1 minute',now()+interval '45 minutes','Europe/Zurich','Recette synthétique',1000,0,$7,'{"mode":"UNIT_PRICE"}')`,[lesson,id.schoolA,party.trainingId,party.learnerId,party.learnerPerson,party.instructorMember,policy]);
  const assessed=await call('POST',`/devices/${device}/assessments`,{operationId:randomUUID(),platform:'IOS',deviceClass:'PHONE',modelCode:'TEST',osVersion:'TEST',appBuild:'TEST',permission:'BACKGROUND',preciseLocation:true,sampleAgeSeconds:0,horizontalAccuracyMeters:5,freeBytes:null,networkAvailable:true},undefined,party.instructorSubject);
  if(assessed.statusCode!==201)throw new Error(assessed.body);
  const choice=await call('POST',`/learners/${party.learnerId}/recording-choice`,{operationId:randomUUID(),lessonId:lesson,status:'ALLOWED',noticeVersionId:notice,source:'SELF'},undefined,party.learnerSubject);
  if(choice.statusCode!==200)throw new Error(choice.body);
  const start=await call('POST',`/lessons/${lesson}/captures`,{operationId:randomUUID(),deviceId:device,choiceId:choice.json().data.id,choiceVersion:choice.json().data.version,noticeVersionId:notice,explicitStartConfirmed:true,deviceAssessmentId:assessed.json().data.id},1,party.instructorSubject);
  if(start.statusCode!==201)throw new Error(start.body);
  const authorization=start.json().data;
  return {lesson,device,capture:authorization.capture as {id:string;authorizedAt:string;version:number},uploadAuthorization:authorization.signedUploadAuthorization as string,party};
 }
 type Trip=Awaited<ReturnType<typeof startTrip>>;
 /** Trois mesures espacées de 10 ms à partir de authorizedAt+1 ms : les instants sont exacts et connus du test. */
 const pointTimes=(trip:Trip)=>{const started=Date.parse(trip.capture.authorizedAt)+1;return {started,at:[10,20,30].map(offset=>started+offset)};};
 /** Envoie le lot, arrête puis finalise. Rend l'identité du segment et les instants des trois mesures. */
 async function uploadStopFinalize(trip:Trip,beforeFinalize?:()=>Promise<void>){
  const {started,at}=pointTimes(trip),segment=randomUUID();
  while(Date.now()<started+60)await new Promise(r=>setTimeout(r,10));
  const points=at.map((capturedAt,sequence)=>({sequence,elapsedMs:capturedAt-started,capturedAt:new Date(capturedAt).toISOString(),latitude:46.99+sequence/100000,longitude:6.9,accuracyMeters:5}));
  const content={segmentIndex:0,segmentStartedAt:new Date(started).toISOString(),segmentStartReason:'START' as const,points};
  const upload=await call('PUT',`/captures/${trip.capture.id}/segments/${segment}/chunks/0`,{operationId:randomUUID(),...content,contentHash:trackContentHash(content),signedUploadAuthorization:trip.uploadAuthorization},undefined,trip.party.instructorSubject);
  if(upload.statusCode!==200)throw new Error(upload.body);
  const manifest=[{segmentId:segment,segmentIndex:0,expectedChunkIndices:[0],expectedPointCount:3,lastSequence:2,endReason:'STOP'}];
  const stop=await call('POST',`/captures/${trip.capture.id}/stop`,{operationId:randomUUID(),stoppedAt:new Date().toISOString(),reason:'USER_STOP',segments:manifest,localCollectorStopped:true},undefined,trip.party.instructorSubject);
  if(stop.statusCode!==200)throw new Error(stop.body);
  await beforeFinalize?.();
  const finalized=await call('POST',`/captures/${trip.capture.id}/finalize`,{operationId:randomUUID(),segments:manifest,allowPartial:false},stop.json().data.version,trip.party.instructorSubject);
  if(finalized.statusCode!==200)throw new Error(finalized.body);
  return {segment,started,at,manifest,finalized:finalized.json().data as {version:number;syncState:string}};
 }
 /** Repère LIVE sans position (comme l'app tant qu'elle n'a pas d'ancre), à l'instant donné. */
 const marker=(observedAt:number,text='Repère synthétique')=>({operationId:randomUUID(),draftId:null,captureId:null,segmentId:null,pointSequence:null,competencyId:null,text,origin:'LIVE',observedAt:new Date(observedAt).toISOString(),eventKind:'MARKER',eventStatus:null});
 return {app,call,config,notice,policy,startTrip,uploadStopFinalize,pointTimes,marker};
}
export type CaptureHarness=Awaited<ReturnType<typeof captureHarness>>;
