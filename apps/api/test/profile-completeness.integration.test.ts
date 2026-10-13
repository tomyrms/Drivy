import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {beforeAll,beforeEach,afterAll,describe,it,expect} from 'vitest';
import {Pool} from 'pg';
import {createLocalJWKSet,exportJWK,generateKeyPair,SignJWT} from 'jose';
import {Ajv2020} from 'ajv/dist/2020.js';
import {fullFormats} from 'ajv-formats/dist/formats.js';
import {parse} from 'yaml';
import {buildApp} from '../src/app.js';
import {createTokenVerifier} from '../src/auth.js';
import {migrate} from '../scripts/migrations.js';
import {fixtureIds as id,seedFixtures} from '../scripts/fixtures.js';

const url=process.env.TEST_DATABASE_URL;
if(!url || new URL(url).pathname!=='/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const pool=new Pool({connectionString:url,max:10,application_name:'drivy-completeness-tests'});
const issuer='https://identity.test.invalid';const school=`/v1/schools/${id.schoolA}`;
let app:ReturnType<typeof buildApp>;let keys:Awaited<ReturnType<typeof generateKeyPair>>;
const validators=new Map<string,ReturnType<Ajv2020['compile']>>();
beforeAll(async()=>{
  await migrate(pool);keys=await generateKeyPair('RS256');const key=await exportJWK(keys.publicKey);
  app=buildApp({pool,cursorSecret:'secret-test-32-caracteres-minimum',invitationMail:{webURL:'http://127.0.0.1:3002/app/invitation',encryptionKey:'a1'.repeat(32),host:'127.0.0.1',port:1025,secure:false,requireTLS:false,from:'drivy@example.invalid'},verifyToken:createTokenVerifier({OIDC_ISSUER:issuer,OIDC_AUDIENCE:'drivy-api',OIDC_JWKS_URL:`${issuer}/jwks`},createLocalJWKSet({keys:[{...key,kid:'g1d',alg:'RS256'}]}))});
  const document=parse(await readFile(new URL('../../../Drivy_Conception_v3_17_2026-09-20/04-technique/openapi.yaml',import.meta.url),'utf8')) as {components:object};
  const ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});ajv.addSchema({$id:'g1d',components:document.components});
  for(const name of ['ProfileFieldPolicyEnvelopeV3','LearnerActionReadinessEnvelopeV3','LearnerEnvelope']) validators.set(name,ajv.compile({$ref:`g1d#/components/schemas/${name}`}));
});
beforeEach(async()=>{await pool.query('TRUNCATE drivy.person,drivy.school CASCADE');await seedFixtures(pool,issuer);});
afterAll(async()=>{await app?.close();await pool.end();});
async function call(method:'GET'|'PUT'|'POST'|'PATCH',path:string,body?:Record<string,unknown>,version?:number,subject='demo-admin',claims:Record<string,unknown>={}) {
  const jwt=await new SignJWT(claims).setProtectedHeader({alg:'RS256',kid:'g1d'}).setSubject(subject).setIssuer(issuer).setAudience('drivy-api').setIssuedAt().setExpirationTime('5m').sign(keys.privateKey);
  return app.inject({method,url:path,headers:{authorization:`Bearer ${jwt}`,...(body?{'idempotency-key':String(body.operationId)}:{}),...(version?{'if-match':`"${version}"`}:{})},...(body?{payload:body}:{})});
}
function conforms(name:string,value:unknown) {const validate=validators.get(name)!;expect(validate(value),JSON.stringify(validate.errors)).toBe(true);}
const names=()=>['firstName','lastName'].map(field=>({field,requirement:'REQUIRED',stage:'JOIN',purposeCode:'IDENTIFICATION',explanation:'Identifier le dossier scolaire.'}));
const optional=(field:string,purposeCode='LESSON_CONTACT')=>({field,requirement:'OPTIONAL',stage:'OPTIONAL',purposeCode,explanation:'Information facultative expliquée.'});
const noticeBody=()=>({operationId:randomUUID(),noticeText:'Notice de test du profil : finalités et contact.',retentionText:'Conservation limitée aux tests, sans donnée réelle.',contactEmail:'privacy@example.invalid',reviewAcknowledged:true});
async function notice() {const response=await call('PUT',`${school}/data-policy`,noticeBody(),1);expect(response.statusCode,response.body).toBe(200);return response.json().data.noticeVersionId as string;}
async function draft(rules=names(),effectiveFrom='2026-01-01T00:00:00Z',noticeId?:string) {
  const noticeVersionId=noticeId ?? await notice();const version=(await call('GET',school)).json().data.version;
  const response=await call('POST',`${school}/profile-field-policies`,{operationId:randomUUID(),fields:rules,effectiveFrom,noticeVersionId,impactAcknowledged:true},version);
  expect(response.statusCode,response.body).toBe(201);conforms('ProfileFieldPolicyEnvelopeV3',response.json());return response.json().data as {id:string;version:number;noticeVersionId:string};
}
async function publish(rules=[...names(),optional('contactEmail'),optional('contactPhone'),optional('birthDate','COURSE_ELIGIBILITY'),optional('postalAddress','POSTAL_CONTACT'),optional('profilePhotoDocumentId','PERSONALISATION')]) {
  const policy=await draft(rules);const response=await call('POST',`${school}/profile-field-policies/${policy.id}/publish`,{operationId:randomUUID()},1);
  expect(response.statusCode,response.body).toBe(200);conforms('ProfileFieldPolicyEnvelopeV3',response.json());return policy.id;
}
const required=(field:string,stage:'BEFORE_LESSON'|'BEFORE_COURSE',purposeCode:string)=>({field,requirement:'REQUIRED',stage,purposeCode,explanation:'Information exigée par l’école.'});
const learnerPath=`${school}/learners/${id.aliceLearner}`;
async function readiness(subject='demo-admin') {
  const response=await call('GET',learnerPath,undefined,undefined,subject);expect(response.statusCode,response.body).toBe(200);conforms('LearnerEnvelope',response.json());
  return response.json().data.profileReadiness as string;
}
async function listed(requiresAction:boolean) {
  const response=await call('GET',`${school}/learners?requiresAction=${requiresAction}`);expect(response.statusCode,response.body).toBe(200);
  return (response.json().data.items as {id:string;profileReadiness:string}[]);
}
/** Ce que le dossier nomme : les champs à renseigner pour planifier, tels que la readiness PLAN_LESSON les rend. */
async function namedFields(subject='demo-admin') {
  const response=await call('GET',`${learnerPath}/action-readiness?action=PLAN_LESSON&resourceId=${id.aliceTraining}`,undefined,undefined,subject);
  conforms('LearnerActionReadinessEnvelopeV3',response.json());
  return (response.json().data.blockers as {code:string;field:string|null}[]).filter(item=>item.code==='PROFILE_ACTION_REQUIRED').map(item=>item.field);
}
async function patch(body:Record<string,unknown>,policyVersionId:string) {
  const version=(await call('GET',`${learnerPath}/administrative-profile`)).json().data.version as number;
  const response=await call('PATCH',`${learnerPath}/administrative-profile`,{operationId:randomUUID(),policyVersionId,...body},version);expect(response.statusCode,response.body).toBe(200);
}

