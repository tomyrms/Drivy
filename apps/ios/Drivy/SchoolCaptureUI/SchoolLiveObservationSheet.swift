import SwiftUI

/// La présentation native reste séparée de la palette posée sur la carte.
struct SchoolLiveObservationSheet: View {
    @Bindable var recorder: SchoolLiveObservationRecorder
    let observedAt: Date
    var anchor: SchoolLiveObservationAnchor? = nil
    var onRecorded: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        SchoolLiveObservationPalette(recorder: recorder, observedAt: observedAt, anchor: anchor, onRecorded: onRecorded)
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(DrivyMapLayout.reportPaletteHeight), .large])
            .presentationDragIndicator(.visible)
            .presentationSizing(.form)
            .presentationCornerRadius(DrivyRadius.mapPanel + DrivySpacing.xs)
            .presentationBackground(DrivyTheme.surface)
    }
}

/// L’instant et l’ancre appartiennent au geste d’ouverture, jamais au choix ou à l’animation.
/// Le conteneur choisit la hauteur ; la grille défile entre les commandes et les appréciations.
struct SchoolLiveObservationPalette: View {
    @Bindable var recorder: SchoolLiveObservationRecorder
    let observedAt: Date
    var anchor: SchoolLiveObservationAnchor? = nil
    var onRecorded: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    @State private var selected: SchoolLiveObservationTheme?
    /// Son propre enregistrement ferme la palette : elle ne change plus d’apparence pendant sa sortie.
    @State private var isClosingAfterRecord = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusedStatus: String?

    private var motion: Animation? { reduceMotion ? nil : .easeOut(duration: 0.16) }
    private let statuses: [SchoolObservationStatus] = [.toWorkOn, .attention, .positive]
    /// Une écriture attend : demande à vérifier, ou signalement précédent encore en cours d’envoi.
    private var writesWait: Bool { !recorder.canRecord && !isClosingAfterRecord }
    /// Cas bref de cette attente, nommé près des appréciations une fois le thème choisi.
    private var waitsForPreviousSignal: Bool { selected != nil && recorder.isSettlingGesture && !isClosingAfterRecord }

    var body: some View {
        ScrollViewReader { scroll in
            paletteContents
                .onChange(of: recorder.errorMessage) { _, error in
                    if error != nil { scroll.scrollTo("live-observation-error", anchor: .bottom) }
                }
        }
        .foregroundStyle(DrivyTheme.text)
        .background(DrivyTheme.surface)
        .tint(DrivyTheme.accent)
        .sensoryFeedback(.selection, trigger: selected?.id)
        .task { await recorder.loadCompetencies() }
    }

    @ViewBuilder private var paletteContents: some View {
        if verticalSizeClass == .compact {
            // Landscape can leave less room than the header and choices need together.
            ScrollView {
                VStack(spacing: 0) {
                    header
                    themeContent
                    appraisalBar
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            VStack(spacing: 0) {
                header
                ScrollView { themeContent }
                    .scrollBounceBehavior(.basedOnSize)
                appraisalBar
            }
        }
    }

    private var themeContent: some View {
        VStack(spacing: DrivySpacing.m) {
            themes
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
        .padding(.horizontal, DrivySpacing.s)
        .padding(.bottom, DrivySpacing.s)
    }

    private var appraisalBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(DrivyTheme.border)
            if waitsForPreviousSignal {
                DrivyLoadingState(title: "Envoi précédent en cours…")
                    .padding(.horizontal, DrivySpacing.m)
            }
            appraisals
                .padding(.horizontal, DrivySpacing.s)
                .padding(.vertical, DrivySpacing.xs)
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
                    .frame(width: 44, height: 44)
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
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(DrivyTileButtonStyle())
        .accessibilityLabel(label)
    }

    private var themes: some View {
        VStack(spacing: DrivySpacing.m) {
            if recorder.isLoadingCompetencies {
                DrivySkeletonRows(count: 3).drivySkeleton("Chargement des thèmes…")
            }
            LazyVGrid(columns: themeColumns, spacing: DrivySpacing.xxs) {
                ForEach(recorder.themes) { theme in themeButton(theme) }
            }
            if let message = recorder.competenciesMessage {
                // Le marqueur de l’en-tête reste disponible même sans référentiel.
                DrivyInlineMessage(text: message, tone: .warning)
                Button("Réessayer", systemImage: "arrow.clockwise") { Task { await recorder.loadCompetencies() } }
                    .buttonStyle(DrivySecondaryButtonStyle())
            }
        }
    }

    private var themeColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize { return [GridItem(.flexible())] }
        // Three columns still fit a 375 pt iPhone after the panel and content gutters.
        return [GridItem(.adaptive(minimum: dynamicTypeSize >= .xxLarge ? 148 : 100), spacing: DrivySpacing.xxs)]
    }

    private func themeButton(_ theme: SchoolLiveObservationTheme) -> some View {
        let isSelected = selected?.id == theme.id
        return Button {
            withAnimation(motion) { selected = theme }
            focusedStatus = SchoolObservationStatus.toWorkOn.rawValue
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: DrivySpacing.s) {
                        SchoolObservationEmblem(theme: theme, size: 32)
                        themeLabel(theme).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(spacing: DrivySpacing.xxs) {
                        SchoolObservationEmblem(theme: theme, size: 28)
                        themeLabel(theme).multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, DrivySpacing.xs)
            .padding(.vertical, DrivySpacing.xs)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(isSelected ? DrivyTheme.accentSoft : .clear,
                        in: RoundedRectangle(cornerRadius: DrivyRadius.field))
            .overlay {
                RoundedRectangle(cornerRadius: DrivyRadius.field)
                    .strokeBorder(isSelected ? DrivyTheme.accent : .clear, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.field))
        }
        .buttonStyle(SchoolObservationChoiceStyle())
        // Choisir un thème n’écrit rien : le choix reste possible pendant l’envoi du signalement précédent.
        .disabled(!recorder.acceptsSignal)
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("live-observation-theme-\(theme.title)")
    }

    private func themeLabel(_ theme: SchoolLiveObservationTheme) -> some View {
        Text(theme.title)
            .font(dynamicTypeSize.isAccessibilitySize ? .body.weight(.semibold) : .footnote.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
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
            SchoolAppraisalLabel(status: status, tone: tone(status), isVertical: !dynamicTypeSize.isAccessibilitySize)
        }
        .buttonStyle(SchoolObservationChoiceStyle())
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

    private func tone(_ status: SchoolObservationStatus) -> DrivyTone {
        switch status { case .toWorkOn: .danger; case .attention: .warning; case .positive: .success }
    }
}

/// Même contenu avant et après la sélection : aucune appréciation n’est présélectionnée.
private struct SchoolAppraisalLabel: View {
    let status: SchoolObservationStatus
    let tone: DrivyTone
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
        .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.field))
    }

    private var symbol: some View {
        Image(systemName: status.symbol)
            .font(DrivyMapGlyph.observation)
            .foregroundStyle(tone.foreground)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }
}

/// Retour tactile discret ; seul le thème sélectionné conserve un fond.
private struct SchoolObservationChoiceStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DrivyTheme.accentSoft : .clear,
                        in: RoundedRectangle(cornerRadius: DrivyRadius.field))
            .scaleEffect(configuration.isPressed && !reduceMotion ? DrivyPress.scale : 1)
            .animation(DrivyMotion.press(reduceMotion), value: configuration.isPressed)
    }
}
