/**
 * Explicit allowlist of school management routes relayed by the BFF.
 * Each entry names one method and one path shape below /v1/schools/{schoolId}.
 * Anything else is refused before an access token is ever used: this is not an open proxy.
 */
export type SchoolMethod = 'GET' | 'POST' | 'PATCH' | 'PUT';
type QueryKey = 'limit' | 'cursor' | 'status' | 'noticeVersionId' | 'learnerId' | 'trainingId' | 'instructorMembershipId' | 'from' | 'to' | 'action' | 'activate' | 'category'
  | 'plannedStart' | 'plannedEnd' | 'timeZone' | 'bufferMinutes' | 'excludeLessonId'
  | 'domain' | 'toExclusive' | 'compare' | 'breakdown' | 'scope' | 'categoryCode' | 'productKey' | 'granularity' | 'measures' | 'measure' | 'part'
  | 'bucketFrom' | 'bucketToExclusive' | 'expectedLineCount' | 'expectedAmountCents';
export interface SchoolRoute {
  readonly method: SchoolMethod;
  /** Literal segments after the school identifier; ':id' stands for one UUID. */
  readonly segments: readonly string[];
  readonly query?: readonly QueryKey[];
  /** Rules replacing the shared ones for this route only (the pilotage period is a civil date, not an instant). */
  readonly queryRules?: Readonly<Partial<Record<QueryKey, RegExp>>>;
  /** Writes whose API contract requires a strong version (If-Match). */
  readonly ifMatch?: boolean;
  /** Maximum JSON body size in bytes for a write. */
  readonly bodyLimit?: number;
}

