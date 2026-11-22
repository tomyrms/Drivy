import { z } from 'zod';

/**
 * Espace abonnement de l'école (R01-T08). Ce fichier décrit ce que `GET subscription` renvoie et ce que l'écran en dit ;
 * il ne calcule aucun montant dû : soldes, retards et échéances viennent des factures et des écritures relues par l'API.
 */
const id = z.string().uuid();
const instant = z.string().datetime({ offset: true });
const civilDay = z.string().date();
const cents = z.number().int().min(0);

const termsSchema = z.object({
  currency: z.literal('CHF'), initialAmount: cents.nullable(), initialDiscount: cents, initialDueOn: civilDay.nullable(), monthlyAmount: cents.nullable(),
  recurringDiscount: cents, recurringDiscountMonths: z.number().int().min(1).nullable(), paymentTermDays: z.number().int().min(0).nullable(), effectiveFrom: civilDay,
});
const offerSchema = z.object({ name: z.string().max(100), effectiveAt: instant });
const invoiceSchema = z.object({
  id, kind: z.enum(['INITIAL', 'PERIOD', 'CREDIT_NOTE']), number: z.string().max(40), periodStart: civilDay.nullable(), periodEnd: civilDay.nullable(), issuedOn: civilDay,
  dueOn: civilDay.nullable(), taxAmount: cents, total: cents, creditsInvoiceNumber: z.string().max(40).nullable(),
  settlement: z.object({ state: z.enum(['CREDITED', 'PAID', 'PARTIAL', 'UNPAID']), allocated: cents, credited: cents, balance: cents, overdue: z.boolean() }).nullable(),
  hasDocument: z.boolean(),
});
const paymentSchema = z.object({ id, amount: cents, receivedOn: civilDay, method: z.enum(['BANK_TRANSFER', 'CASH', 'OTHER']) });
const requestKinds = ['OFFER_CHANGE', 'TERMINATION', 'REGULARIZATION'] as const;
const requestSchema = z.object({
  id, kind: z.enum(requestKinds), status: z.enum(['RECEIVED', 'IN_PROGRESS', 'ACCEPTED', 'REFUSED', 'WITHDRAWN', 'REVOKED']), source: z.enum(['OPERATOR', 'SCHOOL']),
  requestedOn: civilDay, requestedOfferId: id.nullable(), requestedOfferName: z.string().max(100).nullable(), requestedModules: z.array(z.string().max(64)).max(10),
  desiredOn: civilDay.nullable(), details: z.string().max(1000).nullable(), response: z.string().max(1000).nullable(), effectiveOn: civilDay.nullable(),
  decidedAt: instant.nullable(), version: z.number().int().min(1), createdAt: instant,
  revisions: z.array(z.object({ action: z.enum(['CHANGE_DATE', 'RESUME']), previousEffectiveOn: civilDay, newEffectiveOn: civilDay.nullable(), response: z.string().max(1000),
    decidedAt: instant })).max(100),
});

