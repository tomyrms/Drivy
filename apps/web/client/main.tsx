import { createRoot } from 'react-dom/client';
import { App } from './App';
import { readInvitationLink } from './invitation-link';
import './styles.css';

const invitationLink = readInvitationLink();
const root = document.getElementById('root');
if (!root) throw new Error('Élément racine introuvable.');
createRoot(root).render(<App invitationLink={invitationLink} />);
