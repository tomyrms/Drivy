/**
 * Explicit allowlist of school management routes relayed by the BFF.
 * Each entry names one method and one path shape below /v1/schools/{schoolId}.
 * Anything else is refused before an access token is ever used: this is not an open proxy.
 */
export type SchoolMethod = 'GET' | 'POST' | 'PATCH' | 'PUT';
type QueryKey = 'limit' | 'cursor' | 'noticeVersionId';
export interface SchoolRoute {
  readonly method: SchoolMethod;
  /** Literal segments after the school identifier; ':id' stands for one UUID. */
  readonly segments: readonly string[];
  readonly query?: readonly QueryKey[];
  /** Writes whose API contract requires a strong version (If-Match). */
  readonly ifMatch?: boolean;
  /** Maximum JSON body size in bytes for a write. */
  readonly bodyLimit?: number;
}

const list = ['limit', 'cursor'] as const;
export const schoolRoutes: readonly SchoolRoute[] = [
  { method: 'GET', segments: [] },
  { method: 'PATCH', segments: [], ifMatch: true, bodyLimit: 4_096 },
  { method: 'GET', segments: ['setup'] },
  { method: 'PATCH', segments: ['setup'], ifMatch: true, bodyLimit: 2_048 },
  { method: 'GET', segments: ['readiness'] },
  { method: 'GET', segments: ['data-policy'], query: ['noticeVersionId'] },
  { method: 'PUT', segments: ['data-policy'], ifMatch: true, bodyLimit: 200_000 },
  { method: 'POST', segments: ['activate'], ifMatch: true, bodyLimit: 1_024 },
  { method: 'GET', segments: ['operations', ':id'] },
  { method: 'GET', segments: ['members'], query: list },
  { method: 'PATCH', segments: ['members', ':id'], ifMatch: true, bodyLimit: 8_192 },
  { method: 'GET', segments: ['invitations'], query: list },
  { method: 'POST', segments: ['invitations'], bodyLimit: 2_048 },
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
  { method: 'GET', segments: ['profile-field-policies'], query: list },
  { method: 'POST', segments: ['profile-field-policies'], ifMatch: true, bodyLimit: 32_768 },
  { method: 'POST', segments: ['profile-field-policies', ':id', 'publish'], ifMatch: true, bodyLimit: 1_024 },
];

const uuid = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const queryRules: Record<QueryKey, RegExp> = {
  limit: /^(?:[1-9]|[1-9][0-9]|100)$/,
  cursor: /^[A-Za-z0-9_-]{1,6000}$/,
  noticeVersionId: uuid,
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
    if (seen.has(key) || !(allowed as readonly string[]).includes(key) || !queryRules[key as QueryKey].test(value)) return;
    seen.add(key); outgoing.append(key, value);
  }
  const query = outgoing.toString();
  return { route, schoolId, path: `/v1/schools/${schoolId}${rest.length ? '/' + rest.join('/') : ''}`, query: query ? `?${query}` : '' };
}
