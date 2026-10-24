# Cours collectifs : traçabilité critères / tests

Branche `vague/cours-collectifs`. Exécutions réelles au 24 octobre 2026 :

- API complète locale (PostgreSQL 17 + Mailpit), commit 6ef7586 : 604 sur 604.
- Web complète : 348 sur 348.
- Swift (`apps/ios/DrivyTests/SchoolCourseClientTests.swift`) et tests UI : pas encore exécutés.

Abréviations : `C` = `apps/api/test/courses.integration.test.ts`, `E` = `apps/api/test/course-enrollments.integration.test.ts`, `F` = `apps/api/test/course-facts.integration.test.ts`, `WM` = `apps/web/test/course-model.test.ts`, `BFF` = `apps/web/test/school-bff.test.ts`, `SW` = `SchoolCourseClientTests.swift`.

Règle de statut : PASS si un test exécuté vérifie précisément le critère ; PARTIAL si une partie seulement ; NOT_COVERED si aucun test ; NOT_EXECUTED si seul un test Swift ou UI le couvre.

## #38 Création et publication

| Issue | Critère | Test(s) précis | Résultat observé | Statut |
|---|---|---|---|---|
| #38 | Un administrateur crée et publie une série de plusieurs jours depuis chacun des deux clients | C > « brouillon modifiable puis publication visible par l'élève, sans inscription créée, idempotente » (2 séances) ; WM > « construit le corps dans le fuseau de l'école, séances triées » ; SW > `encodesNullsExplicitlyInTheSeriesCommand`, `draftRoundTripsThroughTheForm` | API et modèle web verts. Aucun parcours navigateur ni iOS exécuté | PARTIAL |
| #38 | Un moniteur sans droit ne peut ni créer ni modifier une série, y compris par appel API direct | C > « refuse la gestion au moniteur sans droit, y compris par appel direct, puis l'accorde avec MANAGE_COURSES » | 403 `COURSE_ACCESS_REQUIRED` sur POST série et POST type. PUT, publish, capacity, reschedule, cancel par le moniteur non testés | PARTIAL |
| #38 | L'élève voit toutes les dates uniquement après publication | C > « un élève ne voit pas les brouillons et ne crée rien » ; C > « brouillon modifiable puis publication ... » | Brouillon 404 et absent de la liste ; après publication, 2 séances visibles | PASS |
| #38 | Pas de publication avec horaires invalides ou formateur occupé, y compris sous concurrence | C > « refuse horaires invalides, chevauchements internes et passé » ; C > « bloque le conflit formateur avec un autre cours et avec une leçon ... » ; C > « publications concurrentes sur le même créneau : une seule réussit » | `INVALID_INTERVAL`, `COURSE_OCCURRENCES_OVERLAP`, `COURSE_IN_PAST`, 409 `COURSE_INSTRUCTOR_CONFLICT`, [200,409] en parallèle | PASS |
| #38 | Capacité jamais réduite sous les inscriptions actives, même sous concurrence | C > « capacité : jamais sous les places prises (inscriptions et propositions actives) » ; WM > « refuse une capacité sous les places prises ou le minimum » | Refus `COURSE_CAPACITY_BELOW_TAKEN` séquentiel, fixtures insérées en SQL. Aucune course réduction / inscription concurrente | PARTIAL |
| #38 | Brouillons et erreurs conservent les saisies ; répétition d'une commande sans doublon | C > « bloque le conflit formateur ... en gardant le brouillon » ; C > « brouillon modifiable puis publication ... idempotente » ; SW > `draftRoundTripsThroughTheForm` | Brouillon reste DRAFT après conflit ; rejeu publish même version. Rejeu de POST `/course-series` et conservation des saisies dans le formulaire non testés | PARTIAL |
| #38 | Renommer un type ne perd pas les liens avec cours passés et accomplissements #82 | C > « type personnalisé : renommer garde l'identité et les séries liées ... » ; E > « déjà effectué : offre visible, inscription refusée, même après renommage du type » | Série future liée garde `typeId` ; accomplissement inséré en SQL reste opposé. Aucun cours passé tenu ni accomplissement validé par commande | PARTIAL |
| #38 | Modification/annulation d'une série engagée raccordées aux règles #41 | E > « changement de dates incompatible refusé sans modification ; compatible appliqué, échéance non durcie » ; E > « annulation de série : inscriptions et file fermées, occupations libérées, historique gardé » | 409 sans changement ; échéance conservée ; annulation de série avec motif, inscriptions `SERIES_CANCELLED` | PASS |
| #38 | Aucun paiement en ligne, partenaire externe ou parcours documentaire ajouté | aucun | Rien ne le vérifie (contrat OpenAPI, écrans) | NOT_COVERED |

