# Pilotage de l'école (#373) : dictionnaire des indicateurs, sources et droits

Lot T01 (#374) de l'epic #373. 31 octobre 2026. `definitionsVersion` : **`2026-10-31.1`**.

Base lue : `master` à `2a376c39` (fusion de #384, qui contient la refonte web #311). Spécification seulement : aucune route, aucune migration, aucun changement du contrat OpenAPI canonique 3.11.0, aucun calcul exécuté sur une école réelle. Les totaux du jeu de référence (section 6) ont été recalculés par un petit script indépendant du produit, avec des données entièrement fictives (codes `M1`, `E1`, `S1`... aucun nom).

> Document livré par sections sur cette branche : cette version contient les sections 1 à 3 (dictionnaire complet). Les sections 4 à 8 suivent dans les commits suivants.

Plan : 1. conventions communes · 2. ce que le code garantit réellement · 3. dictionnaire · 4. calculable maintenant / à compléter / hors V1 · 5. matrice des droits · 6. jeu de référence · 7. contrat commun proposé · 8. décisions à relire.

## 1. Conventions communes

Elles s'appliquent à chaque indicateur de la section 3 ; le dictionnaire ne les répète pas.

| Réf. | Règle |
| --- | --- |
| C1 Périmètre | Une seule école (`schoolId` de la route). Identité, rattachement, rôles et grants sont relus au serveur à chaque requête (`withActor` relit `membership`). Aucun agrégat inter-écoles. |
| C2 Fuseau et bornes | Période = dates civiles `from` incluse, `toExclusive` exclue, dans le fuseau **courant** `school.time_zone` (pas celui du navigateur ni UTC). Chaque borne est le premier instant existant du jour civil (même règle que `startOfDay` de `agenda-model.ts`). Un jour dure 23, 24 ou 25 h ; une semaine ou un mois ne se calcule jamais en ajoutant `N × 24 h`. Semaine = lundi à dimanche (comme l'agenda). Période maximale 366 jours. |
| C3 Instant de calcul | `computedAt` = instant de début de la transaction de lecture. « À venir », « à vérifier », « en cours », « à finaliser » et les places sont évalués à cet instant. Aucun état n'est déduit d'un horaire passé. |
| C4 Rattachement unique | Chaque leçon a **un seul** instant de rattachement `eventAt` : `actual_start` si la leçon est `COMPLETED` et a un début réel, sinon `planned_start`. Une leçon appartient donc à une seule période et les statuts d'une période se partitionnent : réalisées + à venir + annulées + absences + à vérifier + en cours + à finaliser = toutes les leçons de la période (contrôle de cohérence, indicateur L08). Les séances de cours se rattachent à `starts_at`, les règlements à `recorded_at`, les inscriptions à `created_at`/`cancelled_at`. Rien n'est découpé à minuit : une séance qui traverse minuit appartient au jour de son début. |
| C5 Confirmé | Seules les lignes serveur comptent. Une commande locale en attente ou incertaine (`command-store`) n'est jamais incluse. Une « réservation confirmée » est une ligne `lesson` au statut `PLANNED`. |
| C6 Zéro, inconnu, partiel | Trois états distincts, jamais confondus : **zéro connu** (la requête a réussi et rien ne correspond), **inconnu/indisponible** (source absente ou non couverte : `null`, jamais 0), **partiel** (valeur calculée sur une partie seulement, avec la part exclue et sa raison). Un échec réseau n'est jamais un zéro. L'absence de droit **omet** la mesure de la réponse (elle ne devient ni 0 ni « non applicable »). |
| C7 Unités et arrondis | Compteurs : entiers. Durées : somme en secondes entières (chaque durée = `floor` des secondes), arrondie à la minute (demi vers le haut) **seulement à l'affichage et après sommation**. Montants : centimes entiers (`bigint` côté SQL, entier JSON ≤ 2^53 − 1, dépassement refusé), aucune division ni virgule flottante. Pourcentage : `delta × 1000 / base` arrondi demi à l'écart de zéro, divisé par 10 (une décimale), calculé en entiers côté serveur. Affichage des montants : `Intl.NumberFormat('fr-CH', { style: 'currency', currency: 'CHF' })`, jamais de formatage manuel. |
| C8 Devise | `CHF`, constante. Aucune colonne de devise n'existe (`school`, `lesson`, `service_product_version`) et la projection de compte écrit `currency: 'CHF'` en dur. La réponse porte `currency: 'CHF'` pour que le jour où une autre devise apparaîtrait, les montants ne soient pas additionnés. |
| C9 Comparaison | Trois modes explicites : **mois complet** (mois civil entier contre mois civil entier, longueurs 28 à 31 jours affichées) ; **mois à date** (du 1er au jour courant inclus, jour entier, contre la même plage de jours du mois précédent, tronquée à la fin de ce mois s'il est plus court, avec `clipped: true`) ; **période équivalente** (même nombre de jours civils immédiatement avant). Le jour courant est compté en entier côté courant : les leçons pas encore réalisées y sont « à venir », donc hors « réalisées ». Le résultat donne `current`, `base`, `delta`, `daysInPeriod`, `daysInBase`. `percent` n'existe que si **base > 0, base connue et les deux côtés complets** ; sinon `percent: null` avec une raison parmi `BASE_ZERO`, `BASE_BEFORE_DATA_START`, `PARTIAL_COVERAGE`. Jamais de pourcentage infini ni de « +100 % » fictif. |
| C10 Début de couverture | `dataSince` = plus ancien `created_at` parmi les leçons et séries de cours de l'école (`school` n'a pas de `created_at`). Une base entièrement antérieure à `dataSince` est **inconnue** (`BASE_BEFORE_DATA_START`), pas nulle. |
| C11 Filtres | Moniteur (`instructor_membership_id`), permis (`category_code` de l'offre de la formation), prestation (`product_key` de la version de prestation choisie). Tous sont validés côté serveur ; un filtre inapplicable à une mesure la rend `NOT_APPLICABLE` (jamais ignoré silencieusement). Les filtres permis et prestation ne s'appliquent pas aux cours (un cours n'a ni permis ni prestation dans le modèle). |
| C12 Population | Leçons de l'école, **tous statuts**, y compris celles d'élèves archivés (l'archivage ne réécrit pas le passé) et de moniteurs dont l'accès est révoqué (la ligne `membership` reste). Les chiffres d'une période peuvent bouger après coup (correction d'issue, annulation d'un règlement) : `computedAt` le dit, aucun instantané historique n'est promis. |
| C13 Granularité | Séries par jour, semaine (lundi) ou mois civil. Un nombre d'élèves **distincts** se recalcule par intervalle, il ne s'additionne jamais d'un intervalle à l'autre. Le premier et le dernier intervalle d'une série sont marqués `partial: true` quand ils débordent de la période. 400 points au plus par série. |
| C14 Version | Toute modification d'une formule ou d'un statut inclus change `definitionsVersion` (format `AAAA-MM-JJ.n`, comme `swissProgrammeVersion`). Chaque réponse d'agrégat, de série, de détail et chaque CSV la porte. |

## 2. Ce que le code garantit réellement (vérifié sur `master` `2a376c39`)

Chaque ligne a été lue dans le code, pas déduite de listes web paginées.

| # | Constat | Source | Conséquence pour les indicateurs |
| --- | --- | --- | --- |
| Q1 | `lesson.status` vaut `PLANNED`, `COMPLETED`, `CANCELLED` ou `NO_SHOW`. Colonnes utiles : `planned_start/end`, `actual_start/end` (nullables, CHECK `lesson_actual_interval` : les deux nuls, ou début non nul et fin nulle ou postérieure), `price_cents_snapshot` (bigint ≥ 0, non nul), `commercial_selection` (jsonb : `mode`, `serviceProductVersionId`, `quantity`), `instructor_membership_id`, `learner_id`, `training_id`, `time_zone`, `created_at`. Index `lesson_schedule (school_id, planned_start, id)`. | migrations 006, 007, 023 | Base de L01 à L08. L'index couvre les périodes par `planned_start` ; le rattachement par `actual_start` demandera un index propre (section 7.6). |
| Q2 | Une leçon commencée reste `PLANNED` avec `actual_start` renseigné. `COMPLETED` n'est posé que par `POST /lessons/{id}/complete`, qui fixe le début réel (déjà enregistré ou fourni) et la fin réelle (obligatoire). La préparation GPS laisse la leçon `PLANNED` sans `actual_start`. | `lessons.ts` (`startLesson`, `start-now`), `lesson-reports.ts`, migration `20261028b` | Ni l'heure prévue ni une trace GPS ne produisent « réalisée ». Équivalent web : `lessonPhase` (`agenda-model.ts`) : `waiting` = L05, `started` = L06, `to-finish` = L07, `planned` = L02. |
| Q3 | Il n'existe **aucune** date d'annulation ni d'absence sur `lesson` (seulement `cancel_reason_code`, `cancel_comment`, `no_show_reason`). L'annulation remet `actual_start` à `NULL`. | migrations 006, 011 ; `lessons.ts` (`cancel`) | Annulées et absences se rattachent à `planned_start` (C4), jamais à un instant d'annulation inventé. |
| Q4 | La correction d'issue (ADMIN) ne sait aller que de `COMPLETED` vers `CANCELLED` ou `NO_SHOW` ; le retour vers `COMPLETED` ou `PLANNED` est refusé (`OUTCOME_CORRECTION_NOT_READY`). Elle remet `actual_start/end` à `NULL`, contre-passe la charge (`charge_entry` `REVERSAL`) et écrit `lesson_outcome_correction`. | `lesson-outcomes.ts`, migration 011 | Un total passé peut baisser après coup. Une leçon corrigée retombe sur `planned_start` (C4). |
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
| Q16 | Aucun export CSV n'existe dans l'API ni dans le web. La conception v3.17 (R96, `statistiques.md`) prévoit `EXPORT_MANAGEMENT`, 10 000 lignes, neutralisation des formules, aucune URL permanente. | recherche dans `apps/` | L'export est entièrement à écrire (T07). |
| Q17 | `GET /lessons` plafonne à 100 résultats par page (curseur HMAC lié à la portée). `agenda-model.ts` et `lesson-planning-model.ts` ne servent qu'à l'affichage et au formulaire de planification. | `lessons.ts` | Aucun compteur n'est calculé depuis ces listes. |
| Q18 | Aucune table de demandes élève vers l'école n'existe (`training_wish` est un texte libre de souhait). Depuis la décision du 28 septembre 2026, le bilan est partagé automatiquement : « bilans à publier » (M09 de la conception) n'a plus d'objet. | migration 007 ; `lesson-reports.ts` (`syncSharedReport`) ; `decisions-2026-09-28.md` | Le bloc « À traiter » ne contient que des obligations démontrées (A01 à A03). |

## 3. Dictionnaire des indicateurs

Légende : **Source** = table et colonnes réelles. **Pér.** = événement de rattachement (C4). Les droits sont ceux de la section 5 : `ACT` = lecture de l'activité de l'école (ADMIN ou `VIEW_SCHOOL_METRICS`) ou de la sienne (moniteur) ; `FIN` = ADMIN ou `VIEW_FINANCIAL_METRICS`.

### 3.1 Leçons individuelles : états

Toutes les lignes portent `school_id = :schoolId`, passent les filtres C11 et se rattachent par `eventAt` (C4). « Planifiée » désigne `status = 'PLANNED'`.

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
| P01 | Élèves ayant eu une activité | élèves | `count(DISTINCT learner_id)` sur l'**union** de (a) `lesson.learner_id` des L01 et (b) `course_enrollment.learner_id` des présences `PRESENT` aux séances de la période. Expose aussi P01a (leçons seules) et P01b (cours seuls). | Distinct par élève sur toute la période (un élève sur deux permis ou deux sources compte une fois). Inclut les élèves archivés depuis. Exclut les élèves seulement inscrits, planifiés, absents ou excusés. Ce n'est pas le nombre de membres actifs. Par intervalle d'une série, recalculé (C13). |

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

Toutes en centimes CHF (C7, C8). Aucune ne contient de TVA, de marge, de coût, de solde bancaire ou de « reste à payer ».

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

<!-- SUITE-T01 -->
