# Médias #97 — T2b4 : cache local authentifié, sans rendu ni réseau

Base : `e2edc85ed092237016620079d52d11eb7a2d02b5` (branche `tomyrms/issues-medias-cache-97`, worktree `issues-medias-cache-97`). Livraison initiale `ed48dbb001b85b891a9385db9ce6fce48304226d`, **correction 1** (`8afece8e`), puis **correction 2** (§15) : ancre de confiance séparée des composants possédés, index absent + fichiers scellés en erreur fermée, fixture corrigée. Les preuves Apple 1515/1515 et Linux des runs `41906356835`/`41906366352` portent sur la **base**, pas sur ce code.

Ce lot livre **un cache local**. Il n'est branché ni au coffre média, ni à l'outbox, ni au contenu v3, ni à l'UI. Aucun écran, aucune copie produit, aucun rendu, aucune requête réseau, aucune activation de parcours. Aucun fichier PDF temporaire en clair n'est introduit : le futur rendu PDF passe par `PDFDocument(data:)` et ne concerne pas ce lot.

## 1. Contrat reçu et interface

`MessagingMediaCache` (§4.5) est fourni **tel quel**, avec deux ajouts rendus nécessaires pour que l'interface soit exécutable :

```swift
protocol MessagingMediaCache: Sendable {
    func store(_ data: Data, mediaID: UUID, scope: MessagingScope) async throws
    func data(mediaID: UUID, scope: MessagingScope) async throws -> Data?
    func thumbnail(mediaID: UUID, scope: MessagingScope) async throws -> Data?
    func storeThumbnail(_ data: Data, mediaID: UUID, scope: MessagingScope) async throws  // ajout
    func purge(mediaIDs: [UUID], scope: MessagingScope) async throws
    func purgeAll(scope: MessagingScope) async throws                                  // ajout
}
```

- Sans `storeThumbnail`, aucune miniature ne peut entrer dans le cache : `thumbnail` seule ne fait que lire.
- Sans `purgeAll`, aucune primitive appelable à la sortie de contexte, à la fin de lien ou à la suppression n'existe. `purgeAll` **n'est branchée à rien** : aucun logout silencieux, aucune UI, aucune décision de conservation.

