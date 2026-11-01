import { useState } from 'react';
import { civilDateIn } from '../../agenda-model';
import { useConsole } from '../../console/context';
import type { StatisticsTab } from '../../console/route';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '../../components/ui/tabs';
import { ActivityPanel } from './activity-panel';
import { PilotageFilters, type FilterPatch } from './components';
import { measureDomain } from './detail-model';
import { FinancePanel } from './finance-panel';
import { MeasureDetail } from './measure-detail';
import type { MetricFilters } from './metrics-api';
import { resolvePeriod } from './period-model';
import { canOpenStatistics, metricRights } from './rights';
import { useCatalogueOptions } from './use-catalogue-options';
import { useDirectory } from './use-directory';

/** Statistiques (#373) : deux onglets, Activité et Finances, sous les mêmes filtres portés par l'adresse. */
export function StatisticsPilot() {
  const { school, membership, routeQuery, setRouteQuery } = useConsole();
  const query = routeQuery ?? {};
  const rights = metricRights(membership);
  const [returnTo, setReturnTo] = useState<string | undefined>(undefined);
  // Moniteurs, permis et prestations servent seulement de filtres : leur lecture ne bloque jamais les chiffres.
  const { instructorOptions: instructors } = useDirectory({ learners: false });
  const { categoryOptions, productOptions } = useCatalogueOptions({ category: query.category, product: query.product });
  if (!canOpenStatistics(rights)) return <section className="pilotage-page">
    <h1>Statistiques</h1>
    <Alert variant="destructive"><AlertTitle>Statistiques non disponibles</AlertTitle><AlertDescription>Vos accès ne permettent pas de consulter les indicateurs de l’école.</AlertDescription></Alert>
  </section>;

  // Les lignes d'une mesure ne s'ouvrent que pour un domaine lisible ; le domaine de la mesure prime sur l'onglet de l'adresse.
  const detail = query.measure && (measureDomain(query.measure) === 'finance' ? rights.finance : rights.activity) ? query.measure : undefined;
  const wanted: StatisticsTab = detail ? (measureDomain(detail) === 'finance' ? 'finance' : 'activity') : query.tab ?? 'activity';
  const tab: StatisticsTab = wanted === 'finance' ? (rights.finance ? 'finance' : 'activity') : (rights.activity ? 'activity' : 'finance');
  const today = civilDateIn(school.timeZone);
  const resolved = resolvePeriod(query, today);
  const filters: MetricFilters = { instructor: query.instructor, category: query.category, product: query.product };
  const scopeLabel = [query.instructor ? instructors.find(item => item.value === query.instructor)?.label ?? 'Un moniteur' : null,
    query.category ? categoryOptions.find(item => item.value === query.category)?.label ?? `Permis ${query.category}` : null,
    query.product ? productOptions.find(item => item.value === query.product)?.label ?? query.product : null].filter(Boolean).join(' · ') || 'Toute l’école';
  const change = (patch: FilterPatch) => setRouteQuery?.({ ...query, ...patch }, true);
  const open = (measure: string) => setRouteQuery?.({ ...query, measure, part: undefined, tab: measureDomain(measure) === 'finance' ? 'finance' : undefined });
  const close = () => { setReturnTo(query.measure); setRouteQuery?.({ ...query, measure: undefined, part: undefined }); };
  const detailPanel = (measure: string, period: NonNullable<typeof resolved.period>, canExport: boolean) =>
    <MeasureDetail measure={measure} part={query.part} period={period} filters={filters} scopeLabel={scopeLabel} canExport={canExport} onBack={close} onPart={part => setRouteQuery?.({ ...query, part }, true)} />;

  return <section className="pilotage-page">
    <header className="pilotage-heading"><h1>Statistiques</h1></header>
    <Tabs className="pilotage-domain" value={tab} onValueChange={value => setRouteQuery?.({ ...query, measure: undefined, part: undefined, tab: value === 'activity' ? undefined : value as StatisticsTab })}>
      <TabsList variant="line" aria-label="Domaine des statistiques">
        {rights.activity && <TabsTrigger value="activity">Activité</TabsTrigger>}
        {rights.finance && <TabsTrigger value="finance">Finances</TabsTrigger>}
      </TabsList>
      <PilotageFilters query={query} instructors={instructors} categories={categoryOptions} products={productOptions} problem={resolved.problem ?? null} onChange={change} />
      {rights.activity && <TabsContent value="activity"><div className="pilotage-panel">
        {resolved.period && (detail && measureDomain(detail) === 'activity'
          ? detailPanel(detail, resolved.period, rights.export)
          : <ActivityPanel period={resolved.period} today={today} filters={filters} scopeLabel={scopeLabel} onOpen={open} returnFocus={returnTo} onFocused={() => setReturnTo(undefined)} />)}
      </div></TabsContent>}
      {rights.finance && <TabsContent value="finance"><div className="pilotage-panel">
        {resolved.period && (detail && measureDomain(detail) === 'finance'
          ? detailPanel(detail, resolved.period, rights.export)
          : <FinancePanel period={resolved.period} today={today} filters={filters} scopeLabel={scopeLabel} onOpen={open} returnFocus={returnTo} onFocused={() => setReturnTo(undefined)} />)}
      </div></TabsContent>}
    </Tabs>
  </section>;
}
