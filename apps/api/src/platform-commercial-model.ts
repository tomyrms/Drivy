import { z } from 'zod';
import { iso, type CommercialLifecycle, type CommercialRestriction, type EntitlementCoreRow, assignmentView } from './entitlements-model.js';

/**
 * Conditions commerciales, essai, début payant et demandes (R01-T04, #456). Modèle pur : bornes des saisies, calendrier mensuel et
 * projection du dossier commercial d'une fiche. Aucune facture n'est émise ici (#457) : l'échéancier rendu est prévisionnel.
 *
 * Montants : entiers en centimes de CHF. Jours commerciaux : chaînes `AAAA-MM-JJ`, jours civils Europe/Zurich (minuit à Zurich).
 */
export const currency = 'CHF' as const;
export const suspensionBillings = ['CONTINUE', 'PAUSE'] as const;
export const missingFields = ['OFFER', 'TERMS', 'INITIAL_AMOUNT', 'MONTHLY_AMOUNT', 'PAYMENT_TERM', 'SUSPENSION_BILLING'] as const;
export type MissingField = (typeof missingFields)[number];
export const termsStatuses = ['NONE', 'INCOMPLETE', 'COMPLETE'] as const;
export const termsPhases = ['IN_FORCE', 'SCHEDULED', 'ENDED', 'SUPERSEDED'] as const;
export type TermsPhase = (typeof termsPhases)[number];
export const trialKinds = ['START', 'EXTEND', 'END_EARLY'] as const;
export const trialPhases = ['SCHEDULED', 'RUNNING', 'ENDED'] as const;
export const requestKinds = ['OFFER_CHANGE', 'TERMINATION'] as const;
export type RequestKind = (typeof requestKinds)[number];
export const requestStatuses = ['RECEIVED', 'IN_PROGRESS', 'ACCEPTED', 'REFUSED', 'WITHDRAWN'] as const;
export type RequestStatus = (typeof requestStatuses)[number];
export const decisionStatuses = ['IN_PROGRESS', 'ACCEPTED', 'REFUSED', 'WITHDRAWN'] as const;
export const paidStartStatuses = ['ACTIVE', 'CANCELLED'] as const;

/** Plus lointaine date acceptée pour une échéance commerciale saisie (essai, début payant, effet) : une saison, pas une décennie. */
export const maxAheadDays = 366;
/** Plus longue durée d'un essai, cohérente avec la contrainte de la base. */
export const maxTrialDays = 400;
/** Nombre de périodes montrées dans l'échéancier prévisionnel. */
export const schedulePeriods = 12;

// --- Jours civils et calendrier mensuel -------------------------------------------------------------------------------------

const dayPattern = /^(\d{4})-(\d{2})-(\d{2})$/;
const parseDay = (day: string) => {
  const match = dayPattern.exec(day);
  if (!match) throw new RangeError(`Jour invalide : ${day}`);
  return { y: Number(match[1]), m: Number(match[2]), d: Number(match[3]) };
};
const pad = (value: number) => String(value).padStart(2, '0');
const format = (y: number, m: number, d: number) => `${String(y).padStart(4, '0')}-${pad(m)}-${pad(d)}`;
/** Nombre de jours du mois `m` (1 à 12) de l'année `y`, années bissextiles comprises. */
export const daysInMonth = (y: number, m: number) => new Date(Date.UTC(y, m, 0)).getUTCDate();
export const addDays = (day: string, days: number) => {
  const { y, m, d } = parseDay(day); const at = new Date(Date.UTC(y, m - 1, d + days));
  return format(at.getUTCFullYear(), at.getUTCMonth() + 1, at.getUTCDate());
};
/** Jour civil à Zurich de l'instant donné. */
export const zurichDay = (at: Date) =>
  new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Zurich', year: 'numeric', month: '2-digit', day: '2-digit' }).format(at);

/**
 * Début de la période d'indice `index` (0 = première) pour une ancre donnée (le jour du début payant). Le jour d'ancre est conservé tous
 * les mois ; s'il n'existe pas dans le mois, la période commence le dernier jour du mois, puis revient au jour d'ancre dès qu'il existe :
 * ancre 31 -> 31 janv., 28/29 févr., 31 mars, 30 avr. ; ancre 29 -> 29 févr. les années bissextiles, 28 sinon. Jamais de dérive.
 */
