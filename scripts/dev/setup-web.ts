import { randomBytes } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { z } from 'zod';
import { keycloakOrigin,loadRuntime,localFetch,protectStateDirectory,secretFile,stateDirectory } from './shared.js';

const savedSchema=z.object({clientSecret:z.string().min(32),outboxKey:z.string().regex(/^[0-9a-f]{64}$/)}).strict();
async function main() {
  await protectStateDirectory();const runtime=await loadRuntime();
  const login=await localFetch(`${keycloakOrigin}/realms/master/protocol/openid-connect/token`,{method:'POST',body:new URLSearchParams({
    grant_type:'password',client_id:'admin-cli',username:runtime.adminUsername,password:runtime.adminPassword})});
  if(!login.ok)throw new Error('Administration locale indisponible.');
  const {access_token}=z.object({access_token:z.string()}).parse(await login.json());
  const admin=(path:string,init:RequestInit={})=>localFetch(`${keycloakOrigin}/admin/realms/drivy-dev/${path}`,{
    ...init,headers:{'Content-Type':'application/json',Authorization:`Bearer ${access_token}`}});
  const clients=await admin('clients?clientId=drivy-web');
  if(!clients.ok)throw new Error('Lecture client local refusée.');
  const existing=z.array(z.object({id:z.string()}).passthrough()).parse(await clients.json());
  let saved:z.infer<typeof savedSchema>;
  try {saved=savedSchema.parse(JSON.parse(await readFile(new URL('web-runtime.json',stateDirectory),'utf8')));}
  catch(error) {
    if(!(error instanceof Error) || !('code' in error) || error.code!=='ENOENT' || existing.length)throw new Error('État web existant incohérent, aucune clé remplacée.');
    saved={clientSecret:randomBytes(32).toString('base64url'),outboxKey:randomBytes(32).toString('hex')};
    await secretFile('web-runtime.json',saved);
  }
  const client={clientId:'drivy-web',name:'Drivy web · Essai local',enabled:true,protocol:'openid-connect',
    clientAuthenticatorType:'client-secret',secret:saved.clientSecret,publicClient:false,standardFlowEnabled:true,
    directAccessGrantsEnabled:false,implicitFlowEnabled:false,serviceAccountsEnabled:false,fullScopeAllowed:false,
    redirectUris:['http://127.0.0.1:3002/app/bff/callback'],webOrigins:[],
    attributes:{'pkce.code.challenge.method':'S256'},defaultClientScopes:['basic','profile','email'],optionalClientScopes:[],
    protocolMappers:[{name:'drivy-api-audience',protocol:'openid-connect',protocolMapper:'oidc-audience-mapper',consentRequired:false,
      config:{'included.custom.audience':'drivy-api','id.token.claim':'false','access.token.claim':'true','introspection.token.claim':'true'}}]};
  if(existing.length>1)throw new Error('Client web dupliqué.');
  if(existing[0]) {
    const secret=await admin(`clients/${existing[0].id}/client-secret`);
    const actual=z.object({value:z.string()}).parse(await secret.json());
    if(actual.value!==saved.clientSecret)throw new Error('Secret local différent, aucun remplacement.');
    const response=await admin(`clients/${existing[0].id}`,{method:'PUT',body:JSON.stringify(client)});
    if(!response.ok)throw new Error('Configuration du client web refusée.');
  } else if(!(await admin('clients',{method:'POST',body:JSON.stringify(client)})).ok)throw new Error('Création du client web refusée.');
  const appleResponse=await admin('clients?clientId=drivy-apple');
  const apple=z.array(z.object({id:z.string(),publicClient:z.literal(true),defaultClientScopes:z.array(z.string())}).passthrough()).parse(await appleResponse.json());
  if(apple.length!==1)throw new Error('Client Apple absent.');
  if(!(await admin(`clients/${apple[0]!.id}`,{method:'PUT',body:JSON.stringify({...apple[0],defaultClientScopes:['basic','profile','email']})})).ok) {
    throw new Error('Scope email Apple local refusé.');
  }
  const realm=await localFetch(`${keycloakOrigin}/admin/realms/drivy-dev`,{method:'PUT',
    headers:{'Content-Type':'application/json',Authorization:`Bearer ${access_token}`},
    body:JSON.stringify({registrationAllowed:true,verifyEmail:true,smtpServer:{host:'mailpit',port:'1025',
      from:'no-reply@drivy.example.invalid',fromDisplayName:'Drivy · Essai local',auth:'false',ssl:'false',starttls:'false'}})});
  if(!realm.ok)throw new Error('Configuration identité/email locale refusée.');
  console.log('Client web confidentiel PKCE prêt. Email vérifié requis ; SMTP capturé uniquement par Mailpit local.');
}
main().catch(()=>{console.error('Préparation web locale interrompue ; aucun secret affiché. Vérifier le provisionnement initial.');process.exitCode=1;});
