import { describe, expect, test } from 'vitest';
import { randomUUID } from 'node:crypto';
import { commandConflictKeys } from '../client/command-conflicts.js';
import { commandSpecs, createCommand } from '../client/command-core.js';
import {
  draftFromExam, emptyExamDraft, examActions, examBody, examListSchema, examProblems, examSchema, examStateSchema, resultBody, resultDraft, resultProblems, rowTitle,
  schedulableKinds, statusText, type Exam, type ExamState,
} from '../client/exam-model.js';

const zone = 'Europe/Zurich';
const exam = (patch: Partial<Exam> = {}): Exam => ({
  id: randomUUID(), trainingId: randomUUID(), kind: 'PRACTICAL', categoryCode: 'B', status: 'SCHEDULED', startsAt: '2030-03-04T09:00:00.000Z', timeZone: zone, location: 'Centre',
  escort: null, resultNote: '', resultRecordedAt: null, postponedToExamId: null, attempt: 1, needsResult: false, version: 1, createdAt: '2030-03-01T08:00:00.000Z', ...patch,
});
const state = (summary: ExamState['summary'], exams: Exam[] = []): ExamState => ({ trainingId: randomUUID(), canManage: true, escortCandidates: [], exams, summary });

describe('Examens : lecture du contrat de l’API', () => {
  test('une tentative, un état complet et une liste transversale se lisent tels que le serveur les rend', () => {
    const one = exam();
    expect(examSchema.parse(one)).toEqual(one);
    expect(() => examSchema.parse({ ...one, status: 'DONE' })).toThrow();
    const summary = [{ kind: 'THEORY' as const, passed: false, attempts: 0, scheduledExamId: null }, { kind: 'PRACTICAL' as const, passed: false, attempts: 1, scheduledExamId: one.id }];
    expect(examStateSchema.parse(state(summary, [one])).exams).toHaveLength(1);
    expect(() => examStateSchema.parse(state(summary.slice(0, 1)))).toThrow();
    expect(examListSchema.parse({ filter: 'PENDING_RESULT', items: [{ exam: one, learnerId: randomUUID(), learnerDisplayName: 'Alice' }] }).items).toHaveLength(1);
  });
});

describe('Examens : règles d’affichage', () => {
  test('une épreuve se prévoit tant qu’elle n’est ni réussie ni déjà prévue', () => {
    const open = [{ kind: 'THEORY' as const, passed: false, attempts: 0, scheduledExamId: null }, { kind: 'PRACTICAL' as const, passed: false, attempts: 2, scheduledExamId: null }];
    expect(schedulableKinds(state(open))).toEqual(['THEORY', 'PRACTICAL']);
    const closed = [{ kind: 'THEORY' as const, passed: true, attempts: 1, scheduledExamId: null }, { kind: 'PRACTICAL' as const, passed: false, attempts: 1, scheduledExamId: randomUUID() }];
    expect(schedulableKinds(state(closed))).toEqual([]);
  });

  test('la tentative se nomme à partir de la deuxième, et une date passée reste « à renseigner »', () => {
    expect(rowTitle({ kind: 'THEORY', attempt: 1 })).toBe('Examen théorique');
    expect(rowTitle({ kind: 'PRACTICAL', attempt: 3 })).toBe('Examen pratique · tentative 3');
    expect(rowTitle({ kind: 'PRACTICAL', attempt: null })).toBe('Examen pratique');
    expect(statusText({ status: 'SCHEDULED', needsResult: true }, true)).toEqual({ label: 'Résultat à renseigner', attention: true });
    expect(statusText({ status: 'SCHEDULED', needsResult: true }, false)).toEqual({ label: 'Résultat en attente', attention: true });
    expect(statusText({ status: 'ABSENT', needsResult: false }, true)).toEqual({ label: 'Absent', attention: false });
    expect(statusText({ status: 'POSTPONED', needsResult: false }, true).label).toBe('Reporté');
  });

  test('les actions suivent l’état : le résultat n’est proposé qu’une fois la date venue, un report n’en a aucune', () => {
    const now = Date.parse('2030-03-04T12:00:00.000Z');
    expect(examActions({ status: 'SCHEDULED', startsAt: '2030-03-05T09:00:00.000Z' }, now)).toEqual(['edit', 'postpone']);
    expect(examActions({ status: 'SCHEDULED', startsAt: '2030-03-04T09:00:00.000Z' }, now)).toEqual(['result', 'edit', 'postpone']);
    expect(examActions({ status: 'FAILED', startsAt: '2030-03-04T09:00:00.000Z' }, now)).toEqual(['correct']);
    expect(examActions({ status: 'POSTPONED', startsAt: '2030-03-04T09:00:00.000Z' }, now)).toEqual([]);
  });
});

