# Médias #97 - T2a : primitive de chiffrement et oracle officiel

Base : `b0152a2a7a9d5679f2f3bd3bdb8b819a43372ff4` (contrat médias corrigé, au-dessus de `master` `0bdaf324`). Cible iOS 26.0 / Swift 6. Aucune dépendance, aucun lockfile, aucune cible de projet modifiés.

Périmètre volontairement réduit : la primitive de chiffrement des pièces jointes et les vecteurs croisés. Le transport binaire, le coffre AES-GCM, le cache, les miniatures, le contenu v3 et l'UI restent hors de ce lot (T2b/T3).

## 1. Ce qui est livré

| Fichier | Rôle |
|---|---|
| `apps/ios/Drivy/MessagingCore/MessagingMediaCryptography.swift` | Types §4.5, protocole `MessagingMediaCryptography`, implémentation AES-CTR/SHA-256, base64 du format |
| `apps/ios/DrivyTests/MessagingMediaCryptographyTests.swift` | Tests Swift des vecteurs, refus, tailles, aléa, fuites |
| `apps/ios/DrivyTests/Fixtures/media-vectors.json` | Vecteurs synthétiques produits par l'oracle officiel |
| `prototypes/messaging-crypto/tests/media_vectors.rs` | Oracle Rust : production, relecture et refus, avec `matrix-sdk-crypto` 0.19.1 |
| `prototypes/messaging-crypto/scripts/generate-media-vectors.ps1` | Régénération documentée (aucun nouveau résolveur) |
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
    func validatedMaterial() throws -> MessagingMediaMaterial
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

- `AESCTRMediaCryptography` : l'implémentation (CommonCrypto + CryptoKit). Nom non figé par le contrat ; T2b peut la recevoir par injection.
- `MessagingMediaMaterial` : octets validés (32/16/32) rendus par `validatedMaterial()`. Aucun accès public.
- `init(reservedKey:reservedIV:)` : **harnais de vecteurs uniquement**. Il rejoue une clé et un IV enregistrés (IV dont les 8 derniers octets doivent être nuls) pour comparer les octets produits par Swift à ceux de l'oracle. Aucun chemin produit ne l'appelle ; il n'existe pas de mode déterministe dans l'API de production.
- `MessagingMediaBase64` : encodeur/décodeur des trois alphabets. `Data(base64Encoded:)` ne garantit ni le refus d'un caractère hors alphabet imposé, ni la tolérance de remplissage en lecture, ni l'absence d'émission de remplissage : les règles de `ruma` sont donc reproduites explicitement.

## 3. Algorithme et invariants

- Clé AES-256 : 32 octets de `SecRandomCopyBytes`, neufs à chaque `seal`. Aucune dérivation depuis un compte, aucune réutilisation.
- IV : 16 octets, 8 aléatoires puis 8 à zéro (compteur 64 bits partant de 0).
- AES-256-CTR, `CCCryptorCreateWithMode(..., kCCModeCTR, kCCAlgorithmAES, ccNoPadding, ..., kCCModeOptionCTR_BE)` : compteur **big-endian**, aucun remplissage, donc `ciphertext.count == plaintext.count`.
- SHA-256 calculé sur le **chiffré** (CryptoKit), encodé en base64 standard sans remplissage.
- `mediaID` = `UUID()` local. La primitive ne reçoit ni nom, ni chemin, ni compte, ni conversation.
- `MessagingSealedMedia` est immuable : un nouvel essai réseau réutilise les mêmes octets et le même `mediaID`, donc le même SHA-256 côté serveur (idempotence §3.4).
- `open` vérifie le SHA-256 **avant** de déchiffrer et ne rend rien en cas d'écart. `verify` ne déchiffre jamais et ne lève pas.
- Plafond d'allocation 4 194 304 octets sur le clair et sur le chiffré ; 0 octet est valide pour la primitive (l'upload produit refusera 0, T1).
- Échecs fermés : aléa ou AES indisponible ⇒ erreur, jamais de repli, jamais de clé faible, aucun `fatalError`, aucun `try!`, aucun déballage forcé sur une donnée reçue.
- Aucune valeur reçue n'est attachée à une erreur : ni clé, ni IV, ni hash, ni octet, ni identifiant.

