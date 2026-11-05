import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Média local prêt pour le sceau (#97, T2b6).
///
/// Valeur pure : des octets, un type, un nom d'affichage assaini, des dimensions
/// facultatives et une miniature locale. Aucun identifiant de média, aucune clé, aucun
/// objet de rendu : `mediaID` et la clé de fichier sont créés **une seule fois** par le
/// sceau du futur coordinateur, jamais ici.
///
/// `data` porte l'original **octet pour octet**. Ce lot ne retouche ni les pixels, ni les
/// pages, ni les métadonnées déjà présentes dans le fichier : il ne supprime donc pas les
/// EXIF/GPS ni les métadonnées PDF, et ne le prétend pas. Le contenu complet est chiffré
/// par la primitive de T2a. `thumbnail` est une image locale, jamais destinée au serveur.
struct MessagingPreparedMedia: Sendable, Equatable {
    /// Original clair, conservé tel quel en mémoire.
    let data: Data
    /// Type réel, lu par le parseur système et conforme à la liste du produit.
    let mime: MessagingMediaAttachment.MIME
    /// Nom d'affichage assaini et borné : jamais un chemin, jamais une clé d'accès.
    let name: String
    /// Dimensions d'affichage d'une image ; `nil` pour un PDF.
    let width: Int?
    let height: Int?
    /// Miniature JPEG ou PNG produite localement (≤ 512 px par axe, ≤ 128 Kio) ; `nil` pour
    /// un PDF, dont l'aperçu complet est rendu par le lot UI depuis `data`.
    let thumbnail: Data?
}

/// Préparation locale d'un média (#97). Un seul point d'entrée : des octets et un nom
/// suggéré. Aucune URL, aucun chemin, aucun fournisseur distant : l'import système
/// (`PhotosPicker`, `fileImporter`) appartient au lot UI.
protocol MessagingMediaPreparing: Sendable {
    /// Rend un média prêt à sceller, ou refuse par une catégorie fermée.
    ///
    /// **Synchrone à dessein.** Les décodeurs ImageIO et PDFKit sont des appels natifs
    /// bloquants : marquer cette fonction `async` ne rendrait pas l'attente interruptible et
    /// promettrait une annulation instantanée qui n'existe pas. Le futur coordinateur
    /// l'appelle donc **hors MainActor** (tâche détachée ou acteur de fond), jamais sur le
    /// fil de l'interface : aucune opération d'image n'est imposée au rendu. L'annulation
    /// Swift ne s'applique qu'aux frontières — avant l'appel, entre deux médias — pas au
    /// milieu d'un décodage système.
    func prepare(_ data: Data, suggestedName: String) throws -> MessagingPreparedMedia
}

/// Refus de préparation (#97, T2b6) : catégories fermées, sans texte libre, sans chemin,
/// sans identifiant ni contenu, et sans `LocalizedError` — le mapping de présentation
/// appartient au lot UI.
enum MessagingMediaPreparationFailure: Error, Equatable, Sendable {
    /// Octets hors de la borne produit 1…4 Mio, vérifiée avant tout parseur.
    case invalidSize
    /// Nom suggéré inutilisable après assainissement : vide ou entièrement composé de
    /// caractères de commande, de direction ou de séparation de chemin.
    case invalidName
    /// Nature réelle non acceptée par cette primitive initiale (JPEG, PNG et PDF seulement :
    /// HEIC, GIF, SVG et tout autre format sont refusés, sans conversion silencieuse).
    case invalidFormat
    /// Dimensions absentes, nulles ou hors des bornes du produit (12 000 px par axe,
    /// 40 millions de pixels), refusées avant toute allocation de bitmap.
    case invalidDimensions
    /// Contenu reconnu mais inexploitable : image tronquée ou illisible, PDF sans page
    /// exploitable, document impossible à ouvrir.
    case unreadable
    /// PDF chiffré exigeant un mot de passe : refusé, sans demande de mot de passe ici.
    case lockedPDF
    /// Aucune miniature n'a pu être produite dans les bornes (512 px, 128 Kio). L'échec est
    /// explicite : aucun succès n'est rendu avec des données hors contrat.
    case thumbnailUnavailable
}

/// Implémentation unique de la préparation locale (#97, T2b6).
///
/// Aucune écriture disque, aucun temporaire, aucun réseau : l'original reste en mémoire,
/// ImageIO écrit la miniature dans un tampon mémoire et PDFKit lit les octets en mémoire.
/// Ce lot ne journalise rien : ni octet, ni nom, ni dimension, ni erreur libre.
struct MessagingMediaPreparer: MessagingMediaPreparing {
    /// Axe maximal de la miniature locale (contrat §3.10, cache média).
    static let maximumThumbnailAxis = 512
    /// Plafond de la miniature locale (contrat §3.10, cache média).
    static let maximumThumbnailByteSize = 131_072

    func prepare(_ data: Data, suggestedName: String) throws -> MessagingPreparedMedia {
        // 1. Borne de taille avant les parseurs : rien n'est décodé hors du contrat.
        guard (MessagingMediaAttachment.minimumByteSize...MessagingMediaAttachment.maximumByteSize)
            .contains(data.count) else {
            throw MessagingMediaPreparationFailure.invalidSize
        }
        // 2. Nom d'affichage : assaini et borné par la règle existante, jamais utilisé comme chemin.
        guard let name = MessagingMediaName.sanitized(suggestedName) else {
            throw MessagingMediaPreparationFailure.invalidName
        }
        // 3. Nature réelle par les octets ; l'extension et le type déclaré n'ont aucun poids.
        guard let format = MessagingMediaPreparationFormat.detect(data) else {
            throw MessagingMediaPreparationFailure.invalidFormat
        }
        switch format {
        case .jpeg:
            return try MessagingMediaPreparationImage.read(data, mime: .jpeg, expected: .jpeg, name: name)
        case .png:
            return try MessagingMediaPreparationImage.read(data, mime: .png, expected: .png, name: name)
        case .pdf:
            return try MessagingMediaPreparationPDF.read(data, name: name)
        }
    }
}

/// Nature détectée par les signatures d'octets. Ce n'est qu'un aiguillage : ImageIO et
/// PDFKit restent les parseurs qui confirment le type et l'exploitabilité.
private enum MessagingMediaPreparationFormat {
    case jpeg
    case png
    case pdf

    static func detect(_ data: Data) -> MessagingMediaPreparationFormat? {
        let prefix = [UInt8](data.prefix(8))
        if prefix.count >= 3, prefix[0] == 0xFF, prefix[1] == 0xD8, prefix[2] == 0xFF {
            return .jpeg
        }
        if prefix.count >= 8, prefix[0] == 0x89, prefix[1] == 0x50, prefix[2] == 0x4E, prefix[3] == 0x47,
           prefix[4] == 0x0D, prefix[5] == 0x0A, prefix[6] == 0x1A, prefix[7] == 0x0A {
            return .png
        }
        let header = [UInt8]("%PDF-".utf8)
        if prefix.count >= header.count, Array(prefix[0..<header.count]) == header {
            return .pdf
        }
        return nil
    }
}

/// Terminaison du conteneur (#97, T2b6) : lecture bornée des octets, sans décodage, sans
/// allocation de bitmap, sans fichier ni réseau.
///
/// Justification mesurée : `CGImageSourceGetStatusAtIndex` ne prouve rien sur un fichier
/// coupé — l'exécution Apple du 5 novembre 2026 (run 41962003316 / job 127030313656) a
/// accepté un JPEG et un PNG réduits à la moitié de leurs octets alors que le statut valait
/// `.statusComplete`. Ce contrôle lit donc la structure minimale que tout fichier complet
/// porte :
/// - JPEG : le marqueur EOI (`0xFFD9`, ITU-T T.81) termine le fichier, un remplissage nul
///   final étant toléré ;
/// - PNG : la marche des chunks atteint `IEND` et rien ne le suit (W3C PNG 3e édition,
///   §4.8.2 et §5.2 : le flux commence par `IHDR` et se termine par `IEND`).
///
/// Ce que ce contrôle ne prouve pas : il atteste la **terminaison** du conteneur, pas
/// l'intégrité des pixels ni celle des CRC. Une corruption interne laissant EOI/IEND intacts
/// peut encore produire une miniature partiellement grise ; la seule preuve exhaustive serait
/// un décodage pleine résolution, refusé par construction (aucun bitmap de 40 Mpx alloué).
private enum MessagingMediaPreparationContainer {
    /// `IEND` comparé sur ses quatre octets ASCII.
    private static let endChunk: UInt32 = 0x4945_4E44

    static func isTerminated(_ data: Data, mime: MessagingMediaAttachment.MIME) -> Bool {
        switch mime {
        case .jpeg:
            return endsWithEndOfImage(data)
        case .png:
            return endsWithEndChunk(data)
        case .pdf:
            return true
        }
    }

    /// EOI en fin de fichier. Les zéros de remplissage finaux sont tolérés ; toute autre
    /// donnée après l'EOI fait refuser le fichier (choix fermé, documenté dans le rapport).
    private static func endsWithEndOfImage(_ data: Data) -> Bool {
        let base = data.startIndex
        var end = data.count
        while end > 0, data[base + end - 1] == 0x00 {
            end -= 1
        }
        guard end >= 2 else { return false }
        return data[base + end - 2] == 0xFF && data[base + end - 1] == 0xD9
    }

    /// Marche des chunks : chaque longueur annoncée doit tenir dans les octets reçus, et le
    /// dernier chunk doit être `IEND` exactement en fin de tampon. Aucune allocation.
    private static func endsWithEndChunk(_ data: Data) -> Bool {
        let base = data.startIndex
        var offset = 8   // signature PNG
        while offset <= data.count - 8 {
            let length = Int(readUInt32(data, at: base + offset))
            let chunkEnd = offset + length + 12
            guard chunkEnd >= offset, chunkEnd <= data.count else { return false }
            if readUInt32(data, at: base + offset + 4) == endChunk {
                return chunkEnd == data.count
            }
            offset = chunkEnd
        }
        return false
    }

    private static func readUInt32(_ data: Data, at index: Data.Index) -> UInt32 {
        (UInt32(data[index]) << 24) | (UInt32(data[index + 1]) << 16)
            | (UInt32(data[index + 2]) << 8) | UInt32(data[index + 3])
    }
}

/// Images : dimensions lues dans l'en-tête, puis miniature produite par sous-échantillonnage
/// borné d'ImageIO. Le bitmap pleine résolution n'est jamais alloué pour la miniature.
private enum MessagingMediaPreparationImage {
    static func read(_ data: Data, mime: MessagingMediaAttachment.MIME, expected: UTType,
                     name: String) throws -> MessagingPreparedMedia {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw MessagingMediaPreparationFailure.unreadable
        }
        guard CGImageSourceGetCount(source) >= 1 else {
            throw MessagingMediaPreparationFailure.unreadable
        }
        // Le type du conteneur doit être celui annoncé par les octets, jamais celui du nom.
        guard let containerType = CGImageSourceGetType(source) else {
            throw MessagingMediaPreparationFailure.unreadable
        }
        guard (containerType as String) == expected.identifier else {
            throw MessagingMediaPreparationFailure.invalidFormat
        }
        // Terminaison du conteneur, avant toute lecture de dimensions : un fichier coupé
        // n'est jamais une image exploitable, même si le décodeur remplirait le manque.
        guard MessagingMediaPreparationContainer.isTerminated(data, mime: mime) else {
            throw MessagingMediaPreparationFailure.unreadable
        }
        // Dimensions et orientation avant toute création de bitmap.
        guard let rawProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) else {
            throw MessagingMediaPreparationFailure.unreadable
        }
        let properties = rawProperties as NSDictionary
        guard let pixelWidth = (properties.object(forKey: kCGImagePropertyPixelWidth) as? NSNumber)?.intValue,
              let pixelHeight = (properties.object(forKey: kCGImagePropertyPixelHeight) as? NSNumber)?.intValue else {
            throw MessagingMediaPreparationFailure.invalidDimensions
        }
        let orientation = (properties.object(forKey: kCGImagePropertyOrientation) as? NSNumber)?.intValue ?? 1
        guard (1...8).contains(orientation) else {
            throw MessagingMediaPreparationFailure.invalidDimensions
        }
        try validateDimensions(pixelWidth, pixelHeight)
        let hasAlpha = (properties.object(forKey: kCGImagePropertyHasAlpha) as? NSNumber)?.boolValue ?? false
        // Fichier tronqué ou inexploitable : refusé avant la miniature.
        guard CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
            throw MessagingMediaPreparationFailure.unreadable
        }
        let display = displaySize(pixelWidth, pixelHeight, orientation: orientation)
        guard let thumbnail = thumbnailData(source, hasAlpha: hasAlpha) else {
            throw MessagingMediaPreparationFailure.thumbnailUnavailable
        }
        return MessagingPreparedMedia(data: data, mime: mime, name: name,
                                      width: display.width, height: display.height, thumbnail: thumbnail)
    }

    /// Bornes du produit, arithmétique sans débordement.
    private static func validateDimensions(_ width: Int, _ height: Int) throws {
        let axis = MessagingMediaAttachment.maximumPixelsPerAxis
        guard width >= 1, height >= 1, width <= axis, height <= axis else {
            throw MessagingMediaPreparationFailure.invalidDimensions
        }
        let pixels = width.multipliedReportingOverflow(by: height)
        guard !pixels.overflow, pixels.partialValue <= MessagingMediaAttachment.maximumPixels else {
            throw MessagingMediaPreparationFailure.invalidDimensions
        }
    }

    /// Dimensions cohérentes avec l'orientation de rendu : les orientations 5 à 8 tournent
    /// d'un quart de tour, la largeur et la hauteur affichées sont échangées.
    private static func displaySize(_ width: Int, _ height: Int,
                                    orientation: Int) -> (width: Int, height: Int) {
        switch orientation {
        case 5, 6, 7, 8:
            return (height, width)
        default:
            return (width, height)
        }
    }

    /// Stratégie bornée : une liste finie de paliers (taille, qualité), jamais une boucle
    /// ouverte. Le PNG conserve la transparence ; le JPEG est produit opaque. Si aucun
    /// palier ne tient sous 128 Kio, l'appelant rend un échec explicite.
    private static func thumbnailData(_ source: CGImageSource, hasAlpha: Bool) -> Data? {
        let steps: [(axis: Int, quality: Double?)] = hasAlpha
            ? [(512, nil), (384, nil), (256, nil), (192, nil), (128, nil)]
            : [(512, 0.8), (512, 0.6), (512, 0.45), (384, 0.6), (384, 0.45),
               (256, 0.6), (192, 0.5), (128, 0.5)]
        for step in steps {
            let axis = min(step.axis, MessagingMediaPreparer.maximumThumbnailAxis)
            guard let image = downsampled(source, maximumAxis: axis) else { return nil }
            guard let encoded = encode(image, hasAlpha: hasAlpha, quality: step.quality) else { continue }
            if encoded.count <= MessagingMediaPreparer.maximumThumbnailByteSize {
                return encoded
            }
        }
        return nil
    }

    /// Sous-échantillonnage ImageIO borné : jamais le bitmap pleine résolution, et la
    /// transformation d'orientation est appliquée par le décodeur.
    private static func downsampled(_ source: CGImageSource, maximumAxis: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumAxis
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Ré-encodage depuis les pixels de la miniature, **sans dictionnaire de propriétés** :
    /// aucune métadonnée de l'original (EXIF, GPS, TIFF) n'est recopiée, et rien n'est écrit
    /// sur disque — la destination écrit dans un tampon mémoire.
    private static func encode(_ image: CGImage, hasAlpha: Bool, quality: Double?) -> Data? {
        let type = hasAlpha ? UTType.png.identifier : UTType.jpeg.identifier
        guard let buffer = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(buffer, type as CFString, 1, nil) else {
            return nil
        }
        if let quality {
            let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
            CGImageDestinationAddImage(destination, image, options as CFDictionary)
        } else {
            CGImageDestinationAddImage(destination, image, nil)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        // Copie explicite du tampon : aucune conversion de pont implicite, aucun fichier.
        guard let bytes = CFDataGetBytePtr(buffer) else { return nil }
        return Data(bytes: bytes, count: CFDataGetLength(buffer))
    }
}

/// PDF : lecture en mémoire, sans fichier temporaire clair, sans lien, action, analyse
/// externe ni réseau. L'acceptation du parseur n'est pas une certification de sécurité du
/// document : le contenu complet sera chiffré par T2a et rendu par le lot UI.
private enum MessagingMediaPreparationPDF {
    static func read(_ data: Data, name: String) throws -> MessagingPreparedMedia {
        guard let document = PDFDocument(data: data) else {
            throw MessagingMediaPreparationFailure.unreadable
        }
        guard !document.isLocked else {
            throw MessagingMediaPreparationFailure.lockedPDF
        }
        guard document.pageCount >= 1, document.page(at: 0) != nil else {
            throw MessagingMediaPreparationFailure.unreadable
        }
        return MessagingPreparedMedia(data: data, mime: .pdf, name: name,
                                      width: nil, height: nil, thumbnail: nil)
    }
}
