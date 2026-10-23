import { useEffect, useId, useMemo, useRef, useState } from 'react';
import { z } from 'zod';
import { createCommand, instantToSchoolTime } from '../command-core';
import { readSchool } from '../school-api';
import { CheckField, ConfirmDialog, Facts, Notice, SelectField, StatusBadge, Symbol, TextArea, TextField } from '../ui';
import { useCommandRunner, useConsole, useLoad, useUnsavedChanges } from './context';
import { LoadState, OutcomeNotice } from './layout';
import {
  LIMITS, cancellationLabel, capacityProblem, courseCatalogueSchema, courseErrorMessage, courseSeriesSchema, courseTypeSchema, emptyForm, emptySession,
  formFromSeries, formatHours, hasProblems, languages, preview, seriesBody, typeProblem, validate,
  type CourseCatalogue, type CourseSeries, type SeriesForm, type SessionForm,
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
export function CourseWorkspace({ seriesId, catalogue, onClose, onSaved }: {
  seriesId: string | null; catalogue: CourseCatalogue; onClose: () => void; onSaved: (series: CourseSeries | null) => void;
}) {
  const { schoolId } = useConsole();
  const loaded = useLoad(async () => seriesId ? readSchool(schoolId, `course-series/${seriesId}`, courseSeriesSchema) : null, [schoolId, seriesId], `${schoolId}/${seriesId ?? 'new'}`);
  return <LoadState loaded={loaded} label="Lecture du cours…">{series => series && series.status !== 'DRAFT'
    ? <CourseSheet series={series} onClose={onClose} onSaved={onSaved} reload={loaded.reload} />
    : <CourseEditor key={series ? `${series.id}/${series.version}` : 'new'} series={series} catalogue={catalogue} onClose={onClose} onSaved={onSaved} />}</LoadState>;
}

function CourseEditor({ series, catalogue: initial, onClose, onSaved }: {
  series: CourseSeries | null; catalogue: CourseCatalogue; onClose: () => void; onSaved: (series: CourseSeries | null) => void;
}) {
  const { schoolId, school, membership } = useConsole();
  const timeZone = school.timeZone;
  const uid = useId();
  const runner = useCommandRunner();
  const [catalogue, setCatalogue] = useState(initial);
  const [current, setCurrent] = useState(series);
  const baseline = useMemo(() => series ? formFromSeries(series, timeZone)
    : emptyForm(catalogue, catalogue.instructors.some(item => item.membershipId === membership.membershipId) ? membership.membershipId : ''), []);
  const [form, setForm] = useState<SeriesForm>(baseline);
  const [touched, setTouched] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [newType, setNewType] = useState<{ title: string; description: string } | null>(null);
  const dirty = JSON.stringify(form) !== JSON.stringify(baseline) || current?.id !== series?.id;
  useUnsavedChanges(dirty && JSON.stringify(form) !== JSON.stringify(current ? formFromSeries(current, timeZone) : baseline));

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

  async function saveDraft() {
    const saved = await save();
    if (saved !== undefined) onSaved(saved);
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
    onSaved(parsed.success ? parsed.data.data : null);
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
      <button type="button" className="button quiet" onClick={onClose}>Fermer</button>
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
          return <li key={session.key} className={problem ? 'course-session invalid' : 'course-session'} aria-label={`Séance ${index + 1}`}>
            <TextField label="Date" type="date" value={session.date} onChange={date => setSession(session.key, { date })} required />
            <TextField label="Début" type="time" value={session.start} onChange={start => setSession(session.key, { start })} required />
            <TextField label="Fin" type="time" value={session.end} onChange={end => setSession(session.key, { end })} required />
            <SelectField label="Moniteur" value={session.instructor} onChange={instructor => setSession(session.key, { instructor })} options={instructors} required />
            <CheckField label="Présence obligatoire" checked={session.attendanceRequired} onChange={attendanceRequired => setSession(session.key, { attendanceRequired })} />
            {form.sessions.length > 1 && <button type="button" className="button quiet" aria-label={`Retirer la séance ${index + 1}`}
              onClick={() => set('sessions', form.sessions.filter(item => item.key !== session.key))}>Retirer</button>}
            {problem && <p className="field-error"><Symbol kind="alert" bare />{problem}</p>}
          </li>;
        })}</ol>
        {form.sessions.length < LIMITS.sessions && <button type="button" className="button secondary"
          onClick={() => set('sessions', [...form.sessions, emptySession(form.sessions.at(-1))])}><Symbol kind="plus" bare />Ajouter une séance</button>}
      </fieldset>

      <section className="course-preview" aria-labelledby={`${uid}-preview`}>
        <h3 id={`${uid}-preview`} className="section-title">Aperçu</h3>
        {overview.sessions.length === 0 ? <p className="caption">Aucune séance complète.</p> : <>
          <ul className="course-preview-list">{overview.sessions.map(item => <li key={item.key}>
            <time dateTime={new Date(item.start).toISOString()}>{formatDay(item.start, timeZone)}</time>{' '}
            {formatClock(item.start, timeZone)}–{formatClock(item.end, timeZone)}
          </li>)}</ul>
          <p className="row-meta">{overview.sessions.length} {overview.sessions.length === 1 ? 'séance' : 'séances'} · {formatHours(overview.totalMinutes)}</p>
        </>}
        <p className="row-meta">{cancellationLabel(policyHours)}</p>
      </section>

      {catalogue.canManage && <div className="button-row">
        <button type="submit" className="button secondary" disabled={busy} aria-busy={runner.busy}>Enregistrer le brouillon</button>
        <button type="button" className="button primary" disabled={busy} onClick={() => void publish()}>Publier</button>
      </div>}
    </form>
  </section>;
}

