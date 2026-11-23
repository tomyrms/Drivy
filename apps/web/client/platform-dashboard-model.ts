import { z } from 'zod';

/** Tableau de bord commercial (R01-T10) : la forme relue depuis l'API. Aucun total n'est calculé ici, sauf la somme des lignes affichées. */
const day = z.iso.date();
const cents = z.number().int().min(0);
const count = z.number().int().min(0);

export const dashboardSituations = ['PREPARATION', 'TRIAL', 'TRIAL_EXPIRED', 'ACTIVE', 'SUSPENDED', 'TERMINATED', 'ARCHIVED'] as const;
export type DashboardSituation = (typeof dashboardSituations)[number];
const preparations = ['AWAITING_SCHOOL', 'IN_PREPARATION', 'ACTIVE', 'ARCHIVED'] as const;
const actionKinds = ['SUSPENSION_UPCOMING', 'OVERDUE', 'DELIVERY_FAILED', 'REQUEST_OPEN', 'TERMS_MISSING', 'OPENING_INCOMPLETE'] as const;

const action = z.object({ kind: z.enum(actionKinds), onDate: day.nullable(), amount: cents.nullable(), count: z.number().int().min(1), codes: z.array(z.string()) });
const client = z.object({
  id: z.uuid(), name: z.string(), situation: z.enum(dashboardSituations), preparation: z.enum(preparations), invoiced: cents, credited: cents, collected: cents,
  regularized: cents, outstanding: cents, overdue: cents, monthly: cents.nullable(), monthlyState: z.enum(['NONE', 'DEFINED', 'MISSING', 'PAUSED']),
  nextRenewalOn: day.nullable(), trialLastDay: day.nullable(), terminationOn: day.nullable(), actions: z.array(action),
});
const dashboard = z.object({
  today: day, from: day, to: day, horizonOn: day, autoSuspend: z.boolean(),
  totals: z.object({
    clients: count, invoiced: cents, invoiceCount: count, credited: cents, creditCount: count, collected: cents, paymentCount: count, regularized: cents,
    outstanding: cents, overdue: cents, overdueInvoices: count, monthly: cents, monthlyClients: count, monthlyMissing: count, monthlyPaused: count,
    renewalsSoon: count, trialsEndingSoon: count, withActions: count,
  }),
  situations: z.record(z.enum(dashboardSituations), count),
  preparations: z.record(z.enum(preparations), count),
  truncated: z.boolean(), clients: z.array(client),
});
export const platformDashboardResult = z.object({ data: dashboard, serverTime: z.iso.datetime() });
export type PlatformDashboard = z.infer<typeof dashboard>;
export type PlatformDashboardClient = z.infer<typeof client>;
export type PlatformDashboardAction = z.infer<typeof action>;

export const situationLabel = (value: DashboardSituation) => ({
  PREPARATION: 'Préparation', TRIAL: 'Essai', TRIAL_EXPIRED: 'Essai terminé', ACTIVE: 'Actives', SUSPENDED: 'Suspendues', TERMINATED: 'Résiliées', ARCHIVED: 'Archivées',
})[value];
export const actionLabel = (item: PlatformDashboardAction) => {
  if (item.kind === 'REQUEST_OPEN') return ({ OFFER_CHANGE: 'Changement d’offre demandé', TERMINATION: 'Résiliation demandée', REGULARIZATION: 'Régularisation demandée' } as Record<string, string>)[item.codes[0] ?? ''] ?? 'Demande à traiter';
  if (item.kind === 'OPENING_INCOMPLETE') return item.codes[0] === 'AWAITING_SCHOOL' ? 'École à ouvrir' : 'Ouverture inachevée';
  return ({ SUSPENSION_UPCOMING: 'Suspension à venir', OVERDUE: item.count > 1 ? `${item.count} factures en retard` : 'Facture en retard',
    DELIVERY_FAILED: item.count > 1 ? `${item.count} envois en échec` : 'Envoi en échec', TERMS_MISSING: 'Conditions à compléter' })[item.kind];
};

export type DashboardPreset = 'month' | 'previous' | 'quarter' | 'year';
export const dashboardPresets: { value: DashboardPreset; label: string }[] = [
  { value: 'month', label: 'Ce mois' }, { value: 'previous', label: 'Mois dernier' }, { value: 'quarter', label: '3 mois' }, { value: 'year', label: 'Cette année' },
];
const iso = (year: number, month: number, date: number) => new Date(Date.UTC(year, month, date)).toISOString().slice(0, 10);
/** Bornes d'un raccourci à partir du jour de Zurich ; l'API relit et borne la période. */
export function presetRange(preset: DashboardPreset, now = new Date()) {
  const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Zurich', year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
  const [year, month] = today.split('-').map(Number) as [number, number, number];
  if (preset === 'previous') return { from: iso(year, month - 2, 1), to: iso(year, month - 1, 0) };
  if (preset === 'quarter') return { from: iso(year, month - 3, 1), to: today };
  if (preset === 'year') return { from: iso(year, 0, 1), to: today };
  return { from: iso(year, month - 1, 1), to: today };
}
