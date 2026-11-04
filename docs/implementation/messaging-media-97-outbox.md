# File média durable chiffrée (#97, T2b3)

Date : 4 novembre 2026. Base : `e2edc85ed092237016620079d52d11eb7a2d02b5` (`tomyrms/issues-medias-outbox-97`).
Portée : **persistance locale de l'intention média** uniquement. Aucun réseau, aucune UI, aucun cache, aucun coordinateur, aucun chiffrement Megolm, aucun envoi.

## Livraison

| Fichier | Rôle |
|---|---|
| `apps/ios/Drivy/MessagingCore/MessagingMediaOutbox.swift` | types, protocoles, Keychain dédiée, système de fichiers, acteur de file |
| `apps/ios/DrivyTests/MessagingMediaOutboxTests.swift` | tests Apple préparés (non exécutés sur le poste Windows) |
| ce document | décisions, bornes, preuves attendues et limites |

Aucun fichier existant n'est modifié : ni le coffre texte (plafond 2 Mio intact), ni les contrats, ni les DTO HTTP, ni `project.yml`, ni `STATUS.md`, ni la conception, ni le candidat intégré.

## Interface livrée

Le protocole du contrat §4.5 est conservé tel quel :

```swift
protocol MessagingMediaOutbox: Sendable {
    func put(_ pending: MessagingPendingMedia, scope: MessagingScope) async throws
    func entries(scope: MessagingScope) async throws -> [MessagingPendingMedia]
    func remove(mediaID: UUID, scope: MessagingScope) async throws
}
```

L'extension demandée est un **protocole distinct**, pour ne pas élargir §4.5 :

```swift
protocol MessagingMediaOutboxEnvelope: Sendable {
    func replaceEnvelope(mediaID: UUID, expected: MessagingCiphertext?,
                         replacement: MessagingCiphertext, scope: MessagingScope) async throws
}
```

`MessagingPendingMedia` porte `clientMessageID`, `conversationID`, `sealed`, `content`, `mentionPersonIDs`, `replyToMessageID`, `createdAt` et `messageCiphertext` (`nil` avant Megolm). `mediaID` est dérivé de `sealed.mediaID` ; aucun champ n'est modifiable. Le type n'est pas `Codable` : un DTO privé `StoredRecord` assure l'encodage validé, et `MessagingSealedMedia` reste inchangé.

`MessagingProtectedMediaOutbox` est un acteur initialisé pour **un** scope complet. Deux ouvertures sont disponibles :

- `init(scope:)` : production, racine `Application Support`, Keychain locale ;
- `init(scope:root:keyStore:fileSystem:limits:)` : interne, injectable par les tests (racine temporaire, clés synthétiques, E/S fautives, bornes réduites).

## Disposition et confidentialité

```
Application Support/
  MessagingMediaOutbox/
    <empreinte SHA-256 du scope>/          # jamais compte, école, époque ni URL en clair
      <digest SHA-256 de l'intention>.sealed
      media-outbox-tmp-<uuid>.tmp          # transitoire, jamais conservé après succès
```

