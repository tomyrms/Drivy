import { useState } from 'react';
import { matchesSearch } from '../command-core';
import { readAll, readPage } from '../school-api';
import { tripDuration, tripSchema } from '../trip-model';
import { EmptyState, Notice, TextField, formatDateTime } from '../ui';
import { useConsole, useLoad } from './context';
import { LoadState, SectionHeading } from './layout';

/** Administrative trip inventory; API/RLS controls the school scope of every page. */
export function TripsSection() {
  const { schoolId, routeQuery, navigate } = useConsole();
  const learner = routeQuery?.learner;
  const [query, setQuery] = useState('');
  const [cursors, setCursors] = useState<(string | null)[]>([null]);
  const cursor = cursors.at(-1);
  const loaded = useLoad(async () => {
    if (learner) {
      const page = await readAll(schoolId, 'captures', tripSchema);
      return { items: page.items.filter(trip => trip.learnerId === learner), nextCursor: null, truncated: page.truncated };
    }
    return { ...await readPage(schoolId, 'captures', tripSchema, cursor), truncated: false };
  }, [schoolId, cursor, learner]);
  const dossier = (id: string) => navigate('eleves', { selection: id, week: routeQuery?.week, instructor: routeQuery?.instructor,
    ...(routeQuery?.week ? { from: 'agenda' } : {}) });
  return <div className="section-stack">
    <SectionHeading title={learner ? 'Trajets de l’élève' : 'Trajets'} actions={learner ? <div className="button-row">
      <button type="button" className="button secondary" onClick={() => dossier(learner)}>Retour au dossier</button>
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
      {visible.length === 0 ? <EmptyState symbol="route" title={page.items.length ? 'Aucun trajet trouvé' : page.truncated ? 'Aucun trajet dans cette partie de l’historique' : 'Aucun trajet'} message="" />
        : <table className="data-table trip-table"><caption className="visually-hidden">Trajets de l’école</caption>
          <thead><tr><th scope="col">Élève</th><th scope="col">Moniteur</th><th scope="col">Départ</th><th scope="col" className="numeric">Durée</th></tr></thead>
          <tbody>{visible.map(trip => <tr key={trip.id}>
            <th scope="row"><button type="button" className="row-button" onClick={() => dossier(trip.learnerId)}>{trip.learnerName}</button></th><td>{trip.instructorName}</td>
            <td><time dateTime={trip.authorizedAt}>{formatDateTime(trip.authorizedAt, trip.lessonTimeZone)}</time></td><td className="numeric">{tripDuration(trip)}</td>
          </tr>)}</tbody>
        </table>}
      <div className="button-row">
        {cursors.length > 1 && <button type="button" className="button secondary" disabled={loaded.status === 'loading'} onClick={() => { setQuery(''); setCursors(values => values.slice(0, -1)); }}>Précédents</button>}
        {page.nextCursor && <button type="button" className="button secondary" disabled={loaded.status === 'loading'} onClick={() => { setQuery(''); setCursors(values => [...values, page.nextCursor]); }}>Suivants</button>}
      </div>
    </>; }}</LoadState>
  </div>;
}
