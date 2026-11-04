# Médias #97 - T2b1 : contenu natif v3, compatibilité et taille finale bornée

Base : `883581ad321b67ae3b7efe15ef2c6b89970b1e20` (T2a revue, `tomyrms/issues-medias-crypto-97`), branche de travail
`tomyrms/issues-medias-contenu-97`. Cible iOS 26.0 / Swift 6. Aucune dépendance, aucun lockfile, aucun `project.yml`,
aucun workflow, aucune sélection de tests modifiés. Aucun fichier de `MessagingContracts`, `ProtectedStore`,
`OutboxCoordinator`, `Workspace`, UI ou diagnostics touché.

Périmètre volontairement réduit : le **contenu applicatif** d'un message porteur d'un média, sa lecture compatible
v1/v2/v3, et les bornes mesurées sur les enveloppes réellement produites. La sélection photo, la préparation
ImageIO/PDFKit, le transport binaire, le coffre, le cache, les miniatures, l'UI et l'activation produit restent hors
de ce lot.

## 0. Modèle, skills et Codebase Memory (preuves de la passe)

| Élément | Valeur observée |
|---|---|
| Modèle effectif | `opencode-go/deepseek-v4.1-flash` (DeepSeek V4.1 Flash), sans model/effort additionnel |
| Skills Superpowers chargés | `test-driven-development` (chemins `.../superpowers/skills/test-driven-development/SKILL.md`) et `verification-before-completion` (`.../skills/verification-before-completion/SKILL.md`) ; `systematic-debugging` non requis : aucun bug à reproduire, la primitive T2a est revue et ses tests ont passé |
| Projet Codebase Memory | `drivy-t2b1-contenu-97-20261104`, créé par `index_repository(repo_path: "C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-contenu-97", mode: "moderate")` |
| Racine (`index_status`) | `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-contenu-97`, `status: ready`, `indexed_at: 2026-11-04T16:59:28Z`, 38 992 nœuds / 166 837 arêtes |
| Couverture des 4 fichiers du lot | `MessagingThreadModels.swift`, `MessagingHTTPTransport.swift`, `MessagingMediaCryptography.swift` : `no_recorded_issue` + `metadata_match` ; `MatrixMessagingCryptography.swift` : `partial` (ligne 100) → source relue directement |
| Recherches | `search_graph` sur `.*PlainContent.*` (`MessagingPlainContent` 43-74, 26 entrées), `.*messageContent.*` (648-652), `.*plaintext.*` (`plaintext(from:)` 697-704), `.*SendBody.*` (145-153), `.*recoveryContent.*` (`MessagingContracts.swift:147`, 13 entrées) ; appels relus dans `MessagingOutboxCoordinator`, `MessagingWorkspace`, `MessagingReportInbox`, `MessagingConversationView` |

Lacunes assumées de l'index : `parse_partial` sur 18 fichiers hors périmètre (dont `MatrixMessagingCryptography.swift:100`
et `DrivyAPIClient.swift`), `openapi.yaml` non analysable, répertoires exclus par `.gitignore`/skip-lists. Les sources du
lot ont donc été lues intégralement, pas seulement via le graphe.

## 1. Ce qui est livré

| Fichier | Rôle |
|---|---|
| `apps/ios/Drivy/MessagingCore/MessagingMediaContent.swift` (nouveau) | `MessagingMediaAttachment`, `MessagingMediaName`, `MessagingMediaContentV3`, `MessagingMediaContent` (écriture/lecture du contenu Matrix) |
| `apps/ios/Drivy/MessagingCore/MessagingThreadModels.swift` | `MessagingPlainContent.media` optionnel, `encoded()` v3, `decode()` v1/v2/v3, `summary` lisible |
| `apps/ios/Drivy/MessagingCore/MatrixMessagingCryptography.swift` | contenu réellement passé à `machine.encrypt`, extraction des deux formes après déchiffrement, borne 12 000 sur le payload produit |
| `apps/ios/Drivy/MessagingAPI/MessagingHTTPTransport.swift` | garde de taille sur le `SendBody` réellement sérialisé, avant jeton et requête |
| `apps/ios/DrivyTests/MessagingMediaContentTests.swift` (nouveau) | forme exacte, bornes, assainissement du nom, dimensions, échecs fermés, compatibilité |
| `apps/ios/DrivyTests/MessagingThreadTests.swift` | trois formes lues, contenu de récupération média |
| `apps/ios/DrivyTests/MatrixMessagingCryptographyTests.swift` | chiffrement réel (deux appareils du SDK), mentions, bornes après chiffrement, extraction, signalement |
| `apps/ios/DrivyTests/MessagingHTTPTransportTests.swift` | borne du `SendBody`, zéro requête au refus, limite propre du signalement |

