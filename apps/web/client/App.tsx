import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { readInvitationLink } from './invitation-link';
import type { InvitationLink } from './invitation-link';
import {
  acceptedSchema, errorMessage, loginSchema, meSchema, okSchema, previewSchema,
  request, RequestFailure, roleLabel, sessionSchema,
} from './protocol';
import type { InvitationPreview, Me, Member, Session } from './protocol';

type Preview = { data: InvitationPreview; confirmation: string };
type Page = 'account' | 'invitation';

export function App({ invitationLink }: { invitationLink: InvitationLink }) {
  const initialPage = window.location.pathname.replace(/\/$/, '') === '/app/invitation' ? 'invitation' : 'account';
  const [page, setPage] = useState<Page>(initialPage);
  const pageRef = useRef<Page>(initialPage);
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
  const inFlight = useRef(false);
  const generation = useRef(0);
  const acceptedSession = useRef<string | null>(null);
  const heading = useRef<HTMLHeadingElement>(null);

  function navigate(next: Page) {
    pageRef.current = next;
    setPage(next);
    window.history.replaceState(null, '', next === 'invitation' ? '/app/invitation' : '/app/');
  }

  async function refresh(current: number) {
    setMe(null);
    setPreview(null);
    setReviewed(false);
    setSession(null);
    let next = await request('session', sessionSchema);
    if (current !== generation.current) return;
    if (acceptedSession.current !== next.csrfToken) setAccepted(null);
    if (invitationLink.token) {
      try {
        await request('invitation', okSchema, { csrf: next.csrfToken, body: { token: invitationLink.token } });
      } catch (cause) {
        if (current !== generation.current) return;
        if (!(cause instanceof RequestFailure) || !['INVITATION_IN_PROGRESS', 'INVITATION_RESULT_UNKNOWN'].includes(cause.code)) throw cause;
        // The new link was not admitted. Recover the preceding server-owned
        // intention, instead of repeatedly trying to replace its unknown result.
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
    if (!next.authenticated) return;
    try {
      const result = await request('me', meSchema);
      if (current !== generation.current) return;
      setMe(result.data);
    } catch (cause) {
      if (!(cause instanceof RequestFailure) || cause.code !== 'IDENTITY_NOT_LINKED') throw cause;
    }
    if (current !== generation.current) return;
    if (next.invitationPending && pageRef.current === 'invitation') {
      const result = await request('invitation/preview', previewSchema, { csrf: next.csrfToken, body: {} });
      if (current !== generation.current) return;
      setPreview(result);
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
      if (cause instanceof RequestFailure && (cause.status === 401 || cause.code === 'CSRF_REJECTED')) {
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
      if (event.persisted) void perform('Vérification de vos accès…', refresh);
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
      setSession(null); setMe(null); setPreview(null); setAccepted(null);
      setReviewed(false); setUncertain(false); setLinkMustReopen(false);
      navigate('invitation');
      void perform('Préparation de votre invitation…', refresh);
    };
    window.addEventListener('pageshow', onPageShow);
    window.addEventListener('hashchange', onHashChange);
    return () => {
      generation.current++;
      window.removeEventListener('pageshow', onPageShow);
      window.removeEventListener('hashchange', onHashChange);
    };
  }, []);

  useEffect(() => {
    document.title = page === 'invitation' ? 'Rejoindre votre école · Drivy' : 'Votre espace · Drivy';
    if (loaded) heading.current?.focus({ preventScroll: true });
  }, [page, loaded]);

  async function login() {
    await perform('Ouverture de la connexion…', async current => {
      const next = await request('session', sessionSchema);
      if (current !== generation.current) return;
      const result = await request('login', loginSchema, { csrf: next.csrfToken, body: {} });
      if (current !== generation.current) return;
      const target = new URL(result.url);
      const local = ['localhost', '127.0.0.1', '[::1]'].includes(target.hostname);
      const localPage = window.location.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(window.location.hostname);
      if ((target.protocol !== 'https:' && !(localPage && local && target.protocol === 'http:')) || target.username || target.password || target.hash) {
        throw new RequestFailure('INVALID_RESPONSE');
      }
      window.location.assign(target.href);
    });
  }

  async function logout() {
    const csrf = session?.csrfToken;
    if (!csrf) return;
    await perform('Déconnexion en cours…', async current => {
      setMe(null); setPreview(null); setSession(null); setAccepted(null); setReviewed(false);
      await request('logout', okSchema, { csrf, body: {} });
      if (current !== generation.current) return;
      if (pageRef.current === 'invitation') setLinkMustReopen(true);
      await refresh(current);
    });
  }

  async function clearInvitation() {
    const csrf = session?.csrfToken;
    if (!csrf) return;
    await perform('Fermeture de l’invitation…', async current => {
      await request('invitation/clear', okSchema, { csrf, body: {} });
      if (current !== generation.current) return;
      invitationLink.token = null;
      invitationLink.error = false;
      setPreview(null); setReviewed(false); setUncertain(false);
      navigate('account');
      await refresh(current);
    });
  }

  async function acceptInvitation() {
    const shown = preview;
    const csrf = session?.csrfToken;
    if (!shown || !csrf || !reviewed || session?.user?.emailVerified !== true) return;
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
        if (cause instanceof RequestFailure && cause.code === 'INVITATION_PREVIEW_CHANGED') {
          setPreview(null); setReviewed(false);
        }
        if (cause instanceof RequestFailure && (cause.status === 0 || cause.status >= 500)) setUncertain(true);
        throw cause;
      }
      setPreview(null); setReviewed(false);
      navigate('account');
      await refresh(current);
    });
  }

  const isBusy = busy !== null;
  const personName = me?.displayName || session?.user?.displayName || 'Votre compte';

  return (
    <div className="app-shell">
      <a className="skip-link" href="#main">Aller au contenu</a>
      <header className="site-header">
        <a className="brand" href="/app/" aria-label="Drivy, votre espace">
          <span className="brand-symbol" aria-hidden="true"><svg viewBox="0 0 32 32"><path d="m11 24 5-16 5 16-5-4Z" /></svg></span>
          <span>Drivy</span>
        </a>
        {session?.authenticated && <div className="account-actions">
          <span className="signed-in-label">{personName}</span>
          <button className="button quiet" type="button" onClick={() => void logout()} disabled={isBusy}>Déconnecter ce navigateur</button>
        </div>}
      </header>

      <main id="main" className={page === 'invitation' ? 'main invitation-main' : 'main'}>
        <div className="page-heading">
          <p className="eyebrow">{page === 'invitation' ? 'Une invitation de votre école' : 'Votre espace scolaire'}</p>
          <h1 ref={heading} tabIndex={-1}>{page === 'invitation' ? 'Rejoindre votre école' : session?.authenticated ? 'Bienvenue dans Drivy' : 'Votre école, à portée de main'}</h1>
          <p className="lead">{page === 'invitation'
            ? 'Vérifiez l’école et le compte utilisé avant de confirmer votre rattachement.'
            : 'Un même compte pour retrouver vos écoles et les accès qu’elles vous confient.'}</p>
        </div>

        <div className="feedback" aria-live="polite" aria-atomic="true">
          {busy && <p className="loading"><span className="spinner" aria-hidden="true" />{busy}</p>}
        </div>
        {error && <div className="notice error" role="alert">
          <strong>Une vérification est nécessaire</strong>
          <p>{error}</p>
          {uncertain && <p>La réponse d’acceptation reste incertaine. Réessayer conserve la même demande ; ne créez pas une nouvelle invitation pour la remplacer.</p>}
          {(!uncertain || !preview) && <button className="button secondary" type="button" disabled={isBusy} onClick={() => void perform('Vérification de vos accès…', refresh)}>{uncertain ? 'Retrouver la demande' : 'Actualiser la page'}</button>}
        </div>}

        {linkMustReopen && <div className="notice warning"><strong>Reprendre votre invitation</strong><p>Connectez-vous avec le compte invité, puis rouvrez le lien envoyé par votre école. Une déconnexion ferme aussi l’invitation préparée dans ce navigateur.</p></div>}

        {!loaded && <div className="card skeleton-card" aria-hidden="true"><span /><span /><span /></div>}

        {loaded && !session?.authenticated && <section className="card sign-in-card" aria-labelledby="sign-in-title">
          <Symbol kind="account" />
          <h2 id="sign-in-title">{page === 'invitation' ? 'Connectez-vous avec le compte invité' : 'Connectez-vous à votre compte'}</h2>
          <p>{page === 'invitation'
            ? 'Utilisez l’adresse à laquelle votre école vous a envoyé ce lien. Vous pourrez relire les informations avant d’accepter.'
            : 'Votre connexion vous permet de retrouver les écoles auxquelles vous êtes rattaché.'}</p>
          <button className="button primary" type="button" disabled={isBusy || invitationLink.token !== null || invitationLink.error} onClick={() => void login()}>Se connecter</button>
          <p className="caption">La connexion s’ouvre dans le service sécurisé de Drivy.</p>
          {page === 'invitation' && <p className="caption">Si vous fermez cette page avant la préparation du lien, rouvrez l’invitation envoyée par votre école.</p>}
        </section>}

        {loaded && session?.authenticated && page === 'invitation' && <>
          <section className="identity-strip" aria-label="Compte utilisé">
            <Symbol kind="account" />
            <div><span className="small-label">Vous utilisez ce compte</span><strong>{personName}</strong>{session.user?.email && <span>{session.user.email}</span>}</div>
            <button type="button" className="button quiet" onClick={() => void logout()} disabled={isBusy}>Changer de compte</button>
          </section>
          <p className="caption">Pour changer de compte, déconnectez ce navigateur puis rouvrez votre lien d’invitation après la connexion.</p>
          {session.user?.emailVerified !== true && <div className="notice warning"><strong>Adresse à vérifier</strong><p>Vérifiez votre adresse auprès du service de connexion, puis reconnectez-vous avant d’accepter l’invitation.</p></div>}
          {preview && <section className="card invitation-card" aria-labelledby="invitation-school-name">
            <div className="school-heading"><Symbol kind="school" /><div><span className="small-label">L’école qui vous invite</span><h2 id="invitation-school-name">{preview.data.schoolName}</h2></div></div>
            <dl className="invitation-facts">
              <div><dt>Votre rôle</dt><dd>{preview.data.roles.map(roleLabel).join(' · ')}</dd></div>
              <div><dt>Invitation adressée à</dt><dd>{preview.data.maskedEmail}</dd></div>
              <div><dt>Lien valable jusqu’au</dt><dd><time dateTime={preview.data.expiresAt}>{formatDate(preview.data.expiresAt)}</time></dd></div>
            </dl>
            <div className="policy">
              <h3>Vos données dans cette école</h3>
              <p className="policy-copy">{preview.data.notice.noticeText}</p>
              <h3>Conservation des données</h3>
              <p className="policy-copy">{preview.data.notice.retentionText}</p>
              <p className="caption">Pour toute question : <a href={`mailto:${preview.data.notice.contactEmail}`}>{preview.data.notice.contactEmail}</a></p>
            </div>
            <div className="acceptance">
              <label className="checkbox-row"><input type="checkbox" checked={reviewed} onChange={event => setReviewed(event.target.checked)} disabled={isBusy} /><span>Je confirme rejoindre <strong>{preview.data.schoolName}</strong> avec le compte indiqué ci-dessus.</span></label>
              <p className="caption">Ce rattachement ne réserve aucun cours et n’autorise aucun enregistrement GPS.</p>
              <div className="button-row">
                <button type="button" className="button primary" disabled={isBusy || !reviewed || session.user?.emailVerified !== true} onClick={() => void acceptInvitation()}>{uncertain ? 'Vérifier et réessayer' : 'Rejoindre cette école'}</button>
                <button type="button" className="button secondary" disabled={isBusy || uncertain} onClick={() => void clearInvitation()}>Pas maintenant</button>
              </div>
              <p className="caption">{uncertain ? 'Vérifiez d’abord le résultat de la demande déjà envoyée avant de fermer cette invitation.' : '« Pas maintenant » laisse le lien utilisable jusqu’à son expiration.'}</p>
            </div>
          </section>}
          {!preview && !isBusy && !error && <section className="card empty-state"><Symbol kind="school" /><h2>Aucune invitation à afficher</h2><p>Ouvrez le lien le plus récent envoyé par votre école. Vous pouvez aussi retrouver les écoles déjà liées à votre compte.</p><a className="button secondary" href="/app/">Voir mes écoles</a></section>}
        </>}

        {loaded && session?.authenticated && page === 'account' && <>
          {accepted && acceptedSession.current === session.csrfToken && <div className="notice success" role="status"><strong>Vous avez rejoint {accepted.schoolName}</strong><p>Votre rattachement à l’école a été confirmé.</p></div>}
          {session.invitationPending && <div className="invitation-banner"><div><strong>Une invitation vous attend</strong><p>Relisez les informations de l’école avant de l’accepter.</p></div><a className="button secondary" href="/app/invitation">Voir l’invitation</a></div>}
          <section className="card schools-card" aria-labelledby="schools-title">
            <div className="section-heading"><div><span className="small-label">{personName}</span><h2 id="schools-title">Vos écoles</h2></div><button className="button quiet" disabled={isBusy} type="button" onClick={() => void perform('Actualisation de vos écoles…', refresh)}>Actualiser</button></div>
            {me && me.memberships.length > 0 ? <ul className="school-list">{me.memberships.map(member => <li key={member.membershipId}><Symbol kind="school" /><div><h3>{member.schoolName}</h3><p>{member.roles.map(roleLabel).join(' · ')}</p></div></li>)}</ul>
              : !isBusy && !error ? <div className="empty-state"><Symbol kind="school" /><h3>Votre école n’apparaît pas encore</h3><p>Rejoignez-la avec le lien qu’elle vous a envoyé. Si vous n’avez pas d’invitation, contactez votre école.</p></div>
                : isBusy ? <p className="muted">Vos accès sont en cours de vérification.</p> : <p className="muted">Vos écoles ne peuvent pas être affichées pour le moment.</p>}
          </section>
        </>}
      </main>
      <footer className="site-footer"><span>Drivy</span><p>Vos accès sont propres à chaque école.</p></footer>
    </div>
  );
}

function Symbol({ kind }: { kind: 'account' | 'school' }) {
  const content: ReactNode = kind === 'account'
    ? <><circle cx="12" cy="8" r="3.5" /><path d="M5 21v-3a7 7 0 0 1 14 0v3" /></>
    : <><path d="M4 21V5l8-3 8 3v16M2 21h20M9 21v-5h6v5M8 7h1m6 0h1M8 11h1m6 0h1" /></>;
  return <span className="symbol" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">{content}</svg></span>;
}

function formatDate(value: string): string {
  return new Intl.DateTimeFormat('fr-CH', { dateStyle: 'long', timeStyle: 'short' }).format(new Date(value));
}
