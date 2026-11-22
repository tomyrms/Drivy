import { useState } from 'react';
import {
  centsOf, chf, francsOf, invoiceKindLabel, paymentMethodLabel, paymentMethods, regularizationKindLabel, regularizationKinds,
  type PlatformBilling, type PlatformInvoice, type PlatformPayment, type PlatformPaymentMethod, type PlatformRegularizationKind,
} from '../../platform-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { FieldGroup } from '../../components/ui/field';
import { PortalSelect } from '../components/portal-select';
import { by, civil, dateTime, dayPattern, Fact, Failure, Footer, NotFound, ReasonField, reasonProblem, selectError, TextField } from './billing-parts';
import type { PaymentDialog, PaymentFields, PaymentInput } from './use-platform-billing';
import type { PlatformConsoleState } from './use-platform-console';

const MAX_AMOUNT = 100_000_000;
const amountProblem = 'Saisissez un montant en francs, par exemple 120.50.';
const methodOptions = paymentMethods.map(value => ({ value, label: paymentMethodLabel(value) }));
const regularizationOptions = regularizationKinds.map(value => ({ value, label: regularizationKindLabel(value) }));
const modeOptions = [{ value: 'SPREAD', label: 'Factures les plus anciennes' }, { value: 'MANUAL', label: 'Choisir les factures' }, { value: 'NONE', label: 'Ne pas affecter' }];
type AllocationMode = 'SPREAD' | 'MANUAL' | 'NONE';
type Problem = { field: string; message: string };
type PaymentDraft = { amount: string; receivedOn: string; method: PlatformPaymentMethod; reference: string; note: string };

const amountOf = (text: string) => {
  const value = centsOf(text, MAX_AMOUNT);
  return value === null || value === undefined || value === 0 ? null : value;
};
const balanceOf = (invoice: PlatformInvoice) => invoice.settlement?.balance ?? 0;
const invoiceName = (invoice: PlatformInvoice) => invoice.number ?? invoiceKindLabel(invoice.kind);
/** Les factures qui peuvent encore recevoir un règlement, de la plus ancienne échéance à la plus récente. */
const openInvoices = (data: PlatformBilling) => data.invoices
  .filter(invoice => invoice.status === 'ISSUED' && (invoice.settlement?.state === 'UNPAID' || invoice.settlement?.state === 'PARTIAL'))
  .sort((left, right) => (left.dueOn ?? '').localeCompare(right.dueOn ?? '') || left.id.localeCompare(right.id));

function fieldsOf(draft: PaymentDraft, today: string): { fields: PaymentFields } | Problem {
  const amount = amountOf(draft.amount);
  if (amount === null) return { field: 'amount', message: amountProblem };
  if (!dayPattern.test(draft.receivedOn) || draft.receivedOn > today) return { field: 'receivedOn', message: 'Choisissez aujourd’hui ou une date passée.' };
  const reference = draft.reference.trim(), note = draft.note.trim();
  if (reference.length > 140) return { field: 'reference', message: 'Ce texte est limité à 140 caractères.' };
  if (note && (note.length < 3 || note.length > 500)) return { field: 'note', message: 'Entre 3 et 500 caractères.' };
  return { fields: { amount, currency: 'CHF', receivedOn: draft.receivedOn, method: draft.method, reference: reference || null, note: note || null } };
}

