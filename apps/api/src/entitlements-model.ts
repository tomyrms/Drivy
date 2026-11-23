/**
 * Droits commerciaux aux modules (R01-T03, #455). Modèle pur, sans accès à la base : catalogue, classes d'action, projections.
 *
 * Trois notions restent distinctes (R03) : les droits commerciaux de Drivy (ce module), les choix d'activation de l'école
 * (`school.modules`, jamais une source de droit commercial) et les permissions des personnes. Un réglage de l'école n'accorde jamais un module.
 *
 * Le catalogue ci-dessous est copié de la table `drivy.platform_module` (amorcée par la migration 20261115) : un test d'intégration
 * vérifie qu'ils ne divergent pas. Seuls les modules réellement livrés par le code y figurent.
 */
export const moduleCodes = ['MESSAGING', 'COLLECTIVE_COURSES'] as const;
export type ModuleCode = (typeof moduleCodes)[number];
export const isModuleCode = (value: unknown): value is ModuleCode => typeof value === 'string' && (moduleCodes as readonly string[]).includes(value);

/**
 * États commerciaux dérivés des attributions. NOT_CONFIGURED = aucune offre en vigueur : le périmètre de l'école est celui d'avant ce lot,
 * sans aucune restriction. #456 ajoutera ses propres états (essai, impayé, suspension) sans changer cette définition.
 */
export const commercialStates = ['NOT_CONFIGURED', 'OFFER_ACTIVE'] as const;
export type CommercialState = (typeof commercialStates)[number];

/**
 * Cycle commercial (R01-T04, #456), distinct de `state` qui garde son sens de R01-T03 (offre en vigueur ou non). NONE = école pilote ou
 * sans essai ni début payant : aucune restriction. TRIAL_EXPIRED et TERMINATED ferment l'usage nouveau de tous les modules (`restriction`) ;
 * la consultation de l'historique et la fin des engagements déjà pris restent possibles. Précédence : TERMINATED > PAID > TRIAL > TRIAL_EXPIRED.
 * Suspension (R01-T09, #461) : une restriction SUSPENDED, distincte du cycle, ferme aussi l'usage nouveau de tous les modules et des opérations
 * de base de l'école ; `causes` dit pourquoi (PAYMENT = impayé, MANUAL = autre décision de l'équipe). Précédence de la restriction :
 * TERMINATED > SUSPENDED > TRIAL_EXPIRED. Ni l'archivage, ni la fin d'essai, ni la résiliation ne sont une suspension.
 */
export const commercialLifecycles = ['NONE', 'TRIAL', 'TRIAL_EXPIRED', 'PAID', 'TERMINATED'] as const;
export type CommercialLifecycle = (typeof commercialLifecycles)[number];
export const restrictionReasons = ['TRIAL_EXPIRED', 'TERMINATED', 'SUSPENDED'] as const;
export const restrictionCauses = ['PAYMENT', 'MANUAL'] as const;
export type RestrictionCause = (typeof restrictionCauses)[number];
export interface CommercialRestriction { reason: (typeof restrictionReasons)[number]; closes: ActionClass[]; causes?: RestrictionCause[] }
/** Raison rendue par `drivy.school_module_access` pour un usage nouveau. */
export const moduleAccesses = ['ENTITLED', 'NOT_ENTITLED', 'TRIAL_EXPIRED', 'TERMINATED', 'SUSPENDED'] as const;
export type ModuleAccess = (typeof moduleAccesses)[number];

/**
 * Classes d'action d'un module. Un retrait commercial ne bloque que l'usage NOUVEAU ; l'historique reste consultable selon les règles
 * existantes de chaque module et les engagements en cours peuvent se terminer (le justificatif, le trajet, la séance déjà acceptée).
 */
export const actionClasses = ['READ_HISTORY', 'COMPLETE_COMMITMENT', 'WRITE_NEW'] as const;
export type ActionClass = (typeof actionClasses)[number];
export const moduleActionAllowed = (entitled: boolean, action: ActionClass): boolean => action === 'WRITE_NEW' ? entitled : true;

/** Modules de l'école courante, tels que l'API les rend à la web et à l'iPhone : jamais l'offre, le motif ni l'auteur. */
export const entitlementEffects = ['GRANT', 'REVOKE'] as const;
export type EntitlementEffect = (typeof entitlementEffects)[number];
export const assignmentPhases = ['IN_FORCE', 'SCHEDULED', 'SUPERSEDED', 'CANCELLED'] as const;
export type AssignmentPhase = (typeof assignmentPhases)[number];
export const adjustmentPhases = ['ACTIVE', 'ENDED', 'LIFTED'] as const;
export type AdjustmentPhase = (typeof adjustmentPhases)[number];
export const consequenceKinds = ['GAINS', 'LOSES', 'KEEPS', 'STAYS_OFF'] as const;
export type ConsequenceKind = (typeof consequenceKinds)[number];

