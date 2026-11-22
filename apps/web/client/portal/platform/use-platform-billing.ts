import { useRef, useState } from 'react';
import { request, RequestFailure, type Session } from '../../protocol';
import {
  platformBillingResult, platformBillingRunResult, platformDeliveryPreviewResult, platformInvoicePageResult, platformIssuerResult,
  type PlatformBilling, type PlatformBillingRun, type PlatformDeliveryPreview, type PlatformInvoice, type PlatformInvoiceKind, type PlatformInvoiceStatus, type PlatformIssuerSettings,
  type PlatformPaymentMethod, type PlatformRegularizationKind, type PlatformSendStatus, type PlatformSettlementState,
} from '../../platform-model';
import type { ClientBilling } from './use-platform-clients';
import { useOperationIds } from './use-platform-offers';

type Kernel = {
  session: Session | null; perform: (action: () => Promise<void>) => Promise<void>; reload: () => Promise<void>; clearError: () => void;
  clientId: string | null; billing: ClientBilling | null; setBilling: (next: ClientBilling | null) => void;
};
export type BillingDialog =
  | { kind: 'activate' }
  | { kind: 'stop' }
  | { kind: 'prepare'; invoiceKind: 'INITIAL' | 'PERIOD'; periodStart?: string }
  | { kind: 'issue'; invoiceId: string }
  | { kind: 'cancel'; invoiceId: string }
  | { kind: 'credit'; invoiceId: string }
  | { kind: 'sent'; invoiceId: string }
  | { kind: 'delivery'; invoiceId: string }
  | { kind: 'invoice'; invoice: PlatformInvoice }
  | { kind: 'issuer' }
  | { kind: 'run' }
  | PaymentDialog;
/** Les boîtes des règlements (R01-T06) : elles relisent le règlement dans la facturation à jour, jamais une copie. */
export type PaymentDialog =
  | { kind: 'payment' }
  | { kind: 'paymentDetail'; paymentId: string }
  | { kind: 'allocate'; paymentId: string }
  | { kind: 'release'; paymentId: string; allocationId: string }
  | { kind: 'paymentVoid'; paymentId: string }
  | { kind: 'paymentCorrect'; paymentId: string }
  | { kind: 'regularize'; paymentId: string }
  | { kind: 'regularizationCancel'; paymentId: string; regularizationId: string };
export const isPaymentDialog = (dialog: BillingDialog): dialog is PaymentDialog =>
  ['payment', 'paymentDetail', 'allocate', 'release', 'paymentVoid', 'paymentCorrect', 'regularize', 'regularizationCancel'].includes(dialog.kind);
/** Un règlement au format de la commande. La devise reste CHF : aucune conversion n'existe. */
export type PaymentFields = { amount: number; currency: 'CHF'; receivedOn: string; method: PlatformPaymentMethod; reference: string | null; note: string | null };
export type PaymentInput = PaymentFields & { allocations: Array<{ invoiceId: string; amount: number }>; spread: boolean };
/** L'émetteur au format de la commande : chaque version redonne tout. */
export type IssuerInput = {
  legalName: string; street: string; buildingNumber: string | null; postalCode: string; city: string; country: string; email: string | null; iban: string | null; accountHolder: string | null;
  taxMode: 'NONE' | 'VAT'; vatNumber: string | null; taxRateBp: number | null; pricesIncludeTax: boolean | null; taxNote: string | null;
};
export type InvoiceFilter = {
  status: PlatformInvoiceStatus | 'ALL'; kind: PlatformInvoiceKind | 'ALL'; sendStatus: PlatformSendStatus | 'ALL'; settlement: PlatformSettlementState | 'ALL'; overdue: boolean;
};
export type InvoiceList = { items: PlatformInvoice[]; total: number; today: string | null };
export type BillingSnapshot = { invoices: InvoiceList; issuer: PlatformIssuerSettings | null };

const PAGE_SIZE = 25;
const allInvoices: InvoiceFilter = { status: 'ALL', kind: 'ALL', sendStatus: 'ALL', settlement: 'ALL', overdue: false };
const emptyList: InvoiceList = { items: [], total: 0, today: null };
export function invoicesPath(filter: InvoiceFilter, offset = 0) {
  const query = new URLSearchParams({ limit: String(PAGE_SIZE) });
  if (offset > 0) query.set('offset', String(offset));
  if (filter.status !== 'ALL') query.set('status', filter.status);
  if (filter.kind !== 'ALL') query.set('kind', filter.kind);
  if (filter.sendStatus !== 'ALL') query.set('sendStatus', filter.sendStatus);
  if (filter.settlement !== 'ALL') query.set('settlement', filter.settlement);
  if (filter.overdue) query.set('overdue', 'true');
  return `platform/invoices?${query}`;
}

/**
 * Factures (R01-T05) : facturation de la fiche ouverte, liste de toutes les factures, émetteur et passage manuel. Chaque commande d'une fiche
 * part sous la version de facturation que l'écran a lue et rend la facturation relue après écriture ; un conflit relit toute la console.
 * Aucun montant, aucune échéance ni aucun numéro ne sont calculés ici.
 */