## 4. Validation stricte de l'objet (§4.3.1)

Contrôlée par `validatedMaterial()` avant tout déchiffrement, et par les cas de refus de la fixture.

| Champ | Alphabet | Longueur décodée | Remplissage | Refus |
|---|---|---|---|---|
| `key.k` | base64url (`-`, `_`) | 32 | toléré en lecture, jamais émis | `+`, `/`, longueur ≠ 32, caractère hors alphabet, blanc |
| `iv` | base64 standard (`+`, `/`) | 16 | idem | `-`, `_`, longueur ≠ 16 |
| `hashes.sha256` | base64 standard (`+`, `/`) | 32 | idem | `-`, `_`, longueur ≠ 32 |
| `v` | — | — | — | ≠ `v2` |
| `key.kty` / `key.alg` / `key.ext` | — | — | — | ≠ `oct` / `A256CTR` / `true` |
| `key.key_ops` | — | — | — | `encrypt` ou `decrypt` absent |

Deux écarts assumés, plus stricts que `ruma` et conformes au contrat :

1. `v` inconnu est refusé **à l'entrée**. `ruma` le lit comme variante `_Custom` et ne le refuse qu'à la création du `AttachmentDecryptor` (`UnknownVersion`). Même refus observé, mécanisme plus tôt.
2. `hashes.sha256` est obligatoire à l'entrée. `ruma` accepte `{"sha512": ...}` puis échoue en `MissingHash`. Même refus observé, plus tôt.

Remplissage : accepté en lecture, refusé s'il n'est pas canonique (`nombre de '='` incohérent, longueur totale non multiple de 4), jamais émis. Les bits de queue non nuls sont tolérés, comme `ruma` (`decode_allow_trailing_bits`).

## 5. Vecteurs : origine, contenu, revalidation

### 5.1 Oracle

`matrix-sdk-crypto` **0.19.1**, version déjà épinglée par `prototypes/messaging-crypto/Cargo.lock` (`Cargo.toml` : `=0.19.1`). Les seuls symboles utilisés sont publics : `AttachmentEncryptor`, `AttachmentDecryptor`, `MediaEncryptionInfo` (`src/file_encryption/attachments.rs`, exportés par `lib.rs`). Aucune seconde implémentation AES/CTR/SHA-2 n'est écrite en Rust, aucune dépendance ajoutée (`aes`/`ctr`/`sha2` ne sont que transitives, via la crate officielle).

