import { describe, expect, it } from 'vitest';
import { readJournal, updateJournal } from '../client/console/session-journal.js';
import { rebaseCourseDraft } from '../client/portal/courses/course-rebase.js';
import { defaultPart, hasDetailLines, laterCorrectionsCents } from '../client/portal/pilotage/detail-model.js';
import { metricsSchema } from '../client/portal/pilotage/metrics-schemas.js';
import { attendanceRows, canMarkAttendance, courseSheetRowSchema, type CourseSheetRow, type SeriesForm } from '../client/console/course-model.js';

describe('#430 : journal de session', () => {
  it('garde un refus écrit après le démontage de la page', () => {
    const drafts = new Map<string, unknown>();
    // La page est quittée ; la réponse tardive écrit encore, dans le journal et non dans un état démonté.
    updateJournal<string>(drafts, 'pricing/refusals', list => [...list, 'refus tarif']);
    expect(readJournal<string>(drafts, 'pricing/refusals')).toEqual(['refus tarif']);
  });
  it('relit au moment d’écrire : deux pages ne s’écrasent pas', () => {
    const drafts = new Map<string, unknown>();
    updateJournal<string>(drafts, 'k', list => [...list, 'a']);
    updateJournal<string>(drafts, 'k', list => [...list, 'b']);
    expect(readJournal<string>(drafts, 'k')).toEqual(['a', 'b']);
  });
  it('isole les écoles et les comptes : un autre magasin ne voit rien', () => {
    const ecoleA = new Map<string, unknown>(), ecoleB = new Map<string, unknown>();
    updateJournal<string>(ecoleA, 'k', list => [...list, 'secret']);
    expect(readJournal<string>(ecoleB, 'k')).toEqual([]);
  });
  it('n’écrit rien hors de la mémoire fournie', () => {
    expect(updateJournal<string>(undefined, 'k', list => [...list, 'x'])).toEqual([]);
  });
});

describe('#422 : fusion du brouillon de cours', () => {
  const base: SeriesForm = {
    typeId: 't', title: 'Cours', description: '', location: 'Salle A', conditions: '', language: 'fr', responsible: 'r', capacity: '10', minimum: '', sessions: [],
  } as unknown as SeriesForm;
  it('ne crée aucun conflit quand les champs touchés diffèrent', () => {
    const result = rebaseCourseDraft(base, { ...base, location: 'Salle B' }, { ...base, title: 'Cours du soir' });
    expect(result.fields).toEqual([]);
    expect(result.merged.title).toBe('Cours du soir');
    expect(result.merged.location).toBe('Salle B');
  });
  it('signale un champ changé des deux côtés et ne l’écrase pas en silence', () => {
    const result = rebaseCourseDraft(base, { ...base, title: 'Version école' }, { ...base, title: 'Ma saisie' });
    expect(result.fields).toEqual(['title']);
    expect(result.merged.title).toBe('Ma saisie');
    expect(result.theirs.title).toBe('Version école');
  });
});

describe('#432-#433 : détail de F06', () => {
  const card = { value: 0, lineCount: 2, parts: { voidedEntries: 0, laterCorrections: 2, laterCorrectionsCents: 4500 } };
  it('ouvre le détail selon lineCount, même quand la valeur est nulle', () => {
    expect(hasDetailLines(card)).toBe(true);
    expect(hasDetailLines({ value: 0, lineCount: 0 })).toBe(false);
    expect(hasDetailLines({ value: 1200 } as never)).toBe(true);
    expect(hasDetailLines({ value: 0 } as never)).toBe(false);
  });
  it('ouvre d’abord la partie qui contient des lignes', () => {
    expect(defaultPart('F06', card)).toBe('b');
    expect(defaultPart('F06', { parts: { voidedEntries: 3, laterCorrections: 2 } })).toBe('a');
    expect(defaultPart('F01', {} as never)).toBeUndefined();
  });
  it('montre les corrections postérieures sans changer la formule', () => {
    expect(laterCorrectionsCents('F06', card)).toBe(4500);
    expect(laterCorrectionsCents('F06', { parts: { laterCorrectionsCents: 0 } })).toBeNull();
    expect(laterCorrectionsCents('F01', card)).toBeNull();
  });
  it('conserve parts dans le schéma client', () => {
    const parsed = metricsSchema.shape.measures.parse({
      F06: { value: 0, unit: 'cents', coverage: { status: 'COMPLETE', reasons: [] }, lineCount: 2, parts: card.parts },
    });
    expect(parsed.F06?.parts).toEqual(card.parts);
    expect(parsed.F06?.lineCount).toBe(2);
  });
});

