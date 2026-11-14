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
/** Ligne rendue par `drivy.platform_client_entitlements` (équipe) : droits en vigueur et historique. */
export interface EntitlementDetailRow {
  state: CommercialState; assignment: AssignmentRow | null; scheduled: AssignmentRow | null; modules: EntitlementModuleRow[];
  version: number; nextChangeAt: string | null;
  assignments: Array<AssignmentRow & { status: 'ACTIVE' | 'CANCELLED'; createdAt: string; createdByName: string | null; cancelledAt: string | null }>;
  adjustments: Array<{ id: string; assignmentId: string; moduleCode: string; effect: EntitlementEffect; reason: string; createdAt: string;
    createdByName: string | null; liftedAt: string | null; liftedByName: string | null; liftReason: string | null }>;
}
/** Ligne rendue par `drivy.school_entitlements` (école) : ni offre, ni motif, ni auteur. */
export interface SchoolEntitlementRow { state: CommercialState; modules: Array<{ code: string; entitled: boolean }>; version: number; nextChangeAt: string | null }
export type ModuleUsage = Record<string, Record<string, number>>;

/** Horodatage de la base (`+00:00`, microsecondes) ramené au format ISO du contrat. */
export const iso = (value: string | Date | null | undefined) => value ? new Date(value).toISOString() : null;

export const assignmentView = (row: AssignmentRow | null) => row ? { offerId: row.offerId, name: row.offerName, effectiveAt: iso(row.effectiveAt)!, modules: [...row.modules] } : null;

/** Projection commerciale d'une fiche (liste et détail) : état dérivé, offre en vigueur, offre programmée. `dueDates` est réservé à #456. */
export interface ClientCommercial { commercial_state: CommercialState; offer: AssignmentRow | null; scheduled_offer: AssignmentRow | null; entitlement_version: number }
export const commercialView = (item: ClientCommercial) => ({
  state: item.commercial_state, offer: assignmentView(item.offer), scheduledOffer: assignmentView(item.scheduled_offer),
  entitlementVersion: item.entitlement_version, dueDates: [] as string[],
});

export const schoolEntitlementsView = (row: SchoolEntitlementRow, computedAt: Date) => ({
  state: row.state, modules: row.modules.map(module => ({ code: module.code, entitled: module.entitled })), version: row.version,
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
