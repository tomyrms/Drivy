import { useState, type ReactNode } from 'react';
import { ReceiptText } from 'lucide-react';
import {
  chf, documentStateLabel, ibanLabel, ibanValid, invoiceKindLabel, invoiceStatusLabel, rateOf, sendStatusLabel, taxRateLabel,
  type PlatformBilling, type PlatformBillingPeriod, type PlatformClientDetail, type PlatformInvoice, type PlatformIssuer,
} from '../../platform-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import { PortalSelect } from '../components/portal-select';
import type { InvoiceFilter, IssuerInput } from './use-platform-billing';
import type { PlatformConsoleState } from './use-platform-console';

const dateTime = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
/** Un jour civil reste ce jour-là, quel que soit le fuseau du navigateur. */
const civil = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeZone: 'UTC' }).format(new Date(`${value}T00:00:00Z`));
const by = (name: string | null) => (name ? ` · par ${name}` : '');
const selectError = (message: string | undefined) => (message ? { error: message } : {});
const reasonProblem = (text: string) => {
  const trimmed = text.trim();
  if (trimmed.length < 3) return 'Indiquez le motif en quelques mots.';
  return trimmed.length > 500 ? 'Ce texte est limité à 500 caractères.' : null;
};
const dayPattern = /^\d{4}-\d{2}-\d{2}$/;
type DocumentState = PlatformBillingPeriod['state'];
const invoiceTitle = (invoice: PlatformInvoice) => `${invoiceKindLabel(invoice.kind)}${invoice.number ? ` ${invoice.number}` : ''}`;
const periodText = (invoice: PlatformInvoice) => (invoice.period ? `${civil(invoice.period.startsOn)} → ${civil(invoice.period.endsOn)}` : null);

/**
 * Facturation de l'école (R01-T05) : documents dus, brouillons, factures émises, avoirs et facturation planifiée.
 * Chaque montant, numéro et échéance vient de la facturation relue par l'API ; l'écran ne fait que proposer les commandes permises.
 */
export function BillingPanel({ state, client }: { state: PlatformConsoleState; client: PlatformClientDetail }) {
  const { billing } = state, data = billing.billing;
  if (!data || (!data.billable && !data.activation && data.invoices.length === 0)) return null;
  const pending = [
    ...(data.initial && (data.initial.state === 'DUE' || data.initial.state === 'DRAFT') ? [{ key: 'initial', kind: 'INITIAL' as const, startsOn: null, endsOn: null, ...data.initial }] : []),
    ...data.periods.filter(period => period.state === 'DUE' || period.state === 'DRAFT').map(period => ({ key: period.startsOn, kind: 'PERIOD' as const, ...period })),
  ];
  const documents = data.invoices.filter(item => item.status !== 'CANCELLED' && item.status !== 'DRAFT');
  return <div className="platform-group platform-rights-panel" role="group" aria-label={`Facturation de ${client.displayName ?? client.school?.name ?? 'l’école'}`}>
    <div className="platform-fiche-head">
      <h4 className="platform-subtitle">Facturation</h4>
      <div className="platform-actions">
        {!data.activation && data.billable && <Button variant="outline" disabled={state.busy} onClick={() => billing.start({ kind: 'activate' })}>Activer la facturation planifiée</Button>}
        {data.activation && <Button variant="ghost" disabled={state.busy} onClick={() => billing.start({ kind: 'stop' })}>Arrêter la facturation planifiée</Button>}
      </div>
    </div>
    {!data.issuerReady && <div className="platform-summary"><strong><Badge variant="destructive">Émetteur à compléter</Badge></strong></div>}
    <dl className="platform-facts">
      <Fact label="Facturation planifiée">{data.activation ? `Active depuis le ${civil(data.activation.startsOn)}` : 'Manuelle'}</Fact>
      <Fact label="Solde ouvert">{chf(data.outstanding)}{data.overdue > 0 ? ` · ${data.overdue === 1 ? '1 facture en retard' : `${data.overdue} factures en retard`}` : ''}</Fact>
      {data.terminationOn && <Fact label="Résiliation">{civil(data.terminationOn)}</Fact>}
    </dl>
    {pending.length > 0 && <ul className="platform-list" aria-label="Documents à traiter">{pending.map(item => <li key={item.key}>
      <div className="platform-summary">
        <strong>{item.kind === 'INITIAL' ? 'Montant initial' : `${civil(item.startsOn!)} → ${civil(item.endsOn!)}`} · {chf(item.net)}
          <StateBadge state={item.state} /></strong>
        {item.kind === 'INITIAL' && 'dueOn' in item && <span>Dû le {civil(item.dueOn)}</span>}
      </div>
      {item.state === 'DUE' && <Button variant="outline" disabled={state.busy}
        onClick={() => billing.start(item.kind === 'INITIAL' ? { kind: 'prepare', invoiceKind: 'INITIAL' } : { kind: 'prepare', invoiceKind: 'PERIOD', periodStart: item.startsOn! })}>Préparer</Button>}
      {item.state === 'DRAFT' && item.invoiceId && <OpenInvoice state={state} invoice={data.invoices.find(invoice => invoice.id === item.invoiceId) ?? null} label="Ouvrir le brouillon" />}
    </li>)}</ul>}
    {documents.length > 0 && <ul className="platform-list" aria-label="Factures et avoirs">{documents.map(invoice => <li key={invoice.id}>
      <InvoiceSummary invoice={invoice} />
      <OpenInvoice state={state} invoice={invoice} label="Voir" />
    </li>)}</ul>}
    <Schedule data={data} />
    <History data={data} />
  </div>;
}

