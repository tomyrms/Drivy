import { useState, type ReactNode } from 'react';
import {
  centsOf, chf, francsOf, instantOf, lifecycleLabel, lifecycleRestricted, missingLabel, modulesLabel, requestKindLabel, requestOpen, requestStatusLabel, suspensionLabel,
  termsPhaseLabel, trialKindLabel, wholeOf, zurichToday,
  type PlatformClientDetail, type PlatformCommercialDetail, type PlatformCommercialRequest, type PlatformTermsVersion,
} from '../../platform-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import { PortalSelect } from '../components/portal-select';
import type { DecisionInput, RequestInput, TermsInput } from './use-platform-commercial';
import type { PlatformConsoleState } from './use-platform-console';

const dateTime = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
/** Un jour civil reste ce jour-là, quel que soit le fuseau du navigateur. */
const civil = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeZone: 'UTC' }).format(new Date(`${value}T00:00:00Z`));
const by = (name: string | null) => (name ? ` · par ${name}` : '');
/** `PortalSelect` n'accepte pas d'erreur `undefined` : la propriété n'est posée que s'il y a un message. */
const selectError = (message: string | undefined) => (message ? { error: message } : {});
/** Instant ISO → valeur d'un champ `datetime-local` à l'heure du navigateur. */
const localInput = (value: string | null) => {
  if (!value) return '';
  const date = new Date(value), pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};
const reasonProblem = (text: string, min = 3, max = 500) => {
  const trimmed = text.trim();
  if (trimmed.length < min) return 'Indiquez le motif en quelques mots.';
  return trimmed.length > max ? `Ce texte est limité à ${max} caractères.` : null;
};

/**
 * Contrat de l'école : cycle commercial, essai, conditions, début payant, demandes et échéancier prévisionnel (R01-T04).
 * L'écran ne calcule rien : chaque montant, chaque date de période et chaque règle viennent du dossier relu par l'API.
 */
export function CommercialPanel({ state, client }: { state: PlatformConsoleState; client: PlatformClientDetail }) {
  const { commercial } = state, data = commercial.commercial;
  if (!data) return null;
  const terminated = data.lifecycle === 'TERMINATED';
  const trialRunning = data.trial?.phase === 'RUNNING' || data.trial?.phase === 'SCHEDULED';
  const trialOpen = !terminated && !data.paidStart?.started;
  const latest = data.terms.scheduled ?? data.terms.inForce;
  const open = data.requests.filter(item => requestOpen(item.status));
  // Après confirmation, seule une décision d'opérateur change la date ou reprend le service, et seulement avant la date d'effet.
  const revisable = data.requests.filter(item => item.kind === 'TERMINATION' && item.status === 'ACCEPTED' && item.effectiveOn !== null && item.effectiveOn > data.today);
  return <div className="platform-group platform-rights-panel" role="group" aria-label={`Contrat de ${client.displayName ?? client.school?.name ?? 'l’école'}`}>
    <div className="platform-fiche-head">
      <h4 className="platform-subtitle">Contrat</h4>
      {!terminated && <div className="platform-actions">
        <Button variant="outline" disabled={state.busy} onClick={() => commercial.start({ kind: 'terms' })}>{latest ? 'Nouvelles conditions' : 'Saisir les conditions'}</Button>
        {!data.paidStart && <Button variant="outline" disabled={state.busy} onClick={() => commercial.start({ kind: 'paid-start' })}>Confirmer le payant</Button>}
        <Button variant="ghost" disabled={state.busy} onClick={() => commercial.start({ kind: 'request' })}>Enregistrer une demande</Button>
      </div>}
    </div>
    <div className="platform-summary">
      <strong>{lifecycleLabel(data.lifecycle)}{lifecycleRestricted(data.lifecycle) && <Badge variant="destructive">Usage nouveau fermé</Badge>}</strong>
      {data.lifecycle === 'NONE' && !data.trial && !data.paidStart && <span>École pilote ou contrat à préparer</span>}
    </div>
    <dl className="platform-facts">
      <Fact label="Essai">{data.trial ? `${dateTime(data.trial.startsAt)} → ${dateTime(data.trial.endsAt)}` : 'Aucun'}</Fact>
      <Fact label="Conditions">{data.terms.status === 'COMPLETE' ? 'Complètes' : data.terms.status === 'NONE' ? 'Aucune' : `À compléter : ${missingLabel(data.terms.missing)}`}</Fact>
      {data.terms.inForce && <TermsFacts terms={data.terms.inForce} />}
      <Fact label="Début payant">{data.paidStart ? `${civil(data.paidStart.startsOn)}${data.paidStart.termsSequence ? ` · conditions v${data.paidStart.termsSequence}` : ''}` : 'Non confirmé'}</Fact>
      {data.nextPeriodStart && <Fact label="Prochaine période">{civil(data.nextPeriodStart)}</Fact>}
      {data.termination && <Fact label="Résiliation">{civil(data.termination.effectiveOn)}</Fact>}
    </dl>
    {(trialOpen || (data.paidStart && !data.paidStart.started)) && <div className="platform-actions">
      {trialOpen && !data.trial && <Button variant="outline" disabled={state.busy} onClick={() => commercial.start({ kind: 'trial-start' })}>Accorder un essai</Button>}
      {trialOpen && data.trial && <Button variant="outline" disabled={state.busy} onClick={() => commercial.start({ kind: 'trial-extend' })}>Prolonger l’essai</Button>}
      {trialOpen && trialRunning && <Button variant="ghost" disabled={state.busy} onClick={() => commercial.start({ kind: 'trial-end' })}>Terminer l’essai</Button>}
      {data.paidStart && !data.paidStart.started && <Button variant="ghost" disabled={state.busy} onClick={() => commercial.start({ kind: 'paid-cancel' })}>Annuler le début payant</Button>}
    </div>}
    {data.terms.scheduled && <div className="platform-pending" role="group" aria-label="Conditions prévues">
      <div className="platform-summary"><strong>Conditions v{data.terms.scheduled.sequence}</strong><span>Dès le {civil(data.terms.scheduled.effectiveFrom)}</span></div>
    </div>}
    {open.length > 0 && <ul className="platform-list" aria-label="Demandes en cours">{open.map(item => <li key={item.id}>
      <RequestSummary item={item} />
      <Button variant="ghost" disabled={state.busy} aria-label={`Traiter la demande : ${requestKindLabel(item.kind)}`} onClick={() => commercial.start({ kind: 'decision', requestId: item.id })}>Traiter</Button>
    </li>)}</ul>}
    {revisable.length > 0 && <ul className="platform-list" aria-label="Résiliations confirmées">{revisable.map(item => <li key={item.id}>
      <RequestSummary item={item} />
      <div className="platform-actions">
        <Button variant="outline" disabled={state.busy} onClick={() => commercial.start({ kind: 'revision', requestId: item.id, action: 'CHANGE_DATE' })}>Changer la date</Button>
        <Button variant="ghost" disabled={state.busy} onClick={() => commercial.start({ kind: 'revision', requestId: item.id, action: 'RESUME' })}>Reprendre le service</Button>
      </div>
    </li>)}</ul>}
    <Schedule data={data} />
    <History data={data} />
  </div>;
}