/** Les règlements de la fiche : les montants viennent de la base, l'écran ne les recalcule pas. */
export function PaymentsBlock({ state, data }: { state: PlatformConsoleState; data: PlatformBilling }) {
  const recorded = data.payments.filter(payment => payment.status === 'RECORDED'), closed = data.payments.filter(payment => payment.status === 'VOIDED');
  const row = (payment: PlatformPayment) => <li key={payment.id}>
    <PaymentSummary payment={payment} />
    <Button variant="ghost" disabled={state.busy} aria-label={`Voir le règlement de ${chf(payment.amount)} reçu le ${civil(payment.receivedOn)}`}
      onClick={() => state.billing.start({ kind: 'paymentDetail', paymentId: payment.id })}>Voir</Button>
  </li>;
  return <>
    <div className="platform-fiche-head">
      <h5 className="platform-subtitle">Règlements</h5>
      <div className="platform-actions"><Button variant="outline" disabled={state.busy} onClick={() => state.billing.start({ kind: 'payment' })}>Saisir un règlement</Button></div>
    </div>
    {recorded.length > 0 && <ul className="platform-list" aria-label="Règlements">{recorded.map(row)}</ul>}
    {closed.length > 0 && <details className="platform-history">
      <summary>Règlements annulés ou corrigés</summary>
      <ol className="platform-list" aria-label="Règlements annulés ou corrigés">{closed.map(row)}</ol>
    </details>}
  </>;
}

function PaymentSummary({ payment }: { payment: PlatformPayment }) {
  const recorded = payment.status === 'RECORDED';
  const parts = [`reçu le ${civil(payment.receivedOn)}`, ...(payment.reference ? [payment.reference] : []), ...(payment.allocated > 0 ? [`affecté ${chf(payment.allocated)}`] : []),
    ...(payment.regularized > 0 ? [`régularisé ${chf(payment.regularized)}`] : []), ...(recorded && payment.available > 0 ? [`non affecté ${chf(payment.available)}`] : [])];
  return <div className="platform-summary">
    <strong>{chf(payment.amount)} · {paymentMethodLabel(payment.method)}
      {!recorded && <Badge variant="outline">{payment.voidCause === 'CORRECTED' ? 'Corrigé' : 'Annulé'}</Badge>}</strong>
    <span>{parts.join(' · ')}</span>
  </div>;
}

/** Chaque boîte relit son règlement dans la facturation à jour ; s'il a disparu, elle le dit au lieu d'agir sur une copie. */
export function PaymentDialogBody({ state, data, target }: { state: PlatformConsoleState; data: PlatformBilling; target: PaymentDialog }) {
  if (target.kind === 'payment') return <RecordBody state={state} data={data} />;
  const payment = data.payments.find(item => item.id === target.paymentId);
  if (!payment) return <NotFound />;
  const back = () => state.billing.start({ kind: 'paymentDetail', paymentId: payment.id });
  const regularized = payment.regularizations.some(item => item.status === 'ACTIVE');
  switch (target.kind) {
    case 'paymentDetail': return <DetailBody state={state} data={data} payment={payment} />;
    case 'allocate': return <AllocateBody state={state} data={data} payment={payment} back={back} />;
    case 'release': {
      const allocation = payment.allocations.find(item => item.id === target.allocationId && item.status === 'ACTIVE');
      if (!allocation) return <NotFound />;
      return <ReasonBody state={state} id="allocation-release" title="Libérer cette affectation ?" description={`${allocation.invoiceNumber ?? 'Facture'} · ${chf(allocation.amount)}`}
        failure="Affectation non libérée" label="Libérer" back={back} send={reason => state.billing.releaseAllocation(payment.id, allocation.id, reason)} />;
    }
    case 'paymentVoid':
      if (regularized) return <RegularizedBody title="Annuler ce règlement" back={back} />;
      return <ReasonBody state={state} id="payment-void" title="Annuler ce règlement ?" description={`${chf(payment.amount)} · reçu le ${civil(payment.receivedOn)}`}
        failure="Règlement non annulé" label="Annuler le règlement" back={back} send={reason => state.billing.voidPayment(payment.id, reason)} />;
    case 'paymentCorrect':
      if (regularized) return <RegularizedBody title="Corriger ce règlement" back={back} />;
      return <CorrectBody state={state} data={data} payment={payment} back={back} />;
    case 'regularize': return <RegularizeBody state={state} payment={payment} back={back} />;
    case 'regularizationCancel': {
      const regularization = payment.regularizations.find(item => item.id === target.regularizationId && item.status === 'ACTIVE');
      if (!regularization) return <NotFound />;
      return <ReasonBody state={state} id="regularization-cancel" title="Annuler cette régularisation ?" description={`${regularizationKindLabel(regularization.kind)} · ${chf(regularization.amount)}`}
        failure="Régularisation non annulée" label="Annuler la régularisation" back={back} send={reason => state.billing.cancelRegularization(payment.id, regularization.id, reason)} />;
    }
  }
}

