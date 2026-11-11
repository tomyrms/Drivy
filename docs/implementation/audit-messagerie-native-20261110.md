# Audit messagerie native F — #428, #435, #436, #445 (10 novembre 2026)

Base : `audit-identite-20261107`, après la fusion de 6a7ac8d0 (compléments média, parcours média non réécrit). Le serveur F est livré avant (`audit-messagerie-serveur-20261110.md`).

## Statut de qualification

**NON COMPILÉ / NON EXÉCUTÉ localement** : cette machine Windows n'a pas de toolchain Swift. Aucun test Swift ni UI n'a tourné. Tout ce qui suit est écrit et relu, pas qualifié. Les tests sont à lancer par le coordinateur sur runner Apple. Les scénarios UI média et READINESS gardent leurs budgets : non repris.

## #428 — reprise unique des envois

- `MessagingWorkspace.refreshVisible` n'appelle plus `outbox.flushPending`. Actualisation, retour réseau et retour actif passent par la même route : `restoreDurableSends()` (rattache les entrées du journal chiffré inconnues de la mémoire, dans l'ordre du journal), `resumeSends()` (repasse `.offline` et `.uncertain` hors vol en `.queued`, même clientMessageID), puis un exécuteur par conversation.
- M1 incertain confirmé au retour (le serveur déduplique) : accepté, M2 part ensuite. M1 encore incertain : M2 reste `.queued`, jamais envoyé avant lui. Les autres conversations sont indépendantes. Un refus définitif passe en `.failed`, sort de la file, ne retient pas le suivant et n'est pas rejoué.
- Une panne de protection ou une limite d'appareils rencontrée pendant la reprise est signalée (`sendBlock`), jamais présentée comme un succès.
- `MessagingOutboxCoordinator` : `retry` renvoie `.waiting` si l'envoi est déjà en vol ; `flushPending` retient les suivants d'une même conversation après une panne, pas après un refus définitif.
- Tests : `DrivyTests/MessagingSendRecoveryTests.swift` (7 tests, vrais workspace et coordinateur, transport scripté par message).

## #435 — clé de récupération durable avant le POST

- `MessagingCryptoVault` : `BackupActivation` (clé de récupération + clé publique) scellée AES-GCM dans `backup-activation.sealed` (AAD propre). `prepareBackupActivation` écrit ou relit **avant** tout POST : un échec de stockage lève `protectionUnavailable` et interdit le POST (diagnostics `S-BKACT-*`, jamais la clé).
- `enableBackup` : intention durable, puis GET `room_keys/version`. Sauvegarde absente : POST. Présente avec la même clé publique : adoptée sans second POST (réponse perdue, relance), et la clé initiale est révélée. Clé publique différente : intention locale effacée et `stateConflict`, décision explicite, sans rotation ni suppression. 409 `BACKUP_ALREADY_EXISTS` ou `BACKUP_VERSION_CONFLICT` au POST : nouveau GET puis même règle.
- `acknowledgeRecoveryKey` (protocole `MessagingKeyManagement`, défaut no-op) efface l'intention quand l'utilisateur confirme avoir noté la clé (`MessagingKeyBackupModel.acknowledgeKey`).
- Relais : nouveau cas `backupAlreadyExists`.
- Tests : `MatrixMessagingBackupRecoveryTests` dans `MatrixMessagingCryptographyTests.swift` (échec de stockage sans POST, réponse perdue puis relance, version distante différente, session synthétique sauvegardée puis restaurée après activation interrompue).

## #436 — lecture paginée de la sauvegarde

- `restoreBackup` lit `limit=500` et `from`, importe page par page, et ne s'arrête que sur `complete: true` (contrat `messaging-api-contract.md`, « Lecture paginée de la sauvegarde (#436) »). Réponse sans `complete`, `complete: false` sans curseur, curseur répété ou plafond de 2000 pages : `invalidResponse`.
- `etag` constant : un changement ou un `409 BACKUP_CHANGED_DURING_READ` réinitialise **seulement le curseur et les compteurs** et relit depuis le début (3 relectures au plus, puis `stateConflict`). Les sessions déjà importées ne sont pas effacées : l'import est idempotent, la relecture les revoit comme déjà présentes (voir « Limites »). `400 BACKUP_CURSOR_INVALID` : même relecture. `422 BACKUP_PAGINATION_REQUIRED` : `invalidResponse`.
- Interruption : le dernier curseur reçu est gardé en mémoire ; la tentative suivante reprend à ce curseur. `saveRecoveryKey` et `enableBackupV1` n'ont lieu qu'après la fin annoncée.
- Relais : cas `backupChangedDuringRead`, `backupCursorInvalid`, `backupPaginationRequired`.
- Tests : 5001 sessions synthétiques lues sans troncature, reprise après interruption, relecture après changement, réponse sans `complete` ou contradictoire.

