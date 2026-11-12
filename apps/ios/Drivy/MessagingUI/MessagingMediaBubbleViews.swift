import SwiftUI

/// Règles de géométrie des pièces jointes du fil (#473).
///
/// L'espace d'une image est **réservé** avant l'arrivée de la miniature, à partir des seules
/// dimensions du contenu chiffré (`width`/`height` de `MessagingMediaAttachment`) : aucune
/// métadonnée publique, aucun déplacement du fil quand la miniature arrive.
///
/// - Largeur maximale 260 pt, hauteur maximale 340 pt ; le plus contraignant l'emporte et le
///   ratio est conservé (la bulle se rétrécit si la colonne est plus étroite que 260 pt).
/// - Portrait, paysage et carré gardent leur ratio réel, sans recadrage.
/// - **Capture longue** (largeur/hauteur < 0,6) : la zone est bornée à 0,6, l'image est
///   recadrée sans déformation et alignée en haut (le début de la capture reste visible).
/// - **Image très large** (largeur/hauteur > 2) : zone bornée à 2, recadrage centré.
/// - Dimensions absentes ou nulles : ratio 4:3 de repli, jamais une zone vide.
/// - **Transparence** : la miniature est posée sur le fond de surface de la bulle.
enum MessagingMediaBubbleGeometry {
    static let maximumWidth: CGFloat = 260
    static let maximumHeight: CGFloat = 340
    static let narrowestRatio: CGFloat = 0.6
    static let widestRatio: CGFloat = 2
    static let fallbackRatio: CGFloat = 4.0 / 3.0

    enum Crop: Equatable, Sendable {
        case none
        /// Capture longue : on garde le haut.
        case top
        /// Image très large : on garde le centre.
        case center
    }

    struct Plan: Equatable, Sendable {
        /// Largeur / hauteur de la zone réservée.
        let ratio: CGFloat
        let crop: Crop
    }

    static func plan(width: Int?, height: Int?) -> Plan {
        guard let width, let height, width > 0, height > 0 else {
            return Plan(ratio: fallbackRatio, crop: .none)
        }
        let ratio = CGFloat(width) / CGFloat(height)
        if ratio < narrowestRatio { return Plan(ratio: narrowestRatio, crop: .top) }
        if ratio > widestRatio { return Plan(ratio: widestRatio, crop: .center) }
        return Plan(ratio: ratio, crop: .none)
    }

    /// Taille réservée pour une largeur disponible (`nil` ou non finie : largeur maximale).
    static func reservedSize(_ plan: Plan, availableWidth: CGFloat?) -> CGSize {
        var width = maximumWidth
        if let availableWidth, availableWidth.isFinite, availableWidth > 0 {
            width = min(width, availableWidth)
        }
        var height = width / plan.ratio
        if height > maximumHeight {
            height = maximumHeight
            width = height * plan.ratio
        }
        return CGSize(width: width, height: height)
    }
}

/// Dispose son unique enfant dans la zone réservée par `MessagingMediaBubbleGeometry`.
struct MessagingMediaBubbleLayout: Layout {
    let plan: MessagingMediaBubbleGeometry.Plan

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        MessagingMediaBubbleGeometry.reservedSize(plan, availableWidth: proposal.width)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}

/// Ce que la bulle image montre. Valeur pure : les previews et le fil la fabriquent de la même façon.
enum MessagingImageBubblePresentation {
    case loading
    case image(UIImage)
    /// `canRetry` : une reprise ciblée a un sens (échec transitoire).
    case unavailable(canRetry: Bool)
}

