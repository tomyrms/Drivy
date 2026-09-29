import SwiftUI

/// Panneau de terrain : l’instant appartient au geste d’ouverture, jamais à l’animation.
struct SchoolLiveObservationSheet: View {
    @Bindable var recorder: SchoolLiveObservationRecorder
    let observedAt: Date
    @State private var selected: SchoolLiveObservationTheme?
    @State private var saved = false
    @State private var savedStatus: SchoolObservationStatus?
    @Namespace private var emblems
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var selectionFocused: Bool

    /// Changement de contexte provoqué par le doigt : ressort court et interrompable (DrivyMotion),
    /// supprimé sous Réduire les animations où le fondu système suffit.
    private var motion: Animation? { DrivyMotion.context(reduceMotion) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: DrivySpacing.l) {
                    if saved {
                        savedFeedback.transition(.opacity)
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
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(DrivyTheme.text)
        .background(DrivyTheme.surface)
        .tint(DrivyTheme.accent)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(560), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DrivyRadius.mapPanel + DrivySpacing.xs)
        .presentationBackground(DrivyTheme.surface)
        .interactiveDismissDisabled(saved)
        .sensoryFeedback(.selection, trigger: selected?.id)
        .sensoryFeedback(.success, trigger: saved)
        .task { await recorder.loadCompetencies() }
        .task(id: saved) {
            guard saved else { return }
            // Retour bref après écriture chiffrée, aucune confirmation supplémentaire.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 280))
            dismiss()
        }
    }

    private var header: some View {
        HStack(spacing: DrivySpacing.s) {
            if selected != nil && !saved {
                roundControl("Revenir aux thèmes", symbol: "chevron.left") {
                    withAnimation(motion) { selected = nil }
                }
                .accessibilityIdentifier("live-observation-back")
            }
            Text("Signaler").font(.drivyTitle).accessibilityAddTraits(.isHeader)
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
                .font(.body.weight(.semibold))
                .foregroundStyle(DrivyTheme.muted)
                .frame(width: 48, height: 48)
                .background(DrivyTheme.surfaceMuted, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(DrivyTileButtonStyle())
        .accessibilityLabel(label)
    }

    private var themes: some View {
        VStack(spacing: DrivySpacing.l) {
            if recorder.isLoadingCompetencies { DrivyLoadingState(title: "Chargement des thèmes…") }
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible())]
                      : Array(repeating: GridItem(.flexible(), spacing: DrivySpacing.s), count: 3),
                      spacing: DrivySpacing.m) {
                ForEach(recorder.themes) { theme in
                    Button {
                        withAnimation(motion) { selected = theme }
                        selectionFocused = true
                    } label: {
                        themeChoice(theme)
                    }
                    .buttonStyle(DrivyTileButtonStyle())
                    .disabled(!recorder.canRecord)
                    .accessibilityLabel(theme.title)
                    .accessibilityIdentifier("live-observation-theme-\(theme.title)")
                }
            }
            if let message = recorder.competenciesMessage {
                // Avertissement, pas une erreur : « Marquer un moment » reste disponible.
                DrivyInlineMessage(text: message, tone: .warning)
                Button("Réessayer", systemImage: "arrow.clockwise") { Task { await recorder.loadCompetencies() } }
                    .buttonStyle(DrivySecondaryButtonStyle())
            }
            Button {
                if recorder.markMoment(at: observedAt) {
                    withAnimation(DrivyMotion.feedback(reduceMotion)) { saved = true }
                }
            } label: {
                Label("Marquer un moment", systemImage: "bookmark")
            }
            .buttonStyle(DrivySecondaryButtonStyle())
            .disabled(!recorder.canRecord)
            .accessibilityIdentifier("live-observation-marker")
        }
    }

    @ViewBuilder private func themeChoice(_ theme: SchoolLiveObservationTheme) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: DrivySpacing.m) {
                emblem(theme, size: 64)
                Text(theme.title).font(.headline).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.body.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
            }
            .padding(DrivySpacing.s)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .modifier(DrivyGroupedSurface(cornerRadius: DrivyRadius.content + DrivySpacing.xxs))
            .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content + DrivySpacing.xxs, style: .continuous))
        } else {
            VStack(spacing: DrivySpacing.xs) {
                emblem(theme, size: 68)
                Text(theme.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 38, alignment: .top)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .top)
            .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
        }
    }

    private func emblem(_ theme: SchoolLiveObservationTheme, size: CGFloat) -> some View {
        SchoolObservationEmblem(theme: theme, size: size)
            .matchedGeometryEffect(id: theme.id, in: emblems, properties: .frame)
    }

    private func appraisal(for theme: SchoolLiveObservationTheme) -> some View {
        VStack(spacing: DrivySpacing.xl) {
            VStack(spacing: DrivySpacing.m) {
                emblem(theme, size: 96)
                Text(theme.title).font(.drivyTitle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($selectionFocused)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DrivySpacing.s)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: DrivySpacing.s))
                : AnyLayout(HStackLayout(alignment: .top, spacing: DrivySpacing.s))
            layout {
                ForEach([SchoolObservationStatus.toWorkOn, .attention, .positive]) { status in
                    appraisalButton(status, theme: theme)
                }
            }
        }
    }

    private func appraisalButton(_ status: SchoolObservationStatus, theme: SchoolLiveObservationTheme) -> some View {
        let tone = tone(status)
        return Button {
            guard recorder.record(theme: theme, status: status, at: observedAt) else { return }
            withAnimation(DrivyMotion.feedback(reduceMotion)) { savedStatus = status; saved = true }
        } label: {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(HStackLayout(spacing: DrivySpacing.m))
                : AnyLayout(VStackLayout(spacing: DrivySpacing.s))
            layout {
                Image(systemName: status.symbol)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(tone.foreground)
                    .frame(width: 56, height: 56)
                    .background(tone.background, in: Circle())
                    .accessibilityHidden(true)
                Text(status.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.text)
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .top)
            }
            .padding(.vertical, DrivySpacing.m)
            .padding(.horizontal, DrivySpacing.xs)
            .frame(maxWidth: .infinity, minHeight: 112)
            // Filet et Contraste accru partagés : la tuile se détache aussi de la feuille en mode sombre.
            .modifier(DrivyGroupedSurface(cornerRadius: DrivyRadius.content + DrivySpacing.xxs))
            .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content + DrivySpacing.xxs, style: .continuous))
        }
        .buttonStyle(DrivyTileButtonStyle())
        .disabled(!recorder.canRecord || saved)
        .accessibilityLabel(status.label)
        .accessibilityIdentifier("live-observation-status-\(status.rawValue)")
    }

    private var savedFeedback: some View {
        VStack(spacing: DrivySpacing.m) {
            Image(systemName: "checkmark")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(DrivyTheme.success)
                .frame(width: 88, height: 88)
                .background(DrivyTheme.successSurface, in: Circle())
                .accessibilityHidden(true)
            Text(selected?.title ?? "Moment ajouté").font(.drivyTitle)
            if let savedStatus { Text(savedStatus.label).font(.headline).foregroundStyle(tone(savedStatus).foreground) }
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
