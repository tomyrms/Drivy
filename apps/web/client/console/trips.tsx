import { matchesSearch } from '../command-core';
import { readAll, readPage } from '../school-api';
import { tripDuration, tripSchema } from '../trip-model';
import { EmptyState, Notice, TextField } from '../ui';
import { useConsole, useLoad } from './context';
import { LoadState, SectionHeading } from './layout';
import { useListState } from './list-state';

function TripTime({ value, timeZone }: { value: string; timeZone: string }) {
  const instant = new Date(value);
  return <time className="trip-time" dateTime={value}>
    <span>{new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeZone }).format(instant)}</span>{' '}
    <span className="row-meta">{new Intl.DateTimeFormat('fr-CH', { timeStyle: 'short', timeZone }).format(instant)}</span>
  </time>;
}

/** Administrative trip inventory; API/RLS controls the school scope of every page. */
export function TripsSection() {
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
  const dossier = (id: string, returning = false) => navigate('eleves', { selection: id, week: routeQuery?.week, instructor: routeQuery?.instructor,
    from: returning && routeQuery?.from === 'eleves' ? routeQuery.week ? 'agenda' : undefined : 'trajets',
    ...(!returning && learner ? { learner } : {}) });
  return <div className="section-stack">
    <SectionHeading title={learner ? 'Trajets de l’élève' : 'Trajets'} actions={learner ? <div className="button-row">
      <button type="button" className="button secondary" onClick={() => dossier(learner, true)}>Retour au dossier</button>
      <button type="button" className="button quiet" onClick={() => navigate('trajets')}>Tous les trajets</button>
    </div> : undefined} />
    <LoadState loaded={loaded} label="Lecture des trajets…">{page => {
      const visible = page.items.filter(trip => matchesSearch([trip.learnerName, trip.instructorName], query));
      return <>
      <div className="list-toolbar">
        <TextField label={learner ? 'Rechercher un moniteur' : 'Rechercher dans cette page'} value={query} onChange={setQuery} placeholder={learner ? 'Moniteur' : 'Élève ou moniteur'} />
        {query && <button type="button" className="button quiet" onClick={() => setQuery('')}>Effacer la recherche</button>}
      </div>
      {page.truncated && <Notice tone="warning" title="Historique partiel" live={false}><p>Ce filtre porte sur les 1 000 derniers trajets de l’école. Ouvrez tous les trajets pour parcourir les plus anciens.</p></Notice>}
      <p className="list-summary" role="status">{visible.length} {visible.length === 1 ? 'trajet' : 'trajets'}{query ? visible.length === 1 ? ' trouvé' : ' trouvés' : ''}{!learner ? ` · page ${cursors.length}` : ''}</p>
      {visible.length === 0 ? <EmptyState symbol="route" title={page.items.length ? 'Aucun trajet trouvé' : page.truncated ? 'Aucun trajet dans cette partie de l’historique' : 'Aucun trajet'} message="" />
        : <table className="data-table trip-table"><caption className="visually-hidden">{learner ? 'Trajets de l’élève' : 'Trajets de l’école'}</caption>
          <thead><tr><th scope="col">Élève et moniteur</th><th scope="col">Trajet</th></tr></thead>
          <tbody>{visible.map(trip => <tr key={trip.id}>
            <th scope="row"><button type="button" className="row-button" onClick={() => dossier(trip.learnerId)}>{trip.learnerName}</button>
              <span className="row-meta block">{trip.instructorName}</span></th>
            <td><TripTime value={trip.authorizedAt} timeZone={trip.lessonTimeZone} />
              <span className="trip-duration row-meta block">Durée : {tripDuration(trip)}</span></td>
          </tr>)}</tbody>
        </table>}
      <nav className="button-row" aria-label="Pages des trajets">
        {cursors.length > 1 && <button type="button" className="button secondary" disabled={loaded.status === 'loading'} onClick={() => { setQuery(''); setCursors(values => values.slice(0, -1)); }}>Précédents</button>}
        {page.nextCursor && <button type="button" className="button secondary" disabled={loaded.status === 'loading'} onClick={() => { setQuery(''); setCursors(values => [...values, page.nextCursor]); }}>Suivants</button>}
      </nav>
    </>; }}</LoadState>
  </div>;
}