function Fact({ label, children }: { label: string; children: ReactNode }) {
  return <div><dt>{label}</dt><dd>{children}</dd></div>;
}
function StateBadge({ state }: { state: DocumentState }) {
  return state === 'ISSUED' || state === 'NOT_DUE' ? null : <Badge variant="outline">{documentStateLabel(state)}</Badge>;
}
function OpenInvoice({ state, invoice, label }: { state: PlatformConsoleState; invoice: PlatformInvoice | null; label: string }) {
  if (!invoice) return null;
  return <Button variant="ghost" disabled={state.busy} aria-label={`${label} : ${invoiceTitle(invoice)}`} onClick={() => state.billing.start({ kind: 'invoice', invoice })}>{label}</Button>;
}

function InvoiceSummary({ invoice, withClient = false }: { invoice: PlatformInvoice; withClient?: boolean }) {
  const parts = [
    ...(withClient ? [invoice.clientName ?? 'École sans nom'] : []),
    ...(periodText(invoice) ? [periodText(invoice)!] : []),
    ...(invoice.issuedOn ? [`émise le ${civil(invoice.issuedOn)}`] : []),
    ...(invoice.dueOn && invoice.kind !== 'CREDIT_NOTE' ? [`échéance ${civil(invoice.dueOn)}`] : []),
    ...(invoice.status === 'ISSUED' ? [sendStatusLabel(invoice.sendStatus).toLowerCase()] : []),
  ];
  return <div className="platform-summary">
    <strong>{invoiceTitle(invoice)} · {chf(invoice.total ?? invoice.netTotal)}
      {invoice.status !== 'ISSUED' && <Badge variant="outline">{invoiceStatusLabel(invoice.status)}</Badge>}
      {invoice.creditNote && <Badge variant="outline">Créditée</Badge>}
      {invoice.overdue && <Badge variant="destructive">En retard</Badge>}</strong>
    {parts.length > 0 && <span>{parts.join(' · ')}</span>}
  </div>;
}

/** L'échéancier tel que l'API le facture : chaque période porte l'état de sa dernière facture. */
function Schedule({ data }: { data: PlatformBilling }) {
  if (!data.initial && data.periods.length === 0) return null;
  return <details className="platform-history">
    <summary>Échéancier facturé</summary>
    <ol className="platform-list" aria-label="Échéances">
      {data.initial && <li><div className="platform-summary"><strong>Montant initial · {chf(data.initial.net)}<StateBadge state={data.initial.state} /></strong>
        <span>{[`Dû le ${civil(data.initial.dueOn)}`, ...(data.initial.number ? [data.initial.number] : [])].join(' · ')}</span></div></li>}
      {data.periods.map(period => <li key={period.index}><div className="platform-summary">
        <strong>{civil(period.startsOn)} → {civil(period.endsOn)} · {chf(period.net)}<StateBadge state={period.state} /></strong>
        {(period.number || period.discount > 0) && <span>{[...(period.number ? [period.number] : []), ...(period.discount > 0 ? [`remise ${chf(period.discount)}`] : [])].join(' · ')}</span>}
      </div></li>)}
    </ol>
  </details>;
}

function History({ data }: { data: PlatformBilling }) {
  const cancelled = data.invoices.filter(item => item.status === 'CANCELLED');
  if (data.activations.length === 0 && cancelled.length === 0) return null;
  return <details className="platform-history">
    <summary>Historique de la facturation</summary>
    {data.activations.length > 0 && <ol className="platform-list" aria-label="Facturation planifiée">{data.activations.map(item => <li key={item.id}>
      <div className="platform-summary"><strong>Planifiée dès le {civil(item.startsOn)}{item.status === 'STOPPED' && <Badge variant="outline">Arrêtée</Badge>}</strong>
        <span>Activée le {dateTime(item.activatedAt)}{by(item.activatedByName)}</span>
        {item.stopReason && <span>Arrêtée{item.stoppedAt ? ` le ${dateTime(item.stoppedAt)}` : ''}{by(item.stoppedByName)} : {item.stopReason}</span>}</div></li>)}</ol>}
    {cancelled.length > 0 && <ol className="platform-list" aria-label="Brouillons annulés">{cancelled.map(item => <li key={item.id}>
      <div className="platform-summary"><strong>{invoiceKindLabel(item.kind)}{periodText(item) ? ` · ${periodText(item)}` : ''}<Badge variant="outline">Annulé</Badge></strong>
        <span>{item.cancelledAt ? `Annulé le ${dateTime(item.cancelledAt)}` : 'Annulé'}{by(item.cancelledByName)}</span>
        {item.reason && <span>{item.reason === 'TERMS_CHANGED' ? 'Conditions modifiées' : item.reason}</span>}</div></li>)}</ol>}
  </details>;
}

