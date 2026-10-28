import SwiftUI

/// La présentation native reste séparée de la palette posée sur la carte.
struct SchoolLiveObservationSheet: View {
    @Bindable var recorder: SchoolLiveObservationRecorder
    let observedAt: Date
    var anchor: SchoolLiveObservationAnchor? = nil
    var onRecorded: (() -> Void)? = nil
    /// Hauteur dont le contenu a besoin, pour un conteneur qui fixe lui-même sa taille (popover sur iPad).
    var onIdealHeight: ((CGFloat) -> Void)? = nil
    @State private var idealHeight: CGFloat?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Le volet suit le nombre de tuiles jusqu’à neuf ; au-delà, il garde la hauteur des neuf premières et la
    /// grille défile. Estimé d’abord, puis mesuré sur le contenu réel.
    private var paletteHeight: CGFloat {
        idealHeight ?? SchoolSignalGridLayout.estimatedPaletteHeight(tileCount: recorder.expectedTileCount,
            width: SchoolSignalGridLayout.assumedWidth, textSize: dynamicTypeSize)
    }

    var body: some View {
        // Le détent d’une feuille ne compte pas la marge du bas : le système l’ajoute.
        SchoolLiveObservationPalette(recorder: recorder, observedAt: observedAt, anchor: anchor, onRecorded: onRecorded,
            countsBottomInset: false, onIdealHeight: { height in
                idealHeight = height
                onIdealHeight?(height)
            })
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(paletteHeight), .large])
            .presentationDragIndicator(.visible)
            .presentationSizing(.form)
            .presentationCornerRadius(DrivyRadius.mapPanel + DrivySpacing.xs)
            .presentationBackground(DrivyTheme.surface)
    }
}

/// L’instant et l’ancre appartiennent au geste d’ouverture, jamais au choix ou à l’animation.
/// Le conteneur choisit la hauteur, d’après celle que la palette lui demande : les neuf premières tuiles, plus
/// l’amorce estompée de la rangée suivante s’il y en a une. Seule la grille défile, entre les commandes et les
/// appréciations, qui restent visibles.
/// Les tuiles viennent de l’instantané que l’enregistreur prend à l’ouverture : une configuration modifiée
/// ailleurs entre-temps ne déplace rien sous le doigt.
struct SchoolLiveObservationPalette: View {
    @Bindable var recorder: SchoolLiveObservationRecorder
    let observedAt: Date
    var anchor: SchoolLiveObservationAnchor? = nil
    var onRecorded: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    /// Un cadre posé sur la carte inclut la marge du bas ; le détent d’une feuille, non.
    var countsBottomInset = true
    var onIdealHeight: ((CGFloat) -> Void)? = nil
    @State private var selected: SchoolLiveObservationTheme?
    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var barHeight: CGFloat = 0
    /// Hauteur d’une tuile, la même pour toutes : elle donne celle de la fenêtre des neuf premières.
    @State private var tileHeight: CGFloat = 0
    /// Des tuiles restent sous le bas de la grille : son bord s’estompe.
    @State private var hidesTilesBelow = false
    /// Son propre enregistrement ferme la palette : elle ne change plus d’apparence pendant sa sortie.
    @State private var isClosingAfterRecord = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusedStatus: String?

