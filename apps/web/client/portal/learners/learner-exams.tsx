import { useState } from 'react';
import { CalendarClock, ChevronRight, Plus } from 'lucide-react';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import { createCommand } from '../../command-core';
import { useCommandSnapshot } from '../../command-store';
import { useCommandRunner, useConsole, useLoad } from '../../console/context';
import {
  draftFromExam, emptyExamDraft, EXAM_LOCATION_LIMIT, EXAM_TEXT_LIMIT, examActions, examBody, examKindLabels, examListSchema, examProblems, examStateSchema,
  resultBody, resultDraft, resultLabels, resultProblems, rowTitle, schedulableKinds, statusText,
  type Exam, type ExamDraft, type ExamKind, type ExamState, type ResultChoice, type ResultDraft,
} from '../../exam-model';
import { readSchool } from '../../school-api';
import { PortalSelect } from '../components/portal-select';
import { dateTime } from './dossier-controller';
import type { LearnerController } from './learner-controller';
import { CommandFeedback, ReadFeedback } from './learner-feedback';

type ExamDialog =
  | { kind: 'create'; exam: ExamKind }
  | { kind: 'edit'; exam: Exam }
  | { kind: 'postpone'; exam: Exam }
  | { kind: 'result'; exam: Exam }
  | null;

/** Examens théorique et pratique d'un élève, par formation : prévus, reportés, résultats saisis par le personnel (#54). */
export function LearnerExams({ state }: { state: LearnerController }) {
  const { schoolId, school } = useConsole();
  const { revision } = useCommandSnapshot();
  const trainings = state.current ? state.trainingsOf(state.current.id) : [];
  const [choice, setChoice] = useState<string | null>(null);
  const [dialog, setDialog] = useState<ExamDialog>(null);
  const training = trainings.find(item => item.id === choice) ?? trainings.find(item => item.status === 'ACTIVE') ?? trainings[0];
  const loaded = useLoad(async (): Promise<ExamState | null> => {
    if (!training) return null;
    const result = await readSchool(schoolId, `trainings/${training.id}/exams`, examStateSchema);
    if (result.trainingId !== training.id) throw new Error('Réponse inattendue.');
    return result;
  }, [schoolId, training?.id, revision], `${schoolId}/${training?.id ?? ''}`);
  const runner = useCommandRunner(() => setDialog(null));
  const busy = runner.busy || !!runner.pending;
  const data = loaded.data;
  const kinds = data ? schedulableKinds(data) : [];
  const canManage = !!data?.canManage && !state.current?.archivedAt && training?.status === 'ACTIVE';
  const open = (next: ExamDialog) => { runner.clearOutcome(); setDialog(next); };
  const close = () => { if (!busy) setDialog(null); };
  if (!training) return <div className="student-empty"><CalendarClock aria-hidden="true" /><h2>Aucune formation ouverte</h2><p>Les examens se suivent par formation.</p></div>;
  return <section className="student-section exam-section">
    {trainings.length > 1 && <div className="student-training-picker"><PortalSelect id="exam-training" label="Formation" value={training.id} onValueChange={setChoice} options={trainings.map(item => ({ value: item.id, label: state.title(item) }))} /></div>}
    <header className="student-section-heading"><h2>Examens</h2>
      {canManage && kinds.length > 0 && <div className="exam-schedule-actions">{kinds.map(kind => <Button key={kind} variant="outline" disabled={busy} onClick={() => open({ kind: 'create', exam: kind })}><Plus data-icon="inline-start" />{examKindLabels[kind]}</Button>)}</div>}
    </header>
    <ReadFeedback loaded={loaded} />
    <CommandFeedback runner={runner} />
    {data && data.exams.length === 0 && <p className="student-muted">Aucun examen suivi pour cette formation.</p>}
    {data && <ul className="exam-list">{data.exams.map(exam => {
      const status = statusText(exam, data.canManage), actions = canManage ? examActions(exam) : [];
      return <li key={exam.id} className="exam-row" data-status={exam.status}>
        <div className="exam-main">
          <strong>{rowTitle(exam)}</strong>
          <span><time dateTime={exam.startsAt}>{dateTime(exam.startsAt, exam.timeZone)}</time>{exam.location && ` · ${exam.location}`}</span>
          {exam.escort && <span className="student-muted">Accompagnement {state.name(exam.escort.instructorMembershipId)}</span>}
          {exam.resultNote && <span>À travailler : {exam.resultNote}</span>}
        </div>
        <div className="exam-side">
          <Badge variant={status.attention ? 'destructive' : exam.status === 'PASSED' ? 'default' : 'secondary'}>{status.label}</Badge>
          <div className="exam-actions">
            {actions.includes('result') && <Button size="sm" disabled={busy} onClick={() => open({ kind: 'result', exam })}>Renseigner le résultat</Button>}
            {actions.includes('edit') && <Button size="sm" variant="outline" disabled={busy} onClick={() => open({ kind: 'edit', exam })}>Modifier</Button>}
            {actions.includes('postpone') && <Button size="sm" variant="outline" disabled={busy} onClick={() => open({ kind: 'postpone', exam })}>Reporter</Button>}
            {actions.includes('correct') && <Button size="sm" variant="outline" disabled={busy} onClick={() => open({ kind: 'result', exam })}>Corriger</Button>}
          </div>
        </div>
      </li>;
    })}</ul>}
    {dialog && data && (dialog.kind === 'result'
      ? <ResultDialog exam={dialog.exam} runner={runner} close={close} />
      : <ScheduleDialog dialog={dialog} trainingId={training.id} candidates={data.escortCandidates} timeZone={school.timeZone} runner={runner} close={close} />)}
  </section>;
}

