# Médias #97 — assemblage et branchement du parcours réel

Date : 5 novembre 2026. Branche locale : `tomyrms/issues-medias-parcours-97`.
Base qualifiée : `e2edc85ed092237016620079d52d11eb7a2d02b5`.
Point d'interface annoncé au coordinateur : `3297c84f7103e330dfd675c30f80cc8b2505dd2b`.
Commit de réalisation : `211c949475ca550d38018cd0098b9c395a318066`, suivi du correctif de
garde de recomposition dans l'historique local. La fusion U97 `3432066e` reste intacte ;
la correction 1/2 est un commit local sur cette même branche, dont le SHA exact est transmis
avec le `worker_done`, sans réécrire l'historique.

Ce lot ferme le **raccord produit local** entre les primitives média déjà livrées et la
messagerie de qualification. Il ne prouve ni l'exploitation suisse, ni la résidence, ni la
restauration, ni la clôture de #97.

## 1. Dépendances intégrées

Les quatre têtes fixées par `M97-interface-parcours-20261105.md` ont été fusionnées
localement avec `--no-ff`, sans conflit :

| Tête | Contenu |
|---|---|
| `627bd4bb4bef6cb80715eb63b97dbf892d6050de` | file média durable scellée |
| `49ff350f22f016209e455b16b8f85caa6ce39674` | cache média authentifié |
| `2cb6d6645134946567563560274bbfe7e1c092ea` | POST média / reçu symétrique |
| `7cb065a2a43b532cb800b81b2b907c7cc9e90499` | préparation locale et miniature |

Le test de frontière de la file signalé défectueux chez son auteur n'est **ni corrigé ni
exécuté** ici : il reste `NOT_QUALIFIED`. Aucun fichier des quatre lots n'a été modifié
après fusion.

## 2. Interfaces gelées et point d'injection

`apps/ios/Drivy/MessagingCore/MessagingMediaRuntimeContracts.swift` reprend exactement les
types et signatures du contrat partagé : `MessagingMediaPendingSnapshot`,
`MessagingMediaRuntimeFailure`, `MessagingMediaDelivery` et `MessagingMediaRuntime`.

`MessagingWorkspace` porte `let mediaRuntime: (any MessagingMediaRuntime)?`, injecté par un
argument d'initialisation optionnel valant `nil` par défaut. Les compositions texte et
sondage existantes restent compatibles et ne changent pas de comportement.

## 3. Réalisation

`apps/ios/Drivy/MessagingCore/MessagingMediaCoordinator.swift` assemble :

- `MessagingMediaPreparer` pour la validation réelle et la miniature ;
- `AESCTRMediaCryptography` pour le sceau et l'ouverture vérifiée ;
- `MessagingProtectedMediaOutbox` pour l'intention durable et le CAS d'enveloppe ;
- `MessagingProtectedMediaCache` pour le cache AES-GCM par scope ;
- `MessagingMatrixContentEncryption` et `MessagingContentProvenanceDecryption` pour le
  contenu Matrix v3 et sa provenance ;
- `MessagingMediaTransport` pour le dépôt/téléchargement binaire ;
- `MessagingMediaMessageSending` (`MessagingAPIClient.sendMedia`) pour le POST média.

### Ordre et reprise

1. `prepare` s'exécute dans une tâche détachée : aucun décodage ImageIO/PDFKit sur le
   MainActor.
2. `enqueue` scelle une seule fois, construit le contenu v3, puis **persiste le sceau et le
   contenu avant tout dépôt**.
3. L'enveloppe Megolm est ensuite chiffrée et persistée par `replaceEnvelope` avec
   `expected: nil` (CAS), toujours avant émission.
4. `send` relit l'intention durable, dépose le même `mediaID` et les mêmes octets, valide
   le reçu (identité, taille, SHA-256 hexadécimal), puis POST le message avec
   `media: { mediaId, byteSize }`.