    /// Changement de thème : un fondu bref même sous Réduire les animations, jamais un remplacement sec.
    private var motion: Animation { reduceMotion ? .easeInOut(duration: 0.16) : .easeOut(duration: 0.16) }
    private let statuses: [SchoolObservationStatus] = [.toWorkOn, .attention, .positive]
    /// Une écriture attend : autre demande de l’école à vérifier. Un signalement précédent encore en cours d’envoi
    /// ne fait rien attendre : il est déjà conservé, le suivant prend sa place dans la file (#112).
    private var writesWait: Bool { !recorder.canRecord && !isClosingAfterRecord }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroll in
                paletteContents(width: proxy.size.width)
                    .onChange(of: recorder.errorMessage) { _, error in
                        if error != nil { scroll.scrollTo("live-observation-error", anchor: .bottom) }
                    }
            }
            .onChange(of: idealHeight(width: proxy.size.width, bottomInset: countsBottomInset ? proxy.safeAreaInsets.bottom : 0), initial: true) { _, height in
                if let height { onIdealHeight?(height) }
            }
        }
        .foregroundStyle(DrivyTheme.text)
        .background(DrivyTheme.surface)
        .tint(DrivyTheme.accent)
        .sensoryFeedback(.selection, trigger: selected?.id)
        // Avant la première image : les tuiles de cette ouverture ne changent plus ensuite.
        .onAppear { recorder.openPalette() }
    }

    /// Hauteur de l’en-tête, de la grille et des appréciations. Jusqu’à neuf tuiles, toute la grille ; au-delà,
    /// sa fenêtre (`SchoolSignalGridLayout.windowHeight`), le reste s’atteignant en défilant.
    /// Un message passager (erreur, envoi précédent) n’entre pas dans le compte : il ne redimensionne pas le
    /// volet sous le doigt, la grille défile pour lui faire place.
    private func idealHeight(width: CGFloat, bottomInset: CGFloat) -> CGFloat? {
        guard headerHeight > 0, contentHeight > 0, barHeight > 0 else { return nil }
        let layout = SchoolSignalGridLayout(tileCount: recorder.themes.count, width: width, textSize: dynamicTypeSize)
        let grid: CGFloat
        if layout.overflows {
            guard tileHeight > 0 else { return nil }
            grid = min(contentHeight, layout.windowHeight(tileHeight: tileHeight))
        } else {
            grid = contentHeight
        }
        return (headerHeight + grid + SchoolSignalGridLayout.gutter + 1 + barHeight + bottomInset).rounded(.up)
    }

    @ViewBuilder private func paletteContents(width: CGFloat) -> some View {
        if verticalSizeClass == .compact {
            // Landscape can leave less room than the header and choices need together.
            ScrollView {
                VStack(spacing: 0) {
                    measuredHeader
                    themeContent(width: width)
                    appraisalBar
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            VStack(spacing: 0) {
                measuredHeader
                ScrollView { themeContent(width: width) }
                    .scrollBounceBehavior(.basedOnSize)
                    // Indicateur montré un instant à l’ouverture, fondu sur l’amorce de la rangée suivante : la suite
                    // de la grille se devine sans bouton ni pagination. Le fondu disparaît en fin de course.
                    .scrollIndicatorsFlash(onAppear: true)
                    .mask { bottomFade }
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentSize.height + geometry.contentInsets.bottom
                            - geometry.contentOffset.y - geometry.containerSize.height > 2
                    } action: { _, hidden in
                        withAnimation(DrivyMotion.feedback(reduceMotion)) { hidesTilesBelow = hidden }
                    }
                appraisalBar
            }
        }
    }

    private var bottomFade: some View {
        VStack(spacing: 0) {
            Color.black
            ZStack {
                LinearGradient(colors: [.black, .black.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                Color.black.opacity(hidesTilesBelow ? 0 : 1)
            }
            .frame(height: SchoolSignalGridLayout.fadeHeight)
        }
    }

    private var measuredHeader: some View {
        header.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
    }

    private func themeContent(width: CGFloat) -> some View {
        VStack(spacing: DrivySpacing.m) {
            themes(width: width)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            if let error = recorder.errorMessage {
                VStack(spacing: DrivySpacing.s) {
                    SchoolErrorNotice(message: error)
                    if recorder.canRetry {
                        Button("Réessayer", systemImage: "arrow.clockwise") { Task { await recorder.retry() } }
                            .buttonStyle(DrivySecondaryButtonStyle())
                    }
                }
                .id("live-observation-error")
            }
        }
        .padding(.horizontal, SchoolSignalGridLayout.gutter)
        .padding(.bottom, SchoolSignalGridLayout.gutter)
    }

    private var appraisalBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(DrivyTheme.border)
            appraisals
                .padding(.horizontal, DrivySpacing.s)
                .padding(.vertical, DrivySpacing.xs)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: DrivySpacing.xxs) {
            Text("Signaler")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DrivySpacing.xs)
            roundControl("Effacer le choix", symbol: "arrow.counterclockwise") {
                withAnimation(motion) { selected = nil }
                focusedStatus = nil
            }
            .opacity(selected == nil ? 0 : 1)
            .disabled(selected == nil)
            .accessibilityHidden(selected == nil)
            .accessibilityIdentifier("live-observation-back")
            Button {
                guard recorder.markMoment(at: observedAt, anchor: anchor) else { return }
                recorded()
            } label: {
                SchoolMarkerEmblem(size: 28)
                    .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(DrivyTileButtonStyle())
            .disabled(!recorder.canRecord)
            .opacity(writesWait ? 0.45 : 1)
            .animation(DrivyMotion.feedback(reduceMotion), value: writesWait)
            .accessibilityLabel("Marquer un moment")
            .accessibilityIdentifier("live-observation-marker")
            roundControl("Annuler le signalement", symbol: "xmark", action: close)
                .accessibilityIdentifier("live-observation-close")
        }
        .padding(.leading, DrivySpacing.m)
        .padding(.trailing, DrivySpacing.s)
        .padding(.vertical, DrivySpacing.xs)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func roundControl(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(DrivyMapGlyph.control)
                .foregroundStyle(DrivyTheme.muted)
                .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(DrivyTileButtonStyle())
        .accessibilityLabel(label)
    }

    private func themes(width: CGFloat) -> some View {
        let tiles = recorder.themes
        let layout = SchoolSignalGridLayout(tileCount: tiles.count, width: width, textSize: dynamicTypeSize)
        return VStack(spacing: DrivySpacing.m) {
            LazyVGrid(columns: layout.gridItems, spacing: SchoolSignalGridLayout.spacing) {
                ForEach(tiles) { theme in
                    themeButton(theme)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            if theme.id == tiles.first?.id { tileHeight = height }
                        }
                }
            }
        }
    }

    private func themeButton(_ theme: SchoolLiveObservationTheme) -> some View {
        let isSelected = selected?.id == theme.id
        return Button {
            withAnimation(motion) { selected = theme }
            focusedStatus = SchoolObservationStatus.toWorkOn.rawValue
        } label: {
            SchoolSignalTileLabel(glyph: theme.glyph, title: theme.title, isSelected: isSelected)
        }
        .buttonStyle(SchoolObservationChoiceStyle())
        // Choisir un thème n’écrit rien : le choix reste possible pendant l’envoi du signalement précédent.
        .disabled(!recorder.acceptsSignal)
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("live-observation-theme-\(theme.title)")
    }

    private var appraisals: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: DrivySpacing.xxs) {
                    ForEach(statuses) { status in appraisalButton(status) }
                }
            } else {
                HStack(alignment: .top, spacing: DrivySpacing.xxs) {
                    ForEach(statuses) { status in appraisalButton(status) }
                }
            }
        }
    }

    private func appraisalButton(_ status: SchoolObservationStatus) -> some View {
        Button {
            guard let selected,
                  recorder.record(theme: selected, status: status, at: observedAt, anchor: anchor) else { return }
            recorded()
        } label: {
            SchoolAppraisalLabel(status: status, isVertical: !dynamicTypeSize.isAccessibilitySize)
        }
        .buttonStyle(SchoolObservationChoiceStyle(pressedFill: status.tone.background))
        .disabled(selected == nil || !recorder.canRecord)
        .opacity(selected == nil || writesWait ? 0.45 : 1)
        .animation(DrivyMotion.feedback(reduceMotion), value: writesWait)
        // The reserved choices are not actionable until a theme has been chosen.
        .accessibilityHidden(selected == nil)
        .accessibilityLabel(status.label)
        .accessibilityHint("Enregistre \(selected?.title ?? "cette observation")")
        .accessibilityIdentifier("live-observation-status-\(status.rawValue)")
        .accessibilityFocused($focusedStatus, equals: status.rawValue)
    }

    private func recorded() {
        isClosingAfterRecord = true
        onRecorded?()
        close()
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}

