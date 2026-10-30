import { useEffect, useRef, useState } from 'react';
import { z } from 'zod';
import { civilDateIn } from '../../agenda-model';
import { createCommand, isCivilDate, isEmail } from '../../command-core';
import { useCommandSnapshot } from '../../command-store';
import { lessonMatchesSelection, reportHistory, reportsMatchLesson } from '../../dossier-model';
import { RequestFailure } from '../../protocol';
import { administrativeProfileSchema, learnerReadinessSchema, lessonSchema, progressSchema, readAll, readSchool, recordingChoiceSchema, reportSchema, type Learner, type Lesson, type Report } from '../../school-api';
import { useCommandRunner, useConsole, useLoad, useUnsavedChanges } from '../../console/context';
import { countries, labels, profileBody, type Draft, type MissingField } from '../../console/profile-completion-model';
import { gpsConsentLabel } from '../../console/privacy-model';
import { coursePrerequisiteEvidence, learnerCourseFactsSchema, type CourseFactsRead } from '../../learner-course-facts';
import { prerequisiteHints, type PrerequisiteMoment } from '../../swiss-prerequisites';

export { countries, labels, type Draft, type MissingField };
export const levelLabels = { DISCOVERING: 'En découverte', GUIDED: 'Avec accompagnement', INDEPENDENT: 'En autonomie' } as const;
export const civil = (value: string) => new Intl.DateTimeFormat('fr-CH', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' }).format(new Date(`${value}T12:00:00Z`));
export const dateTime = (value: string, timeZone: string) => new Intl.DateTimeFormat('fr-CH', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit', timeZone }).format(new Date(value));

export function useTrainingFollowUp(trainingId: string | null) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const [year, setYear] = useState(''), [month, setMonth] = useState('');
  const loaded = useLoad(async () => {
    if (!trainingId) return null;
    const [progress, lessons] = await Promise.all([
      readSchool(schoolId, `trainings/${trainingId}/progress`, progressSchema),
      readAll(schoolId, 'lessons', lessonSchema, { trainingId }),
    ]);
    if (progress.trainingId !== trainingId || lessons.items.some(item => item.trainingId !== trainingId || item.schoolId !== schoolId)) throw new RequestFailure('INVALID_RESPONSE');
    return { progress, lessons: lessons.items, truncated: lessons.truncated };
  }, [schoolId, trainingId, revision], `${schoolId}/${trainingId ?? ''}`);
  useEffect(() => { setYear(''); setMonth(''); }, [schoolId, trainingId]);
  return { loaded, year, setYear, month, setMonth, history: reportHistory(loaded.data?.lessons ?? [], { year, month }, loaded.data?.truncated ?? false) };
}

export function usePublishedReport(lesson: Lesson | null) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    if (!lesson) return null;
    const result = await readAll(schoolId, `lessons/${lesson.id}/reports`, reportSchema);
    if (!reportsMatchLesson(result.items, lesson)) throw new RequestFailure('INVALID_RESPONSE');
    return { ...result, latest: result.items.reduce<Report | undefined>((best, item) => !best || item.sequence > best.sequence ? item : best, undefined) };
  }, [schoolId, lesson?.id, revision], `${schoolId}/${lesson?.id ?? ''}`);
  return loaded;
}

export function useExactLesson(learnerId: string | null, lessonId?: string) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  return useLoad(async () => {
    if (!learnerId || !lessonId) return null;
    const lesson = await readSchool(schoolId, `lessons/${lessonId}`, lessonSchema);
    if (!lessonMatchesSelection(lesson, { schoolId, learnerId, lessonId })) throw new RequestFailure('INVALID_RESPONSE');
    return lesson;
  }, [schoolId, learnerId, lessonId, revision], `${schoolId}/${learnerId ?? ''}/${lessonId ?? ''}`);
}

