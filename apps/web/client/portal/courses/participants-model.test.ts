import { describe, expect, it } from 'vitest';
import type { CourseEnrollment, CourseSeries, CourseSheetRow } from '../../console/course-model';
import { attendanceSummary, defaultOccurrenceId, eligibility, filterByName, groupSettledCents, intentKey, offerState, readIsCurrent, rosterSplit, settledCents } from './participants-model';

const occurrence = (id: string, position: number, startsAt: string, endsAt: string) => ({ id, position, startsAt, endsAt, timeZone: 'Europe/Zurich', instructorMembershipId: 'm', instructorDisplayName: 'M', attendanceRequired: true });
const occurrences = [occurrence('a', 1, '2026-11-02T17:00:00Z', '2026-11-02T19:00:00Z'), occurrence('b', 2, '2026-11-09T17:00:00Z', '2026-11-09T19:00:00Z'), occurrence('c', 3, '2026-11-16T17:00:00Z', '2026-11-16T19:00:00Z')] as CourseSeries['occurrences'];
const row = (patch: Partial<CourseSheetRow> = {}): CourseSheetRow => ({ enrollmentId: 'e', learnerId: 'l', learnerDisplayName: 'Éloïse Müller', status: 'ACTIVE', cancelledAt: null,
  attendance: [], requirements: { required: 2, present: 2, missing: 0 }, payments: [], completion: null, ...patch });
const payment = (id: string, amountCents: number, voidedAt: string | null = null) => ({ id, amountCents, recordedAt: '2026-11-02T18:00:00Z', note: null, voidedAt, voidReason: voidedAt ? 'Erreur de saisie' : null });
const cell = (occurrenceId: string, status: 'PRESENT' | 'ABSENT' | 'EXCUSED' | null) => ({ occurrenceId, status, version: status ? 1 : null, recordedAt: status ? '2026-11-02T19:00:00Z' : null });

describe('course participants model', () => {
  it('picks the session asked for, else the next one, else the last', () => {
    const now = Date.parse('2026-11-10T00:00:00Z');
    expect(defaultOccurrenceId(occurrences, 'a', now)).toBe('a');
    expect(defaultOccurrenceId(occurrences, undefined, now)).toBe('c');
    expect(defaultOccurrenceId(occurrences, 'gone', now)).toBe('c');
    expect(defaultOccurrenceId(occurrences, undefined, Date.parse('2027-01-01T00:00:00Z'))).toBe('c');
    expect(defaultOccurrenceId([], undefined, now)).toBe('');
  });

  it('keeps unset, absent, excused and present apart and ignores cancelled enrolments', () => {
    const rows = [row({ attendance: [cell('a', 'PRESENT')] }), row({ attendance: [cell('a', 'ABSENT')] }), row({ attendance: [cell('a', 'EXCUSED')] }), row({ attendance: [] }),
      row({ status: 'CANCELLED', attendance: [cell('a', 'PRESENT')] })];
    expect(attendanceSummary(rows, 'a')).toEqual({ present: 1, absent: 1, excused: 1, unset: 1 });
    expect(attendanceSummary(rows, 'b')).toEqual({ present: 0, absent: 0, excused: 0, unset: 4 });
  });

  it('counts a payment only until it is voided, and never as a refund', () => {
    const settled = row({ payments: [payment('p1', 12000), payment('p2', 5000, '2026-11-03T08:00:00Z'), payment('p3', 250)] });
    expect(settledCents(settled)).toBe(12250);
    expect(groupSettledCents([settled, row({ payments: [payment('p4', 9500)] }), row({ status: 'CANCELLED', payments: [payment('p5', 9500)] })])).toBe(21750);
  });

  it('reads an offer deadline: proposed, expired, or simply waiting', () => {
    const now = Date.parse('2026-11-02T12:00:00Z');
    expect(offerState({ status: 'WAITING', offerExpiresAt: null }, now)).toBe('waiting');
    expect(offerState({ status: 'OFFERED', offerExpiresAt: '2026-11-03T12:00:00Z' }, now)).toBe('offered');
    expect(offerState({ status: 'OFFERED', offerExpiresAt: '2026-11-01T12:00:00Z' }, now)).toBe('expired');
  });

  it('separates active enrolments from cancelled ones, ordered by name', () => {
    const item = (id: string, name: string, status: 'ACTIVE' | 'CANCELLED') => ({ id, learnerDisplayName: name, status }) as CourseEnrollment;
    const split = rosterSplit({ items: [item('1', 'Zoé', 'ACTIVE'), item('2', 'Bruno', 'CANCELLED'), item('3', 'Ève', 'ACTIVE')] });
    expect(split.active.map(entry => entry.id)).toEqual(['3', '1']);
    expect(split.cancelled.map(entry => entry.id)).toEqual(['2']);
  });

  it('filters by name without accents and keeps the list when the query is empty', () => {
    const people = [{ learnerDisplayName: 'Éloïse Müller' }, { learnerDisplayName: 'Bruno Blanc' }];
    expect(filterByName(people, 'eloise')).toHaveLength(1);
    expect(filterByName(people, '  ')).toHaveLength(2);
    expect(filterByName(people, 'zz')).toHaveLength(0);
  });

  it('keeps validation apart from presence and payment', () => {
    const base = { status: 'ACTIVE' as const, requirements: { required: 2, present: 2, missing: 0 }, completion: null };
    expect(eligibility(base, 's')).toBe('eligible');
    expect(eligibility({ ...base, requirements: { required: 2, present: 1, missing: 1 } }, 's')).toBe('missing');
    expect(eligibility({ ...base, requirements: { required: 0, present: 0, missing: 0 } }, 's')).toBe('no-requirement');
    expect(eligibility({ ...base, completion: { id: 'c', validatedAt: '2026-11-17T08:00:00Z', seriesId: 's', revokedAt: null } }, 's')).toBe('validated');
    expect(eligibility({ ...base, completion: { id: 'c', validatedAt: '2026-11-17T08:00:00Z', seriesId: 'other', revokedAt: null } }, 's')).toBe('validated-elsewhere');
    expect(eligibility({ ...base, completion: { id: 'c', validatedAt: '2026-11-17T08:00:00Z', seriesId: 's', revokedAt: '2026-11-18T08:00:00Z' } }, 's')).toBe('eligible');
    expect(eligibility({ ...base, status: 'CANCELLED' }, 's')).toBe('cancelled');
  });

  it('never lets an older read replace a newer write, and reuses one operation id per intention', () => {
    expect(readIsCurrent(1, 2)).toBe(false);
    expect(readIsCurrent(2, 2)).toBe(true);
    expect(intentKey('s', 'recordCourseAttendance', 'p', { status: 'PRESENT' })).toBe(intentKey('s', 'recordCourseAttendance', 'p', { status: 'PRESENT' }));
    expect(intentKey('s', 'recordCourseAttendance', 'p', { status: 'PRESENT' })).not.toBe(intentKey('s', 'recordCourseAttendance', 'p', { status: 'ABSENT' }));
  });
});