/** Cours publié : lecture, seule la capacité se change ici. */
function CourseSheet({ series, onClose, onSaved, reload }: { series: CourseSeries; onClose: () => void; onSaved: (series: CourseSeries | null) => void; reload: () => void }) {
  const { schoolId, school } = useConsole();
  const timeZone = school.timeZone;
  const runner = useCommandRunner();
  const [capacity, setCapacity] = useState(String(series.capacity));
  const [error, setError] = useState<string | null>(null);
  const problem = capacity === String(series.capacity) ? null : capacityProblem(capacity, series);
  const busy = runner.busy || Boolean(runner.pending);
  useUnsavedChanges(capacity !== String(series.capacity));

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
    onSaved(parsed.success ? parsed.data.data : null);
  }

  const status = series.status === 'CANCELLED' ? 'Annulé' : series.status === 'CLOSED' ? 'Clos' : null;
  return <section className="course-editor section-stack" aria-label={series.title}>
    <div className="course-editor-heading">
      <h2 className="section-title">{series.title}</h2>
      {status && <StatusBadge tone="neutral" symbol="ban">{status}</StatusBadge>}
      <button type="button" className="button quiet" onClick={onClose}>Fermer</button>
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
    <ol className="course-preview-list">{series.occurrences.map(item => <li key={item.id}>
      <time dateTime={item.startsAt}>{formatDay(Date.parse(item.startsAt), timeZone)}</time>{' '}
      {instantToSchoolTime(item.startsAt, timeZone).slice(11)}–{instantToSchoolTime(item.endsAt, timeZone).slice(11)}
      <span className="row-meta"> · {item.instructorDisplayName}{item.attendanceRequired ? '' : ' · Facultative'}</span>
    </li>)}</ol>
    {series.canManage && series.status === 'PUBLISHED' && <form className="course-capacity" noValidate onSubmit={event => { event.preventDefault(); void change(); }}>
      <TextField label="Capacité" value={capacity} onChange={value => { setError(null); setCapacity(value); }} inputMode="numeric" required error={problem} disabled={busy} />
      <button type="submit" className="button secondary" disabled={busy || problem !== null || capacity === String(series.capacity)} aria-busy={runner.busy}>Changer la capacité</button>
    </form>}
  </section>;
}
