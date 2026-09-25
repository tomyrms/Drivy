import { z } from 'zod';
import { RequestFailure } from './protocol';

/* Read models returned by /v1/schools/{schoolId}/… (OpenAPI 3.11.0), validated before display. */
const id = z.string().uuid();
const version = z.number().int().positive();
const timestamp = z.string().datetime({ offset: true });
const civil = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

export const schoolSchema = z.object({
  id, schoolId: id, version, name: z.string(), timeZone: z.string(), status: z.string(),
  contactEmail: z.string(), contactPhone: z.string().nullable(), configurationVersion: version,
  modules: z.object({ gpsEnabled: z.boolean(), packsEnabled: z.boolean(), collectiveCoursesEnabled: z.boolean(), courseOffersVisibleByDefault: z.boolean() }),
});
const blocker = z.object({ code: z.string(), message: z.string(), field: z.string().nullable().optional() });
export const readinessSchema = z.object({
  schoolId: id, configurationVersion: version, computedAt: timestamp, activationReady: z.boolean(),
  activationBlockers: z.array(blocker).max(50),
  capabilities: z.array(z.object({ capability: z.string(), ready: z.boolean(), blockers: z.array(blocker).max(50) })).max(10),
});
export const setupSchema = z.object({
  schoolId: id, version, status: z.enum(['IN_PROGRESS', 'READY', 'COMPLETED']), currentStep: z.string(),
  completedSteps: z.array(z.string()).max(6), lastSavedAt: timestamp, readiness: readinessSchema,
});
export const dataPolicySchema = z.object({
  schoolId: id, version, status: z.enum(['DRAFT', 'APPROVED']), noticeText: z.string().max(20_000), retentionText: z.string().max(20_000),
  contactEmail: z.string().nullable(), approvedAt: timestamp.nullable(), noticeVersionId: id.nullable().optional(),
});
export const receiptSchema = z.object({
  operationId: id, commandType: z.string(), resourceType: z.string(), resourceId: id, committedAt: timestamp, resourceVersion: version,
});
export const memberSchema = z.object({
  id, schoolId: id, version, personId: id, displayName: z.string(), status: z.string(),
  roles: z.array(z.enum(['ADMIN', 'INSTRUCTOR', 'LEARNER'])).max(3), grants: z.array(z.string()).max(20), accessEpoch: z.number().int(),
});
export const invitationSchema = z.object({
  id, schoolId: id, version, maskedEmail: z.string(), roles: z.array(z.enum(['ADMIN', 'INSTRUCTOR', 'LEARNER'])).min(1).max(3),
  status: z.enum(['PENDING', 'ACCEPTED', 'REVOKED', 'EXPIRED']), expiresAt: timestamp,
});
export const offeringSchema = z.object({
  id, schoolId: id, version, offeringKey: z.string(), categoryCode: z.string(), curriculumVersionId: id, policyVersionId: id,
  enabled: z.boolean(), defaultDurationMinutes: z.number().int().min(1).max(480), defaultPriceCents: z.number().int().min(0),
});
export const competencySchema = z.object({ id, key: z.string(), label: z.string(), description: z.string(), sortOrder: z.number().int() });
export const curriculumSchema = z.object({
  id, schoolId: id, version, categoryCode: z.string(), revision: z.number().int().positive(), approved: z.boolean(),
  competencies: z.array(competencySchema).max(200),
});
export const catalogPolicySchema = z.object({
  id, schoolId: id, version, categoryCode: z.string(), procedureText: z.string(), cancellationPolicyText: z.string(),
  sourceUrls: z.array(z.string()).max(30), approved: z.boolean(), approvedAt: timestamp.nullable(),
});
export const termsSchema = z.object({
  id, schoolId: id, version, label: z.string(), termsText: z.string(), validFrom: civil, validUntil: civil.nullable(),
  approved: z.boolean(), approvalReason: z.string().nullable(), approvedAt: timestamp.nullable(),
});
export const productTypes = ['INDIVIDUAL_LESSON', 'COLLECTIVE_COURSE', 'EXAM_SUPPORT', 'EXTERNAL_SERVICE'] as const;
export const productSchema = z.object({
  id, schoolId: id, version, productKey: z.string(), label: z.string(), type: z.enum(productTypes), categoryCode: z.string().nullable(),
  durationMinutes: z.number().int().nullable(), unitLabel: z.string(), unitPriceCents: z.number().int().min(0),
  validFrom: civil, validUntil: civil.nullable(), termsVersionId: id, enabled: z.boolean(),
});
const rule = z.object({
  field: z.enum(['firstName', 'lastName', 'birthDate', 'postalAddress', 'contactEmail', 'contactPhone', 'profilePhotoDocumentId']),
  requirement: z.enum(['REQUIRED', 'CONDITIONAL', 'OPTIONAL']), stage: z.enum(['JOIN', 'BEFORE_LESSON', 'BEFORE_COURSE', 'OPTIONAL']),
  purposeCode: z.enum(['IDENTIFICATION', 'LESSON_CONTACT', 'COURSE_ELIGIBILITY', 'CERTIFICATE', 'POSTAL_CONTACT', 'PERSONALISATION']),
  explanation: z.string(),
});
export const profilePolicySchema = z.object({
  id, schoolId: id, version, status: z.enum(['DRAFT', 'PUBLISHED', 'RETIRED']), effectiveFrom: timestamp,
  fields: z.array(rule).max(7), noticeVersionId: id, approvedByMembershipId: id.nullable(),
});

