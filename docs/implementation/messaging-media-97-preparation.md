# Médias #97 — T2b6 : préparation locale des fichiers et miniatures en mémoire

Candidat : `7cb065a2a43b532cb800b81b2b907c7cc9e90499`, branche de travail
`tomyrms/issues-medias-preparation-97`. Cible iOS 26.0 / Swift 6 (`apps/ios/project.yml`).
Aucune dépendance, aucun `package.json`, aucun `project.yml`, aucun workflow, aucun lock
modifié.

**Correction 1/2**, après une exécution Apple réellement rouge du candidat intégré
`62560a2ed8c55326f73c512c9ac9dfaa08a5382b` (run `41962003316`, job `127030313656`,
compilation réussie puis tests exécutés) : 26 tests lancés dans
`MessagingMediaPreparationTests`, **5 cas en échec, 6 assertions**
(`C:/Users/jtoma/orca/workspaces/Drivy/bristleworm/artifacts/q4-diagnostics-metier.json`).
Les limites produit, les invariants et les 26 scénarios sont conservés ; aucun test rendu
permissif, aucune dépendance ni fichier ajouté.

Périmètre : produire, **en mémoire**, les données que le futur coordinateur média scellera —
nature réelle du fichier, original conservé octet pour octet, nom d'affichage assaini,
dimensions d'affichage et miniature bornée. Aucun écran, aucune persistance, aucun cache,
aucune requête réseau, aucun chiffrement, aucun identifiant de média, aucune clé.

## 0. Modèle, skills et Codebase Memory (preuves de cette passe)

