import SwiftUI

/// Panneau de terrain : l’instant appartient au geste d’ouverture, jamais à l’animation.
struct SchoolLiveObservationSheet: View {
    @Bindable var recorder: SchoolLiveObservationRecorder
    let observedAt: Date
    var anchor: SchoolLiveObservationAnchor? = nil
    @State private var selected: SchoolLiveObservationTheme?
    @State private var saved = false
    @State private var savedStatus: SchoolObservationStatus?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var selectionFocused: Bool

    /// Changement de contexte provoqué par le doigt : ressort court, sans rebond marqué, interrompable
    /// (un nouvel appui reprend l’animation là où elle en est). Court, car le moniteur conduit et répète
    /// ce geste ; supprimé sous Réduire les animations.
    private var motion: Animation? { reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0.03) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: DrivySpacing.l) {
                    if saved {
                        savedFeedback.transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                    } else if let selected {
                        appraisal(for: selected).transition(.opacity)
                    } else {
                        themes.transition(.opacity)
                    }
                    if let error = recorder.errorMessage { SchoolErrorNotice(message: error) }
                }
                .padding(.horizontal, DrivySpacing.l)
                .padding(.top, DrivySpacing.s)
                .padding(.bottom, DrivySpacing.l)
                .frame(maxWidth: DrivyLayout.compactColumn)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(DrivyTheme.text)
        .background(DrivyTheme.surface)
        .tint(DrivyTheme.accent)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DrivyRadius.mapPanel + DrivySpacing.xs)
        .presentationBackground(DrivyTheme.surface)
        .interactiveDismissDisabled(saved)
        .sensoryFeedback(.selection, trigger: selected?.id)
        .sensoryFeedback(.success, trigger: saved)
        .task { await recorder.loadCompetencies() }
        .task(id: saved) {
            guard saved else { return }
            // `saved` n’est posé qu’après l’écriture locale durable (record / markMoment ont répondu vrai) :
            // la confirmation ne précède jamais l’enregistrement. Retour bref, sans étape en plus.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 250 : 420))
            dismiss()
        }
    }

    private var header: some View {
        HStack(spacing: DrivySpacing.s) {
            if selected != nil && !saved {
                roundControl("Revenir aux thèmes", symbol: "chevron.left") {
                    withAnimation(motion) { selected = nil }
                    selectionFocused = false
                }
                .accessibilityIdentifier("live-observation-back")
            }
            Text("Signaler")
                .font(.drivyTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DrivySpacing.s)
            roundControl("Annuler le signalement", symbol: "xmark") { dismiss() }
                .disabled(saved)
                .accessibilityIdentifier("live-observation-close")
        }
        .padding(.horizontal, DrivySpacing.l)
        .padding(.top, DrivySpacing.l)
        .padding(.bottom, DrivySpacing.s)
    }

    private func roundControl(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(DrivyMapGlyph.control)
                .foregroundStyle(DrivyTheme.muted)
                .frame(width: 48, height: 48)
                .background(DrivyTheme.surfaceMuted, in: Circle())
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
            // La largeur utile décide du nombre de colonnes. Les libellés gardent leur taille,
            // y compris dans une feuille étroite ou avec le texte agrandi.
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible())]
                      : [GridItem(.adaptive(minimum: dynamicTypeSize >= .xxLarge ? 144 : 96), spacing: DrivySpacing.xs)],
                      spacing: DrivySpacing.xs) {
                ForEach(recorder.themes) { theme in
                    Button {
                        withAnimation(motion) { selected = theme }
                        selectionFocused = true
                    } label: {
                        tileLabel(theme.title) { emblem(theme, size: 40) }
                    }
                    .buttonStyle(SchoolObservationChoiceStyle())
                    .disabled(!recorder.canRecord)
                    .accessibilityLabel(theme.title)
                    .accessibilityIdentifier("live-observation-theme-\(theme.title)")
                }
            }
            Divider().overlay(DrivyTheme.border)
            Button {
                if recorder.markMoment(at: observedAt, anchor: anchor) {
                    withAnimation(motion) { saved = true }
                }
            } label: {
                HStack(spacing: DrivySpacing.s) {
                    SchoolMarkerEmblem(size: 28)
                    Text("Marquer un moment").font(.subheadline.weight(.semibold))
                        .foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DrivySpacing.s)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(SchoolObservationChoiceStyle())
            .disabled(!recorder.canRecord)
            .accessibilityLabel("Marquer un moment")
            .accessibilityIdentifier("live-observation-marker")
            if let message = recorder.competenciesMessage {
                // Avertissement, pas une erreur : « Marquer un moment » reste disponible.
                DrivyInlineMessage(text: message, tone: .warning)
                Button("Réessayer", systemImage: "arrow.clockwise") { Task { await recorder.loadCompetencies() } }
                    .buttonStyle(DrivySecondaryButtonStyle())
            }
        }
    }

    /// Même commande et même instant quelle que soit la composition ; aucun texte réduit pour tenir.
    @ViewBuilder private func tileLabel<Emblem: View>(_ title: String,
                                                      @ViewBuilder emblem: () -> Emblem) -> some View {
        let mark = emblem()
        let shape = RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous)
        if dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: DrivySpacing.m) {
                mark
                Text(title).font(.headline).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(DrivySpacing.s)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .contentShape(shape)
        } else {
            VStack(spacing: DrivySpacing.xs) {
                mark
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 40, alignment: .top)
            }
            .padding(.vertical, DrivySpacing.s)
            .padding(.horizontal, DrivySpacing.xxs)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .top)
            .contentShape(shape)
        }
    }

    private func emblem(_ theme: SchoolLiveObservationTheme, size: CGFloat) -> some View {
        SchoolObservationEmblem(theme: theme, size: size)
    }

    private func appraisal(for theme: SchoolLiveObservationTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DrivySpacing.s) {
                emblem(theme, size: 32)
                Text(theme.title).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($selectionFocused)
            }
            .padding(.bottom, DrivySpacing.l)
            ForEach([SchoolObservationStatus.toWorkOn, .attention, .positive]) { status in
                appraisalButton(status, theme: theme)
                if status != .positive { Divider().overlay(DrivyTheme.border) }
            }
        }
    }

    private func appraisalButton(_ status: SchoolObservationStatus, theme: SchoolLiveObservationTheme) -> some View {
        SchoolAppraisalTile(status: status, tone: tone(status)) {
            guard recorder.record(theme: theme, status: status, at: observedAt, anchor: anchor) else { return }
            withAnimation(motion) { savedStatus = status; saved = true }
        }
        .disabled(!recorder.canRecord || saved)
    }

    /// This confirmation appears only after the encrypted local write succeeds.
    private var savedFeedback: some View {
        VStack(spacing: DrivySpacing.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(DrivyTheme.success)
                .accessibilityHidden(true)
            Text("Ajouté à la leçon").font(.headline)
            if let savedStatus {
                Text(savedStatus.label).font(.subheadline).foregroundStyle(tone(savedStatus).foreground)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DrivySpacing.xl)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(selected == nil ? "Moment ajouté à la leçon" : "Observation ajoutée à la leçon")
    }

    /// Même ton que `ObservationStatus.tone` (DrivyObservationStyle) : Attention, À retravailler, Point positif.
    private func tone(_ status: SchoolObservationStatus) -> DrivyTone {
        switch status { case .toWorkOn: .danger; case .attention: .warning; case .positive: .success }
    }
}

/// Trois choix explicites, chacun sur une rangée : symbole et mot portent l’état,
/// la couleur reste un repère secondaire. Aucun statut n’est présélectionné.
private struct SchoolAppraisalTile: View {
    let status: SchoolObservationStatus
    let tone: DrivyTone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DrivySpacing.m) {
                Image(systemName: status.symbol)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tone.foreground)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                Text(status.label)
                    .font(.headline)
                    .foregroundStyle(DrivyTheme.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DrivySpacing.s)
            .frame(maxWidth: .infinity, minHeight: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(SchoolObservationChoiceStyle())
        .accessibilityLabel(status.label)
        .accessibilityHint("Enregistre cette observation")
        .accessibilityIdentifier("live-observation-status-\(status.rawValue)")
    }
}

/// A visible touch response without giving every category a permanent card.
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
