# File média durable chiffrée (#97, T2b3)

Date : 4 novembre 2026. Base : `e2edc85ed092237016620079d52d11eb7a2d02b5` (`tomyrms/issues-medias-outbox-97`).
Portée : **persistance locale de l'intention média** uniquement. Aucun réseau, aucune UI, aucun cache, aucun coordinateur, aucun chiffrement Megolm, aucun envoi.

Cette révision répond à la revue indépendante (`media-outbox-independent-review`) : F1 (compilation des tests), F2 (racine/confinement), F3 (succès idempotent sans resynchronisation), F4 (`remove` et dossier de scope), R1–R5 (temporaires, mesure canonique, erreurs d'init, attributs Keychain, énumération bornée).

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

## Disposition, confinement et confidentialité

```
root/
  MessagingMediaOutbox/                    # composant possédé, dossier réel
    <empreinte SHA-256 du scope>/          # jamais compte, école, époque ni URL en clair
      <digest SHA-256 de l'intention>.sealed
      media-outbox-tmp-<uuid>.tmp          # transitoire, compté, jamais effacé par un autre appel
```

- Empreinte du scope : SHA-256 de `accountID|schoolID|accessEpoch|apiBaseURL` (même forme que le store texte).
- Digest du fichier : SHA-256 de `media-outbox-file-v1|<empreinte>|<mediaID minuscule>`. Un nom de pièce, un identifiant ou une clé ne sont **jamais** des noms de fichier.
- AAD AES-GCM : `media-outbox-v1|<empreinte>|<digest>`. Le record contient en plus `version`, `scopeFingerprint` et `mediaID`, et l'acteur revérifie que `digest(mediaID)` égale le nom : un fichier déplacé vers un autre scope ou renommé vers une autre intention échoue fermé.
- **Racine de confiance** : la racine fournie doit exister, être un dossier réel et ne pas être un lien symbolique. Ses ancêtres système légitimes (par exemple `/var` → `/private/var`) sont résolus **uniquement pour la comparaison** ; cette résolution n'autorise aucun lien dans les composants possédés.
- **Composants possédés** : `root/MessagingMediaOutbox` puis `<racine>/<empreinte>` sont contrôlés (`lstat`) **avant** toute création ou protection : un lien, même pendant, est refusé ; un dossier existant doit être un vrai dossier ; après création, le chemin résolu doit correspondre exactement à `racine canonique/MessagingMediaOutbox/<empreinte>`.
- Ces trois contrôles sont refaits au début de chaque opération, juste avant un renommage, juste avant un `unlink`, et avant toute resynchronisation idempotente. Un dossier de scope ou un ancêtre remplacé après l'ouverture fait échouer `put`, `entries`, `remove` et `replaceEnvelope` **avant tout effet**.
- Les erreurs d'initialisation sont fermées (`MessagingFailure.protectionUnavailable`) : aucun `NSError`, `userInfo` ou chemin libre ne remonte.
- Clé AES-256 dédiée par scope : service `ch.drivy.messaging.media-outbox.v1`, compte = empreinte du scope, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false`. Une clé préexistante dont l'accessibilité ou la synchronisation ne correspond pas est refusée : elle n'est ni utilisée, ni remplacée, ni élargie.
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
6. contenu Matrix complet — namespace `ch.drivy.messaging`, mentions comprises — `≤ 6 000` octets, **mesuré dans la forme canonique réellement émise** : `MatrixMessagingCryptography.userID` (`@uuid:drivy`), exactement comme `encryptMatrixContent` et sa borne `MessagingPlainContent.maximumV3ByteCount`. Mesurer des UUID nus sous-estimait 7 octets par mention et pouvait admettre une intention inenvoyable ;
7. enveloppe Megolm, si présente : schéma `1…80` octets, `keyID` `1…128` octets, charge non vide `≤ 9 000` octets (donc `≤ 12 000` caractères base64), `expectedMembersEpoch > 0` ;
8. `createdAt` fini.

Aucune de ces validations n'appelle le réseau ni un chiffrement de message. Les erreurs sont des cas fermés de `MessagingFailure`, sans identifiant, chemin, clé, hash ni contenu :

| Situation | Refus |
|---|---|
| intention incohérente, taille/mentions/contenu/enveloppe hors borne | `.invalidResponse` |
| scope différent | `.contextChanged` |
| même `mediaID` ou même `clientMessageID` avec une autre intention | `.stateConflict` |
| remplacement d'enveloppe avec une valeur courante différente (`stale`) | `.stateConflict` |
| plafond d'intentions, plafond d'octets, archive ou temporaire illisible, clé absente/non conforme, panne d'E/S, confinement invalide | `.protectionUnavailable` |

## Durabilité, atomicité, concurrence

- Écriture : contrôle racine/composants → temporaire scellé → `protect` → `F_FULLFSYNC` → nouveau contrôle racine/composants → `replaceItem`/`moveItem` → `protect` → `F_FULLFSYNC` → `fsync` du dossier. Une erreur **après** le renommage laisse l'état neuf complet, jamais un état partiel ; l'appel rend une erreur, pas un succès.
- **Succès idempotent** : une répétition identique de `put`, ou un `replaceEnvelope` où `expected == replacement == courant`, ne réécrit pas l'intention et ne change pas `createdAt`, mais reconfirme `protect`, `F_FULLFSYNC` du fichier et `fsync` du dossier avant de rendre la main. Un échec de synchro antérieur ne peut donc pas devenir un succès silencieux.
- **Retrait** : `remove` existant supprime puis synchronise le dossier avant succès. Un `remove` dont la cible est déjà absente **synchronise quand même le dossier** avant de réussir : un premier `unlink` suivi d'un échec de synchro ne devient pas un faux succès durable. Une panne d'E/S est rendue, jamais masquée.
- `entries` contrôle la taille de chaque archive **avant** lecture/allocation (`≤ 6 Mio`), refuse les liens symboliques, les fichiers non réguliers et tout nom inattendu. Un record corrompu, une clé absente ou une clé différente échoue fermé : jamais de liste vide trompeuse, jamais de nouvelle clé créée face à des données.
- Une clé n'est créée que si le scope ne contient **aucune** archive. `key(create: false)` est utilisé pour toute lecture et pour tout remplacement.
- Ordre de `entries` : `createdAt` croissant, puis identifiant média croissant. Déterministe après réouverture.
- Toutes les instances d'un même processus (y compris deux instances du même scope) partagent un `NSLock` statique qui englobe lecture, contrôle de quota et écriture. L'acteur seul ne garantirait pas l'absence de perte entre instances. La section critique ne contient aucun `await`.
- `replaceEnvelope` compare strictement l'enveloppe courante à `expected`, refuse `stale`, n'écrit que si la valeur change, et ne touche **aucun** autre champ ni les octets média. La reprise peut relire l'état, jamais écraser une valeur concurrente. Aucun rechiffrement n'est déclenché.

## Bornes techniques locales (réversibles)

| Borne | Valeur | Emplacement |
|---|---|---|
| intentions par scope | 20 | `MessagingMediaOutboxLimits.maximumIntents` |
| archives scellées + temporaires par scope | 64 Mio (somme des tailles sur disque) | `maximumScopeBytes` |
| archive ou temporaire | 6 Mio (contrôle avant lecture, puis après encodage) | `maximumRecordBytes` |
| temporaires résiduels | 8 ; au-delà, admission refusée | `maximumResidualTemporaries` |

Ce ne sont pas des règles d'exploitation : aucune durée de conservation, aucun quota produit approuvé, aucune purge. Les tests injectent des valeurs plus petites sans modifier les valeurs par défaut.

**Temporaires résiduels** : ils sont énumérés, typés (`media-outbox-tmp-<hex>.tmp`), bornés en taille, **comptés dans les 64 Mio** et limités en nombre. Ils ne sont jamais effacés par un autre appel (une autre instance pourrait encore les publier) ; un crash répété ne peut donc ni contourner le quota ni bloquer indéfiniment l'admission sans refus explicite. L'énumération est bornée (`contents(of:limit:)`, plafond `maximumIntents + 8 + 1`) et ne charge aucune archive au-delà de `maximumIntents` : un dossier pollué est refusé avant lecture.

Vingt intentions pleine taille (≈ 5,6 Mio d'archive) dépassent 64 Mio : le plafond d'octets mord avant celui du nombre, vers onze pièces pleines. C'est cohérent avec des bornes techniques, pas avec une promesse de vingt pièces maximales simultanées.

## Tests préparés (non exécutés ici)

40 méthodes `test` couvrent :

1. aller-retour avec clé synthétique et réouverture, noms opaques, absence de sentinelles (identifiants, nom, légende, clair, clé, IV, hash, chiffré média) sur disque ;
2. création de la clé à la première écriture, réutilisation à la réouverture, aucune nouvelle clé ;
3. création puis protection des composants possédés, dans cet ordre (journal du double) ;
4. dossier et archive exclus de la sauvegarde ;
5. `0` octet refusé, `> 4 Mio` refusé, exactement `4 Mio` conservé ;
6. cohérence contenu/sceau (identité, taille, informations) ;
7. contexte compte/école/époque/URL : échec d'initialisation et refus sur chaque opération ;
8. clé absente avec données, clé différente, archive corrompue : échec fermé, aucun remplacement, aucune création ; file vide lue sans créer de clé ;
9. idempotence et conflits (`mediaID`/octets/client/conversation/mentions/réponse/`clientMessageID`), idempotence à quota plein ;
10. comparaison d'enveloppe, `stale`, enveloppe invalide, champs de l'intention inchangés ; no-op resynchronisé avant succès ;
11. bornes d'enveloppe (9 000 octets acceptés, 9 001 refusés, époque nulle ou zéro refusée) ;
12. mentions (8 acceptées, 9 refusées, doublon refusé) ; borne `6 000` atteinte exactement avec 8 mentions canoniques, et refus à `+1` octet ;
13. ordre déterministe créé/identifiant, stable après réouverture ;
14. retrait idempotent et durable, panne d'E/S rendue ; retrait absent après échec de synchro refusé jusqu'à resynchronisation ;
15. deux instances concurrentes : aucune perte ;
16. plafonds d'intentions et d'octets : refus sans éviction ;
17. borne d'archive contrôlée **avant** lecture (compteur de lectures à zéro) ;
18. fichier inattendu et lien symbolique refusés ;
19. racine liée, `root/MessagingMediaOutbox` lié : `init` refuse, aucun `createDirectory`/`protect`, sentinelles externes intactes ;
20. dossier de scope ou ancêtre remplacé après ouverture : `remove`, `put` et `entries` refusent avant tout effet, aucun fichier externe touché ;
21. pannes `protect`, `synchronizeFile` : aucun temporaire ni archive partielle, reprise réussie ;
22. échec `synchronizeDirectory` après renommage : l'appel échoue, la reprise identique resynchronise puis réussit sans réécrire l'archive ;
23. temporaire résiduel : ignoré à la lecture, compté dans le quota, plafond de 8 refusé, jamais effacé ;
24. temporaire hors taille : refusé avant lecture, jamais supprimé ;
25. `entries` au-delà de `maximumIntents` : refusé avant chargement ;
26. échec d'écriture : aucun temporaire résiduel, aucun octet clair capturé ;
27. échec de remplacement d'enveloppe : enveloppe d'origine intacte ;
28. copie entre scopes ou renommage vers une autre intention refusés ;
29. attributs de clé : accessibilité exacte, non-synchronisation, longueur 32, sur dictionnaires synthétiques (aucune Keychain).

Les assertions portent sur l'ordre des appels journalisés et sur les effets réels sur disque, jamais sur une recherche de texte dans la source. Aucune clé de l'hôte ni Keychain système n'est utilisée.

### Fixture de borne corrigée (5 novembre 2026)

`testMatrixContentCeilingUsesCanonicalUserIDs` mesure et construit désormais **le même contenu** : même sceau, mêmes 8 mentions canoniques et même légende explicite `Légende` que l'intention admise. Le cas `+1` réutilise ce sceau et n'ajoute qu'un `a` ASCII au nom ; aucun autre champ ne change. La fixture vérifie que le nom reste strictement sous 255 graphèmes, donc l'assainissement ne tronque pas l'octet ajouté. Le plafond étant validé avant le conflit d'identité, le second `put` échoue en `.invalidResponse` sur 6 001 octets, sans créer un nouveau média. Aucun RED/GREEN natif n'est revendiqué : le poste de correction ne dispose ni de Swift ni de Xcode.

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
- Aucun comportement réel de Keychain (verrouillage, perte, restauration, attributs rendus) : la Keychain est remplacée par un fournisseur synthétique ; seuls les dictionnaires d'attributs sont éprouvés.
- Aucune suspension/saturation mémoire, aucun état de fond, aucune pression disque.
- Aucune protection contre un processus tiers du même appareil : le verrou est intra-processus, et un remplacement de dossier entre le dernier contrôle et le renommage reste une course hors modèle. Un partage inter-processus (extension) exigera un verrou de fichier.
- Aucun envoi utilisateur complet : dépôt, attache, message, renvoi et UI restent hors lot.

## Risques et écarts assumés

- **Compilation inconnue** : aucun Swift/Xcode sur le poste. Aucun RED/GREEN natif n'est revendiqué ; les tests corrigent la contrainte des signatures XCTest (autoclosures non asynchrones) sans build local.
- **Sémantique d'idempotence** : un `put` de la même intention accepte un `createdAt` différent et conserve celui du premier enregistrement ; tous les autres champs doivent être identiques. Ce choix évite qu'un simple nouvel horodatage d'appel transforme une répétition en conflit, sans réécrire l'intention.
- **Octets comptés** : le plafond de 64 Mio porte sur la taille des archives scellées et des temporaires (JSON base64 + tag GCM), donc sur une valeur supérieure aux octets média utiles.
- **Pas de verrou inter-processus** : voir ci-dessus.
- **Pas de sweeper de temporaires** : un temporaire orphelin est compté et borné, jamais supprimé pendant une opération concurrente. Aucune politique de conservation n'est annoncée.
- **Aucune politique de conservation** : conserver, purger ou évincer reste une décision d'exploitation (#68) non prise.

## E0 — époque initiale des conversations médias (5 novembre 2026)

Défaut d'intégration révélé par le parcours relay réel : `validateEnvelope` exigeait `expectedMembersEpoch > 0`, alors qu'une conversation neuve a légalement `members_epoch = 0`. Le `put` initial (sans enveloppe) passait, `encryptMatrixContent` produisait bien une enveloppe à époque `0`, puis `replaceEnvelope` la refusait en `.invalidResponse` → `Runtime.invalidContent` (étape IMAGE).

Preuves : `20261023b_messaging_features.sql` déclare `members_epoch bigint NOT NULL DEFAULT 0 CHECK(members_epoch>=0)` et ne l'incrémente pas à la première arrivée ; `messaging-routes.ts` valide `expectedMembersEpoch` avec `.int().min(0).safe().optional()` ; `encryptContent` renvoie `listed.membersEpoch` tel quel. La sonde Node du lot Q97 (`issues-medias-relais-reel-97/artifacts/q4-media-relay-diagnostic`) mesure `membersEpochFromRoute = 0`, colonne `0`, et un `POST ./messages` avec `expectedMembersEpoch: 0` répond `200`.

Correction : seule la borne de `validateEnvelope` passe de `epoch > 0` à `epoch >= 0` ; le commentaire suit le contrat. `nil` et `-1` restent refusés, ainsi que les autres bornes (schéma, clé, charge ≤ 9 000 octets). Les tests couvrent le `put` à `0` puis réouverture et le chemin `put` sans enveloppe → `replaceEnvelope(expected:nil, replacement epoch 0)` → relecture, no-op idempotent et réouverture.

Aucun droit supplémentaire : `expectedMembersEpoch` est une métadonnée locale durable de la conversation ; le serveur continue de comparer l'époque exacte de cette conversation et les contrôles d'accès, d'identité, de scope et de révocation sont inchangés. Accepter `0` aligne le client sur une valeur que le serveur acceptait déjà, sans élargir la portée d'une enveloppe ni créer de conversation.

Limites : aucun Swift/Xcode sur ce poste, donc aucun GREEN local ; la réexécution Apple du parcours relay reste nécessaire.