/// Bulle image du fil (#473) : miniature dans une zone réservée, états d'attente et d'indisponibilité
/// explicites, toucher = ouverture. Les métadonnées (auteur, heure, état) restent hors de l'image.
struct MessagingImageBubble: View {
    let name: String
    let plan: MessagingMediaBubbleGeometry.Plan
    let presentation: MessagingImageBubblePresentation
    var isDisabled = false
    let open: () -> Void
    var retry: (() -> Void)?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous)
    }

    private var canRetry: Bool {
        if case .unavailable(let canRetry) = presentation { return canRetry && retry != nil }
        return false
    }

    var body: some View {
        MessagingMediaBubbleLayout(plan: plan) {
            ZStack(alignment: .bottom) {
                Button(action: open) {
                    ZStack {
                        DrivyTheme.surfaceCard
                        content
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(DrivyTheme.border, lineWidth: 1))
                    .contentShape(shape)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .accessibilityLabel(Self.accessibilityLabel(name: name))
                .accessibilityValue(Self.accessibilityValue(presentation))
                .accessibilityHint("Ouvre la pièce jointe")
                .accessibilityIdentifier("messaging.media.received.open")
                if canRetry, let retry {
                    Button(action: retry) {
                        Label("Réessayer", systemImage: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, DrivySpacing.s)
                            .frame(minHeight: DrivyLayout.tapTarget)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DrivyTheme.accent)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityLabel(MessagingMediaActionText.thumbnailRetry)
                    .accessibilityIdentifier("messaging.media.thumbnail.retry")
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch presentation {
        case .loading:
            ProgressView()
                .tint(DrivyTheme.muted)
                .accessibilityHidden(true)
        case .image(let image):
            Color.clear
                .overlay(alignment: plan.crop == .top ? .top : .center) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                .clipped()
                .accessibilityHidden(true)
        case .unavailable:
            VStack(spacing: DrivySpacing.xxs) {
                Image(systemName: "photo").font(.title2)
                Text("Aperçu indisponible").font(.caption)
            }
            .foregroundStyle(DrivyTheme.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DrivySpacing.s)
            .padding(.bottom, canRetry ? DrivyLayout.tapTarget : 0)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityHidden(true)
        }
    }

    static func accessibilityLabel(name: String) -> String { "Photo, \(name)" }

    static func accessibilityValue(_ presentation: MessagingImageBubblePresentation) -> String {
        switch presentation {
        case .loading: "Chargement"
        case .image: ""
        case .unavailable: "Aperçu indisponible"
        }
    }
}

/// Carte d'un document PDF (#473) : icône et type, nom sur plusieurs lignes, taille, cible d'ouverture
/// d'au moins 44 pt. Aucune vignette de première page.
struct MessagingPDFCard: View {
    let name: String
    let byteSize: Int
    let mine: Bool
    var isDisabled = false
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 40

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous)
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: DrivySpacing.s) {
                Image(systemName: "doc.richtext")
                    .font(.title3)
                    .foregroundStyle(DrivyTheme.accent)
                    .frame(width: iconSide, height: iconSide)
                    .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DrivyTheme.text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(typeSize.isAccessibilitySize ? 8 : 3)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.detail(byteSize: byteSize))
                        .font(.caption)
                        .foregroundStyle(DrivyTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DrivySpacing.s)
            .frame(maxWidth: MessagingMediaBubbleGeometry.maximumWidth, minHeight: DrivyLayout.tapTarget, alignment: .leading)
            .background(mine ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted, in: shape)
            .overlay(shape.strokeBorder(DrivyTheme.border, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(name: name, byteSize: byteSize))
        .accessibilityHint("Ouvre la pièce jointe")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("messaging.media.received.open")
    }

    static func detail(byteSize: Int) -> String {
        "PDF · " + ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }

    static func accessibilityLabel(name: String, byteSize: Int) -> String {
        "Document PDF, \(name), " + ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }
}

/// Pièce jointe d'une ligne du fil : image (miniature chargée à l'apparition) ou carte PDF.
/// Le toucher passe toujours par `thread.openMedia`.
struct MessagingThreadMediaAttachmentView: View {
    let thread: MessagingThreadModel
    let wire: MessagingWireMessage
    let media: MessagingMediaAttachment
    let mine: Bool

    /// Seule CETTE pièce est désactivée pendant son ouverture (#476) : les autres restent touchables.
    private var isDisabled: Bool {
        thread.reporting || thread.mediaComposer?.isOpening(wire.id) == true
    }

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: DrivySpacing.xxs) {
            attachment
            openStatus
        }
    }

    /// Ouverture en cours ou en échec, au bon média ; la reprise relance cette ouverture et aucune autre action.
    @ViewBuilder private var openStatus: some View {
        switch thread.mediaComposer?.openState(for: wire.id) {
        case .opening?:
            HStack(spacing: DrivySpacing.xs) {
                ProgressView().controlSize(.small).accessibilityHidden(true)
                Text("Ouverture…").font(.footnote).foregroundStyle(DrivyTheme.muted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("messaging.media.opening")
        case .failed(let failure)?:
            VStack(alignment: mine ? .trailing : .leading, spacing: DrivySpacing.xxs) {
                Text(failure.message).font(.footnote).foregroundStyle(DrivyTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("messaging.media.open.error")
                if failure.canRetry {
                    Button {
                        Task { await thread.openMedia(wire) }
                    } label: {
                        Text("Réessayer")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, DrivySpacing.s)
                            .frame(minHeight: DrivyLayout.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DrivyTheme.accent)
                        .accessibilityLabel(MessagingMediaActionText.openRetry)
                        .accessibilityIdentifier("messaging.media.open.retry")
                }
            }
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder private var attachment: some View {
        if media.mime == .pdf {
            MessagingPDFCard(name: media.name, byteSize: media.size, mine: mine, isDisabled: isDisabled) {
                Task { await thread.openMedia(wire) }
            }
        } else {
            imageBubble
                .onAppear { thread.thumbnailAppeared(wire) }
                .onDisappear { thread.thumbnails?.disappear(wire.id) }
        }
    }

    @ViewBuilder private var imageBubble: some View {
        let plan = MessagingMediaBubbleGeometry.plan(width: media.width, height: media.height)
        if let loader = thread.thumbnails {
            let presentation = Self.presentation(of: loader.slot(for: wire.id))
            MessagingImageBubble(name: media.name, plan: plan, presentation: presentation,
                                 isDisabled: isDisabled, open: open,
                                 retry: { loader.retry(wire.id) })
        } else {
            MessagingImageBubble(name: media.name, plan: plan, presentation: .unavailable(canRetry: false),
                                 isDisabled: isDisabled, open: open)
        }
    }

    private func open() { Task { await thread.openMedia(wire) } }

    private static func presentation(of slot: MessagingMediaThumbnailLoader.Slot) -> MessagingImageBubblePresentation {
        switch slot.phase {
        case .loaded:
            guard let image = slot.image else { return .loading }
            return .image(image)
        case .idle, .loading:
            return .loading
        case .unavailable(let retryable):
            return .unavailable(canRetry: retryable)
        }
    }
}

#if DEBUG
/// Images **synthétiques** pour les previews : dégradés générés en mémoire, aucune photo ni personne.
enum MessagingMediaBubbleSamples {
    static func image(width: Int, height: Int, hue: CGFloat, transparent: Bool = false) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = !transparent
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1).cgColor,
                          UIColor(hue: hue, saturation: 0.75, brightness: 0.45, alpha: 1).cgColor]
            if transparent {
                UIColor(hue: hue, saturation: 0.7, brightness: 0.6, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: size.width * 0.2, y: size.height * 0.2,
                                            width: size.width * 0.6, height: size.height * 0.6)).fill()
            } else if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                colors: colors as CFArray, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero,
                                                     end: CGPoint(x: size.width, y: size.height), options: [])
            }
        }
    }
}

