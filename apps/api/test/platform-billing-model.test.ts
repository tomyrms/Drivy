import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
  activationBody, billingView, creditBody, documentState, ibanValid, invoiceBalance, invoiceListQuery, invoiceTax, invoiceTotal, invoiceView, issuerBody,
  normalizeIban, prepareBody, type InvoiceRow,
} from '../src/platform-billing-model.js';
import { billingSchema, invoiceSchema } from '../src/platform-billing-contract.js';
import { billingSchedule, type CommercialDetail, type TermsRow } from '../src/platform-commercial-model.js';

/**
 * R01-T05 (#457) : contrôle d'IBAN, taxe au centime, solde et état d'une période, projection de la facturation d'une fiche.
 * Écrit sans être exécuté (règle du porteur : aucun test avant la fin de l'epic). Données synthétiques ; aucun montant ni IBAN réels
 * (les IBAN sont les exemples publiés de la norme).
 */
const operationId = randomUUID();

describe('IBAN', () => {
  it('accepte les exemples publiés, espaces et minuscules compris ; refuse une clé ou une forme fausse', () => {
    expect(ibanValid('CH93 0076 2011 6238 5295 7')).toBe(true);
    expect(ibanValid('gb82 west 1234 5698 7654 32')).toBe(true);
    expect(normalizeIban('ch93 0076 2011 6238 5295 7')).toBe('CH9300762011623852957');
    expect(ibanValid('CH94 0076 2011 6238 5295 7')).toBe(false);
    expect(ibanValid('CH93')).toBe(false);
    expect(ibanValid('9300762011623852957CH')).toBe(false);
  });
});

describe('taxe', () => {
  it('sans TVA : aucune taxe, le total est le net', () => {
    expect(invoiceTax(9_900, 'NONE', null, null)).toBe(0);
    expect(invoiceTotal(9_900, 'NONE', null, null)).toBe(9_900);
  });
  it('TVA hors taxe : net × taux arrondi au centime le plus proche, ajouté au total', () => {
    expect(invoiceTax(9_900, 'VAT', 810, false)).toBe(802);
    expect(invoiceTotal(9_900, 'VAT', 810, false)).toBe(10_702);
    expect(invoiceTax(5, 'VAT', 1_000, false)).toBe(1);
    expect(invoiceTax(4, 'VAT', 1_000, false)).toBe(0);
  });
  it('TVA comprise : la taxe est extraite du net, le total ne change pas', () => {
    expect(invoiceTax(9_900, 'VAT', 810, true)).toBe(742);
    expect(invoiceTotal(9_900, 'VAT', 810, true)).toBe(9_900);
    expect(invoiceTax(0, 'VAT', 810, true)).toBe(0);
  });
  it('reste exact sur de grands montants (entiers seulement)', () => {
    expect(invoiceTax(999_999_999, 'VAT', 810, false)).toBe(81_000_000);
  });
});

