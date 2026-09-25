import { randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';

export type Principal = { subject: string; displayName: string; email?: string; emailVerified: boolean };
export type Tokens = { accessToken: string; refreshToken?: string; expiresAt: number; principal: Principal };
export type LoginTransaction = { state: string; nonce: string; verifier: string; expiresAt: number; returnTo?: string };
export type InvitationState = {
  token: string; operationId: string; confirmation?: { id: string; invitationId: string; digest: string };
  accepting?: boolean; submitted?: boolean; uncertain?: boolean; accepted?: boolean;
};
export type Session = {
  id: string; csrf: string; createdAt: number; lastSeen: number;
  tokens?: Tokens; login?: LoginTransaction; invitation?: InvitationState; refresh?: Promise<Tokens>;
};
const random = () => randomBytes(32).toString('base64url');

export function matchesSecret(actual: unknown, expected: string): boolean {
  if (typeof actual !== 'string' || actual.length > 1024) return false;
  const a = Buffer.from(actual); const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a,b);
}

/** One process; no token/dossier on disk. Restart deliberately expires all browser sessions. */
export class SessionStore {
  private readonly sessions = new Map<string, Session>();
  constructor(private readonly clock: () => number = Date.now, private readonly capacity = 10_000) {}

  private expired(session: Session): boolean {
    const now = this.clock();
    const idle = session.tokens ? 30 * 60_000 : 10 * 60_000;
    return now - session.lastSeen >= idle || now - session.createdAt >= 2 * 60 * 60_000;
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
    const createdAt = session.createdAt;
    this.destroy(session);
    const next = this.create();
    next.createdAt = createdAt; next.tokens = tokens;
    if (invitation) next.invitation = invitation;
    return next;
  }
  setInvitation(session: Session, token: string): void {
    if (session.invitation?.token === token) return;
    session.invitation = { token, operationId: randomUUID() };
  }
  destroy(session: Session): void {
    this.sessions.delete(session.id);
    delete session.tokens; delete session.login; delete session.invitation; delete session.refresh;
  }
  clear(): void { for (const session of this.sessions.values()) this.destroy(session); }
  sweep(): void { for (const session of this.sessions.values()) if (this.expired(session)) this.destroy(session); }
}