## #445 — alerte de premier plan du fil visible

- `willPresent` appelle `MessagingActiveConversation.absorbs` : fil actif, bas affiché, **aucune feuille par-dessus** (`covered`), `sequence` dans la charge, puis `MessagingWorkspace.absorbForegroundAlert` : séquence lisible (droits), chargée (relecture sinon), confirmée lue par le serveur (`markRead`). Un état différent après la lecture garde l'alerte.
- Lecture échouée, séquence absente du fil lisible, charge sans séquence ou fil quitté : la bannière est présentée. Pas de double présentation quand l'absorption réussit.
- Préférences : le serveur n'émet une alerte que pour une catégorie activée ; le client décide seulement de présenter ou d'absorber.
- Vue : `MessagingThreadLifecycle` reçoit `covered` (recherche, membres, menu, sondage, électeurs, aperçu média, confirmations, signalement envoyé).
- Tests : `MessagingForegroundAlertTests.swift` (8 tests) ; `MessagingActiveConversationTests` inchangé et compatible.

## Sélections à lancer (runner Apple)

- `DrivyTests/MessagingSendRecoveryTests`
- `DrivyTests/MatrixMessagingBackupRecoveryTests`
- `DrivyTests/MatrixMessagingCryptographyTests` (régression du double `InMemoryRelay`)
- `DrivyTests/MessagingForegroundAlertTests`, `DrivyTests/MessagingActiveConversationTests`
- `DrivyTests/MessagingOptimisticMutationTests`, `DrivyTests/MessagingCoreTests`, `DrivyTests/MessagingDiagnosticsTests`
- `DrivyTests/MessagingKeyBackupTests`, `DrivyTests/MessagingOwnDevicesTests`

Sélection ciblée **`messaging-recovery`** (retour 1/2), ajoutée sans toucher à `messaging` ni à `messaging/READINESS` (l'ancien échec reste documenté, ni masqué ni relancé) : dispatch `refonte-ios.yml` avec `unit_only=true` et `unit_test_scope=messaging-recovery`. Entrées exactes :

```
gh workflow run refonte-ios.yml --repo tomyrms/Drivy --ref <SHA_CANDIDAT> -f unit_only=true -f unit_test_scope=messaging-recovery
```

Contenu (`scripts/ios/test-selection.sh`, miroir dans `scripts/ios/test_test_selection.py`) : MessagingSendRecoveryTests, MatrixMessagingBackupRecoveryTests, MessagingForegroundAlertTests, MessagingActiveConversationTests, MatrixMessagingCryptographyTests, MessagingOptimisticMutationTests, MessagingCoreTests, MessagingDiagnosticsTests, MessagingKeyBackupTests, MessagingOwnDevicesTests. Sans relais réel (`relay_required` = 0, doubles seulement). Workflow : option `messaging-recovery` ajoutée au choix `unit_test_scope` et à sa description. Aucun test UI ajouté.

Python exécutés (cette machine) : `python3 -m unittest scripts.ios.test_test_selection scripts.qualification.test_relay_plan` : 35 tests OK ; `python3 -m unittest discover -s scripts/qualification` : 30 tests OK ; `node scripts/qualification/test-workflows.mjs` : 0 échec. Ces contrôles prouvent la sélection, pas le produit.

## Limites

- Rien compilé ni exécuté ; erreurs de syntaxe ou de typage possibles dans les tests neufs et les ajouts au coffre.
- Les sessions synthétiques de la pagination ne sont pas déchiffrables (comptées en `failed`) : l'import réel est prouvé sur une session, pas sur des milliers.
- Le curseur de reprise n'est gardé qu'en mémoire : après relance de l'app, la lecture repart du début (idempotent).
- `400 BACKUP_CURSOR_INVALID` partage la branche du 409 sans test dédié.
- Après un 409 ou un curseur invalide, seuls le curseur et les compteurs sont réinitialisés : les sessions déjà importées restent dans le coffre. C'est sûr si l'import d'une session est idempotent (hypothèse du moteur Matrix, à confirmer sur Apple), mais si la sauvegarde distante a changé entre-temps, une session retirée du serveur reste localement importée (aucune suppression n'est faite).
- Un `loadMessages` déjà en cours fait renvoyer l'absorption sans charger : l'alerte est conservée (doublon possible plutôt que perte).
- Aucun résultat physique (appareil, notifications réelles). Aucune donnée ni secret dans les traces. Aucun push, CI ni déploiement ; STATUS non modifié.
## Retour de revue 1/2 (même branche, budget F 1/2)

