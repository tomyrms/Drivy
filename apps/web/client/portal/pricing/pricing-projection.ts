import { parseCents } from '../../command-core.js';
import type { TariffDraft } from '../../console/formation-model.js';
import type { Tariff } from '../../formation-api.js';

/**
 * Projection locale des intentions de catalogue encore suivies par le magasin de commandes (#124). Pure : aucun DOM, aucun réseau.
 *
 * Une projection est une présentation, jamais un prix, un droit ni un engagement. La version publiée par l'école reste la seule
 * qu'une réservation puisse utiliser : une création est une ligne provisoire sans aucun identifiant de l'école (donc inutilisable
 * ailleurs), une révision montre les valeurs voulues marquées « À confirmer » sans remplacer la version publiée, une bascule
 * proposé/non proposé n'est qu'une marque. L'école reste seule juge des versions, des conditions et des prix.
 */
export type TariffIntentionKind = 'create' | 'update' | 'toggle';

interface Base {
  readonly tag: string;
  readonly operationId: string;
  readonly draft: TariffDraft;
  /** L'école a confirmé cette demande (réponse ou reçu) : la ligne garde les valeurs voulues, sans marque, jusqu'à la relecture. */
  readonly settledAt?: number;
}

export type TariffIntention = Base & {
  readonly kind: TariffIntentionKind;
  /** Produit concerné ; `null` pour une création, qui n'a pas encore d'identifiant de l'école. */
  readonly productKey: string | null;
};

export type TariffMark = 'saving' | 'creating' | 'changing' | 'toggling';

/** Ce que porte la ligne du tarif concerné : « Enregistrement en cours » tant que le magasin n'a pas répondu, puis « À confirmer ». */
export const tariffMarkLabels: Readonly<Record<TariffMark, string>> = {
  saving: 'Enregistrement en cours', creating: 'À confirmer', changing: 'Modification à confirmer', toggling: 'Bascule à confirmer',
};

/** Une ligne provisoire n'existe que par l'intention : aucun identifiant de l'école, donc aucun usage ailleurs. */
export const PROVISIONAL = 'pending:';
export const isProvisional = (key: string) => key.startsWith(PROVISIONAL);

export const tariffTag = (productKey: string | null) => `tariff:${productKey ?? 'new'}`;
export const termsTag = (termsVersionId: string) => `terms:${termsVersionId}`;

/**
 * Portée d'agrégat envoyée avec la commande. Un tarif dont les conditions sont partagées ne peut pas porter deux clés à la fois
 * (son produit et le jeu de conditions) : il part sans portée, donc dans la famille `catalogue`, et attend la révision des
 * conditions comme toute autre écriture du catalogue. Une création n'a pas encore d'identifiant de l'école : même repli.
 */
export const tariffScope = (productKey: string | null, sharedTerms: boolean): string | null => productKey && !sharedTerms ? productKey : null;
export const termsScope = (termsVersionId: string): string => termsVersionId;

export interface ProjectedIntention { readonly intention: TariffIntention; readonly mark: TariffMark | null }

/**
 * Intentions encore affichées : celles que le magasin envoie ou suit, et les confirmées jusqu'à une lecture plus récente que leur
 * confirmation. Une demande refusée ou abandonnée n'est plus suivie : elle disparaît, seules les données de l'école restent.
 */
export function resolveIntentions(intentions: readonly TariffIntention[], sending: ReadonlySet<string>, followed: ReadonlySet<string>,
  readAt?: number): ProjectedIntention[] {
  const shown: ProjectedIntention[] = [];
  for (const intention of intentions) {
    if (intention.settledAt !== undefined) {
      if ((readAt ?? 0) < intention.settledAt) shown.push({ intention, mark: null });
      continue;
    }
    if (!sending.has(intention.operationId) && !followed.has(intention.operationId)) continue;
    const mark: TariffMark = sending.has(intention.operationId) ? 'saving'
      : intention.kind === 'create' ? 'creating' : intention.kind === 'toggle' ? 'toggling' : 'changing';
    shown.push({ intention, mark });
  }
  return shown;
}