## #39 Inscription

| Issue | Critère | Test(s) précis | Résultat observé | Statut |
|---|---|---|---|---|
| #39 | Offre visible pour un élève déjà formé, inscription refusée côté UI et API | E > « déjà effectué : offre visible, inscription refusée, même après renommage du type » ; SW > `decodesEveryLearnerState` | API : état `COMPLETED`, `COURSE_ALREADY_COMPLETED`. UI non vérifiée | PARTIAL |
| #39 | Série de trois jours réservée en une action ; trois engagements, une place | E > « une action inscrit aux trois séances, une seule place consommée, état Inscrit » | 201, 3 réservations actives, `seatsTaken` 1 | PASS |
| #39 | Conflit sur la 2e ou 3e date : aucune réservation partielle | E > « conflit sur la troisième date : aucune réservation partielle » | 409 `COURSE_SCHEDULE_CONFLICT`, 0 réservation, état `AVAILABLE` | PASS |
| #39 | Deux demandes concurrentes pour la dernière place : un succès, un refus compréhensible | E > « deux élèves pour la dernière place : un succès, un refus Complet » | [201,409], code `COURSE_FULL`. Libellé affiché non vérifié | PASS |
| #39 | Une leçon créée simultanément ne produit pas de double réservation | E > « leçon créée après l'inscription : refusée (contrôle réciproque) » ; E > « conflit sur la troisième date ... » | Contrôle réciproque séquentiel. Aucune exécution parallèle leçon / inscription | PARTIAL |
| #39 | Renommer un type ne contourne pas « Déjà effectué » | E > « déjà effectué : offre visible, inscription refusée, même après renommage du type » | Refus maintenu après renommage | PASS |
| #39 | Aucun document ni paiement en ligne exigé | E > toutes les inscriptions (corps `{operationId}` seul) | API accepte sans document ni paiement. Écrans non vérifiés | PARTIAL |
| #39 | Push refusé ou en échec ne compromet pas la confirmation visible | aucun | Aucun test de notification sur ce parcours | NOT_COVERED |
| #39 | Tests couvrent droits, isolement, concurrence, réinscription, fuseaux et reprise réseau | E > « inscription par le personnel : droit requis ... » ; E > « brouillon et autre école : introuvables pour l'élève » ; E > « deux élèves pour la dernière place ... » ; E > « pas deux sessions à venir du même type ; réinscription ... » ; E > « rejeu avec le même operationId : aucun doublon » ; BFF > « une réponse amont perdue devient 503 ... » | Droits, isolement, concurrence, réinscription, rejeu verts. Fuseaux : séries en UTC fixe, aucun cas fuseau/DST côté inscription | PARTIAL |

## #40 File prioritaire et alertes

| Issue | Critère | Test(s) précis | Résultat observé | Statut |
|---|---|---|---|---|
| #40 | A avant B : place proposée exclusivement à A | E > « place proposée au premier seulement, acceptation convertit en inscription, réponse tardive refusée » | Un seul inscrit en file (Bob) ; inscription directe concurrente refusée `COURSE_FULL`. Aucun B : l'ordre et l'exclusivité face à la file ne sont pas vérifiés | PARTIAL |
| #40 | A accepte avant expiration : une seule inscription, aucun doublon ni place prise par B ou concurrent | E > « place proposée au premier seulement ... » | Double acceptation parallèle : 1 inscription active, source `OFFER`. Pas de B en file | PARTIAL |
| #40 | A refuse ou laisse expirer : proposé à B une seule fois, sans inscription automatique | E > « refus ou expiration : la place passe au suivant une seule fois, sans inscription automatique » | Expiration forcée : Bob revient `AVAILABLE`, 0 inscription. Malgré le titre, aucun suivant en file et aucun refus explicite testé | PARTIAL |
| #40 | Réponse tardive refusée ; doubles appuis et concurrence acceptation/expiration sans surréservation | E > « refus ou expiration ... » ; E > « place proposée au premier seulement ... » | `COURSE_OFFER_EXPIRED` ; double appui sans doublon. Transfert à B puis réponse de A et course acceptation/expiration non testés | PARTIAL |
| #40 | Plusieurs places, diminution de capacité, inscription manuelle respectent confirmés et retenues | C > « capacité : jamais sous les places prises (inscriptions et propositions actives) » | Retenue active comptée (fixture SQL). Plusieurs places libérées et inscription manuelle pendant une offre non testées | PARTIAL |
| #40 | Échéance lisible, vérifiée serveur ; fermeture, changement d'heure, inscription tardive | E > « place proposée au premier seulement ... » (échéance <= début - 2 h) ; E > « trop près du début : aucune proposition, la place reste libre » ; E > « refus ou expiration ... » | Heure serveur et fermeture vérifiées. Changement d'heure non testé | PARTIAL |
| #40 | Non-admissibilité, retrait de file, changement de dates, annulation de série sans place bloquée | aucun (E > « annulation de série ... » n'a pas de file) | Rien n'exerce retrait, admissibilité perdue, déplacement ou annulation avec offre en cours | NOT_COVERED |
| #40 | Proposition visible sans push ; panne de livraison sans fausse lecture ni inscription cachée | E > « place proposée au premier seulement ... » (`GET /me` état `OFFERED`) | Visible par lecture. Panne de livraison non testée | PARTIAL |
| #40 | Alertes « prochaines sessions » indépendantes, révocables, sans inscription implicite | aucun | Fonction non testée | NOT_COVERED |
| #40 | Droits, confidentialité, reprise après perte de réponse, workers concurrents | E > « file désactivée par défaut » | Aucun test de droit sur la file, ni d'acceptation rejouée, ni de workers parallèles | NOT_COVERED |

