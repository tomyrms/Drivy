import { useState } from 'react';
import {
  alertKindLabel, chf, dunningDeliveryFailed, dunningDeliveryLabel, dunningStepLabel, exceptionKindLabel, exceptionStatusLabel, liftCauseLabel, reminderDaysLabel,
  suspensionCauseLabel, suspensionOriginLabel, wholeOf, type PlatformClientDetail, type PlatformDunningPolicy, type PlatformDunningView,
} from '../../platform-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldGroup, FieldLabel } from '../../components/ui/field';
import { PortalSelect } from '../components/portal-select';
import { by, civil, dateTime, dayPattern, Fact, Failure, Footer, ReasonField, reasonProblem, selectError, TextField } from './billing-parts';
import type { DunningDialog as DunningTarget, DunningPolicyInput } from './use-platform-dunning';
import type { PlatformConsoleState } from './use-platform-console';

type ReasonTarget = Extract<DunningTarget, { kind: 'revoke' | 'lift' | 'confirm' }>;
const present = <T,>(value: T | null | undefined): value is T => value !== null && value !== undefined;
/** Retire l'erreur d'un champ dès qu'il est corrigé. */
function cleared<K extends string>(errors: Partial<Record<K, string>>, key: K): Partial<Record<K, string>> {
  const next = { ...errors };
  delete next[key];
  return next;
}

// --- Onglet « Factures » : la politique de relance, globale ---
function policyText(policy: PlatformDunningPolicy) {
  return [
    ...(policy.remindersEnabled ? [`Rappels à ${reminderDaysLabel(policy.reminderDays)}`] : []),
    ...(policy.autoSuspend ? [`suspension après ${policy.suspensionMonths} mois, annoncée ${policy.warningDays} jours avant`] : ['suspension manuelle']),
    `fin d’essai signalée ${policy.trialAlertDays} jours avant`,
  ].join(' · ');
}

/** Créée désactivée : ni rappel, ni avertissement, ni suspension automatique avant qu'un opérateur l'active. */
export function DunningPolicyBlock({ state }: { state: PlatformConsoleState }) {
  const { dunning } = state, policy = dunning.policy;
  return <div className="platform-pending" role="group" aria-label="Relances des impayés">
    <div className="platform-summary">
      <strong>{policy?.remindersEnabled ? 'Relances actives' : 'Relances désactivées'}</strong>
      {policy && <span>{policyText(policy)}</span>}
    </div>
    <div className="platform-actions">
      <Button variant="outline" disabled={state.busy || !policy} onClick={() => dunning.start({ kind: 'policy' })}>Modifier les relances</Button>
      <Button variant="ghost" disabled={state.busy} onClick={() => dunning.start({ kind: 'run' })}>Lancer les relances du jour</Button>
    </div>
  </div>;
}

// --- Annuaire : les alertes de la console ---
/** Alertes commerciales (R01-T09) : les prendre en compte ne règle, ne suspend et ne lève rien. */
export function CommercialAlerts({ state }: { state: PlatformConsoleState }) {
  const { alerts } = state.dunning;
  if (alerts.length === 0) return null;
  return <div className="platform-group" role="group" aria-label="Alertes commerciales">
    <div className="platform-fiche-head"><h3 className="platform-subtitle">Alertes</h3></div>
    <ul className="platform-list">{alerts.map(item => <li key={item.id}>
      <div className="platform-summary"><strong>{item.clientName}</strong>
        <span>{[alertKindLabel(item.kind), item.invoiceNumber, item.onDate ? civil(item.onDate) : null].filter(present).join(' · ')}</span></div>
      <div className="platform-actions">
        <Button variant="ghost" disabled={state.busy} aria-label={`Ouvrir la fiche de ${item.clientName}`} onClick={() => void state.clients.openClient(item.clientId)}>Ouvrir</Button>
        <Button variant="ghost" disabled={state.busy} aria-label={`Marquer traitée : ${alertKindLabel(item.kind)}, ${item.clientName}`}
          onClick={() => void state.dunning.acknowledge(item.id)}>Traitée</Button>
      </div>
    </li>)}</ul>
  </div>;
}

// --- Fiche : le dossier de relance ---
/**
 * Dossier de relance de la fiche (R01-T09) : ce que la base a calculé, l'exception et les suspensions en cours, puis l'historique.
 * Suspendre ne change ni l'état de l'école, ni son cycle commercial, ni une facture émise.
 */
