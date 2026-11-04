# Médias #97 — T2b4 : cache local authentifié, sans rendu ni réseau

Base : `e2edc85ed092237016620079d52d11eb7a2d02b5` (branche `tomyrms/issues-medias-cache-97`, worktree `issues-medias-cache-97`). Les preuves Apple 1515/1515 et Linux des runs `41906356835`/`41906366352` portent sur **cette base**, pas sur le code ajouté ici.

Ce lot livre **un cache local**. Il n'est branché ni au coffre média, ni à l'outbox, ni au contenu v3, ni à l'UI. Aucun écran, aucune copie produit, aucun rendu, aucune requête réseau, aucune activation de parcours. Aucun fichier PDF temporaire en clair n'est introduit : le futur rendu PDF passe par `PDFDocument(data:)` (addendum du 4 novembre 2026) et ne concerne pas ce lot.

## 1. Contrat reçu et interface

`MessagingMediaCache` (§4.5 du contrat `medias-exploitation-contrat-20261104.md`) est fourni **tel quel**, avec deux ajouts rendus nécessaires pour que l'interface soit exécutable :

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

Implémentation : `actor MessagingProtectedMediaCache`, **un scope complet par instance** (compte, école, époque, URL d'API). Les erreurs sont celles du module (`MessagingFailure.contextChanged`, `.invalidResponse`, `.protectionUnavailable`) : aucune énumération d'affichage, aucun texte d'interface, aucun `LocalizedError` n'est ajouté.

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

Aucune clé, aucun nom de fichier, aucun MIME, aucun contenu, aucun identifiant de personne ou de média n'apparaît en clair dans un nom de fichier, dans un répertoire ou dans un journal : le cache **n'écrit aucun journal**, ni `print`, ni `MessagingDiagnostics`, ni `Logger`.

**AAD** de chaque fichier : `drivy.media.cache.v1|<empreinte scope>|<genre>|<mediaID>|aad`. Elle lie la **version du format**, le **scope**, l'**identité média** et le **genre** (`original`/`thumbnail`). Conséquence testée : un fichier déplacé d'une identité à l'autre, d'un scope à l'autre ou d'un genre à l'autre ne s'ouvre pas.

**Chiffrement** : AES-GCM par fichier (CryptoKit), nonce aléatoire par scellement, tag vérifié à la lecture. L'index est scellé avec sa propre AAD (`…|<empreinte scope>|index|aad`) : ses métadonnées (identité, genre, taille, rang LRU) ne sont jamais en clair.

Écriture : fichier temporaire protégé → `write` + `synchronize` → `replaceItemAt`/`moveItem` → `protect` → `F_FULLFSYNC` sur le fichier et `fsync` sur le répertoire. **Aucun repli** : si le scellement, l'écriture ou la synchronisation échoue, l'appel échoue et rien n'est réputé stocké.

## 3. Clé Keychain : cycle exact

- Service `ch.drivy.messaging.media.cache.v1`, compte `media-cache-key-v1` : **distincts** du snapshot protégé de la messagerie (`ch.drivy.messaging.local.v1`).
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false` (exclue de la synchronisation iCloud).
- Création : uniquement si aucun fichier `.sealed` n'existe sous la racine (aucun scope). Face à des fichiers existants, une clé absente est une **erreur fermée** (`protectionUnavailable`) : aucune clé n'est jamais recréée en silence.
- Suppression : `purge` et `purgeAll` **ne suppriment pas** la clé, car elle est partagée par tous les scopes de l'appareil ; la détruire casserait les autres scopes. Sa destruction relève d'un retrait Keychain hors de ce composant (désinstallation, réinitialisation de l'appareil).
- `unlink` supprime le nom et les octets lisibles par le système. Ce cache ne promet **ni** effacement physique du support SSD, **ni** effacement garanti de la mémoire : aucune de ces deux propriétés n'est démontrable ici.

## 4. Plafond, LRU, éviction

- Plafond technique **50 Mio par scope** (`52_428_800`), originaux + miniatures + index compris. C'est une **garde de ressources réversible**, pas une politique de conservation : aucune TTL, aucune purge automatique, aucune durée de rétention serveur n'est introduite.
- La consommation réelle est **mesurée sur le disque** (somme des fichiers du scope), jamais déduite d'un index qui pourrait être incomplet.
- L'éviction part **par média entier** : original et miniature ensemble. Ordre : rang LRU croissant, puis identité média croissante à égalité (ordre déterministe testé). Les artefacts orphelins (temporaire, fichier non indexé) partent en premier.
- Une lecture **effective** (`data`/`thumbnail` réussie) actualise le rang LRU, persisté dans l'index scellé : l'ordre survit à la réouverture.
- Seules les copies du cache sont évincées. Aucune intention d'outbox n'est touchée : ce composant ne connaît que son répertoire.

## 5. Cohérence, interruption, durabilité

- L'**index est un indicateur**, pas la source de vérité : les chemins de fichiers sont déterministes, donc une lecture n'a pas besoin de l'index pour trouver un média. Un index incomplet ne peut ni cacher un fichier existant ni fabriquer un faux cache.
- Fichier **réellement absent** → `nil` (et l'entrée d'index orpheline est retirée). Mauvais tag, mauvaise clé, index illisible, entrée incohérente → **erreur fermée** (`protectionUnavailable`), jamais un cache vide présenté comme valide.
- Ordre d'écriture : fichier média puis index. Si l'index ne peut pas être scellé, le fichier média est supprimé et l'appel échoue. Si le processus est tué entre les deux, le fichier devient un orphelin évincé au prochain passage : aucun succès n'a été annoncé, rien n'est ressuscité.
- Ordre de purge : fichiers puis index. Une purge interrompue ne peut pas ressusciter un fichier : sa lecture renvoie `nil`.
- Aucun succès d'écriture ou de purge n'est rendu avant la synchronisation durable disponible (`F_FULLFSYNC` + `fsync` du répertoire).

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

ImageIO ne sert qu'à lire **type et dimensions** : `CGImageSourceCreateImageAtIndex` n'est jamais appelé, aucune miniature n'est générée, aucune allocation proportionnelle aux pixels n'est faite. Aucun chemin, aucune URL de fichier et aucun importateur ne sont acceptés par l'API : seuls des `Data` et un `UUID` entrent.

## 7. Concurrence et isolation

- Deux instances du même scope (deux feuilles) partagent le même répertoire : la section critique est sérialisée par un **verrou statique `NSLock`**, car l'acteur seul est réentrant aux points de suspension.
- **Aucun `await` sous le verrou** : toutes les opérations de fichiers et de Keychain sont synchrones ; vérifié en source (0 occurrence de `await` dans le fichier).
- Le scope attendu est comparé **avant** chaque accès ; un appel d'un autre scope lève `contextChanged` et ne rend jamais de données.
- Une seconde instance du même scope ne peut donc perdre une écriture ni dépasser le quota : lecture-modification-écriture de l'index est entièrement sous le verrou.

## 8. Tests écrits (36)

`apps/ios/DrivyTests/MessagingMediaCacheTests.swift`. Toutes les images sont **synthétiques** (aplat uni ou bruit déterministe généré en mémoire) : aucune photo, aucun fichier importé, aucune donnée de personne, aucune bibliothèque ajoutée.

- aller-retour et réouverture (original + miniature) sur clé fixture ;
- aucun sentinelle, identifiant, genre, MIME ni nom en clair dans les fichiers scellés et l'index ; noms opaques de 64 caractères hexadécimaux ;
- bornes original : 0 refusé, 1 octet accepté, 4 Mio accepté, 4 Mio + 1 refusé, rien d'écrit pour un refus ;
- miniatures : JPEG et PNG 512 px acceptés ; PDF et octets arbitraires refusés ; 513 px refusé (deux axes) ; PNG bruité > 128 Kio refusé (fixture vérifiée au-delà de la borne) ;
- AAD : autres octets pour le même `mediaID` refusés ; fichier échangé entre deux médias refusé ; miniature à la place de l'original refusée ; fichier copié d'un autre scope refusé ;
- clé : absente avec fichiers existants → erreur fermée et **aucune** demande de création (`mayCreate == false`) ; clé étrangère → erreur fermée, jamais un cache vide ;
- index corrompu → erreur fermée sur lecture, écriture et purge, octets corrompus **non remplacés** ;
- fichier supprimé → `nil` (aucun repli mémoire) ; média purgé → absent après réouverture et après une écriture suivante ;
- quota : éviction du LRU, lecture qui rajeunit une entrée et change la victime suivante, original + miniature évincés ensemble, ordre LRU conservé après réouverture, quota respecté après chaque écriture, ordre déterministe à égalité ;
- purge : les deux genres, doublons et liste vide idempotents ; `purge`/`purgeAll` d'un scope ne touchent jamais l'autre ; `purgeAll` vide tout et le cache reste utilisable ;
- pannes réelles : répertoire de scope en `0500` → écriture et purge échouent sans faux succès, index existant intact après restauration ;
- fichier de 8 Mio sur disque → refusé (borne avant lecture) ; fichier média lié symboliquement → refusé ; répertoire de scope lié symboliquement → refusé à l'initialisation ;
- autres scopes : `contextChanged` sur lecture et purge, aucune donnée rendue ;
- scope sans époque ou sans API → refusé à l'initialisation ;
- deux instances, 20 écritures concurrentes : aucune perte ; 12 écritures concurrentes sous quota 12 000 : quota respecté, données relues conformes ;
- surface du protocole exercée à travers l'existence `any MessagingMediaCache`, bornes publiées vérifiées (4 Mio, 128 Kio, 512 px, 50 Mio) ;
- un seul cas traverse la **Keychain réelle** via `init(scope:)` (service et compte dédiés), puis `purgeAll`.

Les tests de panne sont **contrôlés** (permissions POSIX, fichiers forgés) : ce ne sont **pas** des coupures d'alimentation physiques, et ils ne prouvent ni l'atomicité du support ni la tenue après crash réel.

## 9. Ce qui n'a PAS été exécuté

**NON EXÉCUTÉ — aucun outil Apple sur ce poste (Windows).** Aucun test Swift de ce lot n'a été compilé ni exécuté ; aucun RED/GREEN Swift n'est revendiqué. Les tests ont été écrits **avant** l'implémentation (ordre de création des fichiers), puis relus ; ils ne sont **pas** prouvés. Aucun port Python n'est présenté comme un test : le seul script jetable utilisé vérifie l'équilibre des délimiteurs et le comptage des méthodes, rien de plus.

À lancer sur un runner Apple, au SHA de livraison exact :

```bash
xcodegen generate --spec apps/ios/project.yml
xcodebuild test \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DrivyTests/MessagingMediaCacheTests \
  -derivedDataPath artifacts/ios/DerivedData
```

La sélection `DRIVY_IOS_UNIT_TEST_SCOPE=messaging` de `scripts/ios/test-selection.sh` **n'inclut pas** cette classe : ce fichier appartient à un autre lot et n'a pas été modifié. Seul le `-only-testing` ci-dessus l'exécute tant que son propriétaire ne l'ajoute pas.

Non vérifiable ici : compilation Swift 6 (`SWIFT_STRICT_CONCURRENCY: complete`), comportement réel de `FileProtectionType.complete` sur simulateur, disponibilité Keychain en CI, sémantique exacte de `replaceItemAt`/`F_FULLFSYNC` sur APFS, et le rendu effectif de `CGImageSourceCopyPropertiesAtIndex` sur les fixtures générées.

## 10. Modèle, skills, Codebase Memory réellement utilisés

- **Modèle** : `opencode-go/deepseek-v4.1-flash` (DeepSeek V4.1 Flash), sans paramètre de modèle ni d'effort ; révision et effort non exposés par ce runtime, donc **non vérifiables**.
- **Skills Superpowers chargés (outil `skill`, réellement)** :
  - `test-driven-development` — base `C:\Users\jtoma\.config\opencode\node_modules\superpowers\skills\test-driven-development` : tests écrits avant le code, cycle RED → GREEN **non exécuté** faute de compilateur Swift.
  - `verification-before-completion` — base `…\superpowers\skills\verification-before-completion` : chargé avant la livraison ; il interdit de présenter le lot comme compilé ou testé, ce que ce document respecte.
  - `systematic-debugging` non invoqué : aucun bogue produit à reproduire, seulement du code neuf.
  - Aucun sous-agent, aucune revue indépendante simulée, aucun autre skill.
- **Codebase Memory** : projet **unique** de ce worktree, `drivy-media-cache-97-20261104`, indexé par chemin absolu `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-cache-97` (aucun index voisin utilisé).
  - `index_status` : racine du worktree, `status: ready`, `indexed_at 2026-11-04T20:59:09Z`, 39 494 nœuds / 170 688 arêtes.
  - `search_graph` : `MessagingMediaCache` → **0 résultat** dans la base (le type n'existait pas), `MessagingProtectedStore` (classe et méthodes, `MessagingProtectedStore.swift:8-290`), `MessagingMediaAttachment` (`MessagingMediaContent.swift:14-101`), `MessagingScope` (`MessagingContracts.swift:4-12`), `MessagingMediaOutbox`/`MessagingPendingMedia` → **0 résultat** (lots d'un autre worker, non touchés).
  - Lecture source directe des fichiers cités (`MessagingProtectedStore.swift`, `MessagingContracts.swift`, `MessagingMediaContent.swift`, `MessagingMediaCryptography.swift`, `MessagingDiagnostics.swift`, `MessagingProtectedStoreTests.swift`, `scripts/ios/test-selection.sh`, `apps/ios/project.yml`).
  - Lacunes assumées : 19 `parse_partial` hors périmètre, `openapi.yaml` non analysable.

## 11. Commandes réellement exécutées (Windows, sans Swift)

| # | Commande | Résultat | Code |
|---|---|---|---|
| 1 | `git rev-parse HEAD` | `e2edc85ed092237016620079d52d11eb7a2d02b5` (base imposée) | 0 |
| 2 | `index_repository` + `index_status` (MCP, chemin absolu) | racine du worktree, `ready`, 39 494 nœuds | 0 |
| 3 | `search_graph` ×7 (MCP) | 0 `MessagingMediaCache` en base ; dépendances existantes localisées | 0 |
| 4 | `Select-String 'await '` dans le fichier produit | **0** occurrence : aucun `await` sous verrou | 0 |
| 5 | `Select-String 'print(\|MessagingDiagnostics\|Logger'` | aucune écriture de journal (2 correspondances = « fingerprint ») | 0 |
| 6 | `Select-String 'Data\(contentsOf:'` | **1** occurrence, après contrôle de taille (`readBounded`) | 0 |
| 7 | Script Python jetable : équilibre des délimiteurs des deux fichiers | `balanced` ×2 | 0 |
| 8 | Comptage des méthodes de test + doublons | 36 méthodes, 36 noms uniques | 0 |
| 9 | `git status --porcelain` | 2 fichiers nouveaux, aucun fichier existant modifié | 0 |

Aucun port Python n'est présenté comme une preuve de comportement Swift : les seules preuves réelles sont les lignes de ce tableau, et le reste est **à exécuter sur Apple**.

## 12. Fichiers

| Fichier | Rôle |
|---|---|
| `apps/ios/Drivy/MessagingCore/MessagingMediaCache.swift` | protocole §4.5 + deux ajouts, acteur scellé AES-GCM, index scellé, quota/LRU, purge, clé Keychain dédiée |
| `apps/ios/DrivyTests/MessagingMediaCacheTests.swift` | 36 tests, fixtures synthétiques, pannes contrôlées |
| `docs/implementation/messaging-media-97-cache.md` | ce document |

Aucune dépendance, aucun `project.yml` (sources par répertoire), aucun lockfile, aucun workflow, aucun fichier existant (ni `MessagingProtectedStore`, ni outbox, ni primitives crypto, ni transport, ni contenu, ni coordination/factory/UI, ni `STATUS.md`, ni conception) modifié.

## 13. Risques et limites honnêtes

- **Aucune preuve Apple** : le code peut ne pas compiler ; aucun test de ce lot n'a tourné.
- **Aucun RED/GREEN exécuté** : les tests sont écrits et relus, pas prouvés ; plusieurs d'entre eux dépendent de détails d'ImageIO, de `FileProtection` et de Keychain qui ne sont pas observables ici.
- **Pannes simulées** : permissions POSIX et fichiers forgés, pas de coupure d'alimentation ; ni l'atomicité du support ni la reprise après crash réel ne sont démontrées.
- **`unlink` ≠ effacement** : ni effacement physique SSD, ni zéroïsation mémoire ne sont promis ni testés.
- **Clé partagée** : `purgeAll` ne détruit pas la clé ; les octets sont supprimés, la clé reste disponible pour les autres scopes. Un futur besoin de destruction par appareil demandera une clé par scope (décision non prise ici).
- **Index réécrit à chaque lecture** : la LRU durable coûte une écriture scellée par lecture effective ; sur un scope très sollicité, c'est un coût I/O réel, non mesuré.
- **Quota mesuré par énumération** : le calcul parcourt le répertoire du scope à chaque écriture et éviction ; coût proportionnel au nombre de fichiers, non mesuré.
- **Éviction par média entier** : un média avec un original volumineux et une miniature minuscule est évincé en bloc, ce qui est le comportement voulu mais peut retirer une miniature encore utile.
- **Fichier orphelin** : un crash entre l'écriture du média et celle de l'index laisse un orphelin supprimé plus tard ; il n'est jamais servi.
- **`replaceItemAt`/`F_FULLFSYNC`** : les garanties exactes sur APFS/simulateur restent à vérifier sur Apple.
- **Pas de branchement** : outbox, coffre, contenu v3, UI et déconnexion restent à faire dans leurs lots respectifs ; `purgeAll` est fourni mais appelé nulle part.
- **Politique de conservation** : aucune n'est décidée. #68 reste ouverte ; ce lot ne fournit ni résidence, ni restauration, ni preuve d'exploitation.