// --- Onglet « Factures » : toutes les écoles, l'émetteur et le passage manuel ---
const statusOptions = [{ value: 'ALL', label: 'Tous les statuts' }, { value: 'DRAFT', label: 'Brouillons' }, { value: 'ISSUED', label: 'Émises' }, { value: 'CANCELLED', label: 'Annulées' }];
const kindOptions = [{ value: 'ALL', label: 'Toutes les natures' }, { value: 'INITIAL', label: 'Montants initiaux' }, { value: 'PERIOD', label: 'Mensualités' }, { value: 'CREDIT_NOTE', label: 'Avoirs' }];
const sendOptions = [{ value: 'ALL', label: 'Tous les envois' }, { value: 'NOT_SENT', label: 'Non envoyées' }, { value: 'SENT', label: 'Envoyées' }];

export function InvoicesSection({ state }: { state: PlatformConsoleState }) {
  const { billing } = state, { filter, invoices, issuer } = billing;
  const choose = (next: Partial<InvoiceFilter>) => void billing.chooseFilter({ ...filter, ...next });
  const current = issuer?.current ?? null;
  return <section className="platform-section" aria-labelledby="platform-invoices-title">
    <h2 id="platform-invoices-title">Factures</h2>
    <div className="platform-pending" role="group" aria-label="Émetteur des factures">
      <div className="platform-summary">
        <strong>{current ? current.legalName : 'Émetteur à compléter'}{!current && <Badge variant="destructive">Requis</Badge>}</strong>
        {current && <span>{[`${current.postalCode} ${current.city}`, ibanLabel(current.iban), current.taxMode === 'VAT' ? `TVA ${taxRateLabel(current.taxRateBp)}` : 'Sans TVA'].join(' · ')}</span>}
      </div>
      <div className="platform-actions">
        <Button variant="outline" disabled={state.busy || !issuer} onClick={() => billing.start({ kind: 'issuer' })}>{current ? 'Modifier l’émetteur' : 'Renseigner l’émetteur'}</Button>
        <Button variant="ghost" disabled={state.busy} onClick={() => billing.start({ kind: 'run' })}>Lancer la facturation du jour</Button>
      </div>
    </div>
    <div className="platform-toolbar">
      <div className="platform-filter" role="group" aria-label="Filtrer les factures">
        <PortalSelect id="invoice-status" label="Statut" options={statusOptions} value={filter.status} disabled={state.busy}
          onValueChange={value => choose({ status: (value ?? 'ALL') as InvoiceFilter['status'] })} />
        <PortalSelect id="invoice-kind" label="Nature" options={kindOptions} value={filter.kind} disabled={state.busy}
          onValueChange={value => choose({ kind: (value ?? 'ALL') as InvoiceFilter['kind'] })} />
        <PortalSelect id="invoice-send" label="Envoi" options={sendOptions} value={filter.sendStatus} disabled={state.busy}
          onValueChange={value => choose({ sendStatus: (value ?? 'ALL') as InvoiceFilter['sendStatus'] })} />
      </div>
      <Button variant={filter.overdue ? 'secondary' : 'ghost'} aria-pressed={filter.overdue} disabled={state.busy} onClick={() => choose({ overdue: !filter.overdue })}>En retard</Button>
    </div>
    <p className="platform-count" role="status">{invoices.total === 1 ? '1 document' : `${invoices.total} documents`}</p>
    {invoices.items.length === 0
      ? <Empty><EmptyHeader><EmptyMedia variant="icon"><ReceiptText aria-hidden="true" /></EmptyMedia><EmptyTitle>Aucune facture</EmptyTitle></EmptyHeader></Empty>
      : <ul className="platform-list">{invoices.items.map(invoice => <li key={invoice.id}>
        <InvoiceSummary invoice={invoice} withClient />
        <OpenInvoice state={state} invoice={invoice} label="Voir" />
      </li>)}</ul>}
    {invoices.items.length < invoices.total && <Button variant="outline" disabled={state.busy} onClick={() => void billing.moreInvoices()}>Afficher plus</Button>}
  </section>;
}

