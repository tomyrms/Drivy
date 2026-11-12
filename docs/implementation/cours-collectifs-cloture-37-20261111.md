# Cours collectifs (#37) : critères de clôture contre le code de `master` `ff79607a`

11 novembre 2026. Relecture critère par critère de l'épopée contre le code et les tests présents dans le dépôt.
Aucun changement de produit. Une seule addition de test (horloge d'appareil fausse, #41). Les preuves citées sont
celles que les documents et les runs du dépôt établissent ; rien n'est déduit d'un simulateur pour le physique.

Légende : **PROUVÉ** = un test exécuté dans un run cité vérifie le critère ; **NON PROUVÉ** = le code existe mais
aucun run ne vérifie précisément le critère ; **PHYSIQUE / DÉCISION** = ne peut pas être établi depuis le dépôt.

## Les neuf critères de recette transversale

| # | Critère de l'issue | Statut | Preuve ou manque |
|---|---|---|---|
| 1 | Mêmes droits et résultats sur iOS, iPadOS, web et API | PROUVÉ en partie | API : `courses`, `course-enrollments`, `course-facts` (droits, autre école, brouillon, moniteur sans droit). Web : `course-model`, `course-participants-lane`, `school-bff`. iOS : `SchoolCourseJourneyUITests` 13 sur 13 sur iPhone et 12 sur 13 sur iPad au candidat `7c2acdb1` (run 42105462976), l'échec iPad corrigé puis réussi seul au candidat `b562c0e0` (run 42113479468). Les douze autres cas n'ont pas été rejoués sur `b562c0e0` ; aucun run unique ne les réunit. Équivalence des résultats web et iOS contre un même serveur réel non établie. |
| 2 | Offre publiée visible sans inscription ni occupation ; inscription unique pour toute la série | PROUVÉ | `courses` « brouillon modifiable puis publication visible par l'élève, sans inscription créée » ; `course-enrollments` « une action inscrit aux trois séances, une seule place consommée » et « conflit sur la troisième date : aucune réservation partielle ». |
| 3 | Aucune surréservation, double inscription ou fuite inter-écoles, retenues et workers concurrents compris | PROUVÉ | `course-concurrency` (double appui, réduction de capacité simultanée), `course-enrollments` (dernière place, lectures concurrentes de la file), `courses` « isole les écoles » et « publications concurrentes sur le même créneau ». Limite : deux apprenants de démonstration seulement, donc pas de test avec plusieurs places libérées à la fois ni avec trois personnes en file. |
| 4 | Annulation autonome refusée après échéance ; contact sans effet ; décision manuelle auditée | PROUVÉ | `course-enrollments` « annulation autonome jusqu'à l'échéance, refusée après ; contact ne change rien », « à l'échéance exacte », fuseaux et changement d'heure dans `course-timezone`. **Ajouté ce jour** : horloge d'appareil fausse (deux sens), l'échéance reste celle du serveur. |
| 5 | Place offerte dans l'ordre, acceptation explicite, refus ou expiration puis suivant, sans double attribution | PROUVÉ | `course-enrollments` (place proposée au premier seulement ; refus ou expiration ; trop près du début ; retrait de file ; série annulée), `course-notifications` (passage au suivant sans action). |
| 6 | Présence, règlement et accomplissement distincts ; aucune validation automatique | PROUVÉ | `course-facts` (payé ne coche rien ; aucun fait présumé ; validation explicite), `course-completion-effects`, interface `SchoolCourseJourneyUITests` « trois actions distinctes » (run 42113479468, iPad). |
| 7 | Préférences push sans effet caché sur les engagements ou la file ; aucun courriel automatique de cours | PROUVÉ côté serveur | `course-notifications` (préférence désactivée : information toujours consultable), `course-push-failure` (confirmation intacte à chaque étape), `course-push-revalidation`. Aucun envoi de courriel de cours n'existe dans le code. **Réception APNs réelle : PHYSIQUE.** |
| 8 | Aucun périmètre financier ou externe ajouté par effet de bord | PROUVÉ côté API | `course-no-online-payment` (routes et réponses sans champ de paiement, de prix, de document ni de partenaire). Revue d'écrans iOS et web sans montant en ligne : non faite par un test. |
| 9 | Preuves et limites dans #83 et #84 ; l'épopée reste ouverte jusqu'à réalisation et vérification | Voir ci-dessous | |

## Sous-issues

Toutes les sous-issues #38 à #44, #79 à #83 ont une réalisation documentée : `cours-collectifs-cadrage-79.md`,
`cours-collectifs-socle-80.md`, `cours-collectifs-inscriptions-39-41.md`, `cours-collectifs-faits-42-81-82.md`,
`cours-collectifs-notifications-43-44.md`, et la matrice `docs/qa/cours-collectifs-tracabilite.md`.

## Reste du suivi, point par point

| Reste annoncé | État |
|---|---|
| SIGTERM sur POSIX | **Exécuté** sur Linux : le test `course-worker-process.integration.test.ts` n'est ignoré que sous Windows ; le run 42786457056 (10 novembre, `57899be7`) l'a exécuté avec succès (relevé dans `checkup-issues-20261107.md`). Le run de ce lot ajoute une exécution sur sa branche (voir STATUS.md). |
| Rapprochement de la matrice #83 | La matrice date du 24 octobre (59 critères : 19 PASS, 34 PARTIAL, 6 NOT_COVERED au recomptage du 31 octobre). Elle n'a pas été recomptée ligne par ligne depuis : de nombreux tests citent des critères qu'elle donne encore pour partiels. Ce lot ne la réécrit pas sans pouvoir exécuter les 59 lignes ; le recomptage reste une tâche de qualification. |
| Appareil distinct, APNs | **PHYSIQUE / DÉCISION.** Aucune clé APNs ni appareil n'est utilisable depuis le dépôt ; le droit APNs est activé dans le projet, la signature iLoader et la réception restent à qualifier par le porteur. |
| Cas absents de la matrice | Plusieurs places libérées ensemble, inscription manuelle pendant une offre, trois personnes en file : exigent plus de deux apprenants de démonstration dans le harnais de test (`prepareSchool`). Non livré. |
| Worker d'expiration autonome | Livré depuis (`course-worker.ts`, rôle `drivy_course_worker`). L'activation sur le homelab reste soumise à la qualification (voir `cours-collectifs-notifications-43-44.md`). |

## Recommandation

**#37 reste ouverte.** Son périmètre est réalisé et très largement prouvé par des tests API sur PostgreSQL réelle et
par des parcours iOS sur simulateur, mais l'issue exige elle-même « réalisé **et vérifié** » : manquent la réception
APNs sur appareil, l'exécution d'un seul run Apple réunissant les treize cas sur iPhone et iPad, le recomptage de la
matrice, et un parcours multi-clients contre un même serveur réel. Ce qui peut se fermer sans appareil, c'est la
sous-issue #43/#44 côté serveur ; la décision de clôturer l'épopée appartient au porteur.
