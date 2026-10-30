import { useRef, useState } from 'react';
import { ArrowLeft, ArrowRight, Plus } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import { cancellationLabel, formatHours, hasProblems, languages, LIMITS, type CourseCatalogue, type CourseSeries } from '../../console/course-model';
import { PortalSelect } from '../components/portal-select';
import { CommandFeedback } from '../agenda/presentation';
import { useHeadingFocus } from '../agenda/use-heading-focus';
import { civilDayLabel, isSessionRefusal, keptMessage, languageLabel, sessionCountLabel } from './course-presentation';
import { CourseNotice } from './course-notice';
import { CourseTypeDialog } from './course-type-dialog';
import { SessionEditor, SessionList } from './session-parts';
import { useCourseDraft, type CourseDraft } from './use-course-draft';

const none = 'none';
const languageOptions = [{ value: none, label: 'Non précisée' }, ...languages.map(item => ({ value: item.value, label: item.label }))];

/** The school's refusal, next to what it concerns: sessions beside the session list, a stale version with its one useful action. */
function RefusalAlert({ draft, onReread }: { draft: CourseDraft; onReread: () => void }) {
  const { refusal } = draft;
  if (!refusal) return null;
  const stale = refusal.code === 'VERSION_CONFLICT';
  return <Alert variant="destructive"><AlertTitle>{stale ? 'Modifié entre-temps' : 'Non enregistré'}</AlertTitle><AlertDescription>{keptMessage(refusal.message)}</AlertDescription>
    {stale && <div className="course-actions"><Button type="button" variant="outline" disabled={draft.locked} onClick={() => { draft.setRefusal(null); onReread(); }}>Relire, garder ma saisie</Button></div>}
  </Alert>;
}

function LeaveDialog({ open, canSave, busy, onStay, onSave, onDiscard }: { open: boolean; canSave: boolean; busy: boolean; onStay: () => void; onSave: () => void; onDiscard: () => void }) {
  return <Dialog open={open} onOpenChange={(next, details) => { if (busy) { details.cancel(); return; } if (!next) onStay(); }}><DialogContent showCloseButton={!busy}>
    <DialogHeader><DialogTitle>Quitter sans enregistrer ?</DialogTitle><DialogDescription>Les modifications de ce cours ne sont pas enregistrées.</DialogDescription></DialogHeader>
    <DialogFooter><Button variant="outline" disabled={busy} onClick={onStay}>Continuer la saisie</Button>
      {canSave && <Button variant="outline" disabled={busy} onClick={onSave}>Enregistrer le brouillon et quitter</Button>}
      <Button variant="destructive" disabled={busy} onClick={onDiscard}>Abandonner</Button></DialogFooter>
  </DialogContent></Dialog>;
}

