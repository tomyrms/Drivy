import { afterEach,expect,test,vi } from 'vitest';
import { randomBytes,randomUUID } from 'node:crypto';
import { buildWebApp } from '../server/app.js';
import { SessionStore,type Tokens } from '../server/session.js';
import type { IdentityProvider } from '../server/oidc.js';
import { allowedOpeningRequest,type OpeningGateway,type OpeningRequest } from '../server/opening-routes.js';
import { createOpeningGateway } from '../server/upstream.js';

const config={origin:'https://drivy.example.invalid',apiBaseURL:'https://drivy.example.invalid/refonte',issuer:'https://identity.example.invalid/realm',clientId:'drivy-web',clientSecret:randomBytes(32).toString('hex'),development:false,host:'127.0.0.1',port:3002};
const apps:Awaited<ReturnType<typeof buildWebApp>>[]=[];
afterEach(async()=>{await Promise.all(apps.splice(0).map(app=>app.close()));vi.unstubAllGlobals();});
const secret=()=>randomBytes(32).toString('base64url');
const fields={schoolName:'École synthétique',displayName:'Responsable synthétique',contactEmail:'school@example.invalid',contactPhone:null,timeZone:'Europe/Zurich',instructs:true};
const receipt=(operationId:string)=>({schoolId:randomUUID(),schoolName:fields.schoolName,status:'DRAFT',membershipId:randomUUID(),roles:['ADMIN','INSTRUCTOR'],grants:['CONFIGURE_CATALOG'],accessEpoch:1,operationId,committedAt:new Date().toISOString()});
async function harness(openingGateway:OpeningGateway) {
  const now=Date.now(),store=new SessionStore();let subject='new-oidc-account';
  const tokens=():Tokens=>({accessToken:secret(),expiresAt:now+300_000,principal:{subject,displayName:'Responsable synthétique',email:'school@example.invalid',emailVerified:true}});
  const identity:IdentityProvider={begin:vi.fn(async()=>({transaction:{state:secret(),nonce:secret(),verifier:secret(),expiresAt:now+300_000},url:'https://identity.example.invalid/auth'})),complete:vi.fn(async()=>tokens()),refresh:vi.fn(async()=>tokens()),revoke:vi.fn(async()=>{})};
  const gateway=vi.fn(async()=>({status:403,body:{code:'IDENTITY_NOT_LINKED'}}));
  const app=await buildWebApp({config,identity,store,openingGateway,gateway});apps.push(app);
  let cookie='',csrf=(await app.inject({url:'/app/bff/session'})).json().csrfToken;
  const cookieFrom=(value:unknown)=>(Array.isArray(value)?value[0]:value)?.toString().split(';')[0]??'';
  const post=async(path:string,body:unknown,extra:Record<string,string>={})=>{
    const response=await app.inject({method:'POST',url:`/app/bff/${path}`,payload:body as never,headers:{cookie,origin:config.origin,'x-csrf-token':csrf,...extra}});
    if(response.headers['set-cookie']){cookie=cookieFrom(response.headers['set-cookie']);csrf=(await app.inject({url:'/app/bff/session',headers:{cookie}})).json().csrfToken;}return response;
  };
  const login=async(returnTo='/app/ouvrir')=>{const start=await post('login',{returnTo});expect(start.statusCode).toBe(200);const state=store.get(cookie.split('=')[1])!.login!.state;
    const response=await app.inject({url:`/app/bff/callback?code=synthetic&state=${state}`,headers:{cookie}});cookie=cookieFrom(response.headers['set-cookie']);csrf=(await app.inject({url:'/app/bff/session',headers:{cookie}})).json().csrfToken;return response;};
  return {app,post,login,store,gateway,identity,get:(path:string)=>app.inject({url:`/app/bff/${path}`,headers:{cookie}}),current:()=>store.get(cookie.split('=')[1])!,changeSubject:(value:string)=>{subject=value;}};
}