export function DunningPanel({ state, client }: { state: PlatformConsoleState; client: PlatformClientDetail }) {
  const { dunning } = state, data = dunning.dunning;
  if (!data) return null;
  const debt = data.state;
  const active = data.suspensions.filter(item => item.status === 'ACTIVE');
  const exception = data.exceptions.find(item => item.status === 'ACTIVE') ?? null;
  const unconfirmed = debt.warningStepId && dunningDeliveryFailed(debt.warningDelivery) ? debt.warningStepId : null;
  const empty = !debt.overdue && data.exceptions.length === 0 && data.suspensions.length === 0 && data.steps.length === 0;
  if (empty && !client.school) return null;
  const facts = debt.overdue || debt.nextReminderOn || debt.warningOn || debt.suspensionOn;
  return <div className="platform-group platform-rights-panel" role="group" aria-label={`Relances de ${client.displayName ?? client.school?.name ?? 'l’école'}`}>
    <div className="platform-fiche-head">
      <h4 className="platform-subtitle">Relances et suspension</h4>
      <div className="platform-actions">
        {!exception && <Button variant="outline" disabled={state.busy} onClick={() => dunning.start({ kind: 'exception' })}>Accorder une exception</Button>}
        {client.school && active.length < 2 && <Button variant="ghost" disabled={state.busy} onClick={() => dunning.start({ kind: 'suspend' })}>Suspendre l’école</Button>}
      </div>
    </div>
    {facts && <dl className="platform-facts">
      {debt.overdue && <Fact label="Plus ancienne dette">{[debt.invoiceNumber, debt.dueOn ? `échéance ${civil(debt.dueOn)}` : null,
        debt.balance !== null ? `reste ${chf(debt.balance)}` : null, `${debt.daysLate} j de retard`].filter(present).join(' · ')}</Fact>}
      {debt.nextReminderOn && <Fact label="Prochain rappel">{civil(debt.nextReminderOn)}</Fact>}
      {debt.warningOn && <Fact label="Avertissement">{[civil(debt.warningOn), debt.warningDelivery ? dunningDeliveryLabel(debt.warningDelivery).toLowerCase() : null]
        .filter(present).join(' · ')}</Fact>}
      {debt.suspensionOn && <Fact label="Suspension prévue">{civil(debt.suspensionOn)}</Fact>}
    </dl>}
    {unconfirmed && <Alert variant="destructive"><AlertTitle>Avertissement non remis</AlertTitle>
      <AlertDescription>Aucune suspension automatique avant une remise confirmée.</AlertDescription>
      <div className="mt-3"><Button variant="outline" disabled={state.busy} onClick={() => dunning.start({ kind: 'confirm', stepId: unconfirmed })}>Confirmer la remise</Button></div>
    </Alert>}
    {(active.length > 0 || exception) && <ul className="platform-list" aria-label="En cours">
      {active.map(item => <li key={item.id}>
        <div className="platform-summary"><strong>Suspendue · {suspensionCauseLabel(item.cause)}<Badge variant="destructive">En cours</Badge></strong>
          <span>{[`depuis le ${civil(item.startsOn)}`, suspensionOriginLabel(item.origin), item.invoiceNumber].filter(present).join(' · ')}{by(item.createdByName)}</span>
          {item.reason && <span>{item.reason}</span>}</div>
        <Button variant="ghost" disabled={state.busy} aria-label={`Lever la suspension : ${suspensionCauseLabel(item.cause)}`}
          onClick={() => dunning.start({ kind: 'lift', suspensionId: item.id })}>Lever</Button>
      </li>)}
      {exception && <li>
        <div className="platform-summary"><strong>{exceptionKindLabel(exception.kind)}{exception.suspensionMonths ? ` · ${exception.suspensionMonths} mois` : ''}</strong>
          <span>jusqu’au {civil(exception.endsOn)}{by(exception.createdByName)}</span>
          <span>{exception.reason}</span></div>
        <Button variant="ghost" disabled={state.busy} aria-label={`Révoquer l’exception : ${exceptionKindLabel(exception.kind)}`}
          onClick={() => dunning.start({ kind: 'revoke', exceptionId: exception.id })}>Révoquer</Button>
      </li>}
    </ul>}
    <DunningHistory data={data} />
  </div>;
}