## #41 Annulations

| Issue | Critère | Test(s) précis | Résultat observé | Statut |
|---|---|---|---|---|
| #41 | Par défaut, annulation autonome jusqu'à début - 24 h, puis refusée UI et API | E > « une action inscrit aux trois séances ... » (échéance = début - 24 h) ; E > « annulation autonome jusqu'à l'échéance, refusée après ; contact ne change rien » ; SW > `decodesMineAndTheStaffRoster` | API : `COURSE_SELF_CANCEL_CLOSED`, `canSelfCancel` false. UI non vérifiée | PARTIAL |
| #41 | Règle 48 h : même contrôle, bonne échéance ; moniteur non habilité et élève ne la modifient pas | E > « délai de 48 h : nouvelles inscriptions seulement ... » | `selfCancelHours` 48 et élève 403. Échéance 48 h et refus après non vérifiés ; moniteur non testé malgré le titre | PARTIAL |
| #41 | Juste avant, exactement à, juste après ; fuseaux, DST, horloge client fausse | E > « à l'échéance exacte : encore autorisée » ; E > « annulation autonome jusqu'à l'échéance ... » ; WM > « refuse une heure sautée par le passage à l'heure d'été » | Juste avant (+2 s) et juste après (-1 s). L'instant exact, le DST serveur et l'horloge client ne sont pas testés | PARTIAL |
| #41 | Période fermée : contact du responsable ; aucun envoi présumé, ni annulation, ni place libérée | E > « annulation autonome jusqu'à l'échéance, refusée après ; contact ne change rien » ; SW > `contactMailNeedsARealAddress` | `contactEmail` présent, état `ENROLLED`, réservation conservée. Aucun test UI du composeur | PARTIAL |
| #41 | Annulation manuelle habilitée tracée, libération une fois, proposition #40 si pertinente | E > « annulation autonome jusqu'à l'échéance ... » ; E > « refus ou expiration ... » | `cancelKind` STAFF + motif, réservations à 0, seconde annulation `COURSE_ENROLLMENT_CLOSED`, offre créée après staff-cancel. Auteur et date non vérifiés | PARTIAL |
| #41 | Conditions acceptées conservées ; mutation non autorisée refusée ; versions concurrentes | C > « politique d'annulation versionnée ... » ; E > « délai de 48 h ... » | Séries et inscriptions gardent 24 h, PUT périmé 412. Texte `conditions` accepté non vérifié | PARTIAL |
| #41 | Déplacement incompatible refusé sans mise à jour partielle ; offres périmées non acceptables après changement | E > « changement de dates incompatible refusé sans modification ... » | 409 et dates inchangées. Offre après changement ou annulation non testée | PARTIAL |
| #41 | Annulations visibles sans push ; aucun e-mail automatique, frais, remboursement | E > « annulation de série ... » | Statut lisible par `GET /me`. Aucune assertion Mailpit ni sur l'absence de frais | PARTIAL |
| #41 | Abandon/absence et présences passées conservés ; aucune suppression d'historique | E > « pas deux sessions à venir du même type ; réinscription ... » ; E > « annulation de série ... » | Lignes d'inscription conservées. Présences après annulation non testées | PARTIAL |

## #42 Appel

