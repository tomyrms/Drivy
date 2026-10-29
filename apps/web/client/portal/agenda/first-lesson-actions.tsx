import { z } from 'zod';
import { ArrowRight } from 'lucide-react';
import { useCommandSnapshot } from '../../command-store';
import { RequestFailure } from '../../protocol';
import { readSchool } from '../../school-api';
import { useConsole, useLoad } from '../../console/context';
import { useListState } from '../../console/list-state';
import { consolePath, readNavigationQuery, type NavigationQuery } from '../../console/route';
import { sectionKeys, type SectionKey } from '../../console/sections';
import { Button } from '../../components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '../../components/ui/card';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import { ReadFeedback } from '../components/feedback';

const nextActionsSchema = z.object({ schoolId: z.uuid(), planningReady: z.boolean(), actions: z.array(z.object({
  code: z.string(), label: z.string(), section: z.enum(sectionKeys), query: z.record(z.string(), z.string()).optional(),
})).max(30) });
type NextAction = z.infer<typeof nextActionsSchema>['actions'][number];

export function nextActionDestination(action: NextAction): { section: SectionKey; query: NavigationQuery } {
  const query = readNavigationQuery(new URLSearchParams(action.query).toString());
  if (action.code === 'PLAN_FIRST_LESSON') return { section: 'agenda', query: { view: 'nouvelle', learner: query.selection ?? query.learner } };
  if (action.section === 'apercu' && !query.from) query.from = 'configuration';
  return { section: action.section, query };
}

/** The server decides the next task and removes this guidance once a first lesson is confirmed. */
export function FirstLessonActions({ refreshKey = 0 }: { refreshKey?: number }) {
  const { schoolId, school, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const [reducedAction, setReducedAction] = useListState<string | null>('first-lesson/reduced-action', null);
  const loaded = useLoad(async () => {
    const value = await readSchool(schoolId, 'setup-draft/next-actions', nextActionsSchema);
    if (value.schoolId !== schoolId) throw new RequestFailure('INVALID_RESPONSE');
    return value;
  }, [schoolId, school.version, revision, refreshKey]);
  if (loaded.status !== 'ready') return <ReadFeedback loaded={loaded} label="Vérification du premier rendez-vous" />;
  const action = loaded.data?.actions[0];
  if (!loaded.data?.planningReady || !action) return null;
  const reduced = reducedAction === action.code;
  const destination = nextActionDestination(action);
  const label = action.code === 'PLAN_FIRST_LESSON' ? 'Planifier une leçon' : action.label;
  return <Collapsible open={!reduced} onOpenChange={open => setReducedAction(open ? null : action.code)}>
    <Card role="region" aria-label="Premier rendez-vous">
      <CardHeader className="flex flex-row flex-wrap items-center justify-between gap-3"><CardTitle>Votre premier rendez-vous</CardTitle>
        <CollapsibleTrigger render={<Button variant="ghost" size="sm" />}>{reduced ? 'Afficher' : 'Réduire'}</CollapsibleTrigger>
      </CardHeader>
      <CollapsibleContent><CardContent className="flex flex-col items-start gap-3">
        <Button variant="outline" nativeButton={false} className="h-auto max-w-full whitespace-normal text-left" render={<a href={consolePath(schoolId, destination.section, destination.query)}
          onClick={event => { if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return; event.preventDefault(); navigate(destination.section, destination.query); }} />}>
          {label}<ArrowRight aria-hidden="true" data-icon="inline-end" />
        </Button>
        <Button variant="ghost" size="sm" onClick={() => navigate('apercu', { from: 'configuration' })}>Préparation de l’école</Button>
      </CardContent></CollapsibleContent>
    </Card>
  </Collapsible>;
}
