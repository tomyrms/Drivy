import { useRef, useState } from 'react';
import { ArrowLeft, ArrowRight, CalendarDays, Check, Clock3, MapPin, Pencil, UserRound } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldDescription, FieldGroup, FieldLabel, FieldLegend, FieldSet } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import { formatDayHeading, formatTimeRange, civilDateIn, lessonPhase } from '../../agenda-model';
import { canEditPlannedLesson, lessonCommercial, type PlanningLesson } from '../../lesson-planning-model';
import { useConsole, useLoad } from '../../console/context';
import { PortalSelect } from '../components/portal-select';
import { CommandFeedback, dateTime, money, phaseLabels, ReadFeedback } from './presentation';
import { readPlanningCatalogue, useLesson, useLessonEditor, type PlanningCatalogue } from './use-lesson';
import { cancellationReasons, useCancellation } from './use-cancellation';
import { useHeadingFocus } from './use-heading-focus';

export function LessonWorkspace({ lessonId, onClose, onSaved, onDossier }: { lessonId: string | null; onClose: () => void; onSaved: () => void; onDossier: (learnerId: string, lessonId: string) => void }) {
  const context = useConsole();
  const state = useLesson(lessonId, onSaved);
  const lesson = state.loaded.data;
  const canWrite = context.membership.roles.includes('ADMIN') || context.membership.roles.includes('INSTRUCTOR') && (!lesson || context.membership.membershipId === lesson.instructorMembershipId);
  if (state.editing && canWrite && (!lessonId || lesson && canEditPlannedLesson(lesson))) return <LessonEditorLoader original={lesson ?? undefined} onClose={() => lessonId ? state.setEditing(false) : onClose()} onSaved={() => { state.setEditing(false); state.saved(lesson); if (!lessonId) onClose(); }} />;
  return <section className="agenda-page"><ReadFeedback loaded={state.loaded} label="Lecture de la leçon" />
    {state.refreshing && <Alert><AlertTitle>Changement confirmé</AlertTitle><AlertDescription>Actualisation de la fiche en cours.</AlertDescription></Alert>}
    {lesson ? <LessonDetail lesson={lesson} refreshing={state.refreshing} onClose={onClose} onEdit={() => state.setEditing(true)} onSaved={() => state.saved(lesson)} onDossier={() => onDossier(lesson.learnerId, lesson.id)} /> : <Button variant="ghost" className="agenda-back" onClick={onClose}><ArrowLeft data-icon="inline-start" />Retour à l’agenda</Button>}
    {!canWrite && !lessonId && <Alert><AlertTitle>Planification indisponible</AlertTitle><AlertDescription>Votre rôle ne permet pas de planifier une leçon.</AlertDescription></Alert>}
  </section>;
}

