import SwiftUI

/// La trace: a line and a station. Neither replaces the text that explains its state.
struct DrivyTraceLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

struct DrivyMarker: View {
    var isCurrent = false
    var isPast = false
    var color: Color? = nil
    var symbol: String? = nil

    var body: some View {
        Circle()
            .fill(isPast && !isCurrent && symbol == nil ? DrivyTheme.text : DrivyTheme.surface)
            .overlay {
                Circle().strokeBorder(color ?? (isCurrent ? DrivyTheme.accent : isPast ? DrivyTheme.text : DrivyTheme.controlBorder),
                    lineWidth: isCurrent ? 3 : 2)
            }
            .overlay {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                        .foregroundStyle(color ?? DrivyTheme.text)
                }
            }
            .frame(width: symbol != nil ? 28 : isCurrent ? 14 : 10,
                height: symbol != nil ? 28 : isCurrent ? 14 : 10)
            .padding(symbol != nil || isCurrent ? 0 : 2)
            .background(DrivyTheme.surface, in: Circle())
            .accessibilityHidden(true)
    }
}

enum DrivyThreadPosition {
    case first, middle, last, only

    static func at(_ index: Int, count: Int) -> Self {
        if count <= 1 { return .only }
        if index == 0 { return .first }
        if index == count - 1 { return .last }
        return .middle
    }
}

private struct DrivyMarkerAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// Use in a VStack(spacing: 0). The rail follows the actual first text baseline,
/// including accessibility sizes; row height is always determined by its content.
struct DrivyThreadItem<Content: View>: View {
    var position: DrivyThreadPosition = .only
    var isCurrent = false
    var isPast = true
    var markerColor: Color? = nil
    var markerSymbol: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
            DrivyMarker(isCurrent: isCurrent, isPast: isPast, color: markerColor, symbol: markerSymbol)
                .anchorPreference(key: DrivyMarkerAnchorKey.self, value: .bounds) { $0 }
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DrivySpacing.s)
        .backgroundPreferenceValue(DrivyMarkerAnchorKey.self) { anchor in
            GeometryReader { geometry in
                if let anchor {
                    let marker = geometry[anchor]
                    let top = position == .first || position == .only ? marker.midY : 0
                    let bottom = position == .last ? marker.midY : geometry.size.height
                    Path { path in
                        path.move(to: CGPoint(x: marker.midX, y: top))
                        path.addLine(to: CGPoint(x: marker.midX, y: marker.midY))
                    }
                    .stroke(isPast || isCurrent ? DrivyTheme.text : DrivyTheme.rail, lineWidth: 2)
                    Path { path in
                        path.move(to: CGPoint(x: marker.midX, y: marker.midY))
                        path.addLine(to: CGPoint(x: marker.midX, y: bottom))
                    }
                    .stroke(isPast && !isCurrent ? DrivyTheme.text : DrivyTheme.rail, lineWidth: 2)
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
}

/// The empty track is distinct from the three observed levels. The text alongside
/// the track remains the primary reading, including in VoiceOver and high contrast.
struct DrivyCompetencyTrack: View {
    let level: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func rank(_ level: String) -> Int {
        switch level { case "DISCOVERING": 1; case "GUIDED": 2; case "INDEPENDENT": 3; default: 0 }
    }

    private var rank: Int { Self.rank(level) }
    private var description: String {
        switch rank {
        case 1: "En découverte, niveau 1 sur 3"
        case 2: "Avec accompagnement, niveau 2 sur 3"
        case 3: "En autonomie, niveau 3 sur 3"
        default: "Pas encore évaluée"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...3, id: \.self) { step in
                DrivyMarker(isCurrent: step == rank, isPast: step < rank)
                if step < 3 {
                    DrivyTraceLine()
                        .stroke(step < rank ? DrivyTheme.text : DrivyTheme.rail,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 12, height: 14)
                }
            }
        }
        .fixedSize()
        .animation(DrivyMotion.trace(reduceMotion), value: rank)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progression")
        .accessibilityValue(description)
    }
}
