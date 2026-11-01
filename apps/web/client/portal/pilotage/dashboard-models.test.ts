import { describe, expect, test } from 'vitest';
import type { AgendaEvent } from '../../console/agenda-projection';
import { dayHeading, groupByDay, upcomingAppointments } from './appointments';
import { breakdownRows, chartBucket, chooseGranularity } from './chart-model';
import { comparisonPlan, formatSpan, resolvePeriod } from './period-model';
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
    expect(formatSpan('2026-10-01', '2026-10-12', '2026')).toBe('du 1er au 12 octobre');
    expect(formatSpan('2026-09-28', '2026-10-05', '2026')).toBe('du 28 septembre au 5 octobre');
    expect(formatSpan('2025-12-01', '2025-12-12', '2026')).toBe('du 1er au 12 décembre 2025');
    expect(formatSpan('2025-12-28', '2026-01-05', '2026')).toBe('du 28 décembre 2025 au 5 janvier 2026');
    expect(formatSpan('2026-11-01', '2026-11-01', '2026')).toBe('le 1er novembre');
    expect(formatSpan('2026-10-31', '2026-11-01', '2026')).toBe('du 31 octobre au 1er novembre');
    expect(formatSpan('2026-10-11', '2026-10-21', '2026')).toBe('du 11 au 21 octobre');
  });
});

describe('comparaison d’une période', () => {
  const today = '2026-11-02';
  const plan = (query: Parameters<typeof resolvePeriod>[0]) => comparisonPlan(resolvePeriod(query, today).period!, today);
  test('une période écoulée se compare à la précédente, un mois complet à un mois complet', () => {
    expect(plan({ period: 'previous-month' })).toEqual({ kind: 'direct', compare: 'previous-month' });
    expect(plan({ period: 'custom', start: '2026-09-01', end: '2026-09-30' })).toEqual({ kind: 'direct', compare: 'previous-month' });
    expect(plan({ period: 'custom', start: '2026-10-05', end: '2026-10-12' })).toEqual({ kind: 'direct', compare: 'equivalent-period' });
    expect(plan({ period: 'custom', start: '2026-10-20', end: '2026-11-02' })).toEqual({ kind: 'direct', compare: 'equivalent-period' });
  });

  test('le mois en cours se compare à date, une période encore ouverte ne se compare pas', () => {
    expect(plan({})).toEqual({ kind: 'to-date' });
    expect(plan({ period: 'year' })).toEqual({ kind: 'none' });
    expect(plan({ period: 'custom', start: '2026-11-01', end: '2026-11-20' })).toEqual({ kind: 'none' });
  });
});

describe('graphiques d’activité', () => {
  test('la granularité suit la durée de la période', () => {
    expect([7, 14].map(chooseGranularity)).toEqual(['day', 'day']);
    expect([15, 30, 93].map(chooseGranularity)).toEqual(['week', 'week', 'week']);
    expect([94, 365].map(chooseGranularity)).toEqual(['month', 'month']);
  });

  test('chaque intervalle a une étiquette courte et un titre complet, partiel si la période le rogne', () => {
    expect(chartBucket('day', { from: '2026-11-12', toExclusive: '2026-11-13', partial: false }, '2026', [1, 0])).toMatchObject({ label: '12', title: '12 novembre 2026', values: [1, 0] });
    const week = chartBucket('week', { from: '2026-11-09', toExclusive: '2026-11-16', partial: false }, '2026', [3, null]);
    expect(week.label).toMatch(/^9\snov\.?$/);
    expect(week.title).toBe('Semaine du 9 au 15 novembre');
    expect(chartBucket('week', { from: '2026-11-01', toExclusive: '2026-11-02', partial: true }, '2026', [0, 0]).title).toBe('Semaine le 1er novembre (partielle)');
    const month = chartBucket('month', { from: '2026-11-01', toExclusive: '2026-12-01', partial: true }, '2026', [0, 0]);
    expect(month.label).toMatch(/^nov\.?$/);
    expect(month.title).toBe('novembre 2026 (partielle)');
  });
});

describe('répartitions', () => {
  const group = (key: string, label: string | null, value: number | null, status = 'COMPLETE') =>
    ({ key, label, measures: { L01: { value, unit: 'count' as const, coverage: { status: status as 'COMPLETE', reasons: [] } } } });
  test('rangées par nom, jamais par valeur, sans zéro ni valeur absente, les non attribuées en dernier', () => {
    const rows = breakdownRows({ by: 'instructor', groups: [
      group('b', 'Simon Favre', 4), group('x', null, 9), group('a', 'Marie Dupont', 6), group('c', 'Luc Martin', 0), group('d', 'Zoé', null), group('e', 'Éric', 3, 'NOT_APPLICABLE'),
    ].map(item => item.key === 'x' ? { ...item, key: 'UNRESOLVED' } : item) }, 'L01');
    expect(rows).toEqual([{ key: 'a', label: 'Marie Dupont', value: 6 }, { key: 'b', label: 'Simon Favre', value: 4 }, { key: 'UNRESOLVED', label: 'Non attribué', value: 9 }]);
  });

  test('un permis sans libellé se nomme par son code, une mesure absente donne une liste vide', () => {
    expect(breakdownRows({ by: 'category', groups: [group('B', null, 5)] }, 'L01')).toEqual([{ key: 'B', label: 'Permis B', value: 5 }]);
    expect(breakdownRows({ by: 'category', groups: [group('B', null, 5)] }, 'H01')).toEqual([]);
    expect(breakdownRows(undefined, 'L01')).toEqual([]);
  });
});
