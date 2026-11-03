# Registre des commandes et des files d’écriture (#106, étape 1)

État lu : `17b6b667` (master), 3 novembre 2026. Document de constat : aucun code applicatif modifié.
Périmètre : les routes d’écriture de `apps/api/src`, leurs appels depuis `apps/web/client`, et les files d’écriture de `apps/ios/Drivy`.
Une information absente du code est écrite « non trouvé » ; rien n’est déduit d’un nom de route.

## Méthode et preuve d’exhaustivité

- Projet Codebase Memory indexé par chemin absolu : `drivy-lotc-registre-106`
  (`index_repository`, mode `moderate`, état `succeeded`, 10 s).
- Requêtes Codebase Memory utilisées : `search_graph("schoolCommand")`,
  `search_graph("SchoolCommandOutbox")`, `trace_path(function_name: "schoolCommand", direction: "outbound")`,
  `search_graph("commandSpecs")` (contrôle des commandes web), `trace_path(function_name: "submit", outbound)`
  (ambigü, 20 homonymes : écarté au profit de la lecture de `apps/web/client/command-store.ts`).
- Exhaustivité des routes : croisement de deux méthodes.
  1. `grep` textuel `app.(post|put|patch|delete)(` sur `apps/api/src` → 125 enregistrements littéraux ;
  2. lecture des boucles d’enregistrement (`for (const …) app[…]`, `app.route`, `.bind(app)`) pour les routes non littérales :
     `invitations.ts:417`, `lesson-setup.ts:133`, `notification-preferences.ts:94`, `profiles.ts:231` et `profiles.ts:262`,
     `messaging-routes.ts:137,142,147`, `formation-catalogue.ts:502-505`.
  Résultat : **141 routes acceptant une méthode d’écriture**, dont **7 POST sans écriture** (aperçus, calcul, export) et
  **134 routes qui persistent**. Aucune route d’écriture n’a été trouvée dans `matched-routes.ts`, `health.ts` ou `queries.ts`.
- Les routes sont comptées telles qu’enregistrées par Fastify (une boucle `for` de deux valeurs compte deux routes).

Légende des tableaux serveur :

- **Version** : `If-Match` = version forte exigée de la ressource ciblée ; « école » = ligne `drivy.school` verrouillée
  (`FOR UPDATE`, `commands.ts:83`) et/ou `school.version` comparée ; « — » = aucune version comparée.
- **Idempotence** : `operationId` = corps `operationId` + en-tête `Idempotency-Key` liés (`checkIdempotency`, `commands.ts:26`),
  enregistrement dans `drivy.operation` et reçu AP72 `GET /v1/schools/:schoolId/operations/:operationId`
  (`school-setup.ts:138`) ; « aucun » = ni clé ni reçu ; « jeton » = clé naturelle (document, adresse, type).
- **Effets secondaires** : `O/A` = `drivy.operation` + `drivy.audit_event` dans le même commit
  (`commands.ts:49-55`) ; `CFG` = `school.version`/`configuration_version` avancées + `recordSettings`
  (`school-setup.ts:82`, `catalogue.ts:49`, `formation-catalogue.ts:132`) ; `EV` = `lesson_event_outbox`
  (`lessons.ts:167`) ; `RES` = `drivy.reservation` (occupation, exclusion PostgreSQL) ;
  `MAIL` = file de courriel d’invitation (`invitation-mail.ts:38`) ; `PUSH` = `course_event_outbox`.

## 1. Registre des commandes serveur

### 1.1 Configuration de l’école, accès, dossiers et catalogue (24 routes)

| Route | Commande | Version | Idempotence | Effets secondaires | Droits |
|---|---|---|---|---|---|
| `PATCH /v1/schools/:schoolId/setup` (`school-setup.ts:180`) | `SAVE_SCHOOL_SETUP` | setup | `operationId` + AP72 | O/A | ADMIN |
| `PATCH /v1/schools/:schoolId` (`:192`) | `UPDATE_SCHOOL` | école + `school.version` | `operationId` + AP72 | O/A, CFG | ADMIN |
| `PUT /v1/schools/:schoolId/data-policy` (`:211`) | `ADOPT_SCHOOL_DATA_POLICY` | politique | `operationId` + AP72 | O/A, CFG, publication de champs de profil si demandée | ADMIN |
| `POST /v1/schools/:schoolId/activate` (`:234`) | `ACTIVATE_SCHOOL` | école + `configurationVersion` | `operationId` + AP72 | O/A, statut `ACTIVE` | ADMIN |
| `PUT /v1/schools/:schoolId/setup-draft` (`school-onboarding.ts:186`) | `SAVE_SCHOOL_SETUP_DRAFT` | brouillon | `operationId` + AP72 | O/A | ADMIN (`:176`) |
| `POST /v1/schools/:schoolId/setup-draft/complete` (`:195`) | `APPLY_SCHOOL_SETUP_DRAFT` | brouillon + école + configuration | `operationId` + AP72 | O/A, CFG, formations/conditions créées, activation éventuelle | ADMIN |
| `POST …/members/:membershipId/deactivate` (`administration.ts:40`) | `DEACTIVATE_MEMBER` | adhésion | `operationId` + AP72 | O/A, `access_epoch+1`, fin d’affectations | ADMIN + réauthentification (`:42`) |
| `POST …/trainings/:trainingId/assignments/:assignmentId/end` (`:63`) | `END_ASSIGNMENT` | affectation | `operationId` + AP72 | O/A, `access_epoch+1` | ADMIN |
| `POST …/learners/:learnerId/archive` (`:83`) | `ARCHIVE_LEARNER` | dossier | `operationId` + AP72 | O/A | ADMIN |
| `POST …/learners/:learnerId/restore` (`:101`) | `RESTORE_LEARNER` | dossier | `operationId` + AP72 | O/A | ADMIN |
| `POST …/trainings/:trainingId/transition` (`:117`) | `TRANSITION_TRAINING` | formation | `operationId` + AP72 | O/A | ADMIN |
| `PUT …/modules` (`:145`) | `UPDATE_SCHOOL_MODULES` | école | `operationId` + AP72 | O/A, module GPS (garde des captures et du départ) | ADMIN |
| `POST /v1/schools/:schoolId/curricula` (`catalogue.ts:82`) | `CREATE_CURRICULUM_VERSION` | — (création) | `operationId` + AP72 | O/A, CFG | ADMIN |
| `POST …/policy-versions` (`:91`) | `CREATE_SCHOOL_POLICY` | — | `operationId` + AP72 | O/A, CFG | ADMIN |
| `POST …/offerings` (`:100`) | `CREATE_OFFERING_VERSION` | — | `operationId` + AP72 | O/A, CFG | ADMIN |
| `POST …/trainings` (`:113`) | `CREATE_TRAINING` | — | `operationId` + AP72 | O/A, affectation du créateur moniteur | ADMIN, INSTRUCTOR |
| `POST …/trainings/:trainingId/assignments` (`:133`) | `CREATE_ASSIGNMENT` | — | `operationId` + AP72 | O/A, `access_epoch+1` du moniteur | ADMIN |
| `PATCH …/members/:membershipId` (`:149`) | `UPDATE_MEMBER` | adhésion | `operationId` + AP72 | O/A, `access_epoch+1`, profil élève créé au besoin | ADMIN + réauthentification (`:151`) |
| `POST …/profile-field-policies` (`profiles.ts:196`) | `CREATE_PROFILE_FIELD_POLICY` | école | `operationId` + AP72 | O/A, CFG si publication immédiate | ADMIN |
| `POST …/profile-field-policies/:policyId/publish` (`:212`) | `PUBLISH_PROFILE_FIELD_POLICY` | politique | `operationId` + AP72 | O/A, CFG | ADMIN |
| `PATCH …/learners/:learnerId` (héritage, `:231`) | `UPDATE_LEARNER` | profil | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR, LEARNER (selon champs) |
| `PATCH …/learners/:learnerId/administrative-profile` (`:231`) | `UPDATE_ADMINISTRATIVE_PROFILE` | profil | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR, LEARNER (selon champs) |
| `PATCH …/my-onboarding` (`:262`) | `SAVE_ONBOARDING` | progression | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR, LEARNER |
| `POST …/my-onboarding/complete` (`:262`) | `COMPLETE_ONBOARDING` | progression | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR, LEARNER |

### 1.2 Formations et tarifs (4 routes)