5. Un `MEMBERS_CHANGED` avéré laisse l'intention et ne déclenche **aucune** relance
   automatique. `recomposeAfterMembersChanged` est le seul chemin qui remplace l'enveloppe,
   par CAS, et **ne re-dépose pas** les octets média. Ce chemin n'est ouvert qu'après un
   refus `MEMBERS_CHANGED` réellement observé dans l'instance ; une réponse perdue ne
   l'autorise pas.
6. Une réponse perdue ou un POST illisible rend `resultUnknown` ; l'intention reste pour un
   renvoi explicite.
7. Un reçu serveur valide suivi d'un échec d'effacement local rend
   `confirmed(cleanupPending: true)`, jamais un faux échec d'envoi.
8. Le même `clientMessageID` ne peut pas être envoyé deux fois en parallèle dans la même
   instance (`alreadyInFlight`) ; les instances multiples sont couvertes par le CAS et le
   verrou statique de la file, sans promesse de zéro paquet répété.

### Lecture

`MessagingWorkspace.content(for:)` utilise désormais la provenance explicite
`decryptContent` quand la crypto la fournit :

- `.matrixContent` → `MessagingPlainContent.decodeMatrixContent` ;
- `.legacyBody` → décodeur legacy inchangé ;
- v3 connu mais invalide → échec fermé (`D-CONTENT` sur la bulle), jamais un repli
  heuristique depuis un `body` qui ressemblerait à du JSON.

Avant de servir une pièce jointe, la référence serveur (`mediaId`, `byteSize`, `deleted`)
doit correspondre exactement au média authentifié. Le cache d'objet en tête de
`content(for:)` ne contourne plus un tombstone, un changement de contexte ou la limite de
lecture : l'entrée est retirée avant tout retour. Le même contrôle protège l'aperçu de la
boîte de réception.

`MessagingMediaCoordinator.open` :

1. exige une provenance `.matrixContent`, un média typé et une référence serveur active ;
2. lit le cache, sinon télécharge le chiffré (hash vérifié par le transport) ;
3. vérifie le SHA-256 puis déchiffre avec la clé du contenu ;
4. vérifie la taille, le type réel et les dimensions via la préparation système ;
5. n'écrit dans le cache l'original et la miniature **qu'après** ces contrôles ;
6. rend l'original en mémoire et la miniature reconstruite, sans fichier temporaire clair.

Chaque ouverture revalide le format et les dimensions par le préparateur, y compris sur un
cache valide : la miniature scellée est conservée mais n'est pas utilisée comme raccourci de
validation dans ce premier raccord.

### Appareil Matrix

`MatrixMessagingCryptography.currentDeviceID(scope:)` ouvre le coffre existant et rend
l'identifiant d'appareil déjà enregistré, vérifié `[A-Z0-9]{10,32}`. Aucun appareil
synthétique n'est créé. La fabrique du transport binaire est asynchrone et isolée au
MainActor pour capturer la source de jeton ; elle n'y effectue aucune attente bloquante.

### Composition

`MessagingDevelopmentEntry` ouvre la file et le cache média, puis injecte le coordinateur
dans le workspace. Si l'ouverture média échoue (Keychain, coffre, fichiers), la messagerie
texte et les sondages continuent avec `mediaRuntime == nil`. Les conditions d'activation et
les vues restent inchangées.

## 3 bis. Correction 1/2 (revue du coordinateur)

Cette correction reste sur la branche déjà assemblée avec U97 (`3432066e`, UI `b2290bfe`) ;
elle ne réécrit ni les fichiers UI ni les branches sources.

### F1 — reprise idempotente avant nouveau sceau

`enqueue` relit d'abord les intentions du scope et compare le `clientMessageID`. Un record
existant est accepté seulement si la conversation, le contenu original **déchiffré**, la
légende normalisée, les mentions, la réponse et les métadonnées d'affichage correspondent ;
le plaintext est comparé aux octets scellés existants, jamais à un nouveau sceau. Le record
exact est ensuite reconfirmé par `put` (ou par le CAS équivalent) avant tout effet réseau.
Un contenu différent sous le même identifiant échoue fermé (`invalidContent`). Les courses
entre deux instances sont adoptées après `stateConflict`, sans écraser le record gagnant.
`send` et `deliver` reconfirment aussi le record exact par `put` avant le dépôt : `entries`
seul ne prouve pas une synchronisation durable. Le média n'est jamais re-scellé ni
rechiffré pour une reprise.

