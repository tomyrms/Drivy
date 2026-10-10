import SwiftUI

/// Trois chorégraphies du symbole Drivy pour le démarrage d’une leçon. Une seule sera retenue par le porteur.
enum DrivyLaunchChoreography: String, CaseIterable, Identifiable {
    /// A : la tige descend, l’anneau glisse vers elle.
    case join
    /// B : la tige se redresse sur son pied, l’anneau l’accompagne.
    case upright
    /// C : l’anneau suit une courbe courte, passe derrière la tige et ressort à gauche.
    case passBehind

    var id: String { rawValue }
    var title: String {
        switch self {
        case .join: "A — Les deux pièces se rejoignent"
        case .upright: "B — La tige se redresse"
        case .passBehind: "C — L’anneau passe derrière la tige"
        }
    }
}

/// Pose des deux pièces à un instant, dans le repère 256 × 256 des assets de marque.
struct DrivyLaunchPose: Equatable {
    var ring = CGSize.zero
    var stem = CGSize.zero
    /// Inclinaison de la tige autour de son pied, en degrés (sens horaire).
    var stemAngle = 0.0
    /// La tige masque l’anneau, en gardant l’espace de la marque entre les deux.
    var ringBehindStem = false

    static let rest = DrivyLaunchPose()
}

/// Les mouvements sont des fonctions du temps : même pose à même instant sur chaque appareil, rien à synchroniser.
enum DrivyLaunchTimeline {
    /// Durée de la séquence, pose finale comprise.
    static let duration = 2.0
    /// Instant où les pièces des variantes B et C sont en place.
    static let settled = 2.1

    static func pose(_ choreography: DrivyLaunchChoreography, at time: Double) -> DrivyLaunchPose {
        switch choreography {
        case .join:
            // La tige tombe en place sur un ressort ; l’anneau recule d’un rien (anticipation), part à son tour et
            // dépasse légèrement sa place avant de s’y poser. À son arrivée, la tige répond d’un petit écart.
            // Réglé pour que les pièces ne se touchent jamais (écart minimal : 2 unités sur 256).
            let anticipation = 6 * smooth(progress(time, 0.16, 0.32))
            let reaction = time - 0.62
            let nudge = reaction > 0 ? 2 * exp(-9 * reaction) * sin(17 * reaction) : 0
            return DrivyLaunchPose(ring: CGSize(width: (-40 - anticipation) * (1 - spring(time - 0.34, response: 0.52)), height: 0),
                stem: CGSize(width: nudge, height: -34 * (1 - spring(time - 0.12, response: 0.5))))
        case .upright:
            return DrivyLaunchPose(ring: CGSize(width: -12 * (1 - settle(progress(time, 0.55, settled))), height: 0),
                stemAngle: 13 * (1 - settle(progress(time, 0.3, 1.9))))
        case .passBehind:
            let point = arc(travel(progress(time, 0.3, settled)))
            return DrivyLaunchPose(ring: CGSize(width: point.x, height: point.y), ringBehindStem: time < settled)
        }
    }

    static func progress(_ time: Double, _ start: Double, _ end: Double) -> Double { min(1, max(0, (time - start) / (end - start))) }
    static func smooth(_ value: Double) -> Double { value * value * (3 - 2 * value) }
    /// Départ doux, longue décélération : les pièces ralentissent en arrivant, sans rebond.
    static func settle(_ value: Double) -> Double { bezier(value, 0.5, 0, 0.1, 1) }
    static func travel(_ value: Double) -> Double { bezier(value, 0.45, 0, 0.2, 1) }
    /// Ressort sous-amorti (amortissement 0,62) : environ 8 % de dépassement, puis il se pose.
    static func spring(_ time: Double, response: Double, damping: Double = 0.62) -> Double {
        guard time > 0 else { return 0 }
        let frequency = 2 * Double.pi / response, damped = frequency * (1 - damping * damping).squareRoot()
        return 1 - exp(-damping * frequency * time) * (cos(damped * time) + damping * frequency / damped * sin(damped * time))
    }

