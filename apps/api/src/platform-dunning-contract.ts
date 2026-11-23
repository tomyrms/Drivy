import { z } from 'zod';
import { restrictionCauses } from './entitlements-model.js';
import {
  commercialAlertKinds, dunningDeliveries, dunningExceptionKinds, dunningExceptionStatuses, dunningStepKinds, dunningStepStatuses, suspensionLiftCauses,
  suspensionOrigins, suspensionStatuses,
} from './platform-dunning-model.js';

/**
 * Extension exécutable du dépôt (R01-T09, #461) : politique de relance, dossier de relance d'une fiche, exceptions, suspensions, alertes.
 * L'OpenAPI canonique 3.11.0 reste immuable. Ces schémas décrivent exactement ce que `src/platform-dunning.ts` renvoie ;
 * `contracts/platform-dunning.json` en est la projection. Montants en centimes de CHF ; jours en Europe/Zurich.
 */
const timestamp = z.iso.datetime();
const day = z.iso.date();
const cents = z.number().int().min(0);
const count = z.number().int().min(0);
const text = z.string().min(1).max(500);

export const dunningPolicySchema = z.object({
  remindersEnabled: z.boolean(), autoSuspend: z.boolean(), reminderDays: z.array(z.number().int().min(1).max(365)).min(1).max(6),
  suspensionMonths: z.number().int().min(1).max(12), warningDays: z.number().int().min(3).max(28), trialAlertDays: z.number().int().min(1).max(30),
  version: z.number().int().min(1), updatedAt: timestamp, updatedByName: z.string().nullable(),
}).strict();

export const dunningStateSchema = z.object({
  overdue: z.boolean(), hold: z.boolean(), exceptionId: z.uuid().nullable(), invoiceId: z.uuid().nullable(), invoiceNumber: z.string().nullable(),
  dueOn: day.nullable(), balance: cents.nullable(), months: z.number().int().min(1).max(24).nullable(), baseOn: day.nullable(), cycle: count,
  warningStepId: z.uuid().nullable(), warningDelivery: z.enum(dunningDeliveries).nullable(), warningOn: day.nullable(), suspensionOn: day.nullable(),
  suspensionDue: z.boolean(), daysLate: count, nextReminderOn: day.nullable(),
}).strict();

export const dunningExceptionSchema = z.object({
  id: z.uuid(), kind: z.enum(dunningExceptionKinds), suspensionMonths: z.number().int().min(1).max(24).nullable(), endsOn: day, reason: text,
  status: z.enum(dunningExceptionStatuses), createdAt: timestamp, createdByName: z.string().nullable(), revokedAt: timestamp.nullable(),
  revokeReason: text.nullable(),
}).strict();

export const suspensionSchema = z.object({
  id: z.uuid(), cause: z.enum(restrictionCauses), origin: z.enum(suspensionOrigins), status: z.enum(suspensionStatuses), startsOn: day,
  invoiceNumber: z.string().nullable(), dueOn: day.nullable(), months: z.number().int().min(1).max(24).nullable(), reason: text.nullable(),
  createdByName: z.string().nullable(), liftedOn: day.nullable(), liftCause: z.enum(suspensionLiftCauses).nullable(), liftReason: text.nullable(),
  liftedByName: z.string().nullable(),
}).strict();

export const dunningStepSchema = z.object({
  id: z.uuid(), kind: z.enum(dunningStepKinds), invoiceNumber: z.string(), dueOn: day, offsetDays: count, plannedOn: day, doneOn: day,
  status: z.enum(dunningStepStatuses), suspensionOn: day.nullable(), recipientCount: count, delivery: z.enum(dunningDeliveries),
  confirmedAt: timestamp.nullable(), confirmedByName: z.string().nullable(), confirmReason: text.nullable(),
}).strict();

export const dunningViewSchema = z.object({
  today: day, state: dunningStateSchema, recipients: count, exceptions: z.array(dunningExceptionSchema).max(20),
  suspensions: z.array(suspensionSchema).max(20), steps: z.array(dunningStepSchema).max(40), version: z.number().int().min(1),
}).strict();

export const commercialAlertSchema = z.object({
  id: z.uuid(), clientId: z.uuid(), clientName: z.string(), kind: z.enum(commercialAlertKinds), invoiceNumber: z.string().nullable(),
  onDate: day.nullable(), openedAt: timestamp,
}).strict();
export const commercialAlertsSchema = z.object({ items: z.array(commercialAlertSchema).max(100) }).strict();

export const dunningRunSchema = z.union([
  z.object({ skipped: z.literal(true) }).strict(),
  z.object({
    skipped: z.literal(false), today: day, clients: count, reminders: count, warnings: count, suspended: count, lifted: count, failed: count,
  }).strict(),
]);

const envelope = <T extends z.ZodType>(data: T) => z.object({ data, requestId: z.uuid(), serverTime: timestamp }).strict();
export const dunningPolicyEnvelope = envelope(dunningPolicySchema);
export const dunningViewEnvelope = envelope(dunningViewSchema);
export const commercialAlertsEnvelope = envelope(commercialAlertsSchema);
export const dunningRunEnvelope = envelope(dunningRunSchema);
