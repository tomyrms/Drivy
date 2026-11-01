import { useEffect, type ReactNode } from 'react';
import { addDays } from '../../agenda-model';
import { MeasureList, MeasureRow, type MeasureRowProps } from './components';
import type { MeasureComparison } from './measure-format';
import { useOptionalMetrics, type MetricDefinition, type MetricDomain, type MetricFilters, type MetricMeasure, type MetricsAnswer } from './metrics-api';
import { formatSpan, type ResolvedPeriod } from './period-model';

/**
 * Un groupe de mesures sous un titre. Avec `onlyWhenOpen`, une mesure n'est montrée que s'il y a quelque chose à traiter ou si son zéro n'est pas garanti.
 * `total` désigne la mesure que le serveur définit comme la somme des `ids` du groupe : elle se lit sous un filet, les termes précédés d'un signe.
 * `outside` place après ce total des mesures qui n'en font pas partie, montrées seulement s'il y a quelque chose, avec leur précision.
 * `column` range le groupe dans la seconde colonne du relevé sur un écran large ; `action` se place à droite du titre.
 */
export interface MeasureGroup {
  title: string;
  ids: readonly string[];
  onlyWhenOpen?: boolean;
  total?: string | undefined;
  outside?: { ids: readonly string[]; note: string };
  column?: 2;
  action?: ReactNode;
}

const isOpen = (measure: MetricMeasure) => measure.value === null ? measure.coverage.status !== 'NOT_APPLICABLE' : measure.value > 0;
const labelOf = (definitions: ReadonlyMap<string, MetricDefinition>, id: string) => definitions.get(id)?.label ?? id;

/**
 * Le relevé d'un domaine, avec ses comparaisons. Sur une période écoulée, l'écart vient de la même lecture. Pour le mois en cours (`toDate`),
 * il vient d'une seconde lecture du 1er à aujourd'hui, comparée par le serveur à la même plage du mois précédent, et ne concerne que les mesures
 * dont la valeur est la même dans la période entière et dans la période écoulée (`comparableToDate`). Sans cette lecture, les lignes s'affichent sans écart.
 */
export function MeasureGroups({ domain, groups, answer, definitions, period, today, filters, toDate, comparableToDate, onOpen, returnFocus, onFocused }: {
  domain: MetricDomain;
  groups: readonly MeasureGroup[];
  answer: MetricsAnswer;
  definitions: ReadonlyMap<string, MetricDefinition>;
  period: ResolvedPeriod;
  today: string;
  filters: MetricFilters;
  toDate: boolean;
  comparableToDate: ReadonlySet<string>;
  /** Ouvre les lignes d'une mesure (#380) ; sans lui, aucune ligne ne mène au détail. */
  onOpen?: ((measure: string) => void) | undefined;
  /** Mesure dont le détail vient d'être refermé : sa ligne reprend le focus dès qu'elle est affichée. */
  returnFocus?: string | undefined;
  onFocused?: (() => void) | undefined;
}) {
  const dated = useOptionalMetrics(toDate ? { domain, from: period.from, toExclusive: addDays(today, 1), compare: 'previous-month', ...filters } : null);
  const comparison = toDate ? (dated.status === 'ready' ? dated.data?.comparison : undefined) : answer.comparison;
  useEffect(() => {
    if (!returnFocus) return;
    const target = document.querySelector<HTMLElement>(`[data-measure="${returnFocus}"] .pilotage-row-open`);
    if (target) { target.focus(); onFocused?.(); }
  });
  const label = comparison ? `vs ${formatSpan(comparison.base.from, addDays(comparison.base.toExclusive, -1), today.slice(0, 4))}` : undefined;
  const present = (id: string) => answer.measures[id] !== undefined;
  const row = (id: string, extra: Pick<MeasureRowProps, 'position' | 'note'> = {}) => {
    const change: MeasureComparison | undefined = toDate && !comparableToDate.has(id) ? undefined : comparison?.measures[id];
    const measure = answer.measures[id]!, openable = onOpen !== undefined && definitions.get(id)?.details === true && measure.value !== null && measure.value > 0;
    return <MeasureRow key={id} measureId={id} label={labelOf(definitions, id)} measure={measure} definition={definitions.get(id)} comparison={change} comparisonLabel={label}
      onOpen={openable ? () => onOpen(id) : undefined} {...extra} />;
  };
  const sections = groups.flatMap(group => {
    const ids = group.ids.filter(id => present(id) && (!group.onlyWhenOpen || isOpen(answer.measures[id]!)));
    const total = group.total && present(group.total) ? group.total : undefined;
    const outside = (group.outside?.ids ?? []).filter(id => present(id) && isOpen(answer.measures[id]!));
    if (ids.length === 0 && !total && outside.length === 0) return [];
    // Le signe ne se lit que si la somme est affichée sous ses termes.
    const summed = total !== undefined && ids.length > 1;
    return [{ column: group.column ?? 1, node: <MeasureList key={group.title} title={group.title} action={group.action}>
      {ids.map((id, index) => row(id, summed && index > 0 ? { position: 'term' } : {}))}
      {total && row(total, summed ? { position: 'total' } : {})}
      {outside.map(id => row(id, { position: 'outside', note: group.outside!.note }))}
    </MeasureList> }];
  });
  if (!sections.some(section => section.column === 2)) return <div className="pilotage-statement">{sections.map(section => section.node)}</div>;
  return <div className="pilotage-statement" data-columns="2">
    {[1, 2].map(column => <div key={column} className="pilotage-statement-column">{sections.filter(section => section.column === column).map(section => section.node)}</div>)}
  </div>;
}