describe('saisies', () => {
  const issuer = {
    operationId, legalName: 'Drivy Exemple Sàrl', street: 'Rue de l’Exemple 1', postalCode: '1000', city: 'Lausanne', country: 'ch',
    email: 'Facturation@Example.invalid', iban: 'CH93 0076 2011 6238 5295 7', taxMode: 'NONE', vatNumber: null, taxRateBp: null, pricesIncludeTax: null, taxNote: null,
  };
  it('l’émetteur normalise pays, adresse électronique et IBAN ; la TVA exige ses trois champs, sans TVA aucun', () => {
    const parsed = issuerBody.parse(issuer);
    expect(parsed).toMatchObject({ country: 'CH', email: 'facturation@example.invalid', iban: 'CH9300762011623852957' });
    expect(issuerBody.safeParse({ ...issuer, taxMode: 'VAT' }).success).toBe(false);
    expect(issuerBody.safeParse({ ...issuer, taxRateBp: 810 }).success).toBe(false);
    expect(issuerBody.safeParse({ ...issuer, taxMode: 'VAT', vatNumber: 'CHE-123.456.789 TVA', taxRateBp: 810, pricesIncludeTax: true }).success).toBe(true);
    expect(issuerBody.safeParse({ ...issuer, taxMode: 'VAT', vatNumber: 'CHE-123.456.789', taxRateBp: 810, pricesIncludeTax: true }).success).toBe(false);
    expect(issuerBody.safeParse({ ...issuer, iban: 'CH94 0076 2011 6238 5295 7' }).success).toBe(false);
    expect(issuerBody.safeParse({ ...issuer, extra: true }).success).toBe(false);
  });
  it('une période se désigne par son premier jour ; le montant initial n’en a pas', () => {
    expect(prepareBody.safeParse({ operationId, kind: 'INITIAL' }).success).toBe(true);
    expect(prepareBody.safeParse({ operationId, kind: 'INITIAL', periodStart: '2027-01-01' }).success).toBe(false);
    expect(prepareBody.safeParse({ operationId, kind: 'PERIOD' }).success).toBe(false);
    expect(prepareBody.safeParse({ operationId, kind: 'PERIOD', periodStart: '2027-01-01' }).success).toBe(true);
  });
  it('activation et avoir exigent une confirmation explicite ; un avoir exige un motif', () => {
    expect(activationBody.safeParse({ operationId, startsOn: '2027-01-01' }).success).toBe(false);
    expect(activationBody.safeParse({ operationId, startsOn: '2027-01-01', confirm: true }).success).toBe(true);
    expect(creditBody.safeParse({ operationId, confirm: true, reason: 'x' }).success).toBe(false);
    expect(creditBody.safeParse({ operationId, confirm: true, reason: 'Montant erroné' }).success).toBe(true);
  });
  it('la liste ignore les filtres vides et borne la page', () => {
    expect(invoiceListQuery.parse({ status: '', limit: '20' })).toMatchObject({ limit: 20, offset: 0 });
    expect(invoiceListQuery.parse({}).status).toBeUndefined();
    expect(invoiceListQuery.safeParse({ limit: '101' }).success).toBe(false);
    expect(invoiceListQuery.safeParse({ overdue: 'false' }).success).toBe(false);
  });
});

const baseRow = (patch: Partial<InvoiceRow> = {}): InvoiceRow => ({
  id: randomUUID(), client_id: randomUUID(), kind: 'PERIOD', generation: 1, status: 'ISSUED', origin: 'MANUAL', paid_start_id: randomUUID(),
  period_index: 0, period_start: '2027-01-15', period_end: '2027-02-14', credits_invoice_id: null, terms_id: randomUUID(), terms_sequence: 1, currency: 'CHF',
  lines: [{ code: 'MONTHLY', label: 'Abonnement du 15.01.2027 au 14.02.2027', periodStart: '2027-01-15', periodEnd: '2027-02-14', amount: 9_900, discount: 0, net: 9_900, termsSequence: 1 }],
  subtotal: 9_900, discount_total: 0, net_total: 9_900, number: 'F-2027-00001', issued_on: '2027-01-15', due_on: '2027-02-14',
  issued_at: '2027-01-15T08:00:00.000Z',
  issuer: { legalName: 'Drivy Exemple Sàrl', street: 'Rue de l’Exemple 1', postalCode: '1000', city: 'Lausanne', country: 'CH', email: null, iban: null, vatNumber: null, taxNote: null },
  recipient: { name: 'Auto-école des Lilas', contactName: null, street: 'Rue des Lilas 2', postalCode: '1200', city: 'Genève', country: 'CH' },
  payment_term_days: 30, tax_mode: 'NONE', tax_rate_bp: null, prices_include_tax: null, tax_amount: 0, total: 9_900, send_status: 'NOT_SENT', sent_on: null,
  sent_recorded_at: null, prepared_at: '2027-01-15T07:00:00.000Z', cancelled_at: null, reason: null, version: 2,
  client_name: 'Auto-école des Lilas', school_id: randomUUID(), prepared_by_name: null, issued_by_name: null, cancelled_by_name: null,
  sent_recorded_by_name: null, credit_note: null, credited_number: null,
  settlement: { allocated: 0, credited: 0, balance: 9_900, state: 'UNPAID', overdue: false }, allocations: [], ...patch,
});
const unpaid = (overdue: boolean) => ({ allocated: 0, credited: 0, balance: 9_900, state: 'UNPAID' as const, overdue });
const noDebt = { outstanding: 0, overdueAmount: 0, overdueCount: 0, oldestOverdueDueOn: null, unallocated: 0 };