export function useProfileEditor(learner: Learner, canEdit: boolean) {
  const { schoolId, school } = useConsole();
  const { revision } = useCommandSnapshot();
  const [draft, setDraft] = useState<Draft>({});
  const [submitted, setSubmitted] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const baseVersion = useRef<number | null>(null);
  const runner = useCommandRunner(() => { setDraft({}); setSubmitted(false); setConfirming(false); baseVersion.current = null; });
  const dirty = Object.keys(draft).length > 0;
  const release = useUnsavedChanges(dirty && !runner.busy && !runner.pending);
  useEffect(() => { setDraft({}); setSubmitted(false); setConfirming(false); baseVersion.current = null; }, [learner.id]);
  const loaded = useLoad(async () => {
    const [readiness, profile] = await Promise.all([
      readSchool(schoolId, `learners/${learner.id}/action-readiness`, learnerReadinessSchema, { action: 'PLAN_LESSON' }),
      readSchool(schoolId, `learners/${learner.id}/administrative-profile`, administrativeProfileSchema),
    ]);
    if (readiness.learnerId !== learner.id || profile.learnerId !== learner.id || profile.schoolId !== schoolId) throw new RequestFailure('INVALID_RESPONSE');
    const fields = readiness.blockers.filter(item => item.code === 'PROFILE_ACTION_REQUIRED' && item.field && item.field in labels).map(item => item.field as MissingField);
    return { fields: [...new Set(fields)], profile };
  }, [schoolId, learner.id, learner.version, revision], `${schoolId}/${learner.id}`);
  const data = loaded.data;
  const update = (next: Draft) => { if (!dirty && data) baseVersion.current = data.profile.version; setDraft(next); };
  const conflict = dirty && data && baseVersion.current !== data.profile.version;
  const disabled = !canEdit || runner.busy || !!runner.pending || loaded.status !== 'ready' || !!conflict;
  const address = draft.postalAddress ?? { line1: '', postalCode: '', locality: '', countryCode: 'CH' };
  const fieldProblem = (field: Exclude<MissingField, 'postalAddress'>) => {
    const value = draft[field]?.trim();
    if (!value) return 'Renseignez cette information.';
    if (field === 'contactEmail' && !isEmail(value)) return 'Indiquez une adresse e-mail valide.';
    if (field === 'birthDate' && (!isCivilDate(value) || value > civilDateIn(school.timeZone))) return 'Indiquez une date de naissance valide, non future.';
    return null;
  };
  const invalid = !data || data.fields.some(field => field === 'postalAddress' ? Object.values(address).some(value => !value.trim()) : fieldProblem(field) !== null);
  function review() { setSubmitted(true); if (!disabled && !invalid && data && profileBody(data.fields, draft)) setConfirming(true); }
  async function save() {
    if (!data || disabled || invalid) return;
    const body = profileBody(data.fields, draft);
    if (!body) return;
    const result = await runner.run(createCommand({ schoolId, kind: 'updateAdministrativeProfile', path: `learners/${learner.id}/administrative-profile`, ifMatch: data.profile.version,
      resourceId: data.profile.id, resourceVersion: data.profile.version, body: { policyVersionId: data.profile.policyVersionId, ...body } }), 'Le profil de l’élève est à jour.');
    if (result.status !== 'rejected') setConfirming(false);
  }
  return { draft, setDraft: update, dirty, release, submitted, confirming, setConfirming, runner, loaded, data, conflict, disabled, address, fieldProblem, invalid, review, save };
}

const choicesSchema = z.object({ items: z.array(recordingChoiceSchema).max(5000) });
export function useGpsChoice(learnerId: string) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    try { return await readSchool(schoolId, 'recording-choices', choicesSchema); }
    catch (error) { if (error instanceof RequestFailure && error.status === 403) return null; throw error; }
  }, [schoolId, revision]);
  return { loaded, choice: loaded.data ? gpsConsentLabel(loaded.data.items.find(item => item.learnerId === learnerId)) : null };
}

export function usePrerequisites(learnerId: string, categoryCode: string) {
  const { schoolId, school } = useConsole();
  const { revision } = useCommandSnapshot();
  const [moment, setMoment] = useState<PrerequisiteMoment>('PRACTICAL');
  const today = civilDateIn(school.timeZone);
  const usesCourses = ['A', 'A35', 'A1', 'B', 'B1'].includes(categoryCode);
  const loaded = useLoad(async (): Promise<CourseFactsRead | null> => {
    if (!usesCourses) return null;
    try {
      const data = await readSchool(schoolId, `learners/${learnerId}/course-facts`, learnerCourseFactsSchema);
      if (data.schoolId !== schoolId || data.learnerId !== learnerId) throw new RequestFailure('INVALID_RESPONSE');
      return { status: 'READY', data };
    } catch (error) {
      if (error instanceof RequestFailure && error.status === 403) return { status: 'ACCESS_DENIED' };
      if (error instanceof RequestFailure && error.status === 404) return { status: 'NOT_FOUND' };
      throw error;
    }
  }, [schoolId, learnerId, categoryCode, usesCourses, revision], `${schoolId}/${learnerId}/${categoryCode}`);
  const read = loaded.status === 'error' ? { status: 'READ_ERROR' as const } : loaded.status === 'ready' ? loaded.data : null;
  return { loaded, read, moment, setMoment, today, hints: prerequisiteHints({ categoryCode, today, moment, evidence: read ? coursePrerequisiteEvidence(read) : {} }) };
}
