import { civilDateIn } from '../../agenda-model';
import { useConsole, useLoad } from '../../console/context';
import type { StatisticsTab } from '../../console/route';
import { activeInstructors } from '../../invitation-model';
import { distinctLabel, homonymReferences } from '../../person-reference';
import { memberSchema, readAll } from '../../school-api';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '../../components/ui/tabs';
import { MetricSection, MetricTile, PilotageFilters, type FilterOption, type FilterPatch } from './components';
import { MetricsView, ScopeLine } from './metrics-view';
import { periodLabel, resolvePeriod, type ResolvedPeriod } from './period-model';
import { canOpenStatistics, metricRights } from './rights';
import type { MetricDomain } from './metrics-api';

/** Mesures montrées par onglet, dans l'ordre de lecture. Le serveur décide des valeurs et de leur couverture. */
const groups: Record<MetricDomain, readonly { title: string; ids: readonly string[] }[]> = {
  activity: [
    { title: 'Leçons', ids: ['L01', 'L02', 'L03', 'L04'] },
    { title: 'Heures', ids: ['H02', 'H03'] },
    { title: 'Élèves', ids: ['P01'] },
    { title: 'Cours collectifs', ids: ['C01', 'C06', 'C09'] },
  ],
  finance: [
    { title: 'Leçons individuelles', ids: ['F01', 'F02', 'F03', 'F04'] },
    { title: 'Cours collectifs', ids: ['F05', 'F07'] },
  ],
};

/** Statistiques (#373) : deux onglets, Activité et Finances, sous les mêmes filtres portés par l'adresse. */
export function StatisticsPilot() {
  const { schoolId, school, membership, routeQuery, setRouteQuery } = useConsole();
  const query = routeQuery ?? {};
  const rights = metricRights(membership);
  // Les moniteurs servent seulement de filtre : leur lecture ne bloque jamais les chiffres.
  const directory = useLoad(() => readAll(schoolId, 'members', memberSchema), [schoolId]);
  if (!canOpenStatistics(rights)) return <section className="pilotage-page">
    <h1>Statistiques</h1>
    <Alert variant="destructive"><AlertTitle>Statistiques non disponibles</AlertTitle><AlertDescription>Vos accès ne permettent pas de consulter les indicateurs de l’école.</AlertDescription></Alert>
  </section>;

  const members = activeInstructors(directory.data?.items ?? []);
  const references = homonymReferences(members.map(item => ({ id: item.id, label: item.displayName })));
  const instructors: FilterOption[] = members.map(item => ({ value: item.id, label: distinctLabel(item.displayName, references.get(item.id)) }));
  const wanted: StatisticsTab = query.tab ?? 'activity';
  const tab: StatisticsTab = wanted === 'finance' ? (rights.finance ? 'finance' : 'activity') : (rights.activity ? 'activity' : 'finance');
  const resolved = resolvePeriod(query, civilDateIn(school.timeZone));
  const instructorLabel = instructors.find(item => item.value === query.instructor)?.label;
  const change = (patch: FilterPatch) => setRouteQuery?.({ ...query, ...patch }, true);
  const panel = (domain: MetricDomain, period: ResolvedPeriod) => <MetricsView label="Lecture des chiffres" request={{ domain, from: period.from, toExclusive: period.toExclusive, instructor: query.instructor }}>
    {(answer, definitions) => <>
      <ScopeLine period={periodLabel(period)} scope={answer.scope.kind === 'self' ? 'Vos leçons' : instructorLabel ?? 'Toute l’école'} answer={answer} />
      {groups[domain].map(group => {
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
      <PilotageFilters query={query} instructors={instructors} problem={resolved.problem ?? null} onChange={change} />
      {rights.activity && <TabsContent value="activity"><div className="pilotage-panel">{resolved.period && panel('activity', resolved.period)}</div></TabsContent>}
      {rights.finance && <TabsContent value="finance"><div className="pilotage-panel">{resolved.period && panel('finance', resolved.period)}</div></TabsContent>}
    </Tabs>
  </section>;
}