export function usePlatformBilling({ session, perform, reload, clearError, clientId, billing, setBilling }: Kernel) {
  const [dialog, setDialog] = useState<BillingDialog | null>(null);
  const [invoices, setInvoices] = useState<InvoiceList>(emptyList), [filter, setFilter] = useState<InvoiceFilter>(allInvoices);
  const [issuer, setIssuer] = useState<PlatformIssuerSettings | null>(null), [run, setRun] = useState<PlatformBillingRun | null>(null);
  // Doublon probable signalé par la base : rien n'est écrit tant que l'opérateur ne l'a pas confirmé.
  const [duplicate, setDuplicate] = useState(false);
  const [preview, setPreview] = useState<PlatformDeliveryPreview | null>(null);
  const filterRef = useRef(allInvoices);
  const operations = useOperationIds();
  const current: PlatformBilling | null = billing && billing.clientId === clientId ? billing.data : null;

  const stop = () => { setDialog(null); setRun(null); setDuplicate(false); setPreview(null); };
  // Ouvrir une boîte efface le refus de la précédente ; `stop` le garde, car un conflit le dit après avoir fermé.
  const start = (next: BillingDialog) => { clearError(); setRun(null); setDuplicate(false); setPreview(null); setDialog(next); };
  function reset() {
    stop(); operations.clear(); setInvoices(emptyList); setFilter(allInvoices); setIssuer(null); filterRef.current = allInvoices;
  }

  async function snapshot(): Promise<BillingSnapshot> {
    const [list, settings] = await Promise.all([request(invoicesPath(filterRef.current), platformInvoicePageResult), request('platform/billing/issuer', platformIssuerResult)]);
    return { invoices: { items: list.data.items, total: list.data.total, today: list.data.today }, issuer: settings.data };
  }
  function apply(next: BillingSnapshot) { setInvoices(next.invoices); setIssuer(next.issuer); }

  async function write(action: string, path: string, body: object, next: BillingDialog | null = null) {
    if (!session || !clientId || !current) return;
    const key = `${action}:${clientId}:${current.version}:${JSON.stringify(body)}`;
    const operationId = operations.operationFor(key);
    try {
      const result = await request(`platform/clients/${clientId}/${path}`, platformBillingResult,
        { csrf: session.csrfToken, body: { operationId, version: current.version, ...body } });
      operations.settle(key); setBilling({ clientId, data: result.data });
    } catch (reason) { operations.settle(key, reason); throw reason; }
    if (next) { setRun(null); setDuplicate(false); setPreview(null); setDialog(next); } else stop();
    await reload();
  }

  const activate = (startsOn: string) => perform(() => write('activate', 'billing/activation', { startsOn, confirm: true }));
  const stopBilling = (reason: string) => perform(() => write('stop', 'billing/activation/stop', { reason: reason.trim() }));
  const prepare = (invoiceKind: 'INITIAL' | 'PERIOD', periodStart?: string) =>
    perform(() => write(`prepare:${invoiceKind}`, 'invoices', { kind: invoiceKind, ...(invoiceKind === 'PERIOD' && periodStart ? { periodStart } : {}) }));
  const issue = (invoiceId: string) => perform(() => write(`issue:${invoiceId}`, `invoices/${invoiceId}/issue`, { confirm: true }));
  const cancel = (invoiceId: string, reason: string) => perform(() => write(`cancel:${invoiceId}`, `invoices/${invoiceId}/cancel`, { reason: reason.trim() }));
  const credit = (invoiceId: string, reason: string) => perform(() => write(`credit:${invoiceId}`, `invoices/${invoiceId}/credit`, { reason: reason.trim(), confirm: true }));
  const markSent = (invoiceId: string, sentOn: string) => perform(() => write(`sent:${invoiceId}`, `invoices/${invoiceId}/sent`, { sentOn }));

  // --- PDF et envoi (R01-T07) : rien ici ne touche au paiement ni à l'échéance ; l'écran reste sur la facture relue. ---
  const generateDocument = (invoice: PlatformInvoice) =>
    perform(() => write(`document:${invoice.id}`, `invoices/${invoice.id}/document`, {}, { kind: 'invoice', invoice }));
  const sendInvoice = (invoice: PlatformInvoice, resend: boolean) =>
    perform(() => write(`delivery:${invoice.id}`, `invoices/${invoice.id}/delivery`, { confirm: true, resend }, { kind: 'invoice', invoice }));
  const openDelivery = (invoice: PlatformInvoice) => perform(async () => {
    const result = await request(`platform/clients/${invoice.clientId}/invoices/${invoice.id}/delivery/preview`, platformDeliveryPreviewResult);
    start({ kind: 'delivery', invoiceId: invoice.id });
    setPreview(result.data);
  });
  /** Le fichier passe par la session : aucune adresse réutilisable, et une réponse en erreur ne produit aucun fichier. */
  const downloadDocument = (invoice: PlatformInvoice) => perform(async () => {
    let response: Response, blob: Blob;
    try {
      response = await fetch(new URL(`/app/bff/platform/clients/${invoice.clientId}/invoices/${invoice.id}/document`, window.location.origin), {
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
    link.href = url; link.download = `${invoice.kind === 'CREDIT_NOTE' ? 'avoir' : 'facture'}-${invoice.number ?? invoice.id}.pdf`; link.rel = 'noopener'; link.hidden = true;
    document.body.append(link); link.click(); link.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 10_000);
  });

  // --- Règlements : la même opération rejoue une réponse perdue, et seule la facturation relue confirme l'écriture. ---
  const recordPayment = (input: PaymentInput, confirmDuplicate: boolean) => perform(async () => {
    setDuplicate(false);
    try { await write('payment', 'payments', { ...input, confirmDuplicate }); }
    catch (reason) {
      if (reason instanceof RequestFailure && reason.code === 'PAYMENT_POSSIBLE_DUPLICATE') { setDuplicate(true); return; }
      throw reason;
    }
  });
  const clearDuplicate = () => setDuplicate(false);
  const allocatePayment = (paymentId: string, invoiceId: string, amount: number) =>
    perform(() => write(`allocate:${paymentId}`, `payments/${paymentId}/allocations`, { invoiceId, amount }));
  const releaseAllocation = (paymentId: string, allocationId: string, reason: string) =>
    perform(() => write(`release:${allocationId}`, `payments/${paymentId}/allocations/${allocationId}/release`, { reason: reason.trim() }));
  const voidPayment = (paymentId: string, reason: string) =>
    perform(() => write(`void:${paymentId}`, `payments/${paymentId}/void`, { reason: reason.trim(), confirm: true }));
  const correctPayment = (paymentId: string, fields: PaymentFields, reason: string) =>
    perform(() => write(`correct:${paymentId}`, `payments/${paymentId}/correct`, { ...fields, reason: reason.trim() }));
  const regularizePayment = (paymentId: string, amount: number, kind: PlatformRegularizationKind, reason: string) =>
    perform(() => write(`regularize:${paymentId}`, `payments/${paymentId}/regularizations`, { amount, kind, reason: reason.trim() }));
  const cancelRegularization = (paymentId: string, regularizationId: string, reason: string) =>
    perform(() => write(`regularization-cancel:${regularizationId}`, `payments/${paymentId}/regularizations/${regularizationId}/cancel`, { reason: reason.trim() }));

  // --- Liste de toutes les factures ---
  const chooseFilter = (next: InvoiceFilter) => perform(async () => {
    const result = await request(invoicesPath(next), platformInvoicePageResult);
    filterRef.current = next; setFilter(next); setInvoices({ items: result.data.items, total: result.data.total, today: result.data.today });
  });
  const moreInvoices = () => perform(async () => {
    if (invoices.items.length >= invoices.total) return;
    const result = await request(invoicesPath(filterRef.current, invoices.items.length), platformInvoicePageResult);
    setInvoices(previous => {
      const known = new Set(previous.items.map(item => item.id));
      return { items: [...previous.items, ...result.data.items.filter(item => !known.has(item.id))], total: result.data.total, today: result.data.today };
    });
  });

  // --- Émetteur et passage manuel ---
  const saveIssuer = (input: IssuerInput) => perform(async () => {
    if (!session || !issuer) return;
    const key = `issuer:${issuer.version}:${JSON.stringify(input)}`, operationId = operations.operationFor(key);
    try {
      const result = await request('platform/billing/issuer', platformIssuerResult, { csrf: session.csrfToken, body: { operationId, version: issuer.version, ...input } });
      operations.settle(key); setIssuer(result.data);
    } catch (reason) { operations.settle(key, reason); throw reason; }
    stop();
    await reload();
  });
  /** Le même traitement que le service planifié, au jour de Zurich : il ne refait jamais ce qui existe déjà. Le bilan reste affiché. */
  const runBilling = () => perform(async () => {
    if (!session) return;
    const key = 'run', operationId = operations.operationFor(key);
    let result: PlatformBillingRun;
    try {
      result = (await request('platform/billing/run', platformBillingRunResult, { csrf: session.csrfToken, body: { operationId } })).data;
      operations.settle(key);
    } catch (reason) { operations.settle(key, reason); throw reason; }
    await reload();
    setRun(result);
  });

  return { billing: current, dialog, start, stop, reset, snapshot, apply, invoices, filter, issuer, run,
    activate, stopBilling, prepare, issue, cancel, credit, markSent, chooseFilter, moreInvoices, saveIssuer, runBilling,
    preview, generateDocument, downloadDocument, openDelivery, sendInvoice,
    duplicate, clearDuplicate, recordPayment, allocatePayment, releaseAllocation, voidPayment, correctPayment, regularizePayment, cancelRegularization };
}
export type PlatformBillingState = ReturnType<typeof usePlatformBilling>;