private struct MessagingMediaBubblePreviewGallery: View {
    private struct Sample: Identifiable {
        let id = UUID()
        let label: String
        let mine: Bool
        let caption: String?
        let kind: Kind
        enum Kind {
            case image(width: Int, height: Int, presentation: MessagingImageBubblePresentation)
            case pdf(name: String, size: Int)
        }
    }

    private var samples: [Sample] {
        [
            Sample(label: "Paysage reçu", mine: false, caption: "Le circuit de ce matin (légende synthétique)",
                   kind: .image(width: 4032, height: 3024, presentation: .image(MessagingMediaBubbleSamples.image(width: 400, height: 300, hue: 0.58)))),
            Sample(label: "Portrait envoyé", mine: true, caption: nil,
                   kind: .image(width: 3024, height: 4032, presentation: .image(MessagingMediaBubbleSamples.image(width: 300, height: 400, hue: 0.08)))),
            Sample(label: "Carré reçu", mine: false, caption: nil,
                   kind: .image(width: 1200, height: 1200, presentation: .image(MessagingMediaBubbleSamples.image(width: 360, height: 360, hue: 0.35)))),
            Sample(label: "Capture longue envoyée", mine: true, caption: "Capture longue recadrée en haut",
                   kind: .image(width: 1170, height: 5200, presentation: .image(MessagingMediaBubbleSamples.image(width: 117, height: 520, hue: 0.75)))),
            Sample(label: "Panorama reçu", mine: false, caption: nil,
                   kind: .image(width: 6000, height: 1500, presentation: .image(MessagingMediaBubbleSamples.image(width: 512, height: 128, hue: 0.12)))),
            Sample(label: "Transparence reçue", mine: false, caption: nil,
                   kind: .image(width: 800, height: 600, presentation: .image(MessagingMediaBubbleSamples.image(width: 400, height: 300, hue: 0.9, transparent: true)))),
            Sample(label: "Chargement", mine: false, caption: nil,
                   kind: .image(width: 4032, height: 3024, presentation: .loading)),
            Sample(label: "Indisponible avec reprise", mine: false, caption: nil,
                   kind: .image(width: 3024, height: 4032, presentation: .unavailable(canRetry: true))),
            Sample(label: "Indisponible sans reprise", mine: true, caption: nil,
                   kind: .image(width: 1600, height: 900, presentation: .unavailable(canRetry: false))),
            Sample(label: "PDF court reçu", mine: false, caption: nil,
                   kind: .pdf(name: "Consignes.pdf", size: 184_000)),
            Sample(label: "PDF nom long envoyé", mine: true, caption: "Avec légende synthétique",
                   kind: .pdf(name: "Relevé_de_compétences_conduite_accompagnée_et_remarques_du_moniteur_session_de_novembre_2026_version_finale.pdf", size: 2_450_000))
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DrivySpacing.m) {
                Text("Exemples synthétiques")
                    .font(.caption).foregroundStyle(DrivyTheme.muted)
                ForEach(samples) { sample in
                    VStack(alignment: sample.mine ? .trailing : .leading, spacing: 2) {
                        if let caption = sample.caption {
                            Text(caption)
                                .font(.body).foregroundStyle(DrivyTheme.text)
                                .padding(.horizontal, DrivySpacing.s).padding(.vertical, DrivySpacing.xs)
                                .background(sample.mine ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted,
                                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        switch sample.kind {
                        case .image(let width, let height, let presentation):
                            MessagingImageBubble(name: "\(sample.label).jpg",
                                                 plan: MessagingMediaBubbleGeometry.plan(width: width, height: height),
                                                 presentation: presentation, open: {}, retry: {})
                        case .pdf(let name, let size):
                            MessagingPDFCard(name: name, byteSize: size, mine: sample.mine, open: {})
                        }
                        Text(sample.mine ? "10:42 · Envoyé" : "10:41")
                            .font(.caption2).foregroundStyle(DrivyTheme.textTertiary)
                    }
                    .padding(.leading, sample.mine ? 70 : 12)
                    .padding(.trailing, sample.mine ? 22 : 70)
                    .frame(maxWidth: .infinity, alignment: sample.mine ? .trailing : .leading)
                }
            }
            .padding(.vertical, DrivySpacing.m)
        }
        .background(DrivyTheme.canvas)
    }
}

#Preview("Fil · clair (synthétique)") {
    MessagingMediaBubblePreviewGallery().preferredColorScheme(.light)
}

#Preview("Fil · sombre (synthétique)") {
    MessagingMediaBubblePreviewGallery().preferredColorScheme(.dark)
}

#Preview("Fil · grand texte (synthétique)") {
    MessagingMediaBubblePreviewGallery()
        .dynamicTypeSize(.accessibility3)
        .preferredColorScheme(.light)
}
#endif