## 2. Interfaces exactes

```swift
// MessagingMediaContent.swift
struct MessagingMediaAttachment: Codable, Sendable, Equatable {
    enum MIME: String, Codable, Sendable, Equatable, CaseIterable {
        case jpeg = "image/jpeg", png = "image/png", pdf = "application/pdf"
        var isImage: Bool { ... }
        var fallbackBody: String { ... }          // "Photo" | "PDF"
    }
    static let maximumByteSize = 4_194_304        // 4 Mio
    static let minimumByteSize = 1
    static let maximumNameLength = 255
    static let maximumPixelsPerAxis = 12_000
    static let maximumPixels = 40_000_000

    let id: UUID; let size: Int; let mime: MIME; let name: String
    let width: Int?; let height: Int?
    let file: MessagingMediaEncryptionInfo        // type T2a, inchangé

    init(id:size:mime:name:width:height:file:) throws   // valide ET assainit, invariant du type
    init(from decoder: Decoder) throws                  // même validation, échec fermé
}

enum MessagingMediaName { static func sanitized(_:) -> String? ; static func isForbidden(_:) -> Bool }

struct MessagingMediaContentV3: Codable, Sendable, Equatable {
    let v: Int; let text: String?; let media: MessagingMediaAttachment
    init(text:media:) throws
    var body: String                              // légende, sinon repli du MIME
}

enum MessagingMediaContent {
    static let namespacedKey = "ch.drivy.messaging"
    static let messageType = "m.text"
    static let version = 3
    static let maximumByteCount = 6_000
    static let maximumTextLength = 1_000
    enum Reading: Sendable, Equatable { case v3(MessagingMediaContentV3), fallbackBody(String), invalid, notNamespaced }
    static func messageContent(_:mentions:) throws -> Data
    static func reading(_:) -> Reading
}

// MessagingThreadModels.swift (additif)
struct MessagingPlainContent { var media: MessagingMediaAttachment? = nil   // défaut nil : appels existants inchangés
    static let maximumV3ByteCount = MessagingMediaContent.maximumByteCount }

// MatrixMessagingCryptography.swift (additif)
static let maximumOrdinaryPayloadBase64Length = 12_000
static func messageContent(plaintext: Data, mentions: [UUID]) throws -> String

// MessagingHTTPTransport.swift (privé)
private static let maximumSendBodyByteCount = 16_384
```

`MessagingPlainContent(text:)`, `MessagingPlainContent(poll:)`, `MessagingPlainContent(text:poll:)` et l'initialiseur
membre synthétisé restent utilisables tels quels : `media` a une valeur par défaut, donc aucune signature existante ne
change. Aucun initialiseur `reservedKey`/`reservedIV` n'est introduit ni appelé hors du harnais T2a.

## 3. Écriture : ce qui est réellement passé à `machine.encrypt`

Contenu porteur d'un média (`MessagingPlainContent.encoded()`, puis `MatrixMessagingCryptography.encrypt`) :

```json
{"msgtype":"m.text","body":"Légende de la photo",
 "ch.drivy.messaging":{"v":3,"text":"Légende de la photo",
   "media":{"id":"…","size":1834021,"mime":"image/jpeg","name":"IMG_0421.jpg",
            "width":2048,"height":1536,"file":{"v":"v2","key":{…},"iv":"…","hashes":{…}}}}}
```

