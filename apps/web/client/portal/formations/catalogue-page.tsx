import { useEffect } from 'react';
import { BookOpen } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { useConsole } from '../../console/context';
import type { SectionKey } from '../../console/sections';
import { ReadFeedback } from './catalogue-ui';
import { useLegacyReference } from './formation-controllers';
import { PermitList } from './permit-list';
import { PermitSheet } from './permit-sheet';

/**
 * Entrée de « Formations » : catalogue des permis, fiche d'un permis (rubriques et historique) ou, pour une adresse qui ne porte
 * qu'une référence, la version désignée. Préparer un permis ouvre le guide unique, jamais un second assistant.
 */
export function FormationsPage() {
  const { routeQuery = {} } = useConsole();
  if (routeQuery.view === 'nouvelle') return <PrepareRedirect />;
  if (routeQuery.category) return <PermitSheet key={routeQuery.category} category={routeQuery.category} />;
  if (routeQuery.selection) return <ReferenceRoute section="formations" />;
  return <PermitList />;
}

function PrepareRedirect() {
  const { routeQuery = {}, navigate } = useConsole();
  useEffect(() => { navigate('apercu', { from: 'formations', ...(routeQuery.category ? { category: routeQuery.category } : {}) }, { replace: true }); }, []);
  return <ReadFeedback loaded={{ status: 'loading', error: null, reload: () => {} }} label="Ouverture du guide" />;
}

/** Anciennes adresses : la version exacte désignée est retrouvée, puis la destination remplace l'entrée d'historique. */
function ReferenceRoute({ section }: { section: SectionKey }) {
  const { navigate } = useConsole();
  const loaded = useLegacyReference(section);
  return <section className="cat-page">
    {loaded.status === 'error'
      ? <Empty className="cat-empty"><EmptyHeader><EmptyMedia variant="icon"><BookOpen /></EmptyMedia><EmptyTitle>Référence introuvable</EmptyTitle>
        <EmptyDescription>{loaded.error ?? 'Cet élément n’existe pas ou n’est pas accessible avec vos accès.'}</EmptyDescription></EmptyHeader>
        <EmptyContent><Button variant="outline" onClick={() => navigate('formations', {})}>Voir les formations</Button></EmptyContent></Empty>
      : <ReadFeedback loaded={loaded} label="Recherche de l’élément demandé" />}
  </section>;
}

export const OffresPage = () => <ReferenceRoute section="offres" />;
export const ReferentielsPage = () => <ReferenceRoute section="referentiels" />;
export const ProceduresPage = () => <ReferenceRoute section="procedures" />;
