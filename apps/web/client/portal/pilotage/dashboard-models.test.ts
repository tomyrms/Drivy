import { describe, expect, test } from 'vitest';
import type { AgendaEvent } from '../../console/agenda-projection';
import { dayHeading, groupByDay, upcomingAppointments } from './appointments';
import { formatSpan } from './period-model';
import { stackLayout } from './stacked-bars';
import { summarizeToday } from './today-summary';

const now = Date.parse('2026-11-02T10:00:00Z');
const context = { now, limit: 10, learnerName: (id: string) => `Élève ${id}`, memberName: (id: string) => `Moniteur ${id}` };
const lesson = (id: string, start: string, end: string, extra: Record<string, unknown> = {}) => ({
  kind: 'lesson', key: `lesson:${id}`, startsAt: start,
  lesson: { id, schoolId: 's', version: 1, trainingId: 't', learnerId: `l-${id}`, instructorMembershipId: 'm1', plannedStart: start, plannedEnd: end, timeZone: 'Europe/Zurich', meetingPoint: '', status: 'PLANNED', ...extra },
}) as unknown as AgendaEvent;
const course = (id: string, start: string, end: string, status = 'PUBLISHED') => ({
  kind: 'course', key: `course:${id}`, startsAt: start,
  series: { id, status, title: 'Sensibilisation', capacity: 10, seatsTaken: 3 },
  occurrence: { id: `${id}-o`, startsAt: start, endsAt: end, instructorDisplayName: 'Marie Dupont' },
}) as unknown as AgendaEvent;

describe('rendez-vous de l’accueil', () => {
  test('seules les leçons à faire ou à surveiller restent, avec leur phase', () => {
    const days = [{ day: '2026-11-02', items: [
      lesson('done', '2026-11-02T07:00:00Z', '2026-11-02T07:45:00Z', { status: 'COMPLETED' }),
      lesson('cancelled', '2026-11-02T08:00:00Z', '2026-11-02T08:45:00Z', { status: 'CANCELLED' }),
      lesson('absent', '2026-11-02T08:30:00Z', '2026-11-02T09:15:00Z', { status: 'NO_SHOW' }),
      lesson('waiting', '2026-11-02T09:30:00Z', '2026-11-02T10:15:00Z'),
      lesson('started', '2026-11-02T09:45:00Z', '2026-11-02T10:30:00Z', { actualStart: '2026-11-02T09:47:00Z' }),
      lesson('planned', '2026-11-02T13:00:00Z', '2026-11-02T13:45:00Z'),
    ] }];
    const result = upcomingAppointments(days, context);
    expect(result.map(item => [item.key, item.phase])).toEqual([['lesson:waiting', 'waiting'], ['lesson:started', 'started'], ['lesson:planned', 'planned']]);
    expect(result[0]).toMatchObject({ title: 'Élève l-waiting', detail: 'Moniteur m1', target: { lesson: 'waiting' } });
  });

  test('une séance collective passée ou d’un cours non publié n’est pas un rendez-vous utile', () => {
    const days = [{ day: '2026-11-03', items: [
      course('past', '2026-11-02T06:00:00Z', '2026-11-02T08:00:00Z'),
      course('draft', '2026-11-03T17:00:00Z', '2026-11-03T19:00:00Z', 'DRAFT'),
      course('cancelled', '2026-11-03T17:00:00Z', '2026-11-03T19:00:00Z', 'CANCELLED'),
      course('next', '2026-11-03T17:00:00Z', '2026-11-03T19:00:00Z'),
    ] }];
    const result = upcomingAppointments(days, context);
    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({ title: 'Sensibilisation', detail: 'Marie Dupont · 3/10 inscrits', phase: null, target: { course: 'next', occurrence: 'next-o' } });
  });

  test('la liste est bornée et regroupée par jour dans l’ordre reçu', () => {
    const days = [
      { day: '2026-11-02', items: [lesson('a', '2026-11-02T13:00:00Z', '2026-11-02T13:45:00Z'), lesson('b', '2026-11-02T14:00:00Z', '2026-11-02T14:45:00Z')] },
      { day: '2026-11-03', items: [lesson('c', '2026-11-03T13:00:00Z', '2026-11-03T13:45:00Z')] },
    ];
    expect(upcomingAppointments(days, { ...context, limit: 2 }).map(item => item.key)).toEqual(['lesson:a', 'lesson:b']);
    expect(groupByDay(upcomingAppointments(days, context)).map(group => [group.day, group.items.length])).toEqual([['2026-11-02', 2], ['2026-11-03', 1]]);
  });

  test('les jours proches ont un nom courant, les autres une date lisible', () => {
    expect(dayHeading('2026-11-02', '2026-11-02')).toBe('Aujourd’hui');
    expect(dayHeading('2026-11-03', '2026-11-02')).toBe('Demain');
    expect(dayHeading('2026-11-05', '2026-11-02')).toBe('jeudi 5 novembre');
  });
});