// Le solde et le retard sont calculés par la base (`platform_invoice_settlement`) ; le modèle les reprend sans les recalculer.
describe('solde et échéance', () => {
  it('une facture émise reprend le solde et le retard calculés par la base', () => {
    expect(invoiceBalance(baseRow())).toEqual({ balance: 9_900, overdue: false });
    expect(invoiceBalance(baseRow({ settlement: unpaid(true) }))).toEqual({ balance: 9_900, overdue: true });
    expect(invoiceBalance(baseRow({ settlement: { allocated: 4_000, credited: 0, balance: 5_900, state: 'PARTIAL', overdue: true } })))
      .toEqual({ balance: 5_900, overdue: true });
  });
  it('un avoir total solde la facture ; brouillon, annulation et avoir n’ont pas de solde', () => {
    expect(invoiceBalance(baseRow({
      credit_note: { id: randomUUID(), number: 'AV-2027-00001', total: 9_900, issued_on: '2027-01-20' },
      settlement: { allocated: 0, credited: 9_900, balance: 0, state: 'CREDITED', overdue: false },
    }))).toEqual({ balance: 0, overdue: false });
    expect(invoiceBalance(baseRow({ status: 'DRAFT', total: null, settlement: null })).balance).toBeNull();
    expect(invoiceBalance(baseRow({ status: 'CANCELLED', settlement: null })).balance).toBeNull();
    expect(invoiceBalance(baseRow({ kind: 'CREDIT_NOTE', settlement: null })).balance).toBeNull();
  });
  it('la vue d’une facture respecte le contrat, brouillon compris', () => {
    expect(invoiceSchema.safeParse(invoiceView(baseRow())).success).toBe(true);
    const draft = baseRow({
      status: 'DRAFT', number: null, issued_on: null, due_on: null, issued_at: null, issuer: null, recipient: null, payment_term_days: null,
      tax_mode: null, tax_amount: null, total: null, version: 1, settlement: null,
    });
    const view = invoiceView(draft);
    expect(invoiceSchema.safeParse(view).success).toBe(true);
    expect(view).toMatchObject({ number: null, total: null, tax: null, issuer: null, balance: null, overdue: false, settlement: null });
  });
});

describe('état d’une période', () => {
  it('sans facture : due si commencée ; brouillon ; émise ; créditée puis à refaire tant qu’elle est due', () => {
    expect(documentState([], 'PERIOD', '2027-01-15', true).state).toBe('DUE');
    expect(documentState([], 'PERIOD', '2027-02-15', false).state).toBe('NOT_DUE');
    const draft = invoiceView(baseRow({ status: 'DRAFT', number: null, total: null, settlement: null }));
    expect(documentState([draft], 'PERIOD', '2027-01-15', true).state).toBe('DRAFT');
    const issued = invoiceView(baseRow());
    expect(documentState([issued], 'PERIOD', '2027-01-15', true)).toMatchObject({ state: 'ISSUED', number: 'F-2027-00001', total: 9_900, balance: 9_900 });
    const credited = invoiceView(baseRow({
      credit_note: { id: randomUUID(), number: 'AV-2027-00001', total: 9_900, issued_on: '2027-01-20' },
      settlement: { allocated: 0, credited: 9_900, balance: 0, state: 'CREDITED', overdue: false },
    }));
    expect(documentState([credited], 'PERIOD', '2027-01-15', true).state).toBe('DUE');
    expect(documentState([credited], 'PERIOD', '2027-01-15', false).state).toBe('CREDITED');
    const second = invoiceView(baseRow({ generation: 2, number: 'F-2027-00002' }));
    expect(documentState([credited, second], 'PERIOD', '2027-01-15', true)).toMatchObject({ state: 'ISSUED', number: 'F-2027-00002' });
  });
  it('une annulation est ignorée ; une autre période ne compte pas', () => {
    const cancelled = invoiceView(baseRow({ status: 'CANCELLED', settlement: null }));
    expect(documentState([cancelled], 'PERIOD', '2027-01-15', true).state).toBe('DUE');
    expect(documentState([invoiceView(baseRow())], 'PERIOD', '2027-02-15', true).state).toBe('DUE');
  });
});

