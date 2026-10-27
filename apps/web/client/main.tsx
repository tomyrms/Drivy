import { createRoot } from 'react-dom/client';
import { readInvitationLink } from './invitation-link';
import { readOpeningLink } from './school-opening-model';
import './theme';
import './styles.css';
import './school-opening.css';

// Remove any token fragment before rendering, fetching or authenticating, whatever the page.
const isOpening = window.location.pathname === '/app/ouvrir';
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
  root.render(<div className="app-shell"><main className="main"><p role="status">Chargement de Drivy…</p></main></div>);
  try {
    // Exclusive surfaces are loaded only when requested. Styles and link sanitization stay shared.
    if (window.location.pathname === '/app/recover') {
      const { AccountRecoveryPage } = await import('./account-recovery');
      root.render(<AccountRecoveryPage />);
    } else if (window.location.pathname.replace(/\/$/, '') === '/app/preferences') {
      const { PreferencesPage } = await import('./preferences');
      root.render(<PreferencesPage />);
    } else if (isOpening || window.location.pathname === '/app/operateur') {
      const { SchoolOpeningPage } = await import('./school-opening');
      root.render(<SchoolOpeningPage link={openingLink} operator={!isOpening} />);
    } else if (/^\/app\/gestion(\/|$)/.test(window.location.pathname)) {
      const { ManagementConsole } = await import('./console/Console');
      root.render(<ManagementConsole />);
    } else {
      const { App } = await import('./App');
      root.render(<App invitationLink={invitationLink} />);
    }
  } catch {
    root.render(<div className="app-shell"><main className="main">
      <h1 tabIndex={-1} ref={heading => { heading?.focus(); }}>Chargement impossible</h1>
      <p role="alert">Vérifiez votre connexion, puis réessayez de charger cette page.</p>
      <button type="button" className="button primary" onClick={retryLoading}>Réessayer</button>
    </main></div>);
  }
}
void loadPage();
