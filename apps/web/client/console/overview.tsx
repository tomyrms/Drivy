import { useState } from 'react';
import { z } from 'zod';
import { useCommandSnapshot } from '../command-store';
import { readSchool } from '../school-api';
import { setupDraftSchema } from '../setup-model';
import { ConfirmDialog, Symbol, type Tone } from '../ui';
import { useConsole, useLoad } from './context';
import { LoadState, SectionHeading } from './layout';
import { consolePath, readNavigationQuery } from './route';
import { sectionKeys } from './sections';
import { SchoolSetupGuide } from './school-setup';

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
  const [showApp, setShowApp] = useState(false);
  const query = readNavigationQuery(new URLSearchParams(action.query).toString());
  if (action.code === 'PLAN_FIRST_LESSON') return <>
    <button type="button" className="preparation-link" onClick={() => setShowApp(true)}><span className="row-title">Planifier dans l’app Drivy</span><span className="flip"><Symbol kind="back" bare /></span></button>
    <ConfirmDialog open={showApp} busy={false} title="Votre première leçon" confirmLabel="Voir le dossier" onCancel={() => setShowApp(false)} onConfirm={() => { setShowApp(false); navigate('eleves', { selection: query.selection ?? query.learner }); }}>
      <p>Connectez-vous à l’app Drivy avec votre compte moniteur. Dans Élèves, ouvrez le dossier puis choisissez « Planifier une leçon ».</p>
    </ConfirmDialog>
  </>;
  return <a className="preparation-link" href={consolePath(schoolId, action.section, query)} onClick={event => {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
    event.preventDefault(); navigate(action.section, query);
  }}><span className="row-title">{action.label}</span><span className="flip"><Symbol kind="back" bare /></span></a>;
}

export function OverviewSection() {
  const { school, routeQuery, navigate } = useConsole();
  if (school.status === 'DRAFT') return <SchoolSetupGuide />;
  if (routeQuery?.from === 'formations' || routeQuery?.from === 'prestations') return <SchoolSetupGuide catalogueOnly onClose={() => navigate('formations')} />;
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

export function FirstLessonActions() {
  const { schoolId, school, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const [reduced, setReduced] = useState(false);
  const loaded = useLoad(() => readSchool(schoolId, 'setup-draft/next-actions', nextActionsSchema), [schoolId, school.version, revision]);
  return <LoadState loaded={loaded} label="Vérification de la première leçon…">{next => next.actions.length > 0 && <section className="first-lesson-actions" aria-label="Première leçon">
    <div className="first-lesson-heading"><h2>Votre première leçon</h2><button type="button" className="button quiet" aria-expanded={!reduced} onClick={() => setReduced(!reduced)}>{reduced ? 'Afficher' : 'Réduire'}</button></div>
    {!reduced && <><ActionLink action={next.actions[0]!} /><button type="button" className="button quiet" onClick={() => navigate('apercu')}>Voir toute la préparation</button></>}
  </section>}</LoadState>;
}
