import { useEffect, useId, useMemo, useRef, useState } from 'react';
import { z } from 'zod';
import { createCommand, formatCents, instantToSchoolTime, parseCents, type SchoolCommand } from '../command-core';
import { learnerSchema, readAll, readSchool } from '../school-api';
import { CheckField, ConfirmDialog, Facts, Notice, SelectField, StatusBadge, Symbol, TextArea, TextField } from '../ui';
import { useCommandRunner, useConsole, useLoad, useUnsavedChanges } from './context';
import { LoadState, OutcomeNotice } from './layout';
import { RequestFailure } from '../protocol';
import { distinctLabel, homonymReferences } from '../person-reference';
import {
  LIMITS, REASON_LIMIT, courseRosterSchema, enrollableLearners, policyBody, policyForm, policyProblems, reasonProblem, rescheduleBody, sourceLabel,
  type CourseEnrollment, type CourseRoster, type PolicyForm,
  cancellationLabel, capacityProblem, courseCatalogueSchema, courseErrorMessage, courseSeriesSchema, courseTypeSchema, emptyForm, emptySession,
  formFromSeries, formatHours, hasProblems, languages, preview, seriesBody, typeProblem, validate,
  type CourseCatalogue, type CourseSeries, type SeriesForm, type SessionForm,
  PAYMENT_NOTE_LIMIT, activeCompletion, activePayments, attendanceBody, attendanceCell, attendanceLabels, attendanceStatuses, canMarkAttendance,
  canValidateRow, courseSheetSchema, occurrenceStarted, paymentProblem, requirementLabel,
  type AttendanceStatus, type CoursePayment, type CourseSheet as CourseSheetData, type CourseSheetRow,
} from './course-model';

const envelope = <T extends z.ZodTypeAny>(data: T) => z.object({ data });
const formatDay = (instant: number, timeZone: string) => new Intl.DateTimeFormat('fr-CH', { weekday: 'short', day: 'numeric', month: 'long', year: 'numeric', timeZone }).format(new Date(instant));
const formatClock = (instant: number, timeZone: string) => new Intl.DateTimeFormat('fr-CH', { hour: '2-digit', minute: '2-digit', timeZone }).format(new Date(instant));

export function readCourseCatalogue(schoolId: string): Promise<CourseCatalogue> {
  return readSchool(schoolId, 'course-catalogue', courseCatalogueSchema);
}

/** Bouton « Ajouter » de l'agenda : une leçon se planifie dans l'app, un cours collectif ici. */
export function AgendaAddMenu({ canCreateCourse, onCourse, onLesson }: { canCreateCourse: boolean; onCourse: () => void; onLesson: () => void }) {
  const [open, setOpen] = useState(false);
  const menuId = useId();
  const root = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const close = (event: MouseEvent | KeyboardEvent) => {
      if (event instanceof KeyboardEvent ? event.key === 'Escape' : !root.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', close); document.addEventListener('keydown', close);
    return () => { document.removeEventListener('mousedown', close); document.removeEventListener('keydown', close); };
  }, [open]);
  return <div className="course-add" ref={root}>
    <button type="button" className="button primary" aria-expanded={open} aria-controls={menuId} onClick={() => setOpen(!open)}><Symbol kind="plus" bare />Ajouter</button>
    {open && <div id={menuId} className="course-add-menu" role="group" aria-label="Ajouter">
      <button type="button" className="button quiet" onClick={() => { setOpen(false); onLesson(); }}>Leçon</button>
      {canCreateCourse && <button type="button" className="button quiet" onClick={() => { setOpen(false); onCourse(); }}>Cours collectif</button>}
    </div>}
  </div>;
}

/** Leçon : même indication qu'ailleurs, la planification se fait dans l'app. */
export function LessonInAppDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  return <ConfirmDialog open={open} busy={false} title="Planifier une leçon" confirmLabel="Compris" onCancel={onClose} onConfirm={onClose}>
    <p>Dans l’app Drivy, ouvrez le dossier de l’élève puis choisissez « Planifier une leçon ».</p>
  </ConfirmDialog>;
}

/** Ouvre un cours : édition du brouillon, fiche d'un cours publié. `seriesId` absent : nouveau cours. */
export function CourseWorkspace({ seriesId, selectedOccurrenceId, catalogue, onClose, onSaved }: {
  seriesId: string | null; selectedOccurrenceId?: string | undefined; catalogue: CourseCatalogue; onClose: () => void; onSaved: (series: CourseSeries | null) => void;
}) {
  const { schoolId } = useConsole();
  const loaded = useLoad(async () => {
    if (!seriesId) return null;
    const series = await readSchool(schoolId, `course-series/${seriesId}`, courseSeriesSchema);
    if (series.id !== seriesId || series.schoolId !== schoolId) throw new RequestFailure('INVALID_RESPONSE');
    return series;
  }, [schoolId, seriesId], `${schoolId}/${seriesId ?? 'new'}`, `course-series/${seriesId ?? 'new'}`);
  return <LoadState loaded={loaded} label="Lecture du cours…">{series => selectedOccurrenceId && (!series || !series.occurrences.some(item => item.id === selectedOccurrenceId))
    ? <Notice tone="warning" title="Séance indisponible" actions={<button type="button" className="button quiet" onClick={onClose}>Retour à l’agenda</button>}><p>Cette séance n’apparaît plus dans le cours. Actualisez l’agenda pour retrouver ses dates.</p></Notice>
    : series && series.status !== 'DRAFT'
      ? <CourseSheet series={series} selectedOccurrenceId={selectedOccurrenceId} onClose={onClose} onSaved={onSaved} reload={loaded.reload} />
      : <CourseEditor key={series ? `${series.id}/${series.version}` : 'new'} series={series} selectedOccurrenceId={selectedOccurrenceId} catalogue={catalogue} onClose={onClose} onSaved={onSaved} />}</LoadState>;
}