const list = ['limit', 'cursor'] as const;
const civilDate = /^\d{4}-\d{2}-\d{2}$/;
const metricsFilters = ['scope', 'instructorMembershipId', 'categoryCode', 'productKey'] as const;
const metricsRules = { from: civilDate } as const;
export const schoolRoutes: readonly SchoolRoute[] = [
  { method: 'GET', segments: [] },
  { method: 'PATCH', segments: [], ifMatch: true, bodyLimit: 4_096 },
  { method: 'GET', segments: ['setup'] },
  { method: 'GET', segments: ['setup-draft'] },
  { method: 'PUT', segments: ['setup-draft'], ifMatch: true, bodyLimit: 1_000_000 },
  { method: 'GET', segments: ['setup-draft', 'templates'] },
  { method: 'GET', segments: ['setup-draft', 'next-actions'] },
  { method: 'GET', segments: ['setup-draft', 'preview'], query: ['activate'] },
  { method: 'POST', segments: ['setup-draft', 'complete'], ifMatch: true, bodyLimit: 4_096 },
  { method: 'PATCH', segments: ['setup'], ifMatch: true, bodyLimit: 2_048 },
  { method: 'GET', segments: ['readiness'] },
  { method: 'GET', segments: ['data-policy'], query: ['noticeVersionId'] },
  { method: 'GET', segments: ['data-policy', 'impact'] },
  { method: 'GET', segments: ['text-proposals'] },
  { method: 'GET', segments: ['recording-choices'] },
  { method: 'PUT', segments: ['data-policy'], ifMatch: true, bodyLimit: 200_000 },
  { method: 'POST', segments: ['activate'], ifMatch: true, bodyLimit: 1_024 },
  { method: 'GET', segments: ['operations', ':id'] },
  { method: 'GET', segments: ['members'], query: list },
  { method: 'PATCH', segments: ['members', ':id'], ifMatch: true, bodyLimit: 8_192 },
  { method: 'GET', segments: ['invitations'], query: list },
  { method: 'GET', segments: ['invitation-options'] },
  { method: 'POST', segments: ['invitations'], bodyLimit: 8_192 },
  { method: 'POST', segments: ['invitations', ':id', 'resend'], ifMatch: true, bodyLimit: 1_024 },
  { method: 'POST', segments: ['invitations', ':id', 'revoke'], ifMatch: true, bodyLimit: 8_192 },
  { method: 'GET', segments: ['offerings'], query: list },
  { method: 'POST', segments: ['offerings'], bodyLimit: 4_096 },
  { method: 'GET', segments: ['curricula'], query: list },
  { method: 'POST', segments: ['curricula'], bodyLimit: 1_000_000 },
  { method: 'GET', segments: ['policy-versions'], query: list },
  { method: 'POST', segments: ['policy-versions'], bodyLimit: 100_000 },
  { method: 'GET', segments: ['commercial-terms'], query: list },
  { method: 'POST', segments: ['commercial-terms'], bodyLimit: 100_000 },
  { method: 'GET', segments: ['service-products'], query: list },
  { method: 'POST', segments: ['service-products'], bodyLimit: 8_192 },
  // Formations et tarifs : lecture agrégée d'un permis et commandes composées (une opération, un reçu AP72).
  { method: 'GET', segments: ['formations'] },
  { method: 'GET', segments: ['formations', 'sheet'], query: ['category'] },
  { method: 'GET', segments: ['formations', 'uncategorized-tariffs'] },
  { method: 'GET', segments: ['formations', 'terms'] },
  { method: 'GET', segments: ['formations', 'references', ':id'] },
  { method: 'POST', segments: ['formations'], bodyLimit: 1_000_000 },
  { method: 'POST', segments: ['formations', 'programmes'], bodyLimit: 1_000_000 },
  { method: 'POST', segments: ['formations', 'tariffs'], bodyLimit: 100_000 },
  { method: 'POST', segments: ['formations', 'terms', 'revise'], bodyLimit: 100_000 },
  { method: 'GET', segments: ['profile-field-policies'], query: list },
  { method: 'POST', segments: ['profile-field-policies'], ifMatch: true, bodyLimit: 32_768 },
  { method: 'POST', segments: ['profile-field-policies', ':id', 'publish'], ifMatch: true, bodyLimit: 1_024 },
  // Élèves et formations : l'administration ouvre la formation et affecte le moniteur depuis le web.
  { method: 'GET', segments: ['learners'], query: [...list, 'status'] },
  { method: 'GET', segments: ['learners', ':id'] },
  { method: 'GET', segments: ['learners', ':id', 'course-facts'] },
  { method: 'GET', segments: ['trainings'], query: [...list, 'learnerId'] },
  { method: 'GET', segments: ['trainings', ':id'] },
  { method: 'POST', segments: ['trainings'], bodyLimit: 2_048 },
  { method: 'GET', segments: ['trainings', ':id', 'assignments'], query: list },
  { method: 'POST', segments: ['trainings', ':id', 'assignments'], bodyLimit: 2_048 },
  // Disponibilités et absences des moniteurs : réglées sur le web uniquement (décision du 28 septembre 2026).
  { method: 'GET', segments: ['availability-rules'], query: [...list, 'instructorMembershipId'] },
  { method: 'POST', segments: ['availability-rules'], bodyLimit: 2_048 },
  { method: 'PUT', segments: ['availability-rules', ':id'], ifMatch: true, bodyLimit: 2_048 },
  { method: 'POST', segments: ['availability-rules', ':id', 'remove'], ifMatch: true, bodyLimit: 2_048 },
  { method: 'GET', segments: ['closures'], query: [...list, 'instructorMembershipId', 'from', 'to'] },
  { method: 'POST', segments: ['closures'], bodyLimit: 2_048 },
  { method: 'POST', segments: ['closures', ':id', 'remove'], ifMatch: true, bodyLimit: 2_048 },
  // Dossier de l'élève, équipe et module GPS (contrats de la branche claude/api-corrections ; noms de champs à confirmer).
  { method: 'POST', segments: ['members', ':id', 'deactivate'], ifMatch: true, bodyLimit: 8_192 },
  { method: 'POST', segments: ['learners', ':id', 'archive'], ifMatch: true, bodyLimit: 8_192 },
  // Profil à compléter : ce qui manque avant une leçon, et la saisie de ces seuls champs par l'administration.
  { method: 'GET', segments: ['learners', ':id', 'action-readiness'], query: ['action'] },
  { method: 'GET', segments: ['learners', ':id', 'administrative-profile'] },
  { method: 'PATCH', segments: ['learners', ':id', 'administrative-profile'], ifMatch: true, bodyLimit: 4_096 },
  { method: 'POST', segments: ['learners', ':id', 'restore'], ifMatch: true, bodyLimit: 8_192 },
  { method: 'POST', segments: ['trainings', ':id', 'transition'], ifMatch: true, bodyLimit: 8_192 },
  { method: 'POST', segments: ['trainings', ':id', 'assignments', ':id', 'end'], ifMatch: true, bodyLimit: 2_048 },
  { method: 'PUT', segments: ['modules'], ifMatch: true, bodyLimit: 2_048 },
  // Contrôle du permis : l'historique se lit, la décision se consigne (If-Match = version de la formation).
  { method: 'GET', segments: ['trainings', ':id', 'permit-checks'], query: list },
  { method: 'POST', segments: ['trainings', ':id', 'permit-checks'], ifMatch: true, bodyLimit: 8_192 },
  // Signalements configurables : un réglage d'école versionné (ordre et affichage des quinze thèmes).
  { method: 'GET', segments: ['observation-themes'] },
  { method: 'PUT', segments: ['observation-themes'], ifMatch: true, bodyLimit: 4_096 },
  // Cours collectifs (#38) : catalogue, types, conditions d'annulation, séries brouillon puis publiées.
  { method: 'GET', segments: ['course-catalogue'] },
  { method: 'POST', segments: ['course-types'], bodyLimit: 8_192 },
  { method: 'PATCH', segments: ['course-types', ':id'], ifMatch: true, bodyLimit: 8_192 },
  { method: 'PUT', segments: ['course-policy'], ifMatch: true, bodyLimit: 2_048 },
  { method: 'GET', segments: ['course-series'], query: ['from', 'to', 'status'] },
  { method: 'GET', segments: ['course-series', ':id'] },
  { method: 'POST', segments: ['course-series'], bodyLimit: 64_000 },
  { method: 'PUT', segments: ['course-series', ':id'], ifMatch: true, bodyLimit: 64_000 },
  { method: 'POST', segments: ['course-series', ':id', 'publish'], ifMatch: true, bodyLimit: 1_024 },
  { method: 'POST', segments: ['course-series', ':id', 'capacity'], ifMatch: true, bodyLimit: 1_024 },
  // Inscriptions, file d'attente et annulations d'un cours publié (#39-#41) : réservé au personnel habilité.
  { method: 'GET', segments: ['course-series', ':id', 'enrollments'] },
  { method: 'POST', segments: ['course-series', ':id', 'enrollments'], bodyLimit: 1_024 },
  { method: 'POST', segments: ['course-enrollments', ':id', 'staff-cancel'], ifMatch: true, bodyLimit: 2_048 },
  { method: 'POST', segments: ['course-series', ':id', 'cancel'], ifMatch: true, bodyLimit: 2_048 },
  { method: 'POST', segments: ['course-series', ':id', 'reschedule'], ifMatch: true, bodyLimit: 32_000 },
  // Feuille du cours : version de présence dans le corps (expectedVersion), pas d'If-Match.
  { method: 'GET', segments: ['course-series', ':id', 'sheet'] },
  { method: 'PUT', segments: ['course-enrollments', ':id', 'attendance', ':id'], bodyLimit: 2_048 },
  { method: 'POST', segments: ['course-enrollments', ':id', 'payments'], bodyLimit: 2_048 },
  { method: 'POST', segments: ['course-payments', ':id', 'void'], bodyLimit: 2_048 },
  { method: 'POST', segments: ['course-enrollments', ':id', 'validate'], bodyLimit: 2_048 },
  { method: 'POST', segments: ['course-completions', ':id', 'revoke'], bodyLimit: 2_048 },
  // Leçons individuelles : mêmes commandes et disponibilité que l'app, sans capture GPS.
  { method: 'GET', segments: ['lessons'], query: [...list, 'from', 'to', 'trainingId', 'instructorMembershipId'] },
  { method: 'GET', segments: ['lessons', 'availability'], query: ['trainingId', 'instructorMembershipId', 'plannedStart', 'plannedEnd', 'timeZone', 'bufferMinutes', 'excludeLessonId'] },
  { method: 'POST', segments: ['lessons'], bodyLimit: 8_192 },
  { method: 'POST', segments: ['lessons', ':id', 'move'], ifMatch: true, bodyLimit: 8_192 },
  { method: 'POST', segments: ['lessons', ':id', 'cancel'], ifMatch: true, bodyLimit: 4_096 },
  { method: 'GET', segments: ['lessons', ':id'] },
  { method: 'GET', segments: ['captures'], query: list },
  { method: 'GET', segments: ['lessons', ':id', 'reports'], query: list },
  { method: 'GET', segments: ['trainings', ':id', 'progress'] },
  // Pilotage de l'école (#373) : lecture seule, droits relus par l'API. L'export CSV a sa propre route (réponse non JSON).
  { method: 'GET', segments: ['metrics', 'definitions'] },
  { method: 'GET', segments: ['metrics'], query: ['domain', 'from', 'toExclusive', 'compare', 'breakdown', ...metricsFilters], queryRules: metricsRules },
  { method: 'GET', segments: ['metrics', 'series'], query: ['from', 'toExclusive', 'granularity', 'measures', ...metricsFilters], queryRules: metricsRules },
  { method: 'GET', segments: ['metrics', 'details'], query: ['measure', 'part', 'from', 'toExclusive', 'bucketFrom', 'bucketToExclusive', 'limit', 'cursor', 'expectedLineCount', 'expectedAmountCents', ...metricsFilters], queryRules: metricsRules },
];

