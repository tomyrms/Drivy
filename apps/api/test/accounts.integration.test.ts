import { randomBytes, randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, expect, test } from 'vitest';
import type { Pool } from 'pg';
import { buildApp } from '../src/app.js';
import type { NewAccount } from '../src/account-provisioning.js';
import { AttemptLimiter } from '../src/attempt-limiter.js';
import { ApiError } from '../src/errors.js';
import { generateInvitationCode } from '../src/invitation-code.js';
import { freshDatabase, issuer, id } from './support/harness.js';
import { seedFixtures } from '../scripts/fixtures.js';

let pool:Pool,app:ReturnType<typeof buildApp>;
const operator='opening-operator',cursorSecret='accounts-synthetic-test-secret-32-characters';
const verifyToken=async(header:string|undefined)=>{if(!header?.startsWith('Bearer '))throw new ApiError(401,'AUTHENTICATION_REQUIRED','Connexion requise.');return {issuer,subject:header.slice(7)};};
const created:NewAccount[]=[];
// Valeur générée à l'exécution : aucun secret n'est écrit dans le dépôt.
const chosenSecret=`Aa1!${randomUUID()}`;
let provisionFailure:ApiError|undefined;
const provisionAccount=async(account:NewAccount)=>{if(provisionFailure)throw provisionFailure;created.push(account);};
beforeAll(async()=>{
  pool=await freshDatabase();
  app=buildApp({pool,verifyToken,cursorSecret,provisionAccount,schoolOpening:{operators:[{issuer,subject:operator}],validityDays:7}});
});
beforeEach(async()=>{
  created.length=0;provisionFailure=undefined;
  await pool.query('TRUNCATE drivy.person,drivy.school CASCADE');await seedFixtures(pool,issuer);
  const policy=randomUUID(),curriculum=randomUUID();
  await pool.query(`INSERT INTO drivy.school_policy_version(id,school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,'Recette','Recette','{}',true,'Synthétique',$3,now())`,[policy,id.schoolA,id.adminMember]);
  await pool.query(`INSERT INTO drivy.curriculum_version(id,school_id,category_code,revision,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,true,'Synthétique',$3,now())`,[curriculum,id.schoolA,id.adminMember]);
  await pool.query('UPDATE drivy.offering_version SET curriculum_version_id=$2,policy_version_id=$3,default_duration_minutes=50,default_price_cents=9000,enabled=true WHERE id=$1',[id.offeringA,curriculum,policy]);
});
afterAll(async()=>{await app?.close();await pool?.end();});

const call=(method:'GET'|'POST',url:string,body?:Record<string,unknown>,subject?:string)=>app.inject({method,url,
  headers:{...(subject?{authorization:`Bearer ${subject}`}:{}),...(body && 'operationId' in body?{'idempotency-key':String(body.operationId)}:{})},...(body?{payload:body}:{})});
async function openingCode(code=generateInvitationCode()) {
  const response=await call('POST','/v1/operator/school-opening-links',{operationId:randomUUID(),token:code},operator);
  expect(response.statusCode,response.body).toBe(201);return code;
}
async function learnerCode() {
  const response=await call('POST',`/v1/schools/${id.schoolA}/invitations`,{operationId:randomUUID(),delivery:'CODE',roles:['LEARNER'],
    training:{offeringId:id.offeringA,instructorMembershipId:id.instructorMember}},'demo-instructor');
  expect(response.statusCode,response.body).toBe(201);return response.json().data.code as string;
}
const account=(code:string,extra:Record<string,unknown>={})=>({code,firstName:'Camille',lastName:'Recette',email:'Camille.Recette@Example.invalid',password:chosenSecret,...extra});

