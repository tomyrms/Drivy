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
import {
  commercialDetailEnvelope, commercialDetailSchema, commercialRequestSchema, commercialRestrictionSchema, termsVersionSchema, trialChangeSchema
} from '../src/platform-commercial-contract.js';
import {
  decisionBody, paidStartBody, paidStartCancelBody, requestBody, termsBody, trialEndBody, trialExtendBody, trialStartBody
} from '../src/platform-commercial-model.js';
import {
  activationSchema, billingEnvelope, billingRunEnvelope, billingSchema, deliveryPreviewEnvelope, deliveryPreviewSchema, invoiceDeliverySchema, invoiceDocumentSchema, invoiceEnvelope, invoicePageEnvelope, invoiceSchema, issuerSchema, issuerSettingsEnvelope,
  issuerSettingsSchema, debtSchema, paymentSchema, settlementSchema
} from '../src/platform-billing-contract.js';
import {
  allocateBody, correctBody, paymentBody, regularizationCancelBody, regularizeBody, releaseBody, voidBody
} from '../src/platform-payments-model.js';
import {
  activationBody, activationStopBody, cancelBody, creditBody, deliveryBody, documentBody, documentQuery, invoiceListQuery, issueBody, issuerBody, prepareBody, runBody, sentBody
} from '../src/platform-billing-model.js';

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
    + 'et reste distinct de l’état commercial (NOT_CONFIGURED ou OFFER_ACTIVE, R01-T03) et du cycle commercial (lifecycle : NONE, TRIAL, TRIAL_EXPIRED, PAID, TERMINATED, R01-T04). '
    + 'dueDates liste au plus quatre échéances datées à venir (fin d’essai, début payant, prochaine période si les conditions sont complètes, résiliation), jamais un montant. '
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
    + 'La réponse dit seulement l’état commercial, le cycle commercial (lifecycle, restriction, fin d’essai, début payant, résiliation) et les modules accordés '
    + '(version, prochain changement, heure de calcul) : ni offre, ni montant, ni motif, ni auteur, ni historique. '
    + 'Un essai terminé ou un contrat résilié ferme tout usage nouveau (restriction.closes = WRITE_NEW) avec le même 403 MODULE_NOT_ENTITLED, dont le titre dit la marche à suivre ; '
    + 'la consultation et la fin des engagements déjà pris restent permises. Une école pilote sans essai ni début payant reste NONE, sans restriction. '
    + 'La web et l’iPhone relisent cette projection à l’ouverture et au retour en avant-plan ; un client ancien ou hors ligne n’est jamais l’autorité, '
    + 'car chaque écriture concernée est de toute façon refusée au serveur par 403 MODULE_NOT_ENTITLED. '
    + 'L’ETag porte la version des droits ; la réponse n’est jamais mise en cache (Cache-Control: no-store).',
  $defs: {
    SchoolEntitlements: project(schoolEntitlementsSchema),
    SchoolEntitlementsEnvelope: project(schoolEntitlementsEnvelope),
    ModuleNotEntitled: project(moduleNotEntitledSchema)
  }
}, null, 2) + '\n');

