import { afterEach, describe, expect, test, vi } from 'vitest';
import { randomBytes, randomUUID } from 'node:crypto';
import { buildWebApp } from '../server/app.js';
import { readConfig } from '../server/config.js';
import { SessionStore, type Tokens } from '../server/session.js';
import type { IdentityProvider } from '../server/oidc.js';
import type { ApiGateway } from '../server/upstream.js';

const config = {origin:'https://drivy.example',apiBaseURL:'https://drivy.example/refonte',issuer:'https://identity.example/realm',
  clientId:'drivy-web',clientSecret:randomBytes(32).toString('hex'),development:false,host:'127.0.0.1',port:3002};
const token = () => randomBytes(32).toString('base64url');
const sample = () => ({data:{invitationId:randomUUID(),schoolId:randomUUID(),schoolName:'École locale de test',
  roles:['LEARNER'],maskedEmail:'e***@example.test',expiresAt:'2026-10-01T00:00:00.000Z',
  notice:{version:1,noticeText:'Notice de test',retentionText:'Conservation de test',contactEmail:'test@example.test'}}});
const apps: Awaited<ReturnType<typeof buildWebApp>>[] = [];
afterEach(async () => { await Promise.all(apps.splice(0).map(app=>app.close())); });

async function harness(gateway?: ApiGateway) {
  let now = Date.now();
  const tokens: Tokens = {accessToken:token(),refreshToken:token(),expiresAt:now+300_000,
    principal:{subject:randomUUID(),displayName:'Test local',email:'test@example.test',emailVerified:true}};
  const identity: IdentityProvider = {
    begin: vi.fn(async () => ({transaction:{state:token(),nonce:token(),verifier:token(),expiresAt:now+300_000},url:'https://identity.example/auth'})),
    complete:vi.fn(async ()=>tokens), refresh:vi.fn(async()=>({...tokens,expiresAt:now+300_000})),revoke:vi.fn(async()=>{})
  };
  const store = new SessionStore(()=>now);
  const app = await buildWebApp({config,identity,store,now:()=>now,gateway:gateway ?? vi.fn(async()=>({status:200,body:{data:{memberships:[]}}}))});
  apps.push(app);
  let cookie = ''; let csrf = '';
  const cookieFrom = (response: {headers:Record<string,unknown>}) => {
    const set = response.headers['set-cookie']; return (Array.isArray(set) ? set[0] : set)?.toString().split(';')[0] ?? '';
  };
  const start = async () => {
    const response = await app.inject({url:'/app/bff/session'});
    cookie = cookieFrom(response); csrf=response.json().csrfToken; return response;
  };
  const get = (url:string) => app.inject({url,headers:{cookie}});
  const post = (url:string,payload:Record<string,unknown>={}) => app.inject({method:'POST',url,payload,
    headers:{cookie,origin:config.origin,'x-csrf-token':csrf}});
  const login = async () => {
    await post('/app/bff/login');
    const session = store.get(cookie.split('=')[1])!;
    const response = await get(`/app/bff/callback?code=one&state=${session.login!.state}`);
    cookie=cookieFrom(response); const state=await get('/app/bff/session'); csrf=state.json().csrfToken;
    return response;
  };
  return {app,store,identity,tokens,start,get,post,login,cookie:()=>cookie,csrf:()=>csrf,advance:(ms:number)=>{now+=ms;}};
}

