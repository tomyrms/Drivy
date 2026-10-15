import { createHash, randomBytes, randomUUID } from 'node:crypto';
import Fastify, { LogController, type FastifyReply, type FastifyRequest } from 'fastify';
import cookie from '@fastify/cookie';
import staticFiles from '@fastify/static';
import { z, ZodError } from 'zod';
import type { WebConfig } from './config.js';
import { IdentityUnavailable, InvalidCredentials, type IdentityProvider } from './oidc.js';
import { RateLimiter } from './rate-limit.js';
import { SessionStore, matchesSecret, type Session } from './session.js';
import { createAnonymousGateway, createGateway, createSchoolGateway, createOpeningGateway, type AnonymousGateway, type ApiGateway, type ApiResult, type SchoolGateway, type SchoolRequest } from './upstream.js';
import { openingTokenSchema, registerOpeningRoutes, type OpeningGateway, type OpeningRequest } from './opening-routes.js';
import { isUUID, matchSchoolRoute, MAX_SCHOOL_BODY } from './school-routes.js';

class WebError extends Error {
  constructor(readonly status: number, readonly code: string) { super(code); }
}
const empty = z.object({}).strict();
const previewSchema = z.object({ data: z.object({ invitationId: z.uuid(), schoolId: z.uuid(), schoolName: z.string(),
  roles: z.array(z.enum(['ADMIN','INSTRUCTOR','LEARNER'])).min(1), maskedEmail: z.string(), expiresAt: z.iso.datetime({offset:true}),
  notice: z.object({version: z.number().int(), noticeText:z.string(),retentionText:z.string(),contactEmail:z.string()}) }) });
const digest = (data: unknown) => createHash('sha256').update(JSON.stringify(data)).digest('hex');
/** Only a management page of this origin can be a post-login destination. */
const returnPath = /^\/app\/(?:gestion(?:\/[0-9a-fA-F-]{36}(?:\/[a-z-]{1,40})?)?|ouvrir|operateur)$/;
const loginBody = z.object({ returnTo: z.string().max(200).regex(returnPath).optional(), reauthenticate: z.boolean().optional() }).strict();
const strongVersion = /^"[1-9][0-9]{0,9}"$/;
const credentials = { email: z.string().trim().min(3).max(254), password: z.string().min(1).max(128) };
/** A typed code keeps only letters and digits (XXXX-XXXX); a long opening link token is kept as is. */
export function normalizeAccessCode(value: string): string {
  const trimmed = value.trim();
  if (/^[A-Za-z0-9_-]{43}$/.test(trimmed)) return trimmed;
  const compact = trimmed.toUpperCase().replace(/[\s-]/g, '');
  return compact.length === 8 ? `${compact.slice(0,4)}-${compact.slice(4)}` : compact;
}
const accessCode = z.string().max(80).transform(normalizeAccessCode).pipe(openingTokenSchema);
const codeKind = z.object({ data: z.object({ kind: z.enum(['LEARNER_INVITATION','SCHOOL_OPENING']), schoolName: z.string().max(200).optional(),
  expiresAt: z.iso.datetime({offset:true}) }) });
/** Fastify parser refusals (size, media type, malformed JSON) stay client errors, without echoing details. */
function clientError(error: unknown): WebError | undefined {
  const status = (error as { statusCode?: unknown }).statusCode;
  if (status === 413) return new WebError(413,'PAYLOAD_TOO_LARGE');
  if (status === 415) return new WebError(415,'UNSUPPORTED_MEDIA_TYPE');
  if (typeof status === 'number' && status >= 400 && status < 500) return new WebError(400,'INVALID_REQUEST');
  return undefined;
}

