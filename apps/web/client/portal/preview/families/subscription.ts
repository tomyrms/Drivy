import { previewId } from '../fixtures';
import type { PreviewFamily } from '../family';

const offerName = 'Offre d’aperçu', created = '2026-09-01T08:00:00.000Z';
/** Abonnement fictif de l'aperçu : aucune donnée réelle, et aucune écriture ne le modifie. */
const view = {
  hasClient: true, today: '2026-11-20', contact: { name: 'Drivy', email: null }, lifecycle: 'PAID', state: 'OFFER_ACTIVE', restriction: null, trial: null,
  paidStartsOn: '2026-09-01', terminationOn: null, nextPeriodStart: '2026-12-01', nextDueOn: '2026-12-31',
  offer: { name: offerName, effectiveAt: created }, scheduledOffer: null,
  modules: [{ code: 'MESSAGING', inOffer: true, entitled: true }, { code: 'COLLECTIVE_COURSES', inOffer: false, entitled: false }],
  terms: { currency: 'CHF', initialAmount: 50000, initialDiscount: 0, initialDueOn: '2026-09-30', monthlyAmount: 8900, recurringDiscount: 0, recurringDiscountMonths: null,
    paymentTermDays: 30, effectiveFrom: '2026-09-01' },
  scheduledTerms: null,
  debt: { outstanding: 8900, overdueAmount: 0, overdueCount: 0, oldestOverdueDueOn: null, unallocated: 0 },
  invoices: [
    { id: previewId(7801), kind: 'PERIOD', number: 'APERCU-0002', periodStart: '2026-11-01', periodEnd: '2026-11-30', issuedOn: '2026-11-01', dueOn: '2026-12-01', taxAmount: 0, total: 8900,
      creditsInvoiceNumber: null, settlement: { state: 'UNPAID', allocated: 0, credited: 0, balance: 8900, overdue: false }, hasDocument: false },
    { id: previewId(7802), kind: 'INITIAL', number: 'APERCU-0001', periodStart: null, periodEnd: null, issuedOn: '2026-09-01', dueOn: '2026-09-30', taxAmount: 0, total: 50000,
      creditsInvoiceNumber: null, settlement: { state: 'PAID', allocated: 50000, credited: 0, balance: 0, overdue: false }, hasDocument: false },
  ],
  payments: [{ id: previewId(7803), amount: 50000, receivedOn: '2026-09-20', method: 'BANK_TRANSFER' }],
  requests: [{ id: previewId(7804), kind: 'OFFER_CHANGE', status: 'RECEIVED', source: 'SCHOOL', requestedOn: '2026-11-18', requestedOfferId: null, requestedOfferName: null,
    requestedModules: ['COLLECTIVE_COURSES'], desiredOn: null, details: null, response: null, effectiveOn: null, decidedAt: null, version: 1, createdAt: '2026-11-18T09:00:00.000Z', revisions: [] }],
  availableOffers: [{ id: previewId(7805), name: 'Offre complète d’aperçu', modules: ['MESSAGING', 'COLLECTIVE_COURSES'] }],
  notices: [], dunning: null, version: 3,
};

export const subscriptionFamily: PreviewFamily = {
  name: 'subscription',
  read(request, tools) { return request.path === 'subscription' ? tools.reply(200, tools.envelope(structuredClone(view))) : undefined; },
  refusalCode: request => (request.path.startsWith('subscription') ? 'COMMERCIAL_ACCESS_REQUIRED' : undefined),
};