| Élément | Valeur observée |
|---|---|
| Modèle effectif | `opencode-go/deepseek-v4.1-flash` (DeepSeek V4.1 Flash), sans variante de modèle ni d'effort ; la révision et l'effort ne sont pas exposés par ce runtime |
| Skills Superpowers chargés (outil `skill`, réellement) | `systematic-debugging` (base `C:\Users\jtoma\.config\opencode\node_modules\superpowers\skills\systematic-debugging`, pour cette correction) ; `test-driven-development` et `verification-before-completion` (même base, première passe et tests de régression) |
| Projet Codebase Memory | `C-Users-jtoma-orca-workspaces-Drivy-issues-medias-preparation-97`, **racine identique au worktree** : `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-preparation-97` (alias d'indexation demandé `drivy-media-preparation-97-20261104` ; le serveur résout par nom de racine). Aucun index voisin consulté |
| Fraîcheur | `status: ready`, ré-indexation après cette correction à `2026-11-05T04:17:28Z` (53 153 nœuds / 203 033 arêtes), `watch: git` ; les deux fichiers du lot sont lus sans erreur de parse partiel et le nouveau `MessagingMediaPreparationContainer` y est extrait (signal structurel, pas une compilation) |
| Couverture relue | `MessagingMediaContent.swift`, `MessagingContracts.swift`, `MessagingDiagnostics.swift`, `MessagingMediaContentTests.swift` : `no_recorded_issue` + `metadata_match` (caveat « best effort » lu, sources ouvertes directement) |
| Recherches | `MessagingMediaAttachment` (1 nœud, `MessagingMediaContent.swift:14-101`), `MessagingMediaName` (`:106-127`), `MessagingMediaCache` → **0 résultat dans cette base**, `MessagingMediaPrepar*` → le nœud livré par le lot |
| Dépendances entrantes | `trace_path(MessagingMediaAttachment, inbound)` : 22 appelants, tous dans `DrivyTests` ; aucune surface de production ne consomme encore la préparation |
| Sources primaires Apple vérifiées avant usage | `CGImageSourceCreateThumbnailAtIndex(_:_:)`, `kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceCreateThumbnailWithTransform`, `kCGImageSourceThumbnailMaxPixelSize`, `CGImageSourceGetStatusAtIndex` (documenté pour les sources incrémentales, **sans promesse de détection de troncature**), `CGImageSourceStatus.statusComplete`, `CGImageSourceGetType`, `CGImageDestinationCreateWithData`, `CGImageDestinationAddImage`, `CGImageDestinationFinalize`, `kCGImageDestinationLossyCompressionQuality`, `kCGImageProperty{HasAlpha,PixelWidth,PixelHeight,Orientation,GPSDictionary,GPSLatitude,GPSLongitude,ExifDictionary,ExifUserComment,ExifDateTimeOriginal,TIFFDictionary,TIFFMake,TIFFArtist}`, `PDFDocument.init?(data:)`, `isLocked`, `isEncrypted`, `pageCount`, `page(at:)`, `UTType.jpeg`/`UTType.png` |
| Références de format (contrôle du conteneur) | ITU-T T.81 (marqueur EOI `0xFFD9`) ; W3C PNG 3e édition (REC-png-3-20250624) §4.8.2 et §5.2 : le flux commence par `IHDR` et **se termine par `IEND`** |

### 0.1 Diagnostic des cinq échecs Apple (correction 1/2)

Chaque échec est classé : **erreur de fixture/attente** (le produit était correct, la donnée
de test violait une borne) ou **défaut produit** (le contrat promettait un refus que le code
ne rendait pas).

| Échec (assertion Apple) | Cause établie | Classe | Correction |
|---|---|---|---|
| `testNoisyOpaqueJPEGThumbnailStaysWithinTheBounds:469` — `invalidSize` | La fixture 2 400 × 1 800 en bruit uniforme était encodée **sans `kCGImageDestinationLossyCompressionQuality`** : ImageIO encode alors au maximum et le fichier dépassait 4 Mio. La garde de taille a donc refusé avant toute miniature | fixture | fixture 1 200 × 900 avec qualité **explicite** 0,6, plus `assertFixtureFits` qui impose ≤ 4 Mio **avant** d'attendre une miniature |
| `testPixelCountLimitIsEnforcedWithoutAGiantBitmap:419` — `invalidSize` au lieu de `invalidDimensions` | La fixture PNG 1 bit de 12 000 × 3 400 utilisait des blocs deflate « stored » : 5 103 853 octets, donc au-dessus du plafond produit. Là encore, la garde de taille s'appliquait légitimement | fixture | déflateur **réel** (Huffman fixe, copies de 258 octets à distance 1) : 32 367 octets pour les mêmes dimensions, plus `assertFixtureFits`. La limite produit et l'ordre des gardes sont inchangés |
| `testThumbnailCarriesNoPersonalMetadataFromTheOriginal:500` — dictionnaire EXIF non nul | Attente trop large : ImageIO **recrée** des propriétés EXIF techniques (dimensions, espace colorimétrique, version) dans le JPEG produit par `CGImageDestinationAddImage(_, _, nil)`. Le GPS, lui, était bien absent (aucun autre échec sur ces assertions) | attente | le contrat porte désormais sur les **valeurs personnelles** : marqueurs synthétiques d'appareil, d'auteur, de commentaire et de date de prise de vue écrits dans l'original, puis exigés absents de la miniature ; le dictionnaire GPS reste interdit, les propriétés techniques sont admises |
| `testTruncatedJPEGIsRefused:353` et `testTruncatedPNGIsRefused:361` — aucune erreur | **Défaut produit** : `CGImageSourceGetStatusAtIndex(_, 0) == .statusComplete` ne détecte pas une troncature. Les sources Apple ne promettent d'ailleurs un statut utile que pour les sources incrémentales. ImageIO rendait `.statusComplete` et produisait une miniature à partir d'une moitié de fichier | produit | contrôle borné de **terminaison du conteneur** : EOI `0xFFD9` final (JPEG), marche des chunks jusqu'à `IEND` en fin de tampon (PNG), avant toute lecture de dimensions ; tests conservés stricts (`unreadable`), avec contrôle positif sur la fixture complète et deux points de coupure |

Aucune de ces corrections n'élargit une limite, ne déplace la garde de 4 Mio, ne rend une
assertion tolérante sur le contrat, et aucune n'ajoute de dépendance, de fichier temporaire,
de réseau ou de journal.

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
5. **Terminaison du conteneur, avant les dimensions** (correction 1/2) : lecture bornée des
   octets, sans décodage ni bitmap — EOI `0xFFD9` final pour un JPEG (zéros de remplissage
   finaux tolérés), marche des chunks jusqu'à `IEND` exactement en fin de tampon pour un PNG.
   Sinon `unreadable`. **Défaut prouvé par l'exécution Apple** : le seul statut ImageIO ne
   détectait pas un fichier coupé en deux.
6. **Image tronquée ou inexploitable** : en second rideau, `CGImageSourceGetStatusAtIndex(_, 0)`
   doit être `.statusComplete`, sinon `unreadable` ; pas de miniature produite à partir d'un
   fichier partiel.
7. **Miniature** : `CGImageSourceCreateThumbnailAtIndex` avec
   `kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceCreateThumbnailWithTransform`
   et `kCGImageSourceThumbnailMaxPixelSize ≤ 512` : le décodeur réduit avant de matérialiser,
   le bitmap pleine résolution n'est jamais alloué pour la miniature, l'orientation est
   appliquée par le décodeur. Ré-encodage dans un `CFMutableData` **sans dictionnaire de
   propriétés** : aucune valeur personnelle (position, date de prise de vue, appareil, auteur,
   commentaire) de l'original n'est recopiée ; ImageIO recrée en revanche des propriétés
   **techniques** (dimensions, espace colorimétrique, version EXIF) qu'il serait faux
   d'interdire. PNG quand l'image a un canal alpha (transparence conservée), JPEG sinon.
   Paliers **finis** :
   JPEG `(512, 0,80) (512, 0,60) (512, 0,45) (384, 0,60) (384, 0,45) (256, 0,60) (192, 0,50) (128, 0,50)`,
   PNG `512, 384, 256, 192, 128`. Premier palier sous 131 072 octets retenu ; sinon
   `thumbnailUnavailable` — jamais un succès hors contrat.
8. **PDF** : `PDFDocument(data:)` en mémoire, `isLocked` refusé (`lockedPDF`) sans demande de
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

## 5. Tests — exécutés sur Apple, corrigés ici

`apps/ios/DrivyTests/MessagingMediaPreparationTests.swift`, **26 scénarios conservés**.
**Version réellement exécutée** : le candidat `62560a2e` sur run `41962003316` / job
`127030313656` — 5 cas rouges, 6 assertions (§0.1). Les corrections ci-dessous ne sont
**pas** revendiquées vertes : **aucun outil Apple sur ce poste** (`Get-Command swift, swiftc,
xcodebuild, xcrun, xcodegen` → 0 outil, Windows). Aucune fixture Python ne remplace une
compilation, et la base verte du worktree ne couvre pas cet ajout ; le prochain run Apple est
à faire par le coordinateur sur le candidat intégré.

| Test | Ce qu'il exige |
|---|---|
| `testJPEGIsPreparedWithItsRealTypeAndDisplaySize` | type JPEG réel, dimensions d'affichage, original identique, miniature JPEG 512×384 |
| `testPNGWithTransparencyIsPreparedAsPNG` | type PNG réel, miniature PNG conservant `HasAlpha` |
| `testDeclaredNameNeverDecidesTheType` | PDF nommé `photo.jpg` → `.pdf` ; JPEG nommé `bilan.pdf` → `.jpeg` |
| `testSizeBoundIsCheckedBeforeAnyParser` | 0 octet et 4 Mio + 1 → `invalidSize` ; exactement 4 Mio d'octets inconnus → `invalidFormat` (la porte de taille est bien franchie) |
| `testNameIsSanitisedAndBounded` | U+202E et U+0000 retirés ; 400 caractères ramenés à 255 |
| `testUnusableNameIsRefused` | nom vide ou entièrement interdit → `invalidName` |
| `testTruncatedJPEGIsRefused` | **régression Q4** : fixture complète acceptée (contrôle), puis moitié des octets **et** fichier privé de ses deux derniers octets (EOI) → `unreadable` |
| `testTruncatedPNGIsRefused` | **régression Q4** : fixture complète acceptée (contrôle), puis moitié des octets **et** fichier privé de ses quatre derniers octets (`IEND`) → `unreadable` |
| `testEmptyImageBodyIsRefused` | signature PNG seule → refus fermé (`unreadable` ou `invalidDimensions`), jamais un succès |
| `testUnknownBytesAndForeignFormatsAreRefused` | bruit, GIF, HEIC, SVG, texte → `invalidFormat` |
| `testAxisLimitIsEnforcedWithoutAGiantBitmap` | 12 001 × 1 (fixture ≤ 4 Mio imposée) → `invalidDimensions` |
| `testPixelCountLimitIsEnforcedWithoutAGiantBitmap` | 12 000 × 3 400 = 40,8 Mpx → `invalidDimensions` ; PNG 1 bit **réellement compressé** (32 367 octets), `assertFixtureFits` exige ≤ 4 Mio avant l'attente |
| `testAxisBoundaryIsAccepted` | 12 000 × 1 accepté (borne inclusive) avec miniature |
| `testThumbnailIsBoundedInSizeAndKeepsTheAspect` | 900 × 300 → 512 × ~171, ≤ 128 Kio |
| `testThumbnailFollowsTheDisplayOrientation` | JPEG orientation 6 : dimensions 300 × 900, miniature 90° tournée (h = 512) |
| `testNoisyOpaqueJPEGThumbnailStaysWithinTheBounds` | bruit 1 200 × 900, **qualité explicite 0,6**, fixture ≤ 4 Mio imposée : miniature ≤ 128 Kio, axe ≤ 512 |
| `testNoisyTransparentPNGThumbnailStaysWithinTheBounds` | bruit RGBA 800 × 800, fixture ≤ 4 Mio imposée : PNG, alpha, ≤ 128 Kio, axe ≤ 512 |
| `testThumbnailCarriesNoPersonalMetadataFromTheOriginal` | original portant marqueurs synthétiques (appareil, auteur, commentaire, date de prise de vue) et une position : aucun ne survit ; dictionnaire GPS interdit ; propriétés techniques ImageIO admises |
| `testThumbnailIsNeverTheOriginalBytes` | la miniature n'est pas une copie de l'original |
| `testPDFIsPreparedFromMemoryWithNoDimensionsAndNoThumbnail` | PDF 1 page : `.pdf`, dimensions et miniature `nil`, octets identiques |
| `testEmptyPDFIsRefused` | PDF sans page → `unreadable` |
| `testCorruptedPDFIsRefused` | PDF tronqué → `unreadable` |
| `testPasswordProtectedPDFIsRefusedWithoutPasswordPrompt` | PDF chiffré AES-128 : `lockedPDF`, aucune demande de mot de passe |
| `testOriginalBytesAreNeverModified` | JPEG, PNG, PDF : octets strictement inchangés après préparation |
| `testPreparationDoesNotWriteToTheTemporaryDirectory` | aucun fichier apparu (vérification faible, cf. §4) |
| `testProtocolSeamTakesBytesAndAName` | le protocole est le seul point d'entrée ; deux appels identiques rendent la même valeur |

Un helper `assertFixtureFits` précède chaque attente dépendante d'une borne : un dépassement
de fixture se lit comme une erreur de fixture, plus jamais comme `invalidSize` du produit.

Le **RED de cette correction est réel et antérieur** : les deux tests de troncature ont échoué
sur Apple au candidat `62560a2e` avant toute modification ; le contrôle de terminaison du
conteneur a été écrit contre ce rouge établi, sans jamais rendre l'assertion tolérante. Pour
les trois autres cas, le rouge désignait la fixture ou l'attente, pas le produit.

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
  test (bruit déterministe, alpha, orientation EXIF, position 0/0 et **marqueurs personnels
  synthétiques** : appareil, auteur, commentaire, date `1999:12:31 23:59:58`). Aucune photo,
  aucun fichier du poste, aucune coordonnée réelle.
- Encodage JPEG des fixtures : **qualité explicite** quand la taille compte (`0,6`), pour ne
  pas dépendre du maximum par défaut d'ImageIO qui faisait dépasser 4 Mio.
- PNG 1 bit de grande dimension : écrit à la main (IHDR + déflateur **Huffman fixe** —
  littéral puis copies de 258 octets à distance 1 — + CRC32/Adler-32), uniquement pour prouver
  la borne de 40 Mpx sans encoder 40 Mpx. 12 000 × 3 400 pèse 32 367 octets, donc sous le
  plafond produit. La structure de cet écrivain a été **validée hors du dépôt** par un miroir
  Python relu par Pillow (dimensions exactes, image complète) et par `zlib.decompress` — cela
  ne prouve pas la syntaxe Swift.
- PDF minimal : structure écrite dans le test, **relue hors dépôt** par `pypdf` (1 page puis
  0 page correctement parsées). PDF chiffré : produit hors dépôt par `pypdf`
  (`algorithm="AES-128"`, mot de passe synthétique), puis relu : chiffré, pages inaccessibles
  sans mot de passe, une page après déchiffrement. Encodé en base64 dans le test (1 300
  caractères).
- Chaque fixture soumise à une borne passe par `assertFixtureFits` : la mesure ≤ 4 Mio est
  une **précondition** du test, plus une conséquence espérée.

## 6. Limites, risques et hypothèses à confirmer sur le runner Apple

1. **Aucune compilation locale** : le fichier et les tests n'ont jamais été compilés sur ce
   poste. Les APIs employées sont celles vérifiées dans les sources Apple (§0), mais le respect
   de Swift 6 `SWIFT_STRICT_CONCURRENCY: complete` et le comportement réel d'ImageIO restent à
   prouver par le prochain run Apple.
2. **Le contrôle de conteneur prouve la terminaison, pas l'intégrité** : EOI/IEND présents
   n'excluent pas une corruption interne (CRC faux, scan JPEG incohérent). Une telle image
   peut encore passer et produire une miniature partiellement grise. La seule preuve
   exhaustive serait un décodage pleine résolution, refusé par construction (aucun bitmap de
   40 Mpx alloué). Ce point reste **à observer sur Apple** avec des fichiers corrompus au
   milieu, hors de ce lot.
3. **JPEG avec données après l'EOI** : refusé (choix fermé). Un fichier réel qui ajoute une
   queue non nulle après `FFD9` serait rejeté ; à revoir si un tel fichier apparaît.
4. **Acceptation ImageIO de la fixture 1 bit** : le PNG compressé de 12 000 × 3 400 est valide
   pour `zlib` et Pillow, mais qu'ImageIO en lise les dimensions n'a pas été observé. Si le
   prochain run rend `unreadable` au lieu de `invalidDimensions`, la cause serait la fixture,
   pas la garde de 40 Mpx.
5. **Propriétés techniques EXIF** : ImageIO en recrée dans la miniature JPEG (constat Q4). Le
   contrat interdit désormais les **valeurs personnelles**, pas ces propriétés ; un futur
   durcissement (par exemple un ré-encodage sans EXIF du tout) demanderait un autre lot et une
   nouvelle mesure.
6. **Catégorie PDFKit pour un PDF verrouillé** : le test exige `lockedPDF` (donc
   `PDFDocument.isLocked == true`). Si PDFKit refusait de créer le document pour ce fichier
   chiffré AES-128, la primitive rendrait `unreadable` : le contrat « refusé sans demande de
   mot de passe » resterait tenu, mais le test devrait être ajusté et la catégorie consignée.
7. **Écriture de l'orientation EXIF et des marqueurs par les fixtures** : les tests vérifient
   d'abord que le JPEG de test porte bien `Orientation = 6`, l'appareil et la date ; un échec
   de ces préconditions désignerait la fixture, pas la primitive.
8. **Coût CPU borné mais réel** : jusqu'à 8 paliers de miniature pour une image JPEG, chaque
   palier ré-échantillonné par ImageIO, plus une lecture linéaire des octets pour la
   terminaison du conteneur. Le coût d'un média de 4 Mio n'est pas mesuré ; aucune promesse de
   durée n'est faite.
9. **Bornes non couvertes** : le nombre de pages PDF n'est pas limité ici (§3.2/§4.2 parlent
   de 50 pages *rendues*, décision du lot UI) ; un PDF valide de plusieurs centaines de pages
   est accepté. Les bombes de décompression sont couvertes par la borne de dimensions lue
   dans l'en-tête, pas par une mesure mémoire.
