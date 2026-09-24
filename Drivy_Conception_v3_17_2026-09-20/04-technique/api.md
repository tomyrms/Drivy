# Contrats API, erreurs et exemples de transaction

> Drivy · Dossier de conception 3.13 · 20 septembre 2026
> Statut : proposition de référence, à valider avant réalisation. [Index](../README.md).

## Observations pendant la leçon : contrat courant

AP161–AP164 servent désormais F15 **et** F16. `GeoObservationCommand.draftId` accepte null uniquement avec origin LIVE ; observedAt, eventKind et eventStatus sont alors requis. Un événement QUALIFIED exige une compétence de la formation et un statut choisi ; MARKER reste privé et non publiable. Le serveur fixe l’auteur. Les charges héritées sans origin restent REVIEW et exigent leur brouillon.

AP49 rattache les observations privées sous le verrou de leçon sans les publier. Une arrivée après publication retourne OBSERVATION_REVIEW_REQUIRED ; une ancre pas encore reçue retourne ANCHOR_NOT_READY, sans faux succès. Les versions et clés d’idempotence sont conservées selon [R46](../03-fonctionnel/regles-etats.md#r46). Les snapshots publiés copient les métadonnées relues sans déduire une note. Les règles métier ne sont pas démontrées par le seul schéma.


**Ouverture du signalement : aucun endpoint.** Le contexte de saisie est local au client ; AP162 n’est émis qu’après confirmation explicite et journalisation. `observedAt` transporte l’instant figé à l’ouverture, distinct du temps d’envoi ; le triplet d’ancre reprend une mesure déjà admissible, jamais la position au moment de la fermeture. Aucun champ, schéma ou endpoint n’est ajouté pour le panneau. L’annulation avant confirmation n’appelle pas AP164 ; après émission incertaine, le client réconcilie d’abord l’idempotence. [Règle détaillée](../03-fonctionnel/gps-replay.md#instant-signalement).

## Statut et portée

Le fichier [openapi.yaml](openapi.yaml) est un contrat machine-lisible **de conception**. Il décrit le cœur proposé, pas l’API existante du ZIP. Aucun serveur réel ni secret n’y figure. Il ne signifie pas que les endpoints ont été implémentés, compilés ou testés. Les règles [R01–R112](../03-fonctionnel/regles-etats.md) et la [matrice de permissions](../03-fonctionnel/roles-permissions.md) complètent la validation de forme.

## Conventions communes

Préfixe `/v1`. Contexte scolaire dans le chemin, vérifié contre l’identité authentifiée. Corps JSON stricts, champs inconnus refusés. Réponses `{data, requestId, serverTime}`. Pagination opaque stable, 50 par défaut, 100 maximum, ordre documenté par ressource : leçons par `(plannedStart,id)`, bilans par `(date de leçon,id,sequence)`, autres listes par `(createdAt,id)` lorsque disponible. Le curseur fixe les filtres et la portée ; le modifier ou changer d’école le rend invalide.

Les commandes portent `operationId` et `Idempotency-Key` identiques. Les mutations d’une ressource existante exigent `If-Match` avec version forte selon la colonne Version requise, sauf les exceptions explicitement définies en R11 (chunks immuables, écritures append-only prévues et arrêt de sécurité monotone) ; les créations sans ressource antérieure ne possèdent pas cette précondition, mais gardent l’idempotence et les contrôles transactionnels. Les ressources un-à-un Preparation et Wish sont créées vides avec la leçon/formation, ce qui évite une ambiguïté de premier PUT sans version. Leurs objets vides n’impliquent aucune observation. L’API renvoie une version actuelle autorisée ou permet de la recharger ; elle ne révèle jamais un objet d’une autre école.

Le schéma OpenAPI encode la structure ; il ne peut pas exprimer à lui seul les transactions, la portée des droits, la correspondance catégorie/pièce, la décision de publication ni les contraintes temporelles. Ces validations sont dans les services et la base. Les codes d’erreur sont stables ; le texte est localisable. Un 403 de révocation n’autorise pas à conserver un affichage de cache.

Les instants incluent un offset ou Z ; le fuseau de l’école demeure un champ séparé. Une date de validité est `YYYY-MM-DD`, pas un instant UTC. Montants entiers en centimes dans les bornes exactement représentables en JSON. L’API ne reçoit ni montant flottant « 90.00 », ni numéro de carte.

## Catalogue des opérations

| ID | Méthode et chemin | Fonction | Corps → data de réponse finale | Version requise |
|---|---|---|---|---|
| AP01 | `GET /v1/me` | F01 | `sans corps` → `Me` | Non |
| AP02 | `POST /v1/session/logout` | F01 | `LogoutCommand` → `Ack` | Non |
| AP03 | `POST /v1/session/offline-lease` | F01 F12 | `LeaseCommand` → `OfflineLease` | Non |
| AP04 | `POST /v1/invitations/accept` | F02 | `AcceptInvitationCommand` → `MemberContext` | Non |
| AP05 | `GET /v1/schools/{schoolId}` | F13 | `sans corps` → `School` | Non |
| AP06 | `PATCH /v1/schools/{schoolId}` | F13 | `SchoolUpdateCommand` → `School` | Oui |
| AP07 | `GET /v1/schools/{schoolId}/members` | F01 F13 | `sans corps` → `MemberPage` | Non |
| AP08 | `PATCH /v1/schools/{schoolId}/members/{membershipId}` | F01 F13 | `UpdateMemberCommand` → `Member` | Oui |
| AP09 | `POST /v1/schools/{schoolId}/members/{membershipId}/revoke` | F01 F13 | `ReasonCommand` → `Member` | Oui |
| AP10 | `GET /v1/schools/{schoolId}/invitations` | F02 | `sans corps` → `InvitationPage` | Non |
| AP11 | `POST /v1/schools/{schoolId}/invitations` | F02 | `InviteCommand` → `Invitation` | Non |
| AP12 | `POST /v1/schools/{schoolId}/invitations/{invitationId}/resend` | F02 | `EmptyCommand` → `Invitation` | Oui |
| AP13 | `POST /v1/schools/{schoolId}/invitations/{invitationId}/revoke` | F02 | `ReasonCommand` → `Invitation` | Oui |
| AP14 | `GET /v1/schools/{schoolId}/learners` | F02 F22 | `sans corps` → `LearnerPage` | Non |
| AP15 | `GET /v1/schools/{schoolId}/learners/{learnerId}` | F02 | `sans corps` → `Learner` | Non |
| AP16 | `PATCH /v1/schools/{schoolId}/learners/{learnerId}` | F02 | `UpdateLearnerCommand` → `Learner` | Oui |
| AP17 | `POST /v1/schools/{schoolId}/learners/{learnerId}/archive` | F14 F22 | `ArchiveCommitCommand` → `Learner` | Oui |
| AP18 | `GET /v1/schools/{schoolId}/offerings` | F03 F13 | `sans corps` → `OfferingPage` | Non |
| AP19 | `POST /v1/schools/{schoolId}/offerings` | F03 F13 | `OfferingCommand` → `Offering` | Non |
| AP20 | `GET /v1/schools/{schoolId}/curricula` | F08 F13 | `sans corps` → `CurriculumPage` | Non |
| AP21 | `POST /v1/schools/{schoolId}/curricula` | F08 F13 | `CurriculumCommand` → `Curriculum` | Non |
| AP22 | `GET /v1/schools/{schoolId}/trainings` | F03 | `sans corps` → `TrainingPage` | Non |
| AP23 | `POST /v1/schools/{schoolId}/trainings` | F03 | `CreateTrainingCommand` → `Training` | Non |
| AP24 | `GET /v1/schools/{schoolId}/trainings/{trainingId}` | F03 | `sans corps` → `Training` | Non |
| AP25 | `POST /v1/schools/{schoolId}/trainings/{trainingId}/state` | F03 | `TrainingStateCommand` → `Training` | Oui |
| AP26 | `GET /v1/schools/{schoolId}/trainings/{trainingId}/assignments` | F03 | `sans corps` → `AssignmentPage` | Non |
| AP27 | `POST /v1/schools/{schoolId}/trainings/{trainingId}/assignments` | F03 | `AssignCommand` → `Assignment` | Non |
| AP28 | `POST /v1/schools/{schoolId}/assignments/{assignmentId}/end` | F03 | `ReasonCommand` → `Assignment` | Oui |
| AP29 | `GET /v1/schools/{schoolId}/trainings/{trainingId}/permit-checks` | F03 | `sans corps` → `PermitCheckPage` | Non |
| AP30 | `POST /v1/schools/{schoolId}/trainings/{trainingId}/permit-checks` | F03 | `PermitCommand` → `PermitCheck` | Oui |
| AP31 | `GET /v1/schools/{schoolId}/availability-rules` | F04 | `sans corps` → `AvailabilityRulePage` | Non |
| AP32 | `POST /v1/schools/{schoolId}/availability-rules` | F04 | `AvailabilityCommand` → `AvailabilityRule` | Non |
| AP33 | `PUT /v1/schools/{schoolId}/availability-rules/{availabilityRuleId}` | F04 | `AvailabilityCommand` → `AvailabilityRule` | Oui |
| AP34 | `POST /v1/schools/{schoolId}/availability-rules/{availabilityRuleId}/remove` | F04 | `ReasonCommand` → `Ack` | Oui |
| AP35 | `GET /v1/schools/{schoolId}/closures` | F04 | `sans corps` → `ClosurePage` | Non |
| AP36 | `POST /v1/schools/{schoolId}/closures` | F04 | `ClosureCommand` → `Closure` | Non |
| AP37 | `POST /v1/schools/{schoolId}/closures/{closureId}/remove` | F04 | `ReasonCommand` → `Ack` | Oui |
| AP38 | `GET /v1/schools/{schoolId}/slots` | F04 F05 | `sans corps` → `SlotList` | Non |
| AP39 | `GET /v1/schools/{schoolId}/lessons` | F05 | `sans corps` → `LessonPage` | Non |
| AP40 | `POST /v1/schools/{schoolId}/lessons` | F05 | `CreateLessonCommand` → `Lesson` | Non |
| AP41 | `GET /v1/schools/{schoolId}/lessons/{lessonId}` | F05 | `sans corps` → `Lesson` | Non |
| AP42 | `POST /v1/schools/{schoolId}/lessons/{lessonId}/move` | F05 | `MoveLessonCommand` → `Lesson` | Oui |
| AP43 | `POST /v1/schools/{schoolId}/lessons/{lessonId}/cancel` | F05 F07 | `CancelLessonCommand` → `Lesson` | Oui |
| AP44 | `POST /v1/schools/{schoolId}/lessons/{lessonId}/no-show` | F07 | `ReasonCommand` → `Lesson` | Oui |
| AP45 | `GET /v1/schools/{schoolId}/lessons/{lessonId}/preparation` | F06 | `sans corps` → `Preparation` | Non |
| AP46 | `PUT /v1/schools/{schoolId}/lessons/{lessonId}/preparation` | F06 | `PreparationCommand` → `Preparation` | Oui |
| AP47 | `GET /v1/schools/{schoolId}/trainings/{trainingId}/wish` | F06 | `sans corps` → `Wish` | Non |
| AP48 | `PUT /v1/schools/{schoolId}/trainings/{trainingId}/wish` | F06 | `WishCommand` → `Wish` | Oui |
| AP49 | `POST /v1/schools/{schoolId}/lessons/{lessonId}/complete` | F07 F08 | `CompleteCommand` → `CompletionResult` | Oui |
| AP50 | `POST /v1/schools/{schoolId}/lessons/{lessonId}/correct-outcome` | F07 | `CorrectOutcomeCommand` → `Lesson` | Oui |
| AP51 | `POST /v1/schools/{schoolId}/lessons/{lessonId}/report-drafts` | F08 | `CreateCorrectionDraftCommand` → `ReportDraft` | Oui |
| AP52 | `GET /v1/schools/{schoolId}/report-drafts/{draftId}` | F08 | `sans corps` → `ReportDraft` | Non |
| AP53 | `PUT /v1/schools/{schoolId}/report-drafts/{draftId}` | F08 | `SaveDraftCommand` → `ReportDraft` | Oui |
| AP54 | `POST /v1/schools/{schoolId}/report-drafts/{draftId}/publish` | F08 | `PublishCommand` → `ReportRevision` | Oui |
| AP55 | `GET /v1/schools/{schoolId}/lessons/{lessonId}/reports` | F08 | `sans corps` → `ReportRevisionPage` | Non |
| AP56 | `GET /v1/schools/{schoolId}/report-revisions/{revisionId}` | F08 | `sans corps` → `ReportRevision` | Non |
| AP57 | `POST /v1/schools/{schoolId}/lessons/{lessonId}/report-publication/withdraw` | F08 F14 | `ReasonCommand` → `Ack` | Oui |
| AP58 | `GET /v1/schools/{schoolId}/trainings/{trainingId}/progress` | F08 | `sans corps` → `Progress` | Non |
| AP59 | `GET /v1/schools/{schoolId}/documents` | F09 | `sans corps` → `DocumentPage` | Non |
| AP60 | `POST /v1/schools/{schoolId}/documents/upload-intents` | F09 | `UploadCommand` → `UploadTicket` | Non |
| AP61 | `POST /v1/schools/{schoolId}/documents/{documentId}/complete-upload` | F09 | `CompleteUploadCommand` → `Document` | Oui |
| AP62 | `GET /v1/schools/{schoolId}/documents/{documentId}` | F09 | `sans corps` → `Document` | Non |
| AP63 | `POST /v1/schools/{schoolId}/documents/{documentId}/download-ticket` | F09 | `EmptyCommand` → `DownloadTicket` | Non |
| AP64 | `POST /v1/schools/{schoolId}/documents/{documentId}/request-delete` | F09 F14 | `ReasonCommand` → `PrivacyRequest` | Oui |
| AP65 | `GET /v1/schools/{schoolId}/lessons/{lessonId}/account` | F10 | `sans corps` → `Account` | Non |
| AP66 | `POST /v1/schools/{schoolId}/lessons/{lessonId}/payments` | F10 | `PaymentCommand` → `Account` | Oui |
| AP67 | `POST /v1/schools/{schoolId}/lessons/{lessonId}/refunds` | F10 | `RefundCommand` → `Account` | Oui |
| AP68 | `POST /v1/schools/{schoolId}/lessons/{lessonId}/charge-adjustments` | F10 | `ChargeAdjustmentCommand` → `Account` | Oui |
| AP69 | `GET /v1/schools/{schoolId}/notifications` | F11 | `sans corps` → `NotificationPage` | Non |
| AP70 | `POST /v1/schools/{schoolId}/notifications/{notificationId}/viewed` | F11 | `EmptyCommand` → `Notification` | Oui |
| AP71 | `POST /v1/schools/{schoolId}/notifications/{notificationId}/retry-delivery` | F11 | `ReasonCommand` → `Notification` | Oui |
| AP72 | `GET /v1/schools/{schoolId}/operations/{operationId}` | F12 | `sans corps` → `OperationResult` | Non |
| AP73 | `POST /v1/schools/{schoolId}/sync/snapshots` | F12 | `SnapshotCommand` → `Snapshot` | Non |
| AP74 | `GET /v1/schools/{schoolId}/sync/snapshots/{snapshotId}` | F12 | `sans corps` → `SnapshotPage` | Non |
| AP75 | `GET /v1/schools/{schoolId}/sync/changes` | F12 | `sans corps` → `SyncPage` | Non |
| AP76 | `GET /v1/schools/{schoolId}/privacy-requests` | F14 | `sans corps` → `PrivacyRequestPage` | Non |
| AP77 | `POST /v1/schools/{schoolId}/privacy-requests` | F14 | `PrivacyRequestCommand` → `PrivacyRequest` | Non |
| AP78 | `GET /v1/schools/{schoolId}/privacy-requests/{requestId}` | F14 | `sans corps` → `PrivacyRequest` | Non |
| AP79 | `POST /v1/schools/{schoolId}/privacy-requests/{requestId}/decision` | F14 | `PrivacyDecisionCommand` → `PrivacyRequest` | Oui |
| AP80 | `POST /v1/schools/{schoolId}/privacy-requests/{requestId}/exports` | F14 | `EmptyCommand` → `Export` | Oui |
| AP81 | `GET /v1/schools/{schoolId}/exports/{exportId}` | F14 | `sans corps` → `Export` | Non |
| AP82 | `POST /v1/schools/{schoolId}/exports/{exportId}/download-ticket` | F14 | `EmptyCommand` → `ExportDownloadTicket` | Non |
| AP83 | `GET /v1/schools/{schoolId}/audit-events` | F13 F14 | `sans corps` → `AuditEventPage` | Non |
| AP84 | `POST /v1/schools/{schoolId}/school-assets/upload-intents` | F13 | `AssetUploadCommand` → `AssetUploadTicket` | Non |
| AP85 | `GET /v1/schools/{schoolId}/school-assets/{assetId}` | F13 | `sans corps` → `SchoolAsset` | Non |
| AP86 | `POST /v1/schools/{schoolId}/school-assets/{assetId}/complete-upload` | F13 | `CompleteUploadCommand` → `SchoolAsset` | Oui |
| AP87 | `POST /v1/schools/{schoolId}/school-assets/{assetId}/download-ticket` | F13 | `EmptyCommand` → `AssetDownloadTicket` | Non |
| AP88 | `POST /v1/schools/{schoolId}/lessons/{lessonId}/outcome-approvals` | F07 | `ApproveOutcomeCommand` → `OutcomeApproval` | Oui |
| AP89 | `PATCH /v1/me` | F01 | `UpdateMeCommand` → `Me` | Oui |
| AP90 | `GET /v1/schools/{schoolId}/documents/{documentId}/content` | F09 | `sans corps` → `binaire JPEG/PNG/PDF` | Non |
| AP91 | `GET /v1/schools/{schoolId}/exports/{exportId}/content` | F14 | `sans corps` → `binaire CSV UTF-8 ou ZIP selon kind` | Non |
| AP92 | `GET /v1/schools/{schoolId}/school-assets/{assetId}/content` | F13 | `sans corps` → `binaire JPEG/PNG` | Non |
| AP93 | `POST /v1/schools/{schoolId}/lessons/{lessonId}/payment-reversals` | F10 | `ReversePaymentCommand` → `Account` | Oui |
| AP94 | `GET /v1/schools/{schoolId}/policy-versions` | F13 | `sans corps` → `SchoolPolicyPage` | Non |
| AP95 | `POST /v1/schools/{schoolId}/policy-versions` | F13 | `SchoolPolicyCommand` → `SchoolPolicy` | Non |
| AP96 | `GET /v1/schools/{schoolId}/sites` | F13 | `sans corps` → `SchoolSitePageV2` | Non |
| AP97 | `POST /v1/schools/{schoolId}/sites` | F13 | `SiteCommand` → `SchoolSite` | Non |
| AP98 | `GET /v1/schools/{schoolId}/rooms` | F13 | `sans corps` → `RoomPageV2` | Non |
| AP99 | `POST /v1/schools/{schoolId}/rooms` | F13 | `RoomCommand` → `Room` | Non |
| AP100 | `GET /v1/schools/{schoolId}/service-products` | F17 | `sans corps` → `ServiceProductVersionPageV2` | Non |
| AP101 | `POST /v1/schools/{schoolId}/service-products` | F17 | `ServiceProductCommand` → `ServiceProductVersion` | Non |
| AP102 | `GET /v1/schools/{schoolId}/pack-offers` | F17 | `sans corps` → `PackOfferVersionPageV2` | Non |
| AP103 | `POST /v1/schools/{schoolId}/pack-offers` | F17 | `PackOfferCommand` → `PackOfferVersion` | Non |
| AP104 | `PUT /v1/schools/{schoolId}/sites/{siteId}` | F13 | `SiteCommand` → `SchoolSite` | Oui |
| AP105 | `PUT /v1/schools/{schoolId}/rooms/{roomId}` | F13 | `RoomCommand` → `Room` | Oui |
| AP106 | `POST /v1/schools/{schoolId}/service-products/{productVersionId}/archive` | F17 | `ReasonCommand` → `ServiceProductVersion` | Oui |
| AP107 | `POST /v1/schools/{schoolId}/pack-offers/{offerVersionId}/archive` | F17 | `ReasonCommand` → `PackOfferVersion` | Oui |
| AP108 | `GET /v1/schools/{schoolId}/learners/{learnerId}/purchases` | F17 | `sans corps` → `PurchasePageV2` | Non |
| AP109 | `POST /v1/schools/{schoolId}/purchases` | F17 | `PurchaseCommand` → `Purchase` | Non |
| AP110 | `GET /v1/schools/{schoolId}/purchases/{purchaseId}` | F17 | `sans corps` → `Purchase` | Non |
| AP111 | `POST /v1/schools/{schoolId}/purchases/{purchaseId}/cancel` | F17 | `ReasonCommand` → `Purchase` | Oui |
| AP112 | `GET /v1/schools/{schoolId}/learners/{learnerId}/entitlements` | F17 | `sans corps` → `EntitlementLotPageV2` | Non |
| AP113 | `GET /v1/schools/{schoolId}/entitlements/{lotId}/movements` | F17 | `sans corps` → `EntitlementMovementPageV2` | Non |
| AP114 | `POST /v1/schools/{schoolId}/entitlements/{lotId}/restore` | F17 | `RestoreEntitlementCommand` → `EntitlementLot` | Oui |
| AP115 | `GET /v1/schools/{schoolId}/accounts/{accountId}` | F10 | `sans corps` → `Account` | Non |
| AP116 | `POST /v1/schools/{schoolId}/accounts/{accountId}/payments` | F10 | `PaymentCommand` → `Account` | Oui |
| AP117 | `POST /v1/schools/{schoolId}/accounts/{accountId}/refunds` | F10 | `RefundCommand` → `Account` | Oui |
| AP118 | `POST /v1/schools/{schoolId}/accounts/{accountId}/charge-adjustments` | F10 | `ChargeAdjustmentCommand` → `Account` | Oui |
| AP119 | `POST /v1/schools/{schoolId}/accounts/{accountId}/payment-reversals` | F10 | `ReversePaymentCommand` → `Account` | Oui |
| AP120 | `GET /v1/schools/{schoolId}/learners/{learnerId}/requirements` | F03 | `sans corps` → `RequirementRecordPageV2` | Non |
| AP121 | `POST /v1/schools/{schoolId}/learners/{learnerId}/requirements/declarations` | F03 | `DeclareRequirementCommand` → `RequirementRecord` | Non |
| AP122 | `POST /v1/schools/{schoolId}/requirements/{requirementId}/review` | F18 | `ReviewRequirementCommand` → `RequirementRecord` | Oui |
| AP123 | `GET /v1/schools/{schoolId}/regulatory-profiles` | F13 | `sans corps` → `RegulatoryProfilePageV2` | Non |
| AP124 | `POST /v1/schools/{schoolId}/regulatory-profiles` | F13 | `RegulatoryProfileCommand` → `RegulatoryProfile` | Non |
| AP125 | `POST /v1/schools/{schoolId}/regulatory-profiles/{profileId}/approve` | F13 | `ApproveProfileCommand` → `RegulatoryProfile` | Oui |
| AP126 | `GET /v1/schools/{schoolId}/course-templates` | F18 | `sans corps` → `CourseTemplatePageV2` | Non |
| AP127 | `POST /v1/schools/{schoolId}/course-templates` | F18 | `CourseTemplateCommand` → `CourseTemplate` | Non |
| AP128 | `PUT /v1/schools/{schoolId}/course-templates/{templateId}` | F18 | `CourseTemplateCommand` → `CourseTemplate` | Oui |
| AP129 | `GET /v1/schools/{schoolId}/course-sessions` | F18 | `sans corps` → `CourseSessionPageV2` | Non |
| AP130 | `POST /v1/schools/{schoolId}/course-sessions` | F18 | `CourseSessionCommand` → `CourseSession` | Non |
| AP131 | `GET /v1/schools/{schoolId}/course-sessions/{sessionId}` | F18 | `sans corps` → `CourseSession` | Non |
| AP132 | `PUT /v1/schools/{schoolId}/course-sessions/{sessionId}` | F18 | `CourseSessionCommand` → `CourseSession` | Oui |
| AP133 | `POST /v1/schools/{schoolId}/course-sessions/{sessionId}/publish` | F18 | `EmptyCommand` → `CourseSession` | Oui |
| AP134 | `POST /v1/schools/{schoolId}/course-sessions/{sessionId}/unpublish` | F18 | `ReasonCommand` → `CourseSession` | Oui |
| AP135 | `POST /v1/schools/{schoolId}/course-sessions/{sessionId}/reschedule` | F18 | `RescheduleCourseCommand` → `CourseSession` | Oui |
| AP136 | `POST /v1/schools/{schoolId}/course-sessions/{sessionId}/capacity` | F18 | `CourseCapacityCommand` → `CourseSession` | Oui |
| AP137 | `POST /v1/schools/{schoolId}/course-sessions/{sessionId}/cancel` | F18 | `ReasonCommand` → `CourseSession` | Oui |
| AP138 | `POST /v1/schools/{schoolId}/course-sessions/{sessionId}/close` | F18 | `CloseCourseCommand` → `CourseSession` | Oui |
| AP139 | `GET /v1/schools/{schoolId}/course-sessions/{sessionId}/enrollments` | F18 | `sans corps` → `CourseEnrollmentPageV2` | Non |
| AP140 | `POST /v1/schools/{schoolId}/course-sessions/{sessionId}/enrollments` | F18 | `EnrollCourseCommand` → `CourseEnrollment` | Non |
| AP141 | `GET /v1/schools/{schoolId}/learners/{learnerId}/course-enrollments` | F18 | `sans corps` → `CourseEnrollmentPageV2` | Non |
| AP142 | `GET /v1/schools/{schoolId}/course-enrollments/{enrollmentId}` | F18 | `sans corps` → `CourseEnrollment` | Non |
| AP143 | `POST /v1/schools/{schoolId}/course-enrollments/{enrollmentId}/cancel` | F18 | `CancelEnrollmentCommand` → `CourseEnrollment` | Oui |
| AP144 | `POST /v1/schools/{schoolId}/course-enrollments/{enrollmentId}/reconfirm` | F18 | `ReconfirmCourseCommand` → `CourseEnrollment` | Oui |
| AP145 | `GET /v1/schools/{schoolId}/course-occurrences/{occurrenceId}/attendance` | F18 | `sans corps` → `AttendanceRecordPageV2` | Non |
| AP146 | `PUT /v1/schools/{schoolId}/course-occurrences/{occurrenceId}/attendance/{enrollmentId}/cycles/{enrollmentCycle}` | F18 | `AttendanceCommand` → `AttendanceRecord` | Selon opération |
| AP147 | `GET /v1/schools/{schoolId}/calendar` | F19 | `sans corps` → `CalendarView` | Non |
| AP148 | `POST /v1/schools/{schoolId}/devices/push` | F11 | `RegisterPushCommand` → `DevicePushRegistration` | Non |
| AP149 | `POST /v1/schools/{schoolId}/devices/push/{registrationId}/revoke` | F11 | `EmptyCommand` → `DevicePushRegistration` | Oui |
| AP150 | `GET /v1/schools/{schoolId}/notification-preferences` | F11 | `sans corps` → `NotificationPreferences` | Non |
| AP151 | `PUT /v1/schools/{schoolId}/notification-preferences` | F11 | `NotificationPreferencesCommand` → `NotificationPreferences` | Oui |
| AP152 | `GET /v1/schools/{schoolId}/learners/{learnerId}/recording-choice` | F15 | `sans corps` → `RecordingChoice` | Non |
| AP153 | `POST /v1/schools/{schoolId}/learners/{learnerId}/recording-choice` | F15 | `RecordingChoiceCommand` → `RecordingChoice` | Non |
| AP154 | `POST /v1/schools/{schoolId}/lessons/{lessonId}/captures` | F15 | `StartCaptureCommand` → `CaptureAuthorization` | Oui |
| AP155 | `GET /v1/schools/{schoolId}/captures/{captureId}` | F15 | `sans corps` → `CaptureSession` | Non |
| AP156 | `PUT /v1/schools/{schoolId}/captures/{captureId}/segments/{segmentId}/chunks/{chunkIndex}` | F15 | `TrackChunkCommand` → `TrackChunkReceipt` | Non |
| AP157 | `POST /v1/schools/{schoolId}/captures/{captureId}/stop` | F15 | `StopCaptureCommand` → `CaptureSession` | Non |
| AP158 | `POST /v1/schools/{schoolId}/captures/{captureId}/finalize` | F15 | `FinalizeCaptureCommand` → `CaptureSession` | Oui |
| AP159 | `POST /v1/schools/{schoolId}/captures/{captureId}/withdraw` | F16 | `ReasonCommand` → `CaptureSession` | Oui |
| AP160 | `GET /v1/schools/{schoolId}/captures/{captureId}/replay` | F16 | `sans corps` → `ReplayPage` | Non |
| AP161 | `GET /v1/schools/{schoolId}/lessons/{lessonId}/geo-observations` | F15 F16 | `sans corps` → `GeoObservationPageV2` | Non |
| AP162 | `POST /v1/schools/{schoolId}/lessons/{lessonId}/geo-observations` | F15 F16 | `GeoObservationCommand` → `GeoObservation` | Non |
| AP163 | `PUT /v1/schools/{schoolId}/geo-observations/{observationId}` | F15 F16 | `GeoObservationCommand` → `GeoObservation` | Oui |
| AP164 | `POST /v1/schools/{schoolId}/geo-observations/{observationId}/remove` | F15 F16 | `ReasonCommand` → `Ack` | Oui |
| AP165 | `GET /v1/schools/{schoolId}/setup` | F20 | `sans corps` → `SchoolSetup` | Non |
| AP166 | `PATCH /v1/schools/{schoolId}/setup` | F20 | `SchoolSetupCommand` → `SchoolSetup` | Oui |
| AP167 | `GET /v1/schools/{schoolId}/readiness` | F20 F13 | `sans corps` → `SchoolReadiness` | Non |
| AP168 | `POST /v1/schools/{schoolId}/activate` | F20 F01 | `SchoolActivationCommand` → `School` | Oui |
| AP169 | `GET /v1/schools/{schoolId}/profile-field-policies` | F13 F20 F21 | `sans corps` → `ProfileFieldPolicyPageV3` | Non |
| AP170 | `POST /v1/schools/{schoolId}/profile-field-policies` | F13 F20 | `ProfileFieldPolicyCommand` → `ProfileFieldPolicy` | Oui |
| AP171 | `POST /v1/schools/{schoolId}/profile-field-policies/{policyId}/publish` | F13 F20 F21 | `EmptyCommand` → `ProfileFieldPolicy` | Oui |
| AP172 | `GET /v1/schools/{schoolId}/my-onboarding` | F21 | `sans corps` → `OnboardingProgress` | Non |
| AP173 | `PATCH /v1/schools/{schoolId}/my-onboarding` | F21 | `OnboardingProgressCommand` → `OnboardingProgress` | Oui |
| AP174 | `POST /v1/schools/{schoolId}/my-onboarding/complete` | F21 | `OnboardingCompleteCommand` → `OnboardingProgress` | Oui |
| AP175 | `GET /v1/schools/{schoolId}/learners/{learnerId}/administrative-profile` | F21 F22 | `sans corps` → `AdministrativeProfile` | Non |
| AP176 | `PATCH /v1/schools/{schoolId}/learners/{learnerId}/administrative-profile` | F21 F22 | `AdministrativeProfileCommand` → `AdministrativeProfile` | Oui |
| AP177 | `GET /v1/schools/{schoolId}/learners/{learnerId}/action-readiness` | F21 F18 | `sans corps` → `LearnerActionReadiness` | Non |
| AP178 | `GET /v1/schools/{schoolId}/learners/{learnerId}/training-requests` | F03 F21 | `sans corps` → `TrainingRequestPageV3` | Non |
| AP179 | `POST /v1/schools/{schoolId}/learners/{learnerId}/training-requests` | F03 F21 | `TrainingRequestCommand` → `TrainingRequest` | Non |
| AP180 | `POST /v1/schools/{schoolId}/training-requests/{trainingRequestId}/decision` | F03 F21 | `TrainingRequestDecisionCommand` → `TrainingRequest` | Oui |
| AP181 | `POST /v1/schools/{schoolId}/training-requests/{trainingRequestId}/withdraw` | F03 F21 | `ReasonCommand` → `TrainingRequest` | Oui |
| AP182 | `POST /v1/schools/{schoolId}/learner-archive-previews` | F14 F22 | `ArchivePreviewCommand` → `ArchivePreview` | Non |
| AP183 | `GET /v1/schools/{schoolId}/learner-archive-previews/{previewId}` | F22 | `sans corps` → `ArchivePreview` | Non |
| AP184 | `POST /v1/schools/{schoolId}/learners/{learnerId}/restore` | F14 F22 | `ReasonCommand` → `Learner` | Oui |
| AP185 | `POST /v1/schools/{schoolId}/learner-archive-jobs` | F14 F22 | `BulkArchiveCommand` → `Ack` | Non |
| AP186 | `GET /v1/schools/{schoolId}/learner-archive-jobs/{jobId}` | F22 | `sans corps` → `ArchiveJob` | Non |
| AP187 | `GET /v1/schools/{schoolId}/metrics/definitions` | F23 | `sans corps` → `MetricDefinitions` | Non |
| AP188 | `GET /v1/schools/{schoolId}/metrics` | F23 | `sans corps` → `ManagementMetrics` | Non |
| AP189 | `POST /v1/schools/{schoolId}/management-exports` | F22 F23 | `ManagementExportCommand` → `Ack` | Non |
| AP190 | `POST /v1/schools/{schoolId}/devices/{deviceId}/assessments` | F15 F21 | `DeviceAssessmentCommand` → `DeviceAssessment` | Non |
| AP191 | `GET /v1/schools/{schoolId}/devices/{deviceId}/assessments/{assessmentId}` | F15 F21 | `sans corps` → `DeviceAssessment` | Non |
| AP192 | `POST /v1/schools/{schoolId}/course-sessions/{sessionId}/offer-revisions` | F18 F19 | `ReviseCourseOfferCommand` → `CourseSession` | Oui |
| AP193 | `POST /v1/me/account-deletion-previews` | F01 F14 | `AccountDeletionPreviewCommand` → `AccountDeletionPreview` | Non |
| AP194 | `POST /v1/me/account-deletion-requests` | F01 F14 | `AccountDeletionSubmitCommand` → `AccountDeletionAccepted` | Non |
| AP195 | `GET /v1/me/account-deletion-requests/current` | F01 F14 | `sans corps` → `AccountDeletionRequest` | Non |
| AP196 | `GET /v1/me/account-deletion-requests/{requestId}` | F01 F14 | `sans corps` → `AccountDeletionRequest` | Non |
| AP197 | `POST /v1/me/account-deletion-requests/{requestId}/withdraw` | F01 F14 | `AccountDeletionWithdrawCommand` → `AccountDeletionRequest` | Oui |
| AP198 | `GET /v1/account-deletion-status` | F01 F14 | `sans corps` → `AccountDeletionReceipt` | Non |
| AP199 | `POST /v1/schools/{schoolId}/entitlements/{lotId}/deliveries` | F17 | `RecordServiceDeliveryCommand` → `ServiceDeliveryResult` | Oui |
| AP200 | `GET /v1/me/account-deletion-previews/{previewId}/memberships` | F01 | `sans corps` → `AccountDeletionMembershipPage` | Non |

## Exemple nominal : réservation

Exemple fictif, montants illustratifs et catégorie déjà validée par l’école. Le serveur recalcule la capacité ; les créneaux affichés précédemment n’accordent pas une réservation.

```http
POST /v1/schools/11111111-1111-4111-8111-111111111111/lessons
Authorization: Bearer <access-token>
Idempotency-Key: 99999999-9999-4999-8999-999999999999
Content-Type: application/json
```

```json
{
  "operationId": "99999999-9999-4999-8999-999999999999",
  "trainingId": "22222222-2222-4222-8222-222222222222",
  "instructorMembershipId": "33333333-3333-4333-8333-333333333333",
  "plannedStart": "2026-09-24T14:00:00+02:00",
  "plannedEnd": "2026-09-24T14:50:00+02:00",
  "timeZone": "Europe/Zurich",
  "meetingPoint": "Gare, entrée principale",
  "agreedPriceCents": 9000,
  "bufferMinutes": 10,
  "policyVersionId": "44444444-4444-4444-8444-444444444444",
  "commercialSelection": {
    "mode": "UNIT_PRICE",
    "serviceProductVersionId": "55555555-5555-4555-8555-555555555555",
    "quantity": 1,
    "entitlementLotId": null,
    "acceptedTermsVersionId": "66666666-6666-4666-8666-666666666666"
  }
}
```

Le serveur stocke notamment 12:00Z–12:50Z, occupe le moniteur jusqu’à 13:00Z et l’élève jusqu’à 12:50Z. Le prix de 90 CHF est un exemple convenu, pas un tarif recommandé ou une règle générale. La réponse comprend un identifiant de leçon, sa version et `status=PLANNED` ; les champs de réponse exacts figurent dans le schéma Lesson.

## Exemple de conflit et conséquence

```json
{
  "type": "urn:drivy:problem:slot-conflict",
  "title": "Créneau indisponible",
  "status": 409,
  "code": "SLOT_CONFLICT",
  "detail": "Une ressource nécessaire est déjà occupée.",
  "requestId": "req-example-001"
}
```

Aucun nom d’un autre élève ne figure dans la réponse. Lors d’un déplacement, l’ancien rendez-vous reste inchangé. Un 412 signifie que la version a changé ; un 409 SLOT_CONFLICT signifie que l’état demandé viole une contrainte. Les interfaces ne les regroupent pas dans un bouton Réessayer qui écraserait une décision.

## Ordre de traitement d’une commande sensible

Authentifier et retrouver la personne ; vérifier école et droits courants ; valider forme et plafonds ; retrouver une opération déjà commitée ; comparer son hash ; verrouiller les agrégats/ressources dans un ordre stable ; contrôler la version et tous les invariants ; écrire résultat, occupation ou projection, preuve d’opération, audit et outbox ; enregistrer les événements de projection sous horloge scolaire ; commit ; retourner le résultat.

Pour une même clé déjà commitée, les droits **actuels** restent requis pour consulter le résultat. Une révocation ne permet pas de récupérer une ancienne réponse sensible depuis le cache d’idempotence. Ne jamais marquer une opération réussie avant le commit. Un crash avant commit laisse une transaction à réessayer, pas un faux résultat enregistré.

## Cas de contrat à ne pas improviser

**CompleteLesson.** Version de leçon en If-Match ; le prix et l’identité élève sont lus depuis la réservation. L’auteur ne peut pas fournir un autre prix dans le corps de clôture. La réponse composite confirme le résultat, le brouillon et le compte financier.

**Publication.** If-Match porte le brouillon ; `expectedPublicationVersion` protège le pointeur de publication. Une correction prépare une nouvelle révision. Le retrait de publication utilise la version du pointeur, pas la version d’une ancienne révision immuable. La publication expose seulement des pièces READY autorisées.

**Contrôle de permis.** Le dépôt ou remplacement d’une pièce PERMIT incrémente Training.version et remet le contrôle courant en attente, même si le nouveau fichier n’est pas encore READY. La version de formation protège donc contre une pièce remplacée pendant la lecture du contrôleur. L’API impose pièce READY ou attestation physique et catégorie cohérente, même si le JSON autorise des champs nuls pour les différentes variantes.

**Règlement.** If-Match vise Account.version ; les deux écritures concurrentes verrouillent le même compte. `reversePaymentEntry` enregistre une correction administrative REVERSAL, sans mouvement d’argent réel : montant identique au mouvement source, effet opposé, source RECEIPT ou REFUND non déjà inversée, method=null, date de correction et motif. Le net et le solde restent valides dans la transaction. Un véritable remboursement utilise `recordRefund`, sans `reversalOfId`. Les remboursements représentent des faits réels, pas un outil pour contourner une correction bloquée.

**CorrectOutcome.** Le corps est conditionnel : une cible PLANNED exige un futur créneau compatible fourni par ReopenBookingInput, conserve formation/personne/prix/tampon et interdit de les remplacer dans le corps ; COMPLETED exige heures réelles ; les autres ne prennent pas de futur créneau. Le champ d’approbation pédagogique correspond à un OutcomeApproval valide par un moniteur habilité, pas à un UUID arbitraire. Une approbation doit être enregistrée via le processus d’arbitrage décrit ci-dessous avant l’exécution.

**Arbitrage encadré.** `approveOutcomeCorrection` est réservé au moniteur affecté habilité à publier. Il reçoit la proposition complète sans approbation préexistante, lie son hash canonique (hors operationId et pedagogicalApprovalId) aux versions de leçon, de compte et de publication, et crée un accord valable 10 minutes, consommable une seule fois. Toute modification du contenu, des versions ou des droits invalide cet accord. L’ADMIN exécute ensuite exactement cette proposition par `correctOutcome`. Un responsable cumulant les habilitations effectue les deux actions distinctes, auditées, avec réauthentification. E04 montre la proposition à approuver puis l’exécution disponible selon les droits ; aucun module de workflow général n’est requis. Les effacements effectifs restent des procédures d’exploitation à double contrôle, pas une route publique de purge.

**Export.** La génération est asynchrone ; PREPARING ne contient pas de lien de lecture. Le ticket d’export utilise `ExportDownloadTicket` avec `exportId`, distinct de `DownloadTicket.documentId`. Les deux contrôlent les droits actuels et la durée de validité ; leurs identifiants ne sont pas interchangeables.

## Canaux de sécurité

Native : Bearer access token destiné à l’API. Web : session sécurisée via BFF ; toute écriture utilisant cookie exige Origin attendu et jeton CSRF. OpenAPI décrit deux modes d’authentification alternatifs, pas un droit de désactiver CSRF. Les liens de connexion sont gérés par le fournisseur et les routes de callback du client/BFF, pas par un mot de passe envoyé à ce contrat métier.

Le stockage objet reçoit seulement un ticket d’envoi pour une clé précise et une durée courte ; le bucket n’est pas une API générale pour les clients. Les webhooks fournisseur utilisent des signatures et secrets d’environnement distincts, validation d’horodatage/rejeu et traitement idempotent. Les endpoints de webhook restent une interface d’intégration à finaliser après choix du fournisseur, et ne sont pas inventés comme déjà implémentés.

## Compatibilité et gel

Versionnement majeur du chemin pour rupture. Ajouter un champ de réponse nécessite clients tolérants selon contrat de lecture ; les corps de commande restent stricts. Une ancienne app incompatible reçoit une erreur explicite et peut conserver ses brouillons autorisés, pas être forcée à les supprimer. Les nouveaux états métiers ne sont jamais interprétés comme PLANNED par défaut. Un gel du contrat exige validation OpenAPI, tests de schémas et tests de la matrice d’autorisation.

## Contrats consolidés V2

Les identifiants AP01–AP95 sont conservés. Leurs schémas de contexte sont étendus : commercialSelection dans la création de leçon, propriétaire explicite de Account, sélection GPS à publication du bilan, modules d’école et nouveaux grants. Le contrat V2 est un nouveau contrat de conception, pas une promesse de compatibilité binaire avec le code de l’archive. Les exemples V2 sont fictifs.

Une inscription créée exige acceptedOfferRevision et l’accord sur toutes les occurrences ; pas de If-Match sur le compteur de places. Les chunks immuables et la commande monotone d’arrêt GPS sont des exceptions documentées au verrou de version d’une mutation ordinaire. Voir [transactions](transactions-v2.md). Les routes de leçon/account et routes génériques account pointent vers le même agrégat.

| ID | Opération | Fonction | Entrée → sortie |
|---|---|---|---|

## Exemples d’usage et sécurité

Consulter une offre se fait par GET ; aucun lien email ou push ne crée d’inscription. POST enrollCourse porte une nouvelle operationId, l’offre acceptée, les occurrences et la couverture commerciale. Réponse 201 uniquement après commit complet. En cas de réseau coupé après commit, rejouer la même operationId, pas une nouvelle réservation.

Pour une leçon couverte, agreedPriceCents correspond à la charge de cette utilisation (zéro), non au prix catalogue original. CommercialSelection garde le produit, les unités et le droit. Account présente ownerType/ownerId pour distinguer achat de pack et prestation unitaire. Les règles contractuelles et montants agrégés sont contrôlés côté service, pas par les seuls schémas JSON.

F14 garde la procédure de demande d’effacement d’une capture : pas d’endpoint de suppression publique sans instruction. La publication du trajet passe par PublishCommand de la révision de bilan, et non par un PATCH d’une révision déjà publiée. Les données GPS complètes ne sont pas présentes dans les listes de leçons.

Les commandes de présence suivent [R11](../03-fonctionnel/regles-etats.md#r11) : première création avec `If-None-Match: *`, correction avec l’ETag existant dans `If-Match`. Une seule précondition ; aucune version de création fictive. Le cycle d’inscription de l’URI doit être courant. Le contrôle de concurrence est réalisé au commit.


### Écritures financières communes

ChargeEntry et PaymentEntry référencent toujours `accountId`. `lessonId`, lorsqu’il est présent, n’est qu’une projection contextuelle. Un achat ou une inscription n’a jamais besoin d’une fausse leçon pour recevoir un règlement. `RefundCommand.chargeAdjustmentSignedCents` permet une compensation de charge atomique avec la saisie d’un remboursement réellement effectué. Il ne déclenche aucun paiement bancaire. Le serveur contrôle les invariants R24/R25 sur le résultat composé.


## Opérations supplémentaires V3

Le contrat [OpenAPI](openapi.yaml) définit les corps, paramètres, erreurs et réponses. Les endpoints anciens AP01–AP164 restent identifiés ; AP17 est renforcé par une preview, AP14 ajoute filtres, StartCapture exige deviceAssessmentId et le pipeline F09 accepte PROFILE_PHOTO. Les suffixes de noms de schéma V2 sont conservés comme identifiants historiques ; ils ne désignent pas une deuxième version active.

| ID | Méthode et route | Fonction | Opération |
|---|---|---|---|

### Sémantique et erreurs V3

L’initialisation SchoolSetup et des progressions personnelles fait partie de la provision/invitation acceptée, jamais d’un GET. Un compte cumulant STAFF et STUDENT possède une progression par kind. Le champ returnDestinationKey est une enum interne ; aucune URL arbitraire de redirection n’est acceptée.

**422 PROFILE_ACTION_REQUIRED** contient les champs manquants/finalités dans Problem.fieldErrors ; **409 SETUP_INCOMPLETE**, **409 ARCHIVE_BLOCKED**, **410 ARCHIVE_PREVIEW_EXPIRED**, **409 CAPTURE_DEVICE_BUSY**, **422 DEVICE_NOT_QUALIFIED**, **422 METRIC_FILTER_UNSUPPORTED**, **422 EXPORT_TOO_LARGE** sont des codes métier stables à mapper sans inventer un succès. If-Match manque :428 ; version ancienne :412. Autorisation refusée :403 ou404 selon visibilité, jamais énumération d’une autre école.

Pour archive individuelle AP17, If-Match porte sur Learner ; previewId lie les impacts et l’auteur. Le lot AP185 porte ses versions par ligne et ne prétend pas une transaction globale. Les résultats se retrouvent via operationId si réponse perdue. Les cas d’export réutilisent le téléchargement privé existant, mais les finalités restent distinctes et chaque accès est contrôlé.

**DRAFT school :** seules commandes F20 et configuration F13/F17/F18 explicitement nécessaires au setup sont autorisées, sous ADMIN, sans publier cours ni vendre avant readiness appropriée. Une école ACTIVE peut configurer des offres futures sans réécrire les ventes. Les mots ACTIVE/READY d’un wizard ne sont ni un agrément ni une validation réglementaire.

**Limites :** OpenAPI valide des formes de données, pas l’authentification réelle, les transactions SQL, les permissions OS ou une implémentation. Les contraintes multi-champs/temps/droits nécessitent services et recettes. Aucun endpoint de provision publique, de mot de passe maison, de relais GPS live ou de calcul comptable fiscal n’a été ajouté.

<a id="précisions-contractuelles-v31"></a>
## Projections, publications et contrôle des versions
Le catalogue ci-dessus est régénéré depuis le contrat et contrôlé contre celui-ci ; AP17 reçoit ArchiveCommitCommand, pas ReasonCommand. Les suffixes historiques de schémas restent des identifiants stables. Les exemples des media types requestBody sont validés au même titre que ceux des schémas et des annexes.

Exceptions explicites à la pagination générale : AP147 calendrier utilise sa fenêtre/son curseur bornés ; AP160 replay utilise un budget de 1 000 points/page et un curseur de séquence, sans diviser artificiellement un segment logique. Les tableaux d’un agrégat ne deviennent pas des listes publiques globales.

SchoolReadiness sépare activationReady de CAN_USE_WORKSPACE. Un profil PATCH autorise les modifications partielles, mais les droits par champ et la complétude au stade de l’action restent serveur. ReportRevision renvoie une CapturePublication figée, non une CaptureSelection modifiable. AP154 délivre deux preuves distinctes de collecte et d’ingestion ; AP156 utilise signedUploadAuthorization. Les unités monétaires sont les centimes CHF partout.

Codes clarifiés : SETUP_INCOMPLETE, PROFILE_ACTION_REQUIRED, ARCHIVE_FINANCIAL_FOLLOW_UP_REQUIRED (dans les blockers d’ARCHIVE_BLOCKED), ENROLLMENT_FINANCIAL_REVIEW_REQUIRED, CAPTURE_REVIEW_CHANGED, EXPORT_TOO_LARGE. Ces codes documentent des refus à tester, pas une implémentation déjà existante.

<a id="presence-conditionnelle"></a>
## Présence : URI de cycle et création conditionnelle

AP146 porte `/course-occurrences/{occurrenceId}/attendance/{enrollmentId}/cycles/{enrollmentCycle}`. Une première écriture emploie `If-None-Match: *` ; une correction emploie l’ETag existant via `If-Match`. [R11](../03-fonctionnel/regles-etats.md#r11) fixe les erreurs et l’exclusivité. La sémantique suit HTTP conditionnel [S59](../06-gouvernance/sources.md#s59) ; `AttendanceWritePreconditions` est un modèle de recette de ces en-têtes, pas un middleware fourni par OpenAPI.

Le roster et les présences indiquent le cycle. Relever une ancienne URI après une réinscription ne met pas à jour le nouveau cycle. Le service valide appartenance à l’occurrence, période, rôle, état de série et cycle avant consommation.

## Résultats provisoires et enveloppes de transport

La colonne du catalogue décrit `data` de la réponse finale, pas l’enveloppe HTTP. Toutes les réponses JSON de succès sont enveloppées, y compris les pages V2 du catalogue, des cours, des droits et des observations. Les tailles de pages de [R33](../03-fonctionnel/regles-etats.md#r33) s’appliquent également à ces endpoints.

Un 202 contenant `PendingOperationEnvelope` n’est jamais interprété comme une confirmation métier. Les routes asynchrones peuvent renvoyer leur enveloppe Job : cela signifie seulement que le job est créé. Les deux branches sont explicitement distinctes dans le contrat. Les rejets conservent `application/problem+json`, sans enveloppe `data` artificielle. Le corps de reprise ne réexpose pas les données privées d’une ancienne réponse.

## Révisions de leçon et de cours

AP42 inclut `commercialChange` uniquement pour une révision explicite de durée/financement/prix ; [R13](../03-fonctionnel/regles-etats.md#r13) impose son atomicité. AP135 inclut les deux échéances. AP192 ne permet ni de changer une exigence ni de déplacer des dates ; chaque branche de `ReviseCourseOfferCommand` refuse les champs de l’autre. `CourseEnrollment.acceptedCommercialSnapshot` et `acceptedSelfCancellationDeadline` restent les conditions du cycle concerné, indépendamment du titre ou prix courant.

La reconfirmation AP144 inclut aussi `acceptedSelfCancellationDeadline` : les dates, leur révision et l’échéance affichée sont acceptées explicitement ; les identifiants d’occurrences sont uniques. Les conditions de prix ne sont pas modifiées par cette commande.

<a id="portée-du-contrat-pour-lintégration-mobile-v34"></a>
## Contrat partagé et intégration native
Le dossier courant et le contrat OpenAPI sont en **3.7**. Les six opérations globales AP193–AP198 ajoutées en V3.5 sont conservées ; V3.6 complète les transitions de bilan/cours/prix et ajoute AP199/AP200. V3.7 ajoute AP201 et les contrats détaillés ci-dessous. Les 201 opérations sont documentaires, non déployées. Les guides natifs ne permettent jamais d’inventer une route supplémentaire.

**Suppression globale :** AP193–AP198, R103 et E49/J29 spécifient déjà l’initiation et l’orchestration du compte, y compris sans école active. DM06 reste ouvert pour les procédures, délais, rétentions et dernier ADMIN, pas pour l’absence de contrat. Aucun de ces parcours n’est exécuté par cette documentation.


<a id="révision-35-clôture-globale-et-compléments-de-contrats"></a>
## Suppression globale, langues et préférences
Cette révision modifie le contrat avant implémentation. Le dossier et info.version du contrat sont en 3.7 ; ne pas mélanger les DTO actuels avec ceux des contrats 3.2 ou 3.5. Aucune API de serveur déployé n’est prétendue migrée.

| ID | Méthode et chemin | OperationId | Portée | Corps / réponse |
|---|---|---|---|---|

AP193–AP198 ont des enveloppes et erreurs définies dans OpenAPI. Le reçu n’est pas un token d’identité. Les commandes globales en 202 se reprennent avec la même intention par POST ou AP195 ; AP72 scolaire ne s’applique pas. Aperçu expiré : 410 ; version modifiée : 412 ; réauthentification nécessaire : 401 REAUTH_REQUIRED ; retrait irréversible : 409 ; auteur incorrect : 404 sans révéler l’existence de la demande.

Autres changements : Preparation expose plannedWaypoints initialisé [] ; PreparationCommand accepte son remplacement versionné ou conserve en cas d’omission. CourseSessionCommand exige teachingLanguage, figé après publication. CalendarOffer restitue cette langue. PermitCommand requiert une preuve d’approbation et un motif non blanc de rejet ; les références/droits/horaires sont toujours vérifiés au service, pas par JSON Schema seulement. Voir [R101–R105](../03-fonctionnel/regles-etats.md#r101).

<a id="compléments-hérités-de-la-révision-360"></a>
## Publication textuelle et conditions commerciales
AP54 : `textObservationSelection` explicite et `ReportRevision.textObservations`, indépendants de captureSelection. AP157 : manifeste de segment vide sans séquence fictive. AP138 : `CloseCourseCommand` et revue des HOLD inutilisés. AP199 : remise consignée d’un droit externe/examen, corrigée via RESTORE existant. AP193/AP200 : total et pages du manifeste de suppression, confirmation AP194 sur l’ensemble. PackOffer/Purchase exposent prix de base, suppléments d’options et snapshot de dérogation.

AP152 sans événement répond RECORDING_CHOICE_NOT_SET, sans création. AP150 lit les préférences version 1 créées avec l’appartenance. Les règles R106–R108 et l’ordre identité→école→objets constituent les références de service ; JSON Schema vérifie la forme, pas les sommes, les permissions, les comparaisons de dates ou l’unicité par clé métier.

La révision 3.6.0 avait modifié plusieurs corps/retours avant implémentation ; ces changements sont conservés dans le contrat courant 3.11.0. Un client ne doit pas utiliser des DTO 3.5 avec ces nouveaux appels. Les enveloppes, preuves d’idempotence, ETags, réponses 202 et filtrage sous droits restent applicables aux nouvelles opérations.

### Coordination de la suppression globale

Toute séquence abrégée de verrous métier dans ce document s’applique **après** la porte d’accès des personnes et la vérification transactionnelle du périmètre. L’ordre complet et les modes nécessaires sont définis une seule fois dans [Autorisation et frontière de commit](transactions-v2.md#autorisation-et-commit). Le chemin du worker de suppression dispose d’un mandat restreint ; il n’accorde pas une session normale à un compte CLOSING. La concurrence réelle reste à tester sur PostgreSQL.

<a id="compléments-contractuels-v37"></a>
## Preuves d’exigence et corrections de cours
AP122 demande `sourceEnrollmentCycle`, nul uniquement en absence de source interne, et renvoie une preuve serveur figée dans RequirementRecord. Les états finaux ont un reviewer réel. AP146 continue à retourner AttendanceRecord ; sa correction peut faire évoluer CourseEnrollment.rightSettlement et les exigences : les clients relisent ces objets (ou leurs invalidations), pas seulement la cellule de présence.

| ID | Route | Fonction | Entrée | Sortie |
|---|---|---|---|---|
| AP201 | `POST /v1/schools/{schoolId}/course-enrollments/{enrollmentId}/cycles/{enrollmentCycle}/right-settlement` | F17/F18 | ResolveCourseRightCommand ; If-Match inscription et version du suivi | CourseEnrollmentEnvelopeV2 ; 202 possible avant résultat final |

AP148/149 exposent environnement et bindingVersion. Le contrat natif accepte IOS/ANDROID, pas une fausse souscription WEB par token seul ; le web de gestion/centre interne reste inchangé. Les enums futurs ne doivent pas être traités en Swift comme un succès par défaut. Un token ne donne aucune capacité de lecture du dossier.

**Erreurs complémentaires :** RIGHT_SETTLEMENT_CHANGED, INSUFFICIENT_ENTITLEMENT et ENTITLEMENT_NOT_USABLE (409) ; REQUIREMENT_BASIS_CHANGED (409), REQUIREMENT_EVIDENCE_REQUIRED et EXEMPTION_NOT_APPLICABLE (422), PUSH_ENVIRONMENT_MISMATCH/PUSH_PLATFORM_NOT_CONFIGURED (422), ARCHIVE_RIGHT_SETTLEMENT_REQUIRED au sein d’ARCHIVE_BLOCKED (409). La forme JSON ne vérifie ni le solde, ni les relations de preuve, ni l’origine d’un token.

**Garde-fou de revue :** AP122 reçoit sourceEnrollmentVersion, attendanceVersionChecks et documentVersionChecks. Les ensembles attendus correspondent aux identifiants sélectionnés et blocs requis ; le serveur compare avant validation, sans reconstruire silencieusement une nouvelle preuve après changement concurrent. Une erreur de forme et REQUIREMENT_BASIS_CHANGED restent distinctes.

<a id="compléments-v310-transfert-et-formats-binaires"></a>
## Transfert, scellement et formats binaires
AP60/AP84 émettent un `UploadTicket`/`AssetUploadTicket` à `method=PUT`, URL HTTPS et en-têtes signés limités. AP61/AP86 scellent puis contrôlent la génération de contenu ; leur réponse n’est pas automatiquement READY. AP63/AP82/AP87 émettent une URL de passerelle authentifiée, jamais une permission de lecture autonome du bucket. AP90/AP91/AP92 renvoient des octets sous le Content-Type documenté, pas un `Ack` JSON.

AP91 expose CSV pour la gestion et ZIP pour PRIVACY. Les métadonnées de `Export` permettent de vérifier le fichier avant une copie volontaire. [Contrat de transport, reprise et format](fichiers-temps-communications.md#transport-fichiers). Les vérifications JSON Schema ne démontrent ni l’origine réseau effective, ni un checksum calculé, ni la sûreté d’un parseur. Le contrat passe à 3.10.0 avant implémentation ; aucune nouvelle route n’est nécessaire pour ces compléments.