function Fact({ label, children }: { label: string; children: ReactNode }) {
  return <div><dt>{label}</dt><dd>{children}</dd></div>;
}

function TermsFacts({ terms }: { terms: PlatformTermsVersion }) {
  const initialNet = terms.initialAmount === null ? null : terms.initialAmount - terms.initialDiscount;
  const monthlyNet = terms.monthlyAmount === null ? null : terms.monthlyAmount - terms.recurringDiscount;
  return <>
    <Fact label="Montant initial">{chf(initialNet)}{terms.initialDiscount > 0 ? ` (remise ${chf(terms.initialDiscount)})` : ''}</Fact>
    <Fact label="Mensualité">{chf(monthlyNet)}{terms.recurringDiscount > 0
      ? ` (remise ${chf(terms.recurringDiscount)}${terms.recurringDiscountMonths ? ` pendant ${terms.recurringDiscountMonths} mois` : ''})` : ''}</Fact>
    <Fact label="Paiement">{terms.paymentTermDays === null ? 'À compléter' : `${terms.paymentTermDays} jours`} · suspension {suspensionLabel(terms.suspensionBilling).toLowerCase()}</Fact>
  </>;
}

function RequestSummary({ item }: { item: PlatformCommercialRequest }) {
  const parts = [`Reçue le ${civil(item.requestedOn)}`];
  if (item.source === 'SCHOOL') parts.push('demande de l’école');
  if (item.requestedOfferName) parts.push(item.requestedOfferName);
  if (item.requestedModules.length > 0) parts.push(modulesLabel(item.requestedModules));
  if (item.desiredOn) parts.push(`souhaitée le ${civil(item.desiredOn)}`);
  if (item.effectiveOn) parts.push(`effet le ${civil(item.effectiveOn)}`);
  return <div className="platform-summary">
    <strong>{requestKindLabel(item.kind)}<Badge variant="outline">{item.withdrawnBySchool ? 'Retirée par l’école' : requestStatusLabel(item.status)}</Badge></strong>
    <span>{parts.join(' · ')}</span>
    {item.details && <span>{item.details}</span>}
    {item.response && <span>Réponse : {item.response}</span>}
    {item.revisions.map(revision => <span key={revision.decidedAt}>
      {revision.action === 'RESUME' ? 'Service repris' : `Date reportée au ${civil(revision.newEffectiveOn ?? revision.previousEffectiveOn)}`} · {dateTime(revision.decidedAt)}{by(revision.decidedByName)} : {revision.response}
    </span>)}
  </div>;
}