function ScheduleDialog({ dialog, trainingId, candidates, timeZone, runner, close }: {
  dialog: Exclude<ExamDialog, null | { kind: 'result'; exam: Exam }>; trainingId: string; candidates: ExamState['escortCandidates']; timeZone: string;
  runner: ReturnType<typeof useCommandRunner>; close: () => void;
}) {
  const { schoolId } = useConsole();
  const [draft, setDraft] = useState<ExamDraft>(() => dialog.kind === 'create' ? emptyExamDraft(timeZone) : draftFromExam(dialog.exam, timeZone));
  const problems = examProblems(draft, timeZone);
  const busy = runner.busy || !!runner.pending;
  const asksReason = dialog.kind !== 'create';
  const title = dialog.kind === 'create' ? `Prévoir : ${examKindLabels[dialog.exam].toLowerCase()}` : dialog.kind === 'edit' ? 'Modifier la date' : 'Reporter l’examen';
  const change = (patch: Partial<ExamDraft>) => setDraft(current => ({ ...current, ...patch }));
  const submit = () => {
    const body = examBody(draft, timeZone);
    if (!body || busy) return;
    if (dialog.kind === 'create') return runner.run(createCommand({ schoolId, kind: 'createExam', path: `trainings/${trainingId}/exams`, resourceVersion: 0, body: { kind: dialog.exam, ...body } }), 'L’examen est prévu.');
    const reason = draft.reason.trim();
    const edit = dialog.kind === 'edit';
    return runner.run(createCommand({ schoolId, kind: edit ? 'updateExam' : 'postponeExam', path: `exams/${dialog.exam.id}/${edit ? 'update' : 'postpone'}`,
      resourceId: dialog.exam.id, resourceVersion: dialog.exam.version, ifMatch: dialog.exam.version, body: { ...body, reason } }), edit ? 'La date est modifiée.' : 'L’examen est reporté.');
  };
  return <Dialog open onOpenChange={(next, details) => { if (busy) details.cancel(); else if (!next) close(); }}>
    <DialogContent showCloseButton={!busy}>
      <DialogHeader><DialogTitle>{title}</DialogTitle><DialogDescription>{dialog.kind === 'postpone' ? 'La tentative d’origine est gardée comme reportée.' : 'Le fuseau de l’école s’applique.'}</DialogDescription></DialogHeader>
      <form onSubmit={event => { event.preventDefault(); void submit(); }}>
        <FieldGroup>
          <Field data-invalid={!!problems.start}><FieldLabel htmlFor="exam-start">Date et heure</FieldLabel><Input id="exam-start" type="datetime-local" value={draft.start} disabled={busy} aria-invalid={!!problems.start} onChange={event => change({ start: event.target.value })} />{problems.start && <FieldError>{problems.start}</FieldError>}</Field>
          <Field data-invalid={!!problems.location}><FieldLabel htmlFor="exam-location">Lieu (facultatif)</FieldLabel><Input id="exam-location" value={draft.location} maxLength={EXAM_LOCATION_LIMIT} disabled={busy} onChange={event => change({ location: event.target.value })} />{problems.location && <FieldError>{problems.location}</FieldError>}</Field>
          {candidates.length > 0 && <Field><div className="exam-escort-toggle"><Checkbox id="exam-escort" checked={draft.escort} disabled={busy} onCheckedChange={checked => change({ escort: checked === true, escortInstructor: checked === true ? draft.escortInstructor || candidates[0]!.membershipId : draft.escortInstructor })} /><FieldLabel htmlFor="exam-escort">Accompagnement du moniteur</FieldLabel></div></Field>}
          {draft.escort && <>
            <PortalSelect id="exam-escort-instructor" label="Moniteur" value={draft.escortInstructor || null} onValueChange={value => change({ escortInstructor: value ?? '' })} options={candidates.map(item => ({ value: item.membershipId, label: item.displayName }))} />
            <Field data-invalid={!!problems.escort}><FieldLabel htmlFor="exam-escort-start">De</FieldLabel><Input id="exam-escort-start" type="datetime-local" value={draft.escortStart} disabled={busy} onChange={event => change({ escortStart: event.target.value })} /></Field>
            <Field data-invalid={!!problems.escort}><FieldLabel htmlFor="exam-escort-end">À</FieldLabel><Input id="exam-escort-end" type="datetime-local" value={draft.escortEnd} disabled={busy} aria-invalid={!!problems.escort} onChange={event => change({ escortEnd: event.target.value })} />{problems.escort && <FieldError>{problems.escort}</FieldError>}</Field>
          </>}
          {asksReason && <Field data-invalid={!!problems.reason}><FieldLabel htmlFor="exam-reason">Motif (facultatif)</FieldLabel><Textarea id="exam-reason" value={draft.reason} maxLength={EXAM_TEXT_LIMIT} rows={2} disabled={busy} onChange={event => change({ reason: event.target.value })} />{problems.reason && <FieldError>{problems.reason}</FieldError>}</Field>}
        </FieldGroup>
        <CommandFeedback runner={runner} />
        <DialogFooter><Button type="button" variant="outline" disabled={busy} onClick={close}>Annuler</Button><Button type="submit" disabled={busy || Object.keys(problems).length > 0}>{dialog.kind === 'create' ? 'Prévoir l’examen' : 'Enregistrer'}</Button></DialogFooter>
      </form>
    </DialogContent>
  </Dialog>;
}

