import { z } from 'zod';
import { acceptInvitationBody, createInvitationBody, operationBody, platformExcludedAccess, platformLevel, platformRights, previewInvitationBody } from './platform-model.js';

/**
 * Extension exécutable du dépôt (R01-T01, #453) : l'OpenAPI canonique 3.11.0 reste immuable et ne reçoit aucune route de plateforme.
 * Ces schémas sont la source unique des frontières servies par `src/platform.ts` ; `contracts/platform-operators.json` en est la projection.
 * Aucun code d'invitation, aucune empreinte de code, aucun jeton ni adresse complète n'apparaît dans une projection : seule l'adresse masquée.
 */
export const platformErrorCodes = ['INVALID_REQUEST', 'AUTHENTICATION_REQUIRED', 'PLATFORM_OPERATOR_REQUIRED', 'NOT_FOUND', 'PRECONDITION_REQUIRED',
  'VERSION_CONFLICT', 'IDEMPOTENCY_MISMATCH', 'LAST_PLATFORM_OPERATOR', 'PLATFORM_OPERATOR_REVOKED', 'PLATFORM_OPERATOR_EXISTS',
  'PLATFORM_ALREADY_MEMBER', 'PLATFORM_INVITATION_PENDING', 'PLATFORM_INVITATION_USED', 'PLATFORM_INVITATION_REVOKED', 'PLATFORM_INVITATION_EXPIRED',
  'PLATFORM_INVITATION_CLOSED', 'PLATFORM_INVITATION_INVALID', 'PLATFORM_INVITATION_EMAIL_MISMATCH', 'PLATFORM_CODE_TAKEN',
  'EMAIL_VERIFICATION_REQUIRED', 'INVITATION_CODE_ATTEMPTS', 'SERVICE_UNAVAILABLE',
  // Écoles clientes et codes d'ouverture (R01-T02).
  'INVALID_CURSOR', 'CLIENT_CODE_PENDING', 'CLIENT_SCHOOL_LINKED', 'CLIENT_SCHOOL_ALREADY_LINKED', 'OPENING_CODE_TAKEN', 'OPENING_LINK_USED', 'OPENING_LINK_REVOKED'] as const;
export type PlatformErrorCode = typeof platformErrorCodes[number];

const timestamp = z.iso.datetime();
const version = z.number().int().min(1);

export const platformRightsSchema = z.object({
  level: z.literal(platformLevel),
  rights: z.array(z.enum(platformRights)).min(1),
  notGranted: z.array(z.enum(platformExcludedAccess)).min(1)
}).strict();

export const platformOperatorSchema = z.object({
  id: z.uuid(), displayName: z.string().min(1).max(200), maskedEmail: z.string().nullable(), level: z.literal(platformLevel),
  status: z.enum(['ACTIVE', 'REVOKED']), addedVia: z.enum(['BOOTSTRAP', 'INVITATION']), joinedAt: timestamp, revokedAt: timestamp.nullable(),
  version, self: z.boolean()
}).strict();

export const platformInvitationSchema = z.object({
  id: z.uuid(), status: z.enum(['AVAILABLE', 'USED', 'REVOKED', 'EXPIRED']), level: z.literal(platformLevel), maskedEmail: z.string(),
  createdAt: timestamp, expiresAt: timestamp, version, usedAt: timestamp.nullable(), revokedAt: timestamp.nullable(), createdByName: z.string().nullable()
}).strict();

export const platformJournalEntrySchema = z.object({
  id: z.uuid(), occurredAt: timestamp, actorKind: z.enum(['OPERATOR', 'SYSTEM']), actorName: z.string().min(1).max(200),
  action: z.string().regex(/^[A-Z][A-Z0-9_]{2,63}$/), result: z.enum(['SUCCESS', 'REFUSED']), reasonCode: z.string().nullable(),
  schoolId: z.uuid().nullable(), subject: z.object({ type: z.string(), id: z.uuid() }).strict().nullable(), operationId: z.uuid().nullable(),
  changes: z.record(z.string(), z.unknown())
}).strict();

export const platformMeSchema = platformRightsSchema.extend({ operator: platformOperatorSchema }).strict();
export const platformOperatorsSchema = z.object({ items: z.array(platformOperatorSchema) }).strict();
export const platformInvitationsSchema = z.object({ items: z.array(platformInvitationSchema) }).strict();
export const platformJournalSchema = z.object({ items: z.array(platformJournalEntrySchema), nextCursor: z.string().nullable() }).strict();
export const platformPreviewSchema = platformRightsSchema.extend({
  status: z.literal('AVAILABLE'), maskedEmail: z.string(), expiresAt: timestamp, matchesAccount: z.boolean(), alreadyMember: z.boolean()
}).strict();
export const platformOperationSchema = z.object({
  operationId: z.uuid(), kind: z.string().regex(/^[A-Z][A-Z0-9_]{2,63}$/), statusCode: z.number().int().min(200).max(299), result: z.unknown()
}).strict();

const envelope = <T extends z.ZodType>(data: T) => z.object({ data, requestId: z.uuid(), serverTime: timestamp }).strict();
export const platformMeEnvelope = envelope(platformMeSchema);
export const platformOperatorsEnvelope = envelope(platformOperatorsSchema);
export const platformInvitationsEnvelope = envelope(platformInvitationsSchema);
export const platformInvitationEnvelope = envelope(platformInvitationSchema);
export const platformOperatorEnvelope = envelope(platformOperatorSchema);
export const platformJournalEnvelope = envelope(platformJournalSchema);
export const platformPreviewEnvelope = envelope(platformPreviewSchema);
export const platformOperationEnvelope = envelope(platformOperationSchema);

/** Corps d'erreur commun (application/problem+json), borné aux codes réellement émis sur les routes de la plateforme. */
export const platformErrorSchema = z.object({
  type: z.string(), title: z.string(), status: z.number().int().min(400).max(599), code: z.enum(platformErrorCodes), requestId: z.uuid()
}).strict();

export { acceptInvitationBody, createInvitationBody, operationBody, previewInvitationBody };
