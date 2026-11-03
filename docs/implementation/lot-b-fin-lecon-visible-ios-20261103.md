# Lot B iOS : fin de leçon ou absence visible dans Aujourd’hui (#114)

3 novembre 2026. Branche de travail `tomyrms/lotb-ios-fin-114`, base `869cc11f`. Tâche T7 : rendre visible, dans
Aujourd’hui, une fin de leçon ou une absence encore conservée dans le coffre chiffré, et le refus définitif reçu
après la fermeture de la fiche.

Aucun compilateur Swift ni simulateur sur cette machine Windows : **tests écrits mais `NOT_EXECUTED`**, compilation et
exécution à faire sur le runner Apple via l’IPA d’essai par le coordinateur.

## Ce qui existait déjà

- `SchoolLessonReportWorkspace` : `isSendingClosure` (`isBusy && isFirstSend` sur `completeLesson` ou `markNoShow`),
  `leaveWhileClosureIsSent()`, `holdsScreen` excluant le constat de fin ; `transmit` retire la commande du coffre sur
  un refus définitif (`SchoolReportFailure.permitsFreshCorrection` ou `.notFound`) et publie `drivyLessonsDidChange`
  sur une confirmation.
- `SchoolCommandOutbox` / `EncryptedSchoolCommandOutbox` : `completeLesson` et `markNoShow` du domaine `.teaching`, avec
  `resourceID` = leçon ; `PendingSchoolCommand.createdAt` est la seule preuve de vie disponible hors de la fiche.