export function periodStart(anchor: string, index: number): string {
  if (!Number.isInteger(index) || index < 0) throw new RangeError('Indice de période invalide.');
  const a = parseDay(anchor); const total = a.m - 1 + index;
  const y = a.y + Math.floor(total / 12); const m = (total % 12) + 1;
  return format(y, m, Math.min(a.d, daysInMonth(y, m)));
}
const monthsBetween = (anchor: string, day: string) => { const a = parseDay(anchor); const b = parseDay(day); return (b.y - a.y) * 12 + (b.m - a.m); };
/** Indice de la période qui contient `day` ; -1 avant l'ancre. */
export function periodIndexOf(anchor: string, day: string): number {
  if (day < anchor) return -1;
  const index = monthsBetween(anchor, day);
  return periodStart(anchor, index) <= day ? index : index - 1;
}
export const isPeriodStart = (anchor: string, day: string) => day >= anchor && periodStart(anchor, monthsBetween(anchor, day)) === day;
/** Prochain début de période strictement après `day` (l'ancre elle-même tant qu'elle n'est pas atteinte). */
export function nextPeriodStart(anchor: string, day: string): string {
  if (day < anchor) return anchor;
  return periodStart(anchor, periodIndexOf(anchor, day) + 1);
}

// --- Saisies ----------------------------------------------------------------------------------------------------------------

const operationId = z.uuid();
const day = z.iso.date();
const reason = z.string().trim().min(3).max(500);
const cents = (max: number) => z.number().int().min(0).max(max);

/**
 * Nouvelle version des conditions : toutes les valeurs sont redonnées (une version est un tout). `null` = à compléter.
 * `effectiveFrom` absent : aujourd'hui avant le début payant, sinon le prochain début de période (aucun prorata).
 */
export const termsBody = z.object({
  operationId,
  initialAmount: cents(100_000_000).nullable(), initialDiscount: cents(100_000_000).default(0), initialDueOn: day.nullable().default(null),
  monthlyAmount: cents(10_000_000).nullable(), recurringDiscount: cents(10_000_000).default(0),
  recurringDiscountMonths: z.number().int().min(1).max(120).nullable().default(null),
  paymentTermDays: z.number().int().min(0).max(120).nullable(), suspensionBilling: z.enum(suspensionBillings).nullable(),
  effectiveFrom: day.optional(), exceptionReason: reason.optional(),
}).strict()
  .refine(body => body.initialAmount === null ? body.initialDiscount === 0 : body.initialDiscount <= body.initialAmount,
    { message: 'La remise initiale dépasse le montant initial.', path: ['initialDiscount'] })
  .refine(body => body.monthlyAmount === null ? body.recurringDiscount === 0 : body.recurringDiscount <= body.monthlyAmount,
    { message: 'La remise récurrente dépasse la mensualité.', path: ['recurringDiscount'] })
  .refine(body => body.recurringDiscount > 0 || body.recurringDiscountMonths === null,
    { message: 'Une durée de remise suppose une remise.', path: ['recurringDiscountMonths'] });
export type TermsBody = z.infer<typeof termsBody>;

/** Début d'essai : `startsAt` absent = l'activation effective de l'école si elle a eu lieu, sinon maintenant. La fin est toujours explicite. */
export const trialStartBody = z.object({ operationId, startsAt: z.iso.datetime().optional(), endsAt: z.iso.datetime() }).strict();
export const trialExtendBody = z.object({ operationId, endsAt: z.iso.datetime(), reason }).strict();
/** Fin anticipée : `endsAt` absent = maintenant. */
export const trialEndBody = z.object({ operationId, endsAt: z.iso.datetime().optional(), reason }).strict();
/** Le passage au payant exige une confirmation et une date explicites. */
export const paidStartBody = z.object({ operationId, startsOn: day, confirm: z.literal(true) }).strict();
export const paidStartCancelBody = z.object({ operationId, reason }).strict();
export const requestBody = z.object({
  operationId, kind: z.enum(requestKinds), requestedOn: day, requestedOfferId: z.uuid().optional(), desiredOn: day.optional(),
  details: z.string().trim().min(3).max(1000).optional(),
}).strict().refine(body => body.kind === 'OFFER_CHANGE' || body.requestedOfferId === undefined,
  { message: 'Seul un changement d’offre désigne une offre.', path: ['requestedOfferId'] });