describe('facturation d’une fiche', () => {
  const terms: TermsRow[] = [{
    id: randomUUID(), sequence: 1, currency: 'CHF', initialAmount: 50_000, initialDiscount: 10_000, initialDueOn: null, monthlyAmount: 9_900,
    recurringDiscount: 900, recurringDiscountMonths: 2, paymentTermDays: 30, suspensionBilling: 'CONTINUE', effectiveFrom: '2027-01-15',
    exceptionReason: null, createdAt: '2027-01-01T08:00:00.000Z', createdByName: null,
  }];
  const commercial = (today: string, paidStartsOn: string | null, terminationOn: string | null = null) => ({
    today, billable: paidStartsOn !== null, paidStart: paidStartsOn ? { startsOn: paidStartsOn } : null,
    termination: terminationOn ? { effectiveOn: terminationOn } : null, terms: { versions: terms },
  }) as unknown as CommercialDetail;

  it('reprend exactement les montants de l’échéancier de R01-T04, de la première période à la période en cours plus trois', () => {
    const view = billingView({ commercial: commercial('2027-03-20', '2027-01-15'), activation: null, activations: [], invoices: [], issuerReady: true, version: 1, payments: [], debt: noDebt });
    const expected = billingSchedule({ paidStartsOn: '2027-01-15', terminationOn: null, terms, today: '2027-01-15', count: 6 });
    expect(view.periods.map(period => [period.startsOn, period.amount, period.discount, period.net]))
      .toEqual(expected.periods.map(period => [period.startsOn, period.amount, period.discount, period.net]));
    expect(view.periods.map(period => period.startsOn)).toEqual(['2027-01-15', '2027-02-15', '2027-03-15', '2027-04-15', '2027-05-15', '2027-06-15']);
    expect(view.periods.map(period => period.state)).toEqual(['DUE', 'DUE', 'DUE', 'NOT_DUE', 'NOT_DUE', 'NOT_DUE']);
    expect(view.periods.map(period => period.net)).toEqual([9_000, 9_000, 9_900, 9_900, 9_900, 9_900]);
    expect(view.initial).toMatchObject({ dueOn: '2027-01-15', net: 40_000, state: 'DUE' });
    expect(billingSchema.safeParse(view).success).toBe(true);
  });
  it('s’arrête à la résiliation ; sans début payant, aucune période', () => {
    const ended = billingView({ commercial: commercial('2027-02-20', '2027-01-15', '2027-03-15'), activation: null, activations: [], invoices: [], issuerReady: false, version: 1, payments: [], debt: noDebt });
    expect(ended.periods.map(period => period.startsOn)).toEqual(['2027-01-15', '2027-02-15']);
    expect(ended.terminationOn).toBe('2027-03-15');
    const none = billingView({ commercial: commercial('2027-02-20', null), activation: null, activations: [], invoices: [], issuerReady: false, version: 1, payments: [], debt: noDebt });
    expect(none).toMatchObject({ initial: null, periods: [], paidStartsOn: null, outstanding: 0, overdue: 0 });
    expect(billingSchema.safeParse(none).success).toBe(true);
  });
  it('le solde dû et le nombre de factures échues viennent du calcul de la base', () => {
    const invoices = [
      baseRow({ settlement: unpaid(true) }),
      baseRow({ period_start: '2027-02-15', period_end: '2027-03-14', period_index: 1, number: 'F-2027-00002', due_on: '2027-03-30' }),
      baseRow({ status: 'DRAFT', number: null, total: null, period_start: '2027-03-15', period_end: '2027-04-14', period_index: 2, settlement: null }),
    ];
    const debt = { outstanding: 19_800, overdueAmount: 9_900, overdueCount: 1, oldestOverdueDueOn: '2027-02-14', unallocated: 0 };
    const view = billingView({ commercial: commercial('2027-03-20', '2027-01-15'), activation: null, activations: [], invoices, issuerReady: true, version: 4,
      payments: [], debt });
    expect(view).toMatchObject({ outstanding: 19_800, overdue: 1, version: 4, debt });
    expect(billingSchema.safeParse(view).success).toBe(true);
    expect(view.periods.slice(0, 3).map(period => period.state)).toEqual(['ISSUED', 'ISSUED', 'DRAFT']);
  });
});
