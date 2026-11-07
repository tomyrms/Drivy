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

## Retour correctif 1/2 (revue groupée sur 9dc90566)

- **#426, sélecteur d'élèves.** `loadCandidates`, `retryCandidates` et `candidates` suivent maintenant `accessRevoked` / `accessEpoch` : une page, une erreur ou une annulation arrivées après un refus ne réécrivent ni `learners` ni `candidateRead` ; `candidates` est vide tant que l'accès est retiré ; aucune relance n'est possible. Après une lecture autorisée, `restoreCandidatesIfNeeded` et `candidateRead` remis à zéro par le refus permettent une nouvelle lecture complète. Un refus renvoyé par l'annuaire lui-même (droit distinct du cours) reste une erreur de lecture du sélecteur, pas une révocation du cours.
- **#425, feuille de texte intégral.** `SchoolCaptureReplayView.rebuildTimeline()` réconcilie aussi `reading` via `SchoolReplayTimeline.refreshed(_:)` : texte corrigé, ou feuille fermée si l'observation a disparu (retirée / privée). `sheet(item:)` est lié à l'identifiant : elle se met à jour sur place, sans changement visuel.
- **Preuves ciblées (NON EXÉCUTÉES).** `SchoolCourseAccessRevocationTests` : `aDirectoryPageArrivingAfterTheRefusalNeverBringsTheNamesBack` (page, erreur et annulation tardives) et `candidatesReadAgainAfterAnAuthorisedReadFollowingTheRefusal` ; `SchoolCaptureReplayTests.reopeningRereadsObservationsWhileKeepingUnchangedMeasurements` couvre désormais `refreshed` (texte à jour puis `nil`). Le comportement de `@State reading` dans la vue elle-même n'a pas de test d'interface : la preuve porte sur la fonction de réconciliation.
- **Sélection.** Inchangée : `gps` (replay) et `agenda` (cours, 11 tests dans `SchoolCourseAccessRevocationTests`). Le contrôle `test_test_selection.py` (25 OK) n'est pas relancé : aucun script de sélection modifié depuis.
- **Skills UI.** Impeccable et Uncodixfy sont bien présents (`~/.codex/skills`) ; le rapport précédent les disait absents à tort. Les deux ont été lus avant le delta UI ; ce delta ne change aucun rendu (réconciliation d'état, ni copie ni mise en page).

## Fichiers

- `apps/ios/Drivy/SchoolCaptureUI/SchoolCaptureReplayWorkspace.swift`
- `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseAttendanceWorkspace.swift`, `SchoolCourseEnrollmentWorkspace.swift`
- Tests : `DrivyTests/SchoolCaptureReplayTests.swift` (3 nouveaux, 1 assertion adaptée : `replayReads == pagesRead + 1`), `DrivyTests/SchoolCourseAccessRevocationTests.swift` (nouveau, 11), `DrivyTests/SchoolCourseSheetQueueTests.swift` (serveur synthétique étendu).
- `scripts/ios/test-selection.sh` et `test_test_selection.py` : `unit_test_scope=agenda` reçoit `SchoolCourseAccessRevocationTests`, `SchoolCourseSheetQueueTests`, `SchoolCourseIntentPersistenceTests` (aucun changement de workflow). `gps` couvre déjà `SchoolCaptureReplayTests`.

## À lancer sur le runner Apple (NON EXÉCUTÉ)

- `unit_only=true`, `unit_test_scope=gps` : `SchoolCaptureReplayTests` — `reopeningRereadsObservationsWhileKeepingUnchangedMeasurements`, `observationRevalidationRefusedPurgesTheCachedReplayButAnOutageKeepsIt`, `lateObservationResponseCannotReviveAnInvalidatedReplay`, `reopeningAnUnchangedReplayKeepsItsPagesAndOnlyRereadsItsVersion` (adapté), puis le reste de la suite.
- `unit_only=true`, `unit_test_scope=agenda` : `SchoolCourseAccessRevocationTests` (9), `SchoolCourseSheetQueueTests`, `SchoolCourseIntentPersistenceTests`, `SchoolCourseClientTests`.

## Contrôles exécutés ici (Windows)

- `python -m unittest scripts/ios/test_test_selection.py` : 25 tests, OK.
- Swift : **NON COMPILÉ, NON EXÉCUTÉ** (pas de Xcode). Aucune preuve physique ni simulateur.
- Impeccable et Uncodixfy : présents dans `~/.codex/skills` (correction du rapport initial) ; le seul delta UI est une réconciliation d'état sans effet visuel.
