import { addDays } from '../../agenda-model';
import type { NavigationQuery, PeriodChoice } from '../../console/route';

/** Pilotage (#373) : la période se choisit en jours civils de l'école ; le serveur reçoit un début inclus et une fin exclue. */
export const maxPeriodDays = 366;
export interface ResolvedPeriod { choice: PeriodChoice; from: string; toExclusive: string; lastDay: string; days: number }
export type PeriodProblem = 'INCOMPLETE' | 'ORDER' | 'TOO_LARGE' | 'OUT_OF_RANGE';
export type PeriodResult = { period: ResolvedPeriod; problem?: undefined } | { period: null; problem: PeriodProblem };

const firstOfMonth = (civil: string) => `${civil.slice(0, 8)}01`;
/** Premier jour du mois situé `months` mois après celui de la date. */
function monthStart(civil: string, months: number): string {
  const [year, month] = civil.split('-').map(Number) as [number, number];
  return new Date(Date.UTC(year, month - 1 + months, 1)).toISOString().slice(0, 10);
}
export const daysBetween = (from: string, toExclusive: string) => Math.round((Date.parse(`${toExclusive}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000);
/** Le serveur n'accepte que les années 2000 à 2100. */
const inRange = (civil: string) => civil >= '2000-01-01' && civil <= '2100-12-31';

/**
 * Période demandée par l'adresse. Sans choix, le mois en cours (du 1er au dernier jour). La période libre porte
 * sa dernière journée comprise dans l'adresse ; la fin exclue envoyée au serveur en est déduite ici, une seule fois.
 */
export function resolvePeriod(query: Pick<NavigationQuery, 'period' | 'start' | 'end'>, today: string): PeriodResult {
  const choice = query.period ?? 'month';
  let from: string, toExclusive: string;
  if (choice === 'custom') {
    if (!query.start || !query.end) return { period: null, problem: 'INCOMPLETE' };
    if (query.end < query.start) return { period: null, problem: 'ORDER' };
    if (!inRange(query.start) || !inRange(query.end)) return { period: null, problem: 'OUT_OF_RANGE' };
    from = query.start; toExclusive = addDays(query.end, 1);
  } else if (choice === 'previous-month') { from = monthStart(today, -1); toExclusive = firstOfMonth(today); }
  else if (choice === 'year') { from = `${today.slice(0, 4)}-01-01`; toExclusive = `${Number(today.slice(0, 4)) + 1}-01-01`; }
  else { from = firstOfMonth(today); toExclusive = monthStart(today, 1); }
  const days = daysBetween(from, toExclusive);
  if (days > maxPeriodDays) return { period: null, problem: 'TOO_LARGE' };
  return { period: { choice, from, toExclusive, lastDay: addDays(toExclusive, -1), days } };
}

/**
 * Comparaison honnête d'une période (#378). Une période écoulée se compare directement à la précédente (mois complet contre mois complet,
 * sinon même nombre de jours juste avant). Le mois en cours se compare à date, par une seconde lecture du 1er à aujourd'hui.
 * Une période encore en cours (année, période libre jusque dans le futur) n'a pas de base équitable : aucune comparaison.
 */
export type ComparisonPlan = { kind: 'direct'; compare: 'previous-month' | 'equivalent-period' } | { kind: 'to-date' } | { kind: 'none' };
export function comparisonPlan(period: ResolvedPeriod, today: string): ComparisonPlan {
  if (period.toExclusive <= addDays(today, 1)) {
    const wholeMonth = period.from === firstOfMonth(period.from) && period.toExclusive === monthStart(period.from, 1);
    return { kind: 'direct', compare: wholeMonth ? 'previous-month' : 'equivalent-period' };
  }
  return period.choice === 'month' ? { kind: 'to-date' } : { kind: 'none' };
}

/** Le mois en cours est toujours une période valide : l'accueil n'a pas de filtre de période. */
export function currentMonth(today: string): ResolvedPeriod {
  const { period } = resolvePeriod({}, today);
  if (!period) throw new Error('Le mois en cours est toujours une période valide.');
  return period;
}

const dayFormat = new Intl.DateTimeFormat('fr-CH', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
const monthFormat = new Intl.DateTimeFormat('fr-CH', { month: 'long', year: 'numeric', timeZone: 'UTC' });
const atNoon = (civil: string) => new Date(`${civil}T12:00:00Z`);
export const formatCivil = (civil: string) => dayFormat.format(atNoon(civil));

/** Libellé de la période affichée : « octobre 2026 », « 2026 » ou « du 5 octobre 2026 au 12 octobre 2026 ». */
export function periodLabel(period: ResolvedPeriod): string {
  if (period.choice === 'month' || period.choice === 'previous-month') return monthFormat.format(atNoon(period.from));
  if (period.choice === 'year') return period.from.slice(0, 4);
  return `du ${formatCivil(period.from)} au ${formatCivil(period.lastDay)}`;
}

const shortDay = new Intl.DateTimeFormat('fr-CH', { day: 'numeric', month: 'long', timeZone: 'UTC' });
const shortDayYear = new Intl.DateTimeFormat('fr-CH', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
/** « du 1 au 12 octobre » ; l'année n'est ajoutée que si la période n'est pas dans l'année de référence. */
export function formatSpan(from: string, lastDay: string, referenceYear: string): string {
  const format = (civil: string, withYear: boolean) => (withYear ? shortDayYear : shortDay).format(atNoon(civil));
  const withYear = from.slice(0, 4) !== referenceYear || lastDay.slice(0, 4) !== referenceYear;
  if (from === lastDay) return `le ${format(lastDay, withYear)}`;
  const sameMonth = from.slice(0, 7) === lastDay.slice(0, 7);
  const start = sameMonth ? String(Number(from.slice(8))) : format(from, from.slice(0, 4) !== lastDay.slice(0, 4));
  return `du ${start} au ${format(lastDay, withYear)}`;
}

export function periodProblemMessage(problem: PeriodProblem): string {
  switch (problem) {
    case 'INCOMPLETE': return 'Choisissez le premier et le dernier jour de la période.';
    case 'ORDER': return 'Le dernier jour doit suivre le premier.';
    case 'TOO_LARGE': return `La période ne peut pas dépasser ${maxPeriodDays} jours.`;
    case 'OUT_OF_RANGE': return 'Choisissez des dates entre 2000 et 2100.';
  }
}