describe('résumé de la journée', () => {
  const measure = (value: number | null, status = 'COMPLETE') => ({ value, unit: 'count' as const, coverage: { status: status as 'COMPLETE', reasons: [] } });
  test('dit le total, puis seulement les états présents, les heures et les séances', () => {
    const summary = summarizeToday({ measures: {
      L01: measure(2), L02: measure(3), L03: measure(0), L04: measure(0), L05: measure(0), L06: measure(1), L07: measure(1), L08: measure(7),
      H01: { ...measure(19_800), unit: 'seconds' as const }, C01: measure(1),
    } });
    expect(summary.segments).toEqual(['7 leçons aujourd’hui', '2 réalisées', '1 en cours', '1 à finaliser', '3 à venir', '5 h 30 min programmées', '1 séance collective']);
    expect(summary.incomplete).toBe(false);
  });

  test('une journée vide le dit, et un total absent n’est pas un zéro', () => {
    expect(summarizeToday({ measures: { L08: measure(0) } }).segments).toEqual(['Aucune leçon aujourd’hui']);
    expect(summarizeToday({ measures: { L08: measure(1), L01: measure(1) } }).segments).toEqual(['1 leçon aujourd’hui', '1 réalisée']);
    expect(summarizeToday({ measures: { L08: measure(null, 'UNAVAILABLE') } })).toEqual({ segments: ['Leçons du jour indisponibles'], incomplete: true });
  });

  test('une mesure partielle rend le résumé incomplet', () => {
    expect(summarizeToday({ measures: { L08: measure(4), H01: { ...measure(3_600, 'PARTIAL'), unit: 'seconds' as const } } }).incomplete).toBe(true);
  });
});

describe('histogramme empilé', () => {
  test('l’échelle part de zéro, les couches s’empilent et une valeur absente ne dessine rien', () => {
    const { bars, max } = stackLayout([
      { key: 'a', label: '1', values: [2, 1] }, { key: 'b', label: '2', values: [0, 0] }, { key: 'c', label: '3', values: [null, 4] },
    ]);
    expect(max).toBe(4);
    expect(bars).toHaveLength(3);
    expect(bars[0]!.layers[0]!.height).toBeCloseTo(58);
    expect(bars[0]!.layers[1]!.height).toBeCloseTo(29);
    expect(bars[0]!.layers[1]!.y).toBeCloseTo(bars[0]!.layers[0]!.y - 29);
    expect(bars[1]!.layers.map(layer => layer.height)).toEqual([0, 0]);
    expect(bars[2]!.layers[0]!.height).toBe(0);
    expect(bars[2]!.layers[1]!.height).toBeCloseTo(116);
  });

  test('sans aucune valeur, l’échelle reste définie', () => {
    expect(stackLayout([]).max).toBe(1);
    expect(stackLayout([{ key: 'a', label: '1', values: [0] }]).bars[0]!.layers[0]!.height).toBe(0);
  });
});

describe('base de comparaison', () => {
  test('nomme la plage, avec l’année seulement si elle diffère', () => {
    expect(formatSpan('2026-10-01', '2026-10-12', '2026')).toBe('du 1 au 12 octobre');
    expect(formatSpan('2026-09-28', '2026-10-05', '2026')).toBe('du 28 septembre au 5 octobre');
    expect(formatSpan('2025-12-01', '2025-12-12', '2026')).toBe('du 1 au 12 décembre 2025');
    expect(formatSpan('2025-12-28', '2026-01-05', '2026')).toBe('du 28 décembre 2025 au 5 janvier 2026');
  });
});