    /// Trajectoire de l’anneau de la variante C : part en bas à gauche, passe derrière la tige, revient par le haut.
    private static func arc(_ t: Double) -> CGPoint {
        let a = (1 - t) * (1 - t) * (1 - t), b = 3 * (1 - t) * (1 - t) * t, c = 3 * (1 - t) * t * t
        // Points de contrôle : (-40, 30), (30, 34), (40, -30), puis la position du logo (0, 0).
        let x: Double = -40 * a + 30 * b + 40 * c
        let y: Double = 30 * a + 34 * b - 30 * c
        return CGPoint(x: x, y: y)
    }

    /// Courbe de Bézier cubique d’interpolation (comme `cubic-bezier` en CSS), résolue par Newton.
    private static func bezier(_ value: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if value <= 0 { return 0 }
        if value >= 1 { return 1 }
        var t = value
        for _ in 0..<12 {
            let x = 3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t
            let slope = 3 * (1 - t) * (1 - t) * x1 + 6 * (1 - t) * t * (x2 - x1) + 3 * t * t * (1 - x2)
            if abs(slope) < 1e-6 { break }
            t = min(1, max(0, t - (x - value) / slope))
        }
        return 3 * (1 - t) * (1 - t) * t * y1 + 3 * (1 - t) * t * t * y2 + t * t * t
    }
}

/// Tracés des assets `DrivyBrandTrace` et `DrivyBrandMarker`, repris point par point : la pose finale est le logo.
struct DrivyMarkGeometry {
    let stem: Path
    let ring: Path
    /// Espace entre l’anneau et la découpe de la tige.
    let gap: CGFloat
    /// Pied de la tige, centre de son arrondi bas.
    static let stemFoot = CGPoint(x: 190, y: 208)

    static let light = DrivyMarkGeometry(left: 170, right: 210, top: 28, bottom: 228, notchEnd: CGPoint(x: 170.47, y: 212.35),
        notchStart: 99.21, corner: (11.05, 8.95), lower: (CGPoint(x: 180.45, y: 228), CGPoint(x: 172.46, y: 221.3)),
        inward: (CGPoint(x: 185.56, y: 198.29), CGPoint(x: 195, y: 178.25)), outward: (CGPoint(x: 195, y: 133.52), CGPoint(x: 185.37, y: 113.29)),
        outerRadius: 72, innerRadius: 40)
    static let dark = DrivyMarkGeometry(left: 170.75, right: 209.25, top: 28.75, bottom: 227.25, notchEnd: CGPoint(x: 171.11, y: 211.75),
        notchStart: 99.91, corner: (10.63, 8.62), lower: (CGPoint(x: 180.65, y: 227.25), CGPoint(x: 172.86, y: 220.59)),
        inward: (CGPoint(x: 185.83, y: 197.72), CGPoint(x: 195, y: 177.93)), outward: (CGPoint(x: 195, y: 133.89), CGPoint(x: 185.68, y: 113.95)),
        outerRadius: 71.25, innerRadius: 40.75)

    private init(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat, notchEnd: CGPoint, notchStart: CGFloat,
                 corner: (CGFloat, CGFloat), lower: (CGPoint, CGPoint), inward: (CGPoint, CGPoint), outward: (CGPoint, CGPoint),
                 outerRadius: CGFloat, innerRadius: CGFloat) {
        let centre = CGPoint(x: 118, y: 156)
        var stem = Path()
        stem.move(to: CGPoint(x: left, y: 48))
        stem.addCurve(to: CGPoint(x: 190, y: top), control1: CGPoint(x: left, y: 48 - corner.0), control2: CGPoint(x: left + corner.1, y: top))
        stem.addCurve(to: CGPoint(x: right, y: 48), control1: CGPoint(x: 190 + corner.0, y: top), control2: CGPoint(x: right, y: 48 - corner.0))
        stem.addLine(to: CGPoint(x: right, y: 208))
        stem.addCurve(to: CGPoint(x: 190, y: bottom), control1: CGPoint(x: right, y: 208 + corner.0), control2: CGPoint(x: 190 + corner.0, y: bottom))
        stem.addCurve(to: notchEnd, control1: lower.0, control2: lower.1)
        stem.addCurve(to: CGPoint(x: 195, y: centre.y), control1: inward.0, control2: inward.1)
        stem.addCurve(to: CGPoint(x: left, y: notchStart), control1: outward.0, control2: outward.1)
        stem.closeSubpath()
        self.stem = stem
        var ring = Path()
        ring.addEllipse(in: CGRect(x: centre.x - outerRadius, y: centre.y - outerRadius, width: 2 * outerRadius, height: 2 * outerRadius))
        ring.addEllipse(in: CGRect(x: centre.x - innerRadius, y: centre.y - innerRadius, width: 2 * innerRadius, height: 2 * innerRadius))
        self.ring = ring
        gap = 195 - centre.x - outerRadius
    }
}