/** Décision : une acceptation porte toujours sa date d'effet ; un refus, toujours sa réponse. */
export const decisionBody = z.object({
  operationId, status: z.enum(decisionStatuses), response: z.string().trim().min(3).max(1000).optional(), effectiveOn: day.optional(),
  offerId: z.uuid().optional(),
}).strict()
  .refine(body => body.status !== 'ACCEPTED' || body.effectiveOn !== undefined, { message: 'Une acceptation porte sa date d’effet.', path: ['effectiveOn'] })
  .refine(body => body.status === 'ACCEPTED' || body.effectiveOn === undefined, { message: 'Seule une acceptation porte une date d’effet.', path: ['effectiveOn'] })
  .refine(body => body.status !== 'REFUSED' || body.response !== undefined, { message: 'Un refus porte sa réponse.', path: ['response'] })
  .refine(body => body.status === 'ACCEPTED' || body.offerId === undefined, { message: 'Seule une acceptation désigne une offre.', path: ['offerId'] });
export const commercialQuery = z.object({}).strict();

// --- Lignes de la base et projection -----------------------------------------------------------------------------------------

export interface TermsRow {
  id: string; sequence: number; currency: string; initialAmount: number | null; initialDiscount: number; initialDueOn: string | null;
  monthlyAmount: number | null; recurringDiscount: number; recurringDiscountMonths: number | null; paymentTermDays: number | null;
  suspensionBilling: (typeof suspensionBillings)[number] | null; effectiveFrom: string; exceptionReason: string | null; createdAt: string;
  createdByName: string | null;
}
export interface TrialChangeRow {
  id: string; sequence: number; kind: (typeof trialKinds)[number]; startsAt: string; endsAt: string; reason: string | null; createdAt: string;
  createdByName: string | null;
}
export interface PaidStartRow {
  id: string; startsOn: string; termsId: string; status: (typeof paidStartStatuses)[number]; confirmedAt: string; confirmedByName: string | null;
  cancelledAt: string | null; cancelledByName: string | null; cancelReason: string | null;
}
export interface RequestRow {
  id: string; kind: RequestKind; status: RequestStatus; requestedOn: string; requestedOfferId: string | null; requestedOfferName: string | null;
  desiredOn: string | null; details: string | null; response: string | null; effectiveOn: string | null; assignmentId: string | null;
  decidedAt: string | null; decidedByName: string | null; version: number; createdAt: string; createdByName: string | null; updatedAt: string;
}
/** Ligne rendue par `drivy.platform_client_commercial`. */
export interface CommercialRow {
  core: EntitlementCoreRow; today: string; termsInForce: string | null; missing: MissingField[];
  milestones: { codeIssuedAt: string | null; schoolCreatedAt: string | null; schoolLinkedAt: string | null; activatedAt: string | null;
    trialStartsAt: string | null; paidStartsOn: string | null };
  terms: TermsRow[]; trialChanges: TrialChangeRow[]; paidStarts: PaidStartRow[]; requests: RequestRow[]; version: number;
}

/** Version de conditions applicable un jour donné : plus grand numéro dont la date d'effet est atteinte. */
export const termsAt = <T extends Pick<TermsRow, 'sequence' | 'effectiveFrom'>>(terms: readonly T[], on: string): T | null =>
  terms.filter(item => item.effectiveFrom <= on).reduce<T | null>((best, item) => (!best || item.sequence > best.sequence ? item : best), null);

/** Phase d'une version : remplacée avant d'avoir servi, programmée, en vigueur ou terminée. */
export function termsPhase(terms: readonly Pick<TermsRow, 'id' | 'sequence' | 'effectiveFrom'>[], item: Pick<TermsRow, 'id' | 'sequence' | 'effectiveFrom'>, today: string): TermsPhase {
  if (terms.some(other => other.sequence > item.sequence && other.effectiveFrom <= item.effectiveFrom)) return 'SUPERSEDED';
  if (item.effectiveFrom > today) return 'SCHEDULED';
  return termsAt(terms, today)?.id === item.id ? 'IN_FORCE' : 'ENDED';
}

const net = (amount: number, discount: number) => Math.max(0, amount - discount);

/**
 * Échéancier prévisionnel : montant initial (une seule fois, à sa date, par défaut au début payant) puis périodes mensuelles depuis la période
 * en cours. Rien sans début payant confirmé : un essai, même expiré, ne crée jamais de montant. Une résiliation confirmée arrête les périodes
 * qui commenceraient à sa date ou après. Le montant d'une période est celui de la version applicable à son début ; une remise récurrente dure
 * `recurringDiscountMonths` périodes à compter de la première période de sa version. Aucun prorata : une version datée hors début de période
 * (exception motivée) se régularise par les documents (#457).
 */
