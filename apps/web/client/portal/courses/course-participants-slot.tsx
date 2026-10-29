import { Users } from 'lucide-react';
import type { CourseSeries } from '../../console/course-model';

/**
 * Entry point of the participants of a published course (R18 / #329: enrolments, waiting list, attendance, on-site payments, validation).
 * Until that family is rebuilt it shows only what the series itself carries: places taken and left. It offers no control that would
 * lead to an empty view. #329 replaces the body of this component and keeps its place in the sheet (`#course-participants`).
 */
export function CourseParticipantsEntry({ series }: { series: Pick<CourseSeries, 'capacity' | 'seatsTaken' | 'remainingSeats' | 'minParticipants'> }) {
  return <section id="course-participants" className="course-participants" aria-labelledby="course-participants-title">
    <Users aria-hidden="true" />
    <h2 id="course-participants-title">{series.seatsTaken} / {series.capacity} {series.seatsTaken <= 1 ? 'inscrit' : 'inscrits'}</h2>
    <p className="course-muted">{series.remainingSeats === 0 ? 'Complet' : `${series.remainingSeats} ${series.remainingSeats === 1 ? 'place libre' : 'places libres'}`}</p>
  </section>;
}
