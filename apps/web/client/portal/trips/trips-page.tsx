import { ArrowLeft, ChevronLeft, ChevronRight, Route, Search, X } from 'lucide-react';
import { matchesSearch } from '../../command-core';
import { readAll, readPage } from '../../school-api';
import { tripDuration, tripSchema, type Trip } from '../../trip-model';
import { useConsole, useLoad } from '../../console/context';
import { useListState } from '../../console/list-state';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Avatar, AvatarFallback } from '../../components/ui/avatar';
import { Button } from '../../components/ui/button';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { InputGroup, InputGroupAddon, InputGroupButton, InputGroupInput } from '../../components/ui/input-group';
import { ReadFeedback } from '../components/feedback';
import './trips.css';

const initials = (name: string) => name.split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]).join('').toLocaleUpperCase('fr');
function TripTime({ trip }: { trip: Trip }) {
  const instant = new Date(trip.authorizedAt);
  return <time dateTime={trip.authorizedAt}>{new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeZone: trip.lessonTimeZone }).format(instant)}
    <span className="trips-muted"> · {new Intl.DateTimeFormat('fr-CH', { timeStyle: 'short', timeZone: trip.lessonTimeZone }).format(instant)}</span></time>;
}

/** Administrative trip inventory (#332); the API and RLS decide the school scope of every page. */
export function TripsPilot() {
  const { schoolId, routeQuery, navigate } = useConsole();
  const learner = routeQuery?.learner;
  const [query, setQuery] = useListState(`trips/${learner ?? 'all'}/search`, '');
  const [cursors, setCursors] = useListState<(string | null)[]>(`trips/${learner ?? 'all'}/cursors`, [null]);
  const cursor = cursors.at(-1);
  const loaded = useLoad(async () => {
    if (learner) {
      const page = await readAll(schoolId, 'captures', tripSchema);
      return { items: page.items.filter(trip => trip.learnerId === learner), nextCursor: null, truncated: page.truncated };
    }
    return { ...await readPage(schoolId, 'captures', tripSchema, cursor), truncated: false };
  }, [schoolId, cursor, learner], `${schoolId}/${learner ?? ''}/${cursor ?? ''}`);
  const dossier = (id: string, returning = false) => navigate('eleves', { selection: id, week: routeQuery?.week, day: routeQuery?.day, instructor: routeQuery?.instructor,
    from: returning && routeQuery?.from === 'eleves' ? routeQuery.week ? 'agenda' : undefined : 'trajets',
    ...(!returning && learner ? { learner } : {}) });
  const page = loaded.status === 'ready' ? loaded.data : null;
  const visible = page ? page.items.filter(trip => matchesSearch([trip.learnerName, trip.instructorName], query)) : [];
  const learnerName = learner ? page?.items[0]?.learnerName : undefined;
  const searchLabel = learner ? 'Rechercher un moniteur' : 'Rechercher dans cette page';

  return <section className="trips-page">
    {learner && <Button variant="ghost" size="sm" className="trips-back" onClick={() => dossier(learner, true)}><ArrowLeft aria-hidden="true" />{learnerName ?? 'Dossier de l’élève'}</Button>}
    <header className="trips-heading">
      <div><h1>{learner ? 'Trajets de l’élève' : 'Trajets'}</h1>
        {page && <p className="trips-muted" role="status">{visible.length} {visible.length === 1 ? 'trajet' : 'trajets'}{query ? visible.length === 1 ? ' trouvé' : ' trouvés' : ''}{!learner && cursors.length > 1 ? ` · page ${cursors.length}` : ''}</p>}</div>
      {learner && <Button variant="outline" onClick={() => navigate('trajets')}>Tous les trajets</Button>}
    </header>
    <ReadFeedback loaded={loaded} label="Lecture des trajets" />
    {page && <>
      <InputGroup className="trips-search">
        <InputGroupAddon><Search aria-hidden="true" /></InputGroupAddon>
        <InputGroupInput type="search" aria-label={searchLabel} placeholder={searchLabel} value={query} onChange={event => setQuery(event.target.value)} />
        {query && <InputGroupAddon align="inline-end"><InputGroupButton size="icon-xs" aria-label="Effacer la recherche" onClick={() => setQuery('')}><X aria-hidden="true" /></InputGroupButton></InputGroupAddon>}
      </InputGroup>
      {page.truncated && <Alert><AlertTitle>Historique partiel</AlertTitle><AlertDescription>Ce filtre porte sur les 1 000 derniers trajets de l’école. Ouvrez tous les trajets pour parcourir les plus anciens.</AlertDescription></Alert>}
      {visible.length === 0
        ? <Empty><EmptyHeader><EmptyMedia variant="icon"><Route aria-hidden="true" /></EmptyMedia>
            <EmptyTitle>{page.items.length ? 'Aucun trajet trouvé' : page.truncated ? 'Aucun trajet dans cette partie de l’historique' : 'Aucun trajet'}</EmptyTitle></EmptyHeader></Empty>
        : <table className="trips-table">
            <caption className="sr-only">{learner ? 'Trajets de l’élève' : 'Trajets de l’école'}</caption>
            <thead><tr><th scope="col">Élève</th><th scope="col">Moniteur</th><th scope="col">Date</th><th scope="col">Durée</th></tr></thead>
            <tbody>{visible.map(trip => <tr key={trip.id}>
              <th scope="row"><Button variant="ghost" className="trips-person" onClick={() => dossier(trip.learnerId)}>
                <Avatar aria-hidden="true"><AvatarFallback>{initials(trip.learnerName)}</AvatarFallback></Avatar><span>{trip.learnerName}</span></Button></th>
              <td data-label="Moniteur">{trip.instructorName}</td>
              <td data-label="Date"><TripTime trip={trip} /></td>
              <td data-label="Durée">{tripDuration(trip)}</td>
            </tr>)}</tbody>
          </table>}
      {(cursors.length > 1 || page.nextCursor) && <nav className="trips-pages" aria-label="Pages des trajets">
        {cursors.length > 1 && <Button variant="outline" disabled={loaded.status === 'loading'} onClick={() => { setQuery(''); setCursors(values => values.slice(0, -1)); }}><ChevronLeft aria-hidden="true" />Précédents</Button>}
        {page.nextCursor && <Button variant="outline" disabled={loaded.status === 'loading'} onClick={() => { setQuery(''); setCursors(values => [...values, page.nextCursor]); }}>Suivants<ChevronRight aria-hidden="true" /></Button>}
      </nav>}
    </>}
  </section>;
}
