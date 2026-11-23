import { useId, useRef, useState, type ReactNode } from 'react';
import { Check, CircleAlert, Download, Mail, Minus } from 'lucide-react';
import { commandMessage, createCommand } from '../../command-core';
import { kindsOf } from '../../command-families';
import { useCommandRevision } from '../../command-store';
import { RequestFailure } from '../../protocol';
import { readSchool } from '../../school-api';
import {
  availableActions, chfAmount, civilLabel, instantDayLabel, invoiceFileName, invoiceKindLabels, lifecycleLabels, moduleName, noticeLabels, paymentMethodLabels,
  requestableModules, requestBodyOf, requestIsOpen, requestKindLabels, requestStatusLabel, requestSteps, schoolSubscriptionSchema, settlementLabel, subscriptionAttention,
  type RequestProblem, type SchoolSubscription, type SubscriptionInvoice, type SubscriptionRequest, type SubscriptionRequestKind,
} from '../../subscription-model';
import { useCommandRunner, useConsole, useLoad } from '../../console/context';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Empty, EmptyHeader, EmptyTitle } from '../../components/ui/empty';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import { CommandFeedback, ReadFeedback } from '../components/feedback';
import { PortalSelect } from '../components/portal-select';
import './subscription.css';

type Runner = ReturnType<typeof useCommandRunner>;
const subscriptionKinds = kindsOf('subscription');

/** Rubrique commerciale du responsable : lisible sur une école suspendue, résiliée ou archivée, sans jamais rouvrir un droit. */
export function SubscriptionPage() {
  const { schoolId } = useConsole();
  const revision = useCommandRevision(subscriptionKinds);
  const loaded = useLoad(() => readSchool(schoolId, 'subscription', schoolSubscriptionSchema), [schoolId, revision]);
  const data = loaded.data;
  return <section className="subscription-page" aria-labelledby="subscription-title">
    <header className="subscription-head">
      <h1 id="subscription-title">Abonnement</h1>
      {data?.hasClient && <Badge variant={data.restriction ? 'destructive' : 'outline'}>{data.restriction?.reason === 'SUSPENDED' ? 'Suspendu' : lifecycleLabels[data.lifecycle]}</Badge>}
    </header>
    {!data && <ReadFeedback loaded={loaded} label="Chargement de l’abonnement" />}
    {data && loaded.status === 'error' && <ReadFeedback loaded={loaded} />}
    {data && <SubscriptionBody data={data} reload={loaded.reload} />}
  </section>;
}

type RequestTarget = { kind: SubscriptionRequestKind };

