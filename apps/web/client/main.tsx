import { createRoot } from 'react-dom/client';
import { z } from 'zod';
import { readInvitationLink } from './invitation-link';
import { readOpeningLink } from './school-opening-model';
import { sectionKeys } from './console/sections';
import { BrandSymbol } from './BrandSymbol';
import { Button } from './components/ui/button';
import './theme';
import './portal/portal.css';

// Strict CSP: validation must not compile functions at runtime.
z.config({ jitless: true });
// Remove bearer fragments before rendering, fetching or authenticating on every route.
const path = window.location.pathname.replace(/\/+$/, '');
const isOpening = path === '/app/ouvrir';
const openingLink = isOpening ? readOpeningLink() : { token: null, error: false };
const invitationLink = readInvitationLink();
const element = document.getElementById('root');
if (!element) throw new Error('Élément racine introuvable.');
const root = createRoot(element);

// Old presentation bookmarks keep their destination, never the retired UI.
const params = new URLSearchParams(window.location.search);
if (params.has('presentation')) {
  params.delete('presentation');
  const search = params.toString();
  window.history.replaceState(window.history.state, '', `${window.location.pathname}${search ? `?${search}` : ''}`);
}
try { window.localStorage.removeItem('drivy.web.presentation'); } catch { /* Optional preference cleanup only. */ }

function retryLoading() {
  // A failed module fetch may be cached. An unsubmitted link stays in memory/the fragment only.
  const token = openingLink.token ?? invitationLink.token;
  if (token) window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}#token=${encodeURIComponent(token)}`);
  window.location.reload();
}

function LoadingPage({ failed = false }: { failed?: boolean }) {
  return <div className="portal-app">
    <header className="portal-topbar"><a className="portal-brand" href="/app/" aria-label="Drivy, mes écoles"><BrandSymbol /><span>Drivy</span></a></header>
    <main className="portal-entry">{failed ? <section className="portal-entry-card">
      <h1 tabIndex={-1} ref={heading => heading?.focus()}>Chargement impossible</h1>
      <p role="alert">Vérifiez votre connexion, puis réessayez de charger cette page.</p>
      <Button onClick={retryLoading}>Réessayer</Button>
    </section> : <p role="status">Chargement de Drivy…</p>}</main>
  </div>;
}

async function loadPage() {
  const consoleParts = path.split('/');
  const knownConsole = /^\/app\/gestion(\/|$)/.test(path) && consoleParts.length <= 5
    && (!consoleParts[4] || (sectionKeys as readonly string[]).includes(consoleParts[4]));
  const knownEntry = ['/app', '/app/invitation', '/app/recover', '/app/preferences', '/app/ouvrir', '/app/operateur'].includes(path);
  root.render(<LoadingPage />);
  try {
    if (!knownEntry && !knownConsole) {
      const { PortalNotFoundPage } = await import('./portal/entry/not-found-page');
      root.render(<PortalNotFoundPage />);
    } else if (path === '/app/recover') {
      const { PortalRecoveryPage } = await import('./portal/entry/recovery-page');
      root.render(<PortalRecoveryPage />);
    } else if (path === '/app/preferences') {
      const { PortalPreferencesPage } = await import('./portal/account/preferences-page');
      root.render(<PortalPreferencesPage />);
    } else if (isOpening || path === '/app/operateur') {
      const { SchoolOpeningPage } = await import('./portal/opening/opening-page');
      root.render(<SchoolOpeningPage link={openingLink} operator={!isOpening} />);
    } else if (knownConsole) {
      const { PortalConsole } = await import('./portal/portal-console');
      root.render(<PortalConsole />);
    } else {
      const { PortalEntryPage } = await import('./portal/entry/entry-page');
      root.render(<PortalEntryPage invitationLink={invitationLink} />);
    }
  } catch { root.render(<LoadingPage failed />); }
}
void loadPage();