### F2 — autorisation de recomposition liée à l'enveloppe refusée

`membersChanged` n'est plus un simple `Set` : il mémorise l'enveloppe exacte qui a reçu le
refus. `recomposeAfterMembersChanged` exige que l'enveloppe courante soit celle-là, puis
consomme l'autorisation au moment du CAS réussi, **avant** le POST. Une réponse perdue lors
de ce POST ne laisse donc aucune autorisation : une seconde recomposition retourne
`resultUnknown` sans nouveau chiffrement, CAS ni POST. Un nouveau refus `MEMBERS_CHANGED`
lie une nouvelle autorisation à la nouvelle enveloppe. Le replay explicite réutilise
exactement l'enveloppe conservée. `active` reste un verrou **par instance** ; la cohérence
multi-instance vient du CAS et du verrou statique de la file, sans promesse de zéro paquet
répété.

### F3 — aucun clair ressuscité après une attente

Le workspace capture une époque globale (changement de contexte) et une révision **par
conversation** (tombstone, limite lisible, masquage). Après chaque attente de déchiffrement,
il relit la dernière version connue du message, la limite lisible, le masquage et la
révision ; il vérifie à nouveau les métadonnées serveur avant le cache, avant l'historique
et après l'`upsert`. Un résultat périmé retire le clair et l'entrée d'historique au lieu de
les réinscrire. Une révision d'une autre conversation ne rejette pas un déchiffrement isolé.
Le garde initial de contexte passe par `recordFailure`, qui ferme bien la mémoire affichée
au lieu de seulement poser `error`.

### F4 — invalidation après les attentes et révocation serveur

`isActive` et `ensureActive` revérifient l'invalidation **après** l'attente du contexte.
`enqueue` a une barrière après `put` et avant le chiffrement. Les écritures de cache sont
suivies d'une revalidation : une invalidation ou une révocation survenue pendant le `store`
purge la copie tardive avant de rendre la main. Un reçu serveur déjà confirmé n'est jamais
transformé en échec par un défaut de nettoyage local.

Une capacité additive **interne** `MessagingMediaRevocationReceiving` permet au workspace de
transmettre les `mediaIDs` dont la référence serveur est tombstonée, purgée ou hors de la
limite lisible. Le runtime purge ces médias, bloque les lectures en vol et conserve les
intentions encore à vérifier. Une suppression seulement optimiste (masquage local) ne purge
pas le cache. Le protocole UI gelé n'est pas élargi et U97 n'est pas modifié.

### F5 — tests exécutables et bornés

Les treize mutations externes de propriétés d'acteurs sont remplacées par des méthodes
isolées de configuration. Les fixtures de test sont synthétiques ; le PNG 1×1 a été régénéré
et ses CRC IDAT/IEND ainsi que `zlib.decompress` ont été vérifiés avec Python standard.
`Gate.waitUntilWaiting` et la terminaison des tâches retenues sont bornées par échéance, avec
libération sur tous les chemins ; un test contrôle explicitement une entrée qui n'arrive pas.
Aucun task group n'attend un enfant non coopératif.

## 4. Tests préparés (NON EXÉCUTÉS)

Aucun outil Apple n'est présent sur ce poste Windows : `swift`, `swiftc`, `xcodebuild`,
`xcrun` et `xcodegen` sont absents. **Aucune compilation, aucun RED/GREEN Swift et aucune
suite XCTest ne sont revendiqués.**

Deux fichiers, 43 méthodes préparées (aucune exécutée Apple) :

