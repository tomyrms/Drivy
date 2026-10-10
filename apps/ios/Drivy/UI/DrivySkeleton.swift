import SwiftUI

// Placeholder shapes for the first load of a content whose shape is known
// (a list, a record). An operation in progress (saving, checking, sending,
// loading the next page) keeps DrivyLoadingState; a content already on screen
// is never replaced by a skeleton while it is read again.
//
// Blocks sit where the real lines will be, at the height of the real rows, so
// the content arrives without moving the page. Compose them, then put
// `drivySkeleton(_:)` once on their container.

/// Shared metrics of the skeleton. The line boxes mirror the system text
/// styles used by the real rows (headline 22 pt, subheadline 20 pt, caption 16 pt).
private enum DrivySkeletonMetrics {
    /// One pass of the highlight across the container, in seconds.
    static let sweepPeriod: Double = 1.4
    /// Opacity the blocks fall to under the highlight.
    static let sweepDip: Double = 0.45
    /// Width of the highlight, in container widths.
    static let sweepSpan: CGFloat = 0.8
    /// The sweep is a wide soft band: 30 images per second are enough.
    static let sweepFrameInterval: Double = 1.0 / 30.0
    /// A load shorter than this shows no skeleton at all, so a fast answer never flashes.
    static let revealDelay: Duration = .milliseconds(150)
    /// Share of the line box filled by the block, close to the cap height of the text.
    static let blockRatio: CGFloat = 0.62
    /// Longest title and detail lines on a wide column (iPad).
    static let titleMaxWidth: CGFloat = 240
    static let detailMaxWidth: CGFloat = 340

    private static let titleFractions: [CGFloat] = [0.46, 0.62, 0.38, 0.54, 0.70, 0.42]
    private static let detailFractions: [CGFloat] = [0.78, 0.58, 0.86, 0.66, 0.50, 0.72]
    private static let tailFractions: [CGFloat] = [0.40, 0.52, 0.34, 0.60, 0.44, 0.30]

    /// Width of a line as a share of its column. Same row, same widths at every
    /// render: nothing random, so the placeholder never jitters.
    static func fraction(line: Int, seed: Int) -> CGFloat {
        let table = line == 0 ? titleFractions : (line == 1 ? detailFractions : tailFractions)
        let index = ((seed + line) % table.count + table.count) % table.count
        return table[index]
    }
}

/// Fill shared by every placeholder shape: the hairline token, visible on the
/// surface and on the canvas in both appearances; Increase Contrast darkens it.
private struct DrivySkeletonFill<S: Shape>: View {
    let shape: S
    @Environment(\.colorSchemeContrast) private var contrast

    private var tint: Color {
        contrast == .increased ? DrivyTheme.controlBorder.opacity(0.6) : DrivyTheme.border
    }

    var body: some View {
        shape
            .fill(tint)
            .accessibilityHidden(true)
    }
}

/// Bloc arrondi qui tient la place d'un texte, d'un chiffre ou d'une vignette.
/// `width` nil prend toute la largeur. La hauteur suit Dynamic Type ; passer
/// `scalesWithText: false` pour une vignette dont la taille réelle est fixe.
struct DrivySkeletonBlock: View {
    private let width: CGFloat?
    private let baseHeight: CGFloat
    private let radius: CGFloat
    private let scalesWithText: Bool
    @ScaledMetric private var scaledHeight: CGFloat

    init(width: CGFloat? = nil, height: CGFloat = 14, radius: CGFloat = 6, scalesWithText: Bool = true) {
        self.width = width
        self.baseHeight = height
        self.radius = radius
        self.scalesWithText = scalesWithText
        _scaledHeight = ScaledMetric(wrappedValue: height, relativeTo: .body)
    }

    var body: some View {
        let height = scalesWithText ? scaledHeight : baseHeight
        DrivySkeletonFill(shape: RoundedRectangle(cornerRadius: min(radius, height / 2), style: .continuous))
            .frame(height: height)
            .frame(idealWidth: width, maxWidth: width ?? .infinity, alignment: .leading)
    }
}

/// One text line: a block centered in the line box of the real text style,
/// as wide as a share of the column (capped on wide columns).
private struct DrivySkeletonLine: View {
    let fraction: CGFloat
    let maxWidth: CGFloat
    let lineHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            DrivySkeletonBlock(
                width: max(0, min(proxy.size.width * fraction, maxWidth)),
                height: lineHeight * DrivySkeletonMetrics.blockRatio,
                scalesWithText: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: lineHeight)
    }
}

/// Ligne de liste fantôme : repère optionnel puis `lines` lignes de texte de largeurs différentes.
/// `.time` reprend l'anatomie de DrivyLessonRow, `.avatar` celle de DrivyEntityRow,
/// `.none` celle de DrivyNavigationRow. `seed` décale les largeurs d'une ligne à l'autre.
struct DrivySkeletonRow: View {
    enum Leading { case none, avatar, time }   // avatar = disque 44 pt ; time = colonne d'heure comme DrivyLessonRow

