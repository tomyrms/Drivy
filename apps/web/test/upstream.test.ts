import Fastify from 'fastify';
import { randomBytes,randomUUID } from 'node:crypto';
import { expect,test } from 'vitest';
import { createGateway } from '../server/upstream.js';

test.each(['/v1/invitations/accept','/v1/invitations/code/accept'])('échange HTTP réel vers %s : Bearer et Idempotency-Key correspondent exactement à la commande',async path=>{
  const api=Fastify({logger:false});const access=randomBytes(32).toString('base64url');const operationId=randomUUID();
  let seen=false;
  api.post(`/refonte${path}`,async (request,reply)=>{
    const body=request.body as {operationId:string;token:string};
    expect(request.headers.authorization).toBe(`Bearer ${access}`);
    expect(request.headers['idempotency-key']).toBe(operationId);expect(body.operationId).toBe(operationId);
    expect(request.headers.cookie).toBeUndefined();seen=true;
    return reply.code(201).send({data:{schoolName:'École du test'}});
  });
  try {
    const origin=await api.listen({host:'127.0.0.1',port:0});
    expect((await createGateway(origin+'/refonte')(path,access,{operationId,...(path.includes('/code/')?{code:'WXYZ-2345'}:{token:randomBytes(32).toString('base64url')})})).status).toBe(201);
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
