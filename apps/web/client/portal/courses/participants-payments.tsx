import { useEffect, useState } from 'react';
import { Banknote } from 'lucide-react';
import { Alert, AlertDescription } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Field, FieldError, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import { formatCents, parseCents } from '../../command-core';
import { PAYMENT_NOTE_LIMIT, paymentProblem, type CoursePayment, type CourseSheetRow } from '../../console/course-model';
import { useConsole, useUnsavedChanges } from '../../console/context';
import { CommandFeedback, ReadFeedback } from '../agenda/presentation';
import { instantDateTime, keptMessage } from './course-presentation';
import { groupSettledCents, filterByName, settledCents } from './participants-model';
import { ActionDialog } from './participants-dialogs';
import { FeedbackText } from './participants-parts';
import { feedbackKey, type CourseParticipants } from './use-course-participants';

/**
 * On-site settlements, in CHF. Only what the school confirmed is counted. A correction is one more record: the entry it voids
 * stays listed with its motive. Nothing here refunds anyone.
 */
export function PaymentsTab({ state }: { state: CourseParticipants }) {
  const { school } = useConsole();
  const [search, setSearch] = useState('');
  const [paying, setPaying] = useState<CourseSheetRow | null>(null);
  const [voiding, setVoiding] = useState<{ row: CourseSheetRow; payment: CoursePayment } | null>(null);
  const sheet = state.sheet;
  if (!sheet) return <ReadFeedback loaded={state.sheetRead} label="Lecture des règlements" />;
  const rows = filterByName(sheet.rows, search);
  const timeZone = school.timeZone;
  return <div className="participants-tab">
    <ReadFeedback loaded={state.sheetRead} label="Lecture des règlements" />
    <div className="participants-head"><h2>Règlements</h2><p className="participants-total" aria-label="Total compté"><span className="course-muted">Total compté</span><strong>{formatCents(groupSettledCents(sheet.rows))}</strong></p></div>
    {sheet.rows.length > 8 && <Input type="search" aria-label="Rechercher un participant" placeholder="Rechercher un participant" value={search} onChange={event => setSearch(event.target.value)} />}
    {sheet.rows.length === 0 ? <Empty className="participants-empty"><EmptyHeader><EmptyMedia variant="icon"><Banknote /></EmptyMedia><EmptyTitle>Aucun inscrit</EmptyTitle></EmptyHeader></Empty>
      : rows.length === 0 ? <p className="course-muted" role="status">Aucun participant trouvé.</p>
        : <ul className="participants-list">{rows.map(row => <li key={row.enrollmentId} data-muted={row.status !== 'ACTIVE'} className="participants-stack">
          <div className="participants-row">
            <div className="participants-main"><strong>{row.learnerDisplayName || 'Élève'}</strong>
              <span className="course-muted">{row.payments.length === 0 ? 'Aucun règlement' : `${formatCents(settledCents(row))} compté`}</span>
              <FeedbackText feedback={state.feedback[feedbackKey('payments', row.enrollmentId)]} /></div>
            {row.status === 'ACTIVE' ? <Button variant="outline" disabled={state.locked} aria-label={`Consigner un règlement pour ${row.learnerDisplayName || 'cet élève'}`} onClick={() => setPaying(row)}>Consigner un règlement</Button>
              : <Badge variant="outline">Annulée</Badge>}
          </div>
          {row.payments.length > 0 && <ul className="participants-records">{row.payments.map(payment => <li key={payment.id} data-voided={Boolean(payment.voidedAt)}>
            <div className="participants-main"><strong className="participants-amount">{formatCents(payment.amountCents)}</strong>
              <span className="course-muted">{instantDateTime(payment.recordedAt, timeZone)}{payment.note ? ` · ${payment.note}` : ''}</span>
              {payment.voidedAt && <span className="course-muted">Saisie annulée le {instantDateTime(payment.voidedAt, timeZone)}{payment.voidReason ? ` · ${payment.voidReason}` : ''}</span>}</div>
            {payment.voidedAt ? <Badge variant="outline">Annulé</Badge>
              : <Button variant="ghost" disabled={state.locked} aria-label={`Annuler la saisie de ${formatCents(payment.amountCents)} de ${row.learnerDisplayName || 'cet élève'}`} onClick={() => setVoiding({ row, payment })}>Annuler la saisie</Button>}
          </li>)}</ul>}
        </li>)}</ul>}
    {paying && <PaymentDialog state={state} row={paying} onClose={() => setPaying(null)} />}
    <ActionDialog open={voiding !== null} title="Annuler la saisie du règlement" subject={voiding?.row.learnerDisplayName || 'Élève'} withReason destructive confirmLabel="Annuler la saisie" state={state}
      facts={voiding ? [['Montant', formatCents(voiding.payment.amountCents)], ['Saisi le', instantDateTime(voiding.payment.recordedAt, timeZone)]] : []}
      consequence="La saisie reste visible, marquée annulée, et n’est plus comptée. Aucun remboursement n’est effectué."
      onClose={() => setVoiding(null)} onConfirm={reason => voiding ? state.voidPayment(voiding.row, voiding.payment.id, reason) : Promise.resolve({ status: 'rejected' as const, message: 'Saisie introuvable.' })} />
  </div>;
}

