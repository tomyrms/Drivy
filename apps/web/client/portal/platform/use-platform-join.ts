import { useEffect, useRef, useState } from 'react';
import type { z } from 'zod';
import { clearLogoutNotice, noteSessionClosure, readLogoutNotice } from '../../logout-notice';
import {
  formatPlatformCode, isPlatformCode, platformAcceptedResult, platformFailure, platformFailureKind, platformJoinStatus, platformPreviewResult,
  type PlatformPreview,
} from '../../platform-model';
import { endSession, request, RequestFailure, sessionSchema, type Session } from '../../protocol';

export type PlatformAccepted = z.infer<typeof platformAcceptedResult>['data'];

/**
 * Acceptation d'un code d'accès. Le navigateur ne détient que le code saisi : l'aperçu des droits, la confirmation liée
 * à cet aperçu et l'opération rejouable vivent dans la session du relais. Rien n'est accordé avant la réponse du serveur.
 */
export function usePlatformJoin() {
  const [session, setSession] = useState<Session | null>(null);
  const [loaded, setLoaded] = useState(false), [busy, setBusy] = useState(false), [error, setError] = useState<string | null>(null);
  const [code, setCodeState] = useState(''), [codeError, setCodeError] = useState<string | null>(null);
  const [preview, setPreview] = useState<PlatformPreview | null>(null), [uncertain, setUncertain] = useState(false);
  const [accepted, setAccepted] = useState<PlatformAccepted | null>(null);
  const [logoutUnconfirmed, setLogoutUnconfirmed] = useState(readLogoutNotice);
  const running = useRef(false), started = useRef(false), generation = useRef(0);

  async function boot() {
    generation.current += 1;
    // Le compte précédent ne laisse rien à l'écran avant la lecture de la session.
    setLoaded(false); setError(null); setSession(null); setCodeState(''); setCodeError(null); setPreview(null); setUncertain(false); setAccepted(null);
    try {
      const current = await request('session', sessionSchema); setSession(current);
      if (current.authenticated) {
        clearLogoutNotice(); setLogoutUnconfirmed(false);
        const state = await request('platform/join', platformJoinStatus);
        // Une acceptation déjà passée se relit par le même appel : le relais rend son résultat sans rien refaire.
        if (state.accepted) setAccepted((await request('platform/join/accept', platformAcceptedResult, { csrf: current.csrfToken, body: {} })).data);
        else if (state.uncertain) setUncertain(true);
      }
    } catch (reason) { setError(platformFailure(reason)); } finally { setLoaded(true); }
  }
  useEffect(() => { if (started.current) return; started.current = true; void boot(); }, []);

  async function perform(action: () => Promise<void>) {
    if (running.current) return;
    running.current = true; setBusy(true); setError(null);
    try { await action(); } catch (reason) { setError(platformFailure(reason)); } finally { running.current = false; setBusy(false); }
  }
  const changeAccount = () => perform(async () => { noteSessionClosure(await endSession()); setLogoutUnconfirmed(readLogoutNotice()); await boot(); });

  function setCode(value: string) {
    if (busy || uncertain) return;
    setCodeState(formatPlatformCode(value)); setCodeError(null); setPreview(null);
  }
  async function read(csrf: string) {
    return request('platform/join/preview', platformPreviewResult, { csrf, body: { code } });
  }
  const review = () => perform(async () => {
    if (!session) return;
    if (!isPlatformCode(code)) { setCodeError('Saisissez le code reçu : cinq caractères, un tiret, cinq caractères.'); return; }
    setPreview(await read(session.csrfToken));
  });
  const accept = () => perform(async () => {
    if (!session || (!uncertain && !preview)) return;
    try {
      // Premier envoi : la confirmation liée à l'aperçu montré. Reprise : la même opération, sans nouvel aperçu.
      const response = await request('platform/join/accept', platformAcceptedResult, { csrf: session.csrfToken, body: uncertain ? {} : { confirmation: preview?.confirmation } });
      setAccepted(response.data); setPreview(null); setUncertain(false);
    } catch (reason) {
      const kind = platformFailureKind(reason);
      if (kind === 'unconfirmed') setUncertain(true);
      else if (reason instanceof RequestFailure && reason.code === 'PLATFORM_PREVIEW_CHANGED') {
        // Les droits ont bougé depuis l'aperçu : on les remontre, la confirmation reste à donner.
        setPreview(null);
        try { setPreview(await read(session.csrfToken)); } catch { /* Le message ci-dessous suffit. */ }
      } else { setPreview(null); setUncertain(false); }
      throw reason;
    }
  });
  const changeCode = () => { if (!busy && !uncertain) { setPreview(null); setError(null); } };

  return { session, loaded, busy, error, code, codeError, preview, uncertain, accepted, logoutUnconfirmed,
    boot, changeAccount, setCode, review, accept, changeCode };
}
export type PlatformJoinState = ReturnType<typeof usePlatformJoin>;
