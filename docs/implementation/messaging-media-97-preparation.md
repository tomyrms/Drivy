# Médias #97 — T2b6 : préparation locale des fichiers et miniatures en mémoire

Base : `e2edc85ed092237016620079d52d11eb7a2d02b5` (qualifiée Apple 1515/1515 et Linux),
branche de travail `tomyrms/issues-medias-preparation-97`. Cible iOS 26.0 / Swift 6
(`apps/ios/project.yml`). Aucune dépendance, aucun `package.json`, aucun `project.yml`,
aucun workflow, aucun lock modifié. **Aucune correction de revue consommée** : première
passe de ce lot (plafond de deux corrections non entamé).

Périmètre : produire, **en mémoire**, les données que le futur coordinateur média scellera —
nature réelle du fichier, original conservé octet pour octet, nom d'affichage assaini,
dimensions d'affichage et miniature bornée. Aucun écran, aucune persistance, aucun cache,
aucune requête réseau, aucun chiffrement, aucun identifiant de média, aucune clé.

## 0. Modèle, skills et Codebase Memory (preuves de cette passe)

| Élément | Valeur observée |
|---|---|
| Modèle effectif | `opencode-go/deepseek-v4.1-flash` (DeepSeek V4.1 Flash), sans variante de modèle ni d'effort ; la révision et l'effort ne sont pas exposés par ce runtime |
| Skills Superpowers chargés (outil `skill`, réellement) | `test-driven-development` (base `C:\Users\jtoma\.config\opencode\node_modules\superpowers\skills\test-driven-development`), `verification-before-completion` (même base) |
| Projet Codebase Memory | `C-Users-jtoma-orca-workspaces-Drivy-issues-medias-preparation-97`, **racine identique au worktree** : `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-preparation-97` (alias d'indexation demandé `drivy-media-preparation-97-20261104` ; le serveur résout par nom de racine). Aucun index voisin consulté |
| Fraîcheur | `status: ready`, `indexed_at: 2026-11-04T21:52:19Z`, 39 494 nœuds / 170 851 arêtes, `watch: git` (dernier scan 21:52:36Z) ; ré-indexation après commit à `22:06:47Z` (53 137 nœuds / 202 966 arêtes), sans erreur de parse partiel sur les deux fichiers de ce lot |
| Couverture relue | `MessagingMediaContent.swift`, `MessagingContracts.swift`, `MessagingDiagnostics.swift`, `MessagingMediaContentTests.swift` : `no_recorded_issue` + `metadata_match` (caveat « best effort » lu, sources ouvertes directement) |
| Recherches | `MessagingMediaAttachment` (1 nœud, `MessagingMediaContent.swift:14-101`), `MessagingMediaName` (`:106-127`), `MessagingMediaCache` → **0 résultat dans cette base**, `MessagingMediaPrepar*` → **0 résultat** (le lot est bien neuf) |
| Dépendances entrantes | `trace_path(MessagingMediaAttachment, inbound)` : 22 appelants, tous dans `DrivyTests` (`MessagingMediaContentTests`, `MatrixMessagingCryptographyTests`, `MessagingThreadTests`, `MessagingCoreTests`) ; aucune surface de production ne consomme encore la préparation |
| Sources primaires Apple vérifiées avant usage | `CGImageSourceCreateThumbnailAtIndex(_:_:_:)`, `kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceCreateThumbnailWithTransform`, `kCGImageSourceThumbnailMaxPixelSize`, `CGImageSourceGetStatusAtIndex`, `CGImageSourceStatus.statusComplete`, `CGImageSourceGetType`, `CGImageDestinationCreateWithData`, `CGImageDestinationAddImage`, `CGImageDestinationFinalize`, `kCGImageDestinationLossyCompressionQuality`, `kCGImageProperty{HasAlpha,PixelWidth,PixelHeight,Orientation,GPSDictionary,GPSLatitude,GPSLongitude,ExifDictionary,ExifUserComment,TIFFDictionary,TIFFMake}`, `PDFDocument.init?(data:)`, `isLocked`, `isEncrypted`, `pageCount`, `page(at:)`, `UTType.jpeg`/`UTType.png` |

## 1. Interfaces livrées (nouveau fichier seulement)

`apps/ios/Drivy/MessagingCore/MessagingMediaPreparation.swift` :

```swift
struct MessagingPreparedMedia: Sendable, Equatable {
    let data: Data                                   // original clair, en mémoire
    let mime: MessagingMediaAttachment.MIME
    let name: String                                 // assaini, borné, jamais un chemin
    let width: Int?                                  // dimensions d'affichage ; nil pour un PDF
    let height: Int?
    let thumbnail: Data?                             // JPEG/PNG local ; nil pour un PDF
}

protocol MessagingMediaPreparing: Sendable {
    func prepare(_ data: Data, suggestedName: String) throws -> MessagingPreparedMedia
}

enum MessagingMediaPreparationFailure: Error, Equatable, Sendable {
    case invalidSize, invalidName, invalidFormat, invalidDimensions, unreadable, lockedPDF, thumbnailUnavailable
}

struct MessagingMediaPreparer: MessagingMediaPreparing {
    static let maximumThumbnailAxis = 512
    static let maximumThumbnailByteSize = 131_072
}
```

Aucun `mediaID`, aucune clé, aucune `URL`, aucun chemin, aucun `PDFDocument`/`CGImage`/`UI`
dans les types exposés. Aucun `LocalizedError`, aucun texte libre : le mapping de
présentation appartient au lot UI.

**Appel par le futur coordinateur, hors MainActor.** `prepare` est **synchrone** : les
décodeurs ImageIO et PDFKit sont des appels natifs bloquants, et une signature `async`
laisserait croire à une interruption immédiate qui n'existe pas. Le coordinateur appelle donc
la préparation dans une tâche détachée ou sur un acteur de fond, jamais sur le fil de
l'interface :

```swift
let prepared = try await Task.detached(priority: .userInitiated) {
    try preparer.prepare(bytes, suggestedName: suggestedName)
}.value
```

L'annulation coopérative s'applique aux **frontières** (avant l'appel, entre deux médias),
pas au milieu d'un décodage système. Aucune interface ne reçoit d'`URL`, de `URLSession` ni
de fournisseur distant : l'import système (`PhotosPicker`, `fileImporter`) sera un lot UI.

## 2. Règles effectivement appliquées, dans cet ordre

1. **Taille d'abord, avant tout parseur** : `1 … 4 194 304` octets
   (`MessagingMediaAttachment.minimumByteSize…maximumByteSize`), sinon `invalidSize`.
2. **Nom** : passe par `MessagingMediaName.sanitized` (C0, DEL, C1, U+202A–202E,
   U+2066–2069, `/`, `\` retirés ; 255 caractères au plus). Nom inutilisable → `invalidName`.
   Le nom n'est jamais utilisé comme chemin et n'influence jamais le type.
3. **Nature réelle par les octets** : signatures JPEG (`FF D8 FF`), PNG (8 octets), PDF
   (`%PDF-`). Puis le **parseur système** confirme : `CGImageSourceGetType` doit rendre
   exactement `public.jpeg` / `public.png` ; `PDFDocument(data:)` doit ouvrir le document.
   L'extension et un type déclaré ne décident jamais. HEIC, GIF, SVG et tout autre format →
   `invalidFormat`, sans conversion silencieuse.
4. **Images, dimensions avant tout bitmap** : `CGImageSourceCopyPropertiesAtIndex` donne
   `PixelWidth`/`PixelHeight`/`Orientation`/`HasAlpha` sans décoder l'image. Bornes du
   produit réappliquées à l'identique : 1…12 000 px par axe, ≤ 40 000 000 de pixels,
   multiplication avec `multipliedReportingOverflow` (aucun débordement) → sinon
   `invalidDimensions`. Dimensions d'affichage = pixels échangés pour les orientations 5 à 8.
5. **Image tronquée ou inexploitable** : `CGImageSourceGetStatusAtIndex(_, 0)` doit être
   `.statusComplete`, sinon `unreadable` ; pas de miniature produite à partir d'un fichier
   partiel.
6. **Miniature** : `CGImageSourceCreateThumbnailAtIndex` avec
   `kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceCreateThumbnailWithTransform`
   et `kCGImageSourceThumbnailMaxPixelSize ≤ 512` : le décodeur réduit avant de matérialiser,
   le bitmap pleine résolution n'est jamais alloué pour la miniature, l'orientation est
   appliquée par le décodeur. Ré-encodage dans un `CFMutableData` **sans dictionnaire de
   propriétés** : aucune EXIF/GPS/TIFF/XMP/ICC de l'original n'est recopiée. PNG quand
   l'image a un canal alpha (transparence conservée), JPEG sinon. Paliers **finis** :
   JPEG `(512, 0,80) (512, 0,60) (512, 0,45) (384, 0,60) (384, 0,45) (256, 0,60) (192, 0,50) (128, 0,50)`,
   PNG `512, 384, 256, 192, 128`. Premier palier sous 131 072 octets retenu ; sinon
   `thumbnailUnavailable` — jamais un succès hors contrat.
7. **PDF** : `PDFDocument(data:)` en mémoire, `isLocked` refusé (`lockedPDF`) sans demande de
   mot de passe, au moins une page exploitable (`pageCount ≥ 1` et `page(at: 0) != nil`)
   sinon `unreadable`. `width`/`height`/`thumbnail` valent `nil` : l'aperçu complet sera rendu
   par le lot UI depuis `data`, sans fichier clair pour une bibliothèque qui exigerait une URL.
   Aucun lien ouvert, aucune action exécutée, aucune analyse externe, aucun réseau.
   L'acceptation du parseur n'est **pas** une certification de sécurité du document.

## 3. Écarts assumés avec le contrat préparatoire (§3.2, §3.10, §4.2)

| Point du contrat | Décision de ce lot |
|---|---|
| §3.2.3 : redimensionner ≤ 2 048 px, convertir en JPEG 0,8, supprimer EXIF/GPS/XMP **de l'original** | **Remplacé** par la consigne de la tâche : l'original est conservé **octet pour octet**, sans retouche des pixels, pages ni métadonnées. Ce lot **ne supprime pas** les EXIF/GPS et ne le prétend pas ; le contenu complet sera chiffré par T2a. Seule la miniature est reconstruite sans métadonnées |
| §3.2.4 : PDF conservé tel quel ≤ 4 Mio | Appliqué, plus le refus des documents verrouillés ou sans page |
| §3.10 : temporaire de rendu PDF en clair pendant l'affichage | **Non créé ici** : `PDFDocument(data:)` ne demande pas d'URL. Le lot UI tranchera le rendu ; aucun temporaire n'est introduit par cette primitive |
| §3.10 : miniature ≤ 512 px, ≤ 128 Kio, générée localement, jamais envoyée | Appliqué à l'identique |
| §4.2 : PDF ≤ 50 pages rendues | **Non appliqué** ici : aucune page n'est rendue et le compte de pages n'appartient pas à l'interface convenue. Risque résiduel consigné au §6 |
| Poids du lot | Le plafond 4 Mio et les bornes de dimensions réutilisent les constantes existantes de `MessagingMediaAttachment`, sans les redéfinir |

## 4. Garanties structurelles et ce qu'elles ne prouvent pas

- **Aucune écriture disque, aucun temporaire** : la primitive ne connaît ni `URL`, ni
  `FileManager`, ni `CGImageDestinationCreateWithURL` ; l'encodeur écrit dans un
  `CFMutableData`, PDFKit lit `Data`. C'est une propriété **structurelle, relue en source**,
  pas une preuve instrumentale. Le test `testPreparationDoesNotWriteToTheTemporaryDirectory`
  ne couvre que le répertoire temporaire du processus de test.
- **Aucun réseau** : aucun `URLSession`, aucun import réseau dans le fichier. Même limite :
  relu, pas mesuré.
- **Aucun journal** : `MessagingDiagnostics` n'est pas appelé ; aucun octet, nom, dimension,
  identifiant ni erreur libre n'est émis. Vérifié en source (le fichier ne contient aucun
  appel de journalisation), pas par un test de sentinelle.
- **Aucune donnée réelle** : les seules entrées de test sont générées à l'exécution.

## 5. Tests écrits — et **non exécutés**

`apps/ios/DrivyTests/MessagingMediaPreparationTests.swift`, 26 tests, **écrits avant
l'implémentation**. **NON EXÉCUTÉ : aucun outil Apple sur ce poste** (`Get-Command swift,
swiftc, xcodebuild, xcrun, xcodegen` → 0 outil, Windows). Aucun RED/GREEN Swift n'est
revendiqué, aucune fixture Python ne remplace une compilation, et la base verte du worktree
ne couvre pas cet ajout.

| Test | Ce qu'il exige |
|---|---|
| `testJPEGIsPreparedWithItsRealTypeAndDisplaySize` | type JPEG réel, dimensions d'affichage, original identique, miniature JPEG 512×384 |
| `testPNGWithTransparencyIsPreparedAsPNG` | type PNG réel, miniature PNG conservant `HasAlpha` |
| `testDeclaredNameNeverDecidesTheType` | PDF nommé `photo.jpg` → `.pdf` ; JPEG nommé `bilan.pdf` → `.jpeg` |
| `testSizeBoundIsCheckedBeforeAnyParser` | 0 octet et 4 Mio + 1 → `invalidSize` ; exactement 4 Mio d'octets inconnus → `invalidFormat` (la porte de taille est bien franchie) |
| `testNameIsSanitisedAndBounded` | U+202E et U+0000 retirés ; 400 caractères ramenés à 255 |
| `testUnusableNameIsRefused` | nom vide ou entièrement interdit → `invalidName` |
| `testTruncatedJPEGIsRefused` / `testTruncatedPNGIsRefused` | corps coupé à la moitié, signature intacte → `unreadable` |
| `testEmptyImageBodyIsRefused` | signature PNG seule → refus fermé (`unreadable` ou `invalidDimensions`), jamais un succès |
| `testUnknownBytesAndForeignFormatsAreRefused` | bruit, GIF, HEIC, SVG, texte → `invalidFormat` |
| `testAxisLimitIsEnforcedWithoutAGiantBitmap` | 12 001 × 1 → `invalidDimensions` |
| `testPixelCountLimitIsEnforcedWithoutAGiantBitmap` | 12 000 × 3 400 (40,8 Mpx) → `invalidDimensions`, avec un PNG 1 bit de 5 Mio pour ne pas encoder 40 Mpx |
| `testAxisBoundaryIsAccepted` | 12 000 × 1 accepté (borne inclusive) avec miniature |
| `testThumbnailIsBoundedInSizeAndKeepsTheAspect` | 900 × 300 → 512 × ~171, ≤ 128 Kio |
| `testThumbnailFollowsTheDisplayOrientation` | JPEG orientation 6 : dimensions 300 × 900, miniature 90° tournée (h = 512) |
| `testNoisyOpaqueJPEGThumbnailStaysWithinTheBounds` | bruit 2 400 × 1 800 : miniature ≤ 128 Kio, axe ≤ 512 |
| `testNoisyTransparentPNGThumbnailStaysWithinTheBounds` | bruit RGBA 1 024 × 1 024 : PNG, alpha, ≤ 128 Kio, axe ≤ 512 |
| `testThumbnailCarriesNoPersonalMetadataFromTheOriginal` | original portant GPS/TIFF/EXIF synthétiques : miniature sans ces dictionnaires |
| `testThumbnailIsNeverTheOriginalBytes` | la miniature n'est pas une copie de l'original |
| `testPDFIsPreparedFromMemoryWithNoDimensionsAndNoThumbnail` | PDF 1 page : `.pdf`, dimensions et miniature `nil`, octets identiques |
| `testEmptyPDFIsRefused` | PDF sans page → `unreadable` |
| `testCorruptedPDFIsRefused` | PDF tronqué → `unreadable` |
| `testPasswordProtectedPDFIsRefusedWithoutPasswordPrompt` | PDF chiffré AES-128 : `lockedPDF`, aucune demande de mot de passe |
| `testOriginalBytesAreNeverModified` | JPEG, PNG, PDF : octets strictement inchangés après préparation |
| `testPreparationDoesNotWriteToTheTemporaryDirectory` | aucun fichier apparu (vérification faible, cf. §4) |
| `testProtocolSeamTakesBytesAndAName` | le protocole est le seul point d'entrée ; deux appels identiques rendent la même valeur |

À lancer sur un runner Apple, au SHA de livraison exact :

```bash
xcodebuild test \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DrivyTests/MessagingMediaPreparationTests \
  -derivedDataPath artifacts/ios/DerivedData
```

`scripts/ios/test-selection.sh` n'inclut pas cette classe dans la sélection `messaging`
(fichier d'un autre lot, non modifié) : seul le `-only-testing` ci-dessus l'exécute tant que
son propriétaire ne l'y ajoute pas.

### Fixtures synthétiques

- Images : pixels RGBA générés par `CGContext` puis encodés par `CGImageDestination` dans le
  test (bruit déterministe, alpha, orientation EXIF, GPS 0/0 et mentions factices
  « SyntheticCamera »). Aucune photo, aucun fichier du poste, aucune coordonnée réelle.
- PNG 1 bit de grande dimension : écrit à la main (IHDR + `deflate` en blocs « stored » +
  CRC32/Adler-32), uniquement pour prouver la borne de 40 Mpx sans encoder 40 Mpx. La
  structure de cet écrivain a été **validée hors du dépôt** par un miroir Python relu par
  Pillow (dimensions exactes, image complète) et par `zlib.decompress` — cela ne prouve pas
  la syntaxe Swift.
- PDF minimal : structure écrite dans le test, **relue hors dépôt** par `pypdf` (1 page puis
  0 page correctement parsées). PDF chiffré : produit hors dépôt par `pypdf`
  (`algorithm="AES-128"`, mot de passe synthétique), puis relu : chiffré, pages inaccessibles
  sans mot de passe, une page après déchiffrement. Encodé en base64 dans le test (1 300
  caractères).

## 6. Limites, risques et hypothèses à confirmer sur le runner Apple

1. **Aucune compilation locale** : le fichier et les tests n'ont jamais été compilés. Les
   APIs employées sont celles vérifiées dans les sources Apple (§0), mais le respect de
   Swift 6 `SWIFT_STRICT_CONCURRENCY: complete` reste à prouver par le run.
2. **Catégorie PDFKit pour un PDF verrouillé** : le test exige `lockedPDF` (donc
   `PDFDocument.isLocked == true`). Si PDFKit refusait de créer le document pour ce fichier
   chiffré AES-128, la primitive rendrait `unreadable` : le contrat « refusé sans demande de
   mot de passe » resterait tenu, mais le test devrait être ajusté et la catégorie consignée.
3. **Écriture de l'orientation EXIF par les fixtures** : le test d'orientation vérifie
   d'abord que le JPEG de test porte bien `Orientation = 6` ; si `CGImageDestination`
   normalisait l'orientation à l'écriture, l'échec désignerait la fixture, pas la primitive.
4. **Coût CPU borné mais réel** : jusqu'à 8 paliers de miniature pour une image JPEG, chaque
   palier ré-échantillonné par ImageIO. Le coût d'un média de 4 Mio n'est pas mesuré ; aucune
   promesse de durée n'est faite.
5. **Bornes non couvertes** : le nombre de pages PDF n'est pas limité ici (§3.2/§4.2 parlent
   de 50 pages *rendues*, décision du lot UI) ; un PDF valide de plusieurs centaines de pages
   est accepté. Les bombes de décompression sont couvertes par la borne de dimensions lue
   dans l'en-tête, pas par une mesure mémoire.
6. **Miniature et cache** : `MessagingMediaCache` n'existe pas dans cette base (autre worker).
   La compatibilité repose sur le contrat §3.10 (≤ 512 px, ≤ 128 Kio, JPEG/PNG en mémoire) ;
   le format exact attendu par ce cache — et le fait qu'il ré-encode — n'est pas vérifié ici.
7. **Pas de preuve instrumentale** d'absence d'écriture disque, de réseau ou de journal (§4).
8. Aucun parcours utilisateur n'est livré ni annoncé : pas d'écran, pas d'import, pas de
   coordinateur, pas d'activation produit.

## 7. Ce que le futur coordinateur doit faire (et que ce lot ne fait pas)

1. Appeler `prepare` **hors MainActor** (§1) et traiter les sept catégories fermées avec ses
   propres textes, hors de cette primitive.
2. Créer `mediaID` **et** la clé de fichier **une seule fois**, au sceau (T2a), puis chiffrer
   `data` tel quel : la préparation ne conserve aucun hash du clair et ne modifie aucun octet.
3. Passer `thumbnail` au cache local (T2b, autre worker) ; ne **jamais** l'envoyer au
   serveur, ne jamais la placer dans le contenu Matrix.
4. Ne rien annoncer comme envoyé avant l'écriture durable du sceau et l'accusé serveur ; la
   préparation n'est qu'une étape locale et ne prouve aucune livraison.
5. Terminer l'import système (`PhotosPicker`, `fileImporter`) dans le lot UI : cette
   primitive ne reçoit que des octets et un nom, jamais une URL ni un chemin.

## 8. Vérifications réellement exécutées sur ce poste

- `git rev-parse HEAD` → `e2edc85ed092237016620079d52d11eb7a2d02b5` ; `git status --porcelain`
  → seulement les trois fichiers nouveaux de ce lot (deux sources, ce rapport).
- `Get-Command swift, swiftc, xcodebuild, xcrun, xcodegen` → **0 outil** : aucun test, aucune
  compilation, aucun simulateur.
- Indexation Codebase Memory de la racine du worktree, fraîcheur et couverture relues (§0).
- Ré-indexation après commit : les deux fichiers de ce lot sont lus par le parseur Swift de
  l'indexeur sans « parse partiel » et leurs déclarations sont extraites (`MessagingPreparedMedia`,
  `MessagingMediaPreparer`, `MessagingMediaPreparationTests`). C'est un signal structurel de
  syntaxe, **pas** une compilation ni une exécution.
- Sources primaires Apple relues pour chaque API employée (§0).
- Fixtures relues hors dépôt par `pypdf` et Pillow (structure PDF et PNG), sans prétendre
  prouver le code Swift ni le comportement d'ImageIO/PDFKit sur Apple.
- Aucun fichier existant, UI, factory, coordinateur, outbox, cache, crypto, DTO, lock,
  projet, workflow, `STATUS.md` ni dossier de conception modifié.

## 9. Sources

- `AGENTS.md`, `Drivy_Conception_v3_17_2026-09-20/COMMENCER_ICI.md`
- `docs/implementation/medias-exploitation-contrat-20261104.md` §3.2, §3.10, §3.11, §3.12, §4.2, §4.5, §7.1
- `C:/Users/jtoma/orca/workspaces/Drivy/sealion/docs/implementation/orchestration-20261104/medias-arbitrages-coordinateur.md` (addendum : iOS 26, `PDFDocument(data:)` sans temporaire, pas de politique d'exploitation approuvée)
- `docs/implementation/messaging-media-97-content.md` (T2b1 : contenu v3), `messaging-media-97-transport.md` (T2b2), `messaging-media-97-crypto.md` (T2a)
- `apps/ios/Drivy/MessagingCore/MessagingMediaContent.swift` (constantes de `MessagingMediaAttachment`, `MessagingMediaName.sanitized`)
- Apple : `CGImageSourceCreateThumbnailAtIndex`, `CGImageSourceGetStatusAtIndex`, `CGImageDestinationCreateWithData`, `PDFDocument.init?(data:)`, `PDFDocument.isLocked`, `UTType.jpeg`/`png`
