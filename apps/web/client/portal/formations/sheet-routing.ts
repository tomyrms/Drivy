import type { CatalogueReference } from '../../formation-api';
import type { FormationView, NavigationQuery } from '../../console/route';
import type { SectionKey } from '../../console/sections';

/** Rubriques d'une fiche de permis ; l'adresse (`view`) reste celle de l'ancienne console. */
export type SheetView = Exclude<FormationView, 'nouvelle'>;
export const sheetView = (value: string | undefined): SheetView =>
  value === 'competences' || value === 'deroulement' || value === 'tarifs' || value === 'historique' ? value : 'general';
export const rubrics: readonly { view: Exclude<SheetView, 'historique'>; label: string }[] = [
  { view: 'general', label: 'Général' }, { view: 'competences', label: 'Compétences' }, { view: 'deroulement', label: 'Règles' }, { view: 'tarifs', label: 'Tarifs' },
];
export const editorTitles = { general: 'Modifier le parcours', competences: 'Modifier les compétences', deroulement: 'Modifier les règles' } as const;

/**
 * Destination d'une référence : la version exacte demandée n'est jamais remplacée par la dernière.
 * Une version actuelle et sans ambiguïté ouvre sa rubrique ; une ancienne version, un contenu partagé
 * ou un élément non rattaché s'ouvre dans l'historique du permis.
 */
export function referenceDestination(reference: CatalogueReference): { section: SectionKey; query: NavigationQuery } {
  const history = (category: string) => ({ section: 'formations' as const, query: { category, view: 'historique' as const, selection: reference.id } });
  switch (reference.kind) {
    case 'OFFERING': return reference.current ? { section: 'formations', query: { category: reference.categoryCode, view: 'general', programme: reference.offeringKey } } : history(reference.categoryCode);
    case 'CURRICULUM': case 'PROCEDURE': {
      const view: FormationView = reference.kind === 'CURRICULUM' ? 'competences' : 'deroulement';
      const only = reference.programmes.length === 1 ? reference.programmes[0]! : null;
      return only?.current ? { section: 'formations', query: { category: reference.categoryCode, view, programme: only.offeringKey } } : history(reference.categoryCode);
    }
    case 'TARIFF':
      if (reference.categoryCode === null) return { section: 'prestations', query: { selection: reference.id } };
      return reference.current ? { section: 'formations', query: { category: reference.categoryCode, view: 'tarifs', selection: reference.id } } : history(reference.categoryCode);
    case 'TERMS': return { section: 'conditions', query: { selection: reference.id } };
  }
}
