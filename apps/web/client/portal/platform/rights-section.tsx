import { useState } from 'react';
import {
  adjustmentEffectLabel, adjustmentPhaseLabel, assignmentPhaseLabel, commercialStateLabel, consequenceLabel, effectiveInstant, existingUsageLabel,
  moduleLabel, reasonLimit, reasonProblem,
  type PlatformEntitlements, type PlatformClientDetail,
} from '../../platform-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import { PortalSelect } from '../components/portal-select';
import type { PlatformConsoleState } from './use-platform-console';

const dateTime = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
const day = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium' }).format(new Date(value));
const by = (name: string | null) => (name ? ` · par ${name}` : '');

/**
 * Droits de l'école aux modules : l'offre en vigueur, l'offre programmée, chaque module et son ajustement, l'historique.
 * L'écran n'est qu'une lecture : chaque commande est relue et décidée par l'API, sous la version des droits affichée.
 */
export function RightsPanel({ state, client }: { state: PlatformConsoleState; client: PlatformClientDetail }) {
  const { rights } = state, data = rights.rights;
  if (!data) return null;
  const scheduled = data.assignments.find(item => item.phase === 'SCHEDULED') ?? null;
  const configured = data.state !== 'NOT_CONFIGURED';
  return <div className="platform-group platform-rights-panel" role="group" aria-label={`Offre et modules de ${client.displayName ?? client.school?.name ?? 'l’école'}`}>
    <div className="platform-fiche-head">
      <h4 className="platform-subtitle">Offre et modules</h4>
      <div className="platform-actions"><Button variant="outline" disabled={state.busy} onClick={rights.startAssign}>Attribuer une offre</Button></div>
    </div>
    <div className="platform-summary">
      <strong>{data.offer ? data.offer.name : commercialStateLabel(data.state)}</strong>
      {data.offer && <span>En vigueur depuis le {day(data.offer.effectiveAt)}</span>}
    </div>
    {scheduled && data.scheduledOffer && <div className="platform-pending" role="group" aria-label="Offre programmée">
      <div className="platform-summary"><strong>{data.scheduledOffer.name}</strong><span>Prévue le {dateTime(data.scheduledOffer.effectiveAt)}</span></div>
      <Button variant="ghost" disabled={state.busy} aria-label={`Annuler l’attribution prévue de ${data.scheduledOffer.name}`} onClick={() => rights.startCancel(scheduled.id)}>Annuler</Button>
    </div>}
    <ul className="platform-list" aria-label="Modules">{data.modules.map(module => <li key={module.code}>
      <div className="platform-summary"><strong>{moduleLabel(module.code)}{module.adjustment && <Badge variant="outline">{adjustmentEffectLabel(module.adjustment.effect)}</Badge>}</strong>
        <span>{module.entitled ? 'Accordé' : 'Non accordé'}</span>
        {module.adjustment && <span>{module.adjustment.reason}</span>}</div>
      {configured && (module.adjustment
        ? <Button variant="ghost" disabled={state.busy} aria-label={`Lever l’ajustement de ${moduleLabel(module.code)}`} onClick={() => rights.startLift(module.adjustment!.id)}>Lever</Button>
        : <Button variant="ghost" disabled={state.busy} aria-label={`${module.entitled ? 'Retirer' : 'Accorder'} ${moduleLabel(module.code)}`}
          onClick={() => rights.startAdjust(module.code, module.entitled ? 'REVOKE' : 'GRANT')}>{module.entitled ? 'Retirer' : 'Accorder'}</Button>)}
    </li>)}</ul>
    <History data={data} />
  </div>;
}

function History({ data }: { data: PlatformEntitlements }) {
  if (data.assignments.length === 0 && data.adjustments.length === 0) return null;
  return <details className="platform-history">
    <summary>Historique</summary>
    {data.assignments.length > 0 && <ol className="platform-list" aria-label="Attributions">{data.assignments.map(item => <li key={item.id}>
      <div className="platform-summary"><strong>{item.offerName}</strong>
        <span>{assignmentPhaseLabel(item.phase)} · {dateTime(item.effectiveAt)}{by(item.createdByName)}</span></div></li>)}</ol>}
    {data.adjustments.length > 0 && <ol className="platform-list" aria-label="Ajustements">{data.adjustments.map(item => <li key={item.id}>
      <div className="platform-summary"><strong>{moduleLabel(item.moduleCode)} · {adjustmentEffectLabel(item.effect)}</strong>
        <span>{adjustmentPhaseLabel(item.phase)} · {dateTime(item.createdAt)}{by(item.createdByName)}</span>
        <span>{item.reason}</span>
        {item.phase === 'LIFTED' && <span>Levé{item.liftedAt ? ` le ${day(item.liftedAt)}` : ''}{by(item.liftedByName)}{item.liftReason ? ` : ${item.liftReason}` : ''}</span>}</div></li>)}</ol>}
  </details>;
}

