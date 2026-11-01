import { formatMeasure, type MeasureUnit } from './measure-format';
import type { MetricDomain } from './metrics-api';

/** Règles pures du détail d'une mesure et de son export (#380). */
export const measureDomain = (measure: string): MetricDomain => measure.startsWith('F') ? 'finance' : 'activity';

export type LineKind = 'LESSON' | 'COURSE_OCCURRENCE' | 'COURSE_PAYMENT';
export interface DetailLine {
  kind: LineKind;
  id: string;
  eventAt: string;
  status: string;
  instructorLabel?: string | null | undefined;
  learnerLabel?: string | null | undefined;
  durationSeconds?: number | null | undefined;
  amountCents?: number | null | undefined;
  courseTypeLabel?: string | null | undefined;
  markedCount?: number | null | undefined;
  missingMarks?: number | null | undefined;
  seriesId?: string | null | undefined;
  voidedAt?: string | null | undefined;
}

const lessonStatus: Record<string, string> = { COMPLETED: 'Réalisée', PLANNED: 'Planifiée', CANCELLED: 'Annulée', NO_SHOW: 'Absence' };
/** Statut lisible d'une ligne ; un statut que le web ne connaît pas est montré tel que le serveur le donne. */
export function lineStatus(line: DetailLine): string {
  if (line.kind === 'COURSE_PAYMENT') return line.voidedAt ? 'Saisie annulée' : 'Enregistré';
  if (line.kind === 'COURSE_OCCURRENCE') {
    const missing = line.missingMarks ?? 0;
    return missing > 0 ? `Appel : ${missing} à renseigner` : 'Appel renseigné';
  }
  return lessonStatus[line.status] ?? line.status;
}

/** Titre de la ligne : l'élève (si la lecture lui est permise), sinon le fait lui-même. */
export function lineTitle(line: DetailLine): string {
  if (line.kind === 'COURSE_OCCURRENCE') return line.courseTypeLabel?.trim() || 'Séance de cours';
  const learner = line.learnerLabel?.trim();
  if (line.kind === 'COURSE_PAYMENT') return learner ? `Règlement · ${learner}` : 'Règlement de cours';
  return learner || 'Leçon';
}

/** Somme des montants des lignes affichées, ou null si aucune ne porte de montant (droit absent ou mesure sans montant). */
export function shownAmount(lines: readonly DetailLine[]): number | null {
  const amounts = lines.flatMap(line => line.amountCents === null || line.amountCents === undefined ? [] : [line.amountCents]);
  return amounts.length === 0 ? null : amounts.reduce((sum, value) => sum + value, 0);
}

/** « 12 lignes · CHF 570.00 », la valeur de la mesure restant dans son unité. */
export function totalText(total: { lineCount: number; amountCents?: number | null | undefined; durationSeconds?: number | null | undefined }): string {
  const parts = [`${total.lineCount} ${total.lineCount === 1 ? 'ligne' : 'lignes'}`];
  if (total.amountCents !== null && total.amountCents !== undefined) parts.push(formatMeasure(total.amountCents, 'cents'));
  if (total.durationSeconds !== null && total.durationSeconds !== undefined) parts.push(formatMeasure(total.durationSeconds, 'seconds'));
  return parts.join(' · ');
}

/** Valeurs lues sur la carte, renvoyées au serveur pour qu'il signale un écart plutôt que de le taire (7.5). */
export function expectedFromCard(measure: { value: number | null; unit: MeasureUnit; lineCount?: number | undefined }): { lineCount?: number; amountCents?: number } {
  return {
    ...(measure.lineCount === undefined ? {} : { lineCount: measure.lineCount }),
    ...(measure.unit === 'cents' && measure.value !== null && measure.value >= 0 ? { amountCents: measure.value } : {}),
  };
}

export const exportFileName = (measure: string, from: string, toExclusive: string) => `drivy-${measure}-${from}_${toExclusive}.csv`;

/** Messages courts des refus de l'export ; aucun n'invente un fichier. */
export function exportErrorMessage(code: string): string {
  switch (code) {
    case 'EXPORT_TOO_LARGE': return 'Cet export dépasse 10 000 lignes. Réduisez la période ou ajoutez un filtre.';
    case 'ACCESS_REVOKED': return 'Vos droits ont changé : l’export n’est plus autorisé.';
    case 'METRIC_SCOPE_FORBIDDEN': return 'Votre accès ne permet pas d’exporter cette portée.';
    case 'METRIC_FILTER_UNSUPPORTED': return 'Ce filtre ne s’applique pas à cette mesure.';
    case 'NETWORK_UNAVAILABLE': return 'Le réseau est indisponible. Le fichier n’a pas été produit.';
    case 'REAUTH_REQUIRED': return 'Reconnectez-vous pour exporter.';
    case 'SESSION_EXPIRED': return 'La session a expiré. Reconnectez-vous pour exporter.';
    default: return 'Le fichier n’a pas pu être produit. Aucun export partiel n’a été téléchargé.';
  }
}