10. **Miniature et cache** : `MessagingMediaCache` n'existe pas dans cette base (autre worker).
    La compatibilité repose sur le contrat §3.10 (≤ 512 px, ≤ 128 Kio, JPEG/PNG en mémoire) ;
    le format exact attendu par ce cache — et le fait qu'il ré-encode — n'est pas vérifié ici.
11. **Pas de preuve instrumentale** d'absence d'écriture disque, de réseau ou de journal (§4).
12. Aucun parcours utilisateur n'est livré ni annoncé : pas d'écran, pas d'import, pas de
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

- `git rev-parse HEAD` → `7cb065a2a43b532cb800b81b2b907c7cc9e90499` au départ de cette
  correction ; `git status --porcelain` puis `git diff --stat` limités aux trois fichiers du
  périmètre.
- `Get-Command swift, swiftc, xcodebuild, xcrun, xcodegen` → **0 outil** : aucun test, aucune
  compilation, aucun simulateur, aucun RED/GREEN local.
- Diagnostic Apple relu dans `bristleworm/artifacts/q4-diagnostics-metier.json` (run
  `41962003316`, job `127030313656`, sha `62560a2e`) : cinq cas, six assertions, causes
  classées au §0.1.
- Indexation Codebase Memory de la racine du worktree, fraîcheur et couverture relues (§0) ;
  aucun index d'un autre worktree. Après correction : ré-indexation à `04:17:28Z`, parse sans
  erreur partiel sur les deux fichiers, `MessagingMediaPreparationContainer` extrait.
