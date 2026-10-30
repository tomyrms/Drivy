import { createRoot } from 'react-dom/client';
import { EntryPreview, installEntryPreview, type EntryScene } from '../client/portal/preview/entry-preview';

const query = new URLSearchParams(location.search);
const scenes: EntryScene[] = ['login', 'schools', 'empty', 'invitation', 'expired', 'unverified', 'mismatch', 'lost-reply', 'changed', 'slow', 'recovery', 'recovery-unavailable'];
const pages: Record<string, EntryScene> = { connexion: 'login', ecoles: 'schools', invitation: 'invitation', recuperation: 'recovery' };
const requested = query.get('scene');
const scene = scenes.includes(requested as EntryScene) ? requested as EntryScene : pages[query.get('page') ?? ''] ?? 'login';
installEntryPreview(scene);
createRoot(document.getElementById('root')!).render(<EntryPreview scene={scene} />);