/// Le symbole seul, animé une fois depuis `start`. Aucun texte, aucun décor : tout vient des deux pièces.
/// `waits` : la préparation dure plus longtemps que la séquence, l’anneau respire alors très légèrement.
struct DrivyLaunchMark: View {
    let choreography: DrivyLaunchChoreography
    let start: Date
    var waits = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = max(0, timeline.date.timeIntervalSince(start))
            let geometry = colorScheme == .dark ? DrivyMarkGeometry.dark : DrivyMarkGeometry.light
            let color = colorScheme == .dark ? Color.white : Color(red: 0x24 / 255, green: 0x5B / 255, blue: 0xD6 / 255)
            // Mouvement réduit : le logo apparaît en fondu, sans trajectoire ni rotation.
            let pose = reduceMotion ? DrivyLaunchPose.rest : DrivyLaunchTimeline.pose(choreography, at: time)
            let appearance = reduceMotion ? DrivyLaunchTimeline.smooth(DrivyLaunchTimeline.progress(time, 0.1, 0.7)) : 1
            let breath = waits && !reduceMotion && time > DrivyLaunchTimeline.duration
                ? 1 - 0.3 * (0.5 - 0.5 * cos((time - DrivyLaunchTimeline.duration) * 2 * .pi / 1.8)) : 1
            Canvas { context, size in
                let scale = min(size.width, size.height) / 256
                let fit = CGAffineTransform(translationX: (size.width - 256 * scale) / 2, y: (size.height - 256 * scale) / 2).scaledBy(x: scale, y: scale)
                let foot = DrivyMarkGeometry.stemFoot
                let stem = geometry.stem
                    .applying(CGAffineTransform(translationX: -foot.x, y: -foot.y))
                    .applying(CGAffineTransform(rotationAngle: pose.stemAngle * .pi / 180))
                    .applying(CGAffineTransform(translationX: foot.x + pose.stem.width, y: foot.y + pose.stem.height))
                    .applying(fit)
                let ring = geometry.ring.applying(CGAffineTransform(translationX: pose.ring.width, y: pose.ring.height)).applying(fit)
                context.opacity = appearance
                context.drawLayer { layer in
                    layer.opacity = breath
                    layer.fill(ring, with: .color(color), style: FillStyle(eoFill: true))
                    if pose.ringBehindStem {
                        // La tige, élargie de l’espace de la marque, retire l’anneau qui passe derrière elle.
                        layer.blendMode = .destinationOut
                        layer.fill(stem, with: .color(.black))
                        layer.stroke(stem, with: .color(.black), style: StrokeStyle(lineWidth: 2 * (geometry.gap - 0.4) * scale, lineJoin: .round))
                    }
                }
                context.fill(stem, with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
/// Comparaison des trois variantes : même symbole, même taille, même durée. Hors de l’interface de production.
private struct DrivyLaunchComparison: View {
    @State private var start = Date()
    @State private var dark = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(DrivyLaunchChoreography.allCases) { choreography in
                    VStack(spacing: 8) {
                        ZStack {
                            (dark ? Color.black : Color.white)
                            DrivyLaunchMark(choreography: choreography, start: start).frame(width: 96, height: 96)
                        }
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        Text(choreography.title).font(.caption).multilineTextAlignment(.center)
                    }
                }
            }
            .environment(\.colorScheme, dark ? .dark : .light)
            HStack {
                Button("Rejouer") { start = Date() }
                Toggle("Thème sombre", isOn: $dark)
            }
        }
        .padding()
        .background(Color(white: 0.92))
    }
}

#Preview("Démarrage — A, B, C") { DrivyLaunchComparison() }
#endif