export const schoolSubscriptionSchema = z.object({
  hasClient: z.boolean(), today: civilDay, contact: z.object({ name: z.string().max(200), email: z.string().max(320).nullable() }).nullable(),
  lifecycle: z.enum(['NONE', 'TRIAL', 'TRIAL_EXPIRED', 'PAID', 'TERMINATED']), state: z.enum(['NOT_CONFIGURED', 'OFFER_ACTIVE']),
  restriction: z.object({ reason: z.enum(['TRIAL_EXPIRED', 'TERMINATED']), closes: z.array(z.string().max(64)).max(10) }).nullable(),
  trial: z.object({ startsAt: instant, endsAt: instant }).nullable(), paidStartsOn: civilDay.nullable(), terminationOn: civilDay.nullable(),
  nextPeriodStart: civilDay.nullable(), nextDueOn: civilDay.nullable(), offer: offerSchema.nullable(), scheduledOffer: offerSchema.nullable(),
  modules: z.array(z.object({ code: z.string().max(64), inOffer: z.boolean(), entitled: z.boolean() })).max(20),
  terms: termsSchema.nullable(), scheduledTerms: termsSchema.nullable(),
  debt: z.object({ outstanding: cents, overdueAmount: cents, overdueCount: z.number().int().min(0), oldestOverdueDueOn: civilDay.nullable(), unallocated: cents }).nullable(),
  invoices: z.array(invoiceSchema).max(200), payments: z.array(paymentSchema).max(200), requests: z.array(requestSchema).max(50),
  availableOffers: z.array(z.object({ id, name: z.string().max(100), modules: z.array(z.string().max(64)).max(20) })).max(100),
  notices: z.array(z.object({ id, requestId: id, event: z.enum(['RECEIVED', 'IN_PROGRESS', 'ACCEPTED', 'REFUSED', 'WITHDRAWN', 'DATE_CHANGED', 'RESUMED']), createdAt: instant })).max(20),
  version: z.number().int().min(0),
});
export type SchoolSubscription = z.infer<typeof schoolSubscriptionSchema>;
export type SubscriptionInvoice = SchoolSubscription['invoices'][number];
export type SubscriptionRequest = SchoolSubscription['requests'][number];
export type SubscriptionRequestKind = typeof requestKinds[number];

const money = new Intl.NumberFormat('fr-CH', { style: 'currency', currency: 'CHF' });
export const chfAmount = (value: number | null) => (value === null ? '—' : money.format(value / 100));
/** Un jour civil reste ce jour-là, quel que soit le fuseau du navigateur. */
export const civilLabel = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeZone: 'UTC' }).format(new Date(`${value}T00:00:00Z`));
export const instantDayLabel = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeZone: 'Europe/Zurich' }).format(new Date(value));

export const lifecycleLabels: Record<SchoolSubscription['lifecycle'], string> = {
  NONE: 'Sans abonnement', TRIAL: 'Essai', TRIAL_EXPIRED: 'Essai terminé', PAID: 'Abonnement actif', TERMINATED: 'Résilié',
};
export const invoiceKindLabels: Record<SubscriptionInvoice['kind'], string> = { INITIAL: 'Montant initial', PERIOD: 'Abonnement mensuel', CREDIT_NOTE: 'Avoir' };
export const paymentMethodLabels: Record<SchoolSubscription['payments'][number]['method'], string> = { BANK_TRANSFER: 'Virement', CASH: 'Espèces', OTHER: 'Autre' };
export const requestKindLabels: Record<SubscriptionRequestKind, string> = { OFFER_CHANGE: 'Changement d’offre', TERMINATION: 'Résiliation', REGULARIZATION: 'Régularisation' };
export const moduleNames: Record<string, string> = { MESSAGING: 'Messagerie', COLLECTIVE_COURSES: 'Cours collectifs' };
export const moduleName = (code: string) => moduleNames[code] ?? 'Module';
export const requestableModules = ['MESSAGING', 'COLLECTIVE_COURSES'] as const;
export const noticeLabels: Record<SchoolSubscription['notices'][number]['event'], string> = {
  RECEIVED: 'Demande reçue', IN_PROGRESS: 'Prise en charge', ACCEPTED: 'Demande acceptée', REFUSED: 'Demande refusée', WITHDRAWN: 'Demande retirée',
  DATE_CHANGED: 'Date modifiée', RESUMED: 'Service repris',
};

/** Une facture réglée ou créditée n'est jamais présentée comme due ; le retard vient du calcul serveur. */
export function settlementLabel(invoice: SubscriptionInvoice): { label: string; tone: 'default' | 'attention' | 'danger' } {
  if (invoice.kind === 'CREDIT_NOTE') return { label: 'Avoir', tone: 'default' };
  const settlement = invoice.settlement;
  if (!settlement) return { label: 'Émise', tone: 'default' };
  if (settlement.overdue) return { label: 'En retard', tone: 'danger' };
  if (settlement.state === 'PAID') return { label: 'Payée', tone: 'default' };
  if (settlement.state === 'CREDITED') return { label: 'Créditée', tone: 'default' };
  return { label: settlement.state === 'PARTIAL' ? 'Partiellement payée' : 'À payer', tone: 'attention' };
}