const uuid = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const queryRules: Record<QueryKey, RegExp> = {
  activate: /^(?:true|false)$/,
  // Code de permis tel qu'enregistré (30 caractères, sans caractère de contrôle) ; aucune donnée personnelle.
  category: /^[^\u0000-\u001f\u007f]{1,30}$/u,
  limit: /^(?:[1-9]|[1-9][0-9]|100)$/,
  cursor: /^[A-Za-z0-9_-]{1,6000}$/,
  noticeVersionId: uuid,
  learnerId: uuid,
  action: /^(?:ENTER|PLAN_LESSON)$/,
  // Dossiers (ACTIVE, ARCHIVED, ALL) et séries de cours (DRAFT, PUBLISHED, CANCELLED, CLOSED) ; l'API relit chaque valeur.
  status: /^(?:ACTIVE|ARCHIVED|ALL|DRAFT|PUBLISHED|CANCELLED|CLOSED)$/,
  trainingId: uuid,
  instructorMembershipId: uuid,
  excludeLessonId: uuid,
  plannedStart: /^\d{4}-\d{2}-\d{2}T[0-9:.]+(?:Z|[+-]\d{2}:\d{2})$/,
  plannedEnd: /^\d{4}-\d{2}-\d{2}T[0-9:.]+(?:Z|[+-]\d{2}:\d{2})$/,
  timeZone: /^[A-Za-z0-9_+/-]{1,100}$/,
  bufferMinutes: /^(?:[0-9]|[1-9][0-9]|1[0-9]{2}|2[0-3][0-9]|240)$/,
  from: /^\d{4}-\d{2}-\d{2}T[0-9:.]+(?:Z|[+-]\d{2}:\d{2})$/,
  to: /^\d{4}-\d{2}-\d{2}T[0-9:.]+(?:Z|[+-]\d{2}:\d{2})$/,
  // Pilotage : dates civiles de l'école et valeurs énumérées ; l'API relit chaque paramètre.
  domain: /^(?:activity|finance)$/,
  toExclusive: civilDate,
  compare: /^(?:none|previous-month|equivalent-period)$/,
  breakdown: /^(?:instructor|category|product)$/,
  scope: /^(?:school|self)$/,
  categoryCode: /^[^\u0000-\u001f\u007f]{1,30}$/u,
  productKey: /^[^\u0000-\u001f\u007f]{1,100}$/u,
  granularity: /^(?:day|week|month)$/,
  measures: /^[A-Z][0-9]{2}(?:,[A-Z][0-9]{2}){0,4}$/,
  measure: /^[A-Z][0-9]{2}$/,
  part: /^[ab]$/,
  bucketFrom: civilDate,
  bucketToExclusive: civilDate,
  expectedLineCount: /^[0-9]{1,16}$/,
  expectedAmountCents: /^[0-9]{1,16}$/,
};
export const MAX_SCHOOL_BODY = Math.max(...schoolRoutes.map(route => route.bodyLimit ?? 0));
export const isUUID = (value: unknown): value is string => typeof value === 'string' && uuid.test(value);