/// Même contenu avant et après la sélection : aucune appréciation n’est présélectionnée.
private struct SchoolAppraisalLabel: View {
    let status: SchoolObservationStatus
    let isVertical: Bool

    var body: some View {
        Group {
            if isVertical {
                VStack(spacing: DrivySpacing.xs) {
                    symbol
                    Text(status.label).font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: DrivySpacing.s) {
                    symbol
                    Text(status.label).font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .foregroundStyle(DrivyTheme.text)
        .padding(DrivySpacing.xs)
        .frame(maxWidth: .infinity, minHeight: isVertical ? 76 : 56)
        .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
    }

    private var symbol: some View {
        DrivyObservationGlyphImage(glyph: status.glyph)
            .foregroundStyle(status.tone.signal)
            .frame(width: 22, height: 22)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }
}

/// Retour tactile discret ; seul le thème sélectionné conserve un fond. Une appréciation pressée prend la teinte
/// de son état plutôt que le bleu de sélection.
private struct SchoolObservationChoiceStyle: ButtonStyle {
    var pressedFill: Color = DrivyTheme.accentSoft
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? pressedFill : .clear,
                        in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? DrivyPress.scale : 1)
            .animation(DrivyMotion.press(reduceMotion), value: configuration.isPressed)
    }
}
