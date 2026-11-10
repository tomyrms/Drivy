# Audit compte et notifications iOS — 10 novembre 2026

Lot natif : #441 (enregistrement APNs) et raccord #450 (portraits et intention de photo multi-appareils).

**NON COMPILÉ, NON EXÉCUTÉ** : aucun Swift n'a été compilé ni lancé sur cette machine (pas de chaîne Swift), aucune CI n'a été lancée
pour ce lot. Les tests ci-dessous sont écrits, pas passés. Aucune preuve APNs sur appareil physique : l'autorisation système et
l'inscription distante sont injectées dans les tests, jamais appelées.

## #441 — enregistrement APNs

Fichier : `apps/ios/Drivy/SchoolUI/SchoolPushCenter.swift`. L'API reste inchangée ; aucun secret ni jeton n'est journalisé.

### Constats avant correction

- Deux déclenchements rapprochés (connexion et retour du jeton APNs) lançaient deux PUT en vol. L'école fait tourner le secret de
  révocation à chaque PUT : si les réponses arrivaient dans l'ordre inverse de leur validation, le secret gardé n'était plus le
  courant, et la révocation anonyme (200 générique même sur un secret périmé) échouait en silence.
- `registerDevice` ignorait l'échec de sauvegarde du secret (`try?`) et rendait quand même vrai : le jeton était tenu pour enregistré
  sans secret durable.
- Une réponse de PUT arrivée après la fin de session, ou dans une autre session, posait `registeredToken`.
- `clearRecord(for:)` comparait le jeton seul : une révocation efface un record renouvelé pendant son attente.

### Corrections

