import { useEffect, useState } from 'react';
import { Banknote } from 'lucide-react';
import { Alert, AlertDescription } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import { centsToInput, formatCents, parseCents } from '../../command-core';
import { PAYMENT_NOTE_LIMIT, paymentProblem, type CoursePayment, type CourseSheetRow } from '../../console/course-model';
import { useConsole, useUnsavedChanges } from '../../console/context';
import { CommandFeedback, ReadFeedback } from '../agenda/presentation';
import { instantDateTime, keptMessage } from './course-presentation';
import { groupSettledCents, filterByName, settledCents } from './participants-model';
import { markLabels, type ParticipantsResume } from './participants-projection';
import { ActionDialog } from './participants-dialogs';
import { FeedbackText, MarkText } from './participants-parts';
import { feedbackKey, type CourseParticipants } from './use-course-participants';

/**
 * On-site settlements, in CHF. Only what the school confirmed is counted. A correction is one more record: the entry it voids
 * stays listed with its motive. Nothing here refunds anyone. A settlement still being answered shows the wanted amount, marked
 * « À confirmer », and it never enters the counted total before the school's answer.
 */
export function PaymentsTab({ state, resume, onResumeDone }: { state: CourseParticipants; resume: ParticipantsResume | null; onResumeDone: () => void }) {
  const { school } = useConsole();
  const [search, setSearch] = useState('');
  const [paying, setPaying] = useState<{ row: CourseSheetRow; initial: { amountCents: number; note: string | null } | null } | null>(null);
  const [voiding, setVoiding] = useState<{ row: CourseSheetRow; payment: CoursePayment; reason: string } | null>(null);
  const sheet = state.sheet;
  const timeZone = school.timeZone;
  // A refused settlement comes back with the amount and the note that were typed, never with an invented one.
  useEffect(() => {
    if (!sheet || !resume) return;
    if (resume.kind === 'payment') {
      const row = sheet.rows.find(item => item.enrollmentId === resume.enrollmentId);
      onResumeDone();
      if (row) setPaying({ row, initial: { amountCents: resume.amountCents, note: resume.note } });
    } else if (resume.kind === 'void') {
      const row = sheet.rows.find(item => item.enrollmentId === resume.enrollmentId);
      const payment = row?.payments.find(item => item.id === resume.paymentId);
      onResumeDone();
      if (row && payment) setVoiding({ row, payment, reason: resume.reason });
    }
  }, [resume, sheet, onResumeDone]);
  if (!sheet) return <ReadFeedback loaded={state.sheetRead} label="Lecture des règlements" />;
  const rows = filterByName(sheet.rows, search);
  return <div className="participants-tab">
    <ReadFeedback loaded={state.sheetRead} label="Lecture des règlements" />
    <div className="participants-head"><h2>Règlements</h2><p className="participants-total" aria-label="Total compté"><span className="course-muted">Total compté</span><strong>{formatCents(groupSettledCents(sheet.rows))}</strong></p></div>
    {sheet.rows.length > 8 && <Input type="search" aria-label="Rechercher un participant" placeholder="Rechercher un participant" value={search} onChange={event => setSearch(event.target.value)} />}
    {sheet.rows.length === 0 ? <Empty className="participants-empty"><EmptyHeader><EmptyMedia variant="icon"><Banknote /></EmptyMedia><EmptyTitle>Aucun inscrit</EmptyTitle></EmptyHeader></Empty>
      : rows.length === 0 ? <p className="course-muted" role="status">Aucun participant trouvé.</p>
        : <ul className="participants-list">{rows.map(row => {
          const blocked = state.blockedFor(row.enrollmentId);
          const wanted = state.paymentMarks.get(row.enrollmentId);
          const marks = state.marks.get(row.enrollmentId) ?? [];
          const text = marks.map(value => value === 'payment' && wanted ? `${markLabels.payment} · ${formatCents(wanted.amountCents)}` : markLabels[value]).join(' · ');
          const markId = `payment-mark-${row.enrollmentId}`;
          return <li key={row.enrollmentId} data-muted={row.status !== 'ACTIVE'} className="participants-stack">
            <div className="participants-row">
              <div className="participants-main"><strong>{row.learnerDisplayName || 'Élève'}</strong>
                <span className="course-muted">{row.payments.length === 0 ? 'Aucun règlement' : `${formatCents(settledCents(row))} compté`}</span>
                {text && <MarkText id={markId} text={text} />}
                <FeedbackText feedback={state.feedback[feedbackKey('payments', row.enrollmentId)]} /></div>
              {row.status === 'ACTIVE' ? <Button variant="outline" disabled={Boolean(blocked)} {...(text ? { 'aria-describedby': markId } : {})}
                aria-label={`Consigner un règlement pour ${row.learnerDisplayName || 'cet élève'}`} onClick={() => setPaying({ row, initial: null })}>Consigner un règlement</Button>
                : <Badge variant="outline">Annulée</Badge>}
            </div>
            {row.payments.length > 0 && <ul className="participants-records">{row.payments.map(payment => <li key={payment.id} data-voided={Boolean(payment.voidedAt)}>
              <div className="participants-main"><strong className="participants-amount">{formatCents(payment.amountCents)}</strong>
                <span className="course-muted">{instantDateTime(payment.recordedAt, timeZone)}{payment.note ? ` · ${payment.note}` : ''}</span>
                {payment.voidedAt && <span className="course-muted">Saisie annulée le {instantDateTime(payment.voidedAt, timeZone)}{payment.voidReason ? ` · ${payment.voidReason}` : ''}</span>}</div>
              {payment.voidedAt ? <Badge variant="outline">Annulé</Badge>
                : <Button variant="ghost" disabled={Boolean(blocked)} aria-label={`Annuler la saisie de ${formatCents(payment.amountCents)} de ${row.learnerDisplayName || 'cet élève'}`} onClick={() => setVoiding({ row, payment, reason: '' })}>Annuler la saisie</Button>}
            </li>)}</ul>}
          </li>;
        })}</ul>}
    {paying && <PaymentDialog state={state} row={paying.row} initial={paying.initial} onClose={() => setPaying(null)} />}
    <ActionDialog open={voiding !== null} title="Annuler la saisie du règlement" subject={voiding?.row.learnerDisplayName || 'Élève'} withReason destructive confirmLabel="Annuler la saisie"
      blocked={voiding ? state.blockedFor(voiding.row.enrollmentId) : null} initialReason={voiding?.reason ?? ''} onReread={state.reread}
      facts={voiding ? [['Montant', formatCents(voiding.payment.amountCents)], ['Saisi le', instantDateTime(voiding.payment.recordedAt, timeZone)]] : []}
      consequence="La saisie reste visible, marquée annulée, et n’est plus comptée. Aucun remboursement n’est effectué."
      onClose={() => setVoiding(null)} onConfirm={reason => voiding ? state.voidPayment(voiding.row, voiding.payment.id, reason) : 'invalid'} />
  </div>;
}

