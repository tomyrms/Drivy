import type { Outcome } from '../../console/context';
import type { LessonIntention, PlannedLessonDraft } from '../../console/agenda-intentions';

/** Une demande conservée puis refusée par l'école : la saisie revient avec la raison, rien d'autre ne bouge. */
export interface LessonRefusal { readonly intention: LessonIntention; readonly outcome: NonNullable<Outcome> }

/** Le formulaire rouvert avec la saisie refusée, sur la leçon concernée (`null` : une création). */
export interface LessonRestored { readonly lessonId: string | null; readonly draft: PlannedLessonDraft; readonly outcome: NonNullable<Outcome> }

/**
 * Un refus qui prouve que l'école a changé d'état (version, leçon fermée ou commencée) demande une relecture ;
 * un créneau occupé ou une saisie invalide ne change rien à ce qui est affiché.
 */
const rereadCodes: readonly string[] = ['VERSION_CONFLICT', 'LESSON_CLOSED', 'LESSON_STARTED'];
export const refusalNeedsReread = (outcome: Outcome): boolean => outcome?.tone === 'error' && rereadCodes.includes(outcome.code ?? '');