test('le fragment est retenu seulement en session BFF avant OIDC ; aucune dépendance à Person existante',async()=>{
  const api=vi.fn(async(command:OpeningRequest)=>({status:200,body:{data:command.path.endsWith('preview')?{status:'AVAILABLE',expiresAt:new Date().toISOString()}:{items:[]}}})),h=await harness(api),token=secret();
  const parked=await h.post('opening',{token});expect(parked.statusCode).toBe(200);expect(parked.body.includes(token)).toBe(false);
  const callback=await h.login();expect(callback.headers.location).toBe('/app/ouvrir');expect(h.current().opening?.token===token).toBe(true);
  expect((await h.post('opening/preview',{})).statusCode).toBe(200);expect(h.gateway).not.toHaveBeenCalled();
  const state=await h.get('opening');expect(state.body.includes(token)).toBe(false);expect(state.json()).toEqual({pending:true,uncertain:false});
  expect((h.identity.begin as ReturnType<typeof vi.fn>).mock.calls.some(call=>JSON.stringify(call).includes(token))).toBe(false);
});
test('GET et session anonymes ne créent ou ne consomment aucune école ; CSRF, origine et connexion exigés',async()=>{
  const api=vi.fn(async()=>({status:200,body:{data:{items:[]}}})),h=await harness(api);
  expect(h.store.size).toBe(0);expect((await h.get('opening')).statusCode).toBe(401);expect((await h.get('operator/school-opening-links')).statusCode).toBe(401);
  expect((await h.post('opening',{token:secret()},{origin:'https://foreign.example.invalid'})).statusCode).toBe(403);expect(h.store.size).toBe(0);
  await h.login();expect((await h.post('opening/create',fields,{'x-csrf-token':'wrong'})).statusCode).toBe(403);expect(api).not.toHaveBeenCalled();
  expect((await h.post('login',{returnTo:'https://foreign.example.invalid'})).statusCode).toBe(400);
});
test('résultat perdu : charge et UUID conservés, modification refusée, renvoi identique et secret effacé après confirmation',async()=>{
  let first=true,result:ReturnType<typeof receipt>|undefined;const writes:OpeningRequest[]=[];
  const h=await harness(async command=>{writes.push(structuredClone(command));result??=receipt(command.idempotencyKey!);if(first){first=false;throw new Error('synthetic_network_loss');}return {status:201,body:{data:result}};});
  const token=secret();await h.post('opening',{token});await h.login();
  expect((await h.post('opening/create',fields)).statusCode).toBe(503);expect(h.current().opening?.uncertain).toBe(true);
  expect((await h.get('opening')).json()).toMatchObject({pending:true,uncertain:true,draft:fields});
  expect((await h.post('opening/create',{...fields,schoolName:'Autre nom'})).json().code).toBe('OPENING_IN_PROGRESS');expect(writes).toHaveLength(1);
  expect((await h.post('opening',{token:secret()})).json().code).toBe('OPENING_IN_PROGRESS');
  const retry=await h.post('opening/create',fields);expect(retry.statusCode).toBe(201);expect(JSON.stringify(writes[0])===JSON.stringify(writes[1])).toBe(true);
  expect(h.current().opening?.token).toBeUndefined();expect(h.current().opening?.body).toBeUndefined();expect(h.current().opening?.result?.schoolId).toBe(result!.schoolId);
});
test('un premier refus métier libère la saisie ; un refus après réponse perdue conserve l’intention',async()=>{
  const h=await harness(async()=>({status:410,body:{code:'OPENING_LINK_EXPIRED'}}));await h.post('opening',{token:secret()});await h.login();
  expect((await h.post('opening/create',fields)).json().code).toBe('OPENING_LINK_EXPIRED');expect(h.current().opening?.submitted).toBeUndefined();expect(h.current().opening?.uncertain).toBeUndefined();
  let step=0;const uncertain=await harness(async()=>{if(step++===0)throw new Error('synthetic_network_loss');return {status:410,body:{code:'OPENING_LINK_EXPIRED'}};});
  await uncertain.post('opening',{token:secret()});await uncertain.login();await uncertain.post('opening/create',fields);await uncertain.post('opening/create',fields);
  expect(uncertain.current().opening?.submitted).toBe(true);expect(uncertain.current().opening?.uncertain).toBe(true);expect(uncertain.current().opening?.body).toEqual(fields);
});
test('récupération par opération : 404 ne signifie pas annulation ; succès retire le secret',async()=>{
  let recover=false;const h=await harness(async command=>{if(command.method==='POST')throw new Error('synthetic_loss');return recover?{status:200,body:{data:receipt(command.path.split('/').at(-1)!)}}:{status:404,body:{code:'NOT_FOUND'}};});
  await h.post('opening',{token:secret()});await h.login();await h.post('opening/create',fields);
  expect((await h.get('opening/result')).statusCode).toBe(404);expect(h.current().opening?.submitted).toBe(true);recover=true;
  expect((await h.get('opening/result')).statusCode).toBe(200);expect(h.current().opening?.token).toBeUndefined();
});
test('un autre compte OIDC ne peut pas rejouer une intention incertaine',async()=>{
  const api=vi.fn(async()=>{throw new Error('synthetic_loss');}),h=await harness(api);await h.post('opening',{token:secret()});await h.login();await h.post('opening/create',fields);
  h.changeSubject('another-account');await h.login();expect((await h.post('opening/create',fields)).json().code).toBe('OPENING_IDENTITY_CHANGED');expect(api).toHaveBeenCalledTimes(1);
});