| Route | Commande | Version | Idempotence | Effets secondaires | Droits |
|---|---|---|---|---|---|
| `POST /v1/schools/:schoolId/formations` (`formation-catalogue.ts:503`) | `CREATE_FORMATION` | — | `operationId` + AP72 | O/A, CFG, versions de référentiel/procédure | ADMIN |
| `POST …/formations/programmes` (`:502`) | `UPDATE_FORMATION_PROGRAMME` | — | `operationId` + AP72 | O/A, CFG, programme lié aux conditions | ADMIN |
| `POST …/formations/tariffs` (`:504`) | `SAVE_TARIFF` | — | `operationId` + AP72 | O/A, CFG, nouvelle version de prestation | ADMIN |
| `POST …/formations/terms/revise` (`:505`) | `REVISE_SHARED_TERMS` | — | `operationId` + AP72 | O/A, CFG, conditions partagées | ADMIN |

### 1.3 Planning, disponibilités et leçons (13 routes)

| Route | Commande | Version | Idempotence | Effets secondaires | Droits |
|---|---|---|---|---|---|
| `POST …/commercial-terms` (`lesson-setup.ts:89`) | `CREATE_COMMERCIAL_TERMS` | — | `operationId` + AP72 | O/A, conditions approuvées | ADMIN, INSTRUCTOR + droit catalogue |
| `POST …/service-products` (`:98`) | `CREATE_SERVICE_PRODUCT` | — | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR + droit catalogue |
| `POST …/availability-rules` (`:114`) | `CREATE_AVAILABILITY_RULE` | — | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR + droit du moniteur visé |
| `POST …/closures` (`:122`) | `CREATE_CLOSURE` | — | `operationId` + AP72 | O/A, refuse si une leçon tombe dedans | ADMIN, INSTRUCTOR + droit du moniteur visé |
| `POST …/availability-rules/:id/remove` (`:133`) | `REMOVE_AVAILABILITY_RULE` | règle | `operationId` + AP72 | O/A, vérifie les rendez-vous restants | ADMIN, INSTRUCTOR + droit du moniteur visé |
| `POST …/closures/:id/remove` (`:133`) | `REMOVE_CLOSURE` | fermeture | `operationId` + AP72 | O/A | idem |
| `PUT …/availability-rules/:id` (`:147`) | `UPDATE_AVAILABILITY_RULE` | règle | `operationId` + AP72 | O/A, vérifie les rendez-vous restants | idem |
| `PUT …/planning-defaults` (`planning-defaults.ts:27`) | `SAVE_PLANNING_DEFAULTS` | préférence | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR |
| `POST …/lessons` (`lessons.ts:316`) | `CREATE_LESSON` | contexte (procédure) + créneau | `operationId` + AP72 | O/A, `RES`, `EV`, révision commerciale | ADMIN, INSTRUCTOR + accès formation |
| `POST …/lessons/start-now` (`:333`) | `START_LESSON_NOW` | — | `operationId` + AP72 | O/A, `RES`, `EV`, départ réel éventuel | INSTRUCTOR + accès formation |
| `POST …/lessons/:lessonId/start` (`:362`) | `START_LESSON` | leçon | `operationId` + AP72 | O/A, `EV`, départ réel | INSTRUCTOR auteur |
| `POST …/lessons/:lessonId/move` (`:386`) | `MOVE_LESSON` | leçon | `operationId` + AP72 | O/A, `RES` réécrit, `EV`, révision commerciale éventuelle | ADMIN, INSTRUCTOR |
| `POST …/lessons/:lessonId/cancel` (`:410`) | `CANCEL_LESSON` | leçon | `operationId` + AP72 | O/A, occupations libérées, compte rouvert, `EV` | ADMIN, INSTRUCTOR |

### 1.4 Bilan, résultats, partage, permis, demandes de changement (14 routes)

| Route | Commande | Version | Idempotence | Effets secondaires | Droits |
|---|---|---|---|---|---|
| `PUT …/lessons/:lessonId/preparation` (`lesson-reports.ts:134`) | `SAVE_PREPARATION` | préparation | `operationId` + AP72 | O/A | INSTRUCTOR, LEARNER |
| `PUT …/trainings/:trainingId/wish` (`:145`) | `SAVE_WISH` | souhait | `operationId` + AP72 | O/A | INSTRUCTOR, LEARNER |
| `POST …/lessons/:lessonId/complete` (`:155`) | `COMPLETE_LESSON` | leçon | `operationId` + AP72 | O/A, brouillon créé, observations rattachées, compte de leçon, `RES` libéré, `EV`, partage synchronisé | INSTRUCTOR, LEARNER |
| `PUT …/report-drafts/:draftId` (`:193`) | `SAVE_REPORT_DRAFT` | brouillon | `operationId` + AP72 | O/A, partage synchronisé | INSTRUCTOR, LEARNER |
| `POST …/report-drafts/:draftId/publish` (`:206`) | `PUBLISH_REPORT_DRAFT` | brouillon + version de publication | `operationId` + AP72 | O/A, révision immuable, partage | INSTRUCTOR, LEARNER |
| `POST …/lessons/:lessonId/no-show` (`lesson-outcomes.ts:70`) | `MARK_NO_SHOW` | leçon | `operationId` + AP72 | O/A, occupations libérées, `EV` | ADMIN, INSTRUCTOR |
| `POST …/lessons/:lessonId/outcome-approvals` (`:85`) | `APPROVE_OUTCOME_CORRECTION` | leçon + compte + publication | `operationId` + AP72 | O/A, approbation valable 10 min | INSTRUCTOR |
| `POST …/lessons/:lessonId/correct-outcome` (`:104`) | `CORRECT_OUTCOME` | leçon + compte | `operationId` + AP72 | O/A, contre-passation de charge, retrait de bilan, `EV` | ADMIN |
| `POST …/lessons/:lessonId/report-publication/withdraw` (`:156`) | `WITHDRAW_REPORT_PUBLICATION` | leçon | `operationId` + AP72 | O/A, révision conservée, partage privé | INSTRUCTOR auteur |
| `PUT …/lessons/:lessonId/sharing` (`sharing.ts:42`) | `UPDATE_LESSON_SHARING` | `sharing_version` | `operationId` + AP72 | O/A, retrait/publication de bilan, visibilité d’observations | INSTRUCTOR auteur |
| `POST …/trainings/:trainingId/permit-checks` (`permits.ts:63`) | `RECORD_PERMIT_CHECK` | formation | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR + `permit_review_allowed` |
| `POST …/lessons/:lessonId/change-requests` (`lesson-change-requests.ts:116`) | `CREATE_LESSON_CHANGE_REQUEST` | leçon (version lue à la création) | `operationId` + AP72 | O/A, une seule demande en attente par leçon (index unique) | LEARNER de la leçon |
| `POST …/lesson-change-requests/:requestId/withdraw` (`:139`) | `WITHDRAW_LESSON_CHANGE_REQUEST` | demande | `operationId` + AP72 | O/A | LEARNER demandeur + If-Match |
| `POST …/lesson-change-requests/:requestId/refuse` (`:153`) | `REFUSE_LESSON_CHANGE_REQUEST` | demande | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR + `lesson_change_staff` |

### 1.5 Observations, captures, recalage (10 routes)

| Route | Commande | Version | Idempotence | Effets secondaires | Droits |
|---|---|---|---|---|---|
| `POST …/lessons/:lessonId/geo-observations` (`capture-observations.ts:143`) | `CREATE_GEO_OBSERVATION` | — | `operationId` + AP72 | O/A, brouillon touché, ancrage sur trajet finalisé | INSTRUCTOR auteur |
| `PUT …/geo-observations/:id` (`:166`) | `UPDATE_GEO_OBSERVATION` | observation | `operationId` + AP72 | O/A, brouillon touché | INSTRUCTOR auteur |
| `POST …/geo-observations/:id/remove` (`:185`) | `REMOVE_GEO_OBSERVATION` | observation | `operationId` + AP72 | O/A, texte effacé | INSTRUCTOR auteur |
| `POST …/devices/:deviceId/assessments` (`captures.ts:122`) | `ASSESS_CAPTURE_DEVICE` | — | `operationId` + AP72 | O/A, installation liée, diagnostic 5 min | INSTRUCTOR |
| `POST …/learners/:learnerId/recording-choice` (`:145`) | `RECORD_RECORDING_CHOICE` | choix (`expectedChoiceVersion`) | `operationId` + AP72 | O/A | INSTRUCTOR sauf choix `SELF` (élève) |
| `POST …/lessons/:lessonId/captures` (`:160`) | `START_CAPTURE` | leçon | `operationId` + AP72 | O/A, session de capture, départ de leçon si absent, preuves signées hors operation | INSTRUCTOR, LEARNER |
| `PUT …/captures/:captureId/segments/:segmentId/chunks/:chunkIndex` (`:221`) | `UPLOAD_TRACK_CHUNK` | — (identité du lot : hash) | `operationId` + AP72, reçu = lot | O/A, lot chiffré, version de reconstruction | INSTRUCTOR, LEARNER |
| `POST …/captures/:captureId/stop` (`:239`) | `STOP_CAPTURE` | manifeste immuable | `operationId` + AP72 | O/A, borne de collecte | idem |
| `POST …/captures/:captureId/finalize` (`:253`) | `FINALIZE_CAPTURE` | capture | `operationId` + AP72 | O/A, ancrage des observations (ordre leçon puis capture) | idem |
| `POST …/captures/:captureId/live-match` (`live-match-routes.ts:13`) | — (aucune) | — | aucun | aucun (calcul, deux transactions en lecture) | INSTRUCTOR propriétaire, limiteur 429 |

