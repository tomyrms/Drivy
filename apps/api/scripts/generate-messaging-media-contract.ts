import { writeFile } from 'node:fs/promises';
import { z } from 'zod';
import { mediaCancelEnvelopeSchema, mediaCancelResponseSchema, mediaErrorSchema, mediaMessageIntentSchema, mediaMessageSchema,
  mediaPutBodySchema, mediaUploadEnvelopeSchema, mediaUploadResponseSchema } from '../src/messaging-media-contract.js';

// Extension d'implémentation ; le contrat OpenAPI canonique 3.11.0 reste inchangé.
const project = (schema: z.ZodType) => { const { $schema: _ignored, ...definition } = z.toJSONSchema(schema); return definition; };
// JSON Schema n'a pas de type binaire : le corps du PUT est annoté, jamais converti en chaîne JSON ni en base64.
// La consommation réelle d'un Buffer brut est vérifiée par un test de transport distinct.
const binaryPutBody = {
  ...project(mediaPutBodySchema),
  contentMediaType: 'application/octet-stream',
  $comment: 'Corps BINAIRE BRUT (application/octet-stream) : les octets chiffrés sont le corps HTTP lui-même. '
    + 'Le type "string" et maxLength sont l’annotation JSON Schema de cette limite ; aucune chaîne JSON, aucun base64 '
    + 'et aucun objet descripteur n’est accepté par le service. Content-Length obligatoire et égal à la taille reçue.'
};
await writeFile(new URL('../contracts/messaging-media.json', import.meta.url), JSON.stringify({
  $schema: 'https://json-schema.org/draft/2020-12/schema', $id: 'urn:drivy:contract:messaging-media:1',
  title: 'Médias chiffrés de bout en bout de la messagerie (#97)',
  description: 'PUT/GET/DELETE /v1/schools/{schoolId}/messaging/conversations/{conversationId}/media/{mediaId} et champ media du POST messages. '
    + 'Le dossier de conception 3.11.0 reste immuable : aucune route n’y est ajoutée, ce fichier est le contrat exécutable. '
    + 'Les octets sont chiffrés par l’appareil et opaques pour le serveur : le serveur ne stocke ni nom, ni type MIME, ni légende, ni clé, ni IV, '
    + 'ni miniature, seulement identifiant, école, conversation, déposant, taille, SHA-256 du chiffré, octets, horodatages, état et message porteur. '
    + 'Un média est UPLOADED (octets sans message), ATTACHED (octets et message) ou PURGED (sans octets, marque de suppression conservée) ; PURGED est terminal. '
    + 'Les réponses média portent l’enveloppe { data, context, requestId, serverTime } ; un reçu de dépôt n’annonce que UPLOADED ou ATTACHED, jamais PURGED. '
    + 'GET répond application/octet-stream avec Cache-Control private, no-store et X-Drivy-Media-Sha256, ou un 404 MEDIA_NOT_FOUND uniforme. '
    + 'Le corps du PUT est binaire brut ; hors des routes média, application/octet-stream est refusé par le transport (415 UNSUPPORTED_MEDIA_TYPE). '
    + 'Le téléchargement relit la plage de séquence du lien, le masquage, la suppression et l’appareil déclaré actif ; la révocation est une garantie de compte.',
  $defs: {
    MediaPutBody: binaryPutBody,
    MediaMessageIntent: project(mediaMessageIntentSchema),
    MediaUploadResponse: project(mediaUploadResponseSchema),
    MediaCancelResponse: project(mediaCancelResponseSchema),
    MediaMessage: project(mediaMessageSchema),
    MediaUploadEnvelope: project(mediaUploadEnvelopeSchema),
    MediaCancelEnvelope: project(mediaCancelEnvelopeSchema),
    MediaError: project(mediaErrorSchema)
  }
}, null, 2) + '\n');