function PaymentFieldset({ draft, set, errorOf, disabled }: {
  draft: PaymentDraft; set: (field: keyof PaymentDraft) => (value: string) => void; errorOf: (field: string) => string | null; disabled: boolean;
}) {
  return <FieldGroup className="platform-grid">
    <TextField id="payment-amount" label="Montant (CHF)" inputMode="decimal" value={draft.amount} onChange={set('amount')} error={errorOf('amount')} disabled={disabled} />
    <TextField id="payment-received" label="Reçu le" type="date" value={draft.receivedOn} onChange={set('receivedOn')} error={errorOf('receivedOn')} disabled={disabled} />
    <PortalSelect id="payment-method" label="Moyen" options={methodOptions} value={draft.method} disabled={disabled}
      onValueChange={value => { if (value) set('method')(value); }} />
    <TextField id="payment-reference" label="Référence (facultative)" value={draft.reference} onChange={set('reference')} error={errorOf('reference')} disabled={disabled} />
    <TextField id="payment-note" label="Note (facultative)" value={draft.note} onChange={set('note')} error={errorOf('note')} disabled={disabled} />
  </FieldGroup>;
}

function RecordBody({ state, data }: { state: PlatformConsoleState; data: PlatformBilling }) {
  const { billing } = state, open = openInvoices(data);
  const [draft, setDraft] = useState<PaymentDraft>({ amount: '', receivedOn: data.today, method: 'BANK_TRANSFER', reference: '', note: '' });
  const [chosenMode, setMode] = useState<AllocationMode>('SPREAD'), [amounts, setAmounts] = useState<Record<string, string>>({});
  const [invalid, setInvalid] = useState<Problem | null>(null), [submitted, setSubmitted] = useState(false);
  const mode: AllocationMode = open.length === 0 ? 'NONE' : chosenMode;
  // Toute modification rend caduque l'alerte de doublon : elle portait sur la saisie précédente.
  const touched = () => { setInvalid(null); setSubmitted(false); billing.clearDuplicate(); };
  const set = (field: keyof PaymentDraft) => (value: string) => { setDraft(previous => ({ ...previous, [field]: value })); touched(); };
  const errorOf = (field: string) => (invalid?.field === field ? invalid.message : null);

  function inputOf(): { input: PaymentInput } | Problem {
    const result = fieldsOf(draft, data.today);
    if ('field' in result) return result;
    if (mode !== 'MANUAL') return { input: { ...result.fields, allocations: [], spread: mode === 'SPREAD' } };
    const allocations: PaymentInput['allocations'] = [];
    for (const invoice of open) {
      const text = amounts[invoice.id]?.trim() ?? '';
      if (!text) continue;
      const amount = amountOf(text);
      if (amount === null) return { field: `invoice:${invoice.id}`, message: amountProblem };
      if (amount > balanceOf(invoice)) return { field: `invoice:${invoice.id}`, message: 'Le montant dépasse le solde de la facture.' };
      allocations.push({ invoiceId: invoice.id, amount });
    }
    const first = open[0]!;
    if (allocations.length === 0) return { field: `invoice:${first.id}`, message: 'Indiquez au moins un montant.' };
    const last = allocations[allocations.length - 1]!;
    if (allocations.reduce((sum, item) => sum + item.amount, 0) > result.fields.amount) return { field: `invoice:${last.invoiceId}`, message: 'Le total affecté dépasse le règlement.' };
    return { input: { ...result.fields, allocations, spread: false } };
  }
  const submit = (confirmDuplicate: boolean) => {
    if (billing.duplicate && !confirmDuplicate) return;
    const result = inputOf();
    if ('field' in result) { setInvalid(result); return; }
    setSubmitted(true);
    void billing.recordPayment(result.input, confirmDuplicate);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(false); }}>
    <DialogHeader><DialogTitle>Saisir un règlement</DialogTitle></DialogHeader>
    <PaymentFieldset draft={draft} set={set} errorOf={errorOf} disabled={state.busy} />
    {open.length > 0 && <FieldGroup>
      <PortalSelect id="payment-mode" label="Affectation" options={modeOptions} value={mode} disabled={state.busy}
        onValueChange={value => { if (value) { setMode(value as AllocationMode); touched(); } }} />
      {mode === 'MANUAL' && open.map(invoice => <TextField key={invoice.id} id={`payment-invoice-${invoice.id}`} label={`${invoiceName(invoice)} · solde ${chf(balanceOf(invoice))}`}
        inputMode="decimal" value={amounts[invoice.id] ?? ''} error={errorOf(`invoice:${invoice.id}`)} disabled={state.busy}
        onChange={value => { setAmounts(previous => ({ ...previous, [invoice.id]: value })); touched(); }} />)}
    </FieldGroup>}
    {billing.duplicate && <Alert variant="destructive"><AlertTitle>Doublon probable</AlertTitle>
      <AlertDescription>Un règlement du même montant existe déjà à une date ou une référence proche.</AlertDescription></Alert>}
    {/* Hors du pied de page : un double clic sur « Enregistrer » ne peut pas confirmer un doublon. */}
    {billing.duplicate && <div className="platform-actions">
      <Button type="button" variant="destructive" disabled={state.busy} onClick={() => submit(true)}>Enregistrer quand même</Button></div>}
    {submitted && <Failure state={state} title="Règlement non enregistré" />}
    <Footer state={state} label="Enregistrer" disabled={billing.duplicate} />
  </form>;
}

