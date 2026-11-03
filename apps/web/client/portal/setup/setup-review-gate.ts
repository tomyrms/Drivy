import type { SetupStep } from '../../setup-model';
import type { SetupSavePhase } from './setup-save-queue';

/**
 * Revue et activation de la préparation (#123). Le résumé se lit sur un geste explicite — naviguer vers « Résumé »,
 * ou enregistrer une étape qui y conduit — jamais parce qu'un chargement de page retombe sur le résumé : sinon le
 * bouton « Vérifier la préparation » disparaît avant que la personne ou la recette ne l'utilise.
 *
 * L'activation reste interdite tant que le brouillon détenu par l'école n'est pas le brouillon local (`synced`)
 * et qu'aucun envoi n'est en vol.
 */
export interface ReviewGateInput {
  readonly step: SetupStep;
  /** Un geste de cette visite de page a conduit au résumé (navigation, ou enregistrement vers le résumé). */
  readonly requested: boolean;
  /** Le brouillon de l'école est le brouillon local et rien n'est en vol. */
  readonly synced: boolean;
  /** Lecture en cours, demande suivie, adoption d'un brouillon relu : la section attend. */
  readonly blocked: boolean;
  readonly reviewing: boolean;
  readonly preview: { readonly ready: boolean } | null;
  readonly acknowledged: boolean;
  readonly readFailure: boolean;
  readonly phase: SetupSavePhase;
}

export interface ReviewGate {
  /** Lire le résumé maintenant. */
  readonly read: boolean;
  /** « Vérifier la préparation » utilisable. */
  readonly verify: boolean;
  /** Adoption ou activation utilisable. */
  readonly activate: boolean;
  /** Raison courte d'un contrôle désactivé, jamais portée par la seule couleur. */
  readonly reason: string | null;
}

/** Raison courte : l'enregistrement d'abord, la saisie ensuite. */
function reasonFor(phase: SetupSavePhase, synced: boolean): string | null {
  if (synced) return null;
  if (phase === 'saving') return 'Enregistrement en cours.';
  if (phase === 'conflict') return 'La préparation a changé à l’école : relisez l’étape.';
  if (phase === 'unknown') return 'Enregistrement à vérifier.';
  return 'Modifications non enregistrées.';
}

export function reviewGate(input: ReviewGateInput): ReviewGate {
  const onReview = input.step === 'REVIEW';
  const blocked = input.blocked || input.reviewing;
  const idle = onReview && !blocked && !input.preview;
  // Une lecture ne part que sur un geste de cette visite : un chargement qui retombe sur le résumé laisse la relecture explicite.
  const read = idle && input.requested && input.synced && !input.readFailure;
  return {
    read,
    verify: idle && input.synced && !read,
    activate: onReview && !blocked && !!input.preview?.ready && input.acknowledged && input.synced,
    reason: reasonFor(input.phase, input.synced),
  };
}
