import { z } from 'zod';
import { iso, restrictionCauses } from './entitlements-model.js';

/**
 * Relances des impayés, alertes commerciales, suspension et réactivation d'une école (R01-T09, #461). Modèle pur, sans accès à la base.
 *
 * Toutes les décisions sont calculées par la base (`drivy.platform_dunning_*`) : la plus ancienne somme encore due, son échéance, le délai
 * applicable (politique ou exception), l'avertissement, la date de suspension et la levée après règlement confirmé. Ce module ne fait que
 * décrire les formes rendues et valider les corps des commandes. Une suspension ne touche jamais `school.status` : elle reste distincte de
 * l'archivage, de la fin d'essai et de la résiliation.
 */
export const dunningExceptionKinds = ['DELAY', 'HOLD'] as const;
export type DunningExceptionKind = (typeof dunningExceptionKinds)[number];
export const dunningExceptionStatuses = ['ACTIVE', 'REVOKED', 'EXPIRED'] as const;
export const suspensionOrigins = ['AUTOMATIC', 'OPERATOR'] as const;
export const suspensionStatuses = ['ACTIVE', 'LIFTED'] as const;
export const suspensionLiftCauses = ['PAYMENT_CONFIRMED', 'OPERATOR'] as const;
export const dunningStepKinds = ['REMINDER', 'WARNING'] as const;
export const dunningStepStatuses = ['RECORDED', 'SKIPPED'] as const;
/** Remise d'une étape, du fait le plus fort au plus faible. Seuls READ, SENT et CONFIRMED autorisent une suspension automatique. */
export const dunningDeliveries = ['SKIPPED', 'CONFIRMED', 'NO_RECIPIENT', 'READ', 'SENT', 'PENDING', 'FAILED'] as const;
export type DunningDelivery = (typeof dunningDeliveries)[number];
export const commercialAlertKinds = ['TRIAL_ENDING', 'TRIAL_ENDED', 'NEW_OVERDUE', 'DELIVERY_FAILED', 'SUSPENSION_UPCOMING', 'SUSPENDED'] as const;
export type CommercialAlertKind = (typeof commercialAlertKinds)[number];

/** Ligne rendue par `drivy.platform_dunning_policy_read`. */
export interface DunningPolicyRow {
  remindersEnabled: boolean; autoSuspend: boolean; reminderDays: number[]; suspensionMonths: number; warningDays: number; trialAlertDays: number;
  version: number; updatedAt: string; updatedByName: string | null;
}
/** État recalculé d'une fiche (`drivy.platform_dunning_state`). */
export interface DunningStateRow {
  overdue: boolean; hold: boolean; exceptionId: string | null; invoiceId: string | null; invoiceNumber: string | null; dueOn: string | null;
  balance: number | null; months: number | null; baseOn: string | null; cycle: number; warningStepId: string | null; warningDelivery: DunningDelivery | null;
  warningOn: string | null; suspensionOn: string | null; suspensionDue: boolean; daysLate: number; nextReminderOn: string | null;
}
export interface DunningExceptionRow {
  id: string; kind: DunningExceptionKind; suspensionMonths: number | null; endsOn: string; reason: string; status: (typeof dunningExceptionStatuses)[number];
  createdAt: string; createdByName: string | null; revokedAt: string | null; revokeReason: string | null;
}
export interface SuspensionRow {
  id: string; cause: (typeof restrictionCauses)[number]; origin: (typeof suspensionOrigins)[number]; status: (typeof suspensionStatuses)[number];
  startsOn: string; invoiceNumber: string | null; dueOn: string | null; months: number | null; reason: string | null; createdByName: string | null;
  liftedOn: string | null; liftCause: (typeof suspensionLiftCauses)[number] | null; liftReason: string | null; liftedByName: string | null;
}
export interface DunningStepRow {
  id: string; kind: (typeof dunningStepKinds)[number]; invoiceNumber: string; dueOn: string; offsetDays: number; plannedOn: string; doneOn: string;
  status: (typeof dunningStepStatuses)[number]; suspensionOn: string | null; recipientCount: number; delivery: DunningDelivery;
  confirmedAt: string | null; confirmedByName: string | null; confirmReason: string | null;
}
/** Dossier de relance d'une fiche (`drivy.platform_dunning_view`) ; NULL côté base si la fiche n'existe pas. */
export interface DunningViewRow {
  today: string; state: DunningStateRow; recipients: number; exceptions: DunningExceptionRow[]; suspensions: SuspensionRow[]; steps: DunningStepRow[]; version: number;
}
export interface CommercialAlertRow {
  id: string; clientId: string; clientName: string; kind: CommercialAlertKind; invoiceNumber: string | null; onDate: string | null; openedAt: string;
}
/** Résultat d'un passage (`drivy.platform_dunning_run_at`) : compteurs seulement. */
export type DunningRunRow = { skipped: true } | {
  skipped: false; today: string; clients: number; reminders: number; warnings: number; suspended: number; lifted: number; failed: number;
};

