import { addDays } from '../../agenda-model';
import { formatCivil, formatSpan } from './period-model';
import type { MetricsAnswer, SeriesAnswer } from './metrics-api';
import type { ChartBucket } from './stacked-bars';

/** Règles des graphiques de pilotage (#378) : pures, sans réseau. */
export type Granularity = 'day' | 'week' | 'month';

/** Jusqu'à deux semaines, un point par jour ; jusqu'à trois mois, par semaine ; au-delà, par mois. */
export function chooseGranularity(days: number): Granularity {
  return days <= 14 ? 'day' : days <= 93 ? 'week' : 'month';
}

const shortDay = new Intl.DateTimeFormat('fr-CH', { day: 'numeric', month: 'short', timeZone: 'UTC' });
const shortMonth = new Intl.DateTimeFormat('fr-CH', { month: 'short', timeZone: 'UTC' });
const longMonth = new Intl.DateTimeFormat('fr-CH', { month: 'long', year: 'numeric', timeZone: 'UTC' });
const atNoon = (civil: string) => new Date(`${civil}T12:00:00Z`);

/** Étiquette courte de l'axe et titre complet lu au toucher ou au clavier ; un intervalle rogné par la période se dit partiel. */
export function chartBucket(granularity: Granularity, bucket: Pick<SeriesAnswer['buckets'][number], 'from' | 'toExclusive' | 'partial'>, referenceYear: string, values: ChartBucket['values']): ChartBucket {
  const lastDay = addDays(bucket.toExclusive, -1);
  const partial = bucket.partial ? ' (partielle)' : '';
  if (granularity === 'day') return { key: bucket.from, label: String(Number(bucket.from.slice(8))), title: formatCivil(bucket.from), values };
  if (granularity === 'week') return { key: bucket.from, label: shortDay.format(atNoon(bucket.from)), title: `Semaine ${formatSpan(bucket.from, lastDay, referenceYear)}${partial}`, values };
  return { key: bucket.from, label: shortMonth.format(atNoon(bucket.from)), title: `${longMonth.format(atNoon(bucket.from))}${partial}`, values };
}

export interface BreakdownRow { key: string; label: string; value: number }
const unattributed = 'Non attribué';

/**
 * Lignes d'une répartition pour une mesure. Rangées par nom, jamais par valeur : un volume brut ne classe pas les moniteurs (R94).
 * Une valeur absente ou non applicable n'est pas dessinée ; un zéro connu ne l'est pas non plus, il n'ajoute qu'une ligne vide.
 * Les groupes que le serveur n'a pas pu attribuer passent en dernier.
 */
export function breakdownRows(breakdown: MetricsAnswer['breakdown'], measureId: string): BreakdownRow[] {
  if (!breakdown) return [];
  const rows = breakdown.groups.flatMap(group => {
    const measure = group.measures[measureId];
    if (!measure || measure.value === null || measure.value <= 0 || measure.coverage.status === 'NOT_APPLICABLE') return [];
    const unresolved = group.key === 'UNRESOLVED';
    const label = unresolved ? unattributed : group.label ?? (breakdown.by === 'category' ? `Permis ${group.key}` : group.key);
    return [{ key: group.key, label, value: measure.value, unresolved }];
  });
  return rows.sort((a, b) => Number(a.unresolved) - Number(b.unresolved) || a.label.localeCompare(b.label, 'fr'))
    .map(({ key, label, value }) => ({ key, label, value }));
}