### 1.6 Examens (4 routes)

| Route | Commande | Version | Idempotence | Effets secondaires | Droits |
|---|---|---|---|---|---|
| `POST …/trainings/:trainingId/exams` (`exams.ts:185`) | `CREATE_EXAM` | — | `operationId` + AP72 | O/A, réservation d’accompagnement, révision d’examen | ADMIN, INSTRUCTOR + `exam_manage` |
| `POST …/exams/:examId/update` (`:203`) | `UPDATE_EXAM` | examen | `operationId` + AP72 | O/A, réservation d’accompagnement, révision | idem |
| `POST …/exams/:examId/postpone` (`:219`) | `POSTPONE_EXAM` | examen | `operationId` + AP72 | O/A, nouvelle tentative, révisions | idem |
| `POST …/exams/:examId/result` (`:240`) | `SET_EXAM_RESULT` | examen | `operationId` + AP72 | O/A, révision | idem |

### 1.7 Cours collectifs, inscriptions et faits (22 routes)

| Route | Commande | Version | Idempotence | Effets secondaires | Droits |
|---|---|---|---|---|---|
| `POST …/course-types` (`courses.ts:137`) | `CREATE_COURSE_TYPE` | — | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR + droit cours |
| `PATCH …/course-types/:typeId` (`:146`) | `UPDATE_COURSE_TYPE` | type | `operationId` + AP72 | O/A | idem |
| `PUT …/course-policy` (`:159`) | `SAVE_COURSE_POLICY` | politique | `operationId` + AP72 | O/A, nouvelle version | idem |
| `POST …/course-series` (`:189`) | `CREATE_COURSE_SERIES` | — | `operationId` + AP72 | O/A, séances écrites (brouillon, sans réservation) | idem |
| `PUT …/course-series/:seriesId` (`:202`) | `UPDATE_COURSE_SERIES` | série | `operationId` + AP72 | O/A, séances réécrites | idem |
| `POST …/course-series/:seriesId/publish` (`:220`) | `PUBLISH_COURSE_SERIES` | série | `operationId` + AP72 | O/A, `RES` par séance, `PUSH` | idem |
| `POST …/course-series/:seriesId/capacity` (`:242`) | `CHANGE_COURSE_CAPACITY` | série | `operationId` + AP72 | O/A | idem |
| `POST …/course-series/:seriesId/enroll` (`course-enrollments.ts:160`) | `ENROLL_COURSE` | — | `operationId` + AP72 | O/A, inscription + file | LEARNER |
| `POST …/course-series/:seriesId/enrollments` (`:170`) | `STAFF_ENROLL_COURSE` | — | `operationId` + AP72 | O/A, inscription tracée `STAFF` | ADMIN, INSTRUCTOR |
| `POST …/course-series/:seriesId/waitlist` (`:182`) | `JOIN_COURSE_WAITLIST` | — | `operationId` + AP72 | O/A, file | LEARNER |
| `POST …/course-series/:seriesId/waitlist/leave` (`:191`) | `LEAVE_COURSE_WAITLIST` | — | `operationId` + AP72 | O/A | LEARNER |
| `POST …/course-offers/:offerId/accept` (`:199`) | `ACCEPT_COURSE_OFFER` | — | `operationId` + AP72 | O/A, place consommée | LEARNER |
| `POST …/course-offers/:offerId/decline` (`:209`) | `DECLINE_COURSE_OFFER` | — | `operationId` + AP72 | O/A, place rendue à la file | LEARNER |
| `POST …/course-enrollments/:id/cancel` (`:219`) | `CANCEL_COURSE_ENROLLMENT` | inscription | `operationId` + AP72 | O/A | LEARNER |
| `POST …/course-enrollments/:id/staff-cancel` (`:228`) | `STAFF_CANCEL_COURSE_ENROLLMENT` | inscription | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR |
| `POST …/course-series/:seriesId/cancel` (`:239`) | `CANCEL_COURSE_SERIES` | série | `operationId` + AP72 | O/A, séances/inscriptions | ADMIN, INSTRUCTOR |
| `POST …/course-series/:seriesId/reschedule` (`:248`) | `RESCHEDULE_COURSE_SERIES` | série | `operationId` + AP72 | O/A, `RES` | ADMIN, INSTRUCTOR |
| `PUT …/course-enrollments/:id/attendance/:occurrenceId` (`course-facts.ts:155`) | `RECORD_COURSE_ATTENDANCE` | présence (`expectedVersion`) | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR |
| `POST …/course-enrollments/:id/payments` (`:163`) | `RECORD_COURSE_PAYMENT` | — | `operationId` + AP72 | O/A, écriture financière | ADMIN, INSTRUCTOR |
| `POST …/course-payments/:id/void` (`:171`) | `VOID_COURSE_PAYMENT` | — | `operationId` + AP72 | O/A, contre-passation | ADMIN, INSTRUCTOR |
| `POST …/course-enrollments/:id/validate` (`:180`) | `VALIDATE_COURSE` | — | `operationId` + AP72 | O/A, accomplissement | ADMIN, INSTRUCTOR |
| `POST …/course-completions/:id/revoke` (`:188`) | `REVOKE_COURSE_COMPLETION` | — | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR |

### 1.8 Invitations (7 routes)

| Route | Commande | Version | Idempotence | Effets secondaires | Droits |
|---|---|---|---|---|---|
| `POST /v1/invitations/preview` (`invitations.ts:352`) | — (lecture) | — | aucun | aucun | authentifié |
| `POST /v1/invitations/accept` (`:354`) | `ACCEPT_INVITATION` | invitation + adhésion | `operationId` + AP72 | O/A, adhésion, affectations | authentifié |
| `POST /v1/invitations/code/preview` (`:358`) | — (lecture) | — | aucun | limiteur de tentatives | authentifié |
| `POST /v1/invitations/code/accept` (`:361`) | `ACCEPT_INVITATION` | invitation + adhésion | `operationId` + AP72 | O/A, adhésion | authentifié |
| `POST /v1/schools/:schoolId/invitations` (`:385`) | `CREATE_INVITATION` | — | `operationId` + AP72 | O/A, `MAIL` ou code rendu une seule fois | ADMIN, INSTRUCTOR |
| `POST …/invitations/:invitationId/resend` (`:417`) | `RESEND_INVITATION` | invitation | `operationId` + AP72 | O/A, `MAIL`, nouveau jeton | ADMIN, INSTRUCTOR |
| `POST …/invitations/:invitationId/revoke` (`:417`) | `REVOKE_INVITATION` | invitation | `operationId` + AP72 | O/A, courriel annulé | ADMIN, INSTRUCTOR |

### 1.9 Comptes, entrée et ouverture d’école (6 routes)

| Route | Commande | Version | Idempotence | Effets secondaires | Droits |
|---|---|---|---|---|---|
| `POST /v1/access-codes/preview` (`accounts.ts:92`) | — (lecture) | — | aucun | limiteur par IP | public |
| `POST /v1/accounts` (`:97`) | — | — | aucun | création chez le fournisseur d’identité, limiteur | public |
| `POST /v1/operator/school-opening-links` (`school-opening.ts:101`) | — | — | `operationId` + hash stocké | jeton de lien (jamais relu) | opérateur |
| `POST /v1/operator/school-opening-links/:linkId/revoke` (`:113`) | — | — | `operationId` par acteur | lien révoqué | opérateur |
| `POST /v1/school-openings/preview` (`:129`) | — (lecture) | — | aucun | aucun | authentifié |
| `POST /v1/school-openings` (`:139`) | — | — | `operationId` + reçu par opération | école créée, lien consommé | authentifié |