test('un reçu conservé relit activation et révocation avant chaque restitution au navigateur',async()=>{
  const result=receipt(randomUUID());let active=false,revoked=false;
  const api=vi.fn(async(command:OpeningRequest)=>{
    if(command.method==='POST')return {status:201,body:{data:result}};
    expect(command.path).toBe(`/v1/school-openings/operations/${result.operationId}`);
    return revoked?{status:403,body:{code:'FORBIDDEN'}}:{status:200,body:{data:{...result,status:active?'ACTIVE':'DRAFT'}}};
  });
  const h=await harness(api);await h.post('opening',{token:secret()});await h.login();await h.post('opening/create',fields);
  expect(h.current().opening!.operationId).not.toBe(result.operationId);active=true;
  expect((await h.get('opening')).json().result.status).toBe('ACTIVE');
  expect((await h.post('opening/preview',{})).json().data.school.status).toBe('ACTIVE');
  expect((await h.post('opening/create',fields)).json().data.status).toBe('ACTIVE');
  expect((await h.get('opening/result')).json().data.status).toBe('ACTIVE');
  revoked=true;
  for(const response of [await h.get('opening'),await h.post('opening/preview',{}),await h.post('opening/create',fields),await h.get('opening/result')]){
    expect(response.statusCode).toBe(403);expect(response.body.includes(result.schoolId)).toBe(false);
  }
  expect(api.mock.calls.filter(([command])=>command.method==='POST')).toHaveLength(1);
  expect(api.mock.calls.filter(([command])=>command.method==='GET')).toHaveLength(8);
});

