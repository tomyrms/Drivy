import { useRef, useState } from 'react';
import { request, type Session } from '../../protocol';
import {
  platformBillingResult, platformBillingRunResult, platformInvoicePageResult, platformIssuerResult,
  type PlatformBilling, type PlatformBillingRun, type PlatformInvoice, type PlatformInvoiceKind, type PlatformInvoiceStatus, type PlatformIssuerSettings,
  type PlatformSendStatus,
} from '../../platform-model';
import type { ClientBilling } from './use-platform-clients';
import { useOperationIds } from './use-platform-offers';

type Kernel = {
  session: Session | null; perform: (action: () => Promise<void>) => Promise<void>; reload: () => Promise<void>;
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
  | { kind: 'invoice'; invoice: PlatformInvoice }
  | { kind: 'issuer' }
  | { kind: 'run' };
/** L'émetteur au format de la commande : chaque version redonne tout. */
export type IssuerInput = {
  legalName: string; street: string; postalCode: string; city: string; country: string; email: string | null; iban: string | null;
  taxMode: 'NONE' | 'VAT'; vatNumber: string | null; taxRateBp: number | null; pricesIncludeTax: boolean | null; taxNote: string | null;
};
export type InvoiceFilter = { status: PlatformInvoiceStatus | 'ALL'; kind: PlatformInvoiceKind | 'ALL'; sendStatus: PlatformSendStatus | 'ALL'; overdue: boolean };
export type InvoiceList = { items: PlatformInvoice[]; total: number; today: string | null };
export type BillingSnapshot = { invoices: InvoiceList; issuer: PlatformIssuerSettings | null };

const PAGE_SIZE = 25;
const allInvoices: InvoiceFilter = { status: 'ALL', kind: 'ALL', sendStatus: 'ALL', overdue: false };
const emptyList: InvoiceList = { items: [], total: 0, today: null };
export function invoicesPath(filter: InvoiceFilter, offset = 0) {
  const query = new URLSearchParams({ limit: String(PAGE_SIZE) });
  if (offset > 0) query.set('offset', String(offset));
  if (filter.status !== 'ALL') query.set('status', filter.status);
  if (filter.kind !== 'ALL') query.set('kind', filter.kind);
  if (filter.sendStatus !== 'ALL') query.set('sendStatus', filter.sendStatus);
  if (filter.overdue) query.set('overdue', 'true');
  return `platform/invoices?${query}`;
}

/**
 * Factures (R01-T05) : facturation de la fiche ouverte, liste de toutes les factures, émetteur et passage manuel. Chaque commande d'une fiche
 * part sous la version de facturation que l'écran a lue et rend la facturation relue après écriture ; un conflit relit toute la console.
 * Aucun montant, aucune échéance ni aucun numéro ne sont calculés ici.
 */
export function usePlatformBilling({ session, perform, reload, clientId, billing, setBilling }: Kernel) {
  const [dialog, setDialog] = useState<BillingDialog | null>(null);
  const [invoices, setInvoices] = useState<InvoiceList>(emptyList), [filter, setFilter] = useState<InvoiceFilter>(allInvoices);
  const [issuer, setIssuer] = useState<PlatformIssuerSettings | null>(null), [run, setRun] = useState<PlatformBillingRun | null>(null);
  const filterRef = useRef(allInvoices);
  const operations = useOperationIds();
  const current: PlatformBilling | null = billing && billing.clientId === clientId ? billing.data : null;

  const stop = () => { setDialog(null); setRun(null); };
  const start = (next: BillingDialog) => { setRun(null); setDialog(next); };
  function reset() {
    stop(); operations.clear(); setInvoices(emptyList); setFilter(allInvoices); setIssuer(null); filterRef.current = allInvoices;
  }

  async function snapshot(): Promise<BillingSnapshot> {
    const [list, settings] = await Promise.all([request(invoicesPath(filterRef.current), platformInvoicePageResult), request('platform/billing/issuer', platformIssuerResult)]);
    return { invoices: { items: list.data.items, total: list.data.total, today: list.data.today }, issuer: settings.data };
  }
  function apply(next: BillingSnapshot) { setInvoices(next.invoices); setIssuer(next.issuer); }

  async function write(action: string, path: string, body: object) {
    if (!session || !clientId || !current) return;
    const key = `${action}:${clientId}:${current.version}:${JSON.stringify(body)}`;
    const operationId = operations.operationFor(key);
    try {
      const result = await request(`platform/clients/${clientId}/${path}`, platformBillingResult,
        { csrf: session.csrfToken, body: { operationId, version: current.version, ...body } });
      operations.settle(key); setBilling({ clientId, data: result.data });
    } catch (reason) { operations.settle(key, reason); throw reason; }
    stop();
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
    activate, stopBilling, prepare, issue, cancel, credit, markSent, chooseFilter, moreInvoices, saveIssuer, runBilling };
}
export type PlatformBillingState = ReturnType<typeof usePlatformBilling>;