- Empreinte du scope : SHA-256 de `accountID|schoolID|accessEpoch|apiBaseURL` (même forme que le store texte).
- Digest du fichier : SHA-256 de `media-outbox-file-v1|<empreinte>|<mediaID minuscule>`. Un nom de pièce, un identifiant ou une clé ne sont **jamais** des noms de fichier.
- AAD AES-GCM : `media-outbox-v1|<empreinte>|<digest>`. Le record contient en plus `version`, `scopeFingerprint` et `mediaID`, et l'acteur revérifie que `digest(mediaID)` égale le nom : un fichier déplacé vers un autre scope ou renommé vers une autre intention échoue fermé.
- Clé AES-256 dédiée par scope : service `ch.drivy.messaging.media-outbox.v1`, compte = empreinte du scope, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false`. Aucune clé n'est lue hors Keychain en production.
- Dossier et fichiers : `completeFileProtection` et `isExcludedFromBackup`. Le temporaire reçoit la même protection avant écriture.
- Une archive = un fichier AES-GCM. Seuls les octets scellés sont écrits ; le chiffré média, le nom, la légende et les enveloppes ne sont lisibles qu'après ouverture AES-GCM.
- Aucune éviction automatique, aucune purge : cette tâche ne décide d'aucune politique de conservation.

## Validation avant conservation

`put` et `replaceEnvelope` valident avant toute écriture :

1. scope identique champ par champ, `accessEpoch > 0`, `apiBaseURL` non vide ;
2. chiffré média `1…4 194 304` octets ;
3. `content.media.id == sealed.mediaID`, `size == sealed.byteSize`, `file == sealed.info` ;
4. informations de chiffrement canoniques et SHA-256 du chiffré vérifiés par `AESCTRMediaCryptography` (primitive T2a, aucun état, aucune clé créée) ;
5. mentions `≤ 8` et uniques ;
6. contenu Matrix complet — namespace `ch.drivy.messaging`, mentions comprises — `≤ 6 000` octets par `MessagingMediaContent.messageContent` ;
7. enveloppe Megolm, si présente : schéma `1…80` octets, `keyID` `1…128` octets, charge non vide `≤ 9 000` octets (donc `≤ 12 000` caractères base64), `expectedMembersEpoch > 0` ;
8. `createdAt` fini.

Aucune de ces validations n'appelle le réseau ni un chiffrement de message. Les erreurs sont des cas fermés de `MessagingFailure`, sans identifiant, chemin, clé, hash ni contenu :

| Situation | Refus |
|---|---|
| intention incohérente, taille/mentions/contenu/enveloppe hors borne | `.invalidResponse` |
| scope différent | `.contextChanged` |
| même `mediaID` ou même `clientMessageID` avec une autre intention | `.stateConflict` |
| remplacement d'enveloppe avec une valeur courante différente (`stale`) | `.stateConflict` |
| plafond d'intentions, plafond d'octets, archive illisible, clé absente, panne d'E/S | `.protectionUnavailable` |

## Durabilité, atomicité, concurrence

- Écriture : temporaire scellé dans le dossier du scope → `protect` → `F_FULLFSYNC` → `replaceItem` (cible existante) ou `moveItem` (nouvelle cible) → `protect` → `F_FULLFSYNC` → `fsync` du dossier. `put` ne rend la main qu'après ces étapes ; un échec supprime **son** temporaire et rend une erreur, jamais un succès partiel.
- `entries` contrôle la taille de chaque archive **avant** lecture/allocation (`≤ 6 Mio`), refuse les liens symboliques, les fichiers non réguliers et tout nom inattendu du dossier. Un record corrompu, une clé absente ou une clé différente échoue fermé : jamais de liste vide trompeuse, jamais de nouvelle clé créée face à des données.
- Une clé n'est créée que si le scope ne contient **aucune** archive. `key(create: false)` est utilisé pour toute lecture et pour tout remplacement.
- Ordre de `entries` : `createdAt` croissant, puis identifiant média croissant. Déterministe après réouverture.
- Toutes les instances d'un même processus (y compris deux instances du même scope) partagent un `NSLock` statique qui englobe lecture, contrôle de quota et écriture. L'acteur seul ne garantirait pas l'absence de perte entre instances. La section critique ne contient aucun `await`.
- `remove` absent est idempotent ; un retrait existant n'est un succès qu'après `fsync` du dossier ; une erreur d'E/S est rendue, jamais masquée.
- `replaceEnvelope` compare l'enveloppe courante à `expected`, refuse `stale`, n'écrit que si la valeur change, et ne touche **aucun** autre champ ni les octets média. Aucun rechiffrement n'est déclenché.

## Bornes techniques locales (réversibles)

| Borne | Valeur | Emplacement |
|---|---|---|
| intentions par scope | 20 | `MessagingMediaOutboxLimits.maximumIntents` |
| archives scellées par scope | 64 Mio (somme des tailles sur disque) | `maximumScopeBytes` |
| archive scellée | 6 Mio (contrôle avant lecture, puis après encodage) | `maximumRecordBytes` |

Ce ne sont pas des règles d'exploitation : aucune durée de conservation, aucun quota produit approuvé, aucune purge. Les tests injectent des valeurs plus petites sans modifier les valeurs par défaut.

## Tests préparés (non exécutés ici)

Le fichier `MessagingMediaOutboxTests.swift` couvre :

1. aller-retour avec clé synthétique et réouverture, noms opaques, absence de sentinelles (identifiants, nom, légende, clair, clé, IV, hash, chiffré média) sur disque ;
2. dossier et archive exclus de la sauvegarde ;
3. `0` octet refusé, `> 4 Mio` refusé, exactement `4 Mio` conservé ;
4. cohérence contenu/sceau (identité, taille, informations) ;
5. contexte compte/école/époque/URL : échec d'initialisation et refus sur chaque opération ;
6. clé absente avec données, clé différente, archive corrompue : échec fermé, aucun remplacement, aucune création de clé ; file vide lue sans créer de clé ;
7. idempotence et conflits (`mediaID`/octets/client/conversation/mentions/réponse/`clientMessageID`) ;
8. comparaison d'enveloppe, `stale`, enveloppe invalide, champs de l'intention inchangés ;
9. bornes d'enveloppe (9 000 octets acceptés, 9 001 refusés, époque nulle ou zéro refusée) ;
10. mentions (8 acceptées, 9 refusées, doublon refusé) et plafond Matrix complet atteint par des grafèmes multi-scalaires ;
11. ordre déterministe créé/identifiant, stable après réouverture ;
12. retrait idempotent, durable, et panne d'E/S rendue ;
13. deux instances concurrentes : aucune perte ;
14. plafonds d'intentions et d'octets : refus sans éviction ;
15. borne d'archive contrôlée **avant** lecture (compteur de lectures à zéro) ;
16. fichier inattendu et lien symbolique refusés ;
17. échec d'écriture : aucun temporaire résiduel, aucun octet clair capturé ;
18. échec de remplacement d'enveloppe : enveloppe d'origine intacte ;
19. copie entre scopes ou renommage vers une autre intention refusés.

Aucune clé de l'hôte ni Keychain système n'est utilisée : les tests injectent `SyntheticKeyStore` et une racine temporaire. `FaultyFileSystem` délègue au système de fichiers réel et injecte la panne demandée.

### Preuve attendue sur runner Apple

```bash
xcodegen generate --spec apps/ios/project.yml
xcodebuild build-for-testing \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO COMPILER_INDEX_STORE_ENABLE=NO \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath artifacts/ios/DerivedData
# puis, avec l'identifiant du simulateur démarré :
xcodebuild test-without-building \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -only-testing:DrivyTests/MessagingMediaOutboxTests \
  -derivedDataPath artifacts/ios/DerivedData
