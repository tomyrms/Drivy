# Pilotage de l'école (#373) : dictionnaire des indicateurs, sources et droits

Lot T01 (#374) de l'epic #373. 31 octobre 2026. `definitionsVersion` : **`2026-10-31.1`**.

Base lue : `master` à `2a376c39` (fusion de #384, qui contient la refonte web #311). Spécification seulement : aucune route, aucune migration, aucun changement du contrat OpenAPI canonique 3.11.0, aucun calcul exécuté sur une école réelle. Les totaux du jeu de référence (section 6) ont été recalculés par un petit script indépendant du produit, avec des données entièrement fictives (codes `M1`, `E1`, `S1`... aucun nom).

Plan : 1. conventions communes · 2. ce que le code garantit réellement · 3. dictionnaire · 4. calculable maintenant / à compléter / hors V1 · 5. matrice des droits · 6. jeu de référence · 7. contrat commun proposé · 8. décisions à relire · 9. tests de référence préparés · 10. limites.

## 1. Conventions communes

Elles s'appliquent à chaque indicateur de la section 3 ; le dictionnaire ne les répète pas.

| Réf. | Règle |
| --- | --- |
| K1 Périmètre | Une seule école (`schoolId` de la route). Identité, rattachement, rôles et grants sont relus au serveur à chaque requête (`withActor` relit `membership`). Aucun agrégat inter-écoles. |
| K2 Fuseau et bornes | Période = dates civiles `from` incluse, `toExclusive` exclue, dans le fuseau **courant** `school.time_zone` (pas celui du navigateur ni UTC). Chaque borne est le premier instant existant du jour civil (même règle que `startOfDay` de `agenda-model.ts`). Un jour dure 23, 24 ou 25 h ; une semaine ou un mois ne se calcule jamais en ajoutant `N × 24 h`. Semaine = lundi à dimanche (comme l'agenda). Période maximale 366 jours. |
| K3 Instant de calcul | `computedAt` = instant de début de la transaction de lecture. « À venir », « à vérifier », « en cours », « à finaliser » et les places sont évalués à cet instant. Aucun état n'est déduit d'un horaire passé. |
| K4 Rattachement unique | Chaque leçon a **un seul** instant de rattachement `eventAt` : `actual_start` si la leçon est `COMPLETED` et a un début réel, sinon `planned_start`. Une leçon appartient donc à une seule période et les statuts d'une période se partitionnent : réalisées + à venir + annulées + absences + à vérifier + en cours + à finaliser = toutes les leçons de la période (contrôle de cohérence, indicateur L08). Les séances de cours se rattachent à `starts_at`, les règlements à `recorded_at`, les inscriptions à `created_at`/`cancelled_at`. Rien n'est découpé à minuit : une séance qui traverse minuit appartient au jour de son début. |
| K5 Confirmé | Seules les lignes serveur comptent. Une commande locale en attente ou incertaine (`command-store`) n'est jamais incluse. Une « réservation confirmée » est une ligne `lesson` au statut `PLANNED`. |
| K6 Zéro, inconnu, partiel | Trois états distincts, jamais confondus : **zéro connu** (la requête a réussi et rien ne correspond), **inconnu/indisponible** (source absente ou non couverte : `null`, jamais 0), **partiel** (valeur calculée sur une partie seulement, avec la part exclue et sa raison). Un échec réseau n'est jamais un zéro. L'absence de droit **omet** la mesure de la réponse (elle ne devient ni 0 ni « non applicable »). |
| K7 Unités et arrondis | Compteurs : entiers. Durées : somme en secondes entières (chaque durée = `floor` des secondes), arrondie à la minute (demi vers le haut) **seulement à l'affichage et après sommation**. Montants : centimes entiers (`bigint` côté SQL, entier JSON ≤ 2^53 − 1, dépassement refusé), aucune division ni virgule flottante. Pourcentage : `delta × 1000 / base` arrondi demi à l'écart de zéro, divisé par 10 (une décimale), calculé en entiers côté serveur. Affichage des montants : `Intl.NumberFormat('fr-CH', { style: 'currency', currency: 'CHF' })`, jamais de formatage manuel. |
| K8 Devise | `CHF`, constante. Aucune colonne de devise n'existe (`school`, `lesson`, `service_product_version`) et la projection de compte écrit `currency: 'CHF'` en dur. La réponse porte `currency: 'CHF'` pour que le jour où une autre devise apparaîtrait, les montants ne soient pas additionnés. |
| K9 Comparaison | Trois modes explicites : **mois complet** (mois civil entier contre mois civil entier, longueurs 28 à 31 jours affichées) ; **mois à date** (du 1er au jour courant inclus, jour entier, contre la même plage de jours du mois précédent, tronquée à la fin de ce mois s'il est plus court, avec `clipped: true`) ; **période équivalente** (même nombre de jours civils immédiatement avant). Le jour courant est compté en entier côté courant : les leçons pas encore réalisées y sont « à venir », donc hors « réalisées ». Le résultat donne `current`, `base`, `delta`, `daysInPeriod`, `daysInBase`. `percentTenths` (dixièmes de pour cent, entier) n'existe que si **base > 0, base connue et les deux côtés complets** ; sinon `percentTenths: null` avec une raison parmi `BASE_ZERO`, `BASE_BEFORE_DATA_START`, `PARTIAL_COVERAGE`. Jamais de pourcentage infini ni de « +100 % » fictif. |
| K10 Début de couverture | `dataSince` = **date civile** (fuseau de l'école) du plus ancien `created_at` parmi les leçons et séries de cours de l'école (`school` n'a pas de `created_at`) ; `null` si l'école n'a encore rien enregistré. Une période dont `toExclusive <= dataSince` est **inconnue** : ses mesures valent `null` (`BEFORE_DATA_START`), pas 0, et en base d'une comparaison elle donne `BASE_BEFORE_DATA_START`. Une période avec `from < dataSince < toExclusive` est calculée mais marquée partielle (`STARTS_BEFORE_DATA_START`). Une école sans aucune donnée (`dataSince = null`) a des zéros connus et aucune base de comparaison. |
| K10b Tout exclu | Quand toutes les lignes d'une mesure sont exclues pour une raison de couverture (durée inconnue, mode pack, compte incohérent), la valeur est `null` (`UNAVAILABLE`), pas 0 ; quand une partie seulement est exclue, la valeur est la somme du reste et la mesure est `PARTIAL` avec le nombre exclu. |
| K11 Filtres | Moniteur (`instructor_membership_id`), permis (`category_code` de l'offre de la formation), prestation (`product_key` de la version de prestation choisie). Tous sont validés côté serveur ; un filtre inapplicable à une mesure la rend `NOT_APPLICABLE` (jamais ignoré silencieusement). Les filtres permis et prestation ne s'appliquent pas aux cours (un cours n'a ni permis ni prestation dans le modèle). |
| K12 Population | Leçons de l'école, **tous statuts**, y compris celles d'élèves archivés (l'archivage ne réécrit pas le passé) et de moniteurs dont l'accès est révoqué (la ligne `membership` reste). Les chiffres d'une période peuvent bouger après coup (correction d'issue, annulation d'un règlement) : `computedAt` le dit, aucun instantané historique n'est promis. |
| K13 Granularité | Séries par jour, semaine (lundi) ou mois civil. Un nombre d'élèves **distincts** se recalcule par intervalle, il ne s'additionne jamais d'un intervalle à l'autre. Le premier et le dernier intervalle d'une série sont marqués `partial: true` quand ils débordent de la période. 400 points au plus par série. |
| K14 Version | Toute modification d'une formule ou d'un statut inclus change `definitionsVersion` (format `AAAA-MM-JJ.n`, comme `swissProgrammeVersion`). Chaque réponse d'agrégat, de série, de détail et chaque CSV la porte. |

## 2. Ce que le code garantit réellement (vérifié sur `master` `2a376c39`)

Chaque ligne a été lue dans le code, pas déduite de listes web paginées.

| # | Constat | Source | Conséquence pour les indicateurs |
| --- | --- | --- | --- |
| Q1 | `lesson.status` vaut `PLANNED`, `COMPLETED`, `CANCELLED` ou `NO_SHOW`. Colonnes utiles : `planned_start/end`, `actual_start/end` (nullables, CHECK `lesson_actual_interval` : les deux nuls, ou début non nul et fin nulle ou postérieure), `price_cents_snapshot` (bigint ≥ 0, non nul), `commercial_selection` (jsonb : `mode`, `serviceProductVersionId`, `quantity`), `instructor_membership_id`, `learner_id`, `training_id`, `time_zone`, `created_at`. Index `lesson_schedule (school_id, planned_start, id)`. | migrations 006, 007, 023 | Base de L01 à L08. L'index couvre les périodes par `planned_start` ; le rattachement par `actual_start` demandera un index propre (section 7.6). |
| Q2 | Une leçon commencée reste `PLANNED` avec `actual_start` renseigné. `COMPLETED` n'est posé que par `POST /lessons/{id}/complete`, qui fixe le début réel (déjà enregistré ou fourni) et la fin réelle (obligatoire). La préparation GPS laisse la leçon `PLANNED` sans `actual_start`. | `lessons.ts` (`startLesson`, `start-now`), `lesson-reports.ts`, migration `20261028b` | Ni l'heure prévue ni une trace GPS ne produisent « réalisée ». Équivalent web : `lessonPhase` (`agenda-model.ts`) : `waiting` = L05, `started` = L06, `to-finish` = L07, `planned` = L02. |
| Q3 | Il n'existe **aucune** date d'annulation ni d'absence sur `lesson` (seulement `cancel_reason_code`, `cancel_comment`, `no_show_reason`). L'annulation remet `actual_start` à `NULL`. | migrations 006, 011 ; `lessons.ts` (`cancel`) | Annulées et absences se rattachent à `planned_start` (K4), jamais à un instant d'annulation inventé. |
| Q4 | La correction d'issue (ADMIN) ne sait aller que de `COMPLETED` vers `CANCELLED` ou `NO_SHOW` ; le retour vers `COMPLETED` ou `PLANNED` est refusé (`OUTCOME_CORRECTION_NOT_READY`). Elle remet `actual_start/end` à `NULL`, contre-passe la charge (`charge_entry` `REVERSAL`) et écrit `lesson_outcome_correction`. | `lesson-outcomes.ts`, migration 011 | Un total passé peut baisser après coup. Une leçon corrigée retombe sur `planned_start` (K4). |
| Q5 | `price_cents_snapshot` est écrit à l'INSERT : prix unitaire de la version de prestation × quantité (exception ADMIN seulement au déplacement). Il n'est modifié que par `MOVE_LESSON` avec `commercialChange`, sur une leçon `PLANNED` non commencée, avec une ligne `lesson_commercial_revision` (`revision`, `price_cents`, `reason`). `service_product_version` n'accorde à `drivy_app` que SELECT et INSERT : un nouveau tarif est une **nouvelle version**, jamais une réécriture. À la complétion, `lesson_account.planned_price_cents` et une `charge_entry` `INITIAL` égale au snapshot sont créées ; une leçon `COMPLETED` n'est plus déplaçable (`LESSON_CLOSED`). | migration 006, `lessons.ts` (`validateCommercial`, `move`), `lesson-reports.ts` (`complete`) | Le snapshot d'une leçon `COMPLETED` est final. Valeur = snapshot, jamais le tarif courant (le cas de tarif révisé de la section 6 le teste). |
| Q6 | `lesson_account` existe aussi pour `CANCELLED` et `NO_SHOW` (`openClosedAccount`, backfill de la migration 011) avec `planned_price_cents` égal au prix réservé, **sans charge**. | `lessons.ts`, migration 011 | Piège : `planned_price_cents` ne doit jamais être lu comme une valeur due. Annulations et absences ne valent rien. |
| Q7 | Aucun paiement de leçon n'est stocké : la projection de compte renvoie `payments: []` et `netReceivedCents: 0` en dur. | `lesson-reports.ts` (`account`) | Les règlements ne couvrent pas les leçons individuelles. « Reste à payer » n'existe pas. |
| Q8 | Le mode `ENTITLEMENT` (pack) est refusé à la réservation et à la complétion (`ENTITLEMENT_NOT_READY`). | `lessons.ts`, `lesson-reports.ts` | Aucune leçon n'en porte aujourd'hui ; la règle F01 reste défensive (si une ligne existe, sa valeur n'est pas comptée). |
| Q9 | `course_series` n'a **ni prix ni lien** vers `service_product_version` (colonnes : type, titre, capacité, politique d'annulation...). `course_enrollment` ne fige aucun prix. Le catalogue sait décrire un produit `COLLECTIVE_COURSE`, mais aucune série n'y renvoie. | migration 042 | Aucune valeur contractuelle de cours n'est calculable (F07 indisponible). |
| Q10 | `course_payment_record` : `amount_cents` ≥ 0 libre (« informatif », zéro permis), `method = 'ON_SITE'` seule valeur, `recorded_by`, `recorded_at` (instant de **saisie**), `note`, `voided_at/voided_by/void_reason`. Annuler = poser `voided_at` avec motif (`course_void_payment`), la ligne reste. Pas de date de paiement, pas de remboursement, pas de lien à un prix. Annuler une inscription ou la série ne touche pas les règlements. Lecture et écriture : `course_can_record_payment` = `can_manage_courses` (ADMIN, ou INSTRUCTOR avec `MANAGE_COURSES`) ou rôle ADMIN/INSTRUCTOR avec le grant `cash_record`. | migrations 042, 044 ; `course-facts.ts` ; `participants-model.ts` (`settledCents`, « confirmed records keep counting ») | Date des règlements = date de saisie, nommée comme telle. Règlements de **cours seulement**. |
| Q11 | Séries : `DRAFT`, `PUBLISHED`, `CANCELLED`, `CLOSED` (aucune écriture ne produit `CLOSED` aujourd'hui). `course_cancel_series` (série publiée seulement) annule les inscriptions (`cancel_kind = 'SERIES_CANCELLED'`), révoque les propositions et libère les occupations futures, mais garde présences et règlements. Inscription : `ACTIVE`/`CANCELLED`, `created_at`, `cancelled_at`, `cancel_kind` (`SELF`, `STAFF`, `SERIES_CANCELLED`). Places occupées = `course_seats_taken` = inscriptions `ACTIVE` + propositions `ACTIVE` non échues (instantané). Présence : une ligne `course_attendance` par (inscription, séance), saisissable seulement après le début de la séance ; pas de ligne = non renseigné. | migrations 042, 043, 044 | C01 à C11. |
| Q12 | `availability_rule` est modifiée **en place** (GRANT UPDATE sur jours, heures, validité) sans historique ; `closure` est une fermeture ponctuelle. | migrations 006, 022 | Le dénominateur d'un taux de remplissage du planning ne se reconstitue pas pour une période passée : indicateur hors V1. |
| Q13 | Le grant `membership.grants` accepte déjà `VIEW_SCHOOL_METRICS`, `VIEW_FINANCIAL_METRICS` et `EXPORT_MANAGEMENT` (CHECK de la migration 026, enum zod de `catalogue.ts`, libellés de `access-controller.ts`). Seul un ADMIN les attribue (`PATCH members`, réauthentification, audit). **Aucun code serveur ne les lit aujourd'hui.** À la création d'une école, l'ADMIN reçoit seulement `CONFIGURE_CATALOG`. | `catalogue.ts`, `school-opening.ts` | Aucune nouvelle permission n'est nécessaire (section 5). Le contrôle reste à écrire en T02. |
| Q14 | Sous RLS, un ADMIN lit toutes les leçons de l'école. Un moniteur lit une leçon s'il en est le moniteur **et** affecté à la formation à l'instant courant (`lesson_access`), ou si la formation lui est actuellement affectée (`report_training_access`). Une affectation terminée retire donc à un moniteur la lecture de ses anciennes leçons. | migrations 006, 007 | Un agrégat « ma propre activité » calculé sous RLS **sous-compterait en silence**. Le périmètre doit être appliqué explicitement par une fonction serveur (section 8, décision D1). |
| Q15 | `withActor` ouvre `BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY`, passe en rôle `drivy_app` et relit `roles`, `grants`, `access_epoch`. Toutes les mesures d'une même requête partagent donc un instantané ; deux requêtes successives n'en partagent pas. `Cache-Control: no-store` est posé sur toutes les réponses. | `database.ts`, `app.ts` | Cohérence carte et série dans une réponse ; entre agrégat et détail, un écart est détecté, pas évité (section 7.5). |
| Q16 | Aucun export CSV n'existe dans l'API ni dans le web. La conception v3.17 (R96, `statistiques.md`) prévoit `EXPORT_MANAGEMENT`, 10 000 lignes, neutralisation des formules, aucune URL permanente. | recherche dans `apps/api/src` et `apps/web/client` | L'export est entièrement à écrire (T07). |
| Q17 | `GET /lessons` plafonne à 100 résultats par page (curseur HMAC lié à la portée). `agenda-model.ts` et `lesson-planning-model.ts` ne servent qu'à l'affichage et au formulaire de planification. | `lessons.ts` | Aucun compteur n'est calculé depuis ces listes. |
| Q18 | Aucune table de demandes élève vers l'école n'existe (`training_wish` est un texte libre de souhait). Depuis la décision du 28 septembre 2026, le bilan est partagé automatiquement : « bilans à publier » (M09 de la conception) n'a plus d'objet. | migration 007 ; `lesson-reports.ts` (`syncSharedReport`) ; `decisions-2026-09-28.md` | Le bloc « À traiter » ne contient que des obligations démontrées (A01 à A03). |

## 3. Dictionnaire des indicateurs

Légende : **Source** = table et colonnes réelles. **Pér.** = événement de rattachement (K4). Les droits sont ceux de la section 5 : `ACT` = lecture de l'activité de l'école (ADMIN ou `VIEW_SCHOOL_METRICS`) ou de la sienne (moniteur) ; `FIN` = ADMIN ou `VIEW_FINANCIAL_METRICS`.

### 3.1 Leçons individuelles : états

Toutes les lignes portent `school_id = :schoolId`, passent les filtres K11 et se rattachent par `eventAt` (K4). « Planifiée » désigne `status = 'PLANNED'`.

| ID | Libellé affiché | Unité | Formule et statuts | Inclus / exclus | Droit |
| --- | --- | --- | --- | --- | --- |
| L01 | Leçons réalisées | leçons | `count(*)` où `status = 'COMPLETED'` ; `eventAt = actual_start`, ou `planned_start` si `actual_start` est nul (cas défensif, signalé `ACTUAL_START_MISSING` dans la couverture). | Exclut tout autre statut. Une leçon sans trace GPS compte pareil. Une leçon de plusieurs unités (quantité 2) compte pour **1**. | ACT |
| L02 | Leçons à venir | leçons | Planifiée, `actual_start IS NULL`, `planned_start > computedAt`. | Réservation confirmée future. Exclut les leçons dont l'heure est passée (L05) et les commencées (L06, L07). | ACT |
| L03 | Leçons annulées | leçons | `status = 'CANCELLED'` ; `eventAt = planned_start` (Q3). | Toute raison d'annulation. Valeur nulle (Q6). | ACT |
| L04 | Absences | leçons | `status = 'NO_SHOW'` ; `eventAt = planned_start`. | Constatées par l'école après la fin prévue. Aucun frais déduit. | ACT |
| L05 | À vérifier | leçons | Planifiée, `actual_start IS NULL`, `planned_start <= computedAt`. | Créneau passé sans départ ni constat ; équivalent de `waiting`. Exclut les futures et les commencées. Ne devient jamais « réalisée » d'elle-même. | ACT |
| L06 | En cours | leçons | Planifiée, `actual_start IS NOT NULL`, `planned_end > computedAt`. | Départ enregistré, fin prévue pas encore atteinte. | ACT |
| L07 | À finaliser | leçons | Planifiée, `actual_start IS NOT NULL`, `planned_end <= computedAt`. | Départ enregistré, aucun constat de fin. Alimente le bloc « À traiter ». | ACT |
| L08 | Total des leçons de la période | leçons | L01 + L02 + L03 + L04 + L05 + L06 + L07. | Contrôle : doit égaler `count(*)` de la cohorte. Une différence est une anomalie bloquante pour les tests, pas un chiffre à afficher. | ACT |

### 3.2 Durées

| ID | Libellé | Unité | Source et formule | Inclus / exclus |
| --- | --- | --- | --- | --- |
| H01 | Heures programmées | minutes (affichage h min) | `sum(planned_end − planned_start)` des leçons de la période au statut planifiée ou `COMPLETED` (L01, L02, L05, L06, L07). | Durée **prévue** seulement, jamais mélangée à H02. Exclut annulées et absences. |
| H02 | Heures réalisées (durées connues) | secondes → minutes | `sum(actual_end − actual_start)` des L01 dont `actual_start` et `actual_end` sont non nuls. Fournit aussi `knownCount` et `unknownDurationCount` (L01 sans les deux). | Une durée réelle manquante n'est **ni 0 ni la durée prévue** : la leçon sort de la somme, est comptée dans `unknownDurationCount`, et la mesure passe `PARTIAL`. Le temps complet appartient au jour de début. La durée contractuelle et la durée GPS ne sont jamais utilisées. |
| H03 | Heures à venir | minutes | `sum(planned_end − planned_start)` des L02. | Durée prévue d'engagements confirmés, pas des heures données. |

Les trois restent des grandeurs séparées : aucun total « H01 + H02 ».

### 3.3 Personnes

| ID | Libellé | Unité | Source et formule | Inclus / exclus |
| --- | --- | --- | --- | --- |
| P01 | Élèves ayant eu une activité | élèves | `count(DISTINCT learner_id)` sur l'**union** de (a) `lesson.learner_id` des L01 et (b) `course_enrollment.learner_id` des présences `PRESENT` aux séances de la période. Expose aussi P01a (leçons seules) et P01b (cours seuls). | Distinct par élève sur toute la période (un élève sur deux permis ou deux sources compte une fois). Inclut les élèves archivés depuis. Exclut les élèves seulement inscrits, planifiés, absents ou excusés. Ce n'est pas le nombre de membres actifs. Par intervalle d'une série, recalculé (K13). |

### 3.4 Répartitions

Une répartition partitionne la même cohorte que l'indicateur réparti : la somme des groupes est égale au total (contrôle de test). Une valeur de regroupement non résoluble tombe dans le groupe `UNRESOLVED`, jamais dans un autre.

| ID | Libellé | Clé de regroupement | Source |
| --- | --- | --- | --- |
| R01 | Par moniteur | `instructor_membership_id` | `lesson` (une valeur par leçon). Cours : moniteur de la **séance** (`course_occurrence.instructor_membership_id`), mesures C01, C03, C04, C05 seulement. Libellé : nom résolu par la fonction `course_staff_name` existante. |
| R02 | Par permis | `category_code` | `lesson.training_id → training.offering_id → offering_version.category_code`. Le produit choisi porte le même code (contrôlé à la réservation). Cours : non applicable. |
| R03 | Par prestation | `product_key` | `commercial_selection->>'serviceProductVersionId' → service_product_version.product_key` ; libellé = celui de la version utilisée par la leçon (le plus récent si plusieurs dans le groupe). Cours : non applicable. |

Répartition applicable à L01 à L07, H01 à H03, F01 à F04. Pas de classement ni de comparaison de moniteurs entre eux (décision de conception R94).

### 3.5 Cours collectifs

Séances (`course_occurrence`) et séries (`course_series`) sont deux unités distinctes et ne se multiplient jamais : aucune valeur, aucun compteur de « cours vendus » n'est calculé comme `séries × séances`. Une série compte si elle est `PUBLISHED` ou `CLOSED` ; `DRAFT` est ignorée et `CANCELLED` est comptée à part (indicateur C11 ci-dessous).

| ID | Libellé | Unité | Source et formule | Inclus / exclus | Pér. | Droit |
| --- | --- | --- | --- | --- | --- | --- |
| C01 | Séances de cours | séances | `count(*)` des `course_occurrence` des séries `PUBLISHED`/`CLOSED`. | Exclut séries brouillon et annulées. | `starts_at` | ACT |
| C02 | Cours concernés | séries | `count(DISTINCT series_id)` des occurrences de C01. | Une série de 3 séances compte pour 1. | `starts_at` | ACT |
| C03 | Séances avec appel renseigné | séances | Occurrences de C01 ayant au moins une ligne `course_attendance`. | Une séance passée sans aucune ligne n'est **pas** présumée tenue : elle est dans C04. | `starts_at` | ACT |
| C04 | Appels à renseigner | séances (et marques) | Occurrences de C01 avec `starts_at <= computedAt` et au moins une inscription attendue sans ligne `course_attendance`. Inscription attendue = `ACTIVE`, ou annulée après `starts_at`. Expose `missingMarks` (nombre de lignes manquantes). | Hors période : instantané sans borne basse (alimente « À traiter », A02). Une séance future n'a jamais d'appel manquant. | `starts_at` | ACT |
| C05 | Présences, absences, excusés | marques | `count(*)` de `course_attendance` par `status` pour les occurrences de C01 (séance rattachée à `starts_at`, non à `recorded_at`). | Une marque absente reste « non renseigné », jamais « absent ». | `starts_at` | ACT |
| C06 | Inscriptions actives | inscriptions | `count(*)` des `course_enrollment` `ACTIVE` des séries `PUBLISHED`. Instantané à `computedAt`. | Une inscription compte **une fois par série**, pas par séance. Exclut annulées (y compris `SERIES_CANCELLED`). | instantané | ACT |
| C07 | Places retenues | places | `count(*)` des `course_seat_offer` `ACTIVE` avec `expires_at > computedAt`. Instantané. | Retenue temporaire pour une personne en file ; ce n'est pas une inscription. Une proposition échue ne compte plus. | instantané | ACT |
| C08 | Places | places | Capacité = `course_series.capacity` ; occupées = C06 + C07 (identique à `course_seats_taken`) ; libres = `max(0, capacité − occupées)` avec `overbooked` si occupées > capacité. | Séries `PUBLISHED`. Une capacité abaissée sous les inscriptions donne `overbooked`, pas un nombre négatif. | instantané | ACT |
| C09 | Remplissage des cours à venir | % | `sum(occupées) / sum(capacité)` (somme des places, **pas** moyenne de pourcentages) sur les séries `PUBLISHED` dont la première séance est après `computedAt` et dans la période demandée. | `null` si le dénominateur est 0 ou si une capacité est invalide. Indisponible (`SNAPSHOT_ONLY`) pour une période entièrement passée : aucun historique de places n'est stocké. | instantané | ACT |
| C10 | Mouvements d'inscription | inscriptions | Créées : `created_at` dans la période. Annulées : `cancelled_at` dans la période, ventilées par `cancel_kind` (`SELF`, `STAFF`, `SERIES_CANCELLED`). | Flux datés par des colonnes réelles, donc valables pour le passé. Une annulation de série est une annulation de masse : elle est distinguée. | `created_at`, `cancelled_at` | ACT |
| C11 | Cours annulés | séries | `count(*)` des séries `CANCELLED` dont `cancelled_at` est dans la période, et leurs séances (écartées de C01). | Séries brouillon ignorées. | `cancelled_at` | ACT |

### 3.6 À traiter (accueil)

Aucun faux événement : uniquement des états démontrés par le serveur. Instantané à `computedAt`, sans borne de période (un retard ancien reste à traiter).

| ID | Libellé | Unité | Formule |
| --- | --- | --- | --- |
| A01 | Leçons à finaliser | leçons | L07 sans borne de période. |
| A02 | Appels à renseigner | séances | C04 sans borne de période. |
| A03 | Leçons à vérifier | leçons | L05 sans borne de période. |

Aucune « demande » d'élève n'est exposée (Q18). Aucun bilan « à publier » (Q18).

### 3.7 Valeurs financières

Toutes en centimes CHF (K7, K8). Aucune ne contient de TVA, de marge, de coût, de solde bancaire ou de « reste à payer ».

| ID | Libellé affiché | Formule et statuts | Inclus / exclus | Pér. | Droit |
| --- | --- | --- | --- | --- | --- |
| F01 | Valeur des leçons réalisées | `sum(price_cents_snapshot)` des L01 dont `commercial_selection.mode = 'UNIT_PRICE'`, et dont la somme des `charge_entry` du compte égale le snapshot. | Prix **convenus à la réservation** (jamais le tarif courant), pas une preuve d'encaissement. Exclut les leçons au mode `ENTITLEMENT` (comptées dans `entitlementLessons`, F8) et celles dont le compte est incohérent (`CHARGE_MISMATCH`) : la mesure passe `PARTIAL` avec le nombre exclu. Un prix de 0 est une valeur connue. | `eventAt` de L01 | FIN |
| F02 | Valeur des leçons à venir | `sum(price_cents_snapshot)` des L02 en mode `UNIT_PRICE`. | Réservations confirmées futures. Prix éventuellement révisable avant la leçon (`lesson_commercial_revision`) : c'est le dernier prix convenu. | `planned_start` | FIN |
| F03 | Total attendu selon le planning | F01 + F02 sur le même périmètre, les mêmes filtres, le même `computedAt`. | Deux catégories **disjointes** (une leçon est soit réalisée, soit à venir). Ce n'est ni un revenu garanti ni une prévision : libellé « selon le planning ». Ne contient **jamais** F05. | idem | FIN |
| F04 | Valeur en attente de constat | `sum(price_cents_snapshot)` des L05, L06 et L07 en mode `UNIT_PRICE`. | Hors de F03. Affichée à part pour ne pas faire croire qu'une leçon commencée non finalisée est réalisée ni qu'une leçon dont l'heure est passée est une réservation certaine. | `planned_start` | FIN |
| F05 | Règlements de cours enregistrés | `sum(amount_cents)` des `course_payment_record` avec `voided_at IS NULL`, rattachés à `recorded_at` converti en date civile de l'école. Expose `entries` (nombre de saisies actives). | Périmètre : **règlements de cours collectifs saisis sur place** (Q10) ; le libellé le dit. Date de **saisie**, jamais « date bancaire ». Paiements en plusieurs fois : chaque saisie compte. Les saisies à 0 comptent comme saisies, pas comme montant. Une inscription annulée ne retire pas ses règlements. Ce n'est pas un rapprochement bancaire. | `recorded_at` | FIN |
| F06 | Saisies annulées et corrections | (a) saisies dont `voided_at` est non nul rattachées à `recorded_at` : nombre et montant ; (b) corrections postérieures : saisies annulées dans la période mais saisies avant elle (nombre et montant). | Annuler une saisie n'est **pas** un remboursement ; la ligne reste visible. Sert à expliquer pourquoi le total d'une période passée a baissé. Pas de remboursement dans le modèle : aucun montant négatif. | `recorded_at`, `voided_at` | FIN |
| F07 | Valeur des cours collectifs | Indisponible : `null`, `COURSE_PRICE_SOURCE_MISSING`. | Ni reconstituée à partir des règlements, ni à partir du tarif courant, ni `prix de série × séances`. Le titre et la couverture de F03 disent que seules les leçons individuelles sont couvertes. | n/a | FIN |

Règles de non-confusion, vérifiables par test : aucun champ de réponse ne contient `F03 + F05` ; F05 n'est jamais filtrable par moniteur, permis ou prestation (un règlement dépend d'une inscription, pas d'une leçon) : ces filtres rendent F05 et F06 `NOT_APPLICABLE` ; F05 peut se répartir par type de cours (`course_type`) et par série.

## 4. Calculable maintenant, source à compléter, hors V1

| Statut | Indicateurs | Pourquoi, ou ce qui manque |
| --- | --- | --- |
| **Calculable maintenant** | L01 à L08, H01, H03, P01, R01 à R03 (leçons), C01, C02, C03, C05, C06, C07, C08, C10, C11, A01, A02, A03 | Colonnes réelles (section 2). Aucune migration de données ni de saisie nouvelle. |
| **Calculable maintenant, couverture limitée à afficher** | H02 · C04 · C09 · F01 à F04 · F05, F06 | H02 : durée réelle absente = mesure partielle, jamais 0 ni durée prévue. C04 : instantané sans borne basse. C09 : instantané, indisponible pour une période passée (aucun historique de places). F01 à F04 : leçons individuelles au mode `UNIT_PRICE` seulement (ni packs, ni cours) ; compte incohérent exclu et compté. F05, F06 : règlements de **cours** saisis sur place, par date de **saisie** ; ne couvrent pas l'encaissement des leçons. |
| **Source à compléter** | F07 valeur des cours collectifs | `course_series` n'a ni prix ni lien produit, `course_enrollment` ne fige aucun prix (Q9). Il faudrait une base contractuelle (référence de la série vers une version de prestation `COLLECTIVE_COURSE` et prix figé), à cadrer et approuver séparément avant toute écriture. Rien n'est reconstitué depuis les règlements ni depuis le tarif courant. |
| | Règlements de leçons individuelles | Aucune table de paiement de leçon (`payments: []`, Q7). |
| | Reste à payer, impayés, solde par élève | Aucun lien contractuel fiable entre prestation et règlement : un règlement de cours est un montant libre rattaché à une inscription, pas à un prix. |
| | Valeur des leçons en pack (`ENTITLEMENT`) | Mode refusé aujourd'hui, registre de consommation absent (Q8). |
| | Date de règlement effective ou bancaire | Seule la date de saisie existe (Q10). |
| | Remplissage historique des cours | Places = instantané ; pas d'historique des retenues. Les mouvements d'inscription (C10) sont, eux, datés par des colonnes réelles. |
| | Date d'annulation ou d'absence d'une leçon | Aucune colonne (Q3). Le rattachement se fait à la date prévue. |
| | Devise autre que CHF | Aucune colonne de devise (K8). |
| **Hors V1** | Taux d'occupation du planning | Le dénominateur (`availability_rule`) est modifié en place sans historique (Q12) : un taux passé serait inventé. Pourrait revenir pour le futur seulement, ou avec un journal des disponibilités. |
| | Bénéfice, marge nette, coût d'un moniteur, solde bancaire, TVA, HT/TTC, conformité comptable | Aucune base ; aucune n'est affirmée. |
| | Frais d'annulation ou d'absence automatiques | Les règles structurées (`cancellationHours`, `lateAction` valant `CONTACT` ou `NO_FEE`) décrivent un délai, jamais un montant. Aucun frais n'est déduit d'un texte libre. |
| | Remboursements | Absents du modèle ; annuler une saisie n'en est pas un. |
| | Paiement en ligne, packs (#45), simulateur financier, extrapolation de créneaux libres, suivi d'examens | Exclus de #373 sans décision distincte. |
| | Classement ou comparaison de moniteurs, score de conduite, taux de réussite | Exclus par la conception (R94). |
| | Bilans à publier, demandes d'élèves | Obsolète depuis le partage automatique, ou non démontré (Q18). |

**Inconnues bloquantes.** Aucune ne bloque la V1 telle que décrite dans #373 : les finances s'affichent avec le titre et la couverture « leçons individuelles » et les règlements de cours à part. Elles bloquent seulement, tant qu'une décision distincte n'est pas prise : le chiffre d'affaires des cours (F07), tout « reste à payer » et la valeur des packs. Aucune donnée n'est inventée pour les contourner et aucun logiciel comptable n'est exigé.

## 5. Matrice des droits

**Aucune nouvelle permission.** Les trois grants nécessaires existent déjà dans le schéma et dans l'écran d'accès du web : `VIEW_SCHOOL_METRICS` (« Consulter les indicateurs de l'école »), `VIEW_FINANCIAL_METRICS` (« Consulter les indicateurs financiers »), `EXPORT_MANAGEMENT` (« Exporter les données de gestion ») (Q13). Seul un ADMIN les attribue (`PATCH members`, réauthentification, audit). Ils ne sont accordés à personne par défaut, y compris à l'ADMIN créateur de l'école, et rien ne s'ajoute aux rôles web. Les droits existants des fiches (`MANAGE_COURSES`, `cash_record`, RLS des leçons) ne sont ni élargis ni remplacés par une page de statistiques.

Périmètres : `école` = toute l'école ; `soi` = les leçons dont le moniteur est la personne connectée, et les séances de cours qu'elle anime, résolu côté serveur depuis la session (jamais depuis un paramètre).

| Capacité | ADMIN (sans grant) | ADMIN + `EXPORT_MANAGEMENT` | Moniteur (sans grant) | Moniteur + `VIEW_SCHOOL_METRICS` | Moniteur + `VIEW_FINANCIAL_METRICS` | Moniteur + `EXPORT_MANAGEMENT` | Élève |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Activité de l'école (L, H, P, R, C, A) | Oui, école | Oui, école | Non | Oui, école | Non | Non | Non |
| Sa propre activité | Oui s'il est aussi moniteur (sinon sans objet) | idem | Oui, `soi` | Oui | Oui, `soi` | Oui, `soi` | Non |
| Valeurs des leçons (F01 à F04) | Oui, école | Oui, école | Non | Non | Oui, école | Non | Non |
| Règlements de cours : totaux, corrections (F05, F06) | Oui, école | Oui, école | Non | Non | Oui, école | Non | Non |
| Filtre ou répartition par moniteur sur les valeurs | Oui | Oui | Non | Non | Oui | Non | Non |
| Détail d'une mesure d'activité (lignes) | Oui, noms d'élèves compris | Oui | Ses leçons | École entière ; nom d'élève seulement là où la lecture est déjà permise | Ses leçons | Ses leçons | Non |
| Détail d'une mesure financière (lignes avec montant) | Oui | Oui | Non | Non | Oui, nom d'élève seulement là où la lecture est déjà permise | Non | Non |
| Ouvrir la fiche liée à une ligne (leçon, cours, règlement) | Droits propres de chaque fiche, inchangés : le droit d'agrégat ne les remplace pas | idem | idem | idem | idem | idem | Non |
| Export CSV d'activité | Non (grant requis) | Oui, école | Non | Non | Non | Oui, `soi` | Non |
| Export CSV de finances | Non | Oui, école | Non | Non | Non (sans le grant d'export) | Non | Non |

Un moniteur qui cumule `VIEW_FINANCIAL_METRICS` et `EXPORT_MANAGEMENT` exporte les finances de l'école ; qui cumule `VIEW_SCHOOL_METRICS` et `EXPORT_MANAGEMENT`, l'activité de l'école. Un ADMIN qui est aussi moniteur garde le périmètre `école` par défaut. Un élève, un non-membre, un membre d'une autre école ou une appartenance révoquée n'obtiennent rien (403 générique, sans confirmer l'existence de l'école).

Règles serveur, toutes vérifiées par test (T02, T07) :

1. **Avant tout résultat.** Authentification, rattachement à l'école, rôle et grants sont relus sur `membership` à chaque requête (`withActor`), avant toute requête de mesure. Un montant, un sous-total, une comparaison, un lien de détail ou un message d'erreur n'est jamais produit pour une personne sans le droit financier. Un onglet masqué n'est pas une permission.
2. **Omission, pas zéro.** Une mesure interdite est absente de la réponse (clé absente), jamais renvoyée à 0, ni `null`, ni `NOT_APPLICABLE`.
3. **Périmètre explicite.** Sans `VIEW_SCHOOL_METRICS` ni ADMIN, la portée est `soi` ; demander `école` ou le moniteur d'une autre personne donne `403 METRIC_SCOPE_FORBIDDEN`, sans bascule silencieuse. Une vue limitée à un moniteur ne reçoit aucun montant, ni dans une comparaison, ni dans une série, ni dans un export, ni dans un message d'erreur.
4. **Le filtre ne contourne pas le droit.** Filtrer par moniteur ne donne accès aux valeurs qu'à qui détient le droit financier. Les filtres sur les règlements de cours (moniteur, permis, prestation) sont refusés (`METRIC_FILTER_UNSUPPORTED`), parce qu'un règlement dépend d'une inscription, pas d'une leçon.
5. **Un agrégat ne ferme pas les fiches.** Les lignes de détail portent des identifiants ; les noms d'élèves passent par les fonctions de lecture existantes (`lesson_learner_name` et équivalents), qui renvoient vide hors droit. Ouvrir une fiche exige le droit propre de la fiche. Le détail d'un règlement (inscrit, note, motif d'annulation) exige `course_can_record_payment`, que `VIEW_FINANCIAL_METRICS` seul ne donne pas.
6. **Révocation.** Retirer un grant (`access_epoch` augmente) coupe l'accès à la requête suivante. Détail et export relisent le droit à la génération ; un grant retiré entre l'affichage et l'export donne `403 ACCESS_REVOKED`, sans fichier partiel.
7. **Caches.** `Cache-Control: no-store` déjà global ; côté web, mémoire seulement, clé = personne + école + époque d'accès, aucun stockage persistant de données scolaires ; un changement de personne ou d'école purge (mécanisme #106/#107). Aucun cache serveur partagé entre comptes ou écoles.
8. **École non active.** `ACTIVE` et `ARCHIVED` sont consultables selon les droits ; `DRAFT` donne `409 SCHOOL_NOT_ACTIVE` (rien à compter, la préparation reste sur sa propre page).
9. **Télémétrie.** Aucun nom, contenu ni montant personnel dans les logs ou la télémétrie ; seuls l'identifiant de requête, le type de mesure, le nombre de lignes et la durée.

## 6. Jeu synthétique de référence

Toutes les données sont fictives : des codes (`M1`, `E1`, `S1`), aucune personne. Tous les totaux ci-dessous se recalculent à la main ; ils ont aussi été recalculés par un script indépendant, avec des conversions de fuseau vérifiées sur `Europe/Zurich`.

### 6.1 Contexte

- **École A** : fuseau `Europe/Zurich`, `ACTIVE`. Heure d'été jusqu'au dimanche 25 octobre 2026 à 03:00 local (01:00 UTC), puis heure d'hiver : le jour du 25 octobre dure 25 h, la semaine du lundi 19 au dimanche 25 octobre commence le 18/10 à 22:00 UTC et finit le 25/10 à 23:00 UTC (**169 h**), octobre dure **745 h**, septembre 720 h.
- **Instant de calcul** `computedAt` = **2026-10-28T17:00:00Z** (18:00 local, mercredi 28 octobre).
- **Catalogue** : prestation `b-45` (permis B, 45 min) version 1 à 9 000 centimes, version 2 à 10 000 centimes créée le 2026-09-30T12:00:00Z ; prestation `a-60` (permis A, 60 min) à 11 000 centimes, une seule version. Une leçon porte le prix figé à sa réservation : S1, S2 (2 × 9 000), S4, S6, O2 et O3 (2 × 9 000, voir plus bas) ont été réservées avant la version 2 ; les autres leçons `b-45` ont été réservées après et valent 10 000. Les tests de T02 insèrent directement les lignes `lesson` avec ces valeurs ; la formation du snapshot par la route de réservation est déjà testée ailleurs.
- `created_at` d'une leçon = 7 jours avant son début prévu, sauf trois exceptions : O1 (2026-09-30T12:30:00Z, réservée le jour même, après la version 2), O2 (2026-09-25T10:00:00Z) et O3 (2026-09-28T10:00:00Z). Plus ancienne création : S1, 2026-09-01T08:00:00Z, donc `dataSince` = **2026-09-01**.
- **Acteurs** : `ADM1` (ADMIN, sans grant), `ADM2` (ADMIN + `EXPORT_MANAGEMENT`), `M1` (moniteur, sans grant), `M2` (moniteur + `VIEW_SCHOOL_METRICS`), `M3` (moniteur + `VIEW_FINANCIAL_METRICS`), `M4` (moniteur + `EXPORT_MANAGEMENT`, aucune leçon dans le jeu), `L1` (élève).
- Toutes les leçons sont de quantité 1 de la prestation, sauf S2 et O3 (quantité 2, soit 90 min).

### 6.2 Leçons de l'école A (23)

Heures locales : CEST (+02:00) jusqu'au 25/10 à 01:00Z, CET (+01:00) ensuite.

| Leçon | Mon. | Élève | Prestation × qté | Statut | Prévu (UTC) | Prévu (local) | Réel (UTC) | Prix (centimes) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | M1 | E1 | b-45 × 1 | COMPLETED | 08/09 08:00Z → 08:45Z | 08/09 10:00 → 10:45 | 08/09 08:02Z → 08:49Z | 9000 |
| S2 | M1 | E2 | b-45 × 2 | COMPLETED | 15/09 12:00Z → 13:30Z | 15/09 14:00 → 15:30 | 15/09 12:00Z → 13:30Z | 18000 |
| S3 | M2 | E3 | a-60 × 1 | COMPLETED | 22/09 07:00Z → 08:00Z | 22/09 09:00 → 10:00 | 22/09 07:05Z → 08:03Z | 11000 |
| S4 | M1 | E1 | b-45 × 1 | CANCELLED | 24/09 08:00Z → 08:45Z | 24/09 10:00 → 10:45 | aucun | 9000 |
| S5 | M2 | E4 | a-60 × 1 | NO_SHOW | 25/09 13:00Z → 14:00Z | 25/09 15:00 → 16:00 | aucun | 11000 |
| S6 | M1 | E2 | b-45 × 1 | COMPLETED | 29/09 09:00Z → 09:45Z | 29/09 11:00 → 11:45 | 29/09 09:00Z → 09:45Z | 9000 |
| S7 | M2 | E3 | a-60 × 1 | COMPLETED | 30/09 21:30Z → 22:30Z | 30/09 23:30 → 00:30 | 30/09 21:30Z → 22:30Z | 11000 |
| O1 | M1 | E5 | b-45 × 1 | COMPLETED | 30/09 22:30Z → 23:15Z | 01/10 00:30 → 01:15 | 30/09 22:30Z → 23:15Z | 10000 |
| O2 | M1 | E1 | b-45 × 1 | COMPLETED | 06/10 08:00Z → 08:45Z | 06/10 10:00 → 10:45 | 06/10 08:00Z → 08:40Z | 9000 |
| O3 | M1 | E2 | b-45 × 2 | COMPLETED | 13/10 12:00Z → 13:30Z | 13/10 14:00 → 15:30 | 13/10 12:03Z → 13:31Z | 17000 |
| O5 | M2 | E4 | a-60 × 1 | COMPLETED | 15/10 07:00Z → 08:00Z | 15/10 09:00 → 10:00 | aucun | 11000 |
| O6 | M2 | E3 | a-60 × 1 | CANCELLED | 07/10 08:00Z → 09:00Z | 07/10 10:00 → 11:00 | aucun | 11000 |
| X1 | M1 | E2 | b-45 × 1 | CANCELLED | 16/10 08:00Z → 08:45Z | 16/10 10:00 → 10:45 | aucun | 10000 |
| X2 | M2 | E4 | a-60 × 1 | NO_SHOW | 21/10 13:00Z → 14:00Z | 21/10 15:00 → 16:00 | aucun | 11000 |
| X3 | M1 | E5 | b-45 × 1 | CANCELLED | 23/10 08:00Z → 08:45Z | 23/10 10:00 → 10:45 | aucun | 10000 |
| V1 | M2 | E4 | a-60 × 1 | PLANNED | 20/10 07:00Z → 08:00Z | 20/10 09:00 → 10:00 | aucun | 11000 |
| V2 | M1 | E5 | b-45 × 1 | PLANNED | 22/10 08:00Z → 08:45Z | 22/10 10:00 → 10:45 | départ 22/10 08:00Z, pas de fin | 10000 |
| V3 | M1 | E1 | b-45 × 1 | PLANNED | 28/10 16:30Z → 17:15Z | 28/10 17:30 → 18:15 | départ 28/10 16:30Z, pas de fin | 10000 |
| D1 | M1 | E1 | b-45 × 1 | COMPLETED | 25/10 22:30Z → 23:15Z | 25/10 23:30 → 00:15 | 25/10 22:30Z → 23:15Z | 10000 |
| U1 | M1 | E1 | b-45 × 1 | PLANNED | 29/10 09:00Z → 09:45Z | 29/10 10:00 → 10:45 | aucun | 10000 |
| U2 | M2 | E3 | a-60 × 1 | PLANNED | 30/10 13:00Z → 14:00Z | 30/10 14:00 → 15:00 | aucun | 11000 |
| U3 | M1 | E2 | b-45 × 1 | PLANNED | 31/10 22:30Z → 23:15Z | 31/10 23:30 → 00:15 | aucun | 10000 |
| N1 | M1 | E5 | b-45 × 1 | PLANNED | 31/10 23:30Z → 00:15Z | 01/11 00:30 → 01:15 | aucun | 10000 |

Particularités voulues :

- **S7 / O1 (changement de mois).** S7 débute le 30/09 à 23:30 local : septembre. O1 débute le 01/10 à 00:30 local, mais le 30/09 à 22:30 en UTC : octobre. Un découpage en UTC déplace O1 en septembre.
- **D1 (fuseau, heure d'hiver).** Débute le 25/10 à 23:30 local (22:30Z), après le changement d'heure : semaine du 19 au 25 octobre, jour du 25. Une semaine calculée comme `7 × 24 h` depuis le lundi 19 à 00:00 local finirait le 25/10 à 22:00Z et la placerait dans la semaine suivante.
- **U3 / N1.** U3 débute le 31/10 à 23:30 local (octobre) ; N1 le 01/11 à 00:30 local (novembre). Les deux traversent ou touchent minuit.
- **S2, O3 (multi-unités, prix révisé).** Quantité 2, comptées pour **1** leçon. O3 a été réservée 18 000 (2 × 9 000) puis révisée par l'ADMIN à **17 000** (ligne `lesson_commercial_revision` révision 2, motif) : le snapshot courant, 17 000, fait foi ; l'historique reste lisible.
- **O2 (tarif historique).** Réservée à 9 000 avant la version 2 (10 000), réalisée le 06/10 : elle vaut 9 000.
- **O6 (correction après coup).** Réalisée puis corrigée en annulée par l'ADMIN : `actual_start`/`actual_end` effacés, charge contre-passée. Elle ne vaut plus rien et se rattache à sa date prévue.
- **O5 (cas défensif).** `COMPLETED` sans début ni fin réels. Aucune route actuelle ne produit cet état, mais la contrainte de la base le permet (migration 007) et il peut venir de données plus anciennes : durée inconnue, date de rattachement repliée sur le prévu, valeur comptée.
- **V1, V2, V3.** À vérifier (heure passée, jamais démarrée), à finaliser (démarrée, fin prévue passée), en cours (démarrée, fin prévue 17:15Z, après 17:00Z).

### 6.3 Cours collectifs et règlements (école A)

Séries :

| Série | Type | Statut | Capacité | Séances (UTC → local) |
| --- | --- | --- | --- | --- |
| CS1 | FIRST_AID | PUBLISHED | 8 | 12/10 17:00Z–19:00Z (19:00–21:00) ; 13/10 17:00Z–19:00Z (19:00–21:00) |
| CS2 | AWARENESS | PUBLISHED | 12 | 10/11 18:00Z–20:00Z (19:00–21:00) |
| CS3 | FIRST_AID | PUBLISHED | 8 | 20/11 18:00Z–20:00Z (19:00–21:00) |
| CS4 | FIRST_AID | CANCELLED (le 02/10 à 09:00Z) | 8 | 20/10 18:00Z–20:00Z |

Aucune série n'a de prix. Les séries sont créées après le 01/09/2026 : elles ne changent pas `dataSince`.

Inscriptions (`created_at` en UTC) :

| Inscr. | Élève | Série | État | Créée | Annulée |
| --- | --- | --- | --- | --- | --- |
| I1 | E1 | CS1 | ACTIVE | 02/10 08:00Z | |
| I2 | E2 | CS1 | ACTIVE | 02/10 08:05Z | |
| I3 | E3 | CS1 | CANCELLED (`SELF`) | 03/10 08:00Z | 10/10 08:00Z |
| I4 | E4 | CS1 | ACTIVE | 04/10 08:00Z | |
| I5 | E1 | CS2 | ACTIVE | 15/09 08:00Z (septembre) | |
| I6 | E2 | CS2 | ACTIVE | 20/10 08:00Z | |
| I7 à I12 | E1 à E6 | CS3 | ACTIVE | 21/10 08:00Z | |
| I13 | E6 | CS4 | CANCELLED (`SERIES_CANCELLED`) | 01/10 08:00Z | 02/10 09:00Z |

Une proposition de place `ACTIVE` pour E5 sur CS2, échéance 29/10 12:00Z (après l'instant de calcul).

Présences : séance 1 de CS1 (12/10) : I1 `PRESENT`, I2 `PRESENT`, I4 `ABSENT`. Séance 2 de CS1 (13/10) : I1 `PRESENT` ; I2 et I4 **non renseignés**. Aucune autre ligne.

Règlements de cours (`course_payment_record`, centimes) :

| Règl. | Inscr. | Montant | Saisi (UTC) | Annulé (UTC) | Particularité |
| --- | --- | --- | --- | --- | --- |
| P1 | I1 | 12 000 | 12/10 09:00Z | | |
| P2 | I2 | 6 000 | 12/10 09:05Z | | paiement en deux fois |
| P3 | I2 | 6 000 | 20/10 09:00Z | | seconde échéance |
| P4 | I4 | 12 000 | 12/10 09:10Z | 13/10 08:00Z | saisie erronée annulée |
| P5 | I4 | 12 000 | 13/10 08:05Z | | ressaisie |
| P6 | I3 | 12 000 | 05/10 09:00Z | | inscription annulée ensuite : le règlement reste |
| P7 | I5 | 3 000 | 30/09 21:30Z (23:30 local) | | septembre |
| P8 | I5 | 3 000 | 30/09 22:30Z (01/10 à 00:30 local) | | octobre |
| P9 | I1 | 0 | 14/10 09:00Z | | saisie à zéro |
| P10 | I5 | 12 000 | 20/09 09:00Z | 09/10 09:00Z | saisie de septembre annulée en octobre |

### 6.4 Résultats attendus (école A, `computedAt` = 2026-10-28T17:00:00Z)

**Leçons et durées.** Les bornes sont des dates civiles locales ; `à date` = jusqu'au 28 inclus.

| Période | L01 | L02 | L03 | L04 | L05 | L06 | L07 | L08 | H01 (min) | H02 (min) | H03 (min) | P01 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Août [01/08, 01/09) | null (`BEFORE_DATA_START`) | | | | | | | | | | | |
| Septembre [01/09, 01/10) | 5 | 0 | 1 | 1 | 0 | 0 | 0 | 7 | 300 | 300 (5 connues, 0 inconnue) | 0 | 3 (E1, E2, E3) |
| Octobre [01/10, 01/11) | 5 | 3 | 3 | 1 | 1 | 1 | 1 | 15 | 585 | 218 (4 connues, 1 inconnue) | 150 | 4 (E1, E2, E4, E5) |
| Octobre à date [01/10, 29/10) | 5 | 0 | 3 | 1 | 1 | 1 | 1 | 12 | 435 | 218 (4, 1) | 0 | 4 |
| Septembre à date [01/09, 29/09) | 3 | 0 | 1 | 1 | 0 | 0 | 0 | 5 | 195 | 195 (3, 0) | 0 | 3 |
| Novembre [01/11, 01/12) | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 45 | 0 (aucune leçon réalisée) | 45 | 0 |
| Semaine du 19/10 (169 h) | 1 | 0 | 1 | 1 | 1 | 0 | 1 | 5 | 150 | 45 (1, 0) | 0 | 1 (E1) |
| Jour 28/10 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 45 | 0 (aucune leçon réalisée) | 0 | 0 |

Octobre : L01 = O1, O2, O3, O5, D1. L02 = U1, U2, U3. L03 = O6, X1, X3. L04 = X2. L05 = V1. L06 = V3. L07 = V2. H01 = durées **prévues** : O1 45 + O2 45 + O3 90 + O5 60 + D1 45 + V1 60 + V2 45 + V3 45 + U1 45 + U2 60 + U3 45 = 585 (dont H03 = U1 + U2 + U3 = 150). H02 = O1 45 + O2 40 + O3 88 + D1 45 = 218 min, O5 non connue. Septembre : H02 = 47 + 90 + 58 + 45 + 60 = 300.

**Répartitions d'octobre.**

| Groupe | L01 | L02 | L03 | L04 | L05 | L06 | L07 | H02 (min) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Moniteur M1 | 4 | 2 | 2 | 0 | 0 | 1 | 1 | 218 (4 connues, 0 inconnue) |
| Moniteur M2 | 1 | 1 | 1 | 1 | 1 | 0 | 0 | null (0 connue, 1 inconnue : tout exclu) |
| Permis B | 4 | 2 | 2 | 0 | 0 | 1 | 1 | 218 |
| Permis A | 1 | 1 | 1 | 1 | 1 | 0 | 0 | null |
| Prestation `b-45` | 4 | 2 | 2 | 0 | 0 | 1 | 1 | 218 |
| Prestation `a-60` | 1 | 1 | 1 | 1 | 1 | 0 | 0 | null |

Chaque colonne de groupes se somme au total d'octobre (5, 3, 3, 1, 1, 1, 1).

**Série hebdomadaire d'octobre, leçons réalisées** (semaines du lundi ; les extrémités sont partielles) : semaine du 28/09 (partielle, 01 au 04/10) : 1 (O1) · semaine du 05/10 : 1 (O2) · semaine du 12/10 : 2 (O3, O5) · semaine du 19/10 : 1 (D1) · semaine du 26/10 (partielle, 26 au 31/10) : 0. Somme 5. Leçons à venir : 3 dans la semaine du 26/10 (U1, U2, U3). N1 appartient à novembre bien que sa semaine commence en octobre.

**Valeurs financières** (centimes) :

| Période | F01 réalisée | F02 à venir | F03 total attendu | F04 en attente de constat | F05 règlements de cours | F06 (a) saisies annulées | F06 (b) corrections postérieures | F07 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Août | null (`BEFORE_DATA_START`) | null | null | null | null | null | null | null |
| Septembre | 58 000 (5 leçons) | 0 | 58 000 | 0 | 3 000 (1 saisie, P7) | 1 saisie, 12 000 (P10) | 0 | null |
| Octobre | 57 000 (5 leçons) | 31 000 (3) | 88 000 | 31 000 (V1 11 000 + V2 10 000 + V3 10 000) | 51 000 (7 saisies : P1, P2, P3, P5, P6, P8, P9) | 1 saisie, 12 000 (P4) | 1 saisie, 12 000 (P10) | null |
| Octobre à date | 57 000 | 0 | 57 000 | 31 000 | 51 000 | idem | idem | null |
| Septembre à date | 38 000 (S1 9 000 + S2 18 000 + S3 11 000) | 0 | 38 000 | 0 | | | | null |
| Novembre | 0 | 10 000 (N1) | 10 000 | 0 | 0 | 0 | 0 | null |

F01 d'octobre = O1 10 000 + O2 9 000 + O3 17 000 + O5 11 000 + D1 10 000 = 57 000. F01 de septembre = 9 000 + 18 000 + 11 000 + 9 000 + 11 000 = 58 000. Le règlement saisi P6 reste compté malgré l'annulation de I3. P4 est annulé et ressaisi en P5 : un seul compte. P10, saisi en septembre et annulé en octobre, n'est plus dans le total de septembre aujourd'hui (3 000), et c'est la ligne F06 (b) d'octobre qui l'explique. P9 à zéro est une saisie qui ajoute 0.

**Comparaisons** (règle K9) :

| Cas | Courant | Base | Écart | Pourcentage |
| --- | --- | --- | --- | --- |
| Mois complet, leçons réalisées : octobre (31 j) contre septembre (30 j) | 5 | 5 | 0 | 0,0 % |
| Mois complet, F01 | 57 000 | 58 000 | −1 000 | −1,7 % |
| Mois à date (01 au 28/10) contre (01 au 28/09), leçons réalisées | 5 | 3 | +2 | +66,7 % |
| Mois à date, F01 | 57 000 | 38 000 | +19 000 | +50,0 % |
| Mois à date, H02 | 218 (1 inconnue) | 195 | non calculé | `null`, `PARTIAL_COVERAGE` |
| Septembre contre août (**mois précédent vide**) | 5 | `null` | `null` | `null`, `BASE_BEFORE_DATA_START` |
| Moniteur M2, semaine du 12/10 contre semaine du 05/10, leçons réalisées | 1 | 0 (connue : une annulation O6, aucune réalisée) | +1 | `null`, `BASE_ZERO` |

Test de la règle de tronquage sur la fonction pure : « mois à date » le 31/10/2026 contre septembre donne la base [01/09, 01/10), `daysInBase = 30`, `clipped = true`.

**Cours collectifs** (école A) :

| Mesure | Octobre (ou instantané à l'instant de calcul) |
| --- | --- |
| C01 séances | 2 (CS1, 12 et 13/10). CS4 est exclue. |
| C02 cours concernés | 1 |
| C03 séances avec appel renseigné | 2 |
| C04 appels à renseigner (instantané) | 1 séance (celle du 13/10), `missingMarks = 2` (I2 et I4 ; I3, annulée avant, n'est pas attendue) |
| C05 présences d'octobre | `PRESENT` 3 (I1 ×2, I2 ×1), `ABSENT` 1 (I4), `EXCUSED` 0 |
| C06 inscriptions actives (instantané) | 11 (CS1 : 3 · CS2 : 2 · CS3 : 6) |
| C07 places retenues | 1 (E5 sur CS2) |
| C08 places | CS1 : 3 occupées, 5 libres · CS2 : 3 occupées (2 + 1 retenue), 9 libres · CS3 : 6 occupées, 2 libres |
| C09 remplissage des cours à venir | **45 %** = (3 + 6) / (12 + 8) sur CS2 et CS3. Piège : la moyenne des pourcentages, (25 % + 75 %) / 2, donnerait 50 %. CS1 est commencée, CS4 annulée : exclues. |
| C10 mouvements d'octobre | créées 12 (I1, I2, I3, I4, I6, I7 à I12, I13), annulées 2 (`SELF` 1 : I3, `SERIES_CANCELLED` 1 : I13). Septembre : créées 1 (I5). |
| C11 cours annulés d'octobre | 1 série (CS4), 1 séance écartée |
| P01 d'octobre | 4 : leçons E1, E2, E4, E5 ; cours E1, E2 (P01b = 2) ; l'union ne double pas E1 et E2 |
| F07 | `null`, `COURSE_PRICE_SOURCE_MISSING` : jamais « 3 inscriptions × 2 séances × un prix » |

CS1 compte 2 séances et 1 série ; ses 3 inscriptions actives comptent chacune **une fois** (C06), pas une fois par séance ; chaque règlement porte sur l'inscription, pas sur la séance (P1 = 12 000 une seule fois).

**À traiter** à l'instant de calcul : A01 = 1 (V2), A02 = 1 séance (CS1, 13/10, 2 marques manquantes), A03 = 1 (V1).

**Résultats faux à faire échouer** (un test doit détecter chacun) :

| Erreur | Valeur fautive |
| --- | --- |
| Mois découpé en UTC | octobre : 4 leçons, 47 000 ; septembre : 6 leçons, 68 000 |
| Tarif courant appliqué au passé | septembre 62 000, octobre 61 000 (au lieu de 58 000 et 57 000) |
| Valeur + règlements additionnés | octobre 88 000 + 51 000 = 139 000 |
| Semaine en `7 × 24 h` | D1 hors de la semaine du 19/10 |
| Durée inconnue comptée comme 0 ou comme prévue | H02 d'octobre : 218 + 0 ou 218 + 60 min présentés comme complets |
| Pourcentage avec base nulle ou inconnue | « +100 % » ou « ∞ » pour les cas `BASE_ZERO` et `BASE_BEFORE_DATA_START` |
| Remplissage en moyenne de pourcentages | 50 % au lieu de 45 % |
| Compteurs calculés sur une page de liste | tout total calculé sur 50 ou 100 leçons |

### 6.5 Jeu B : 8 000 + 2 000 = 10 000 CHF, un règlement de 500 CHF n'y change rien

École B, même fuseau, `computedAt` = 2026-10-28T17:00:00Z, générée mécaniquement (4 moniteurs, créneaux sans chevauchement) :

- **80 leçons `COMPLETED`** à 10 000 centimes chacune (100,00 CHF), `actual_start` entre le 01/10 et le 27/10 inclus ;
- **20 leçons `PLANNED`** futures à 10 000 centimes, début entre le 29/10 et le 31/10 ;
- **1 règlement de cours** de 50 000 centimes (500,00 CHF) saisi le 15/10, sur une inscription active, sans autre règlement.

Attendus pour octobre : F01 = **800 000** (8 000,00 CHF), F02 = **200 000** (2 000,00 CHF), F03 = **1 000 000** (10 000,00 CHF), F05 = **50 000** (500,00 CHF). Aucun champ de la réponse ne vaut 1 050 000. L01 = 80, L02 = 20. Le test lit les détails par pages de 25 : 4 pages pour F01, 1 pour F02, et le total de pages égale le chiffre de la carte.

Isolation : un utilisateur membre de B seulement obtient 403 sur toute route de l'école A ; une personne membre des deux écoles reçoit, pour chaque école, ses propres totaux sans mélange.

### 6.6 Micro-cas de couverture (école C, une ligne chacun)

| Cas | Attendu |
| --- | --- |
| Une leçon `COMPLETED` en mode `ENTITLEMENT` (insérée directement, aucune route ne la produit) | L01 = 1 ; F01 = `null` (`UNAVAILABLE`), `entitlementLessons = 1` |
| Deux leçons `COMPLETED` à 10 000 dont l'une a une charge initiale de 9 000 | L01 = 2 ; F01 = 10 000, `PARTIAL`, 1 exclue (`CHARGE_MISMATCH`) |
| Une leçon `COMPLETED` à prix 0 | F01 = 0 connu, `COMPLETE` |
| École sans aucune donnée | zéros connus, `dataSince = null`, aucune comparaison |
| Une leçon dont `time_zone` diffère du fuseau courant de l'école | rattachement par le fuseau courant, `TIME_ZONE_MIXED` en couverture |
| Le grant `VIEW_FINANCIAL_METRICS` retiré entre l'affichage d'un total et son export | `403 ACCESS_REVOKED`, aucun fichier |

### 6.7 Droits, sur le jeu A (octobre)

| Acteur | Demande | Attendu |
| --- | --- | --- |
| `M1` | activité, portée par défaut | `soi` : L01 4, L02 2, L03 2, L04 0, L05 0, L06 1, L07 1, H02 218 ; aucune clé financière |
| `M1` | portée `école` ou moniteur `M2` | 403 `METRIC_SCOPE_FORBIDDEN` |
| `M2` | activité de l'école | totaux d'octobre de l'école (5, 3, 3, 1, 1, 1, 1) ; aucune clé financière |
| `M3` | finances de l'école | F01 57 000, F02 31 000, F03 88 000, F04 31 000, F05 51 000 ; aucune clé d'activité de l'école |
| `M3` | filtre moniteur `M1` sur les valeurs | F01 46 000 (O1 10 000 + O2 9 000 + O3 17 000 + D1 10 000), F02 20 000 (U1, U3) |
| `M3` | filtre moniteur sur les règlements | 400 `METRIC_FILTER_UNSUPPORTED` |
| `ADM1` | activité et finances | tout, sans export ; export : 403 |
| `ADM2` | export d'activité, export de finances | fichiers ; nombre de lignes = total de la carte |
| `M1` avec `EXPORT_MANAGEMENT` ajouté pour ce cas | export du détail d'octobre | 10 lignes, ses seules leçons (O1, O2, O3, D1, X1, X3, U1, U3, V2, V3) |
| `M4` | export d'activité d'octobre | fichier avec en-tête et métadonnées, 0 ligne : un zéro connu, pas une erreur |
| `L1` (élève) ou membre de B | n'importe quelle route de l'école A | 403 |

## 7. Contrat commun proposé (agrégat, série, détail, CSV)

**Proposition à relire : rien de ceci n'est écrit.** Ni route, ni schéma, ni modification du contrat OpenAPI canonique 3.11.0. Si elle est validée, T02 la formalise comme extension hors canon, dans un fichier `apps/api/contracts/school-metrics.json` (même pratique que `lesson-next-slot.json` ou `learner-course-facts.json`).

### 7.1 Principes

- Les noms suivent la conception v3.17 quand ils existent (`/metrics`, `/metrics/definitions`, `definitionsVersion`, codes d'erreur `METRIC_SCOPE_FORBIDDEN`, `METRIC_FILTER_UNSUPPORTED`, `PERIOD_TOO_LARGE`, `EXPORT_TOO_LARGE`, `ACCESS_REVOKED`). L'export s'en écarte volontairement (7.7).
- Enveloppe existante `{ data, requestId, serverTime }`, `Cache-Control: no-store`, query validée en mode strict (un paramètre inconnu est refusé), uuid et dates validés, aucune écriture métier : tout est en lecture seule, y compris l'export.
- Un seul moteur de calcul : agrégat, série, détail et export appellent les mêmes fonctions de cohorte avec les mêmes bornes, filtres, fuseau et instant. Aucun composant web ne recalcule un chiffre.
- Les clés de mesure sont les identifiants du dictionnaire (`L01`, `H02`, `F03`...). Leur sens est figé par `definitionsVersion`.

### 7.2 Routes

Préfixe `/v1/schools/{schoolId}`.

| Méthode et chemin | Rôle | Droit minimal |
| --- | --- | --- |
| `GET /metrics/definitions` | Version et dictionnaire (identifiant, unité, libellé, formule en clair, couverture connue) pour « Comment est-ce calculé ? ». Contenu statique, sans donnée d'école. | Être membre actif de l'école, rôle ADMIN ou INSTRUCTOR |
| `GET /metrics?domain=activity` | Cartes d'activité (L, H, P, C, A), comparaison, répartition éventuelle. | Section 5 : activité de l'école ou sa propre activité |
| `GET /metrics?domain=finance` | Cartes financières (F01 à F07), comparaison, répartition éventuelle. | ADMIN ou `VIEW_FINANCIAL_METRICS` |
| `GET /metrics/series` | Séries temporelles de 1 à 5 mesures. | Celui de chaque mesure |
| `GET /metrics/details` | Lignes qui composent une mesure, paginées. | Celui de la mesure |
| `POST /metrics/exports` | CSV de la même sélection, sur action explicite. | `EXPORT_MANAGEMENT` + droit de la mesure |

Deux domaines distincts plutôt qu'une route unique : une réponse « finances » ne contient aucune clé d'activité et inversement, ce qui rend l'omission par droit triviale à tester et à mettre en cache sans fuite.

### 7.3 Paramètres communs (query pour les GET, corps JSON pour l'export)

| Paramètre | Règle |
| --- | --- |
| `from`, `toExclusive` | Dates civiles `AAAA-MM-JJ` de l'école, `from < toExclusive`, 366 jours au plus (`PERIOD_TOO_LARGE`), date valide (`INVALID_PERIOD`). Les raccourcis « Ce mois », « Mois dernier », « Cette année » sont calculés par le client avec la date civile de l'école et envoyés comme dates ; le serveur ne les devine pas. |
| `compare` | `none` (défaut), `previous-month` ou `equivalent-period`. Le serveur déduit le mode (`FULL_MONTH`, `MONTH_TO_DATE` ou `EQUIVALENT_PERIOD`) de `from` et `toExclusive` et le renvoie. `previous-month` exige un mois complet ou un mois du 1er à aujourd'hui, sinon `INVALID_PERIOD`. |
| `scope` | `school` ou `self`. Défaut : `school` si le droit existe, sinon `self`. Un `school` non autorisé donne `403 METRIC_SCOPE_FORBIDDEN`. |
| `instructorMembershipId`, `categoryCode`, `productKey` | Filtres K11. Un filtre inapplicable à une mesure la rend `NOT_APPLICABLE` dans la réponse, jamais ignoré. Un `instructorMembershipId` autre que le sien en portée `self` donne `403`. |
| `breakdown` | Un seul parmi `instructor`, `category`, `product` (borne la taille de la réponse). Refusé pour `instructor` sur les finances sans droit financier. |
| `granularity` (séries) | `day`, `week` ou `month` ; 400 intervalles au plus. |
| `measures` (séries) | 1 à 5 identifiants. Les mesures de nature instantanée (C06 à C09, A01 à A03) et P01 additionné n'ont pas de série. |
| `measure`, `limit`, `cursor` (détail) | `limit` de 1 à 100 (50 par défaut) ; curseur signé lié à la personne, à l'école, à `accessEpoch`, à la mesure, aux bornes, aux filtres et à `definitionsVersion` (mécanisme `Cursors` existant). Option : `bucketFrom`, `bucketToExclusive` ou `groupKey` pour ouvrir une barre ou un groupe précis. |
| `expectedLineCount`, `expectedAmountCents` (détail, export) | Valeurs lues sur la carte, pour détecter un écart (7.5). Facultatifs. |

### 7.4 Forme des réponses

Agrégat (`GET /metrics?domain=...`) :

```
data: {
  definitionsVersion: "2026-10-31.1",
  schoolId, timeZone: "Europe/Zurich", currency: "CHF",
  computedAt: "2026-10-28T17:00:00.000Z",      // instant de la transaction, référence de « à venir »
  dataSince: "2026-09-01" | null,
  period: { from, toExclusive, days, fromInstant, toInstant },
  scope: { kind: "school" | "self", filters: { instructorMembershipId, categoryCode, productKey } },
  coverageNotes: {                               // ce que la page ne peut pas sur-promettre
    lessons: "INDIVIDUAL_UNIT_PRICE_ONLY",
    payments: "COURSE_ON_SITE_ENTRIES_ONLY",
    paymentDate: "ENTRY_DATE"
  },
  measures: {
    L01: { value: 5, unit: "count", coverage: { status: "COMPLETE", reasons: [] }, lineCount: 5 },
    H02: { value: 13080, unit: "seconds", knownCount: 4, unknownDurationCount: 1,
           coverage: { status: "PARTIAL", reasons: [{ code: "DURATION_UNKNOWN", count: 1 }] } },
    F01: { value: 57000, unit: "cents", coverage: { status: "COMPLETE", reasons: [] }, lineCount: 5 },
    C09: { value: 450, unit: "permille", numerator: 9, denominator: 20, coverage: { status: "COMPLETE", reasons: [] } },
    F07: { value: null, unit: "cents", coverage: { status: "UNAVAILABLE", reasons: [{ code: "COURSE_PRICE_SOURCE_MISSING" }] } }
  },
  comparison?: { mode: "MONTH_TO_DATE", base: { from, toExclusive, days, clipped },
                 measures: { L01: { current: 5, base: 3, delta: 2, percentTenths: 667, percentReason: null } } },
  breakdown?: { by: "instructor", groups: [{ key, label, measures: { ... } }], unresolved: { ... } }
}
```

Les valeurs de l'exemple sont celles du jeu A (octobre, section 6). Le contrat n'impose que la forme.

Règles de forme :

- `value` est un entier ou `null`. Jamais de flottant : pourcentage d'écart en dixièmes de pour cent (`percentTenths: 667` s'affiche « +66,7 % »), remplissage en pour mille (`450` s'affiche « 45 % »).
- `coverage.status` : `COMPLETE` (toutes les lignes admissibles sont comptées), `PARTIAL` (une partie exclue, avec ses raisons et leur nombre), `UNAVAILABLE` (`value: null`), `NOT_APPLICABLE` (filtre incompatible). Une mesure sans droit est **absente**.
- Codes de raison : `DURATION_UNKNOWN`, `ACTUAL_START_MISSING`, `ENTITLEMENT_NOT_VALUED`, `CHARGE_MISMATCH`, `COURSE_PRICE_SOURCE_MISSING`, `BEFORE_DATA_START`, `STARTS_BEFORE_DATA_START`, `SNAPSHOT_ONLY`, `TIME_ZONE_MIXED`.
- `percentReason` quand `percentTenths` est nul : `BASE_ZERO`, `BASE_BEFORE_DATA_START`, `PARTIAL_COVERAGE`.
- `lineCount` d'une mesure financière est le nombre de lignes de son détail, pas un indicateur d'activité (D3).

Série (`GET /metrics/series`) : mêmes en-têtes que l'agrégat, plus `granularity` et `buckets: [{ from, toExclusive, partial, measures: { L01: { value, coverage? } } }]` (`coverage` n'est répété que s'il n'est pas `COMPLETE`). Invariant testé : la somme des intervalles d'une mesure additive (L, H01, H02, H03, F01 à F06) égale l'agrégat de la même période ; P01 est recalculé par intervalle et n'est pas additif.

Détail (`GET /metrics/details`) :

```
data: {
  definitionsVersion, computedAt, measure, period, scope,
  total: { lineCount, amountCents?, durationSeconds? },      // somme TOTALE du périmètre
  pageSum: { amountCents?, durationSeconds? },               // somme de CETTE page seulement
  drift: null | { lineCount: { expected, actual }, amountCents?: { expected, actual } },
  lines: [ ... ], page: { limit, nextCursor }
}
```

Lignes : `LESSON` (`lessonId`, `eventAt`, `status`, `state`, `instructorMembershipId`, `instructorLabel`, `learnerLabel`, `categoryCode`, `productKey`, `quantity`, `durationSeconds`, `amountCents`), `COURSE_OCCURRENCE` (`occurrenceId`, `seriesId`, `startsAt`, `courseTypeLabel`, `markedCount`, `missingMarks`), `COURSE_PAYMENT` (`paymentId`, `enrollmentId`, `recordedAt`, `amountCents`, `voidedAt`, `learnerLabel`). `amountCents` n'existe que pour qui a le droit financier ; `learnerLabel` est vide hors lecture déjà permise ; `instructorLabel` utilise la fonction de nom d'équipe existante. Aucun contenu de bilan, aucune position, aucune note personnelle.

### 7.5 Couverture, fraîcheur et cohérence

- **Dans une réponse** : une seule transaction `REPEATABLE READ` en lecture seule (`withActor`), donc cartes, comparaison, répartition et séries d'une même requête partagent un instantané. `computedAt` le date.
- **Entre deux réponses** : aucun instantané n'est promis. Le détail et l'export relisent la base. Pour qu'un écart ne passe pas inaperçu, le client renvoie `expectedLineCount` et `expectedAmountCents` lus sur la carte ; si le recalcul diffère, `drift` est renseigné (détail) ou l'en-tête de réponse `X-Metrics-Drift: true` et la ligne `# driftFromDisplayed;true` du fichier le disent, et l'interface propose de relire. Une donnée modifiée entre deux consultations est donc signalée, jamais masquée.
- **Réponse périmée** : chaque réponse renvoie `period`, `scope` et `filters` effectifs ; le web ignore toute réponse qui ne correspond plus aux filtres affichés et annule la lecture dépassée (`AbortController`). Aucun repli en zéro sur erreur : 503 `METRICS_UNAVAILABLE`.
- **Invalidation** : après une commande confirmée, le web revalide les statistiques par le mécanisme de révision de #107. Une commande locale en attente n'est pas intégrée.
- **Droits retirés** : chaque requête relit les grants ; le détail et l'export ne s'appuient jamais sur une autorisation mémorisée.

### 7.6 Pistes de mise en œuvre pour T02 (hors contrat)

À valider en T02, avec mesure de coût sur un volume représentatif ; aucun objectif de performance n'est affirmé ici.

- **Fonctions de lecture à périmètre explicite** (décision D1) : fonctions SQL `STABLE`, `SECURITY DEFINER`, `SET search_path`, en lecture seule, qui revérifient `current_school_member`, les rôles et grants de l'appelant, puis appliquent le périmètre `soi` ou `école` elles-mêmes. Même convention que `course_seats_taken` ou `lesson_learner_name`. Elles évitent le sous-comptage silencieux d'un moniteur dont l'affectation est terminée (Q14).
- **Index candidats**, un par mesure à justifier par `EXPLAIN` : `lesson (school_id, actual_start) WHERE status = 'COMPLETED'` (L01, H02, F01) ; l'index existant `lesson_schedule` couvre les autres états ; `course_payment_record (school_id, recorded_at)` (F05, F06) ; `course_enrollment (school_id, created_at)` et `(school_id, cancelled_at)` (C10) ; `course_attendance (occurrence_id)` (C03 à C05). Aucun n'est créé tant que la mesure ne le justifie pas.
- **Bornes** : période 366 jours, 400 intervalles, détail 100 lignes, export 10 000 lignes, délai maximal de requête à fixer après mesure (échec = 503, jamais zéro).
- Aucune lecture n'écrit : ni opération, ni audit métier, ni ligne dans une table de travail.

### 7.7 Export CSV

`POST /metrics/exports`, corps `{ measure, from, toExclusive, scope, filters..., expectedLineCount?, expectedAmountCents? }`. Droit : `EXPORT_MANAGEMENT` **et** droit de la mesure ; les deux sont relus à la requête (`403 ACCESS_REVOKED` sinon, sans fichier).

**Écart assumé avec la conception.** AP189 de la v3.17 décrit un export asynchrone (instantané privé, travailleur, jeton de téléchargement, 24 h). Rien de cette infrastructure n'existe dans le code (Q16). La proposition est un téléchargement **synchrone**, produit dans la transaction de lecture, répondu directement (`200 text/csv`, `Content-Disposition: attachment`, `Cache-Control: no-store`), sans fichier conservé, sans URL réutilisable ni stockage de données scolaires. Au-delà de 10 000 lignes : `413 EXPORT_TOO_LARGE` avec `maxLines`.

Format, documenté dans le fichier lui-même et dans `/metrics/definitions` :

- UTF-8 avec BOM, séparateur `;`, fin de ligne CRLF, guillemets doublés, champs entre guillemets dès qu'ils contiennent `;`, guillemet ou saut de ligne.
- Cellules **texte** commençant par `=`, `+`, `-`, `@`, tabulation ou retour chariot : préfixées d'une apostrophe (neutralisation des formules) ; les colonnes numériques ne contiennent que des chiffres.
- Montants en centimes entiers (`amount_cents`) et colonne `currency`, durées en secondes entières, dates ISO 8601 avec décalage dans le fuseau de l'école : aucune mise en forme locale, donc aucune dérive de montants ou de dates.
- Bloc de métadonnées en tête, lignes commençant par `#` : `definitionsVersion`, `computedAt`, `period`, `timeZone`, `currency`, `scope`, `filters`, `measure`, `lineCount`, `totalAmountCents` ou `totalDurationSeconds`, `coverage` (statut et raisons), `complete` (`false` dès que la couverture est partielle : un export partiel n'est jamais annoncé complet), `driftFromDisplayed`, `notAnAccountingDocument;true`.
- En-têtes de colonnes stables, versionnés avec `definitionsVersion` : `line_kind`, `line_id`, `event_at`, `status`, `instructor_id`, `instructor_name`, `category_code`, `product_key`, `quantity`, `duration_seconds`, `amount_cents`, `currency` (colonnes vides quand non applicables ou non autorisées).
- Nom de fichier `drivy-<mesure>-<from>_<toExclusive>.csv` : ni nom d'école, ni nom de personne.
- **Aucun nom d'élève** (D8). Les identifiants de ligne permettent de retrouver la fiche dans l'application.
- Le fichier n'est ni une facture, ni un bilan comptable, ni un relevé bancaire, et ne le prétend pas.

### 7.8 Erreurs

| Code | HTTP | Cas |
| --- | --- | --- |
| `METRIC_SCOPE_FORBIDDEN` | 403 | Portée `école` ou moniteur tiers sans droit |
| `ACCESS_REVOKED` | 403 | Droit retiré pour le détail ou l'export |
| `METRIC_FILTER_UNSUPPORTED` | 400 | Filtre refusé pour la mesure demandée (règlements) |
| `INVALID_PERIOD` | 422 | Dates invalides, ordre inversé, `compare` incompatible |
| `PERIOD_TOO_LARGE` | 422 | Plus de 366 jours ou plus de 400 intervalles |
| `EXPORT_TOO_LARGE` | 413 | Plus de 10 000 lignes |
| `SCHOOL_NOT_ACTIVE` | 409 | École en préparation |
| `METRICS_UNAVAILABLE` | 503 | Échec ou délai dépassé : jamais un zéro |

Un refus de droit ne contient ni montant, ni compte, ni identifiant de ressource.

## 8. Décisions à relire

Ce que le code ne permet pas de trancher. Chaque ligne a un choix par défaut. **Relues et acceptées le 31 octobre 2026** (coordination du projet), avec la condition de D1 ci-dessous. Le déploiement de ce qui en découle reste soumis à l'accord du porteur.

**Condition attachée à D1 (31 octobre 2026).** Une migration additive de fonctions de lecture et d'index est autorisée pour #375, sans table ni donnée. Toute fonction qui contourne la RLS (`SECURITY DEFINER`) doit : revérifier elle-même l'identité, l'adhésion à l'école, le rôle et le grant propre à la mesure ; fixer `search_path` ; n'être exécutable que par le rôle applicatif (`REVOKE ... FROM PUBLIC`, `GRANT ... TO drivy_app`) ; être couverte par des tests qui prouvent qu'elle refuse une autre école, un autre moniteur et un élève. Pour D3, le libellé reste « valeur convenue », jamais « revenu » ni « paie ».

| # | Question | Choix par défaut | Raison |
| --- | --- | --- | --- |
| D1 | Comment lire l'activité d'un moniteur dont l'affectation est terminée, et d'où lire les agrégats ? | Une migration **de fonctions et d'index seulement** en T02 (aucune table, aucune donnée, aucun backfill) : fonctions de lecture `SECURITY DEFINER` à périmètre explicite. Elle n'est pas écrite par T01 et aucun déploiement n'est impliqué. | Sous RLS, un moniteur perd la lecture de ses anciennes leçons (Q14) : l'agrégat sous-compterait en silence, ce qui confond zéro et inconnu. L'alternative sans migration (lecture sous RLS) obligerait à marquer `self` comme partiel en permanence. #375 interdit une migration implicite : celle-ci est donc à confirmer explicitement. |
| D2 | Un ADMIN peut-il exporter sans grant ? | Non : `EXPORT_MANAGEMENT` est requis, même pour un ADMIN ; il l'obtient une fois par `PATCH members` (réauthentification, audit). Lecture des statistiques : ADMIN sans grant. | Un ADMIN lit déjà tous les prix de leçons et tous les règlements de cours ; ses statistiques n'élargissent rien. L'export, lui, produit un fichier hors contrôle ; la conception (R96) demande un droit d'export explicite même pour l'ADMIN. Aucune permission n'est accordée par défaut. |
| D3 | Qui voit les finances, et par moniteur ? | ADMIN ou `VIEW_FINANCIAL_METRICS`, école entière, avec filtre et répartition par moniteur ; ce grant ne donne pas l'activité de l'école. Le nombre de lignes du détail d'un montant (égal à L01 ou L02 par construction) est visible. Libellé « valeur convenue des leçons », jamais « revenu » ni « paie » du moniteur. Un moniteur sans ce grant ne voit aucun montant agrégé, même sur ses propres leçons. | #373 et #379 prévoient la ventilation « selon droits » ; le grant existe avec ce libellé (Q13). Un montant agrégé par moniteur pourrait être lu comme sa rémunération ; il reste donc réservé à qui gère l'école. Le prix de chaque leçon reste lisible dans sa fiche, inchangé. |
| D4 | À quelle date rattacher une leçon ? | Réalisée : début réel ; toutes les autres : début prévu (K4). Une leçon `COMPLETED` sans début réel est comptée avec son début prévu et signalée `ACTUAL_START_MISSING`. | Aucune date d'annulation ni d'absence n'existe (Q3). Un rattachement unique garantit que les statuts se partitionnent sans double compte. Le cas `COMPLETED` sans début réel ne peut pas être produit par les routes actuelles ; c'est un filet pour des données plus anciennes. |
| D5 | Une saisie de règlement annulée, dans quelle période ? | Elle sort du total de sa période d'origine (date de saisie) et apparaît dans F06 : (a) pour sa période d'origine, (b) comme « correction postérieure » dans la période où elle a été annulée. Aucune écriture inverse n'est inventée. | Le modèle conserve la ligne avec `voided_at` et ne contient ni date de paiement ni remboursement (Q10). Annuler une saisie n'est pas un remboursement. C'est la lecture la plus proche de la règle de conception (correction rattachée à la date d'origine). |
| D6 | Devise | `CHF` constante, portée par chaque réponse. | Aucune colonne de devise n'existe et les comptes affichent déjà CHF (Q7). Ajouter une devise serait un changement de modèle, hors T01. |
| D7 | Définitions sans état serveur | « Élèves ayant eu une activité » = union des élèves ayant une leçon réalisée et des élèves marqués présents à une séance de cours dans la période. Une séance de cours est dite « avec appel » quand au moins une présence est saisie ; une séance passée sans aucune saisie est « à renseigner », jamais « tenue ». | Aucun état « séance tenue » n'existe. Le cadrage demande « une activité réelle », pas les membres actifs ; l'appel est la seule preuve saisie par une personne. |
| D8 | Contenu et mécanique du CSV | Synchrone, sans fichier conservé, UTF-8 avec BOM, séparateur `;`, métadonnées en lignes `#`, **sans nom d'élève**, 10 000 lignes au plus. | Le web suisse ouvre ces fichiers dans un tableur francophone. Un fichier téléchargé échappe à toute purge : on n'y met pas de nom d'élève ; la conception distingue d'ailleurs la liste d'élèves comme un autre type d'export. Aucune infrastructure d'export asynchrone n'existe (Q16). |
| D9 | Trace d'un export | Journal technique sans personne (identifiant de requête, mesure, nombre de lignes, durée). Pas d'`audit_event` métier dans cette tâche. | La lecture s'exécute dans une transaction en lecture seule ; y écrire un audit demanderait une écriture séparée. À arbitrer avec T07 si l'on veut tracer qui exporte. |
| D10 | Comparaison « mois à date » | Le jour courant est compté en entier côté courant ; la base est la même plage de jours du mois précédent, tronquée si plus courte (`clipped`). | Reste cohérent avec la carte « Ce mois-ci » de l'accueil, où les leçons du jour encore à faire sont « à venir ». Le jour incomplet est signalé, pas masqué. |
| D11 | Périmètre `soi` pour les cours | Séances qu'on anime (C01 à C05) ; séries dont on est responsable (C06 à C10). Les valeurs ne sont jamais en `soi`. | Une séance a un formateur, une série un responsable (`course_occurrence`, `course_series`). |
| D12 | Valeur des cours collectifs | Pas d'extension du modèle dans #373 : F07 reste indisponible (`COURSE_PRICE_SOURCE_MISSING`), les finances disent « leçons individuelles », les règlements de cours sont présentés à part. Un prix de cours demandera son propre cadrage. | Aucun prix inventé, aucune reconstruction depuis un règlement ou le tarif courant, et #373 exige qu'une extension indispensable soit cadrée séparément avant écriture (Q9). |

## 9. Tests de référence préparés (cas exigés par #374)

Chaque cas pointe vers la ligne du jeu qui le porte ; T02 en fait des tests contre une vraie PostgreSQL, sans donnée réelle.

| Cas exigé | Où dans le jeu | Ce que le test impose |
| --- | --- | --- |
| Changement de mois | S7 / O1, U3 / N1 | O1 en octobre, S7 en septembre, U3 en octobre, N1 en novembre ; échec d'un découpage UTC (47 000 et 68 000) |
| Fuseau et heure d'hiver | D1, semaine du 19/10 (169 h), octobre (745 h) | D1 dans la semaine du 19 ; bornes de période en instants corrects |
| Prix révisé | O3 (révision 18 000 vers 17 000), O2 et S1 à 9 000 | Valeurs au snapshot ; échec du tarif courant (62 000 / 61 000) |
| Multi-séances | CS1 (2 séances, 1 série, 3 inscriptions) ; S2 et O3 (quantité 2) | C01 = 2, C02 = 1, C06 compte chaque inscription une fois, F07 nul, une leçon de quantité 2 compte pour 1 |
| Règlement annulé | P4 / P5, P6, P10 | Une saisie annulée n'est pas comptée ; la ressaisie l'est ; P6 reste après l'annulation de I3 ; P10 expliqué par F06 (b) |
| Valeur absente | F07, O5 (durée inconnue), micro-cas école C | `null` et raisons, jamais 0 ; tout exclu donne `null` |
| Mois précédent vide | Septembre contre août ; M2 semaine du 12/10 | `BASE_BEFORE_DATA_START` et `BASE_ZERO`, jamais de pourcentage |
| 8 000 + 2 000 = 10 000 CHF avec un règlement de 500 CHF | Jeu B | F03 = 1 000 000 centimes ; aucun champ ne vaut 1 050 000 |
| Au-delà d'une page | Jeu B, pages de 25 | Total, série, détail et export concordent sur plusieurs pages |
| Droits, révocation, isolation | 6.7 | Aucun montant ni clé interdits dans les réponses, caches ni erreurs ; 403 inter-écoles |

## 10. Limites de ce document

- Aucun calcul n'a été exécuté sur une école réelle ni sur une base : les totaux viennent d'un jeu fictif et d'un script de contrôle indépendant. Au moment de T01, aucune requête SQL n'avait été écrite ni mesurée ; T02 les a écrites et mesurées en 11.3, les autres index de 7.6 restent des candidats.
- Aucune recette authentifiée, aucun résultat de performance, de GPS, de batterie ou d'accessibilité n'est affirmé.
- Rien n'est affirmé sur la marge, la trésorerie, la TVA ou la conformité comptable : le périmètre financier incomplet est dit dans les titres, la couverture et les fichiers.
- Le contrat de la section 7 est réalisé par T02 (section 11) ; le contrat OpenAPI 3.11.0 n'est pas modifié.
- `docs/implementation/STATUS.md` est mis à jour avec T02.

## 11. T02 (#375) : réalisation, limites et mesures

Les sections 1 à 10 sont l'état de T01 (#374). Cette section décrit ce que T02 a réellement livré ; en cas de contradiction avec la section 10, elle prévaut.

### 11.1 Routes

| Couche | Route | Rôle |
| --- | --- | --- |
| API | `GET /v1/schools/:schoolId/metrics/definitions` | Dictionnaire versionné et limites, sans donnée d'école |
| API | `GET /v1/schools/:schoolId/metrics` | Cartes par domaine (`activity` ou `finance`), comparaison et répartition |
| API | `GET /v1/schools/:schoolId/metrics/series` | Série par jour, semaine ou mois |
| API | `GET /v1/schools/:schoolId/metrics/details` | Lignes d'une mesure, paginées par curseur lié à la mesure et aux filtres |
| API | `POST /v1/schools/:schoolId/metrics/exports` | Export CSV synchrone, sans fichier conservé |
| BFF | `GET /app/bff/schools/:schoolId/metrics…` | Relais en lecture : dates civiles et valeurs énumérées validées avant tout appel amont |
| BFF | `POST /app/bff/schools/:schoolId/metrics/exports` | Session et jeton CSRF exigés ; le nom du fichier est reconstruit depuis des champs validés, rien de l'API n'atteint un en-tête |

Toutes les lectures passent par des fonctions SQL (`drivy.metrics_*`) qui appellent d'abord `drivy.metrics_gate` : rattachement à l'école, rôle, grants et portée sont relus par la base, sous `drivy_app`, avant toute ligne. Aucune écriture n'est déclenchée par une lecture ; la migration `20261031_pilotage_metrics.sql` ne crée que des fonctions et des index.

### 11.2 Limites appliquées

Période de 366 jours au plus, 400 intervalles de série au plus, 100 lignes par page de détail, 10 000 lignes par export, corps de commande de 4 096 octets, `statement_timeout` de 15 s par lecture (au-delà : `503 METRICS_UNAVAILABLE`, jamais un résultat partiel). Un export de plus de 10 000 lignes est refusé d'après le seul compte (`413 EXPORT_TOO_LARGE`), avant le calcul de la moindre page ; il n'est jamais tronqué.

### 11.3 Mesures sur volume représentatif

Mesure ponctuelle, **non commitée**, sur une PostgreSQL 17 locale (Docker Desktop, Windows), une école synthétique de 10 064 leçons réalisées réparties sur 8 moniteurs, 300 apprenants et 90 jours, une écriture de débit par leçon. Temps de bout en bout d'une requête HTTP de test (un seul passage, base chaude, aucune charge concurrente) :

| Lecture | Avant l'index d'écritures | Après |
| --- | --- | --- |
| Carte activité, 1 mois / 3 mois / 1 an | 171 / 190 / 187 ms | 183 / 223 / 126 ms |
| Carte finance, 1 mois | 2 073 ms | 79 ms |
| Carte finance, 3 mois ou 1 an | 4 705 ms et 4 717 ms | 86 ms et 89 ms |
| Carte finance par moniteur, 3 mois ou 1 an | 9 355 ms et 9 281 ms | 169 ms et 164 ms |
| Série par jour, 3 mois | 102 ms | 66 ms |
| Série par semaine, 1 an (finance) | 4 668 ms | 85 ms |
| Détail finance, page de 100 | 9 335 ms | 248 ms |
| Export de plus de 10 000 lignes | 4 642 ms (refus) | 88 ms (refus) |

Constat : la somme des écritures d'une leçon relisait toute la table des écritures pour chaque ligne (aucun index n'existe sur `account_id` hors des écritures initiales). L'index `charge_entry_metrics_account` règle ce point. Les noms des moniteurs et des apprenants d'une page ne sont plus calculés par ligne mais une fois par moniteur et par apprenant distincts : le test d'export refusé au-delà de 10 000 lignes, qui dépassait le délai de 15 s sur le serveur d'intégration (503 au lieu de 413), passe de 12,2 s à 2,1 s en local, graine de 10 001 leçons comprise.

Ce que ces chiffres ne disent pas : aucun objectif de performance n'est déclaré atteint. Le volume est celui d'une école ; la machine n'est pas celle d'un serveur de production ; la charge concurrente, un cache froid et une école de plus de 10 000 leçons par an ne sont pas mesurés. Les index des autres mesures (section 7.6) restent des candidats : seuls ceux qui servent les requêtes ci-dessus ont été vérifiés par une mesure.

### 11.4 Reste hors de T02

- Le contrat OpenAPI 3.11.0 du dossier de conception n'est pas modifié : les routes ci-dessus existent dans le code et dans leurs tests, pas dans le contrat conservé. À trancher avant tout client autre que le BFF.
- Les lectures `occurrence` et `paiement` du détail calculent encore leur libellé par ligne ; seul le détail des leçons a été rendu indépendant du nombre de lignes.
- Aucun écran : T03 à T09 (hors périmètre de cette livraison).
- Aucun déploiement : la migration n'est appliquée sur aucune base de production.

## 12. T03 (#376) : navigation, composition et socle d'affichage

Code : `apps/web/client/portal/pilotage/` (composants, période, formats, droits, lectures), `portal/destinations.ts` (navigation), `console/route.ts` (adresses). Aucun changement d'API ni de contrat.

### 12.1 Navigation (arbitrages à regarder à l'écran)

- **Un espace « Pilotage », deux rubriques** (Tableau de bord, Statistiques), en première place. Avec deux entrées séparées, la barre mobile aurait sept boutons ; elle en a six. Contrepartie : un clic de plus pour atteindre Statistiques depuis une autre page (l'espace s'ouvre sur le tableau de bord).
- **L'entrée quotidienne d'une école active ouvre toujours l'agenda.** Faire du tableau de bord l'accueil par défaut est un critère de T04 (#377), qui y met le contenu quotidien. Les cas DRAFT, ARCHIVED, la préparation et le catalogue ne sont pas touchés.
- **Statistiques** n'est offerte qu'à un administrateur ou à qui a `VIEW_SCHOOL_METRICS` ou `VIEW_FINANCIAL_METRICS` ; l'onglet Finances demande le droit financier. C'est un affichage : l'API revérifie à chaque lecture (section 5). Une adresse directe sans droit montre un refus, jamais des chiffres.
- **Adresses** : `/statistiques?tab=finance&period=custom&start=2026-10-05&end=2026-10-12&instructor=<uuid>&product=<clé>`. Sans `tab`, Activité ; sans `period`, le mois en cours. `end` est la dernière journée comprise ; la fin exclue envoyée au serveur est déduite une seule fois, dans `period-model.ts`. Un paramètre répété, inconnu ou mal formé est ignoré. Changer un filtre remplace l'entrée d'historique ; changer d'onglet en ajoute une. Seul le moniteur suit d'une rubrique à l'autre.

### 12.2 Ce que les pages montrent

Les chiffres viennent de `GET metrics` et `GET metrics/definitions` (relais BFF de T02) ; le web ne recalcule rien.

- **Tableau de bord** : bouton Planifier une leçon ; À traiter (A01, A02, A03, seulement celles dont la valeur est positive ou que le serveur ne peut pas garantir à zéro ; chacune ouvre l'agenda) ; Ce mois-ci (L01, L02, H02) ; une ligne période · portée · heure de calcul.
- **Statistiques → Activité** : Leçons (L01 à L04), Heures (H02, H03), Élèves (P01), Cours collectifs (C01, C06, C09).
- **Statistiques → Finances** : Leçons individuelles (F01 à F04), Cours collectifs (F05 et F07, cette dernière indisponible par construction).
- Une tuile montre la valeur, un badge **seulement** si la couverture est partielle, indisponible ou non applicable, et une aide « Comment ce chiffre est calculé » (formule du dictionnaire et parts exclues). Une valeur absente est un tiret, jamais un zéro.
- Rien n'est affiché tant que les chiffres et le dictionnaire ne sont pas tous deux lus. La portée de lecture contient école, domaine, période et moniteur : changer un filtre efface les chiffres précédents au lieu de les montrer sous un autre titre. Une réponse dont la période ne correspond pas à la demande est refusée.

### 12.3 Graphiques

Aucun graphique dans T03. Constat : `apps/web` n'a aucune bibliothèque de graphiques ; le composant Chart de shadcn s'appuie sur `recharts`, absent des dépendances. L'ajouter demande une dépendance verrouillée et la mise à jour du verrou. Non vérifié ici : la compatibilité de `recharts` avec React 19.3. À trancher en T05 (#378) avec le premier graphique, en face d'un dessin SVG sans dépendance.

### 12.4 Reste

- Aperçu synthétique (`?page=tableau-de-bord`, `?page=statistiques`) jamais regardé : 390 et 1440 px, clair et sombre, à faire par le porteur. Les valeurs de l'aperçu sont inventées.
- Filtres prestation et permis : `product` et `category` existent dans l'adresse, aucun contrôle ne les pose encore (T05). La comparaison (`compare`) est prévue dans le lecteur, aucune page ne la demande.
- Barre mobile à six entrées : l'étiquette « Formations » peut être tronquée à 320 px (déjà le cas à cinq).
- Non exécuté : aucun test. Seul `tsc --noEmit` a tourné, sans `lucide-react` ni `class-variance-authority` installés sur cette machine ; il ne signale aucune erreur dans les fichiers touchés. Aucun rendu navigateur.

## 13. T04 (#377) : accueil quotidien

Code : `portal/pilotage/dashboard-page.tsx` (blocs), `dashboard-appointments.tsx` (rendez-vous), `appointments.ts` et `today-summary.ts` (règles pures), `stacked-bars.tsx` (graphique), `portal/overview/overview-page.tsx` (entrée). Aucun changement d'API.

### 13.1 Entrée par défaut (changement visible pour tous, à valider à l'écran)

L'entrée nue d'une école active ouvre maintenant le tableau de bord, plus l'agenda. Une adresse qui porte déjà un contexte d'agenda (semaine, jour, moniteur, leçon, élève, cours, séance, vue) garde son agenda, pour que les liens existants ne changent pas de destination. DRAFT, ARCHIVED, préparation de l'école et catalogue sont inchangés. Le test navigateur de la CI (`scripts/dev/check-school-opening.ts`) attendait l'agenda pour l'adresse d'entrée nue d'une école active : il a échoué sur la PR #395, ce qui a confirmé le changement. **Son assertion a été remplacée, pas retirée** : l'adresse d'entrée avec contexte d'agenda (`?week=…`) garde l'assertion d'origine (elle retrouve l'agenda), et l'adresse nue doit ouvrir le tableau de bord, qui doit se lire sur la vraie API sans « Lecture impossible » ni débordement mobile. Le changement vient de #376 et #377 (« accueil d'une école active »), pas d'une décision de la CI ; revenir à l'agenda par défaut ne demande que de forcer `agendaLink` dans `overview-page.tsx` et de restaurer l'ancienne assertion.

### 13.2 Blocs et sources

Chaque bloc lit pour lui-même : l'échec d'un bloc ne retire ni les autres blocs ni l'accès au planning. Le filtre Moniteur (Toute l'équipe par défaut) est l'adresse `instructor`, partagée avec Statistiques.

- **Aujourd'hui** : une lecture d'activité sur le jour civil de l'école. Le total est L08 (le contrôle du serveur), puis seulement les états non nuls (L01, L06, L07, L05, L02, L03, L04), les heures programmées (H01) et les séances collectives (C01). Un badge « Partiel » apparaît si une de ces mesures n'est pas complète ; un total absent se lit « Leçons du jour indisponibles », jamais « Aucune leçon ».
- **À traiter** : A01, A02, A03 lorsqu'elles sont positives ou que le serveur ne garantit pas leur zéro. Chacune ouvre l'agenda en gardant le moniteur. Sinon « Rien à traiter ». Aucune demande d'élève n'est exposée (Q18).
- **Prochains rendez-vous** : leçons et séances collectives des sept prochains jours, par la projection de l'agenda (`agendaDays`), huit lignes au plus. Sont exclues les leçons terminées, annulées ou en absence, les séances passées et les cours qui ne sont pas publiés. Un badge n'apparaît que si la leçon sort de l'ordinaire (À démarrer, En cours, À terminer). La ligne ouvre la fiche dans l'agenda, avec semaine, jour et moniteur. Une lecture de séances qui échoue ne cache pas les leçons. La liste se recalcule chaque minute, sans nouvelle lecture.
- **Ce mois-ci** : L01, L02 et H02 du mois entier. L'écart de L01 et de H02 vient d'une seconde lecture, du 1er à aujourd'hui avec `compare=previous-month` (mode `MONTH_TO_DATE` : la même plage du mois précédent) ; la base est nommée (« vs du 1 au 12 octobre ») et L02 n'a pas d'écart. Si cette seconde lecture échoue, les tuiles s'affichent sans écart. Une leçon réalisée l'est déjà : sa valeur est la même dans les deux lectures.
- **Graphique** : « Leçons par jour », empilé, réalisées en plein et à venir en hachuré (la distinction ne repose pas sur la couleur), légende, résumé lu par les lecteurs d'écran et tableau des valeurs sous « Voir les valeurs ». Un jour sans valeur laisse un vide.
- **Finances du mois** (droit financier seulement) : F01, F02, F03 avec leur couverture, jamais présentées comme un encaissement ; « Voir les finances » ouvre Statistiques → Finances avec le moniteur.

### 13.3 Graphique sans dépendance (arbitrage)

Le graphique est un histogramme SVG écrit pour cet usage (`stacked-bars.tsx`), sans bibliothèque ni mise à jour du verrou des dépendances. C'est un choix de T04 pour ne pas bloquer l'accueil ; T05 et T06 peuvent le réutiliser ou décider d'une bibliothèque (section 12.3) si leurs besoins dépassent des barres empilées.

### 13.4 Reste

- Jamais regardé : aperçu `?page=tableau-de-bord` (valeurs synthétiques) à 390 et 1440 px, clair et sombre ; la hachure du graphique en sombre en particulier.
- Les chiffres de la journée ne se rafraîchissent qu'après une commande confirmée ou une relecture de la page, pas toutes les minutes.
- Le changement d'école purge l'ancien contexte par la portée de lecture ; non qualifié.
- Non exécuté : aucun test (écrits : `dashboard-models.test.ts`), aucun rendu navigateur. `tsc --noEmit` sans erreur dans les fichiers touchés, avec les mêmes réserves qu'en 12.4.

## 14. T05 (#378) : Statistiques → Activité

Code : `portal/pilotage/activity-panel.tsx`, `chart-model.ts` (granularité, intervalles, répartitions), `breakdown-bars.tsx`, `stacked-bars.tsx`, filtres dans `components.tsx`, `use-catalogue-options.ts`. Aucun changement d'API.

### 14.1 Filtres

Période (Ce mois, Mois dernier, Cette année, Période libre), moniteur, puis Permis et Prestation en second niveau. Ils sont dans l'adresse (`instructor`, `category`, `product`) et s'appliquent à toutes les mesures, tous les graphiques et à l'onglet Finances. Les choix viennent du catalogue de l'école (offres pour les permis, prestations de leçon individuelle pour les prestations) ; un filtre sans choix n'est pas affiché, et une valeur déjà dans l'adresse reste proposée même si le catalogue ne la connaît plus. Un filtre inapplicable à une mesure (cours collectifs) la rend « Non applicable », comme le serveur le décide.

### 14.2 Mesures

Leçons (L01 à L04 ; L05 « À vérifier » et L07 « À finaliser » seulement s'il y en a, ou si le serveur ne peut pas garantir leur zéro, donc jamais arbitrairement réalisées), Heures (H01 programmées, H02 réalisées aux durées connues, H03 à venir : trois grandeurs jamais additionnées), Élèves (P01 : élèves distincts ayant eu une activité), Cours collectifs (C02 cours, C01 séances, C06 inscriptions actives, C07 places retenues, C09 remplissage : cinq mesures distinctes, une inscription n'est pas multipliée par ses séances). Le taux d'occupation du planning n'est pas montré : aucune mesure du dictionnaire n'a de dénominateur de disponibilité fiable (section 4), et le chantier n'invente pas un moteur de disponibilité.

### 14.3 Comparaison

Calculée par le serveur, jamais par le web, et seulement sur une base équitable (`comparisonPlan`) :

- période écoulée : mois complet contre mois complet, sinon même nombre de jours juste avant (`equivalent-period`) ;
- mois en cours : à date, par une seconde lecture du 1er à aujourd'hui comparée à la même plage du mois précédent, pour les seules mesures réalisées (L01, H02), dont la valeur est la même dans la période entière et dans la période écoulée ;
- période encore ouverte (année en cours, période libre jusque dans le futur) : aucune comparaison.

Une base nulle ou partielle n'a pas de pourcentage : le serveur le dit (`percentReason`) et le web affiche l'écart absolu, ou rien.

### 14.4 Trois graphiques

1. **Évolution** : leçons réalisées (plein) et à venir (hachuré) par jour jusqu'à 14 jours, par semaine jusqu'à 93 jours, par mois au-delà ; un intervalle rogné par la période se dit « partielle ».
2. **Heures programmées par moniteur** : barres horizontales avec la valeur écrite, rangées **par nom**, jamais par valeur (R94 : pas de classement des moniteurs). Absent quand un moniteur est filtré.
3. **Leçons réalisées par permis ou par prestation**, au choix. Les groupes que le serveur n'a pas pu attribuer passent en dernier (« Non attribué »). Un zéro et une valeur absente ne sont pas dessinés.

Chaque barre de l'évolution se lit à la souris, au toucher et au clavier (flèches, début, fin) : titre complet de l'intervalle, valeur et unité dans une ligne de lecture annoncée aux lecteurs d'écran. Le tableau des valeurs est sous « Voir les valeurs ». Un intervalle sans valeur reste une lacune.

### 14.5 Reste

- **Clic d'une mesure vers le détail** : T07 (#380) ; aucun lien n'est posé ici.
- Aperçu `?page=statistiques` (valeurs synthétiques, filtres Permis et Prestation divisent les valeurs par deux) jamais regardé à 390 et 1440 px, clair et sombre ; la lecture au clavier du graphique n'a pas été essayée dans un navigateur.
- Aucune concordance vérifiée avec le jeu de référence de la section 6 : les tuiles affichent ce que le serveur renvoie, rien n'a été comparé chiffre à chiffre.
- Non exécuté : aucun test (écrits : `dashboard-models.test.ts`). `tsc --noEmit` sans erreur dans les fichiers touchés, mêmes réserves qu'en 12.4.

## 15. T06 (#379) : Statistiques → Finances

Code : `portal/pilotage/finance-panel.tsx`, `measure-groups.tsx` (rendu commun des groupes et de la comparaison), `breakdown-bars.tsx`, `stacked-bars.tsx`. Aucun changement d'API, aucun calcul de montant côté web.

### 15.1 Quatre notions séparées

Chaque tuile porte le libellé du dictionnaire et la couverture que le serveur déclare.

- **Leçons individuelles (tarif à l'unité)** : valeur des leçons réalisées (F01), valeur des leçons à venir (F02), total attendu selon le planning (F03). Le titre dit la couverture : seules les leçons individuelles à prix unitaire sont valorisées.
- **En attente de constat, hors du total** (F04) : leçons commencées ou dont l'heure est passée, ni réalisées ni réservations certaines. Montrée seulement s'il y en a, ou si le serveur ne garantit pas son zéro.
- **Règlements enregistrés (par date de saisie)** (F05) et **saisies annulées et corrections** (F06) : le titre dit la date retenue. Aucune tuile, aucun graphique ni aucun libellé n'additionne un règlement à la valeur des leçons ; annuler une saisie n'est pas un remboursement (libellé du serveur).
- **Cours collectifs** (F07) : indisponible, avec le badge du serveur. Aucun prix de série multiplié par ses séances, aucune valeur reconstruite depuis un règlement.

Un montant absent est un tiret, jamais « CHF 0.00 ». Un filtre moniteur, permis ou prestation rend F05 et F06 « Non applicables » : un règlement dépend d'une inscription, pas d'une leçon.

### 15.2 Graphiques

1. **Valeur des leçons par jour, semaine ou mois** : réalisée en plein, à venir en hachuré ; échelle en francs entiers, valeurs lues au centime près.
2. **Règlements enregistrés**, à part, avec la mention « date de saisie » : une date de prestation et une date de saisie ne se lisent pas sur le même graphique. Absent dès qu'un filtre est posé (le serveur refuse les filtres sur les règlements).
3. **Valeur des leçons réalisées par permis, prestation ou moniteur**, rangée par nom ; les valeurs non attribuées en dernier.

Même lecture au clavier et au toucher, même tableau des valeurs qu'en 14.4.

### 15.3 Comparaison

Même règle qu'en 14.3. À date, seules F01 (valeur constatée) et F05 (règlements saisis) sont comparées : ce sont les valeurs qui ne changent pas entre la période entière et la période écoulée.

### 15.4 Reste

- **Détail vérifiable et export** : T07 (#380) ; aucune tuile ne mène encore à ses lignes.
- L'exemple d'acceptation (8 000 CHF réalisés + 2 000 CHF réservés = 10 000 CHF attendus, un règlement de 500 CHF n'y change rien) est établi par les tests d'intégration de #375 (section 6.5) ; rien ne l'a été à l'écran ici, aucun chiffre n'a été comparé au jeu de référence.
- L'API ne renvoie que le franc suisse : aucune conversion, aucun hors taxe ou toutes taxes comprises.
- Aperçu `?page=statistiques&tab=finance` (valeurs inventées) jamais regardé à 390 et 1440 px, clair et sombre. Non exécuté : aucun test (écrits : `pilotage-models.test.ts`, `dashboard-models.test.ts`). `tsc --noEmit` sans erreur dans les fichiers touchés, mêmes réserves qu'en 12.4.

## 16. T07 (#380) : détail des mesures et export CSV

Code : `portal/pilotage/measure-detail.tsx`, `details-api.ts` (lecture des lignes et téléchargement), `detail-model.ts` (règles pures), `measure-groups.tsx` (accès depuis les tuiles). Aucun changement d'API ni de BFF : les routes `metrics/details` et `metrics/exports` de #375 sont consommées telles quelles.

### 16.1 Du chiffre à ses lignes

Une tuile dont le dictionnaire annonce des lignes (`details`) et dont la valeur est positive propose « Voir le détail ». L'adresse porte alors `measure` (par exemple `?tab=finance&measure=F01`) avec la période, le moniteur, le permis et la prestation de la carte : les lignes sont celles qui composent le chiffre, pas l'agenda non filtré. Changer d'onglet referme le détail. Un identifiant de mesure mal formé, répété ou d'un domaine non lisible est ignoré.

### 16.2 Ce que le détail montre

- Le chiffre de la carte avec sa couverture et les raisons des parts exclues, puis la ligne période · portée · heure de calcul.
- Les lignes : titre (l'élève seulement si le serveur le renvoie, sinon le fait lui-même), date et heure de l'école, moniteur, statut, durée, et le montant **seulement si le serveur le renvoie** (aucun montant n'est déduit côté web).
- Le total du serveur (lignes, montant, durée) à côté du nombre de lignes affichées ; quand toutes ne le sont pas, la somme des lignes affichées est écrite à part : somme de la page et somme totale ne se confondent pas.
- Cinquante lignes par lecture, « Afficher la suite » jusqu'au bout du périmètre (curseur lié par le serveur à la personne, à la mesure et aux filtres). Un curseur périmé propose de relire depuis le début.
- Les valeurs lues sur la carte repartent au serveur (`expectedLineCount`, `expectedAmountCents`) : si le total a changé depuis l'affichage, le serveur le dit, le web l'écrit et propose « Relire » qui relit la carte et les lignes d'un même instant.

### 16.3 Fiches

« Ouvrir » mène à la fiche existante dans l'agenda : la leçon, la séance de cours, ou le cours d'un règlement (aucune fiche de règlement n'existe seule). Le moniteur filtré est conservé. Le retour du navigateur ramène au détail avec ses filtres.

### 16.4 Export CSV

Le bouton « Exporter en CSV » n'apparaît que pour une personne qui a `EXPORT_MANAGEMENT` ; l'API relit ce droit et celui de la mesure à la génération. L'export reprend la sélection du détail (mesure, période, filtres, valeurs de la carte), pas la seule page affichée. Le web envoie la commande avec le jeton CSRF, lit la réponse comme **octets** (le BOM du serveur est conservé : la décoder puis la réécrire le perdrait) et déclenche le téléchargement ; rien n'est conservé, aucune adresse réutilisable n'est créée. Les refus ont chacun leur message (plus de 10 000 lignes, droit retiré, réseau, reconnexion) et ne produisent aucun fichier ; un écart signalé par l'en-tête du serveur est écrit à côté du nom du fichier. Le contenu du fichier (en-têtes stables, neutralisation des formules, métadonnées de couverture, `complete`) est celui de la section 7.7.

### 16.5 Reste

- Le clic d'une barre de graphique vers les lignes de son intervalle (`bucketFrom`, `bucketToExclusive`) n'est pas câblé, bien que le serveur le permette. F06, seule mesure en deux parties (`part`), s'ouvre par partie depuis la section 18.3.
- Au retour d'une fiche, le détail repart de la première page : les pages déjà chargées, le défilement et le focus ne sont pas restaurés.
- Non essayé : le téléchargement dans un navigateur, la lecture d'un vrai fichier dans un tableur, la révocation d'un droit pendant l'affichage. Le test de l'export avec texte accentué, guillemets, retours à la ligne et cellules de type formule est celui de l'API (#375) ; le web n'a rien écrit pour le contenu du fichier. L'aperçu fournit un CSV synthétique sans nom d'élève.
- Aucun test lancé (écrits : `detail-models.test.ts`, une ligne de `console-route.test.ts`). `tsc --noEmit` sans erreur dans les fichiers touchés, mêmes réserves qu'en 12.4.

## 17. T08 (#381) : responsive, accessibilité et états réseau

Lot de correction des seules pages de pilotage. Il ne remplace pas la revue globale différée de la roadmap et ne touche aucune autre page.

### 17.1 Fait

- **Données connues conservées en cas d'erreur** : quand une mise à jour échoue alors que des chiffres de la même portée sont déjà affichés (cartes, graphiques, répartitions, rendez-vous), ils restent à l'écran sous un avis « La mise à jour a échoué » qui donne l'heure de leur calcul et propose de réessayer. Ils ne sont jamais remplacés par zéro. Un refus (401, 403, 404) retire ce qui était affiché, comme partout ailleurs. Un changement de période, de moniteur, de permis, de prestation ou d'école repart d'un écran de chargement : les chiffres d'une autre portée ne sont jamais montrés sous le nouveau titre.
- **Réponses obsolètes** : une réponse qui ne correspond plus à la période ou à la portée demandées est refusée, et une lecture dépassée par une plus récente est ignorée (mécanisme commun des lectures).
- **Focus** : l'ouverture du détail d'une mesure place le focus sur « Retour aux chiffres » ; en revenant par ce bouton, la tuile d'origine reprend le focus dès qu'elle est affichée.
- **Cibles tactiles et petits écrans** : listes, champs de date, aides et boutons de tuile à 44 px au moins sur écran tactile ou étroit ; tableau des valeurs d'un graphique confiné dans son propre défilement horizontal (aucun défilement horizontal de la page) ; liste des lignes en lignes verticales.
- **Contraste forcé** : bordures, barres de répartition et focus des barres du graphique suivent les couleurs système.
- **Doublon retiré** : la comparaison à date de l'accueil passe par le même composant que les statistiques (`MeasureGroups`) ; cinq exports internes ne sont plus exposés.

### 17.2 Déjà vrai avant ce lot, relu

Titre, période, unité, légende, résumé lu et tableau des valeurs pour chaque graphique ; réalisé et à venir distingués par le plein et le hachuré ; barres lisibles au clavier (flèches, début, fin), au toucher et à la souris ; aucune animation ; formats fr-CH ; libellés longs et grandes valeurs qui passent à la ligne ; valeur absente en tiret.

### 17.3 Non fait, à ne pas tenir pour vérifié

- **Aucune vérification dans un navigateur ni sur appareil** : 320, 390, 768, 1024 et 1440 px, portrait et paysage, clair et sombre, agrandissement du texte et zoom n'ont pas été regardés. Aucune capture avant ou après n'existe. Les règles ci-dessus sont écrites, pas observées.
- Session expirée pendant une lecture d'accueil, refus de droit en cours de consultation, écran de chargement long : comportement hérité des lectures communes, non essayé.
- Un graphique financier échoué ne bloque pas l'agenda (chaque bloc lit pour lui-même) : établi par la structure du code, non essayé.
- Le défilement et les pages déjà chargées du détail ne sont pas restaurés au retour d'une fiche (16.5).
- Non exécuté : aucun test. `tsc --noEmit` sans erreur dans les fichiers touchés, mêmes réserves qu'en 12.4.

## 18. T09 (#382) : qualification du candidat `27a5a4e2`

Cette section **prévaut sur les mentions « non exécuté » des sections 12 à 17**, écrites avant l'exécution. Candidat : `27a5a4e2612d805799fa920ee1206a81be06c9e3`, branche `claude/pilotage-376-navigation`, base `master` `123304df`. Rien n'est fusionné, rien n'est déployé hors l'aperçu synthétique, aucune issue n'est fermée.

### 18.1 Ce qui a été exécuté

| Contrôle | Résultat | Où |
| --- | --- | --- |
| Typage de `apps/web` (dépendances réelles, `npm ci`) | PASS, 0 erreur | local |
| Typage de `apps/api` | PASS, 0 erreur | local |
| Tests web : 57 fichiers | PASS, 593 réussis, 1 échec attendu préexistant | local |
| Tests API du pilotage sur PostgreSQL 17 : modèle, intégration de #375, contrat web/API | PASS, 83 / 83 | conteneur local `postgres:17-alpine`, base `drivy_test` |
| Build de production (`vite build`, qui refuse tout module d'aperçu dans le produit) | PASS | local |
| Build de l'aperçu synthétique | PASS | local |
| Parcours dans Edge : détail, retour, focus, pagination, export, filtres, F06, période invalide, clavier du graphique | PASS, 23 / 23, aucune erreur JavaScript | aperçu local puis public |
| Captures : 5 pages × 5 largeurs (1440, 768, 390, 360, 320) × clair et sombre, 50 images | aucun débordement horizontal, aucun libellé de navigation tronqué, aucun texte de graphique sous 9 px, aucune erreur JavaScript | `.local/captures-373/final-27a5a4e2/` (non versionné) |
| Aperçu publié : SHA servi, en-têtes, chargement | PASS : `27a5a4e2612d` affiché, CSP, noindex, `no-store` | https://shulker.ch/drivy-preview/ |

Les tests web et API n'ont pas été rejoués par la CI : aucun workflow GitHub n'a été lancé pour ce lot.

### 18.2 Matrice critère → preuve

`PASS` = un test exécuté, nommé, le prouve ; `PARTIAL` = prouvé en partie ; `NOT_EXECUTED` = rien n'a tourné ; `N/A` = sans objet dans le produit actuel.

| Famille | Critère de #382 | Preuve | État |
| --- | --- | --- | --- |
| Calculs | zéro connu, valeur inconnue, période partielle | `août précède les données : inconnu, jamais zéro`, `une année qui commence avant les données est partielle`, `un montant exclu rend la mesure partielle ou inconnue, jamais zéro` (API, base réelle) | PASS |
| Calculs | mois complet, mois à date, février, début et fin de période | `mois à date contre la même plage…`, `mois à date tronqué quand le mois précédent est plus court`, `changement de mois`, modèle des dates (API) ; côté web `période du pilotage` (février 2026) | PASS |
| Calculs | changement d'heure | `la semaine du 19/10 dure une heure de plus`, `jours : … trois jours sur le changement d'heure` (API) | PASS |
| Calculs | comparaison de base nulle ou absente | `mois précédent vide : pas de pourcentage`, `base connue et nulle : écart absolu` (API) ; web : `la comparaison dit le pourcentage quand le serveur le donne, sinon l'écart` | PASS |
| Calculs | somme d'heures, prix historiques | `octobre : états, durées…`, `prix révisé et tarif historique : le snapshot fait foi` (API) | PASS |
| Activité | terminé, annulé, absent, en cours, non finalisé, leçon déplacée | `octobre : états, durées, élèves, cours et partition des leçons`, `une leçon corrigée en annulée ne vaut plus rien…` (API) | PASS |
| Activité | élève unique multi-permis, séries multi-séances, places retenues | `un cours sur plusieurs séances compte une série…`, `remplissage des cours à venir : somme des places…`, `instantanés : … places` (API) | PASS |
| Activité | annuaire paginé | le pilotage ne lit pas d'annuaire paginé pour ses chiffres ; la liste des moniteurs et des élèves passe par `readAll` existant | N/A |
| Finances | prix révisé, règlements identiques, saisie annulée, dates distinctes | `prix révisé…`, `détail des règlements : saisies actives, annulées et corrections postérieures`, `septembre : règlement d'octobre exclu, saisie annulée en octobre expliquée` (API) | PASS |
| Finances | exemple de l'acceptation : 8 000 + 2 000 = 10 000 CHF, un règlement de 500 CHF n'y change rien | `jeu B : …` (API) : totaux, séries, pages et export concordent au-delà d'une page | PASS côté API ; **jamais vu à l'écran** |
| Finances | tarif de cours absent | `F07` indisponible avec `COURSE_PRICE_SOURCE_MISSING` (API), tuile « Indisponible » sur capture | PASS |
| Finances | devises séparées | l'API ne renvoie que CHF (`currency: z.literal('CHF')`) | N/A |
| Finances | aucun double compte paiement et valeur d'activité | `octobre : réalisé, à venir, total attendu…`, jeu B | PASS |
| Droits | deux écoles, rôles et périmètres de moniteur | `une personne membre de deux écoles reçoit les totaux de chaque école, sans mélange`, `moniteur sans grant…`, `VIEW_SCHOOL_METRICS…`, `VIEW_FINANCIAL_METRICS…` (API) | PASS |
| Droits | activité autorisée, finances interdites | `VIEW_SCHOOL_METRICS : activité de l'école, aucune clé financière` (API) ; web : `droits d'affichage du pilotage` | PASS |
| Droits | accès direct API, BFF, export | `élève, autre école et personne sans appartenance : refusés`, `fonctions SQL : refus propres` (API) ; `un refus de droit de l'API traverse le relais…`, `exige session et jeton CSRF…` (BFF) | PASS |
| Droits | révocation | `un droit retiré entre l'affichage et l'export : refus, aucun fichier` (API) | PASS |
| Droits | changement d'identité en cours de consultation | portée de lecture clé par personne, école et époque d'accès (code) ; aucun test ne change d'identité pendant l'affichage | PARTIAL |
| Concordance | carte, total, montant, écart signalé | nouveau test `lignes de détail de chaque nature…` : 11 mesures, `lineCount`, `amountCents` et absence d'écart identiques entre la carte et le détail ; `signale un écart avec le total affiché` | PASS |
| Concordance | détail, CSV | `l'export contient exactement les lignes de la carte`, `même définition que la carte` (API) | PASS |
| Concordance | accueil → graphique → détail → CSV, de bout en bout | chaque maillon est prouvé séparément ; aucun test ne suit la chaîne sur l'API réelle depuis le navigateur | PARTIAL |
| CSV | accents, guillemets, sauts de ligne, formules | `accents, guillemets, sauts de ligne et cellules de formule`, `neutralise les formules des cellules texte` ; octets, BOM et CRLF conservés côté web (parcours) | PASS |
| CSV | plus de 10 000 lignes | `plus de 10 000 lignes : refus explicite, jamais un fichier tronqué` | PASS |
| Interface | clavier, retour navigateur | parcours : flèches du graphique, focus rendu à la tuile, retour du navigateur rouvre le détail | PASS (Edge émulé) |
| Interface | desktop, mobile, clair, sombre | 50 captures, mesures automatiques ci-dessus | PASS (Edge émulé) ; **œil du porteur attendu** |
| Interface | zoom, texte agrandi, paysage | rien n'a été essayé | NOT_EXECUTED |
| Interface | chargement lent, erreur partielle | structure du code, non provoqué dans le navigateur | NOT_EXECUTED |
| Interface | filtres rapides (réponses obsolètes) | mécanisme commun des lectures, refus des réponses de mauvaise période ; aucun test de course | PARTIAL |
| Interface | appareil physique | aucun | NOT_EXECUTED |
| Non-régression | préparation d'école, agenda, fiches, navigation #311 | les 593 tests web (dont navigation et agenda) passent ; **l'entrée par défaut a changé** (13.1) et n'a pas été essayée avec la vraie session | PARTIAL |
| Sécurité | confidentialité des caches et logs | `Cache-Control: no-store`, caches en mémoire clés par personne, école et époque d'accès ; revue de code, aucun test dédié | PARTIAL |
| Performance | agrégats et volume d'export | mesures de 11.3 (une école de 10 064 leçons, machine locale) ; aucun objectif déclaré atteint | PARTIAL |

### 18.3 Défaut trouvé par cette qualification

`F06` (saisies annulées et corrections) n'a pas de liste unique : l'API refuse son détail sans `part` (`a` ou `b`). Le web proposait pourtant « Voir le détail » sans partie, donc la liste se serait ouverte en erreur 400 devant l'utilisateur. Le test de contrat l'a révélé. Corrigé : le détail de F06 propose deux onglets (Saisies annulées, Corrections postérieures), l'adresse porte `part`, l'export envoie la partie et son nom de fichier la reprend. Les valeurs attendues de la carte ne sont pas envoyées pour F06, car le chiffre de la carte additionne les deux listes.

Trois défauts visuels, trouvés sur les captures et corrigés : la barre de navigation mobile à six entrées tronquait « Formations » et débordait dès 320 px ; les onglets de répartition d'un graphique faisaient déborder la page à 320 px ; le dessin du graphique, réduit avec son cadre, rendait les chiffres de l'axe illisibles sur téléphone (il suit maintenant la largeur réelle). Le groupe « À vérifier » de l'onglet Activité contenait une mesure du même nom et s'appelle « Non finalisées ».

### 18.4 Contrôle de contrat web et API

`apps/api/test/school-metrics-web-contract.integration.test.ts` fait lire les **vraies réponses de l'API** (dictionnaire, cartes d'activité et de finances, comparaisons, trois répartitions, séries par jour, semaine et mois, détails de neuf mesures) par les schémas de lecture du web (`portal/pilotage/metrics-schemas.ts`, désormais un module sans React). Une dérive de forme apparaît donc au test et non à l'écran. C'est le premier test de l'API qui importe et exécute du code de `apps/web` (deux autres n'en lisent un fichier que comme texte). Le module n'importe que `zod`, déjà installé à la racine par l'espace de travail de l'API à la même version (4.6.6) que le web : la CI de l'API, qui ne fait `npm ci` qu'à la racine, le résout. Non vérifié dans cette CI, qui n'a pas été lancée.

### 18.5 Reste, par nature

- **Essai du porteur sur l'aperçu** : fait le 1er novembre 2026 (« c'est bon, j'ai testé, c'est ok »), sans correction demandée. Son retour est oral : ni capture ni liste de ce qu'il a regardé n'a été conservée.
- **CI de la PR #395 (premier run, `250180fd`)** : « Refonte · vérifications » verte (API sur PostgreSQL, web et BFF, intégrité documentaire, GitGuardian) ; le test navigateur « ouverture école » a échoué sur l'entrée quotidienne (voir 13.1).
- **Pas de campagne CI (avant la PR)** : les workflows GitHub (« Refonte · vérifications », « Refonte · ouverture école navigateur » avec le vrai OIDC et le vrai BFF) n'ont pas été lancés. Ouvrir une PR les lancerait ; à décider avec lui.
- **Aucun essai sur la vraie pile** : le navigateur n'a jamais parlé au vrai BFF et à la vraie API. L'aperçu est synthétique ; la concordance des formes est prouvée par 18.4, pas le parcours.
- **Essais ajoutés après l'essai du porteur** (Edge, aperçu synthétique, 18 contrôles PASS, aucune erreur JavaScript) : défilement horizontal nul à 720 et 360 px de large (équivalent d'un zoom de 200 % et 400 %, obtenu par la taille de la fenêtre, **pas** par le zoom du navigateur) et en paysage 844×390 et 667×375 ; écran de chargement nommé pendant une lecture lente (2,5 s) ; erreur de lecture : message, aucun chiffre ni zéro, reprise par « Réessayer » ; réponse lente d'un ancien filtre ignorée quand un filtre plus récent a déjà répondu.
- **Toujours non exécuté** : texte agrandi par les réglages du système, appareil physique, échec d'une mise à jour quand des chiffres sont déjà affichés (la conservation des chiffres connus tient au code, elle n'a pas été provoquée), changement d'identité pendant l'affichage.
- **Déploiement du produit** : fait le 1er novembre 2026 après la fusion de la PR #395 (voir `STATUS.md`), web seulement : `8d6350c5`, reçu `20261101T180106Z-8d6350c53e13`, sauvegarde de la base préalable, retour arrière documenté. Aucun parcours authentifié n'a été fait en production.
- **Clôture** : #373 et ses lots ne sont pas fermés. Les cases de l'index de #373 restent ouvertes tant que l'essai et l'intégration n'ont pas eu lieu.
- **Retour arrière de l'aperçu** : `python scripts/homelab/deploy-preview-311.py --rollback 20261101T153438Z-27a5a4e2612d` (puis `--execute`) ; la version précédente `ce3b3559` est conservée.

Mode d'emploi destiné à la direction de l'école : [pilotage-373-utilisation.md](pilotage-373-utilisation.md).