    private let leading: Leading
    private let lines: Int
    private let seed: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .headline) private var titleLine: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) private var detailLine: CGFloat = 20
    @ScaledMetric(relativeTo: .caption) private var captionLine: CGFloat = 16
    @ScaledMetric(relativeTo: .headline) private var startWidth: CGFloat = 46
    @ScaledMetric(relativeTo: .caption) private var endWidth: CGFloat = 32

    init(leading: Leading = .none, lines: Int = 2, seed: Int = 0) {
        self.leading = leading
        self.lines = max(1, lines)
        self.seed = seed
    }

    private var isEntity: Bool { leading == .avatar }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                stackedBody
            } else {
                HStack(alignment: isEntity ? .center : .top, spacing: isEntity ? DrivySpacing.s : DrivySpacing.m) {
                    leadingView
                    textLines
                }
            }
        }
        .padding(.vertical, isEntity ? DrivySpacing.xs : DrivySpacing.m)
        .frame(maxWidth: .infinity, minHeight: isEntity ? 56 : 64, alignment: .leading)
    }

    /// Accessibility text sizes: one column, as the real rows do. The time takes
    /// its own line; the avatar is dropped.
    private var stackedBody: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            if leading == .time {
                DrivySkeletonLine(fraction: 0.44, maxWidth: DrivySkeletonMetrics.titleMaxWidth, lineHeight: titleLine)
            }
            textLines
        }
    }

    @ViewBuilder private var leadingView: some View {
        switch leading {
        case .none:
            EmptyView()
        case .avatar:
            DrivySkeletonFill(shape: Circle())
                .frame(width: 44, height: 44)
        case .time:
            timeColumn
        }
    }

    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            DrivySkeletonBlock(width: startWidth, height: titleLine * DrivySkeletonMetrics.blockRatio, scalesWithText: false)
                .frame(height: titleLine)
            DrivySkeletonBlock(width: endWidth, height: captionLine * DrivySkeletonMetrics.blockRatio, scalesWithText: false)
                .frame(height: captionLine)
        }
        .frame(minWidth: 52, alignment: .leading)
    }

    private var textLines: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            ForEach(0..<lines, id: \.self) { index in
                DrivySkeletonLine(
                    fraction: DrivySkeletonMetrics.fraction(line: index, seed: seed),
                    maxWidth: index == 0 ? DrivySkeletonMetrics.titleMaxWidth : DrivySkeletonMetrics.detailMaxWidth,
                    lineHeight: index == 0 ? titleLine : detailLine
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `count` lignes fantômes séparées par les filets d'une liste Drivy (mêmes filets que DrivyRowGroup).
struct DrivySkeletonRows: View {
    private let count: Int
    private let leading: DrivySkeletonRow.Leading
    private let lines: Int

    init(count: Int = 4, leading: DrivySkeletonRow.Leading = .none, lines: Int = 2) {
        self.count = max(1, count)
        self.leading = leading
        self.lines = lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                DrivySkeletonRow(leading: leading, lines: lines, seed: index)
                if index < count - 1 { Divider().overlay(DrivyTheme.border) }
            }
        }
    }
}

extension View {
    /// À poser sur le conteneur de blocs fantômes : balayage lumineux discret (immobile avec Réduire les animations),
    /// un seul élément VoiceOver qui annonce `label` (« Chargement de l’agenda… »), enfants masqués à VoiceOver,
    /// aucun toucher accepté.
    func drivySkeleton(_ label: String) -> some View {
        modifier(DrivySkeletonModifier(label: label))
    }
}

/// The sweep only changes the opacity of the blocks through a mask: no layout,
/// no movement of the content. Reduce Motion keeps the blocks still; they and
/// the VoiceOver label still say that the content is loading.
private struct DrivySkeletonModifier: ViewModifier {
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = false

    func body(content: Content) -> some View {
        content
            .mask { sweep }
            .opacity(isRevealed ? 1 : 0)
            .animation(DrivyMotion.feedback(reduceMotion), value: isRevealed)
            .task {
                do { try await Task.sleep(for: DrivySkeletonMetrics.revealDelay) } catch { return }
                isRevealed = true
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }

    @ViewBuilder private var sweep: some View {
        if reduceMotion {
            Rectangle()
        } else {
            TimelineView(.animation(minimumInterval: DrivySkeletonMetrics.sweepFrameInterval, paused: false)) { context in
                DrivySkeletonSweep(date: context.date)
            }
        }
    }
}

/// Mask of the sweep: opaque everywhere, with a soft band of lower opacity that
/// crosses the container at constant speed. The phase comes from the clock, so
/// every skeleton on screen sweeps together and the loop has no visible seam
/// (the band starts and ends outside the container).
private struct DrivySkeletonSweep: View {
    let date: Date

    var body: some View {
        let period = DrivySkeletonMetrics.sweepPeriod
        let progress = CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period)
        let span = DrivySkeletonMetrics.sweepSpan
        let start = -span + progress * (1 + span)
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color.black, location: 0),
                Gradient.Stop(color: Color.black.opacity(DrivySkeletonMetrics.sweepDip), location: 0.5),
                Gradient.Stop(color: Color.black, location: 1),
            ],
            startPoint: UnitPoint(x: start, y: 0.5),
            endPoint: UnitPoint(x: start + span, y: 0.5)
        )
    }
}
