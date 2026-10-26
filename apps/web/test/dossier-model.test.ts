import { describe, expect, it } from 'vitest';
import { lessonMatchesSelection, reportHistory, reportsMatchLesson } from '../client/dossier-model.js';

const lesson = (id: string, plannedStart: string, timeZone: string, published = true) => ({
  id, plannedStart, timeZone, currentPublishedRevisionId: published ? `${id}-report` : null,
});
const ids = (lessons: { id: string }[]) => lessons.map(item => item.id);

describe('Contexte exact de leçon', () => {
  const response = { id: 'lesson', schoolId: 'school', learnerId: 'learner' };
  const selection = { lessonId: 'lesson', schoolId: 'school', learnerId: 'learner' };
  it('n’accepte que le rendez-vous, l’école et l’élève demandés', () => {
    expect(lessonMatchesSelection(response, selection)).toBe(true);
    for (const field of ['id', 'schoolId', 'learnerId'] as const) expect(lessonMatchesSelection({ ...response, [field]: 'another' }, selection)).toBe(false);
  });
  it('refuse un bilan d’une autre leçon, même dans la même école', () => {
    const reports = [{ lessonId: response.id, schoolId: response.schoolId }];
    expect(reportsMatchLesson(reports, response)).toBe(true);
    expect(reportsMatchLesson([...reports, { ...reports[0]!, lessonId: 'other' }], response)).toBe(false);
    expect(reportsMatchLesson([{ ...reports[0]!, schoolId: 'other' }], response)).toBe(false);
  });
});

describe('Historique des bilans par période', () => {
  const sameInstant = [
    lesson('zurich', '2026-09-30T22:30:00.000Z', 'Europe/Zurich'),
    lesson('new-york', '2026-09-30T22:30:00.000Z', 'America/New_York'),
  ];

  it('classe le même instant en octobre à Zurich et en septembre à New York', () => {
    expect(ids(reportHistory(sameInstant, { year: '', month: '10' }, false).filtered)).toEqual(['zurich']);
    expect(ids(reportHistory(sameInstant, { year: '', month: '09' }, false).filtered)).toEqual(['new-york']);
  });

  it('combine mois et année sans confondre les années et utilise le fuseau historique à minuit', () => {
    const lessons = [
      ...sameInstant,
      lesson('previous-october', '2025-10-12T12:00:00.000Z', 'Europe/Zurich'),
      lesson('new-year-zurich', '2025-12-31T23:30:00.000Z', 'Europe/Zurich'),
      lesson('new-year-new-york', '2025-12-31T23:30:00.000Z', 'America/New_York'),
    ];
    expect(ids(reportHistory(lessons, { year: '2026', month: '10' }, false).filtered)).toEqual(['zurich']);
    expect(ids(reportHistory(lessons, { year: '', month: '10' }, false).filtered)).toEqual(['zurich', 'previous-october']);
    expect(ids(reportHistory(lessons, { year: '2026', month: '' }, false).filtered)).toEqual(['zurich', 'new-york', 'new-year-zurich']);
    expect(reportHistory([lessons[3]!], { year: '', month: '' }, false).years).toEqual(['2026']);
    expect(reportHistory([lessons[4]!], { year: '', month: '' }, false).years).toEqual(['2025']);
  });

  it('ne présente pas une absence de bilan déduite d’un historique partiel', () => {
    const result = reportHistory(sameInstant, { year: '2024', month: '02' }, true);
    expect(result.canFilter).toBe(false);
    expect(ids(result.filtered)).toEqual(['zurich', 'new-york']);
  });

  it('n’inclut que les leçons avec un bilan publié, sans modifier la liste reçue', () => {
    const lessons = [lesson('without-report', '2027-03-12T12:00:00.000Z', 'Europe/Zurich', false), ...sameInstant];
    const original = [...lessons];
    const result = reportHistory(lessons, { year: '', month: '' }, false);
    expect(result.years).toEqual(['2026']);
    expect(ids(result.reported)).toEqual(['zurich', 'new-york']);
    expect(lessons).toEqual(original);
  });
});
