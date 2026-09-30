import SwiftUI

/// Panneau de terrain : l’instant appartient au geste d’ouverture, jamais à l’animation.
struct SchoolLiveObservationSheet: View {
    @Bindable var recorder: SchoolLiveObservationRecorder
    let observedAt: Date
    var anchor: SchoolLiveObservationAnchor? = nil
    @State private var selected: SchoolLiveObservationTheme?
    @State private var saved = false
    @State private var savedStatus: SchoolObservationStatus?
    @State private var confirmationPop = false
    @Namespace private var emblems
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
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(584), .large])
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
            // Grille de tuiles égales, sans orpheline : « Marquer un moment » est la dernière tuile, au même
            // rang que les thèmes (même cible, même geste), et tout tient dans la feuille sans défiler.
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible())]
                      : Array(repeating: GridItem(.flexible(), spacing: DrivySpacing.s), count: 3),
                      spacing: DrivySpacing.s) {
                ForEach(recorder.themes) { theme in
                    Button {
                        withAnimation(motion) { selected = theme }
                        selectionFocused = true
                    } label: {
                        tileLabel(theme.title) { emblem(theme, size: 64) }
                    }
                    .buttonStyle(DrivyTileButtonStyle())
                    .disabled(!recorder.canRecord)
                    .accessibilityLabel(theme.title)
                    .accessibilityIdentifier("live-observation-theme-\(theme.title)")
                }
                Button {
                    if recorder.markMoment(at: observedAt, anchor: anchor) {
                        withAnimation(motion) { saved = true }
                    }
                } label: {
                    tileLabel("Marquer un moment") { SchoolMarkerEmblem(size: 64) }
                }
                .buttonStyle(DrivyTileButtonStyle())
                .disabled(!recorder.canRecord)
                .accessibilityLabel("Marquer un moment")
                .accessibilityIdentifier("live-observation-marker")
            }
            if let message = recorder.competenciesMessage {
                // Avertissement, pas une erreur : « Marquer un moment » reste disponible.
                DrivyInlineMessage(text: message, tone: .warning)
                Button("Réessayer", systemImage: "arrow.clockwise") { Task { await recorder.loadCompetencies() } }
                    .buttonStyle(DrivySecondaryButtonStyle())
            }
        }
    }

    /// Tuile pleine : le choix se lit comme un bouton, et la cible dépasse largement 44 pt. Un mot long
    /// (« Stationnement ») se réduit un peu plutôt que de se couper en deux.
    @ViewBuilder private func tileLabel<Emblem: View>(_ title: String,
                                                      @ViewBuilder emblem: () -> Emblem) -> some View {
        let mark = emblem()
        let shape = RoundedRectangle(cornerRadius: DrivyRadius.content + DrivySpacing.xxs, style: .continuous)
        if dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: DrivySpacing.m) {
                mark
                Text(title).font(.headline).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.body.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
            }
            .padding(DrivySpacing.s)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .modifier(DrivyGroupedSurface(cornerRadius: DrivyRadius.content + DrivySpacing.xxs))
            .contentShape(shape)
        } else {
            VStack(spacing: DrivySpacing.xs) {
                mark
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 38, alignment: .top)
            }
            .padding(.vertical, DrivySpacing.s)
            .padding(.horizontal, DrivySpacing.xxs)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .top)
            .modifier(DrivyGroupedSurface(cornerRadius: DrivyRadius.content + DrivySpacing.xxs))
            .contentShape(shape)
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
        SchoolAppraisalTile(status: status, tone: tone(status)) {
            guard recorder.record(theme: theme, status: status, at: observedAt, anchor: anchor) else { return }
            withAnimation(motion) { savedStatus = status; saved = true }
        }
        .disabled(!recorder.canRecord || saved)
    }

    /// Confirmation brève, à la couleur de l’appréciation choisie : le pictogramme rebondit une fois,
    /// le sceau vert dit « enregistré », puis la feuille se ferme d’elle-même.
    private var savedFeedback: some View {
        let savedTone: DrivyTone = savedStatus.map(tone) ?? .accent
        return VStack(spacing: DrivySpacing.m) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: savedStatus?.symbol ?? "bookmark.fill")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(savedTone.foreground)
                    .frame(width: 96, height: 96)
                    .background(savedTone.background, in: Circle())
                    .overlay { Circle().strokeBorder(savedTone.foreground.opacity(0.45), lineWidth: 1) }
                    .symbolEffect(.bounce, options: .nonRepeating, value: confirmationPop)
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(DrivyTheme.successSurface)
                    .frame(width: 32, height: 32)
                    .background(DrivyTheme.success, in: Circle())
                    .overlay { Circle().strokeBorder(DrivyTheme.surface, lineWidth: 3) }
            }
            .accessibilityHidden(true)
            Text(selected?.title ?? "Moment ajouté").font(.drivyTitle)
                .multilineTextAlignment(.center)
            if let savedStatus { Text(savedStatus.label).font(.headline).foregroundStyle(tone(savedStatus).foreground) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DrivySpacing.xl)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(selected == nil ? "Moment ajouté à la leçon" : "Observation ajoutée à la leçon")
        .task { if !reduceMotion { confirmationPop = true } }
    }

    /// Même ton que `ObservationStatus.tone` (DrivyObservationStyle) : Attention, À retravailler, Point positif.
    private func tone(_ status: SchoolObservationStatus) -> DrivyTone {
        switch status { case .toWorkOn: .danger; case .attention: .warning; case .positive: .success }
    }
}

/// Tuile d’appréciation : aplat de la teinte de l’état, pastille pleine et libellé en gras, pour se lire
/// d’un coup d’œil en plein soleil comme de nuit. L’état n’est jamais porté par la seule couleur :
/// symbole et mot sont toujours présents. Aucune animation d’entrée propre : le geste se répète des dizaines
/// de fois par leçon, seuls l’appui (DrivyTileButtonStyle) et le passage de l’écran précédent bougent.
private struct SchoolAppraisalTile: View {
    let status: SchoolObservationStatus
    let tone: DrivyTone
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let shape = RoundedRectangle(cornerRadius: DrivyRadius.content + DrivySpacing.xxs, style: .continuous)
        let badge: CGFloat = stacked ? 64 : 76
        Button(action: action) {
            let layout = stacked
                ? AnyLayout(HStackLayout(spacing: DrivySpacing.m))
                : AnyLayout(VStackLayout(spacing: DrivySpacing.s))
            layout {
                Image(systemName: status.symbol)
                    .font(.title.weight(.heavy))
                    .foregroundStyle(tone.background)
                    .frame(width: badge, height: badge)
                    .background(tone.foreground, in: Circle())
                    .accessibilityHidden(true)
                Text(status.label)
                    .font(.headline)
                    .foregroundStyle(DrivyTheme.text)
                    .multilineTextAlignment(stacked ? .leading : .center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: stacked ? .leading : .top)
            }
            .padding(.vertical, DrivySpacing.m)
            .padding(.horizontal, DrivySpacing.xs)
            .frame(maxWidth: .infinity, minHeight: stacked ? 96 : 168)
            .background(tone.background, in: shape)
            .overlay { shape.strokeBorder(tone.foreground.opacity(contrast == .increased ? 1 : 0.45), lineWidth: contrast == .increased ? 2 : 1) }
            .contentShape(shape)
        }
        .buttonStyle(DrivyTileButtonStyle())
        .accessibilityLabel(status.label)
        .accessibilityIdentifier("live-observation-status-\(status.rawValue)")
    }
}