Implémentation : `actor MessagingProtectedMediaCache`, un scope complet par instance (compte, école, époque, URL d'API). Erreurs du module (`MessagingFailure.contextChanged`, `.invalidResponse`, `.protectionUnavailable`) : aucune énumération d'affichage, aucun texte d'interface, aucun `LocalizedError`.

### Ce que le cache reçoit, exactement

`Data` est le **contenu déjà authentifié et déchiffré en mémoire** par le consommateur (Megolm pour le fichier, contenu Matrix pour les métadonnées). Le cache ne déchiffre rien de bout en bout, ne vérifie aucun hash de transport, ne compare **jamais** le SHA-256 du chiffré téléchargé aux octets clairs. Il **rechiffre au repos** en AES-GCM. Aucun déchiffrement E2EE, aucun réseau, aucune génération de miniature, aucun rendu.

## 2. Stockage : chemins opaques, AAD, scellement

| Élément | Valeur |
|---|---|
| Ancre (fournie) | `Application Support` (production) ou répertoire fourni par la factory de test |
| Composant possédé 1 | `<ancre>/MessagingMediaCache` |
| Composant possédé 2 | `<racine>/SHA256("accountID|schoolID|epoch|apiBaseURL")` (64 hexadécimaux) |
| Fichier média | `SHA256("drivy.media.cache.v1|<empreinte scope>|<genre>|<mediaID>")` + `.sealed` |
| Index | `index.sealed` |
| Temporaire d'écriture | `<UUID aléatoire>.tmp`, supprimé en cas d'échec |

Aucune clé, aucun nom de fichier, aucun MIME, aucun contenu, aucun identifiant de personne ou de média n'apparaît en clair dans un nom de fichier, un répertoire ou un journal : le cache **n'écrit aucun journal**.

**AAD** de chaque fichier : `drivy.media.cache.v1|<empreinte scope>|<genre>|<mediaID>|aad`. Elle lie version, scope, identité média et genre. Un fichier déplacé d'une identité, d'un scope ou d'un genre ne s'ouvre pas. L'index est scellé avec sa propre AAD (`…|<empreinte scope>|index|aad`).

Écriture : temporaire protégé → `write` + `synchronize` → `close` (fermé sur tous les chemins, échec compris) → `replaceItemAt`/`moveItem` → `protect` → `F_FULLFSYNC` sur le fichier et `fsync` sur le répertoire. Aucun repli : si une étape échoue, l'appel échoue, le fichier non commité est retiré et le répertoire synchronisé.

## 3. Clé Keychain : cycle exact

- Espace de production : service `ch.drivy.messaging.media.cache.v1`, compte `media-cache-key-v1` (`MessagingMediaCacheKeychain.production`), distincts du snapshot protégé de la messagerie.
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false`.
- Création : uniquement si **aucun fichier `.sealed` n'existe sous la racine**, et seulement après que l'état de l'index a été jugé cohérent. Un index absent avec des fichiers scellés échoue **avant** toute demande de clé (§5), donc `mayCreate` ne peut jamais devenir vrai à cause d'un nettoyage d'orphelins.
- Face à des fichiers existants, une clé absente est une **erreur fermée** : aucune clé n'est recréée en silence.
- `purge` et `purgeAll` **ne suppriment pas** la clé (partagée par les scopes de l'appareil) ; sa destruction relève d'un retrait Keychain hors de ce composant.
- Injection : `keychainKey(mayCreate:namespace:)` est interne et paramétré par un espace nommé. Les tests n'utilisent qu'un **espace temporaire propre** et ne lisent ni ne suppriment la clé de l'application ; la production garde `.production`. Sous Windows, Security n'est jamais appelé.
- `unlink` supprime le nom et les octets lisibles par le système : ni effacement physique SSD, ni zéroïsation mémoire ne sont promis.

## 4. Plafond, LRU, éviction — et borne après lecture

- Plafond technique **50 Mio par scope** (`52_428_800`), originaux + miniatures + index. Garde de ressources réversible, pas une politique de conservation : aucune TTL, aucune purge automatique, aucune rétention serveur.
- Consommation réelle **mesurée sur le disque**, jamais déduite de l'index.
- Éviction **par média entier** (original + miniature), rang LRU croissant puis identité média croissante à égalité ; orphelins d'abord ; chaque suppression suivie d'un `fsync` du répertoire.
- Une lecture effective actualise le rang LRU, persisté dans l'index scellé : l'ordre survit à la réouverture.
- La borne s'applique **aussi après une lecture** : toute opération qui fait croître l'index (compteur LRU compris), y compris une écriture idempotente des mêmes octets, repasse par `commit` → `saveIndex` → `enforceQuota`. Si le média conservé et son index ne tiennent plus, l'issue est **fermée**, jamais un dépassement silencieux.
- Seules les copies du cache sont évincées ; aucune intention d'outbox n'est touchée.

## 5. Cohérence : orphelins, index absent, interruptions

Deux situations distinctes, explicites dans le code et les tests :

1. **Index valide présent** : un fichier scellé sans entrée est un orphelin. Il n'est **jamais servi** ; il est nettoyé de façon contrôlée, et l'échec du nettoyage est propagé (`protectionUnavailable`). Ce nettoyage n'a lieu qu'après une lecture d'index réussie : la clé existante a donc déjà été validée.
2. **Index absent alors que des fichiers scellés existent** : état **incohérent**, **erreur fermée** (`protectionUnavailable`). Rien n'est servi, adopté, réécrit ni supprimé ; aucune clé n'est demandée ni créée. Une réouverture ne rétablit rien implicitement. La seule sortie est `purgeAll`, explicite : elle supprime les fichiers scellés et l'index sans avoir besoin de l'index, et le cache redevient utilisable ensuite.

Conséquences vérifiées :

- Un fichier absent de l'index ne peut pas être « réinscrit » par une lecture.
- Un fichier purgé ne peut pas être ressuscité depuis l'index : la purge supprime d'abord les fichiers, puis l'index ; un fichier absent renvoie `nil` et l'entrée orpheline est retirée.
- Un mauvais tag, une mauvaise clé, un index illisible ou une entrée incohérente échouent fermés.
- Ordre d'écriture : fichier média puis index. Si l'index ne peut pas être scellé, le fichier média est retiré, le répertoire synchronisé, l'appel échoue. Un arrêt brutal entre les deux laisse un orphelin qui n'est jamais servi (règle 1) ; il n'est jamais adopté.
- Aucun succès d'écriture ou de purge avant la synchronisation durable disponible (`F_FULLFSYNC` + `fsync`), `purgeAll` comprise.

## 6. Bornes et validation

| Élément | Borne | Contrôle |
|---|---|---|
| Original | 1 … 4 194 304 octets (`MessagingMediaAttachment.maximumByteSize`) | avant écriture **et** à la lecture ; octets opaques, aucun parseur introduit |
| Miniature | 1 … 131 072 octets | avant toute analyse ImageIO |
| Miniature | JPEG ou PNG uniquement | `CGImageSourceGetType` + `UTType` ; PDF et HEIC refusés |
| Miniature | 1 … 512 px par axe | `CGImageSourceCopyPropertiesAtIndex` (`ShouldCache: false`) |
| Fichier scellé | borne du genre + 28 octets (nonce 12 + tag 16) | taille d'abord, `Data(contentsOf:)` ensuite |
| Index scellé | 1 048 576 octets | idem |
| Entrées d'index | 4 096 | borne de travail, pas une règle produit |

ImageIO ne lit que **type et dimensions** : `CGImageSourceCreateImageAtIndex` n'est jamais appelé. Aucun chemin, aucune URL de fichier et aucun importateur ne sont acceptés par l'API : seuls des `Data` et un `UUID` entrent.

## 7. Concurrence et confinement

- Deux instances du même scope partagent le même répertoire : section critique sérialisée par un **verrou statique**. `NSLock.lock`/`unlock` portent `noasync` : elles ne sont **jamais** appelées depuis un contexte async, mais depuis la fonction **synchrone** `withIOLock` (`NSLock.withLock`). Aucun `await` ne peut s'y glisser.
- Le scope attendu est comparé avant chaque accès ; un autre scope lève `contextChanged` et ne rend jamais de données.
- **Ancre de confiance vs composants possédés.** L'ancre est fournie par l'OS (`Application Support`) ou par la factory de test. Seule l'ancre est canonisée, **une fois** (`resolvingSymlinksInPath`) : les préfixes système légitimes (`/var` → `/private/var`) ne sont pas des contre-exemples. Les composants **possédés** sous l'ancre — la racine du cache puis le répertoire du scope — ne sont **jamais** résolus : s'ils existent comme lien, comme fichier, ou si le parent attendu n'est pas le bon, la construction échoue **avant** toute création, protection, écriture ou suppression. Le nom du composant possédé est validé (un seul segment, ni `.` ni `..`, pas de `/`), et aucun composant intermédiaire n'est créé (`withIntermediateDirectories: false`).
- Avant **chaque** effet, `verifyConfinement` revérifie : ancre réelle et canonique, racine et scope réels et non résolus, racine enfant de l'ancre, scope enfant de la racine. Un remplacement de l'un de ces répertoires par un lien **après** l'initialisation échoue donc fermé.
- Limite honnête : ce n'est **pas** une protection contre une course inter-processus active pendant l'opération ; elle couvre un remplacement entre deux opérations. L'ancre elle-même est supposée fournie par un composant de confiance.

## 8. Tests écrits (56)

`apps/ios/DrivyTests/MessagingMediaCacheTests.swift`. Images **synthétiques** uniquement (aplat uni ou bruit déterministe en mémoire) : aucune photo, aucun fichier importé, aucune donnée de personne, aucune bibliothèque ajoutée.

- aller-retour et réouverture (original + miniature) ; aucun sentinelle, identifiant, genre, MIME ni nom en clair dans les fichiers scellés et l'index ; noms opaques de 64 caractères hexadécimaux ;
- bornes original (0 refusé, 1 octet, 4 Mio, 4 Mio + 1 refusé, rien d'écrit pour un refus) ; miniatures JPEG/PNG 512 px acceptées, PDF et octets arbitraires refusés, 513 px refusé sur les deux axes, PNG bruité > 128 Kio refusé ;
- AAD : autres octets pour le même `mediaID` refusés ; fichier échangé entre deux médias refusé ; miniature à la place de l'original refusée ; fichier copié d'un autre scope refusé (entrée valide des deux côtés) ;
- clé : absente avec fichiers existants → erreur fermée et aucune demande de création ; clé étrangère → erreur fermée ;
- index corrompu → erreur fermée sur lecture, écriture et purge, octets corrompus non remplacés ;
- **orphelins** : fichier sans entrée (index valide) jamais servi et nettoyé ; échec réel du nettoyage (permissions) → erreur fermée sans suppression silencieuse ; point de panne de nettoyage → erreur fermée puis nettoyage contrôlé ;
- **index absent + fichiers scellés** : `data`, `store` et `purge` échouent fermés ; **aucune demande de création de clé** (fournisseur qui pourrait créer, jamais sollicité) ; fichier scellé **inchangé** ; index toujours absent ; réouverture sans rétablissement ; après `purgeAll` explicite le cache redevient utilisable ;
- **autre scope** sous la même ancre portant des fichiers scellés sans index : la clé existante est validée (aucune création demandée), ce scope échoue fermé, ses fichiers ne sont ni adoptés ni nettoyés ;
- **pannes contrôlées** : échec avant le commit d'index, après le rename du fichier, à la synchronisation du fichier, à la synchronisation du répertoire de `purgeAll` → aucun faux succès, aucune donnée servie, aucun artefact résiduel ;
- quota : éviction du LRU, lecture qui rajeunit une entrée, original + miniature ensemble, ordre persisté après réouverture, quota respecté après **chaque lecture** (borne = taille mesurée, douze lectures, passages de chiffres du compteur), deux instances, quota respecté après écritures concurrentes ;
- purge : les deux genres, doublons et liste vide idempotents ; `purge`/`purgeAll` d'un scope ne touchent jamais l'autre ; **sentinelles hors périmètre intactes** (fichier à la racine, répertoire d'un autre scope) après purge et après éviction ;
- pannes réelles : répertoire de scope en `0500` → écriture et purge échouent sans faux succès, index intact après restauration ;
- fichier de 8 Mio avec entrée valide → refusé (borne avant lecture) ; fichier média lié symboliquement → refusé ;
- **confinement** : ancre liée avant l'initialisation → canonisée une fois, données sous l'ancre canonique, aucune écriture vers une autre cible, changement de cible du lien d'ancre sans redirection ; **racine possédée liée avant l'initialisation** → refus, cible externe intacte (contenu et liste inchangés), aucune clé demandée ; **scope possédé lié avant l'initialisation** → refus, cible externe intacte ; composant possédé existant comme fichier → refus, contenu intact ; nom de composant s'échappant de l'ancre (`../escape`, `sub/cache`, vide, `.`, `..`) → refus ; racine remplacée par un lien après l'initialisation → lecture, écriture, purge et purgeAll refusées ; scope remplacé par un lien après l'initialisation → refusé ;
- autres scopes : `contextChanged` sur lecture et purge ; scope sans époque ou sans API → refusé ;
- deux instances, 20 écritures concurrentes : aucune perte ; surface exercée à travers `any MessagingMediaCache` ; bornes publiées vérifiées (4 Mio, 128 Kio, 512 px, 50 Mio) ;
- **Security réel, espace isolé** : aller-retour de clé (création, relecture identique, 256 bits), attributs `WhenUnlockedThisDeviceOnly` et non synchronisé, refus de création sans autorisation, puis cache complet sur cette clé.

Les tests de panne sont **contrôlés** (points de panne internes bornés, permissions POSIX, fichiers forgés) : ce ne sont **pas** des coupures d'alimentation physiques.

## 9. Ce qui n'a PAS été exécuté

**NON EXÉCUTÉ — aucun outil Apple sur ce poste (Windows).** Aucun test Swift de ce lot n'a été compilé ni exécuté ; aucun RED/GREEN Swift n'est revendiqué. Les tests ont été écrits avant l'implémentation, puis relus. Aucun port Python n'est présenté comme un test : le script jetable ne vérifie que l'équilibre des délimiteurs.

À lancer sur un runner Apple, au SHA de livraison exact :

```bash
xcodegen generate --spec apps/ios/project.yml
xcodebuild test \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DrivyTests/MessagingMediaCacheTests \
  -derivedDataPath artifacts/ios/DerivedData
```

La sélection `DRIVY_IOS_UNIT_TEST_SCOPE=messaging` de `scripts/ios/test-selection.sh` **n'inclut pas** cette classe : ce fichier appartient à un autre lot et n'a pas été modifié. Seul le `-only-testing` ci-dessus l'exécute.

Non vérifiable ici : compilation Swift 6 (`SWIFT_STRICT_CONCURRENCY: complete`), `NSLock.withLock` sur la cible (iOS 26), `FileProtectionType.complete` sur simulateur, `replaceItemAt`/`F_FULLFSYNC` sur APFS, résolution des liens par `resolvingSymlinksInPath` sur le volume de test, disponibilité Keychain en CI.

## 10. Modèle, skills, Codebase Memory réellement utilisés

- **Modèle** : `opencode-go/deepseek-v4.1-flash` (DeepSeek V4.1 Flash), sans paramètre de modèle ni d'effort ; révision et effort non exposés par ce runtime, donc **non vérifiables**.
- **Skills Superpowers chargés (outil `skill`, réellement)** :
  - `test-driven-development` — base `C:\Users\jtoma\.config\opencode\node_modules\superpowers\skills\test-driven-development` : tests écrits avant le code ; cycle RED → GREEN **non exécuté** faute de compilateur Swift.
  - `systematic-debugging` — base `…\superpowers\skills\systematic-debugging` : chargé pour les corrections 1 et 2 ; chaque constat reproduit en source avant modification (canonisation de la racine possédée avant contrôle, `loadIndex` vide menant au nettoyage puis à `mayCreate == true`, double initialisation de la fixture).
  - `verification-before-completion` — base `…\superpowers\skills\verification-before-completion` : chargé avant la livraison ; il interdit de présenter le lot comme compilé ou testé.
  - Aucun sous-agent, aucune revue indépendante simulée.
- **Codebase Memory** : projet **unique** `drivy-media-cache-97-20261104`, chemin absolu `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-cache-97` (aucun index voisin).
  - `index_status` après réindexation avant édition : racine du worktree, `status: ready`, `indexed_at 2026-11-04T22:06:18Z`, 39 684 nœuds.
  - `search_graph` (correction 2) : `prepareDirectory` et `loadIndex` localisés dans `MessagingMediaCache.swift` — c'est bien le code du lot qui portait les deux défauts.
  - Lecture source directe : `MessagingProtectedStore.swift`, `MessagingContracts.swift`, `MessagingMediaContent.swift`, `MessagingMediaCryptography.swift`, `MessagingDiagnostics.swift`, `MessagingProtectedStoreTests.swift`, `scripts/ios/test-selection.sh`, `apps/ios/project.yml`.
  - Lacunes assumées : `parse_partial` hors périmètre, `openapi.yaml` non analysable.

## 11. Commandes réellement exécutées (Windows, sans Swift)

| # | Commande | Résultat | Code |
|---|---|---|---|
| 1 | `git rev-parse HEAD` (avant correction) | `8afece8e3e6093328148b80c398385240a9ad127` (candidat relu) | 0 |
| 2 | `index_repository` (MCP, chemin absolu) + `index_status` | `ready`, 39 684 nœuds, `2026-11-04T22:06:18Z` | 0 |
| 3 | `search_graph` ×2 (MCP) : `prepareDirectory`, `loadIndex` | les deux méthodes du lot localisées | 0 |
| 4 | `Select-String '\.lock\(\)\|\.unlock\(\)'` | **0** occurrence | 0 |
| 5 | `Select-String 'withIOLock'` | 1 définition synchrone + 6 usages | 0 |
| 6 | `Select-String 'handle\.close'` | 2 occurrences (nominal + `catch`) | 0 |
| 7 | `Select-String 'Self\.synchronize\('` | 9 occurrences (purgeAll et chaque éviction comprises) | 0 |
| 8 | `Select-String 'verifyConfinement\|prepareOwnedDirectory\|hasSealedArtifacts\|anchor'` | 8 vérifications (init + 6 effets + relais), 2 appels de préparation possédée, contrôle d'index absent | 0 |
| 9 | `Select-String 'let key'` dans les tests | déclaration `let key: KeyFixture` + **une** affectation dans l'init | 0 |
| 10 | Script Python jetable : équilibre des délimiteurs | `balanced` ×2 | 0 |
| 11 | Comptage des méthodes de test + doublons | 56 méthodes, 56 noms uniques | 0 |
| 12 | `Select-String 'XCTAssert\w+\([^)]*await'` | **0** : aucun `await` dans une autoclosure XCTest | 0 |
| 13 | `git diff --check` | aucune erreur d'espacement (fins de ligne LF normalisées) | 0 |
| 14 | `git status --porcelain` | 3 fichiers du lot, aucun autre | 0 |

Aucun port Python n'est présenté comme une preuve de comportement Swift : le reste est **à exécuter sur Apple**.

## 12. Fichiers

| Fichier | Rôle |
|---|---|
| `apps/ios/Drivy/MessagingCore/MessagingMediaCache.swift` | protocole §4.5 + deux ajouts, acteur scellé AES-GCM, index scellé, quota/LRU (y compris après lecture), purge durable, ancre de confiance / composants possédés, clé Keychain nommée |
| `apps/ios/DrivyTests/MessagingMediaCacheTests.swift` | 56 tests, fixtures synthétiques, pannes contrôlées, Security isolé, confinement |
| `docs/implementation/messaging-media-97-cache.md` | ce document |

Aucune dépendance, aucun `project.yml` (sources par répertoire), aucun lockfile, aucun workflow, aucun fichier existant (ni `MessagingProtectedStore`, ni outbox, ni primitives crypto, ni transport, ni contenu, ni coordination/factory/UI, ni `STATUS.md`, ni conception) modifié.

## 13. Risques et limites honnêtes

- **Aucune preuve Apple** : le code peut ne pas compiler ; aucun test de ce lot n'a tourné.
- **Aucun RED/GREEN exécuté** : plusieurs tests dépendent d'ImageIO, `FileProtection`, `resolvingSymlinksInPath` et Keychain, non observables ici.
- **Pannes simulées** : points de panne internes et permissions POSIX, pas de coupure d'alimentation ; ni l'atomicité du support ni la reprise après crash réel ne sont démontrées.
- **Confinement sans course** : couvre un remplacement entre deux opérations, pas un attaquant actif pendant l'opération ; l'ancre est supposée fournie par un composant de confiance.
- **Index perdu = cache fermé** : sans index valide mais avec des fichiers scellés, le cache refuse tout jusqu'à `purgeAll` explicite. C'est la règle choisie ; aucune récupération implicite, aucune reconstruction depuis l'index.
- **`unlink` ≠ effacement** : ni effacement physique SSD, ni zéroïsation mémoire ne sont promis.
- **Clé partagée** : `purgeAll` ne détruit pas la clé ; une destruction par appareil demanderait une clé par scope (décision non prise ici).
- **Index réécrit à chaque lecture** : la LRU durable coûte une écriture scellée (et une éventuelle éviction) par lecture effective ; coût I/O non mesuré.
- **Quota mesuré par énumération** : coût proportionnel au nombre de fichiers, non mesuré.
- **Issue fermée sur quota** : une lecture peut échouer si le média conservé et son index ne tiennent plus ; voulu, mais un quota très petit rend le cache inutilisable plutôt que silencieusement dépassé.
- **Éviction par média entier** : un original volumineux emporte sa miniature.
- **Pas de branchement** : outbox, coffre, contenu v3, UI et déconnexion restent à faire ; `purgeAll` est fourni mais appelé nulle part.
- **Politique de conservation** : aucune n'est décidée. #68 reste ouverte.

## 14. Correction 1 (revue du coordinateur)

| # | Constat | Cause racine vérifiée en source | Correction |
|---|---|---|---|
| 1 | `NSLock.lock`/`unlock` appelées dans des méthodes `async` | `noasync` dans Foundation/Swift 6 : la section était synchrone mais le contexte d'appel async | section dans `withIOLock`, fonction synchrone qui appelle `NSLock.withLock` ; 0 occurrence de `.lock()`/`.unlock()` |
| 2 | `purgeAll` sans synchronisation ; `FileHandle` non fermé dans le `catch` | suppressions sans `fsync` ; `close` seulement au nominal | `fsync` après purge et après chaque éviction (échec propagé) ; `close` explicite + `try? close` en échec ; nettoyage synchronisé après échec d'index ; points de panne bornés |
| 3 | un fichier absent de l'index pouvait être servi puis réinscrit | lecture du chemin déterministe sans exiger d'entrée, puis adoption | aucun fichier sans entrée valide n'est servi ; nettoyage contrôlé ou erreur fermée (règle précisée en correction 2 pour l'index absent) |
| 4 | contrôles de répertoires limités à l'initialisation | aucun contrôle avant les effets | vérification avant chaque effet (complétée en correction 2 par la séparation ancre / composants possédés) |
| 5 | index réécrit sans borne après lecture | `readLocked`/`touch` réécrivaient sans borne | `commit` = `saveIndex` + `enforceQuota` sur toutes les opérations qui font croître l'index |
| 6 | test sur le Keychain de production | preuve système sur l'espace applicatif | `keychainKey(namespace:)`, `.production` conservé, tests dans un espace temporaire propre |

## 15. Correction 2 (revue du coordinateur)

| # | Constat | Cause racine vérifiée en source | Correction |
|---|---|---|---|
| 1 | Le confinement initial était contourné : `init` canonisait la **racine possédée** avant tout contrôle et adoptait la cible d'un lien préexistant ; le test entérinait cette acceptation | une seule valeur `root` servait d'ancre et de composant possédé, sans distinction de confiance | deux notions explicites : **ancre de confiance** fournie (canonisée une fois, préfixes système préservés) et **composants possédés** (racine puis scope) construits sous elle, jamais résolus, refusés s'ils existent comme lien ou fichier, nom validé, aucun intermédiaire créé. `verifyConfinement` revérifie ancre + racine + scope avant chaque effet. Tests réécrits : racine possédée liée, scope possédé lié, composant possédé fichier, nom échappant, ancre liée (acceptée et canonisée), remplacements après init, sentinelles externes intactes, aucune clé demandée |
| 2 | Clé manquante + index absent : `loadIndex` rendait un index vide, `storeLocked` supprimait alors les fichiers scellés non référencés et `mayCreateKey` pouvait rendre vrai | l'absence d'index était traitée comme un cache vide sans vérifier la présence de données | index absent + fichiers scellés ⇒ **erreur fermée** dans `loadIndex`, avant tout nettoyage et avant toute demande de clé ; aucun fichier servi, adopté, réécrit ou supprimé ; réouverture sans rétablissement ; seule sortie `purgeAll` explicite. Le nettoyage d'orphelins reste autorisé uniquement quand un index valide a été lu (donc clé validée). Tests : fournisseur qui pourrait créer jamais sollicité, preuve inchangée, réouverture, autre scope sous la même ancre, récupération par `purgeAll` |
| 3 | La fixture déclarait `let key = KeyFixture()` puis le réinitialisait dans `init` | double initialisation d'une propriété `let` | une seule initialisation (`let key: KeyFixture` affecté dans `init`), fournisseur injecté conservé pour `makeCache`/réouverture et compteurs ; relecture des nouveaux tests pour les redéclarations (aucune autre) |

Budget de corrections : **2 sur 2** consommées. Aucune assertion de quotas, de purge, d'AAD ou d'erreurs n'a été retirée ; l'espace Keychain de test reste distinct de la production. Aucune UI, aucun format serveur, aucun transport, aucune politique de conservation, aucun effacement d'intentions n'est introduit.