describe('Complétude du dossier · une règle pour la liste, le dossier et la planification',()=>{
  it('sans politique publiée, rien n’est exigé : aucun dossier ne se dit incomplet',async()=>{
    expect(await readiness()).toBe('READY');
    expect((await listed(true)).map(item=>item.id)).toEqual([]);
  });
  it('un champ facultatif ou d’une étape à venir ne rend pas le dossier incomplet',async()=>{
    await publish([...names(),optional('contactPhone'),required('birthDate','BEFORE_COURSE','COURSE_ELIGIBILITY'),optional('postalAddress','POSTAL_CONTACT')]);
    const policyVersionId=(await call('GET',`${learnerPath}/administrative-profile`)).json().data.policyVersionId as string;
    expect(await readiness()).toBe('MINIMAL');
    await patch({firstName:'Alice',lastName:'Exemple'},policyVersionId);
    expect(await readiness()).toBe('READY');expect(await namedFields()).toEqual([]);
  });
  it('incomplet, partiellement complété, complet : la liste, le dossier et le filtre suivent chaque écriture',async()=>{
    await publish([...names(),required('contactPhone','BEFORE_LESSON','LESSON_CONTACT'),required('postalAddress','BEFORE_LESSON','POSTAL_CONTACT'),optional('profilePhotoDocumentId','PERSONALISATION')]);
    const policyVersionId=(await call('GET',`${learnerPath}/administrative-profile`)).json().data.policyVersionId as string;
    // Incomplet : identité, téléphone et adresse.
    expect(await readiness()).toBe('MINIMAL');
    expect(await namedFields()).toEqual(['firstName','lastName','contactPhone','postalAddress']);
    expect((await listed(true)).map(item=>item.id)).toContain(id.aliceLearner);
    // Partiellement complété : l’identité est là, le reste manque encore.
    await patch({firstName:'Alice',lastName:'Exemple'},policyVersionId);
    expect(await readiness()).toBe('ACTION_REQUIRED');
    expect(await namedFields()).toEqual(['contactPhone','postalAddress']);
    // Le moniteur affecté lit le même état ; le dossier ne lui nomme que les champs qu’il voit.
    expect(await readiness('demo-instructor')).toBe('ACTION_REQUIRED');
    expect(await namedFields('demo-instructor')).toEqual(['contactPhone']);
    await patch({contactPhone:'+41 21 000 00 00'},policyVersionId);
    expect(await readiness()).toBe('ACTION_REQUIRED');expect(await namedFields()).toEqual(['postalAddress']);
    // Complet : plus rien dans la liste filtrée, la planification ne refuse plus pour le profil.
    await patch({postalAddress:{line1:'Rue du Lac 1',line2:null,postalCode:'1000',locality:'Lausanne',countryCode:'CH'}},policyVersionId);
    expect(await readiness()).toBe('READY');expect(await namedFields()).toEqual([]);
    expect((await listed(true)).map(item=>item.id)).not.toContain(id.aliceLearner);
    expect((await listed(false)).find(item=>item.id===id.aliceLearner)?.profileReadiness).toBe('READY');
  });
  it('un champ vidé rend le dossier de nouveau incomplet, sans relance',async()=>{
    await publish([...names(),required('contactPhone','BEFORE_LESSON','LESSON_CONTACT'),optional('profilePhotoDocumentId','PERSONALISATION')]);
    const policyVersionId=(await call('GET',`${learnerPath}/administrative-profile`)).json().data.policyVersionId as string;
    await patch({firstName:'Alice',lastName:'Exemple',contactPhone:'+41 21 000 00 00'},policyVersionId);
    expect(await readiness()).toBe('READY');
    await patch({contactPhone:null},policyVersionId);
    expect(await readiness()).toBe('ACTION_REQUIRED');expect(await namedFields()).toEqual(['contactPhone']);
  });
});
