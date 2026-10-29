import { useEffect, useRef, useState } from 'react';
import { readInvitationLink, type InvitationLink } from '../../invitation-link';
import {
  acceptedSchema, endSession, errorMessage, meSchema, okSchema, previewSchema, request, RequestFailure, sessionSchema,
  type InvitationPreview, type Me, type Member, type Session,
} from '../../protocol';
import {
  acceptanceFailure, accountEntryDestination, admissionNeedsCheck, canAcceptInvitation, invitationNeedsVerifiedEmail, sessionLost,
  type AccessKind, type EntryPageKind, type EntryRoutes,
} from './entry-model';

type Preview = { data: InvitationPreview; confirmation: string };

/**
 * Session, linked schools and received invitation of `/app` and `/app/invitation`: the historical `App` behaviour,
 * without its rendering. One request at a time; a late answer of a replaced reading (`generation`) changes nothing.
 * The invitation link held in memory is sent once, then forgotten.
 */
export function useEntrySession({ invitationLink, initialPage, routes }: { invitationLink: InvitationLink; initialPage: EntryPageKind; routes: EntryRoutes }) {
  const [page, setPage] = useState<EntryPageKind>(initialPage);
  const pageRef = useRef<EntryPageKind>(initialPage);
  const [session, setSession] = useState<Session | null>(null);
  const [me, setMe] = useState<Me | null>(null);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [accepted, setAccepted] = useState<Member | null>(null);
  const [reviewed, setReviewed] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [busy, setBusy] = useState<string | null>('Ouverture de votre espace…');
  const [error, setError] = useState<string | null>(null);
  const [uncertain, setUncertain] = useState(false);
  const [linkMustReopen, setLinkMustReopen] = useState(false);
  const [linkError, setLinkError] = useState(invitationLink.error);
  const [enteringCode, setEnteringCode] = useState(false);
  const inFlight = useRef(false);
  const generation = useRef(0);
  const acceptedSession = useRef<string | null>(null);
  const checkedSession = useRef<string | null>(null);
  const heading = useRef<HTMLHeadingElement>(null);

  function navigate(next: EntryPageKind) {
    pageRef.current = next;
    setPage(next);
    window.history.replaceState(null, '', next === 'invitation' ? routes.invitation : routes.account);
  }

  /**
   * Read the session, the person and the pending invitation again. A reading the person asked for (Actualiser,
   * Réessayer, after an action) keeps the page on screen; a restoration from the browser history (`keepView` false)
   * is not an authorization check, so it shows nothing until the server answers.
   */
  async function refresh(current: number, keepView = true) {
    setPreview(null);
    setMe(null);
    setReviewed(false);
    if (!keepView) { setMe(null); setSession(null); setLoaded(false); }
    let next = await request('session', sessionSchema);
    if (current !== generation.current) return;
    if (acceptedSession.current !== next.csrfToken) setAccepted(null);
    if (checkedSession.current !== next.csrfToken) setUncertain(false);
    checkedSession.current = next.csrfToken;
    if (invitationLink.token) {
      try {
        await request('invitation', okSchema, { csrf: next.csrfToken, body: { token: invitationLink.token } });
      } catch (cause) {
        if (current !== generation.current) return;
        if (!admissionNeedsCheck(cause)) throw cause;
        // The new link was not admitted. Recover the preceding server-owned intention,
        // instead of repeatedly trying to replace its unknown result.
        setUncertain(true);
        setError('Une précédente acceptation doit être vérifiée. Le nouveau lien n’a pas été ouvert ; vous pourrez le rouvrir ensuite.');
      }
      if (current !== generation.current) return;
      invitationLink.token = null;
      next = await request('session', sessionSchema);
      if (current !== generation.current) return;
    }
    setSession(next);
    if (invitationLink.error) throw new RequestFailure('INVITATION_INVALID');
    if (!next.authenticated) { setMe(null); return; }
    try {
      const result = await request('me', meSchema);
      if (current !== generation.current) return;
      setMe(result.data);
    } catch (cause) {
      if (current !== generation.current) return;
      if (!(cause instanceof RequestFailure) || cause.code !== 'IDENTITY_NOT_LINKED') throw cause;
      setMe(null);
    }
    if (current !== generation.current) return;
    if (next.invitationPending && pageRef.current === 'invitation') {
      const result = await request('invitation/preview', previewSchema, { csrf: next.csrfToken, body: {} });
      if (current !== generation.current) return;
      setPreview(result);
      setUncertain(result.uncertain === true);
    }
  }

  async function perform(label: string, action: (current: number) => Promise<void>) {
    if (inFlight.current) return;
    inFlight.current = true;
    const current = ++generation.current;
    setBusy(label);
    setError(null);
    try { await action(current); }
    catch (cause) {
      if (current !== generation.current) return;
      if (sessionLost(cause)) {
        setSession(null); setMe(null); setPreview(null); setReviewed(false); setAccepted(null);
        acceptedSession.current = null;
        if (pageRef.current === 'invitation') setLinkMustReopen(true);
      }
      setError(errorMessage(cause));
    } finally {
      if (current === generation.current) {
        inFlight.current = false;
        setBusy(null);
        setLoaded(true);
      }
    }
  }

  useEffect(() => {
    void perform('Ouverture de votre espace…', refresh);
    const onPageShow = (event: PageTransitionEvent) => {
      // A browser history restoration is not a fresh authorization check.
      if (event.persisted) {
        generation.current++;
        inFlight.current = false;
        void perform('Vérification de vos accès…', current => refresh(current, false));
      }
    };
    const onHashChange = () => {
      const incoming = readInvitationLink();
      if (!incoming.token && !incoming.error) return;
      // Pasting a new fragment can reuse this document. Drop the old preview
      // immediately; a late response must not restore the previous school.
      generation.current++;
      inFlight.current = false;
      invitationLink.token = incoming.token;
      invitationLink.error = incoming.error;
      setLinkError(incoming.error);
      setSession(null); setMe(null); setPreview(null); setAccepted(null); setLoaded(false);
      setReviewed(false); setUncertain(false); setLinkMustReopen(false);
      navigate('invitation');
      void perform('Préparation de votre invitation…', refresh);
    };
    window.addEventListener('pageshow', onPageShow);
    window.addEventListener('hashchange', onHashChange);
    return () => {
      generation.current++;
      inFlight.current = false;
      window.removeEventListener('pageshow', onPageShow);
      window.removeEventListener('hashchange', onHashChange);
    };
  }, []);

  useEffect(() => {
    document.title = page === 'invitation' ? 'Rejoindre votre école · Drivy' : 'Votre espace · Drivy';
    if (loaded) heading.current?.focus({ preventScroll: true });
  }, [page, loaded]);

  /** An opening code continues to the school form; otherwise the account page is read again. */
  function signedIn(kind: AccessKind | null) {
    setEnteringCode(false);
    const destination = accountEntryDestination(kind);
    if (destination === '/app/ouvrir') { window.location.assign(routes.opening); return; }
    if (destination === '/app/invitation') navigate('invitation');
    setLinkMustReopen(false);
    void perform('Ouverture de votre espace…', refresh);
  }

  async function logout() {
    if (!session || uncertain) return;
    await perform('Déconnexion en cours…', async current => {
      await endSession();
      if (current !== generation.current) return;
      setMe(null); setPreview(null); setSession(null); setAccepted(null); setReviewed(false);
      if (pageRef.current === 'invitation') setLinkMustReopen(true);
      setEnteringCode(false);
      navigate('account');
      await refresh(current);
    });
  }

  async function clearInvitation() {
    const csrf = session?.csrfToken;
    if (!csrf || uncertain) return;
    await perform('Fermeture de l’invitation…', async current => {
      await request('invitation/clear', okSchema, { csrf, body: {} });
      if (current !== generation.current) return;
      invitationLink.token = null;
      invitationLink.error = false;
      setLinkError(false);
      setPreview(null); setReviewed(false); setUncertain(false);
      navigate('account');
      await refresh(current);
    });
  }

  async function acceptInvitation() {
    const shown = preview;
    const csrf = session?.csrfToken;
    if (!shown || !csrf || !canAcceptInvitation(shown.data, session, reviewed)) return;
    await perform('Confirmation par votre école…', async current => {
      try {
        const result = await request('invitation/accept', acceptedSchema, {
          csrf,
          body: { invitationId: shown.data.invitationId, confirmation: shown.confirmation },
        });
        if (current !== generation.current) return;
        if (result.data.schoolId !== shown.data.schoolId) throw new RequestFailure('INVALID_RESPONSE');
        acceptedSession.current = csrf;
        setAccepted(result.data);
        setUncertain(false);
      } catch (cause) {
        if (current !== generation.current) return;
        const failure = acceptanceFailure(cause);
        if (failure.dropPreview) { setPreview(null); setReviewed(false); }
        if (failure.uncertain) setUncertain(true);
        throw cause;
      }
      setPreview(null); setReviewed(false);
      navigate('account');
      await refresh(current);
    });
  }

  const authenticated = session?.authenticated === true;
  return {
    page, session, me, preview, reviewed, setReviewed, loaded, busy, error, uncertain, linkMustReopen, linkError, enteringCode, setEnteringCode, heading,
    authenticated,
    personName: me?.displayName || session?.user?.displayName || 'Votre compte',
    /** The receipt of an acceptance is shown only to the session that sent it. */
    accepted: accepted && session && acceptedSession.current === session.csrfToken ? accepted : null,
    emailVerificationRequired: invitationNeedsVerifiedEmail(preview?.data, session),
    canAccept: canAcceptInvitation(preview?.data, session, reviewed),
    refresh: (label = 'Vérification de vos accès…') => void perform(label, refresh),
    signedIn, logout: () => void logout(), clearInvitation: () => void clearInvitation(), acceptInvitation: () => void acceptInvitation(),
    /** The sign-in form lives on the account page; the reminder to reopen the link stays until sign-in. */
    openAccount: () => { setError(null); navigate('account'); },
  };
}
export type EntrySessionState = ReturnType<typeof useEntrySession>;