describe('#434 : cours annulé, lecture, correction et nouveaux actes', () => {
  const occurrence = 'f1111111-1111-4111-8111-111111111111', other = 'f2222222-2222-4222-8222-222222222222';
  const row = (patch: Partial<CourseSheetRow> = {}): CourseSheetRow => courseSheetRowSchema.parse({
    enrollmentId: 'e1111111-1111-4111-8111-111111111111', learnerId: '11111111-1111-4111-8111-111111111111', learnerDisplayName: 'Ana',
    status: 'ACTIVE', cancelledAt: null, attendance: [], requirements: { required: 1, present: 1, missing: 0 }, payments: [], completion: null, ...patch,
  });
  const rights = { rights: { canTakeAttendance: true, canRecordPayment: true, canValidate: true } };
  const started = '2026-11-03T17:00:00Z', now = Date.parse('2026-11-03T18:00:00Z');
  const mark = { occurrenceId: occurrence, status: 'PRESENT' as const, version: 2, recordedAt: '2026-11-03T17:30:00Z' };

  it('corrige une présence déjà marquée d’une inscription annulée après le début de la séance', () => {
    const cancelled = row({ status: 'CANCELLED', cancelledAt: '2026-11-03T17:45:00Z', attendance: [mark] });
    expect(canMarkAttendance(rights, cancelled, { id: occurrence, startsAt: started }, now)).toBe(true);
  });
  it('refuse toute nouvelle marque sur une inscription annulée', () => {
    const cancelled = row({ status: 'CANCELLED', cancelledAt: '2026-11-03T17:45:00Z', attendance: [mark] });
    expect(canMarkAttendance(rights, cancelled, { id: other, startsAt: started }, now)).toBe(false);
    expect(canMarkAttendance(rights, row({ status: 'CANCELLED', cancelledAt: '2026-11-03T17:45:00Z' }), { id: occurrence, startsAt: started }, now)).toBe(false);
  });
  it('refuse la correction quand l’annulation précède la séance (COURSE_ENROLLMENT_CLOSED)', () => {
    const before = row({ status: 'CANCELLED', cancelledAt: '2026-11-03T16:00:00Z', attendance: [mark] });
    expect(canMarkAttendance(rights, before, { id: occurrence, startsAt: started }, now)).toBe(false);
  });
  it('exige toujours le droit d’appel', () => {
    const cancelled = row({ status: 'CANCELLED', cancelledAt: '2026-11-03T17:45:00Z', attendance: [mark] });
    expect(canMarkAttendance({ rights: { ...rights.rights, canTakeAttendance: false } }, cancelled, { id: occurrence, startsAt: started }, now)).toBe(false);
  });
  it('liste dans l’appel les actifs et les annulés qui gardent une marque sur la séance', () => {
    const rows = [row(), row({ enrollmentId: 'e2222222-2222-4222-8222-222222222222', status: 'CANCELLED', cancelledAt: '2026-11-03T17:45:00Z', attendance: [mark] }),
      row({ enrollmentId: 'e3333333-3333-4333-8333-333333333333', status: 'CANCELLED', cancelledAt: '2026-11-03T17:45:00Z' })];
    expect(attendanceRows(rows, occurrence).map(item => item.enrollmentId)).toEqual(['e1111111-1111-4111-8111-111111111111', 'e2222222-2222-4222-8222-222222222222']);
  });
});
