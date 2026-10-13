import { createRoot } from 'react-dom/client';
import { App } from './App';
import { ManagementConsole } from './console/Console';
import { readInvitationLink } from './invitation-link';
import { SchoolOpeningPage } from './school-opening';
import { readOpeningLink } from './school-opening-model';
import './styles.css';
import './school-opening.css';

// Remove any token fragment before rendering, fetching or authenticating, whatever the page.
const isOpening = window.location.pathname === '/app/ouvrir';
const openingLink = isOpening ? readOpeningLink() : {token:null,error:false};
const invitationLink = readInvitationLink();
const root = document.getElementById('root');
if (!root) throw new Error('Élément racine introuvable.');
// The management console is a separate desktop-style surface; the invitation and account pages keep their reading layout.
if (isOpening || window.location.pathname === '/app/operateur') {
  createRoot(root).render(<SchoolOpeningPage link={openingLink} operator={!isOpening} />);
} else if (/^\/app\/gestion(\/|$)/.test(window.location.pathname)) {
  createRoot(root).render(<ManagementConsole />);
} else {
  createRoot(root).render(<App invitationLink={invitationLink} />);
}
