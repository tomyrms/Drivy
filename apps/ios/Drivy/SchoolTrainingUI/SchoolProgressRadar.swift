import SwiftUI

/// Une branche de la toile : une compétence du référentiel et son dernier niveau publié.
struct SchoolProgressRadarAxis: Equatable, Identifiable {
    let id: UUID
    let label: String
    /// 0 pas encore vue, 1 en découverte, 2 avec accompagnement, 3 en autonomie.
    let rank: Int
}

/// La toile de la Progression : une branche par compétence, dans l’ordre du référentiel, le niveau du centre
/// (pas encore vue) au bord (en autonomie). Elle trace les niveaux publiés tels quels : ni score, ni moyenne.
/// Décorative pour VoiceOver : la phrase d’ensemble et les listes disent déjà chaque niveau.
struct SchoolProgressRadar: View {
    let axes: [SchoolProgressRadarAxis]

    private static let labelSize = CGSize(width: 68, height: 30)
    private static let gap: CGFloat = 10
    private static let height: CGFloat = 264

    var body: some View {
        GeometryReader { geometry in
            let radius = Self.radius(in: geometry.size)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                web(radius: radius)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                ForEach(Array(axes.enumerated()), id: \.element.id) { index, axis in
                    label(axis, index: index, center: center, radius: radius)
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }

    /// Le plus grand rayon qui laisse leur place aux libellés, sans dépasser celui qu’une grande largeur permet.
    private static func radius(in size: CGSize) -> CGFloat {
        let horizontal = (size.width - 2 * (labelSize.width + gap)) / 2
        let vertical = (size.height - 2 * (labelSize.height + gap)) / 2
        return max(40, min(horizontal, vertical))
    }

    /// Anneaux des trois niveaux, branches, puis la forme des niveaux atteints et un point par compétence vue.
    private func web(radius: CGFloat) -> some View {
        let count = axes.count
        return ZStack {
            ForEach(1...3, id: \.self) { ring in
                SchoolRadarPolygon(values: Array(repeating: CGFloat(ring) / 3, count: count))
                    .stroke(DrivyTheme.border, lineWidth: 1)
            }
            SchoolRadarSpokes(count: count)
                .stroke(DrivyTheme.border, lineWidth: 1)
            SchoolRadarPolygon(values: axes.map { CGFloat($0.rank) / 3 })
                .fill(DrivyTheme.accent.opacity(0.16))
            SchoolRadarPolygon(values: axes.map { CGFloat($0.rank) / 3 })
                .stroke(DrivyTheme.accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            ForEach(Array(axes.enumerated()), id: \.element.id) { index, axis in
                if axis.rank > 0 {
                    Circle()
                        .fill(DrivyTheme.accent)
                        .frame(width: 7, height: 7)
                        .position(SchoolRadarPolygon.point(index: index, count: count,
                            center: CGPoint(x: radius, y: radius), radius: radius * CGFloat(axis.rank) / 3))
                }
            }
        }
    }

    private func label(_ axis: SchoolProgressRadarAxis, index: Int, center: CGPoint, radius: CGFloat) -> some View {
        let angle = SchoolRadarPolygon.angle(index: index, count: axes.count)
        let cosine = cos(angle), sine = sin(angle)
        let x = center.x + cosine * (radius + Self.gap + Self.labelSize.width / 2)
        let y = center.y + sine * (radius + Self.gap + Self.labelSize.height / 2)
        return Text(axis.label)
            .font(.caption2)
            .foregroundStyle(axis.rank == 0 ? DrivyTheme.muted : DrivyTheme.text)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(Self.textAlignment(cosine))
            .frame(width: Self.labelSize.width, height: Self.labelSize.height, alignment: Self.alignment(cosine: cosine, sine: sine))
            .position(x: x, y: y)
    }

    /// Le libellé s’écarte de la toile : il part du bord qui la touche.
    private static func textAlignment(_ cosine: CGFloat) -> TextAlignment {
        if cosine > 0.3 { return .leading }
        if cosine < -0.3 { return .trailing }
        return .center
    }

    private static func alignment(cosine: CGFloat, sine: CGFloat) -> Alignment {
        let horizontal: HorizontalAlignment = cosine > 0.3 ? .leading : (cosine < -0.3 ? .trailing : .center)
        let vertical: VerticalAlignment = sine > 0.3 ? .top : (sine < -0.3 ? .bottom : .center)
        return Alignment(horizontal: horizontal, vertical: vertical)
    }
}

/// Un polygone dont chaque sommet est à `values[i]` (0 au centre, 1 au bord) sur sa branche ; la première branche
/// pointe vers le haut, les suivantes tournent dans le sens des aiguilles d’une montre.
struct SchoolRadarPolygon: Shape {
    let values: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 2 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for (index, value) in values.enumerated() {
            let point = Self.point(index: index, count: values.count, center: center, radius: radius * value)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    static func angle(index: Int, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return -CGFloat.pi / 2 + 2 * CGFloat.pi * CGFloat(index) / CGFloat(count)
    }

    static func point(index: Int, count: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let value = angle(index: index, count: count)
        return CGPoint(x: center.x + cos(value) * radius, y: center.y + sin(value) * radius)
    }
}

/// Les branches de la toile, du centre au bord.
private struct SchoolRadarSpokes: Shape {
    let count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for index in 0..<max(0, count) {
            path.move(to: center)
            path.addLine(to: SchoolRadarPolygon.point(index: index, count: count, center: center, radius: radius))
        }
        return path
    }
}
