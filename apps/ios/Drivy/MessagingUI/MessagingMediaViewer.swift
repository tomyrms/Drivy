import ImageIO
import PDFKit
import SwiftUI
import UIKit

// MARK: - Géométrie du zoom (pure, testée)

/// Calculs de la visionneuse d'images, sans UIKit : le même code sert l'écran et les tests.
/// L'échelle 1 est toujours « ajustée au cadre » ; l'image zoomée vit dans un `UIScrollView`
/// dont l'échelle va de 1 à `maximumScale`.
enum MessagingZoomGeometry {
    static let minimumScale: CGFloat = 1
    /// Plancher du zoom maximal : une capture d'écran reste lisible même si ses pixels sont peu nombreux.
    static let minimumOfMaximumScale: CGFloat = 3
    static let absoluteMaximumScale: CGFloat = 8
    /// Agrandissement d'un double toucher quand l'image couvre déjà presque le cadre.
    static let doubleTapScale: CGFloat = 2.5
    /// Plus grand côté décodé, en pixels : borne la mémoire (4096 × 4096 × 4 octets ≈ 64 Mio).
    static let decodeCeiling: CGFloat = 4096
    static let decodeFloor: CGFloat = 512
    /// Tolérance pour dire « on est à l'échelle ajustée ».
    static let fitTolerance: CGFloat = 1.05

    /// Taille de l'image ajustée dans le cadre, proportions conservées, jamais déformée.
    static func fittedSize(content: CGSize, in viewport: CGSize) -> CGSize {
        guard content.width > 0, content.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let ratio = min(viewport.width / content.width, viewport.height / content.height)
        return CGSize(width: content.width * ratio, height: content.height * ratio)
    }

    /// Zoom maximal : deux fois l'échelle où un pixel de l'image égale un pixel de l'écran,
    /// encadré par [3, 8].
    static func maximumScale(pixelSize: CGSize, fitted: CGSize, displayScale: CGFloat) -> CGFloat {
        guard fitted.width > 0, displayScale > 0, pixelSize.width > 0 else { return minimumOfMaximumScale }
        let native = pixelSize.width / (fitted.width * displayScale)
        return min(absoluteMaximumScale, max(minimumOfMaximumScale, native * 2))
    }

    /// Cible d'un double toucher : retour à l'ajustement si déjà agrandi, sinon l'agrandissement
    /// qui remplit le cadre (au moins 2,5×), plafonné au zoom maximal.
    static func doubleTapTarget(current: CGFloat, minimum: CGFloat, maximum: CGFloat,
                                fitted: CGSize, viewport: CGSize) -> CGFloat {
        if current > minimum * fitTolerance { return minimum }
        var fill = doubleTapScale
        if fitted.width > 0, fitted.height > 0 {
            fill = max(fill, viewport.width / fitted.width, viewport.height / fitted.height)
        }
        return max(minimum, min(maximum, fill))
    }

    /// Rectangle, dans le repère de l'image ajustée (échelle 1), à rendre visible pour que
    /// `center` apparaisse au centre du cadre à l'échelle `scale`.
    static func zoomRect(center: CGPoint, scale: CGFloat, viewport: CGSize) -> CGRect {
        let scale = max(scale, minimumScale)
        let size = CGSize(width: viewport.width / scale, height: viewport.height / scale)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    /// Marge qui centre un contenu plus petit que le cadre ; nulle sur l'axe où il le dépasse.
    static func centeringInset(content: CGSize, bounds: CGSize) -> CGSize {
        CGSize(width: max(0, (bounds.width - content.width) / 2), height: max(0, (bounds.height - content.height) / 2))
    }

    /// Ramène un décalage dans les bornes de déplacement : jamais d'espace vide d'un côté tant que
    /// l'image dépasse le cadre, image centrée sinon.
    static func clampedOffset(_ offset: CGPoint, content: CGSize, bounds: CGSize) -> CGPoint {
        let inset = centeringInset(content: content, bounds: bounds)
        let minX = -inset.width, maxX = content.width - bounds.width + inset.width
        let minY = -inset.height, maxY = content.height - bounds.height + inset.height
        return CGPoint(x: min(max(offset.x, minX), max(minX, maxX)), y: min(max(offset.y, minY), max(minY, maxY)))
    }

    /// Plus grand côté à décoder : deux fois le cadre en pixels, jamais plus que la source ni 4096.
    static func decodeMaxPixel(sourceLongestSide: CGFloat, viewportLongestSide: CGFloat, displayScale: CGFloat) -> Int {
        let wanted = min(decodeCeiling, max(decodeFloor, (viewportLongestSide * max(displayScale, 1) * 2).rounded(.up)))
        guard sourceLongestSide > 0 else { return Int(wanted) }
        return Int(min(wanted, sourceLongestSide))
    }
}

// MARK: - Décodage ImageIO

/// Image déjà décodée à la bonne résolution. `CGImage` est immuable une fois créée.
struct MessagingDecodedImage: @unchecked Sendable {
    let cgImage: CGImage
    var pixelSize: CGSize { CGSize(width: cgImage.width, height: cgImage.height) }
}

enum MessagingImageDecoder {
    /// Un seul décodage, orientation appliquée, sous-échantillonné ; à appeler hors du thread principal.
    nonisolated static func decode(_ data: Data, viewportLongestSide: CGFloat, displayScale: CGFloat) -> MessagingDecodedImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions), CGImageSourceGetCount(source) > 0 else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let maxPixel = MessagingZoomGeometry.decodeMaxPixel(sourceLongestSide: CGFloat(max(width, height)),
                                                            viewportLongestSide: viewportLongestSide, displayScale: displayScale)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return MessagingDecodedImage(cgImage: image)
    }
}

