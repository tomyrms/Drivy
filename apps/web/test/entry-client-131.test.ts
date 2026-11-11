import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';

// Modules du navigateur, importés par chemin dynamique : le contrôle de types serveur n'en suit pas les imports sans extension.
const protocolPath = '../client/protocol.ts', entryModelPath = '../client/portal/entry/entry-model.ts';
const protocol = await import(/* @vite-ignore */ protocolPath) as {
  RequestFailure: new (code: string, status?: number) => Error & { code: string; status: number };
  endSession(): Promise<unknown>;
  errorMessage(cause: unknown): string;
  okSchema: z.ZodType;
  request(path: string, schema: z.ZodType, options?: { csrf: string; body: Record<string, unknown> }): Promise<unknown>;
};
const entry = await import(/* @vite-ignore */ entryModelPath) as {
  accessCodeSchema: z.ZodType;
  accountCreationFailure(kind: string | null, cause: unknown): unknown;
  acceptanceFailure(cause: unknown): { dropPreview: boolean; uncertain: boolean };
  codeFromInput(value: string): string;
  entryFailureMessage(cause: unknown): string;
  sessionLost(cause: unknown): boolean;
};
const { RequestFailure, endSession, errorMessage, okSchema, request } = protocol;
const { accessCodeSchema, accountCreationFailure, acceptanceFailure, codeFromInput, entryFailureMessage, sessionLost } = entry;

/**
 * #131, écritures web d'entrée sans test dédié (matrice W01, W03, W04, W05, W06) : ce qui part sur le réseau, avec quelle
 * protection, et ce que le client conclut — ou ne conclut pas — de chaque réponse. Le rendu des formulaires relève de la
 * campagne navigateur ; ici seulement le contrat d'échange et la classification des échecs, sans DOM.
 */
type Sent = { method: string; path: string; headers: Record<string, string>; body: string | undefined };
let sent: Sent[] = [];
const csrf = 'jeton-csrf-synthetique';
const record = (input: URL | string, init?: RequestInit) => {
  sent.push({ method: init?.method ?? 'GET', path: new URL(String(input)).pathname, headers: init?.headers as Record<string, string>, body: init?.body as string | undefined });
};
function reply(status: number, body: unknown, contentType = 'application/json') {
  return vi.fn(async (input: URL | string, init?: RequestInit) => {
    record(input, init);
    return { status, ok: status >= 200 && status < 300, url: String(input), headers: new Headers({ 'content-type': contentType }), json: async () => body };
  });
}
beforeEach(() => { sent = []; vi.stubGlobal('window', { location: { origin: 'https://drivy.example' } }); });
afterEach(() => { vi.unstubAllGlobals(); });

describe('Une écriture d\'entrée part une fois, en POST, avec le jeton de la session et jamais ailleurs', () => {
  test.each([
    ['W01 vérifier un code', 'access-code', accessCodeSchema, { kind: 'SCHOOL_OPENING', expiresAt: '2026-12-01T00:00:00Z' }, { code: 'ABCD-1234' }],
    ['W03 créer un compte', 'accounts', z.object({ kind: z.string() }), { kind: 'LEARNER_INVITATION' },
      { code: 'ABCD-1234', firstName: 'Camille', lastName: 'Test', email: 'camille@example.invalid', password: 'x'.repeat(12) }],
    ['W04 accepter une invitation', 'invitation/accept', z.object({ ok: z.literal(true) }), { ok: true }, { invitationId: randomUUID(), confirmation: 'confirmation' }],
    ['W05 fermer une invitation', 'invitation/clear', okSchema, { ok: true }, {}],
  ])('%s', async (_name, path, schema, answer, body) => {
    vi.stubGlobal('fetch', reply(200, answer));
    await request(path, schema as z.ZodType, { csrf, body });
    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({ method: 'POST', path: `/app/bff/${path}`, body: JSON.stringify(body) });
    expect(sent[0]!.headers['X-CSRF-Token']).toBe(csrf);
    expect(sent[0]!.headers['Content-Type']).toBe('application/json');
  });

  test('le jeton n\'est jamais mis dans l\'adresse ni dans le corps', async () => {
    vi.stubGlobal('fetch', reply(200, { ok: true }));
    await request('invitation/clear', okSchema, { csrf, body: {} });
    expect(sent[0]!.path).not.toContain(csrf);
    expect(sent[0]!.body).not.toContain(csrf);
  });

  test('W01 : le code saisi est normalisé avant l\'envoi, y compris collé depuis un lien', () => {
    expect(codeFromInput('  ABCD-1234  ')).toBe('ABCD-1234');
    expect(codeFromInput('https://drivy.example/app/ouvrir#token=Abc_123-x')).toBe('Abc_123-x');
  });
});

