import { writeFile } from 'node:fs/promises';
import { z } from 'zod';
import {
  acceptInvitationBody, createInvitationBody, operationBody, platformErrorSchema, platformInvitationEnvelope, platformInvitationSchema, platformInvitationsEnvelope,
  platformJournalEntrySchema, platformJournalEnvelope, platformMeEnvelope, platformOperationEnvelope, platformOperatorEnvelope, platformOperatorSchema, platformOperatorsEnvelope,
  platformPreviewEnvelope, platformRightsSchema, previewInvitationBody
} from '../src/platform-contract.js';
import { journalQuery } from '../src/platform-model.js';
import {
  issuedCodeEnvelope, issuedCodeSchema, platformClientEnvelope, platformClientSchema, platformClientSummarySchema, platformClientsPageEnvelope, platformCodeEnvelope, platformCodeSchema,
  platformCodesPageEnvelope, unattachedSchoolSchema, unattachedSchoolsEnvelope
} from '../src/platform-clients-contract.js';
import {
  attachSchoolBody, clientListQuery, codeListQuery, createClientBody, issueCodeBody, revokeCodeBody, unattachedQuery, updateClientBody
} from '../src/platform-clients-model.js';
import {
  assignmentHistorySchema, adjustmentHistorySchema, assignmentPreviewEnvelope, assignmentPreviewSchema, clientEntitlementsEnvelope, clientEntitlementsSchema,
  entitlementModuleSchema, moduleNotEntitledSchema, offerSchema, platformModuleSchema, platformModulesEnvelope, platformOfferEnvelope, platformOffersEnvelope,
  schoolEntitlementsEnvelope, schoolEntitlementsSchema
} from '../src/platform-offers-contract.js';
import {
  adjustModuleBody, assignOfferBody, assignmentPreviewQuery, createOfferBody, liftAdjustmentBody, offerCommandBody, offerListQuery, updateOfferBody
} from '../src/platform-offers-model.js';

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

await writeFile(new URL('../contracts/platform-clients.json', import.meta.url), JSON.stringify({
  $schema: 'https://json-schema.org/draft/2020-12/schema', $id: 'urn:drivy:contract:platform-clients:1',
  title: 'Écoles clientes et codes d’ouverture (R01-T02, #454)',
  description: 'GET et POST /v1/platform/clients, GET et PATCH /v1/platform/clients/{id}, POST /v1/platform/clients/{id}/attach-school, '
    + 'GET /v1/platform/unattached-schools, GET et POST /v1/platform/school-codes, POST /v1/platform/school-codes/{id}/revoke. '
    + 'Le dossier de conception 3.11.0 reste immuable : aucune route n’y est ajoutée, ce fichier est le contrat exécutable. '
    + 'Mêmes règles d’accès que le contrat des opérateurs : équipe relue en base à chaque requête, 403 PLATFORM_OPERATOR_REQUIRED sinon, '
    + 'Idempotency-Key égal à operationId, If-Match "N" sur la modification et le rattachement (428 sans version, 412 VERSION_CONFLICT si elle a changé). '
    + 'Une fiche cliente est la relation commerciale avec une école : elle peut précéder l’école (code distribué), aucune zone n’est obligatoire. '
    + 'L’école et son premier ADMIN ne sont reliés qu’une fois, à l’utilisation du code ou par un rattachement explicite d’une école déjà ouverte ; '
    + 'le destinataire ne choisit ni offre ni privilège. L’état de préparation (AWAITING_SCHOOL, IN_PREPARATION, ACTIVE, ARCHIVED) est dérivé des faits de l’école '
    + 'et reste distinct de l’état commercial (NOT_CONFIGURED ou OFFER_ACTIVE, R01-T03 ; les montants, essais et échéances relèvent de #456, dueDates reste vide). '
    + 'Le code d’ouverture est tiré par la passerelle et ne figure dans aucune réponse du service : seule son empreinte à clé serveur est conservée. '
    + 'Les projections d’école se limitent à son nom, son contact, son état et la progression de sa mise en place : jamais un dossier, un trajet ni un message.',
  $defs: {
    PlatformClientSummary: project(platformClientSummarySchema),
    PlatformClient: project(platformClientSchema),
    PlatformCode: project(platformCodeSchema),
    UnattachedSchool: project(unattachedSchoolSchema),
    IssuedCode: project(issuedCodeSchema),
    CreateClientBody: project(createClientBody),
    UpdateClientBody: project(updateClientBody),
    AttachSchoolBody: project(attachSchoolBody),
    IssueCodeBody: project(issueCodeBody),
    RevokeCodeBody: project(revokeCodeBody),
    ClientListQuery: project(clientListQuery),
    CodeListQuery: project(codeListQuery),
    UnattachedQuery: project(unattachedQuery),
    ClientsPageEnvelope: project(platformClientsPageEnvelope),
    ClientEnvelope: project(platformClientEnvelope),
    CodesPageEnvelope: project(platformCodesPageEnvelope),
    CodeEnvelope: project(platformCodeEnvelope),
    UnattachedSchoolsEnvelope: project(unattachedSchoolsEnvelope),
    IssuedCodeEnvelope: project(issuedCodeEnvelope),
    PlatformError: project(platformErrorSchema)
  }
}, null, 2) + '\n');

