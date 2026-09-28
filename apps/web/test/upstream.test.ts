import Fastify from 'fastify';
import { randomBytes,randomUUID } from 'node:crypto';
import { expect,test } from 'vitest';
import { createGateway } from '../server/upstream.js';

test('échange HTTP réel vers AP04 : Bearer et Idempotency-Key correspondent exactement à la commande',async()=>{
  const api=Fastify({logger:false});const access=randomBytes(32).toString('base64url');const operationId=randomUUID();
  let seen=false;
  api.post('/refonte/v1/invitations/accept',async (request,reply)=>{
    const body=request.body as {operationId:string;token:string};
    expect(request.headers.authorization).toBe(`Bearer ${access}`);
    expect(request.headers['idempotency-key']).toBe(operationId);expect(body.operationId).toBe(operationId);
    expect(request.headers.cookie).toBeUndefined();seen=true;
    return reply.code(201).send({data:{schoolName:'École du test'}});
  });
  try {
    const origin=await api.listen({host:'127.0.0.1',port:0});
    expect((await createGateway(origin+'/refonte')('/v1/invitations/accept',access,{operationId,token:randomBytes(32).toString('base64url')})).status).toBe(201);
    expect(seen).toBe(true);
  } finally {await api.close();}
});

test('une redirection API ne transfère pas le jeton et les chemins arbitraires sont refusés',async()=>{
  const api=Fastify({logger:false});let followed=false;
  api.get('/v1/me',async (_request,reply)=>reply.redirect('/other'));
  api.get('/other',async()=>{followed=true;return {};});
  try {
    const origin=await api.listen({host:'127.0.0.1',port:0});const gateway=createGateway(origin);const access=randomBytes(32).toString('base64url');
    await expect(gateway('/v1/me',access)).rejects.toThrow();expect(followed).toBe(false);
    await expect(gateway('/../other',access)).rejects.toThrow();
  } finally {await api.close();}
});

test('profil HTTP réel : PATCH, UUID et version transmis sans cookie navigateur',async()=>{
  const api=Fastify({logger:false});const schoolId=randomUUID(),learnerId=randomUUID(),operationId=randomUUID(),policyVersionId=randomUUID();let called=false;
  api.patch(`/v1/schools/${schoolId}/learners/${learnerId}/administrative-profile`,async request=>{
    called=true;expect(request.headers['if-match']).toBe('"3"');expect(request.headers['idempotency-key']).toBe(operationId);
    expect(request.headers.cookie).toBeUndefined();expect(request.body).toEqual({operationId,policyVersionId,contactPhone:'+41790000000'});return {data:{version:4}};
  });
  try {const origin=await api.listen({host:'127.0.0.1',port:0});const gateway=createGateway(origin);
    const response=await gateway(`/v1/schools/${schoolId}/learners/${learnerId}/administrative-profile`,'test-only',{operationId,policyVersionId,contactPhone:'+41790000000'},{method:'PATCH',expectedVersion:3});
    expect(response.status).toBe(200);expect(called).toBe(true);
  } finally {await api.close();}
});

test('allowlist scolaire refuse query arbitraire, double paramètre, segments encodés et méthode non prévue avant HTTP',async()=>{
  const gateway=createGateway('http://127.0.0.1:1');const schoolId=randomUUID(),learnerId=randomUUID();
  for(const path of [`/v1/schools/${schoolId}/learners?secret=1`,`/v1/schools/${schoolId}/learners?cursor=a&cursor=b`,
    `/v1/schools/${schoolId}/learners/%2e%2e/me`,`/v1/schools/${schoolId}/../me`,`/v1/schools/${schoolId}/members`,
    `/v1/schools/${schoolId}/learners/${learnerId}/action-readiness?action=ENTER&schoolId=${schoolId}`]) {
    await expect(gateway(path,'test-only')).rejects.toThrow();
  }
  await expect(gateway(`/v1/schools/${schoolId}/learners/${learnerId}/administrative-profile`,'test-only',{operationId:randomUUID(),policyVersionId:randomUUID(),contactPhone:null},{method:'POST',expectedVersion:1})).rejects.toThrow();
});