### 1.10 Notifications, profil personnel, thèmes, métriques (11 routes)

| Route | Commande | Version | Idempotence | Effets secondaires | Droits |
|---|---|---|---|---|---|
| `PUT /v1/me/notification-preferences` (`notification-preferences.ts:48`) | — | préférences | aucun (verrou personne + If-Match) | aucun reçu ; 412 si version | personne |
| `PUT /v1/me/push-devices` (`:69`) | — | — | jeton d’appareil | réattribution d’un jeton | personne |
| `POST /v1/me/push-devices/revoke` (`:77`) | — | — | jeton | jeton révoqué | personne |
| `PUT /v1/schools/:schoolId/course-follows/me/:typeId` (`:94`) | — | — | type (upsert) | aucun | membre élève |
| `POST …/course-follows/me/:typeId/unfollow` (`:94`) | — | — | type | aucun | membre élève |
| `PATCH /v1/me/profile` (`self-profile.ts:112`) | — | personne | aucun (Id-Match) | aucun reçu | personne |
| `PUT /v1/me/profile/photo` (`:147`) | — | version personne | aucun | photo chiffrée, métadonnées retirées | personne |
| `DELETE /v1/me/profile/photo` (`:171`) | — | version personne | aucun | photo supprimée | personne |
| `PUT …/observation-themes` (`observation-themes.ts:84`) | `SAVE_OBSERVATION_THEMES` | thèmes | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR + droit signalements |
| `PUT …/observation-ranking` (`observation-ranking.ts:98`) | `SAVE_OBSERVATION_RANKING` | classement | `operationId` + AP72 | O/A | ADMIN, INSTRUCTOR |
| `POST …/metrics/exports` (`school-metrics.ts:549`) | — (calcul) | — | aucun | aucun (CSV en réponse, rien de conservé) | droit export + `metrics_gate` |

Note : `GET …/observation-ranking` peut écrire un rafraîchissement quotidien (`REFRESH_OBSERVATION_RANKING`,
`observation-ranking.ts:78`) — une lecture qui porte une commande, cas à part dans tout ordonnancement.

### 1.11 Messagerie (17 routes)

Toutes passent par `execute` (`messaging-routes.ts:62`), adhésion + époque d’accès relues, mutation optionnelle
`Idempotency-Key` → `MESSAGING_REACTION|PIN|VOTE|HIDE|DELETE` avec `drivy.operation` + `audit_event`
(`messaging-commands.ts:21-38`). Versions : aucune `If-Match` ; l’état de lecture porte `expectedVersion`.
Les lignes `PUT|DELETE` du tableau comptent deux routes chacune.

| Route | Mutation | Version | Idempotence |
|---|---|---|---|
| `PUT …/messaging/private/:personId` (`:85`) | — | — | aucun (fil créé si absent) |
| `PUT …/messaging/general` (`:89`) | — | — | aucun |
| `POST …/conversations/:id/messages` (`:109`) | — | aucune | `clientMessageId` |
| `PUT …/conversations/:id/read-state` (`:116`) | — | `expectedVersion` si `mutedUntil` | aucun |
| `DELETE …/messages/:messageId` (`:130`) | `MESSAGING_HIDE`/`MESSAGING_DELETE` | — | `operationId` (optionnel) |
| `PUT|DELETE …/messages/:messageId/reactions/:emoji` (`:137`) | `MESSAGING_REACTION` | — | `operationId` (optionnel) |
| `PUT|DELETE …/messages/:messageId/pin` (`:142`) | `MESSAGING_PIN` | — | `operationId` (optionnel) |
| `PUT|DELETE …/general/admins/:personId` (`:147`) | — | — | aucun |
| `PUT …/messages/:messageId/poll/votes` (`:152`) | `MESSAGING_VOTE` | — | `operationId` (optionnel) |
| `POST …/messages/:messageId/poll/close` (`:158`) | — | — | aucun |
| `DELETE …/general/members/:personId` (`:162`) | — | — | aucun |
| `PUT …/general/members/:personId` (`:167`) | — | — | aucun |
| `POST …/reports` (`:172`) | — | — | `clientReportId` |
| `PUT …/reports/:reportId/status` (`:185`) | — | `expectedStatus` | aucun |

### 1.12 Clés de messagerie (9 routes)

`/v1/schools/:schoolId/messaging/crypto` (`messaging-keys-routes.ts:59`), qualification de messagerie exigée.

| Route | Version | Idempotence | Effets secondaires |
|---|---|---|---|
| `POST …/keys/upload` (`:62`) | — | clés (usage unique) | O/A |
| `POST …/keys/query` (`:64`) | — | lecture | aucun |
| `POST …/keys/claim` (`:66`) | — | clés | O/A |
| `POST …/keys/device_signing/upload` (`:68`) | — | clé | O/A |
| `POST …/keys/signatures/upload` (`:70`) | — | signatures | O/A |
| `PUT …/sendToDevice/:eventType/:txnId` (`:72`) | txn | `txnId` | O/A |
| `DELETE …/devices/:deviceId` (`:84`) | — | appareil | O/A |
| `POST …/room_keys/version` (`:88`) | — | version de sauvegarde | O/A |
| `PUT …/room_keys/keys` (`:92`) | version de sauvegarde | clés | O/A |

## 2. Clients web (`apps/web/client`)

### 2.1 Voie de commandes

60 commandes déclarées (`command-core.ts:40-104`), toutes envoyées par `commandStore.submit`
(`command-store.ts:119`) via `schoolFetch` (`:146`). Persistance : **corps en mémoire seulement** ; seules les métadonnées
(`operationId`, `schoolId`, `kind`, `resourceId`, `resourceVersion`, `createdAt`) vont dans `sessionStorage`
(`command-store.ts:92`, clé `drivy-gestion-demandes-v1`, `:49`). Après rechargement, l’entrée revient `orphaned` sans corps
(`:70-74`) : elle bloque tout ce que son type recouvre (`command-conflicts.ts:98`). Reçu AP72 : `readSchool(schoolId,
operations/:id)` (`:187`). Plafonds locaux : 50 entrées, 4 envois en cours (`:123`).

Mode : attente serveur (aucun succès avant réponse ou reçu). Les projections provisoires vivent dans les sections
(agenda, formations, cours), pas dans le store.

