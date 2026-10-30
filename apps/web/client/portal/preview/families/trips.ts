import { schoolTimeToInstant } from '../../../command-core';
import { dayAfter, ids, previewId } from '../fixtures';
import type { PreviewFamily } from '../family';

/** Synthetic GPS trips (#332): one capture per completed lesson, an ongoing one and an interrupted one. Read only. */
const zone = 'Europe/Zurich';
const learners = ['Éloïse Müller', 'Bruno Blanc', 'Jade Perrin', 'Sami Dubois', 'Léa Rochat', 'Noah Meier'];
const instructors: readonly [string, string][] = [[ids.instructor, 'Marie Dupont'], [previewId(6), 'Simon Favre']];

export const tripsFamily: PreviewFamily = {
  name: 'trips',
  seed(db) {
    db.captures = Array.from({ length: 14 }, (_, index) => {
      const learner = index % learners.length, [instructorId, instructorName] = instructors[index % 2]!;
      const start = schoolTimeToInstant(`${dayAfter(-1 - index)}T${index % 2 ? '14:00' : '09:30'}`, zone)!;
      const minutes = [45, 50, 42, 60, 38, 45, 90][index % 7]!;
      const ongoing = index === 0, interrupted = index === 5;
      return { id: previewId(900 + index), schoolId: ids.school, lessonId: previewId(950 + index), learnerId: previewId(10 + learner), learnerName: learners[learner]!,
        instructorName, instructorMembershipId: instructorId, authorizedAt: start, lessonPlannedStart: start, lessonTimeZone: zone,
        stoppedAt: ongoing || interrupted ? null : new Date(Date.parse(start) + minutes * 60_000).toISOString(),
        cutoffAt: interrupted ? new Date(Date.parse(start) + 21 * 60_000).toISOString() : null,
        captureState: ongoing ? 'AUTHORIZED' : interrupted ? 'CUT_OFF' : 'STOPPED', syncState: 'SYNCED' };
    });
  },
};
