import { z } from 'zod';

/**
 * Extension exécutable du dépôt (R01-T10, #462) : tableau de bord commercial de l'équipe Drivy.
 * L'OpenAPI canonique 3.11.0 reste immuable ; `contracts/platform-dashboard.json` est la projection de ces schémas.
 * Montants en centimes de CHF ; jours en Europe/Zurich. Aucune donnée d'élève, de trajet ni de message.
 */
const day = z.iso.date();
const cents = z.number().int().min(0);
const count = z.number().int().min(0);

export const dashboardSituations = ['PREPARATION', 'TRIAL', 'TRIAL_EXPIRED', 'ACTIVE', 'SUSPENDED', 'TERMINATED', 'ARCHIVED'] as const;
export const dashboardPreparations = ['AWAITING_SCHOOL', 'IN_PREPARATION', 'ACTIVE', 'ARCHIVED'] as const;
export const dashboardActionKinds = ['SUSPENSION_UPCOMING', 'OVERDUE', 'DELIVERY_FAILED', 'REQUEST_OPEN', 'TERMS_MISSING', 'OPENING_INCOMPLETE'] as const;
export const dashboardMonthlyStates = ['NONE', 'DEFINED', 'MISSING', 'PAUSED'] as const;

export const dashboardActionSchema = z.object({
  kind: z.enum(dashboardActionKinds), onDate: day.nullable(), amount: cents.nullable(), count: z.number().int().min(1),
  codes: z.array(z.string().min(1).max(40)).max(10),
}).strict();

export const dashboardClientSchema = z.object({
  id: z.uuid(), name: z.string(), situation: z.enum(dashboardSituations), preparation: z.enum(dashboardPreparations),
  invoiced: cents, credited: cents, collected: cents, regularized: cents, outstanding: cents, overdue: cents,
  monthly: cents.nullable(), monthlyState: z.enum(dashboardMonthlyStates), nextRenewalOn: day.nullable(), trialLastDay: day.nullable(),
  terminationOn: day.nullable(), actions: z.array(dashboardActionSchema).max(8),
}).strict();

export const dashboardTotalsSchema = z.object({
  clients: count, invoiced: cents, invoiceCount: count, credited: cents, creditCount: count, collected: cents, paymentCount: count, regularized: cents,
  outstanding: cents, overdue: cents, overdueInvoices: count, monthly: cents, monthlyClients: count, monthlyMissing: count, monthlyPaused: count,
  renewalsSoon: count, trialsEndingSoon: count, withActions: count,
}).strict();

export const dashboardSchema = z.object({
  today: day, from: day, to: day, horizonOn: day, autoSuspend: z.boolean(), totals: dashboardTotalsSchema,
  situations: z.object(Object.fromEntries(dashboardSituations.map(key => [key, count])) as Record<(typeof dashboardSituations)[number], typeof count>).strict(),
  preparations: z.object(Object.fromEntries(dashboardPreparations.map(key => [key, count])) as Record<(typeof dashboardPreparations)[number], typeof count>).strict(),
  truncated: z.boolean(), clients: z.array(dashboardClientSchema).max(500),
}).strict();

export const dashboardEnvelope = z.object({ data: dashboardSchema, requestId: z.uuid(), serverTime: z.iso.datetime() }).strict();