| Commande | Route | Portée de conflit (`command-conflicts.ts`) | Appel web |
|---|---|---|---|
| `updateSchool` | `PATCH /schools/:id` | `school` (`:26`) | `portal/settings/school-page.tsx:53` |
| `saveSetup` | `PATCH /schools/:id/setup` | `school` | aucun appel trouvé (déclarée seulement ; tests `apps/web/test/command-core.test.ts`) |
| `saveSetupDraft` | `PUT /schools/:id/setup-draft` | `school` | `portal/setup/use-setup-guide.ts:55` |
| `applySetupDraft` | `POST /schools/:id/setup-draft/complete` | `*` (`:25`) | `portal/setup/use-setup-guide.ts:271` |
| `activate` | `POST /schools/:id/activate` | `*` | aucun appel trouvé (l’activation passe par `applySetupDraft`) |
| `saveDataPolicy` | `PUT /schools/:id/data-policy` | `school` | `portal/settings/privacy-page.tsx:137` |
| `updateModules` | `PUT …/modules` | `*` | `portal/settings/privacy-page.tsx:80` |
| `updateMember` | `PATCH …/members/:id` | `*` | `portal/access/access-controller.ts:116` |
| `deactivateMember` | `POST …/members/:id/deactivate` | `*` | `portal/team/team-controller.ts:57` |
| `createInvitation` | `POST …/invitations` | `invitations:new:<email|op>` (`:31-34`) | `portal/invitations/use-invitations.ts:175,179` |
| `resendInvitation` | `POST …/invitations/:id/resend` | `invitations:<id>` (`:35-38`) | `portal/invitations/use-invitations.ts:184` |
| `revokeInvitation` | `POST …/invitations/:id/revoke` | `invitations:<id>` | `portal/invitations/use-invitations.ts:189` |
| `createProfilePolicy` | `POST …/profile-field-policies` | `profile-policy` (`:29`) | `portal/settings/privacy-page.tsx:230` |
| `publishProfilePolicy` | `POST …/profile-field-policies/:id/publish` | `profile-policy` | aucun appel trouvé (déclarée seulement ; la création peut publier d’un coup, `privacy-page.tsx:230`) |
| `createOffering` | `POST …/offerings` | `catalogue` (`:39-40`) | aucun appel trouvé (déclarée seulement ; tests `command-core.test.ts:21`) |
| `createCurriculum` | `POST …/curricula` | `catalogue` | aucun appel trouvé (tests `command-core.test.ts:79`) |
| `createCatalogPolicy` | `POST …/policy-versions` | `catalogue` | aucun appel trouvé |
| `createCommercialTerms` | `POST …/commercial-terms` | `catalogue` | aucun appel trouvé |
| `createServiceProduct` | `POST …/service-products` | `catalogue` | aucun appel trouvé |
| `createFormation` | `POST …/formations` | `catalogue` | aucun appel trouvé en direct (création via `APPLY_SCHOOL_SETUP_DRAFT` et `saveFormationProgramme`) |
| `saveFormationProgramme` | `POST …/formations/programmes` | `catalogue:offering:<scope>` ou `catalogue` (`:43-46`) | `portal/formations/formation-commands.ts:84` |
| `saveTariff` | `POST …/formations/tariffs` | `catalogue:product:<scope>` ou `catalogue` (`:49-52`) | `portal/pricing/pricing-commands.ts:103` |
| `reviseSharedTerms` | `POST …/formations/terms/revise` | `catalogue:terms:<scope>` + `planning` (`:54-57`) | `portal/pricing/pricing-commands.ts:155` |
| `createTraining` | `POST …/trainings` | `learners:<id>` + `planning:learner:<id>` (`:79-83`) | `portal/learners/learner-controller.ts:201` |
| `createAssignment` | `POST …/trainings/:id/assignments` | idem | `portal/learners/learner-controller.ts:212` |
| `transitionTraining` | `POST …/trainings/:id/transition` | idem | `portal/learners/learner-controller.ts:231` |
| `endAssignment` | `POST …/trainings/:id/assignments/:id/end` | idem | `portal/learners/learner-controller.ts:238` |
| `archiveLearner` | `POST …/learners/:id/archive` | idem | `portal/learners/learner-controller.ts:250` |
| `restoreLearner` | `POST …/learners/:id/restore` | idem | `portal/learners/learner-controller.ts:255` |
| `recordPermitCheck` | `POST …/permit-checks` | idem | `portal/learners/learner-controller.ts:244` |
| `updateAdministrativeProfile` | `PATCH …/administrative-profile` | idem | `portal/learners/dossier-controller.ts:98` |
| `saveObservationThemes` | `PUT …/observation-themes` | `observation-themes` (`:27`) | `portal/signals/signals-page.tsx:158` |
| `saveCoursePolicy` | `PUT …/course-policy` | `course-policy` (`:28`) | `portal/courses/course-policy-dialog.tsx:31` |
| `createCourseType` | `POST …/course-types` | `course-types` (`:71`) | `portal/courses/course-type-dialog.tsx:32` |
| `createCourseSeries` | `POST …/course-series` | `planning` (`:66-67`) | `portal/courses/use-course-draft.ts:72` |
| `updateCourseSeries` | `PUT …/course-series/:id` | `planning` | `portal/courses/use-course-draft.ts:71` |
| `publishCourseSeries` | `POST …/course-series/:id/publish` | `planning` | `portal/courses/use-course-draft.ts:101` |
| `changeCourseCapacity` | `POST …/course-series/:id/capacity` | `planning` | `portal/courses/course-changes.tsx:39` |
| `staffEnrollCourse` | `POST …/course-series/:id/enrollments` | `planning` | `portal/courses/use-course-participants.ts:152` |
| `staffCancelCourseEnrollment` | `POST …/course-enrollments/:id/staff-cancel` | `planning` | `portal/courses/use-course-participants.ts:161` |
| `cancelCourseSeries` | `POST …/course-series/:id/cancel` | `planning` | `portal/courses/course-changes.tsx:75` |
| `rescheduleCourseSeries` | `POST …/course-series/:id/reschedule` | `planning` | `portal/courses/course-reschedule.tsx:55` |
| `recordCourseAttendance` | `PUT …/attendance/:occurrenceId` | `course-facts:<participant>` (`:74-77`) | `portal/courses/use-course-participants.ts:142` |
| `recordCoursePayment` | `POST …/payments` | `course-facts:<participant>` | `use-course-participants.ts:173` |
| `voidCoursePayment` | `POST …/course-payments/:id/void` | `course-facts:<participant>` | `use-course-participants.ts:183` |
| `validateCourse` | `POST …/validate` | `course-facts:<participant>` | `use-course-participants.ts:193` |
| `revokeCourseCompletion` | `POST …/course-completions/:id/revoke` | `course-facts:<participant>` | `use-course-participants.ts:203` |
| `createExam` | `POST …/trainings/:id/exams` | `exams` + `planning` (`:69`) | `portal/learners/learner-exams.tsx:103` |
| `updateExam` | `POST …/exams/:id/update` | `exams` + `planning` | `learner-exams.tsx` |
| `postponeExam` | `POST …/exams/:id/postpone` | `exams` + `planning` | `learner-exams.tsx` |
| `setExamResult` | `POST …/exams/:id/result` | `exams` (`:70`) | `learner-exams.tsx:141` |
| `createLesson` | `POST …/lessons` | `planning` (`:67`) | `portal/agenda/use-lesson.ts` |
| `moveLesson` | `POST …/lessons/:id/move` | `planning` | `portal/agenda/use-lesson.ts` |
| `cancelLesson` | `POST …/lessons/:id/cancel` | `planning` | `portal/agenda/use-cancellation.ts:43` |
| `createAvailabilityRule` | `POST …/availability-rules` | `planning:availability:<instructor>:rules` (`:59-64`) | `portal/availability/use-schedule-commands.ts:79` |
| `updateAvailabilityRule` | `PUT …/availability-rules/:id` | idem | `use-schedule-commands.ts:77` |
| `removeAvailabilityRule` | `POST …/availability-rules/:id/remove` | idem | `use-schedule-commands.ts:101` |
| `createClosure` | `POST …/closures` | `…:closures` | `use-schedule-commands.ts:89` |
| `removeClosure` | `POST …/closures/:id/remove` | `…:closures` | `use-schedule-commands.ts:101` |
| `refuseLessonChangeRequest` | `POST …/lesson-change-requests/:id/refuse` | `planning` | `portal/agenda/lesson-request-card.tsx:65` |

Le web n’a **aucune** commande pour : `start-now`, `start`, `no-show`, `correct-outcome`, `approve-outcome`,
`withdraw-report-publication`, `save-preparation`, `save-wish`, `complete-lesson`, `publish-report`, `sharing`, géo-observations,
captures, inscriptions élève, préférences, profil personnel, messagerie. Ces routes ne sont appelées que par iOS (section 3)
ou par aucun client.

Garde-fous web : `wouldConflict` (`command-conflicts.ts:107`) interroge la portée de conflit avant de construire la commande ;
`useCommandLane.blocked` (`console/context.ts:247`) désactive le contrôle concerné et explique pourquoi. `useCommandRunner`
(`:256`) bloque son propre formulaire tant que sa demande attend (`:297-299`).

### 2.2 Appels directs (hors voie de commandes)

| Route | Appel | Persistance | Mode |
|---|---|---|---|
| `PUT /v1/me/notification-preferences` | `notification-preferences-model.ts:25-31` (BFF `/app/bff/me/notification-preferences`) | aucune (corps en mémoire) | `If-Match` ; 412 → conflit à relire ; réseau → incertain ; pas de reçu |
| `POST …/metrics/exports` | `portal/pilotage/details-api.ts:52-60` | aucune | attente serveur, fichier en mémoire (blob) |
| `POST /v1/school-openings` (+ aperçu, liens opérateur) | `portal/opening/use-school-opening.ts:26-113` via `request()` | métadonnées BFF | attente serveur ; état incertain exposé (`:84`) |
| `POST /v1/invitations/accept` (entrée) | `portal/entry/use-entry-session.ts:206` | jeton d’invitation en session | attente serveur ; `uncertain` géré |
| `POST /v1/accounts` (création) | `portal/entry/use-account-entry.ts:101` | aucune | attente serveur, aucun reçu |
| `PUT /v1/me/profile/photo`, `PATCH /v1/me/profile` | non trouvé côté web (aucun appel) | — | — |
| Messagerie | non trouvé côté web | — | — |

## 3. Clients iOS (`apps/ios/Drivy`)

### 3.1 Files existantes