await writeFile(new URL('../contracts/platform-commercial.json', import.meta.url), JSON.stringify({
  $schema: 'https://json-schema.org/draft/2020-12/schema', $id: 'urn:drivy:contract:platform-commercial:1',
  title: 'Conditions commerciales, essai, début payant et demandes (R01-T04, #456)',
  description: 'GET /v1/platform/clients/{id}/commercial, POST /v1/platform/clients/{id}/commercial/terms, /trial/start, /trial/extend, /trial/end, '
    + '/paid-start, /paid-start/cancel, /requests et /requests/{requestId}/decision. '
    + 'Le dossier de conception 3.11.0 reste immuable : aucune route n’y est ajoutée, ce fichier est le contrat exécutable. '
    + 'Mêmes règles d’accès que le contrat des opérateurs (équipe relue en base, 403 PLATFORM_OPERATOR_REQUIRED sinon, Idempotency-Key égal à operationId). '
    + 'If-Match "N" porte la version du dossier commercial (428 sans version, 412 VERSION_CONFLICT si elle a changé) ; chaque commande rend le dossier relu après écriture. '
    + 'Montants entiers en centimes de CHF ; jours commerciaux en Europe/Zurich. Une version de conditions redonne toutes ses valeurs (null = à compléter) ; '
    + 'aucune n’est jamais modifiée ni supprimée. Après le début payant, une nouvelle version prend effet au prochain début de période ; '
    + 'une autre date exige un motif (409 TERMS_EXCEPTION_REASON_REQUIRED). Aucun prorata. Les périodes gardent le jour du mois du début payant, '
    + 'ramené au dernier jour des mois plus courts. Le début payant exige confirm=true, une date explicite et des conditions complètes à cette date (409 TERMS_INCOMPLETE). '
    + 'Un essai expiré ne crée aucun montant ; il ferme l’usage nouveau (lifecycle TRIAL_EXPIRED) sans retirer la consultation. '
    + 'Une résiliation acceptée est définitive et ferme l’usage nouveau à sa date. Les demandes (changement d’offre, résiliation) passent par '
    + 'RECEIVED, IN_PROGRESS puis ACCEPTED, REFUSED ou WITHDRAWN ; une décision est définitive. '
    + 'schedule est prévisionnel : aucune facture n’est émise (#457). billable n’est vrai qu’avec un début payant confirmé, des conditions complètes et sans résiliation effective. '
    + 'Le journal commercial reçoit l’action et les montants, jamais un motif ni une réponse en texte libre.',
  $defs: {
    CommercialRestriction: project(commercialRestrictionSchema),
    TermsVersion: project(termsVersionSchema),
    TrialChange: project(trialChangeSchema),
    CommercialRequest: project(commercialRequestSchema),
    CommercialDetail: project(commercialDetailSchema),
    TermsBody: project(termsBody),
    TrialStartBody: project(trialStartBody),
    TrialExtendBody: project(trialExtendBody),
    TrialEndBody: project(trialEndBody),
    PaidStartBody: project(paidStartBody),
    PaidStartCancelBody: project(paidStartCancelBody),
    RequestBody: project(requestBody),
    DecisionBody: project(decisionBody),
    CommercialDetailEnvelope: project(commercialDetailEnvelope),
    PlatformError: project(platformErrorSchema)
  }
}, null, 2) + '\n');

