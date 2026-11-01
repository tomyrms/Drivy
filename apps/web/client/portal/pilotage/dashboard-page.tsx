import { CircleCheck, Plus } from 'lucide-react';
import { addDays, civilDateIn } from '../../agenda-model';
import { useConsole } from '../../console/context';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { ReadFeedback } from '../components/feedback';
import { chartBucket } from './chart-model';
import { InstructorSelect, MeasureList, MeasureRow, PilotageSection } from './components';
import { Appointments } from './dashboard-appointments';
import { lessonValueGroup } from './finance-panel';
import { MetricsView, ScopeLine } from './metrics-view';
import { MeasureGroups, type MeasureGroup } from './measure-groups';
import { useMetricSeries, type MetricDefinition, type MetricMeasure } from './metrics-api';
import { currentMonth, formatCivil, periodLabel, type ResolvedPeriod } from './period-model';
import { metricRights } from './rights';
import { StackedBars } from './stacked-bars';
import { summarizeToday } from './today-summary';
import { useDirectory } from './use-directory';

/** Mesures du serveur qui demandent une action ; les trois s'ouvrent dans l'agenda, où se trouvent les leçons et les séances. */
const todo = ['A01', 'A02', 'A03'] as const;
/** Sont montrées celles qui ont quelque chose à traiter, ou dont le serveur ne peut pas garantir le zéro. */
const needsAction = (measure: MetricMeasure | undefined): measure is MetricMeasure =>
  measure !== undefined && (measure.value === null ? measure.coverage.status !== 'NOT_APPLICABLE' : measure.value > 0);

type Navigate = ReturnType<typeof useConsole>['navigate'];
interface Scope { today: string; instructor: string | undefined }
const labelOf = (definitions: ReadonlyMap<string, MetricDefinition>, id: string) => definitions.get(id)?.label ?? id;

/**
 * Tableau de bord (#373, T04 #377 ; composition #397) : la journée et ses actions d'abord, puis les rendez-vous, puis le mois — son relevé
 * d'activité et, pour qui y a droit, ses valeurs financières côte à côte, au-dessus de l'évolution jour par jour. Chaque bloc lit pour lui-même :
 * l'échec d'un bloc ne retire ni l'accès au planning ni les autres blocs.
 */
export function DashboardPilot() {
  const { school, membership, navigate, routeQuery, setRouteQuery } = useConsole();
  const rights = metricRights(membership);
  const today = civilDateIn(school.timeZone);
  const instructor = routeQuery?.instructor;
  const { instructorOptions, learnerName, memberName } = useDirectory({ learners: true });
  const scope: Scope = { today, instructor };
  const scopeLabel = instructorOptions.find(option => option.value === instructor)?.label ?? 'Toute l’école';
  return <section className="pilotage-page">
    <header className="pilotage-heading">
      <div><h1>Tableau de bord</h1><p>{formatCivil(today)}</p></div>
      <div className="pilotage-heading-actions">
        <InstructorSelect value={instructor} options={instructorOptions} onChange={value => setRouteQuery?.({ ...routeQuery, instructor: value }, true)} />
        <Button onClick={() => navigate('agenda', { view: 'nouvelle' })}><Plus data-icon="inline-start" aria-hidden="true" />Planifier une leçon</Button>
      </div>
    </header>
    {rights.activity && <TodayBlock {...scope} navigate={navigate} />}
    <Appointments today={today} instructor={instructor} learnerName={learnerName} memberName={memberName} />
    {(rights.activity || rights.finance) && <div className="pilotage-month">
      <div className="pilotage-month-figures">
        {rights.activity && <MonthBlock {...scope} scopeLabel={scopeLabel} />}
        {rights.finance && <FinanceBlock {...scope} navigate={navigate} />}
      </div>
      {rights.activity && <MonthChart month={currentMonth(today)} instructor={instructor} />}
    </div>}
  </section>;
}

