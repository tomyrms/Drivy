import { describe, expect, it } from 'vitest';
import type { AgendaEvent } from '../../console/agenda-projection';
import { calendarInterval, calendarLanes } from './calendar-layout';

function event(id: string, start: string, end: string): AgendaEvent {
  return { kind: 'lesson', key: id, startsAt: start, lesson: { id, schoolId: 'school', version: 1, trainingId: 'training', learnerId: id, instructorMembershipId: 'instructor', plannedStart: start, plannedEnd: end, timeZone: 'Europe/Zurich', meetingPoint: '', status: 'PLANNED' } };
}
describe('agenda calendar readability', () => {
  it('keeps intersecting appointments in separate lanes, then recovers the full width', () => {
    const result = calendarLanes([
      event('first', '2026-11-02T08:00:00Z', '2026-11-02T09:30:00Z'),
      event('second', '2026-11-02T08:30:00Z', '2026-11-02T09:00:00Z'),
      event('later', '2026-11-02T11:00:00Z', '2026-11-02T12:00:00Z'),
    ], 'Europe/Zurich');
    expect(result.map(item => [item.event.key, item.lane, item.lanes])).toEqual([['first', 0, 2], ['second', 1, 2], ['later', 0, 1]]);
  });
  it('protects short appointment labels from the next event', () => {
    const result = calendarLanes([event('short', '2026-11-02T08:00:00Z', '2026-11-02T08:15:00Z'), event('next', '2026-11-02T08:15:00Z', '2026-11-02T09:00:00Z')], 'Europe/Zurich');
    expect(result[0]?.lanes).toBe(2); expect(result[1]?.lane).toBe(1);
  });
  it('uses the school wall clock on either side of the daylight-saving change', () => {
    expect(calendarInterval(event('summer', '2026-10-24T07:00:00Z', '2026-10-24T08:00:00Z'), 'Europe/Zurich')).toEqual({ start: 540, end: 600 });
    expect(calendarInterval(event('winter', '2026-10-26T08:00:00Z', '2026-10-26T09:00:00Z'), 'Europe/Zurich')).toEqual({ start: 540, end: 600 });
  });
  it('keeps both occurrences of a repeated local hour visible', () => {
    const result = calendarLanes([event('first-hour', '2026-10-25T00:00:00Z', '2026-10-25T00:30:00Z'), event('second-hour', '2026-10-25T01:00:00Z', '2026-10-25T01:30:00Z')], 'Europe/Zurich');
    expect(result.map(item => [item.start, item.lane, item.lanes])).toEqual([[120, 0, 2], [120, 1, 2]]);
  });
});