function CourseEditor({ series, selectedOccurrenceId, catalogue: initial, onClose, onSaved }: {
  series: CourseSeries | null; selectedOccurrenceId?: string | undefined; catalogue: CourseCatalogue; onClose: () => void; onSaved: (series: CourseSeries | null) => void;
}) {
  const { schoolId, school, membership } = useConsole();
  const timeZone = school.timeZone;
  const uid = useId();
  const runner = useCommandRunner();
  const [catalogue, setCatalogue] = useState(initial);
  const [current, setCurrent] = useState(series);
  const baseline = useMemo(() => series ? formFromSeries(series, timeZone)
    : emptyForm(catalogue, catalogue.instructors.some(item => item.membershipId === membership.membershipId) ? membership.membershipId : ''), []);
  const selectedSessionKey = baseline.sessions[series?.occurrences.findIndex(item => item.id === selectedOccurrenceId) ?? -1]?.key;
  const selectedSession = useRef<HTMLLIElement>(null);
  useEffect(() => { selectedSession.current?.focus(); }, [selectedSessionKey]);
  const [form, setForm] = useState<SeriesForm>(baseline);
  const [touched, setTouched] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [newType, setNewType] = useState<{ title: string; description: string } | null>(null);
  const [closing, setClosing] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [expanded, setExpanded] = useState<Set<string>>(() => new Set([selectedSessionKey ?? baseline.sessions[0]?.key].filter((key): key is string => key !== undefined)));
  const dirty = JSON.stringify(form) !== JSON.stringify(baseline) || current?.id !== series?.id;
  const pendingKind = runner.pending?.meta.kind;
  const formSent = pendingKind === 'createCourseSeries' || pendingKind === 'updateCourseSeries' || pendingKind === 'publishCourseSeries';
  const unsent = (!formSent && JSON.stringify(form) !== JSON.stringify(current ? formFromSeries(current, timeZone) : baseline))
    || (pendingKind !== 'createCourseType' && Boolean(newType?.title || newType?.description));
  const releaseGuard = useUnsavedChanges(unsent);
  const close = () => { releaseGuard(); onClose(); };

  const problems = validate(form, timeZone);
  const shown = touched ? problems : { fields: {}, sessions: {} };
  const overview = preview(form, timeZone);
  const policyHours = catalogue.policy.selfCancelHours;
  const busy = runner.busy || Boolean(runner.pending);
  const instructors = catalogue.instructors.map(item => ({ value: item.membershipId, label: item.displayName }));
  // Responsable : formateurs de l'école, plus la personne connectée (administration) et le responsable actuel.
  const responsibles = useMemo(() => {
    const options = [...instructors];
    if (series && !options.some(item => item.value === series.responsibleMembershipId)) options.push({ value: series.responsibleMembershipId, label: series.responsibleDisplayName || 'Responsable actuel' });
    if (!options.some(item => item.value === membership.membershipId)) options.push({ value: membership.membershipId, label: 'Moi' });
    return options;
  }, [catalogue]);
  const typeOptions = catalogue.types.map(type => ({ value: type.id, label: type.title }));

  const set = <K extends keyof SeriesForm>(key: K, value: SeriesForm[K]) => { setError(null); setForm(previous => ({ ...previous, [key]: value })); };
  const setSession = (key: string, patch: Partial<SessionForm>) => set('sessions', form.sessions.map(item => item.key === key ? { ...item, ...patch } : item));

  const refuse = (code: string, message: string) => setError(courseErrorMessage(code) ?? message);

  async function save(): Promise<CourseSeries | null | undefined> {
    setTouched(true);
    const body = seriesBody(form, timeZone);
    if (!body || busy) return undefined;
    setError(null);
    const command = current
      ? createCommand({ schoolId, kind: 'updateCourseSeries', path: `course-series/${current.id}`, ifMatch: current.version, resourceId: current.id, resourceVersion: current.version, body })
      : createCommand({ schoolId, kind: 'createCourseSeries', path: 'course-series', resourceVersion: 0, body });
    const result = await runner.run(command, 'Brouillon enregistré.');
    if (result.status === 'rejected') { runner.clearOutcome(); refuse(result.code, result.message); return undefined; }
    if (result.status !== 'confirmed') return undefined;
    const parsed = envelope(courseSeriesSchema).safeParse(result.body);
    const saved = parsed.success ? parsed.data.data : null;
    if (saved) setCurrent(saved);
    return saved;
  }

  async function saveDraft(closeAfter = false) {
    const saved = await save();
    if (saved !== undefined) { releaseGuard(); onSaved(saved); if (closeAfter) onClose(); }
  }

  async function publish() {
    setTouched(true);
    if (hasProblems(problems) || busy) return;
    let target = current;
    if (!target || dirty) {
      const saved = await save();
      if (saved === undefined) return;
      if (saved === null) { onSaved(null); return; }
      target = saved;
    }
    runner.clearOutcome();
    const command = createCommand({ schoolId, kind: 'publishCourseSeries', path: `course-series/${target.id}/publish`, ifMatch: target.version, resourceId: target.id, resourceVersion: target.version, body: {} });
    const result = await runner.run(command, 'Cours publié.');
    if (result.status === 'rejected') { runner.clearOutcome(); refuse(result.code, result.message); return; }
    if (result.status !== 'confirmed') return;
    const parsed = envelope(courseSeriesSchema).safeParse(result.body);
    releaseGuard(); onSaved(parsed.success ? parsed.data.data : null);
  }

  async function createType() {
    if (!newType || busy) return;
    const problem = typeProblem(newType.title, newType.description, catalogue.types);
    if (problem) { setError(problem); return; }
    const command = createCommand({ schoolId, kind: 'createCourseType', path: 'course-types', resourceVersion: 0,
      body: { title: newType.title.trim(), description: newType.description.trim() } });
    const result = await runner.run(command, 'Type ajouté.');
    if (result.status === 'rejected') { runner.clearOutcome(); refuse(result.code, result.message); return; }
    if (result.status !== 'confirmed') return;
    runner.clearOutcome();
    const parsed = envelope(courseTypeSchema).safeParse(result.body);
    if (parsed.success) {
      setCatalogue(previous => ({ ...previous, types: [...previous.types, parsed.data.data] }));
      set('typeId', parsed.data.data.id);
    } else {
      // Confirmé par reçu : le type existe, on relit le catalogue pour le proposer.
      try { setCatalogue(await readSchool(schoolId, 'course-catalogue', courseCatalogueSchema)); } catch { /* le catalogue affiché reste utilisable */ }
    }
    setNewType(null);
  }

  return <section className="course-editor section-stack" aria-labelledby={`${uid}-title`}>
    <div className="course-editor-heading">
      <h2 id={`${uid}-title`} className="section-title">{current ? current.title || 'Cours collectif' : 'Nouveau cours collectif'}</h2>
      {current && <StatusBadge tone="neutral" symbol="edit">Brouillon</StatusBadge>}
      <button type="button" className="button quiet" disabled={runner.busy} onClick={() => unsent ? setClosing(true) : close()}>Fermer</button>
    </div>
    {error && <Notice tone="error" title="Non enregistré"><p>{error}</p></Notice>}
    <OutcomeNotice outcome={runner.outcome?.tone === 'success' ? null : runner.outcome} />
    {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}

    <form className="course-form" noValidate onSubmit={event => { event.preventDefault(); void saveDraft(); }}>
      <fieldset className="course-fieldset" disabled={busy}>
        <legend className="section-title">Cours</legend>
        <div className="course-type-row">
          <SelectField label="Type" value={form.typeId} onChange={value => set('typeId', value)} options={typeOptions} required error={shown.fields.typeId} />
          {!newType && <button type="button" className="button quiet" onClick={() => setNewType({ title: '', description: '' })}><Symbol kind="plus" bare />Nouveau type</button>}
        </div>
        {newType && <div className="course-new-type" role="group" aria-label="Nouveau type">
          <TextField label="Nom du type" value={newType.title} maxLength={LIMITS.typeTitle} required onChange={title => setNewType({ ...newType, title })} />
          <TextArea label="Description du type" value={newType.description} maxLength={LIMITS.typeDescription} rows={2} required={false} onChange={description => setNewType({ ...newType, description })} />
          <div className="button-row compact">
            <button type="button" className="button secondary" onClick={() => void createType()} aria-busy={runner.busy}>Ajouter le type</button>
            <button type="button" className="button quiet" onClick={() => setNewType(null)}>Annuler</button>
          </div>
        </div>}
        <TextField label="Titre" value={form.title} onChange={value => set('title', value)} maxLength={LIMITS.title} required error={shown.fields.title} />
        <TextArea label="Description" value={form.description} onChange={value => set('description', value)} maxLength={LIMITS.description} rows={3} required={false} error={shown.fields.description} />
        <TextField label="Lieu" value={form.location} onChange={value => set('location', value)} maxLength={LIMITS.location} required={false} error={shown.fields.location} />
        <SelectField label="Responsable" value={form.responsible} onChange={value => set('responsible', value)} options={responsibles} required error={shown.fields.responsible} />
        <div className="course-numbers">
          <TextField label="Capacité" value={form.capacity} onChange={value => set('capacity', value)} inputMode="numeric" required error={shown.fields.capacity} />
          <TextField label="Minimum" value={form.minimum} onChange={value => set('minimum', value)} inputMode="numeric" required={false} error={shown.fields.minimum} />
          <SelectField label="Langue" value={form.language} onChange={value => set('language', value as SeriesForm['language'])}
            options={[{ value: '', label: 'Non précisée' }, ...languages.map(item => ({ value: item.value, label: item.label }))]} required={false} />
        </div>
        <TextArea label="Conditions" value={form.conditions} onChange={value => set('conditions', value)} maxLength={LIMITS.conditions} rows={3} required={false} error={shown.fields.conditions} />
      </fieldset>

      <fieldset className="course-fieldset" disabled={busy}>
        <legend className="section-title">Séances</legend>
        {shown.fields.sessions && <p className="field-error"><Symbol kind="alert" bare />{shown.fields.sessions}</p>}
        <ol className="course-sessions">{form.sessions.map((session, index) => {
          const problem = shown.sessions[session.key];
          return <li key={session.key} ref={session.key === selectedSessionKey ? selectedSession : undefined} tabIndex={session.key === selectedSessionKey ? -1 : undefined}
            aria-current={session.key === selectedSessionKey ? 'true' : undefined} className={problem ? 'course-session invalid' : 'course-session'} aria-label={`Séance ${index + 1}`}>
            <details open={expanded.has(session.key) || Boolean(problem)} onToggle={event => {
              const open = event.currentTarget.open;
              setExpanded(previous => { const next = new Set(previous); if (open) next.add(session.key); else next.delete(session.key); return next; });
            }}>
            <summary>Séance {index + 1}{session.date ? ` · ${session.date.split('-').reverse().join('.')}` : ''}{session.start && session.end ? ` · ${session.start}–${session.end}` : ''}</summary>
            <div className="course-session-fields">
            <TextField label="Date" type="date" value={session.date} onChange={date => setSession(session.key, { date })} required />
            <TextField label="Début" type="time" value={session.start} onChange={start => setSession(session.key, { start })} required />
            <TextField label="Fin" type="time" value={session.end} onChange={end => setSession(session.key, { end })} required />
            <SelectField label="Moniteur" value={session.instructor} onChange={instructor => setSession(session.key, { instructor })} options={instructors} required />
            <CheckField label="Présence obligatoire" checked={session.attendanceRequired} onChange={attendanceRequired => setSession(session.key, { attendanceRequired })} />
            {form.sessions.length > 1 && <button type="button" className="button quiet" aria-label={`Retirer la séance ${index + 1}`}
              onClick={() => set('sessions', form.sessions.filter(item => item.key !== session.key))}>Retirer</button>}
            {problem && <p className="field-error"><Symbol kind="alert" bare />{problem}</p>}
            </div></details>
          </li>;
        })}</ol>
        {form.sessions.length < LIMITS.sessions && <button type="button" className="button secondary"
          onClick={() => { const added = emptySession(form.sessions.at(-1)); set('sessions', [...form.sessions, added]); setExpanded(new Set([added.key])); }}><Symbol kind="plus" bare />Ajouter une séance</button>}
      </fieldset>

      {catalogue.canManage && <div className="button-row">
        <button type="submit" className="button secondary" disabled={busy} aria-busy={runner.busy}>Enregistrer le brouillon</button>
        <button type="button" className="button primary" disabled={busy} onClick={() => { setTouched(true); if (!hasProblems(problems)) setReviewing(true); }}>Vérifier et publier</button>
      </div>}
    </form>
    <ConfirmDialog open={closing} busy={runner.busy} title="Fermer sans enregistrer ?" confirmLabel="Abandonner les modifications"
      onCancel={() => setClosing(false)} onConfirm={close}>
      <p>Les modifications de ce cours ne sont pas enregistrées.</p>
      <button type="button" className="button secondary" disabled={busy || hasProblems(problems)} onClick={() => void saveDraft(true)}>Enregistrer le brouillon et fermer</button>
      {error && <Notice tone="error" title="Non enregistré"><p>{error}</p></Notice>}
      <OutcomeNotice outcome={runner.outcome?.tone === 'success' ? null : runner.outcome} />
    </ConfirmDialog>
    <ConfirmDialog open={reviewing} busy={busy} title="Publier ce cours ?" confirmLabel="Publier le cours"
      onCancel={() => setReviewing(false)} onConfirm={() => void publish()}>
      <h3>{form.title}</h3>
      {form.description && <p>{form.description}</p>}
      <Facts items={[[ 'Lieu', form.location || 'Non renseigné' ], ['Capacité', form.capacity],
        ['Séances', `${overview.sessions.length} · ${formatHours(overview.totalMinutes)}`]]} />
      <ol className="course-preview-list">{overview.sessions.map(item => <li key={item.key}>
        <time dateTime={new Date(item.start).toISOString()}>{formatDay(item.start, timeZone)}</time>{' '}
        {formatClock(item.start, timeZone)}–{formatClock(item.end, timeZone)}
        <span className="row-meta"> · {form.sessions.find(session => session.key === item.key)?.attendanceRequired ? 'Présence obligatoire' : 'Facultative'}</span>
      </li>)}</ol>
      <p>{cancellationLabel(policyHours)}</p>
      {form.conditions && <p className="preserve-lines">{form.conditions}</p>}
      {error && <Notice tone="error" title="Non publié"><p>{error}</p></Notice>}
      <OutcomeNotice outcome={runner.outcome?.tone === 'success' ? null : runner.outcome} />
    </ConfirmDialog>
  </section>;
}

