import { useState } from 'react';
import { matchesSearch } from '../command-core';
import { readPage } from '../school-api';
import { tripDuration, tripSchema } from '../trip-model';
import { EmptyState, TextField, formatDateTime } from '../ui';
import { useConsole, useLoad } from './context';
import { LoadState, SectionHeading } from './layout';

/** Administrative trip inventory; API/RLS controls the school scope of every page. */
export function TripsSection() {
  const { schoolId } = useConsole();
  const [query, setQuery] = useState('');
  const [cursors, setCursors] = useState<(string | null)[]>([null]);
  const cursor = cursors.at(-1);
  const loaded = useLoad(() => readPage(schoolId, 'captures', tripSchema, cursor), [schoolId, cursor]);
  return <div className="section-stack">
    <SectionHeading title="Trajets" />
    <LoadState loaded={loaded} label="Lecture des trajets…">{page => <>
      <TextField label="Rechercher dans cette page" value={query} onChange={setQuery} placeholder="Élève ou moniteur" />
      {page.items.length === 0 ? <EmptyState symbol="layers" title="Aucun trajet" message="Les trajets enregistrés pendant les leçons apparaîtront ici." />
        : <table className="data-table"><caption className="visually-hidden">Trajets de l’école</caption>
          <thead><tr><th scope="col">Élève</th><th scope="col">Moniteur</th><th scope="col">Départ</th><th scope="col">Durée</th></tr></thead>
          <tbody>{page.items.filter(trip => matchesSearch([trip.learnerName, trip.instructorName], query)).map(trip => <tr key={trip.id}>
            <th scope="row">{trip.learnerName}</th><td>{trip.instructorName}</td>
            <td>{formatDateTime(trip.authorizedAt, trip.lessonTimeZone)}</td><td>{tripDuration(trip)}</td>
          </tr>)}</tbody>
        </table>}
      <div className="button-row">
        {cursors.length > 1 && <button type="button" className="button secondary" disabled={loaded.status === 'loading'} onClick={() => { setQuery(''); setCursors(values => values.slice(0, -1)); }}>Précédents</button>}
        {page.nextCursor && <button type="button" className="button secondary" disabled={loaded.status === 'loading'} onClick={() => { setQuery(''); setCursors(values => [...values, page.nextCursor]); }}>Suivants</button>}
      </div>
    </>}</LoadState>
  </div>;
}
