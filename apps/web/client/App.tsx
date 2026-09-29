import { useEffect, useRef, useState } from 'react';
import { readInvitationLink } from './invitation-link';
import type { InvitationLink } from './invitation-link';
import {
  acceptedSchema, errorMessage, loginSchema, meSchema, okSchema, previewSchema,
  request, RequestFailure, roleLabel, sessionSchema,
} from './protocol';
import type { InvitationPreview, Me, Member, Session } from './protocol';
import { StatusBadge, Symbol } from './ui';

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
  const emailVerified = session?.user?.emailVerified === true;
  const acceptanceHint = !reviewed && emailVerified;

  return (
    <div className="app-shell">
      <a className="skip-link" href="#main">Aller au contenu</a>
      <header className="site-header">
        <a className="brand" href="/app/" aria-label="Drivy, votre espace">
          <span className="brand-symbol" aria-hidden="true"><svg viewBox="0 0 32 32"><path d="m11 24 5-16 5 16-5-4Z" /></svg></span>
          <span>Drivy</span>
        </a>
        {session?.authenticated && <button className="button quiet" type="button" onClick={() => void logout()} disabled={isBusy}>Se déconnecter</button>}
      </header>

      <main id="main" className="main" aria-busy={!loaded}>
        <div className="page-heading">
          <p className="context">{page === 'invitation' ? 'Invitation de votre école' : 'Votre espace'}</p>
          <h1 ref={heading} tabIndex={-1}>{page === 'invitation' ? 'Rejoindre votre école' : session?.authenticated ? 'Bienvenue dans Drivy' : 'Votre école, à portée de main'}</h1>
          <p className="lead">{page === 'invitation'
            ? 'Vérifiez l’école et le compte utilisé avant de confirmer votre rattachement.'
            : session?.authenticated ? personName : 'Un seul compte pour retrouver vos écoles et les accès qu’elles vous donnent.'}</p>
        </div>

        <div className="feedback" aria-live="polite" aria-atomic="true">
          {busy && <p className="loading"><span className="spinner" aria-hidden="true" />{busy}</p>}
        </div>

        {error && <div className="notice error" role="alert">
          <Symbol kind="alert" />
          <div className="notice-body">
            <strong>Une vérification est nécessaire</strong>
            <p>{error}</p>
            {uncertain && <p>La réponse à votre acceptation n’est pas encore connue. Réessayer conserve la même demande : ne demandez pas de nouvelle invitation pour la remplacer.</p>}
            {(!uncertain || !preview) && <button className="button retry" type="button" disabled={isBusy} onClick={() => void perform('Vérification de vos accès…', refresh)}>
              <Symbol kind="refresh" bare />{uncertain ? 'Retrouver la demande' : 'Réessayer'}
            </button>}
          </div>
        </div>}

        {linkMustReopen && <div className="notice warning">
          <Symbol kind="alert" />
          <div className="notice-body">
            <strong>Reprendre votre invitation</strong>
            <p>Connectez-vous avec le compte invité, puis rouvrez le lien envoyé par votre école. La déconnexion ferme aussi l’invitation préparée dans ce navigateur.</p>
          </div>
        </div>}

        {!loaded && <div className="panel skeleton" aria-hidden="true"><span /><span /><span /></div>}

        {loaded && !session?.authenticated && <section className="panel sign-in" aria-labelledby="sign-in-title">
          <Symbol kind="account" tile />
          <h2 id="sign-in-title">{page === 'invitation' ? 'Connectez-vous avec le compte invité' : 'Connectez-vous à votre compte'}</h2>
          <p className="secondary-text">{page === 'invitation'
            ? 'Utilisez l’adresse à laquelle votre école a envoyé ce lien. Vous pourrez relire les informations avant d’accepter.'
            : 'Retrouvez les écoles auxquelles vous êtes rattaché.'}</p>
          <button className="button primary" type="button" disabled={isBusy || invitationLink.token !== null || invitationLink.error} onClick={() => void login()}>Se connecter</button>
          <p className="caption with-symbol"><Symbol kind="lock" bare />La connexion s’ouvre sur le service sécurisé de Drivy.</p>
          {page === 'invitation' && <p className="caption">Si vous fermez cette page avant la fin de la préparation, rouvrez le lien envoyé par votre école.</p>}
        </section>}

        {loaded && session?.authenticated && page === 'invitation' && <>
          <section className="section" aria-labelledby="identity-title">
            <h2 id="identity-title" className="section-title">Compte utilisé</h2>
            <div className="identity-row">
              <Symbol kind="account" />
              <div className="row-text">
                <strong className="row-title">{personName}</strong>
                {session.user?.email && <span className="row-meta">{session.user.email}</span>}
                <StatusBadge tone={emailVerified ? 'success' : 'warning'} symbol={emailVerified ? 'check' : 'alert'}>{emailVerified ? 'Adresse vérifiée' : 'Adresse à vérifier'}</StatusBadge>
              </div>
              <button type="button" className="button quiet" onClick={() => void logout()} disabled={isBusy}>Changer de compte</button>
            </div>
            <p className="caption">Pour changer de compte, déconnectez-vous puis rouvrez votre lien d’invitation une fois connecté.</p>
            {!emailVerified && <div className="notice warning">
              <Symbol kind="alert" />
              <div className="notice-body">
                <strong>Adresse à vérifier</strong>
                <p>Vérifiez votre adresse auprès du service de connexion, puis reconnectez-vous avant d’accepter l’invitation.</p>
              </div>
            </div>}
          </section>

          {preview && <section className="panel invitation" aria-labelledby="invitation-school-name">
            <div className="school-heading">
              <Symbol kind="school" tile />
              <div className="row-text">
                <span className="row-meta">L’école qui vous invite</span>
                <h2 id="invitation-school-name">{preview.data.schoolName}</h2>
              </div>
            </div>
            <dl className="invitation-facts">
              <div><Symbol kind="shield" /><dt>Votre rôle</dt><dd>{preview.data.roles.map(roleLabel).join(' · ')}</dd></div>
              <div><Symbol kind="mail" /><dt>Invitation envoyée à</dt><dd>{preview.data.maskedEmail}</dd></div>
              <div><Symbol kind="clock" /><dt>Lien valable jusqu’au</dt><dd><time dateTime={preview.data.expiresAt}>{formatDate(preview.data.expiresAt)}</time></dd></div>
            </dl>
            <div className="policy">
              <h3>Vos données dans cette école</h3>
              <p className="policy-copy">{preview.data.notice.noticeText}</p>
              <h3>Conservation des données</h3>
              <p className="policy-copy">{preview.data.notice.retentionText}</p>
              <p className="caption">Pour toute question : <a href={`mailto:${preview.data.notice.contactEmail}`}>{preview.data.notice.contactEmail}</a></p>
            </div>
            <div className="acceptance">
              <label className="confirm-card">
                <input type="checkbox" checked={reviewed} onChange={event => setReviewed(event.target.checked)} disabled={isBusy} />
                <span>Je confirme rejoindre <strong>{preview.data.schoolName}</strong> avec le compte indiqué ci-dessus.</span>
              </label>
              <p className="caption">Ce rattachement ne réserve aucune leçon et n’autorise aucun enregistrement GPS.</p>
              {acceptanceHint && <p className="caption" id="acceptance-hint">Cochez la confirmation pour rejoindre l’école.</p>}
              {!emailVerified && <p className="caption">Vérifiez d’abord votre adresse pour rejoindre l’école.</p>}
              <div className="button-row">
                <button type="button" className="button primary" aria-describedby={acceptanceHint ? 'acceptance-hint' : undefined} disabled={isBusy || !reviewed || !emailVerified} onClick={() => void acceptInvitation()}>{uncertain ? 'Vérifier et réessayer' : 'Rejoindre cette école'}</button>
                <button type="button" className="button secondary" disabled={isBusy || uncertain} onClick={() => void clearInvitation()}>Pas maintenant</button>
              </div>
              <p className="caption">{uncertain ? 'Vérifiez d’abord le résultat de la demande déjà envoyée avant de fermer cette invitation.' : '« Pas maintenant » laisse le lien utilisable jusqu’à son expiration.'}</p>
            </div>
          </section>}

          {!preview && !isBusy && !error && <section className="panel empty-state" aria-labelledby="no-invitation-title">
            <Symbol kind="school" />
            <div className="row-text">
              <h2 id="no-invitation-title" className="row-title">Aucune invitation à afficher</h2>
              <p className="row-meta">Ouvrez le lien le plus récent envoyé par votre école, ou retrouvez les écoles déjà liées à votre compte.</p>
              <a className="button secondary" href="/app/">Voir mes écoles</a>
            </div>
          </section>}
        </>}

        {loaded && session?.authenticated && page === 'account' && <>
          {accepted && acceptedSession.current === session.csrfToken && <div className="notice success" role="status">
            <Symbol kind="check" />
            <div className="notice-body">
              <strong>Vous avez rejoint {accepted.schoolName}</strong>
              <p>Votre école a confirmé votre rattachement.</p>
            </div>
          </div>}

          {session.invitationPending && <section className="panel invitation-banner" aria-labelledby="pending-title">
            <div className="row-text">
              <StatusBadge tone="accent" symbol="mail">Invitation en attente</StatusBadge>
              <h2 id="pending-title" className="row-title">Une école vous invite</h2>
              <p className="row-meta">Relisez les informations de l’école avant d’accepter.</p>
            </div>
            <a className="button primary" href="/app/invitation">Voir l’invitation</a>
          </section>}

          <section className="section" aria-labelledby="schools-title">
            <div className="section-heading">
              <h2 id="schools-title" className="section-title">Vos écoles</h2>
              <button className="button quiet" disabled={isBusy} type="button" onClick={() => void perform('Actualisation de vos écoles…', refresh)}>
                <Symbol kind="refresh" bare />Actualiser
              </button>
            </div>
            {me && me.memberships.length > 0
              ? <ul className="row-list">{me.memberships.map(member => <li key={member.membershipId}>
                  <Symbol kind="school" />
                  <div className="row-text"><h3 className="row-title">{member.schoolName}</h3><p className="row-meta">{member.roles.map(roleLabel).join(' · ')}</p></div>
                  {member.roles.includes('ADMIN') && <a className="button secondary compact" href={`/app/gestion/${member.schoolId}`}>Gérer l’école</a>}
                </li>)}</ul>
              : !isBusy && !error
                ? <div className="empty-state">
                    <Symbol kind="school" />
                    <div className="row-text">
                      <h3 className="row-title">Votre école n’apparaît pas encore</h3>
                      <p className="row-meta">Ouvrez le lien d’invitation envoyé par votre école. Sans invitation, contactez directement votre école.</p>
                    </div>
                  </div>
                : isBusy
                  ? <div className="row-skeleton" aria-hidden="true"><span /><span /></div>
                  : <p className="row-meta">Vos écoles ne peuvent pas être affichées pour le moment.</p>}
          </section>
        </>}
      </main>
      <footer className="site-footer"><span>Drivy</span><p>Vos accès sont propres à chaque école.</p></footer>
    </div>
  );
}

function formatDate(value: string): string {
  return new Intl.DateTimeFormat('fr-CH', { dateStyle: 'long', timeStyle: 'short' }).format(new Date(value));
}
