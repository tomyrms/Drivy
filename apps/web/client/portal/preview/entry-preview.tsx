import { useState } from 'react';
import { PortalEntryPage } from '../entry/entry-page';
import { PortalRecoveryPage } from '../entry/recovery-page';
import { EntryFrame } from '../entry/entry-frame';
import { entryRoutes, type EntryRoutes } from '../entry/entry-model';
import { Button, buttonVariants } from '../../components/ui/button';
import { createEntryPreviewTransport, type EntryScene } from './entry-transport';

export { createEntryPreviewTransport, type EntryScene } from './entry-transport';

/** Called only by the separate synthetic entry, never by a production page. */
export function installEntryPreview(scene: EntryScene) {
  window.fetch = createEntryPreviewTransport(scene, location.origin);
}

export function EntryPreview({ scene = 'login' }: { scene?: EntryScene }) {
  const [provider, setProvider] = useState(false);
  const base = location.pathname;
  const routes: EntryRoutes = {
    ...entryRoutes, account: `${base}?page=connexion`, invitation: `${base}?page=invitation`, recover: `${base}?page=recuperation`,
    opening: `${base}?page=ouverture`, preferences: `${base}?page=preferences`, school: () => `${base}?page=agenda`,
  };
  if (provider) return <EntryFrame home={routes.account}><h1>Service de connexion</h1><p>La récupération se poursuit chez le fournisseur d’identité. Cet aperçu s’arrête à cette frontière.</p><Button onClick={() => setProvider(false)}>Retour à la récupération</Button></EntryFrame>;
  return <>
    {scene === 'recovery' || scene === 'recovery-unavailable'
      ? <PortalRecoveryPage routes={routes} openProvider={() => setProvider(true)} />
      : <PortalEntryPage invitationLink={{ token: null, error: false }} routes={routes} page={['login', 'schools', 'empty'].includes(scene) ? 'account' : 'invitation'} />}
    <div className="preview-controls"><span>Aperçu fictif · code DEMO-DEMO</span><a className={buttonVariants({ variant: 'ghost' })} href={`${base}?page=agenda`}>Retour à l’aperçu</a></div>
  </>;
}
