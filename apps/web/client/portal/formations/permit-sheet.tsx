import { useEffect, useRef } from 'react';
import { History } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Empty, EmptyContent, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '../../components/ui/tabs';
import { BookOpen } from 'lucide-react';
import type { TariffType } from '../../formation-api';
import { categoryBadge, categoryIssueText, programmeName } from '../../console/formation-model';
import { useConsole } from '../../console/context';
import type { NavigationQuery } from '../../console/route';
import { PortalSelect } from '../components/portal-select';
import { TariffsPanel } from '../pricing/tariffs-panel';
import { BackButton, CommandFeedback, PermitMark, ReadFeedback, StateBadge } from './catalogue-ui';
import { useCatalogueCommand } from './catalogue-command';
import { useFormationSheet } from './formation-controllers';
import { plural } from './formation-format';
import { HistoryView } from './history-view';
import { ProgrammeSection } from './programme-sections';
import { rubrics, sheetView, type SheetView } from './sheet-routing';

/** Fiche d'un permis : comprendre l'offre, consulter le programme, faire une modification autorisée. */
export function PermitSheet({ category }: { category: string }) {
  const { school, routeQuery = {}, navigate, setRouteQuery } = useConsole();
  const { loaded, proposals, programmes, selected } = useFormationSheet(category);
  const command = useCatalogueCommand();
  const view = sheetView(routeQuery.view);
  const title = useRef<HTMLHeadingElement>(null);
  useEffect(() => { title.current?.focus({ preventScroll: true }); }, [category]);
  const data = loaded.data;
  // Changer de rubrique ou de parcours passe par la garde de navigation : une saisie non enregistrée ne se perd pas en silence.
  const go = (query: NavigationQuery) => setRouteQuery?.({ category, ...query }, false);
  const inside = (query: NavigationQuery) => setRouteQuery?.({ category, ...query }, false, true);
  const tariffTypes: TariffType[] = ['INDIVIDUAL_LESSON', 'EXAM_SUPPORT', ...(school.modules.collectiveCoursesEnabled ? ['COLLECTIVE_COURSE' as const] : [])];
  const learners = programmes.reduce((sum, item) => sum + item.enrollments.current + item.enrollments.previous, 0);
  return <section className="cat-page">
    <BackButton onClick={() => view === 'historique' ? go({ view: 'general', ...(selected ? { programme: selected.offeringKey } : {}) }) : navigate('formations', {})}>{view === 'historique' ? `Permis ${category}` : 'Formations'}</BackButton>
    <ReadFeedback loaded={loaded} label={`Lecture du permis ${category}`} />
    {data && <>
      <header className="cat-heading cat-sheet-head">
        <div className="cat-title"><PermitMark code={data.categoryCode} />
          <div><h1 ref={title} tabIndex={-1}>{view === 'historique' ? 'Historique' : `Permis ${data.categoryCode}`}</h1>
            <p className="cat-muted">{view === 'historique' ? `Permis ${data.categoryCode}` : `${plural(learners, 'élève')} en formation · ${plural(data.tariffs.length, 'tarif')}`}</p></div>
          {view !== 'historique' && <StateBadge badge={categoryBadge(data.state)} />}</div>
        {view !== 'historique' && <div className="cat-heading-actions"><Button variant="ghost" onClick={() => inside({ view: 'historique' })}><History data-icon="inline-start" />Historique</Button></div>}
      </header>
      {data.issues.length > 0 && view !== 'historique' && <Alert><AlertTitle>À compléter</AlertTitle>
        <AlertDescription><ul className="cat-issues">{data.issues.map(issue => <li key={issue}>{categoryIssueText(issue)}</li>)}</ul></AlertDescription></Alert>}
      {view === 'historique'
        ? <HistoryView sheet={data} selection={routeQuery.selection} />
        : <Tabs value={view} onValueChange={next => { const value = sheetView(String(next)); go({ view: value, ...(selected && value !== 'tarifs' ? { programme: selected.offeringKey } : {}) }); }} className="cat-tabs">
          <TabsList aria-label={`Rubriques du permis ${data.categoryCode}`}>{rubrics.map(rubric => <TabsTrigger key={rubric.view} value={rubric.view}>{rubric.label}</TabsTrigger>)}</TabsList>
          <TabsContent value={view} className="cat-tab-content">
            {view === 'tarifs'
              ? <TariffsPanel tariffs={data.tariffs} categoryCode={data.categoryCode} today={data.today} canConfigure={data.canConfigureCatalog} types={tariffTypes} proposals={proposals.data}
                command={command} reload={loaded.reload} programmeCount={programmes.length} selection={routeQuery.selection}
                onSelect={id => inside({ view: 'tarifs', ...(id ? { selection: id } : {}) })} onConsultVersion={id => inside({ view: 'historique', selection: id })} onOpenTerms={id => navigate('conditions', { selection: id })} />
              : !selected
                ? <Empty className="cat-empty"><EmptyHeader><EmptyMedia variant="icon"><BookOpen /></EmptyMedia><EmptyTitle>Aucun parcours pour ce permis</EmptyTitle></EmptyHeader>
                  {data.canConfigureCatalog && <EmptyContent><Button onClick={() => navigate('apercu', { from: 'formations', category: data.categoryCode })}>Préparer ce permis</Button></EmptyContent>}</Empty>
                : <>
                  {programmes.length > 1 && <PortalSelect id="cat-programme" label="Parcours" value={selected.offeringKey} className="cat-programme-switch"
                    options={programmes.map(item => ({ value: item.offeringKey, label: programmeName(item, programmes) }))} onValueChange={key => { if (key) go({ view, programme: key }); }} />}
                  {!data.canConfigureCatalog && <p className="cat-hint">L’autorisation de configurer les tarifs est nécessaire pour modifier ce permis.</p>}
                  <ProgrammeSection key={`${view}:${selected.offeringKey}`} view={view as Exclude<SheetView, 'historique' | 'tarifs'>} sheet={data} programme={selected} command={command} proposals={proposals.data} reload={loaded.reload}
                    onTariffs={() => inside({ view: 'tarifs' })} onHistory={() => inside({ view: 'historique' })} />
                </>}
          </TabsContent>
        </Tabs>}
      {view === 'historique' && <CommandFeedback runner={command.runner} />}
    </>}
  </section>;
}