/** Amount in CHF and an optional note, in one short action. The amount is counted once the school confirms it. */
function PaymentDialog({ state, row, initial, onClose }: { state: CourseParticipants; row: CourseSheetRow; initial: { amountCents: number; note: string | null } | null; onClose: () => void }) {
  const [amount, setAmount] = useState(initial ? centsToInput(initial.amountCents) : ''), [note, setNote] = useState(initial?.note ?? '');
  const [touched, setTouched] = useState(false), [refusal, setRefusal] = useState<string | null>(null);
  const blocked = state.blockedFor(row.enrollmentId);
  const cents = parseCents(amount);
  const problem = paymentProblem(cents, note);
  useUnsavedChanges(amount.trim() !== '' || note.trim() !== '');
  function save() {
    setTouched(true);
    if (problem || cents === null || blocked) return;
    setRefusal(null);
    const result = state.pay(row, cents, note.trim() || null);
    if (result === 'kept') { onClose(); return; }
    if (result === 'refused') setRefusal('Une demande sur ce participant attend encore sa confirmation.');
  }
  return <Dialog open onOpenChange={(next, details) => { if (blocked) { details.cancel(); return; } if (!next) onClose(); }}><DialogContent className="participants-dialog" showCloseButton={!blocked}>
    <DialogHeader><DialogTitle>Consigner un règlement</DialogTitle><DialogDescription>{row.learnerDisplayName || 'Élève'}</DialogDescription></DialogHeader>
    <form noValidate onSubmit={event => { event.preventDefault(); save(); }}>
      <FieldGroup>
      <Field data-invalid={touched && cents === null}><FieldLabel htmlFor="payment-amount">Montant (CHF)</FieldLabel>
        <Input id="payment-amount" inputMode="decimal" value={amount} placeholder="120.00" disabled={Boolean(blocked)} aria-invalid={touched && cents === null} onChange={event => { setRefusal(null); setAmount(event.target.value); }} />
        {touched && cents === null && <FieldError>{problem}</FieldError>}</Field>
      <Field data-invalid={touched && cents !== null && Boolean(problem)}><FieldLabel htmlFor="payment-note">Note (facultatif)</FieldLabel>
        <Textarea id="payment-note" value={note} maxLength={PAYMENT_NOTE_LIMIT} rows={2} disabled={Boolean(blocked)} onChange={event => setNote(event.target.value)} />
        {touched && cents !== null && problem && <FieldError>{problem}</FieldError>}</Field>
      </FieldGroup>
      {refusal && <Alert variant="destructive"><AlertDescription>{keptMessage(refusal)}</AlertDescription></Alert>}
      <CommandFeedback outcome={null} blocked={blocked} />
      <DialogFooter><Button type="button" variant="outline" disabled={Boolean(blocked)} onClick={onClose}>Annuler</Button>
        <Button type="submit" disabled={Boolean(blocked)}>Enregistrer le règlement</Button></DialogFooter>
    </form>
  </DialogContent></Dialog>;
}
