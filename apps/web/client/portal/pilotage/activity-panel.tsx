import { useState } from 'react';
import { addDays } from '../../agenda-model';
import { Tabs, TabsList, TabsTrigger } from '../../components/ui/tabs';
import { ReadFeedback } from '../components/feedback';
import { breakdownRows, chartBucket, chooseGranularity } from './chart-model';
import { BreakdownBars } from './breakdown-bars';
import { MetricSection, MetricTile } from './components';
import { formatDuration, formatMeasure, type MeasureComparison } from './measure-format';
import { MetricsView, ScopeLine } from './metrics-view';
import { useMetrics, useMetricSeries, useOptionalMetrics, type MetricDefinition, type MetricFilters, type MetricMeasure, type MetricsAnswer, type MetricsRequest } from './metrics-api';
import { comparisonPlan, formatSpan, periodLabel, type ResolvedPeriod } from './period-model';
import { StackedBars } from './stacked-bars';

/** Mesures de l'onglet Activité (#378), dans l'ordre de lecture. Heures programmées, réalisées et à venir restent trois grandeurs séparées. */
const groups: readonly { title: string; ids: readonly string[] }[] = [
  { title: 'Leçons', ids: ['L01', 'L02', 'L03', 'L04', 'L05', 'L07'] },
  { title: 'Heures', ids: ['H01', 'H02', 'H03'] },
  { title: 'Élèves', ids: ['P01'] },
  { title: 'Cours collectifs', ids: ['C02', 'C01', 'C06', 'C07', 'C09'] },
];
/** Les cas non finalisés ne sont montrés que s'il y en a, ou si le serveur ne peut pas garantir qu'il n'y en a pas. */
const onlyWhenOpen: ReadonlySet<string> = new Set(['L05', 'L07']);
const isOpen = (measure: MetricMeasure) => measure.value === null ? measure.coverage.status !== 'NOT_APPLICABLE' : measure.value > 0;
/** À date, seules les mesures déjà réalisées ont la même valeur dans la période entière et dans la période écoulée. */
const comparableToDate: ReadonlySet<string> = new Set(['L01', 'H02']);

const labelOf = (definitions: ReadonlyMap<string, MetricDefinition>, id: string) => definitions.get(id)?.label ?? id;

/**
 * Statistiques → Activité : mesures du serveur, comparaison à période cohérente et trois graphiques (évolution, charge par moniteur,
 * répartition par permis ou prestation). Aucun classement des moniteurs : les lignes sont rangées par nom.
 */
export function ActivityPanel({ period, today, filters, scopeLabel }: { period: ResolvedPeriod; today: string; filters: MetricFilters; scopeLabel: string }) {
  const plan = comparisonPlan(period, today);
  const request: MetricsRequest = {
    domain: 'activity', from: period.from, toExclusive: period.toExclusive, ...filters,
    compare: plan.kind === 'direct' ? plan.compare : undefined,
    // La charge par moniteur n'a de sens que pour toute l'équipe.
    breakdown: filters.instructor ? undefined : 'instructor',
  };
  return <MetricsView label="Lecture de l’activité" request={request}>
    {(answer, definitions) => <>
      <ScopeLine period={periodLabel(period)} scope={answer.scope.kind === 'self' ? 'Vos leçons' : scopeLabel} answer={answer} />
      <ActivityTiles answer={answer} definitions={definitions} period={period} today={today} filters={filters} toDate={plan.kind === 'to-date'} />
      <div className="pilotage-charts">
        <EvolutionChart period={period} filters={filters} />
        {!filters.instructor && <BreakdownBars title="Heures programmées par moniteur" periodText={periodLabel(period)} rows={breakdownRows(answer.breakdown, 'H01')}
          format={formatDuration} emptyText="Aucune heure programmée sur cette période." />}
        <MixChart period={period} filters={filters} />
      </div>
    </>}
  </MetricsView>;
}

