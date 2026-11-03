# Lot B iOS : repères des demandes de planification en attente (#108, #109)

3 novembre 2026. Branche `tomyrms/lotb-ios-reperes-108`, base `34d4c01a`. Tâche T4 : rendre visible, dans Aujourd’hui et dans l’Agenda, une demande de planification conservée dans le coffre chiffré avant son envoi.

Aucun compilateur Swift ni simulateur sur cette machine Windows : **tests écrits mais `NOT_EXECUTED`**, compilation et exécution à faire sur le runner Apple via l’IPA d’essai par le coordinateur.

## Ce qui existait déjà

- `PendingSchoolCommand` (`SchoolCommandOutbox.swift`) : `id`, `scope` (`SchoolCommandScope` : personne, école, rattachement, époque d’accès, API), `kind`, `resourceID`, `routeResourceID`, `createdAt`, `body`.
- `SchoolCommandKind.schedulingDomain` : `createLesson`, `moveLesson`, `cancelLesson` appartiennent au domaine `.teaching`, avec les bilans, fins de leçon, signalements, examens et gestes de cours.
- `SchoolCommandOutbox.pendingCommands(for:)` : la file réelle ; `EncryptedSchoolCommandOutbox.pendingCommands(for:)` ne rend que les commandes de la même personne, école et API (pas l’époque).
- `SchoolPendingCommandText.swift` : `inProgressTitle` (« Planification / Déplacement / Annulation en cours »), `requestedLessonStart`, `isStaleLessonRequest(at:)`, `waitingMessage(absent:)`.
- `SchoolPlanningWorkspace` : `pending`, `verify()`, `retry()`, `abandonPending()`, `pendingNotes`, `pendingIsStale`, `canRetry` ; `load()` relit `pending(for:domain: .teaching)`.
- `SchoolPlanningView` (non modifié) : bloc de demande avec Vérifier / Réessayer / Abandonner, et `cancelling` pour les champs d’annulation.
- Aujourd’hui : `SchoolTodayAppointments.ordered`, `SchoolTodayPresentation`, `lessonSummary`, `DrivyLessonRow` (`note:` / `state:`).
- Agenda : `dayIndex`, `SchoolAgendaEvent.day/summary`, `lessonRow`, feuille `$planningModel` avec `planningReturn`.
- Tests existants : `SchoolPlanningBookingTests` (dont `eachPlanningActionNamesItsOwnProgressAndNeverSaysItIsDone`), `SchoolPendingRequestResolutionTests`, `SchoolCommandOutboxTests`.

Constat qui motivait la tâche : hors de la feuille de planification, aucune demande conservée n’était visible ; il fallait la rouvrir pour savoir qu’une écriture attendait.

## Ce qui change

1. **`SchoolAgendaUI/SchoolPendingPlanningProjection.swift`** (nouveau, Foundation seul)
   - `SchoolPendingPlanningMarker` : `id` (opération), `scope`, `kind` (`.creation`, `.move`, `.cancellation`), `lessonID` (jamais pour une création), `requestedStart` (début voulu, nil pour une annulation), `createdAt`, `state` (`.inProgress`, `.toVerify`), `title` et `concerns(_:)`.
   - `SchoolPendingPlanningProjection.markers(from:scope:now:)` : pure, en lecture seule. Elle ne garde que les trois commandes de planification du domaine `.teaching` et la portée **exacte** (école, personne, rattachement, époque d’accès). Elle ne lit ni n’écrit le coffre.
   - État : « en cours » pour une demande écrite depuis moins de `inFlightWindow` (60 s) et dont l’horaire n’est pas passé ; « à vérifier » au-delà, ou dès que l’horaire demandé est passé (une demande périmée n’est plus renvoyable, seulement vérifiable). Hors de la feuille, l’app ne conserve aucun état d’envoi : l’horodatage d’écriture est la seule preuve de vie disponible, et le libellé ne prétend jamais que l’école a enregistré.
2. **`SchoolPlanningWorkspace.swift`** (minimum) : `static func opening(_:scope:client:lesson:outbox:)` rend une feuille ouverte sur la demande (portée vérifiée, début voulu, leçon seulement pour un déplacement ou une annulation). Aucune autre règle de la feuille n’est touchée.
3. **`SchoolTodayView.swift`**
   - Relecture des repères à l’apparition (`scopeKey`), au retour au premier plan, sur `.drivyLessonsDidChange`, et après fermeture de la feuille ; purge à chaque changement de portée.
   - Une création du jour devient une **ligne provisoire** (« Planification en cours » ou « À vérifier », horaire voulu, aucun élève, aucun état de leçon) sous les rendez-vous.
   - Un déplacement ou une annulation ne crée aucune ligne : la leçon confirmée reste à sa place, son mot d’état habituel restant lisible après le repère (« Déplacement en cours · En attente »).
   - Toucher la ligne ou le repère ouvre `SchoolPlanningView` sur la demande (`planningCancels` pour une annulation) ; aucun envoi ne part du repère.
4. **`SchoolAgendaView.swift`** : mêmes relectures et même purge ; mêmes repères dans la liste du jour ; une journée qui ne contient qu’une demande conservée n’affiche plus « Aucun rendez-vous ce jour » ; la feuille existante reçoit `cancelling`.

