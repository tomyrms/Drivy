/** Pilotage (#373) : affichage des mesures du serveur. Les valeurs sont des entiers ; rien n'est recalculé ici. */
export type MeasureUnit = 'count' | 'seconds' | 'cents' | 'permille';
export interface MeasureComparison { current: number | null; base: number | null; delta: number | null; percentTenths: number | null; percentReason: string | null }

const numbers = new Intl.NumberFormat('fr-CH');
const money = new Intl.NumberFormat('fr-CH', { style: 'currency', currency: 'CHF' });
const percent = new Intl.NumberFormat('fr-CH', { style: 'percent', maximumFractionDigits: 1 });
const signedPercent = new Intl.NumberFormat('fr-CH', { style: 'percent', maximumFractionDigits: 1, signDisplay: 'exceptZero' });
const signedNumbers = new Intl.NumberFormat('fr-CH', { signDisplay: 'exceptZero' });
const signedMoney = new Intl.NumberFormat('fr-CH', { style: 'currency', currency: 'CHF', signDisplay: 'exceptZero' });

/** « 3 h 38 min », « 42 min » ; les secondes restantes ne sont pas arrondies à la minute supérieure. */
export function formatDuration(seconds: number): string {
  const minutes = Math.floor(Math.abs(seconds) / 60), hours = Math.floor(minutes / 60), rest = minutes % 60;
  const text = hours > 0 ? `${hours} h ${String(rest).padStart(2, '0')} min` : `${rest} min`;
  return seconds < 0 ? `−${text}` : text;
}

/** Une valeur absente est un tiret, jamais un zéro : l'état de couverture dit pourquoi. */
export function formatMeasure(value: number | null, unit: MeasureUnit): string {
  if (value === null) return '—';
  switch (unit) {
    case 'count': return numbers.format(value);
    case 'seconds': return formatDuration(value);
    case 'cents': return money.format(value / 100);
    case 'permille': return percent.format(value / 1000);
  }
}

/** Écart absolu avec son signe, dans l'unité de la mesure. */
export function formatDelta(delta: number, unit: MeasureUnit): string {
  switch (unit) {
    case 'count': return signedNumbers.format(delta);
    case 'seconds': return delta === 0 ? '0 min' : `${delta > 0 ? '+' : ''}${formatDuration(delta)}`;
    case 'cents': return signedMoney.format(delta / 100);
    case 'permille': return `${delta > 0 ? '+' : delta < 0 ? '−' : ''}${percent.format(Math.abs(delta) / 1000)}`;
  }
}

/** Écart relatif en dixièmes de pour cent (667 donne « +66,7 % »). */
export const formatPercentTenths = (tenths: number) => signedPercent.format(tenths / 1000);

/** Texte court d'une comparaison, ou null quand le serveur n'en donne pas une lisible. */
export function describeComparison(comparison: MeasureComparison | undefined, unit: MeasureUnit): string | null {
  if (!comparison || comparison.delta === null) return null;
  if (comparison.percentTenths !== null) return formatPercentTenths(comparison.percentTenths);
  return formatDelta(comparison.delta, unit);
}

const reasonTexts: Record<string, (count?: number) => string> = {
  DURATION_UNKNOWN: count => count === 1 ? '1 leçon sans durée réelle connue' : `${count ?? 'Des'} leçons sans durée réelle connue`,
  ACTUAL_START_MISSING: () => 'Début réel manquant pour certaines leçons',
  ENTITLEMENT_NOT_VALUED: () => 'Leçons réglées par forfait, non valorisées',
  CHARGE_MISMATCH: count => count === 1 ? '1 leçon dont le compte ne correspond pas au prix' : `${count ?? 'Des'} leçons dont le compte ne correspond pas au prix`,
  COURSE_PRICE_SOURCE_MISSING: () => 'Aucun prix de cours collectif n’est enregistré',
  BEFORE_DATA_START: () => 'Période antérieure aux premières données de l’école',
  STARTS_BEFORE_DATA_START: () => 'Début de période antérieur aux premières données',
  SNAPSHOT_ONLY: () => 'Connu seulement pour le moment présent, pas pour une période passée',
  TIME_ZONE_MIXED: () => 'Plusieurs fuseaux horaires dans la période',
  BASE_ZERO: () => 'Base de comparaison nulle',
  BASE_BEFORE_DATA_START: () => 'Base antérieure aux premières données',
  PARTIAL_COVERAGE: () => 'Couverture partielle sur l’une des périodes',
};
export function describeReason(code: string, count?: number): string {
  return reasonTexts[code]?.(count) ?? 'Une partie des données n’est pas couverte';
}