// --- Boîtes de dialogue ---
/** Les commandes de facturation partent d'ici ; `openClient` mène à la fiche d'une facture ouverte depuis l'onglet Factures. */
export function BillingDialog({ state, openClient }: { state: PlatformConsoleState; openClient: (clientId: string) => void }) {
  const { billing } = state, target = billing.dialog, data = billing.billing;
  const find = (invoiceId: string) => data?.invoices.find(item => item.id === invoiceId) ?? null;
  return <Dialog open={target !== null} onOpenChange={(open, details) => { if (state.busy) details.cancel(); else if (!open) billing.stop(); }}>
    <DialogContent showCloseButton={!state.busy}>
      {target?.kind === 'invoice' && <InvoiceBody state={state} invoice={find(target.invoice.id) ?? target.invoice} fresh={find(target.invoice.id) !== null} openClient={openClient} />}
      {data && target?.kind === 'activate' && <ActivateBody state={state} data={data} />}
      {data && target?.kind === 'stop' && <ReasonBody state={state} kind="stop" invoice={null} />}
      {data && target?.kind === 'prepare' && <PrepareBody state={state} data={data} invoiceKind={target.invoiceKind} periodStart={target.periodStart ?? null} />}
      {data && target?.kind === 'issue' && <IssueBody state={state} data={data} invoice={find(target.invoiceId)} />}
      {data && (target?.kind === 'cancel' || target?.kind === 'credit') && <ReasonBody state={state} kind={target.kind} invoice={find(target.invoiceId)} />}
      {data && target?.kind === 'sent' && <SentBody state={state} data={data} invoice={find(target.invoiceId)} />}
      {target?.kind === 'issuer' && <IssuerBody state={state} issuer={billing.issuer?.current ?? null} />}
      {target?.kind === 'run' && <RunBody state={state} />}
    </DialogContent>
  </Dialog>;
}

function Failure({ state, title }: { state: PlatformConsoleState; title: string }) {
  return state.error ? <Alert variant="destructive"><AlertTitle>{title}</AlertTitle><AlertDescription>{state.error}</AlertDescription></Alert> : null;
}
function Footer({ state, label, busyLabel = 'Enregistrement…', destructive = false, cancel = 'Annuler' }: {
  state: PlatformConsoleState; label: string; busyLabel?: string; destructive?: boolean; cancel?: string;
}) {
  return <DialogFooter><Button type="button" variant="outline" disabled={state.busy} onClick={state.billing.stop}>{cancel}</Button>
    <Button type="submit" variant={destructive ? 'destructive' : 'default'} disabled={state.busy} aria-busy={state.busy}>{state.busy ? busyLabel : label}</Button></DialogFooter>;
}
function TextField({ id, label, value, onChange, error, type = 'text', disabled, inputMode, autoComplete }: {
  id: string; label: string; value: string; onChange: (value: string) => void; error?: string | null | undefined; type?: string; disabled: boolean;
  inputMode?: 'decimal' | 'numeric' | 'email'; autoComplete?: string;
}) {
  return <Field data-invalid={!!error}>
    <FieldLabel htmlFor={id}>{label}</FieldLabel>
    <Input id={id} name={id} type={type} inputMode={inputMode} autoComplete={autoComplete ?? 'off'} value={value} disabled={disabled} aria-invalid={!!error}
      aria-describedby={error ? `${id}-error` : undefined} onChange={event => onChange(event.target.value)} />
    {error && <FieldError id={`${id}-error`}>{error}</FieldError>}
  </Field>;
}
function NotFound() {
  return <DialogHeader><DialogTitle>Document introuvable</DialogTitle><DialogDescription>L’écran a été actualisé.</DialogDescription></DialogHeader>;
}