export function billingSchedule(args: { paidStartsOn: string | null; terminationOn: string | null; terms: readonly TermsRow[]; today: string; count?: number }) {
  const { paidStartsOn: anchor, terminationOn, terms, today } = args; const count = args.count ?? schedulePeriods;
  if (!anchor) return { initial: null, periods: [] as SchedulePeriod[] };
  const atStart = termsAt(terms, anchor);
  const initial = atStart && atStart.initialAmount !== null ? {
    dueOn: atStart.initialDueOn ?? anchor, amount: atStart.initialAmount, discount: atStart.initialDiscount,
    net: net(atStart.initialAmount, atStart.initialDiscount), termsSequence: atStart.sequence,
  } : null;
  const periods: SchedulePeriod[] = [];
  for (let index = Math.max(0, periodIndexOf(anchor, today)); periods.length < count; index += 1) {
    const startsOn = periodStart(anchor, index);
    if (terminationOn && startsOn >= terminationOn) break;
    const endsOn = addDays(periodStart(anchor, index + 1), -1);
    const version = termsAt(terms, startsOn);
    if (!version || version.monthlyAmount === null) {
      periods.push({ index, startsOn, endsOn, amount: null, discount: 0, net: null, termsSequence: version?.sequence ?? null });
      continue;
    }
    const first = version.effectiveFrom <= anchor ? 0 : periodIndexOf(anchor, addDays(version.effectiveFrom, -1)) + 1;
    const discounted = version.recurringDiscount > 0 && (version.recurringDiscountMonths === null || index - first < version.recurringDiscountMonths);
    const discount = discounted ? version.recurringDiscount : 0;
    periods.push({ index, startsOn, endsOn, amount: version.monthlyAmount, discount, net: net(version.monthlyAmount, discount), termsSequence: version.sequence });
  }
  return { initial, periods };
}
export interface SchedulePeriod {
  index: number; startsOn: string; endsOn: string; amount: number | null; discount: number; net: number | null; termsSequence: number | null;
}

const termsView = (item: TermsRow, phase: TermsPhase) => ({
  id: item.id, sequence: item.sequence, currency: item.currency, initialAmount: item.initialAmount, initialDiscount: item.initialDiscount,
  initialDueOn: item.initialDueOn, monthlyAmount: item.monthlyAmount, recurringDiscount: item.recurringDiscount,
  recurringDiscountMonths: item.recurringDiscountMonths, paymentTermDays: item.paymentTermDays, suspensionBilling: item.suspensionBilling,
  effectiveFrom: item.effectiveFrom, exceptionReason: item.exceptionReason, createdAt: iso(item.createdAt)!, createdByName: item.createdByName, phase,
});

/**
 * Dossier commercial d'une fiche vu par l'équipe. `billable` n'est vrai qu'avec un début payant confirmé, des conditions complètes et sans
 * résiliation effective : c'est la seule porte qu'un traitement facturant (#457) a le droit d'ouvrir.
 */
