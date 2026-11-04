# Médias #97 - T2a : primitive de chiffrement et oracle officiel

Base : `b0152a2a7a9d5679f2f3bd3bdb8b819a43372ff4` (contrat médias corrigé, au-dessus de `master` `0bdaf324`). Cible iOS 26.0 / Swift 6. Aucune dépendance, aucun lockfile, aucune cible de projet modifiés.

Périmètre volontairement réduit : la primitive de chiffrement des pièces jointes et les vecteurs croisés. Le transport binaire, le coffre AES-GCM, le cache, les miniatures, le contenu v3 et l'UI restent hors de ce lot (T2b/T3).

Historique du lot : première livraison `aedc1f0f`, puis correction après revue (remplissage partiel, borne d'allocation, écriture canonique réelle, régénération volontaire, rapport). Le commit correctif est indiqué dans le message de livraison.

## 0. Codebase Memory : correction de la preuve

La première livraison s'appuyait sur le projet MCP `drivy-issues-medias-97`. Ce projet **n'est pas** celui de ce worktree : `index_status` le donne à la racine `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-97` (worktree T1), et `list_projects` n'énumérait aucun index à `issues-medias-crypto-97`. Les recherches `search_graph` de la première passe ont donc été faites sur l'index d'un autre worktree et ne prouvaient **rien** sur ce lot ; elles ne sont pas présentées rétrospectivement comme conformes. Elles n'ont pas été modifiées, ni supprimées, ni reconfigurées depuis.

Preuve corrigée, exécutée pendant cette correction :

| Élément | Valeur observée |
|---|---|
| Projet unique créé | `drivy-t2a-crypto-97-20261104` |
| Appel | `index_repository(repo_path: "C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-crypto-97", name: "drivy-t2a-crypto-97-20261104", mode: "moderate")` |
| Racine (`index_status`) | `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-crypto-97` |
| Fraîcheur | `indexed_at: 2026-11-04T15:22:36Z`, `status: ready`, 38 964 nœuds / 166 755 arêtes |
| Couverture des 4 fichiers du lot | `no_recorded_issue`, `metadata_match`, `generation_matches: true` (`check_index_coverage`) |
| Recherches | `search_graph name_pattern "MessagingMedia.*"` : `MessagingMediaCryptography`, `MessagingMediaEncryptionInfo`, `MessagingMediaBase64`, `MessagingMediaCryptographyFailure`, `MessagingMediaMaterial`, les tests ; `trace_path MessagingMediaCryptography` : 0 appelant / 0 appelé (primitive isolée, comme attendu) |

Lacunes assumées de cet index : `parse_partial` sur 5 fichiers hors périmètre (`MatrixMessagingCryptography.swift` ligne 100, `DrivyAPIClient.swift` 53-57/319, `SchoolPlanningView.swift` 421-423, `SchoolCaptureSessionController.swift` 351, `MessagingQualificationFixture.swift` 243) ; `openapi.yaml` non analysable ; répertoires exclus par `.gitignore`/skip-lists. Aucun de ces fichiers n'appartient au lot, et la source concernée a été lue directement.

## 1. Ce qui est livré

| Fichier | Rôle |
|---|---|
| `apps/ios/Drivy/MessagingCore/MessagingMediaCryptography.swift` | Types §4.5, protocole `MessagingMediaCryptography`, implémentation AES-CTR/SHA-256, base64 borné et canonique |
| `apps/ios/DrivyTests/MessagingMediaCryptographyTests.swift` | Tests Swift des vecteurs, matrice de remplissage, borne, tailles, aléa, fuites |
| `apps/ios/DrivyTests/Fixtures/media-vectors.json` | Vecteurs, refus, matrice de remplissage et bornes produits par l'oracle officiel |
| `prototypes/messaging-crypto/tests/media_vectors.rs` | Oracle Rust : production, relecture, refus, matrice et bornes |
| `prototypes/messaging-crypto/scripts/generate-media-vectors.ps1` | Régénération volontaire (aucun nouveau résolveur) |
| `docs/implementation/messaging-media-97-crypto.md` | Ce document |

## 2. Interfaces exactes

Forme §4.5 du contrat, sans ajout de champ :

```swift
struct MessagingMediaEncryptionInfo: Codable, Sendable, Equatable {
    struct Key: Codable, Sendable, Equatable {
        let kty: String; let alg: String; let ext: Bool; let k: String; let keyOps: [String]  // key_ops
    }
    struct Hashes: Codable, Sendable, Equatable { let sha256: String }
    let v: String; let key: Key; let iv: String; let hashes: Hashes
    init(from decoder: Decoder) throws          // lecture tolérante, validation, réécriture canonique
    func validatedMaterial() throws -> MessagingMediaMaterial
    static func material(v:key:iv:hashes:) throws -> MessagingMediaMaterial
}

struct MessagingSealedMedia: Sendable, Equatable {
    let mediaID: UUID; let ciphertext: Data; let info: MessagingMediaEncryptionInfo
    var byteSize: Int { ciphertext.count }
}

protocol MessagingMediaCryptography: Sendable {
    func seal(_ plaintext: Data) throws -> MessagingSealedMedia
    func open(_ ciphertext: Data, info: MessagingMediaEncryptionInfo) throws -> Data
    func verify(_ ciphertext: Data, info: MessagingMediaEncryptionInfo) -> Bool
}

enum MessagingMediaCryptographyFailure: Error, Equatable, Sendable, LocalizedError {
    case invalidSize, invalidEncryptionInfo, integrityMismatch, randomnessUnavailable, cipherUnavailable
}
```

Ajouts internes, non prévus par §4.5 mais nécessaires et bornés :

- `AESCTRMediaCryptography` : l'implémentation (CommonCrypto + CryptoKit).
- `MessagingMediaMaterial` : octets validés (32/16/32).
- `init(reservedKey:reservedIV:)` : **harnais de vecteurs uniquement**, jamais appelé par l'app.
- `MessagingMediaBase64` : encodeur/décodeur des deux alphabets, avec borne de longueur et verdicts de remplissage alignés sur `ruma` (voir §4 et §5).

## 3. Algorithme et invariants

- Clé AES-256 : 32 octets de `SecRandomCopyBytes`, neufs à chaque `seal`. Aucune dérivation depuis un compte, aucune réutilisation.
- IV : 16 octets, 8 aléatoires puis 8 à zéro (compteur 64 bits partant de 0).
- AES-256-CTR, `CCCryptorCreateWithMode(..., kCCModeCTR, kCCAlgorithmAES, ccNoPadding, ..., kCCModeOptionCTR_BE)` : compteur big-endian, aucun remplissage, `ciphertext.count == plaintext.count`.
- SHA-256 calculé sur le **chiffré** (CryptoKit), base64 standard sans remplissage.
- `mediaID` = `UUID()` local. La primitive ne reçoit ni nom, ni chemin, ni compte, ni conversation.
- `MessagingSealedMedia` est immuable : un nouvel essai réseau réutilise les mêmes octets et le même `mediaID`.
- `open` vérifie le SHA-256 **avant** de déchiffrer et ne rend rien en cas d'écart ; `verify` ne déchiffre jamais.
- Plafond 4 194 304 octets sur le clair et sur le chiffré ; 0 octet est valide pour la primitive.
- Échecs fermés : aléa ou AES indisponible ⇒ erreur, jamais de repli ; aucun `fatalError`, `try!` ni déballage forcé sur une donnée reçue ; aucune valeur reçue attachée à une erreur.

## 4. Remplissage : verdicts réels de la bibliothèque

La règle de la première livraison (`(caractères + '=') multiple de 4`, remplissage canonique exigé) était **plus stricte que `ruma`** et refusait un objet que la bibliothèque accepte. Vérification faite sur la bibliothèque compilée du prototype (`ruma-common` 0.20.1 → `base64` 0.23.1) : une chaîne de 22 caractères représentant 16 octets est acceptée sans `=`, avec un `=` **et** avec deux `==` — `DecodePaddingMode::Indifferent` ne contrôle le multiple de 4 que dans `RequireCanonical`, et `decode_suffix` n'impose que deux règles : au moins deux symboles dans le dernier groupe, et premier `=` après deux symboles de ce groupe.

Verdicts enregistrés dans `paddingMatrix` (14 cas, tous reproduits par l'oracle au moment du test) :

| Cas | Verdict |
|---|---|
| IV 22 caractères, sans `=`, avec `=`, avec `==` | accepté, 16 octets |
| IV avec `===`, avec `====` | refusé |
| IV `=` à la place du dernier symbole (un seul symbole avant) | refusé |
| IV `=` au milieu, ou `=` suivi d'un symbole | refusé |
| IV suivi d'un blanc, IV avec un caractère non ASCII | refusé |
| clé 43 caractères, sans `=`, avec `=` | accepté, 32 octets |
| clé avec `==`, ou `=` au milieu | refusé |

Le décodeur Swift applique exactement ces règles : remplissage uniquement dans le dernier groupe de 4, après au moins deux symboles, jamais interne, jamais plus de deux, et les bits de queue non nuls restent tolérés comme dans `ruma`.

Verdicts de l'**objet** (au-delà du base64), identiques à `ruma` mais contrôlés plus tôt : `v` ≠ `v2`, `kty` ≠ `oct`, `alg` ≠ `A256CTR`, `ext` ≠ `true`, `key_ops` sans `encrypt` ou sans `decrypt`, longueur décodée ≠ 32/16/32, alphabet incorrect : tous refusés à l'entrée, aucun clair produit.

## 5. Écriture canonique réelle

Le type porte l'invariant « décodé donc canonique » : `init(from:)` décode, valide (version, en-tête JWK, alphabets, longueurs, remplissage) puis reconstruit `v`, `key` (avec `["decrypt", "encrypt"]`), `iv` et `hashes.sha256` **sans remplissage**. Conséquences :

- un objet obtenu par `JSONDecoder` puis réencodé par `JSONEncoder` est canonique sans intervention : c'est ce que teste `testPaddedInputIsToleratedAndNeverReemitted`, sur l'objet décodé lui-même et non sur une seconde construction ;
- un alphabet incorrect, une longueur fausse ou un en-tête invalide lèvent une `DecodingError` fermée, dont le message ne reprend aucune valeur : rien n'est normalisé en silence ;
- `encode(to:)` est synthétisé sur les chaînes déjà canoniques ; un objet construit par l'initialiseur interne pour sceller est canonique par construction.

## 6. Borne d'allocation

`MessagingMediaBase64.decode` vérifie **avant toute copie ou itération** :

1. `0 ≤ count ≤ maximumDecodedCount` (4 194 304) ;
2. `text.utf8.count ≤ maximumEncodedLength(for: count)` avec
   `maximumEncodedLength(count) = (count * 4 + 2) / 3 + 2`, en arithmétique sans débordement (`multipliedReportingOverflow` / `addingReportingOverflow`, repli `Int.max`).

Pour une clé (32 octets) la borne est 45 caractères, pour un IV (16 octets) 24, pour un chiffré de 4 Mio 5 592 408. Une chaîne de 4 096 caractères présentée comme une clé est donc refusée sans `Array(text.utf8)` ni `Data` de sa taille. La borne est publiée dans `limits.perSize` de la fixture pour les six tailles stockées et vérifiée des deux côtés.

## 7. Vecteurs : origine, contenu, revalidation

### 7.1 Oracle

`matrix-sdk-crypto` **0.19.1**, version épinglée par `prototypes/messaging-crypto/Cargo.lock`. Seuls les symboles publics sont utilisés : `AttachmentEncryptor`, `AttachmentDecryptor`, `MediaEncryptionInfo`. Aucune seconde implémentation AES/CTR/SHA-2, aucune dépendance ajoutée. Le vecteur `EXAMPLE_DATA`/`example_key_json` est identique en 0.17.0 (module amont de la FFI liée) et en 0.19.1.

### 7.2 Contenu de `media-vectors.json`

- `vectors` : tailles 0, 1, 15, 16, 17, 65 536 ; `byteSize`, `ciphertext`, `info`. Chaque ligne couvre les deux alphabets (`k` avec `-`/`_`, `iv` et `sha256` avec `+`/`/`).
- `upstreamVector` : `EXAMPLE_DATA` (26 octets) et `example_key_json` tels quels, clair attendu `It's a secret to everybody`.
- `rejections` : 18 cas, chacun avec `refusedAt` (`deserialize` ou `decryptor`) : 16 refusés à la lecture par `ruma`, 2 au déchiffreur (`v` inconnu, `hashes` sans `sha256`). Drivy refuse les deux plus tôt, même verdict final.
- `padding` : deux cas décryptés par le déchiffreur officiel — remplissage **canonique** complet, et remplissage **partiel** (un seul `=` sur l'IV de 22 caractères).
- `paddingMatrix` : 14 verdicts base64 de la bibliothèque (voir §4).
- `limits` : plafond 4 194 304 et borne d'encodage par taille.
- `plaintextRule` : `byte(i) = u8(7 + 31*i + (i >> 8))`, partagée avec le test Swift.

Le cas 4 194 304 octets n'est pas stocké : il est réellement exécuté par `large_sizes_are_exercised_with_the_official_oracle` (chiffrement puis déchiffrement officiels de 4 Mio en mémoire) et par le test Swift `testPayloadBoundsAcceptZeroAndTheLimitAndRejectBeyond` (à exécuter sur Apple).

### 7.3 Clé et IV « imposés » : ce que l'API officielle permet

`AttachmentEncryptor::new(reader)` tire lui-même clé et IV ; aucun constructeur public n'accepte une clé ou un IV imposés, et `MediaEncryptionInfo` n'est pas `Clone`. Les vecteurs sont donc **enregistrés** après chiffrement officiel. Le déchiffrement de ces octets par le module officiel prouve **oracle → oracle**, c'est-à-dire que la fixture est bien une sortie officielle cohérente. Les deux sens croisés Swift ↔ oracle (Swift scelle avec la clé/IV enregistrés et doit retrouver les octets officiels ; Swift ouvre la sortie officielle) sont **écrits mais pas exécutés** : ils ne seront prouvés que sur un runner Apple (§9).

### 7.4 Génération volontaire et revalidation

```text
# réécrit la fixture — activation explicite « 1 » uniquement
pwsh -File prototypes/messaging-crypto/scripts/generate-media-vectors.ps1
# ou
DRIVY_MEDIA_VECTORS_WRITE=1 cargo test --locked \
  --manifest-path prototypes/messaging-crypto/Cargo.toml \
  --test media_vectors regenerate_when_requested -- --exact

# revalidation : relit, déchiffre, refuse, compare la matrice et les bornes
cargo test --locked --manifest-path prototypes/messaging-crypto/Cargo.toml --test media_vectors
```

Toute autre valeur (`0`, `false`, vide) ou l'absence de variable laisse la fixture intacte. Le test échoue si le format change : info non relisible, `key_ops` réordonné, remplissage émis, alphabet inversé, hash incohérent ou verdict de la matrice modifié cassent une assertion nommée.

## 8. Résultats réellement exécutés

Environnement : Windows x86_64, `cargo 1.99.0`, `rustc 1.99.0`, hors ligne, `--locked`.

| # | Commande | Résultat | Code |
|---|---|---|---|
| 1 | `cargo test --locked --offline ... --test media_vectors` (avant régénération) | **RED** : 8 verts, 3 échecs — `paddingMatrix` et `limits` absents de la fixture, pas une erreur de compilation | 101 |
| 2 | `cargo test ... --test media_vectors regenerate_when_requested -- --exact` **sans** variable | 1 vert, fixture inchangée (SHA-256 `19BAEE6A…` et horodatage identiques) | 0 |
| 3 | idem avec `DRIVY_MEDIA_VECTORS_WRITE=0` puis `=false` | 1 vert, fixture inchangée (même SHA-256) | 0 |
| 4 | idem avec `DRIVY_MEDIA_VECTORS_WRITE=1` | 1 vert, fixture réécrite (SHA-256 `1C103A50…`, 108 630 octets) | 0 |
| 5 | `cargo test --locked --offline ... --test media_vectors` (après régénération) | **GREEN** : 11 verts, 0 échec, 1,19 s | 0 |
| 6 | `cargo test --locked --offline --manifest-path prototypes/messaging-crypto/Cargo.toml` (suite complète) | 11 + 4 verts, 0 échec | 0 |
| 7 | `cargo fmt --check` | aucune différence | 0 |
| 8 | Port Python jetable de l'algorithme Swift (base64 borné, matrice, règle de clair, validation), hors dépôt | 47 vérifications, 0 échec, dont les 14 verdicts de la matrice et les deux cas de remplissage | 0 |

Les lignes 1 à 6 et 8 portent sur du code exécuté ; la ligne 8 ne prouve pas la compilation Swift, seulement la logique transposée.

### NON EXÉCUTÉ

- **Swift / Xcode / simulateur** : aucun outil Apple sur le poste. `MessagingMediaCryptographyTests.swift` est écrit et aligné sur la fixture, mais aucun test Swift n'a été compilé ni exécuté ici. Aucun RED/GREEN Swift n'est revendiqué.
- **CommonCrypto** : `kCCModeOptionCTR_BE`, l'absence de tampon interne de `CCCryptorUpdate` et `SecRandomCopyBytes` ne peuvent pas être vérifiés hors Apple. Le code échoue fermé (`cipherUnavailable`) si `moved != input.count`.
- **Sens croisés Swift ↔ oracle** : écrits, non exécutés (voir §7.3).
- **4 Mio côté Swift** : test écrit, non exécuté.

## 9. Limites et risques

- La voie Swift est une **implémentation** du format publié : la fidélité n'est pas garantie par construction. Elle ne sera démontrée que par l'exécution Apple des vecteurs ; l'écriture du code et les tests Rust ne la prouvent pas.
- Une divergence résiduelle (par exemple un compteur little-endian si `kCCModeOptionCTR_BE` était ignoré) serait détectée par le premier test Swift ; elle ne peut pas être exclue avant un runner Apple.
- La matrice de remplissage fige les verdicts de `base64` 0.23.1 via `ruma-common` 0.20.1 ; une montée de version de la bibliothèque exigera de régénérer puis de relire la matrice.
- Aucune zéroïsation mémoire des octets clairs ou de la clé n'est revendiquée.
- `verify` ne protège que l'intégrité du chiffré relativement à l'événement Megolm qui porte la clé et le hash : ni authenticité d'expéditeur, ni confidentialité contre un appareil compromis.
- Le décodage de `MessagingMediaEncryptionInfo` est strict : un média invalide fait échouer le décodage du contenu qui le porte. T2b devra décider si cela se traduit par un message illisible ou par un seul média illisible.
- Le harnais `init(reservedKey:reservedIV:)` doit rester sans appel produit ; une revue de T2b doit le vérifier.
- Les erreurs ne sont pas encore mappées sur les codes `M-SIZE`/`M-INTEGRITY`/`M-HASH` du contrat §3.11 : cela relève du transport et du cache (T2b).

## 10. Suite (hors lot)

T2b consomme `MessagingMediaCryptography`, `MessagingSealedMedia` et `MessagingMediaEncryptionInfo` tels quels : intention scellée AES-GCM + Keychain, transport binaire, cache AES-GCM, miniatures, contenu v3 `ch.drivy.messaging`. Pour les PDF, le rendu passe par `PDFDocument(data:)` depuis la mémoire (décision du coordinateur) : **aucun temporaire déchiffré persistant**, ni dans `Documents`, ni ailleurs. Aucune activation produit ni publication n'est autorisée par ce lot.
