import { z } from 'zod';
import { openingToken } from './school-opening-model.js';
import { platformEmail } from './platform-model.js';

/**
 * Écoles clientes de la plateforme (R01-T02, #454). Une fiche cliente est la relation commerciale avec une école : elle peut
 * exister avant l'école (code distribué, fiche de suivi légère) et lui est reliée une seule fois, à l'ouverture par code
 * ou par rattachement explicite d'une école déjà ouverte. Aucune zone de saisie n'est obligatoire.
 */
export const clientPreparations = ['AWAITING_SCHOOL', 'IN_PREPARATION', 'ACTIVE', 'ARCHIVED'] as const;
export type ClientPreparation = (typeof clientPreparations)[number];
export const codeStates = ['AVAILABLE', 'USED', 'EXPIRED', 'REVOKED'] as const;
export type CodeState = (typeof codeStates)[number];
export const setupStepCount = 6;
/** Emplacement de l'état commercial : #455 (offres) et #456 (conditions) l'élargissent ; aucune offre ni condition n'est inventée ici. */
export const commercialPlaceholder = () => ({ state: 'NOT_CONFIGURED' as const, offer: null, dueDates: [] as string[] });

const operationId = z.uuid();
const bounded = (max: number) => z.string().trim().min(1).max(max);
/** `null` efface la valeur ; une valeur absente ne la touche pas. */
const clearable = <T extends z.ZodType>(schema: T) => schema.nullable().optional();

const fieldShape = {
  displayName: clearable(bounded(150)),
  contactName: clearable(bounded(200)),
  contactEmail: clearable(platformEmail),
  contactPhone: clearable(bounded(32)),
  billingStreet: clearable(bounded(200)),
  billingPostalCode: clearable(bounded(20)),
  billingCity: clearable(bounded(100)),
  billingCountry: clearable(bounded(100)),
  internalNotes: clearable(bounded(4000)),
};
export const clientFieldNames = Object.keys(fieldShape) as (keyof typeof fieldShape)[];
const columnOf: Record<keyof typeof fieldShape, string> = {
  displayName: 'display_name', contactName: 'contact_name', contactEmail: 'contact_email', contactPhone: 'contact_phone',
  billingStreet: 'billing_street', billingPostalCode: 'billing_postal_code', billingCity: 'billing_city', billingCountry: 'billing_country',
  internalNotes: 'internal_notes',
};
export const clientColumn = (field: keyof typeof fieldShape) => columnOf[field];

export const createClientBody = z.object({ operationId, ...fieldShape, schoolId: z.uuid().optional() }).strict();
export const updateClientBody = z.object({ operationId, ...fieldShape }).strict()
  .refine(body => clientFieldNames.some(name => body[name] !== undefined), { message: 'Aucune modification demandée.' });
export const attachSchoolBody = z.object({ operationId, schoolId: z.uuid() }).strict();
/** Le code est tiré par la passerelle web et n'arrive qu'ici : le service n'en garde que l'empreinte à clé serveur. */
export const issueCodeBody = z.object({
  operationId, code: openingToken, clientId: z.uuid().optional(), displayName: bounded(150).optional(),
  validityDays: z.number().int().min(1).max(30).optional(),
}).strict().refine(body => !(body.clientId && body.displayName), { message: 'Le libellé se saisit sur la fiche existante.' });
export const revokeCodeBody = z.object({ operationId }).strict();

const page = { limit: z.coerce.number().int().min(1).max(100).default(25), cursor: z.string().max(6000).optional() };
export const clientListQuery = z.object({
  ...page,
  q: z.string().trim().max(100).optional().transform(value => value || undefined),
  preparation: z.enum(clientPreparations).optional(),
}).strict();
export const codeListQuery = z.object({
  ...page,
  clientId: z.uuid().optional(),
  state: z.enum(codeStates).optional(),
}).strict();
export const unattachedQuery = z.object({
  q: z.string().trim().max(100).optional().transform(value => value || undefined),
  limit: z.coerce.number().int().min(1).max(50).default(25),
}).strict();