await writeFile(new URL('../contracts/platform-billing.json', import.meta.url), JSON.stringify({
  $schema: 'https://json-schema.org/draft/2020-12/schema', $id: 'urn:drivy:contract:platform-billing:1',
  title: 'Factures initiales et mensuelles, avoirs, préparation planifiée (R01-T05, #457), règlements manuels (R01-T06, #458), PDF et QR-facture (R01-T07, #459)',
  description: 'GET et POST /v1/platform/billing/issuer, GET /v1/platform/invoices, GET /v1/platform/invoices/{id}, POST /v1/platform/billing/run, '
    + 'GET /v1/platform/clients/{id}/billing, POST /v1/platform/clients/{id}/billing/activation, /billing/activation/stop, /invoices, '
    + '/invoices/{invoiceId}/issue, /invoices/{invoiceId}/cancel, /invoices/{invoiceId}/credit et /invoices/{invoiceId}/sent. '
    + 'Le dossier de conception 3.11.0 reste immuable : aucune route n’y est ajoutée, ce fichier est le contrat exécutable. '
    + 'Mêmes règles d’accès que le contrat des opérateurs (équipe relue en base, 403 PLATFORM_OPERATOR_REQUIRED sinon, Idempotency-Key égal à operationId). '
    + 'If-Match "N" porte la version de facturation de la fiche (ou la version des paramètres de l’émetteur) ; 412 VERSION_CONFLICT si elle a changé, 428 sans version. '
    + 'Montants entiers en centimes de CHF, jours en Europe/Zurich. Seule une fiche facturable (début payant confirmé, conditions complètes, aucune résiliation effective) '
    + 'peut être activée ; l’activation part d’aujourd’hui ou d’une date future. Une facture est d’abord un brouillon calculé dans la base à partir des conditions '
    + 'en vigueur ; l’émission fige numéro (F-AAAA-NNNNN, sans trou par année), émetteur, destinataire, taxe, total et échéance. Une facture émise ne change plus, '
    + 'sauf l’enregistrement de son envoi ; elle se corrige par un avoir total (AV-AAAA-NNNNN), puis une nouvelle génération pour la même période. '
    + 'Une période ou un montant initial n’a qu’une facture vivante par génération ; aucune facture n’est jamais supprimée. '
    + 'Le passage planifié (rôle drivy_billing_worker, une fois par heure) prépare puis émet ce qui est dû ; il ne fait rien sans activation et ne rattrape '
    + 'jamais plus de 24 documents par école et par passage. Taxe : NONE ou TVA au taux en points de base, prix TTC ou HT, arrondi au centime le plus proche. '
    + 'Règlements (R01-T06) : POST /v1/platform/clients/{id}/payments, /payments/{paymentId}/allocations, '
    + '/payments/{paymentId}/allocations/{allocationId}/release, /payments/{paymentId}/void, /payments/{paymentId}/correct, '
    + '/payments/{paymentId}/regularizations et /payments/{paymentId}/regularizations/{regularizationId}/cancel, sous la même version de facturation. '
    + 'Un règlement est un fait confirmé à la main par l’équipe, en CHF seulement ; aucun prestataire d’encaissement, et un téléchargement, un QR '
    + 'ou une déclaration de l’école ne règlent jamais une facture. Il s’affecte à des factures émises de la même école, sans dépasser son reste ni le solde '
    + 'de la facture ; à la saisie, les affectations sont données ou réparties de l’échéance la plus ancienne à la plus récente. Un même montant pour la même école '
    + 'à une référence identique ou à trois jours près est refusé (409 PAYMENT_POSSIBLE_DUPLICATE) sauf confirmDuplicate. Une correction annule l’original '
    + '(gardé, avec son auteur) et réaffecte le nouveau règlement aux mêmes factures ; une régularisation explicite sort un reste du règlement, '
    + 'aucun remboursement n’est déduit d’un avoir ni d’une correction. Un avoir est refusé tant qu’une facture porte des affectations (409 INVOICE_PAID). '
    + 'Solde, état de règlement, retard et dette sont calculés par la base (platform_invoice_settlement, platform_client_debt), le même calcul pour '
    + 'l’équipe, l’espace école et la suspension. La lecture par l’école (#460) et la suspension (#461) ne sont pas couvertes. '
    + 'Documents (R01-T07) : POST /v1/platform/clients/{id}/invoices/{invoiceId}/document, GET du même chemin (application/pdf, ?revision=, attachment, no-store), '
    + 'GET /invoices/{invoiceId}/delivery/preview et POST /invoices/{invoiceId}/delivery ({confirm:true, resend}). Un document est rendu une fois depuis l’instantané '
    + 'de la facture émise puis conservé. Section QR selon les directives SIX v2.4 : adresses structurées, compte CH/LI, QR-IBAN avec QRR ou IBAN avec SCOR, montant égal au total. '
    + 'Avoir, facture à zéro, créditée ou déjà réglée en partie sans QR antérieur : document sans ordre de paiement. Envoi au contact de facturation par une file durable '
    + 'chiffrée (rôle drivy_billing_mailer, sans droit de table) : QUEUED, PROCESSING, ACCEPTED (accepté par le serveur SMTP, ni livraison ni lecture prouvées), FAILED, '
    + 'UNCERTAIN (issue inconnue, jamais rejouée sans renvoi explicite), CANCELLED. Générer, télécharger, envoyer ou scanner ne règle jamais une facture. '
    + 'Le journal commercial reçoit l’action, le numéro et les montants, jamais un motif, une référence de paiement, une note, un IBAN ni une adresse électronique.',
  $defs: {
    Issuer: project(issuerSchema),
    IssuerSettings: project(issuerSettingsSchema),
    Invoice: project(invoiceSchema),
    InvoiceDocument: project(invoiceDocumentSchema),
    InvoiceDelivery: project(invoiceDeliverySchema),
    DeliveryPreview: project(deliveryPreviewSchema),
    DeliveryPreviewEnvelope: project(deliveryPreviewEnvelope),
    Activation: project(activationSchema),
    Billing: project(billingSchema),
    Settlement: project(settlementSchema),
    Payment: project(paymentSchema),
    Debt: project(debtSchema),
    IssuerBody: project(issuerBody),
    ActivationBody: project(activationBody),
    ActivationStopBody: project(activationStopBody),
    PrepareBody: project(prepareBody),
    IssueBody: project(issueBody),
    CancelBody: project(cancelBody),
    CreditBody: project(creditBody),
    SentBody: project(sentBody),
    DocumentBody: project(documentBody),
    DocumentQuery: project(documentQuery),
    DeliveryBody: project(deliveryBody),
    RunBody: project(runBody),
    PaymentBody: project(paymentBody),
    AllocateBody: project(allocateBody),
    ReleaseBody: project(releaseBody),
    VoidPaymentBody: project(voidBody),
    CorrectPaymentBody: project(correctBody),
    RegularizeBody: project(regularizeBody),
    RegularizationCancelBody: project(regularizationCancelBody),
    InvoiceListQuery: project(invoiceListQuery),
    IssuerSettingsEnvelope: project(issuerSettingsEnvelope),
    InvoiceEnvelope: project(invoiceEnvelope),
    InvoicePageEnvelope: project(invoicePageEnvelope),
    BillingEnvelope: project(billingEnvelope),
    BillingRunEnvelope: project(billingRunEnvelope),
    PlatformError: project(platformErrorSchema)
  }
}, null, 2) + '\n');
