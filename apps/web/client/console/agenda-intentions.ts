import type { CommandKind, SchoolCommand } from '../command-core.js';
import type { LessonForm } from '../lesson-planning-model.js';

/**
 * Ce qu'une planification du bureau demande encore à l'école (#109) : créer une leçon, la déplacer, l'annuler.
 * Une intention est une présentation, jamais un fait : elle porte la saisie (en mémoire seulement) et l'opération suivie
 * par le magasin de commandes, jamais un identifiant, une version ou un prix venus de l'école.
 *
 * Pur : ni DOM, ni réseau. Les écrans décident de ce qu'ils montrent, jamais de ce qui est réservé.
 */

/** Le créneau et les personnes voulus, tels que la saisie les a produits. */
export interface PlannedLessonDraft {
  readonly learnerId: string;
  readonly trainingId: string;
  readonly instructorMembershipId: string;
  readonly learnerDisplayName: string;
  readonly instructorDisplayName: string;
  readonly meetingPoint: string;
  readonly timeZone: string;
  readonly plannedStart: string;
  readonly plannedEnd: string;
  /** La saisie du formulaire, rendue telle quelle après un refus. Jamais écrite dans le stockage du navigateur. */
  readonly form: LessonForm;
}

interface IntentionBase {
  readonly tag: string;
  readonly operationId: string;
  /**
   * L'école a confirmé cette intention (réponse vérifiée ou reçu AP72). Elle reste projetée, sans marque, jusqu'à une
   * lecture plus récente que cette confirmation : une ligne confirmée ne disparaît pas puis ne revient pas.
   */
  readonly settledAt?: number;
}

export type LessonIntention =
  | (IntentionBase & { readonly kind: 'lesson-create'; readonly draft: PlannedLessonDraft })
  | (IntentionBase & { readonly kind: 'lesson-move'; readonly lessonId: string; readonly draft: PlannedLessonDraft })
  | (IntentionBase & { readonly kind: 'lesson-cancel'; readonly lessonId: string });

export type LessonIntentionKind = LessonIntention['kind'];

/** Marques d'une intention dans l'agenda et dans l'aperçu : toujours un texte, jamais une couleur seule. */
export type AgendaMark = 'planning' | 'moving' | 'move-proposal' | 'cancelling';
export const agendaMarkLabels: Readonly<Record<AgendaMark, string>> = {
  planning: 'Planification en cours',
  moving: 'Déplacement en cours',
  'move-proposal': 'Nouveau créneau proposé',
  cancelling: 'Annulation en cours',
};

/** Une ligne provisoire porte ce préfixe : aucun identifiant de l'école, aucune version, aucune action. */
export const PROVISIONAL_LESSON = 'pending:';
export const isProvisionalLesson = (id: string) => id.startsWith(PROVISIONAL_LESSON);

/** Identité logique d'une intention : deux lignes d'un déplacement comptent pour une seule leçon. */
export const intentionLogicalKey = (intention: LessonIntention): string =>
  intention.kind === 'lesson-create' ? `lesson:${PROVISIONAL_LESSON}${intention.operationId}` : `lesson:${intention.lessonId}`;

/**
 * Intentions qui restent affichées : celles que le magasin suit encore, et celles qu'il a confirmées jusqu'à ce qu'une
 * lecture plus récente que leur confirmation soit à l'écran. Une demande refusée ou abandonnée n'est plus suivie.
 */
export function visibleIntentions(intentions: readonly LessonIntention[], followed: ReadonlySet<string>, readAt: number | undefined): LessonIntention[] {
  return intentions.filter(intention => intention.settledAt !== undefined ? (readAt ?? 0) < intention.settledAt : followed.has(intention.operationId));
}

/** Demandes encore suivies (les confirmées sont faites) : ce qui ordonne la prochaine écriture de la section. */
export const stillFollowed = (intentions: readonly LessonIntention[], followed: ReadonlySet<string>): LessonIntention[] =>
  intentions.filter(intention => intention.settledAt === undefined && followed.has(intention.operationId));

/** Le créneau voulu d'une création ou d'un déplacement, en millisecondes, quand le corps de la demande le porte. */
export function desiredSlotOf(command: SchoolCommand | null): number | null {
  if (!command || (command.kind !== 'createLesson' && command.kind !== 'moveLesson')) return null;
  const start = command.body.plannedStart;
  return typeof start === 'string' && Number.isFinite(Date.parse(start)) ? Date.parse(start) : null;
}

/**
 * Renvoyer la même demande n'a de sens que tant que le créneau voulu est encore devant : une création ou un déplacement
 * dont l'horaire est passé n'est plus proposé au renvoi, il reste à vérifier le résultat ou à abandonner le suivi.
 * Une commande restaurée sans corps ne prouve pas que son créneau est encore devant : pas de renvoi non plus.
 * Tout autre type de commande garde le comportement existant (`true` ici, le magasin décide du reste).
 */
export function lessonResendAllowed(entry: { readonly kind: CommandKind; readonly command: SchoolCommand | null }, now = Date.now()): boolean {
  if (entry.kind !== 'createLesson' && entry.kind !== 'moveLesson') return true;
  const slot = desiredSlotOf(entry.command);
  return slot !== null && slot > now;
}

/** Raison courte affichée à côté d'un renvoi retiré, ou `null` quand le renvoi reste possible. */
export function lessonResendReason(entry: { readonly kind: CommandKind; readonly command: SchoolCommand | null }, now = Date.now()): string | null {
  return lessonResendAllowed(entry, now) ? null : 'L’horaire demandé est passé : vérifiez le résultat ou arrêtez le suivi.';
}
