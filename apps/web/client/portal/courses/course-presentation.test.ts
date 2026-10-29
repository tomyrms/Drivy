import { describe, expect, it } from 'vitest';
import type { CourseSeries, SeriesForm, SessionForm } from '../../console/course-model';
import { changedSessions, civilDayLabel, formSignature, isSessionRefusal, languageLabel, seriesStateLabel, seriesSummary, sessionMinutes } from './course-presentation';

const session = (key: string, patch: Partial<SessionForm> = {}): SessionForm => ({ key, date: '2026-11-04', start: '18:00', end: '20:00', instructor: 'marie', attendanceRequired: true, ...patch });
const form = (sessions: SessionForm[]): SeriesForm => ({ typeId: 't', title: 'Cours', description: '', location: '', conditions: '', language: 'fr', responsible: 'luc', capacity: '12', minimum: '', sessions });
const occurrence = (id: string, position: number, startsAt: string, endsAt: string) => ({ id, position, startsAt, endsAt, timeZone: 'Europe/Zurich', instructorMembershipId: 'marie', instructorDisplayName: 'Marie', attendanceRequired: true });

describe('collective course presentation', () => {
  it('labels only the states worth a badge', () => {
    const base = { status: 'PUBLISHED' as const, lastEndsAt: '2026-12-01T10:00:00Z' };
    expect(seriesStateLabel(base, Date.parse('2026-11-01T00:00:00Z'))).toBeNull();
    expect(seriesStateLabel(base, Date.parse('2026-12-02T00:00:00Z'))).toBe('Terminé');
    expect(seriesStateLabel({ ...base, status: 'DRAFT' })).toBe('Brouillon');
    expect(seriesStateLabel({ ...base, status: 'CANCELLED' })).toBe('Annulé');
    expect(languageLabel('de')).toBe('Allemand');
    expect(languageLabel(null)).toBeNull();
  });

  it('summarises a series in the school time zone, in date order', () => {
    const series = { totalMinutes: 240, occurrences: [occurrence('b', 2, '2026-11-11T17:00:00Z', '2026-11-11T19:00:00Z'), occurrence('a', 1, '2026-11-04T17:00:00Z', '2026-11-04T19:00:00Z')] } as unknown as CourseSeries;
    expect(seriesSummary(series, 'Europe/Zurich')).toMatch(/^2 séances · 4 h · mer\. 4 nov\. 2026 – mer\. 11 nov\. 2026$/);
    expect(seriesSummary({ ...series, occurrences: [series.occurrences[1]!] } as CourseSeries, 'Europe/Zurich')).toMatch(/^1 séance · 4 h · mer\. 4 nov\. 2026$/);
    expect(civilDayLabel('')).toBe('Date à choisir');
  });

  it('compares drafts by content: session keys and order do not matter', () => {
    const left = form([session('s1'), session('s2', { date: '2026-11-11' })]);
    const right = form([session('x2', { date: '2026-11-11' }), session('x1')]);
    expect(formSignature(left)).toBe(formSignature(right));
    expect(formSignature(left)).not.toBe(formSignature(form([session('s1'), session('s2', { date: '2026-11-12' })])));
  });

  it('finds the sessions moved by a reschedule, by position', () => {
    const before = [session('a'), session('b', { date: '2026-11-11' })];
    const after = [session('a'), session('b', { date: '2026-11-18' })];
    expect([...changedSessions(before, after)]).toEqual(['b']);
    expect(changedSessions(before, before).size).toBe(0);
  });

  it('measures a typed session and rejects an hour that does not exist', () => {
    expect(sessionMinutes(session('a'), 'Europe/Zurich')).toBe(120);
    expect(sessionMinutes(session('a', { date: '2026-03-29', start: '02:30', end: '03:30' }), 'Europe/Zurich')).toBeNull();
    expect(sessionMinutes(session('a', { end: '' }), 'Europe/Zurich')).toBeNull();
  });

  it('routes schedule refusals beside the sessions', () => {
    expect(isSessionRefusal('COURSE_INSTRUCTOR_CONFLICT')).toBe(true);
    expect(isSessionRefusal('VERSION_CONFLICT')).toBe(false);
    expect(isSessionRefusal(undefined)).toBe(false);
  });
});
