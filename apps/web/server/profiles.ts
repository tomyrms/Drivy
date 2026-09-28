import { randomBytes } from 'node:crypto';
import type { FastifyInstance,FastifyRequest } from 'fastify';
import { z } from 'zod';
import { type Session } from './session.js';
import {digest} from './command-crypto.js';
import type {CommandStore,CommandRecord,CommandOwner} from './command-store.js';
import type { ApiOptions,ApiResult } from './upstream.js';
import * as c from './profile-contract.js';

export class WebError extends Error { constructor(readonly status:number,readonly code:string) {super(code);} }
const empty=z.object({}).strict();
const pagination=z.object({cursor:z.string().min(1).max(6000).optional()}).strict();
const result=(response:ApiResult)=>{
  if(response.status>=400) {const problem=z.object({code:z.string().regex(/^[A-Z0-9_]{1,80}$/)}).safeParse(response.body);throw new WebError(response.status,problem.success?problem.data.code:'API_UNAVAILABLE');}
  return response.body;
};
const routes=(request:c.Prepare)=>{
  const base=`/v1/schools/${request.schoolId}`;
  if(request.kind==='PROFILE')return {path:`${base}/learners/${request.learnerId}/administrative-profile`,method:'PATCH' as const,type:'UPDATE_ADMINISTRATIVE_PROFILE'};
  if(request.kind==='POLICY_CREATE')return {path:`${base}/profile-field-policies`,method:'POST' as const,type:'CREATE_PROFILE_FIELD_POLICY'};
  return {path:`${base}/profile-field-policies/${request.policyId}/publish`,method:'POST' as const,type:'PUBLISH_PROFILE_FIELD_POLICY'};
};
export function registerProfiles(app:FastifyInstance,deps:{current:(request:FastifyRequest)=>Session;protect:(request:FastifyRequest)=>Session;
  issuer:string;commands:CommandStore;ensureCurrent:(session:Session)=>void;
  call:(session:Session,path:string,body?:unknown,options?:ApiOptions)=>Promise<ApiResult>}) {
  const read=async<T extends z.ZodType>(session:Session,path:string,schema:T)=>schema.parse(result(await deps.call(session,path)));
  const scope=async(session:Session,schoolId:string)=>{
    const data=(await read(session,'/v1/me',c.me)).data;const member=data.memberships.find(item=>item.schoolId===schoolId);
    if(!member)throw new WebError(403,'ACCESS_REVOKED');return {...member,personId:data.personId};
  };
  const policies=async(session:Session,schoolId:string)=>{
    const items:z.infer<typeof c.policy>[]=[];let cursor:string|null=null;
    // Find a displayed version across pages, never silently choose an unrelated one.
    for(let count=0;count<100;count++) {
      const data:{items:c.Policy[];nextCursor:string|null}=(await read(session,`/v1/schools/${schoolId}/profile-field-policies?limit=100${cursor?`&cursor=${encodeURIComponent(cursor)}`:''}`,c.page(c.policy))).data;
      items.push(...data.items);if(!data.nextCursor)return items;if(data.nextCursor===cursor)break;cursor=data.nextCursor;
    }
    throw new WebError(503,'POLICY_PAGE_INCOMPLETE');
  };
  const profile=async(session:Session,schoolId:string,learnerId:string)=>{
    const context=await scope(session,schoolId);const base=`/v1/schools/${schoolId}/learners/${learnerId}`;
    const pupil=(await read(session,base,c.envelope(c.learner))).data;
    const data=(await read(session,`${base}/administrative-profile`,c.envelope(c.profile))).data;
    const policy=(await policies(session,schoolId)).find(item=>item.id===data.policyVersionId&&item.status==='PUBLISHED');
    if(!policy)throw new WebError(409,'PROFILE_POLICY_CHANGED');
    const readiness=(await read(session,`${base}/action-readiness?action=ENTER`,c.envelope(c.readiness))).data;
    if(pupil.schoolId!==schoolId||data.schoolId!==schoolId||data.learnerId!==learnerId||readiness.learnerId!==learnerId)throw new WebError(503,'INVALID_RESPONSE');
    const all=context.roles.includes('ADMIN') || context.roles.includes('LEARNER') && pupil.personId===context.personId;
    const editableFields=all?c.field.options.filter(field=>field in data):['contactEmail','contactPhone'].filter(field=>field in data);
    return c.profileView.parse({scope:context,learner:pupil,profile:data,policy,readiness,editableFields});
  };
  const owner=(session:Session):CommandOwner=>{deps.ensureCurrent(session);return {issuer:deps.issuer,subject:session.tokens!.principal.subject};};
  const bound=async(session:Session,intent:CommandRecord)=>{
    const current=await scope(session,intent.request.schoolId);
    if(current.personId!==intent.personId||current.membershipId!==intent.membershipId||current.accessEpoch!==intent.accessEpoch)throw new WebError(409,'PROFILE_SCOPE_CHANGED');
    if(intent.request.kind!=='PROFILE'&&!current.roles.includes('ADMIN'))throw new WebError(403,'ACCESS_REVOKED');
    if(intent.request.kind==='PROFILE') {
      const data=await profile(session,intent.schoolId,intent.request.learnerId);
      if(Object.keys(intent.request.payload).some(field=>field!=='policyVersionId'&&!data.editableFields.includes(field as c.Field)))throw new WebError(403,'PROFILE_FIELD_FORBIDDEN');
    }
    deps.ensureCurrent(session);
    return current;
  };
  const snapshot=async(session:Session,request:c.Prepare)=>{
    const current=await scope(session,request.schoolId);
    let reviewPolicy:c.Policy|undefined;
    let reviewNotice:z.infer<typeof c.notice>|undefined;
    if(request.kind==='PROFILE') {
      const currentProfile=await profile(session,request.schoolId,request.learnerId);
      if(currentProfile.profile.version!==request.expectedVersion)throw new WebError(409,'VERSION_CONFLICT');
      if(currentProfile.profile.policyVersionId!==request.payload.policyVersionId)throw new WebError(409,'PROFILE_POLICY_CHANGED');
      if(Object.keys(request.payload).some(field=>field!=='policyVersionId'&&!currentProfile.editableFields.includes(field as c.Field)))throw new WebError(403,'PROFILE_FIELD_FORBIDDEN');
    } else {
      if(!current.roles.includes('ADMIN'))throw new WebError(403,'ACCESS_REVOKED');
      if(request.kind==='POLICY_CREATE') {
        const school=(await read(session,`/v1/schools/${request.schoolId}`,c.envelope(c.school))).data;
        if(school.version!==request.expectedVersion)throw new WebError(409,'VERSION_CONFLICT');
        const notice=(await read(session,`/v1/schools/${request.schoolId}/data-policy?noticeVersionId=${request.payload.noticeVersionId}`,c.envelope(c.notice))).data;
        if(notice.status!=='APPROVED'||notice.noticeVersionId!==request.payload.noticeVersionId)throw new WebError(409,'PROFILE_POLICY_CHANGED');
        reviewNotice=notice;
      } else {
        const policy=(await policies(session,request.schoolId)).find(item=>item.id===request.policyId);
        if(!policy||policy.status!=='DRAFT'||policy.version!==request.expectedVersion)throw new WebError(409,'VERSION_CONFLICT');
        reviewPolicy=policy;
        reviewNotice=(await read(session,`/v1/schools/${request.schoolId}/data-policy?noticeVersionId=${policy.noticeVersionId}`,c.envelope(c.notice))).data;
        if(reviewNotice.status!=='APPROVED'||reviewNotice.noticeVersionId!==policy.noticeVersionId)throw new WebError(409,'PROFILE_POLICY_CHANGED');
      }
    }
    deps.ensureCurrent(session);
    return {...current,...(reviewPolicy?{reviewPolicy}:{}),...(reviewNotice?{reviewNotice}:{})};
  };
  app.get('/app/bff/schools/:schoolId',async request=>{
    empty.parse(request.query);const {schoolId}=z.object({schoolId:c.id}).strict().parse(request.params);const session=deps.current(request);
    const context=await scope(session,schoolId);const school=(await read(session,`/v1/schools/${schoolId}`,c.envelope(c.school))).data;
    if(school.id!==schoolId)throw new WebError(503,'INVALID_RESPONSE');return {scope:context,school};
  });
  for(const resource of ['learners','profile-field-policies'] as const)app.get(`/app/bff/schools/:schoolId/${resource}`,async request=>{
    const {schoolId}=z.object({schoolId:c.id}).strict().parse(request.params);const {cursor}=pagination.parse(request.query);const session=deps.current(request);await scope(session,schoolId);
    const url=`/v1/schools/${schoolId}/${resource}?limit=50${cursor?`&cursor=${encodeURIComponent(cursor)}`:''}`;
    return resource==='learners'?read(session,url,c.page(c.learner)):read(session,url,c.page(c.policy));
  });
  app.get('/app/bff/schools/:schoolId/data-policy',async request=>{
    const {noticeVersionId}=z.object({noticeVersionId:c.id.optional()}).strict().parse(request.query);const {schoolId}=z.object({schoolId:c.id}).strict().parse(request.params);const session=deps.current(request);
    if(!(await scope(session,schoolId)).roles.includes('ADMIN'))throw new WebError(403,'ACCESS_REVOKED');
    return read(session,`/v1/schools/${schoolId}/data-policy${noticeVersionId?`?noticeVersionId=${noticeVersionId}`:''}`,c.envelope(c.notice));
  });
  app.get('/app/bff/schools/:schoolId/learners/:learnerId/profile',async request=>{
    empty.parse(request.query);const {schoolId,learnerId}=z.object({schoolId:c.id,learnerId:c.id}).strict().parse(request.params);
    return profile(deps.current(request),schoolId,learnerId);
  });
  const review=async(session:Session,intent:CommandRecord)=>{
    await bound(session,intent);
    const confirmation=randomBytes(32).toString('base64url');
    const saved=await deps.commands.review(owner(session),intent,digest(session.id),digest(confirmation));
    deps.ensureCurrent(session);
    return c.intentView.parse({...saved,confirmation});
  };
  const commandInput=z.object({operationId:c.id,confirmation:z.string().min(32).max(256)}).strict();
  const retrieve=async(session:Session,operationId:string)=>{
    const saved=await deps.commands.get(owner(session),operationId);
    if(!saved||saved.state==='CANCELLED')throw new WebError(409,'PROFILE_CONFIRMATION_CHANGED');
    return saved;
  };
  app.get('/app/bff/profile-command',async request=>{
    empty.parse(request.query);const session=deps.current(request);
    const intent=await deps.commands.find(owner(session));
    return {command:intent?await review(session,intent):null};
  });
  app.post('/app/bff/profile-command/prepare',{bodyLimit:24_000},async request=>{
    const session=deps.protect(request);const command=c.prepare.parse(request.body);
    const context=await snapshot(session,command);
    const intent=await deps.commands.create(owner(session),{personId:context.personId,schoolId:command.schoolId,membershipId:context.membershipId,
      accessEpoch:context.accessEpoch,kind:command.kind,expectedVersion:command.expectedVersion,
      targetId:command.kind==='PROFILE'?command.learnerId:command.kind==='POLICY_PUBLISH'?command.policyId:command.schoolId},
      {request:command,...(context.reviewPolicy?{reviewPolicy:context.reviewPolicy}:{}),...(context.reviewNotice?{reviewNotice:context.reviewNotice}:{})});
    return {command:await review(session,intent)};
  });
  app.post('/app/bff/profile-command/cancel',async request=>{
    const session=deps.protect(request);const {operationId,confirmation}=commandInput.parse(request.body);
    const intent=await retrieve(session,operationId);await bound(session,intent);
    await deps.commands.cancel(owner(session),intent,digest(session.id),digest(confirmation));
    deps.ensureCurrent(session);return {ok:true};
  });
  app.post('/app/bff/profile-command/confirm',async request=>{
    const session=deps.protect(request);const {operationId,confirmation}=commandInput.parse(request.body);
    const account=owner(session);
    let intent=await retrieve(session,operationId);
    intent=await deps.commands.claim(account,intent,digest(session.id),digest(confirmation));
    try {
      await bound(session,intent);const route=routes(intent.request);
      if(intent.state!=='PREPARED'&&intent.state!=='REJECTED') {
        const proof=await deps.call(session,`/v1/schools/${intent.schoolId}/operations/${intent.operationId}`);
        if(proof.status===200) {
          const data=z.object({data:z.object({operationId:c.id,commandType:z.string()})}).parse(proof.body).data;
          if(data.operationId!==intent.operationId||data.commandType!==route.type)throw new WebError(503,'INVALID_RESPONSE');
          intent=await deps.commands.settle(account,intent,'COMMITTED');deps.ensureCurrent(session);
          return {ok:true,operationId:intent.operationId};
        }
        if(proof.status!==404)result(proof);
        // A known success is never emitted again just because its proof was purged.
        if(intent.state==='COMMITTED')throw new WebError(409,'OPERATION_PROOF_MISSING');
      } else {
        const fresh=await snapshot(session,intent.request);
        if(JSON.stringify(fresh.reviewPolicy)!==JSON.stringify(intent.reviewPolicy)||JSON.stringify(fresh.reviewNotice)!==JSON.stringify(intent.reviewNotice))throw new WebError(409,'PROFILE_POLICY_CHANGED');
      }
      deps.ensureCurrent(session);
      const uncertain=intent.state==='UNCERTAIN'||intent.state==='SUBMITTED';
      // This transaction must COMMIT before the first mutating HTTP request. Any
      // ambiguous storage failure stops here; AP72 reconciles the persisted UUID.
      intent=await deps.commands.submitting(account,intent);
      deps.ensureCurrent(session);
      const response=await deps.call(session,route.path,{operationId:intent.operationId,...intent.request.payload},{method:route.method,expectedVersion:intent.expectedVersion});
      let state:'COMMITTED'|'REJECTED'|'UNCERTAIN';
      if(response.status>=500)state='UNCERTAIN';
      else if(response.status>=400)state=uncertain?'UNCERTAIN':'REJECTED';
      else {
        if(intent.request.kind==='PROFILE')c.envelope(c.profile).parse(response.body);else c.envelope(c.policy).parse(response.body);
        state='COMMITTED';
      }
      intent=await deps.commands.settle(account,intent,state);
      result(response);deps.ensureCurrent(session);return {ok:true,operationId:intent.operationId};
    } finally {
      // Conditional on our lease token: cannot unlock or overwrite another process.
      // Failure leaves SUBMITTED durable and recoverable after lease expiry.
      await deps.commands.release(account,intent);
    }
  });
}