export interface AssignmentRow { id: string; offerId: string; offerName: string; effectiveAt: string; modules: string[] }
export interface AdjustmentDetail { id: string; effect: EntitlementEffect; reason: string; createdAt: string; createdByName: string | null }
export interface EntitlementModuleRow { code: string; inOffer: boolean; entitled: boolean; adjustment: AdjustmentDetail | null }
/** Ligne rendue par `drivy.platform_client_entitlement_core` : droits en vigueur et cycle commercial. */
export interface EntitlementCoreRow {
  state: CommercialState; lifecycle: CommercialLifecycle; restriction: CommercialRestriction | null;
  trial: { startsAt: string; endsAt: string } | null; paidStartsOn: string | null; terminationOn: string | null;
  assignment: AssignmentRow | null; scheduled: AssignmentRow | null; modules: EntitlementModuleRow[]; version: number; nextChangeAt: string | null;
}
/** Ligne rendue par `drivy.platform_client_entitlements` (équipe) : droits en vigueur et historique. */
export interface EntitlementDetailRow {
  state: CommercialState; assignment: AssignmentRow | null; scheduled: AssignmentRow | null; modules: EntitlementModuleRow[];
  version: number; nextChangeAt: string | null; lifecycle?: CommercialLifecycle;
  assignments: Array<AssignmentRow & { status: 'ACTIVE' | 'CANCELLED'; createdAt: string; createdByName: string | null; cancelledAt: string | null }>;
  adjustments: Array<{ id: string; assignmentId: string; moduleCode: string; effect: EntitlementEffect; reason: string; createdAt: string;
    createdByName: string | null; liftedAt: string | null; liftedByName: string | null; liftReason: string | null }>;
}
/** Ligne rendue par `drivy.school_entitlements` (école) : ni offre, ni motif, ni auteur. */
export interface SchoolEntitlementRow {
  state: CommercialState; modules: Array<{ code: string; entitled: boolean }>; version: number; nextChangeAt: string | null;
  /** Cycle commercial (R01-T04) ; absent d'une base qui n'a pas encore la migration : NONE, sans restriction. */
  lifecycle?: CommercialLifecycle; restriction?: CommercialRestriction | null; trialEndsAt?: string | null; paidStartsOn?: string | null; terminationOn?: string | null;
}
export type ModuleUsage = Record<string, Record<string, number>>;

/** Horodatage de la base (`+00:00`, microsecondes) ramené au format ISO du contrat. */
export const iso = (value: string | Date | null | undefined) => value ? new Date(value).toISOString() : null;

export const assignmentView = (row: AssignmentRow | null) => row ? { offerId: row.offerId, name: row.offerName, effectiveAt: iso(row.effectiveAt)!, modules: [...row.modules] } : null;

/**
 * Projection commerciale d'une fiche (liste et détail) : état dérivé, offre en vigueur, offre programmée, cycle et jalons (R01-T04).
 * `dueDates` annonce les échéances commerciales datées à venir (fin d'essai, début payant, prochaine période facturable si les conditions
 * sont complètes, résiliation), en instants (minuit à Zurich pour un jour). Prévisionnel : aucune facture n'est émise ici (#457).
 */
export interface ClientCommercial {
  commercial_state: CommercialState; offer: AssignmentRow | null; scheduled_offer: AssignmentRow | null; entitlement_version: number;
  lifecycle?: CommercialLifecycle | null; trial_ends_at?: string | null; paid_starts_on?: string | null; termination_on?: string | null; billing_ready?: boolean | null;
}
/** Minuit à Zurich du jour donné, en instant UTC (le décalage d'heure d'été est relu pour ce jour). */
export function zurichMidnight(day: string): Date {
  const guess = new Date(`${day}T00:00:00Z`);
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Zurich', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(guess);
  const hour = Number(parts.find(part => part.type === 'hour')?.value ?? 0); const minute = Number(parts.find(part => part.type === 'minute')?.value ?? 0);
  return new Date(guess.getTime() - (hour * 60 + minute) * 60_000);
}
export function commercialDueDates(item: ClientCommercial, nextPeriodOn: string | null, now: Date): string[] {
  const dates = [
    item.lifecycle === 'TRIAL' ? iso(item.trial_ends_at) : null,
    item.paid_starts_on ? zurichMidnight(item.paid_starts_on).toISOString() : null,
    nextPeriodOn ? zurichMidnight(nextPeriodOn).toISOString() : null,
    item.termination_on ? zurichMidnight(item.termination_on).toISOString() : null,
  ].filter((value): value is string => value !== null && new Date(value) > now);
  return [...new Set(dates)].sort();
}
/** `nextPeriodOn` : prochain début de période calculé par l'appelant ; ignoré tant que les conditions ne sont pas complètes. */
export const commercialView = (item: ClientCommercial, nextPeriodOn: string | null = null, now: Date = new Date()) => ({
  state: item.commercial_state, lifecycle: (item.lifecycle ?? 'NONE') as CommercialLifecycle,
  offer: assignmentView(item.offer), scheduledOffer: assignmentView(item.scheduled_offer),
  trialEndsAt: iso(item.trial_ends_at), paidStartsOn: item.paid_starts_on ?? null, terminationOn: item.termination_on ?? null,
  billingReady: item.billing_ready === true, entitlementVersion: item.entitlement_version,
  dueDates: commercialDueDates(item, item.billing_ready === true ? nextPeriodOn : null, now),
});

