import { z } from 'zod';

/**
 * Extension exécutable du dépôt : l'OpenAPI canonique 3.11.0 reste immuable et ne reçoit aucune route média.
 * Ces schémas sont la source unique des frontières réellement consommées : intention média du POST message,
 * réponses HTTP média (enveloppe comprise), message porteur et refus. Les octets restent opaques : le corps du PUT
 * est binaire brut (application/octet-stream), jamais du JSON ni du base64.
 * Aucun nom de fichier, type MIME, légende, clé, IV ni hash du clair n'apparaît dans une projection serveur.
 * Ce module ne dépend d'aucun module métier : les constantes de limite et d'état y sont définies, le module média
 * les réexporte, ce qui évite tout cycle d'initialisation.
 */
export const mediaMaxBytes = 4_194_304;
/** États qu'un reçu de dépôt peut annoncer : une purge est un refus, jamais un succès. */
export const mediaReceiptStates = ['UPLOADED', 'ATTACHED'] as const;
export type MediaReceiptState = typeof mediaReceiptStates[number];

export const mediaErrorCodes = ['INVALID_MEDIA', 'INVALID_REQUEST', 'PAYLOAD_TOO_LARGE', 'UNSUPPORTED_MEDIA_TYPE',
  'AUTHENTICATION_REQUIRED', 'ACCESS_DENIED', 'MESSAGING_DEVICE_REQUIRED', 'MEDIA_NOT_FOUND', 'MEDIA_INTENT_CONFLICT',
  'MEDIA_ALREADY_ATTACHED', 'MEDIA_SIZE_MISMATCH', 'MEDIA_PURGED', 'CONCURRENT_REQUEST', 'MESSAGING_NOT_ENABLED',
  'SERVICE_UNAVAILABLE'] as const;
export type MediaErrorCode = typeof mediaErrorCodes[number];

/** Intention média du POST message : validée à la frontière du domaine, donc refusée en INVALID_MEDIA. */
export const mediaMessageIntentSchema = z.object({
  mediaId: z.string().min(1).max(64),
  byteSize: z.number()
}).strict();

/**
 * Corps du PUT : octets chiffrés bruts. JSON Schema n'a pas de type binaire ; le générateur ajoute
 * `contentMediaType: application/octet-stream` comme annotation, et un test séparé vérifie que la route consomme
 * réellement un Buffer brut (aucune chaîne JSON ni base64 n'est acceptée comme substitut).
 */
export const mediaPutBodySchema = z.string().min(1).max(mediaMaxBytes)
  .describe('Octets chiffrés bruts, Content-Type application/octet-stream, Content-Length obligatoire et égal à la taille reçue.');

export const mediaUploadResponseSchema = z.object({
  mediaId: z.uuid(),
  byteSize: z.number().int().min(1).max(mediaMaxBytes),
  sha256: z.string().regex(/^[0-9a-f]{64}$/),
  state: z.enum(mediaReceiptStates)
}).strict();

export const mediaCancelResponseSchema = z.object({ mediaId: z.uuid(), deleted: z.literal(true) }).strict();

export const mediaMessageSchema = z.object({
  mediaId: z.uuid(),
  byteSize: z.number().int().min(1).max(mediaMaxBytes),
  deleted: z.boolean()
}).strict();

export const mediaContextSchema = z.object({
  schoolId: z.uuid(),
  actorPersonId: z.uuid(),
  accessEpoch: z.number().int().min(1)
}).strict();

/** Enveloppe réellement servie par les routes média : data, contexte, requestId technique, serverTime. */
export const mediaUploadEnvelopeSchema = z.object({
  data: mediaUploadResponseSchema,
  context: mediaContextSchema,
  requestId: z.uuid(),
  serverTime: z.iso.datetime()
}).strict();

export const mediaCancelEnvelopeSchema = z.object({
  data: mediaCancelResponseSchema,
  context: mediaContextSchema,
  requestId: z.uuid(),
  serverTime: z.iso.datetime()
}).strict();

/** Corps d'erreur commun (application/problem+json), borné aux codes réellement émis sur les routes média. */
export const mediaErrorSchema = z.object({
  type: z.string(),
  title: z.string(),
  status: z.number().int().min(400).max(599),
  code: z.enum(mediaErrorCodes),
  requestId: z.uuid()
}).strict();
