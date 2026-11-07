# Audit de confidentialité iOS — lot B (#425, #426)

Base : `2a801eaf`. Branche `tomyrms/audit-confidentialite-20261107`. Aucun backend, aucune UI modifiée : la correction est dans l'état de présentation (les vues lisent déjà `sheet`, `roster`, `errorMessage` et `observations`).

## #425 — le replay relit les observations à chaque ouverture

**Cause.** `isUnchanged` ne compare que `capture.version` et `syncState`. Une note corrigée, retirée ou passée en privée ne les change pas : le replay rouvert depuis le cache gardait l'ancienne copie.

**Correction** (`SchoolCaptureReplayWorkspace`).
- Le cache est conservé, mais sa validité est séparée en deux : les mesures valent tant que version et synchronisation sont identiques ; les observations sont **toujours** relues auprès de l'école (`refreshObservations`).
- Aucune route ne sert les observations seules (elles voyagent dans les pages du replay, ancrées sur les mesures) et le backend est hors périmètre. La relecture parcourt donc les pages mais ne retient que les annotations : `fragments`, `matchedRoute` et l'identité des mesures ne sont pas reconstruits. Si les pages ne correspondent plus au cache (qualité, nombre de mesures, leçon, curseur répété), le trajet est relu en entier.
- `observations` est remplacé, `contentRevision` incrémenté et le cache mis à jour seulement si le contenu diffère. Carte, liste, rail et sélection suivent `observations`.
- Refus 401/403/404 pendant la relecture : purge existante (`failMeasurements` : cache, mesures, observations). Panne transitoire : la copie autorisée reste, le message d'erreur est visible. Une relecture partie avant `invalidate()` / `stopLoading()` est ignorée (`current(request)`).

**Limites assumées.**
- Les observations en cache s'affichent dès l'ouverture, puis sont remplacées à la revalidation. Hors connexion, la copie locale reste affichée (traitement hors ligne prévu, pas d'effacement à distance promis).
- Coût : une lecture de pages de plus à chaque réouverture (le même nombre que le chargement initial, sans reconstruction). Une route d'observations dédiée ou une révision d'annotations côté API l'éviterait ; hors lot.

## #426 — refus d'accès à un cours

**Cause.** Les `catch` de `SchoolCourseAttendanceWorkspace.load` et `SchoolCourseRosterWorkspace.load` traitaient toute erreur comme une panne : `sheet`, `roster` et droits restaient.

**Correction.**
- `SchoolCourseAccess.isDenied` : 401, 403, 404 (`SchoolPlanningFailure.unauthorized/forbidden/notFound`) ; rien d'autre.
- Feuille : `revokeAccess` vide `sheet`, séance, files en mémoire, refus affichés et annonce ; positionne `accessRevoked` et le message. `rights` devient `nil` : aucun mode (appel, règlements, validation). `submit`, `retry`, `abandon` et `drain` ne font plus rien.
- Inscrits : `roster`, confirmation et élèves proposés sont vidés ; `enroll` et `cancel` sont inertes.
- Un refus sur une **écriture** (feuille ou inscrits) vaut refus d'accès ; il ne supprime plus l'intention de la file durable.
- Ordre : `accessEpoch` est incrémenté à chaque refus. Lecture ou écriture partie avant lui : sa réponse (succès comme erreur) est écartée, sans annonce ni remise de la feuille.
- Reprise : la première lecture autorisée lève `accessRevoked`, relit le coffre et rend les gestes conservés « à reprendre » (`restoredMessage`) ; rien n'est renvoyé de soi-même, la reprise reste soumise aux droits courants.
- Gestes financiers durables : le coffre n'est jamais vidé par un refus. Ils ne sont plus visibles ni envoyables tant que l'accès est retiré.

**Limites.** Les élèves « semences » restent en mémoire dans `seed` (jamais affichés tant que l'accès est retiré). La vue affiche déjà le message et « Réessayer » quand `sheet` est nul ; aucune capture n'a été vue, pas de recette native de la révocation.

## Fichiers

- `apps/ios/Drivy/SchoolCaptureUI/SchoolCaptureReplayWorkspace.swift`
- `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseAttendanceWorkspace.swift`, `SchoolCourseEnrollmentWorkspace.swift`
- Tests : `DrivyTests/SchoolCaptureReplayTests.swift` (3 nouveaux, 1 assertion adaptée : `replayReads == pagesRead + 1`), `DrivyTests/SchoolCourseAccessRevocationTests.swift` (nouveau, 9), `DrivyTests/SchoolCourseSheetQueueTests.swift` (serveur synthétique étendu).
- `scripts/ios/test-selection.sh` et `test_test_selection.py` : `unit_test_scope=agenda` reçoit `SchoolCourseAccessRevocationTests`, `SchoolCourseSheetQueueTests`, `SchoolCourseIntentPersistenceTests` (aucun changement de workflow). `gps` couvre déjà `SchoolCaptureReplayTests`.

## À lancer sur le runner Apple (NON EXÉCUTÉ)

- `unit_only=true`, `unit_test_scope=gps` : `SchoolCaptureReplayTests` — `reopeningRereadsObservationsWhileKeepingUnchangedMeasurements`, `observationRevalidationRefusedPurgesTheCachedReplayButAnOutageKeepsIt`, `lateObservationResponseCannotReviveAnInvalidatedReplay`, `reopeningAnUnchangedReplayKeepsItsPagesAndOnlyRereadsItsVersion` (adapté), puis le reste de la suite.
- `unit_only=true`, `unit_test_scope=agenda` : `SchoolCourseAccessRevocationTests` (9), `SchoolCourseSheetQueueTests`, `SchoolCourseIntentPersistenceTests`, `SchoolCourseClientTests`.

## Contrôles exécutés ici (Windows)

- `python -m unittest scripts/ios/test_test_selection.py` : 25 tests, OK.
- Swift : **NON COMPILÉ, NON EXÉCUTÉ** (pas de Xcode). Aucune preuve physique ni simulateur.
- Impeccable et Uncodixfy : non installés ici ; aucune modification d'interface n'a été faite.