function LessonDetail({ lesson, refreshing, onClose, onEdit, onSaved, onDossier }: { lesson: PlanningLesson; refreshing: boolean; onClose: () => void; onEdit: () => void; onSaved: () => void; onDossier: () => void }) {
  const state = useCancellation(lesson, onSaved);
  const heading = useRef<HTMLHeadingElement>(null);
  useHeadingFocus(heading);
  const phase = lessonPhase(lesson);
  return <>
    <Button className="agenda-back" variant="ghost" onClick={onClose} disabled={state.locked}><ArrowLeft data-icon="inline-start" />Retour à l’agenda</Button>
    <header className="agenda-heading"><div><span className="agenda-eyebrow">Leçon individuelle</span><h1 ref={heading} tabIndex={-1}>{lesson.learnerDisplayName}</h1></div>{state.editable && <Button onClick={onEdit} disabled={state.locked || refreshing}><Pencil data-icon="inline-start" />Modifier la leçon</Button>}</header>
    <CommandFeedback outcome={state.runner.outcome} blocked={state.runner.blockedReason} />
    {lesson.permitWarning && <Alert><AlertTitle>Permis à vérifier</AlertTitle></Alert>}
    <div className="agenda-detail-layout"><div className="agenda-detail-main"><section className="agenda-appointment-read"><div className="agenda-calendar-mark"><CalendarDays aria-hidden="true" /></div><div><span className="agenda-eyebrow">{phaseLabels[phase]}</span><h2>{formatDayHeading(civilDateIn(lesson.timeZone, Date.parse(lesson.plannedStart)))}</h2><p>{formatTimeRange(lesson.plannedStart, lesson.plannedEnd, lesson.timeZone)}</p></div></section>
      <section><h2>Le rendez-vous</h2><dl className="agenda-detail-facts"><div><dt><UserRound aria-hidden="true" />Moniteur</dt><dd>{lesson.instructorDisplayName}</dd></div><div><dt><MapPin aria-hidden="true" />Lieu</dt><dd>{lesson.meetingPoint || 'Non précisé'}</dd></div><div><dt><Clock3 aria-hidden="true" />Durée prévue</dt><dd>{(Date.parse(lesson.plannedEnd) - Date.parse(lesson.plannedStart)) / 60000} min</dd></div>{lesson.actualStart && <div><dt>Début réel</dt><dd>{dateTime(lesson.actualStart, lesson.timeZone)}</dd></div>}{lesson.actualEnd && <div><dt>Fin réelle</dt><dd>{dateTime(lesson.actualEnd, lesson.timeZone)}</dd></div>}</dl></section>
      <div className="agenda-actions"><Button variant="outline" onClick={onDossier} disabled={state.locked}>Ouvrir la fiche élève<ArrowRight data-icon="inline-end" /></Button>{state.editable && <Button variant="ghost" onClick={state.open} disabled={state.locked || refreshing}>Annuler la leçon</Button>}</div>
    </div><aside className="agenda-context"><span className="agenda-eyebrow">Prix convenu</span><p className="agenda-price">{money(lesson.priceCentsSnapshot)}</p><dl className="agenda-facts"><div><dt>Mode</dt><dd>{lesson.commercialSelection.mode === 'ENTITLEMENT' ? 'Droit prépayé' : 'À la leçon'}</dd></div><div><dt>Temps de battement</dt><dd>{lesson.bufferMinutesSnapshot} min</dd></div></dl><Badge variant="secondary">Conditions enregistrées</Badge></aside></div>
    <Dialog open={!!state.target && !state.discard} onOpenChange={(open, details) => { if (state.locked) { details.cancel(); return; } if (!open) state.close(); }}><DialogContent showCloseButton={!state.locked}><DialogHeader><DialogTitle>Annuler cette leçon ?</DialogTitle><DialogDescription>{state.target?.learnerDisplayName} · {state.target && dateTime(state.target.plannedStart, state.target.timeZone)}</DialogDescription></DialogHeader>
      <FieldGroup><PortalSelect id="lesson-cancel-reason" label="Motif" options={cancellationReasons} value={state.reason} onValueChange={value => state.setReason(value ?? 'LEARNER_REQUEST')} disabled={state.locked} /><Field><FieldLabel htmlFor="lesson-cancel-comment">Commentaire</FieldLabel><Textarea id="lesson-cancel-comment" value={state.comment} onChange={event => state.setComment(event.target.value)} rows={3} maxLength={1000} disabled={state.locked} /></Field></FieldGroup>
      <CommandFeedback outcome={state.runner.outcome} blocked={state.runner.blockedReason} />{state.problem && <Alert variant="destructive"><AlertTitle>Actualisation impossible</AlertTitle><AlertDescription>{state.problem}</AlertDescription></Alert>}
      {state.runner.outcome?.code === 'VERSION_CONFLICT' && <Button variant="outline" disabled={state.locked} onClick={() => void state.reread()}>Relire la leçon, conserver le motif</Button>}
      <DialogFooter><Button variant="outline" disabled={state.locked} onClick={state.close}>Retour</Button><Button variant="destructive" disabled={state.locked || !!state.runner.blockedReason || !!state.problem} onClick={() => void state.cancel()}>{state.runner.busy ? 'Confirmation…' : 'Confirmer l’annulation'}</Button></DialogFooter>
    </DialogContent></Dialog>
    <DiscardDialog open={state.discard} onCancel={() => state.setDiscard(false)} onDiscard={state.reset} />
  </>;
}

function LessonEditorLoader({ original, onClose, onSaved }: { original: PlanningLesson | undefined; onClose: () => void; onSaved: () => void }) {
  const { schoolId, routeQuery } = useConsole();
  const catalogue = useLoad(() => readPlanningCatalogue(schoolId), [schoolId], undefined, 'planning-catalogue');
  return catalogue.data && catalogue.status === 'ready' ? <LessonEditor original={original} learnerId={routeQuery?.learner} catalogue={catalogue.data} onClose={onClose} onSaved={onSaved} /> : <section className="agenda-page"><Button variant="ghost" className="agenda-back" onClick={onClose}><ArrowLeft data-icon="inline-start" />Retour</Button><ReadFeedback loaded={catalogue} label="Lecture des élèves et conditions" /></section>;
}