function ActivityTiles({ answer, definitions, period, today, filters, toDate }: {
  answer: MetricsAnswer; definitions: ReadonlyMap<string, MetricDefinition>; period: ResolvedPeriod; today: string; filters: MetricFilters; toDate: boolean;
}) {
  // Le mois en cours se compare à date : une seconde lecture du 1er à aujourd'hui, comparée par le serveur à la même plage du mois précédent.
  const dated = useOptionalMetrics(toDate ? { domain: 'activity', from: period.from, toExclusive: addDays(today, 1), compare: 'previous-month', ...filters } : null);
  const comparison = toDate ? (dated.status === 'ready' ? dated.data?.comparison : undefined) : answer.comparison;
  const label = comparison ? `vs ${formatSpan(comparison.base.from, addDays(comparison.base.toExclusive, -1), today.slice(0, 4))}` : undefined;
  return <>{groups.map(group => {
    const ids = group.ids.filter(id => {
      const measure = answer.measures[id];
      return measure !== undefined && (!onlyWhenOpen.has(id) || isOpen(measure));
    });
    if (ids.length === 0) return null;
    return <MetricSection key={group.title} title={group.title}>
      {ids.map(id => {
        const change: MeasureComparison | undefined = toDate && !comparableToDate.has(id) ? undefined : comparison?.measures[id];
        return <MetricTile key={id} label={labelOf(definitions, id)} measure={answer.measures[id]!} definition={definitions.get(id)} comparison={change} comparisonLabel={label} />;
      })}
    </MetricSection>;
  })}</>;
}

const evolutionTitle = { day: 'Leçons par jour', week: 'Leçons par semaine', month: 'Leçons par mois' } as const;

/** Réalisées en plein, à venir en hachuré ; l'intervalle rogné par la période se dit partiel. */
function EvolutionChart({ period, filters }: { period: ResolvedPeriod; filters: MetricFilters }) {
  const granularity = chooseGranularity(period.days);
  const series = useMetricSeries({ from: period.from, toExclusive: period.toExclusive, granularity, measures: ['L01', 'L02'], ...filters });
  if (series.status !== 'ready' || !series.data) return <ReadFeedback loaded={series} label="Lecture de l’évolution" />;
  return <StackedBars title={evolutionTitle[granularity]} periodText={periodLabel(period)} emptyText="Aucune leçon sur cette période."
    series={[{ label: 'Réalisées', pattern: 'solid' }, { label: 'À venir', pattern: 'hatch' }]}
    buckets={series.data.buckets.map(bucket => chartBucket(granularity, bucket, period.from.slice(0, 4), [bucket.measures.L01?.value ?? null, bucket.measures.L02?.value ?? null]))} />;
}

type Mix = 'category' | 'product';
/** Leçons réalisées par permis ou par prestation, au choix. */
function MixChart({ period, filters }: { period: ResolvedPeriod; filters: MetricFilters }) {
  const [by, setBy] = useState<Mix>('category');
  const loaded = useMetrics({ domain: 'activity', from: period.from, toExclusive: period.toExclusive, ...filters, breakdown: by });
  const choice = <Tabs value={by} onValueChange={value => setBy(value as Mix)}>
    <TabsList aria-label="Répartition des leçons réalisées"><TabsTrigger value="category">Par permis</TabsTrigger><TabsTrigger value="product">Par prestation</TabsTrigger></TabsList>
  </Tabs>;
  if (loaded.status !== 'ready' || !loaded.data) return <figure className="pilotage-chart">{choice}<ReadFeedback loaded={loaded} label="Lecture de la répartition" /></figure>;
  return <BreakdownBars title={by === 'category' ? 'Leçons réalisées par permis' : 'Leçons réalisées par prestation'} periodText={periodLabel(period)} action={choice}
    rows={breakdownRows(loaded.data.breakdown, 'L01')} format={value => formatMeasure(value, 'count')} emptyText="Aucune leçon réalisée sur cette période." />;
}
