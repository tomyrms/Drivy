import { useEffect, useRef, useState } from 'react';
import type { z } from 'zod';
import { clearLogoutNotice, noteSessionClosure, readLogoutNotice } from '../../logout-notice';
import {
  platformFailure, platformFailureKind, platformInvitationResult, platformInvitationsResult, platformIssuedResult, platformJournalResult,
  platformMeResult, platformOperatorResult, platformOperatorsResult,
  type PlatformInvitation, type PlatformJournalEntry, type PlatformMe, type PlatformOperator, type PlatformPending,
} from '../../platform-model';
import { endSession, okSchema, request, sessionSchema, type Session } from '../../protocol';

export type JournalFilter = 'ALL' | 'REFUSED';
export type PlatformAccess = 'unknown' | 'allowed' | 'denied';
type Issued = z.infer<typeof platformIssuedResult>;
const emptyJournal = { items: [] as PlatformJournalEntry[], nextCursor: null as string | null };
const identityKey = (session: Session) => session.authenticated ? `${session.user?.email ?? ''}|${session.user?.displayName ?? ''}` : null;

function journalPath(filter: JournalFilter, cursor?: string | null) {
  const query = new URLSearchParams({ limit: '30' });
  if (filter === 'REFUSED') query.set('result', 'REFUSED');
  if (cursor) query.set('cursor', cursor);
  return `platform/journal?${query}`;
}

/**
 * Console des opérateurs. Le navigateur ne garde que des projections de lecture : chaque droit est relu par l'API à
 * chaque appel, et le premier refus « plus opérateur » vide l'écran. Aucune donnée n'entre dans le stockage du navigateur.
 */
