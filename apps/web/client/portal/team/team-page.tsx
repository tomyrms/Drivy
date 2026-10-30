import { useEffect, useRef, useState } from 'react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { useRouteSelection } from '../../console/context';
import { AccessPilot } from '../access/access-page';
import { ReadFeedback } from './feedback';
import { MemberSheet } from './member-sheet';
import { TeamDirectory } from './team-directory';
import { useTeamDirectory } from './team-controller';
import './team.css';

/**
 * Team of the school: directory, member page, access editing (AccessPilot) and removal of an access.
 * Only the selected member lives in the URL; editing is local and guarded against accidental departure.
 */
export function TeamPilot() {
  const directory = useTeamDirectory();
  const [selected, select] = useRouteSelection();
  const [editing, setEditing] = useState(false);
  const [confirmed, setConfirmed] = useState<string | null>(null);
  const lastOpened = useRef<string | null>(null);
  useEffect(() => { setEditing(false); setConfirmed(null); }, [selected]);
  const open = (id: string) => { lastOpened.current = id; select(id); };
  if (!selected) return <TeamDirectory state={directory} focusId={lastOpened.current} onOpen={open} />;
  const member = directory.members.find(item => item.id === selected) ?? null;
  if (editing && member) return <AccessPilot initialEdit onClose={message => { setEditing(false); if (message) setConfirmed(message); }} />;
  if (!member) return <section className="access-page team-sheet">
    <header className="access-heading"><h1>Membre</h1></header>
    <ReadFeedback loaded={directory.loaded} label="Lecture du membre" />
    {directory.loaded.status === 'ready' && <Alert variant="destructive"><AlertTitle>Membre non disponible</AlertTitle>
      <AlertDescription>Ce membre n’est pas présent dans la liste lue avec vos accès actuels.</AlertDescription>
      <div className="team-alert-actions"><Button variant="outline" onClick={() => select(null)}>Retour à l’équipe</Button></div></Alert>}
  </section>;
  return <MemberSheet member={member} reference={directory.references.get(member.id)} loaded={directory.loaded} confirmed={confirmed}
    onDismissConfirmed={() => setConfirmed(null)} onEditAccess={() => setEditing(true)} onBack={() => select(null)} />;
}
