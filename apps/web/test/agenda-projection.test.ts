import { describe, expect, it } from 'vitest';
import { agendaCountLabel, agendaCounts, agendaDays, agendaReadStatus } from '../client/console/agenda-projection.js';
import type { Lesson } from '../client/school-api.js';
import type { CourseSeries } from '../client/console/course-model.js';

const options = { timeZone: 'Europe/Zurich', from: '2026-10-25T23:00:00Z', to: '2026-11-01T23:00:00Z', instructor: '', includeCourses: true };
const lesson = (id: string, plannedStart = '2026-10-26T10:00:00Z', instructorMembershipId = 'a'): Lesson => ({ id, plannedStart,
  plannedEnd: new Date(Date.parse(plannedStart) + 3600000).toISOString(), instructorMembershipId, schoolId: 'school', learnerId: 'learner',
  trainingId: 'training', version: 1, timeZone: 'Europe/Zurich', meetingPoint: '', status: 'PLANNED' });
const series = (id: string, sessions: [string, string, string][], status: CourseSeries['status'] = 'PUBLISHED'): CourseSeries => ({ id, schoolId: 'school', version: 1,
  status, typeId: 'type', typeTitle: 'Sensibilisation', title: 'Cours', description: '', location: '', conditions: '', teachingLanguage: 'fr',
  responsibleMembershipId: 'a', responsibleDisplayName: 'A', capacity: 10, seatsTaken: 0, remainingSeats: 10, minParticipants: null,
  policyVersion: 1, selfCancelHours: 24, selfCancellationDeadline: options.from, firstStartsAt: sessions[0]![1], lastEndsAt: options.to,
  totalMinutes: 60, publishedAt: options.from, canManage: true,
  occurrences: sessions.map(([occurrenceId, startsAt, instructorMembershipId], i) => ({ id: occurrenceId, position: i + 1, startsAt,
    endsAt: new Date(Date.parse(startsAt) + 3600000).toISOString(), timeZone: 'Europe/Zurich', instructorMembershipId, instructorDisplayName: instructorMembershipId, attendanceRequired: true })),
});
const courses = [series('s', [['morning', '2026-10-26T08:00:00Z', 'a'], ['afternoon', '2026-10-26T13:00:00Z', 'b'], ['next', '2026-10-27T08:00:00Z', 'a']])];

describe('agenda mixte autorisé', () => {
  it('intercale les séances et leçons, avec les mêmes compteurs par jour et semaine', () => {
    const days = agendaDays([lesson('l')], courses, options);
    expect(days[0]!.items.map(event => event.key)).toEqual(['course:s:morning', 'lesson:l', 'course:s:afternoon']);
    expect(agendaCountLabel(agendaCounts(days[0]!.items))).toBe('1 leçon · 2 séances collectives');
    expect(agendaCountLabel(agendaCounts(days[1]!.items))).toBe('1 séance collective');
    expect(agendaCounts(days.flatMap(day => day.items))).toEqual({ lessons: 1, courses: 3 });
  });
  it('filtre le moniteur de chaque séance, pas le responsable de série', () => {
    const days = agendaDays([lesson('a'), lesson('b', undefined, 'b')], courses, { ...options, instructor: 'b' });
    expect(days.flatMap(day => day.items).map(event => event.key)).toEqual(['lesson:b', 'course:s:afternoon']);
  });
  it('une recherche élève exclut les cours, pas un filtre moniteur', () => {
    expect(agendaDays([lesson('l')], courses, { ...options, includeCourses: false }).flatMap(day => day.items).map(event => event.kind)).toEqual(['lesson']);
    expect(agendaCountLabel({ lessons: 0, courses: 0 }, true)).toBe('0 leçons');
  });
  it('conserve états, identité, égalités déterministes et dédoublonne chaque occurrence', () => {
    const cancelled = series('cancelled', [['l', '2026-10-26T10:00:00Z', 'a']], 'CANCELLED');
    const draft = series('draft', [['l', '2026-10-26T10:00:00Z', 'a']], 'DRAFT');
    const forward = agendaDays([lesson('l')], [cancelled, draft, cancelled], options);
    const reverse = agendaDays([lesson('l')], [draft, cancelled], options);
    expect(forward).toEqual(reverse);
    expect(forward[0]!.items).toHaveLength(3);
    expect(forward[0]!.items.filter(event => event.kind === 'course').map(event => event.series.status)).toEqual(['CANCELLED', 'DRAFT']);
  });
  it('à départ égal, trie par fin puis identité comme le calendrier natif', () => {
    const longCourse = series('a', [['session', '2026-10-26T10:00:00Z', 'a']]);
    longCourse.occurrences[0]!.endsAt = '2026-10-26T12:00:00Z';
    const shortLesson = lesson('z');
    shortLesson.plannedEnd = '2026-10-26T10:30:00Z';
    const days = agendaDays([lesson('b'), shortLesson], [longCourse], options);
    expect(days[0]!.items.map(event => event.key)).toEqual(['lesson:z', 'lesson:b', 'course:a:session']);
  });
  it('borne les occurrences et groupe dans le fuseau, y compris après changement d’heure', () => {
    const boundary = series('boundary', [['inside', '2026-10-25T23:30:00Z', 'a'], ['outside', options.to, 'a']]);
    const days = agendaDays([], [boundary], options);
    expect(days.map(day => day.day)).toEqual(['2026-10-26']);
    expect(days[0]!.items.map(event => event.key)).toEqual(['course:boundary:inside']);
  });
});

describe('fraîcheur réelle de toutes les sources', () => {
  const read = (readAt: number) => ({ status: 'ready' as const, data: [], readAt });
  it('utilise la plus ancienne lecture nécessaire, jamais celle des seules leçons', () => {
    expect(agendaReadStatus([read(300), read(100), read(200)], false)).toEqual({ complete: true, readAt: 100 });
  });
  it('ne déclare pas complet un chargement, un échec conservé ou une collection tronquée', () => {
    expect(agendaReadStatus([read(300), { ...read(100), status: 'error' }], false)).toEqual({ complete: false, readAt: undefined });
    expect(agendaReadStatus([read(300), { status: 'loading', data: undefined }], false).complete).toBe(false);
    expect(agendaReadStatus([read(300), read(100)], true)).toEqual({ complete: false, readAt: 100 });
  });
});