export const schoolEntitlementsView = (row: SchoolEntitlementRow, computedAt: Date) => ({
  state: row.state, lifecycle: row.lifecycle ?? 'NONE',
  restriction: row.restriction ? { reason: row.restriction.reason, closes: [...row.restriction.closes], ...(row.restriction.causes ? { causes: [...row.restriction.causes] } : {}) } : null,
  trialEndsAt: iso(row.trialEndsAt), paidStartsOn: row.paidStartsOn ?? null, terminationOn: row.terminationOn ?? null,
  modules: row.modules.map(module => ({ code: module.code, entitled: module.entitled })), version: row.version,
  nextChangeAt: iso(row.nextChangeAt), computedAt: computedAt.toISOString(),
});

export const entitlementDetailView = (row: EntitlementDetailRow, at: Date) => {
  const currentId = row.assignment?.id ?? null;
  const adjustmentView = (adjustment: AdjustmentDetail | null) => adjustment ? {
    id: adjustment.id, effect: adjustment.effect, reason: adjustment.reason, createdAt: iso(adjustment.createdAt)!, createdByName: adjustment.createdByName,
  } : null;
  return {
    state: row.state, offer: assignmentView(row.assignment), scheduledOffer: assignmentView(row.scheduled),
    modules: row.modules.map(module => ({ code: module.code, inOffer: module.inOffer, entitled: module.entitled, adjustment: adjustmentView(module.adjustment) })),
    assignments: row.assignments.map(item => ({
      id: item.id, offerId: item.offerId, offerName: item.offerName, modules: [...item.modules], effectiveAt: iso(item.effectiveAt)!,
      phase: (item.status === 'CANCELLED' ? 'CANCELLED' : item.id === currentId ? 'IN_FORCE' : new Date(item.effectiveAt) > at ? 'SCHEDULED' : 'SUPERSEDED') as AssignmentPhase,
      createdAt: iso(item.createdAt)!, createdByName: item.createdByName, cancelledAt: iso(item.cancelledAt),
    })),
    adjustments: row.adjustments.map(item => ({
      id: item.id, moduleCode: item.moduleCode, effect: item.effect, reason: item.reason, createdAt: iso(item.createdAt)!, createdByName: item.createdByName,
      phase: (item.liftedAt ? 'LIFTED' : item.assignmentId === currentId ? 'ACTIVE' : 'ENDED') as AdjustmentPhase,
      liftedAt: iso(item.liftedAt), liftedByName: item.liftedByName, liftReason: item.liftReason,
    })),
    version: row.version, nextChangeAt: iso(row.nextChangeAt),
  };
};
export type EntitlementDetail = ReturnType<typeof entitlementDetailView>;

/**
 * Aperçu des conséquences d'une attribution, calculé avant toute écriture : pour chaque module, droit avant et après, et ce que
 * le retrait laisse en place (volumes d'objets existants, jamais un contenu). Les ajustements de l'attribution actuelle prennent fin
 * avec elle ; une attribution déjà programmée est remplacée.
 */
export function assignmentPreview(args: {
  current: EntitlementDetail; offer: { id: string; name: string; modules: string[] }; effectiveAt: string | null; usage: ModuleUsage;
}) {
  const target = new Set(args.offer.modules);
  const modules = args.current.modules.map(module => {
    const after = target.has(module.code);
    const kind: ConsequenceKind = module.entitled ? (after ? 'KEEPS' : 'LOSES') : (after ? 'GAINS' : 'STAYS_OFF');
    return { code: module.code, before: module.entitled, after, kind, existing: kind === 'LOSES' ? (args.usage[module.code] ?? {}) : null };
  });
  return {
    offer: { id: args.offer.id, name: args.offer.name, modules: [...args.offer.modules] },
    effectiveAt: args.effectiveAt, immediate: args.effectiveAt === null, replacesScheduled: args.current.scheduledOffer,
    endingAdjustments: args.current.adjustments.filter(item => item.phase === 'ACTIVE').map(item => ({ id: item.id, moduleCode: item.moduleCode, effect: item.effect })),
    modules, version: args.current.version,
  };
}
export type AssignmentPreview = ReturnType<typeof assignmentPreview>;