| File | Fichier | Contenu | Persistance | Expiration |
|---|---|---|---|---|
| File des commandes de l’école | `SchoolConfigurationAPI/SchoolCommandOutbox.swift:305` | 49 types (`SchoolCommandKind`, `:31-48`) | AES-GCM, clé Keychain (`:449-462`), fichier `pending-v1.bin` (`:312`) en `FileProtectionType.complete` (`:405`), `F_FULLFSYNC` avant envoi (`:430-447`), 50 commandes max (`:348`), validation de cible (`:238-281`) | aucune (pas d’horodatage d’expiration ; `createdAt` sert à l’ordre) |
| Gestes de cours | `SchoolAgendaAPI/SchoolCourseIntentStore.swift:36` | feuille, élève, éditeur de cours (`courseSheetIntent`, `courseLearnerIntent`, `courseEditorIntent`) | même classe chiffrée, dossier `SchoolCourseIntents` (`:42`) | aucune |
| Corrections d’observation | `SchoolObservationUI/SchoolObservationCorrections.swift:25` | `updateObservation`, `removeObservation` | idem, dossier `SchoolObservationCorrections` (`:31`) | aucune |
| Messagerie | `MessagingCore/MessagingOutboxCoordinator.swift`, `MessagingProtectedStore.swift` | envois et mutations (cacher, épingler, vote, lecture) | fichier chiffré + clé Keychain (`:233-285`) | aucune |
| Préférences de notification | `SchoolProfileUI/SchoolNotificationSettingsModel.swift:106` | intention de préférences | `EncryptedAccountIntentStore` (`Core/AccountIntentStorage.swift:19`), AES-GCM, `completeFileProtection` | aucune |
| Profil personnel | `SchoolProfileUI/SchoolSelfProfileIntent.swift:5` | champs, photo | `EncryptedAccountIntentStore` | aucune |
| Captures | `SchoolCaptureCore/SQLCipherSchoolCaptureStore.swift` | diagnostics, démarrages, lots | SQLCipher | `uploadHours` côté serveur ; pas de purge locale trouvée |
| Adhésion / ouverture | `SchoolJoinAPI/SchoolJoinJournal.swift:42`, `SchoolCodeJoinJournal.swift` | invitation acceptée, aperçu | Keychain (`:46`) | aucune |
| Refus d’enregistrement | `SchoolCaptureCore/SchoolRecordingRefusalIntent.swift` | refus local | chiffré (même famille) | aucune |

Conséquence : « pas de repli en clair » est tenu ; en revanche aucune des **files de commandes** n’a d’**expiration** : une intention non
confirmée reste indéfiniment (seule la borne de 50 commandes et la validation de cible l’arrêtent). Les bornes de capture
(`uploadHours`, `expires_at`) sont côté serveur et ne purgent pas la file locale.

### 3.2 Ordonnancement actuel

`SchoolCommandScheduling.swift` définit quatre domaines (`:5-9`) : `school`, `invitations`, `teaching`,
`planningPreferences`. Deux commandes entrent en conflit si (`:23-39`) :

1. même identifiant (double appui) ;
2. portées de compte/école/API différentes → non ;
3. deux corrections de deux observations différentes → non (indépendantes) ;
4. deux gestes de cours → non (coffre séparé) ;
5. époques d’accès différentes → oui (barrière) ;
6. deux créations d’observation de la même leçon → non (ordre de la file) ;
7. sinon, domaines en conflit (`school` avec tout, sinon même domaine).

C’est déjà un ordonnancement par conflits, mais **au grain du domaine** : `teaching` couvre leçons, bilan, observations et
examens ensemble ; `invitations` sérialise toutes les invitations entre elles ; `school` reste une barrière globale
(justifiée pour `updateMember`, `deactivateMember`, `activate`, `applySetupDraft`, `updateModules` : version d’école, époque
d’accès et modules partagés).

### 3.3 Endroits qui bloquent une action parce qu’une autre écriture de l’école est en cours

Lecture de la file : `pending == nil` sur `outbox.pending(for: scope)` = **toute** commande de l’école ; sur
`pending(for:domain:)` = le domaine seulement.

| # | Site (lecture de la file) | Effet visible | Commande bloquée | Conflit réel ? |
|---|---|---|---|---|
| 1 | `SchoolAgendaUI/SchoolStartNowView.swift:69` (`pending(for: scope)` → `:519`, `:546`, `:588`) | formulaire et choix GPS désactivés | `START_LESSON_NOW` | Non en général : le départ ne partage la version d’aucune autre ressource ; il n’entre en conflit qu’avec une leçon du même moniteur/élève ou un changement de module GPS. Une invitation, un profil ou un tarif en attente ne le concernent pas. **Injustifié.** |
| 2 | `SchoolProfileUI/SchoolProfileWorkspace.swift:153` (`pending(for: scope)`) → `canMutate :63-65`, `acceptsInput :69-72` ; UI `SchoolUI/SchoolLearnerDossierView.swift:286,385`, `SchoolProfileUI/SchoolOnboardingView.swift:229,378,392,411,419,443,449,462,489` | dossier élève et accueil non modifiables | `UPDATE_ADMINISTRATIVE_PROFILE`, `SAVE_ONBOARDING`, `CREATE/PUBLISH_PROFILE_FIELD_POLICY` | Non : le profil porte sa propre version ; il ne dépend d’aucune leçon, invitation ni tarif. Seul `updateMember` (époque d’accès) le concerne. **Injustifié.** |
| 3 | `SchoolObservationUI/SchoolObservationWorkspace.swift:189` (`pending(for: scope)`) → `canMutate :74-77` ; UI `SchoolObservationView.swift:354,480` | ajout/correction de signalement désactivés | `CREATE/UPDATE/REMOVE_GEO_OBSERVATION` | Partiel : la même observation et le même bilan de la même leçon sont en conflit (versions, ancrage, partage) ; une observation d’une **autre** leçon, une invitation ou un examen ne le sont pas. **Injustifié la plupart du temps.** |
| 4 | `SchoolAgendaUI/SchoolPlanningWorkspace.swift:367` (`domain: .teaching`) → `canMutate :185` ; UI `SchoolPlanningView.swift:175,219,227,261,331,434,532,539` | création/déplacement/annulation de leçon désactivés | `CREATE/MOVE/CANCEL_LESSON` | Partiel : même leçon = conflit réel (version) ; créneau du même moniteur/élève = conflit réel (occupation) ; un bilan ou une observation d’une autre leçon ne partage ni version ni créneau. **Trop large.** |
| 5 | `SchoolLessonReportUI/SchoolLessonReportWorkspace.swift:620` (`domain: .teaching`) → `canMutate :125` ; UI `SchoolLessonReportView.swift:760,770,774,816` | préparation, constat, brouillon, publication, partage désactivés | `SAVE_PREPARATION`, `COMPLETE_LESSON`, `SAVE/PUBLISH_REPORT_DRAFT`, `UPDATE_LESSON_SHARING`, `MARK_NO_SHOW`, `RECORD_PERMIT_CHECK`, `START_LESSON` | Partiel : `completeLesson` et `publish` de la même leçon se croisent (observations, compte, publication) ; une leçon d’une autre formation ne partage rien. **Trop large.** |
| 6 | `SchoolAgendaUI/SchoolPlanningSettingsView.swift:91` (`domain: .planningPreferences`) → `:259` | comparaison des préférences désactivée | `SAVE_PLANNING_DEFAULTS` | Oui pour la même préférence (version de la ligne). Rien d’autre n’est bloqué par ce domaine. **Justifié.** |
| 7 | `SchoolTrainingUI/SchoolExamsUI.swift:31` (examens de la formation) → `:72-75`, `:82-84`, `:203`, `:228` | gestes d’examen désactivés, message « Une autre demande de cette école attend sa réponse » | `CREATE/UPDATE/POSTPONE_EXAM`, `SET_EXAM_RESULT` | Partiel : un accompagnement occupe l’agenda (conflit avec `planning`) ; deux examens distincts de la même formation n’ont pas de version commune — seule leur liste est relue. **Trop large pour `SET_EXAM_RESULT`.** |
| 8 | `SchoolInvitationsUI/SchoolInvitationWorkspace.swift:165` (`domain: .invitations`) → `SchoolInvitationsView.swift:181,703` | formulaire d’invitation masqué/désactivé tant qu’une invitation attend | `CREATE/RESEND/REVOKE_INVITATION` | Non entre deux invitations distinctes (chacune a sa version). Renvoi/révocation de la **même** invitation = conflit réel. **Injustifié entre invitations différentes.** |
| 9 | `SchoolAgendaUI/SchoolCourseEnrollmentWorkspace.swift:243,324` (file des gestes de cours) | un seul geste élève à la fois | `ENROLL/WAITLIST/ACCEPT/DECLINE/CANCEL` | Oui pour la même série (place, file, version d’inscription) ; deux séries distinctes sont indépendantes. File dédiée, ne bloque pas l’école. **Partiellement justifié.** |
| 10 | `SchoolAgendaUI/SchoolCourseEditorWorkspace.swift:285,362,380` (file de l’éditeur) | un seul enregistrement/publication à la fois | `CREATE/UPDATE/PUBLISH_COURSE_SERIES` | Oui : même série, même brouillon, même version. **Justifié.** |
| — | `SchoolUI/SchoolAgendaView.swift:770`, `SchoolUI/SchoolTodayView.swift:493` | marqueurs « en attente » seulement | aucune action bloquée | — |