**1. Compilation (verrou).** `MessagingActiveConversation.absorbs` n'appelle plus `NSLock.lock/unlock` dans une fonction `async`. Les captures et vérifications passent par des helpers synchrones à `lock.withLock` (`snapshot()`, `isCurrent(_:)`, `set`, `clear`) : le verrou n'est jamais tenu à travers un `await`.

**2. #445 : séquence exacte et époque.**
- `absorbForegroundAlert` ne prend plus `lastReadableSequence >= sequence` pour preuve. Il faut le message de la séquence **exacte** dans le fil visible (`visibleMessages`), lisible, sans échec de déchiffrement connu (`decryptionCodes`), après chargement si besoin. Messages 4 et 6 chargés, push 5 : alerte gardée, aucun accusé. Chargement en échec : alerte gardée, aucun accusé.
- `State` porte une `epoch` neuve à chaque `set` (compteur monotone, jamais réutilisé). L'absorbeur reçoit `stillPresented` (vrai tant que l'époque courante est celle de la lecture) ; il est vérifié avant le chargement, après, et avant l'accusé. `absorbs` revérifie l'époque exacte avant de supprimer. Départ puis retour du même fil, ou remplacement par un contexte identique en apparence : l'ancienne lecture est invalidée, alerte gardée. Aucune minuterie.
- Limite : un accusé déjà parti vers le serveur quand la feuille s'ouvre reste enregistré (le serveur sait que le message est lu) ; l'alerte est alors tout de même présentée.
- Tests ajoutés (`MessagingForegroundAlertTests`) : cible absente sous une séquence supérieure, chargement en échec, présentation terminée pendant le chargement, présentation déjà terminée, départ/retour pendant la lecture, remplacement par un contexte identique.

**3. #428 : retenue, ordre durable, indépendance.**
- `refreshVisible` n'attend plus les exécuteurs d'envoi : un M1 retenu (réponse en attente) ne bloque ni la lecture de sa conversation ni celle des autres. La panne de protection ou la limite d'appareils est signalée une fois, après les lectures (qui remettent l'erreur à zéro), par l'actualisation si elle est en cours, sinon par l'exécuteur lui-même (`reportSendBlock`).
- Trajet atteignable : `enqueue` + `scheduleSend` pendant `restoreDurableSends` (suspendu sur la lecture du journal) envoyait M2 avant un ancien M1 du journal, puis ajoutait M1 derrière. Corrigé à la source : pendant la restauration aucun exécuteur ne démarre (`restoringDurableSends`), puis `restoreDurableSends` reconstruit chaque file dans l'ordre du journal (entrées du journal d'abord, déjà en file ou inconnues, puis celles que le journal ne contient pas). Une entrée connue hors file (refus définitif, acceptée) n'est jamais remise en file.
- Tests ajoutés (`MessagingSendRecoveryTests`, transport suspendu) : M1 retenu en vol + M2 en attente + deux actualisations concurrentes + bascule réseau + autre conversation : un seul envoi de M1, M2 jamais avant l'accusé, l'autre conversation part librement ; envoi retenu sans blocage de la lecture d'une autre conversation ; ordre durable sous enqueue pendant restauration ; refus définitif non rejoué par la restauration. `testStillUncertain…` et `testProtectionFailure…` attendent désormais les exécuteurs non bloquants.

**4. Qualification.** Voir la sélection `messaging-recovery` ci-dessus. Aucune CI ni push par moi ; compilation et exécution Swift par le coordinateur après intégration stable.

**Lecture UI.** Impeccable (registre ui-skills `pbakaus/impeccable`, mode Operate) et Uncodixfy (`~/.codex/skills/uncodixfy`) lus avant de toucher `MessagingConversationView`. Les seules modifications de vue sont logiques (indicateur `covered` et fermeture de lecture dans `.task(id:)`) : aucune surface, aucun texte, aucune couleur, aucun espacement nouveau. Rien n'a été vu tourner.