await writeFile(new URL('../contracts/platform-offers.json', import.meta.url), JSON.stringify({
  $schema: 'https://json-schema.org/draft/2020-12/schema', $id: 'urn:drivy:contract:platform-offers:1',
  title: 'Offres, modules et droits par école (R01-T03, #455)',
  description: 'GET /v1/platform/modules, GET et POST /v1/platform/offers, PATCH /v1/platform/offers/{id}, POST /v1/platform/offers/{id}/archive et /restore, '
    + 'GET /v1/platform/clients/{id}/entitlements, GET /v1/platform/clients/{id}/assignment-preview, POST /v1/platform/clients/{id}/assignments, '
    + 'POST /v1/platform/clients/{id}/assignments/{assignmentId}/cancel, POST /v1/platform/clients/{id}/adjustments et '
    + 'POST /v1/platform/clients/{id}/adjustments/{adjustmentId}/lift. '
    + 'Le dossier de conception 3.11.0 reste immuable : aucune route n’y est ajoutée, ce fichier est le contrat exécutable. '
    + 'Mêmes règles d’accès que le contrat des opérateurs (équipe relue en base, 403 PLATFORM_OPERATOR_REQUIRED sinon, Idempotency-Key égal à operationId). '
    + 'Le catalogue de modules est stable (MESSAGING, COLLECTIVE_COURSES : uniquement ce qui est réellement livré) et se lit en base. '
    + 'Une offre est un ensemble de modules, sans montant, essai ni échéance (#456) ; la modifier ne change aucune école déjà attribuée, qui garde la copie '
    + 'des modules reçue à l’attribution. If-Match "N" porte la version de l’offre (modifier, archiver, restaurer) ou la version des droits de la fiche '
    + '(attribuer, annuler, ajuster, lever) ; 412 VERSION_CONFLICT si elle a changé, 428 sans version. '
    + 'La date d’effet est immédiate (absente ou nulle) ou strictement future ; une date passée répond 409 EFFECTIVE_DATE_PAST. '
    + 'L’aperçu des conséquences ne contient que des volumes d’objets existants par module, jamais un contenu ni un message. '
    + 'Un ajustement par école (GRANT ou REVOKE) porte un motif de 3 à 500 caractères et l’auteur ; il se rattache à l’attribution en vigueur, '
    + 'cesse de s’appliquer quand une autre attribution prend effet et reste lisible dans l’historique. Aucune ligne n’est jamais supprimée. '
    + 'Une fiche sans attribution (NOT_CONFIGURED) garde le périmètre historique : tous les modules du catalogue restent accordés. '
    + 'Le serveur refuse tout nouvel usage d’un module non accordé (403 MODULE_NOT_ENTITLED) ; lire l’historique et terminer un engagement déjà pris restent permis.',
  $defs: {
    PlatformModule: project(platformModuleSchema),
    Offer: project(offerSchema),
    EntitlementModule: project(entitlementModuleSchema),
    AssignmentHistory: project(assignmentHistorySchema),
    AdjustmentHistory: project(adjustmentHistorySchema),
    ClientEntitlements: project(clientEntitlementsSchema),
    AssignmentPreview: project(assignmentPreviewSchema),
    CreateOfferBody: project(createOfferBody),
    UpdateOfferBody: project(updateOfferBody),
    OfferCommandBody: project(offerCommandBody),
    OfferListQuery: project(offerListQuery),
    AssignOfferBody: project(assignOfferBody),
    AssignmentPreviewQuery: project(assignmentPreviewQuery),
    AdjustModuleBody: project(adjustModuleBody),
    LiftAdjustmentBody: project(liftAdjustmentBody),
    ModulesEnvelope: project(platformModulesEnvelope),
    OffersEnvelope: project(platformOffersEnvelope),
    OfferEnvelope: project(platformOfferEnvelope),
    ClientEntitlementsEnvelope: project(clientEntitlementsEnvelope),
    AssignmentPreviewEnvelope: project(assignmentPreviewEnvelope),
    PlatformError: project(platformErrorSchema)
  }
}, null, 2) + '\n');

await writeFile(new URL('../contracts/school-entitlements.json', import.meta.url), JSON.stringify({
  $schema: 'https://json-schema.org/draft/2020-12/schema', $id: 'urn:drivy:contract:school-entitlements:1',
  title: 'Droits commerciaux aux modules, côté école (R01-T03, #455)',
  description: 'GET /v1/schools/{schoolId}/entitlements. Réservé aux membres actifs de l’école, tous rôles confondus. '
    + 'Le dossier de conception 3.11.0 reste immuable : aucune route n’y est ajoutée, ce fichier est le contrat exécutable. '
    + 'La réponse dit seulement l’état commercial et les modules accordés (version, prochain changement, heure de calcul) : ni offre, ni motif, ni auteur, ni historique. '
    + 'La web et l’iPhone relisent cette projection à l’ouverture et au retour en avant-plan ; un client ancien ou hors ligne n’est jamais l’autorité, '
    + 'car chaque écriture concernée est de toute façon refusée au serveur par 403 MODULE_NOT_ENTITLED. '
    + 'L’ETag porte la version des droits ; la réponse n’est jamais mise en cache (Cache-Control: no-store).',
  $defs: {
    SchoolEntitlements: project(schoolEntitlementsSchema),
    SchoolEntitlementsEnvelope: project(schoolEntitlementsEnvelope),
    ModuleNotEntitled: project(moduleNotEntitledSchema)
  }
}, null, 2) + '\n');