**Total : 10 sites de blocage, dont 8 adossés à la file de l’école et 2 à une file dédiée.**
Verdict : **4 injustifiés** (1, 2, 3, 8), **4 trop larges** (4, 5, 7, et 9 dans sa file propre), **2 justifiés** (6, 10).

Points non trouvés : aucun écran ne désactive *globalement* l’application ; il n’existe pas de `isBusy` global de l’école.
Les `isBusy` rencontrés (`SchoolCapturePreparationWorkspace.swift:40`, `SchoolJoinWorkspace.swift:12`, etc.) sont locaux à
un écran ou à une opération.

### 3.4 Appels iOS et file utilisée

| Domaine | File | Routes (client) |
|---|---|---|
| Configuration, catalogue, profils, droits, invitations, planning, bilan, observations, examens | file de l’école (`EncryptedSchoolCommandOutbox`) | `SchoolInvitationClient` (`SchoolInvitationWorkspace:394-411`), `SchoolProfileClient` (`SchoolProfileWorkspace:334-344`), `SchoolPlanningClient` (`SchoolPlanningWorkspace:781`, `SchoolPlanningSettingsView:214`), `SchoolLessonReportClient:114-123` (brouillon, publication, permis), `SchoolObservationClient:146-148` (signalements, dans `SchoolObservationWorkspace` et `SchoolCaptureLiveObservations:220`), `SchoolExamClient` (`SchoolExamsUI:80`), `SchoolStartNowView:220,289` |
| Feuille de cours, gestes élève, éditeur | coffre `SchoolCourseIntents` | `SchoolCourseClient:363-464` |
| Corrections d’observation | coffre `SchoolObservationCorrections` | `SchoolObservationClient` (corrections, `SchoolObservationWorkspace:286`) |
| Captures GPS | coffre SQLCipher | `SchoolCaptureClient:183-203` (autorisation, lots, arrêt, finalisation), `SchoolCaptureTransferCoordinator:178` |
| Messagerie | file de messagerie | `MessagingAPIClient`, `MessagingWorkspace` |
| Préférences de notification | `EncryptedAccountIntentStore` | `SchoolNotificationClient:109-127` (PUT préférences, appareils) |
| Profil personnel | `EncryptedAccountIntentStore` | `DrivyAPIClient:204-217` (`PATCH /v1/me/profile`, `PUT|DELETE /v1/me/profile/photo`) + `SchoolSelfProfileIntent` |
| Adhésion, ouverture | journal Keychain | `SchoolJoinClient:180-228` |
| Demandes de changement de leçon (élève) | appel direct, `operationId` à chaque essai (`SchoolLessonChangeClient:100-104`) | `POST …/change-requests`, `withdraw` |
| Abonnements aux cours | appel direct, sans file (`SchoolCourseClient:484-489`) | `PUT/POST course-follows` |
| Recalage, lecture | appel direct | `POST …/live-match` (`SchoolCaptureClient:83`) |
| Notifications push / suppression d’appareil | appel direct (`SchoolNotificationClient:120,127`) | `PUT push-devices`, `POST push-devices/revoke` |

**Types déclarés sans émetteur trouvé** (`SchoolCommandKind`, `SchoolCommandOutbox.swift:31-48`) : `updateSchool`, `saveSetup`,
`activate`, `saveDataPolicy`, `createOffering`, `createCurriculum`, `createCatalogPolicy`, `createTraining`, `createAssignment`,
`updateMember`. Ils n’apparaissent que dans l’énumération, les libellés (`SchoolPendingCommandText.swift`) et la validation de
cible (`:268-273`) ; aucune écriture de l’app ne les met en file. À l’inverse, `createProfilePolicy`, `publishProfilePolicy`,
`updateProfile`, `saveOnboarding`, `completeOnboarding` sont émis (`SchoolProfileWorkspace:243,249,334`).


## 4. Dépendances et séquences obligatoires

1. **Accès et école** : `updateMember`, `deactivateMember`, `createAssignment`, `endAssignment`, `acceptInvitation` changent
   `access_epoch` (`catalogue.ts:143,158`, `administration.ts:53`, `:74`). Toute commande d’une époque antérieure doit être résolue
   avant émission (`SchoolCommandScheduling.swift:33-34`) : c’est une dépendance de droits, pas de ressource.
2. **Modules GPS** : `UPDATE_SCHOOL_MODULES` conditionne `START_CAPTURE`, `START_LESSON_NOW` et le choix GPS
   (`captures.ts:163`, `lessons.ts:344`). Une bascule de module doit précéder un départ/capture, jamais l’inverse.
3. **Création → version** : une création n’a pas d’identifiant ; toute commande suivante sur l’objet dépend de la réponse
   (léçon → préparation/constat, série → publication/capacité/inscription, examen → mise à jour/résultat, brouillon → publication,
   dossier → permis/examens, offre → formation → affectation). C’est la dépendance que matérialise `resourceVersion = 0`
   (`SchoolCommandOutbox.swift:258-271`).
4. **Même agrégat, même version** : leçon (déplacer/annuler/commencer/terminer), brouillon de bilan, inscription, examen,
   série, préférence de planning, invitation (renvoi/révocation). Deux écritures simultanées y produisent un 409/412 ; le
   client ne peut pas les paralléliser sans perdre une saisie.
5. **Occupation d’agenda** : `CREATE_LESSON`, `MOVE_LESSON`, `START_LESSON_NOW`, `PUBLISH_COURSE_SERIES`,
   `RESCHEDULE_COURSE_SERIES`, `CREATE/UPDATE_EXAM` écrivent `drivy.reservation` et sont départagés par une exclusion
   PostgreSQL (`lessons.ts:149`, `courses.ts:230`, `exams.ts:195`). Deux commandes de créneaux qui se recouvrent doivent
   rester séquentielles **par moniteur et par élève**, pas par école.
6. **Bilan et observations** : `COMPLETE_LESSON` rattache les observations en direct (`lesson-reports.ts:171`), la
   finalisation d’une capture ancre les observations (`captures.ts:264`), `UPDATE_LESSON_SHARING` et `PUBLISH_REPORT_DRAFT`
   lisent/écrivent la visibilité. Par leçon, l’ordre sûr est : capture finalisée (si trajet) → constat → brouillon →
   publication → partage ; le constat reste possible sans trajet, et une publication ne précède jamais le constat.
7. **Finances** : `COMPLETE_LESSON` crée le compte et la charge ; `CORRECT_OUTCOME` contre-passe exactement ; `RECORD_COURSE_PAYMENT`
   / `VOID_COURSE_PAYMENT` sont append-only. Une correction de résultat dépend de la version du compte
   (`lesson-outcomes.ts:111`) : séquence obligatoire.
8. **Publication** : `PUBLISH_REPORT_DRAFT` exige la version de publication de la leçon et le brouillon de base
   (`lesson-reports.ts:211`) ; un retrait ou une correction avance cette version. Séquence obligatoire.
9. **Invitations** : création → (renvoi | révocation | acceptation). L’acceptation crée l’adhésion et son époque ; elle doit
   précéder toute écriture de la nouvelle adhésion.
10. **Aucune contrainte de séquence** entre : deux leçons de moniteurs différents, deux invitations distinctes, deux examens
    distincts, deux corrections d’observations distinctes, un geste de cours et une leçon, des préférences de notification et
    toute écriture d’école, une capture et une invitation, deux cellules de présence de deux élèves.

## 5. Proposition de découpage (à valider, pas un plan)

Classement par gain/risque décroissant.

1. **Départ et observations : retirer la barrière globale** (gain fort, risque faible). `SchoolStartNowView:69` et
   `SchoolObservationWorkspace:189` passent à `pending(for:domain:.teaching)` ; les corrections restent dans leur coffre.
   Vérifier : départ pendant qu’une invitation attend, observation pendant qu’un tarif attend.