- `encrypt` reçoit les octets clairs, les relit comme contenu (`MessagingMediaContent.reading`) et construit **la chaîne
  complète** remise à `machine.encrypt` : la namespace est au premier niveau, pas dans `body`.
- `body` porte la légende, sinon `Photo`, `PDF` (ou `Pièce jointe` si un MIME hors liste arrivait, ce que le type
  interdit). Aucun JSON dans `body`.
- `m.mentions` reste construit **uniquement** depuis le paramètre `mentions` de `encrypt` (mêmes `@uuid:drivy` qu'avant) ;
  le clair applicatif ne peut pas l'imposer.
- Messages sans média : `messageContent(text:mentions:)` est conservée à l'identique. Le `body` reste les octets
  applicatifs reçus (texte brut v1, enveloppe v2 JSON), donc **aucun octet d'une intention existante ne change** et
  aucun retry ne rechiffre : `MessagingOutboxCoordinator.retry` renvoie l'enveloppe stockée, code inchangé.
- `summary` reste lisible : légende, sinon repli du MIME, sinon texte.

Un contenu porteur d'une namespace **inconnue** ou d'un v3 **illisible** n'est jamais émis comme texte : `encrypt` lève
`MessagingFailure.invalidResponse` (échec fermé, rien n'est envoyé).

## 4. Lecture : deux formes acceptées, documentées ensemble

`MatrixMessagingCryptography.plaintext(from:)` rend, après les gardes existantes (`mismatchedSender`, type
`m.room.message`, présence de `body`) :

| Forme | Octets rendus | Origine |
|---|---|---|
| legacy | ceux de `body` | texte brut v1, enveloppe applicative v2 JSON, contenu de récupération local |
| v3 | le JSON du `content` Matrix complet | contenu porteur de `ch.drivy.messaging` |

`MessagingPlainContent.decode` applique ensuite, dans cet ordre :

1. namespace présente + `msgtype` `m.text` + `body` lisible → **v3** si `v == 3` et si le média est valide ; le v3 est
   alors préféré ;
2. `v` numérique différent de 3 (version future) → **le `body` de repli**, jamais le JSON technique ;
3. v3 connu mais incomplet ou invalide (média absent, taille hors plafond, MIME inconnu, légende trop longue, crypto
   invalide, `body` absent) → `nil` : **échec fermé** ;
4. sinon enveloppe applicative `v == 2` → contenu v2 (texte et sondage), comme avant ;
5. sinon texte UTF-8 brut (v1), comme avant.

Un ancien texte qui ressemble à du JSON reste du texte utilisateur : la namespace n'est interprétée que sur un contenu
Matrix complet (namespace **et** `msgtype` **et** `body`). `{"media":{"id":"x"},"v":3}` tapé par une personne reste son
texte ; `{"msgtype":"m.text","body":"coucou"}` aussi.

Résultat attendu côté future UI (aucune UI modifiée dans ce lot) : un v3 connu et invalide rend `decode` `nil`, donc
`MessagingWorkspace.content(for:)` lève `invalidResponse` et **n'affiche aucun faux succès** ; le message n'est ni rendu
comme du JSON, ni comme un média. Le mapping fin (bulle « média illisible » plutôt qu'erreur de conversation) relève du
lot UI et n'est pas inventé ici.

## 5. Bornes : où chacune est mesurée

| Borne | Valeur | Où | Sur quoi |
|---|---|---|---|
| contenu v3 encodé | ≤ 6 000 octets | `MessagingPlainContent.encoded()`, `messageContent(plaintext:)` | les octets du contenu, pas les caractères |
| légende | ≤ 1 000 caractères | `MessagingMediaContentV3` | `text.count` |
| taille de pièce | 1 … 4 194 304 octets | `MessagingMediaAttachment` | `size` déclaré |
| nom | ≤ 255 caractères, C0/DEL/C1, U+202A–202E, U+2066–2069 et séparateurs retirés | `MessagingMediaName` | nom assaini avant stockage dans le type |
| dimensions | 1 … 12 000 par axe, ≤ 40 M pixels, `multipliedReportingOverflow` | `MessagingMediaAttachment.validate` | image seulement ; PDF sans dimensions |
| MIME | `image/jpeg`, `image/png`, `application/pdf` | `MIME` | enum, un autre type échoue au décodage |
| crypto | validée par T2a (`validatedMaterial()`), aucun alphabet normalisé | `MessagingMediaAttachment` | en-tête JWK, alphabets, longueurs, remplissage |
| payload Megolm d'un message ordinaire | base64 ≤ 12 000 caractères | `MatrixMessagingCryptography.encrypt`, **après** `machine.encrypt` | l'enveloppe réellement produite |
| corps JSON du message ordinaire | ≤ 16 384 octets | `MessagingHTTPTransport.send`, **avant** `request()` | `JSONEncoder().encode(SendBody(...))` |
| corps d'un signalement | 640 Kio (serveur), inchangé | hors de cette garde | `report()` n'est pas filtré par la borne 16 384 |

Aucune ressource externe n'entre dans le contenu : le type n'a ni URL, ni chemin, ni miniature, ni aperçu de lien. Le nom
est une donnée d'affichage, jamais utilisée comme chemin (séparateurs retirés, aucun accès fichier dans ce lot).

Vérification arithmétique complémentaire (hors Swift, donc **pas** une preuve Swift) : pour un payload de 11 000 octets le
`SendBody` mesure 14 840 octets (accepté) et pour 12 200 octets il mesure 16 440 octets (refusé, borne 16 384) ; un contenu
v3 au plafond de 6 000 octets produit un payload Megolm base64 d'environ 8 400 caractères, sous la borne de 12 000.

## 6. Signalement (#77) : préservé, avec sa propre limite

`sealForSchoolAdmins` continue d'utiliser `messageContent(text:mentions:)` : le contenu scellé garde son enveloppe
(`body` = octets reçus) et n'est **pas** soumis à la borne 12 000 d'un message ordinaire. Un signalement de message média
transmet donc l'enveloppe legacy contenant déjà la clé de fichier et les métadonnées (nom, type, dimensions) : l'administrateur
les relit via le même décodeur, et **aucun octet binaire** n'est copié. La limite de 640 Kio et la cadence restent
inchangées et côté serveur.

## 7. Tests écrits (à exécuter sur runner Apple)

`MessagingMediaContentTests` (nouveau, 13 cas) : forme namespacée et `body` lisible, repli par MIME, synthèse lisible,
aller-retour, enveloppe v2 inchangée sans média, légende 1 000/1 001, contenu encodé 6 000 (unicode lourd compris), taille
0/1/4 Mio/4 Mio+1/−1, MIME hors liste, nom assaini (C0, C1, bidi, chemins, 255), dimensions (bornes, 40 M pixels exactement,
débordement), métadonnées crypto refusées (version et alphabet), version future → `body`, v3 incomplet → `nil`, texte JSON
legacy → texte.

`MessagingThreadTests` : trois formes lues (v1, v2, v3) et contenu de récupération média.

`MatrixMessagingCryptographyTests` (chiffrement Megolm réel, deux appareils du SDK, relais en mémoire) : namespace au
premier niveau et `body` sans JSON, `m.mentions` du paramètre, contenu reçu identique, aucune valeur média dans le payload,
octets legacy inchangés (texte et enveloppe v2), borne 12 000 après chiffrement (contenu v3 au plafond accepté, 9 000 et
16 000 octets refusés), v3 invalide et version inconnue refusés avant envoi, extraction des deux formes avec gardes
`mismatchedSender` et type, signalement gardant son enveloppe et sa limite, signalement d'un média relisible par
l'administrateur.

`MessagingHTTPTransportTests` : `SendBody` au-delà de 16 Kio refusé avec **zéro requête** enregistrée, `SendBody` sous la
borne réellement émis, signalement de 20 Kio de payload non refusé par la garde du message.

## 8. Commandes réellement exécutées

| Commande | Résultat | Code |
|---|---|---|
| `git rev-parse HEAD` / `git status --porcelain` (avant édition) | `883581ad…`, arbre propre, branche `tomyrms/issues-medias-contenu-97` | 0 |
| `index_repository` puis `index_status` / `check_index_coverage` | projet `drivy-t2b1-contenu-97-20261104`, racine = ce worktree, `ready` | — |
| `Get-Command swift,xcodebuild` | **absents** : aucun outil Apple sur ce poste | — |
| `node` (contrôle arithmétique des bornes, fichier temporaire supprimé) | 11 000 → 14 840 octets ; 12 200 → 16 440 ; contenu v3 au plafond 2 949 octets | 0 |
| `git diff --stat` / relecture du diff | 3 fichiers modifiés, 1 nouveau module, 3 fichiers de tests modifiés, 1 nouveau fichier de tests | 0 |

### NON EXÉCUTÉ

- **Swift / Xcode / simulateur** : aucun outil Apple ici. Les tests ci-dessus sont **écrits, non compilés, non exécutés**.
  Aucun RED/GREEN Swift n'est revendiqué : la séquence RED → GREEN n'a pas pu être observée.
- **Chiffrement Megolm réel des cas v3** : écrit, non exécuté. La borne 12 000 sur le payload produit n'est donc pas encore
  prouvée par une exécution.
- **`SendBody` à 14 840 / 16 440 octets** : arithmétique reproduite hors Swift ; la garde elle-même n'est pas exécutée.
- **CommonCrypto / CryptoKit / Keychain** : hors périmètre de ce lot (T2a), inchangés.
- Le contrôle Node ne compile pas Swift et ne prouve pas la logique Swift ; il ne sert qu'à vérifier les ordres de grandeur.

## 9. Limites, risques et écarts de périmètre

- **Aucune preuve Apple à ce SHA.** La prochaine exécution doit viser le SHA de cette branche (ou un candidat intégré
  autorisé) ; le run `41861281984` couvre T2a (`883581ad`), **pas** ce code.
- **`MessagingOutboxCoordinator.enqueue(content:)` refuse encore un média sans légende** (`guard hasText != (poll != nil)`).
  Le fichier est hors périmètre : l'émission réelle d'une pièce jointe sans légende exige ce changement dans un lot
  ultérieur. Un média **avec** légende traverse déjà le chemin de contenu.
- **Aucune activation produit** : pas de sélection de fichier, pas de dépôt, pas de champ `media` serveur, pas de file
  binaire, pas de cache, pas de rendu. Un JSON namespacé seul ne qualifie pas un parcours pièce jointe complet.
- La borne 12 000 est appliquée au message ordinaire ; un contenu v3 valide au plafond de 6 000 octets laisse une marge
  mesurée (~8 400 caractères), mais seule une exécution Apple le confirmera pour la version de Megolm liée.
- Le décodage v3 est strict : un média reçu invalide rend le message illisible plutôt qu'un média partiel (choix documenté
  au §4). Les erreurs réutilisent `MessagingFailure.invalidResponse` ; le mapping UI détaillé (codes `M-SIZE`,
  `M-INTEGRITY`) reste à faire dans le lot transport/UI.
- `MessagingSearchExcerpt` ne cherche pas encore dans une pièce jointe sans légende (source vide) : recherche média hors lot.
- Un texte utilisateur qui serait **exactement** un contenu Matrix complet avec namespace serait lu comme v3 : ambiguïté
  résiduelle, bornée aux trois conditions simultanées (namespace, `msgtype` `m.text`, `body`), documentée au §4.
- Aucune zéroïsation mémoire, aucune analyse de contenu de fichier, aucune politique de conservation : hors lot.
