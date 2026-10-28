import { ChevronLeft, ChevronRight, Clock, KeyRound, Mail, UsersRound } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Field, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { roleNames } from '../access/access-controller';
import { PortalSelect } from '../components/portal-select';
import { ReadFeedback } from '../team/feedback';
import { formatDateTime, invitationStatuses, invitationStatusLabels, type InvitationStatusFilter } from './invitations-model';
import type { InvitationsState } from './use-invitations';

const statusOptions = [{ value: 'all', label: 'Toutes' }, ...invitationStatuses.map(value => ({ value, label: invitationStatusLabels[value] }))];

/** Follow-up: every invitation of the audience with its state and expiry; a badge only for what needs attention. */
export function InvitationList({ state }: { state: InvitationsState }) {
  const { school } = state.context;
  const ready = state.loaded.status === 'ready';
  const filtered = state.search !== '' || state.status !== 'all';
  return <>
    <div className="invitation-tools">
      <Field className="invitation-search"><FieldLabel htmlFor="invitation-search">Rechercher une invitation</FieldLabel>
        <Input id="invitation-search" type="search" placeholder={state.team ? 'Adresse' : 'Permis ou moniteur'} value={state.search} onChange={event => { state.setSearch(event.target.value); state.setPage(1); }} /></Field>
      <PortalSelect id="invitation-status" label="État" options={statusOptions} value={state.status}
        onValueChange={value => { if (value) { state.setStatus(value as InvitationStatusFilter); state.setPage(1); } }} />
    </div>
    <ReadFeedback loaded={state.loaded} label="Lecture des invitations" />
    {ready && state.data?.truncated && <Alert><AlertTitle>Liste partielle</AlertTitle><AlertDescription>Seules les 1 000 premières invitations sont chargées : la recherche et les comptes portent sur celles-ci.</AlertDescription></Alert>}
    {ready && state.pendingCreations > 0 && <p className="invitation-waiting" role="status"><Clock aria-hidden="true" />{state.pendingCreations === 1 ? 'Création d’une invitation en cours' : `Création de ${state.pendingCreations} invitations en cours`}</p>}
    {ready && state.visible.length > 0 && <>
      <p className="invitation-count" role="status">{state.visible.length} {state.visible.length === 1 ? 'invitation' : 'invitations'}{state.visible.length !== state.items.length ? ` sur ${state.items.length}` : ''}</p>
      <ul className="invitation-list" aria-label="Invitations de l’école, les plus récentes d’abord">{state.pageRows.map(item => {
        const waiting = state.pendingLabel(item.id), Icon = item.delivery === 'CODE' ? KeyRound : Mail;
        return <li key={item.id}><button type="button" className="invitation-row" data-invitation-id={item.id} onClick={() => state.openInvitation(item.id)}>
          <span className="invitation-icon"><Icon aria-hidden="true" /></span>
          <span className="invitation-row-main"><strong>{state.labelOf(item)}</strong>
            <span>{state.team && <>{roleNames(item.roles)} · </>}Expire le <time dateTime={item.expiresAt}>{formatDateTime(item.expiresAt, school.timeZone)}</time></span></span>
          <span className="invitation-row-state">{waiting ? <span className="invitation-waiting"><Clock aria-hidden="true" />{waiting}</span>
            : item.status === 'EXPIRED' || item.status === 'REVOKED' ? <Badge variant="secondary">{invitationStatusLabels[item.status]}</Badge> : <span>{invitationStatusLabels[item.status]}</span>}</span>
          <ChevronRight aria-hidden="true" />
        </button></li>;
      })}</ul>
    </>}
    {ready && state.visible.length === 0 && <div className="invitation-empty"><UsersRound aria-hidden="true" />
      <h2>{state.items.length === 0 ? 'Aucune invitation' : 'Aucune invitation trouvée'}</h2>
      {filtered && <Button variant="outline" onClick={() => { state.setSearch(''); state.setStatus('all'); state.setPage(1); }}>Effacer les filtres</Button>}</div>}
    {state.pages > 1 && <nav className="invitation-pagination" aria-label="Pages des invitations"><span>Page {state.currentPage} sur {state.pages}</span>
      <div><Button variant="outline" size="icon" aria-label="Page précédente" disabled={state.currentPage <= 1} onClick={() => state.setPage(state.currentPage - 1)}><ChevronLeft aria-hidden="true" /></Button>
        <Button variant="outline" size="icon" aria-label="Page suivante" disabled={state.currentPage >= state.pages} onClick={() => state.setPage(state.currentPage + 1)}><ChevronRight aria-hidden="true" /></Button></div></nav>}
  </>;
}
