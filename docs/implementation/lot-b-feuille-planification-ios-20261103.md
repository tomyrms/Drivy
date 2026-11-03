# Lot B iOS : quitter la feuille de planification pendant l’envoi (#109)

3 novembre 2026. Branche `tomyrms/lotb-ios-feuille-109`, base `60adf11b`. Tâche T8 : rendre la feuille de planification
quittable pendant l’envoi d’une **création** ou d’un **déplacement** déjà conservés dans le coffre chiffré, sans rien
confirmer avant la preuve de l’école, et sans jamais libérer une **annulation** (la capture en direct en dépend).

Aucun compilateur Swift ni simulateur sur cette machine Windows : **tests écrits mais `NOT_EXECUTED`**, compilation et
exécution à faire sur le runner Apple via l’IPA d’essai par le coordinateur. Aucun rendu, aucun VoiceOver, aucune
mesure de latence n’est prétendu ici.

## Étape 1 — audit, écrit avant de coder

### Qui possède la feuille et la tâche d’envoi

- `SchoolPlanningWorkspace` est créé **par la vue qui présente la feuille** et détenu par son `@State` (ou par
  `SchoolStartNowPresentation.planning`, `SchoolLessonReportView.presentedPlanning`, `SchoolCaptureLiveView.cancellationModel`),
  puis passé à `SchoolPlanningView` par `.sheet(item:)`. À la fermeture, SwiftUI remet ce binding à `nil` : la feuille
  ne possède donc plus rien.
- L’envoi est lancé depuis le bouton : `Button { Task { _ = await model.saveBooking() } }` (`SchoolPlanningView`,
  `bookingActionContent`) et, pour une annulation, `Task { … _ = await model.cancel() }`. C’est une `Task` **non
  structurée** : ni la disparition de la vue ni la fermeture de la feuille ne l’annulent. Les lectures de la feuille
  (`.task { await model.load() }`, `.task(id:)` pour le créneau et les disponibilités) sont, elles, annulées à la
  disparition — et `load`, `validateSlot`, `findSuggestedSlot`, `loadAvailability` vérifient `Task.isCancelled`.
- **L’envoi survit donc à la fermeture** : `submit` écrit la demande dans le coffre chiffré (`outbox.save`) avant
  `transmit`, et `transmit` ne s’interrompt pas à la disparition de la vue. Ce qui ne survivait pas, c’était son
  **résultat** : `transmit` faisait `guard request == generation else { return true }` après le reçu, donc une
  confirmation arrivée après un changement de génération (`invalidate`, `close`) n’était ni appliquée, ni annoncée
  (`.drivyLessonsDidChange` n’était pas publié).
- Jusqu’ici la feuille ne pouvait de toute façon pas être fermée pendant un envoi : « Fermer » était
  `.disabled(model.isBusy || isPreparingCancellation)` et `.interactiveDismissDisabled(model.isBusy || …)`. Le garde de
  génération ne servait donc qu’à un changement de portée (`scopeKey` / `identityScope`) pendant l’envoi.

### Hôtes qui présentent `SchoolPlanningView`

| Hôte | Ce qu’il présente | Comportement à la fermeture | Verdict après le changement |
| --- | --- | --- | --- |
| `SchoolTodayView` (`.sheet(item: $planningModel)`) | création, déplacement, annulation (`planningCancels`) | `onDismiss` → `refreshAfterPlanning()` = relecture des repères + `load()` ; `.onReceive(.drivyLessonsDidChange)` → repères + `load()` | relit deux fois au pire, rien n’est perdu |
| `SchoolAgendaView` (`.sheet(item: $planningModel)`) | idem, avec `onConfirmedLesson: { planningReturn.receive($0) }` | `onDismiss` → ouvre la fiche de la leçon confirmée si elle a été reçue, puis `refreshAfterPlanning()` ; `.onReceive` → agenda + repères | la fiche ne s’ouvre pas si la personne est partie avant la réponse : l’agenda relit et la leçon y est (voir plus bas) |
| `SchoolHomeView` (`.sheet(item: $dossierPlanningModel)`) | planification depuis le dossier de l’élève | **aucun `onDismiss`** : le commentaire du code dit que la planification annonce elle-même son écriture confirmée une fois ; `.onReceive(.drivyLessonsDidChange)` relit | inchangé — c’est cet hôte qui exige que l’annonce parte même après fermeture |
| `SchoolStartNowSheets` / `SchoolStartNowView` (`.sheet(item: $presentation.planning)`) | planification après un conflit de « Lancer maintenant » | `onDismiss` → `presentation.finished()` → `onFinished` de l’écran d’origine | inchangé |
| `SchoolLessonReportView` (`planningSheet`, `.sheet(item: $planningRoute)`) | déplacement, annulation (toujours avec `lesson:`) | `planningClosed()` : ferme le trajet si `confirmedCancellationLessonID` correspond, puis `model.load()` + `changeModel?.load()` ; **aucun observateur de `.drivyLessonsDidChange`** | relecture à la fermeture conservée ; une confirmation arrivée *après* la sortie n’est pas relue dans cette fiche (limite, voir plus bas) |
| `SchoolCaptureLiveView` (`.sheet(item: $cancellationModel, cancelling: true)`) | **annulation seulement**, avec `beforeCancellation: { await controller.stopAndSynchronize() }` | `onDismiss` → `cancellationClosed()` : ferme le trajet et ouvre la leçon sur `confirmedCancellationLessonID` | intact : une annulation n’est jamais quittable pendant son envoi, donc `confirmedCancellationLessonID` n’est jamais posé après coup |
| `SchoolOfficeVisualReview` | maquette de revue visuelle (`models.planning`) | aucun | inchangé |