/** Une facture telle que l'API l'a figée : lignes, taxe, total, émetteur et destinataire. Les commandes ne sont offertes que depuis sa fiche. */
function InvoiceBody({ state, invoice, fresh, openClient }: {
  state: PlatformConsoleState; invoice: PlatformInvoice; fresh: boolean; openClient: (clientId: string) => void;
}) {
  const { billing } = state;
  const draft = invoice.status === 'DRAFT', issued = invoice.status === 'ISSUED';
  const creditable = issued && invoice.kind !== 'CREDIT_NOTE' && !invoice.creditNote;
  return <div className="platform-form">
    <DialogHeader><DialogTitle>{invoiceTitle(invoice)}</DialogTitle>
      <DialogDescription>{[invoice.clientName ?? 'École sans nom', ...(periodText(invoice) ? [periodText(invoice)!] : [])].join(' · ')}</DialogDescription></DialogHeader>
    <div className="platform-summary"><strong>{invoiceStatusLabel(invoice.status)}
      {invoice.creditNote && <Badge variant="outline">Créditée par {invoice.creditNote.number}</Badge>}
      {invoice.overdue && <Badge variant="destructive">En retard</Badge>}</strong>
      {invoice.creditsInvoice && <span>Crédite {invoice.creditsInvoice.number ?? 'une facture'}</span>}</div>
    <ul className="platform-list platform-dialog-list" aria-label="Lignes">{invoice.lines.map((line, index) => <li key={`${line.code}:${index}`}>
      <div className="platform-summary"><strong>{line.label}</strong>
        <span>{[chf(line.amount), ...(line.discount > 0 ? [`remise ${chf(line.discount)}`] : []), `net ${chf(line.net)}`].join(' · ')}</span></div>
    </li>)}</ul>
    <dl className="platform-facts">
      <Fact label="Net">{chf(invoice.netTotal)}</Fact>
      {invoice.tax && invoice.tax.mode === 'VAT' && <Fact label={`TVA ${taxRateLabel(invoice.tax.rateBp)}${invoice.tax.pricesIncludeTax ? ' incluse' : ''}`}>{chf(invoice.tax.amount)}</Fact>}
      <Fact label="Total">{invoice.total === null ? 'À l’émission' : chf(invoice.total)}</Fact>
      {invoice.issuedOn && <Fact label="Émise">{civil(invoice.issuedOn)}{by(invoice.issuedByName)}</Fact>}
      {invoice.dueOn && invoice.kind !== 'CREDIT_NOTE' && <Fact label="Échéance">{civil(invoice.dueOn)}</Fact>}
      {issued && invoice.balance !== null && <Fact label="Solde">{chf(invoice.balance)}</Fact>}
      {issued && <Fact label="Envoi">{invoice.sentOn ? `Envoyée le ${civil(invoice.sentOn)}` : 'Non envoyée'}</Fact>}
      {invoice.recipient && <Fact label="Destinataire">{[invoice.recipient.name, invoice.recipient.street, `${invoice.recipient.postalCode} ${invoice.recipient.city}`, invoice.recipient.country].join(', ')}</Fact>}
      {invoice.issuer && <Fact label="Émetteur">{invoice.issuer.legalName} · {ibanLabel(invoice.issuer.iban)}</Fact>}
      {invoice.reason && <Fact label="Motif">{invoice.reason === 'TERMS_CHANGED' ? 'Conditions modifiées' : invoice.reason}</Fact>}
    </dl>
    <DialogFooter>
      {!fresh && <Button variant="outline" disabled={state.busy} onClick={() => { billing.stop(); openClient(invoice.clientId); }}>Ouvrir la fiche</Button>}
      {fresh && draft && <Button variant="ghost" disabled={state.busy} onClick={() => billing.start({ kind: 'cancel', invoiceId: invoice.id })}>Annuler le brouillon</Button>}
      {fresh && creditable && <Button variant="ghost" disabled={state.busy} onClick={() => billing.start({ kind: 'credit', invoiceId: invoice.id })}>Émettre un avoir</Button>}
      {fresh && issued && invoice.sendStatus === 'NOT_SENT' && <Button variant="outline" disabled={state.busy} onClick={() => billing.start({ kind: 'sent', invoiceId: invoice.id })}>Enregistrer l’envoi</Button>}
      {fresh && draft && <Button disabled={state.busy} onClick={() => billing.start({ kind: 'issue', invoiceId: invoice.id })}>Émettre</Button>}
      {!(fresh && draft) && <Button variant={fresh ? 'outline' : 'default'} disabled={state.busy} onClick={billing.stop}>Fermer</Button>}
    </DialogFooter>
  </div>;
}

