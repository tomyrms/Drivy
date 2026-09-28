import { z } from 'zod';
import { id, policyPayload, profilePayload, version } from './profile-contract.js';
export type ApiResult = { status:number; body:unknown };
export type ApiOptions = { method?:'GET'|'POST'|'PATCH'; expectedVersion?:number };
export type ApiGateway = (path:string,accessToken:string,body?:unknown,options?:ApiOptions)=>Promise<ApiResult>;
const uuid='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';
const root=`/v1/schools/(${uuid})`;
const pagination=z.object({limit:z.coerce.number().int().min(1).max(100).optional(),cursor:z.string().min(1).max(6000).optional()}).strict();
function allowed(path:string,body:unknown,options:ApiOptions) {
  const url=new URL(path,'https://api.invalid');
  if (!path.startsWith('/v1/') || url.origin!=='https://api.invalid' || url.hash || url.pathname.includes('%') || url.pathname.includes('..') || path.split('?')[0]!==url.pathname) throw new Error('Route non autorisée');
  const query=Object.fromEntries(url.searchParams);
  if (url.searchParams.size!==Object.keys(query).length) throw new Error('Paramètre dupliqué');
  const method=options.method??(body===undefined?'GET':'POST');
  const route=(suffix:string)=>new RegExp(`^${root}${suffix}$`).test(url.pathname);
  if (method==='GET' && body===undefined) {
    if (path==='/v1/me') return method;
    if (route('/learners') || route('/profile-field-policies')) {pagination.parse(query);return method;}
    if (route(`/learners/(${uuid})/action-readiness`)) {z.object({action:z.enum(['ENTER','PLAN_LESSON','ENROLL_COURSE'])}).strict().parse(query);return method;}
    if (route('/data-policy')) {z.object({noticeVersionId:id.optional()}).strict().parse(query);return method;}
    if (route('') || route(`/learners/(${uuid})`) || route(`/learners/(${uuid})/administrative-profile`) || route(`/operations/(${uuid})`)) {z.object({}).strict().parse(query);return method;}
  }
  if (!url.search && method==='POST' && path==='/v1/invitations/preview') {z.object({token:z.string().min(32).max(256)}).strict().parse(body);return method;}
  if (!url.search && method==='POST' && path==='/v1/invitations/accept') {z.object({operationId:id,token:z.string().min(32).max(256)}).strict().parse(body);return method;}
  if (!url.search && method==='POST' && route('/profile-field-policies')) {
    const {operationId:_,...payload}=z.object({operationId:id}).passthrough().parse(body);
    policyPayload.parse(payload);version.parse(options.expectedVersion);return method;
  }
  if (!url.search && method==='POST' && route(`/profile-field-policies/(${uuid})/publish`)) {z.object({operationId:id}).strict().parse(body);version.parse(options.expectedVersion);return method;}
  if (!url.search && method==='PATCH' && route(`/learners/(${uuid})/administrative-profile`)) {
    const {operationId:_,...payload}=z.object({operationId:id}).passthrough().parse(body);
    profilePayload.parse(payload);version.parse(options.expectedVersion);return method;
  }
  throw new Error('Route API non autorisée');
}
export function createGateway(baseURL:string):ApiGateway {
  return async(path,accessToken,body,options={})=>{
    const method=allowed(path,body,options);
    const response=await fetch(baseURL+path,{method,redirect:'error',signal:AbortSignal.timeout(15_000),
      headers:{Authorization:`Bearer ${accessToken}`,Accept:'application/json',...(body===undefined?{}:{'Content-Type':'application/json'}),
        ...(body && typeof body==='object' && 'operationId' in body?{'Idempotency-Key':String(body.operationId)}:{}),
        ...(options.expectedVersion===undefined?{}:{'If-Match':`"${options.expectedVersion}"`})},
      ...(body===undefined?{}:{body:JSON.stringify(body)})});
    if (!response.body) throw new Error('Réponse API absente');
    const chunks:Uint8Array[]=[];let size=0;
    for await(const chunk of response.body) {size+=chunk.byteLength;if(size>1024*1024)throw new Error('Réponse trop grande');chunks.push(chunk);}
    return {status:response.status,body:JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown};
  };
}
