import { Users } from 'lucide-react';
import { Button } from '../../components/ui/button';
import type { CourseSeries } from '../../console/course-model';
import type { ParticipantTask } from './participants-view';

/**
 * Entry point of the participants of a published course (R18 / #329). It shows what the series itself carries, places taken and left,
 * and opens the participants view where enrolments, the waiting list, the call, settlements and validation each have their own task.
 * Whether a task is offered is decided there, from the rights the school returns with the sheet.
 */
export function CourseParticipantsEntry({ series, canOpen, onOpen }: {
  series: Pick<CourseSeries, 'capacity' | 'seatsTaken' | 'remainingSeats' | 'minParticipants'>; canOpen: boolean; onOpen: (task: ParticipantTask) => void;
}) {
  return <section id="course-participants" className="course-participants" aria-labelledby="course-participants-title">
    <Users aria-hidden="true" />
    <h2 id="course-participants-title">{series.seatsTaken} / {series.capacity} {series.seatsTaken <= 1 ? 'inscrit' : 'inscrits'}</h2>
    <p className="course-muted">{series.remainingSeats === 0 ? 'Complet' : `${series.remainingSeats} ${series.remainingSeats === 1 ? 'place libre' : 'places libres'}`}</p>
    {canOpen && <Button variant="outline" onClick={() => onOpen('roster')}>Participants</Button>}
  </section>;
}