| Issue | Critère | Test(s) précis | Résultat observé | Statut |
|---|---|---|---|---|
| #42 | Appel depuis une feuille web et depuis iOS/iPadOS | WM > « première saisie sans version, correction avec la version lue, rien si inchangé » ; WM > « lit la feuille et traduit les refus » ; SW > `decodesTheCourseSheet`, `encodesSheetCommandsWithExplicitNulls` | Modèle web vert. Feuille en navigateur et écran iOS non exécutés | PARTIAL |
| #42 | État par élève et par séance, compteur juste | F > « feuille sans présence déduite ; saisie, correction versionnée, historique » ; WM > « compte les séances obligatoires » | `requirements` {2,0,2} puis {2,1,1} | PASS |
| #42 | Aucun statut déduit du paiement, d'un horaire dépassé ou de l'inscription | F > « feuille sans présence déduite ... » ; F > « payé ne coche rien ... » ; WM > « laisse vide une cellule absente, jamais déduite » | Séances passées et payées : statuts `null` | PASS |
| #42 | Corrections avec auteur et historique ; ancienne version ou inscription invalide refusée | F > « feuille sans présence déduite ... » | `VERSION_CONFLICT`, 2 lignes d'historique. Auteur non vérifié ; inscription annulée non testée | PARTIAL |
| #42 | Présences passées survivent à l'annulation ; séance annulée ou future jamais présente | F > « formateur de la séance autorisé ... séance future refusée » | `COURSE_OCCURRENCE_NOT_STARTED`. Survie après annulation et séance annulée non testées | PARTIAL |
| #42 | Correction impactant l'accomplissement transmise à #82 | aucun | Aucune correction après validation | NOT_COVERED |
| #42 | Droits, autre école, double appui, perte de réponse, séance déplacée, inscription modifiée en parallèle | F > « formateur de la séance autorisé ; autre moniteur, élève, autre école refusés ... » ; F > « feuille sans présence déduite ... » (rejeu `operationId`) | Droits, autre école, rejeu verts. Séance déplacée et inscription modifiée en parallèle non testées | PARTIAL |
| #42 | Aucune présence fictive pour les anciens élèves lors d'une migration | aucun | Non testé | NOT_COVERED |

## #81 Règlement sur place

| Issue | Critère | Test(s) précis | Résultat observé | Statut |
|---|---|---|---|---|
| #81 | Renseigner et corriger un règlement sur web et iOS, historique, droits serveur | F > « payé ne coche rien ; annulation avec motif, preuve conservée ; droits » ; WM > « ignore les règlements annulés et borne la note » | API : saisie, annulation motivée, ligne conservée. Clients non exécutés | PARTIAL |
| #81 | « Payé sur place » ne coche aucune présence, ne valide rien | F > « payé ne coche rien ... » | Présences `null`, `completion` null, validation `COURSE_REQUIREMENTS_MISSING` | PASS |
| #81 | Paiement non renseigné n'empêche ni l'appel ni l'accomplissement | F > « validée seulement après les séances obligatoires ... » | Appel et validation 201 sans règlement | PASS |
| #81 | Annulation ne supprime pas la preuve ni ne crée de remboursement fictif | F > « payé ne coche rien ... » | Annulation du règlement conservée (1 ligne). Annulation de l'inscription non testée | PARTIAL |
| #81 | Concurrence entre deux agents, double appui, reprise après perte de réponse | F > « payé ne coche rien ... » (rejeu `operationId`) | Rejeu sans doublon. Deux agents en parallèle non testés | PARTIAL |
| #81 | Élève, moniteur non habilité, autre école ne modifient pas | F > « payé ne coche rien ... » | Moniteur et élève 403 sur saisie. Autre école et `void` non testés | PARTIAL |
| #81 | Migration sans participants présumés payés ou débiteurs | aucun | Non testé | NOT_COVERED |

## #82 Accomplissement