function LessonEditor({ original: loadedOriginal, learnerId, catalogue, onClose, onSaved }: { original: PlanningLesson | undefined; learnerId: string | undefined; catalogue: PlanningCatalogue; onClose: () => void; onSaved: () => void }) {
  const state = useLessonEditor(loadedOriginal, learnerId, catalogue, () => { state.release(); onSaved(); });
  const original = state.original;
  const [discard, setDiscard] = useState(false);
  const heading = useRef<HTMLHeadingElement>(null);
  useHeadingFocus(heading, state.step, { preventScroll: true });
  const close = () => { if (state.locked) return; if (state.dirty) setDiscard(true); else { state.release(); onClose(); } };
  const name = catalogue.learners.find(item => item.id === state.form.learnerId)?.displayName ?? original?.learnerDisplayName ?? 'Nouvelle leçon';
  const instructorName = catalogue.members.find(item => item.id === state.form.instructorId)?.displayName ?? original?.instructorDisplayName ?? 'À choisir';
  const steps = [{ key: 'people', label: 'Participants' }, { key: 'appointment', label: 'Rendez-vous' }, { key: 'review', label: 'Relire' }] as const;
  const stepIndex = steps.findIndex(item => item.key === state.step);
  const setLocal = (value: string) => { state.change('localStart', value); state.change('localChoice', ''); };
  const originalDuration = original ? (Date.parse(original.plannedEnd) - Date.parse(original.plannedStart)) / 60000 : null;
  return <section className="agenda-page"><Button variant="ghost" className="agenda-back" disabled={state.locked} onClick={close}><ArrowLeft data-icon="inline-start" />{original ? 'Retour à la leçon' : 'Retour à l’agenda'}</Button>
    <header className="agenda-heading"><div><span className="agenda-eyebrow">{original ? name : 'Leçon individuelle'}</span><h1>{original ? 'Modifier la leçon' : 'Planifier une leçon'}</h1></div></header>
    <div className="agenda-editor-layout"><aside className="agenda-stepper" aria-label="Étapes de planification"><ol>{steps.map((item, index) => <li key={item.key} data-current={state.step === item.key}><Button variant="ghost" disabled={state.locked || index >= stepIndex || !!original && item.key === 'people'} onClick={() => state.setStep(item.key)} aria-current={state.step === item.key ? 'step' : undefined}><span className="agenda-step-number">{index < stepIndex ? <Check aria-hidden="true" /> : index + 1}</span><span>{item.label}</span></Button></li>)}</ol><div className="agenda-step-context"><CalendarDays aria-hidden="true" /><strong>{state.school.name}</strong><span>{state.school.timeZone}</span></div></aside>
      <form className="agenda-editor-body" onSubmit={event => { event.preventDefault(); if (state.step === 'people') state.next(); else if (state.step === 'appointment') void state.verify(); else void state.submit(); }}>
        <div className="agenda-step-content"><h2 tabIndex={-1} ref={heading}>{state.step === 'people' ? 'Avec qui ?' : state.step === 'appointment' ? 'Quand et où ?' : 'Confirmer le rendez-vous'}</h2>
          <CommandFeedback outcome={state.runner.outcome} blocked={state.runner.blockedReason} />
          {state.problem && <Alert variant="destructive"><AlertTitle>Vérifiez la proposition</AlertTitle><AlertDescription>{state.problem}</AlertDescription></Alert>}
          {state.runner.outcome?.code === 'VERSION_CONFLICT' && <Button type="button" variant="outline" disabled={state.locked} onClick={() => void state.rereadVersion()}>Relire la version actuelle</Button>}
          {catalogue.truncated && <Alert><AlertTitle>Lecture incomplète</AlertTitle><AlertDescription>La planification est bloquée jusqu’à une lecture complète du catalogue.</AlertDescription></Alert>}
          <ReadFeedback loaded={state.trainingRead} label="Lecture des formations" /><ReadFeedback loaded={state.assignmentRead} label="Lecture des affectations" />
          {state.step === 'people' && <FieldGroup><PortalSelect id="lesson-learner" label="Élève" value={state.form.learnerId || null} onValueChange={value => state.chooseLearner(value ?? '')} options={state.learnerOptions} searchable disabled={state.locked} placeholder="Choisir un élève" />
            <PortalSelect id="lesson-training" label="Formation" value={state.form.trainingId || null} onValueChange={value => state.chooseTraining(value ?? '')} options={state.trainingOptions} disabled={state.locked || !state.form.learnerId || state.trainingRead.status !== 'ready'} placeholder="Choisir une formation active" />
            <PortalSelect id="lesson-instructor" label="Moniteur" value={state.form.instructorId || null} onValueChange={value => state.change('instructorId', value ?? '')} options={state.instructorOptions} searchable disabled={state.locked || !state.form.trainingId || state.assignmentRead.status !== 'ready'} placeholder="Choisir un moniteur affecté" />
            {state.form.trainingId && state.assignmentRead.status === 'ready' && !state.instructorOptions.length && <Alert><AlertTitle>Aucun moniteur affecté disponible</AlertTitle><AlertDescription>Une affectation active est nécessaire pour planifier la leçon.</AlertDescription></Alert>}
          </FieldGroup>}
          {state.step === 'appointment' && <FieldGroup><div className="agenda-participant-summary"><UserRound aria-hidden="true" /><div><strong>{name}</strong><span>{state.trainingOptions.find(item => item.value === state.form.trainingId)?.label}</span></div>{!original && <Button type="button" variant="ghost" onClick={() => state.setStep('people')} disabled={state.locked}>Changer</Button>}</div>
            <FieldSet><FieldLegend>Créneau</FieldLegend><FieldGroup><div className="agenda-field-row"><Field><FieldLabel htmlFor="lesson-date">Date</FieldLabel><Input id="lesson-date" type="date" required value={state.form.localStart.slice(0, 10)} onChange={event => setLocal(`${event.target.value}T${state.form.localStart.slice(11) || '09:00'}`)} disabled={state.locked} /></Field><Field><FieldLabel htmlFor="lesson-time">Heure</FieldLabel><Input id="lesson-time" type="time" required value={state.form.localStart.slice(11)} onChange={event => setLocal(`${state.form.localStart.slice(0, 10)}T${event.target.value}`)} disabled={state.locked} /></Field></div>
              {state.localInstants.length > 1 && <PortalSelect id="lesson-local-occurrence" label="Cette heure existe deux fois" value={state.form.localChoice || null} onValueChange={value => state.change('localChoice', value ?? '')} options={state.localInstants.map((instant, index) => ({ value: instant, label: `${index === 0 ? 'Première' : 'Seconde'} occurrence · ${new Intl.DateTimeFormat('fr-CH', { timeZone: state.school.timeZone, timeStyle: 'long' }).format(new Date(instant))}` }))} disabled={state.locked} />}
              <div className="agenda-field-row"><Field><FieldLabel htmlFor="lesson-duration">Durée (min)</FieldLabel><Input id="lesson-duration" type="number" min={1} max={480} step={1} required value={state.form.duration} onChange={event => state.change('duration', event.target.value)} disabled={state.locked || !!original && !state.form.commercialChange} /></Field><Field><FieldLabel htmlFor="lesson-buffer">Battement (min)</FieldLabel><Input id="lesson-buffer" type="number" min={0} max={240} step={1} required value={state.form.buffer} onChange={event => state.change('buffer', event.target.value)} disabled={state.locked || !!original} /></Field></div>
              <PortalSelect id="lesson-appointment-instructor" label="Moniteur" value={state.form.instructorId || null} onValueChange={value => state.change('instructorId', value ?? '')} options={state.instructorOptions} searchable disabled={state.locked} />
              <Field><FieldLabel htmlFor="lesson-place">Lieu de rendez-vous</FieldLabel><Input id="lesson-place" value={state.form.meetingPoint} onChange={event => state.change('meetingPoint', event.target.value)} maxLength={500} disabled={state.locked} placeholder="Adresse ou point de rencontre" /></Field>
            </FieldGroup></FieldSet>
            <FieldSet><FieldLegend>Prix et conditions</FieldLegend><FieldGroup>{original && <><div className="agenda-price-preserved"><span>Prix enregistré</span><strong>{money(original.priceCentsSnapshot)}</strong></div><Field orientation="horizontal"><Checkbox id="lesson-commercial-change" checked={state.form.commercialChange} disabled={state.locked} onCheckedChange={value => { state.change('commercialChange', value === true); if (!value && originalDuration) state.change('duration', String(originalDuration)); }} /><FieldLabel htmlFor="lesson-commercial-change">Modifier le tarif ou la durée</FieldLabel></Field></>}
              {state.usesNewTerms && <PortalSelect id="lesson-product" label="Prestation" value={state.form.productId || null} onValueChange={value => state.change('productId', value ?? '')} options={state.products.map(product => ({ value: product.id, label: `${product.label} · ${money(lessonCommercial(product, Number(state.form.duration)).agreedPriceCents)}` }))} disabled={state.locked} placeholder="Choisir un tarif applicable" />}
              {state.usesNewTerms && state.form.localStart && state.form.duration && !state.products.length && <Alert><AlertTitle>Aucun tarif applicable</AlertTitle><AlertDescription>Vérifiez la date et la durée. Une prestation approuvée doit couvrir la leçon.</AlertDescription></Alert>}
              {original && <><Field><FieldLabel htmlFor="lesson-move-reason">{state.form.commercialChange ? 'Motif du changement de tarif' : 'Motif du déplacement'}</FieldLabel><Textarea id="lesson-move-reason" value={state.form.reason} onChange={event => state.change('reason', event.target.value)} maxLength={1000} rows={3} required={state.form.commercialChange} disabled={state.locked} /></Field><Field orientation="horizontal"><Checkbox id="lesson-agreement" checked={state.form.agreement} disabled={state.locked} onCheckedChange={value => state.change('agreement', value === true)} /><FieldLabel htmlFor="lesson-agreement">L’accord pour ce déplacement a été obtenu.</FieldLabel></Field></>}
            </FieldGroup></FieldSet>
          </FieldGroup>}
          {state.step === 'review' && <div className="agenda-review"><div className="agenda-review-person"><span className="agenda-calendar-mark"><Check aria-hidden="true" /></span><div><strong>{name}</strong><span>{instructorName}</span></div></div>
            <dl className="agenda-review-facts"><div><dt>Rendez-vous</dt><dd>{original && <del>{dateTime(original.plannedStart, original.timeZone)}</del>}<strong>{state.interval && dateTime(state.interval.plannedStart, state.school.timeZone)}</strong></dd></div><div><dt>Durée</dt><dd>{original && originalDuration !== Number(state.form.duration) && <del>{originalDuration} min</del>}{state.form.duration} min</dd></div><div><dt>Lieu</dt><dd>{original && original.meetingPoint !== state.form.meetingPoint.trim() && <del>{original.meetingPoint || 'Non précisé'}</del>}{state.form.meetingPoint.trim() || 'Non précisé'}</dd></div><div><dt>Prix convenu</dt><dd>{original && state.form.commercialChange && <del>{money(original.priceCentsSnapshot)}</del>}<strong>{state.price !== null ? money(state.price) : 'Non défini'}</strong>{original && !state.form.commercialChange && <span className="agenda-muted">Prix conservé</span>}</dd></div>{original && original.instructorMembershipId !== state.form.instructorId && <div><dt>Moniteur</dt><dd><del>{original.instructorDisplayName}</del>{instructorName}</dd></div>}{state.form.reason.trim() && <div><dt>Motif</dt><dd>{state.form.reason.trim()}</dd></div>}</dl>
            {state.terms && <section className="agenda-terms"><h3>{state.terms.label}</h3><p>{state.terms.termsText}</p></section>}{!state.terms && original && <p className="agenda-muted">Les conditions enregistrées de la leçon sont conservées.</p>}
            {!original && state.policy?.cancellationPolicyText && <section className="agenda-terms"><h3>Annulation</h3><p>{state.policy.cancellationPolicyText}</p>{state.cancellationDeadline && <p>Contacter l’école pour une annulation après le {dateTime(state.cancellationDeadline, state.school.timeZone)}.</p>}</section>}
            {original && <FieldDescription>L’accord pour ce déplacement est confirmé.</FieldDescription>}
          </div>}
        </div><footer className="agenda-editor-footer"><Button type="button" variant="ghost" disabled={state.locked} onClick={close}>Annuler</Button><div>{state.step !== 'people' && (!original || state.step === 'review') && <Button type="button" variant="outline" disabled={state.locked} onClick={() => state.setStep(state.step === 'review' ? 'appointment' : 'people')}><ArrowLeft data-icon="inline-start" />Retour</Button>}<Button type="submit" disabled={state.locked || !!state.runner.blockedReason || !state.complete || state.step === 'review' && !state.review}>{state.checking ? 'Vérification…' : state.runner.busy ? 'Confirmation…' : state.step === 'review' ? original ? 'Confirmer le changement' : 'Planifier la leçon' : 'Continuer'}<ArrowRight data-icon="inline-end" /></Button></div></footer>
      </form>
    </div><DiscardDialog open={discard} onCancel={() => setDiscard(false)} onDiscard={() => { state.release(); onClose(); }} />
  </section>;
}

function DiscardDialog({ open, onCancel, onDiscard }: { open: boolean; onCancel: () => void; onDiscard: () => void }) {
  return <Dialog open={open} onOpenChange={value => { if (!value) onCancel(); }}><DialogContent><DialogHeader><DialogTitle>Quitter sans enregistrer ?</DialogTitle><DialogDescription>Votre saisie sera perdue.</DialogDescription></DialogHeader><DialogFooter><Button variant="outline" onClick={onCancel}>Continuer la saisie</Button><Button variant="destructive" onClick={onDiscard}>Abandonner</Button></DialogFooter></DialogContent></Dialog>;
}
