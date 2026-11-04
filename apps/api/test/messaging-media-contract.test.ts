import { readFile } from 'node:fs/promises';
import { expect, it } from 'vitest';
import { z } from 'zod';
import { mediaCancelResponseSchema, mediaErrorSchema, mediaMessageSchema, mediaPutBodySchema,
  mediaUploadResponseSchema } from '../src/messaging-media-contract.js';

const project = (schema: z.ZodType) => { const { $schema: _ignored, ...definition } = z.toJSONSchema(schema); return definition; };

it('le contrat média suit exactement la projection servie et ne divulgue aucun contenu', async () => {
  const contract = JSON.parse(await readFile(new URL('../contracts/messaging-media.json', import.meta.url), 'utf8')) as {
    $id: string; $defs: Record<string, unknown>; description: string };
  expect(contract.$id).toBe('urn:drivy:contract:messaging-media:1');
  expect(contract.description).toMatch(/3\.11\.0/);
  expect(contract.$defs).toEqual({
    MediaPutBody: project(mediaPutBodySchema),
    MediaUploadResponse: project(mediaUploadResponseSchema),
    MediaCancelResponse: project(mediaCancelResponseSchema),
    MediaMessage: project(mediaMessageSchema),
    MediaError: project(mediaErrorSchema)
  });
  const serialized = JSON.stringify(contract.$defs);
  // Ni nom de fichier, ni type MIME, ni légende, ni clé, ni IV, ni miniature, ni hash du clair.
  expect(serialized).not.toMatch(/fileName|displayName|mimeType|"mime"|plaintext|caption|thumbnail|preview|"key"|"iv"/);
});
