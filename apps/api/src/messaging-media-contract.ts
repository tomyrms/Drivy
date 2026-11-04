import { z } from 'zod';
import { mediaMaxBytes, mediaStates } from './messaging-media.js';

/**
 * Extension exécutable du dépôt : l'OpenAPI canonique 3.11.0 reste immuable et ne reçoit aucune route média.
 * Les octets sont opaques pour le serveur ; ces schémas ne décrivent que des métadonnées de transport.
 * Aucun nom de fichier, type MIME, légende, clé, IV ni hash du clair n'apparaît dans une projection serveur.
 */
export const mediaErrorCodes = ['INVALID_MEDIA', 'PAYLOAD_TOO_LARGE', 'MESSAGING_DEVICE_REQUIRED', 'MEDIA_NOT_FOUND',
  'MEDIA_INTENT_CONFLICT', 'MEDIA_ALREADY_ATTACHED', 'MEDIA_SIZE_MISMATCH', 'MEDIA_PURGED', 'MESSAGING_NOT_ENABLED'] as const;
export type MediaErrorCode = typeof mediaErrorCodes[number];

/** Corps du PUT : octets chiffrés bruts, jamais du JSON, jamais un nom ou un type. */
export const mediaPutBodySchema = z.string().min(1).max(mediaMaxBytes)
  .describe('Octets chiffrés bruts, Content-Type application/octet-stream, Content-Length obligatoire et égal à la taille reçue.');

export const mediaUploadResponseSchema = z.object({
  mediaId: z.uuid(),
  byteSize: z.number().int().min(1).max(mediaMaxBytes),
  sha256: z.string().regex(/^[0-9a-f]{64}$/),
  state: z.enum(mediaStates)
}).strict();

export const mediaCancelResponseSchema = z.object({ mediaId: z.uuid(), deleted: z.literal(true) }).strict();

export const mediaMessageSchema = z.object({
  mediaId: z.uuid(),
  byteSize: z.number().int().min(1).max(mediaMaxBytes),
  deleted: z.boolean()
}).strict();

/** Corps d'erreur commun (application/problem+json), borné aux codes média stables. */
export const mediaErrorSchema = z.object({
  type: z.string(),
  title: z.string(),
  status: z.number().int().min(400).max(599),
  code: z.enum(mediaErrorCodes),
  requestId: z.uuid()
}).strict();
