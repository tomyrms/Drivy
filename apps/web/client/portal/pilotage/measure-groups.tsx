import { addDays } from '../../agenda-model';
import { MetricSection, MetricTile } from './components';
import type { MeasureComparison } from './measure-format';
import { useOptionalMetrics, type MetricDefinition, type MetricDomain, type MetricFilters, type MetricMeasure, type MetricsAnswer } from './metrics-api';
import { formatSpan, type ResolvedPeriod } from './period-model';

/** Un groupe de mesures sous un titre. Avec `onlyWhenOpen`, une mesure n'est montrée que s'il y a quelque chose à traiter ou si son zéro n'est pas garanti. */
export interface MeasureGroup { title: string; ids: readonly string[]; onlyWhenOpen?: boolean }

const isOpen = (measure: MetricMeasure) => measure.value === null ? measure.coverage.status !== 'NOT_APPLICABLE' : measure.value > 0;
const labelOf = (definitions: ReadonlyMap<string, MetricDefinition>, id: string) => definitions.get(id)?.label ?? id;

/**
 * Les groupes de mesures d'un domaine, avec leur comparaison. Sur une période écoulée, l'écart vient de la même lecture. Pour le mois en cours (`toDate`),
 * il vient d'une seconde lecture du 1er à aujourd'hui, comparée par le serveur à la même plage du mois précédent, et ne concerne que les mesures
 * dont la valeur est la même dans la période entière et dans la période écoulée (`comparableToDate`). Sans cette lecture, les tuiles s'affichent sans écart.
 */
export function MeasureGroups({ domain, groups, answer, definitions, period, today, filters, toDate, comparableToDate, onOpen }: {
  domain: MetricDomain;
  groups: readonly MeasureGroup[];
  answer: MetricsAnswer;
  definitions: ReadonlyMap<string, MetricDefinition>;
  period: ResolvedPeriod;
  today: string;
  filters: MetricFilters;
  toDate: boolean;
  comparableToDate: ReadonlySet<string>;
  /** Ouvre les lignes d'une mesure (#380) ; sans lui, aucune tuile ne mène au détail. */
  onOpen?: ((measure: string) => void) | undefined;
}) {
  const dated = useOptionalMetrics(toDate ? { domain, from: period.from, toExclusive: addDays(today, 1), compare: 'previous-month', ...filters } : null);
  const comparison = toDate ? (dated.status === 'ready' ? dated.data?.comparison : undefined) : answer.comparison;
  const label = comparison ? `vs ${formatSpan(comparison.base.from, addDays(comparison.base.toExclusive, -1), today.slice(0, 4))}` : undefined;
  return <>{groups.map(group => {
    const ids = group.ids.filter(id => {
      const measure = answer.measures[id];
      return measure !== undefined && (!group.onlyWhenOpen || isOpen(measure));
    });
    if (ids.length === 0) return null;
    return <MetricSection key={group.title} title={group.title}>
      {ids.map(id => {
        const change: MeasureComparison | undefined = toDate && !comparableToDate.has(id) ? undefined : comparison?.measures[id];
        const measure = answer.measures[id]!, openable = onOpen !== undefined && definitions.get(id)?.details === true && measure.value !== null && measure.value > 0;
        return <MetricTile key={id} label={labelOf(definitions, id)} measure={measure} definition={definitions.get(id)} comparison={change} comparisonLabel={label}
          action={openable ? { label: 'Voir le détail', onClick: () => onOpen(id) } : undefined} />;
      })}
    </MetricSection>;
  })}</>;
}
