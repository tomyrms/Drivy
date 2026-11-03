# Lot B — #111 iOS : tests de pause, de reprise et d’arrêt d’un trajet (3 novembre 2026)

Branche `tomyrms/lotb-ios-capture-111`, base `96e7a37b` (`claude/lot-a-20261102`). iOS uniquement, côté tests : **aucun fichier de production n’est modifié**. Aucun push, aucune PR, aucun workflow, aucun commentaire d’issue, aucun déploiement. Les tests Swift n’ont pas été exécutés ici (pas de chaîne d’outils Apple sur cette machine Windows) : ils le seront par la campagne « Refonte » iOS lancée par le coordinateur.

## Ce qui existait déjà

### Symboles de production

| Symbole | Ce qu’il fait, vérifié par lecture |
| --- | --- |
| `SchoolCaptureSessionController.pause()` (`apps/ios/Drivy/SchoolCaptureCore/SchoolCaptureSessionController.swift`, l. 595) | Garde `state == .recording` et `active.handle` ; pose `state = .stopping` **et** `transition = .pausing` avant le premier point de suspension, puis scelle le segment localement (`active.local.pause`). |
| `SchoolCaptureSessionController.resume()` (l. 610) | Garde `canResume` (`state == .paused`, bail encore valable, pas d’arrêt demandé) ; pose `state = .preparing` avant `openSegment`, puis relit l’école **après** la réouverture (`confirmResumedCapture`, l. 638). |
| `SchoolCaptureSessionController.stopAndSynchronize()` (l. 675) | Scelle l’arrêt local (`finish`, l. 1016 → `finishOnce`, l. 1025 → `SchoolCaptureLocalCoordinator.stop`), puis seulement `scheduleSynchronization` (l. 795) lance le transfert dans une tâche détachée : l’appelant repart dès que l’écriture est durable. |
| `SchoolCaptureLocalCoordinator.pause(handle:endedAt:reason:)` (l. 87) | Barrière locale : `closeAdmission()`, attente des écritures en cours, `store.sealSegment`. Aucun réseau. |
| `SchoolCaptureLocalCoordinator.stop(captureID:stoppedAt:reason:)` (l. 102) | Attend `while stopping` le scellement d’une pause en cours, puis `store.stopAndSeal` : l’ordre pause → arrêt est garanti par la file locale. |
| `SQLCipherSchoolCaptureStore.sealSegment` (l. 480) | Écrit le segment (`endReason: PAUSE`, `endedAt`) et passe le trajet en `.paused`. **N’insère aucune mutation.** |
| `SQLCipherSchoolCaptureStore.stopAndSeal` (l. 494) / `sealCapture` (l. 579) | Une seule opération `stopCapture` par trajet : `stopOperationID` est conservé, un second appel rend la mutation existante au lieu d’en créer une. Le manifeste reprend l’`endReason` de chaque segment. |
| `SchoolCaptureTransferCoordinator.sendPersisted` (l. 164) + `SchoolCaptureClient.perform` (l. 406) | `markAttempted` puis envoi avec `Idempotency-Key: mutation.id` : une reprise garde la même clé et le même corps. |
| `SchoolCaptureTransferCoordinator.transferAvailableData` (l. 89) | Trie les faits éligibles : `stopCapture` **avant** les `uploadChunk`. |
| `SchoolCaptureSessionController.resumePendingSynchronizations(client:scope:)` (l. 703) et `installNetworkMonitor` (l. 764) | Rejoue les trajets scellés ; c’est exactement la méthode que le moniteur réseau appelle au retour du réseau (`retryPendingSynchronizations`, l. 759). |

### Tests existants (réutilisés par leurs doublures, non modifiés)

`apps/ios/DrivyTests/SchoolCaptureLifecycleTests.swift` : `pauseThenResumeNeverPresentAnIntermediateState`, `resumingReopensTheSegmentWithoutWaitingForTheSchool`, `endingTheLessonDuringAResumeReplacesTheTransitionOnScreen`, `closingTheLessonDoesNotCancelDurableSynchronization`, `lostFinalizationResponseRetriesTheSameDurableOperation`. Aucun ne couvre le double appui ni la coupure réseau autour d’une pause ou d’un arrêt.

## Ce qui a changé

