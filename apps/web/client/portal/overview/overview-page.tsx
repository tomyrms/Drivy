import { useEffect } from 'react';
import { z } from 'zod';
import { ArrowRight, CalendarDays, CircleCheck, Info, Layers } from 'lucide-react';
import { useCommandSnapshot } from '../../command-store';
import { readSchool } from '../../school-api';
import { useConsole, useLoad } from '../../console/context';
import { readNavigationQuery } from '../../console/route';
import { sectionKeys } from '../../console/sections';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Skeleton } from '../../components/ui/skeleton';
import { ReadFeedback } from '../components/feedback';
import { SetupGuide } from '../setup/setup-guide';
import './overview.css';

const nextActionsSchema = z.object({ schoolId: z.string().uuid(), planningReady: z.boolean(), actions: z.array(z.object({
  code: z.string(), label: z.string(), section: z.enum(sectionKeys), query: z.record(z.string(), z.string()).optional(),
})).max(30) });
type NextAction = z.infer<typeof nextActionsSchema>['actions'][number];
/** Only the deferred formations are read from the setup draft here; the guide (#320) owns the rest. */
const deferredSchema = z.object({ content: z.object({ formations: z.array(z.object({ apply: z.boolean() }).passthrough()) }).passthrough() }).passthrough();

/** School entry (#321): the daily entry opens the agenda; the preparation page lists the server's next actions. */
export function OverviewPilot() {
  const { school, routeQuery, navigate } = useConsole();
  const catalogueOnly = routeQuery?.from === 'formations' || routeQuery?.from === 'prestations';
  const dailyEntry = school.status === 'ACTIVE' && !catalogueOnly && routeQuery?.from !== 'configuration';
  useEffect(() => {
    if (dailyEntry) navigate('agenda', { week: routeQuery?.week, day: routeQuery?.day, instructor: routeQuery?.instructor,
      lesson: routeQuery?.lesson, learner: routeQuery?.learner, course: routeQuery?.course, occurrence: routeQuery?.occurrence, view: routeQuery?.view }, { replace: true });
  }, [dailyEntry, navigate, routeQuery]);
  if (school.status === 'DRAFT' || catalogueOnly) return <SetupGuide catalogueOnly={catalogueOnly} />;
  if (school.status === 'ARCHIVED') return <section className="overview-page">
    <h1>École archivée</h1>
    <Alert><Info aria-hidden="true" /><AlertTitle>La préparation est fermée</AlertTitle><AlertDescription>Le planning et les informations de l’école restent consultables selon vos accès.</AlertDescription></Alert>
    <div className="overview-actions"><Button onClick={() => navigate('agenda')}>Consulter le planning</Button><Button variant="outline" onClick={() => navigate('configuration')}>Informations de l’école</Button></div>
  </section>;
  if (dailyEntry) return <div className="grid gap-5" role="status" aria-label="Ouverture du planning"><Skeleton className="h-10 w-56" /><Skeleton className="h-80 w-full" /></div>;
  return <Preparation />;
}

function ActionRow({ action }: { action: NextAction }) {
  const { navigate } = useConsole();
  const query = readNavigationQuery(new URLSearchParams(action.query).toString());
  if (action.section === 'apercu' && !query.from) query.from = 'configuration';
  const open = () => action.code === 'PLAN_FIRST_LESSON' ? navigate('agenda', { view: 'nouvelle', learner: query.selection ?? query.learner }) : navigate(action.section, query);
  return <Button variant="ghost" className="overview-action" onClick={open}>
    <span className="overview-action-icon">{action.code === 'PLAN_FIRST_LESSON' ? <CalendarDays aria-hidden="true" /> : <Layers aria-hidden="true" />}</span>
    <span>{action.code === 'PLAN_FIRST_LESSON' ? 'Planifier une leçon' : action.label}</span><ArrowRight aria-hidden="true" />
  </Button>;
}

function Preparation() {
  const { schoolId, school, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    const [next, draft] = await Promise.all([readSchool(schoolId, 'setup-draft/next-actions', nextActionsSchema), readSchool(schoolId, 'setup-draft', deferredSchema)]);
    return { next, deferred: draft.content.formations.filter(item => !item.apply).length };
  }, [schoolId, school.version, revision]);
  return <section className="overview-page">
    <header className="overview-heading"><h1>Préparation de l’école</h1><Button onClick={() => navigate('agenda')}>Ouvrir le planning</Button></header>
    <ReadFeedback loaded={loaded} label="Lecture de la préparation" />
    {loaded.status === 'ready' && loaded.data && <>
      {loaded.data.next.actions.length
        ? <ul className="overview-list">{loaded.data.next.actions.map(action => <li key={action.code}><ActionRow action={action} /></li>)}</ul>
        : <Empty><EmptyHeader><EmptyMedia variant="icon"><CircleCheck aria-hidden="true" /></EmptyMedia><EmptyTitle>Votre école est prête</EmptyTitle></EmptyHeader></Empty>}
      <div className="overview-actions">
        {loaded.data.deferred > 0 && <Button variant="outline" onClick={() => navigate('apercu', { from: 'formations' })}>Reprendre les formations mises de côté ({loaded.data.deferred})</Button>}
        <Button variant="ghost" onClick={() => navigate('apercu', { from: 'formations' })}>Préparer une formation</Button>
      </div>
    </>}
  </section>;
}