test('un code se lit sans connexion : élève, ouverture d’école, ou refus identique',async()=>{
  const learner=await learnerCode();
  const preview=await call('POST','/v1/access-codes/preview',{code:learner.toLowerCase().replace('-',' ')});
  expect(preview.statusCode,preview.body).toBe(200);
  expect(preview.json().data).toMatchObject({kind:'LEARNER_INVITATION',roles:['LEARNER']});
  const opening=await openingCode();
  const openingPreview=await call('POST','/v1/access-codes/preview',{code:opening});
  expect(openingPreview.json().data).toMatchObject({kind:'SCHOOL_OPENING'});
  // Le lien long d'ouverture reste accepté par la même route.
  const token=randomBytes(32).toString('base64url');
  await call('POST','/v1/operator/school-opening-links',{operationId:randomUUID(),token},operator);
  expect((await call('POST','/v1/access-codes/preview',{code:token})).json().data.kind).toBe('SCHOOL_OPENING');
  const unknown=await call('POST','/v1/access-codes/preview',{code:generateInvitationCode()});
  expect(unknown.statusCode).toBe(404);expect(unknown.json().code).toBe('ACCESS_CODE_INVALID');
  expect((await call('POST','/v1/access-codes/preview',{code:'pas un code'})).statusCode).toBe(400);
});

test('un compte ne se crée qu’avec un code valable, sans le consommer',async()=>{
  const refused=await call('POST','/v1/accounts',account(generateInvitationCode()));
  expect(refused.statusCode).toBe(404);expect(created).toHaveLength(0);
  const code=await openingCode();
  const response=await call('POST','/v1/accounts',account(code));
  expect(response.statusCode,response.body).toBe(201);
  expect(response.json().data).toEqual({kind:'SCHOOL_OPENING',email:'camille.recette@example.invalid'});
  expect(created).toEqual([{email:'camille.recette@example.invalid',firstName:'Camille',lastName:'Recette',password:chosenSecret}]);
  expect(JSON.stringify(response.json())).not.toContain(chosenSecret);
  // Le code reste disponible : c'est l'ouverture, connectée, qui le consomme, par le code court lui-même.
  const opened=await call('POST','/v1/school-openings',{operationId:randomUUID(),token:code,schoolName:'École par code',displayName:'Camille Recette',
    contactEmail:'ecole@example.invalid',contactPhone:null,timeZone:'Europe/Zurich',instructs:true},'new-account-subject');
  expect(opened.statusCode,opened.body).toBe(201);
  expect((await call('POST','/v1/access-codes/preview',{code})).statusCode).toBe(404);
  expect((await call('POST','/v1/accounts',account(code,{email:'autre@example.invalid'}))).statusCode).toBe(404);
});

test('les refus du fournisseur et les champs invalides ne créent rien',async()=>{
  const code=await learnerCode();
  expect((await call('POST','/v1/accounts',account(code,{password:chosenSecret.slice(0,5)}))).statusCode).toBe(400);
  expect((await call('POST','/v1/accounts',account(code,{email:'pas-une-adresse'}))).statusCode).toBe(400);
  expect((await call('POST','/v1/accounts',{...account(code),extra:true})).statusCode).toBe(400);
  provisionFailure=new ApiError(409,'ACCOUNT_EXISTS','Un compte existe déjà.');
  expect((await call('POST','/v1/accounts',account(code))).json().code).toBe('ACCOUNT_EXISTS');
  expect(created).toHaveLength(0);
});

test('sans fournisseur configuré, la création répond indisponible',async()=>{
  const closed=buildApp({pool,verifyToken,cursorSecret});
  try {
    const code=await learnerCode();
    const response=await closed.inject({method:'POST',url:'/v1/accounts',payload:account(code)});
    expect(response.statusCode).toBe(503);expect(response.json().code).toBe('ACCOUNT_CREATION_UNAVAILABLE');
  } finally {await closed.close();}
});

test('les codes refusés et les créations en série sont freinés par adresse',async()=>{
  const limited=buildApp({pool,verifyToken,cursorSecret,provisionAccount,accessCodeAttempts:new AttemptLimiter(2,60_000),accountCreations:new AttemptLimiter(1,60_000)});
  try {
    const preview=()=>limited.inject({method:'POST',url:'/v1/access-codes/preview',payload:{code:generateInvitationCode()}});
    expect((await preview()).statusCode).toBe(404);expect((await preview()).statusCode).toBe(404);
    const blocked=await preview();expect(blocked.statusCode).toBe(429);expect(blocked.json().code).toBe('ACCESS_CODE_ATTEMPTS');
  } finally {await limited.close();}
});
