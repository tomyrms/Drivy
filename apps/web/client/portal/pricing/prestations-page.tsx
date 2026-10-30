import { useEffect, useRef } from 'react';
import { ArrowRight } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { useConsole } from '../../console/context';
import { ReadFeedback } from '../formations/catalogue-ui';
import { useCatalogueCommand } from '../formations/catalogue-command';
import type { TariffType } from '../../formation-api';
import { TariffReference } from './tariff-reference';
import { TariffsPanel } from './tariffs-panel';
import { consultedTariff, useReference, useUncategorizedTariffs } from './pricing-controllers';
import { Badge } from '../../components/ui/badge';
import '../formations/formations.css';
import './pricing.css';

/** Prestations sans permis : mêmes tarifs, même fiche, sans catégorie. Les anciennes versions se consultent à la demande. */
export function PrestationsPage() {
  const { school, routeQuery = {}, navigate, setRouteQuery } = useConsole();
  const { loaded, proposals } = useUncategorizedTariffs();
  const command = useCatalogueCommand();
  const selection = routeQuery.selection;
  const title = useRef<HTMLHeadingElement>(null);
  const consultTitle = useRef<HTMLHeadingElement>(null);
  // Une référence d'un tarif rattaché à un permis ouvre la fiche de ce permis.
  useEffect(() => { if (routeQuery.category) navigate('formations', { category: routeQuery.category, view: 'tarifs', ...(selection ? { selection } : {}) }, { replace: true }); }, [routeQuery.category]);
  const data = loaded.data;
  // Une version ancienne (ou absente de la liste) est relue telle quelle, en lecture seule.
  const { consulting: consult } = consultedTariff(data?.tariffs, selection);
  const reference = useReference(consult ? selection : undefined);
  useEffect(() => {
    const value = reference.data;
    if (value && value.kind === 'TARIFF' && value.categoryCode) navigate('formations', { category: value.categoryCode, view: value.current ? 'tarifs' : 'historique', selection: value.id }, { replace: true });
    else if (value && value.kind !== 'TARIFF') navigate('formations', { selection: value.id }, { replace: true });
  }, [reference.data]);
  const types: TariffType[] = ['EXTERNAL_SERVICE', 'EXAM_SUPPORT', ...(school.modules.collectiveCoursesEnabled ? ['COLLECTIVE_COURSE' as const] : [])];
  const select = (id: string | null) => setRouteQuery?.(id ? { selection: id } : {}, false, true);
  return <section className="cat-page">
    <h1 className="visually-hidden" ref={title} tabIndex={-1}>Prestations sans permis</h1>
    <ReadFeedback loaded={loaded} label="Lecture des prestations" />
    {data && <>
      {consult && <div className="cat-surface cat-consulted">
        <ReadFeedback loaded={reference} label="Lecture de la version" />
        {reference.data?.kind === 'TARIFF' && reference.data.categoryCode === null && <TariffReference reference={reference.data} onClose={() => select(null)} headingRef={consultTitle}
          badge={<Badge variant="secondary" className="cat-badge" data-tone="neutral">{reference.data.current ? 'Version actuelle' : 'Version précédente'}</Badge>} />}
      </div>}
      <TariffsPanel tariffs={data.tariffs} categoryCode={null} today={data.today} canConfigure={data.canConfigureCatalog} types={types} proposals={proposals.data} command={command}
        reload={loaded.reload} programmeCount={0} selection={consult ? undefined : selection} listLabel="Prestations sans permis"
        actions={<Button variant="ghost" onClick={() => navigate('conditions', {})}>Conditions commerciales<ArrowRight data-icon="inline-end" /></Button>} onSelect={select} onConsultVersion={id => select(id)} onOpenTerms={id => navigate('conditions', { selection: id })} />
    </>}
  </section>;
}