La présentation réutilise le composant d’état inhabituel du dépôt : le mot de `DrivyRowNote` en tête de la ligne de `DrivyLessonRow` (texte semi-gras, encre du ton), jamais une pastille, et l’état ne repose pas sur la seule couleur.

## Preuve par critère

| Critère de la tâche | Preuve | État |
| --- | --- | --- |
| Projection pure, portée courante seulement | `aRequestFromAnotherScopeNeverAppears` (autre époque, autre personne, autre école) | écrit, `NOT_EXECUTED` |
| Seuls les types de planification retenus | `onlyCreationMoveAndCancellationBecomeMarkers` (bilan, fin de leçon, signalement, démarrage immédiat, préférences, invitation écartés) | écrit, `NOT_EXECUTED` |
| Création non confondue avec une leçon | `aCreationStaysProvisionalAndNeverBecomesALesson` (`lessonID == nil`, titre, aucun repère sur une leçon) | écrit, `NOT_EXECUTED` |
| Déplacement et annulation gardent la leçon | `aMoveAndACancellationKeepTheirConfirmedLesson` (`concerns(lesson.id)`, début voulu pour le déplacement, aucun horaire inventé pour l’annulation) | écrit, `NOT_EXECUTED` |
| Aucun effet sur les compteurs, totaux ou la prochaine leçon | `aMarkerCountsAsNoLessonAndAsNoNextLesson` (`SchoolAgendaEvent.day/summary` et `SchoolTodayPresentation` inchangés avec un repère) | écrit, `NOT_EXECUTED` |
| État « en cours » / « à vérifier » sans fausse confirmation | `anUnansweredRequestIsToVerifyAndAStaleOneIsNeverInFlight` | écrit, `NOT_EXECUTED` |
| Repères relus sur `.drivyLessonsDidChange`, au premier plan, purgés au changement de portée | Relecture dans les deux vues + `pendingMarkers = []` sur `scopeKey` / `identityScope` | lecture du diff seulement |
| Toucher un repère ouvre la feuille existante sur la demande | `SchoolPlanningWorkspace.opening`, `planningModel`, `planningCancels` | lecture du diff seulement |
| Aucun nouvel envoi depuis le repère | Le repère ne touche ni le coffre ni le client ; la feuille garde `verify/retry/abandonPending` | lecture du diff seulement |
| Libellé accessible, état jamais porté par la couleur seule | `accessibilityLabel` sur la ligne provisoire, mot du repère dans la ligne combinée de la leçon, `accessibilityHint` « Ouvre la demande conservée » | lecture du diff seulement |
| Rendu, VoiceOver, grand texte, clair/sombre | Non compilé, non lancé | `NOT_EXECUTED` |

## Écarts, limites, décisions

- **« En cours » repose sur une fenêtre d’horodatage (60 s)**, pas sur un état d’envoi partagé : la feuille détient ce savoir, les deux écrans lisent le coffre. C’est une approximation assumée, documentée dans le code ; elle ne dit jamais que l’école a enregistré. Un état d’envoi partagé (propriétaire de la demande survivant à la feuille) reste le vrai correctif de fond, hors de cette tâche.
- **La ligne provisoire d’une création se pose après les engagements confirmés du jour**, pas à sa place chronologique : elle ne prend ni rail, ni position, ni total, et les lignes confirmées gardent leur ordre. Son horaire voulu reste lisible dans la colonne de gauche. Un déplacement ou une annulation, eux, restent attachés à la leçon qu’ils visent.
- **Une demande dont la leçon n’est pas dans la fenêtre lue n’a pas de ligne** : pour une annulation, le coffre ne porte aucun horaire ; pour un déplacement hors période, la ligne provisoire serait posée à un autre jour. La demande reste alors visible depuis Aujourd’hui si elle concerne aujourd’hui, sinon en rouvrant la feuille. Non traité.
- **Toucher une leçon qui porte un repère ouvre la demande, plus la fiche de la leçon** : c’est le geste demandé (« toucher un repère ouvre la feuille »). Après vérification ou abandon, le repère disparaît et la ligne rouvre la leçon. La fiche reste accessible par la recherche de l’agenda et le dossier.
- **Recherche de l’agenda** : les résultats de recherche ne portent pas les repères ; seule la liste du jour les affiche. Hors périmètre de la tâche.
- **Pas de nouveau propriétaire de la demande** : la feuille est encore créée par la vue qui la présente (même choix que le lot A). Le repère est un accès, pas une seconde file.
- `docs/implementation/STATUS.md` n’est pas mis à jour : hors de la liste des fichiers autorisés pour cette tâche.
- Aucune mesure de performance, aucune capture, aucune exécution : rien n’est inventé.

## Vérifications lancées

- `git log -1 --format=%h` avant modification : `34d4c01a` (conforme).
- Lecture du diff complet `git diff 34d4c01a` (accolades, `try`/`await`, types, libellés d’arguments, `@MainActor`, `switch` exhaustifs) : six tests écrits dans `SchoolPendingPlanningProjectionTests`.
- Compilation Swift, tests, IPA : `NOT_EXECUTED` (pas de chaîne Apple sur cette machine ; à faire sur GitHub Actions).
