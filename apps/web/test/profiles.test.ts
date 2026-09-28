import {TestMemoryCommandStore} from '../server/test-memory-commands.js';
import { randomUUID } from 'node:crypto';
import { afterEach,expect,test } from 'vitest';
import { buildWebApp } from '../server/app.js';
import { SessionStore,type Tokens } from '../server/session.js';
import type { ApiGateway,ApiOptions } from '../server/upstream.js';
import type { IdentityProvider } from '../server/oidc.js';
import { profilePayload,fieldRule } from '../server/profile-contract.js';

const ids={school:randomUUID(),person:randomUUID(),member:randomUUID(),learner:randomUUID(),profile:randomUUID(),policy:randomUUID(),notice:randomUUID()};
const config={origin:'https://drivy.example',apiBaseURL:'https://api.example',issuer:'https://identity.example/realm',clientId:'drivy-web',clientSecret:'x'.repeat(40),development:false,host:'127.0.0.1',port:3002};
const rules=[{field:'firstName',requirement:'REQUIRED',stage:'JOIN',purposeCode:'IDENTIFICATION',explanation:'Identification scolaire.'},
  {field:'lastName',requirement:'REQUIRED',stage:'JOIN',purposeCode:'IDENTIFICATION',explanation:'Identification scolaire.'}];
const policy={id:ids.policy,schoolId:ids.school,version:1,status:'PUBLISHED',effectiveFrom:'2026-01-01T00:00:00Z',fields:rules,noticeVersionId:ids.notice,approvedByMembershipId:ids.member};
const profile={id:ids.profile,schoolId:ids.school,learnerId:ids.learner,version:1,firstName:null,lastName:null,contactEmail:null,contactPhone:null,birthDate:null,postalAddress:null,profilePhotoDocumentId:null,policyVersionId:ids.policy,updatedAt:'2026-01-01T00:00:00Z',enteredByMembershipId:ids.member,entrySource:'SELF'};
const learner={id:ids.learner,schoolId:ids.school,personId:ids.person,version:1,displayName:'Nom affiché non décomposé',contactEmail:null,contactPhone:null,archivedAt:null,profileReadiness:'MINIMAL'};
const apps:Awaited<ReturnType<typeof buildWebApp>>[]=[];
const body=()=>({kind:'PROFILE',schoolId:ids.school,learnerId:ids.learner,expectedVersion:1,payload:{policyVersionId:ids.policy,firstName:'Éléonore',lastName:'Test'}});
afterEach(async()=>{await Promise.all(apps.splice(0).map(app=>app.close()));});
async function harness() {
  let epoch=1;let role='LEARNER';let forbidden=false;
  let scopePause:(()=>Promise<void>)|undefined;
  const store=new SessionStore();const session=store.create();
  const tokens:Tokens={accessToken:'fixture-access-only',expiresAt:Date.now()+600_000,principal:{subject:randomUUID(),displayName:'Test',emailVerified:true}};
  session.tokens=tokens;
  const identity:IdentityProvider={begin:async()=>{throw new Error();},complete:async()=>tokens,refresh:async()=>tokens,revoke:async()=>{}};
  const writes:{path:string;body:unknown;options:ApiOptions|undefined}[]=[];
  let mutate:ApiGateway=async()=>({status:200,body:{data:{...profile,version:2,firstName:'Éléonore',lastName:'Test'}}});
  let proof:ApiGateway=async()=>({status:404,body:{code:'NOT_FOUND'}});
  const gateway:ApiGateway=async(path,token,value,options)=>{
    if(path==='/v1/me'&&scopePause){const pause=scopePause;scopePause=undefined;await pause();}
    if(path==='/v1/me')return {status:200,body:{data:{personId:ids.person,memberships:forbidden?[]:[{schoolId:ids.school,schoolName:'École test',membershipId:ids.member,accessEpoch:epoch,roles:[role],grants:[]}]}}};
    if(value!==undefined){writes.push({path,body:value,options});return mutate(path,token,value,options);}
    if(path.includes('/operations/'))return proof(path,token);
    if(path===`/v1/schools/${ids.school}`)return {status:200,body:{data:{id:ids.school,schoolId:ids.school,name:'École test',version:1,status:'ACTIVE'}}};
    if(path.includes('/data-policy'))return {status:200,body:{data:{noticeVersionId:ids.notice,status:'APPROVED',noticeText:'Notice de test',retentionText:'Conservation de test',version:1}}};
    if(path.includes('/profile-field-policies?'))return {status:200,body:{data:{items:[{...policy,status:role==='ADMIN'?'DRAFT':'PUBLISHED'}],nextCursor:null}}};
    if(path.endsWith('/administrative-profile'))return {status:200,body:{data:role==='INSTRUCTOR'?Object.fromEntries(Object.entries(profile).filter(([key])=>!['birthDate','postalAddress','profilePhotoDocumentId'].includes(key))):profile}};
    if(path.endsWith('/action-readiness?action=ENTER'))return {status:200,body:{data:{learnerId:ids.learner,action:'ENTER',resourceId:null,ready:false,blockers:[],policyVersionId:ids.policy,computedAt:'2026-01-01T00:00:00Z'}}};
    if(path===`/v1/schools/${ids.school}/learners/${ids.learner}`)return {status:200,body:{data:learner}};
    return {status:404,body:{code:'NOT_FOUND'}};
  };
  const commandStore=new TestMemoryCommandStore();
  const commandOwner={issuer:config.issuer,subject:tokens.principal.subject};
  const app=await buildWebApp({config,identity,store,gateway,commandStore});apps.push(app);
  const headers={cookie:`__Host-drivy-session=${session.id}`,origin:config.origin,'x-csrf-token':session.csrf};
  const post=(action:string,payload:unknown)=>app.inject({method:'POST',url:`/app/bff/profile-command/${action}`,headers,payload:payload as object});
  const prepare=async()=>{const response=await post('prepare',body());expect(response.statusCode).toBe(200);const {operationId,confirmation}=response.json().command as {operationId:string;confirmation:string};return {operationId,confirmation};};
  const pauseNextScope=()=>{
    let enter!:()=>void,release!:()=>void;const started=new Promise<void>(resolve=>{enter=resolve;}),wait=new Promise<void>(resolve=>{release=resolve;});
    scopePause=async()=>{enter();await wait;};return {started,release};
  };
  return {app,headers,post,prepare,session,commandStore,commandOwner,writes,pauseNextScope,setEpoch:(value:number)=>{epoch=value;},setRole:(value:string)=>{role=value;},revoke:()=>{forbidden=true;},setMutate:(value:ApiGateway)=>{mutate=value;},setProof:(value:ApiGateway)=>{proof=value;}};
}