export async function buildWebApp(options: { config: WebConfig; identity: IdentityProvider; gateway?: ApiGateway;
  schoolGateway?: SchoolGateway; openingGateway?: OpeningGateway; anonymousGateway?: AnonymousGateway; store?: SessionStore; staticRoot?: string; now?: () => number; entryLimiter?: RateLimiter }) {
  const { config, identity } = options;
  const now = options.now ?? Date.now;
  const sessionMinutes = { idle: config.sessionIdleMinutes ?? 480, max: config.sessionMaxMinutes ?? 720 };
  const store = options.store ?? new SessionStore(now,10_000,{ idleMs: sessionMinutes.idle * 60_000, maxMs: sessionMinutes.max * 60_000 });
  // Only the two anonymous entry points (login, invitation link) can create a session: a bounded number per address.
  const entryLimiter = options.entryLimiter ?? new RateLimiter(30,10 * 60_000,now);
  // Sent to a browser without session so that its first POST proves it read this origin; it protects nothing else.
  const anonymousCsrf = randomBytes(32).toString('base64url');
  const gateway = options.gateway ?? createGateway(config.apiBaseURL);
  const schoolGateway = options.schoolGateway ?? createSchoolGateway(config.apiBaseURL);
  const openingGateway = options.openingGateway ?? createOpeningGateway(config.apiBaseURL);
  const anonymousGateway = options.anonymousGateway ?? createAnonymousGateway(config.apiBaseURL);
  const cookieName = config.development ? 'drivy-dev-session' : '__Host-drivy-session';
  // After a sign-out the identity provider may still hold its own session: the next login must ask for the credentials.
  const reloginName = config.development ? 'drivy-dev-relogin' : '__Host-drivy-relogin';
  const cookieBase = { path:'/', httpOnly:true, secure: !config.development, sameSite:'lax' } as const;
  const app = Fastify({ logger: false, logController: new LogController({disableRequestLogging: true}),
    genReqId: () => randomUUID(), bodyLimit: 2048, trustProxy: config.trustProxy ?? false });
  await app.register(cookie);
  const purge = setInterval(() => store.sweep(),60_000); purge.unref();
  app.addHook('onClose',async () => { clearInterval(purge); store.clear(); });
  app.addHook('onRequest',async (request,reply) => {
    reply.headers({ 'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff', 'Referrer-Policy':'no-referrer',
      'X-Frame-Options':'DENY', 'Cross-Origin-Opener-Policy':'same-origin',
      'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; manifest-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
      'Permissions-Policy': 'camera=(), microphone=(), geolocation=()' });
    if (request.headers['sec-fetch-site'] === 'cross-site' && request.url.startsWith('/app/bff/') && !request.url.startsWith('/app/bff/callback?')) {
      throw new WebError(403,'CROSS_SITE_REQUEST');
    }
  });
  // Hashed build assets never change: cache them (only when found, so a missing file is not remembered).
  app.addHook('onSend',async (request,reply,payload) => {
    if (reply.statusCode === 200 && request.url.startsWith('/app/assets/')) reply.header('Cache-Control','public, max-age=31536000, immutable');
    return payload;
  });
  app.setErrorHandler((error,_request,reply) => {
    const known = error instanceof WebError ? error : error instanceof ZodError ? new WebError(400,'INVALID_REQUEST')
      : clientError(error) ?? new WebError(503,'SERVICE_UNAVAILABLE');
    return reply.status(known.status).send({code: known.code, title: known.status === 401 ? 'Reconnectez-vous pour continuer.' :
      known.status === 429 ? 'Trop de tentatives. Patientez quelques minutes.' :
      known.status === 409 ? 'La situation a changé. Rechargez les informations avant de confirmer.' : 'La demande ne peut pas aboutir pour le moment.'});
  });
  const setCookie = (reply: FastifyReply, session: Session) => reply.setCookie(cookieName,session.id,{
    ...cookieBase, maxAge: sessionMinutes.max * 60 });
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
  /**
   * Entry points (login, invitation link). An existing session is protected as usual; a browser without one may only
   * be admitted here: same origin, JSON, the anonymous value, and within the per-address limit. The session itself is
   * created by `open`, once the body has proved valid.
   */
  const admit = (request: FastifyRequest): Session | null => {
    if (!entryLimiter.allow(request.ip)) throw new WebError(429,'RATE_LIMITED');
    if (store.get(request.cookies[cookieName])) return protect(request);
    if (request.headers.origin !== config.origin || !matchesSecret(request.headers['x-csrf-token'],anonymousCsrf) ||
      request.headers['content-type']?.split(';')[0]?.trim() !== 'application/json') throw new WebError(403,'CSRF_REJECTED');
    return null;
  };
  const open = (reply: FastifyReply, admitted: Session | null): Session => {
    if (admitted) return admitted;
    const session = store.create(); setCookie(reply,session); return session;
  };
  const accessToken = async (session: Session): Promise<string> => {
    if (!store.isCurrent(session) || !session.tokens) throw new WebError(401,'SESSION_EXPIRED');
    if (session.tokens.expiresAt <= now() + 30_000) {
      session.refresh ??= identity.refresh(session.tokens);
      try {
        const tokens = await session.refresh;
        if (!store.isCurrent(session)) throw new WebError(401,'SESSION_EXPIRED');
        session.tokens = tokens;
      } catch (error) {
        // An identity provider outage is not an expired session: keep it and let the page retry.
        if (error instanceof IdentityUnavailable && store.isCurrent(session)) throw new WebError(503,'SERVICE_UNAVAILABLE');
        store.destroy(session); throw new WebError(401,'SESSION_EXPIRED');
      }
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
  // Management relay: same session, token refresh and 401 rules as /v1/me. A step-up
  // demand (REAUTH_REQUIRED) keeps the session: the person reconnects with the same account.
  const callSchool = async (session: Session, command: SchoolRequest): Promise<ApiResult & { etag?: string }> => {
    const result = await schoolGateway(command,await accessToken(session));
    // A write may have been committed while the session ended: the browser must verify it, not assume a refusal.
    if (!store.isCurrent(session)) throw new WebError(401,command.method === 'GET' ? 'SESSION_EXPIRED' : 'SESSION_LOST_RESULT_UNKNOWN');
    if (result.status === 401) {
      const code = z.object({code:z.literal('REAUTH_REQUIRED')}).safeParse(result.body);
      if (code.success) throw new WebError(401,'REAUTH_REQUIRED');
      store.destroy(session); throw new WebError(401,'SESSION_EXPIRED');
    }
    return result;
  };
  const sendApi = (reply: FastifyReply, result: ApiResult) => {
    if (result.status >= 400) {
      const code = z.object({code:z.string().regex(/^[A-Z0-9_]{1,80}$/)}).safeParse(result.body);
      throw new WebError(result.status,code.success ? code.data.code : 'API_UNAVAILABLE');
    }
    return reply.status(result.status).send(result.body);
  };
  const callOpening = async(session:Session,command:OpeningRequest):Promise<ApiResult>=>{
    const result=await openingGateway(command,await accessToken(session));
    if(!store.isCurrent(session))throw new WebError(401,'SESSION_LOST_RESULT_UNKNOWN');
    if(result.status===401){store.destroy(session);throw new WebError(401,'SESSION_EXPIRED');}
    return result;
  };
  registerOpeningRoutes(app,{origin:config.origin,current,protect,admit,open,call:callOpening,send:sendApi,error:(status,code)=>new WebError(status,code)});
  app.get('/app/bff/session',async request => {
    const session = store.get(request.cookies[cookieName]);
    // No session is created for a visitor who only looks: that would let anyone fill the table.
    if (!session) return { authenticated:false, csrfToken:anonymousCsrf, invitationPending:false };
    if (session.tokens) await accessToken(session);
    const user = session.tokens?.principal;
    return { authenticated:!!user, csrfToken:session.csrf, invitationPending:!!session.invitation && !session.invitation.accepted,
      ...(user ? {user:{displayName:user.displayName,emailVerified:user.emailVerified,...(user.email ? {email:user.email} : {})}} : {}) };
  });
  app.post('/app/bff/login',async (request,reply) => {
    const admitted = admit(request); const body = loginBody.parse(request.body);
    const session = open(reply,admitted); const { returnTo } = body;
    const reauthenticate = body.reauthenticate === true || request.cookies[reloginName] === '1';
    const result = await identity.begin(reauthenticate ? { reauthenticate: true } : undefined);
    if (!store.isCurrent(session)) throw new WebError(401,'SESSION_EXPIRED');
    session.login = { ...result.transaction, ...(returnTo ? { returnTo } : {}) };
    return {url:result.url};
  });
  /** Sign-in by the form of this origin. The session (and an opening code typed before) carries over to the signed-in session. */
  const passwordSignIn = async (reply: FastifyReply, session: Session, email: string, password: string): Promise<Session> => {
    let tokens;
    try { tokens = await identity.password(email,password); }
    catch (error) {
      if (error instanceof InvalidCredentials) throw new WebError(401,'INVALID_CREDENTIALS');
      if (error instanceof IdentityUnavailable) throw new WebError(503,'SERVICE_UNAVAILABLE');
      throw error;
    }
    if (!store.isCurrent(session)) throw new WebError(401,'SESSION_EXPIRED');
    const next = store.rotate(session,tokens); setCookie(reply,next); reply.clearCookie(reloginName,cookieBase);
    return next;
  };
  const keepOpening = (session: Session, code: string) => {
    if (session.opening?.token === code) return;
    if (session.opening?.busy || (session.opening?.submitted && !session.opening.result)) throw new WebError(409,'OPENING_IN_PROGRESS');
    session.opening = { token: code, operationId: randomUUID() };
  };
  app.post('/app/bff/password-login',async (request,reply) => {
    const admitted = admit(request); const body = z.object(credentials).strict().parse(request.body);
    await passwordSignIn(reply,open(reply,admitted),body.email,body.password);
    return {ok:true};
  });
  /** « J'ai un code » : what the code opens. An opening code is kept in the session for the school form after sign-in. */
  app.post('/app/bff/access-code',async (request,reply) => {
    const admitted = admit(request); const { code } = z.object({ code: accessCode }).strict().parse(request.body);
    const result = await anonymousGateway('/v1/access-codes/preview',{code},request.ip);
    if (result.status >= 400) return sendApi(reply,result);
    const parsed = codeKind.parse(result.body).data;
    if (parsed.kind === 'SCHOOL_OPENING') keepOpening(open(reply,admitted),code);
    return { kind: parsed.kind, ...(parsed.schoolName ? { schoolName: parsed.schoolName } : {}), expiresAt: parsed.expiresAt };
  });
  /** Account creation is only possible with a valid code; the person is then signed in with the password just chosen. */
  app.post('/app/bff/accounts',async (request,reply) => {
    const admitted = admit(request);
    const body = z.object({ code: accessCode.optional(), firstName: z.string().trim().min(1).max(100), lastName: z.string().trim().min(1).max(100),
      ...credentials }).strict().parse(request.body);
    // Without a typed code, the invitation link opened in this browser names the invitation (it never leaves the server).
    const code = body.code ?? admitted?.invitation?.token;
    if (!code) throw new WebError(400,'INVALID_REQUEST');
    const result = await anonymousGateway('/v1/accounts',{ ...body, code },request.ip);
    if (result.status >= 400) return sendApi(reply,result);
    const { kind } = z.object({ data: z.object({ kind: z.enum(['LEARNER_INVITATION','SCHOOL_OPENING','EMAIL_INVITATION']) }) }).parse(result.body).data;
    const session = await passwordSignIn(reply,open(reply,admitted),body.email,body.password);
    if (kind === 'SCHOOL_OPENING') keepOpening(session,code);
    return { kind };
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
      const next = store.rotate(session,tokens); setCookie(reply,next); reply.clearCookie(reloginName,cookieBase);
      return reply.redirect(transaction.returnTo==='/app/ouvrir' || transaction.returnTo==='/app/operateur' ? transaction.returnTo : next.invitation ? '/app/invitation' : transaction.returnTo ?? '/app');
    } catch { return reply.redirect('/app?auth=failed'); }
  });
  app.post('/app/bff/logout',async (request,reply) => {
    const session = protect(request); empty.parse(request.body); const tokens = session.tokens;
    store.destroy(session); reply.clearCookie(cookieName,cookieBase);
    reply.setCookie(reloginName,'1',{ ...cookieBase, maxAge: 30 * 24 * 3600 });
    if (tokens) { try { await identity.revoke(tokens); } catch { /* Local session already destroyed; no token exposed. */ } }
    return {ok:true};
  });
  app.post('/app/bff/invitation',async (request,reply) => {
    const admitted = admit(request);
    const {token} = z.object({token:z.string().min(32).max(256).regex(/^[A-Za-z0-9_-]+$/)}).strict().parse(request.body);
    const session = open(reply,admitted);
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
  app.route({ method: ['GET','POST','PATCH','PUT'], url: '/app/bff/schools/*', bodyLimit: MAX_SCHOOL_BODY + 1_024,
    // Refused before the body is read: an unknown path or a missing session costs nothing to serve.
    onRequest: async request => {
      const url = new URL(request.raw.url!,config.origin);
      const match = matchSchoolRoute(request.method,url.pathname.slice('/app/bff'.length),url.search);
      if (!match) throw new WebError(404,'NOT_FOUND');
      if (match.route.method === 'GET') current(request); else protect(request);
    },
    handler: async (request,reply) => {
      const url = new URL(request.raw.url!,config.origin);
      const match = matchSchoolRoute(request.method,url.pathname.slice('/app/bff'.length),url.search);
      if (!match) throw new WebError(404,'NOT_FOUND');
      const command: SchoolRequest = { method: match.route.method, path: match.path, query: match.query };
      let session: Session;
      if (match.route.method === 'GET') {
        session = current(request);
      } else {
        session = protect(request);
        const body = request.body;
        if (typeof body !== 'object' || body === null || Array.isArray(body)) throw new WebError(400,'INVALID_REQUEST');
        if (Buffer.byteLength(JSON.stringify(body)) > (match.route.bodyLimit ?? 0)) throw new WebError(413,'PAYLOAD_TOO_LARGE');
        // The idempotency key must name the operation carried by the body, so a retry cannot change its target.
        const key = request.headers['idempotency-key'];
        const operationId = (body as { operationId?: unknown }).operationId;
        if (!isUUID(key) || !isUUID(operationId) || key.toLowerCase() !== operationId.toLowerCase()) throw new WebError(400,'INVALID_REQUEST');
        const version = request.headers['if-match'];
        if (match.route.ifMatch) {
          if (version === undefined) throw new WebError(428,'PRECONDITION_REQUIRED');
          if (typeof version !== 'string' || !strongVersion.test(version)) throw new WebError(400,'INVALID_REQUEST');
          command.ifMatch = version;
        } else if (version !== undefined) throw new WebError(400,'INVALID_REQUEST');
        command.body = body; command.idempotencyKey = key;
      }
      const result = await callSchool(session,command);
      if (result.status < 400 && result.etag) reply.header('ETag',result.etag);
      return sendApi(reply,result);
    } });
  if (options.staticRoot) {
    await app.register(staticFiles,{root:options.staticRoot,prefix:'/app/',index:false,wildcard:false,cacheControl:false});
    for (const path of ['/app','/app/','/app/preferences','/app/preferences/','/app/invitation','/app/ouvrir','/app/operateur','/app/gestion','/app/gestion/*']) app.get(path,async (_request,reply) => reply.sendFile('index.html'));
  }
  app.setNotFoundHandler(async (_request,reply) => reply.status(404).send({code:'NOT_FOUND',title:'Page introuvable.'}));
  return app;
}
