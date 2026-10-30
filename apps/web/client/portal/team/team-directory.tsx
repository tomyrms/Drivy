import { useEffect, useRef } from 'react';
import { ChevronLeft, ChevronRight, Clock, Search, UserPlus, UsersRound } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Avatar, AvatarFallback } from '../../components/ui/avatar';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Field, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../../components/ui/select';
import { Tabs, TabsList, TabsTrigger } from '../../components/ui/tabs';
import { useConsole } from '../../console/context';
import { roleNames } from '../access/access-controller';
import { initials } from '../access/members';
import { portalSections } from '../pages';
import { ReadFeedback } from './feedback';
import type { SortOrder, StatusFilter } from './team-model';
import type { useTeamDirectory } from './team-controller';

const sortOptions = [{ value: 'name-asc', label: 'Nom : A à Z' }, { value: 'name-desc', label: 'Nom : Z à A' }];

/** Searchable list of members: identity, roles and access state, with homonyms told apart by a short reference. */
export function TeamDirectory({ state, focusId, onOpen }: { state: ReturnType<typeof useTeamDirectory>; focusId: string | null; onOpen: (id: string) => void }) {
  const { navigate } = useConsole();
  const heading = useRef<HTMLHeadingElement>(null);
  const ready = state.loaded.status === 'ready';
  // Coming back from a member sheet restores the focus on the row that was opened, or on the title when it is not on this page.
  const restored = useRef(false);
  useEffect(() => {
    if (restored.current) return;
    if (focusId && ready) {
      restored.current = true;
      const row = document.querySelector<HTMLElement>(`[data-member-id="${focusId}"]`);
      (row ?? heading.current)?.focus({ preventScroll: false });
    } else if (!focusId) { restored.current = true; heading.current?.focus({ preventScroll: true }); }
  }, [focusId, ready]);
  const total = state.visible.length;
  const pages = Math.ceil(total / state.pageSize);
  const canInvite = state.canInvite && portalSections.includes('invitations');
  return <section className="team-page">
    <header className="team-heading">
      <div><h1 ref={heading} tabIndex={-1}>Équipe</h1>{ready && <p className="team-count" role="status">{total} {total > 1 ? 'membres' : 'membre'}</p>}</div>
      {canInvite && <Button onClick={() => navigate('invitations', { audience: 'team' })}><UserPlus aria-hidden="true" />Inviter un membre</Button>}
    </header>
    <div className="team-tools">
      <Field className="team-search"><FieldLabel className="sr-only" htmlFor="team-search">Rechercher un membre</FieldLabel><Search aria-hidden="true" />
        <Input id="team-search" type="search" placeholder="Rechercher un membre" value={state.search} onChange={event => { state.setSearch(event.target.value); state.setPage(1); }} /></Field>
      <Select value={state.sort} onValueChange={value => { if (value) state.setSort(value as SortOrder); }} items={sortOptions}>
        <SelectTrigger aria-label="Trier les membres"><SelectValue /></SelectTrigger>
        <SelectContent>{sortOptions.map(option => <SelectItem key={option.value} value={option.value}>{option.label}</SelectItem>)}</SelectContent>
      </Select>
    </div>
    <div className="team-filters">
      <Tabs value={state.status} onValueChange={value => { state.setStatus(String(value) as StatusFilter); state.setPage(1); }}>
        <TabsList aria-label="État de l’accès"><TabsTrigger value="all">Tous</TabsTrigger><TabsTrigger value="active">Actifs</TabsTrigger><TabsTrigger value="inactive">Inactifs</TabsTrigger></TabsList>
      </Tabs>
      <Field orientation="horizontal" className="team-learners"><Checkbox id="team-learners" checked={state.withLearners} onCheckedChange={checked => { state.setWithLearners(checked === true); state.setPage(1); }} />
        <FieldLabel htmlFor="team-learners">Inclure les élèves</FieldLabel></Field>
    </div>
    <ReadFeedback loaded={state.loaded} label="Lecture de l’équipe" />
    {ready && state.loaded.data?.truncated && <Alert><AlertTitle>Liste partielle</AlertTitle><AlertDescription>La recherche porte sur les membres chargés.</AlertDescription></Alert>}
    {ready && total > 0 && <div className="team-directory">
      <div className="team-directory-labels" aria-hidden="true"><span>Membre</span><span>Rôles dans l’école</span><span /><span /></div>
      <ul aria-label="Membres de l’école">{state.pageRows.map(member => {
        const reference = state.references.get(member.id), waiting = state.pendingLabel(member.id);
        return <li key={member.id}><button type="button" className="team-row" data-member-id={member.id} onClick={() => onOpen(member.id)}>
          <span className="team-row-person"><Avatar><AvatarFallback>{initials(member.displayName)}</AvatarFallback></Avatar>
            <span className="team-row-name"><strong>{member.displayName}</strong>{reference && <span className="team-ref">Réf. {reference}</span>}{member.id === state.membershipId && <span className="team-ref">Vous</span>}</span></span>
          <span className="team-row-roles">{roleNames(member.roles)}</span>
          <span className="team-row-state">{waiting ? <span className="team-waiting"><Clock aria-hidden="true" />{waiting}</span> : member.status !== 'ACTIVE' ? <Badge variant="secondary">Accès inactif</Badge> : null}</span>
          <ChevronRight aria-hidden="true" />
        </button></li>;
      })}</ul>
    </div>}
    {ready && total === 0 && <div className="team-empty"><UsersRound aria-hidden="true" /><h2>{state.members.length ? 'Aucun membre trouvé' : 'Aucun membre'}</h2>
      {state.filtered && <Button variant="outline" onClick={state.reset}>Effacer les filtres</Button>}</div>}
    {pages > 1 && <nav className="team-pagination" aria-label="Pages de l’équipe">
      <span>Page {state.currentPage} sur {pages}</span>
      <div><Button variant="outline" size="icon" aria-label="Page précédente" disabled={state.currentPage <= 1} onClick={() => state.setPage(state.currentPage - 1)}><ChevronLeft aria-hidden="true" /></Button>
        <Button variant="outline" size="icon" aria-label="Page suivante" disabled={state.currentPage >= pages} onClick={() => state.setPage(state.currentPage + 1)}><ChevronRight aria-hidden="true" /></Button></div>
    </nav>}
  </section>;
}
