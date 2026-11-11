import { useEffect, useMemo, useRef, useState } from 'react';
import { ArrowLeft, ArrowRight } from 'lucide-react';
import { createCommand } from '../../command-core';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { courseErrorMessage, formFromSeries, rescheduleBody, validate, type CourseCatalogue, type CourseSeries, type SessionForm } from '../../console/course-model';
import { useCommandRunner, useConsole, useUnsavedChanges } from '../../console/context';
import { CommandFeedback } from '../agenda/presentation';
import { useHeadingFocus } from '../agenda/use-heading-focus';
import { confirmedSeries } from './course-catalogue';
import { changedSessions, civilDayLabel, seatsLabel, sessionCountLabel } from './course-presentation';
import { SessionEditor, SessionList } from './session-parts';
import { DiscardDialog } from '../availability/schedule-feedback';

type Stage = { kind: 'list' } | { kind: 'session'; key: string } | { kind: 'review' };

/**
 * New dates for a published series: the same sessions, the same identifiers, only date, hours and instructor move.
 * The people enrolled are named before anything is sent; nobody is cancelled, and a refusal leaves the dates as typed.
 */
export function CourseReschedule({ series, catalogue, onBack, onChanged, onReread }: {
  series: CourseSeries; catalogue: CourseCatalogue; onBack: () => void; onChanged: (series: CourseSeries | null, message: string) => void; onReread: () => void;
}) {
  const { schoolId, school } = useConsole();
  const timeZone = school.timeZone;
  const runner = useCommandRunner();
  // `base` est la version sur laquelle les dates saisies reposent : elle seule part dans If-Match. Une relecture plus récente ne
  // l'avance que si les dates de l'école n'ont pas bougé ou si rien n'est saisi ; sinon la personne choisit (#443, même règle que #422).
  const [base, setBase] = useState(series);
  const opened = useMemo(() => formFromSeries(base, timeZone), [base]);
  const [sessions, setSessions] = useState<SessionForm[]>(opened.sessions);
  const newer = series.version > base.version ? series : null;
  const newerSessions = useMemo(() => newer ? formFromSeries(newer, timeZone).sessions : null, [newer]);
  const schoolMoved = newerSessions !== null && changedSessions(opened.sessions, newerSessions).size > 0;
  const mineChanged = changedSessions(opened.sessions, sessions).size > 0;
  const concurrent = newer !== null && schoolMoved && mineChanged ? newer : null;
  useEffect(() => {
    if (!newer || !newerSessions || concurrent) return;
    if (!mineChanged) setSessions(newerSessions);
    setBase(newer);
  }, [newer, concurrent, mineChanged]);
  const resolveConcurrent = (keep: 'mine' | 'theirs') => {
    if (!concurrent || !newerSessions) return;
    if (keep === 'theirs') setSessions(newerSessions);
    setBase(concurrent); setRefusal(null);
  };
  const [stage, setStage] = useState<Stage>({ kind: 'list' });
  const [touched, setTouched] = useState(false), [discard, setDiscard] = useState(false);
  const [refusal, setRefusal] = useState<{ code: string; message: string } | null>(null);
  const heading = useRef<HTMLHeadingElement>(null);
  useHeadingFocus(heading, stage.kind, { preventScroll: true });
  const changed = changedSessions(opened.sessions, sessions);
  const dirty = changed.size > 0;
  const locked = runner.busy || Boolean(runner.pending) || concurrent !== null;
  useUnsavedChanges(dirty && !runner.pending);
  const problems = touched ? validate({ ...opened, sessions }, timeZone).sessions : {};
  const instructors = useMemo(() => {
    const options = new Map<string, string>(catalogue.instructors.map(item => [item.membershipId, item.displayName]));
    for (const item of series.occurrences) if (!options.has(item.instructorMembershipId)) options.set(item.instructorMembershipId, item.instructorDisplayName || 'Moniteur');
    return [...options].map(([value, label]) => ({ value, label }));
  }, [catalogue, series]);
  const setSession = (key: string, patch: Partial<SessionForm>) => { setRefusal(null); setSessions(previous => previous.map(item => item.key === key ? { ...item, ...patch } : item)); };
  const back = () => { if (locked) return; if (dirty) setDiscard(true); else onBack(); };
  const review = () => {
    setTouched(true);
    if (!dirty || !rescheduleBody(base, sessions, timeZone)) return;
    setStage({ kind: 'review' });
  };
  async function save() {
    const body = rescheduleBody(base, sessions, timeZone);
    if (!body || locked) return;
    setRefusal(null);
    const result = await runner.run(createCommand({ schoolId, kind: 'rescheduleCourseSeries', path: `course-series/${base.id}/reschedule`, ifMatch: base.version,
      resourceId: base.id, resourceVersion: base.version, body }), 'Les dates sont modifiées.');
    if (result.status === 'rejected') { if (!result.needsLogin) runner.clearOutcome(); setRefusal({ code: result.code, message: courseErrorMessage(result.code) ?? result.message }); setStage({ kind: 'list' }); return; }
    if (result.status === 'pending') { onBack(); return; }
    runner.clearOutcome(); onChanged(confirmedSeries(result.body), 'Les dates sont modifiées.');
  }
  const stale = refusal?.code === 'VERSION_CONFLICT';
  const feedback = <>
    {concurrent && <Alert variant="destructive"><AlertTitle>Modifié ailleurs</AlertTitle><AlertDescription>Les dates ont changé à l’école. Choisissez les dates à garder.</AlertDescription>
      <div className="course-actions"><Button type="button" variant="outline" onClick={() => resolveConcurrent('mine')}>Garder mes dates</Button>
        <Button type="button" variant="outline" onClick={() => resolveConcurrent('theirs')}>Prendre les dates de l’école</Button></div></Alert>}
    <CommandFeedback outcome={runner.outcome?.needsLogin ? runner.outcome : null} blocked={runner.blockedReason} />
    {refusal && <Alert variant="destructive"><AlertTitle>{stale ? 'Modifié entre-temps' : 'Dates non enregistrées'}</AlertTitle><AlertDescription>{/conservé/.test(refusal.message) ? refusal.message : `${refusal.message} Vos dates sont conservées.`}</AlertDescription>
      {stale && <div className="course-actions"><Button type="button" variant="outline" disabled={locked} onClick={() => { setRefusal(null); onReread(); }}>Relire, garder mes dates</Button></div>}</Alert>}</>;

  if (stage.kind === 'session') {
    const index = sessions.findIndex(item => item.key === stage.key);
    const session = sessions[index];
    if (!session) { setStage({ kind: 'list' }); return null; }
    return <section className="course-page"><SessionEditor session={session} index={index} total={sessions.length} problem={problems[session.key]} instructors={instructors} timeZone={timeZone} draft={false}
      locked={locked} onChange={patch => setSession(session.key, patch)} onBack={() => setStage({ kind: 'list' })} /></section>;
  }
  if (stage.kind === 'review') return <section className="course-page">
    <Button variant="ghost" className="course-back" disabled={locked} onClick={() => setStage({ kind: 'list' })}><ArrowLeft data-icon="inline-start" />Retour aux séances</Button>
    <header className="course-heading"><div><span className="course-eyebrow">{series.title}</span><h1 ref={heading} tabIndex={-1}>Relire les nouvelles dates</h1></div></header>
    {feedback}
    <dl className="course-review course-review-compact"><div><dt>Séances</dt><dd>{changed.size} sur {sessionCountLabel(sessions.length)} changées</dd></div><div><dt>Inscrits</dt><dd>{series.seatsTaken === 0 ? 'Aucun inscrit' : `${seatsLabel(series.seatsTaken)} concernés`}</dd></div></dl>
    <ol className="course-sessions course-sessions-static">{sessions.map((session, index) => changed.has(session.key) && <li key={session.key} data-changed="true"><span className="course-session-index" aria-hidden="true">{index + 1}</span>
      <div className="course-session-main"><strong>{civilDayLabel(session.date)}<span className="course-session-time"> · {session.start}–{session.end}</span></strong>
        <span className="course-muted">{instructors.find(item => item.value === session.instructor)?.label}</span>
        <span className="course-session-before"><span className="visually-hidden">Avant : </span><del>{civilDayLabel(opened.sessions[index]!.date)} · {opened.sessions[index]!.start}–{opened.sessions[index]!.end}</del></span></div></li>)}</ol>
    <div className="course-footer"><Button variant="ghost" disabled={locked} onClick={() => setStage({ kind: 'list' })}><ArrowLeft data-icon="inline-start" />Modifier</Button>
      <Button disabled={locked || Boolean(runner.blockedReason)} onClick={() => void save()}>{runner.busy ? 'Confirmation…' : 'Enregistrer les dates'}</Button></div>
  </section>;

  return <section className="course-page">
    <Button variant="ghost" className="course-back" disabled={locked} onClick={back}><ArrowLeft data-icon="inline-start" />Retour au cours</Button>
    <header className="course-heading"><div><span className="course-eyebrow">{series.title}</span><h1 ref={heading} tabIndex={-1}>Modifier les dates</h1></div></header>
    {series.seatsTaken > 0 && <Alert><AlertTitle>{seatsLabel(series.seatsTaken)} concernés</AlertTitle></Alert>}
    {feedback}
    <SessionList sessions={sessions} problems={problems} instructors={instructors} before={opened.sessions} changed={changed} locked={locked} onEdit={key => setStage({ kind: 'session', key })} />
    <div className="course-footer"><Button variant="ghost" disabled={locked} onClick={back}>Annuler</Button><Button disabled={locked || !dirty} onClick={review}>Relire<ArrowRight data-icon="inline-end" /></Button></div>
    <DiscardDialog open={discard} onCancel={() => setDiscard(false)} onDiscard={() => { setDiscard(false); onBack(); }} />
  </section>;
}
