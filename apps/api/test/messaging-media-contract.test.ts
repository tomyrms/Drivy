import { readFile } from 'node:fs/promises';
import { expect, it } from 'vitest';
import { z } from 'zod';
import { mediaCancelEnvelopeSchema, mediaCancelResponseSchema, mediaErrorCodes, mediaErrorSchema, mediaMessageIntentSchema,
  mediaMessageSchema, mediaPutBodySchema, mediaUploadEnvelopeSchema, mediaUploadResponseSchema } from '../src/messaging-media-contract.js';

const project = (schema: z.ZodType) => { const { $schema: _ignored, ...definition } = z.toJSONSchema(schema); return definition; };

it('le contrat média suit exactement la projection servie, enveloppe et transport binaire compris', async () => {
  const contract = JSON.parse(await readFile(new URL('../contracts/messaging-media.json', import.meta.url), 'utf8')) as {
    $id: string; $defs: Record<string, Record<string, unknown>>; description: string };
  expect(contract.$id).toBe('urn:drivy:contract:messaging-media:1');
  expect(contract.description).toMatch(/3\.11\.0/);
  const { contentMediaType, $comment, ...putBody } = contract.$defs.MediaPutBody!;
  expect(putBody).toEqual(project(mediaPutBodySchema));
  // Annotation binaire explicite : le corps est brut, jamais une chaîne JSON ni du base64.
  expect(contentMediaType).toBe('application/octet-stream');
  expect($comment).toMatch(/BINAIRE BRUT/);
  expect(contract.$defs.MediaPutBody).not.toHaveProperty('contentEncoding');
  expect(contract.$defs).toMatchObject({
    MediaMessageIntent: project(mediaMessageIntentSchema),
    MediaUploadResponse: project(mediaUploadResponseSchema),
    MediaCancelResponse: project(mediaCancelResponseSchema),
    MediaMessage: project(mediaMessageSchema),
    MediaUploadEnvelope: project(mediaUploadEnvelopeSchema),
    MediaCancelEnvelope: project(mediaCancelEnvelopeSchema),
    MediaError: project(mediaErrorSchema)
  });
  // Un reçu de dépôt n'annonce que UPLOADED ou ATTACHED : PURGED est un refus, jamais un succès.
  const receiptStates = (contract.$defs.MediaUploadResponse!.properties as Record<string, { enum?: string[] }>).state!.enum;
  expect(receiptStates).toEqual(['UPLOADED', 'ATTACHED']);
  // L'enveloppe réellement servie fait partie du contrat, avec les codes réellement émis.
  const envelopeRequired = contract.$defs.MediaUploadEnvelope!.required as string[];
  expect(envelopeRequired.sort()).toEqual(['context', 'data', 'requestId', 'serverTime']);
  for (const code of ['UNSUPPORTED_MEDIA_TYPE', 'ACCESS_DENIED', 'INVALID_MEDIA', 'MEDIA_PURGED', 'MESSAGING_NOT_ENABLED'])
    expect(mediaErrorCodes).toContain(code as never);
  const serialized = JSON.stringify(contract.$defs);
  // Ni nom de fichier, ni type MIME de contenu, ni légende, ni clé, ni IV, ni miniature, ni hash du clair.
  expect(serialized).not.toMatch(/fileName|displayName|mimeType|"mime"|plaintext|caption|thumbnail|preview|"key"|"iv"/);
});
