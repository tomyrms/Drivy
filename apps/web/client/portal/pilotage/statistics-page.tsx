import { civilDateIn } from '../../agenda-model';
import { useConsole } from '../../console/context';
import type { StatisticsTab } from '../../console/route';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '../../components/ui/tabs';
import { ActivityPanel } from './activity-panel';
import { MetricSection, MetricTile, PilotageFilters, type FilterPatch } from './components';
import { MetricsView, ScopeLine } from './metrics-view';
import { periodLabel, resolvePeriod, type ResolvedPeriod } from './period-model';
import { canOpenStatistics, metricRights } from './rights';
import type { MetricFilters } from './metrics-api';
import { useCatalogueOptions } from './use-catalogue-options';
import { useDirectory } from './use-directory';

/** Mesures de l'onglet Finances ; T06 (#379) les reprend. Le serveur décide des valeurs et de leur couverture. */
const financeGroups: readonly { title: string; ids: readonly string[] }[] = [
  { title: 'Leçons individuelles', ids: ['F01', 'F02', 'F03', 'F04'] },
  { title: 'Cours collectifs', ids: ['F05', 'F07'] },
];

/** Statistiques (#373) : deux onglets, Activité et Finances, sous les mêmes filtres portés par l'adresse. */
export function StatisticsPilot() {
  const { school, membership, routeQuery, setRouteQuery } = useConsole();
  const query = routeQuery ?? {};
  const rights = metricRights(membership);
  // Les moniteurs servent seulement de filtre : leur lecture ne bloque jamais les chiffres.
  const { instructorOptions: instructors } = useDirectory({ learners: false });
  const { categoryOptions, productOptions } = useCatalogueOptions({ category: query.category, product: query.product });
  if (!canOpenStatistics(rights)) return <section className="pilotage-page">
    <h1>Statistiques</h1>
    <Alert variant="destructive"><AlertTitle>Statistiques non disponibles</AlertTitle><AlertDescription>Vos accès ne permettent pas de consulter les indicateurs de l’école.</AlertDescription></Alert>
  </section>;

  const wanted: StatisticsTab = query.tab ?? 'activity';
  const tab: StatisticsTab = wanted === 'finance' ? (rights.finance ? 'finance' : 'activity') : (rights.activity ? 'activity' : 'finance');
  const today = civilDateIn(school.timeZone);
  const resolved = resolvePeriod(query, today);
  const filters: MetricFilters = { instructor: query.instructor, category: query.category, product: query.product };
  const scopeLabel = [query.instructor ? instructors.find(item => item.value === query.instructor)?.label ?? 'Un moniteur' : null,
    query.category ? categoryOptions.find(item => item.value === query.category)?.label ?? `Permis ${query.category}` : null,
    query.product ? productOptions.find(item => item.value === query.product)?.label ?? query.product : null].filter(Boolean).join(' · ') || 'Toute l’école';
  const change = (patch: FilterPatch) => setRouteQuery?.({ ...query, ...patch }, true);
  const financePanel = (period: ResolvedPeriod) => <MetricsView label="Lecture des chiffres" request={{ domain: 'finance', from: period.from, toExclusive: period.toExclusive, ...filters }}>
    {(answer, definitions) => <>
      <ScopeLine period={periodLabel(period)} scope={answer.scope.kind === 'self' ? 'Vos leçons' : scopeLabel} answer={answer} />
      {financeGroups.map(group => {
        const ids = group.ids.filter(id => answer.measures[id] !== undefined);
        if (ids.length === 0) return null;
        return <MetricSection key={group.title} title={group.title}>
          {ids.map(id => <MetricTile key={id} label={definitions.get(id)?.label ?? id} measure={answer.measures[id]!} definition={definitions.get(id)} />)}
        </MetricSection>;
      })}
    </>}
  </MetricsView>;

  return <section className="pilotage-page">
    <header className="pilotage-heading"><h1>Statistiques</h1></header>
    <Tabs value={tab} onValueChange={value => setRouteQuery?.({ ...query, tab: value === 'activity' ? undefined : value as StatisticsTab })}>
      <TabsList variant="line" aria-label="Domaine des statistiques">
        {rights.activity && <TabsTrigger value="activity">Activité</TabsTrigger>}
        {rights.finance && <TabsTrigger value="finance">Finances</TabsTrigger>}
      </TabsList>
      <PilotageFilters query={query} instructors={instructors} categories={categoryOptions} products={productOptions} problem={resolved.problem ?? null} onChange={change} />
      {rights.activity && <TabsContent value="activity"><div className="pilotage-panel">{resolved.period && <ActivityPanel period={resolved.period} today={today} filters={filters} scopeLabel={scopeLabel} />}</div></TabsContent>}
      {rights.finance && <TabsContent value="finance"><div className="pilotage-panel">{resolved.period && financePanel(resolved.period)}</div></TabsContent>}
    </Tabs>
  </section>;
}
