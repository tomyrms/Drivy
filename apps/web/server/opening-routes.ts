import { randomBytes, randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';
import type { Session } from './session.js';
import type { ApiResult } from './upstream.js';

export type OpeningRequest={method:'GET'|'POST';path:string;body?:unknown;idempotencyKey?:string};
export type OpeningGateway=(command:OpeningRequest,accessToken:string)=>Promise<ApiResult>;
export function allowedOpeningRequest(request:OpeningRequest):boolean {
  if(request.method==='GET')return request.body===undefined && (request.path==='/v1/operator/school-opening-links' || /^\/v1\/school-openings\/operations\/[0-9a-f-]{36}$/.test(request.path));
  if(request.method!=='POST')return false;
  if(request.path==='/v1/school-openings/preview')return true;
  return (request.path==='/v1/operator/school-opening-links' || request.path==='/v1/school-openings' || /^\/v1\/operator\/school-opening-links\/[0-9a-f-]{36}\/revoke$/.test(request.path))
    && typeof request.idempotencyKey==='string' && z.uuid().safeParse(request.idempotencyKey).success;
}
const empty=z.object({}).strict();
const tokenSchema=z.string().regex(/^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/);
const fields=z.object({schoolName:z.string().trim().min(1).max(150),displayName:z.string().trim().min(1).max(200),
  contactEmail:z.email().max(254),contactPhone:z.string().trim().min(1).max(50).nullable(),timeZone:z.string().min(1).max(100),instructs:z.boolean()}).strict();
export type OpeningFields=z.infer<typeof fields>;
export const openingResult=z.object({data:z.object({schoolId:z.uuid(),schoolName:z.string(),status:z.enum(['DRAFT','ACTIVE','ARCHIVED']),
  membershipId:z.uuid(),roles:z.array(z.string()),grants:z.array(z.string()),accessEpoch:z.number().int().positive(),operationId:z.uuid(),committedAt:z.iso.datetime({offset:true})})});
const linkResult=z.object({data:z.object({id:z.uuid(),status:z.enum(['AVAILABLE','USED','REVOKED','EXPIRED']),createdAt:z.iso.datetime({offset:true}),expiresAt:z.iso.datetime({offset:true}),usedAt:z.string().nullable(),revokedAt:z.string().nullable()})});
export type OpeningReceipt=z.infer<typeof openingResult>['data'];
export type OpeningState={token?:string;operationId:string;body?:OpeningFields;principal?:string;submitted?:boolean;uncertain?:boolean;busy?:boolean;result?:OpeningReceipt};
export type OperatorOpeningState={operationId:string;token:string;busy?:boolean};

export function registerOpeningRoutes(app:FastifyInstance,deps:{origin:string;current:(req:FastifyRequest)=>Session;
  protect:(req:FastifyRequest)=>Session;admit:(req:FastifyRequest)=>Session|null;open:(reply:FastifyReply,session:Session|null)=>Session;
  call:(session:Session,command:OpeningRequest)=>Promise<ApiResult>;send:(reply:FastifyReply,result:ApiResult)=>unknown;
  error:(status:number,code:string)=>Error}) {
  const requireOpening=(session:Session)=>{if(!session.opening)throw deps.error(404,'OPENING_LINK_MISSING');return session.opening;};
  const scope=(session:Session,opening:OpeningState)=>{
    if(!session.tokens)throw deps.error(401,'SESSION_EXPIRED');
    if(opening.principal && opening.principal!==session.tokens.principal.subject)throw deps.error(409,'OPENING_IDENTITY_CHANGED');
  };
  const confirm=(opening:OpeningState,result:ApiResult)=>{
    const parsed=openingResult.safeParse(result.body);
    if(result.status>=200 && result.status<300 && parsed.success){opening.result=parsed.data.data;delete opening.token;delete opening.body;delete opening.uncertain;}
    else if(result.status>=500 || (result.status<400 && !parsed.success))opening.uncertain=true;
    return parsed;
  };
  app.post('/app/bff/opening',async(request,reply)=>{
    const admitted=deps.admit(request);empty.parse(request.query);const {token}=z.object({token:tokenSchema}).strict().parse(request.body);
    const session=deps.open(reply,admitted),previous=session.opening;
    if(previous?.token===token)return {ok:true};
    if(previous?.busy || (previous?.submitted && !previous.result))throw deps.error(409,'OPENING_IN_PROGRESS');
    session.opening={token,operationId:randomUUID()};return {ok:true};
  });
  app.get('/app/bff/opening',async request=>{
    empty.parse(request.query);const session=deps.current(request),opening=requireOpening(session);scope(session,opening);
    return {pending:!opening.result,uncertain:!!opening.uncertain,...(opening.body?{draft:opening.body}:{}),...(opening.result?{result:opening.result}:{})};
  });
  app.post('/app/bff/opening/preview',async(request,reply)=>{
    empty.parse(request.query);empty.parse(request.body);const session=deps.protect(request),opening=requireOpening(session);scope(session,opening);
    if(opening.result)return {data:{status:'USED',school:opening.result}};
    if(!opening.token)throw deps.error(404,'OPENING_LINK_MISSING');
    return deps.send(reply,await deps.call(session,{method:'POST',path:'/v1/school-openings/preview',body:{token:opening.token}}));
  });
  app.post('/app/bff/opening/create',async(request,reply)=>{
    empty.parse(request.query);const body=fields.parse(request.body),session=deps.protect(request),opening=requireOpening(session);scope(session,opening);
    if(opening.result)return {data:opening.result};
    if(opening.busy)throw deps.error(409,'OPENING_IN_PROGRESS');
    if(!opening.token)throw deps.error(404,'OPENING_LINK_MISSING');
    if(opening.submitted && JSON.stringify(opening.body)!==JSON.stringify(body))throw deps.error(409,'OPENING_IN_PROGRESS');
    opening.body ??= body;opening.principal=session.tokens!.principal.subject;opening.busy=true;opening.submitted=true;
    try {
      const result=await deps.call(session,{method:'POST',path:'/v1/school-openings',body:{...opening.body,token:opening.token,operationId:opening.operationId},idempotencyKey:opening.operationId});
      const parsed=confirm(opening,result);
      if(result.status>=400 && result.status<500 && !opening.uncertain){delete opening.submitted;delete opening.body;delete opening.principal;}
      if(result.status<400 && !parsed.success)throw deps.error(503,'INVALID_RESPONSE');
      return deps.send(reply,result);
    } catch(error){if(opening.submitted)opening.uncertain=true;throw error;}finally{delete opening.busy;}
  });
  app.get('/app/bff/opening/result',async(request,reply)=>{
    empty.parse(request.query);const session=deps.current(request),opening=requireOpening(session);scope(session,opening);
    if(opening.result)return {data:opening.result};
    const result=await deps.call(session,{method:'GET',path:`/v1/school-openings/operations/${opening.operationId}`});
    const parsed=confirm(opening,result);if(result.status<400 && !parsed.success)throw deps.error(503,'INVALID_RESPONSE');
    return deps.send(reply,result);
  });
  app.get('/app/bff/operator/school-opening-links',async(request,reply)=>{
    empty.parse(request.query);const session=deps.current(request);
    const response=await deps.call(session,{method:'GET',path:'/v1/operator/school-opening-links'});
    if(response.status>=400)return deps.send(reply,response);
    return {...z.object({data:z.object({items:z.array(linkResult.shape.data)})}).parse(response.body),...(session.operatorOpening?{pendingOperationId:session.operatorOpening.operationId}:{})};
  });
  app.post('/app/bff/operator/school-opening-links',async(request,reply)=>{
    empty.parse(request.query);const {operationId}=z.object({operationId:z.uuid()}).strict().parse(request.body);const session=deps.protect(request);
    const previous=session.operatorOpening;
    if(previous && previous.operationId!==operationId)throw deps.error(409,'OPENING_IN_PROGRESS');
    const command=previous ?? {operationId,token:randomBytes(32).toString('base64url')};session.operatorOpening=command;
    if(command.busy)throw deps.error(409,'OPENING_IN_PROGRESS');command.busy=true;
    try {
      const result=await deps.call(session,{method:'POST',path:'/v1/operator/school-opening-links',body:{operationId,token:command.token},idempotencyKey:operationId});
      if(result.status>=400)return deps.send(reply,result);
      const parsed=linkResult.parse(result.body);
      return {...parsed,link:`${deps.origin}/app/ouvrir#token=${command.token}`};
    }finally{delete command.busy;}
  });
  app.post('/app/bff/operator/school-opening-links/clear',async request=>{
    empty.parse(request.query);empty.parse(request.body);const session=deps.protect(request);
    if(session.operatorOpening?.busy)throw deps.error(409,'OPENING_IN_PROGRESS');delete session.operatorOpening;return {ok:true};
  });
  app.post('/app/bff/operator/school-opening-links/:linkId/revoke',async(request,reply)=>{
    empty.parse(request.query);const {linkId}=z.object({linkId:z.uuid()}).parse(request.params);
    const body=z.object({operationId:z.uuid()}).strict().parse(request.body);
    return deps.send(reply,await deps.call(deps.protect(request),{method:'POST',path:`/v1/operator/school-opening-links/${linkId}/revoke`,body,idempotencyKey:body.operationId}));
  });
}