function ResultDialog({ exam, runner, close }: { exam: Exam; runner: ReturnType<typeof useCommandRunner>; close: () => void }) {
  const { schoolId } = useConsole();
  const correcting = exam.status === 'PASSED' || exam.status === 'FAILED' || exam.status === 'ABSENT';
  const [draft, setDraft] = useState<ResultDraft>(() => resultDraft(exam));
  const problems = resultProblems(draft, correcting);
  const busy = runner.busy || !!runner.pending;
  const change = (patch: Partial<ResultDraft>) => setDraft(current => ({ ...current, ...patch }));
  const submit = () => {
    const body = resultBody(draft, correcting);
    if (!body || busy) return;
    return runner.run(createCommand({ schoolId, kind: 'setExamResult', path: `exams/${exam.id}/result`, resourceId: exam.id, resourceVersion: exam.version, ifMatch: exam.version, body }),
      correcting ? 'Le résultat est corrigé.' : 'Le résultat est enregistré.');
  };
  return <Dialog open onOpenChange={(next, details) => { if (busy) details.cancel(); else if (!next) close(); }}>
    <DialogContent showCloseButton={!busy}>
      <DialogHeader><DialogTitle>{correcting ? 'Corriger le résultat' : 'Résultat de l’examen'}</DialogTitle><DialogDescription>{rowTitle(exam)}</DialogDescription></DialogHeader>
      <form onSubmit={event => { event.preventDefault(); void submit(); }}>
        <FieldGroup>
          <PortalSelect id="exam-result" label="Résultat" value={draft.result} onValueChange={value => { if (value === 'PASSED' || value === 'FAILED' || value === 'ABSENT') change({ result: value as ResultChoice }); }}
            options={(['PASSED', 'FAILED', 'ABSENT'] as const).map(value => ({ value, label: resultLabels[value] }))} />
          <Field data-invalid={!!problems.note}><FieldLabel htmlFor="exam-note">Points à travailler (facultatif)</FieldLabel><Textarea id="exam-note" value={draft.note} maxLength={EXAM_TEXT_LIMIT} rows={3} disabled={busy} onChange={event => change({ note: event.target.value })} />{problems.note && <FieldError>{problems.note}</FieldError>}</Field>
          {correcting && <Field data-invalid={!!problems.reason}><FieldLabel htmlFor="exam-result-reason">Motif de la correction</FieldLabel><Textarea id="exam-result-reason" value={draft.reason} maxLength={EXAM_TEXT_LIMIT} rows={2} disabled={busy} aria-invalid={!!problems.reason} onChange={event => change({ reason: event.target.value })} />{problems.reason && <FieldError>{problems.reason}</FieldError>}</Field>}
        </FieldGroup>
        <CommandFeedback runner={runner} />
        <DialogFooter><Button type="button" variant="outline" disabled={busy} onClick={close}>Annuler</Button><Button type="submit" disabled={busy || Object.keys(problems).length > 0}>{correcting ? 'Corriger le résultat' : 'Enregistrer le résultat'}</Button></DialogFooter>
      </form>
    </DialogContent>
  </Dialog>;
}

