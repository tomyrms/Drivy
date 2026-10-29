import { createRoot } from 'react-dom/client';
import { readInvitationLink } from './invitation-link';
import { readOpeningLink } from './school-opening-model';
import { sectionKeys } from './console/sections';
import { BrandSymbol } from './BrandSymbol';
import { readPresentation } from './presentation';
import './theme';

// Remove any token fragment before rendering, fetching or authenticating, whatever the page.
const path = window.location.pathname.replace(/\/+$/, '');
const isOpening = path === '/app/ouvrir';
const openingLink = isOpening ? readOpeningLink() : { token: null, error: false };
const invitationLink = readInvitationLink();
const element = document.getElementById('root');
if (!element) throw new Error('Élément racine introuvable.');
const root = createRoot(element);

function retryLoading() {
  // A failed module fetch can remain cached by the browser. Reload explicitly, never in a loop.
  // Keep a not-yet-submitted bearer link in memory only. The fragment is never sent to the server.
  const token = openingLink.token ?? invitationLink.token;
  if (token) window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}#token=${encodeURIComponent(token)}`);
  window.location.reload();
}

async function loadPage() {
  // Exclusive surfaces are loaded only when requested. Link sanitization stays shared.
  const consoleParts = path.split('/');
  const isConsole = /^\/app\/gestion(\/|$)/.test(path);
  const knownConsole = isConsole && consoleParts.length <= 5 && (!consoleParts[4] || (sectionKeys as readonly string[]).includes(consoleParts[4]));
  const knownEntry = ['/app', '/app/invitation', '/app/recover', '/app/preferences', '/app/ouvrir', '/app/operateur'].includes(path);
  // The rebuilt console, preferences and entry (#311, #319) are opt-in per browser and never load the historical stylesheets.
  const portalEntry = ['/app', '/app/invitation', '/app/recover'].includes(path) || (!knownEntry && !knownConsole);
  const portal = (knownConsole || portalEntry || path === '/app/preferences') && readPresentation() === 'portal';
  try {
    if (portal) {
      root.render(<p role="status">Chargement de Drivy…</p>);
      if (path === '/app/preferences') {
        const { PortalPreferencesPage } = await import('./portal/account/preferences-page');
        root.render(<PortalPreferencesPage />);
      } else if (path === '/app/recover') {
        const { PortalRecoveryPage } = await import('./portal/entry/recovery-page');
        root.render(<PortalRecoveryPage />);
      } else if (path === '/app' || path === '/app/invitation') {
        // The fragment was already removed above; the link only lives in this object.
        const { PortalEntryPage } = await import('./portal/entry/entry-page');
        root.render(<PortalEntryPage invitationLink={invitationLink} />);
      } else if (!knownConsole) {
        document.title = 'Page introuvable · Drivy';
        const { PortalNotFoundPage } = await import('./portal/entry/not-found-page');
        root.render(<PortalNotFoundPage />);
      } else {
        const { PortalConsole } = await import('./portal/portal-console');
        root.render(<PortalConsole />);
      }
      return;
    }
    await import('./legacy-styles');
    root.render(<div className="app-shell"><main className="main"><p role="status">Chargement de Drivy…</p></main></div>);
    if (!knownEntry && !knownConsole) {
      document.title = 'Page introuvable · Drivy';
      root.render(<div className="app-shell"><header className="site-header"><a className="brand" href="/app/"><BrandSymbol /><span>Drivy</span></a></header><main className="main"><section className="account-entry">
        <h1 tabIndex={-1} ref={heading => heading?.focus()}>Page introuvable</h1>
        <p>Cette adresse ne correspond à aucune page de Drivy.</p>
        <a className="button primary" href="/app/">Retrouver mes écoles</a>
      </section></main></div>);
    } else if (path === '/app/recover') {
      const { AccountRecoveryPage } = await import('./account-recovery');
      root.render(<AccountRecoveryPage />);
    } else if (path === '/app/preferences') {
      const { PreferencesPage } = await import('./preferences');
      root.render(<PreferencesPage />);
    } else if (isOpening || path === '/app/operateur') {
      const { SchoolOpeningPage } = await import('./school-opening');
      root.render(<SchoolOpeningPage link={openingLink} operator={!isOpening} />);
    } else if (knownConsole) {
      const { ManagementConsole } = await import('./console/Console');
      root.render(<ManagementConsole />);
    } else {
      const { App } = await import('./App');
      root.render(<App invitationLink={invitationLink} />);
    }
  } catch {
    root.render(<div className="app-shell"><header className="site-header"><a className="brand" href="/app/"><BrandSymbol /><span>Drivy</span></a></header><main className="main"><section className="account-entry">
      <h1 tabIndex={-1} ref={heading => { heading?.focus(); }}>Chargement impossible</h1>
      <p role="alert">Vérifiez votre connexion, puis réessayez de charger cette page.</p>
      <button type="button" className="button primary" onClick={retryLoading}>Réessayer</button>
    </section></main></div>);
  }
}
void loadPage();