- `apps/ios/DrivyTests/MessagingMediaCoordinatorTests.swift` (34)
  - préparation hors MainActor et mapping fermé ;
  - ordre `put` du sceau → chiffrement → CAS de l'enveloppe, avant tout dépôt ;
  - panne à la persistance, légende/mentions/nom bornés ;
  - reprise idempotente après échec de `put`, de chiffrement ou de CAS, même sceau,
    même `createdAt`, même enveloppe ; contenu différent refusé ; adoption d'un record
    concurrent ; deux instances ;
  - dépôt → POST → retrait, reçu sans nettoyage local, réponse perdue ;
  - `MEMBERS_CHANGED` : recomposition liée à l'enveloppe refusée, réponse perdue interdisant
    une seconde recomposition, replay explicite de la même enveloppe ;
  - double geste concurrent avec suspension contrôlée (`Gate` borné, aucun sommeil de preuve) ;
  - réouverture avec le même enregistrement et la même enveloppe ;
  - métadonnées serveur, tombstone, autre média, autre taille, corruption, format divergent ;
  - invalidation ou changement de contexte pendant `put`, `store` et miniature, purge de la copie tardive, révocation
    connue et blocage de lecture ;
  - déchiffrement retenu puis tombstone ou limite lisible : aucun clair/historique tardif ;
  - panne de coffre non rendue comme liste vide ; entrée de barrière qui n'arrive pas.
- `apps/ios/DrivyTests/MessagingMediaJourneyIntegrationTests.swift` (9)
  - parcours émetteur avec file et cache **réels** sur répertoire temporaire, PNG 1×1
    synthétique valide, primitives AES-CTR/SHA-256 réelles ; seuls Megolm/dépôt/POST sont doublés ;
  - réouverture de la file avec le même sceau ;
  - réception : téléchargement unique, validation, cache, second rendu depuis le cache ;
  - invalidation du cache réel, intention conservée ;
  - workspace : provenance Matrix, v3 invalide refusé, repli legacy, tombstone, référence
    serveur disparue, point d'injection optionnel.

Commande Apple exacte à exécuter au SHA du commit de livraison :

```bash
xcodegen generate --spec apps/ios/project.yml
xcodebuild test \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DrivyTests/MessagingMediaCoordinatorTests \
  -only-testing:DrivyTests/MessagingMediaJourneyIntegrationTests \
  -derivedDataPath artifacts/ios/DerivedData
```

Suites partagées à rejouer dans le même run ou dans le candidat final :
`MessagingMediaOutboxTests`, `MessagingMediaCacheTests`, `MessagingMediaPreparationTests`,
`MessagingMediaMessageClientTests`, `MessagingMediaMessageTransportTests`,
`MessagingHTTPMediaTransportTests`, `MessagingMediaContentTests`, `MessagingThreadTests`,
`MessagingHTTPTransportTests`, `MessagingDiagnosticsTests`, `MessagingCoreTests`,
`MessagingEntryTests`, `MatrixMessagingCryptographyTests`,
`MatrixMessagingRelayIntegrationTests`, `MatrixMessagingSealedReportRelayTests`.
La commande de CI du dépôt reste `bash scripts/ios/test-simulator.sh` ; elle n'a pas été
lancée ici et aucun workflow n'a été modifié.

## 5. Contrôles réellement exécutés sur ce poste

| Commande / contrôle | Résultat |
|---|---|
| `git status --porcelain` avant fusion | propre, base `e2edc85e` |
| `git cat-file -t` sur les quatre têtes | quatre commits présents |
| `git merge --no-ff` ×4 | aucun conflit |
| `git diff --check` | aucune erreur d'espacement |
| Script Python d'équilibre des délimiteurs (chaînes/commentaires ignorés) | équilibré sur les 7 fichiers touchés/neufs |
| `Select-String 'XCTAssert\w+\([^)]*await'` | 0 occurrence dans les deux fichiers de tests |
| `Select-String 'Task\.sleep|sleep\('` | 0 occurrence : suspensions par `Gate` |
| Comptage des méthodes de test | 34 + 9 = 43 |
| `Select-String 'await\s+\w+\.\w+\s*='` dans les tests | 0 mutation externe de propriété d'acteur |
| PNG 1×1 de test : CRC des chunks + `zlib.decompress(IDAT)` | valides (Python standard) |
| Codebase Memory `drivy-medias-parcours-97` | réindexé avant remise, `status: ready` ; les deux fichiers de tests, le coordinateur et le workspace sont absents de `parse_partial` |
| `Get-Command swift, swiftc, xcodebuild, xcrun, xcodegen` | 0 outil |
| `git status --porcelain` final | uniquement les fichiers de réalisation, puis ce rapport |