function DunningHistory({ data }: { data: PlatformDunningView }) {
  const lifted = data.suspensions.filter(item => item.status === 'LIFTED'), closed = data.exceptions.filter(item => item.status !== 'ACTIVE');
  if (data.steps.length === 0 && lifted.length === 0 && closed.length === 0) return null;
  return <details className="platform-history">
    <summary>Historique des relances</summary>
    {data.steps.length > 0 && <ol className="platform-list" aria-label="Rappels et avertissements">{data.steps.map(step => <li key={step.id}>
      <div className="platform-summary">
        <strong>{dunningStepLabel(step.kind)} · {step.invoiceNumber}{dunningDeliveryFailed(step.delivery) && <Badge variant="destructive">{dunningDeliveryLabel(step.delivery)}</Badge>}</strong>
        <span>{[civil(step.doneOn), `J+${step.offsetDays}`, dunningDeliveryFailed(step.delivery) ? null : dunningDeliveryLabel(step.delivery).toLowerCase(),
          step.suspensionOn ? `suspension le ${civil(step.suspensionOn)}` : null].filter(present).join(' · ')}</span>
        {step.confirmedAt && <span>Remise confirmée le {dateTime(step.confirmedAt)}{by(step.confirmedByName)}{step.confirmReason ? ` : ${step.confirmReason}` : ''}</span>}
      </div></li>)}</ol>}
    {lifted.length > 0 && <ol className="platform-list" aria-label="Suspensions levées">{lifted.map(item => <li key={item.id}>
      <div className="platform-summary">
        <strong>{suspensionCauseLabel(item.cause)} · {civil(item.startsOn)}{item.liftedOn ? ` → ${civil(item.liftedOn)}` : ''}</strong>
        <span>{item.liftCause ? liftCauseLabel(item.liftCause) : 'Levée'}{by(item.liftedByName)}{item.liftReason ? ` : ${item.liftReason}` : ''}</span>
      </div></li>)}</ol>}
    {closed.length > 0 && <ol className="platform-list" aria-label="Exceptions closes">{closed.map(item => <li key={item.id}>
      <div className="platform-summary">
        <strong>{exceptionKindLabel(item.kind)}<Badge variant="outline">{exceptionStatusLabel(item.status)}</Badge></strong>
        <span>jusqu’au {civil(item.endsOn)}{by(item.createdByName)} : {item.reason}</span>
        {item.revokeReason && <span>Révoquée{item.revokedAt ? ` le ${dateTime(item.revokedAt)}` : ''} : {item.revokeReason}</span>}
      </div></li>)}</ol>}
  </details>;
}

// --- Boîtes de dialogue ---
export function DunningDialog({ state }: { state: PlatformConsoleState }) {
  const { dunning } = state, target = dunning.dialog, data = dunning.dunning;
  return <Dialog open={target !== null} onOpenChange={(open, details) => { if (state.busy) details.cancel(); else if (!open) dunning.stop(); }}>
    <DialogContent showCloseButton={!state.busy}>
      {target?.kind === 'policy' && dunning.policy && <PolicyBody state={state} policy={dunning.policy} />}
      {target?.kind === 'run' && <RunBody state={state} />}
      {data && target?.kind === 'exception' && <ExceptionBody state={state} data={data} />}
      {data && target?.kind === 'suspend' && <SuspendBody state={state} data={data} />}
      {data && (target?.kind === 'revoke' || target?.kind === 'lift' || target?.kind === 'confirm') && <ReasonBody state={state} data={data} target={target} />}
    </DialogContent>
  </Dialog>;
}

type PolicyField = 'days' | 'months' | 'warning' | 'trial';
/** Les jours de rappel sont triés et dédoublonnés ; l'API revalide chaque borne et la cohérence de l'ensemble. */
function policyInput(reminders: boolean, auto: boolean, days: string, months: string, warning: string, trial: string):
  { input: DunningPolicyInput } | { errors: Partial<Record<PolicyField, string>> } {
  const errors: Partial<Record<PolicyField, string>> = {};
  const parts = days.split(/[\s,;]+/).filter(part => part !== '').map(part => wholeOf(part, 1, 365));
  const reminderDays = [...new Set(parts.filter((value): value is number => typeof value === 'number'))].sort((a, b) => a - b);
  if (parts.length === 0 || parts.some(value => typeof value !== 'number') || reminderDays.length > 6) errors.days = 'De 1 à 6 jours de retard, entre 1 et 365, séparés par des virgules.';
  const suspensionMonths = wholeOf(months, 1, 12), warningDays = wholeOf(warning, 3, 28), trialAlertDays = wholeOf(trial, 1, 30);
  if (typeof suspensionMonths !== 'number') errors.months = 'Entre 1 et 12 mois.';
  if (typeof warningDays !== 'number') errors.warning = 'Entre 3 et 28 jours.';
  if (typeof trialAlertDays !== 'number') errors.trial = 'Entre 1 et 30 jours.';
  if (typeof suspensionMonths !== 'number' || typeof warningDays !== 'number' || typeof trialAlertDays !== 'number' || errors.days) return { errors };
  return { input: { remindersEnabled: reminders, autoSuspend: reminders && auto, reminderDays, suspensionMonths, warningDays, trialAlertDays } };
}