// MARK: - Interface d'état (consommée par #476)

/// Ce que la visionneuse affiche. `ready` porte le média déjà vérifié et déchiffré en mémoire ;
/// `failed` porte un message français court, sans nom de fichier ni détail technique.
enum MessagingMediaViewerState: Equatable {
    case loading
    case ready(MessagingPreparedMedia)
    case failed(String)
}

/// Surface plein écran : barre « Fermer » à gauche + nom, puis photo zoomable ou lecteur PDF.
/// `retry` n'apparaît (« Réessayer ») que pour l'état `failed` et seulement s'il est fourni.
struct MessagingMediaViewer: View {
    let state: MessagingMediaViewerState
    let title: String
    var retry: (() -> Void)?
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MessagingViewerBar(title: title, close: close)
            content
        }
        .background(DrivyTheme.canvas.ignoresSafeArea())
        .tint(DrivyTheme.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messaging.media.preview")
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            ProgressView("Ouverture…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            MessagingViewerUnavailable(message: message, retry: retry)
        case .ready(let media):
            if media.mime == .pdf {
                MessagingPDFReader(data: media.data)
            } else {
                MessagingImageViewerSurface(media: media)
            }
        }
    }
}

/// Aperçu d'un média déjà prêt : l'état « prêt » existant, branché tel quel par la conversation.
struct MessagingMediaPreview: View {
    let media: MessagingPreparedMedia
    let close: () -> Void

    var body: some View {
        MessagingMediaViewer(state: .ready(media), title: media.name, retry: nil, close: close)
    }
}

private struct MessagingViewerBar: View {
    let title: String
    let close: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let large = typeSize.isAccessibilitySize
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xxs)) : AnyLayout(HStackLayout(spacing: DrivySpacing.s))
        layout {
            Button("Fermer", action: close)
                .font(.body.weight(.semibold))
                .foregroundStyle(DrivyTheme.accent)
                .frame(minWidth: DrivyLayout.tapTarget, minHeight: DrivyLayout.tapTarget, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityIdentifier("messaging.media.close")
            Text(title)
                .font(.headline)
                .foregroundStyle(DrivyTheme.text)
                .lineLimit(large ? 3 : 1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: large ? .leading : .trailing)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, DrivySpacing.m)
        .padding(.vertical, DrivySpacing.xxs)
        .background(DrivyTheme.canvas)
    }
}

