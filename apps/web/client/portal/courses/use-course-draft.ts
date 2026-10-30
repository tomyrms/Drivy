import { useEffect, useMemo, useRef, useState } from 'react';
import { createCommand } from '../../command-core';
import { courseErrorMessage, emptyForm, emptySession, formFromSeries, hasProblems, LIMITS, preview, seriesBody, validate,
  type CourseCatalogue, type CourseSeries, type CourseType, type SeriesForm, type SessionForm } from '../../console/course-model';
import { useCommandRunner, useConsole, useUnsavedChanges } from '../../console/context';
import { confirmedSeries } from './course-catalogue';
import { formSignature } from './course-presentation';

/** One composition at a time: the series, a single session, or the review before publication. */
export type DraftStage = { kind: 'course' } | { kind: 'session'; key: string } | { kind: 'review' };
export interface Refusal { code: string; message: string }

/**
 * Draft of a series. State and commands only: every write goes through the shared command engine (version and operation id
 * kept), nothing is shown as saved before the school's receipt, and a refusal keeps the whole draft.
 */
export function useCourseDraft(series: CourseSeries | null, catalogue: CourseCatalogue, done: (series: CourseSeries | null, message: string) => void) {
  const { schoolId, school, membership } = useConsole();
  const timeZone = school.timeZone;
  const [current, setCurrent] = useState(series);
  // A re-read after a version conflict supplies the version to send next; the typed draft is never replaced.
  useEffect(() => { if (series && (!current || series.version > current.version)) setCurrent(series); }, [series]);
  const initial = useMemo(() => series ? formFromSeries(series, timeZone)
    : emptyForm(catalogue, catalogue.instructors.some(item => item.membershipId === membership.membershipId) ? membership.membershipId : ''), []);
  const [form, setForm] = useState<SeriesForm>(initial);
  const [stage, setStage] = useState<DraftStage>({ kind: 'course' });
  const [touched, setTouched] = useState(false);
  const [refusal, setRefusal] = useState<Refusal | null>(null);
  const [addedTypes, setAddedTypes] = useState<CourseType[]>([]);
  const runner = useCommandRunner();
  const guard = useRef(false);
  const saved = useMemo(() => current ? formSignature(formFromSeries(current, timeZone)) : formSignature(emptyForm(catalogue, initial.responsible)), [current, timeZone]);
  const dirty = formSignature(form) !== saved;
  const pendingKind = runner.pending?.meta.kind;
  const sent = pendingKind === 'createCourseSeries' || pendingKind === 'updateCourseSeries' || pendingKind === 'publishCourseSeries';
  const releaseGuard = useUnsavedChanges(dirty && !sent);
  const locked = runner.busy || Boolean(runner.pending);
  const problems = validate(form, timeZone);
  const shown = touched ? problems : { fields: {}, sessions: {} };
  const overview = preview(form, timeZone);
  const types = useMemo(() => [...catalogue.types, ...addedTypes.filter(type => !catalogue.types.some(item => item.id === type.id))], [catalogue.types, addedTypes]);
  const instructorOptions = catalogue.instructors.map(item => ({ value: item.membershipId, label: item.displayName }));
  // Responsible: the school's instructors, the signed-in member and the current responsible, so no saved value disappears.
  const responsibleOptions = useMemo(() => {
    const options = [...instructorOptions];
    if (series && !options.some(item => item.value === series.responsibleMembershipId)) options.push({ value: series.responsibleMembershipId, label: series.responsibleDisplayName || 'Responsable actuel' });
    if (!options.some(item => item.value === membership.membershipId)) options.push({ value: membership.membershipId, label: 'Moi' });
    return options;
  }, [catalogue]);

  const set = <K extends keyof SeriesForm>(key: K, value: SeriesForm[K]) => { setRefusal(null); runner.clearOutcome(); setForm(previous => ({ ...previous, [key]: value })); };
  const setSession = (key: string, patch: Partial<SessionForm>) => set('sessions', form.sessions.map(item => item.key === key ? { ...item, ...patch } : item));
  const addSession = () => {
    if (form.sessions.length >= LIMITS.sessions) return;
    const added = emptySession(form.sessions.at(-1));
    set('sessions', [...form.sessions, added]); setStage({ kind: 'session', key: added.key });
  };
  const removeSession = (key: string) => {
    if (form.sessions.length <= 1) return;
    set('sessions', form.sessions.filter(item => item.key !== key)); setStage({ kind: 'course' });
  };
  const refuse = (code: string, message: string) => { setRefusal({ code, message: courseErrorMessage(code) ?? message }); };

  /** Save the draft: undefined when nothing was confirmed, null when the school confirmed without returning the series. */
  async function save(): Promise<CourseSeries | null | undefined> {
    setTouched(true);
    const body = seriesBody(form, timeZone);
    if (!body || locked) return undefined;
    setRefusal(null);
    const result = await runner.run(createCommand(current
      ? { schoolId, kind: 'updateCourseSeries', path: `course-series/${current.id}`, ifMatch: current.version, resourceId: current.id, resourceVersion: current.version, body }
      : { schoolId, kind: 'createCourseSeries', path: 'course-series', resourceVersion: 0, body }), 'Le brouillon est enregistré.');
    if (result.status === 'rejected') { if (!result.needsLogin) runner.clearOutcome(); refuse(result.code, result.message); return undefined; }
    if (result.status !== 'confirmed') return undefined;
    const confirmed = confirmedSeries(result.body);
    if (confirmed) setCurrent(confirmed);
    return confirmed;
  }
  const once = async <T,>(work: () => Promise<T>, otherwise: T): Promise<T> => { if (guard.current) return otherwise; guard.current = true; try { return await work(); } finally { guard.current = false; } };

  /** True once the school confirmed the draft. */
  const saveDraft = () => once(async () => {
    const result = await save();
    if (result === undefined) return false;
    releaseGuard(); setStage({ kind: 'course' }); done(result, 'Le brouillon est enregistré.');
    return true;
  }, false);

  /** Publication is explicit and follows a save when the draft changed: the school publishes the stored version, never the screen. */
  const publish = () => once(async () => {
    setTouched(true);
    if (hasProblems(problems) || locked) return;
    let target = current;
    if (!target || dirty) {
      const result = await save();
      if (result === undefined) return;
      if (result === null) { releaseGuard(); done(null, 'Le brouillon est enregistré.'); return; }
      target = result;
    }
    runner.clearOutcome();
    const result = await runner.run(createCommand({ schoolId, kind: 'publishCourseSeries', path: `course-series/${target.id}/publish`, ifMatch: target.version,
      resourceId: target.id, resourceVersion: target.version, body: {} }), 'Le cours est publié.');
    if (result.status === 'rejected') { if (!result.needsLogin) runner.clearOutcome(); refuse(result.code, result.message); setStage({ kind: 'review' }); return; }
    if (result.status !== 'confirmed') return;
    releaseGuard(); done(confirmedSeries(result.body), 'Le cours est publié.');
  }, undefined);

  const review = () => { setTouched(true); if (hasProblems(problems)) { setStage({ kind: 'course' }); return false; } setStage({ kind: 'review' }); return true; };
  return { form, set, setSession, addSession, removeSession, stage, setStage, touched, shown, problems, overview, dirty, locked, runner, refusal, setRefusal, current,
    types, addType: (type: CourseType) => setAddedTypes(previous => [...previous, type]), instructorOptions, responsibleOptions, saveDraft, publish, review, releaseGuard, timeZone };
}
export type CourseDraft = ReturnType<typeof useCourseDraft>;