function SubscriptionBody({ data, reload }: { data: SchoolSubscription; reload: () => void }) {
  const { schoolId } = useConsole();
  const runner = useCommandRunner(reload);
  const [target, setTarget] = useState<RequestTarget | null>(null);
  const [withdrawing, setWithdrawing] = useState<SubscriptionRequest | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const actions = availableActions(data), attention = subscriptionAttention(data);
  const disabled = runner.busy || runner.blockedReason !== null;

  function openRequest(kind: SubscriptionRequestKind) { setNotice(null); runner.clearOutcome(); setTarget({ kind }); }

  /** Un refus précis laisse la demande en place : la page relit l'état au lieu de deviner. */
  function refused(code: string) {
    if (code === 'VERSION_CONFLICT' || code === 'PRECONDITION_REQUIRED' || code === 'REQUEST_ALREADY_OPEN' || code === 'REQUEST_CLOSED') {
      runner.clearOutcome();
      setNotice(code === 'REQUEST_ALREADY_OPEN' ? commandMessage(code) : 'Cette demande a changé. Voici son état actuel.');
      reload();
    }
  }
  async function withdraw(item: SubscriptionRequest) {
    setNotice(null);
    const command = createCommand({ schoolId, kind: 'withdrawSubscriptionRequest', path: `subscription/requests/${item.id}/withdraw`, ifMatch: item.version,
      resourceId: item.id, resourceVersion: item.version, body: {} });
    const result = await runner.run(command, 'La demande est retirée.');
    setWithdrawing(null);
    if (result.status === 'rejected') refused(result.code);
  }
  async function acknowledge() {
    setNotice(null);
    const result = await runner.run(createCommand({ schoolId, kind: 'acknowledgeSubscriptionNotices', path: 'subscription/notices/read', resourceVersion: 0, body: {} }), 'Réponses marquées comme lues.');
    if (result.status === 'rejected') refused(result.code);
  }

  if (!data.hasClient) return <>
    <Empty className="subscription-empty"><EmptyHeader><EmptyTitle>Aucun abonnement</EmptyTitle></EmptyHeader></Empty>
    <ContactBlock data={data} />
  </>;

  return <>
    {!target && <CommandFeedback runner={runner} showSuccess={false} />}
    {runner.outcome?.tone === 'success' && <Alert><AlertTitle>{runner.outcome.message}</AlertTitle></Alert>}
    {notice && <Alert><AlertTitle>État actualisé</AlertTitle><AlertDescription>{notice}</AlertDescription></Alert>}
    {attention && <Alert variant={attention.tone === 'danger' ? 'destructive' : 'default'}>
      <CircleAlert aria-hidden="true" />
      <AlertTitle>{attention.title}</AlertTitle><AlertDescription>{attention.detail}</AlertDescription>
      {attention.regularize && actions.regularization && <div className="subscription-alert-action">
        <Button variant="outline" disabled={disabled} onClick={() => openRequest('REGULARIZATION')}>Demander une régularisation</Button>
      </div>}
    </Alert>}
    {data.notices.length > 0 && <div className="subscription-notices" role="group" aria-label="Réponses de Drivy">
      <ul>{data.notices.slice(0, 3).map(item => {
        // Un avis de relance ou de suspension n'a pas de demande d'origine : seule sa date est montrée.
        const request = item.requestId ? data.requests.find(entry => entry.id === item.requestId) : undefined;
        return <li key={item.id}><strong>{noticeLabels[item.event]}</strong><span>{item.requestId ? `${request ? requestKindLabels[request.kind] : 'Demande'} · ` : ''}{instantDayLabel(item.createdAt)}</span></li>;
      })}</ul>
      <Button variant="outline" disabled={disabled} onClick={() => void acknowledge()}>Marquer comme lu</Button>
    </div>}
    <Statement data={data} />
    <div className="subscription-columns">
      <div className="subscription-main">
        <Invoices data={data} />
        <Payments data={data} />
      </div>
      <div className="subscription-side">
        <OfferBlock data={data} />
        <Requests data={data} disabled={disabled} actions={actions} onRequest={openRequest}
          onWithdraw={item => { runner.clearOutcome(); setWithdrawing(item); }} />
        <ContactBlock data={data} />
      </div>
    </div>
    <RequestDialog key={target?.kind ?? 'closed'} data={data} target={target} runner={runner} onClose={() => setTarget(null)} onRefused={refused} />
    <Dialog open={withdrawing !== null} onOpenChange={(open, details) => { if (runner.busy) details.cancel(); else if (!open) setWithdrawing(null); }}>
      <DialogContent showCloseButton={!runner.busy}>
        <DialogHeader><DialogTitle>Retirer cette demande ?</DialogTitle>
          {withdrawing && <DialogDescription>{requestKindLabels[withdrawing.kind]} du {civilLabel(withdrawing.requestedOn)}</DialogDescription>}</DialogHeader>
        <DialogFooter>
          <Button variant="outline" disabled={runner.busy} onClick={() => setWithdrawing(null)}>Garder</Button>
          <Button variant="destructive" disabled={disabled || !withdrawing} aria-busy={runner.busy} onClick={() => { if (withdrawing) void withdraw(withdrawing); }}>{runner.busy ? 'Retrait…' : 'Retirer'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </>;
}

function Fact({ label, children, tone }: { label: string; children: ReactNode; tone?: 'danger' }) {
  return <div data-tone={tone}><dt>{label}</dt><dd>{children}</dd></div>;
}

/** Relevé : l'initial et la mensualité restent séparés, le solde ne vient que des factures et écritures confirmées. */
function Statement({ data }: { data: SchoolSubscription }) {
  const terms = data.terms, debt = data.debt;
  const initial = terms && terms.initialAmount !== null ? terms.initialAmount - terms.initialDiscount : null;
  const monthly = terms && terms.monthlyAmount !== null ? terms.monthlyAmount - terms.recurringDiscount : null;
  return <dl className="subscription-statement" aria-label="Relevé de l’abonnement">
    <Fact label="Offre">{data.offer?.name ?? '—'}</Fact>
    {data.trial && <Fact label="Fin de l’essai">{instantDayLabel(data.trial.endsAt)}</Fact>}
    <Fact label="Montant initial">{chfAmount(initial)}{terms && terms.initialDiscount > 0 && <small>remise {chfAmount(terms.initialDiscount)}</small>}</Fact>
    <Fact label="Mensualité">{chfAmount(monthly)}{terms && terms.recurringDiscount > 0 && <small>remise {chfAmount(terms.recurringDiscount)}{terms.recurringDiscountMonths ? ` · ${terms.recurringDiscountMonths} mois` : ''}</small>}</Fact>
    <Fact label="Prochaine période">{data.nextPeriodStart ? civilLabel(data.nextPeriodStart) : '—'}</Fact>
    <Fact label="Prochaine échéance">{data.nextDueOn ? civilLabel(data.nextDueOn) : '—'}</Fact>
    <Fact label="Solde dû">{debt ? chfAmount(debt.outstanding) : '—'}</Fact>
    {debt && debt.overdueAmount > 0 && <Fact label="En retard" tone="danger">{chfAmount(debt.overdueAmount)}</Fact>}
    {debt && debt.unallocated > 0 && <Fact label="Reçu non affecté">{chfAmount(debt.unallocated)}</Fact>}
  </dl>;
}

function Block({ title, children, action }: { title: string; children: ReactNode; action?: ReactNode }) {
  const id = useId();
  return <section className="subscription-block" aria-labelledby={id}><div className="subscription-block-head"><h2 id={id}>{title}</h2>{action}</div>{children}</section>;
}

/** Le fichier passe par la session : aucune adresse réutilisable, et une réponse en erreur ne produit aucun fichier. */
async function downloadInvoice(schoolId: string, invoice: SubscriptionInvoice) {
  let response: Response, blob: Blob;
  try {
    response = await fetch(new URL(`/app/bff/schools/${schoolId}/subscription/invoices/${invoice.id}/document`, window.location.origin), {
      credentials: 'same-origin', cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer', signal: AbortSignal.timeout(25_000),
      headers: { Accept: 'application/pdf, application/problem+json' },
    });
    if (!response.ok) {
      const problem = await response.json().catch(() => null) as { code?: unknown } | null;
      throw new RequestFailure(typeof problem?.code === 'string' ? problem.code : 'REQUEST_FAILED', response.status);
    }
    if (response.headers.get('content-type')?.split(';')[0]?.trim() !== 'application/pdf') throw new RequestFailure('INVALID_RESPONSE', response.status);
    blob = await response.blob();
  } catch (reason) {
    if (reason instanceof RequestFailure) throw reason;
    throw new RequestFailure('NETWORK_UNAVAILABLE');
  }
  const link = document.createElement('a'), url = URL.createObjectURL(blob);
  link.href = url; link.download = invoiceFileName(invoice); link.rel = 'noopener'; link.hidden = true;
  document.body.append(link); link.click(); link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
const downloadProblem = (reason: unknown) => {
  if (!(reason instanceof RequestFailure)) return 'Le document n’a pas pu être téléchargé. Réessayez.';
  if (reason.code === 'DOCUMENT_UNAVAILABLE') return 'Ce document n’est pas encore disponible.';
  if (reason.status === 404) return 'Ce document n’est pas disponible avec vos accès.';
  if (reason.status === 401) return 'Votre connexion a expiré. Reconnectez-vous puis réessayez.';
  return 'Le document n’a pas pu être téléchargé. Réessayez.';
};

function Invoices({ data }: { data: SchoolSubscription }) {
  const { schoolId } = useConsole();
  const [busy, setBusy] = useState<string | null>(null), [problems, setProblems] = useState<Readonly<Record<string, string>>>({});
  const running = useRef(false);
  async function download(invoice: SubscriptionInvoice) {
    if (running.current) return;
    running.current = true; setBusy(invoice.id);
    setProblems(({ [invoice.id]: _cleared, ...rest }) => rest);
    try { await downloadInvoice(schoolId, invoice); }
    catch (reason) { setProblems(previous => ({ ...previous, [invoice.id]: downloadProblem(reason) })); }
    finally { running.current = false; setBusy(null); }
  }
  return <Block title="Factures">
    {data.invoices.length === 0 ? <p className="subscription-none">Aucune facture</p> : <ul className="subscription-invoices">{data.invoices.map(invoice => {
      const status = settlementLabel(invoice), settlement = invoice.settlement, problem = problems[invoice.id];
      return <li key={invoice.id}>
        <div className="subscription-invoice-row">
          <div className="subscription-invoice-title">
            <strong>{invoiceKindLabels[invoice.kind]}</strong>
            <span>{invoice.number}{invoice.periodStart && invoice.periodEnd ? ` · ${civilLabel(invoice.periodStart)} → ${civilLabel(invoice.periodEnd)}` : ''}</span>
          </div>
          <div className="subscription-invoice-amount">
            <strong>{chfAmount(invoice.total)}</strong>
            <Badge variant={status.tone === 'danger' ? 'destructive' : 'outline'}>{status.label}</Badge>
          </div>
          <Button variant="ghost" size="icon" disabled={!invoice.hasDocument || busy !== null} aria-busy={busy === invoice.id}
            aria-label={invoice.hasDocument ? `Télécharger ${invoiceFileName(invoice)}` : `Document de ${invoice.number} indisponible`} onClick={() => void download(invoice)}><Download aria-hidden="true" /></Button>
        </div>
        {problem && <p className="subscription-error" role="alert">{problem}</p>}
        <details>
          <summary>Détail</summary>
          <dl className="subscription-details">
            <Fact label="Émise le">{civilLabel(invoice.issuedOn)}</Fact>
            {invoice.dueOn && <Fact label="Échéance">{civilLabel(invoice.dueOn)}</Fact>}
            <Fact label="Dont TVA">{chfAmount(invoice.taxAmount)}</Fact>
            {invoice.creditsInvoiceNumber && <Fact label="Corrige">{invoice.creditsInvoiceNumber}</Fact>}
            {settlement && <Fact label="Réglé">{chfAmount(settlement.allocated)}</Fact>}
            {settlement && settlement.credited > 0 && <Fact label="Crédité">{chfAmount(settlement.credited)}</Fact>}
            {settlement && <Fact label="Solde">{chfAmount(settlement.balance)}</Fact>}
          </dl>
        </details>
      </li>;
    })}</ul>}
  </Block>;
}

function Payments({ data }: { data: SchoolSubscription }) {
  return <Block title="Règlements">
    {data.payments.length === 0 ? <p className="subscription-none">Aucun règlement</p> : <ul className="subscription-lines">{data.payments.map(item => <li key={item.id}>
      <span>{civilLabel(item.receivedOn)} · {paymentMethodLabels[item.method]}</span><strong>{chfAmount(item.amount)}</strong>
    </li>)}</ul>}
  </Block>;
}

function OfferBlock({ data }: { data: SchoolSubscription }) {
  return <Block title="Offre et modules">
    {data.modules.length > 0 && <ul className="subscription-modules">{data.modules.map(item => <li key={item.code} data-on={item.entitled}>
      {item.entitled ? <Check aria-hidden="true" /> : <Minus aria-hidden="true" />}<span>{moduleName(item.code)}</span>
      <span className="sr-only">{item.entitled ? 'inclus' : 'non inclus'}</span>
    </li>)}</ul>}
    {data.scheduledOffer && <p className="subscription-future">{data.scheduledOffer.name} dès le {instantDayLabel(data.scheduledOffer.effectiveAt)}</p>}
    {data.scheduledTerms && <p className="subscription-future">Nouvelles conditions dès le {civilLabel(data.scheduledTerms.effectiveFrom)}</p>}
  </Block>;
}

function Requests({ data, disabled, actions, onRequest, onWithdraw }: {
  data: SchoolSubscription; disabled: boolean; actions: ReturnType<typeof availableActions>; onRequest: (kind: SubscriptionRequestKind) => void; onWithdraw: (item: SubscriptionRequest) => void;
}) {
  const open = data.requests.filter(requestIsOpen), closed = data.requests.filter(item => !requestIsOpen(item));
  return <Block title="Demandes">
    {(actions.offerChange || actions.termination || actions.regularization) && <div className="subscription-actions">
      {actions.offerChange && <Button variant="outline" disabled={disabled} onClick={() => onRequest('OFFER_CHANGE')}>Changer d’offre</Button>}
      {actions.regularization && <Button variant="outline" disabled={disabled} onClick={() => onRequest('REGULARIZATION')}>Régularisation</Button>}
      {actions.termination && <Button variant="ghost" disabled={disabled} onClick={() => onRequest('TERMINATION')}>Résilier</Button>}
    </div>}
    {open.length > 0 && <ul className="subscription-requests">{open.map(item => <RequestItem key={item.id} item={item} today={data.today} disabled={disabled} onWithdraw={onWithdraw} />)}</ul>}
    {closed.length > 0 && <details className="subscription-history"><summary>Historique</summary>
      <ul className="subscription-requests">{closed.map(item => <RequestItem key={item.id} item={item} today={data.today} disabled={disabled} onWithdraw={onWithdraw} />)}</ul>
    </details>}
    {data.requests.length === 0 && <p className="subscription-none">Aucune demande</p>}
  </Block>;
}

function RequestItem({ item, today, disabled, onWithdraw }: { item: SubscriptionRequest; today: string; disabled: boolean; onWithdraw: (item: SubscriptionRequest) => void }) {
  const wanted = [item.requestedOfferName, ...item.requestedModules.map(moduleName)].filter(Boolean).join(', ');
  return <li>
    <div className="subscription-request-head"><strong>{requestKindLabels[item.kind]}</strong><Badge variant={item.status === 'REFUSED' ? 'destructive' : 'outline'}>{requestStatusLabel(item)}</Badge></div>
    {wanted && <p>{wanted}</p>}
    {item.desiredOn && <p>Souhaitée le {civilLabel(item.desiredOn)}</p>}
    {item.details && <p className="subscription-quote">{item.details}</p>}
    <ol className="subscription-steps">{requestSteps(item, today).map(step => <li key={step.key} data-state={step.state}><span>{step.label}</span>{step.detail && <small>{step.detail}</small>}</li>)}</ol>
    {item.response && <p className="subscription-quote"><strong>Drivy :</strong> {item.response}</p>}
    {item.revisions.length > 0 && <ul className="subscription-revisions">{item.revisions.map(revision => <li key={revision.decidedAt}>
      <strong>{revision.action === 'RESUME' ? 'Service repris' : `Date reportée au ${civilLabel(revision.newEffectiveOn ?? revision.previousEffectiveOn)}`}</strong>
      <span>{instantDayLabel(revision.decidedAt)} · {revision.response}</span>
    </li>)}</ul>}
    {requestIsOpen(item) && <Button variant="ghost" disabled={disabled} aria-label={`Retirer la demande : ${requestKindLabels[item.kind]}`} onClick={() => onWithdraw(item)}>Retirer</Button>}
  </li>;
}

function ContactBlock({ data }: { data: SchoolSubscription }) {
  if (!data.contact) return null;
  return <Block title="Contact Drivy">
    <p className="subscription-contact">{data.contact.name}</p>
    {data.contact.email && <Button variant="outline" render={<a href={`mailto:${data.contact.email}`} />} nativeButton={false}><Mail aria-hidden="true" />{data.contact.email}</Button>}
  </Block>;
}

const dialogTitles: Record<SubscriptionRequestKind, string> = { OFFER_CHANGE: 'Changer d’offre', TERMINATION: 'Demander la résiliation', REGULARIZATION: 'Demander une régularisation' };

function RequestDialog({ data, target, runner, onClose, onRefused }: {
  data: SchoolSubscription; target: RequestTarget | null; runner: Runner; onClose: () => void; onRefused: (code: string) => void;
}) {
  const { schoolId } = useConsole();
  const uid = useId();
  const [offerId, setOfferId] = useState<string | null>(null), [modules, setModules] = useState<readonly string[]>([]);
  const [desiredOn, setDesiredOn] = useState(''), [details, setDetails] = useState(''), [problem, setProblem] = useState<RequestProblem | null>(null);
  // Une réponse perdue se rejoue sous la même opération tant que la saisie ne change pas : jamais une seconde demande.
  const operation = useRef<{ key: string; id: string } | null>(null);
  const kind = target?.kind;
  const errorOf = (field: RequestProblem['field']) => (problem?.field === field ? problem.message : undefined);
  const clear = () => setProblem(null);
  async function submit() {
    if (!kind || runner.busy) return;
    const result = requestBodyOf({ kind, offerId, modules, desiredOn, details }, data.today);
    if ('problem' in result) { setProblem(result.problem); return; }
    const key = JSON.stringify(result.body);
    const operationId = operation.current?.key === key ? operation.current.id : crypto.randomUUID();
    operation.current = { key, id: operationId };
    const command = createCommand({ schoolId, kind: 'createSubscriptionRequest', path: 'subscription/requests', resourceVersion: 0, operationId, body: result.body });
    const sent = await runner.run(command, kind === 'TERMINATION' ? 'Demande reçue. Elle reste en attente de confirmation par Drivy.' : 'Demande reçue par Drivy.');
    if (sent.status === 'rejected') { operation.current = null; onRefused(sent.code); if (sent.code !== 'REQUEST_ALREADY_OPEN') return; }
    onClose();
  }
  const offers = data.availableOffers.filter(item => item.name !== data.offer?.name).map(item => ({ value: item.id, label: item.name }));
  return <Dialog open={target !== null} onOpenChange={(open, reason) => { if (runner.busy) reason.cancel(); else if (!open) onClose(); }}>
    <DialogContent showCloseButton={!runner.busy}>
      {kind && <form className="subscription-form" noValidate onSubmit={event => { event.preventDefault(); void submit(); }}>
        <DialogHeader><DialogTitle>{dialogTitles[kind]}</DialogTitle>
          {kind === 'TERMINATION' && <DialogDescription>Drivy confirme la date d’effet.</DialogDescription>}</DialogHeader>
        <FieldGroup>
          {kind === 'OFFER_CHANGE' && <>
            {offers.length > 0 && <PortalSelect id={`${uid}-offer`} label="Offre souhaitée" value={offerId} options={offers} disabled={runner.busy}
              onValueChange={value => { setOfferId(value); clear(); }} />}
            <Field data-invalid={!!errorOf('choice')}>
              <FieldLabel id={`${uid}-modules`}>Modules souhaités</FieldLabel>
              <div className="subscription-checks" role="group" aria-labelledby={`${uid}-modules`}>{requestableModules.map(code => <label key={code}>
                <Checkbox checked={modules.includes(code)} disabled={runner.busy}
                  onCheckedChange={checked => { setModules(previous => checked ? [...previous, code] : previous.filter(item => item !== code)); clear(); }} />
                <span>{moduleName(code)}</span>
              </label>)}</div>
              {errorOf('choice') && <FieldError>{errorOf('choice')}</FieldError>}
            </Field>
          </>}
          {kind !== 'REGULARIZATION' && <Field data-invalid={!!errorOf('desiredOn')}>
            <FieldLabel htmlFor={`${uid}-date`}>{kind === 'TERMINATION' ? 'Date souhaitée' : 'Date souhaitée (facultative)'}</FieldLabel>
            <Input id={`${uid}-date`} type="date" min={data.today} value={desiredOn} disabled={runner.busy} aria-invalid={!!errorOf('desiredOn')}
              aria-describedby={errorOf('desiredOn') ? `${uid}-date-error` : undefined} onChange={event => { setDesiredOn(event.target.value); clear(); }} />
            {errorOf('desiredOn') && <FieldError id={`${uid}-date-error`}>{errorOf('desiredOn')}</FieldError>}
          </Field>}
          <Field data-invalid={!!errorOf('details')}>
            <FieldLabel htmlFor={`${uid}-details`}>{kind === 'REGULARIZATION' ? 'Message' : kind === 'TERMINATION' ? 'Motif (facultatif)' : 'Précisions (facultatives)'}</FieldLabel>
            <Textarea id={`${uid}-details`} rows={3} maxLength={1000} value={details} disabled={runner.busy} aria-invalid={!!errorOf('details')}
              aria-describedby={errorOf('details') ? `${uid}-details-error` : undefined} onChange={event => { setDetails(event.target.value); clear(); }} />
            {errorOf('details') && <FieldError id={`${uid}-details-error`}>{errorOf('details')}</FieldError>}
          </Field>
        </FieldGroup>
        <CommandFeedback runner={runner} showSuccess={false} />
        <DialogFooter>
          <Button type="button" variant="outline" disabled={runner.busy} onClick={onClose}>Annuler</Button>
          <Button type="submit" variant={kind === 'TERMINATION' ? 'destructive' : 'default'} disabled={runner.busy || runner.blockedReason !== null} aria-busy={runner.busy}>{runner.busy ? 'Envoi…' : 'Envoyer la demande'}</Button>
        </DialogFooter>
      </form>}
    </DialogContent>
  </Dialog>;
}
