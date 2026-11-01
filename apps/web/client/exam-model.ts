import { z } from 'zod';
import { instantToSchoolTime, schoolTimeToInstant } from './command-core.js';

/**
 * Examens théorique et pratique d'une formation (#54), côté gestion web. Règles pures, sans DOM ni réseau : le serveur reste le seul
 * juge, ces règles évitent un aller-retour inutile et nomment un refus près de son champ. Une date passée n'est jamais un résultat.
 */
const id = z.string().uuid();
const timestamp = z.string().datetime({ offset: true });

export type ExamKind = 'THEORY' | 'PRACTICAL';
export type ExamStatus = 'SCHEDULED' | 'POSTPONED' | 'ABSENT' | 'PASSED' | 'FAILED';
export const examKinds: readonly ExamKind[] = ['THEORY', 'PRACTICAL'];
export const examKindLabels: Record<ExamKind, string> = { THEORY: 'Examen théorique', PRACTICAL: 'Examen pratique' };
export const examStatusLabels: Record<ExamStatus, string> = { SCHEDULED: 'Prévu', POSTPONED: 'Reporté', ABSENT: 'Absent', PASSED: 'Réussi', FAILED: 'Échoué' };
export const EXAM_TEXT_LIMIT = 1000;
export const EXAM_LOCATION_LIMIT = 200;

const escortSchema = z.object({ instructorMembershipId: id, startsAt: timestamp, endsAt: timestamp });
export const examSchema = z.object({
  id, trainingId: id, kind: z.enum(['THEORY', 'PRACTICAL']), categoryCode: z.string(), status: z.enum(['SCHEDULED', 'POSTPONED', 'ABSENT', 'PASSED', 'FAILED']),
  startsAt: timestamp, timeZone: z.string(), location: z.string(), escort: escortSchema.nullable(), resultNote: z.string(), resultRecordedAt: timestamp.nullable(),
  postponedToExamId: id.nullable(), attempt: z.number().int().positive().nullable(), needsResult: z.boolean(), version: z.number().int().positive(), createdAt: timestamp,
});
export type Exam = z.infer<typeof examSchema>;
export const examStateSchema = z.object({
  trainingId: id, canManage: z.boolean(),
  escortCandidates: z.array(z.object({ membershipId: id, displayName: z.string() })).max(50),
  exams: z.array(examSchema).max(100),
  summary: z.array(z.object({ kind: z.enum(['THEORY', 'PRACTICAL']), passed: z.boolean(), attempts: z.number().int().min(0), scheduledExamId: id.nullable() })).length(2),
});
export type ExamState = z.infer<typeof examStateSchema>;
export const examListSchema = z.object({
  filter: z.enum(['PENDING_RESULT', 'UPCOMING']),
  items: z.array(z.object({ exam: examSchema, learnerId: id, learnerDisplayName: z.string() })).max(100),
});
export type ExamListItem = z.infer<typeof examListSchema>['items'][number];

/** Une épreuve se prévoit tant qu'elle n'est ni réussie ni déjà prévue. */
export function schedulableKinds(state: ExamState): ExamKind[] {
  return examKinds.filter(kind => {
    const summary = state.summary.find(item => item.kind === kind);
    return !!summary && !summary.passed && summary.scheduledExamId === null;
  });
}

export function rowTitle(exam: Pick<Exam, 'kind' | 'attempt'>): string {
  return exam.attempt && exam.attempt > 1 ? `${examKindLabels[exam.kind]} · tentative ${exam.attempt}` : examKindLabels[exam.kind];
}

/** Ce que la ligne dit de l'état : le résultat manquant d'une date passée est le seul signal, le reste se lit à son mot. */
export function statusText(exam: Pick<Exam, 'status' | 'needsResult'>, canManage: boolean): { label: string; attention: boolean } {
  if (exam.needsResult) return { label: canManage ? 'Résultat à renseigner' : 'Résultat en attente', attention: true };
  return { label: examStatusLabels[exam.status], attention: false };
}

/** Actions proposées au personnel pour un examen : un examen reporté n'en a aucune. */
export function examActions(exam: Pick<Exam, 'status' | 'startsAt'>, now = Date.now()): ('result' | 'edit' | 'postpone' | 'correct')[] {
  if (exam.status === 'SCHEDULED') return [...(Date.parse(exam.startsAt) <= now ? ['result' as const] : []), 'edit', 'postpone'];
  if (exam.status === 'PASSED' || exam.status === 'FAILED' || exam.status === 'ABSENT') return ['correct'];
  return [];
}