/** Cours publié : lecture, seule la capacité se change ici. */
function CourseSheet({ series, selectedOccurrenceId, onClose, onSaved, reload }: { series: CourseSeries; selectedOccurrenceId?: string | undefined; onClose: () => void; onSaved: (series: CourseSeries | null) => void; reload: () => void }) {
  const { schoolId, school } = useConsole();
  const timeZone = school.timeZone;
  const selectedOccurrence = useRef<HTMLLIElement>(null);
  useEffect(() => { selectedOccurrence.current?.focus(); }, [selectedOccurrenceId]);
  const runner = useCommandRunner();
  const [capacity, setCapacity] = useState(String(series.capacity));
  const [error, setError] = useState<string | null>(null);
  const [closing, setClosing] = useState(false);
  const problem = capacity === String(series.capacity) ? null : capacityProblem(capacity, series);
  const busy = runner.busy || Boolean(runner.pending);
  const unsent = !runner.pending && capacity !== String(series.capacity);
  const releaseGuard = useUnsavedChanges(unsent);
  const close = () => { releaseGuard(); onClose(); };

  async function change() {
    if (problem || busy || capacity === String(series.capacity)) return;
    setError(null);
    const command = createCommand({ schoolId, kind: 'changeCourseCapacity', path: `course-series/${series.id}/capacity`, ifMatch: series.version,
      resourceId: series.id, resourceVersion: series.version, body: { capacity: Number(capacity.trim()) } });
    const result = await runner.run(command, 'Capacité modifiée.');
    if (result.status === 'rejected') {
      runner.clearOutcome(); setError(courseErrorMessage(result.code) ?? result.message);
      if (result.code === 'VERSION_CONFLICT') reload();
      return;
    }
    if (result.status !== 'confirmed') return;
    const parsed = envelope(courseSeriesSchema).safeParse(result.body);
    releaseGuard(); onSaved(parsed.success ? parsed.data.data : null);
  }

  const status = series.status === 'CANCELLED' ? 'Annulé' : series.status === 'CLOSED' ? 'Clos' : null;
  return <section className="course-editor section-stack" aria-label={series.title}>
    <div className="course-editor-heading">
      <h2 className="section-title">{series.title}</h2>
      {status && <StatusBadge tone="neutral" symbol="ban">{status}</StatusBadge>}
      <button type="button" className="button quiet" disabled={runner.busy} onClick={() => unsent ? setClosing(true) : onClose()}>Fermer</button>
    </div>
    {error && <Notice tone="error" title="Non enregistré"><p>{error}</p></Notice>}
    <OutcomeNotice outcome={runner.outcome?.tone === 'success' ? null : runner.outcome} />
    <Facts items={[
      ['Type', series.typeTitle],
      ...(series.location ? [['Lieu', series.location] as const] : []),
      ['Responsable', series.responsibleDisplayName || 'Non renseigné'],
      ['Places', `${series.seatsTaken} / ${series.capacity}`],
      ['Places restantes', String(Math.max(0, series.capacity - series.seatsTaken))],
      ...(series.minParticipants !== null ? [['Minimum', String(series.minParticipants)] as const] : []),
      ['Durée', formatHours(series.totalMinutes)],
      ['Annulation', cancellationLabel(series.selfCancelHours)],
    ]} />
    {series.description && <p>{series.description}</p>}
    {series.conditions && <p className="row-meta">{series.conditions}</p>}
    <ol className="course-preview-list">{series.occurrences.map(item => <li key={item.id} ref={item.id === selectedOccurrenceId ? selectedOccurrence : undefined}
      data-occurrence-id={item.id} tabIndex={item.id === selectedOccurrenceId ? -1 : undefined} aria-current={item.id === selectedOccurrenceId ? 'true' : undefined}>
      <time dateTime={item.startsAt}>{formatDay(Date.parse(item.startsAt), timeZone)}</time>{' '}
      {instantToSchoolTime(item.startsAt, timeZone).slice(11)}–{instantToSchoolTime(item.endsAt, timeZone).slice(11)}
      <span className="row-meta"> · {item.instructorDisplayName}{item.attendanceRequired ? '' : ' · Facultative'}</span>
    </li>)}</ol>
    {series.canManage && series.status === 'PUBLISHED' && <form className="course-capacity" noValidate onSubmit={event => { event.preventDefault(); void change(); }}>
      <TextField label="Capacité" value={capacity} onChange={value => { setError(null); setCapacity(value); }} inputMode="numeric" required error={problem} disabled={busy} />
      <button type="submit" className="button secondary" disabled={busy || problem !== null || capacity === String(series.capacity)} aria-busy={runner.busy}>Changer la capacité</button>
    </form>}
    {series.status === 'PUBLISHED' && <CourseFactsSheet series={series} />}
    {series.canManage && series.status === 'PUBLISHED' && <>
      <CourseRosterPanel series={series} />
      <CourseDangerZone series={series} onSaved={onSaved} reload={reload} />
    </>}
    <ConfirmDialog open={closing} busy={busy} title="Fermer sans enregistrer ?" confirmLabel="Abandonner les modifications"
      onCancel={() => setClosing(false)} onConfirm={close}><p>La capacité modifiée n’est pas enregistrée.</p></ConfirmDialog>
  </section>;
}

