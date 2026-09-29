import SwiftUI

/// Décor du thème : son titre et son action restent portés par le contrôle parent.
struct SchoolObservationEmblem: View {
    let theme: SchoolLiveObservationTheme
    var size: CGFloat = 72
    @Environment(\.colorSchemeContrast) private var contrast

    private enum Motif { case intersection, sign, giveWay, speed, parking, motorway, anticipation, symbol }

    private var motif: Motif {
        switch theme.title {
        case "Priorité à droite": return .intersection
        case "Signalisation": return .sign
        case "Céder le passage": return .giveWay
        case "Vitesse", "Adaptation de la vitesse": return .speed
        case "Stationnement": return .parking
        case "Autoroute", "Autoroutes": return .motorway
        case "Anticipation": return .anticipation
        default: return theme.competency.key == "autoroute" ? .motorway : .symbol
        }
    }

    var body: some View {
        // Aplat de marque et filet, sans dégradé ni ombre : l’emblème reste net en plein soleil
        // comme de nuit, et les routes claires se détachent du fond accentSoft dans les deux thèmes.
        ZStack {
            Circle().fill(DrivyTheme.accentSoft)
            Circle().strokeBorder(contrast == .increased ? DrivyTheme.controlBorder : DrivyTheme.border,
                                  lineWidth: contrast == .increased ? 1 : 0.5)
            drawing
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var drawing: some View {
        switch motif {
        case .intersection:
            road([(0.5, 0.16), (0.5, 0.84)])
            road([(0.16, 0.49), (0.84, 0.49)])
            stroke([(0.5, 0.8), (0.5, 0.61)], color: DrivyTheme.muted, width: 0.025, dash: true)
            stroke([(0.68, 0.49), (0.85, 0.49)], color: DrivyTheme.muted, width: 0.025, dash: true)
            symbol("arrow.turn.up.right", scale: 0.38, x: 0.45, y: 0.43)
        case .sign:
            stroke([(0.48, 0.42), (0.48, 0.77)], color: DrivyTheme.muted, width: 0.055)
            stroke([(0.29, 0.79), (0.7, 0.79)], color: DrivyTheme.border, width: 0.04)
            symbol("signpost.right", scale: 0.49, x: 0.5, y: 0.42)
        case .giveWay:
            SchoolEmblemLine(points: [(0.26, 0.27), (0.74, 0.27), (0.5, 0.67)], closed: true)
                .fill(DrivyTheme.surface)
            SchoolEmblemLine(points: [(0.26, 0.27), (0.74, 0.27), (0.5, 0.67)], closed: true)
                .stroke(DrivyTheme.accent, style: StrokeStyle(lineWidth: size * 0.055, lineJoin: .round))
            stroke([(0.27, 0.78), (0.73, 0.78)], color: DrivyTheme.muted, width: 0.035, dash: true)
        case .speed:
            symbol("speedometer", scale: 0.53, x: 0.5, y: 0.45)
            stroke([(0.35, 0.78), (0.39, 0.69)], color: DrivyTheme.muted, width: 0.035)
            stroke([(0.65, 0.78), (0.61, 0.69)], color: DrivyTheme.muted, width: 0.035)
        case .parking:
            stroke([(0.52, 0.58), (0.52, 0.78)], color: DrivyTheme.muted, width: 0.045)
            stroke([(0.31, 0.8), (0.7, 0.8)], color: DrivyTheme.border, width: 0.04)
            RoundedRectangle(cornerRadius: size * 0.085, style: .continuous)
                .fill(DrivyTheme.accent)
                .frame(width: size * 0.44, height: size * 0.44)
                .position(x: size * 0.5, y: size * 0.41)
            symbol("parkingsign", scale: 0.29, x: 0.5, y: 0.41, color: DrivyTheme.onAccent)
        case .motorway:
            SchoolEmblemLine(points: [(0.21, 0.79), (0.42, 0.21), (0.58, 0.21), (0.79, 0.79)], closed: true)
                .fill(DrivyTheme.surface)
            stroke([(0.23, 0.79), (0.42, 0.22)], color: DrivyTheme.accent, width: 0.045)
            stroke([(0.77, 0.79), (0.58, 0.22)], color: DrivyTheme.accent, width: 0.045)
            stroke([(0.5, 0.77), (0.5, 0.27)], color: DrivyTheme.muted, width: 0.03, dash: true)
            stroke([(0.25, 0.43), (0.75, 0.43)], color: DrivyTheme.accent, width: 0.07)
        case .anticipation:
            SchoolEmblemBend()
                .stroke(DrivyTheme.surface, style: StrokeStyle(lineWidth: size * 0.19, lineCap: .round))
            SchoolEmblemBend()
                .stroke(DrivyTheme.accent, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round,
                                                            dash: [size * 0.065, size * 0.06]))
            symbol("arrow.up.forward", scale: 0.33, x: 0.65, y: 0.3)
        case .symbol:
            symbol(theme.symbol, scale: 0.45, x: 0.5, y: 0.5)
        }
    }

    private func symbol(_ name: String, scale: CGFloat, x: CGFloat, y: CGFloat,
                        color: Color = DrivyTheme.accent) -> some View {
        Image(systemName: name)
            .font(.system(size: size * scale, weight: .semibold))
            .foregroundStyle(color)
            .position(x: size * x, y: size * y)
    }

    private func road(_ points: [(CGFloat, CGFloat)]) -> some View {
        SchoolEmblemLine(points: points)
            .stroke(DrivyTheme.surface, style: StrokeStyle(lineWidth: size * 0.2, lineCap: .round))
    }

    private func stroke(_ points: [(CGFloat, CGFloat)], color: Color, width: CGFloat,
                        dash: Bool = false) -> some View {
        SchoolEmblemLine(points: points)
            .stroke(color, style: StrokeStyle(lineWidth: size * width, lineCap: .round, lineJoin: .round,
                                             dash: dash ? [size * 0.05, size * 0.055] : []))
    }
}

private struct SchoolEmblemLine: Shape {
    let points: [(CGFloat, CGFloat)]
    var closed = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let position = CGPoint(x: rect.minX + point.0 * rect.width, y: rect.minY + point.1 * rect.height)
            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        if closed { path.closeSubpath() }
        return path
    }
}

private struct SchoolEmblemBend: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.81))
        path.addCurve(to: CGPoint(x: rect.minX + rect.width * 0.63, y: rect.minY + rect.height * 0.29),
                      control1: CGPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.46),
                      control2: CGPoint(x: rect.minX + rect.width * 0.69, y: rect.minY + rect.height * 0.68))
        return path
    }
}