/** Draft of a series, in three compositions: the course, one session at a time, then the review that precedes publication. */
export function CourseEditor({ series, catalogue, canManage, notice, onClose, onDone, onReread }: {
  series: CourseSeries | null; catalogue: CourseCatalogue; canManage: boolean; notice: string | null; onClose: () => void; onDone: (series: CourseSeries | null, message: string) => void; onReread: () => void;
}) {
  const draft = useCourseDraft(series, catalogue, onDone);
  const { form, shown, stage, locked, runner, refusal } = draft;
  const [typeOpen, setTypeOpen] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const heading = useRef<HTMLHeadingElement>(null);
  useHeadingFocus(heading, stage.kind === 'session' ? stage.key : stage.kind, { preventScroll: true });
  const leave = () => { if (draft.dirty) setLeaving(true); else { draft.releaseGuard(); onClose(); } };
  const sessionIssue = isSessionRefusal(refusal?.code);
  const instructors = draft.instructorOptions;
  const feedback = <><CommandFeedback outcome={runner.outcome?.needsLogin ? runner.outcome : null} blocked={runner.blockedReason} />
    {refusal && !sessionIssue && <RefusalAlert draft={draft} onReread={onReread} />}</>;
  const title = form.title.trim() || 'Nouveau cours collectif';
  const policyHours = catalogue.policy.selfCancelHours;

  if (stage.kind === 'session') {
    const index = form.sessions.findIndex(item => item.key === stage.key);
    const session = form.sessions[index];
    if (!session) { draft.setStage({ kind: 'course' }); return null; }
    return <section className="course-page"><SessionEditor session={session} index={index} total={form.sessions.length} problem={shown.sessions[session.key]} instructors={instructors} timeZone={draft.timeZone} draft
      locked={locked} onChange={patch => draft.setSession(session.key, patch)} onBack={() => draft.setStage({ kind: 'course' })} {...(form.sessions.length > 1 ? { onRemove: () => draft.removeSession(session.key) } : {})} />{feedback}</section>;
  }

  if (stage.kind === 'review') {
    const sessions = [...form.sessions].sort((a, b) => `${a.date}${a.start}`.localeCompare(`${b.date}${b.start}`));
    return <section className="course-page">
      <Button variant="ghost" className="course-back" disabled={locked} onClick={() => draft.setStage({ kind: 'course' })}><ArrowLeft data-icon="inline-start" />Retour à la modification</Button>
      <header className="course-heading"><div><span className="course-eyebrow">Relire avant de publier</span><h1 ref={heading} tabIndex={-1}>{title}</h1></div></header>
      {feedback}
      <dl className="course-review">
        <div><dt>Type</dt><dd>{draft.types.find(item => item.id === form.typeId)?.title ?? '—'}</dd></div>
        {form.location.trim() && <div><dt>Lieu</dt><dd>{form.location.trim()}</dd></div>}
        <div><dt>Responsable</dt><dd>{draft.responsibleOptions.find(item => item.value === form.responsible)?.label ?? '—'}</dd></div>
        {languageLabel(form.language || null) && <div><dt>Langue</dt><dd>{languageLabel(form.language || null)}</dd></div>}
        <div><dt>Places</dt><dd>{form.capacity}{form.minimum.trim() ? ` · minimum ${form.minimum.trim()}` : ''}</dd></div>
        <div><dt>Durée</dt><dd>{sessionCountLabel(draft.overview.sessions.length)} · {formatHours(draft.overview.totalMinutes)}</dd></div>
        <div><dt>Annulation</dt><dd>{cancellationLabel(policyHours)}</dd></div>
      </dl>
      <section className="course-section" aria-labelledby="course-review-sessions"><h2 id="course-review-sessions">Séances</h2>
        {refusal && sessionIssue && <RefusalAlert draft={draft} onReread={onReread} />}
        <ol className="course-sessions course-sessions-static">{sessions.map((session, index) => <li key={session.key}><span className="course-session-index" aria-hidden="true">{index + 1}</span>
          <div className="course-session-main"><strong>{civilDayLabel(session.date)}<span className="course-session-time"> · {session.start}–{session.end}</span></strong>
            <span className="course-muted">{instructors.find(item => item.value === session.instructor)?.label}{!session.attendanceRequired && ' · '}{!session.attendanceRequired && <Badge variant="secondary">Facultative</Badge>}</span></div></li>)}</ol>
      </section>
      {form.description.trim() && <p className="course-prose">{form.description.trim()}</p>}
      {form.conditions.trim() && <section className="course-section"><h2>Conditions</h2><p className="course-prose">{form.conditions.trim()}</p></section>}
      <div className="course-footer"><Button variant="ghost" disabled={locked} onClick={() => draft.setStage({ kind: 'course' })}><ArrowLeft data-icon="inline-start" />Modifier</Button>
        <Button variant="outline" disabled={locked || !canManage} onClick={() => void draft.saveDraft()}>Enregistrer le brouillon</Button>
        <Button disabled={locked || !canManage || Boolean(runner.blockedReason)} onClick={() => void draft.publish()}>{runner.busy ? 'Confirmation…' : 'Publier le cours'}</Button></div>
    </section>;
  }

  return <section className="course-page">
    <CourseNotice message={notice} />
    <Button variant="ghost" className="course-back" disabled={locked} onClick={leave}><ArrowLeft data-icon="inline-start" />Retour à l’agenda</Button>
    <header className="course-heading"><div><span className="course-eyebrow">Cours collectif</span><h1 ref={heading} tabIndex={-1}>{title}</h1></div>{series && <Badge variant="secondary">Brouillon</Badge>}</header>
    {!canManage && <Alert><AlertTitle>Lecture seule</AlertTitle><AlertDescription>Vos accès ne permettent pas de gérer les cours.</AlertDescription></Alert>}
    {feedback}
    <form className="course-form" noValidate onSubmit={event => { event.preventDefault(); draft.review(); }}>
      <FieldGroup>
        <div className="course-type-row">
          <PortalSelect id="course-type" label="Type" className="course-grow" value={form.typeId || null} onValueChange={value => draft.set('typeId', value ?? '')} placeholder="Choisir un type"
            options={draft.types.map(type => ({ value: type.id, label: type.title }))} disabled={locked || !canManage} {...(shown.fields.typeId ? { error: shown.fields.typeId } : {})} />
          <Button type="button" variant="outline" disabled={locked || !canManage} onClick={() => setTypeOpen(true)}><Plus data-icon="inline-start" />Nouveau type</Button>
        </div>
        <Field data-invalid={Boolean(shown.fields.title)}><FieldLabel htmlFor="course-title">Titre</FieldLabel>
          <Input id="course-title" value={form.title} maxLength={LIMITS.title} disabled={locked || !canManage} aria-invalid={Boolean(shown.fields.title)} onChange={event => draft.set('title', event.target.value)} />
          {shown.fields.title && <FieldError>{shown.fields.title}</FieldError>}</Field>
        <Field data-invalid={Boolean(shown.fields.description)}><FieldLabel htmlFor="course-description">Description (facultatif)</FieldLabel>
          <Textarea id="course-description" value={form.description} maxLength={LIMITS.description} rows={3} disabled={locked || !canManage} onChange={event => draft.set('description', event.target.value)} />
          {shown.fields.description && <FieldError>{shown.fields.description}</FieldError>}</Field>
        <Field data-invalid={Boolean(shown.fields.location)}><FieldLabel htmlFor="course-location">Lieu (facultatif)</FieldLabel>
          <Input id="course-location" value={form.location} maxLength={LIMITS.location} disabled={locked || !canManage} onChange={event => draft.set('location', event.target.value)} />
          {shown.fields.location && <FieldError>{shown.fields.location}</FieldError>}</Field>
        <PortalSelect id="course-responsible" label="Responsable" value={form.responsible || null} onValueChange={value => draft.set('responsible', value ?? '')} placeholder="Choisir un responsable"
          options={draft.responsibleOptions} searchable={draft.responsibleOptions.length > 6} disabled={locked || !canManage} {...(shown.fields.responsible ? { error: shown.fields.responsible } : {})} />
        <div className="course-field-row course-field-row-three">
          <Field data-invalid={Boolean(shown.fields.capacity)}><FieldLabel htmlFor="course-capacity">Places</FieldLabel>
            <Input id="course-capacity" inputMode="numeric" value={form.capacity} disabled={locked || !canManage} aria-invalid={Boolean(shown.fields.capacity)} onChange={event => draft.set('capacity', event.target.value)} />
            {shown.fields.capacity && <FieldError>{shown.fields.capacity}</FieldError>}</Field>
          <Field data-invalid={Boolean(shown.fields.minimum)}><FieldLabel htmlFor="course-minimum">Minimum (facultatif)</FieldLabel>
            <Input id="course-minimum" inputMode="numeric" value={form.minimum} disabled={locked || !canManage} aria-invalid={Boolean(shown.fields.minimum)} onChange={event => draft.set('minimum', event.target.value)} />
            {shown.fields.minimum && <FieldError>{shown.fields.minimum}</FieldError>}</Field>
          <PortalSelect id="course-language" label="Langue" value={form.language || none} onValueChange={value => draft.set('language', value === none || value === null ? '' : value as typeof form.language)} options={languageOptions} disabled={locked || !canManage} />
        </div>
        <Field data-invalid={Boolean(shown.fields.conditions)}><FieldLabel htmlFor="course-conditions">Conditions (facultatif)</FieldLabel>
          <Textarea id="course-conditions" value={form.conditions} maxLength={LIMITS.conditions} rows={3} disabled={locked || !canManage} onChange={event => draft.set('conditions', event.target.value)} />
          {shown.fields.conditions && <FieldError>{shown.fields.conditions}</FieldError>}</Field>
      </FieldGroup>
      <section className="course-section" aria-labelledby="course-sessions-title">
        <h2 id="course-sessions-title">Séances</h2>
        {shown.fields.sessions && <FieldError>{shown.fields.sessions}</FieldError>}
        {refusal && sessionIssue && <RefusalAlert draft={draft} onReread={onReread} />}
        <SessionList sessions={form.sessions} problems={shown.sessions} instructors={instructors} locked={locked || !canManage}
          onEdit={key => draft.setStage({ kind: 'session', key })} {...(canManage ? { onAdd: draft.addSession } : {})} />
      </section>
      {canManage && <div className="course-footer"><Button type="button" variant="ghost" disabled={locked} onClick={leave}>Fermer</Button>
        <Button type="button" variant="outline" disabled={locked} onClick={() => void draft.saveDraft()}>Enregistrer le brouillon</Button>
        <Button type="submit" disabled={locked}>Relire et publier<ArrowRight data-icon="inline-end" /></Button></div>}
    </form>
    <CourseTypeDialog open={typeOpen} existing={draft.types} onClose={() => setTypeOpen(false)} onCreated={type => { if (type) { draft.addType(type); draft.set('typeId', type.id); } setTypeOpen(false); }} />
    <LeaveDialog open={leaving} canSave={!hasProblems(draft.problems) && canManage} busy={locked} onStay={() => setLeaving(false)}
      onSave={() => void draft.saveDraft().then(saved => { if (saved) { setLeaving(false); onClose(); } })} onDiscard={() => { draft.releaseGuard(); onClose(); }} />
  </section>;
}