test.each(['prepare','confirm','cancel'])('%s exige Origin et CSRF avant toute mutation',async action=>{
  const h=await harness();const response=await h.app.inject({method:'POST',url:`/app/bff/profile-command/${action}`,headers:{cookie:h.headers.cookie},payload:{}});
  expect(response.statusCode).toBe(403);expect(h.writes.length).toBe(0);
});
test('préparation sans effet, confirmation unique lie corps UUID et version',async()=>{
  const h=await harness();const command=await h.prepare();expect(h.writes.length).toBe(0);
  expect((await h.post('confirm',command)).statusCode).toBe(200);
  expect(h.writes).toHaveLength(1);expect(h.writes[0]?.body).toEqual({operationId:command.operationId,...body().payload});
  expect(h.writes[0]?.options).toEqual({method:'PATCH',expectedVersion:1});
});
test('réponse perdue après commit : AP72 confirme sans second envoi',async()=>{
  const h=await harness();const command=await h.prepare();h.setMutate(async()=>{throw new Error('Transport interrompu');});
  expect((await h.post('confirm',command)).statusCode).toBe(503);expect((await h.commandStore.find(h.commandOwner))?.state).toBe('UNCERTAIN');
  h.setProof(async()=>({status:200,body:{data:{operationId:command.operationId,commandType:'UPDATE_ADMINISTRATIVE_PROFILE'}}}));
  expect((await h.post('confirm',command)).statusCode).toBe(200);expect(h.writes).toHaveLength(1);
});
test('absence AP72 : reprise identique, puis 4xx ne détruit pas le résultat incertain',async()=>{
  const h=await harness();const command=await h.prepare();h.setMutate(async()=>({status:503,body:{code:'SERVICE_UNAVAILABLE'}}));
  expect((await h.post('confirm',command)).statusCode).toBe(503);
  h.setMutate(async()=>({status:409,body:{code:'VERSION_CONFLICT'}}));
  expect((await h.post('confirm',command)).statusCode).toBe(409);expect(h.writes).toHaveLength(2);expect(h.writes[1]).toEqual(h.writes[0]);
  expect((await h.commandStore.find(h.commandOwner))?.state).toBe('UNCERTAIN');expect((await h.post('cancel',command)).statusCode).toBe(409);
  expect((await h.post('prepare',body())).statusCode).toBe(409);
});
test('epoch modifiée interdit la reprise avant AP72 et toute émission',async()=>{
  const h=await harness();const command=await h.prepare();h.setMutate(async()=>{throw new Error();});await h.post('confirm',command);
  h.setEpoch(2);let looked=false;h.setProof(async()=>{looked=true;throw new Error();});
  const response=await h.post('confirm',command);expect(response.statusCode).toBe(409);expect(response.json().code).toBe('PROFILE_SCOPE_CHANGED');expect(looked).toBe(false);expect(h.writes).toHaveLength(1);
});
test('révocation masque aussi la demande conservée et le dossier',async()=>{
  const h=await harness();await h.prepare();h.revoke();
  const response=await h.app.inject({url:'/app/bff/profile-command',headers:h.headers});expect(response.statusCode).toBe(403);expect(response.body).not.toContain('Éléonore');
  expect((await h.app.inject({url:`/app/bff/schools/${ids.school}/learners/${ids.learner}/profile`,headers:h.headers})).statusCode).toBe(403);
});
test('ancienne confirmation interonglets ne peut pas envoyer une nouvelle intention',async()=>{
  const h=await harness();const old=await h.prepare();expect((await h.post('cancel',old)).statusCode).toBe(200);const next=await h.prepare();expect(next.operationId).not.toBe(old.operationId);
  expect((await h.post('confirm',old)).statusCode).toBe(409);expect(h.writes).toHaveLength(0);
});
test('annulation commencée avant confirmation ne supprime pas une émission devenue concurrente',async()=>{
  const h=await harness();const command=await h.prepare();const scope=h.pauseNextScope();
  const cancellation=h.post('cancel',command).then(response=>response);await scope.started;
  let entered!:()=>void,release!:()=>void;const sending=new Promise<void>(resolve=>{entered=resolve;}),wait=new Promise<void>(resolve=>{release=resolve;});
  h.setMutate(async()=>{entered();await wait;return {status:200,body:{data:{...profile,version:2}}};});
  const confirmation=h.post('confirm',command).then(response=>response);await sending;scope.release();
  expect((await cancellation).statusCode).toBe(409);expect((await h.commandStore.find(h.commandOwner))?.operationId).toBe(command.operationId);
  release();expect((await confirmation).statusCode).toBe(200);expect(h.writes).toHaveLength(1);
});
test('un moniteur ne peut modifier les noms même si les noms sont visibles',async()=>{
  const h=await harness();h.setRole('INSTRUCTOR');const response=await h.post('prepare',body());expect(response.statusCode).toBe(403);expect(response.json().code).toBe('PROFILE_FIELD_FORBIDDEN');expect(h.writes).toHaveLength(0);
  const response2=await h.post('prepare',{...body(),payload:{policyVersionId:ids.policy,contactPhone:'+41790000000'}});expect(response2.statusCode).toBe(200);
});
test('publication ADMIN explicite garde les règles affichées et refuse une autre école',async()=>{
  const h=await harness();h.setRole('ADMIN');const response=await h.post('prepare',{kind:'POLICY_PUBLISH',schoolId:ids.school,policyId:ids.policy,expectedVersion:1,payload:{}});
  expect(response.statusCode).toBe(200);expect(response.json().command.reviewPolicy.fields).toEqual(rules);expect(h.writes).toHaveLength(0);
  const foreign=await harness();expect((await foreign.post('prepare',{...body(),schoolId:randomUUID()})).statusCode).toBe(403);
});
test('schémas refusent champs arbitraires, photo requise et modification vide',()=>{
  expect(profilePayload.safeParse({policyVersionId:ids.policy}).success).toBe(false);
  expect(profilePayload.safeParse({policyVersionId:ids.policy,firstName:'Valide',displayName:'Ne pas découper'}).success).toBe(false);
  expect(fieldRule.safeParse({field:'profilePhotoDocumentId',requirement:'REQUIRED',stage:'JOIN',purposeCode:'IDENTIFICATION',explanation:'Interdit'}).success).toBe(false);
});