export type School = z.infer<typeof schoolSchema>;
export type Readiness = z.infer<typeof readinessSchema>;
export type Setup = z.infer<typeof setupSchema>;
export type DataPolicy = z.infer<typeof dataPolicySchema>;
export type Receipt = z.infer<typeof receiptSchema>;
export type SchoolMember = z.infer<typeof memberSchema>;
export type Invitation = z.infer<typeof invitationSchema>;
export type Offering = z.infer<typeof offeringSchema>;
export type Curriculum = z.infer<typeof curriculumSchema>;
export type CatalogPolicy = z.infer<typeof catalogPolicySchema>;
export type CommercialTerms = z.infer<typeof termsSchema>;
export type ServiceProduct = z.infer<typeof productSchema>;
export type ProfilePolicy = z.infer<typeof profilePolicySchema>;
export type Page<T> = { items: T[]; nextCursor: string | null };

export type RawResponse = { status: number; body: unknown; etag: string | null; code: string };

/** One same-origin call to the management relay. Never throws: status 0 means no response. */
export async function schoolFetch(schoolId: string, path: string, options: {
  method?: 'GET' | 'POST' | 'PATCH' | 'PUT'; query?: Record<string, string>; headers?: Record<string, string>; body?: unknown;
} = {}): Promise<RawResponse> {
  const url = new URL(`/app/bff/schools/${schoolId}${path ? '/' + path : ''}`, window.location.origin);
  for (const [key, value] of Object.entries(options.query ?? {})) url.searchParams.set(key, value);
  let response: Response;
  try {
    response = await fetch(url, {
      method: options.method ?? 'GET', credentials: 'same-origin', cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer',
      signal: AbortSignal.timeout(30_000),
      headers: { Accept: 'application/json', ...(options.headers ?? {}) },
      ...(options.body === undefined ? {} : { body: JSON.stringify(options.body) }),
    });
  } catch { return { status: 0, body: null, etag: null, code: 'NETWORK_UNAVAILABLE' }; }
  if (response.url !== url.href) return { status: 0, body: null, etag: null, code: 'INVALID_RESPONSE' };
  let body: unknown = null;
  const type = response.headers.get('content-type')?.split(';')[0]?.trim();
  if (type === 'application/json') { try { body = await response.json(); } catch { body = null; } }
  const problem = z.object({ code: z.string().regex(/^[A-Z0-9_]{1,80}$/) }).safeParse(body);
  return { status: response.status, body, etag: response.headers.get('etag'),
    code: response.ok ? '' : problem.success ? problem.data.code : response.status >= 500 ? 'SERVICE_UNAVAILABLE' : 'REQUEST_FAILED' };
}

const envelope = <T extends z.ZodTypeAny>(data: T) => z.object({ data, requestId: z.string().min(1), serverTime: timestamp });

/** Validated read: throws RequestFailure with the API code, never returns unverified data. */
export async function readSchool<T extends z.ZodTypeAny>(schoolId: string, path: string, schema: T, query?: Record<string, string>): Promise<z.infer<T>> {
  const response = await schoolFetch(schoolId, path, query ? { query } : {});
  if (response.status !== 200) throw new RequestFailure(response.code || 'REQUEST_FAILED', response.status);
  const parsed = envelope(schema).safeParse(response.body);
  if (!parsed.success) throw new RequestFailure('INVALID_RESPONSE', response.status);
  return (parsed.data as { data: z.infer<T> }).data;
}

export async function readPage<T extends z.ZodTypeAny>(schoolId: string, path: string, item: T, cursor?: string | null): Promise<Page<z.infer<T>>> {
  const page = z.object({ items: z.array(item).max(100), nextCursor: z.string().min(1).max(6000).nullable() });
  const result = await readSchool(schoolId, path, page, { limit: '100', ...(cursor ? { cursor } : {}) });
  if (result.items.some(entry => (entry as { schoolId?: string }).schoolId !== schoolId)) throw new RequestFailure('INVALID_RESPONSE');
  return result as Page<z.infer<T>>;
}

/** Read every page of a short management list (at most 1 000 entries); `truncated` says when more exist. */
export async function readAll<T extends z.ZodTypeAny>(schoolId: string, path: string, item: T): Promise<{ items: z.infer<T>[]; truncated: boolean }> {
  const items: z.infer<T>[] = [];
  let cursor: string | null = null;
  for (let page = 0; page < 10; page++) {
    const result: Page<z.infer<T>> = await readPage(schoolId, path, item, cursor);
    items.push(...result.items);
    cursor = result.nextCursor;
    if (!cursor) return { items, truncated: false };
  }
  return { items, truncated: true };
}

/** Parse the confirmed resource of a write; any mismatch keeps the request uncertain. */
export function confirmedData(body: unknown): { schoolId?: string | undefined; version?: number | undefined; id?: string | undefined } | null {
  const parsed = envelope(z.object({ schoolId: id.optional(), version: z.number().int().optional(), id: id.optional() }).passthrough()).safeParse(body);
  return parsed.success ? parsed.data.data : null;
}