export interface ProjectedTariff {
  /** Identifiant d'école du tarif publié, ou `pending:<opération>` pour une création non confirmée. */
  readonly key: string;
  /** Version publiée par l'école ; `null` pour une ligne provisoire. */
  readonly tariff: Tariff | null;
  /** Valeurs demandées : montrées à côté de la version publiée, jamais à sa place. */
  readonly wanted: TariffDraft | null;
  readonly mark: TariffMark | null;
}

/** Liste des tarifs telle que la personne la voit : publiés d'abord, puis les créations provisoires, sans rien inventer d'autre. */
export function projectTariffs(tariffs: readonly Tariff[], projected: readonly ProjectedIntention[]): ProjectedTariff[] {
  const rows: ProjectedTariff[] = tariffs.map(tariff => ({ key: tariff.productKey, tariff, wanted: null, mark: null }));
  const provisional: ProjectedTariff[] = [];
  for (const { intention, mark } of projected) {
    if (intention.kind === 'create') {
      provisional.push({ key: `${PROVISIONAL}${intention.operationId}`, tariff: null, wanted: intention.draft, mark });
      continue;
    }
    // Produit absent de la lecture courante : rien n'est projeté sur un tarif qu'on ne voit pas.
    const index = rows.findIndex(row => row.tariff?.productKey === intention.productKey);
    if (index < 0) continue;
    rows[index] = { ...rows[index]!, wanted: intention.draft, mark };
  }
  return [...rows, ...provisional];
}

/** Ce qu'une fiche de tarif publié doit montrer en plus : les valeurs voulues et leur marque, jamais à la place de la version en vigueur. */
export function pendingFor(productKey: string, projected: readonly ProjectedIntention[]): { readonly mark: TariffMark | null; readonly wanted: TariffDraft } | null {
  const found = [...projected].reverse().find(item => item.intention.productKey === productKey);
  return found ? { mark: found.mark, wanted: found.intention.draft } : null;
}

/**
 * Valeurs voulues, jamais présentées comme un engagement : le prix reste un entier de centimes ou `null` — un champ vide
 * n'est jamais 0 — et la proposition est dite telle quelle. Le libellé monétaire est rendu par la vue, comme partout ailleurs.
 */
export function wantedValues(draft: TariffDraft): { readonly priceCents: number | null; readonly unitLabel: string; readonly enabled: boolean } {
  return { priceCents: parseCents(draft.price), unitLabel: draft.unitLabel.trim() || 'unité', enabled: draft.enabled };
}

export interface TermsIntention {
  readonly tag: string;
  readonly operationId: string;
  readonly termsVersionId: string;
  readonly text: string;
  readonly settledAt?: number;
}

export type TermsMark = 'saving' | 'revising';

/** « Révision en cours » tant que le magasin n'a pas répondu, puis « À confirmer » : le texte publié reste celui de l'école. */
export const termsMarkLabels: Readonly<Record<TermsMark, string>> = { saving: 'Révision en cours', revising: 'À confirmer' };

/** Texte demandé pour ce jeu de conditions, avec sa marque ; `null` quand rien n'attend sur ce jeu. */
export function projectTermsRevision(termsVersionId: string, intentions: readonly TermsIntention[], sending: ReadonlySet<string>,
  followed: ReadonlySet<string>, readAt?: number): { readonly mark: TermsMark | null; readonly text: string } | null {
  const found = [...intentions].reverse().find(intention => intention.termsVersionId === termsVersionId);
  if (!found) return null;
  if (found.settledAt !== undefined) return (readAt ?? 0) < found.settledAt ? { mark: null, text: found.text } : null;
  if (sending.has(found.operationId)) return { mark: 'saving', text: found.text };
  if (followed.has(found.operationId)) return { mark: 'revising', text: found.text };
  return null;
}
