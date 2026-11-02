import { ChevronRight } from 'lucide-react';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { useCommandSnapshot } from '../../command-store';
import { useConsole, useLoad } from '../../console/context';
import { lateLabel, lessonChangeInboxSchema, requestShort } from '../../lesson-change-model';
import { readSchool } from '../../school-api';
import { dateTime } from '../agenda/presentation';
import type { LearnerController } from './learner-controller';

/** Demandes des élèves en attente (#52), dans l'annuaire : chaque ligne ouvre la leçon dans l'agenda, où le personnel répond. */
export function PendingLessonRequests({ state }: { state: LearnerController }) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => (await readSchool(schoolId, 'lesson-change-requests', lessonChangeInboxSchema)).items, [schoolId, revision], `${schoolId}/lesson-change-requests`);
  const items = loaded.data ?? [];
  // Une panne ne dit rien des demandes : le bloc se tait plutôt que d'affirmer qu'il n'y en a pas.
  if (loaded.status !== 'ready' || items.length === 0) return null;
  return <section className="student-section lesson-requests" aria-labelledby="lesson-requests-title">
    <h2 id="lesson-requests-title">Demandes des élèves</h2>
    <ul className="exam-list">{items.slice(0, 8).map(item => {
      const late = lateLabel(item.request);
      return <li key={item.request.id} className="exam-row">
        <Button type="button" variant="ghost" className="exam-pending-open" onClick={() => state.navigate('agenda', { lesson: item.lesson.id })}>
          <span className="exam-main"><strong>{item.lesson.learnerDisplayName || 'Élève'}</strong>
            <span>{requestShort(item.request.kind)} · leçon du {dateTime(item.lesson.plannedStart, item.lesson.timeZone)}</span></span>
          {late && <Badge variant="outline">{late}</Badge>}<ChevronRight aria-hidden="true" />
        </Button>
      </li>;
    })}</ul>
    {items.length > 8 && <p className="student-muted">{items.length - 8} autres demandes.</p>}
  </section>;
}