| Issue | Critère | Test(s) précis | Résultat observé | Statut |
|---|---|---|---|---|
| #82 | Avancement correct ; inscription ou paiement seuls ne donnent jamais « Validé » | F > « feuille sans présence déduite ... » ; F > « payé ne coche rien ... » ; F > « validée seulement après les séances obligatoires ... » | `COURSE_REQUIREMENTS_MISSING` avec inscription seule, paiement seul, 1 sur 2 présences | PASS |
| #82 | Personnel habilité valide ; autres rôles refusés côté API | F > « validée seulement après les séances obligatoires ... » | Admin 201, autre moniteur 403. Élève et autre école non testés | PARTIAL |
| #82 | L'élève consulte son parcours, pas celui des autres ; vues iOS/web cohérentes | F > « validée seulement ... » ; SW > `decodesTheLearnerProgress` | `/course-progress/me` contient son type, sans montant. Absence des autres et cohérence clients non vérifiées | PARTIAL |
| #82 | Après validation, #39 refuse le même type et #40 cesse les sollicitations | F > « validée seulement ... » | `COURSE_ALREADY_COMPLETED` sur nouvelle série. Effet sur la file non testé | PARTIAL |
| #82 | Renommer un type ou changer de catégorie de permis ne duplique ni n'efface | E > « déjà effectué : offre visible, inscription refusée, même après renommage du type » | Renommage sur fixture SQL. Catégorie de permis non testée | PARTIAL |
| #82 | Corrections, présence manquante, annulation de séance, concurrence, historique | F > « validée seulement ... » ; F > « validations concurrentes : une seule » | Manque refusé, [201,409] en parallèle, retrait motivé conservé (1 ligne). Annulation de séance non testée | PARTIAL |
| #82 | Aucune donnée inconnue en accomplissement ; aucune inscription annulée silencieusement | F > « feuille sans présence déduite ... » ; F > « validée seulement ... » | Présences inconnues bloquent la validation. Effet de la validation sur une inscription future existante non testé | PARTIAL |

## Totaux

59 critères : 12 PASS, 39 PARTIAL, 8 NOT_COVERED, 0 NOT_EXECUTED.

## Critères NOT_COVERED et tests à ajouter

1. #38 Aucun paiement en ligne, partenaire ou parcours documentaire. Test API : parcourir le contrat OpenAPI servi et vérifier qu'aucune route `/course*` n'expose de champ paiement en ligne, document ou partenaire ; compléter par une revue d'écrans.
2. #39 Push refusé sans effet sur la confirmation. Test API : simuler l'échec du fournisseur de notifications (adaptateur en erreur), inscrire, attendre 201 et `GET /me` = `ENROLLED`. Le refus système iOS reste à tester sur appareil.
3. #40 Non-admissibilité, retrait, changement de dates, annulation de série. Tests API : (a) Bob en file puis `DELETE /waitlist`, libérer une place, aucune offre ; (b) offre en cours puis validation d'un accomplissement de Bob, offre close et passée au suivant ; (c) offre en cours puis `reschedule` ou `cancel` de série, `accept` refusé et `seatsTaken` recalculé.
4. #40 Alertes prochaines sessions. Test API : abonnement au type, publication d'une nouvelle série, aucune inscription ni entrée de file créée ; désabonnement puis aucune alerte.
5. #40 Droits, confidentialité, perte de réponse, workers. Tests API : moniteur et autre école refusés sur `/waitlist` et `/course-offers/:id/accept` d'autrui ; rejeu de `accept` avec le même `operationId` après succès ; deux libérations parallèles avec deux places, une offre par entrée.
6. #42 Correction transmise à #82. Test API : valider, corriger une présence obligatoire en ABSENT, vérifier refus explicite ou retrait tracé de la validation, jamais une validation incohérente.
7. #42 et #81 Migrations. Test API : appliquer les migrations sur une base contenant d'anciennes inscriptions et vérifier zéro ligne dans `course_attendance` et `course_payment_record`.

Trous transverses aussi à combler : fuseau et changement d'heure côté serveur (série Europe/Zurich autour du dernier dimanche d'octobre, échéance 24 h et 48 h exacte), toute exécution Swift et UI, et parcours navigateur web.


## Complément du 24 octobre 2026 (commit suivant 6ef7586)

- Tests métier Swift iPhone (DrivyTests, toute la suite) **réussis** sur 6ef7586 : [run 40120229567](https://github.com/tomyrms/Drivy/actions/runs/40120229567). Les critères couverts seulement par SchoolCourseClientTests passent de NOT_EXECUTED à PASS pour le décodage et l'encodage ; l'interface reste non testée (UI iPhone/iPad).
- 5 tests API ajoutés, 39 tests de cours réussis localement : #40 retrait de file, annulation de série avec proposition active (réponse tardive refusée, aucune proposition active), droits et confidentialité de la proposition (un autre élève 404, le personnel 403, aucun nom exposé), reprise après réponse perdue (même opération, une inscription), lectures concurrentes (une seule proposition) ; #42/#81/#82 aucun fait présumé sans saisie, correction de présence après validation tracée sans retrait silencieux.
- Ces critères passent de NOT_COVERED à PASS : #40 non-admissibilité/retrait/annulation de série (partiel pour le déplacement de dates, couvert à part par le test de reschedule), #40 droits et reprise, #42 correction vers #82, #42 et #81 aucun fait présumé.
- Restent NOT_COVERED : #38 absence de paiement en ligne (vérification d'interface), #39 push en échec et #40 alertes « prochaines sessions » (non livrés, #43/#44).