private struct MessagingViewerUnavailable: View {
    let message: String?
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: DrivySpacing.m) {
            ContentUnavailableView("Aperçu indisponible", systemImage: "doc", description: message.map { Text($0) })
            if let retry {
                Button("Réessayer", action: retry)
                    .buttonStyle(.bordered)
                    .frame(minHeight: DrivyLayout.tapTarget)
                    .accessibilityIdentifier("messaging.media.retry-open")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Photo

private struct MessagingImageViewerSurface: View {
    let media: MessagingPreparedMedia
    @Environment(\.displayScale) private var displayScale
    @State private var phase: Phase = .decoding

    private enum Phase {
        case decoding
        case ready(MessagingDecodedImage)
        case failed
    }

    var body: some View {
        GeometryReader { proxy in
            let longest = max(proxy.size.width, proxy.size.height)
            Group {
                switch phase {
                case .decoding:
                    ProgressView("Ouverture…")
                case .ready(let decoded):
                    MessagingZoomableImage(image: decoded.cgImage, pixelSize: decoded.pixelSize,
                                           displayScale: displayScale, name: media.name)
                case .failed:
                    MessagingViewerUnavailable(message: nil, retry: nil)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // Une seule fois, hors du calcul de `body` et hors du thread principal.
            .task(id: longest > 0) {
                guard longest > 0, case .decoding = phase else { return }
                let data = media.data, scale = displayScale
                let decoded = await Task.detached(priority: .userInitiated) {
                    MessagingImageDecoder.decode(data, viewportLongestSide: longest, displayScale: scale)
                }.value
                guard !Task.isCancelled else { return }
                phase = decoded.map(Phase.ready) ?? .failed
            }
        }
    }
}

private struct MessagingZoomableImage: UIViewRepresentable {
    let image: CGImage
    let pixelSize: CGSize
    let displayScale: CGFloat
    let name: String

    func makeUIView(context: Context) -> MessagingZoomScrollView {
        MessagingZoomScrollView(image: UIImage(cgImage: image, scale: 1, orientation: .up),
                                pixelSize: pixelSize, displayScale: displayScale, name: name)
    }

    func updateUIView(_ view: MessagingZoomScrollView, context: Context) {}

    static func dismantleUIView(_ view: MessagingZoomScrollView, coordinator: Void) {
        view.release()
    }
}

/// `UIScrollView` à image unique : pincement natif, double toucher centré sur le point touché,
/// image centrée tant qu'elle est plus petite que le cadre, réajustement à chaque changement de taille.
private final class MessagingZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    private let pixelSize: CGSize
    private let displayPixelScale: CGFloat
    private var laidOutSize: CGSize = .zero

    init(image: UIImage, pixelSize: CGSize, displayScale: CGFloat, name: String) {
        imageView = UIImageView(image: image)
        self.pixelSize = pixelSize
        displayPixelScale = displayScale
        super.init(frame: .zero)
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = true
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = name
        imageView.accessibilityTraits = .image
        imageView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Agrandir", target: self, selector: #selector(zoomInFromAccessibility)),
            UIAccessibilityCustomAction(name: "Réduire", target: self, selector: #selector(zoomOutFromAccessibility))
        ]
        addSubview(imageView)
        delegate = self
        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas pris en charge") }

    func release() {
        delegate = nil
        imageView.image = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize, bounds.width > 0, bounds.height > 0 else { return }
        laidOutSize = bounds.size
        refit()
    }

    /// Rotation ou redimensionnement iPad : retour propre à l'image ajustée au nouveau cadre.
    private func refit() {
        zoomScale = MessagingZoomGeometry.minimumScale
        let fitted = MessagingZoomGeometry.fittedSize(content: imageView.image?.size ?? .zero, in: bounds.size)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
        minimumZoomScale = MessagingZoomGeometry.minimumScale
        maximumZoomScale = MessagingZoomGeometry.maximumScale(pixelSize: pixelSize, fitted: fitted, displayScale: displayPixelScale)
        centerContent()
        contentOffset = MessagingZoomGeometry.clampedOffset(.zero, content: contentSize, bounds: bounds.size)
    }

    private func centerContent() {
        let inset = MessagingZoomGeometry.centeringInset(content: contentSize, bounds: bounds.size)
        let insets = UIEdgeInsets(top: inset.height, left: inset.width, bottom: inset.height, right: inset.width)
        if contentInset != insets { contentInset = insets }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    private var animatesZoom: Bool { !UIAccessibility.isReduceMotionEnabled }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        let target = MessagingZoomGeometry.doubleTapTarget(current: zoomScale, minimum: minimumZoomScale, maximum: maximumZoomScale,
                                                           fitted: imageView.bounds.size, viewport: bounds.size)
        if target <= minimumZoomScale * MessagingZoomGeometry.fitTolerance {
            setZoomScale(minimumZoomScale, animated: animatesZoom)
        } else {
            let center = recognizer.location(in: imageView)
            zoom(to: MessagingZoomGeometry.zoomRect(center: center, scale: target, viewport: bounds.size), animated: animatesZoom)
        }
    }

    @objc private func zoomInFromAccessibility() -> Bool {
        let target = min(maximumZoomScale, max(zoomScale * 2, MessagingZoomGeometry.doubleTapScale))
        let center = CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
        zoom(to: MessagingZoomGeometry.zoomRect(center: center, scale: target, viewport: bounds.size), animated: animatesZoom)
        return true
    }

    @objc private func zoomOutFromAccessibility() -> Bool {
        setZoomScale(minimumZoomScale, animated: animatesZoom)
        return true
    }
}

// MARK: - PDF

/// Repère de page, hors de l'arbre d'observation de PDFKit.
@MainActor @Observable private final class MessagingPDFPageState {
    var page = 1
    var count = 0
    @ObservationIgnored weak var view: PDFView?

    func refresh() {
        guard let view, let document = view.document else { return }
        count = document.pageCount
        if let current = view.currentPage { page = document.index(for: current) + 1 }
    }
}

/// PDFKit sur des octets en mémoire : aucun fichier déchiffré, aucune action externe.
private struct MessagingPDFReader: View {
    let data: Data
    @State private var document: PDFDocument?
    @State private var loaded = false
    @State private var pages = MessagingPDFPageState()

    var body: some View {
        Group {
            if let document {
                MessagingMemoryPDF(document: document, state: pages)
                    .overlay(alignment: .bottom) { pageIndicator }
                    .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { _ in pages.refresh() }
            } else if loaded {
                MessagingViewerUnavailable(message: nil, retry: nil)
            } else {
                ProgressView("Ouverture…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !loaded else { return }
            let opened = PDFDocument(data: data)
            document = opened
            loaded = true
            // Le PDFView n'existe pas encore (il naît au rendu qui suit) : `refresh()` ne trouverait pas `view` et le
            // nombre de pages resterait à 0 jusqu'au premier changement de page (run UI 43287772177, iPhone : repère absent).
            pages.count = opened?.pageCount ?? 0
            pages.refresh()
        }
    }

    @ViewBuilder private var pageIndicator: some View {
        if pages.count > 1 {
            Text("Page \(pages.page) sur \(pages.count)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(DrivyTheme.text)
                .padding(.horizontal, DrivySpacing.s)
                .padding(.vertical, DrivySpacing.xxs)
                .background(DrivyTheme.surfaceRaised, in: Capsule())
                .overlay(Capsule().stroke(DrivyTheme.border))
                .padding(.bottom, DrivySpacing.s)
                .accessibilityIdentifier("messaging.media.page")
        }
    }
}

/// PDFKit lit les octets en mémoire et ne rend que les pages du cadre.
/// La surcharge d'action et le délégué suppriment tous deux les actions externes du document.
private struct MessagingMemoryPDF: UIViewRepresentable {
    let document: PDFDocument
    let state: MessagingPDFPageState

    func makeUIView(context: Context) -> MessagingReadOnlyPDFView {
        let view = MessagingReadOnlyPDFView()
        view.delegate = context.coordinator
        view.autoScales = true
        view.maxScaleFactor = 4
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(DrivyTheme.canvas)
        view.document = document
        state.view = view
        return view
    }

    func updateUIView(_ view: MessagingReadOnlyPDFView, context: Context) {}

    static func dismantleUIView(_ view: MessagingReadOnlyPDFView, coordinator: Coordinator) {
        view.document = nil
        view.delegate = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, PDFViewDelegate {
        func pdfViewWillClick(onLink sender: PDFView, with url: URL) {}
        func pdfViewOpenPDF(_ sender: PDFView, forRemoteGoToAction action: PDFActionRemoteGoTo) {}
        func pdfViewPerformPrint(_ sender: PDFView) {}
    }
}

private final class MessagingReadOnlyPDFView: PDFView {
    override func perform(_ action: PDFAction) {
        // No implicit links, remote documents, launches, scripts or form actions.
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Le dézoom s'arrête à la page entière.
        guard document != nil else { return }
        let fit = scaleFactorForSizeToFit
        if fit > 0, abs(minScaleFactor - fit) > 0.001 { minScaleFactor = fit }
    }
}
