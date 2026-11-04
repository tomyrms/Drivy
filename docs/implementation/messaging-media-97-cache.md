# Médias #97 — T2b4 : cache local authentifié, sans rendu ni réseau

Base : `e2edc85ed092237016620079d52d11eb7a2d02b5` (branche `tomyrms/issues-medias-cache-97`, worktree `issues-medias-cache-97`). Livraison initiale `ed48dbb001b85b891a9385db9ce6fce48304226d`, puis **correction 1** (§14) : verrou Swift 6, purge durable, orphelins, confinement, quota après lecture, Keychain isolé. Les preuves Apple 1515/1515 et Linux des runs `41906356835`/`41906366352` portent sur la **base**, pas sur le code ajouté ici.

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
- Sans `purgeAll`, aucune primitive appelable à la sortie de contexte, à la fin de lien ou à la suppression n'existe. `purgeAll` **n'est branchée à rien** : aucun logout silencieux, aucune UI, aucune décision de conservation n'est prise ici.

Implémentation : `actor MessagingProtectedMediaCache`, **un scope complet par instance** (compte, école, époque, URL d'API). Les erreurs sont celles du module (`MessagingFailure.contextChanged`, `.invalidResponse`, `.protectionUnavailable`) : aucune énumération d'affichage, aucun texte d'interface, aucun `LocalizedError`.

### Ce que le cache reçoit, exactement

`Data` est le **contenu déjà authentifié et déchiffré en mémoire** par le consommateur (Megolm pour le fichier, contenu Matrix pour les métadonnées). Le cache ne déchiffre rien de bout en bout, ne vérifie aucun hash de transport, ne compare **jamais** le SHA-256 du chiffré téléchargé aux octets clairs : c'est une erreur de contrat (§3.10). Il **rechiffre au repos** en AES-GCM.

Aucun déchiffrement E2EE, aucun réseau, aucune génération de miniature, aucun rendu dans ce fichier.

## 2. Stockage : chemins opaques, AAD, scellement

| Élément | Valeur |
|---|---|
| Racine | `Application Support/MessagingMediaCache` (dédiée, `.completeFileProtection`, `isExcludedFromBackup`) |
| Répertoire de scope | `SHA256("accountID|schoolID|epoch|apiBaseURL")` en hexadécimal (64 caractères) |
| Fichier média | `SHA256("drivy.media.cache.v1|<empreinte scope>|<genre>|<mediaID>")` + `.sealed` |
| Index | `index.sealed` |
| Temporaire d'écriture | `<UUID aléatoire>.tmp`, supprimé en cas d'échec |

Aucune clé, aucun nom de fichier, aucun MIME, aucun contenu, aucun identifiant de personne ou de média n'apparaît en clair dans un nom de fichier, dans un répertoire ou dans un journal : le cache **n'écrit aucun journal** (ni `print`, ni `MessagingDiagnostics`, ni `Logger`).

**AAD** de chaque fichier : `drivy.media.cache.v1|<empreinte scope>|<genre>|<mediaID>|aad`. Elle lie la **version du format**, le **scope**, l'**identité média** et le **genre**. Conséquence testée : un fichier déplacé d'une identité à l'autre, d'un scope à l'autre ou d'un genre à l'autre ne s'ouvre pas.

**Chiffrement** : AES-GCM par fichier (CryptoKit), nonce aléatoire par scellement, tag vérifié à la lecture. L'index est scellé avec sa propre AAD (`…|<empreinte scope>|index|aad`) : ses métadonnées (identité, genre, taille, rang LRU) ne sont jamais en clair.

Écriture : fichier temporaire protégé → `write` + `synchronize` → `close` (fermé sur **tous** les chemins, échec compris) → `replaceItemAt`/`moveItem` → `protect` → `F_FULLFSYNC` sur le fichier et `fsync` sur le répertoire. **Aucun repli** : si le scellement, l'écriture ou la synchronisation échoue, l'appel échoue et rien n'est réputé stocké ; le fichier non commité est retiré et le répertoire synchronisé.

## 3. Clé Keychain : cycle exact

- Espace de production : service `ch.drivy.messaging.media.cache.v1`, compte `media-cache-key-v1` (`MessagingMediaCacheKeychain.production`), **distincts** du snapshot protégé de la messagerie.
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false` (exclue de la synchronisation iCloud).
- Création : uniquement si aucun fichier `.sealed` n'existe sous la racine. Face à des fichiers existants, une clé absente est une **erreur fermée** : aucune clé n'est jamais recréée en silence.
- Suppression : `purge` et `purgeAll` **ne suppriment pas** la clé, car elle est partagée par tous les scopes de l'appareil. Sa destruction relève d'un retrait Keychain hors de ce composant.
- Injection : `keychainKey(mayCreate:namespace:)` est interne et paramétré par un espace nommé. Les tests n'utilisent qu'un **espace temporaire qui leur est propre** et ne lisent ni ne suppriment jamais la clé de l'application ; la production garde `.production`. Sous Windows, Security n'est jamais appelé.
- `unlink` supprime le nom et les octets lisibles par le système. Ce cache ne promet **ni** effacement physique du support SSD, **ni** effacement garanti de la mémoire.

## 4. Plafond, LRU, éviction — et borne après lecture

- Plafond technique **50 Mio par scope** (`52_428_800`), originaux + miniatures + index compris. C'est une **garde de ressources réversible**, pas une politique de conservation : aucune TTL, aucune purge automatique, aucune durée de rétention serveur.
- La consommation réelle est **mesurée sur le disque** (somme des fichiers du scope), jamais déduite de l'index.
- L'éviction part **par média entier** : original et miniature ensemble. Ordre : rang LRU croissant, puis identité média croissante à égalité. Les artefacts orphelins partent en premier. Toute suppression est suivie d'un `fsync` du répertoire avant de rendre la main.
- Une lecture **effective** actualise le rang LRU dans l'index scellé : l'ordre survit à la réouverture.
- **La borne s'applique aussi après une lecture** : toute opération qui fait croître l'index (compteur LRU compris), y compris une écriture idempotente des mêmes octets, repasse par `commit` → `saveIndex` → `enforceQuota`. Si le média conservé et son index ne tiennent plus, l'issue est **fermée** (`protectionUnavailable`), jamais un dépassement silencieux.
- Seules les copies du cache sont évincées. Aucune intention d'outbox n'est touchée : ce composant ne connaît que son répertoire.

## 5. Cohérence : orphelins jamais servis, interruptions, durabilité

Règle de cette première livraison, explicite et testée :

- **Un fichier qu'aucun index valide ne référence n'est jamais servi.** Il est nettoyé de façon contrôlée ; l'échec du nettoyage est propagé (`protectionUnavailable`), jamais un faux cache vide.
- **Un index manquant alors que des fichiers scellés existent n'est pas un cache vide** : les fichiers non référencés ne sont ni adoptés ni lus, ils sont écartés. La lecture du média concerné renvoie `nil` après nettoyage ; une écriture nettoie tous les non-référencés avant d'écrire.
- **L'index n'est pas une source de vérité et ne reconstruit rien.** Un fichier purgé ne peut pas être ressuscité depuis l'index : la purge supprime d'abord les fichiers, puis l'index ; un fichier absent renvoie `nil` et l'entrée orpheline est retirée.
- Fichier **réellement absent** → `nil`. Mauvais tag, mauvaise clé, index illisible, entrée incohérente → **erreur fermée**.
- Ordre d'écriture : fichier média puis index. Si l'index ne peut pas être scellé, le fichier média est retiré, le répertoire synchronisé, et l'appel échoue. Un arrêt brutal entre les deux laisse un orphelin qui n'est jamais servi et sera nettoyé.
- Aucun succès d'écriture ou de purge n'est rendu avant la synchronisation durable disponible (`F_FULLFSYNC` + `fsync`), y compris pour `purgeAll` qui synchronise le répertoire après ses suppressions.

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

ImageIO ne sert qu'à lire **type et dimensions** : `CGImageSourceCreateImageAtIndex` n'est jamais appelé. Aucun chemin, aucune URL de fichier et aucun importateur ne sont acceptés par l'API : seuls des `Data` et un `UUID` entrent.

## 7. Concurrence, confinement, isolation

- Deux instances du même scope partagent le même répertoire : la section critique est sérialisée par un **verrou statique**. `NSLock.lock`/`unlock` portent `noasync` : elles ne sont **jamais** appelées depuis un contexte async, mais depuis la fonction **synchrone** `withIOLock` (`NSLock.withLock`). **Aucun `await`** ne peut s'y glisser (vérifié en source).
- Le scope attendu est comparé **avant** chaque accès ; un appel d'un autre scope lève `contextChanged` et ne rend jamais de données.
- **Confinement** : la racine est canonisée **une fois** à la construction (`resolvingSymlinksInPath`, donc `/var` → `/private/var` reste légitime), puis, avant **chaque** effet (lecture, écriture, éviction, purge, purgeAll), sont revérifiés : racine et répertoire de scope réels (ni lien, ni fichier), parent de confiance réel, forme canonique inchangée, et appartenance du scope à la racine. Un remplacement de la racine ou du scope par un lien **après** l'initialisation échoue donc fermé. Un lien intermédiaire présent **avant** l'initialisation est résolu une fois : l'instance n'opère ensuite que sur le chemin canonique enregistré et ne se laisse pas rediriger si le lien change de cible.
- Limite honnête : ce n'est **pas** une protection contre une course inter-processus active pendant l'opération ; elle couvre un remplacement entre deux opérations.

## 8. Tests écrits (51)

`apps/ios/DrivyTests/MessagingMediaCacheTests.swift`. Toutes les images sont **synthétiques** (aplat uni ou bruit déterministe généré en mémoire) : aucune photo, aucun fichier importé, aucune donnée de personne, aucune bibliothèque ajoutée.

- aller-retour et réouverture (original + miniature) ; aucun sentinelle, identifiant, genre, MIME ni nom en clair dans les fichiers scellés et l'index ; noms opaques de 64 caractères hexadécimaux ;
- bornes original (0 refusé, 1 octet, 4 Mio, 4 Mio + 1 refusé, rien d'écrit pour un refus) ; miniatures JPEG/PNG 512 px acceptées, PDF et octets arbitraires refusés, 513 px refusé sur les deux axes, PNG bruité > 128 Kio refusé ;
- AAD : autres octets pour le même `mediaID` refusés ; fichier échangé entre deux médias refusé ; miniature à la place de l'original refusée ; fichier copié d'un autre scope refusé (une entrée valide existe des deux côtés) ;
- clé : absente avec fichiers existants → erreur fermée et **aucune** demande de création ; clé étrangère → erreur fermée ;
- index corrompu → erreur fermée sur lecture, écriture et purge, octets corrompus non remplacés ;
- **orphelins** : fichier sans entrée jamais servi et nettoyé ; index manquant avec fichiers scellés → jamais servi, fichiers écartés, cache utilisable ensuite ; échec réel du nettoyage (permissions) → erreur fermée sans suppression silencieuse ; point de panne de nettoyage → erreur fermée puis nettoyage contrôlé ;
- **pannes contrôlées** : échec avant le commit d'index, après le rename du fichier, à la synchronisation du fichier, et à la synchronisation du répertoire de `purgeAll` → aucun faux succès, aucune donnée servie, aucun artefact résiduel ;
- quota : éviction du LRU, lecture qui rajeunit une entrée, original + miniature ensemble, ordre persisté après réouverture, quota respecté après **chaque lecture** (borne = taille mesurée, douze lectures, passages de chiffres du compteur), deux instances, quota respecté après écritures concurrentes ;
- purge : les deux genres, doublons et liste vide idempotents ; `purge`/`purgeAll` d'un scope ne touchent jamais l'autre ; **sentinelles hors périmètre intactes** (fichier à la racine, répertoire d'un autre scope) après purge et après éviction ;
- pannes réelles : répertoire de scope en `0500` → écriture et purge échouent sans faux succès, index intact après restauration ;
- fichier de 8 Mio avec entrée valide → refusé (borne avant lecture) ; fichier média lié symboliquement → refusé ; répertoire de scope lié symboliquement à l'initialisation → refusé ; **racine remplacée par un lien après l'initialisation** → lecture, écriture, purge et purgeAll refusées ; **scope remplacé par un lien après l'initialisation** → refusé ; **lien intermédiaire avant l'initialisation** → chemin canonique seul utilisé, pas de redirection ;
- autres scopes : `contextChanged` sur lecture et purge ; scope sans époque ou sans API → refusé ;
- deux instances, 20 écritures concurrentes : aucune perte ; surface du protocole exercée à travers `any MessagingMediaCache` ; bornes publiées vérifiées (4 Mio, 128 Kio, 512 px, 50 Mio) ;
- **Security réel, espace isolé** : aller-retour de clé (création, relecture identique, 256 bits), attributs `WhenUnlockedThisDeviceOnly` et non synchronisé, refus de création sans autorisation, puis cache complet sur cette clé.

Les tests de panne sont **contrôlés** (points de panne internes bornés, permissions POSIX, fichiers forgés) : ce ne sont **pas** des coupures d'alimentation physiques, et ils ne prouvent ni l'atomicité du support ni la tenue après crash réel.

## 9. Ce qui n'a PAS été exécuté

**NON EXÉCUTÉ — aucun outil Apple sur ce poste (Windows).** Aucun test Swift de ce lot n'a été compilé ni exécuté ; aucun RED/GREEN Swift n'est revendiqué. Les tests ont été écrits **avant** l'implémentation, puis relus ; ils ne sont **pas** prouvés. Aucun port Python n'est présenté comme un test : le seul script jetable vérifie l'équilibre des délimiteurs.

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

Non vérifiable ici : compilation Swift 6 (`SWIFT_STRICT_CONCURRENCY: complete`), disponibilité de `NSLock.withLock` sur la cible (iOS 26), comportement réel de `FileProtectionType.complete` sur simulateur, sémantique de `replaceItemAt`/`F_FULLFSYNC` sur APFS, résolution des liens par `resolvingSymlinksInPath` sur le volume de test, et disponibilité Keychain en CI.

## 10. Modèle, skills, Codebase Memory réellement utilisés

- **Modèle** : `opencode-go/deepseek-v4.1-flash` (DeepSeek V4.1 Flash), sans paramètre de modèle ni d'effort ; révision et effort non exposés par ce runtime, donc **non vérifiables**.
- **Skills Superpowers chargés (outil `skill`, réellement), sur la livraison initiale et la correction** :
  - `test-driven-development` — base `C:\Users\jtoma\.config\opencode\node_modules\superpowers\skills\test-driven-development` : tests écrits avant le code, cycle RED → GREEN **non exécuté** faute de compilateur Swift.
  - `systematic-debugging` — base `…\superpowers\skills\systematic-debugging` : chargé pour la correction 1 ; chaque constat a été reproduit en source (appels `NSLock` dans un contexte async, absence de `fsync` après `purgeAll`, adoption d'un fichier non indexé, contrôles de confinement limités à l'initialisation, index réécrit sans borne après lecture, Keychain de production utilisé par un test) avant toute modification.
  - `verification-before-completion` — base `…\superpowers\skills\verification-before-completion` : chargé avant la livraison ; il interdit de présenter le lot comme compilé ou testé.
  - Aucun sous-agent, aucune revue indépendante simulée, aucun autre skill.
- **Codebase Memory** : projet **unique** de ce worktree, `drivy-media-cache-97-20261104`, indexé par chemin absolu `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-cache-97` (aucun index voisin utilisé).
  - `index_status` après réindexation avant édition : racine du worktree, `status: ready`, `indexed_at 2026-11-04T21:29:43Z`, 39 650 nœuds / 171 967 arêtes.
  - `search_graph` : `MessagingProtectedMediaCache` (classe et méthodes dans `MessagingMediaCache.swift`), `MessagingMediaCache` → 0 résultat ailleurs en base, `NSLock`/`withLock` (occurrences du paquet MatrixSDKCrypto, aucune dans le cache), `MessagingProtectedStore`, `MessagingMediaAttachment`, `MessagingScope`, `MessagingMediaOutbox`/`MessagingPendingMedia` → 0 résultat (lots d'un autre worker, non touchés).
  - `get_file_outline` du fichier produit après indexation : protocole et acteur présents, lignes à jour.
  - Lecture source directe : `MessagingProtectedStore.swift`, `MessagingContracts.swift`, `MessagingMediaContent.swift`, `MessagingMediaCryptography.swift`, `MessagingDiagnostics.swift`, `MessagingProtectedStoreTests.swift`, `scripts/ios/test-selection.sh`, `apps/ios/project.yml`.
  - Lacunes assumées : 19 `parse_partial` hors périmètre, `openapi.yaml` non analysable.

## 11. Commandes réellement exécutées (Windows, sans Swift)

| # | Commande | Résultat | Code |
|---|---|---|---|
| 1 | `git rev-parse HEAD` (avant correction) | `ed48dbb001b85b891a9385db9ce6fce48304226d` (candidat relu) | 0 |
| 2 | `index_repository` (MCP, chemin absolu) + `index_status` | racine du worktree, `ready`, 39 650 nœuds, `2026-11-04T21:29:43Z` | 0 |
| 3 | `search_graph` ×3 (correction) + `get_file_outline` (MCP) | fichier du lot indexé, dépendances localisées, 0 homonyme en base | 0 |
| 4 | `Select-String '\.lock\(\)\|\.unlock\(\)'` dans l'implémentation | **0** occurrence : plus aucun appel `noasync` direct | 0 |
| 5 | `Select-String 'withLock\|withIOLock'` | 1 définition synchrone (`withIOLock`) + 1 appel `NSLock.withLock`, 6 usages par les méthodes async | 0 |
| 6 | `Select-String 'handle\.close'` | 2 occurrences : fermeture explicite **et** dans le `catch` | 0 |
| 7 | `Select-String 'Self\.synchronize\('` | 9 occurrences, dont `purgeAll` et chaque éviction | 0 |
| 8 | `Select-String 'verifyConfinement\|samePath\|resolvingSymlinksInPath'` | 1 canonisation à la construction, vérification à l'initialisation puis avant les six effets | 0 |
| 9 | Script Python jetable : équilibre des délimiteurs des deux fichiers | `balanced` ×2 | 0 |
| 10 | Comptage des méthodes de test + doublons | 51 méthodes, 51 noms uniques | 0 |
| 11 | `Select-String 'XCTAssert\w+\([^)]*await'` dans les tests | **0** : aucun `await` dans une autoclosure XCTest | 0 |
| 12 | `git diff --check` | aucune erreur d'espacement | 0 |
| 13 | `git status --porcelain` | 3 fichiers du lot, aucun autre | 0 |

Aucun port Python n'est présenté comme une preuve de comportement Swift : les seules preuves réelles sont les lignes de ce tableau, et le reste est **à exécuter sur Apple**.

## 12. Fichiers

| Fichier | Rôle |
|---|---|
| `apps/ios/Drivy/MessagingCore/MessagingMediaCache.swift` | protocole §4.5 + deux ajouts, acteur scellé AES-GCM, index scellé, quota/LRU (y compris après lecture), purge durable, confinement, clé Keychain nommée |
| `apps/ios/DrivyTests/MessagingMediaCacheTests.swift` | 51 tests, fixtures synthétiques, pannes contrôlées, Security isolé |
| `docs/implementation/messaging-media-97-cache.md` | ce document |

Aucune dépendance, aucun `project.yml` (sources par répertoire), aucun lockfile, aucun workflow, aucun fichier existant (ni `MessagingProtectedStore`, ni outbox, ni primitives crypto, ni transport, ni contenu, ni coordination/factory/UI, ni `STATUS.md`, ni conception) modifié.

## 13. Risques et limites honnêtes

- **Aucune preuve Apple** : le code peut ne pas compiler ; aucun test de ce lot n'a tourné.
- **Aucun RED/GREEN exécuté** : plusieurs tests dépendent de détails d'ImageIO, de `FileProtection`, de `resolvingSymlinksInPath` et de Keychain qui ne sont pas observables ici.
- **Pannes simulées** : points de panne internes et permissions POSIX, pas de coupure d'alimentation ; ni l'atomicité du support ni la reprise après crash réel ne sont démontrées.
- **Confinement sans course** : la vérification couvre un remplacement entre deux opérations, pas un attaquant actif pendant l'opération ; ce n'est pas une garantie inter-processus.
- **`unlink` ≠ effacement** : ni effacement physique SSD, ni zéroïsation mémoire ne sont promis ni testés.
- **Clé partagée** : `purgeAll` ne détruit pas la clé ; un futur besoin de destruction par appareil demandera une clé par scope (décision non prise ici).
- **Index réécrit à chaque lecture** : la LRU durable coûte une écriture scellée (et une éventuelle éviction) par lecture effective ; coût I/O réel, non mesuré.
- **Quota mesuré par énumération** : le calcul parcourt le répertoire du scope à chaque écriture, lecture et éviction ; coût non mesuré.
- **Issue fermée sur quota** : une lecture peut échouer si le média conservé et son index ne tiennent plus dans la borne ; c'est voulu, mais cela signifie qu'un quota très petit rend le cache inutilisable plutôt que silencieusement dépassé.
- **Index perdu = cache perdu** : sans index valide, les fichiers scellés sont écartés (jamais adoptés). C'est la règle choisie ; un futur besoin de reconstruction demanderait un index redondant, non décidé ici.
- **Éviction par média entier** : un original volumineux emporte sa miniature, même si elle était encore utile.
- **Pas de branchement** : outbox, coffre, contenu v3, UI et déconnexion restent à faire ; `purgeAll` est fourni mais appelé nulle part.
- **Politique de conservation** : aucune n'est décidée. #68 reste ouverte ; ce lot ne fournit ni résidence, ni restauration, ni preuve d'exploitation.

## 14. Correction 1 (revue du coordinateur)

| # | Constat | Cause racine vérifiée en source | Correction |
|---|---|---|---|
| 1 | `NSLock.lock`/`unlock` appelées dans des méthodes `async` | `noasync` dans Foundation/Swift 6 : la section était synchrone mais le **contexte d'appel** async | section déplacée dans `withIOLock`, fonction **synchrone** qui appelle `NSLock.withLock` ; les méthodes de l'acteur restent `async throws` et ne contiennent aucun `await` sous verrou. Vérifié : 0 occurrence de `.lock()`/`.unlock()` |
| 2 | `purgeAll` ne synchronisait jamais le répertoire ; `FileHandle` non fermé dans le `catch` | suppressions faites sans `fsync`, et `close` seulement sur le chemin nominal | `fsync` du répertoire après chaque purge/éviction (échec propagé, point de panne `.directorySync` testé) ; `close` explicite **et** `try? handle.close()` dans le `catch` ; après échec d'index le fichier est retiré et le répertoire synchronisé ; points de panne bornés `.payloadAfterRename`, `.indexBeforeCommit`, `.fileSync`, `.directorySync`, `.orphanCleanup` pour couvrir rename et synchronisation |
| 3 | un fichier absent de l'index pouvait être servi puis réinscrit | `readLocked` lisait le chemin déterministe sans exiger d'entrée, puis `touch` adoptait l'orphelin | règle explicite : **aucun fichier sans entrée valide n'est servi** ; il est nettoyé (`discardUnreferenced`) ou l'échec est propagé ; une écriture nettoie tous les non-référencés avant d'écrire ; index manquant + fichiers scellés → jamais un cache vide, jamais une adoption. Tests : orphelin, index supprimé, échec de nettoyage (permissions et point de panne), puis réouverture |
| 4 | `verify(scope)` ne contrôlait que les champs ; les répertoires n'étaient vérifiés qu'à l'initialisation | aucun contrôle de confinement avant les effets ; `readBounded`/`removeFile` ne voyaient que le composant final | racine canonisée une fois (`resolvingSymlinksInPath`, préfixes système légitimes préservés), puis `verifyConfinement` avant **chaque** effet : racine, scope et parent réels, forme canonique inchangée, scope enfant de la racine. Tests : racine et scope remplacés par un lien après init, lien intermédiaire avant init, sentinelles hors périmètre intactes. Limite documentée : pas de course inter-processus |
| 5 | l'index pouvait croître au-delà du quota après une lecture ou une mise à jour idempotente | `readLocked`/`touch` réécrivaient l'index sans repasser par la borne | `commit` = `saveIndex` + `enforceQuota` sur **toutes** les opérations qui font croître l'index (lecture, écriture idempotente, écriture neuve) ; issue fermée si le média conservé et l'index ne tiennent plus ; éviction toujours par média entier. Tests : borne mesurée sans marge, douze lectures (compteur LRU), deux instances, réouverture |
| 6 | un test utilisait le service Keychain de production | preuve système prise sur l'espace applicatif, avec risque de lire ou supprimer une clé d'application | `keychainKey(mayCreate:namespace:)` paramétré, `.production` conservé par défaut ; tests sur un espace **temporaire propre** (service unique, suppression limitée à cet espace, attributs vérifiés). Aucun Keychain réel sous Windows |

Budget de corrections : **1 sur 2** consommée. Aucune assertion de données, de contexte ou de concurrence n'a été retirée ; les tests contradictoires avec la nouvelle règle d'orphelin (échange inter-scopes, fichier surdimensionné) ont été reconstruits avec une entrée valide pour continuer à prouver l'AAD et la borne de lecture.