- **File d'enregistrement** : `registerDevice` et `upload` passent par une file FIFO sur l'acteur principal (chaînage de `Task`). Un seul
  PUT est en vol. `upload` revérifie ses conditions dans son tour : trois déclenchements rapprochés donnent un seul PUT, les autres
  trouvent le jeton déjà enregistré. `registerDevice` direct refait un PUT à chaque appel (nouveau secret, remplace l'ancien).
- **Sauvegarde obligatoire** : si l'école rend un secret, `revocations.save` doit réussir ; sinon `registerDevice` rend faux, le jeton
  n'est pas « enregistré » et le prochain `upload` réessaie (un nouveau PUT, un nouveau secret). Une école sans secret efface le record
  périmé du même jeton.
- **Génération de session** : `sessionGeneration` avance à `sessionStarted` et à `sessionEnding`. `registeredToken` n'est posé que si la
  session est ouverte, que la génération est inchangée et que la sauvegarde a réussi.
- **Révocation exacte** : `revoke` capture le record complet avant l'attente et ne l'efface que si la relecture lui est égale (jeton ET
  secret). Un record renouvelé pendant l'attente reste.
- **Injection** : `SchoolPushCenter.init` accepte `systemStatus` et `registersForRemote` (défauts = comportement d'avant). `upload()` est
  internal, `deviceToken` et `registeredToken` sont `private(set)` pour les tests.

### Limite à connaître

Une réponse de PUT en vol pendant `sessionEnding` sauvegarde son secret hors session ; la révocation de fin de session est déjà partie.
La reprise (`resumePendingRevocation`, au lancement ou au retour au premier plan) révoque alors ce record. Entre-temps l'appareil reste
inscrit côté école : fenêtre courte, couverte par le test `aLateResponseAfterTheSessionEndedDoesNotMarkTheTokenRegisteredAndTheRevocationResumes`.

### Tests (nouveau fichier `apps/ios/DrivyTests/SchoolPushRegistrationTests.swift`)

École simulée à secret tournant : `revoked` n'est vrai que si le secret reçu par la route anonyme est le courant (la réponse reste un
200 générique), PUT retenus puis relâchés un à un, concurrence maximale mesurée.

- `closeCallbacksCoalesceIntoASingleSerializedPut` : callbacks rapprochés, un PUT, secret gardé = secret du serveur.
- `overlappingRegistrationsNeverRunTogetherAndTheKeptSecretIsTheLastOne` : deux enregistrements directs, jamais en parallèle, secret
  conservé = dernier enregistrement du serveur.
- `aLateResponseAfterTheSessionEndedDoesNotMarkTheTokenRegisteredAndTheRevocationResumes` : réponse tardive, panne de session, reprise.
- `aNewSessionOpenedDuringAPutRegistersAgainInsteadOfTrustingTheOldResponse` : changement de session pendant un PUT.
- `aTokenChangeDuringAPutEndsOnTheNewTokenWithItsOwnSecret` : changement de jeton pendant un PUT.
- `aKeychainThatCannotStoreLeavesTheDeviceUnregisteredUntilItWorksAgain` : panne du Trousseau (`refusesToStore`) puis reprise.
- `aRecordRenewedWhileTheRevocationWaitsIsKept` : la révocation ne retire pas un record renouvelé.
- `anExpiredSessionStillRevokesAnonymouslyWithTheLatestSecret` : session expirée, révocation anonyme effective du serveur simulé.
- `aStaleSecretWouldNotRevokeSoTheTestsProveTheOracleIsReal` : contre-épreuve, un secret périmé ne révoque pas.

## #450 — photo de profil multi-appareils

`photoVersion` est `nil` sans photo et peut revenir à une valeur déjà vue après un retrait puis un ajout ailleurs ; `photoGeneration`
est monotone. Le contrat serveur (champ additif) n'est pas dans cette branche : le client le lit s'il est présent, sinon il décode comme
avant.

### Constats avant correction

- Le cache `selfPhoto` était indexé par `photoVersion` seule : un appareil qui n'a pas vu l'état « sans photo » gardait l'ancienne image
  pour une photo remplacée portant la même version.
- Une lecture de photo tardive était rangée si la version coïncidait, sans autre identité.
- `baseStillMatches` (photo) comparait `photoVersion` seule : « sans photo → ajout ailleurs → retrait ailleurs → sans photo » rebasait
  silencieusement l'intention ancienne sur la base fraîche et l'envoyait.

### Corrections

- `SchoolSelfProfile.photoGeneration: Int?` (absent = `nil`, décode sans erreur) ; il voyage dans l'archive chiffrée d'intention
  (`base` est un `SchoolSelfProfile`) et dans `projecting`.
- `SchoolSelfProfile.hasSamePhotoState(as:)` : même personne, même `photoVersion`, et génération égale des deux côtés. **Génération d'un
  seul côté : non prouvé, donc différent** (comportement conservateur : l'intention est conservée, `.changed`, réconciliation existante).
  **Génération absente des deux côtés (ancienne API)** : la version seule décide, comme avant ; l'aller-retour « sans photo → photo →
  sans photo » y reste invisible. C'est la limite documentée.
- `SchoolProfilePhoto` porte `personID`, `version`, `generation` ; `matches(_ profile:)` exige les trois. `refreshSelfPhoto` relit si le
  cache ne correspond pas exactement et ne range une réponse tardive que si le profil confirmé désigne encore cette personne, cette
  version et cette génération. La fin d'une intention de photo range l'octet confirmé avec la génération de la réponse.
- `baseStillMatches` (photo) utilise `hasSamePhotoState`. Aucune refonte d'interface : l'éditeur reçoit toujours `photoVersion`.

### Conséquence à connaître

Une intention de photo archivée avant ce lot (sans génération) rencontrant une école qui publie la génération est traitée comme
changée une fois : le choix est gardé et la réconciliation existante s'applique. Rien n'est envoyé silencieusement.

### Tests (`SchoolSelfProfileIntentTests`, sélection `profile`)

- `aPhotoRemovedThenReplacedElsewhereIsReloadedEvenWhenItsVersionComesBack`
- `aDeviceThatSawTheRemovalShowsNoPhotoThenLoadsTheReplacement`
- `aLateReadOfTheOldPhotoNeverOverwritesTheReplacement`
- `aPhotoChoiceIsNeverSilentlyRebasedOntoAnotherPhotoStateWithTheSameVersion` (sans photo → ajout → retrait → sans photo)
- `anOldAPIWithoutGenerationKeepsTheVersionOnlyComparisonAsADocumentedLimit`
- `photoStateComparisonNeverAssumesEqualityWhenAGenerationIsMissing` (matrice, `personId`, décodage avec et sans le champ)
- `theEncryptedPhotoIntentKeepsItsBaseGenerationAndOlderArchivesStayConservative`

## Sélection

`scripts/ios/test-selection.sh` : `SchoolPushCenterTests` n'était dans aucune sélection nommée ; `SchoolPushCenterTests` et
`SchoolPushRegistrationTests` sont ajoutées à `unit_test_scope=reactivity`. #450 reste dans `unit_test_scope=profile`.
Sélections à lancer, sur Apple : `reactivity` et `profile`.

## Compilation de l'agenda (run 42778603013, d19e978f)

Terminé en **échec** à l'étape « Compiler l'application et les cibles nécessaires », erreur Swift dans le lot précédent (E),
non touché ici : `apps/ios/DrivyTests/SchoolIntentExactnessTests.swift:485` et `:494`,
`#expect(await server.writes.count == writes && await server.heldReads == 1)` et `… && await server.mutations == 1)` :
`await` à droite d'un opérateur dans `#expect` (« 'await' cannot appear to the right of a non-assignment operator », propriétés
d'acteur lues hors de l'acteur). Correction attendue : lire les deux valeurs dans des `let` avant le `#expect`. Les nouveaux tests de
ce lot suivent cette règle (aucun `await` à droite d'un `&&`).

## Limites

Rien n'a été vu tourner. Aucune interface modifiée (Impeccable et Uncodixfy sans objet). Aucun résultat APNs physique, GPS, batterie
ou VoiceOver.

## Oracle Python de sélection (retour natif 1/2)

Après intégration de 6e6870ee, `python -m unittest scripts/ios/test_test_selection.py` : 25 exécutés, **2 ÉCHECS**
(`test_unit_build_and_test_share_exact_selection_and_never_run_ui_or_ipad` pour le périmètre `reactivity`, et
`test_reactivity_selects_preferences_and_domain_scheduling_regressions`). Cause : `test-selection.sh` sélectionnait déjà
`SchoolPushCenterTests` et `SchoolPushRegistrationTests`, mais la constante `REACTIVITY_SUITES` du test Python ne les listait pas.
Correction : ces deux suites sont inscrites explicitement dans `REACTIVITY_SUITES`, aucune suite retirée, égalités inchangées.
Nouvelle exécution : 25 exécutés, **RÉUSSI** (code 0).

Limite : cela ne qualifie que la sélection de suites. Swift reste NON EXÉCUTÉ sur ce poste Windows ; `reactivity` et `profile`
restent à lancer sur Apple après la compilation de l'agenda.