describe('Session BFF et frontière navigateur',()=>{
  test('cookie __Host Secure HttpOnly SameSite, aucun jeton ni sujet OIDC au navigateur',async()=>{
    const h=await harness(); const anonymous=await h.start();
    expect(anonymous.headers['set-cookie']).toContain('__Host-drivy-session=');
    for(const flag of ['HttpOnly','Secure','SameSite=Lax','Path=/']) expect(anonymous.headers['set-cookie']).toContain(flag);
    const oldCookie=h.cookie(),oldCSRF=h.csrf(); await h.login();
    expect(h.cookie()).not.toBe(oldCookie); expect(h.csrf()).not.toBe(oldCSRF);
    const response=await h.get('/app/bff/session'); expect(response.json().authenticated).toBe(true);
    for(const value of [h.tokens.accessToken,h.tokens.refreshToken!,h.tokens.principal.subject]) expect(response.body).not.toContain(value);
    expect(response.headers['cache-control']).toBe('no-store'); expect(response.headers['referrer-policy']).toBe('no-referrer');
    expect((await h.app.inject({url:'/app/bff/me',headers:{cookie:oldCookie}})).statusCode).toBe(401);
  });
  test.each(['/app/bff/login','/app/bff/logout','/app/bff/invitation','/app/bff/invitation/clear','/app/bff/invitation/preview','/app/bff/invitation/accept'])(
    '%s refuse Origin ou CSRF manquant/étranger',async url=>{
      const h=await harness();await h.start();
      for(const headers of [{cookie:h.cookie()},{cookie:h.cookie(),origin:'https://evil.example','x-csrf-token':h.csrf()},
        {cookie:h.cookie(),origin:config.origin,'x-csrf-token':token()}]) {
        expect((await h.app.inject({method:'POST',url,headers,payload:{}})).statusCode).toBe(403);
      }
    });
  test('le callback est lié au cookie, state et délai et consommé une fois',async()=>{
    const h=await harness();await h.start();await h.post('/app/bff/login');
    const state=h.store.get(h.cookie().split('=')[1])!.login!.state;
    expect((await h.app.inject({url:`/app/bff/callback?code=x&state=${state}`})).headers.location).toBe('/app?auth=expired');
    expect((await h.get('/app/bff/callback?code=x&state=wrong')).headers.location).toBe('/app?auth=failed');
    expect(h.identity.complete).not.toHaveBeenCalled();
    const valid=await h.get(`/app/bff/callback?code=x&state=${state}`);
    expect(valid.headers.location).toBe('/app');
    expect((await h.get(`/app/bff/callback?code=x&state=${state}`)).headers.location).toBe('/app?auth=expired');
    await h.start();
    await h.post('/app/bff/login'); h.advance(300_001);
    expect((await h.get('/app/bff/callback?code=x&state=expired')).headers.location).toBe('/app?auth=expired');
  });
  test('expire après inactivité et interdit de restaurer une session détruite pendant un refresh',async()=>{
    const h=await harness();await h.start();await h.login();h.advance(280_000);
    let finish!: (tokens:Tokens)=>void;
    vi.mocked(h.identity.refresh).mockImplementation(()=>new Promise(resolve=>{finish=resolve;}));
    const pending=h.get('/app/bff/me'); await new Promise(resolve=>setTimeout(resolve,20));
    await h.post('/app/bff/logout');finish({...h.tokens,expiresAt:Date.now()+300_000});
    expect((await pending).statusCode).toBe(401);expect((await h.get('/app/bff/me')).statusCode).toBe(401);
    vi.mocked(h.identity.refresh).mockResolvedValue({...h.tokens,expiresAt:Date.now()+600_000});
    await h.start();await h.login();h.advance(30*60_000);
    expect((await h.get('/app/bff/me')).statusCode).toBe(401);
  });
  test('partage un seul refresh concurrent, puis relit API pour chaque demande',async()=>{
    const api=vi.fn(async()=>({status:200,body:{data:{memberships:[]}}})); const h=await harness(api);
    await h.start();await h.login();h.advance(280_000);
    vi.mocked(h.identity.refresh).mockImplementation(async()=>{await new Promise(resolve=>setTimeout(resolve,30));return {...h.tokens,expiresAt:Date.now()+600_000};});
    const responses=await Promise.all([h.get('/app/bff/me'),h.get('/app/bff/me')]);
    expect(responses.map(r=>r.statusCode)).toEqual([200,200]);expect(h.identity.refresh).toHaveBeenCalledTimes(1);expect(api).toHaveBeenCalledTimes(2);
  });
  test('ne réfléchit pas un détail amont sensible dans une erreur',async()=>{
    const secret=token(); const h=await harness(async()=>({status:403,body:{code:'FORBIDDEN',title:secret,internal:secret}}));
    await h.start();await h.login();const response=await h.get('/app/bff/me');expect(response.statusCode).toBe(403);expect(response.body).not.toContain(secret);
  });
});