export const requestIsOpen = (request: Pick<SubscriptionRequest, 'status'>) => request.status === 'RECEIVED' || request.status === 'IN_PROGRESS';

export function requestStatusLabel(request: Pick<SubscriptionRequest, 'kind' | 'status'>): string {
  // Une résiliation envoyée reste en attente : seule la confirmation de Drivy lui donne une date d'effet.
  if (request.kind === 'TERMINATION' && requestIsOpen(request)) return 'En attente de confirmation';
  return { RECEIVED: 'Reçue', IN_PROGRESS: 'En cours', ACCEPTED: request.kind === 'TERMINATION' ? 'Confirmée' : 'Acceptée', REFUSED: 'Refusée', WITHDRAWN: 'Retirée', REVOKED: 'Service repris' }[request.status];
}

export type RequestStep = { key: 'received' | 'decision' | 'effect'; label: string; detail: string | null; state: 'done' | 'current' | 'upcoming' | 'stopped' };

/** Demande reçue, décision et fin effective restent trois faits distincts. Une régularisation n'a pas de fin effective à montrer. */
export function requestSteps(request: SubscriptionRequest, today: string): RequestStep[] {
  const steps: RequestStep[] = [{ key: 'received', label: 'Demande reçue', detail: civilLabel(request.requestedOn), state: 'done' }];
  const decidedOn = request.decidedAt ? instantDayLabel(request.decidedAt) : null;
  if (requestIsOpen(request)) steps.push({ key: 'decision', label: 'Décision de Drivy', detail: request.status === 'IN_PROGRESS' ? 'En cours' : 'En attente', state: 'current' });
  else if (request.status === 'ACCEPTED') steps.push({ key: 'decision', label: request.kind === 'TERMINATION' ? 'Confirmée par Drivy' : 'Acceptée par Drivy', detail: decidedOn, state: 'done' });
  else if (request.status === 'REFUSED') steps.push({ key: 'decision', label: 'Refusée par Drivy', detail: decidedOn, state: 'stopped' });
  else if (request.status === 'WITHDRAWN') steps.push({ key: 'decision', label: 'Demande retirée', detail: decidedOn, state: 'stopped' });
  else steps.push({ key: 'decision', label: 'Service repris', detail: decidedOn, state: 'stopped' });
  if (request.kind === 'REGULARIZATION') return steps;
  const effect = request.kind === 'TERMINATION' ? 'Fin effective' : 'Entrée en vigueur';
  if (request.status === 'ACCEPTED' && request.effectiveOn) {
    steps.push({ key: 'effect', label: effect, detail: civilLabel(request.effectiveOn), state: request.effectiveOn <= today ? 'done' : 'upcoming' });
  } else if (requestIsOpen(request)) steps.push({ key: 'effect', label: effect, detail: 'Non confirmée', state: 'upcoming' });
  return steps;
}

/** Ce que l'école peut demander maintenant ; l'API relit les mêmes règles, et une demande ne change aucun droit. */
export function availableActions(subscription: SchoolSubscription) {
  const openKind = (kind: SubscriptionRequestKind) => subscription.requests.some(item => item.kind === kind && requestIsOpen(item));
  const closed = subscription.lifecycle === 'TERMINATED' || subscription.terminationOn !== null;
  return {
    offerChange: subscription.hasClient && !closed && !openKind('OFFER_CHANGE'),
    termination: subscription.hasClient && !closed && !openKind('TERMINATION'),
    regularization: subscription.hasClient && !openKind('REGULARIZATION'),
  };
}