- Sources primaires Apple relues (`CGImageSourceGetStatusAtIndex` : statut utile surtout pour
  les sources incrémentales, aucune promesse de détection de troncature) et références de
  format (ITU-T T.81 pour EOI, W3C PNG 3e édition §4.8.2/§5.2 pour `IEND`).
- Miroirs Python **hors dépôt** (aucun artefact ajouté au dépôt) :
  - déflateur Huffman fixe de la fixture 40 Mpx : `zlib.decompress` rend exactement le flux
    attendu, Pillow lit l'image (12 000 × 3 400) et le fichier pèse **32 367 octets** ;
  - contrôle de terminaison : fichier complet accepté, moitié refusée, fichier privé de
    EOI/`IEND` refusé, remplissage nul après EOI toléré, octet parasite après `IEND` refusé,
    sur des fichiers produits par un encodeur réel ;
  - tailles de fixtures mesurées : bruit 1 200 × 900 JPEG q60 ≈ 0,5 Mio (sous 4 Mio), alors
    que 2 400 × 1 800 en qualité maximale — la fixture fautive — dépassait largement.
  Ces miroirs prouvent l'arithmétique des octets, **pas** le comportement d'ImageIO/PDFKit.
- Aucun fichier existant, UI, factory, coordinateur, outbox, cache, crypto, DTO, lock,
  projet, workflow, `STATUS.md` ni dossier de conception modifié.