- `SchoolPendingPlanningProjection` (#108, lot B) : `inFlightWindow` (60 s), état « en cours » / « à vérifier »,
  affichage par `DrivyRowNote` en tête de ligne.
- Aujourd’hui : `SchoolTodayView.pendingMarkers`, `planningNote`, `DrivyLessonRow(note:)`, relectures sur
  `.drivyLessonsDidChange`, au premier plan et à la fermeture des feuilles, purge au changement de `scopeKey`.
- Tests existants : `SchoolLessonClosureReactivityTests` (envoi, fermeture, reçu manquant, absence),
  `SchoolPendingPlanningProjectionTests` (projection pure des demandes de planification).

Constat qui motivait la tâche : une fin refusée définitivement après la fermeture de la fiche ne se voyait plus que
par la leçon restée « à terminer » dans Aujourd’hui, sans dire qu’un envoi avait été refusé.

## Ce qui change

1. **`apps/ios/Drivy/SchoolLessonReportUI/SchoolPendingClosureProjection.swift`** (nouveau, Foundation seul)
   - `SchoolPendingClosureMarker` : `id` (opération), `scope`, `kind` (`.completion`, `.absence`), `lessonID`,
     `createdAt`, `state` (`.inProgress`, `.toVerify`), `title` (« Fin en cours », « Absence en cours », « À vérifier »).
   - `SchoolPendingClosureProjection.markers(from:scope:now:)` : pure, en lecture seule. Elle ne garde que
     `completeLesson` et `markNoShow` de la portée **exacte** (école, personne, rattachement, époque d’accès) ; toutes
     les autres commandes, y compris les demandes de planification, restent dehors. Aucune lecture ni écriture du
     coffre, aucun envoi.
   - État : « en cours » tant que la demande a été écrite depuis moins de `SchoolPendingPlanningProjection.inFlightWindow`
     (constante existante réutilisée, aucune seconde fenêtre) ; « à vérifier » au-delà. Une fin n’ayant pas d’horaire
     propre, la règle « horaire passé » des demandes de planification ne s’y applique pas. Hors de la fiche, l’app ne
     conserve aucun état d’envoi : le libellé ne prétend jamais que l’école a enregistré.
   - `SchoolRefusedClosureMarker` + `@MainActor SchoolRefusedClosureMemory` : mémoire de session seulement, jamais sur
     le disque, par portée et par leçon. `remember`, `marker(forLesson:scope:)`, `markers(for:)`, `forget`, `forgetAll`.
2. **`SchoolLessonReportWorkspace.swift`** (minimum)
   - Dans `transmit`, un refus définitif (`permitsFreshCorrection` ou `.notFound`) reçu alors que la fiche est fermée
     (`invalidated` ou génération changée) enregistre le repère en mémoire puis s’arrête, au lieu de perdre
     l’information. Le refus reçu fiche ouverte ne change rien (il s’y lit déjà).
   - `rememberRefusedClosure` ne retient que `completeLesson` et `markNoShow`, et publie `drivyLessonsDidChange` avec un
     `SchoolLessonChange` **sans `kind`** : les écrans relisent leurs repères, mais rien n’est annoncé terminé ni
     absent (le point « à terminer » et le trajet ne se ferment pas sur un refus).
   - `load()` réussi efface le repère de cette leçon (réouverture de la fiche) ; `invalidate()` aussi (accès perdu).
3. **`SchoolTodayView.swift`**
   - `closureMarkers` et `refusedClosures` relus par `reloadPendingRequests()` (ex-`reloadPendingPlanning`) sur
     `.drivyLessonsDidChange`, au retour au premier plan, à l’apparition et à la fermeture des feuilles.
   - Purge au changement de `scopeKey` : les trois listes sont vidées et `SchoolRefusedClosureMemory.forgetAll()`.
   - `forgetSettledRefusals` retire un repère de refus dès qu’une relecture (jour ou historique) montre la leçon
     terminée, absente ou annulée.
   - `rowNote` : un seul repère par ligne. Le repère de planification garde la priorité (il porte le geste de la ligne
     et reste vérifiable dans sa feuille) ; le repère de fin n’apparaît qu’en son absence, devant l’état habituel
     (« Fin en cours · En attente »), et se vérifie en ouvrant la fiche de la leçon.
   - Toucher la ligne garde le geste actuel (fiche de leçon, ou feuille de planification si un repère de planification
     est posé). Aucun envoi ne part du repère.
   - Aucun changement d’ordre, de compteur, de total ni du rappel « à terminer » : le repère est une note de ligne.

La présentation réutilise `DrivyRowNote` (texte semi-gras, encre du ton), jamais une pastille ; le mot porte l’état,
la couleur ne le porte pas seule. « En cours » et « refusée » s’écrivent dans l’encre principale, « À vérifier » en
encre secondaire, comme les repères de planification.

## Preuve par critère

| Critère de la tâche | Preuve | État |
| --- | --- | --- |
| Projection pure, portée exacte seulement | `aClosureFromAnotherScopeNeverAppears` (autre époque, autre personne, autre école) | écrit, `NOT_EXECUTED` |
| Seules `completeLesson` et `markNoShow` retenues | `onlyCompletionAndAbsenceBecomeMarkers` (planification, bilan, objectifs, départ, observation écartés) | écrit, `NOT_EXECUTED` |
| En cours puis à vérifier, même règle que la planification | `anUnansweredClosureIsToVerifyAndAFreshOneIsInFlight` (fenêtre partagée `inFlightWindow`) | écrit, `NOT_EXECUTED` |
| Refus gardé en mémoire seulement, puis effacé à la réouverture et au changement de portée | `aRefusalStaysInMemoryUntilTheSheetReopensOrTheScopeChanges` ; `aRefusalReceivedAfterTheSheetWasLeftIsKeptThenForgottenOnReopening` (serveur qui refuse après la fermeture) | écrit, `NOT_EXECUTED` |
| Refus fiche ouverte jamais mémorisé | `aRefusalWithTheSheetStillOpenIsNeverKeptInMemory` | écrit, `NOT_EXECUTED` |
| Aucune leçon montrée terminée sans preuve | `aLessonIsNeverShownCompletedWithoutProof` ; `model.lesson?.status == "PLANNED"` après le refus | écrit, `NOT_EXECUTED` |
| Repères relus sur `.drivyLessonsDidChange`, au premier plan, à la fermeture des feuilles ; purge au changement de portée | `reloadPendingRequests` et `forgetAll` dans `SchoolTodayView` | lecture du diff seulement |
| Toucher la ligne ouvre la fiche existante, aucun envoi depuis le repère | `lessonSummary` inchangé pour le geste ; le repère ne touche ni coffre ni client | lecture du diff seulement |
| Ordre, compteurs, totaux et rappel « à terminer » inchangés | note de ligne seulement ; `appointments`, `SchoolTodayPresentation` et la tâche `requiredActions` non modifiés | lecture du diff seulement |
| Libellé accessible, état jamais porté par la couleur seule | mot du repère dans la ligne combinée de `DrivyLessonRow` ; aucun nouveau libellé séparé | lecture du diff seulement |
| Rendu, VoiceOver, grand texte, clair/sombre, latence réelle | Non compilé, non lancé | `NOT_EXECUTED` |

## Décisions, écarts, limites

- **Priorité d’un seul repère par ligne** : quand une leçon porte à la fois un repère de planification et un repère de
  fin, le repère de planification est seul affiché, parce qu’il décide du geste de la ligne (ouvrir la demande
  conservée, où Vérifier / Réessayer / Abandonner existent). La fin se vérifie depuis la fiche de la leçon. Simple,
  documenté dans `rowNote`.
- **« En cours » reste une approximation d’horodatage (60 s)**, héritée des repères de planification : hors de la
  fiche, l’app ne possède pas l’état d’envoi. Le libellé ne dit jamais que l’école a enregistré.
- **Le refus n’est mémorisé qu’après la fermeture** : fiche ouverte, le refus et sa raison s’affichent dans la fiche.
  La mémoire ne survit ni au redémarrage ni au changement de portée (exigence : rien sur le disque).
- **La raison détaillée du refus n’est pas conservée** : la demande a quitté le coffre sur un refus définitif. Le
  repère dit seulement « Fin refusée » / « Absence refusée » ; la consigne interdisait tout texte de refus sur la
  ligne. La fiche rouverte relit la leçon, qui reste planifiée : elle ne rejoue pas automatiquement la demande.
- **L’Agenda n’est pas modifié** (contrainte de la tâche : une autre tâche y travaille). Seul Aujourd’hui affiche ces
  repères.
- **`STATUS.md` n’est pas mis à jour** : hors de la liste des fichiers autorisés pour cette tâche.
- **`project.yml` non touché** : le nouveau fichier Swift est pris par XcodeGen sans déclaration.
- Aucune mesure de rendu, aucune capture, aucune exécution : rien n’est inventé.

## Vérifications lancées

- `git log -1 --format=%h` avant modification : `869cc11f` (conforme).
- Relecture du diff complet `git diff 869cc11f` (accolades, `try`/`await`, `switch` exhaustifs, labels d’arguments,
  `@MainActor`, types `Sendable`, `self.` dans les closures, ordre des paramètres des initialiseurs synthétiques).
- Compilation Swift, exécution des tests, IPA : `NOT_EXECUTED` (pas de chaîne Apple sur cette machine ; à faire sur
  GitHub Actions).