| Fichier | Rôle |
| --- | --- |
| `apps/ios/DrivyTests/SchoolCaptureLifecycleReactivityTests.swift` (nouveau) | 5 tests (#111) avec les doublures du fichier voisin, recopiées : `ReactivityFixture` (même montage : coffre SQLCipher temporaire, autorisation signée Ed25519, bail vérifié, `adoptAndStart`), `ReactivitySource` (même fausse source GPS), `ReactivityServer` (même transport en mémoire, plus `setOffline`, `holdTransfers`/`releaseTransfers` et l’enregistrement de chaque requête). Deux lectures ajoutées hors du magasin partagé, par `CipherConnection` : `segments()` (lignes `segment`, ordre des index) et `mutations(kind:)` (opérations durables, acquittées comprises). |
| `docs/implementation/lot-b-capture-tests-111-20261103.md` | Ce document. |

`SchoolCaptureLifecycleTests.swift` n’est pas touché : ses doublures y sont `private`, donc recopiées ici (mêmes types, mêmes signatures, même transport), conformément à la consigne.

`docs/implementation/STATUS.md` n’est pas modifié : la tâche limite les fichiers modifiables au test et à ce document.

## Preuve par critère

| Critère demandé | Test | Symbole de production vérifié | Ce que le test affirme |
| --- | --- | --- | --- |
| 1. Double appui sur pause : un seul segment fermé, une seule mutation de pause en file | `aSecondTapOnPauseClosesOneSegmentAndQueuesNoPauseOperation` | `pause()` (l. 595), `SchoolCaptureLocalCoordinator.pause` (l. 87), `SQLCipherSchoolCaptureStore.sealSegment` (l. 480) | Deux appuis concurrents : une seule ligne `segment`, `endReason = PAUSE`, `endedAt` posé, trajet `.paused`, `stopOperationID == nil`, `manifest == nil` ; la file reste **vide** avant et après. **Écart** : il n’existe aucune mutation de pause (voir plus bas), donc « une seule mutation de pause » se vérifie comme « aucune mutation de pause, et rien de dupliqué ». |
| 2. Double appui sur reprise : un seul segment rouvert | `aSecondTapOnResumeReopensOnlyOneSegment` | `resume()` (l. 610), `openSegment` (l. 880), `SchoolCaptureLocalCoordinator.begin` (l. 31) | Deux appuis concurrents : deux lignes `segment` (`segmentIndex` 0 puis 1), la seconde `reason = RESUME` et non scellée, `startCount == 2`, état `.recording` sans transition. |
| 3. Pause sans réseau puis retour du réseau : pause locale immédiate, mutation au retour avec la même clé, une seule fois | `aPauseWithoutNetworkAppliesLocallyAndLeavesNoPauseOperationBehind` | `pause()`, `sealSegment`, `resumePendingSynchronizations` (l. 703) | Avec le transport coupé (`URLError.notConnectedToInternet`) : état `.paused` immédiat, segment `PAUSE`, **aucune requête portant une clé d’idempotence** pendant la pause ; le seul fait en file est le lot des positions scellées (`[.uploadChunk]`). Au retour du réseau : toujours aucune requête de fait durable, aucun segment rouvert (`startCount == 1`), aucun `stop`/`finalize`. Le second membre du critère (une mutation de pause envoyée avec la même clé) **ne peut pas exister** : il est consigné en `withKnownIssue` (voir « Écarts »). |
| 4. Arrêt sans réseau puis retour du réseau : arrêt local immédiat, GPS arrêté avant tout réseau, synchronisation au retour, aucun segment rouvert, aucune seconde écriture | `aStopWithoutNetworkStopsTheGPSBeforeAnyNetworkAndLeavesOnceWhenTheNetworkReturns` | `stopAndSynchronize()` (l. 675), `finishOnce` (l. 1025), `scheduleSynchronization` (l. 795), `stopAndSeal` (l. 494), `sendPersisted` (l. 164), `resumePendingSynchronizations` (l. 703) | Le transport est suspendu (`holdTransfers`) : `stopAndSynchronize()` rend `true` alors qu’une requête est encore en vol, source arrêtée, trajet `.stopped` avec manifeste et `stopOperationID`. Le réseau est ensuite coupé puis rendu : une **seule** opération `stopCapture` durable, toutes les requêtes `stop` portent la même `Idempotency-Key` (celle de cette opération), une seule finalisation, `finalizedSyncState == .synced`, `startCount == 1`, une seule ligne `segment`. |
| 5. Pause puis arrêt rapprochés sans réseau : ordre conservé à l’envoi | `aPauseFollowedByAStopWithoutNetworkKeepsTheirOrderOnSend` | `SchoolCaptureLocalCoordinator.stop` (l. 102, attente `stopping`), `sealCapture` (l. 579), `transferAvailableData` (l. 89, tri arrêt avant lots) | Pause en cours puis arrêt : `state == .saved`, une seule ligne `segment` (`endReason = PAUSE`), manifeste `["PAUSE"]`, une seule opération `stopCapture` ; au retour du réseau, la requête `stop` précède la requête de lot (`PUT …/chunks/…`) et le trajet finit `.synced` sans segment rouvert. |

## Écarts trouvés (aucun code de production modifié)

1. **La pause n’a aucune opération réseau.** `SchoolCaptureMutationKind` (`apps/ios/Drivy/SchoolCaptureAPI/SchoolCaptureMutations.swift`, l. 3) ne contient que `assessDevice`, `recordChoice`, `startCapture`, `uploadChunk`, `stopCapture`, `finalizeCapture` ; `SchoolCaptureClient` n’expose aucune route de pause, et `apps/api/src/capture-contracts.ts` ne décrit la pause que comme `endReason: PAUSE` dans le manifeste d’arrêt. Une pause est donc purement locale : elle scelle le segment et passe le trajet en `.paused` dans le coffre, et l’école ne l’apprend qu’au moment de l’arrêt. Le critère 3 tel qu’il est libellé (« la mutation part au retour avec la même clé d’idempotence qu’à la première tentative ») décrit un mécanisme qui n’existe pas ; il est consigné par un `withKnownIssue` dans le test 3, avec le comportement réel vérifié juste au-dessus. C’est un écart de contrat, pas un défaut de ce lot : rien n’est inventé côté app.
2. **La reprise n’a pas non plus d’opération réseau** (même raison) : elle rouvre un segment localement puis relit le trajet (`confirmResumedCapture`). Le test 2 vérifie donc le nombre de segments, pas un envoi.
3. **Le critère 1 mentionne « une seule mutation de pause mise en file ».** Il n’existe pas de telle mutation : le test vérifie l’invariant réel — un seul segment scellé et une file vide avant/après le double appui (avec des positions, la seule écriture ajoutée est le lot `uploadChunk` du scellement, vérifié dans le test 3).
4. **Le retour du réseau n’est pas observé par `NWPathMonitor` dans les tests.** Le moniteur (`installNetworkMonitor`, l. 764) ne se simule pas de façon déterministe sur un runner ; les tests 3, 4 et 5 appellent `resumePendingSynchronizations(client:scope:)`, qui est exactement la méthode que `pathUpdateHandler` déclenche au retour du réseau. Le mode avion réel et un vrai changement de chemin réseau restent `NOT_EXECUTED`.

## Vérifications exécutées (3 novembre 2026)

| Vérification | Résultat |
| --- | --- |
| `git log -1 --format=%h` avant modification | `96e7a37b` (base attendue) |
| Compilation Swift / `xcodebuild test` | **NOT_EXECUTED** : aucune chaîne d’outils Apple sur cette machine Windows. Le coordinateur compile l’IPA d’essai et lance la campagne de tests sur `macos-26` / Xcode 26.6. |
| Exécution des 5 tests | **NOT_EXECUTED** (même raison). Aucun résultat ne peut être annoncé avant la campagne. |
| Équilibrage syntaxique du fichier (accolades, parenthèses) et fins de ligne | Contrôlé : 84/84 accolades, 330/330 parenthèses, LF uniquement (`.gitattributes` : `eol=lf`). Ce n’est pas une compilation. |
| Relecture du diff complet (`git diff 96e7a37b`) | Fait. Points relus : accolades et fermetures de `Task`/`#expect`/`withKnownIssue` ; `await` sur chaque appel d’acteur (`setOffline`, `holdTransfers`, `releaseTransfers`, `requests`, `isHoldingTransfers`, `store.*`) ; `try` sur chaque appel `throws` (`segments()`, `mutations(kind:)`, `CipherConnection`, `#require`) ; `self.` inutile dans les closures de `ReactivitySource` et `ReactivityServer` (mêmes formes que le fichier voisin) ; optionnels comparés avec `?? ""` ou `!= nil` plutôt qu’avec `contains` sur `String?` ; `Sendable` des doublures (acteur pour le transport, `@MainActor` pour la source et le montage) ; pas de `switch` ajouté ; aucune API iOS plus récente que celles du fichier voisin ; aucun paquet ajouté. |

## Ce qui n’est pas fait ou pas prouvé

- Les 5 tests n’ont pas tourné : ni succès ni échec ne sont affirmés. `NOT_EXECUTED`.
- Le double appui est reproduit par deux tâches concurrentes sur le `MainActor`, pas par deux touchers réels : la sérialisation du `MainActor` et la garde posée avant le premier `await` rendent l’issue déterministe, mais le geste physique (et un éventuel délai entre les deux appuis) n’est pas mesuré.
- Le retour du réseau est simulé par le transport (`setOffline`) et par l’appel direct à `resumePendingSynchronizations` : `NWPathMonitor`, le mode avion et la bascule Wi-Fi/cellulaire ne sont pas exercés.
- Aucune mesure de latence, de batterie ou de mémoire n’est faite ; rien de tel n’est affirmé.
- La file d’envoi n’a pas été observée au-delà de ce que le coffre expose (`segment`, `mutation`) : le contenu réellement reçu par l’école n’est vérifié que par les requêtes enregistrées et les réponses du transport synthétique.