function PolicyBody({ state, policy }: { state: PlatformConsoleState; policy: PlatformDunningPolicy }) {
  const [reminders, setReminders] = useState(policy.remindersEnabled), [auto, setAuto] = useState(policy.autoSuspend);
  const [days, setDays] = useState(policy.reminderDays.join(', ')), [months, setMonths] = useState(String(policy.suspensionMonths));
  const [warning, setWarning] = useState(String(policy.warningDays)), [trial, setTrial] = useState(String(policy.trialAlertDays));
  const [errors, setErrors] = useState<Partial<Record<PolicyField, string>>>({});
  const edit = (field: PolicyField, set: (value: string) => void) => (value: string) => { set(value); setErrors(previous => cleared(previous, field)); };
  const submit = () => {
    const result = policyInput(reminders, auto, days, months, warning, trial);
    if ('errors' in result) { setErrors(result.errors); return; }
    void state.dunning.savePolicy(result.input);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Relances des impayés</DialogTitle><DialogDescription>Pour toutes les écoles.</DialogDescription></DialogHeader>
    <FieldGroup>
      <Field orientation="horizontal"><Checkbox id="dunning-reminders" checked={reminders} disabled={state.busy}
        onCheckedChange={value => { setReminders(value === true); if (value !== true) setAuto(false); }} />
        <FieldLabel htmlFor="dunning-reminders">Envoyer les rappels</FieldLabel></Field>
      <TextField id="dunning-days" label="Jours de retard des rappels" value={days} onChange={edit('days', setDays)} error={errors.days} disabled={state.busy || !reminders} />
      <Field orientation="horizontal"><Checkbox id="dunning-auto" checked={auto} disabled={state.busy || !reminders} onCheckedChange={value => setAuto(value === true)} />
        <FieldLabel htmlFor="dunning-auto">Suspendre automatiquement</FieldLabel></Field>
      <TextField id="dunning-months" label="Suspension après (mois)" inputMode="numeric" value={months} onChange={edit('months', setMonths)} error={errors.months} disabled={state.busy} />
      <TextField id="dunning-warning" label="Avertissement avant suspension (jours)" inputMode="numeric" value={warning} onChange={edit('warning', setWarning)} error={errors.warning}
        disabled={state.busy} />
      <TextField id="dunning-trial" label="Alerte avant fin d’essai (jours)" inputMode="numeric" value={trial} onChange={edit('trial', setTrial)} error={errors.trial} disabled={state.busy} />
    </FieldGroup>
    {auto && !policy.autoSuspend && <Alert><AlertTitle>Suspension automatique</AlertTitle>
      <AlertDescription>Chaque suspension suivra un avertissement remis à l’école.</AlertDescription></Alert>}
    <Failure state={state} title="Relances non enregistrées" />
    <Footer state={state} label="Enregistrer" onCancel={state.dunning.stop} />
  </form>;
}

/** Le même passage que le service planifié : un rappel, un avertissement ou une suspension déjà enregistrés ne se refont jamais. */
function RunBody({ state }: { state: PlatformConsoleState }) {
  const run = state.dunning.run;
  if (run) return <div className="platform-form">
    <DialogHeader><DialogTitle>Relances du jour</DialogTitle>
      <DialogDescription>{run.skipped ? 'Un autre passage est en cours.' : civil(run.today)}</DialogDescription></DialogHeader>
    {!run.skipped && <dl className="platform-facts">
      <Fact label="Écoles">{run.clients}</Fact><Fact label="Rappels">{run.reminders}</Fact><Fact label="Avertissements">{run.warnings}</Fact>
      <Fact label="Suspendues">{run.suspended}</Fact><Fact label="Rétablies">{run.lifted}</Fact><Fact label="Échecs">{run.failed}</Fact>
    </dl>}
    {!run.skipped && run.failed > 0 && <Alert variant="destructive"><AlertTitle>Échecs</AlertTitle>
      <AlertDescription>Des écoles n’ont pas été traitées. Un nouveau passage les reprend sans rien refaire.</AlertDescription></Alert>}
    <DialogFooter><Button onClick={state.dunning.stop}>Fermer</Button></DialogFooter>
  </div>;
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); void state.dunning.runDunning(); }}>
    <DialogHeader><DialogTitle>Lancer les relances du jour ?</DialogTitle>
      <DialogDescription>Le même passage que le service planifié.</DialogDescription></DialogHeader>
    <Failure state={state} title="Relances non lancées" />
    <Footer state={state} label="Lancer" busyLabel="Relances…" onCancel={state.dunning.stop} />
  </form>;
}