function DetailBody({ state, data, payment }: { state: PlatformConsoleState; data: PlatformBilling; payment: PlatformPayment }) {
  const { billing } = state, recorded = payment.status === 'RECORDED';
  const allocations = recorded ? payment.allocations.filter(item => item.status === 'ACTIVE') : payment.allocations;
  const released = recorded ? payment.allocations.filter(item => item.status === 'RELEASED') : [];
  const open = (paymentId: string) => billing.start({ kind: 'paymentDetail', paymentId });
  return <div className="platform-form">
    <DialogHeader><DialogTitle>Règlement de {chf(payment.amount)}</DialogTitle>
      <DialogDescription>{paymentMethodLabel(payment.method)} · reçu le {civil(payment.receivedOn)}</DialogDescription></DialogHeader>
    {!recorded && <div className="platform-summary"><strong><Badge variant="outline">{payment.voidCause === 'CORRECTED' ? 'Corrigé' : 'Annulé'}</Badge></strong>
      <span>{payment.voidedAt ? dateTime(payment.voidedAt) : ''}{by(payment.voidedByName)}</span>
      {payment.voidReason && <span>{payment.voidReason}</span>}</div>}
    <dl className="platform-facts">
      <Fact label="Affecté">{chf(payment.allocated)}</Fact>
      {payment.regularized > 0 && <Fact label="Régularisé">{chf(payment.regularized)}</Fact>}
      {recorded && <Fact label="Non affecté">{chf(payment.available)}</Fact>}
      {payment.reference && <Fact label="Référence">{payment.reference}</Fact>}
      {payment.note && <Fact label="Note">{payment.note}</Fact>}
      <Fact label="Saisi">{dateTime(payment.recordedAt)}{by(payment.recordedByName)}</Fact>
    </dl>
    {allocations.length > 0 && <ul className="platform-list platform-dialog-list" aria-label="Affectations">{allocations.map(item => <li key={item.id}>
      <div className="platform-summary"><strong>{item.invoiceNumber ?? 'Facture'} · {chf(item.amount)}{item.status === 'RELEASED' && <Badge variant="outline">Libérée</Badge>}</strong>
        <span>{dateTime(item.createdAt)}{by(item.createdByName)}</span></div>
      {recorded && <Button variant="ghost" disabled={state.busy} aria-label={`Libérer ${chf(item.amount)} de ${item.invoiceNumber ?? 'la facture'}`}
        onClick={() => billing.start({ kind: 'release', paymentId: payment.id, allocationId: item.id })}>Libérer</Button>}
    </li>)}</ul>}
    {payment.regularizations.length > 0 && <ul className="platform-list platform-dialog-list" aria-label="Régularisations">{payment.regularizations.map(item => <li key={item.id}>
      <div className="platform-summary"><strong>{regularizationKindLabel(item.kind)} · {chf(item.amount)}{item.status === 'CANCELLED' && <Badge variant="outline">Annulée</Badge>}</strong>
        <span>{item.reason}</span><span>{dateTime(item.createdAt)}{by(item.createdByName)}</span>
        {item.cancelReason && <span>Annulée{item.cancelledAt ? ` le ${dateTime(item.cancelledAt)}` : ''}{by(item.cancelledByName)} : {item.cancelReason}</span>}</div>
      {recorded && item.status === 'ACTIVE' && <Button variant="ghost" disabled={state.busy} aria-label={`Annuler la régularisation de ${chf(item.amount)}`}
        onClick={() => billing.start({ kind: 'regularizationCancel', paymentId: payment.id, regularizationId: item.id })}>Annuler</Button>}
    </li>)}</ul>}
    {released.length > 0 && <details className="platform-history">
      <summary>Affectations libérées</summary>
      <ol className="platform-list" aria-label="Affectations libérées">{released.map(item => <li key={item.id}><div className="platform-summary">
        <strong>{item.invoiceNumber ?? 'Facture'} · {chf(item.amount)}</strong>
        <span>{item.releasedAt ? dateTime(item.releasedAt) : ''}{by(item.releasedByName)}{item.releaseReason ? ` : ${item.releaseReason}` : ''}</span>
      </div></li>)}</ol>
    </details>}
    {(recorded || payment.correctsPaymentId || payment.correctedByPaymentId) && <div className="platform-actions">
      {payment.correctsPaymentId && <Button variant="ghost" disabled={state.busy} onClick={() => open(payment.correctsPaymentId!)}>Voir l’original</Button>}
      {payment.correctedByPaymentId && <Button variant="ghost" disabled={state.busy} onClick={() => open(payment.correctedByPaymentId!)}>Voir la correction</Button>}
      {recorded && <Button variant="ghost" disabled={state.busy} onClick={() => billing.start({ kind: 'paymentCorrect', paymentId: payment.id })}>Corriger</Button>}
      {recorded && payment.available > 0 && <Button variant="ghost" disabled={state.busy} onClick={() => billing.start({ kind: 'regularize', paymentId: payment.id })}>Régulariser</Button>}
      {recorded && <Button variant="ghost" disabled={state.busy} onClick={() => billing.start({ kind: 'paymentVoid', paymentId: payment.id })}>Annuler le règlement</Button>}
    </div>}
    <DialogFooter>
      <Button variant="outline" disabled={state.busy} onClick={billing.stop}>Fermer</Button>
      {recorded && payment.available > 0 && openInvoices(data).length > 0 && <Button disabled={state.busy}
        onClick={() => billing.start({ kind: 'allocate', paymentId: payment.id })}>Affecter</Button>}
    </DialogFooter>
  </div>;
}

