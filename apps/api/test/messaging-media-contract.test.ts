import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { expect, it } from 'vitest';
import { z } from 'zod';
import { Ajv2020 } from 'ajv/dist/2020.js';
import { fullFormats } from 'ajv-formats/dist/formats.js';
import { mediaCancelEnvelopeSchema, mediaCancelResponseSchema, mediaErrorCodes, mediaErrorSchema, mediaMessageIntentSchema,
  mediaMessageSchema, mediaPutBodySchema, mediaUploadEnvelopeSchema, mediaUploadResponseSchema } from '../src/messaging-media-contract.js';

const project = (schema: z.ZodType) => { const { $schema: _ignored, ...definition } = z.toJSONSchema(schema); return definition; };
const readContract = async () => JSON.parse(await readFile(new URL('../contracts/messaging-media.json', import.meta.url), 'utf8')) as {
  $id: string; $defs: Record<string, Record<string, unknown>>; description: string };

it('le contrat média suit exactement la projection servie, enveloppe et transport binaire compris', async () => {
  const contract = await readContract();
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

it('le schéma d’intention média publié refuse exactement les cas que la frontière HTTP refuse', async () => {
  const contract = await readContract();
  const properties = contract.$defs.MediaMessageIntent!.properties as Record<string, Record<string, unknown>>;
  // Contraintes statiques réellement appliquées par le module média : UUID, entier sûr positif, plafond 4 Mio.
  expect(properties.mediaId!.format).toBe('uuid');
  expect(String(properties.mediaId!.pattern)).toMatch(/\[1-8\]/);
  expect(properties.byteSize).toEqual({ type: 'integer', minimum: 1, maximum: 4_194_304 });
  const invalid = [
    { label: 'identifiant non UUID', value: { mediaId: 'not-a-uuid', byteSize: 10 } },
    { label: 'taille zéro', value: { mediaId: randomUUID(), byteSize: 0 } },
    { label: 'taille fractionnaire', value: { mediaId: randomUUID(), byteSize: 1.5 } },
    { label: 'taille au-delà du plafond', value: { mediaId: randomUUID(), byteSize: 4_194_305 } },
    { label: 'taille négative', value: { mediaId: randomUUID(), byteSize: -1 } }
  ];
  for (const { label, value } of invalid)
    expect(mediaMessageIntentSchema.safeParse(value).success, label).toBe(false);
  // Un validateur indépendant applique le JSON Schema généré : il refuse les mêmes cas.
  const ajv = new Ajv2020({ strict: false, allErrors: true, formats: fullFormats });
  ajv.addSchema(contract);
  const validate = ajv.getSchema(`${contract.$id}#/$defs/MediaMessageIntent`);
  expect(validate, 'MediaMessageIntent').toBeTypeOf('function');
  for (const { label, value } of invalid)
    expect(validate!(value), label).toBe(false);
  // Les bornes valides restent acceptées par les deux.
  for (const value of [{ mediaId: randomUUID(), byteSize: 1 }, { mediaId: randomUUID(), byteSize: 4_194_304 }]) {
    expect(mediaMessageIntentSchema.safeParse(value).success, JSON.stringify(value)).toBe(true);
    expect(validate!(value), JSON.stringify(value)).toBe(true);
  }
});
