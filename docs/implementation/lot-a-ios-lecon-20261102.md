# Lot A iOS : fin de leçon, trajets et démarrage (2 novembre 2026)

Branche `claude/lot-a-ios-lecon` (base `0312e768`), issues #114, #115 et #111, côté iOS seulement. Aucune PR, aucun déploiement, aucun test exécuté : la compilation est prouvée par l'IPA d'essai, les tests écrits attendent la campagne « Refonte · iOS » lancée par le coordinateur.

## Compilation

| Preuve | Résultat |
| --- | --- |
| IPA d'essai · iLoader, commit `b05e1aba`, run `41518179094` | PASS |
| Tests Swift écrits (11) | NOT_EXECUTED |
| Recette physique (GPS, latence réelle de 15 s, VoiceOver, mode avion, mesures de rendu et de mémoire) | NOT_EXECUTED |

## #114 : fin de leçon, bilan, évaluations, partage

### Existait déjà (audit)

- Saisie qui survit à la réponse : `SchoolLessonReportWorkspace` (`confirmedReport`, `isSendingReport`), test `typingDuringTheReportSendIsKeptAndTheSheetStaysOpen` ; refus de l'envoi N qui garde le texte : `rejectedReportNeverClosesAndKeepsItsText`.
- Relecture échouée qui n'efface rien : `aFailedRereadNeverErasesTheReportAlreadyShown` ; second appui sans renvoi : `aSecondTapNeverResendsTheReportTheSchoolJustConfirmed`.
- Partage : `optimisticSharing`, réglages envoyés un à un (`sharingChangesKeepTheReportOpenAndAreSentOneAtATime`) ; panne de stockage locale signalée (`localDraftError`).
- Constat de fin : arrêt local du trajet avant tout réseau (`finishLesson` dans `SchoolLessonReportView`), intention écrite dans la file chiffrée avant l'envoi (`prepare`), reçu vérifié avant de conclure (`SchoolLessonReportClient.send`).

### Ce qui change

- `SchoolLessonReportWorkspace.isSendingClosure` : fin de leçon ou absence tout juste envoyée. Elle ne retient plus la fiche (`holdsScreen`) ; l'écran reste sur « Fin de la leçon en cours… » avec un bouton « Fermer ».
- `leaveWhileClosureIsSent()` : quitte la fiche, la demande reste dans la file chiffrée. Refusé s'il reste une saisie locale.
- Si l'école répond après la fermeture, la confirmation est annoncée (`drivyLessonsDidChange`) : Aujourd'hui, l'agenda et le dossier se relisent ; `SchoolHomeView` marque aussi le trajet arrêté de la leçon comme terminé (`noteLessonCompleted`).
- Rien n'est confirmé avant la preuve : la leçon reste « PLANIFIÉE » côté fiche, aucune annonce n'est faite sans réponse de l'école, une réponse sans preuve laisse la demande en file, retrouvée « à vérifier » à la réouverture, sans renvoi.
- L'aperçu du trajet de la fiche ne retient plus la lecture du bilan (voir #115).

### Preuve par critère

| Critère | État |
| --- | --- |
| Rédaction et niveau fluides à 15 s de latence ; aucune perte à la fermeture | Logique prouvée par tests existants (saisie N+1, brouillon chiffré) ; latence réelle non mesurée |
| Sauvegarde N, édition N+1, réponses inversées ; refus de N | Prouvé par les tests existants cités plus haut |
| Fin confirmée puis relecture échouée : ni constat ni publication recréés ; double appui ; reprise sans doublon | Nouveaux tests `SchoolLessonClosureReactivityTests` (un seul POST après fermeture, vérification, réouverture) ; non exécutés |
| L'élève ne voit que le contenu autorisé ; niveaux provisoires distingués | Inchangé, décidé par l'école ; non rejoué |
| Panne de stockage, révocation, deux appareils, changement de leçon | Stockage et révocation couverts par les tests existants ; deux appareils non prouvé |

## #115 : historique, replay, suivi de synchronisation

### Existait déjà (audit)

- Cache mémoire `SchoolReplayCache` des replays synchronisés (3 au plus, par compte, école, adhésion et époque, vidé à la déconnexion et à tout refus) : `reopeningAnUnchangedReplayKeepsItsPagesAndOnlyRereadsItsVersion`.
- Lecture, pause, vitesse et curseur locaux (`SchoolReplayPlayer`, jamais soumis au réseau) ; instant, vitesse et état conservés à l'arrivée d'une géométrie tardive : `lateMatchedGeometryPreservesPlaybackInstantSpeedAndPlayState`, `seekingIsImmediateAndPlaybackFollowsOneClock`.
- Pages tardives sans saut ni raccourcissement : `refreshKeepsTheOldCompleteReplayUntilEveryNewPageArrives`.
- Suivi « À envoyer » (`SchoolCaptureHistoryWorkspace`) : mêmes opérations durables réémises, jamais de lot dupliqué ; un refus purge le cache du replay.

### Ce qui change