/** Échéancier prévisionnel : aucune facture n'en naît ici. Montré seulement quand le dossier en porte un. */
function Schedule({ data }: { data: PlatformCommercialDetail }) {
  const { initial, periods } = data.schedule;
  if (!initial && periods.length === 0) return null;
  return <details className="platform-history">
    <summary>Échéancier prévisionnel</summary>
    <ol className="platform-list" aria-label="Échéances">
      {initial && <li><div className="platform-summary"><strong>Montant initial · {chf(initial.net)}</strong><span>Dû le {civil(initial.dueOn)}</span></div></li>}
      {periods.map(period => <li key={period.index}><div className="platform-summary">
        <strong>{civil(period.startsOn)} → {civil(period.endsOn)} · {chf(period.net)}</strong>
        {period.discount > 0 && <span>Remise {chf(period.discount)}</span>}
      </div></li>)}
    </ol>
  </details>;
}

function History({ data }: { data: PlatformCommercialDetail }) {
  const closed = data.requests.filter(item => !requestOpen(item.status));
  if (data.terms.versions.length === 0 && data.trialChanges.length === 0 && data.paidStarts.length === 0 && closed.length === 0) return null;
  return <details className="platform-history">
    <summary>Historique du contrat</summary>
    {data.terms.versions.length > 0 && <ol className="platform-list" aria-label="Versions des conditions">{data.terms.versions.map(item => <li key={item.id}>
      <div className="platform-summary"><strong>Conditions v{item.sequence}<Badge variant="outline">{termsPhaseLabel(item.phase)}</Badge></strong>
        <span>Dès le {civil(item.effectiveFrom)} · {dateTime(item.createdAt)}{by(item.createdByName)}</span>
        {item.exceptionReason && <span>Exception : {item.exceptionReason}</span>}</div></li>)}</ol>}
    {data.trialChanges.length > 0 && <ol className="platform-list" aria-label="Essai">{data.trialChanges.map(item => <li key={item.id}>
      <div className="platform-summary"><strong>{trialKindLabel(item.kind)}</strong>
        <span>Fin {dateTime(item.endsAt)} · {dateTime(item.createdAt)}{by(item.createdByName)}</span>
        {item.reason && <span>{item.reason}</span>}</div></li>)}</ol>}
    {data.paidStarts.length > 0 && <ol className="platform-list" aria-label="Débuts payants">{data.paidStarts.map(item => <li key={item.id}>
      <div className="platform-summary"><strong>Début payant le {civil(item.startsOn)}{item.status === 'CANCELLED' && <Badge variant="outline">Annulé</Badge>}</strong>
        <span>Confirmé le {dateTime(item.confirmedAt)}{by(item.confirmedByName)}</span>
        {item.cancelReason && <span>Annulé{item.cancelledAt ? ` le ${dateTime(item.cancelledAt)}` : ''}{by(item.cancelledByName)} : {item.cancelReason}</span>}</div></li>)}</ol>}
    {closed.length > 0 && <ol className="platform-list" aria-label="Demandes traitées">{closed.map(item => <li key={item.id}><RequestSummary item={item} /></li>)}</ol>}
  </details>;
}

/** Les commandes du contrat partent d'ici ; chacune est relue par l'API sous la version du dossier affichée. */
export function CommercialDialog({ state }: { state: PlatformConsoleState }) {
  const { commercial } = state, target = commercial.dialog, data = commercial.commercial;
  return <Dialog open={target !== null && data !== null} onOpenChange={(open, details) => { if (state.busy) details.cancel(); else if (!open) commercial.stop(); }}>
    <DialogContent showCloseButton={!state.busy}>
      {data && target?.kind === 'terms' && <TermsBody state={state} data={data} />}
      {data && target?.kind === 'trial-start' && <TrialStartBody state={state} data={data} />}
      {data && (target?.kind === 'trial-extend' || target?.kind === 'trial-end' || target?.kind === 'paid-cancel') && <ReasonBody state={state} data={data} kind={target.kind} />}
      {data && target?.kind === 'paid-start' && <PaidStartBody state={state} data={data} />}
      {data && target?.kind === 'request' && <RequestBody state={state} data={data} />}
      {data && target?.kind === 'decision' && <DecisionBody state={state} item={data.requests.find(item => item.id === target.requestId) ?? null} />}
      {data && target?.kind === 'revision' && <RevisionBody state={state} data={data} action={target.action} item={data.requests.find(item => item.id === target.requestId) ?? null} />}
    </DialogContent>
  </Dialog>;
}