export type SchoolRouteMatch = { route: SchoolRoute; schoolId: string; path: string; query: string };

/**
 * Match `/schools/{schoolId}/...` plus its raw query string against the allowlist.
 * Encoded characters, empty segments, dot segments and unknown or repeated query keys are refused.
 */
export function matchSchoolRoute(method: string, pathname: string, search: string): SchoolRouteMatch | undefined {
  if (!/^\/schools\/[A-Za-z0-9/-]+$/.test(pathname) || pathname.length > 256) return;
  const parts = pathname.split('/').slice(1);
  if (parts.some(part => part === '' || part === '.' || part === '..')) return;
  const [, schoolId, ...rest] = parts;
  if (!isUUID(schoolId)) return;
  const route = schoolRoutes.find(candidate => candidate.method === method && candidate.segments.length === rest.length &&
    candidate.segments.every((segment, index) => segment === ':id' ? isUUID(rest[index]) : segment === rest[index]));
  if (!route) return;
  if (search.length > 6_200) return;
  const incoming = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  const allowed = route.query ?? [];
  const outgoing = new URLSearchParams();
  const seen = new Set<string>();
  for (const [key, value] of incoming) {
    if (seen.has(key) || !(allowed as readonly string[]).includes(key) || !(route.queryRules?.[key as QueryKey] ?? queryRules[key as QueryKey]).test(value)) return;
    seen.add(key); outgoing.append(key, value);
  }
  const query = outgoing.toString();
  return { route, schoolId, path: `/v1/schools/${schoolId}${rest.length ? '/' + rest.join('/') : ''}`, query: query ? `?${query}` : '' };
}