/** La journée en une phrase, puis ce qui reste à traiter. */
function TodayBlock({ today, instructor, navigate }: Scope & { navigate: Navigate }) {
  return <MetricsView label="Lecture de la journée" request={{ domain: 'activity', from: today, toExclusive: addDays(today, 1), instructor }}>
    {(answer, definitions) => {
      const summary = summarizeToday(answer);
      const pending = todo.filter(id => needsAction(answer.measures[id]));
      const [lead, ...rest] = summary.segments;
      return <>
        <PilotageSection title="Aujourd’hui">
          <p className="pilotage-today"><strong>{lead}</strong>{rest.map(segment => <span key={segment}> · {segment}</span>)}
            {summary.incomplete && <> <Badge variant="outline">Partiel</Badge></>}</p>
        </PilotageSection>
        <MeasureList title="À traiter">
          {pending.length === 0
            ? <li className="pilotage-row pilotage-row-done"><CircleCheck aria-hidden="true" />Rien à traiter</li>
            : pending.map(id => <MeasureRow key={id} label={labelOf(definitions, id)} measure={answer.measures[id]!} definition={definitions.get(id)}
              action={{ label: 'Ouvrir l’agenda', onClick: () => navigate('agenda', instructor ? { instructor } : {}) }} />)}
        </MeasureList>
      </>;
    }}
  </MetricsView>;
}

/** Ce mois-ci : valeurs du mois entier, écart à date avec le mois dernier (voir `MeasureGroups`). */
const monthGroups: readonly MeasureGroup[] = [{ title: 'Ce mois-ci', ids: ['L01', 'L02', 'H02'] }];
const monthComparable: ReadonlySet<string> = new Set(['L01', 'H02']);
const noComparison: ReadonlySet<string> = new Set();
function MonthBlock({ today, instructor, scopeLabel }: Scope & { scopeLabel: string }) {
  const month = currentMonth(today);
  return <div className="pilotage-month-block">
    <MetricsView label="Lecture du mois" request={{ domain: 'activity', from: month.from, toExclusive: month.toExclusive, instructor }}>
      {(answer, definitions) => <>
        <MeasureGroups domain="activity" groups={monthGroups} answer={answer} definitions={definitions} period={month} today={today} filters={{ instructor }} toDate comparableToDate={monthComparable} />
        <ScopeLine period={periodLabel(month)} scope={scopeLabel} answer={answer} />
      </>}
    </MetricsView>
  </div>;
}

/** Leçons réalisées et à venir, par jour : la part réalisée est pleine, la part à venir hachurée. */
function MonthChart({ month, instructor }: { month: ResolvedPeriod; instructor: string | undefined }) {
  const series = useMetricSeries({ from: month.from, toExclusive: month.toExclusive, granularity: 'day', measures: ['L01', 'L02'], instructor });
  if (!series.data) return <ReadFeedback loaded={series} label="Lecture de l’évolution du mois" />;
  return <>{series.status === 'error' && <ReadFeedback loaded={series} label="Lecture de l’évolution du mois" />}<StackedBars title="Leçons par jour" periodText={periodLabel(month)} emptyText="Aucune leçon ce mois-ci."
    series={[{ label: 'Réalisées', pattern: 'solid' }, { label: 'À venir', pattern: 'hatch' }]}
    buckets={series.data.buckets.map(bucket => chartBucket('day', bucket, month.from.slice(0, 4), [bucket.measures.L01?.value ?? null, bucket.measures.L02?.value ?? null]))} /></>;
}

/**
 * Valeurs financières du mois pour qui y a droit, en relevé : réalisé, à venir et leur total selon le planning, jamais présentés comme un
 * encaissement. Le lien garde le moniteur filtré.
 */
function FinanceBlock({ today, instructor, navigate }: Scope & { navigate: Navigate }) {
  const month = currentMonth(today);
  const groups: readonly MeasureGroup[] = [{ title: 'Finances du mois', ids: lessonValueGroup.ids, total: lessonValueGroup.total,
    action: <Button variant="ghost" size="sm" onClick={() => navigate('statistiques', { tab: 'finance', ...(instructor ? { instructor } : {}) })}>Voir les finances</Button> }];
  return <div className="pilotage-month-block">
    <MetricsView label="Lecture des valeurs du mois" request={{ domain: 'finance', from: month.from, toExclusive: month.toExclusive, instructor }}>
      {(answer, definitions) => <MeasureGroups domain="finance" groups={groups} answer={answer} definitions={definitions} period={month} today={today} filters={{ instructor }} toDate={false} comparableToDate={noComparison} />}
    </MetricsView>
  </div>;
}