function Failure({ state, title }: { state: PlatformConsoleState; title: string }) {
  return state.error ? <Alert variant="destructive"><AlertTitle>{title}</AlertTitle><AlertDescription>{state.error}</AlertDescription></Alert> : null;
}
function Footer({ state, label, busyLabel = 'Enregistrement…', destructive = false }: { state: PlatformConsoleState; label: string; busyLabel?: string; destructive?: boolean }) {
  return <DialogFooter><Button type="button" variant="outline" disabled={state.busy} onClick={state.commercial.stop}>Annuler</Button>
    <Button type="submit" variant={destructive ? 'destructive' : 'default'} disabled={state.busy} aria-busy={state.busy}>{state.busy ? busyLabel : label}</Button></DialogFooter>;
}
function TextField({ id, label, value, onChange, error, type = 'text', disabled, inputMode }: {
  id: string; label: string; value: string; onChange: (value: string) => void; error?: string | null | undefined; type?: string; disabled: boolean;
  inputMode?: 'decimal' | 'numeric';
}) {
  return <Field data-invalid={!!error}>
    <FieldLabel htmlFor={id}>{label}</FieldLabel>
    <Input id={id} name={id} type={type} inputMode={inputMode} value={value} disabled={disabled} aria-invalid={!!error} aria-describedby={error ? `${id}-error` : undefined}
      onChange={event => onChange(event.target.value)} />
    {error && <FieldError id={`${id}-error`}>{error}</FieldError>}
  </Field>;
}
function ReasonField({ id, label = 'Motif', value, onChange, error, disabled, max = 500 }: {
  id: string; label?: string; value: string; onChange: (value: string) => void; error?: string | null | undefined; disabled: boolean; max?: number;
}) {
  return <Field data-invalid={!!error}>
    <FieldLabel htmlFor={id}>{label}</FieldLabel>
    <Textarea id={id} name={id} rows={3} maxLength={max} value={value} disabled={disabled} aria-invalid={!!error}
      aria-describedby={error ? `${id}-error` : undefined} onChange={event => onChange(event.target.value)} />
    {error && <FieldError id={`${id}-error`}>{error}</FieldError>}
  </Field>;
}

type TermsDraft = Record<'initialAmount' | 'initialDiscount' | 'initialDueOn' | 'monthlyAmount' | 'recurringDiscount' | 'recurringDiscountMonths' | 'paymentTermDays'
  | 'effectiveFrom' | 'exceptionReason', string> & { suspensionBilling: string | null };
const draftOf = (terms: PlatformTermsVersion | null): TermsDraft => ({
  initialAmount: francsOf(terms?.initialAmount ?? null), initialDiscount: terms?.initialDiscount ? francsOf(terms.initialDiscount) : '',
  initialDueOn: terms?.initialDueOn ?? '', monthlyAmount: francsOf(terms?.monthlyAmount ?? null),
  recurringDiscount: terms?.recurringDiscount ? francsOf(terms.recurringDiscount) : '', recurringDiscountMonths: terms?.recurringDiscountMonths ? String(terms.recurringDiscountMonths) : '',
  paymentTermDays: terms?.paymentTermDays !== null && terms?.paymentTermDays !== undefined ? String(terms.paymentTermDays) : '',
  suspensionBilling: terms?.suspensionBilling ?? null, effectiveFrom: '', exceptionReason: '',
});
/** La saisie au format de la commande, ou la première zone à corriger ; l'API relit les mêmes règles et la date de période. */
function termsInput(draft: TermsDraft): { input: TermsInput } | { field: keyof TermsDraft; message: string } {
  const money = 'Saisissez un montant en francs, par exemple 1200 ou 89.50.';
  const initialAmount = centsOf(draft.initialAmount, 100_000_000);
  if (initialAmount === undefined) return { field: 'initialAmount', message: money };
  const initialDiscount = centsOf(draft.initialDiscount, 100_000_000);
  if (initialDiscount === undefined) return { field: 'initialDiscount', message: money };
  if ((initialDiscount ?? 0) > 0 && (initialAmount === null || (initialDiscount ?? 0) > initialAmount)) return { field: 'initialDiscount', message: 'La remise dépasse le montant initial.' };
  const monthlyAmount = centsOf(draft.monthlyAmount, 10_000_000);
  if (monthlyAmount === undefined) return { field: 'monthlyAmount', message: money };
  const recurringDiscount = centsOf(draft.recurringDiscount, 10_000_000);
  if (recurringDiscount === undefined) return { field: 'recurringDiscount', message: money };
  if ((recurringDiscount ?? 0) > 0 && (monthlyAmount === null || (recurringDiscount ?? 0) > monthlyAmount)) return { field: 'recurringDiscount', message: 'La remise dépasse la mensualité.' };
  const recurringDiscountMonths = wholeOf(draft.recurringDiscountMonths, 1, 120);
  if (recurringDiscountMonths === undefined) return { field: 'recurringDiscountMonths', message: 'Entre 1 et 120 mois.' };
  if (recurringDiscountMonths !== null && !recurringDiscount) return { field: 'recurringDiscountMonths', message: 'Une durée suppose une remise.' };
  const paymentTermDays = wholeOf(draft.paymentTermDays, 0, 120);
  if (paymentTermDays === undefined) return { field: 'paymentTermDays', message: 'Entre 0 et 120 jours.' };
  const reason = draft.exceptionReason.trim();
  if (reason && reasonProblem(reason)) return { field: 'exceptionReason', message: reasonProblem(reason)! };
  const suspension = draft.suspensionBilling === 'CONTINUE' || draft.suspensionBilling === 'PAUSE' ? draft.suspensionBilling : null;
  return { input: {
    initialAmount, initialDiscount: initialDiscount ?? 0, initialDueOn: draft.initialDueOn || null, monthlyAmount, recurringDiscount: recurringDiscount ?? 0,
    recurringDiscountMonths, paymentTermDays, suspensionBilling: suspension,
    ...(draft.effectiveFrom ? { effectiveFrom: draft.effectiveFrom } : {}), ...(reason ? { exceptionReason: reason } : {}),
  } };
}