function ActivateBody({ state, data }: { state: PlatformConsoleState; data: PlatformBilling }) {
  const [startsOn, setStartsOn] = useState(data.today), [invalid, setInvalid] = useState<string | null>(null);
  const submit = () => {
    if (!dayPattern.test(startsOn) || startsOn < data.today) { setInvalid('Choisissez aujourd’hui ou une date à venir.'); return; }
    void state.billing.activate(startsOn);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Activer la facturation planifiée</DialogTitle>
      <DialogDescription>Chaque document dû sera préparé puis émis automatiquement.</DialogDescription></DialogHeader>
    <FieldGroup>
      <TextField id="billing-starts" label="À partir du" type="date" value={startsOn} onChange={value => { setStartsOn(value); setInvalid(null); }} error={invalid} disabled={state.busy} />
    </FieldGroup>
    {!data.issuerReady && <Alert><AlertTitle>Émetteur à compléter</AlertTitle><AlertDescription>Rien ne sera émis avant.</AlertDescription></Alert>}
    <Failure state={state} title="Facturation non activée" />
    <Footer state={state} label="Activer" />
  </form>;
}

function ReasonBody({ state, kind, invoice }: { state: PlatformConsoleState; kind: 'stop' | 'cancel' | 'credit'; invoice: PlatformInvoice | null }) {
  const [reason, setReason] = useState(''), [invalid, setInvalid] = useState<string | null>(null);
  if (kind !== 'stop' && !invoice) return <NotFound />;
  const titles = { stop: 'Arrêter la facturation planifiée ?', cancel: 'Annuler ce brouillon ?', credit: 'Émettre un avoir ?' } as const;
  const failures = { stop: 'Facturation non arrêtée', cancel: 'Brouillon non annulé', credit: 'Avoir non émis' } as const;
  const labels = { stop: 'Arrêter', cancel: 'Annuler le brouillon', credit: 'Émettre l’avoir' } as const;
  const submit = () => {
    const problem = reasonProblem(reason);
    if (problem) { setInvalid(problem); return; }
    if (kind === 'stop') void state.billing.stopBilling(reason);
    else if (kind === 'cancel') void state.billing.cancel(invoice!.id, reason);
    else void state.billing.credit(invoice!.id, reason);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>{titles[kind]}</DialogTitle>
      {kind === 'stop' && <DialogDescription>Les documents dus se prépareront à la main.</DialogDescription>}
      {kind === 'credit' && invoice && <DialogDescription>{invoiceTitle(invoice)} · avoir de {chf(invoice.total)}</DialogDescription>}
      {kind === 'cancel' && invoice && <DialogDescription>{invoiceKindLabel(invoice.kind)}{periodText(invoice) ? ` · ${periodText(invoice)}` : ''}</DialogDescription>}</DialogHeader>
    <FieldGroup>
      <Field data-invalid={!!invalid}>
        <FieldLabel htmlFor="billing-reason">Motif</FieldLabel>
        <Textarea id="billing-reason" name="billing-reason" rows={3} maxLength={500} value={reason} disabled={state.busy} aria-invalid={!!invalid}
          aria-describedby={invalid ? 'billing-reason-error' : undefined} onChange={event => { setReason(event.target.value); setInvalid(null); }} />
        {invalid && <FieldError id="billing-reason-error">{invalid}</FieldError>}
      </Field>
    </FieldGroup>
    <Failure state={state} title={failures[kind]} />
    <Footer state={state} label={labels[kind]} destructive cancel="Retour" />
  </form>;
}

/** Préparer fige les lignes sur les conditions en vigueur ; rien n'est numéroté avant l'émission. */
function PrepareBody({ state, data, invoiceKind, periodStart }: { state: PlatformConsoleState; data: PlatformBilling; invoiceKind: 'INITIAL' | 'PERIOD'; periodStart: string | null }) {
  const period = invoiceKind === 'PERIOD' ? data.periods.find(item => item.startsOn === periodStart) ?? null : null;
  const net = invoiceKind === 'INITIAL' ? data.initial?.net ?? null : period?.net ?? null;
  if (invoiceKind === 'PERIOD' && !period) return <NotFound />;
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); void state.billing.prepare(invoiceKind, periodStart ?? undefined); }}>
    <DialogHeader><DialogTitle>Préparer {invoiceKind === 'INITIAL' ? 'le montant initial' : 'la mensualité'}</DialogTitle>
      <DialogDescription>{period ? `${civil(period.startsOn)} → ${civil(period.endsOn)} · ` : ''}{chf(net)}</DialogDescription></DialogHeader>
    {!data.issuerReady && <Alert><AlertTitle>Émetteur à compléter</AlertTitle><AlertDescription>Le brouillon ne pourra pas être émis avant.</AlertDescription></Alert>}
    <Failure state={state} title="Brouillon non préparé" />
    <Footer state={state} label="Préparer le brouillon" />
  </form>;
}

function IssueBody({ state, data, invoice }: { state: PlatformConsoleState; data: PlatformBilling; invoice: PlatformInvoice | null }) {
  if (!invoice) return <NotFound />;
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); void state.billing.issue(invoice.id); }}>
    <DialogHeader><DialogTitle>Émettre {invoiceKindLabel(invoice.kind).toLowerCase()} ?</DialogTitle>
      <DialogDescription>Le numéro est attribué et le document ne se modifie plus.</DialogDescription></DialogHeader>
    <dl className="platform-facts">
      <Fact label="Net">{chf(invoice.netTotal)}</Fact>
      {periodText(invoice) && <Fact label="Période">{periodText(invoice)}</Fact>}
      <Fact label="Émise le">{civil(data.today)}</Fact>
    </dl>
    {!data.issuerReady && <Alert><AlertTitle>Émetteur à compléter</AlertTitle><AlertDescription>Renseignez-le dans l’onglet Factures.</AlertDescription></Alert>}
    <Failure state={state} title="Facture non émise" />
    <Footer state={state} label="Émettre" busyLabel="Émission…" cancel="Retour" />
  </form>;
}