/** Amount in CHF and an optional note, in one short action. The amount is counted once the school confirms it. */
function PaymentDialog({ state, row, onClose }: { state: CourseParticipants; row: CourseSheetRow; onClose: () => void }) {
  const [amount, setAmount] = useState(''), [note, setNote] = useState('');
  const [touched, setTouched] = useState(false), [refusal, setRefusal] = useState<string | null>(null);
  const cents = parseCents(amount);
  const problem = paymentProblem(cents, note);
  useUnsavedChanges(amount.trim() !== '' || note.trim() !== '');
  useEffect(() => { state.runner.clearOutcome(); }, []);
  async function save() {
    setTouched(true);
    if (problem || cents === null || state.locked) return;
    setRefusal(null);
    const result = await state.pay(row, cents, note.trim() || null);
    if (result.status === 'rejected') { setRefusal(result.message); return; }
    onClose();
  }
  return <Dialog open onOpenChange={(next, details) => { if (state.locked) { details.cancel(); return; } if (!next) onClose(); }}><DialogContent showCloseButton={!state.locked}>
    <DialogHeader><DialogTitle>Consigner un règlement</DialogTitle><DialogDescription>{row.learnerDisplayName || 'Élève'}</DialogDescription></DialogHeader>
    <form noValidate onSubmit={event => { event.preventDefault(); void save(); }}>
      <Field data-invalid={touched && cents === null}><FieldLabel htmlFor="payment-amount">Montant (CHF)</FieldLabel>
        <Input id="payment-amount" inputMode="decimal" value={amount} placeholder="120.00" disabled={state.locked} aria-invalid={touched && cents === null} onChange={event => { setRefusal(null); setAmount(event.target.value); }} />
        {touched && cents === null && <FieldError>{problem}</FieldError>}</Field>
      <Field data-invalid={touched && cents !== null && Boolean(problem)}><FieldLabel htmlFor="payment-note">Note (facultatif)</FieldLabel>
        <Textarea id="payment-note" value={note} maxLength={PAYMENT_NOTE_LIMIT} rows={2} disabled={state.locked} onChange={event => setNote(event.target.value)} />
        {touched && cents !== null && problem && <FieldError>{problem}</FieldError>}</Field>
      {refusal && <Alert variant="destructive"><AlertDescription>{keptMessage(refusal)}</AlertDescription></Alert>}
      <CommandFeedback outcome={state.runner.outcome?.needsLogin ? state.runner.outcome : null} blocked={state.runner.blockedReason} />
      <DialogFooter><Button type="button" variant="outline" disabled={state.locked} onClick={onClose}>Annuler</Button>
        <Button type="submit" disabled={state.locked || Boolean(state.runner.blockedReason)}>{state.runner.busy ? 'Confirmation…' : 'Enregistrer le règlement'}</Button></DialogFooter>
    </form>
  </DialogContent></Dialog>;
}