describe('Chaque échec garde une seule lecture : refus définitif, résultat à vérifier, ou session perdue', () => {
  test('W01/W03 : les refus de l\'école ont leur message propre', async () => {
    for (const [code, status] of [['ACCESS_CODE_INVALID', 404], ['ACCESS_CODE_ATTEMPTS', 429], ['ACCOUNT_EXISTS', 409], ['ACCOUNT_PASSWORD_REJECTED', 422]] as const) {
      vi.stubGlobal('fetch', reply(status, { code }, 'application/problem+json'));
      const failure = await request('accounts', z.object({}), { csrf, body: {} }).catch(cause => cause);
      expect(failure).toBeInstanceOf(RequestFailure);
      expect(failure).toMatchObject({ code, status });
      expect(entryFailureMessage(failure)).not.toBe(errorMessage(new RequestFailure('REQUEST_FAILED', status)));
    }
  });

  test('W03 : un code refusé pour une invitation e-mail dit que l\'adresse n\'est pas la bonne', () => {
    const refused = new RequestFailure('ACCESS_CODE_INVALID', 404);
    expect(accountCreationFailure('EMAIL_INVITATION', refused)).toMatchObject({ code: 'EMAIL_INVITATION_MISMATCH' });
    expect(accountCreationFailure('LEARNER_INVITATION', refused)).toBe(refused);
  });

  test('W04 : une coupure ou une erreur serveur laisse le résultat à vérifier sans écarter l\'aperçu', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new TypeError('network'); }));
    const lost = await request('invitation/accept', okSchema, { csrf, body: {} }).catch(cause => cause);
    expect(lost).toMatchObject({ code: 'NETWORK_UNAVAILABLE', status: 0 });
    expect(acceptanceFailure(lost)).toEqual({ dropPreview: false, uncertain: true });
    expect(acceptanceFailure(new RequestFailure('INTERNAL_ERROR', 503))).toEqual({ dropPreview: false, uncertain: true });
    expect(acceptanceFailure(new RequestFailure('SESSION_LOST_RESULT_UNKNOWN', 401))).toMatchObject({ uncertain: true });
  });

  test('W04 : une invitation changée ou utilisée écarte l\'aperçu, sans prétendre que le résultat est incertain', () => {
    for (const code of ['INVITATION_EXPIRED', 'INVITATION_REVOKED', 'INVITATION_USED', 'INVITATION_PREVIEW_CHANGED'])
      expect(acceptanceFailure(new RequestFailure(code, 409))).toEqual({ dropPreview: true, uncertain: false });
  });

  test('une réponse sans type JSON, mal formée ou venue d\'une autre adresse ne confirme rien', async () => {
    vi.stubGlobal('fetch', reply(200, 'ok', 'text/html'));
    await expect(request('invitation/clear', okSchema, { csrf, body: {} })).rejects.toMatchObject({ code: 'INVALID_RESPONSE' });
    vi.stubGlobal('fetch', reply(200, { ok: false }));
    await expect(request('invitation/clear', okSchema, { csrf, body: {} })).rejects.toMatchObject({ code: 'INVALID_RESPONSE' });
    vi.stubGlobal('fetch', vi.fn(async () => ({ status: 200, ok: true, url: 'https://autre.example/app/bff/invitation/clear',
      headers: new Headers({ 'content-type': 'application/json' }), json: async () => ({ ok: true }) })));
    await expect(request('invitation/clear', okSchema, { csrf, body: {} })).rejects.toMatchObject({ code: 'INVALID_RESPONSE' });
  });

  test('W05/W04 : 401 ou jeton refusé = session perdue ; un refus métier ne l\'est pas', () => {
    expect(sessionLost(new RequestFailure('UNAUTHENTICATED', 401))).toBe(true);
    expect(sessionLost(new RequestFailure('CSRF_REJECTED', 403))).toBe(true);
    expect(sessionLost(new RequestFailure('INVITATION_USED', 409))).toBe(false);
  });
});

describe('W06 : se déconnecter', () => {
  const session = (authenticated: boolean) => ({ authenticated, csrfToken: csrf, invitationPending: false });

  test('sans session ouverte, aucune déconnexion n\'est envoyée et rien n\'est présenté comme révoqué', async () => {
    vi.stubGlobal('fetch', reply(200, session(false)));
    await expect(endSession()).resolves.toEqual({ sessionClosed: true, revocation: 'not-attempted' });
    expect(sent.map(call => `${call.method} ${call.path}`)).toEqual(['GET /app/bff/session']);
  });

  test('avec une session, le jeton relu part en POST ; la révocation non annoncée reste « inconnue »', async () => {
    const answers: unknown[] = [session(true), { sessionClosed: true }];
    vi.stubGlobal('fetch', vi.fn(async (input: URL | string, init?: RequestInit) => {
      record(input, init);
      return { status: 200, ok: true, url: String(input), headers: new Headers({ 'content-type': 'application/json' }), json: async () => answers.shift() };
    }));
    await expect(endSession()).resolves.toEqual({ sessionClosed: true, revocation: 'unknown' });
    expect(sent.map(call => `${call.method} ${call.path}`)).toEqual(['GET /app/bff/session', 'POST /app/bff/logout']);
    expect(sent[1]!.headers['X-CSRF-Token']).toBe(csrf);
  });

  test('une déconnexion dont la réponse est perdue lève : l\'écran ne conclut pas à une fermeture', async () => {
    let calls = 0;
    vi.stubGlobal('fetch', vi.fn(async (input: URL | string) => {
      calls++;
      if (calls === 2) throw new TypeError('network');
      return { status: 200, ok: true, url: String(input), headers: new Headers({ 'content-type': 'application/json' }), json: async () => session(true) };
    }));
    await expect(endSession()).rejects.toMatchObject({ code: 'NETWORK_UNAVAILABLE' });
  });
});