function AllocateBody({ state, data, payment, back }: { state: PlatformConsoleState; data: PlatformBilling; payment: PlatformPayment; back: () => void }) {
  const open = openInvoices(data), suggested = (invoice: PlatformInvoice | null) => (invoice ? francsOf(Math.min(payment.available, balanceOf(invoice))) : '');
  const [invoiceId, setInvoiceId] = useState<string | null>(open[0]?.id ?? null), [amount, setAmount] = useState(() => suggested(open[0] ?? null));
  const [invalid, setInvalid] = useState<Problem | null>(null), [submitted, setSubmitted] = useState(false);
  const invoice = open.find(item => item.id === invoiceId) ?? null;
  const errorOf = (field: string) => (invalid?.field === field ? invalid.message : null);
  const submit = () => {
    if (!invoice) { setInvalid({ field: 'invoice', message: 'Choisissez une facture.' }); return; }
    const value = amountOf(amount);
    if (value === null) { setInvalid({ field: 'amount', message: amountProblem }); return; }
    if (value > payment.available) { setInvalid({ field: 'amount', message: 'Le montant dépasse le reste disponible du règlement.' }); return; }
    if (value > balanceOf(invoice)) { setInvalid({ field: 'amount', message: 'Le montant dépasse le solde de la facture.' }); return; }
    setSubmitted(true);
    void state.billing.allocatePayment(payment.id, invoice.id, value);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Affecter le règlement</DialogTitle><DialogDescription>Non affecté : {chf(payment.available)}</DialogDescription></DialogHeader>
    <FieldGroup>
      <PortalSelect id="allocation-invoice" label="Facture" value={invoiceId} disabled={state.busy} {...selectError(errorOf('invoice') ?? undefined)}
        options={open.map(item => ({ value: item.id, label: `${invoiceName(item)} · solde ${chf(balanceOf(item))}` }))}
        onValueChange={value => { setInvoiceId(value); setAmount(suggested(open.find(item => item.id === value) ?? null)); setInvalid(null); setSubmitted(false); }} />
      <TextField id="allocation-amount" label="Montant (CHF)" inputMode="decimal" value={amount} error={errorOf('amount')} disabled={state.busy}
        onChange={value => { setAmount(value); setInvalid(null); setSubmitted(false); }} />
    </FieldGroup>
    {submitted && <Failure state={state} title="Règlement non affecté" />}
    <Footer state={state} label="Affecter" cancel="Retour" onCancel={back} />
  </form>;
}

/** Une correction remplace l'original, qui reste lisible avec son auteur ; la base reprend ses factures jusqu'au nouveau montant. */
function CorrectBody({ state, data, payment, back }: { state: PlatformConsoleState; data: PlatformBilling; payment: PlatformPayment; back: () => void }) {
  const [draft, setDraft] = useState<PaymentDraft>({ amount: francsOf(payment.amount), receivedOn: payment.receivedOn, method: payment.method,
    reference: payment.reference ?? '', note: payment.note ?? '' });
  const [reason, setReason] = useState(''), [invalid, setInvalid] = useState<Problem | null>(null), [submitted, setSubmitted] = useState(false);
  const touched = () => { setInvalid(null); setSubmitted(false); };
  const set = (field: keyof PaymentDraft) => (value: string) => { setDraft(previous => ({ ...previous, [field]: value })); touched(); };
  const errorOf = (field: string) => (invalid?.field === field ? invalid.message : null);
  const submit = () => {
    const result = fieldsOf(draft, data.today);
    if ('field' in result) { setInvalid(result); return; }
    const problem = reasonProblem(reason);
    if (problem) { setInvalid({ field: 'reason', message: problem }); return; }
    setSubmitted(true);
    void state.billing.correctPayment(payment.id, result.fields, reason);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Corriger le règlement</DialogTitle><DialogDescription>{chf(payment.amount)} · reçu le {civil(payment.receivedOn)}</DialogDescription></DialogHeader>
    <PaymentFieldset draft={draft} set={set} errorOf={errorOf} disabled={state.busy} />
    <FieldGroup><ReasonField id="payment-correct-reason" value={reason} error={errorOf('reason')} disabled={state.busy} onChange={value => { setReason(value); touched(); }} /></FieldGroup>
    {submitted && <Failure state={state} title="Règlement non corrigé" />}
    <Footer state={state} label="Corriger" cancel="Retour" onCancel={back} />
  </form>;
}

/** Une régularisation enregistre ce que l'opérateur a fait : Drivy n'exécute et n'annonce aucun remboursement. */
function RegularizeBody({ state, payment, back }: { state: PlatformConsoleState; payment: PlatformPayment; back: () => void }) {
  const [amount, setAmount] = useState(() => francsOf(payment.available)), [kind, setKind] = useState<PlatformRegularizationKind>('OTHER');
  const [reason, setReason] = useState(''), [invalid, setInvalid] = useState<Problem | null>(null), [submitted, setSubmitted] = useState(false);
  const touched = () => { setInvalid(null); setSubmitted(false); };
  const errorOf = (field: string) => (invalid?.field === field ? invalid.message : null);
  const submit = () => {
    const value = amountOf(amount);
    if (value === null) { setInvalid({ field: 'amount', message: amountProblem }); return; }
    if (value > payment.available) { setInvalid({ field: 'amount', message: 'Le montant dépasse le reste disponible du règlement.' }); return; }
    const problem = reasonProblem(reason);
    if (problem) { setInvalid({ field: 'reason', message: problem }); return; }
    setSubmitted(true);
    void state.billing.regularizePayment(payment.id, value, kind, reason);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Régulariser le règlement</DialogTitle><DialogDescription>Non affecté : {chf(payment.available)}</DialogDescription></DialogHeader>
    <FieldGroup>
      <TextField id="regularization-amount" label="Montant (CHF)" inputMode="decimal" value={amount} error={errorOf('amount')} disabled={state.busy}
        onChange={value => { setAmount(value); touched(); }} />
      <PortalSelect id="regularization-kind" label="Nature" options={regularizationOptions} value={kind} disabled={state.busy}
        onValueChange={value => { if (value) { setKind(value as PlatformRegularizationKind); touched(); } }} />
      <ReasonField id="regularization-reason" value={reason} error={errorOf('reason')} disabled={state.busy} onChange={value => { setReason(value); touched(); }} />
    </FieldGroup>
    {submitted && <Failure state={state} title="Régularisation non enregistrée" />}
    <Footer state={state} label="Enregistrer" cancel="Retour" onCancel={back} />
  </form>;
}

function ReasonBody({ state, id, title, description, failure, label, back, send }: {
  state: PlatformConsoleState; id: string; title: string; description: string; failure: string; label: string; back: () => void; send: (reason: string) => Promise<void>;
}) {
  const [reason, setReason] = useState(''), [invalid, setInvalid] = useState<string | null>(null), [submitted, setSubmitted] = useState(false);
  const submit = () => {
    const problem = reasonProblem(reason);
    if (problem) { setInvalid(problem); return; }
    setSubmitted(true);
    void send(reason);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>{title}</DialogTitle><DialogDescription>{description}</DialogDescription></DialogHeader>
    <FieldGroup><ReasonField id={`${id}-reason`} value={reason} error={invalid} disabled={state.busy}
      onChange={value => { setReason(value); setInvalid(null); setSubmitted(false); }} /></FieldGroup>
    {submitted && <Failure state={state} title={failure} />}
    <Footer state={state} label={label} destructive cancel="Retour" onCancel={back} />
  </form>;
}

function RegularizedBody({ title, back }: { title: string; back: () => void }) {
  return <div className="platform-form">
    <DialogHeader><DialogTitle>{title}</DialogTitle></DialogHeader>
    <Alert variant="destructive"><AlertTitle>Régularisation active</AlertTitle><AlertDescription>Annulez d’abord les régularisations de ce règlement.</AlertDescription></Alert>
    <DialogFooter><Button variant="outline" onClick={back}>Retour</Button></DialogFooter>
  </div>;
}
