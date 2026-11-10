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
- `etag` constant : un changement ou un `409 BACKUP_CHANGED_DURING_READ` jette l'état partiel et relit depuis le début (3 relectures au plus, puis `stateConflict`). `400 BACKUP_CURSOR_INVALID` : même relecture. `422 BACKUP_PAGINATION_REQUIRED` : `invalidResponse`.
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

Aucun sélecteur Python n'est modifié : aucun script du dépôt ne référence ces classes. Aucun test UI ajouté. Aucun texte nouveau à l'écran (Impeccable et Uncodixfy : sans objet, pas de changement visible).

## Limites

- Rien compilé ni exécuté ; erreurs de syntaxe ou de typage possibles dans les tests neufs et les ajouts au coffre.
- Les sessions synthétiques de la pagination ne sont pas déchiffrables (comptées en `failed`) : l'import réel est prouvé sur une session, pas sur des milliers.
- Le curseur de reprise n'est gardé qu'en mémoire : après relance de l'app, la lecture repart du début (idempotent).
- `400 BACKUP_CURSOR_INVALID` partage la branche du 409 sans test dédié.
- Un `loadMessages` déjà en cours fait renvoyer l'absorption sans charger : l'alerte est conservée (doublon possible plutôt que perte).
- Aucun résultat physique (appareil, notifications réelles). Aucune donnée ni secret dans les traces. Aucun push, CI ni déploiement ; STATUS non modifié.