describe('Examens : saisie', () => {
  test('la date se lit dans le fuseau de l’école et part en instant', () => {
    const draft = { ...emptyExamDraft(zone, Date.parse('2030-03-01T08:00:00.000Z')), start: '2030-03-04T10:00', location: '  Centre d’examen ' };
    expect(examProblems(draft, zone)).toEqual({});
    expect(examBody(draft, zone)).toEqual({ startsAt: '2030-03-04T09:00:00.000Z', timeZone: zone, location: 'Centre d’examen', escort: null });
    expect(examBody({ ...draft, start: '' }, zone)).toBeNull();
    expect(examProblems({ ...draft, start: '2030-03-31T02:30' }, zone).start).toMatch(/n’existe pas/);
    expect(examProblems({ ...draft, location: 'x'.repeat(201) }, zone).location).toBeDefined();
  });

  test('l’accompagnement exige un moniteur et un intervalle valide de 12 heures au plus', () => {
    const base = { ...emptyExamDraft(zone), start: '2030-03-04T10:00', escort: true, escortInstructor: randomUUID(), escortStart: '2030-03-04T09:00', escortEnd: '2030-03-04T11:00' };
    expect(examProblems(base, zone).escort).toBeUndefined();
    expect(examBody(base, zone)?.escort).toEqual({ instructorMembershipId: base.escortInstructor, startsAt: '2030-03-04T08:00:00.000Z', endsAt: '2030-03-04T10:00:00.000Z' });
    expect(examProblems({ ...base, escortInstructor: '' }, zone).escort).toMatch(/moniteur/);
    expect(examProblems({ ...base, escortEnd: '2030-03-04T09:00' }, zone).escort).toMatch(/suivre/);
    expect(examProblems({ ...base, escortEnd: '2030-03-04T22:00' }, zone).escort).toMatch(/12 heures/);
    expect(examProblems({ ...base, escortStart: '' }, zone).escort).toMatch(/Indiquez/);
    expect(examBody({ ...base, escort: false }, zone)?.escort).toBeNull();
  });

  test('modifier un examen reprend sa saisie, accompagnement compris', () => {
    const instructor = randomUUID();
    const draft = draftFromExam(exam({ escort: { instructorMembershipId: instructor, startsAt: '2030-03-04T08:00:00.000Z', endsAt: '2030-03-04T10:00:00.000Z' } }), zone);
    expect(draft).toMatchObject({ start: '2030-03-04T10:00', escort: true, escortInstructor: instructor, escortStart: '2030-03-04T09:00', escortEnd: '2030-03-04T11:00' });
  });

  test('un résultat se saisit, une correction exige son motif', () => {
    const first = resultDraft({ status: 'SCHEDULED', resultNote: '' });
    expect(first).toEqual({ result: 'PASSED', note: '', reason: '' });
    expect(resultBody({ ...first, result: 'FAILED', note: ' Priorités à droite ' }, false)).toEqual({ result: 'FAILED', note: 'Priorités à droite', reason: '' });
    const known = resultDraft({ status: 'FAILED', resultNote: 'Priorités' });
    expect(known).toEqual({ result: 'FAILED', note: 'Priorités', reason: '' });
    expect(resultProblems(known, true).reason).toMatch(/motif/);
    expect(resultBody(known, true)).toBeNull();
    expect(resultBody({ ...known, result: 'PASSED', reason: ' Erreur de saisie ' }, true)).toEqual({ result: 'PASSED', note: 'Priorités', reason: 'Erreur de saisie' });
    expect(resultProblems({ ...known, note: 'x'.repeat(1001), reason: 'ok' }, true).note).toBeDefined();
  });
});

describe('Examens : commandes de gestion', () => {
  test('quatre commandes, un reçu par intention, et les conflits suivent l’agenda du moniteur', () => {
    const schoolId = randomUUID(), examId = randomUUID();
    expect(commandSpecs.createExam).toMatchObject({ operationType: 'CREATE_EXAM', resourceType: 'Exam', target: 'created', expectedStatus: 201 });
    expect(commandSpecs.updateExam).toMatchObject({ operationType: 'UPDATE_EXAM', target: 'resource' });
    expect(commandSpecs.postponeExam).toMatchObject({ operationType: 'POSTPONE_EXAM', target: 'resource' });
    expect(commandSpecs.setExamResult).toMatchObject({ operationType: 'SET_EXAM_RESULT', target: 'resource' });
    const create = createCommand({ schoolId, kind: 'createExam', path: `trainings/${randomUUID()}/exams`, resourceVersion: 0, body: { kind: 'THEORY' } });
    const result = createCommand({ schoolId, kind: 'setExamResult', path: `exams/${examId}/result`, resourceId: examId, resourceVersion: 2, ifMatch: 2, body: { result: 'PASSED' } });
    expect(commandConflictKeys(create)).toEqual(['exams', 'planning']);
    expect(commandConflictKeys(result)).toEqual(['exams']);
    expect(() => createCommand({ schoolId, kind: 'setExamResult', path: `exams/${examId}/result`, resourceVersion: 2, body: {} })).toThrow();
  });
});