const exceptionOptions = [{ value: 'DELAY', label: 'Délai propre' }, { value: 'HOLD', label: 'Arrêt des relances' }];
function ExceptionBody({ state, data }: { state: PlatformConsoleState; data: PlatformDunningView }) {
  const [kind, setKind] = useState<'DELAY' | 'HOLD'>('DELAY'), [months, setMonths] = useState(''), [endsOn, setEndsOn] = useState('');
  const [reason, setReason] = useState(''), [errors, setErrors] = useState<Partial<Record<'months' | 'endsOn' | 'reason', string>>>({});
  const submit = () => {
    const next: Partial<Record<'months' | 'endsOn' | 'reason', string>> = {};
    const value = kind === 'DELAY' ? wholeOf(months, 1, 24) : null;
    if (kind === 'DELAY' && typeof value !== 'number') next.months = 'Entre 1 et 24 mois.';
    if (!dayPattern.test(endsOn) || endsOn < data.today) next.endsOn = 'Choisissez aujourd’hui ou une date à venir.';
    const problem = reasonProblem(reason);
    if (problem) next.reason = problem;
    setErrors(next);
    if (Object.keys(next).length > 0) return;
    void state.dunning.grantException(kind, typeof value === 'number' ? value : null, endsOn, reason);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Accorder une exception</DialogTitle>
      <DialogDescription>{kind === 'DELAY' ? 'Un autre délai avant suspension pour cette école.' : 'Ni rappel, ni avertissement, ni suspension automatique.'}</DialogDescription></DialogHeader>
    <FieldGroup>
      <PortalSelect id="dunning-exception-kind" label="Nature" options={exceptionOptions} value={kind} disabled={state.busy}
        onValueChange={value => setKind(value === 'HOLD' ? 'HOLD' : 'DELAY')} />
      {kind === 'DELAY' && <TextField id="dunning-exception-months" label="Délai avant suspension (mois)" inputMode="numeric" value={months}
        onChange={value => { setMonths(value); setErrors(previous => cleared(previous, 'months')); }} error={errors.months} disabled={state.busy} />}
      <TextField id="dunning-exception-ends" label="Jusqu’au" type="date" value={endsOn}
        onChange={value => { setEndsOn(value); setErrors(previous => cleared(previous, 'endsOn')); }} error={errors.endsOn} disabled={state.busy} />
      <ReasonField id="dunning-exception-reason" value={reason} error={errors.reason ?? null} disabled={state.busy}
        onChange={value => { setReason(value); setErrors(previous => cleared(previous, 'reason')); }} />
    </FieldGroup>
    <Failure state={state} title="Exception non accordée" />
    <Footer state={state} label="Accorder" onCancel={state.dunning.stop} />
  </form>;
}

/** Pour impayé, la base exige une dette arrivée à son délai et aucune exception d'arrêt ; une autre décision reste motivée. */
function SuspendBody({ state, data }: { state: PlatformConsoleState; data: PlatformDunningView }) {
  const debt = data.state;
  const taken = new Set(data.suspensions.filter(item => item.status === 'ACTIVE').map(item => item.cause));
  const paymentReady = debt.overdue && !debt.hold && debt.baseOn !== null && data.today >= debt.baseOn;
  const options = [
    ...(paymentReady && !taken.has('PAYMENT') ? [{ value: 'PAYMENT', label: 'Impayé' }] : []),
    ...(!taken.has('MANUAL') ? [{ value: 'MANUAL', label: 'Autre décision' }] : []),
  ];
  const [cause, setCause] = useState<string | null>(options[0]?.value ?? null);
  const [reason, setReason] = useState(''), [errors, setErrors] = useState<Partial<Record<'cause' | 'reason', string>>>({});
  const submit = () => {
    const next: Partial<Record<'cause' | 'reason', string>> = {};
    if (cause !== 'PAYMENT' && cause !== 'MANUAL') next.cause = 'Choisissez la cause.';
    const problem = reasonProblem(reason);
    if (problem) next.reason = problem;
    setErrors(next);
    if (Object.keys(next).length > 0 || (cause !== 'PAYMENT' && cause !== 'MANUAL')) return;
    void state.dunning.suspend(cause, reason);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Suspendre l’école ?</DialogTitle>
      <DialogDescription>L’école garde la lecture et les finalisations ; rien de nouveau ne s’ouvre.</DialogDescription></DialogHeader>
    <FieldGroup>
      <PortalSelect id="dunning-suspension-cause" label="Cause" options={options} value={cause} disabled={state.busy || options.length === 0}
        onValueChange={value => { setCause(value); setErrors(previous => cleared(previous, 'cause')); }} {...selectError(errors.cause)} />
      <ReasonField id="dunning-suspension-reason" value={reason} error={errors.reason ?? null} disabled={state.busy}
        onChange={value => { setReason(value); setErrors(previous => cleared(previous, 'reason')); }} />
    </FieldGroup>
    <Failure state={state} title="École non suspendue" />
    <Footer state={state} label="Suspendre" destructive disabled={options.length === 0} onCancel={state.dunning.stop} />
  </form>;
}

function ReasonBody({ state, data, target }: { state: PlatformConsoleState; data: PlatformDunningView; target: ReasonTarget }) {
  const [reason, setReason] = useState(''), [invalid, setInvalid] = useState<string | null>(null);
  const exception = target.kind === 'revoke' ? data.exceptions.find(item => item.id === target.exceptionId && item.status === 'ACTIVE') ?? null : null;
  const suspension = target.kind === 'lift' ? data.suspensions.find(item => item.id === target.suspensionId && item.status === 'ACTIVE') ?? null : null;
  const step = target.kind === 'confirm' ? data.steps.find(item => item.id === target.stepId) ?? null : null;
  if (!exception && !suspension && !step) return <DialogHeader><DialogTitle>Élément introuvable</DialogTitle>
    <DialogDescription>L’écran a été actualisé.</DialogDescription></DialogHeader>;
  const titles = { revoke: 'Révoquer l’exception ?', lift: 'Lever la suspension ?', confirm: 'Confirmer la remise de l’avertissement ?' } as const;
  const failures = { revoke: 'Exception non révoquée', lift: 'Suspension non levée', confirm: 'Remise non confirmée' } as const;
  const labels = { revoke: 'Révoquer', lift: 'Lever', confirm: 'Confirmer' } as const;
  const description = exception ? `${exceptionKindLabel(exception.kind)} · jusqu’au ${civil(exception.endsOn)}`
    : suspension ? `${suspensionCauseLabel(suspension.cause)} · depuis le ${civil(suspension.startsOn)}`
      : `${step!.invoiceNumber} · ${civil(step!.doneOn)}`;
  const submit = () => {
    const problem = reasonProblem(reason);
    if (problem) { setInvalid(problem); return; }
    if (target.kind === 'revoke') void state.dunning.revokeException(target.exceptionId, reason);
    else if (target.kind === 'lift') void state.dunning.lift(target.suspensionId, reason);
    else void state.dunning.confirmWarning(target.stepId, reason);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>{titles[target.kind]}</DialogTitle><DialogDescription>{description}</DialogDescription></DialogHeader>
    <FieldGroup>
      <ReasonField id="dunning-reason" value={reason} error={invalid} disabled={state.busy} label={target.kind === 'confirm' ? 'Canal et preuve de la remise' : 'Motif'}
        onChange={value => { setReason(value); setInvalid(null); }} />
    </FieldGroup>
    <Failure state={state} title={failures[target.kind]} />
    <Footer state={state} label={labels[target.kind]} cancel="Retour" onCancel={state.dunning.stop} />
  </form>;
}