/** Les commandes sur les droits partent d'ici : attribuer (avec aperçu), ajuster, lever, annuler une attribution programmée. */
export function RightsDialog({ state }: { state: PlatformConsoleState }) {
  const { rights } = state, target = rights.dialog;
  return <Dialog open={target !== null} onOpenChange={(open, details) => { if (state.busy) details.cancel(); else if (!open) rights.stop(); }}>
    <DialogContent showCloseButton={!state.busy}>
      {target?.kind === 'assign' && <AssignBody state={state} />}
      {(target?.kind === 'adjust' || target?.kind === 'lift') && <ReasonBody state={state} target={target} />}
      {target?.kind === 'cancel' && <CancelBody state={state} assignmentId={target.assignmentId} />}
    </DialogContent>
  </Dialog>;
}

function AssignBody({ state }: { state: PlatformConsoleState }) {
  const { rights, offers } = state;
  const [offerId, setOfferId] = useState<string | null>(null), [local, setLocal] = useState(''), [invalid, setInvalid] = useState<string | null>(null);
  const options = offers.offers.filter(offer => offer.status === 'ACTIVE').map(offer => ({ value: offer.id, label: offer.name }));
  const instant = effectiveInstant(local);
  const current = rights.rights;
  // Un aperçu ne vaut que pour l'offre, la date et la version des droits qui l'ont produit : sinon il faut le relire.
  const shown = rights.preview && rights.preview.choice.offerId === offerId && rights.preview.choice.effectiveAt === (instant ?? null) && current && rights.preview.data.version === current.version
    ? rights.preview.data : null;
  const submit = () => {
    if (!offerId) { setInvalid('Choisissez une offre.'); return; }
    if (instant === undefined) { setInvalid('Choisissez une date à venir, ou laissez vide pour une attribution immédiate.'); return; }
    setInvalid(null);
    if (shown) void rights.assign({ offerId, effectiveAt: instant });
    else void rights.showPreview({ offerId, effectiveAt: instant });
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Attribuer une offre</DialogTitle></DialogHeader>
    <FieldGroup>
      <PortalSelect id="assign-offer" label="Offre" options={options} value={offerId} disabled={state.busy} onValueChange={value => { setOfferId(value); setInvalid(null); }} />
      <Field data-invalid={!!invalid}>
        <FieldLabel htmlFor="assign-date">Date d’effet (facultative)</FieldLabel>
        <Input id="assign-date" name="effectiveAt" type="datetime-local" value={local} disabled={state.busy} aria-invalid={!!invalid}
          aria-describedby={invalid ? 'assign-date-error' : undefined} onChange={event => { setLocal(event.target.value); setInvalid(null); }} />
        {invalid && <FieldError id="assign-date-error">{invalid}</FieldError>}
      </Field>
    </FieldGroup>
    {shown && <Consequences preview={shown} />}
    {state.error && <Alert variant="destructive"><AlertTitle>Offre non attribuée</AlertTitle><AlertDescription>{state.error}</AlertDescription></Alert>}
    <DialogFooter><Button type="button" variant="outline" disabled={state.busy} onClick={rights.stop}>Annuler</Button>
      <Button type="submit" disabled={state.busy} aria-busy={state.busy}>{state.busy ? 'Un instant…' : shown ? 'Attribuer l’offre' : 'Voir les conséquences'}</Button></DialogFooter>
  </form>;
}

/** Ce que l'attribution change, calculé par le serveur avant toute écriture : modules gagnés ou perdus, volumes qui restent en place. */
function Consequences({ preview }: { preview: NonNullable<PlatformConsoleState['rights']['preview']>['data'] }) {
  return <div className="platform-consequences" role="group" aria-label="Conséquences">
    <div className="platform-summary"><strong>{preview.offer.name}</strong>
      <span>{preview.immediate || !preview.effectiveAt ? 'Immédiatement' : `À partir du ${dateTime(preview.effectiveAt)}`}</span></div>
    <ul className="platform-list" aria-label="Modules">{preview.modules.map(module => {
      const usage = module.kind === 'LOSES' ? existingUsageLabel(module.existing) : '';
      return <li key={module.code}>
        <div className="platform-summary"><strong>{moduleLabel(module.code)}</strong>{usage && <span>Existant : {usage}</span>}</div>
        <Badge variant={module.kind === 'LOSES' ? 'destructive' : 'outline'}>{consequenceLabel(module.kind)}</Badge>
      </li>;
    })}</ul>
    {preview.endingAdjustments.length > 0 && <p>Ajustements qui prennent fin : {preview.endingAdjustments.map(item => `${moduleLabel(item.moduleCode)} (${adjustmentEffectLabel(item.effect).toLowerCase()})`).join(', ')}.</p>}
    {preview.replacesScheduled && <p>Remplace l’attribution prévue : {preview.replacesScheduled.name}, le {dateTime(preview.replacesScheduled.effectiveAt)}.</p>}
  </div>;
}

function ReasonBody({ state, target }: { state: PlatformConsoleState; target: { kind: 'adjust'; moduleCode: string; effect: 'GRANT' | 'REVOKE' } | { kind: 'lift'; adjustmentId: string } }) {
  const { rights } = state;
  const [reason, setReason] = useState(''), [invalid, setInvalid] = useState<string | null>(null);
  const adjusting = target.kind === 'adjust';
  const title = adjusting ? `${target.effect === 'REVOKE' ? 'Retirer' : 'Accorder'} ${moduleLabel(target.moduleCode)}` : 'Lever l’ajustement';
  const submit = () => {
    const problem = reasonProblem(reason);
    if (problem) { setInvalid(problem); return; }
    setInvalid(null);
    if (target.kind === 'adjust') void rights.adjust(target.moduleCode, target.effect, reason);
    else void rights.lift(target.adjustmentId, reason);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>{title}</DialogTitle></DialogHeader>
    <FieldGroup>
      <Field data-invalid={!!invalid}>
        <FieldLabel htmlFor="rights-reason">Motif</FieldLabel>
        <Textarea id="rights-reason" name="reason" rows={3} maxLength={reasonLimit.max} required value={reason} disabled={state.busy} aria-invalid={!!invalid}
          aria-describedby={invalid ? 'rights-reason-error' : undefined} onChange={event => { setReason(event.target.value); setInvalid(null); }} />
        {invalid && <FieldError id="rights-reason-error">{invalid}</FieldError>}
      </Field>
    </FieldGroup>
    {state.error && <Alert variant="destructive"><AlertTitle>{adjusting ? 'Module non ajusté' : 'Ajustement non levé'}</AlertTitle><AlertDescription>{state.error}</AlertDescription></Alert>}
    <DialogFooter><Button type="button" variant="outline" disabled={state.busy} onClick={rights.stop}>Annuler</Button>
      <Button type="submit" disabled={state.busy} aria-busy={state.busy}>{state.busy ? 'Enregistrement…' : adjusting ? 'Enregistrer l’ajustement' : 'Lever'}</Button></DialogFooter>
  </form>;
}

function CancelBody({ state, assignmentId }: { state: PlatformConsoleState; assignmentId: string }) {
  const { rights } = state;
  const item = rights.rights?.assignments.find(entry => entry.id === assignmentId) ?? null;
  return <>
    <DialogHeader><DialogTitle>Annuler l’attribution prévue ?</DialogTitle>
      {item && <DialogDescription>{item.offerName} · {dateTime(item.effectiveAt)}</DialogDescription>}</DialogHeader>
    {state.error && <Alert variant="destructive"><AlertTitle>Attribution non annulée</AlertTitle><AlertDescription>{state.error}</AlertDescription></Alert>}
    <DialogFooter><Button variant="outline" disabled={state.busy} onClick={rights.stop}>Garder</Button>
      <Button variant="destructive" disabled={state.busy} onClick={() => void rights.cancelAssignment(assignmentId)}>{state.busy ? 'Annulation…' : 'Annuler l’attribution'}</Button></DialogFooter>
  </>;
}
