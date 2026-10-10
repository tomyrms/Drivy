import { describe, expect, test } from 'vitest';
import { addDays, civilDateIn, dayOf, formatTimeRange, formatWeek, groupByDay, lessonPhase, lessonsOfLearners, startOfDay, weekStart, weekWindow } from '../client/agenda-model.js';

describe('Agenda : heure prévue distincte du démarrage enregistré', () => {
  const lesson = { status: 'PLANNED', plannedStart: '2026-10-09T12:00:00Z', plannedEnd: '2026-10-09T13:00:00Z', actualStart: null };
  test('à 14 h 30, la leçon de 14 h reste en attente tant que personne ne la démarre', () => {
    expect(lessonPhase(lesson, Date.parse('2026-10-09T11:59:00Z'))).toBe('planned');
    expect(lessonPhase(lesson, Date.parse('2026-10-09T12:30:00Z'))).toBe('waiting');
    expect(lessonPhase(lesson, Date.parse('2026-10-10T12:30:00Z'))).toBe('waiting');
  });
  test('seul un démarrage enregistré autorise En cours puis À terminer', () => {
    const started = { ...lesson, actualStart: '2026-10-09T12:05:00Z' };
    expect(lessonPhase(started, Date.parse('2026-10-09T12:30:00Z'))).toBe('started');
    expect(lessonPhase(started, Date.parse('2026-10-09T13:00:00Z'))).toBe('to-finish');
    expect(lessonPhase({ ...lesson, actualStart: 'invalid' }, Date.parse('2026-10-09T12:30:00Z'))).toBe('waiting');
  });
  test.each([['COMPLETED', 'completed'], ['CANCELLED', 'cancelled'], ['NO_SHOW', 'absent']] as const)('préserve le constat %s', (status, expected) => {
    expect(lessonPhase({ ...lesson, status, actualStart: '2026-10-09T12:05:00Z' }, Date.parse('2026-10-10T12:30:00Z'))).toBe(expected);
  });
});

describe('Agenda : recherche d’un élève dans la semaine', () => {
  const learners = [{ id: 'a', displayName: 'Élodie Müller' }, { id: 'b', displayName: 'Noé Favre' }];
  const lessons = [{ id: '1', learnerId: 'a' }, { id: '2', learnerId: 'b' }, { id: '3', learnerId: 'inconnu' }, { id: '4', learnerId: 'a' }];
  test('sans recherche, toutes les leçons restent, même celles d’un élève absent de la liste', () => {
    expect(lessonsOfLearners(lessons, learners, '  ').map(lesson => lesson.id)).toEqual(['1', '2', '3', '4']);
  });
  test('la recherche ignore accents et casse et ne garde que les leçons de l’élève trouvé', () => {
    expect(lessonsOfLearners(lessons, learners, 'elodie').map(lesson => lesson.id)).toEqual(['1', '4']);
    expect(lessonsOfLearners(lessons, learners, 'FAVRE').map(lesson => lesson.id)).toEqual(['2']);
    expect(lessonsOfLearners(lessons, learners, 'personne')).toEqual([]);
  });
});

describe('Agenda : semaine dans le fuseau de l’école', () => {
  test('le calcul de dates civiles traverse mois et années', () => {
    expect(addDays('2026-09-28', 7)).toBe('2026-10-05');
    expect(addDays('2026-12-30', 3)).toBe('2027-01-02');
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28');
  });

  test('la semaine commence le lundi', () => {
    expect(weekStart('2026-09-28')).toBe('2026-09-28');
    expect(weekStart('2026-10-04')).toBe('2026-09-28');
    expect(weekStart('2026-10-05')).toBe('2026-10-05');
    expect(weekStart('2027-01-01')).toBe('2026-12-28');
  });

  test('les bornes sont celles de minuit à Zurich, changement d’heure compris', () => {
    expect(weekWindow('2026-09-28', 'Europe/Zurich')).toEqual({ from: '2026-09-27T22:00:00.000Z', to: '2026-10-04T22:00:00.000Z' });
    // Fin de l’heure d’été le 25 octobre 2026 : la semaine dure une heure de plus.
    const change = weekWindow('2026-10-19', 'Europe/Zurich')!;
    expect(change).toEqual({ from: '2026-10-18T22:00:00.000Z', to: '2026-10-25T23:00:00.000Z' });
    expect((Date.parse(change.to) - Date.parse(change.from)) / 3_600_000).toBe(169);
    expect(weekWindow('2026-02-30', 'Europe/Zurich')).toBeNull();
    expect(weekWindow('2026-09-28', 'Nulle/Part')).toBeNull();
  });

  test('minuit sauté par un changement d’heure : le jour commence à la première heure qui existe', () => {
    // Téhéran a avancé ses horloges de 00:00 à 01:00 le lundi 22 mars 2021 : sans repli, la semaine devenait illisible.
    expect(startOfDay('2021-03-22', 'Asia/Tehran')).toBe('2021-03-21T20:30:00.000Z');
    expect(weekWindow('2021-03-22', 'Asia/Tehran')).toEqual({ from: '2021-03-21T20:30:00.000Z', to: '2021-03-28T19:30:00.000Z' });
    expect(weekWindow('2021-03-15', 'Asia/Tehran')).toEqual({ from: '2021-03-14T20:30:00.000Z', to: '2021-03-21T20:30:00.000Z' });
    expect(startOfDay('2026-10-19', 'Europe/Zurich')).toBe('2026-10-18T22:00:00.000Z');
    expect(startOfDay('2026-10-19', 'Nulle/Part')).toBeNull();
  });

  test('un jour se lit à l’heure de l’école, pas en UTC', () => {
    expect(dayOf('2026-09-28T22:30:00.000Z', 'Europe/Zurich')).toBe('2026-09-29');
    expect(dayOf('2026-09-28T22:30:00.000Z', 'UTC')).toBe('2026-09-28');
    expect(civilDateIn('Europe/Zurich', Date.parse('2026-12-31T23:30:00.000Z'))).toBe('2027-01-01');
  });

  test('les leçons sont groupées par jour local et triées', () => {
    const lessons = [
      { id: 'c', plannedStart: '2026-09-29T07:00:00.000Z' }, { id: 'a', plannedStart: '2026-09-28T06:00:00.000Z' },
      { id: 'd', plannedStart: '2026-09-28T22:30:00.000Z' }, { id: 'b', plannedStart: '2026-09-28T13:00:00.000Z' },
    ];
    const days = groupByDay(lessons, 'Europe/Zurich');
    expect(days.map(day => day.day)).toEqual(['2026-09-28', '2026-09-29']);
    expect(days[0]!.items.map(item => item.id)).toEqual(['a', 'b']);
    expect(days[1]!.items.map(item => item.id)).toEqual(['d', 'c']);
    expect(groupByDay([], 'Europe/Zurich')).toEqual([]);
  });

  test('libellés : plage horaire de l’école et semaine', () => {
    expect(formatTimeRange('2026-09-28T06:00:00.000Z', '2026-09-28T07:00:00.000Z', 'Europe/Zurich')).toBe('08:00–09:00');
    expect(formatWeek('2026-09-28')).toContain('2026');
    expect(formatWeek('2026-09-28')).toContain('28');
    expect(formatWeek('2026-09-28')).toContain('4 octobre');
  });
});