Aucun hôte ne devient dangereux : les deux seuls qui s’appuient sur la preuve (`Agenda` via `planningReturn`, capture en
direct via `confirmedCancellationLessonID`) restent corrects — le premier parce qu’il relit, le second parce que
l’annulation reste verrouillée. Aucun hôte n’est exclu.

## Ce qui change

1. **`SchoolPlanningWorkspace.swift`**
   - `isSendingRequest` : vrai pendant `transmit` d’une **création** ou d’un **déplacement** (premier envoi comme renvoi
     d’une demande déjà conservée). Rien d’autre ne le pose : `verify()`, `cancel()` et `startLessonNow` ne le lèvent
     jamais.
   - `holdsScreen` = `isBusy && !isSendingRequest` : ce qui retient la feuille (annulation, vérification, renvoi d’un
     « Lancer maintenant » conservé, préparation d’annulation).
   - `draftChangedSinceSend` : compare la saisie courante à `sentDraft`, l’instantané pris quand l’envoi est parti
     (`submit`, `retry`). Une saisie retouchée après le départ (par exemple une proposition d’horaire arrivée tard) n’est
     jamais abandonnée par une sortie.
   - `close()` : la feuille se ferme, plus aucune lecture ni écriture ne s’applique, mais ce qui est affiché reste en
     place pendant que la feuille descend (même choix que `SchoolLessonReportWorkspace.close()` de #114).
   - `leaveWhileRequestIsSent()` : refuse hors envoi, refuse si la feuille est déjà fermée, refuse si la saisie a changé
     depuis l’envoi ; sinon `close()` et `true`. Il n’écrit rien, ne renvoie rien, ne supprime rien du coffre.
   - `transmit` : lève `isSendingRequest` avant l’envoi (`defer` le baisse), et **annonce une seule fois** la preuve
     quand elle arrive, y compris si la feuille a été quittée entre-temps (`guard request == generation, !invalidated
     else { announceConfirmedWrite(); return false }`). Rien n’est réécrit dans une feuille qui n’existe plus :
     `pending`, `writeConfirmed`, `successMessage`, `confirmedLesson` restent intacts, et la relecture de la leçon
     n’est pas lancée pour personne.
   - `announceConfirmedWrite()` : un seul point de publication de `.drivyLessonsDidChange` (les trois appels de
     `verify`/`transmit` passent par lui, même comportement qu’avant).
   - `notifications: NotificationCenter = .default` à l’initialisation (comme `SchoolLessonReportWorkspace`) : permet
     aux tests de compter les annonces sans dépendre du centre global partagé par les autres suites. Aucun appelant
     existant n’est modifié (valeur par défaut).
   - `clear()` remet `isSendingRequest` et `sentDraft` à zéro (perte d’accès, purge de portée).
2. **`SchoolPlanningView.swift`**
   - « Fermer » n’est plus désactivé que par `model.holdsScreen` (ou la préparation d’annulation) : pendant l’envoi
     d’une création ou d’un déplacement, il reste actif. Son action passe par `leaveWhileSending()`, qui ferme la feuille
     après `leaveWhileRequestIsSent()` — ou demande la confirmation habituelle (« Quitter sans conserver la saisie ? »)
     si une saisie a changé depuis l’envoi.
   - `interactiveDismissDisabled(blocksInteractiveDismissal)` : glissement autorisé pendant l’envoi d’une création ou
     d’un déplacement, refusé pendant une annulation, une vérification, une préparation d’annulation, une saisie non
     envoyée, ou une saisie modifiée depuis l’envoi.
   - Aucun nouveau texte à l’écran : ni « Réservée », ni « Déplacée », ni sous-titre. Pendant l’envoi, l’écran garde ce
     qu’il disait déjà (« Planification en cours », « Déplacement en cours »).

## Preuve par critère

| Critère de la tâche | Preuve | État |
| --- | --- | --- |
| Quitter pendant l’envoi d’une création | `aCreationBeingSentLeavesTheSheetFreeButConfirmsNothing` (`isSendingRequest && !holdsScreen`, sortie acceptée, coffre vidé une seule fois) | écrit, `NOT_EXECUTED` |
| Quitter pendant l’envoi d’un déplacement | `aMoveBeingSentLeavesTheSheetFreeToo` | écrit, `NOT_EXECUTED` |
| Annulation non quittable (capture en direct) | `aCancellationBeingSentKeepsTheSheetLocked` (`holdsScreen`, `!isSendingRequest`, sortie refusée, `confirmedCancellationLessonID` posé à la réponse) | écrit, `NOT_EXECUTED` |
| Rien de confirmé avant la preuve | `aCreationBeingSentLeavesTheSheetFreeButConfirmsNothing` (`!writeConfirmed`, `confirmedLesson == nil`, `successMessage == nil` pendant l’envoi) | écrit, `NOT_EXECUTED` |
| Confirmation après fermeture publiée une fois | `leavingWhileTheSchoolAnswersPublishesTheConfirmationOnce` (0 annonce avant la réponse, 1 après, 1 POST, coffre vidé une fois, feuille fermée sans état confirmé) | écrit, `NOT_EXECUTED` |
| Réponse perdue après fermeture : demande au coffre, aucun second POST | `aLostProofAfterLeavingKeepsTheRequestWithoutASecondPost` (coffre intact, 0 annonce, repère « À vérifier », réouverture en lecture seule, toujours 1 POST) | écrit, `NOT_EXECUTED` |
| Brouillon modifié non envoyé : sortie refusée | `aDraftChangedDuringTheSendIsNeverAbandonedByLeaving` (sortie refusée, feuille intacte, confirmation reçue ensuite, saisie gardée) | écrit, `NOT_EXECUTED` |
| Aucune sortie sans envoi | `nothingCanBeLeftBeforeARequestIsBeingSent` | écrit, `NOT_EXECUTED` |
| « Fermer » actif / glissement autorisé pendant l’envoi, verrouillés pour une annulation | `holdsScreen`, `blocksInteractiveDismissal`, `leaveWhileSending` | lecture du diff seulement |
| Aucun hôte ne perd sa fermeture | audit ci-dessus : `onDismiss` et `.drivyLessonsDidChange` inchangés ; l’annonce part désormais aussi après fermeture | lecture du diff seulement |
| Rendu, VoiceOver, grand texte, latence réelle de 15 s | Non compilé, non lancé | `NOT_EXECUTED` |

## Écarts, limites, décisions

- **`onConfirmedLesson` ne s’exécute pas si la personne est partie avant la réponse.** C’est le prix de la sortie
  demandée : l’Agenda ne fait pas surgir la fiche de la leçon devant quelqu’un qui a explicitement quitté. Rien n’est
  perdu : `.drivyLessonsDidChange` relit l’agenda et Aujourd’hui, la leçon y figure à son nouvel horaire. Choisir
  d’ouvrir la fiche malgré la sortie aurait volé le geste de la personne.
- **`SchoolLessonReportView` n’écoute pas `.drivyLessonsDidChange`** : un déplacement quitté pendant l’envoi puis
  confirmé après coup n’est pas relu dans cette fiche (elle s’est déjà relue à la fermeture). La fiche reste ouverte sur
  l’ancienne version jusqu’à sa prochaine relecture ; l’agenda et Aujourd’hui, eux, sont à jour. Corriger cela demande de
  modifier `SchoolLessonReportView.swift`, hors de la liste des fichiers autorisés : non fait, signalé.
- **Le glissement d’une feuille en cours d’envoi ne passe pas par `close()`** : le modèle reste vivant, la confirmation
  est appliquée et annoncée normalement (la vue n’existe plus, donc rien ne s’affiche). Le bouton « Fermer » et le
  chemin de confirmation, eux, ferment proprement. Écart cosmétique, sans effet sur le coffre ni sur les annonces.
- **Un renvoi (« Réessayer ») d’une création ou d’un déplacement déjà conservé est traité comme le premier envoi** : la
  demande est dans le coffre et la feuille peut être quittée. Une annulation conservée reste verrouillée à chaque renvoi.
- **« Lancer maintenant » (`startLessonNow`) retenu par le coffre n’est pas concerné** : sa réponse n’a pas de reçu AP72
  et le garder quittable aurait changé un comportement déjà validé (`pendingStartNowRetriedFromThePlanningSheetLeavesTheOutbox`).
- **Une erreur définitive survenue après la sortie ne s’affiche pas** : elle laisse la demande dans le coffre, le repère
  d’Aujourd’hui/Agenda la montre « À vérifier » et la feuille rouverte propose Vérifier / Abandonner. Aucun renvoi
  automatique n’existe, à aucun moment.
- Docs/`STATUS.md` non mis à jour : `docs/implementation/STATUS.md` est hors de la liste des fichiers autorisés.
- Aucune mesure, aucune capture, aucune exécution : rien n’est inventé.

## Vérifications lancées

- `git log -1 --format=%h` avant modification : `60adf11b` (conforme).
- `git status --short` : seul `package-lock.json` était déjà modifié avant la tâche (non touché, non commité).
- Relecture du diff complet `git diff 60adf11b` : accolades, `@MainActor`/`@Observable` conformes au fichier voisin,
  `try`/`await` (aucun `await` à droite d’un opérateur dans les `#expect`), types des `Task`, `defer` sur
  `isSendingRequest`, `switch` non modifiés, initialiseurs à valeur par défaut (aucun appelant cassé), aucun `self.`
  implicite dans une closure `@Sendable`.
- Compilation Swift, tests, IPA, rendu : `NOT_EXECUTED` (pas de chaîne Apple sur cette machine).
