import { useEffect, useRef } from 'react';
import { ArrowRight, CalendarClock, CalendarDays, CalendarOff, ChevronRight, LockKeyhole } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Avatar, AvatarFallback } from '../../components/ui/avatar';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Textarea } from '../../components/ui/textarea';
import { useConsole, usePendingResources, type Loaded } from '../../console/context';
import type { SectionKey } from '../../console/sections';
import type { SchoolMember } from '../../school-api';
import { grantName, roleNames } from '../access/access-controller';
import { AccessSummary } from '../access/access-summary';
import { initials } from '../access/members';
import { distinctLabel } from '../../person-reference';
import { portalSections } from '../pages';
import { CommandFeedback } from './feedback';
import { useMemberRemoval } from './team-controller';

const shortcutTargets: readonly { section: SectionKey; label: string; icon: typeof CalendarDays; from: boolean }[] = [
  { section: 'agenda', label: 'Agenda', icon: CalendarDays, from: false },
  { section: 'disponibilites', label: 'Disponibilités', icon: CalendarClock, from: true },
  { section: 'absences', label: 'Absences', icon: CalendarOff, from: true },
];

interface MemberSheetProps {
  member: SchoolMember;
  /** Short reference telling a homonym apart; absent when the name is unique. */
  reference: string | undefined;
  loaded: Pick<Loaded<unknown>, 'status' | 'refresh'>;
  /** Confirmation of a change made in the access editor, shown until dismissed. */
  confirmed: string | null;
  onDismissConfirmed: () => void;
  onEditAccess: () => void;
  onBack: () => void;
}

/** Read-first member page: identity, roles, state, shortcuts to the planning. Editing accesses and removing an access are separate. */
export function MemberSheet({ member, reference, loaded, confirmed, onDismissConfirmed, onEditAccess, onBack }: MemberSheetProps) {
  const { schoolId, school, membership, navigate } = useConsole();
  const waiting = usePendingResources(schoolId);
  const removal = useMemberRemoval(member, () => loaded.refresh?.());
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => { heading.current?.focus({ preventScroll: true }); }, [member.id]);
  const self = member.id === membership.membershipId;
  const admin = membership.roles.includes('ADMIN');
  const active = member.status === 'ACTIVE';
  const canEdit = admin && school.status === 'ACTIVE' && active && loaded.status === 'ready' && !removal.busy && !waiting.has(member.id.toLowerCase());
  const shortcuts = member.roles.includes('INSTRUCTOR') ? shortcutTargets.filter(target => portalSections.includes(target.section)) : [];
  const displayName = distinctLabel(member.displayName, reference);
  return <section className="access-page team-sheet">
    <nav className="access-breadcrumb" aria-label="Fil d’Ariane"><button type="button" onClick={onBack}>Équipe</button><ChevronRight aria-hidden="true" /><span aria-current="page">{displayName}</span></nav>
    <header className="access-heading">
      <div><h1 ref={heading} tabIndex={-1}>{member.displayName}{reference && <span className="team-ref team-heading-ref">Réf. {reference}</span>}</h1>
        <div className="access-person-line"><Avatar><AvatarFallback>{initials(member.displayName)}</AvatarFallback></Avatar><span>{roleNames(member.roles)}</span>
          {self && <span className="team-ref">Vous</span>}{!active && <Badge variant="secondary">Accès inactif</Badge>}</div>
      </div>
      {admin && active && school.status === 'ACTIVE' && <Button disabled={!canEdit} onClick={onEditAccess}>Modifier les accès<ArrowRight data-icon="inline-end" /></Button>}
    </header>
    {confirmed && <Alert><AlertTitle>Confirmé par l’école</AlertTitle><AlertDescription>{confirmed}</AlertDescription>
      <div className="team-alert-actions"><Button variant="ghost" onClick={onDismissConfirmed}>Masquer</Button></div></Alert>}
    {!removal.open && <CommandFeedback runner={removal.runner} />}

    <div className="access-read-layout">
      <div className="access-read-main"><AccessSummary roles={member.roles} grants={member.grants} /></div>
      <aside className="team-aside">
        <section className="access-context"><LockKeyhole aria-hidden="true" /><h2>{school.name}</h2><dl><div><dt>État</dt><dd>{active ? 'Accès actif' : 'Accès inactif'}</dd></div></dl></section>
        {shortcuts.length > 0 && <nav className="team-shortcuts" aria-label="Planning de ce moniteur"><h2>Planning</h2>
          <ul>{shortcuts.map(target => <li key={target.section}><Button variant="outline" onClick={() => navigate(target.section, target.from ? { instructor: member.id, from: 'equipe' } : { instructor: member.id })}>
            <target.icon aria-hidden="true" />{target.label}<ChevronRight data-icon="inline-end" aria-hidden="true" /></Button></li>)}</ul></nav>}
        {removal.offered && <div className="team-removal"><Button variant="destructive" disabled={!removal.available} onClick={removal.start}>Retirer l’accès</Button></div>}
      </aside>
    </div>

    <Dialog open={removal.open} onOpenChange={(open, details) => { if (removal.busy) { details.cancel(); return; } if (!open) removal.close(); }}>
      <DialogContent showCloseButton={!removal.busy}>
        <DialogHeader><DialogTitle>Retirer l’accès à l’école ?</DialogTitle><DialogDescription>{displayName} · {school.name}</DialogDescription></DialogHeader>
        <dl className="access-changes">
          <div><dt>Rôles retirés</dt><dd>{roleNames(member.roles)}</dd></div>
          <div><dt>Autorisations retirées</dt><dd>{member.grants.length ? member.grants.map(grantName).join(', ') : 'Aucune'}</dd></div>
        </dl>
        <FieldGroup><Field data-invalid={!!removal.reason && !!removal.reasonProblem}><FieldLabel htmlFor="removal-reason">Motif du retrait</FieldLabel>
          <Textarea id="removal-reason" value={removal.reason} onChange={event => removal.setReason(event.target.value)} maxLength={1000} rows={3} disabled={removal.busy} />
          {removal.reason !== '' && removal.reasonProblem && <FieldError>{removal.reasonProblem}</FieldError>}
        </Field></FieldGroup>
        <Field orientation="horizontal"><Checkbox id="removal-acknowledge" checked={removal.acknowledged} onCheckedChange={value => removal.setAcknowledged(value === true)} disabled={removal.busy} />
          <FieldLabel htmlFor="removal-acknowledge">Cette personne ne pourra plus accéder à l’école.</FieldLabel></Field>
        {removal.runner.outcome?.tone === 'error' && <Alert variant="destructive"><AlertTitle>{removal.runner.outcome.title}</AlertTitle><AlertDescription>{removal.runner.outcome.message}</AlertDescription></Alert>}
        <DialogFooter><Button variant="outline" disabled={removal.busy} onClick={removal.close}>Retour</Button>
          <Button variant="destructive" disabled={removal.busy || !removal.available || !!removal.reasonProblem || !removal.acknowledged} onClick={() => void removal.confirm(displayName)}>{removal.busy ? 'Retrait…' : 'Retirer l’accès'}</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  </section>;
}