Le format de `0.19.1` est le même que celui du module `0.17.0` (la version liée dans l'app) : le vecteur `EXAMPLE_DATA`/`example_key_json` est identique dans les deux sources. La FFI `matrix-sdk-crypto-ffi` 0.17.0 réellement embarquée n'expose, elle, **aucun** symbole de pièce jointe : ce lot ne peut donc pas s'appuyer sur un appel officiel depuis l'app, seulement sur des vecteurs comparables.

### 5.2 Contenu de `media-vectors.json` (103 550 octets)

- `vectors` : tailles 0, 1, 15, 16, 17 et 65 536 octets. Chaque entrée porte `byteSize`, `ciphertext` (base64 standard) et `info` (`v`, `key`, `iv`, `hashes`). Chaque vecteur a été tiré jusqu'à ce que **sa** `k` contienne `-` ou `_`, **son** `iv` et **son** `sha256` contiennent `+` ou `/` : les deux alphabets sont donc couverts par chaque ligne, pas seulement par le jeu.
- `upstreamVector` : `EXAMPLE_DATA` (26 octets) et `example_key_json` repris tels quels, avec leur source exacte. Clair attendu : `It's a secret to everybody`.
- `rejections` : 18 cas — version, `kty`, `alg`, `ext`, `key_ops` (2), alphabets (3), longueurs (5), remplissage trop long, blanc de fin, `hashes` absent, `hashes` sans `sha256` (sha512 seul). Chaque cas porte `refusedAt` : `deserialize` (refusé par `ruma` à la lecture) ou `decryptor` (refusé par le déchiffreur officiel), ce que le test Rust affirme précisément.
- `padding` : un cas où `k`, `iv` et `sha256` portent un remplissage canonique, avec le `ciphertext` correspondant. Il prouve la tolérance en lecture et la réémission sans remplissage.
- `plaintextRule` : `byte(i) = u8(7 + 31*i + (i >> 8))`, partagée mot pour mot avec le test Swift. Aucun octet de clair stocké n'est nécessaire, ce qui permet d'exercer 4 Mio sans JSON de 5,6 Mo.

Le cas 4 194 304 octets n'est **pas** stocké : il est réellement exécuté par `large_sizes_are_exercised_with_the_official_oracle` (chiffrement puis déchiffrement officiels de 4 Mio en mémoire) et par le test Swift `testPayloadBoundsAcceptZeroAndTheLimitAndRejectBeyond` (à exécuter sur runner Apple).

### 5.3 Clé et IV « imposés » : ce que l'API officielle permet

`AttachmentEncryptor::new(reader)` tire lui-même clé et IV ; il n'existe aucun constructeur public qui accepte une clé ou un IV imposés, et `MediaEncryptionInfo` n'est pas `Clone`. Conformément à la consigne (« si l'API Rust ne permet pas seed/key/IV imposés, employer fixtures enregistrées et déchiffrement officiel ; aucune API inventée ») :

- le chiffrement est produit par l'oracle avec sa propre clé/IV, puis **enregistré** ;
- le sens oracle → Swift est prouvé par le déchiffrement officiel de ces octets (`committed_vectors_open_with_the_official_module`) ;
- le sens Swift → oracle utilise le harnais réservé : Swift scelle avec la clé/IV enregistrés et doit retrouver **exactement** le chiffré officiel (`testSealReproducesEveryOfficialVector`, y compris le vecteur amont). C'est une réponse connue dans les deux sens, sans second oracle Rust.

### 5.4 Génération et revalidation

```text
# réécrit la fixture (oracle officiel, lockfile inchangé)
pwsh -File prototypes/messaging-crypto/scripts/generate-media-vectors.ps1
# ou
DRIVY_MEDIA_VECTORS_WRITE=1 cargo test --locked \
  --manifest-path prototypes/messaging-crypto/Cargo.toml \
  --test media_vectors regenerate_when_requested -- --exact

# revalidation : relit, déchiffre, refuse et vérifie la couverture
cargo test --locked --manifest-path prototypes/messaging-crypto/Cargo.toml --test media_vectors
```

Le test échoue si le format change : une info qui ne se relit plus, un `key_ops` réordonné, un remplissage émis, un alphabet inversé ou un hash incohérent cassent une assertion nommée. La fixture étant committée, une régénération fraîche n'est pas nécessaire pour détecter une divergence : le test Swift et le test Rust la comparent aux octets enregistrés.

## 6. Résultats réellement exécutés

Environnement : Windows x86_64, `cargo 1.99.0`, `rustc 1.99.0`, hors ligne, `--locked`.

| # | Commande | Résultat | Code |
|---|---|---|---|
| 1 | `cargo test --locked --offline --manifest-path prototypes/messaging-crypto/Cargo.toml` (avant ajout) | 4 scénarios `scenarios` verts, 0 échec ; lib 0 test ; doctests 0 ; compilation 1 min 06 s | 0 |
| 2 | `cargo test --locked --offline ... --test media_vectors` (fixture absente) | **RED** : 2 verts, 6 échecs, cause « fixture absente (os error 2) », pas une erreur de compilation | 1 |
| 3 | `DRIVY_MEDIA_VECTORS_WRITE=1 cargo test --locked --offline ... --test media_vectors regenerate_when_requested -- --exact` | 1 vert, 7 filtrés, fixture écrite (103 550 octets) | 0 |
| 4 | `cargo test --locked --offline ... --test media_vectors` | **GREEN** : 8 verts, 0 échec, 1,1 à 1,2 s | 0 |
| 5 | `cargo test --locked --offline --manifest-path prototypes/messaging-crypto/Cargo.toml` (suite complète, après ajout) | 8 + 4 verts, 0 échec | 0 |
| 6 | Port Python jetable de l'algorithme base64, de la règle de clair et de la validation Swift (hors dépôt) | 35 vérifications, 0 échec : alphabets, longueurs, remplissage toléré/refusé, hash des 6 vecteurs + amont, 18 refus | 0 |

Les tests 1, 4 et 5 portent sur du code exécuté ; le test 6 ne prouve **pas** la compilation Swift, seulement la logique transposée.

### NON EXÉCUTÉ

- **Swift / Xcode / simulateur** : aucun outil Apple sur le poste. `MessagingMediaCryptographyTests.swift` est écrit, relu et aligné sur la fixture, mais aucun test Swift n'a été compilé ni exécuté ici. Aucun RED/GREEN Swift n'est revendiqué.
- **CommonCrypto** : le comportement de `CCCryptorCreateWithMode` en `kCCModeOptionCTR_BE`, l'absence de tampon interne de `CCCryptorUpdate` et `SecRandomCopyBytes` ne peuvent pas être vérifiés hors Apple. Le code échoue fermé (`cipherUnavailable`) si `moved != input.count`.
- **Compteur big-endian** : prouvé côté Rust (`ctr::Ctr128BE` utilisé par la crate officielle) ; l'équivalence avec `kCCModeOptionCTR_BE` de CommonCrypto n'est pas encore prouvée.
- **4 Mio côté Swift** : test écrit, non exécuté.

## 7. Limites et risques

- La voie Swift est une **implémentation** du format publié : la fidélité n'est pas garantie par construction comme le serait un appel direct au module amont (contrat §4.3.3). Elle est traitée par les vecteurs, pas par la langue.
- Une divergence résiduelle (par exemple un compteur little-endian si `kCCModeOptionCTR_BE` était ignoré) serait détectée par le premier test Swift ; elle ne peut pas être exclue avant un runner Apple.
- Le vecteur amont prouve la stabilité du format entre 0.17.0 et 0.19.1, pas que la FFI liée expose un jour ces primitives.
- Aucune zéroïsation mémoire des octets clairs ou de la clé n'est revendiquée. `V2EncryptedFileInfo` de `ruma` zéroïse sa clé à la destruction ; l'implémentation Swift ne fait pas cette promesse.
- `verify` ne protège que l'intégrité du chiffré relativement à l'événement Megolm qui porte la clé et le hash : ni authenticité d'expéditeur, ni confidentialité contre un appareil compromis (contrat §4.3.3).
- Le harnais `init(reservedKey:reservedIV:)` doit rester sans appel produit. Une revue de T2b doit le vérifier.
- Les erreurs portent des messages français fixes ; elles ne sont pas encore mappées sur les codes `M-SIZE`/`M-INTEGRITY`/`M-HASH` du contrat §3.11, ce qui relève du transport et du cache (T2b).

## 8. Suite (hors lot)

T2b consomme `MessagingMediaCryptography`, `MessagingSealedMedia` et `MessagingMediaEncryptionInfo` tels quels : intention scellée AES-GCM + Keychain, transport binaire, cache AES-GCM, miniatures, contenu v3 `ch.drivy.messaging`, temporaire PDF borné. Aucune activation produit ni publication n'est autorisée par ce lot.