export type SubscriptionAttention = { tone: 'danger' | 'default'; title: string; detail: string; regularize: boolean };
/** Le fait le plus urgent seulement. La résiliation, l'essai terminé et le retard restent des états distincts. */
export function subscriptionAttention(subscription: SchoolSubscription): SubscriptionAttention | null {
  if (!subscription.hasClient) return null;
  if (subscription.lifecycle === 'TERMINATED') return { tone: 'danger', title: 'Abonnement résilié', regularize: true,
    detail: subscription.terminationOn ? `Fin effective le ${civilLabel(subscription.terminationOn)}.` : 'La résiliation a pris effet.' };
  if (subscription.lifecycle === 'TRIAL_EXPIRED') return { tone: 'danger', title: 'Essai terminé', regularize: true,
    detail: subscription.trial ? `Terminé le ${instantDayLabel(subscription.trial.endsAt)}.` : 'L’essai a pris fin.' };
  if (subscription.debt && subscription.debt.overdueCount > 0) {
    const count = subscription.debt.overdueCount;
    const since = subscription.debt.oldestOverdueDueOn ? ` depuis le ${civilLabel(subscription.debt.oldestOverdueDueOn)}` : '';
    return { tone: 'danger', title: count > 1 ? `${count} factures en retard` : 'Une facture en retard', regularize: true,
      detail: `${chfAmount(subscription.debt.overdueAmount)}${since}.` };
  }
  if (subscription.terminationOn) return { tone: 'default', title: 'Résiliation confirmée', regularize: false, detail: `Fin effective le ${civilLabel(subscription.terminationOn)}.` };
  return null;
}

export type RequestDraft = { kind: SubscriptionRequestKind; offerId: string | null; modules: readonly string[]; desiredOn: string; details: string };
export type RequestProblem = { field: 'choice' | 'desiredOn' | 'details'; message: string };
export type RequestBody = { kind: SubscriptionRequestKind; offerId?: string; modules?: string[]; desiredOn?: string; details?: string };

const maxAheadDays = 366;
const addDays = (value: string, days: number) => new Date(Date.parse(`${value}T00:00:00Z`) + days * 86_400_000).toISOString().slice(0, 10);

/** Le corps de la commande, ou la première zone à corriger. Seuls les champs propres au type de demande partent. */
export function requestBodyOf(draft: RequestDraft, today: string): { body: RequestBody } | { problem: RequestProblem } {
  const details = draft.details.trim();
  if (draft.kind === 'OFFER_CHANGE' && !draft.offerId && draft.modules.length === 0) return { problem: { field: 'choice', message: 'Choisissez une offre ou un module.' } };
  if (draft.kind === 'TERMINATION' && !draft.desiredOn) return { problem: { field: 'desiredOn', message: 'Indiquez la date souhaitée.' } };
  if (draft.kind !== 'REGULARIZATION' && draft.desiredOn) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(draft.desiredOn) || draft.desiredOn < today) return { problem: { field: 'desiredOn', message: 'Choisissez aujourd’hui ou une date à venir.' } };
    if (draft.desiredOn > addDays(today, maxAheadDays)) return { problem: { field: 'desiredOn', message: 'Choisissez une date dans les douze prochains mois.' } };
  }
  if (draft.kind === 'REGULARIZATION' && !details) return { problem: { field: 'details', message: 'Indiquez votre demande en quelques mots.' } };
  if (details && details.length < 3) return { problem: { field: 'details', message: 'Précisez en quelques mots.' } };
  if (details.length > 1000) return { problem: { field: 'details', message: 'Ce texte est limité à 1000 caractères.' } };
  return { body: {
    kind: draft.kind,
    ...(draft.kind === 'OFFER_CHANGE' && draft.offerId ? { offerId: draft.offerId } : {}),
    ...(draft.kind === 'OFFER_CHANGE' && draft.modules.length > 0 ? { modules: [...new Set(draft.modules)] } : {}),
    ...(draft.kind !== 'REGULARIZATION' && draft.desiredOn ? { desiredOn: draft.desiredOn } : {}),
    ...(details ? { details } : {}),
  } };
}

export const invoiceFileName = (invoice: Pick<SubscriptionInvoice, 'kind' | 'number'>) => `${invoice.kind === 'CREDIT_NOTE' ? 'avoir' : 'facture'}-${invoice.number}.pdf`;
