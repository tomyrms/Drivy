import type { WizardDraft } from '../../console/formation-model.js';
import type { LaneOutcome } from '../../command-lane.js';
import type { Programme } from '../../formation-api.js';

/**
 * Projection locale des intentions de programme encore suivies par le magasin de commandes (#124). Pure : aucun DOM, aucun réseau.
 *
 * Une projection est une présentation, jamais une version publiée. L'école reste seule à créer une formation et à enregistrer une
 * version de programme : une création est une ligne provisoire sans aucun identifiant de l'école (donc inutilisable par un dossier,
 * une leçon ou une fiche), une version enregistrée montre la version voulue marquée à côté de la version publiée, sans la remplacer,
 * et l'historique des versions reste celui de l'école, sans rien de provisoire.
 */

/** Rubrique d'un parcours : la marque et le refus ne concernent que la demande de cette rubrique. */
export type ProgrammeSection = 'general' | 'competences' | 'deroulement' | 'reference';

interface IntentionBase {
  readonly tag: string;
  readonly operationId: string;
  /** Parcours concerné ; `null` pour une création, qui n'a pas encore d'identifiant de l'école. */
  readonly offeringKey: string | null;
  /** L'école a confirmé cette demande (réponse ou reçu) : la rubrique garde la version voulue, sans marque, jusqu'à la relecture. */
  readonly settledAt?: number;
}

export type FormationIntention =
  | (IntentionBase & { readonly kind: 'create'; readonly draft: WizardDraft })
  | (IntentionBase & { readonly kind: 'programme'; readonly section: ProgrammeSection; readonly draft: unknown });

export type FormationMark = 'saving' | 'creating' | 'changing';

/** Ce que porte la rubrique concernée : « Enregistrement en cours » tant que le magasin n'a pas répondu, puis « À confirmer ». */
export const formationMarkLabels: Readonly<Record<FormationMark, string>> = {
  saving: 'Enregistrement en cours', creating: 'À confirmer', changing: 'Modification à confirmer',
};

/** Une ligne provisoire n'existe que par l'intention : aucun identifiant de l'école, donc aucun usage ailleurs. */
export const PROVISIONAL = 'pending:';
export const isProvisional = (key: string) => key.startsWith(PROVISIONAL);

export const formationTag = (offeringKey: string | null) => `formation:${offeringKey ?? 'new'}`;

export interface ShownIntention { readonly intention: FormationIntention; readonly mark: FormationMark | null }

type ProgrammeIntention = Extract<FormationIntention, { readonly kind: 'programme' }>;
export type { ProgrammeIntention };
const isProgrammeIntention = (item: ShownIntention): item is ShownIntention & { readonly intention: ProgrammeIntention } =>
  item.intention.kind === 'programme';

/**
 * Intentions encore affichées : celles que le magasin envoie ou suit, et les confirmées jusqu'à une lecture plus récente que leur
 * confirmation. Une demande refusée ou abandonnée n'est plus suivie : elle disparaît, seules les données de l'école restent.
 */
export function resolveFormationIntentions(intentions: readonly FormationIntention[], sending: ReadonlySet<string>,
  followed: ReadonlySet<string>, readAt?: number): ShownIntention[] {
  const shown: ShownIntention[] = [];
  for (const intention of intentions) {
    if (intention.settledAt !== undefined) {
      if ((readAt ?? 0) < intention.settledAt) shown.push({ intention, mark: null });
      continue;
    }
    if (!sending.has(intention.operationId) && !followed.has(intention.operationId)) continue;
    const mark: FormationMark = sending.has(intention.operationId) ? 'saving' : intention.kind === 'create' ? 'creating' : 'changing';
    shown.push({ intention, mark });
  }
  return shown;
}

export type ProjectedCategory =
  | { readonly kind: 'published'; readonly categoryCode: string }
  | { readonly kind: 'provisional'; readonly key: string; readonly categoryCode: string | null; readonly draft: WizardDraft; readonly mark: FormationMark | null };

/**
 * Liste des permis telle que la personne la voit : ceux de l'école d'abord, puis les créations provisoires, sans rien inventer
 * d'autre. Une création porte le code saisi par la personne, mais ce code n'est pas encore celui de l'école.
 */
export function projectCategories(categories: readonly { readonly categoryCode: string }[],
  projected: readonly ShownIntention[]): ProjectedCategory[] {
  const rows: ProjectedCategory[] = categories.map(item => ({ kind: 'published', categoryCode: item.categoryCode }));
  const provisional: ProjectedCategory[] = [];
  for (const { intention, mark } of projected) {
    if (intention.kind !== 'create') continue;
    provisional.push({ kind: 'provisional', key: `${PROVISIONAL}${intention.operationId}`,
      categoryCode: intention.draft.category.trim() || null, draft: intention.draft, mark });
  }
  return [...rows, ...provisional];
}

/** Identifiant d'école d'une ligne de catalogue, `null` tant que l'école n'a rien créé : ni dossier, ni leçon ne peut la désigner. */
export const schoolIdentifier = (row: ProjectedCategory): string | null => row.kind === 'published' ? row.categoryCode : null;
/** Une ligne provisoire ne s'ouvre pas : il n'y a pas encore de fiche de l'école derrière elle. */
export const isOpenable = (row: ProjectedCategory) => row.kind === 'published';

export interface ProjectedProgramme<D = unknown> {
  /** Le parcours publié par l'école, jamais réécrit par une intention. */
  readonly programme: Programme;
  /** Version voulue pour cette rubrique : montrée à côté de la version publiée, jamais à sa place. */
  readonly wanted: { readonly section: ProgrammeSection; readonly draft: D } | null;
  readonly mark: FormationMark | null;
  /** Historique des versions : uniquement celui de l'école, rien de provisoire n'y entre. */
  readonly history: Programme['history'];
}

/** Projection d'une rubrique d'un parcours : la version enregistrée reste celle de l'école, la demande est marquée à côté. */
export function projectProgramme<D = unknown>(programme: Programme, section: ProgrammeSection,
  projected: readonly ShownIntention[]): ProjectedProgramme<D> {
  const found = [...projected].filter(isProgrammeIntention).reverse()
    .find(item => item.intention.offeringKey === programme.offeringKey && item.intention.section === section);
  return {
    programme,
    wanted: found ? { section, draft: found.intention.draft as D } : null,
    mark: found?.mark ?? null,
    history: programme.history,
  };
}

/**
 * Refus d'une demande de programme : seule la rubrique concernée le reçoit, avec la saisie exacte qui l'accompagnait et la raison
 * donnée. Rien d'autre n'est touché : la fiche de l'école, les autres rubriques et les autres formations restent en place.
 */
export interface ProgrammeRefusal<D = unknown> {
  readonly intention: ProgrammeIntention;
  readonly section: ProgrammeSection;
  readonly draft: D;
  readonly outcome: LaneOutcome;
}

export function programmeRefusal<D>(intention: ProgrammeIntention, draft: D, outcome: LaneOutcome): ProgrammeRefusal<D> {
  return { intention, section: intention.section, draft, outcome };
}