Le signal Codebase Memory est structurel, pas une compilation. Aucun port Python ne
remplace un test Swift.

## 6. Limites et manques non comblés

- **Aucune compilation ni exécution Apple** : le code peut ne pas compiler ; tout résultat
  de test est `NOT_EXECUTED`.
- **Aucune intégration réelle** relais/API/PostgreSQL exécutée dans ce lot. Les tests
  d'intégration utilisent la file et le cache réels, mais Megolm, le dépôt binaire et le
  POST sont des doubles contrôlés.
- **Aucune preuve UI** : import, sélection, aperçu, états d'envoi, iPhone/iPad,
  clair/sombre, Dynamic Type, clavier et VoiceOver restent au lot U97 et à la
  qualification.
- **Le signalement média typé complet reste hors de ce premier raccord.** Aucun droit
  administrateur n'est élargi et aucune copie d'octets n'est ajoutée aux signalements.
- **Révocation serveur ciblée** : le workspace transmet au runtime les `mediaIDs` des
  tombstones, purges et limites lisibles ; le runtime purge les copies connues et bloque
  les lectures en vol. Une suppression seulement optimiste (masquage) ne purge pas le cache.
  Aucun hook de déconnexion automatique n'est ajouté ; l'UI doit appeler `invalidate` à la
  sortie de contexte.
- **Pas d'effacement physique promis** : `unlink`, cache AES-GCM et invalidation ne
  garantissent ni zéroïsation mémoire ni effacement SSD.
- **Pas de politique de conservation** : aucune TTL, aucune purge automatique, aucune
  restauration. #68 reste ouverte.
- **Résidence suisse non prouvée** : ce lot ne fournit aucune preuve d'exploitation, de
  stockage ou de restauration en Suisse. #97 n'est pas close.
- **Test de frontière de la file** : toujours défectueux chez son auteur, non corrigé et
  non qualifié ici.
- **Miniature de cache** : conservée, mais chaque lecture revalide par le préparateur ; ce
  choix privilégie le contrôle du format et des dimensions sur l'économie d'un décodage.
- **PDF** : l'aperçu emploie `PDFDocument(data:)` dans la préparation ; aucun temporaire
  clair n'est créé. Le rendu complet, les 50 pages et les actions restent au lot UI.

## 7. Modèle, skills et Codebase Memory réellement utilisés

- **Modèle actif** : `opencode-go/deepseek-v4.1-flash` (DeepSeek V4.1 Flash), sans variante
  ni effort exposé par ce runtime.
- **Skills Superpowers réellement chargés** via l'outil `skill` :
  - `test-driven-development` (base
    `C:\Users\jtoma\.config\opencode\node_modules\superpowers\skills\test-driven-development`) :
    tests écrits avant le coordinateur ; RED/GREEN non exécuté faute d'outil Apple ;
  - `systematic-debugging` (même base) : chargé pour la correction 1/2 ; chaque constat F1–F5
    a été lu dans le source réel avant modification ;
  - `verification-before-completion` (même base) : chargé avant les contrôles et la remise ;
    il interdit de présenter le lot comme compilé ou testé.
- **Codebase Memory** : projet `drivy-medias-parcours-97`, racine
  `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-parcours-97`, `status: ready` après
  réindexation avant remise. Recherches et lectures directes :
  `MessagingMediaRuntimeContracts`, `MessagingMediaCoordinator`,
  `MessagingWorkspace`, `MessagingDevelopmentEntry`, `MatrixMessagingCryptography`,
  `MessagingProtectedMediaOutbox`, `MessagingProtectedMediaCache`, `MessagingMediaPreparer`,
  `MessagingMediaContent`, `MessagingHTTPMediaTransport`, `MessagingAPIClient`. Les
  fichiers neufs ne figurent pas dans `parse_partial` ; l'`openapi.yaml` de conception reste
  non analysable, comme avant.
- **Aucun sous-agent, aucun worktree supplémentaire, aucune action distante.**