const formatInstant = (instant: string, timeZone: string) => new Intl.DateTimeFormat('fr-CH', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', timeZone }).format(new Date(instant));

/** Inscrits et file d'attente d'un cours publié ; inscription et annulation par le personnel. */
function CourseRosterPanel({ series }: { series: CourseSeries }) {
  const { schoolId, school } = useConsole();
  const timeZone = school.timeZone;
  const runner = useCommandRunner();
  const [revision, setRevision] = useState(0);
  const roster = useLoad(() => readSchool(schoolId, `course-series/${series.id}/enrollments`, courseRosterSchema), [schoolId, series.id, series.version, revision], undefined, `course-roster/${series.id}`);
  const learners = useLoad(() => readAll(schoolId, 'learners', learnerSchema, { status: 'ALL' }), [schoolId], undefined, 'learners/status=ALL');
  const [learner, setLearner] = useState('');
  const [cancelling, setCancelling] = useState<CourseEnrollment | null>(null);
  const [reason, setReason] = useState('');
  const [reasonTouched, setReasonTouched] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const busy = runner.busy || Boolean(runner.pending);
  const refuse = (code: string, message: string) => { runner.clearOutcome(); setError(courseErrorMessage(code) ?? message); if (code === 'VERSION_CONFLICT') setRevision(value => value + 1); };

  async function enroll() {
    if (!learner || busy) return;
    setError(null);
    const command = createCommand({ schoolId, kind: 'staffEnrollCourse', path: `course-series/${series.id}/enrollments`, resourceVersion: 0, body: { learnerId: learner } });
    const result = await runner.run(command, 'Élève inscrit.');
    if (result.status === 'rejected') { refuse(result.code, result.message); return; }
    if (result.status !== 'confirmed') return;
    setLearner(''); setRevision(value => value + 1);
  }

  async function cancel() {
    setReasonTouched(true);
    if (!cancelling || reasonProblem(reason) || busy) return;
    setError(null);
    const command = createCommand({ schoolId, kind: 'staffCancelCourseEnrollment', path: `course-enrollments/${cancelling.id}/staff-cancel`, ifMatch: cancelling.version,
      resourceId: cancelling.id, resourceVersion: cancelling.version, body: { reason: reason.trim() } });
    const result = await runner.run(command, 'Inscription annulée.');
    if (result.status === 'rejected') { refuse(result.code, result.message); return; }
    if (result.status === 'confirmed') { setCancelling(null); setReason(''); setReasonTouched(false); setRevision(value => value + 1); }
  }

  return <section className="section-stack" aria-label="Inscriptions">
    <h3 className="section-title">Inscrits</h3>
    {error && <Notice tone="error" title="Non enregistré"><p>{error}</p></Notice>}
    <OutcomeNotice outcome={runner.outcome} />
    <LoadState loaded={roster} label="Lecture des inscrits…">{(value: CourseRoster) => {
      const active = value.items.filter(item => item.status === 'ACTIVE');
      const candidates = enrollableLearners(learners.data?.items ?? [], value);
      const references = homonymReferences(candidates.map(item => ({ id: item.id, label: item.displayName })));
      const options = candidates.map(item => ({ value: item.id, label: distinctLabel(item.displayName, references.get(item.id)) }));
      return <>
        {active.length === 0 ? <p className="row-meta">Aucun inscrit</p> : <ul className="row-list">{value.items.map(item => <li key={item.id} className={item.status === 'CANCELLED' ? 'muted-row' : undefined}>
          <span className="row-title">{item.learnerDisplayName || 'Élève'}</span>{' '}
          <span className="row-meta">{sourceLabel(item.source)} · annulation libre jusqu’au <time dateTime={item.selfCancelDeadline}>{formatInstant(item.selfCancelDeadline, timeZone)}</time></span>{' '}
          {item.status === 'CANCELLED'
            ? <StatusBadge tone="neutral" symbol="ban">Annulée</StatusBadge>
            : <details className="course-enrollment-actions"><summary>Actions pour {item.learnerDisplayName || 'cet élève'}</summary>
              <button type="button" className="button quiet" disabled={busy} onClick={() => { setError(null); setReason(''); setReasonTouched(false); setCancelling(item); }}>Annuler l’inscription</button>
            </details>}
        </li>)}</ul>}
        {value.waitlist.length > 0 && <>
          <h3 className="section-title">Liste d’attente</h3>
          <ol className="row-list">{value.waitlist.map(entry => <li key={entry.id}>
            <span className="row-meta">{entry.position}.</span>{' '}<span className="row-title">{entry.learnerDisplayName || 'Élève'}</span>
            {entry.status === 'OFFERED' && <>{' '}<StatusBadge tone="accent" symbol="clock">Place proposée</StatusBadge>
              {entry.offerExpiresAt && <span className="row-meta"> jusqu’au <time dateTime={entry.offerExpiresAt}>{formatInstant(entry.offerExpiresAt, timeZone)}</time></span>}</>}
          </li>)}</ol>
        </>}
        <form className="course-capacity" noValidate onSubmit={event => { event.preventDefault(); void enroll(); }}>
          <SelectField label="Élève" value={learner} onChange={value => { setError(null); setLearner(value); }} search
            options={[{ value: '', label: learners.status === 'error' ? 'Élèves indisponibles' : 'Choisir un élève' }, ...options]} required={false} disabled={busy} />
          <button type="submit" className="button secondary" disabled={busy || !learner} aria-busy={runner.busy}>Inscrire un élève</button>
        </form>
      </>;
    }}</LoadState>
    <ConfirmDialog open={cancelling !== null} busy={busy} title="Annuler l’inscription" confirmLabel="Annuler l’inscription"
      onCancel={() => setCancelling(null)} onConfirm={() => void cancel()}>
      <p>{cancelling?.learnerDisplayName || 'Élève'}</p>
      <p>Son inscription à toute la série sera annulée.</p>
      <TextArea label="Motif" value={reason} onChange={setReason} maxLength={REASON_LIMIT} rows={3} required error={reasonTouched ? reasonProblem(reason) : null} />
      {error && <Notice tone="error" title="Non enregistré"><p>{error}</p></Notice>}
    </ConfirmDialog>
  </section>;
}

type SheetDialog = 'cancel' | 'reschedule' | null;

type FactDialog =
  | { kind: 'pay'; row: CourseSheetRow }
  | { kind: 'void'; row: CourseSheetRow; payment: CoursePayment }
  | { kind: 'revoke'; row: CourseSheetRow; completionId: string }
  | null;

/**
 * Feuille du cours : élèves × séances (présence), règlement sur place, validation. Trois colonnes indépendantes,
 * chacune affichée seulement si le serveur accorde le droit. Chaque réponse renvoie la feuille à jour.
 */
function CourseFactsSheet({ series }: { series: CourseSeries }) {
  const { schoolId, school } = useConsole();
  const timeZone = school.timeZone;
  const runner = useCommandRunner();
  const loaded = useLoad(() => readSchool(schoolId, `course-series/${series.id}/sheet`, courseSheetSchema), [schoolId, series.id, series.version], undefined, `course-sheet/${series.id}`);
  const [mode, setMode] = useState<'attendance' | 'payments' | 'validation'>('attendance');
  const [fresh, setFresh] = useState<CourseSheetData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [dialog, setDialog] = useState<FactDialog>(null);
  const [text, setText] = useState('');
  const [amount, setAmount] = useState('');
  const [touched, setTouched] = useState(false);
  // Même intention renvoyée après un résultat incertain : même operationId.
  const attempts = useRef(new Map<string, string>());
  const busy = runner.busy || Boolean(runner.pending);
  useEffect(() => { setFresh(null); }, [loaded.data]);

  async function send(kind: SchoolCommand['kind'], path: string, body: Record<string, unknown>, resourceId: string | undefined, resourceVersion: number, success: string): Promise<boolean> {
    if (busy) return false;
    setError(null);
    const intent = `${kind} ${path} ${JSON.stringify(body)}`;
    const previous = attempts.current.get(intent);
    const command = createCommand({ schoolId, kind, path, body, resourceVersion, ...(resourceId ? { resourceId } : {}), ...(previous ? { operationId: previous } : {}) });
    attempts.current.set(intent, command.operationId);
    const result = await runner.run(command, success);
    if (result.status === 'pending') return false;
    attempts.current.delete(intent);
    if (result.status === 'rejected') {
      runner.clearOutcome(); setError(courseErrorMessage(result.code) ?? result.message);
      if (['VERSION_CONFLICT', 'NOT_FOUND', 'COURSE_PAYMENT_VOIDED', 'COURSE_COMPLETION_REVOKED', 'COURSE_ALREADY_COMPLETED'].includes(result.code)) loaded.reload();
      return false;
    }
    runner.clearOutcome();
    const parsed = envelope(courseSheetSchema).safeParse(result.body);
    if (parsed.success) setFresh(parsed.data.data); else loaded.reload();
    return true;
  }

  const mark = (row: CourseSheetRow, occurrenceId: string, status: AttendanceStatus) => {
    const cell = attendanceCell(row, occurrenceId);
    const body = attendanceBody(cell, status);
    if (!body) return;
    void send('recordCourseAttendance', `course-enrollments/${row.enrollmentId}/attendance/${occurrenceId}`, body, row.enrollmentId, cell.version ?? 0, 'Présence enregistrée.');
  };
  const validateRow = (row: CourseSheetRow) => void send('validateCourse', `course-enrollments/${row.enrollmentId}/validate`, { note: null }, undefined, 0, 'Cours validé.');

  const open = (next: FactDialog) => { setError(null); setText(''); setAmount(''); setTouched(false); setDialog(next); };
  const cents = parseCents(amount);
  const dialogProblem = !dialog ? null : dialog.kind === 'pay' ? paymentProblem(cents, text) : reasonProblem(text);

  async function confirm() {
    setTouched(true);
    if (!dialog || dialogProblem || busy) return;
    const done = dialog.kind === 'pay'
      ? await send('recordCoursePayment', `course-enrollments/${dialog.row.enrollmentId}/payments`, { amountCents: cents, note: text.trim() || null }, undefined, 0, 'Règlement enregistré.')
      : dialog.kind === 'void'
        ? await send('voidCoursePayment', `course-payments/${dialog.payment.id}/void`, { reason: text.trim() }, dialog.payment.id, 1, 'Règlement annulé.')
        : await send('revokeCourseCompletion', `course-completions/${dialog.completionId}/revoke`, { reason: text.trim() }, dialog.completionId, 1, 'Validation retirée.');
    if (done) setDialog(null);
  }

  const shortDay = (instant: string) => new Intl.DateTimeFormat('fr-CH', { day: 'numeric', month: 'short', timeZone }).format(new Date(instant));
  const longDate = (instant: string) => new Intl.DateTimeFormat('fr-CH', { day: 'numeric', month: 'long', year: 'numeric', timeZone }).format(new Date(instant));

  return <section className="section-stack" aria-label="Suivi des participants">
    <h3 className="section-title">Participants</h3>
    {error && <Notice tone="error" title="Non enregistré"><p>{error}</p></Notice>}
    <OutcomeNotice outcome={runner.outcome} />
    <LoadState loaded={loaded} label="Lecture de la feuille…">{(read: CourseSheetData) => {
      const sheet = fresh ?? read;
      const occurrences = [...sheet.series.occurrences].sort((a, b) => a.position - b.position);
      const rows = sheet.rows;
      if (rows.length === 0) return <p className="row-meta">Aucun inscrit</p>;
      const now = Date.now();
      const modes = [
        ...(sheet.rights.canTakeAttendance ? [{ key: 'attendance' as const, title: 'Appel' }] : []),
        ...(sheet.rights.canRecordPayment ? [{ key: 'payments' as const, title: 'Règlements' }] : []),
        ...(sheet.rights.canValidate ? [{ key: 'validation' as const, title: 'Validation' }] : []),
      ];
      const selectedMode = modes.some(item => item.key === mode) ? mode : modes[0]?.key;
      if (!selectedMode) return null;
      return <>
        <div className="button-row compact" role="group" aria-label="Suivi des participants">{modes.map(item => <button key={item.key} type="button"
          className={`button ${selectedMode === item.key ? 'secondary' : 'quiet'}`} aria-pressed={selectedMode === item.key} onClick={() => setMode(item.key)}>{item.title}</button>)}</div>
        <div className="course-sheet-scroll"><table className="course-sheet" aria-label={modes.find(item => item.key === selectedMode)?.title}>
          <thead><tr>
            <th scope="col">Élève</th>
            {selectedMode === 'attendance' && occurrences.map(item => <th scope="col" key={item.id}>
              <time dateTime={item.startsAt}>{shortDay(item.startsAt)}</time>
              {!item.attendanceRequired && <span className="row-meta"> · Facultative</span>}
            </th>)}
            {selectedMode === 'validation' && <th scope="col">Présences requises</th>}
            {selectedMode === 'payments' && <th scope="col" className="course-sheet-group">Règlement</th>}
            {selectedMode === 'validation' && <th scope="col" className="course-sheet-group">Validation</th>}
          </tr></thead>
          <tbody>{rows.map(row => {
            const name = row.learnerDisplayName || 'Élève';
            const completion = activeCompletion(row);
            return <tr key={row.enrollmentId} className={row.status === 'CANCELLED' ? 'muted-row' : undefined}>
              <th scope="row">{name}{row.status === 'CANCELLED' && <>{' '}<StatusBadge tone="neutral" symbol="ban">Annulée</StatusBadge></>}</th>
              {selectedMode === 'attendance' && occurrences.map(item => {
                const cell = attendanceCell(row, item.id);
                const editable = canMarkAttendance(sheet, row, item, now);
                return <td key={item.id}>
                  {editable
                    ? <div role="group" aria-label={`${name}, ${shortDay(item.startsAt)}`} className="course-sheet-choices">
                      {attendanceStatuses.map(status => <button key={status} type="button" aria-pressed={cell.status === status}
                        className={`button ${cell.status === status ? 'secondary' : 'quiet'}`} disabled={busy}
                        onClick={() => mark(row, item.id, status)}>{attendanceLabels[status]}</button>)}
                    </div>
                    : cell.status ? <span>{attendanceLabels[cell.status]}</span>
                      : <span className="row-meta">{occurrenceStarted(item, now) ? 'À renseigner' : 'À venir'}</span>}
                </td>;
              })}
              {selectedMode === 'validation' && <td>{requirementLabel(row.requirements)}</td>}
              {selectedMode === 'payments' && <td className="course-sheet-group">
                <ul className="row-list">{row.payments.map(payment => <li key={payment.id} className={payment.voidedAt ? 'muted-row' : undefined}>
                  <span>Payé sur place {formatCents(payment.amountCents)}</span>
                  {payment.voidedAt
                    ? <>{' '}<StatusBadge tone="neutral" symbol="ban">Annulé</StatusBadge></>
                    : <>{' '}<button type="button" className="button quiet" disabled={busy} onClick={() => open({ kind: 'void', row, payment })}>Annuler</button></>}
                </li>)}</ul>
                {row.status === 'ACTIVE' && <button type="button" className="button quiet" disabled={busy} onClick={() => open({ kind: 'pay', row })}>
                  {activePayments(row).length ? 'Ajouter un règlement' : 'Enregistrer un règlement'}</button>}
              </td>}
              {selectedMode === 'validation' && <td className="course-sheet-group">
                {completion
                  ? <><span>Validé le <time dateTime={completion.validatedAt}>{longDate(completion.validatedAt)}</time></span>{' '}
                    {completion.seriesId === sheet.series.id && <button type="button" className="button quiet" disabled={busy} onClick={() => open({ kind: 'revoke', row, completionId: completion.id })}>Retirer</button>}</>
                  : row.status === 'ACTIVE' && <button type="button" className="button secondary" disabled={busy || !canValidateRow(sheet, row)} onClick={() => validateRow(row)}>Valider</button>}
              </td>}
            </tr>;
          })}</tbody>
        </table>
      </div></>;
    }}</LoadState>
    <ConfirmDialog open={dialog !== null} busy={busy}
      title={dialog?.kind === 'pay' ? 'Règlement sur place' : dialog?.kind === 'void' ? 'Annuler le règlement' : 'Retirer la validation'}
      confirmLabel={dialog?.kind === 'pay' ? 'Enregistrer' : dialog?.kind === 'void' ? 'Annuler le règlement' : 'Retirer'}
      onCancel={() => setDialog(null)} onConfirm={() => void confirm()}>
      <p>{dialog?.row.learnerDisplayName || 'Élève'}{dialog?.kind === 'void' ? ` · ${formatCents(dialog.payment.amountCents)}` : ''}</p>
      {dialog?.kind === 'pay' ? <>
        <TextField label="Montant (CHF)" value={amount} onChange={setAmount} inputMode="decimal" required error={touched && cents === null ? paymentProblem(cents, '') : null} />
        <TextArea label="Note" value={text} onChange={setText} maxLength={PAYMENT_NOTE_LIMIT} rows={2} error={touched && cents !== null ? dialogProblem : null} />
      </> : <TextArea label="Motif" value={text} onChange={setText} maxLength={REASON_LIMIT} rows={3} required error={touched ? dialogProblem : null} />}
    </ConfirmDialog>
  </section>;
}

/** Annuler le cours ou déplacer ses séances (même nombre). */
function CourseDangerZone({ series, onSaved, reload }: { series: CourseSeries; onSaved: (series: CourseSeries | null) => void; reload: () => void }) {
  const { schoolId, school } = useConsole();
  const timeZone = school.timeZone;
  const runner = useCommandRunner();
  const [dialog, setDialog] = useState<SheetDialog>(null);
  const [reason, setReason] = useState('');
  const [touched, setTouched] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sessions, setSessions] = useState<SessionForm[]>(() => formFromSeries(series, timeZone).sessions);
  const instructors = useMemo(() => {
    const seen = new Map<string, string>();
    for (const item of series.occurrences) seen.set(item.instructorMembershipId, item.instructorDisplayName || 'Moniteur');
    return [...seen].map(([value, label]) => ({ value, label }));
  }, [series]);
  const busy = runner.busy || Boolean(runner.pending);
  const sessionProblems = touched ? validate({ ...formFromSeries(series, timeZone), sessions }, timeZone).sessions : {};

  async function finish(result: Awaited<ReturnType<typeof runner.run>>) {
    if (result.status === 'rejected') {
      runner.clearOutcome(); setError(courseErrorMessage(result.code) ?? result.message);
      if (result.code === 'VERSION_CONFLICT') reload();
      return;
    }
    if (result.status !== 'confirmed') return;
    setDialog(null);
    const parsed = envelope(courseSeriesSchema).safeParse(result.body);
    onSaved(parsed.success ? parsed.data.data : null);
  }

  async function cancelSeries() {
    setTouched(true);
    if (reasonProblem(reason) || busy) return;
    setError(null);
    await finish(await runner.run(createCommand({ schoolId, kind: 'cancelCourseSeries', path: `course-series/${series.id}/cancel`, ifMatch: series.version,
      resourceId: series.id, resourceVersion: series.version, body: { reason: reason.trim() } }), 'Cours annulé.'));
  }

  async function reschedule() {
    setTouched(true);
    const body = rescheduleBody(series, sessions, timeZone);
    if (!body || busy) return;
    setError(null);
    await finish(await runner.run(createCommand({ schoolId, kind: 'rescheduleCourseSeries', path: `course-series/${series.id}/reschedule`, ifMatch: series.version,
      resourceId: series.id, resourceVersion: series.version, body }), 'Dates modifiées.'));
  }

  const open = (next: SheetDialog) => { setError(null); setTouched(false); setReason(''); setSessions(formFromSeries(series, timeZone).sessions); setDialog(next); };
  const setSession = (key: string, patch: Partial<SessionForm>) => setSessions(previous => previous.map(item => item.key === key ? { ...item, ...patch } : item));

  return <>
    <div className="button-row compact">
      <button type="button" className="button secondary" disabled={busy} onClick={() => open('reschedule')}>Modifier les dates</button>
      <button type="button" className="button quiet danger" disabled={busy} onClick={() => open('cancel')}>Annuler le cours</button>
    </div>
    {error && dialog === null && <Notice tone="error" title="Non enregistré"><p>{error}</p></Notice>}
    <ConfirmDialog open={dialog === 'cancel'} busy={busy} title="Annuler le cours" confirmLabel="Annuler le cours"
      onCancel={() => setDialog(null)} onConfirm={() => void cancelSeries()}>
      <p>{series.seatsTaken} {series.seatsTaken === 1 ? 'inscrit sera prévenu' : 'inscrits seront prévenus'}.</p>
      {error && <p className="field-error"><Symbol kind="alert" bare />{error}</p>}
      <TextArea label="Motif" value={reason} onChange={setReason} maxLength={REASON_LIMIT} rows={3} required error={touched ? reasonProblem(reason) : null} />
    </ConfirmDialog>
    <ConfirmDialog open={dialog === 'reschedule'} busy={busy} title="Modifier les dates" confirmLabel="Enregistrer les dates"
      onCancel={() => setDialog(null)} onConfirm={() => void reschedule()}>
      {error && <p className="field-error"><Symbol kind="alert" bare />{error}</p>}
      <ol className="course-sessions">{sessions.map((session, index) => {
        const problem = sessionProblems[session.key];
        return <li key={session.key} className={problem ? 'course-session invalid' : 'course-session'} aria-label={`Séance ${index + 1}`}>
          <TextField label="Date" type="date" value={session.date} onChange={date => setSession(session.key, { date })} required />
          <TextField label="Début" type="time" value={session.start} onChange={start => setSession(session.key, { start })} required />
          <TextField label="Fin" type="time" value={session.end} onChange={end => setSession(session.key, { end })} required />
          <SelectField label="Moniteur" value={session.instructor} onChange={instructor => setSession(session.key, { instructor })} options={instructors} required />
          {problem && <p className="field-error"><Symbol kind="alert" bare />{problem}</p>}
        </li>;
      })}</ol>
    </ConfirmDialog>
  </>;
}