```

L'entrée de CI du dépôt reste `bash scripts/ios/test-simulator.sh` (job `refonte-ios.yml`) ; la commande ciblée ci-dessus ne remplace pas cette exécution complète.

### Ce que la simulation de panne ne prouve pas

- Aucun crash physique, aucune coupure d'alimentation, aucun défaut APFS/SSD : seule l'API de renommage/synchronisation est exercée.
- Aucune garantie sur la protection réelle des fichiers sur appareil verrouillé : `completeFileProtection` est demandée via la même API que le store texte, mais sa relecture n'est pas garantie sur simulateur.
- Aucun comportement réel de Keychain (verrouillage, perte, restauration) : la Keychain est remplacée par un fournisseur synthétique.
- Aucune suspension/saturation mémoire, aucun état de fond, aucune pression disque.
- Aucune protection contre un processus tiers du même appareil : le verrou est intra-processus. Un partage inter-processus (extension) exigera un verrou de fichier, hors de ce lot.
- Aucun envoi utilisateur complet : dépôt, attache, message, renvoi et UI restent hors lot.

## Risques et écarts assumés

- **Compilation inconnue** : aucun Swift/Xcode sur le poste. Aucun RED/GREEN natif n'est revendiqué ; seuls l'écriture et la revue statique ont eu lieu.
- **Sémantique d'idempotence** : un `put` de la même intention accepte un `createdAt` différent et conserve celui du premier enregistrement ; tous les autres champs doivent être identiques. Ce choix évite qu'un simple nouvel horodatage d'appel transforme une répétition en conflit, sans réécrire l'intention.
- **Octets comptés** : le plafond de 64 Mio porte sur la taille des archives scellées (JSON base64 + tag GCM), donc sur une valeur supérieure aux octets média utiles.
- **Pas de verrou inter-processus** : voir ci-dessus.
- **Pas de sweeper de temporaires au démarrage** : un temporaire orphelin d'un crash passé est ignoré, jamais supprimé pendant une opération concurrente. Aucun nettoyage destructif n'est fait hors de son propre temporaire.
- **Aucune politique de conservation** : conserver, purger ou évincer reste une décision d'exploitation (#68) non prise.
