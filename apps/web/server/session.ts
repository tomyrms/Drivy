import { randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import type { OpeningState, OperatorOpeningState } from './opening-routes.js';

export type Principal = { subject: string; displayName: string; email?: string; emailVerified: boolean; authenticatedAt?: number };
export type Tokens = { accessToken: string; refreshToken?: string; expiresAt: number; principal: Principal };
export type LoginTransaction = { state: string; nonce: string; verifier: string; expiresAt: number; returnTo?: string; reauthenticationSubject?: string };
export type InvitationState = {
  token: string; delivery?: 'EMAIL' | 'CODE'; operationId: string; confirmation?: { id: string; invitationId: string; digest: string; data: unknown };
  accepting?: boolean; submitted?: boolean; uncertain?: boolean; accepted?: boolean;
};
export type Session = {
  id: string; csrf: string; createdAt: number; lastSeen: number;
  tokens?: Tokens; login?: LoginTransaction; invitation?: InvitationState; refresh?: Promise<Tokens>; reauthenticating?: boolean;
  opening?: OpeningState; operatorOpening?: OperatorOpeningState;
};
const random = () => randomBytes(32).toString('base64url');

export function matchesSecret(actual: unknown, expected: string): boolean {
  if (typeof actual !== 'string' || actual.length > 1024) return false;
  const a = Buffer.from(actual); const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a,b);
}

/** Lifetime of a signed-in session: sliding idle time and absolute maximum, both bounded by the identity provider's own refresh. */
export type SessionLimits = { idleMs: number; maxMs: number };
export const defaultSessionLimits: SessionLimits = { idleMs: 30 * 60_000, maxMs: 2 * 60 * 60_000 };

/** One process; no token/dossier on disk. Restart deliberately expires all browser sessions. */
export class SessionStore {
  private readonly sessions = new Map<string, Session>();
  constructor(private readonly clock: () => number = Date.now, private readonly capacity = 10_000,
    private readonly limits: SessionLimits = defaultSessionLimits) {}

  get size(): number { return this.sessions.size; }
  private expired(session: Session): boolean {
    const now = this.clock();
    const idle = session.tokens ? this.limits.idleMs : 10 * 60_000;
    return now - session.lastSeen >= idle || now - session.createdAt >= this.limits.maxMs;
  }
  get(id: string | undefined): Session | undefined {
    if (!id || !/^[A-Za-z0-9_-]{43}$/.test(id)) return;
    const session = this.sessions.get(id);
    if (session && this.expired(session)) { this.destroy(session); return; }
    return session;
  }
  isCurrent(session: Session): boolean { return this.get(session.id) === session; }
  touch(session: Session): void { if (this.isCurrent(session)) session.lastSeen = this.clock(); }
  create(): Session {
    this.sweep();
    if (this.sessions.size >= this.capacity) throw new Error('SESSION_CAPACITY');
    const session: Session = { id: random(), csrf: random(), createdAt: this.clock(), lastSeen: this.clock() };
    this.sessions.set(session.id,session); return session;
  }
  rotate(session: Session, tokens: Tokens): Session {
    if (!this.isCurrent(session)) throw new Error('SESSION_EXPIRED');
    const invitation = session.invitation;
    const opening = session.opening;
    // Opening-link issuance belongs to its operator: another account starts a separate intention.
    const operatorOpening = session.tokens?.principal.subject === tokens.principal.subject ? session.operatorOpening : undefined;
    const createdAt = session.createdAt;
    this.destroy(session);
    const next = this.create();
    next.createdAt = createdAt; next.tokens = tokens;
    if (invitation) next.invitation = invitation;
    if (opening) next.opening = opening;
    if (operatorOpening) next.operatorOpening = operatorOpening;
    return next;
  }
  setInvitation(session: Session, token: string, delivery: 'EMAIL' | 'CODE' = 'EMAIL'): void {
    if (session.invitation?.token === token && (session.invitation.delivery ?? 'EMAIL') === delivery) return;
    session.invitation = { token, delivery, operationId: randomUUID() };
  }
  destroy(session: Session): void {
    this.sessions.delete(session.id);
    delete session.tokens; delete session.login; delete session.invitation; delete session.refresh; delete session.reauthenticating;
    delete session.opening; delete session.operatorOpening;
  }
  clear(): void { for (const session of this.sessions.values()) this.destroy(session); }
  sweep(): void { for (const session of this.sessions.values()) if (this.expired(session)) this.destroy(session); }
}