export function usePlatformConsole() {
  const [session, setSession] = useState<Session | null>(null);
  const [loaded, setLoaded] = useState(false), [busy, setBusy] = useState(false), [access, setAccess] = useState<PlatformAccess>('unknown');
  const [me, setMe] = useState<PlatformMe | null>(null), [operators, setOperators] = useState<PlatformOperator[]>([]);
  const [invitations, setInvitations] = useState<PlatformInvitation[]>([]), [pending, setPending] = useState<PlatformPending | null>(null);
  const [journal, setJournal] = useState(emptyJournal), [filter, setFilter] = useState<JournalFilter>('ALL');
  const [issued, setIssued] = useState<Issued | null>(null), [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null), [conflict, setConflict] = useState(false), [uncertain, setUncertain] = useState(false);
  const [removing, setRemoving] = useState<PlatformOperator | null>(null);
  const [logoutUnconfirmed, setLogoutUnconfirmed] = useState(readLogoutNotice);
  const running = useRef(false), started = useRef(false), generation = useRef(0), identity = useRef<string | null>(null);
  const invite = useRef<{ operationId: string; email: string; validityDays: number } | null>(null);
  const revocations = useRef(new Map<string, { version: number; operationId: string }>());

  function purge() {
    setMe(null); setOperators([]); setInvitations([]); setPending(null); setJournal(emptyJournal); setFilter('ALL'); setIssued(null);
    setRemoving(null); setCopied(false); setUncertain(false); setConflict(false);
    invite.current = null; revocations.current.clear();
  }
  /** Retourne le genre d'erreur : un refus « plus opérateur » vide tout, un conflit demande une relecture. */
  function fail(reason: unknown) {
    const kind = platformFailureKind(reason);
    if (kind === 'denied') { generation.current += 1; purge(); setAccess('denied'); setError(null); return kind; }
    if (kind === 'conflict') setConflict(true);
    setError(platformFailure(reason));
    return kind;
  }

  async function load(value: JournalFilter = filter) {
    const current = generation.current;
    const mine = await request('platform/me', platformMeResult);
    const [team, listing, log] = await Promise.all([
      request('platform/operators', platformOperatorsResult), request('platform/invitations', platformInvitationsResult),
      request(journalPath(value), platformJournalResult),
    ]);
    // Un autre compte ou un refus est arrivé pendant la lecture : ces réponses ne sont plus celles de l'écran.
    if (current !== generation.current) return;
    setMe(mine.data); setOperators(team.data.items); setInvitations(listing.data.items); setPending(listing.pending ?? null);
    setJournal(log.data); setFilter(value); setAccess('allowed');
  }
  async function boot() {
    generation.current += 1;
    setLoaded(false); setError(null); setSession(null); setAccess('unknown'); purge();
    try {
      const current = await request('session', sessionSchema);
      setSession(current); identity.current = identityKey(current);
      if (current.authenticated) { clearLogoutNotice(); setLogoutUnconfirmed(false); await load('ALL'); }
    } catch (reason) { fail(reason); } finally { setLoaded(true); }
  }
  useEffect(() => { if (started.current) return; started.current = true; void boot(); }, []);
  // Un autre onglet a changé de compte : cet écran ne montre jamais les projections de l'ancien.
  useEffect(() => {
    if (!loaded) return;
    const check = async () => {
      if (document.visibilityState !== 'visible' || running.current) return;
      try {
        const current = await request('session', sessionSchema);
        if (identityKey(current) !== identity.current) void boot();
      } catch { /* La prochaine action le dira. */ }
    };
    document.addEventListener('visibilitychange', check); window.addEventListener('focus', check);
    return () => { document.removeEventListener('visibilitychange', check); window.removeEventListener('focus', check); };
  }, [loaded]);

  async function perform(action: () => Promise<void>) {
    if (running.current) return;
    running.current = true; setBusy(true); setError(null); setConflict(false);
    try { await action(); }
    catch (reason) {
      if (fail(reason) === 'conflict') {
        // Une autre personne a modifié la ligne : on relit avant de laisser recommencer.
        setRemoving(null);
        try { await load(); } catch (next) { fail(next); }
      }
    } finally { running.current = false; setBusy(false); }
  }

  const refresh = () => perform(() => load());
  const changeAccount = () => perform(async () => { noteSessionClosure(await endSession()); setLogoutUnconfirmed(readLogoutNotice()); await boot(); });

  const sendInvitation = (email: string, validityDays: number) => perform(async () => {
    if (!session) return;
    // Une réponse perdue se rejoue à l'identique : même opération, mêmes données. Un refus définitif libère l'émission.
    const operation = invite.current ?? (invite.current = { operationId: crypto.randomUUID(), email, validityDays });
    try {
      const result = await request('platform/invitations', platformIssuedResult, { csrf: session.csrfToken, body: { ...operation } });
      invite.current = null; setUncertain(false); setIssued(result); setCopied(false);
    } catch (reason) {
      if (platformFailureKind(reason) === 'unconfirmed') setUncertain(true); else { invite.current = null; setUncertain(false); }
      throw reason;
    }
    await load();
  });
  /** Après une coupure ou un rechargement : le relais rend le même code pour la même opération, sans en créer un second. */
  const resumeInvitation = () => perform(async () => {
    if (!session || !pending) return;
    const result = await request('platform/invitations', platformIssuedResult, { csrf: session.csrfToken, body: {
      operationId: pending.operationId, email: pending.email, ...(pending.validityDays !== undefined ? { validityDays: pending.validityDays } : {}),
    } });
    setIssued(result); setCopied(false); await load();
  });
  const closeCode = () => perform(async () => {
    if (!session) return;
    await request('platform/invitations/clear', okSchema, { csrf: session.csrfToken, body: {} });
    setIssued(null); setPending(null); setCopied(false); await load();
  });

  async function revokeOne<T>(kind: 'invitations' | 'operators', id: string, version: number, schema: z.ZodType<T>): Promise<T> {
    if (!session) throw new Error('session');
    const key = `${kind}:${id}`;
    let operation = revocations.current.get(key);
    if (!operation || operation.version !== version) { operation = { version, operationId: crypto.randomUUID() }; revocations.current.set(key, operation); }
    try {
      const result = await request(`platform/${kind}/${id}/revoke`, schema, { csrf: session.csrfToken, body: { operationId: operation.operationId, version } });
      revocations.current.delete(key);
      return result;
    } catch (reason) {
      // Seule une réponse inconnue garde l'opération : la même demande, rejouée, dira si elle a eu lieu.
      if (platformFailureKind(reason) !== 'unconfirmed') revocations.current.delete(key);
      throw reason;
    }
  }
  const revokeInvitation = (item: PlatformInvitation) => perform(async () => { await revokeOne('invitations', item.id, item.version, platformInvitationResult); await load(); });
  const removeOperator = () => perform(async () => {
    if (!removing) return;
    const result = await revokeOne('operators', removing.id, removing.version, platformOperatorResult);
    setRemoving(null);
    if (result.data.self) { generation.current += 1; purge(); setAccess('denied'); return; }
    await load();
  });

  // Ouvrir ou fermer la confirmation repart d'un écran sans erreur : celle d'un retrait refusé reste dans la boîte, pas derrière elle.
  const chooseRemoval = (operator: PlatformOperator | null) => { setError(null); setRemoving(operator); };
  const chooseFilter = (value: JournalFilter) => perform(async () => {
    const log = await request(journalPath(value), platformJournalResult);
    setFilter(value); setJournal(log.data);
  });
  const moreJournal = () => perform(async () => {
    if (!journal.nextCursor) return;
    const log = await request(journalPath(filter, journal.nextCursor), platformJournalResult);
    setJournal(previous => ({ items: [...previous.items, ...log.data.items], nextCursor: log.data.nextCursor }));
  });
  async function copy() {
    if (!issued) return;
    setCopied(false);
    try { await navigator.clipboard.writeText(issued.code); setCopied(true); }
    catch { setError('La copie a échoué. Sélectionnez et copiez le code affiché.'); }
  }

  return { session, loaded, busy, access, me, operators, invitations, pending, journal, filter, issued, copied, error, conflict, uncertain,
    removing, chooseRemoval, logoutUnconfirmed, boot, refresh, changeAccount, sendInvitation, resumeInvitation, closeCode,
    revokeInvitation, removeOperator, chooseFilter, moreJournal, copy };
}
export type PlatformConsoleState = ReturnType<typeof usePlatformConsole>;