function TermsBody({ state, data }: { state: PlatformConsoleState; data: PlatformCommercialDetail }) {
  const [draft, setDraft] = useState(() => draftOf(data.terms.scheduled ?? data.terms.inForce));
  const [invalid, setInvalid] = useState<{ field: keyof TermsDraft; message: string } | null>(null);
  const set = (field: keyof TermsDraft) => (value: string | null) => { setDraft(previous => ({ ...previous, [field]: value ?? '' })); setInvalid(null); };
  const errorOf = (field: keyof TermsDraft) => (invalid?.field === field ? invalid.message : null);
  const paid = data.paidStart !== null;
  const submit = () => {
    const result = termsInput(draft);
    if ('field' in result) { setInvalid(result); return; }
    // Après le début payant, une date autre que la prochaine période est une exception : l'API la refuse sans motif.
    if (paid && draft.effectiveFrom && draft.effectiveFrom !== data.nextPeriodStart && !result.input.exceptionReason) {
      setInvalid({ field: 'exceptionReason', message: 'Indiquez pourquoi cette date fait exception.' }); return;
    }
    void state.commercial.saveTerms(result.input);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Conditions commerciales</DialogTitle>
      {paid && data.nextPeriodStart && <DialogDescription>Prend effet le {civil(data.nextPeriodStart)} sauf autre date motivée.</DialogDescription>}</DialogHeader>
    <FieldGroup className="platform-grid">
      <TextField id="terms-initial" label="Montant initial (CHF)" inputMode="decimal" value={draft.initialAmount} onChange={set('initialAmount')} error={errorOf('initialAmount')} disabled={state.busy} />
      <TextField id="terms-initial-discount" label="Remise initiale (CHF)" inputMode="decimal" value={draft.initialDiscount} onChange={set('initialDiscount')} error={errorOf('initialDiscount')} disabled={state.busy} />
      <TextField id="terms-initial-due" label="Échéance du montant initial" type="date" value={draft.initialDueOn} onChange={set('initialDueOn')} disabled={state.busy} />
      <TextField id="terms-monthly" label="Mensualité (CHF)" inputMode="decimal" value={draft.monthlyAmount} onChange={set('monthlyAmount')} error={errorOf('monthlyAmount')} disabled={state.busy} />
      <TextField id="terms-recurring-discount" label="Remise mensuelle (CHF)" inputMode="decimal" value={draft.recurringDiscount} onChange={set('recurringDiscount')} error={errorOf('recurringDiscount')} disabled={state.busy} />
      <TextField id="terms-discount-months" label="Durée de la remise (mois)" inputMode="numeric" value={draft.recurringDiscountMonths} onChange={set('recurringDiscountMonths')} error={errorOf('recurringDiscountMonths')} disabled={state.busy} />
      <TextField id="terms-payment" label="Délai de paiement (jours)" inputMode="numeric" value={draft.paymentTermDays} onChange={set('paymentTermDays')} error={errorOf('paymentTermDays')} disabled={state.busy} />
      <PortalSelect id="terms-suspension" label="Pendant une suspension" value={draft.suspensionBilling} disabled={state.busy}
        options={[{ value: 'CONTINUE', label: 'Facturer' }, { value: 'PAUSE', label: 'Ne pas facturer' }]} onValueChange={value => { setDraft(previous => ({ ...previous, suspensionBilling: value })); setInvalid(null); }} />
      <TextField id="terms-effective" label="Date d’effet (facultative)" type="date" value={draft.effectiveFrom} onChange={set('effectiveFrom')} disabled={state.busy} />
    </FieldGroup>
    {paid && draft.effectiveFrom !== '' && <ReasonField id="terms-exception" label="Motif de l’exception" value={draft.exceptionReason} onChange={set('exceptionReason')}
      error={errorOf('exceptionReason')} disabled={state.busy} />}
    <Failure state={state} title="Conditions non enregistrées" />
    <Footer state={state} label="Enregistrer la version" />
  </form>;
}

function TrialStartBody({ state, data }: { state: PlatformConsoleState; data: PlatformCommercialDetail }) {
  const [starts, setStarts] = useState(localInput(data.proposedTrialStart)), [ends, setEnds] = useState(''), [invalid, setInvalid] = useState<string | null>(null);
  const submit = () => {
    const endsAt = instantOf(ends);
    if (!endsAt || new Date(endsAt).getTime() <= Date.now()) { setInvalid('Choisissez une fin à venir.'); return; }
    const startsAt = starts ? instantOf(starts) : undefined;
    if (startsAt && new Date(startsAt).getTime() >= new Date(endsAt).getTime()) { setInvalid('La fin doit suivre le début.'); return; }
    void state.commercial.startTrial(endsAt, startsAt);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Accorder un essai</DialogTitle></DialogHeader>
    <FieldGroup>
      <TextField id="trial-start" label="Début" type="datetime-local" value={starts} onChange={value => { setStarts(value); setInvalid(null); }} disabled={state.busy} />
      <TextField id="trial-end" label="Fin" type="datetime-local" value={ends} onChange={value => { setEnds(value); setInvalid(null); }} error={invalid} disabled={state.busy} />
    </FieldGroup>
    <Failure state={state} title="Essai non accordé" />
    <Footer state={state} label="Accorder l’essai" />
  </form>;
}

function ReasonBody({ state, data, kind }: { state: PlatformConsoleState; data: PlatformCommercialDetail; kind: 'trial-extend' | 'trial-end' | 'paid-cancel' }) {
  const [reason, setReason] = useState(''), [ends, setEnds] = useState(localInput(data.trial?.endsAt ?? null));
  const [invalid, setInvalid] = useState<{ field: 'reason' | 'ends'; message: string } | null>(null);
  const titles = { 'trial-extend': 'Prolonger l’essai', 'trial-end': 'Terminer l’essai maintenant ?', 'paid-cancel': 'Annuler le début payant ?' } as const;
  const failures = { 'trial-extend': 'Essai non prolongé', 'trial-end': 'Essai non terminé', 'paid-cancel': 'Début payant non annulé' } as const;
  const labels = { 'trial-extend': 'Prolonger', 'trial-end': 'Terminer l’essai', 'paid-cancel': 'Annuler le début payant' } as const;
  const submit = () => {
    const problem = reasonProblem(reason);
    if (problem) { setInvalid({ field: 'reason', message: problem }); return; }
    if (kind === 'trial-extend') {
      const endsAt = instantOf(ends);
      if (!endsAt || (data.trial && new Date(endsAt).getTime() <= new Date(data.trial.endsAt).getTime())) { setInvalid({ field: 'ends', message: 'Choisissez une fin après la fin actuelle.' }); return; }
      void state.commercial.extendTrial(endsAt, reason);
    } else if (kind === 'trial-end') void state.commercial.endTrial(reason);
    else void state.commercial.cancelPaidStart(reason);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>{titles[kind]}</DialogTitle>
      {kind === 'trial-end' && <DialogDescription>L’usage nouveau se ferme aussitôt ; la consultation reste possible.</DialogDescription>}
      {kind === 'paid-cancel' && data.paidStart && <DialogDescription>Prévu le {civil(data.paidStart.startsOn)}</DialogDescription>}</DialogHeader>
    <FieldGroup>
      {kind === 'trial-extend' && <TextField id="trial-new-end" label="Nouvelle fin" type="datetime-local" value={ends} onChange={value => { setEnds(value); setInvalid(null); }}
        error={invalid?.field === 'ends' ? invalid.message : null} disabled={state.busy} />}
      <ReasonField id="commercial-reason" value={reason} onChange={value => { setReason(value); setInvalid(null); }} error={invalid?.field === 'reason' ? invalid.message : null} disabled={state.busy} />
    </FieldGroup>
    <Failure state={state} title={failures[kind]} />
    <Footer state={state} label={labels[kind]} destructive={kind !== 'trial-extend'} />
  </form>;
}

/** Le passage au payant se confirme sur ce que le serveur dit des conditions à cette date : rien n'est déduit ici. */
function PaidStartBody({ state, data }: { state: PlatformConsoleState; data: PlatformCommercialDetail }) {
  // Proposé : le jour où l'essai finit, jamais avant aujourd'hui.
  const proposed = data.trial?.endsAt ? zurichToday(new Date(data.trial.endsAt)) : data.today;
  const [startsOn, setStartsOn] = useState(proposed < data.today ? data.today : proposed), [invalid, setInvalid] = useState<string | null>(null);
  const incomplete = data.terms.status !== 'COMPLETE';
  const submit = () => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(startsOn) || startsOn < data.today) { setInvalid('Choisissez aujourd’hui ou une date à venir.'); return; }
    void state.commercial.confirmPaidStart(startsOn);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Confirmer le début payant</DialogTitle>
      <DialogDescription>Les périodes suivront le jour du mois de cette date.</DialogDescription></DialogHeader>
    <FieldGroup>
      <TextField id="paid-start" label="Premier jour payant" type="date" value={startsOn} onChange={value => { setStartsOn(value); setInvalid(null); }} error={invalid} disabled={state.busy} />
    </FieldGroup>
    {incomplete && <Alert><AlertTitle>Conditions à compléter</AlertTitle><AlertDescription>{missingLabel(data.terms.missing)}</AlertDescription></Alert>}
    <Failure state={state} title="Début payant non confirmé" />
    <Footer state={state} label="Confirmer" />
  </form>;
}

function RequestBody({ state, data }: { state: PlatformConsoleState; data: PlatformCommercialDetail }) {
  const [kind, setKind] = useState<RequestInput['kind'] | null>(null), [requestedOn, setRequestedOn] = useState(data.today), [offerId, setOfferId] = useState<string | null>(null);
  const [desiredOn, setDesiredOn] = useState(''), [details, setDetails] = useState(''), [invalid, setInvalid] = useState<{ field: string; message: string } | null>(null);
  const offers = state.offers.offers.filter(offer => offer.status === 'ACTIVE').map(offer => ({ value: offer.id, label: offer.name }));
  const submit = () => {
    if (!kind) { setInvalid({ field: 'kind', message: 'Choisissez le type de demande.' }); return; }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(requestedOn) || requestedOn > data.today) { setInvalid({ field: 'requestedOn', message: 'La date de la demande ne peut pas être à venir.' }); return; }
    const text = details.trim();
    if (text && reasonProblem(text, 3, 1000)) { setInvalid({ field: 'details', message: reasonProblem(text, 3, 1000)! }); return; }
    void state.commercial.recordRequest({ kind, requestedOn, ...(kind === 'OFFER_CHANGE' && offerId ? { requestedOfferId: offerId } : {}),
      ...(desiredOn ? { desiredOn } : {}), ...(text ? { details: text } : {}) });
  };
  const errorOf = (field: string) => (invalid?.field === field ? invalid.message : undefined);
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Enregistrer une demande</DialogTitle></DialogHeader>
    <FieldGroup>
      <PortalSelect id="request-kind" label="Demande" value={kind} disabled={state.busy} {...selectError(errorOf('kind'))}
        options={[{ value: 'OFFER_CHANGE', label: 'Changement d’offre' }, { value: 'TERMINATION', label: 'Résiliation' }]}
        onValueChange={value => { setKind(value === 'OFFER_CHANGE' || value === 'TERMINATION' ? value : null); setInvalid(null); }} />
      {kind === 'OFFER_CHANGE' && <PortalSelect id="request-offer" label="Offre souhaitée (facultative)" value={offerId} options={offers} disabled={state.busy} onValueChange={setOfferId} />}
      <TextField id="request-on" label="Reçue le" type="date" value={requestedOn} onChange={value => { setRequestedOn(value); setInvalid(null); }} error={errorOf('requestedOn')} disabled={state.busy} />
      <TextField id="request-desired" label="Date souhaitée (facultative)" type="date" value={desiredOn} onChange={setDesiredOn} disabled={state.busy} />
      <ReasonField id="request-details" label="Précisions (facultatives)" max={1000} value={details} onChange={value => { setDetails(value); setInvalid(null); }} error={errorOf('details')} disabled={state.busy} />
    </FieldGroup>
    <Failure state={state} title="Demande non enregistrée" />
    <Footer state={state} label="Enregistrer" />
  </form>;
}

function DecisionBody({ state, item }: { state: PlatformConsoleState; item: PlatformCommercialRequest | null }) {
  const [status, setStatus] = useState<DecisionInput['status'] | null>(null), [response, setResponse] = useState(''), [effectiveOn, setEffectiveOn] = useState(item?.desiredOn ?? (item?.kind === 'REGULARIZATION' ? zurichToday() : ''));
  const [offerId, setOfferId] = useState<string | null>(item?.requestedOfferId ?? null), [invalid, setInvalid] = useState<{ field: string; message: string } | null>(null);
  const offers = state.offers.offers.filter(offer => offer.status === 'ACTIVE').map(offer => ({ value: offer.id, label: offer.name }));
  if (!item) return <DialogHeader><DialogTitle>Demande introuvable</DialogTitle></DialogHeader>;
  const termination = item.kind === 'TERMINATION', offerChange = item.kind === 'OFFER_CHANGE';
  const statuses = [
    ...(item.status === 'RECEIVED' ? [{ value: 'IN_PROGRESS', label: 'Prendre en charge' }] : []),
    { value: 'ACCEPTED', label: 'Accepter' }, { value: 'REFUSED', label: 'Refuser' }, { value: 'WITHDRAWN', label: 'Retirée par l’école' },
  ];
  const submit = () => {
    if (!status) { setInvalid({ field: 'status', message: 'Choisissez une décision.' }); return; }
    const text = response.trim();
    if (status === 'REFUSED' && !text) { setInvalid({ field: 'response', message: 'Un refus porte sa réponse.' }); return; }
    if (text && reasonProblem(text, 3, 1000)) { setInvalid({ field: 'response', message: reasonProblem(text, 3, 1000)! }); return; }
    if (status === 'ACCEPTED' && !/^\d{4}-\d{2}-\d{2}$/.test(effectiveOn)) { setInvalid({ field: 'effectiveOn', message: 'Une acceptation porte sa date d’effet.' }); return; }
    if (status === 'ACCEPTED' && offerChange && !offerId) { setInvalid({ field: 'offer', message: 'Choisissez l’offre acceptée.' }); return; }
    void state.commercial.decide(item.id, { status, ...(text ? { response: text } : {}),
      ...(status === 'ACCEPTED' ? { effectiveOn, ...(offerChange && offerId ? { offerId } : {}) } : {}) });
  };
  const errorOf = (field: string) => (invalid?.field === field ? invalid.message : undefined);
  const final = status === 'ACCEPTED' || status === 'REFUSED' || status === 'WITHDRAWN';
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>{requestKindLabel(item.kind)}</DialogTitle>
      <DialogDescription>Reçue le {civil(item.requestedOn)}{item.requestedOfferName ? ` · ${item.requestedOfferName}` : ''}{item.requestedModules.length ? ` · ${modulesLabel(item.requestedModules)}` : ''}</DialogDescription></DialogHeader>
    <FieldGroup>
      <PortalSelect id="decision-status" label="Décision" value={status} options={statuses} disabled={state.busy} {...selectError(errorOf('status'))}
        onValueChange={value => { setStatus(value as DecisionInput['status'] | null); setInvalid(null); }} />
      {status === 'ACCEPTED' && <TextField id="decision-effective" label="Date d’effet" type="date" value={effectiveOn} onChange={value => { setEffectiveOn(value); setInvalid(null); }}
        error={errorOf('effectiveOn')} disabled={state.busy} />}
      {status === 'ACCEPTED' && offerChange && <PortalSelect id="decision-offer" label="Offre acceptée" value={offerId} options={offers} disabled={state.busy} {...selectError(errorOf('offer'))}
        onValueChange={value => { setOfferId(value); setInvalid(null); }} />}
      <ReasonField id="decision-response" label={status === 'REFUSED' ? 'Réponse' : 'Réponse (facultative)'} max={1000} value={response}
        onChange={value => { setResponse(value); setInvalid(null); }} error={errorOf('response')} disabled={state.busy} />
    </FieldGroup>
    {status === 'ACCEPTED' && termination && <Alert variant="destructive"><AlertTitle>Résiliation définitive</AlertTitle>
      <AlertDescription>L’usage nouveau se fermera à la date d’effet.</AlertDescription></Alert>}
    <Failure state={state} title="Décision non enregistrée" />
    <Footer state={state} label={final ? 'Enregistrer la décision' : 'Prendre en charge'} destructive={status === 'ACCEPTED' && termination} />
  </form>;
}

/** Une résiliation confirmée ne change qu'ici : décision conservée à côté de la première, jamais après la date d'effet. */
function RevisionBody({ state, data, action, item }: { state: PlatformConsoleState; data: PlatformCommercialDetail; action: 'CHANGE_DATE' | 'RESUME'; item: PlatformCommercialRequest | null }) {
  const [effectiveOn, setEffectiveOn] = useState(item?.effectiveOn ?? ''), [response, setResponse] = useState('');
  const [invalid, setInvalid] = useState<{ field: 'effectiveOn' | 'response'; message: string } | null>(null);
  if (!item) return <DialogHeader><DialogTitle>Demande introuvable</DialogTitle></DialogHeader>;
  const changing = action === 'CHANGE_DATE';
  const submit = () => {
    if (changing && (!/^\d{4}-\d{2}-\d{2}$/.test(effectiveOn) || effectiveOn < data.today)) { setInvalid({ field: 'effectiveOn', message: 'Choisissez aujourd’hui ou une date à venir.' }); return; }
    if (changing && effectiveOn === item.effectiveOn) { setInvalid({ field: 'effectiveOn', message: 'Choisissez une autre date.' }); return; }
    const text = response.trim(), problem = reasonProblem(text, 3, 1000);
    if (problem) { setInvalid({ field: 'response', message: problem }); return; }
    void state.commercial.revise(item.id, { action, ...(changing ? { effectiveOn } : {}), response: text });
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>{changing ? 'Changer la date de résiliation' : 'Reprendre le service ?'}</DialogTitle>
      {item.effectiveOn && <DialogDescription>Fin prévue le {civil(item.effectiveOn)}</DialogDescription>}</DialogHeader>
    <FieldGroup>
      {changing && <TextField id="revision-effective" label="Nouvelle date d’effet" type="date" value={effectiveOn} onChange={value => { setEffectiveOn(value); setInvalid(null); }}
        error={invalid?.field === 'effectiveOn' ? invalid.message : null} disabled={state.busy} />}
      <ReasonField id="revision-response" label="Réponse à l’école" max={1000} value={response} onChange={value => { setResponse(value); setInvalid(null); }}
        error={invalid?.field === 'response' ? invalid.message : null} disabled={state.busy} />
    </FieldGroup>
    <Failure state={state} title="Décision non enregistrée" />
    <Footer state={state} label={changing ? 'Enregistrer la date' : 'Reprendre le service'} />
  </form>;
}
