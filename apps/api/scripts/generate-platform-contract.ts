import { writeFile } from 'node:fs/promises';
import { z } from 'zod';
import {
  acceptInvitationBody, createInvitationBody, operationBody, platformErrorSchema, platformInvitationEnvelope, platformInvitationSchema, platformInvitationsEnvelope,
  platformJournalEntrySchema, platformJournalEnvelope, platformMeEnvelope, platformOperationEnvelope, platformOperatorEnvelope, platformOperatorSchema, platformOperatorsEnvelope,
  platformPreviewEnvelope, platformRightsSchema, previewInvitationBody
} from '../src/platform-contract.js';
import { journalQuery } from '../src/platform-model.js';

// Extension d'implémentation ; le contrat OpenAPI canonique 3.11.0 reste inchangé.
const project = (schema: z.ZodType) => { const { $schema: _ignored, ...definition } = z.toJSONSchema(schema, { io: 'input' }); return definition; };
await writeFile(new URL('../contracts/platform-operators.json', import.meta.url), JSON.stringify({
  $schema: 'https://json-schema.org/draft/2020-12/schema', $id: 'urn:drivy:contract:platform-operators:1',
  title: 'Console des opérateurs de la plateforme (R01-T01, #453)',
  description: 'GET /v1/platform/me, GET /v1/platform/operators, GET et POST /v1/platform/invitations, POST /v1/platform/invitations/{id}/revoke, '
    + 'POST /v1/platform/operators/{id}/revoke, GET /v1/platform/operations/{operationId}, GET /v1/platform/journal, '
    + 'POST /v1/platform/invitations/preview et POST /v1/platform/invitations/accept. '
    + 'Le dossier de conception 3.11.0 reste immuable : aucune route n’y est ajoutée, ce fichier est le contrat exécutable. '
    + 'L’appartenance à l’équipe est relue dans la base à chaque requête ; un compte scolaire, un élève ou un ancien opérateur reçoit 403 PLATFORM_OPERATOR_REQUIRED. '
    + 'Un seul niveau de droits (COMMERCIAL) : gérer l’équipe, ouvrir des écoles, lire le journal commercial ; jamais dossiers, trajets, messages ni rôle scolaire. '
    + 'Les mutations portent Idempotency-Key égal à operationId ; les retraits portent aussi If-Match "N" (428 sans version, 412 VERSION_CONFLICT si elle a changé). '
    + 'Un rejeu à l’identique rend le reçu durable ; la même clé avec un autre contenu répond 409 IDEMPOTENCY_MISMATCH. '
    + 'Le dernier opérateur actif ne peut pas être retiré (409 LAST_PLATFORM_OPERATOR), y compris en concurrence. '
    + 'Les codes d’accès à la plateforme (XXXXX-XXXXX) sont distincts des codes d’ouverture d’école ; la base ne conserve qu’une empreinte à clé serveur. '
    + 'Aucune réponse ne contient le code, son empreinte, un jeton ni une adresse complète : l’adresse est masquée. '
    + 'Le journal commercial est en ajout seul : acteur, date, école éventuelle, action, résultat (SUCCESS ou REFUSED) et modification utile.',
  $defs: {
    PlatformRights: project(platformRightsSchema),
    PlatformOperator: project(platformOperatorSchema),
    PlatformInvitation: project(platformInvitationSchema),
    PlatformJournalEntry: project(platformJournalEntrySchema),
    CreateInvitationBody: project(createInvitationBody),
    OperationBody: project(operationBody),
    PreviewInvitationBody: project(previewInvitationBody),
    AcceptInvitationBody: project(acceptInvitationBody),
    JournalQuery: project(journalQuery),
    MeEnvelope: project(platformMeEnvelope),
    OperatorsEnvelope: project(platformOperatorsEnvelope),
    OperatorEnvelope: project(platformOperatorEnvelope),
    InvitationsEnvelope: project(platformInvitationsEnvelope),
    InvitationEnvelope: project(platformInvitationEnvelope),
    JournalEnvelope: project(platformJournalEnvelope),
    PreviewEnvelope: project(platformPreviewEnvelope),
    OperationEnvelope: project(platformOperationEnvelope),
    PlatformError: project(platformErrorSchema)
  }
}, null, 2) + '\n');
