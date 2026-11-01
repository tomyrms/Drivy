import { useState } from 'react';
import { Tabs, TabsList, TabsTrigger } from '../../components/ui/tabs';
import { ReadFeedback } from '../components/feedback';
import { breakdownRows, chartBucket, chooseGranularity } from './chart-model';
import { BreakdownBars } from './breakdown-bars';
import { MeasureGroups, type MeasureGroup } from './measure-groups';
import { formatDuration, formatMeasure } from './measure-format';
import { MetricsView, ScopeLine } from './metrics-view';
import { useMetrics, useMetricSeries, type MetricFilters, type MetricsRequest } from './metrics-api';
import { comparisonPlan, periodLabel, type ResolvedPeriod } from './period-model';
import { StackedBars } from './stacked-bars';

/** Mesures de l'onglet Activité (#378), dans l'ordre de lecture. Heures programmées, réalisées et à venir restent trois grandeurs séparées. */
const groups: readonly MeasureGroup[] = [
  { title: 'Leçons', ids: ['L01', 'L02', 'L03', 'L04'] },
  // Les cas non finalisés ne sont jamais comptés comme réalisés : ils ont leur place, et n'apparaissent que s'il y en a.
  { title: 'À vérifier', ids: ['L05', 'L07'], onlyWhenOpen: true },
  { title: 'Heures', ids: ['H01', 'H02', 'H03'] },
  { title: 'Élèves', ids: ['P01'] },
  { title: 'Cours collectifs', ids: ['C02', 'C01', 'C06', 'C07', 'C09'] },
];
/** À date, seules les mesures déjà réalisées ont la même valeur dans la période entière et dans la période écoulée. */
const comparableToDate: ReadonlySet<string> = new Set(['L01', 'H02']);

/**
 * Statistiques → Activité : mesures du serveur, comparaison à période cohérente et trois graphiques (évolution, charge par moniteur,
 * répartition par permis ou prestation). Aucun classement des moniteurs : les lignes sont rangées par nom.
 */
export function ActivityPanel({ period, today, filters, scopeLabel, onOpen }: { period: ResolvedPeriod; today: string; filters: MetricFilters; scopeLabel: string; onOpen?: (measure: string) => void }) {
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
      <MeasureGroups domain="activity" groups={groups} answer={answer} definitions={definitions} period={period} today={today} filters={filters} toDate={plan.kind === 'to-date'} comparableToDate={comparableToDate} onOpen={onOpen} />
      <div className="pilotage-charts">
        <EvolutionChart period={period} filters={filters} />
        {!filters.instructor && <BreakdownBars title="Heures programmées par moniteur" periodText={periodLabel(period)} rows={breakdownRows(answer.breakdown, 'H01')}
          format={formatDuration} emptyText="Aucune heure programmée sur cette période." />}
        <MixChart period={period} filters={filters} />
      </div>
    </>}
  </MetricsView>;
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
