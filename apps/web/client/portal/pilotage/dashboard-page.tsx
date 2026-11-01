import { CircleCheck, Plus } from 'lucide-react';
import { civilDateIn } from '../../agenda-model';
import { useConsole } from '../../console/context';
import { Button } from '../../components/ui/button';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { MetricSection, MetricTile } from './components';
import { MetricsView, ScopeLine } from './metrics-view';
import { currentMonth, formatCivil, periodLabel } from './period-model';
import { metricRights } from './rights';
import type { MetricMeasure } from './metrics-api';

/** Mesures du serveur qui demandent une action ; les trois s'ouvrent dans l'agenda, où se trouvent les leçons et les séances. */
const todo = ['A01', 'A02', 'A03'] as const;
/** Sont montrées celles qui ont quelque chose à traiter, ou dont le serveur ne peut pas garantir le zéro. */
const needsAction = (measure: MetricMeasure | undefined): measure is MetricMeasure =>
  measure !== undefined && (measure.value === null ? measure.coverage.status !== 'NOT_APPLICABLE' : measure.value > 0);

/**
 * Tableau de bord (#373). Cette composition pose la place de chaque bloc avec les chiffres du serveur ; la liste chronologique
 * des rendez-vous, l'encart financier et l'évolution du mois sont portés par T04 (#377). Deux graphiques au plus y trouveront leur place.
 */
export function DashboardPilot() {
  const { school, membership, navigate } = useConsole();
  const rights = metricRights(membership);
  const today = civilDateIn(school.timeZone);
  const month = currentMonth(today);
  return <section className="pilotage-page">
    <header className="pilotage-heading">
      <div><h1>Tableau de bord</h1><p>{formatCivil(today)}</p></div>
      <Button onClick={() => navigate('agenda', { view: 'nouvelle' })}><Plus data-icon="inline-start" aria-hidden="true" />Planifier une leçon</Button>
    </header>
    {rights.activity && <MetricsView label="Lecture des chiffres du mois" request={{ domain: 'activity', from: month.from, toExclusive: month.toExclusive }}>
      {(answer, definitions) => {
        const pending = todo.filter(id => needsAction(answer.measures[id]));
        const label = (id: string) => definitions.get(id)?.label ?? id;
        return <div className="pilotage-panel">
          <MetricSection title="À traiter">
            {pending.length === 0
              ? <li className="pilotage-empty"><Empty><EmptyHeader><EmptyMedia variant="icon"><CircleCheck aria-hidden="true" /></EmptyMedia><EmptyTitle>Rien à traiter</EmptyTitle></EmptyHeader></Empty></li>
              : pending.map(id => <MetricTile key={id} label={label(id)} measure={answer.measures[id]!} definition={definitions.get(id)}
                action={{ label: 'Ouvrir l’agenda', onClick: () => navigate('agenda') }} />)}
          </MetricSection>
          <MetricSection title="Ce mois-ci">
            {(['L01', 'L02', 'H02'] as const).filter(id => answer.measures[id] !== undefined)
              .map(id => <MetricTile key={id} label={label(id)} measure={answer.measures[id]!} definition={definitions.get(id)} />)}
          </MetricSection>
          <ScopeLine period={periodLabel(month)} scope="Toute l’école" answer={answer} />
        </div>;
      }}
    </MetricsView>}
  </section>;
}
