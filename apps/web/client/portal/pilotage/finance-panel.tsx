import { useState } from 'react';
import { ReadFeedback } from '../components/feedback';
import { BreakdownBars, BreakdownChoice } from './breakdown-bars';
import { breakdownRows, chartBucket, chooseGranularity } from './chart-model';
import { MeasureGroups, type MeasureGroup } from './measure-groups';
import { formatFrancsShort, formatMeasure } from './measure-format';
import { MetricsView, ScopeLine } from './metrics-view';
import { useMetrics, useMetricSeries, type MetricFilters } from './metrics-api';
import { comparisonPlan, periodLabel, type ResolvedPeriod } from './period-model';
import { StackedBars } from './stacked-bars';

/**
 * Relevé de l'onglet Finances (#379). Quatre notions restent séparées et nommées pour ce qu'elles sont : la valeur des leçons réalisées,
 * celle des leçons à venir, leur total selon le planning (le serveur le définit comme leur somme, jamais augmentée d'un règlement) et les
 * règlements enregistrés, par date de saisie, dans leur propre colonne. Les titres disent la couverture : seules les leçons individuelles au
 * tarif à l'unité sont valorisées, les cours collectifs ne le sont pas.
 */
export const lessonValueGroup: MeasureGroup = {
  title: 'Leçons individuelles (tarif à l’unité)', ids: ['F01', 'F02'], total: 'F03',
  // Une leçon commencée ou dont l'heure est passée n'est ni réalisée ni une réservation certaine : elle se lit après le total, hors de lui.
  outside: { ids: ['F04'], note: 'hors du total' },
};
const groups: readonly MeasureGroup[] = [
  lessonValueGroup,
  { title: 'Règlements enregistrés (par date de saisie)', ids: ['F05', 'F06'], column: 2 },
  { title: 'Cours collectifs', ids: ['F07'], column: 2 },
];
/** À date, seules les valeurs déjà constatées sont les mêmes dans la période entière et dans la période écoulée. */
const comparableToDate: ReadonlySet<string> = new Set(['F01', 'F05']);

const money = (value: number) => formatMeasure(value, 'cents');
const unitName = { day: 'jour', week: 'semaine', month: 'mois' } as const;

export function FinancePanel({ period, today, filters, scopeLabel, onOpen, returnFocus, onFocused }: { period: ResolvedPeriod; today: string; filters: MetricFilters; scopeLabel: string; onOpen?: (measure: string) => void; returnFocus?: string | undefined; onFocused?: () => void }) {
  const plan = comparisonPlan(period, today);
  return <MetricsView label="Lecture des finances" request={{ domain: 'finance', from: period.from, toExclusive: period.toExclusive, ...filters, compare: plan.kind === 'direct' ? plan.compare : undefined }}>
    {(answer, definitions) => <>
      <ScopeLine period={periodLabel(period)} scope={answer.scope.kind === 'self' ? 'Vos leçons' : scopeLabel} answer={answer} />
      <MeasureGroups domain="finance" groups={groups} answer={answer} definitions={definitions} period={period} today={today} filters={filters} toDate={plan.kind === 'to-date'} comparableToDate={comparableToDate} onOpen={onOpen} returnFocus={returnFocus} onFocused={onFocused} />
      <div className="pilotage-charts">
        <Evolution period={period} filters={filters} />
        <ValueMix period={period} filters={filters} />
      </div>
    </>}
  </MetricsView>;
}

/**
 * Valeur réalisée (plein) et à venir (hachuré) par intervalle, puis les règlements à part : une date de prestation et une date de saisie
 * ne se lisent pas sur le même graphique. Un règlement ne dépend pas d'une leçon : avec un filtre moniteur, permis ou prestation, il n'a pas de série.
 */
function Evolution({ period, filters }: { period: ResolvedPeriod; filters: MetricFilters }) {
  const granularity = chooseGranularity(period.days);
  const filtered = Boolean(filters.instructor || filters.category || filters.product);
  const series = useMetricSeries({ from: period.from, toExclusive: period.toExclusive, granularity, measures: filtered ? ['F01', 'F02'] : ['F01', 'F02', 'F05'], ...filters });
  if (!series.data) return <ReadFeedback loaded={series} label="Lecture de l’évolution" />;
  const year = period.from.slice(0, 4), buckets = series.data.buckets;
  const value = (bucket: (typeof buckets)[number], id: string) => bucket.measures[id]?.value ?? null;
  return <>
    {series.status === 'error' && <ReadFeedback loaded={series} label="Lecture de l’évolution" />}
    <StackedBars title={`Valeur des leçons par ${unitName[granularity]}`} periodText={periodLabel(period)} emptyText="Aucune valeur de leçon sur cette période."
      series={[{ label: 'Réalisée', pattern: 'solid' }, { label: 'À venir', pattern: 'hatch' }]} format={money} tickFormat={formatFrancsShort}
      buckets={buckets.map(bucket => chartBucket(granularity, bucket, year, [value(bucket, 'F01'), value(bucket, 'F02')]))} />
    {!filtered && <StackedBars title={`Règlements enregistrés par ${unitName[granularity]}`} note="Par date de saisie" periodText={`${periodLabel(period)} · date de saisie`} emptyText="Aucun règlement enregistré sur cette période."
      series={[{ label: 'Enregistrés', pattern: 'solid' }]} format={money} tickFormat={formatFrancsShort}
      buckets={buckets.map(bucket => chartBucket(granularity, bucket, year, [value(bucket, 'F05')]))} />}
  </>;
}

type Mix = 'category' | 'product' | 'instructor';
const mixTitle = { category: 'par permis', product: 'par prestation', instructor: 'par moniteur' } as const;
const mixOptions = [{ value: 'category', label: 'Par permis' }, { value: 'product', label: 'Par prestation' }, { value: 'instructor', label: 'Par moniteur' }] as const;
/** Valeur des leçons réalisées par permis, prestation ou moniteur. Lignes rangées par nom : un montant ne classe personne. */
function ValueMix({ period, filters }: { period: ResolvedPeriod; filters: MetricFilters }) {
  const [by, setBy] = useState<Mix>('category');
  const chosen: Mix = by === 'instructor' && filters.instructor ? 'category' : by;
  const loaded = useMetrics({ domain: 'finance', from: period.from, toExclusive: period.toExclusive, ...filters, breakdown: chosen });
  const title = `Valeur des leçons réalisées ${mixTitle[chosen]}`;
  const choice = <BreakdownChoice label="Répartition de la valeur des leçons réalisées" value={chosen} options={filters.instructor ? mixOptions.slice(0, 2) : mixOptions} onChange={setBy} />;
  if (!loaded.data) return <BreakdownBars title={title} periodText={periodLabel(period)} action={choice} rows={null} format={money} emptyText="" notice={<ReadFeedback loaded={loaded} label="Lecture de la répartition" />} />;
  return <BreakdownBars title={title} notice={loaded.status === 'error' ? <ReadFeedback loaded={loaded} label="Lecture de la répartition" /> : undefined} periodText={periodLabel(period)} action={choice}
    rows={breakdownRows(loaded.data.breakdown, 'F01')} format={money} emptyText="Aucune valeur de leçon réalisée sur cette période." />;
}