test('un autre compte OIDC ne voit aucun reçu confirmé ni données du premier compte',async()=>{
  const result=receipt(randomUUID()),api=vi.fn(async()=>({status:201,body:{data:result}})),h=await harness(api);
  await h.post('opening',{token:secret()});await h.login();await h.post('opening/create',fields);h.changeSubject('another-account');await h.login();
  for(const response of [await h.get('opening'),await h.post('opening/preview',{}),await h.post('opening/create',fields),await h.get('opening/result')]){
    expect(response.statusCode).toBe(409);expect(response.json().code).toBe('OPENING_IDENTITY_CHANGED');expect(response.body.includes(result.schoolId)).toBe(false);
  }
  expect(api).toHaveBeenCalledTimes(1);
});
test('la page opérateur reçoit le refus serveur même si le navigateur possède une session',async()=>{
  const h=await harness(async()=>({status:403,body:{code:'OPERATOR_REQUIRED'}}));expect((await h.login('/app/operateur')).headers.location).toBe('/app/operateur');
  expect((await h.get('operator/school-opening-links')).json().code).toBe('OPERATOR_REQUIRED');
  expect((await h.post('operator/school-opening-links',{operationId:randomUUID()})).json().code).toBe('OPERATOR_REQUIRED');
});
test('opérateur : même secret et opération sur nouvelle tentative ; liste sans lien secret, récupération après rechargement',async()=>{
  const writes:OpeningRequest[]=[],linkId=randomUUID(),row={id:linkId,status:'AVAILABLE',createdAt:new Date().toISOString(),expiresAt:new Date().toISOString(),usedAt:null,revokedAt:null};
  const h=await harness(async command=>{if(command.method==='GET')return {status:200,body:{data:{items:[row]}}};writes.push(command);if(writes.length===1)throw new Error('synthetic_loss');return {status:201,body:{data:row}};});
  await h.login('/app/operateur');const operationId=randomUUID();expect((await h.post('operator/school-opening-links',{operationId})).statusCode).toBe(503);
  await h.login('/app/operateur');
  const listing=await h.get('operator/school-opening-links');expect(listing.json().pendingOperationId).toBe(operationId);expect(listing.body.includes(h.current().operatorOpening!.token)).toBe(false);
  const retried=await h.post('operator/school-opening-links',{operationId});expect(retried.statusCode).toBe(200);expect(JSON.stringify(writes[0])===JSON.stringify(writes[1])).toBe(true);
  expect(new URL(retried.json().link).pathname).toBe('/app/ouvrir');expect(new URL(retried.json().link).search).toBe('');
});

test('changer d’opérateur retire son intention et ne réutilise ni UUID ni secret du compte précédent',async()=>{
  const writes:OpeningRequest[]=[],row={id:randomUUID(),status:'AVAILABLE',createdAt:new Date().toISOString(),expiresAt:new Date().toISOString(),usedAt:null,revokedAt:null};
  const h=await harness(async command=>{if(command.method==='GET')return {status:200,body:{data:{items:[row]}}};writes.push(structuredClone(command));return {status:201,body:{data:row}};});
  await h.login('/app/operateur');await h.post('operator/school-opening-links',{operationId:randomUUID()});
  const prior=h.current().operatorOpening!;h.changeSubject('another-operator');await h.login('/app/operateur');
  expect(h.current().operatorOpening).toBeUndefined();expect((await h.get('operator/school-opening-links')).json().pendingOperationId).toBeUndefined();
  await h.post('operator/school-opening-links',{operationId:randomUUID()});const current=h.current().operatorOpening!;
  expect(current.operationId).not.toBe(prior.operationId);expect(current.token).not.toBe(prior.token);expect(writes).toHaveLength(2);
});
test('aucun autre chemin, méthode ou query ne peut recevoir un jeton OIDC via le relais ouverture',async()=>{
  expect(allowedOpeningRequest({method:'GET',path:'/v1/operator/school-opening-links'})).toBe(true);
  for(const path of ['/v1/me','/v1/operator/school-opening-links?token=secret','https://foreign.example.invalid/v1/school-openings','/v1/school-openings/../me'])expect(allowedOpeningRequest({method:'GET',path})).toBe(false);
  const fetchMock=vi.fn(async(_input:string|URL|Request)=>new Response(JSON.stringify({data:{items:[]}}),{status:200,headers:{'content-type':'application/json'}}));vi.stubGlobal('fetch',fetchMock);
  const gateway=createOpeningGateway('https://api.example.invalid');await expect(gateway({method:'GET',path:'/v1/me'},secret())).rejects.toThrow();expect(fetchMock).not.toHaveBeenCalled();
  await gateway({method:'GET',path:'/v1/operator/school-opening-links'},secret());expect(fetchMock.mock.calls[0]?.[0]).toBe('https://api.example.invalid/v1/operator/school-opening-links');
});
