import { useEffect } from 'react';
import { z } from 'zod';
import { useCommandSnapshot } from '../command-store';
import { readSchool } from '../school-api';
import { setupDraftSchema } from '../setup-model';
import { Loading, Notice, Symbol, type Tone } from '../ui';
import { useConsole, useLoad } from './context';
import { LoadState, SectionHeading } from './layout';
import { consolePath, readNavigationQuery } from './route';
import { sectionKeys } from './sections';
import { SchoolSetupGuide } from './school-setup';
import { useListState } from './list-state';

export const schoolStatus = (status: string): { label: string; tone: Tone } =>
  status === 'ACTIVE' ? { label: 'École active', tone: 'success' } : status === 'DRAFT' ? { label: 'En préparation', tone: 'warning' } : { label: 'École inactive', tone: 'neutral' };

export const capabilityTitle = (capability: string) => ({
  CAN_USE_WORKSPACE: 'Espace de l’école', CAN_PLAN_LESSON: 'Planification des leçons',
  CAN_CAPTURE: 'Enregistrement des trajets', CAN_PUBLISH_COURSE: 'Publication des cours',
} as Record<string, string>)[capability] ?? 'Autre fonction';

const nextActionsSchema = z.object({ schoolId: z.string().uuid(), planningReady: z.boolean(), actions: z.array(z.object({
  code: z.string(), label: z.string(), section: z.enum(sectionKeys), query: z.record(z.string(), z.string()).optional(),
})).max(30) });
type NextAction = z.infer<typeof nextActionsSchema>['actions'][number];

function ActionLink({ action }: { action: NextAction }) {
  const { schoolId, navigate } = useConsole();
  const query = readNavigationQuery(new URLSearchParams(action.query).toString());
  if (action.section === 'apercu' && !query.from) query.from = 'configuration';
  if (action.code === 'PLAN_FIRST_LESSON') return <button type="button" className="preparation-link" onClick={() => navigate('agenda', { view: 'nouvelle', learner: query.selection ?? query.learner })}><span className="row-title">Planifier une leçon</span><span className="flip"><Symbol kind="back" bare /></span></button>;
  return <a className="preparation-link" href={consolePath(schoolId, action.section, query)} onClick={event => {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
    event.preventDefault(); navigate(action.section, query);
  }}><span className="row-title">{action.label}</span><span className="flip"><Symbol kind="back" bare /></span></a>;
}

export function OverviewSection() {
  const { school, routeQuery, navigate } = useConsole();
  const catalogueOnly = routeQuery?.from === 'formations' || routeQuery?.from === 'prestations';
  const dailyEntry = school.status === 'ACTIVE' && !catalogueOnly && routeQuery?.from !== 'configuration';
  useEffect(() => {
    if (dailyEntry) navigate('agenda', { week: routeQuery?.week, instructor: routeQuery?.instructor,
      lesson: routeQuery?.lesson, learner: routeQuery?.learner, view: routeQuery?.view }, { replace: true });
  }, [dailyEntry, navigate, routeQuery]);
  if (school.status === 'DRAFT') return <SchoolSetupGuide />;
  if (school.status === 'ARCHIVED') return <div className="section-stack"><SectionHeading title="École archivée" />
    <Notice tone="info" title="La préparation est fermée" live={false}><p>Vous pouvez consulter les rendez-vous et les informations de l’école selon vos accès.</p></Notice>
    <div className="form-actions"><button type="button" className="button primary" onClick={() => navigate('agenda')}>Consulter le planning</button>
      <button type="button" className="button secondary" onClick={() => navigate('configuration')}>Informations de l’école</button></div>
  </div>;
  if (catalogueOnly) return <SchoolSetupGuide catalogueOnly onClose={() => navigate('formations')} />;
  if (dailyEntry) return <Loading label="Ouverture du planning…" />;
  return <SchoolPreparation />;
}

function SchoolPreparation() {
  const { schoolId, school, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    const [next, draft] = await Promise.all([readSchool(schoolId, 'setup-draft/next-actions', nextActionsSchema), readSchool(schoolId, 'setup-draft', setupDraftSchema)]);
    return { next, deferred: draft.content.formations.filter(item => !item.apply) };
  }, [schoolId, school.version, revision]);
  return <div className="section-stack"><SectionHeading title="Préparation de l’école" />
    <LoadState loaded={loaded} label="Lecture de la préparation…">{({ next, deferred }) => <>
      {next.actions.length ? <ul className="preparation-list">{next.actions.map(action => <li key={action.code}><ActionLink action={action} /></li>)}</ul>
        : <p className="empty-inline">La préparation de l’école est terminée.</p>}
      {deferred.length > 0 && <button type="button" className="button secondary" onClick={() => navigate('apercu', { from: 'formations' })}>Reprendre les formations mises de côté ({deferred.length})</button>}
    </>}</LoadState>
    <div className="form-actions"><button type="button" className="button primary" onClick={() => navigate('agenda')}>Ouvrir le planning</button>
      <button type="button" className="button secondary" onClick={() => navigate('apercu', { from: 'formations' })}>Préparer une formation</button></div>
  </div>;
}

export function FirstLessonActions({ refreshKey = 0 }: { refreshKey?: number }) {
  const { schoolId, school, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const [reducedAction, setReducedAction] = useListState<string | null>('first-lesson/reduced-action', null);
  const loaded = useLoad(() => readSchool(schoolId, 'setup-draft/next-actions', nextActionsSchema), [schoolId, school.version, revision, refreshKey]);
  return <LoadState loaded={loaded} label="Vérification du premier rendez-vous…">{next => {
    const action = next.actions[0];
    if (!next.planningReady || !action) return null;
    const reduced = reducedAction === action.code;
    return <section className="first-lesson-actions" aria-label="Premier rendez-vous">
    <div className="first-lesson-heading"><h2>Votre premier rendez-vous</h2><button type="button" className="button quiet" aria-expanded={!reduced} onClick={() => setReducedAction(reduced ? null : action.code)}>{reduced ? 'Afficher' : 'Réduire'}</button></div>
    {!reduced && <><ActionLink action={action} />
      {loaded.readAt !== undefined && <p className="caption">Vérifié à <time dateTime={new Date(loaded.readAt).toISOString()}>{new Intl.DateTimeFormat('fr-CH', { hour: '2-digit', minute: '2-digit', timeZone: school.timeZone }).format(loaded.readAt)}</time></p>}
      <button type="button" className="button quiet" onClick={() => navigate('apercu', { from: 'configuration' })}>Préparation de l’école</button></>}
  </section>;
  }}</LoadState>;
}
