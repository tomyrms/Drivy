import { createHash, randomBytes, randomUUID } from 'node:crypto';
import Fastify, { LogController, type FastifyReply, type FastifyRequest } from 'fastify';
import cookie from '@fastify/cookie';
import staticFiles from '@fastify/static';
import { z, ZodError } from 'zod';
import type { WebConfig } from './config.js';
import type { IdentityProvider } from './oidc.js';
import { SessionStore, matchesSecret, type Session } from './session.js';
import { createGateway, type ApiGateway, type ApiResult } from './upstream.js';

class WebError extends Error {
  constructor(readonly status: number, readonly code: string) { super(code); }
}
const empty = z.object({}).strict();
const previewSchema = z.object({ data: z.object({ invitationId: z.uuid(), schoolId: z.uuid(), schoolName: z.string(),
  roles: z.array(z.enum(['ADMIN','INSTRUCTOR','LEARNER'])).min(1), maskedEmail: z.string(), expiresAt: z.iso.datetime({offset:true}),
  notice: z.object({version: z.number().int(), noticeText:z.string(),retentionText:z.string(),contactEmail:z.string()}) }) });
const digest = (data: unknown) => createHash('sha256').update(JSON.stringify(data)).digest('hex');

export async function buildWebApp(options: { config: WebConfig; identity: IdentityProvider; gateway?: ApiGateway;
  store?: SessionStore; staticRoot?: string; now?: () => number }) {
  const { config, identity } = options;
  const now = options.now ?? Date.now;
  const store = options.store ?? new SessionStore(now);
  const gateway = options.gateway ?? createGateway(config.apiBaseURL);
  const cookieName = config.development ? 'drivy-dev-session' : '__Host-drivy-session';
  const app = Fastify({ logger: false, logController: new LogController({disableRequestLogging: true}),
    genReqId: () => randomUUID(), bodyLimit: 2048 });
  await app.register(cookie);
  const purge = setInterval(() => store.sweep(),60_000); purge.unref();
  app.addHook('onClose',async () => { clearInterval(purge); store.clear(); });
  app.addHook('onRequest',async (request,reply) => {
    reply.headers({ 'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff', 'Referrer-Policy':'no-referrer',
      'X-Frame-Options':'DENY', 'Cross-Origin-Opener-Policy':'same-origin',
      'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
      'Permissions-Policy': 'camera=(), microphone=(), geolocation=()' });
    if (request.headers['sec-fetch-site'] === 'cross-site' && request.url.startsWith('/app/bff/') && !request.url.startsWith('/app/bff/callback?')) {
      throw new WebError(403,'CROSS_SITE_REQUEST');
    }
  });
  app.setErrorHandler((error,_request,reply) => {
    const known = error instanceof WebError ? error : error instanceof ZodError ? new WebError(400,'INVALID_REQUEST')
      : new WebError(503,'SERVICE_UNAVAILABLE');
    return reply.status(known.status).send({code: known.code, title: known.status === 401 ? 'Reconnecte-toi pour continuer.' :
      known.status === 409 ? 'La situation a changé. Recharge les informations avant de confirmer.' : 'La demande ne peut pas aboutir pour le moment.'});
  });
  const setCookie = (reply: FastifyReply, session: Session) => reply.setCookie(cookieName,session.id,{
    path:'/', httpOnly:true, secure: !config.development, sameSite:'lax', maxAge:7200 });
  const current = (request: FastifyRequest): Session => {
    const session = store.get(request.cookies[cookieName]);
    if (!session) throw new WebError(401,'SESSION_EXPIRED');
    return session;
  };
  const protect = (request: FastifyRequest): Session => {
    const session = current(request);
    if (request.headers.origin !== config.origin || !matchesSecret(request.headers['x-csrf-token'],session.csrf) ||
      request.headers['content-type']?.split(';')[0]?.trim() !== 'application/json') throw new WebError(403,'CSRF_REJECTED');
    store.touch(session); return session;
  };
  const accessToken = async (session: Session): Promise<string> => {
    if (!store.isCurrent(session) || !session.tokens) throw new WebError(401,'SESSION_EXPIRED');
    if (session.tokens.expiresAt <= now() + 30_000) {
      session.refresh ??= identity.refresh(session.tokens);
      try {
        const tokens = await session.refresh;
        if (!store.isCurrent(session)) throw new WebError(401,'SESSION_EXPIRED');
        session.tokens = tokens;
      } catch { store.destroy(session); throw new WebError(401,'SESSION_EXPIRED'); }
      finally { delete session.refresh; }
    }
    store.touch(session);
    return session.tokens.accessToken;
  };
  const callApi = async (session: Session, path: string, body?: unknown): Promise<ApiResult> => {
    const result = await gateway(path,await accessToken(session),body);
    if (!store.isCurrent(session)) throw new WebError(401,'SESSION_EXPIRED');
    if (result.status === 401) { store.destroy(session); throw new WebError(401,'SESSION_EXPIRED'); }
    return result;
  };
  const sendApi = (reply: FastifyReply, result: ApiResult) => {
    if (result.status >= 400) {
      const code = z.object({code:z.string().regex(/^[A-Z0-9_]{1,80}$/)}).safeParse(result.body);
      throw new WebError(result.status,code.success ? code.data.code : 'API_UNAVAILABLE');
    }
    return reply.status(result.status).send(result.body);
  };
  app.get('/app/bff/session',async (request,reply) => {
    let session = store.get(request.cookies[cookieName]);
    if (!session) { session = store.create(); setCookie(reply,session); }
    if (session.tokens) await accessToken(session);
    const user = session.tokens?.principal;
    return { authenticated:!!user, csrfToken:session.csrf, invitationPending:!!session.invitation && !session.invitation.accepted,
      ...(user ? {user:{displayName:user.displayName,emailVerified:user.emailVerified,...(user.email ? {email:user.email} : {})}} : {}) };
  });
  app.post('/app/bff/login',async request => {
    const session = protect(request); empty.parse(request.body);
    const result = await identity.begin();
    if (!store.isCurrent(session)) throw new WebError(401,'SESSION_EXPIRED');
    session.login = result.transaction;
    return {url:result.url};
  });
  app.get('/app/bff/callback',async (request,reply) => {
    const session = store.get(request.cookies[cookieName]);
    const transaction = session?.login;
    if (!session || !transaction || transaction.expiresAt <= now()) {
      if (session) delete session.login;
      return reply.redirect('/app?auth=expired');
    }
    const url = new URL(request.raw.url!,config.origin);
    if (url.searchParams.getAll('state').length !== 1 || !matchesSecret(url.searchParams.get('state'),transaction.state)) {
      return reply.redirect('/app?auth=failed');
    }
    delete session.login;
    try {
      const tokens = await identity.complete(url,transaction);
      const next = store.rotate(session,tokens); setCookie(reply,next);
      return reply.redirect(next.invitation ? '/app/invitation' : '/app');
    } catch { return reply.redirect('/app?auth=failed'); }
  });
  app.post('/app/bff/logout',async (request,reply) => {
    const session = protect(request); empty.parse(request.body); const tokens = session.tokens;
    store.destroy(session); reply.clearCookie(cookieName,{path:'/',secure:!config.development,httpOnly:true,sameSite:'lax'});
    if (tokens) { try { await identity.revoke(tokens); } catch { /* Local session already destroyed; no token exposed. */ } }
    return {ok:true};
  });
  app.post('/app/bff/invitation',async request => {
    const session = protect(request);
    const {token} = z.object({token:z.string().min(32).max(256).regex(/^[A-Za-z0-9_-]+$/)}).strict().parse(request.body);
    const pending=session.invitation;
    if (pending && pending.token!==token && (pending.accepting || (pending.submitted && !pending.accepted))) {
      throw new WebError(409,'INVITATION_IN_PROGRESS');
    }
    store.setInvitation(session,token); return {ok:true};
  });
  app.post('/app/bff/invitation/clear',async request => {
    const session = protect(request); empty.parse(request.body);
    if (session.invitation?.accepting || (session.invitation?.submitted && !session.invitation.accepted)) throw new WebError(409,'INVITATION_IN_PROGRESS');
    delete session.invitation; return {ok:true};
  });
  app.get('/app/bff/me',async (request,reply) => sendApi(reply,await callApi(current(request),'/v1/me')));
  app.post('/app/bff/invitation/preview',async (request,reply) => {
    const session = protect(request); empty.parse(request.body); const invitation = session.invitation;
    if (!invitation) throw new WebError(404,'INVITATION_NOT_FOUND');
    if (invitation.accepting) throw new WebError(409,'INVITATION_IN_PROGRESS');
    const result = await callApi(session,'/v1/invitations/preview',{token:invitation.token});
    if (result.status >= 400) return sendApi(reply,result);
    if (session.invitation !== invitation) throw new WebError(409,'INVITATION_PREVIEW_CHANGED');
    const parsed = previewSchema.parse(result.body);
    const id = randomBytes(32).toString('base64url');
    invitation.confirmation = {id,invitationId:parsed.data.invitationId,digest:digest(parsed.data)};
    return {...parsed,confirmation:id};
  });
  app.post('/app/bff/invitation/accept',async (request,reply) => {
    const session = protect(request);
    const command = z.object({invitationId:z.uuid(),confirmation:z.string().min(32).max(256)}).strict().parse(request.body);
    const invitation = session.invitation; const confirmation = invitation?.confirmation;
    if (!invitation || !confirmation || command.invitationId !== confirmation.invitationId ||
      !matchesSecret(command.confirmation,confirmation.id)) throw new WebError(409,'INVITATION_PREVIEW_CHANGED');
    if (invitation.accepting) throw new WebError(409,'INVITATION_IN_PROGRESS');
    invitation.accepting = true;
    try {
      // The displayed notice and role must still match. A second tab cannot silently change the target.
      if (!invitation.submitted) {
        const preview = await callApi(session,'/v1/invitations/preview',{token:invitation.token});
        if (preview.status >= 400) return sendApi(reply,preview);
        if (digest(previewSchema.parse(preview.body).data) !== confirmation.digest || session.invitation !== invitation) {
          throw new WebError(409,'INVITATION_PREVIEW_CHANGED');
        }
      }
      // Keep the same intention even when an API commit loses its HTTP response.
      invitation.submitted = true;
      let result: ApiResult;
      try { result = await callApi(session,'/v1/invitations/accept',{operationId:invitation.operationId,token:invitation.token}); }
      catch (error) { invitation.uncertain = true; throw error; }
      if (result.status >= 200 && result.status < 300) invitation.accepted = true;
      else if (result.status >= 500) invitation.uncertain = true;
      else if (!invitation.uncertain) delete invitation.submitted;
      return sendApi(reply,result);
    } finally { delete invitation.accepting; }
  });
  if (options.staticRoot) {
    await app.register(staticFiles,{root:options.staticRoot,prefix:'/app/',index:false,wildcard:false,cacheControl:false});
    for (const path of ['/app','/app/','/app/invitation']) app.get(path,async (_request,reply) => reply.sendFile('index.html'));
  }
  app.setNotFoundHandler(async (_request,reply) => reply.status(404).send({code:'NOT_FOUND',title:'Page introuvable.'}));
  return app;
}
