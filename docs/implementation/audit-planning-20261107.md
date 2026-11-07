# Audit du 7 novembre 2026 — lot A : planning cohérent (#423, #424, #439, #444, #446)

Base : `2a801eaf`. Les quatre défauts ont d'abord été **reproduits** par des tests rouges (PostgreSQL 17 synthétique, Docker, port 55431) : congé + cours/examen acceptés, séance laissée à +100 ans (`lastEndsAt` en 2127), règles d'annulation `NULL` après révision, formation close avec accompagnement impossible à corriger. Aucune issue n'est fermée.

## Corrections

| Issue | Décision |
|---|---|
| #423 | `src/instructor-closures.ts` : `overlapsClosure` (publication d'un cours, accompagnement d'examen) et `drivy.closure_bookings` (SQL, réservé à qui gère le moniteur) pour la **création** d'un congé, qui refuse désormais leçons planifiées, séances de cours publiées et accompagnements d'examen prévus (`409 EXISTING_BOOKINGS`, message avec le décompte). Publication : `409 COURSE_INSTRUCTOR_CLOSED` (brouillon conservé). Examen (création, modification, report) : `409 EXAM_ESCORT_CONFLICT`. Replanification : contrôle dans la fonction SQL. Intervalles `[début, fin)` : un créneau adjacent reste permis ; un cours hors heures de conduite sans congé aussi. |
| #439 | Migration `20261107_planning_coherence.sql` remplace `drivy.course_reschedule` : tableau, positions numériques, cardinalité **et égalité des ensembles de positions** vérifiés avant le premier `UPDATE` (`422 COURSE_POSITIONS_MISMATCH`). Doublon refusé aussi dès la validation HTTP. Un échange de dates réussit ; le décalage de 100 ans reste interne à la transaction. |
| #424 | `procedure.cancellationRules` optionnel (objet, `null` = retrait explicite). Omis : repris de la version précédente tant que `cancellationPolicyText` ne change pas ; si ce texte change alors qu'une règle existe : `422 CANCELLATION_RULES_DECISION_REQUIRED`. La fiche programme expose maintenant `procedure.cancellationRules` (relecture puis sauvegarde sans perte). Versions historiques non réécrites. `contracts/formations.json` complété. |
| #444 | Choix : **ne pas bloquer** les transitions, car aucune commande n'annule un examen futur (le blocage serait sans issue). `TRANSITION_TRAINING` renvoie `scheduledExamCount` (examens `SCHEDULED` dont la date ou l'accompagnement est à venir) pour PAUSED/COMPLETED/CANCELLED. `UPDATE_EXAM` et `POSTPONE_EXAM` n'exigent plus une formation active (ni un dossier non archivé) : retirer ou déplacer l'accompagnement libère exactement l'ancienne réservation, l'examen, ses révisions et son résultat restent intacts. Créer un examen reste réservé à une formation active ; résultats et corrections passés inchangés. |
| #446 | `attemptNumbers` regroupe désormais par `training_id` **et** `kind` (avant : par `kind` seul, donc les formations d'un même résultat de liste, voire de toute l'école, se comptaient ensemble : rangs 9 à 11 observés). `examList` et `examState` partagent la même fonction, donc le même ordre stable (date, création, id). Un examen `POSTPONED` garde `attempt=null` et ne consomme aucun numéro. Aucun changement de contrat ni d'UI. |

## Concurrence

Toute commande prend le verrou de l'école (`commands.ts`), donc congé et réservation d'une même école sont sérialisés ; la seconde relit l'état validé. Les tests le rejouent avec le blocage commun de `course-concurrency` : exactement un succès pour congé/publication et congé/accompagnement, refus sans occupation ni version partielle.

## Vérification

- `tsc --noEmit` et `npm run build` : RÉUSSI.
- `test/planning-coherence-20261107.integration.test.ts` : 16/16 RÉUSSI (RED observé avant correction, 14/16 en échec).
- Suite API complète sur PostgreSQL 17 : 1073 réussis, 1 ignoré, **2 ÉCHECS** dans `g1c.integration.test.ts` (SMTP réel Mailpit non fourni : message resté `QUEUED`) — sans lien avec ce lot, NON requalifiés.
- #446 : régression `exams.integration.test.ts` (3 formations dont 2 d'un même élève et 1 d'un autre, THEORY/PRACTICAL, un report, filtres UPCOMING et PENDING_RESULT, comparaison avec le dossier individuel) : RED observé (rangs 9, 11, 10, 11), puis 16/16 VERT ; `tsc --noEmit` RÉUSSI ; planning-coherence 16/16 toujours vert. Suite globale non rejouée (changement limité à `attemptNumbers`).
- Adaptations de tests existants : liste des migrations différées (`harness.ts`, `course-upgrade`) pour la nouvelle migration.

## Limites et suites

- Aucune UI : la console web doit (a) renvoyer `cancellationRules` relu de la fiche lors d'une révision et proposer le choix quand le texte d'annulation change (sinon 422), (b) afficher `scheduledExamCount` à la clôture, (c) traiter `COURSE_INSTRUCTOR_CLOSED` / `COURSE_POSITIONS_MISMATCH`. Contrat OpenAPI canonique 3.11.0 non modifié.
- Les erreurs n'ont pas de champ `details` : la liste des engagements n'est qu'un décompte dans le message.
- Pas de lien entre congé et `availability_rule` ; les leçons individuelles gardent leur contrôle `ensureOpen` existant.
- `STATUS.md` non touché (propriété du coordinateur).
