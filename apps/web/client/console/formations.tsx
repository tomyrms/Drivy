import { useConsole } from './context';
import { FormationList, FormationSheetView } from './formation-sheet';
import { SchoolSetupGuide } from './school-setup';
import { LegacyReferenceRoute } from './formation-references';
import './formations-studio.css';

/**
 * « Formations et tarifs » : la liste des permis, la fiche d'un permis (Général, Compétences, Déroulement et annulation,
 * Tarifs, Historique) et l'assistant de création. Les rubriques ont une adresse propre ; la fiche reste montée entre elles.
 */
export function FormationsSection() {
  const { routeQuery = {} } = useConsole();
  if (routeQuery.view === 'nouvelle') return <SchoolSetupGuide catalogueOnly initialCategory={routeQuery.category} />;
  if (routeQuery.category) return <FormationSheetView key={routeQuery.category} category={routeQuery.category} />;
  // Adresse portant seulement une référence (prochaines actions, ancien lien) : la version désignée est retrouvée.
  if (routeQuery.selection) return <LegacyReferenceRoute section="formations" />;
  return <FormationList />;
}
