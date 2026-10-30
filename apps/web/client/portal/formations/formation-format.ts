import { formatCents } from '../../command-core';

/** Formatage pur de la famille Formations et tarifs : aucun import de l'ancien rendu. */
const civilFormatter = new Intl.DateTimeFormat('fr-CH', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
const shortFormatter = new Intl.DateTimeFormat('fr-CH', { day: '2-digit', month: '2-digit', year: 'numeric', timeZone: 'UTC' });

/** Date civile de l'école ('2026-10-28'), sans conversion de fuseau. */
export function civilDate(value: string): string {
  const date = new Date(`${value}T12:00:00Z`);
  return Number.isFinite(date.getTime()) ? civilFormatter.format(date) : 'Date indisponible';
}
export function shortDate(value: string): string {
  const date = new Date(`${value}T12:00:00Z`);
  return Number.isFinite(date.getTime()) ? shortFormatter.format(date) : 'Date indisponible';
}
export function dateTime(value: string, timeZone: string): string {
  try { return new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeStyle: 'short', timeZone }).format(new Date(value)); }
  catch { return 'Date indisponible'; }
}
/** « 45 min », « 1 h 30 » : la durée d'une leçon ou d'une prestation. */
export function duration(minutes: number | null): string {
  if (minutes === null) return 'Non renseignée';
  const hours = Math.floor(minutes / 60), rest = minutes % 60;
  return hours ? `${hours} h${rest ? ` ${String(rest).padStart(2, '0')}` : ''}` : `${minutes} min`;
}
/**
 * Un prix absent n'est jamais un prix nul : « Prix non défini » pour `null`, « Offert » seulement pour un 0 enregistré.
 */
export function priceLabel(cents: number | null): string {
  if (cents === null) return 'Prix non défini';
  return cents === 0 ? 'Offert' : formatCents(cents);
}
export const plural = (count: number, one: string, many = `${one}s`) => `${count} ${count > 1 ? many : one}`;
/** Validité d'un tarif ou de conditions : « Dès le … » ou « Du … au … ». */
export function validity(from: string, until: string | null): string {
  return until ? `Du ${shortDate(from)} au ${shortDate(until)}` : `Dès le ${shortDate(from)}`;
}