2. **Profil et accueil : portée par dossier** (gain fort, risque faible). Remplacer `pending(for: scope)` par une lecture
   filtrée (`kind.isProfile` sur le même dossier) ; ne garder la barrière que pour `updateMember`/`deactivateMember`.
3. **Invitations : portée par invitation** (gain moyen, risque faible). `pending(for:domain:.invitations)` → conflit seulement
   pour le même `resourceID` (renvoi/révocation) ; deux créations distinctes peuvent coexister.
4. **Domaine `teaching` : clé par agrégat** (gain fort, risque moyen). Introduire une portée « leçon » (routeResourceID) et
   « moniteur/élève » pour les créneaux ; garder la sérialisation pour la même leçon et les mêmes occupations. Couvre les sites 4, 5, 7.
5. **File dédiée des gestes de cours** (gain moyen, risque moyen) : deux élèves ou deux séries distinctes en parallèle, la
   même feuille restant ordonnée ; à faire après 4 pour ne pas dupliquer la logique de conflit.

Hors périmètre de cette étape (à traiter en étape 2) : expiration/reprise des files, annulation avant envoi, réconciliation
par champ, états 5/10 s.

## Blocages levés (tâches 1-3)

Réalisation des propositions 1 à 3 de la section 5, **corrigée après relecture** : la barrière d’un écran est
exactement la règle d’admission de la file. Un écran n’ouvre donc jamais une saisie que
`EncryptedSchoolCommandOutbox.save` refusera (`pendingCommand` après coup). Aucune route, aucun envoi, aucune
idempotence, aucun droit et aucun texte d’écran ne change.

### Mécanisme commun

`SchoolConfigurationAPI/SchoolCommandOutbox.swift:302-313` :

```swift
func pending(for scope: SchoolCommandScope, refusing kind: SchoolCommandKind,
             resourceID: UUID? = nil, routeResourceID: UUID? = nil) throws -> PendingSchoolCommand?
```

La lecture construit la commande que l’écran émettrait (type, portée, ressource) et rend la première commande
conservée qui la refuserait **selon `blocksQueueEntry`**, la fonction qu’utilise `save` (`:374`) et la relecture du
coffre (`:411`). L’écran est ouvert quand cette lecture est vide : la règle ne peut plus diverger, c’est la même
fonction.

### Paires desserrées, avec preuve côté API

`blocksQueueEntry` (`:315-345`) ne touche pas à `conflicts(with:)` : il l’appelle d’abord, puis écarte uniquement les
paires ci-dessous.

| Paire | Preuve (fichier:ligne) | Version écrite ou vérifiée |
|---|---|---|
| Deux invitations distinctes ; renvoi ou révocation de la **même** invitation restent séquentiels | `apps/api/src/invitations.ts:385-415` (création : aucun `If-Match`, `INSERT drivy.invitation`) et `:417-444` (renvoi/révocation : `checkVersion(current.version)`, `UPDATE drivy.invitation`) | `drivy.invitation.version` seulement ; aucune version d’école |
| Une invitation et une écriture de **dossier** de profil (profil administratif, accueil guidé) | `apps/api/src/profiles.ts:122-161` (`checkVersion(row.version)` sur `drivy.learner_profile`, puis `drivy.person` et `drivy.learner_profile` en `version=version+1`) et `:262-283` (accueil : `drivy.onboarding_progress.version`) ; `invitations.ts:385-444` ne lit aucune de ces lignes | `learner_profile.version`, `person.version`, `onboarding_progress.version` ; aucune version d’école |
| Deux signalements de **leçons différentes** | `apps/api/src/capture-observations.ts:143-165` : aucun `If-Match`, `INSERT drivy.geo_observation`, `touchDraft` sur le brouillon de la leçon | `geo_observation.version` (ligne neuve) et `report_draft.version` de la leçon |

Ce qui **n’est pas** desserré, faute de preuve :

- **Politique de champ de profil** : elle vérifie et avance la version de l’école (`profiles.ts:69`, `:208`, `:221`).
  Elle reste une barrière pour tout, invitation comprise.
- **Enregistrement d’un dossier de profil** face à un tarif, une leçon, une observation, un changement d’accès ou une
  écriture d’école : `saveProfile` relit la politique courante et valide la date de naissance avec le fuseau de
  l’école (`profiles.ts:123`, `:131`), que ces commandes peuvent changer. Seul le cas « invitation en attente » est
  prouvé.
- **Signalement** face à la même leçon (fin de leçon, bilan, partage) : `COMPLETE_LESSON` rattache les observations de
  la leçon. Face à une autre écriture d’enseignement d’une autre leçon (bilan, examen, tarif), la file les sérialise
  encore par domaine ; l’écran est donc bloqué, comme `save`. La clé par agrégat est la proposition 4, hors de ces
  tâches.
- **Création d’invitation dont l’issue est inconnue** : l’écran reste fermé alors que la file accepterait une autre
  création (le code de la première serait perdu). C’est la seule barrière volontairement plus stricte que la file,
  et elle ne peut pas produire le défaut « saisir puis erreur ».

### Site par site

| # | Fichier:ligne | Barrière | Levé | Gardé |
|---|---|---|---|---|
| 1 | `SchoolAgendaUI/SchoolStartNowView.swift:79` (sonde), `:35` (`blocksStart`), `:64-65` (`canStart`), `:531`, `:558`, `:600` (désactivation) | règle exacte pour `START_LESSON_NOW` | invitation, préférence de planning | tarif, bilan/observation/examen (domaine `teaching`), profil, école, `updateMember`, autre époque |
| 2 | `SchoolProfileUI/SchoolProfileWorkspace.swift:159-161` (`pending`, qui pilote `canMutate :65` et `acceptsInput :71`) | règle exacte pour `UPDATE_ADMINISTRATIVE_PROFILE` (dossier) ou `CREATE_PROFILE_FIELD_POLICY` (écran des politiques) | invitation, pour un dossier | tarif, leçon/observation, profil d’un autre élève, école, `updateMember`, politique, autre époque |
| 3 | `SchoolObservationUI/SchoolObservationWorkspace.swift:197` (sonde), `:78` (`canMutate`), `:196` et `:441` (`storedPending` : affichage et reprise de la demande de cette leçon) | règle exacte pour `CREATE_GEO_OBSERVATION` | invitation, préférence de planning, signalement d’une autre leçon | fin de leçon/bilan/examen/tarif, école, autre époque |
| 4 | `SchoolInvitationsUI/SchoolInvitationWorkspace.swift:176` (`blocksCreation`), `:90-92` (`mayEdit`), `:350-353` (`canManage`) | règle exacte pour `CREATE_INVITATION`, puis la même invitation pour renvoi/révocation | invitations distinctes (création, renvoi ou révocation d’une autre) | même invitation, école, autre époque, création à l’issue inconnue |

**Sur le point (b) de la relecture.** Un tarif (`createServiceProduct`) et une écriture de profil étaient déjà
bloquants pour le départ avec l’ancienne lecture `pending(for:domain:.teaching)`, parce que
`SchoolCommandDomain.conflicts` rend `.school` conflictuel avec tout (`SchoolCommandScheduling.swift:8`) : le départ
n’a jamais ouvert sur un tarif ou un profil. Le défaut réel, lui, existait bien pour le profil et les observations
(l’écran s’ouvrait, `save` refusait) ; il est corrigé par la sonde, et le mécanisme empêche désormais toute nouvelle
divergence.

### Vérification

`apps/ios/DrivyTests/SchoolCommandScopes106Tests.swift` : pour chacun des quatre écrans, neuf états réels de la file
chiffrée (invitation, tarif, bilan d’une autre leçon, observation d’une autre leçon, observation de cette leçon, profil
d’un autre élève, changement d’accès, configuration de l’école, ancienne époque) avec l’assertion
« écran ouvert == `save` accepte » ; plus un test par paire desserrée et un test du renvoi (même invitation, autre
invitation, tarif, école). Ajustements : `SchoolCommandSchedulingTests` (deux leçons de signalements indépendantes),
`SchoolCommandOutboxTests` (l’annulation conservée ferme sa leçon, pas une autre école) et
`SchoolProfileWorkspaceTests` (une observation en attente bloque de nouveau le dossier, comme `save`).

**Rien n’a été compilé ni exécuté ici** : cette machine n’a pas de compilateur Swift. Ces tests doivent être lancés sur
un runner Apple avant de considérer la tâche qualifiée.