/** Motif de recherche LIKE : les caractères spéciaux de la saisie sont des caractères ordinaires. */
export const searchPattern = (text: string | undefined) => text ? `%${text.replace(/[\\%_]/g, match => `\\${match}`)}%` : null;

interface SchoolFacts {
  id?: string; name: string; status: 'DRAFT' | 'ACTIVE' | 'ARCHIVED'; contact_email: string; contact_phone: string | null;
  setup_step: string | null; setup_done: number; setup_completed_at: string | null; setup_saved_at?: string | null;
}
export interface ClientItem {
  id: string; display_name: string | null; school_id: string | null; link_source: 'OPENING_CODE' | 'EXISTING_SCHOOL' | null;
  opened_via_link_id: string | null; school_linked_at: string | null; issued_by_name: string | null;
  contact_name: string | null; contact_email: string | null; contact_phone: string | null;
  billing_street: string | null; billing_postal_code: string | null; billing_city: string | null; billing_country: string | null;
  internal_notes: string | null; commercial_state: 'NOT_CONFIGURED'; version: number; created_at: string; updated_at: string;
  preparation: ClientPreparation; latest_code: { id: string; status: CodeState; expires_at: string; created_at: string } | null;
  school: SchoolFacts | null;
}
export interface CodeItem {
  id: string; client_id: string | null; client_name: string | null; state: CodeState; created_at: string; expires_at: string;
  used_at: string | null; revoked_at: string | null; issued_by_name: string | null; school: (SchoolFacts & { id: string }) | null;
}
export interface UnattachedItem { id: string; name: string; status: 'DRAFT' | 'ACTIVE' | 'ARCHIVED'; contact_email: string; contact_phone: string | null;
  setup_step: string | null; setup_done: number; setup_completed_at: string | null }

/** Horodatage de la base (`+00:00`, microsecondes) ramené au format ISO du contrat. */
const iso = (value: string | null | undefined) => value ? new Date(value).toISOString() : null;

const schoolView = (school: SchoolFacts | null) => school ? {
  name: school.name, status: school.status, contactEmail: school.contact_email, contactPhone: school.contact_phone,
  setup: { step: school.setup_step, stepsDone: school.setup_done, stepsTotal: setupStepCount, completedAt: iso(school.setup_completed_at), savedAt: iso(school.setup_saved_at ?? null) },
} : null;
const codeView = (code: ClientItem['latest_code']) => code ? { id: code.id, state: code.status, expiresAt: iso(code.expires_at)!, createdAt: iso(code.created_at)! } : null;

export const clientSummary = (item: ClientItem) => ({
  id: item.id, displayName: item.display_name, preparation: item.preparation, schoolId: item.school_id, school: schoolView(item.school),
  contactName: item.contact_name, contactEmail: item.contact_email, latestCode: codeView(item.latest_code), commercial: commercialPlaceholder(),
  version: item.version, createdAt: iso(item.created_at)!, updatedAt: iso(item.updated_at)!,
});
export const clientDetail = (item: ClientItem, codes: ReturnType<typeof codeProjection>[]) => ({
  ...clientSummary(item),
  contactPhone: item.contact_phone,
  billing: { street: item.billing_street, postalCode: item.billing_postal_code, city: item.billing_city, country: item.billing_country },
  internalNotes: item.internal_notes,
  link: item.school_id ? { source: item.link_source!, linkedAt: iso(item.school_linked_at)!, issuedByName: item.issued_by_name } : null,
  codes,
});
export const codeProjection = (item: CodeItem) => ({
  id: item.id, state: item.state, clientId: item.client_id, clientName: item.client_name, createdAt: iso(item.created_at)!, expiresAt: iso(item.expires_at)!,
  usedAt: iso(item.used_at), revokedAt: iso(item.revoked_at), issuedByName: item.issued_by_name,
  school: item.school ? { id: item.school.id, ...schoolView(item.school)! } : null,
});
export const unattachedProjection = (item: UnattachedItem) => ({
  id: item.id, name: item.name, status: item.status, contactEmail: item.contact_email, contactPhone: item.contact_phone,
  setup: { step: item.setup_step, stepsDone: item.setup_done, stepsTotal: setupStepCount, completedAt: iso(item.setup_completed_at), savedAt: null },
});