/** Réglages des cours de l'école : délai d'annulation autonome et délai de réponse de la liste d'attente. */
export function CoursePolicyDialog({ open, catalogue, onClose, onSaved }: { open: boolean; catalogue: CourseCatalogue; onClose: () => void; onSaved: () => void }) {
  const { schoolId } = useConsole();
  const runner = useCommandRunner();
  const [form, setForm] = useState<PolicyForm>(() => policyForm(catalogue.policy));
  const [touched, setTouched] = useState(false);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { if (open) { setForm(policyForm(catalogue.policy)); setTouched(false); setError(null); } }, [open, catalogue.policy.version]);
  const problems = touched ? policyProblems(form) : {};
  const busy = runner.busy || Boolean(runner.pending);

  async function save() {
    setTouched(true);
    const body = policyBody(form);
    if (!body || busy) return;
    setError(null);
    const result = await runner.run(createCommand({ schoolId, kind: 'saveCoursePolicy', path: 'course-policy', ifMatch: catalogue.policy.version,
      resourceVersion: catalogue.policy.version, body }), 'Réglages enregistrés.');
    if (result.status === 'rejected') { runner.clearOutcome(); setError(courseErrorMessage(result.code) ?? result.message); return; }
    if (result.status === 'confirmed') { onSaved(); onClose(); }
  }

  return <ConfirmDialog open={open} busy={busy} title="Réglages des cours" confirmLabel="Enregistrer" onCancel={onClose} onConfirm={() => void save()}>
    {error && <p className="field-error"><Symbol kind="alert" bare />{error}</p>}
    <TextField label="Annulation autonome (heures avant le cours)" value={form.selfCancelHours} inputMode="numeric" required
      onChange={selfCancelHours => setForm({ ...form, selfCancelHours })} error={problems.selfCancelHours} />
    <TextField label="Réponse de la liste d’attente (minutes)" value={form.offerResponseMinutes} inputMode="numeric" required={false} placeholder="720"
      hint="Vide : liste d’attente désactivée" onChange={offerResponseMinutes => setForm({ ...form, offerResponseMinutes })} error={problems.offerResponseMinutes} />
  </ConfirmDialog>;
}
