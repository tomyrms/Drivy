import type { Member } from '../../protocol';

/**
 * Droits d'affichage du pilotage, relus de l'appartenance ; l'API les revérifie à chaque requête (#375).
 * Un administrateur lit l'activité et les finances de l'école ; l'export demande en plus son droit propre.
 */
export interface MetricRights { activity: boolean; finance: boolean; export: boolean }

export function metricRights(membership: Pick<Member, 'roles' | 'grants'>): MetricRights {
  const administrator = membership.roles.includes('ADMIN');
  return {
    activity: administrator || membership.grants.includes('VIEW_SCHOOL_METRICS'),
    finance: administrator || membership.grants.includes('VIEW_FINANCIAL_METRICS'),
    export: membership.grants.includes('EXPORT_MANAGEMENT'),
  };
}

/** Statistiques s'ouvre dès qu'un des deux domaines est lisible. */
export const canOpenStatistics = (rights: MetricRights) => rights.activity || rights.finance;