export function commercialDetailView(row: CommercialRow, now: Date) {
  const { core, today } = row;
  const terms = [...row.terms].sort((a, b) => b.sequence - a.sequence);
  const versions = terms.map(item => termsView(item, termsPhase(terms, item, today)));
  const inForce = versions.find(item => item.phase === 'IN_FORCE') ?? null;
  const scheduled = [...versions].reverse().find(item => item.phase === 'SCHEDULED') ?? null;
  const missing = [...row.missing];
  const status = terms.length === 0 ? 'NONE' : missing.length ? 'INCOMPLETE' : 'COMPLETE';
  const trialRow = row.trialChanges.reduce<TrialChangeRow | null>((best, item) => (!best || item.sequence > best.sequence ? item : best), null);
  const paid = row.paidStarts.find(item => item.status === 'ACTIVE') ?? null;
  const termination = row.requests.find(item => item.kind === 'TERMINATION' && item.status === 'ACCEPTED') ?? null;
  const schedule = billingSchedule({ paidStartsOn: paid?.startsOn ?? null, terminationOn: termination?.effectiveOn ?? null, terms, today });
  const billable = paid !== null && missing.length === 0 && core.lifecycle !== 'TERMINATED';
  const anchor = paid?.startsOn ?? null;
  const nextPeriod = anchor ? nextPeriodStart(anchor, today) : null;
  return {
    state: core.state, lifecycle: core.lifecycle, restriction: restrictionView(core.restriction),
    offer: assignmentView(core.assignment), scheduledOffer: assignmentView(core.scheduled),
    milestones: {
      codeIssuedAt: iso(row.milestones.codeIssuedAt), schoolCreatedAt: iso(row.milestones.schoolCreatedAt), schoolLinkedAt: iso(row.milestones.schoolLinkedAt),
      activatedAt: iso(row.milestones.activatedAt), trialStartsAt: iso(row.milestones.trialStartsAt), paidStartsOn: row.milestones.paidStartsOn,
    },
    /** Départ d'essai proposé : l'activation effective de l'école si elle a eu lieu, sinon rien (l'opérateur choisit). */
    proposedTrialStart: iso(row.milestones.activatedAt),
    trial: trialRow ? {
      startsAt: iso(trialRow.startsAt)!, endsAt: iso(trialRow.endsAt)!,
      phase: (new Date(trialRow.startsAt) > now ? 'SCHEDULED' : new Date(trialRow.endsAt) > now ? 'RUNNING' : 'ENDED') as (typeof trialPhases)[number],
    } : null,
    trialChanges: [...row.trialChanges].sort((a, b) => b.sequence - a.sequence).map(item => ({
      id: item.id, sequence: item.sequence, kind: item.kind, startsAt: iso(item.startsAt)!, endsAt: iso(item.endsAt)!, reason: item.reason,
      createdAt: iso(item.createdAt)!, createdByName: item.createdByName,
    })),
    terms: { status: status as (typeof termsStatuses)[number], missing, currency, inForce, scheduled, versions },
    paidStart: paid ? {
      id: paid.id, startsOn: paid.startsOn, started: paid.startsOn <= today, termsSequence: terms.find(item => item.id === paid.termsId)?.sequence ?? null,
      confirmedAt: iso(paid.confirmedAt)!, confirmedByName: paid.confirmedByName,
    } : null,
    paidStarts: row.paidStarts.map(item => ({
      id: item.id, startsOn: item.startsOn, status: item.status, confirmedAt: iso(item.confirmedAt)!, confirmedByName: item.confirmedByName,
      cancelledAt: iso(item.cancelledAt), cancelledByName: item.cancelledByName, cancelReason: item.cancelReason,
    })),
    termination: termination ? { requestId: termination.id, effectiveOn: termination.effectiveOn!, decidedAt: iso(termination.decidedAt)! } : null,
    requests: row.requests.map(requestView),
    billable, nextPeriodStart: nextPeriod && (!termination || nextPeriod < termination.effectiveOn!) ? nextPeriod : null,
    schedule, today, entitlementVersion: core.version, nextChangeAt: iso(core.nextChangeAt), version: row.version,
  };
}
export type CommercialDetail = ReturnType<typeof commercialDetailView>;

export const restrictionView = (value: CommercialRestriction | null) => value ? { reason: value.reason, closes: [...value.closes] } : null;

export const requestView = (item: RequestRow) => ({
  id: item.id, kind: item.kind, status: item.status, requestedOn: item.requestedOn, requestedOfferId: item.requestedOfferId,
  requestedOfferName: item.requestedOfferName, desiredOn: item.desiredOn, details: item.details, response: item.response, effectiveOn: item.effectiveOn,
  assignmentId: item.assignmentId, decidedAt: iso(item.decidedAt), decidedByName: item.decidedByName, version: item.version,
  createdAt: iso(item.createdAt)!, createdByName: item.createdByName, updatedAt: iso(item.updatedAt)!,
});

/** Statut d'arrivée autorisé pour une demande dans un statut donné ; une décision (acceptée, refusée, retirée) est définitive. */
export const requestTransitionAllowed = (from: RequestStatus, to: (typeof decisionStatuses)[number]) =>
  (from === 'RECEIVED' || from === 'IN_PROGRESS') && !(from === 'IN_PROGRESS' && to === 'IN_PROGRESS');

/** Cycle de vie : texte de marche à suivre montré à l'école quand de nouveaux usages sont fermés. */
export const lifecycleBlocks = (lifecycle: CommercialLifecycle) => lifecycle === 'TRIAL_EXPIRED' || lifecycle === 'TERMINATED';
