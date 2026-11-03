import { civilDateIn } from '../agenda-model.js';
import type { Lesson } from '../school-api.js';
import { seriesByDay, type CourseSeries } from './course-model.js';
import {
  PROVISIONAL_LESSON, intentionLogicalKey, type AgendaMark, type LessonIntention, type PlannedLessonDraft,
} from './agenda-intentions.js';

export type AgendaEvent =
  | { kind: 'lesson'; key: string; logicalKey: string; startsAt: string; lesson: Lesson; mark?: AgendaMark; provisional?: true }
  | { kind: 'course'; key: string; logicalKey: string; startsAt: string; series: CourseSeries; occurrence: CourseSeries['occurrences'][number] };

/** A lesson the school has not created yet: no identifier, no version, no price, nothing to open. */
function provisionalLesson(id: string, draft: PlannedLessonDraft): Lesson {
  return { id, schoolId: '', version: 0, trainingId: draft.trainingId, learnerId: draft.learnerId,
    instructorMembershipId: draft.instructorMembershipId, plannedStart: draft.plannedStart, plannedEnd: draft.plannedEnd,
    timeZone: draft.timeZone, meetingPoint: draft.meetingPoint, status: 'PLANNED' };
}

/**
 * One authorized projection owns ordering, day markers and counts. An occurrence is not its series.
 *
 * Scheduling intentions (#109) enter here and nowhere else: a creation is a provisional row without an identifier of the
 * school, a move keeps the confirmed lesson at its original place and marks the proposal at the target, a requested
 * cancellation keeps the lesson and marks it. Nothing is freed, booked, counted twice or opened from a proposal.
 */
export function agendaDays(lessons: readonly Lesson[], series: readonly CourseSeries[], options: {
  timeZone: string; from: string; to: string; instructor: string; includeCourses: boolean; intentions?: readonly LessonIntention[];
}): { day: string; items: AgendaEvent[] }[] {
  const { timeZone, instructor, includeCourses } = options;
  const from = Date.parse(options.from), to = Date.parse(options.to);
  const intentions = options.intentions ?? [];
  const inWindow = (start: string, end: string) => Date.parse(end) > from && Date.parse(start) < to;
  const byDay = new Map<string, Map<string, AgendaEvent>>();
  const add = (event: AgendaEvent) => {
    const day = civilDateIn(timeZone, Date.parse(event.startsAt));
    const events = byDay.get(day) ?? new Map<string, AgendaEvent>();
    events.set(event.key, event); byDay.set(day, events);
  };
  // Une même leçon ne peut être déplacée ou annulée qu'une fois : la dernière intention suivie pour elle fait foi.
  const moves = new Map<string, Extract<LessonIntention, { kind: 'lesson-move' }>>();
  const cancels = new Map<string, Extract<LessonIntention, { kind: 'lesson-cancel' }>>();
  for (const intention of intentions) {
    if (intention.kind === 'lesson-move') moves.set(intention.lessonId, intention);
    else if (intention.kind === 'lesson-cancel') cancels.set(intention.lessonId, intention);
  }
  for (const lesson of lessons) {
    if (instructor && lesson.instructorMembershipId !== instructor) continue;
    if (!inWindow(lesson.plannedStart, lesson.plannedEnd)) continue;
    const move = moves.get(lesson.id);
    // L'école a accepté le déplacement : sa position confirmée est la cible, pas l'ancienne place.
    if (move && move.settledAt !== undefined) continue;
    const cancel = cancels.get(lesson.id);
    const mark: AgendaMark | undefined = move ? 'moving' : cancel && cancel.settledAt === undefined ? 'cancelling' : undefined;
    add({ kind: 'lesson', key: `lesson:${lesson.id}`, logicalKey: `lesson:${lesson.id}`, startsAt: lesson.plannedStart, lesson, ...(mark ? { mark } : {}) });
  }
  for (const intention of intentions) {
    if (intention.kind === 'lesson-cancel') continue;
    const draft = intention.draft;
    if (instructor && draft.instructorMembershipId !== instructor) continue;
    if (!inWindow(draft.plannedStart, draft.plannedEnd)) continue;
    const id = `${PROVISIONAL_LESSON}${intention.operationId}`;
    const mark: AgendaMark | undefined = intention.settledAt !== undefined ? undefined
      : intention.kind === 'lesson-move' ? 'move-proposal' : 'planning';
    add({ kind: 'lesson', key: intention.kind === 'lesson-move' ? `move:${intention.operationId}` : `create:${intention.operationId}`,
      logicalKey: intentionLogicalKey(intention), startsAt: draft.plannedStart, lesson: provisionalLesson(id, draft), provisional: true,
      ...(mark ? { mark } : {}) });
  }
  if (includeCourses) for (const entries of seriesByDay(series, instant => civilDateIn(timeZone, Date.parse(instant)), from, to).values()) {
    for (const { series: course, occurrence } of entries) {
      if (instructor && occurrence.instructorMembershipId !== instructor) continue;
      add({ kind: 'course', key: `course:${course.id}:${occurrence.id}`, logicalKey: `course:${course.id}:${occurrence.id}`,
        startsAt: occurrence.startsAt, series: course, occurrence });
    }
  }
  return [...byDay].sort(([a], [b]) => a.localeCompare(b)).map(([day, events]) => ({ day,
    items: [...events.values()].sort((a, b) => Date.parse(a.startsAt) - Date.parse(b.startsAt)
      || Date.parse(a.kind === 'lesson' ? a.lesson.plannedEnd : a.occurrence.endsAt) - Date.parse(b.kind === 'lesson' ? b.lesson.plannedEnd : b.occurrence.endsAt)
      || a.key.localeCompare(b.key)),
  }));
}

/** Une leçon déplacée garde une seule identité logique : son ancienne place et sa proposition ne comptent pas deux fois. */
export function agendaCounts(events: readonly AgendaEvent[]) {
  const seen = new Set<string>();
  return events.reduce((counts, event) => {
    if (seen.has(event.logicalKey)) return counts;
    seen.add(event.logicalKey);
    counts[event.kind === 'lesson' ? 'lessons' : 'courses']++;
    return counts;
  }, { lessons: 0, courses: 0 });
}

export function agendaCountLabel(counts: { lessons: number; courses: number }, lessonsOnly = false): string {
  const parts: string[] = [];
  if (counts.lessons || lessonsOnly) parts.push(`${counts.lessons} ${counts.lessons === 1 ? 'leçon' : 'leçons'}`);
  if (counts.courses) parts.push(`${counts.courses} ${counts.courses === 1 ? 'séance collective' : 'séances collectives'}`);
  return parts.join(' · ') || '0 rendez-vous';
}

/**
 * Ce que l'école a confirmé : aucune création provisoire, aucune proposition de créneau. C'est la seule liste qu'un
 * aperçu, un compteur ou un temps de formation peut utiliser ; une intention ne change aucun total.
 */
export function agendaFacts(events: readonly AgendaEvent[]): AgendaEvent[] {
  return events.filter(event => event.kind === 'course' || (event.provisional !== true && event.mark !== 'move-proposal'));
}

/** A successful lesson read cannot certify an older or failed course/directory read. */
export function agendaReadStatus(sources: readonly { status: 'loading' | 'ready' | 'error'; data: unknown; readAt?: number }[], partial: boolean) {
  const ready = sources.every(source => source.status === 'ready' && source.data !== undefined && source.readAt !== undefined);
  return { complete: ready && !partial, readAt: ready ? Math.min(...sources.map(source => source.readAt!)) : undefined };
}