/** Horodatages de la base (`+00:00`, microsecondes) ramenés au format ISO du contrat. */
export const policyView = (row: DunningPolicyRow) => ({
  remindersEnabled: row.remindersEnabled, autoSuspend: row.autoSuspend, reminderDays: [...row.reminderDays], suspensionMonths: row.suspensionMonths,
  warningDays: row.warningDays, trialAlertDays: row.trialAlertDays, version: row.version, updatedAt: iso(row.updatedAt)!, updatedByName: row.updatedByName,
});
export type DunningPolicy = ReturnType<typeof policyView>;

export const dunningView = (row: DunningViewRow) => ({
  today: row.today, state: { ...row.state }, recipients: row.recipients,
  exceptions: row.exceptions.map(item => ({ ...item, createdAt: iso(item.createdAt)!, revokedAt: iso(item.revokedAt) })),
  suspensions: row.suspensions.map(item => ({ ...item })),
  steps: row.steps.map(item => ({ ...item, confirmedAt: iso(item.confirmedAt) })),
  version: row.version,
});
export type DunningView = ReturnType<typeof dunningView>;

export const alertView = (row: CommercialAlertRow) => ({ ...row, openedAt: iso(row.openedAt)! });
export type CommercialAlert = ReturnType<typeof alertView>;

// --- Corps des commandes --------------------------------------------------------------------------------------------------------------------
const operationId = z.uuid();
const reason = z.string().trim().min(3).max(500);

/** Politique globale. Une suspension automatique exige les rappels ; les jours de rappel sont strictement croissants. */
export const policyBody = z.object({
  operationId, remindersEnabled: z.boolean(), autoSuspend: z.boolean(),
  reminderDays: z.array(z.number().int().min(1).max(365)).min(1).max(6),
  suspensionMonths: z.number().int().min(1).max(12), warningDays: z.number().int().min(3).max(28), trialAlertDays: z.number().int().min(1).max(30),
}).strict()
  .refine(body => !body.autoSuspend || body.remindersEnabled, { message: 'La suspension automatique exige les rappels.', path: ['autoSuspend'] })
  .refine(body => body.reminderDays.every((value, index) => index === 0 || value > body.reminderDays[index - 1]!),
    { message: 'Les jours de rappel doivent être croissants et distincts.', path: ['reminderDays'] });
export type PolicyBody = z.infer<typeof policyBody>;

/** Exception temporaire motivée : DELAY change le délai de suspension (en mois), HOLD suspend relances et suspension automatique. */
export const exceptionBody = z.object({
  operationId, kind: z.enum(dunningExceptionKinds), suspensionMonths: z.number().int().min(1).max(24).optional(), endsOn: z.iso.date(), reason,
}).strict().refine(body => (body.kind === 'DELAY') === (body.suspensionMonths !== undefined),
  { message: 'Un délai exige un nombre de mois ; un arrêt n’en prend pas.', path: ['suspensionMonths'] });
export type ExceptionBody = z.infer<typeof exceptionBody>;

/** Suspension décidée par un opérateur : pour impayé (dette arrivée à son délai) ou pour une autre cause (MANUAL), toujours motivée. */
export const suspensionBody = z.object({ operationId, cause: z.enum(restrictionCauses), reason }).strict();
export const reasonBody = z.object({ operationId, reason }).strict();
export const commandBody = z.object({ operationId }).strict();