/** Aucun courriel ne part d'ici : l'opérateur enregistre l'envoi qu'il a fait lui-même. */
function SentBody({ state, data, invoice }: { state: PlatformConsoleState; data: PlatformBilling; invoice: PlatformInvoice | null }) {
  const [sentOn, setSentOn] = useState(data.today), [invalid, setInvalid] = useState<string | null>(null);
  if (!invoice) return <NotFound />;
  const submit = () => {
    if (!dayPattern.test(sentOn) || sentOn > data.today || (invoice.issuedOn !== null && sentOn < invoice.issuedOn)) {
      setInvalid('Choisissez une date entre l’émission et aujourd’hui.'); return;
    }
    void state.billing.markSent(invoice.id, sentOn);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Enregistrer l’envoi</DialogTitle><DialogDescription>{invoiceTitle(invoice)}</DialogDescription></DialogHeader>
    <FieldGroup>
      <TextField id="invoice-sent-on" label="Envoyée le" type="date" value={sentOn} onChange={value => { setSentOn(value); setInvalid(null); }} error={invalid} disabled={state.busy} />
    </FieldGroup>
    <Failure state={state} title="Envoi non enregistré" />
    <Footer state={state} label="Enregistrer" cancel="Retour" />
  </form>;
}

type IssuerDraft = Record<'legalName' | 'street' | 'postalCode' | 'city' | 'country' | 'email' | 'iban' | 'vatNumber' | 'taxRate' | 'taxNote', string>
  & { taxMode: string | null; pricesIncludeTax: string | null };
const issuerDraftOf = (issuer: PlatformIssuer | null): IssuerDraft => ({
  legalName: issuer?.legalName ?? '', street: issuer?.street ?? '', postalCode: issuer?.postalCode ?? '', city: issuer?.city ?? '', country: issuer?.country ?? 'CH',
  email: issuer?.email ?? '', iban: issuer?.iban ? ibanLabel(issuer.iban) : '', vatNumber: issuer?.vatNumber ?? '',
  taxRate: issuer?.taxRateBp ? String(issuer.taxRateBp / 100) : '', taxNote: issuer?.taxNote ?? '', taxMode: issuer?.taxMode ?? 'NONE',
  pricesIncludeTax: issuer?.pricesIncludeTax === null || issuer?.pricesIncludeTax === undefined ? null : issuer.pricesIncludeTax ? 'INCLUDED' : 'EXCLUDED',
});
/** La saisie au format de la commande, ou la première zone à corriger ; l'API relit les mêmes règles. */
function issuerInput(draft: IssuerDraft): { input: IssuerInput } | { field: keyof IssuerDraft; message: string } {
  const required = (field: 'legalName' | 'street' | 'postalCode' | 'city', max: number) => {
    const value = draft[field].trim();
    return value.length === 0 ? 'Ce champ est requis.' : value.length > max ? `Ce texte est limité à ${max} caractères.` : null;
  };
  for (const [field, max] of [['legalName', 150], ['street', 200], ['postalCode', 20], ['city', 100]] as const) {
    const problem = required(field, max);
    if (problem) return { field, message: problem };
  }
  const country = draft.country.trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(country)) return { field: 'country', message: 'Code pays à deux lettres, par exemple CH.' };
  const email = draft.email.trim().toLowerCase();
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return { field: 'email', message: 'Saisissez une adresse e-mail valide.' };
  const iban = draft.iban.replace(/\s+/g, '').toUpperCase();
  if (iban && !ibanValid(iban)) return { field: 'iban', message: 'Cet IBAN n’est pas valide.' };
  const vat = draft.taxMode === 'VAT';
  const taxRateBp = vat ? rateOf(draft.taxRate) : null;
  if (vat && (taxRateBp === undefined || taxRateBp === null)) return { field: 'taxRate', message: 'Saisissez un taux en pour cent, par exemple 8.1.' };
  const vatNumber = draft.vatNumber.trim();
  if (vat && !vatNumber) return { field: 'vatNumber', message: 'Le numéro de TVA est requis.' };
  if (vat && draft.pricesIncludeTax === null) return { field: 'pricesIncludeTax', message: 'Indiquez si les prix incluent la TVA.' };
  const taxNote = draft.taxNote.trim();
  if (taxNote && (taxNote.length < 3 || taxNote.length > 200)) return { field: 'taxNote', message: 'Entre 3 et 200 caractères.' };
  return { input: {
    legalName: draft.legalName.trim(), street: draft.street.trim(), postalCode: draft.postalCode.trim(), city: draft.city.trim(), country,
    email: email || null, iban: iban || null, taxMode: vat ? 'VAT' : 'NONE', vatNumber: vat ? vatNumber : null, taxRateBp: vat ? taxRateBp ?? null : null,
    pricesIncludeTax: vat ? draft.pricesIncludeTax === 'INCLUDED' : null, taxNote: taxNote || null,
  } };
}