## 9. Sources

- `AGENTS.md`, `Drivy_Conception_v3_17_2026-09-20/COMMENCER_ICI.md`
- `docs/implementation/medias-exploitation-contrat-20261104.md` §3.2, §3.10, §3.11, §3.12, §4.2, §4.5, §7.1
- `C:/Users/jtoma/orca/workspaces/Drivy/sealion/docs/implementation/orchestration-20261104/medias-arbitrages-coordinateur.md` (addendum : iOS 26, `PDFDocument(data:)` sans temporaire, pas de politique d'exploitation approuvée)
- `docs/implementation/messaging-media-97-content.md` (T2b1 : contenu v3), `messaging-media-97-transport.md` (T2b2), `messaging-media-97-crypto.md` (T2a)
- `apps/ios/Drivy/MessagingCore/MessagingMediaContent.swift` (constantes de `MessagingMediaAttachment`, `MessagingMediaName.sanitized`)
- Exécution Apple réellement rouge : `C:/Users/jtoma/orca/workspaces/Drivy/bristleworm/artifacts/q4-diagnostics-metier.json` (run `41962003316`, job `127030313656`, sha `62560a2e`) ; artefacts complets annoncés sous `integration-issues-20261105/artifacts/qualification-62560a2e`
- Apple : `CGImageSourceCreateThumbnailAtIndex`, `CGImageSourceGetStatusAtIndex`, `CGImageDestinationCreateWithData`, `PDFDocument.init?(data:)`, `PDFDocument.isLocked`, `UTType.jpeg`/`png`, clés `kCGImageProperty*` citées au §0
- Formats : ITU-T T.81 (EOI `0xFFD9`) ; W3C *Portable Network Graphics (PNG) Specification (Third Edition)*, REC-png-3-20250624, §4.8.2 et §5.2 (`IEND` dernier chunk)