describe('Invitation web confirmée',()=>{
  test('survit à OAuth uniquement côté serveur et GET ne consomme pas',async()=>{
    const preview=sample(),invite=token(); const api=vi.fn(async()=>({status:200,body:preview})); const h=await harness(api);
    await h.start();expect((await h.post('/app/bff/invitation',{token:invite})).statusCode).toBe(200);
    expect((await h.login()).headers.location).toBe('/app/invitation');
    const session=await h.get('/app/bff/session');expect(session.json().invitationPending).toBe(true);expect(session.body).not.toContain(invite);
    expect(api).not.toHaveBeenCalled();const response=await h.post('/app/bff/invitation/preview');
    expect(response.json().data.schoolName).toBe(preview.data.schoolName);expect(response.json().confirmation).toBeTypeOf('string');
    expect(api).toHaveBeenCalledWith('/v1/invitations/preview',h.tokens.accessToken,{token:invite});
  });
  test('un second onglet ne peut pas remplacer la cible déjà affichée puis accepter silencieusement',async()=>{
    const preview=sample();const api=vi.fn<ApiGateway>(async()=>({status:200,body:preview}));const h=await harness(api);
    await h.start();await h.login();await h.post('/app/bff/invitation',{token:token()});
    const first=(await h.post('/app/bff/invitation/preview')).json();await h.post('/app/bff/invitation',{token:token()});
    const response=await h.post('/app/bff/invitation/accept',{invitationId:first.data.invitationId,confirmation:first.confirmation});
    expect(response.statusCode).toBe(409);expect(api.mock.calls.every(call=>call[0]!=='/v1/invitations/accept')).toBe(true);
  });
  test('une notice modifiée exige une nouvelle lecture et confirmation avant mutation',async()=>{
    const preview=sample(); const api=vi.fn<ApiGateway>(async()=>({status:200,body:structuredClone(preview)}));const h=await harness(api);
    await h.start();await h.login();await h.post('/app/bff/invitation',{token:token()});
    const first=(await h.post('/app/bff/invitation/preview')).json();preview.data.notice.version=2;
    const response=await h.post('/app/bff/invitation/accept',{invitationId:first.data.invitationId,confirmation:first.confirmation});
    expect(response.statusCode).toBe(409);expect(api.mock.calls.every(call=>call[0]!=='/v1/invitations/accept')).toBe(true);
  });
  test('réessaye même operationId après réponse perdue et ne réutilise pas des droits en cache',async()=>{
    const preview=sample();let accepts=0;
    const api=vi.fn<ApiGateway>(async path=>{
      if(path==='/v1/invitations/preview')return {status:200,body:preview};
      accepts++;if(accepts===1)throw new Error('réponse perdue après commit');
      if(accepts===2)return {status:201,body:{data:{schoolId:preview.data.schoolId}}};
      return {status:403,body:{code:'FORBIDDEN'}};
    });
    const h=await harness(api);await h.start();await h.login();const invite=token();await h.post('/app/bff/invitation',{token:invite});
    const first=(await h.post('/app/bff/invitation/preview')).json();const command={invitationId:first.data.invitationId,confirmation:first.confirmation};
    expect((await h.post('/app/bff/invitation/accept',command)).statusCode).toBe(503);
    expect((await h.post('/app/bff/invitation/clear')).statusCode).toBe(409);
    expect((await h.post('/app/bff/invitation',{token:token()})).statusCode).toBe(409);
    expect((await h.post('/app/bff/invitation',{token:invite})).statusCode).toBe(200);
    expect((await h.post('/app/bff/invitation/accept',command)).statusCode).toBe(201);
    expect((await h.post('/app/bff/invitation/accept',command)).statusCode).toBe(403);
    const calls=api.mock.calls.filter(call=>call[0]==='/v1/invitations/accept');
    expect(calls).toHaveLength(3);expect(calls[0]![2]).toEqual(calls[1]![2]);expect(calls[1]![2]).toEqual(calls[2]![2]);
    expect((calls[0]![2] as {token:string}).token).toBe(invite);
  });
});

test('configuration refuse HTTP hors loopback et tout assouplissement production',()=>{
  const env={WEB_ORIGIN:config.origin,API_BASE_URL:config.apiBaseURL,OIDC_ISSUER:config.issuer,
    OIDC_WEB_CLIENT_ID:config.clientId,OIDC_WEB_CLIENT_SECRET:config.clientSecret};
  expect(()=>readConfig({...env,WEB_ORIGIN:'http://drivy.example'})).toThrow();
  expect(()=>readConfig({...env,WEB_DEVELOPMENT:'true',NODE_ENV:'production'})).toThrow();
  expect(()=>readConfig({...env,API_BASE_URL:'https://name:secret@example.com'})).toThrow();
  expect(readConfig(env).origin).toBe(config.origin);
});

test('stock de sessions borné et nettoyage des jetons expirés',()=>{
  let now=0;const store=new SessionStore(()=>now,2);const first=store.create();store.create();expect(()=>store.create()).toThrow();
  now=600_000;store.sweep();expect(store.get(first.id)).toBeUndefined();expect(()=>store.create()).not.toThrow();
});