- L'aperçu du trajet de la fiche de leçon (`track`, `trackAnchors`) se télécharge page après page sans retenir la fiche, le bilan ni ses commandes : il part avec les autres lectures, se publie à son arrivée (`publishPreview`), et une lecture plus récente, la fermeture ou la perte d'accès l'abandonnent. Le replay reste ouvrable depuis la liste des trajets dans l'intervalle ; un tracé absent reste vide, jamais inventé.
- Un trajet synchronisé déjà lu garde son tracé en mémoire de la fiche (`previewMemo`), tant que l'école n'en change pas la version ; jamais écrit sur le disque, perdu à la fermeture de la fiche, vidé à `invalidate()`. Un trajet encore en envoi ou partiel est relu à chaque fois.
- Un autre jeu de trajets efface l'aperçu affiché sans attendre le suivant.

### Preuve par critère

| Critère | État |
| --- | --- |
| Même trajet rouvert sans téléchargement intégral ; premier trajet décrit honnêtement | Replay : cache existant et son test. Aperçu de la fiche : `aSyncedTripPreviewIsNotDownloadedAgainWhileTheSchoolKeepsItsVersion` (non exécuté) |
| Commandes locales réactives hors connexion ; instant et vitesse conservés | Tests existants du lecteur ; réactivité réelle non mesurée |
| Pages anciennes, résultat partiel puis complet, erreurs serveur sans saut ni faux segment | Tests existants de `SchoolCaptureReplayTests` |
| Plusieurs essais de synchronisation, fermeture et reprise, changement de droits sans doublon ni fuite | Tests existants (`closingTheLessonDoesNotCancelDurableSynchronization`, `refusalWhilePollingPurgesThePreviouslyLoadedPrivateReplay`) |
| Mesures de rendu, vidéo synthétique, mémoire | NON PROUVÉ : aucune mesure faite |

Reste : trajets encore en envoi non mis en cache dans `SchoolReplayCache` (volontaire : leurs pages changent) ; mesures.

## #111 : démarrage, pause, reprise, arrêt

### Audit

- Pause, reprise et arrêt agissent déjà sur l'appareil sans attendre l'école : `SchoolCaptureSessionController.pause`, `resume` (bail local, relecture de l'école ensuite), `stopAndSynchronize` ; tests `pauseThenResumeNeverPresentAnIntermediateState`, `resumingReopensTheSegmentWithoutWaitingForTheSchool`, `endingTheLessonDuringAResumeReplacesTheTransitionOnScreen`, `closingTheLessonDoesNotCancelDurableSynchronization`.
- Démarrage : `SchoolCapturePreparationWorkspace.startInOneStep` enchaîne les contrôles (leçon, accord, localisation, mesure, diagnostic, autorisation) l'un après l'autre. Chaque étape annonce son libellé et rien n'est déclaré actif avant l'autorisation, mais les lectures restent séquentielles.

### Résultat

- Aucun changement de code. Reprendre la file de démarrage sans appareil physique serait fragile (autorisations, bail, position exacte) : non fait.
- Tests prévus mais non ajoutés : double appui sur pause ou reprise, pause et arrêt sans réseau suivis d'un retour du réseau (même clé d'idempotence, aucun segment rouvert). L'ajout dans `SchoolCaptureLifecycleTests.swift` a été refusé pendant la session et n'a pas été retenté ; à reprendre sur instruction.
- Cases non prouvées : latence de 15 s, mode avion réel, perte de bail ou de droit en situation, retour vers d'autres pages avec trajet actif.

## Tests écrits, non exécutés

- `apps/ios/DrivyTests/SchoolLessonClosureReactivityTests.swift` (6) : `aCompletionBeingSentLeavesTheSheetFreeButConfirmsNothing`, `nothingCanBeLeftBeforeAClosureIsBeingSent`, `leavingWhileTheSchoolAnswersKeepsTheRequestThenAnnouncesItsConfirmation`, `aFinishWithoutProofStaysRecoverableAfterTheSheetWasLeft`, `anAbsenceBeingSentDoesNotHoldTheSheetEither`, `aSharingChangeOrAReportSendIsNeverTakenForAClosure`.
- `apps/ios/DrivyTests/SchoolLessonPreviewReactivityTests.swift` (5) : `theLessonOpensAndStaysEditableWhileTheTripPreviewIsStillDownloading`, `aSyncedTripPreviewIsNotDownloadedAgainWhileTheSchoolKeepsItsVersion`, `aTripThatMayStillChangeIsAlwaysReadAgain`, `aClosedSheetNeverReceivesALatePreview`, `aNewerReadReplacesAPreviewStillInFlightAndPublishesItOnce`.

## À valider ou à surveiller

- Une fin de leçon refusée définitivement par l'école après la fermeture de la fiche ne se voit plus que par la leçon qui reste « à terminer » dans Aujourd'hui ; rien n'est faussement confirmé.
- Le bouton « Fermer » de l'attente de fin apparaît dès que la demande est dans la file chiffrée ; son rendu n'a jamais été vu tourner.
- Les anciens tests qui lisaient `track` ou `information` juste après `load()` doivent être relus à la campagne : l'aperçu arrive maintenant après la fiche (`previewSettled()` pour l'attendre).