export interface ExamDraft { start: string; location: string; escort: boolean; escortInstructor: string; escortStart: string; escortEnd: string; reason: string }
export function emptyExamDraft(timeZone: string, now = Date.now()): ExamDraft {
  const start = instantToSchoolTime(new Date(Math.ceil((now + 7 * 86_400_000) / 3_600_000) * 3_600_000).toISOString(), timeZone);
  return { start, location: '', escort: false, escortInstructor: '', escortStart: '', escortEnd: '', reason: '' };
}
export function draftFromExam(exam: Exam, timeZone: string): ExamDraft {
  return {
    start: instantToSchoolTime(exam.startsAt, timeZone), location: exam.location, escort: !!exam.escort, escortInstructor: exam.escort?.instructorMembershipId ?? '',
    escortStart: exam.escort ? instantToSchoolTime(exam.escort.startsAt, timeZone) : '', escortEnd: exam.escort ? instantToSchoolTime(exam.escort.endsAt, timeZone) : '', reason: '',
  };
}
export interface ExamProblems { start?: string; location?: string; escort?: string; reason?: string }
export function examProblems(draft: ExamDraft, timeZone: string): ExamProblems {
  const problems: ExamProblems = {};
  if (!draft.start) problems.start = 'Indiquez la date et l’heure.';
  else if (!schoolTimeToInstant(draft.start, timeZone)) problems.start = 'Cette heure n’existe pas dans le fuseau de l’école.';
  if ([...draft.location].length > EXAM_LOCATION_LIMIT) problems.location = `${EXAM_LOCATION_LIMIT} caractères au plus.`;
  if ([...draft.reason].length > EXAM_TEXT_LIMIT) problems.reason = `${EXAM_TEXT_LIMIT} caractères au plus.`;
  if (draft.escort) {
    const start = draft.escortStart ? schoolTimeToInstant(draft.escortStart, timeZone) : null, end = draft.escortEnd ? schoolTimeToInstant(draft.escortEnd, timeZone) : null;
    if (!draft.escortInstructor) problems.escort = 'Choisissez le moniteur qui accompagne.';
    else if (!start || !end) problems.escort = 'Indiquez le début et la fin de l’accompagnement.';
    else if (Date.parse(end) <= Date.parse(start)) problems.escort = 'La fin doit suivre le début.';
    else if (Date.parse(end) - Date.parse(start) > 12 * 3_600_000) problems.escort = 'L’accompagnement dure 12 heures au plus.';
  }
  return problems;
}
/** Corps commun de la création, de la modification et du report ; null tant que la saisie est incomplète. */
export function examBody(draft: ExamDraft, timeZone: string) {
  if (Object.keys(examProblems(draft, timeZone)).length) return null;
  const startsAt = schoolTimeToInstant(draft.start, timeZone);
  if (!startsAt) return null;
  const escort = draft.escort
    ? { instructorMembershipId: draft.escortInstructor, startsAt: schoolTimeToInstant(draft.escortStart, timeZone)!, endsAt: schoolTimeToInstant(draft.escortEnd, timeZone)! }
    : null;
  return { startsAt, timeZone, location: draft.location.trim(), escort };
}

export type ResultChoice = 'PASSED' | 'FAILED' | 'ABSENT';
export const resultLabels: Record<ResultChoice, string> = { PASSED: 'Réussi', FAILED: 'Échoué', ABSENT: 'Absent' };
export interface ResultDraft { result: ResultChoice; note: string; reason: string }
export function resultDraft(exam: Pick<Exam, 'status' | 'resultNote'>): ResultDraft {
  const known = exam.status === 'PASSED' || exam.status === 'FAILED' || exam.status === 'ABSENT';
  return { result: known ? exam.status as ResultChoice : 'PASSED', note: exam.resultNote, reason: '' };
}
export interface ResultProblems { note?: string; reason?: string }
/** Corriger un résultat déjà saisi exige un motif. */
export function resultProblems(draft: ResultDraft, correcting: boolean): ResultProblems {
  const problems: ResultProblems = {};
  if ([...draft.note].length > EXAM_TEXT_LIMIT) problems.note = `${EXAM_TEXT_LIMIT} caractères au plus.`;
  if (correcting && !draft.reason.trim()) problems.reason = 'Indiquez le motif de la correction.';
  else if ([...draft.reason].length > EXAM_TEXT_LIMIT) problems.reason = `${EXAM_TEXT_LIMIT} caractères au plus.`;
  return problems;
}
export function resultBody(draft: ResultDraft, correcting: boolean) {
  if (Object.keys(resultProblems(draft, correcting)).length) return null;
  return { result: draft.result, note: draft.note.trim(), reason: draft.reason.trim() };
}