function IssuerBody({ state, issuer }: { state: PlatformConsoleState; issuer: PlatformIssuer | null }) {
  const [draft, setDraft] = useState(() => issuerDraftOf(issuer));
  const [invalid, setInvalid] = useState<{ field: keyof IssuerDraft; message: string } | null>(null);
  const set = (field: keyof IssuerDraft) => (value: string | null) => { setDraft(previous => ({ ...previous, [field]: value ?? '' })); setInvalid(null); };
  const errorOf = (field: keyof IssuerDraft) => (invalid?.field === field ? invalid.message : null);
  const vat = draft.taxMode === 'VAT';
  const submit = () => {
    const result = issuerInput(draft);
    if ('field' in result) { setInvalid(result); return; }
    void state.billing.saveIssuer(result.input);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Émetteur des factures</DialogTitle>
      <DialogDescription>Vaut pour les prochaines émissions ; une facture émise garde son émetteur.</DialogDescription></DialogHeader>
    <FieldGroup className="platform-grid">
      <TextField id="issuer-name" label="Raison sociale" value={draft.legalName} onChange={set('legalName')} error={errorOf('legalName')} disabled={state.busy} />
      <TextField id="issuer-street" label="Rue et numéro" value={draft.street} onChange={set('street')} error={errorOf('street')} disabled={state.busy} />
      <TextField id="issuer-postal" label="NPA" value={draft.postalCode} onChange={set('postalCode')} error={errorOf('postalCode')} disabled={state.busy} />
      <TextField id="issuer-city" label="Localité" value={draft.city} onChange={set('city')} error={errorOf('city')} disabled={state.busy} />
      <TextField id="issuer-country" label="Pays (code)" value={draft.country} onChange={set('country')} error={errorOf('country')} disabled={state.busy} />
      <TextField id="issuer-email" label="E-mail (facultatif)" type="email" inputMode="email" value={draft.email} onChange={set('email')} error={errorOf('email')} disabled={state.busy} />
      <TextField id="issuer-iban" label="IBAN (facultatif)" value={draft.iban} onChange={set('iban')} error={errorOf('iban')} disabled={state.busy} />
      <PortalSelect id="issuer-tax" label="TVA" value={draft.taxMode} disabled={state.busy}
        options={[{ value: 'NONE', label: 'Non assujetti' }, { value: 'VAT', label: 'Assujetti' }]} onValueChange={set('taxMode')} />
      {vat && <TextField id="issuer-vat" label="Numéro de TVA" value={draft.vatNumber} onChange={set('vatNumber')} error={errorOf('vatNumber')} disabled={state.busy} />}
      {vat && <TextField id="issuer-rate" label="Taux (%)" inputMode="decimal" value={draft.taxRate} onChange={set('taxRate')} error={errorOf('taxRate')} disabled={state.busy} />}
      {vat && <PortalSelect id="issuer-included" label="Prix des conditions" value={draft.pricesIncludeTax} disabled={state.busy} {...selectError(errorOf('pricesIncludeTax') ?? undefined)}
        options={[{ value: 'EXCLUDED', label: 'Hors TVA' }, { value: 'INCLUDED', label: 'TVA incluse' }]} onValueChange={set('pricesIncludeTax')} />}
    </FieldGroup>
    <TextField id="issuer-note" label="Mention fiscale (facultative)" value={draft.taxNote} onChange={set('taxNote')} error={errorOf('taxNote')} disabled={state.busy} />
    <Failure state={state} title="Émetteur non enregistré" />
    <Footer state={state} label="Enregistrer" />
  </form>;
}

/** Le même passage que le service planifié : il ne refait jamais un document déjà préparé ou émis. */
function RunBody({ state }: { state: PlatformConsoleState }) {
  const run = state.billing.run;
  if (run) return <div className="platform-form">
    <DialogHeader><DialogTitle>Facturation du jour</DialogTitle>
      <DialogDescription>{run.skipped ? 'Un autre passage est en cours.' : civil(run.today)}</DialogDescription></DialogHeader>
    {!run.skipped && <dl className="platform-facts">
      <Fact label="Écoles">{run.clients}</Fact><Fact label="Préparées">{run.prepared}</Fact><Fact label="Émises">{run.issued}</Fact>
      <Fact label="En attente">{run.waiting}</Fact><Fact label="Échecs">{run.failed}</Fact>
    </dl>}
    {!run.skipped && run.failed > 0 && <Alert variant="destructive"><AlertTitle>Échecs</AlertTitle><AlertDescription>Le journal porte le motif de chaque refus.</AlertDescription></Alert>}
    <DialogFooter><Button onClick={state.billing.stop}>Fermer</Button></DialogFooter>
  </div>;
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); void state.billing.runBilling(); }}>
    <DialogHeader><DialogTitle>Lancer la facturation du jour ?</DialogTitle>
      <DialogDescription>Les écoles en facturation planifiée reçoivent leurs documents dus.</DialogDescription></DialogHeader>
    <Failure state={state} title="Facturation non lancée" />
    <Footer state={state} label="Lancer" busyLabel="Facturation…" />
  </form>;
}