/** Examens dont la date est passée et dont le résultat reste à renseigner, dans l'annuaire : une lecture en panne ne dit rien. */
export function PendingExamResults({ state }: { state: LearnerController }) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    const result = await readSchool(schoolId, 'exams', examListSchema, { filter: 'PENDING_RESULT' });
    return result.items;
  }, [schoolId, revision], `${schoolId}/pending-exams`);
  const items = loaded.data ?? [];
  if (loaded.status !== 'ready' || items.length === 0) return null;
  return <section className="student-section exam-pending" aria-labelledby="exam-pending-title">
    <h2 id="exam-pending-title">Examens à renseigner</h2>
    <ul className="exam-list">{items.slice(0, 8).map(item => <li key={item.exam.id} className="exam-row">
      <Button type="button" variant="ghost" className="exam-pending-open" onClick={() => state.setSelected(item.learnerId)}>
        <span className="exam-main"><strong>{item.learnerDisplayName || 'Élève'}</strong><span>{rowTitle(item.exam)} · {dateTime(item.exam.startsAt, item.exam.timeZone)}</span></span><ChevronRight aria-hidden="true" />
      </Button>
    </li>)}</ul>
    {items.length > 8 && <p className="student-muted">{items.length - 8} autres examens à renseigner.</p>}
  </section>;
}

