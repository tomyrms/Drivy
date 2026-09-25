import SwiftUI

extension ObservationStatus {
    var symbol: String {
        switch self {
        case .attention: "exclamationmark"
        case .toWorkOn: "xmark"
        case .positive: "checkmark"
        }
    }

    var color: Color { tone.foreground }
    var surface: Color { tone.background }

    /// Status tone: always paired with the status symbol and label.
    var tone: DrivyTone {
        switch self {
        case .attention: .warning
        case .toWorkOn: .danger
        case .positive: .success
        }
    }
}

extension ObservationTheme {
    var journeySymbol: String {
        switch self {
        case .priority: "arrow.triangle.branch"
        case .parking: "parkingsign"
        case .signs: "signpost.right"
        case .roundabout: "arrow.trianglehead.2.clockwise.rotate.90"
        case .observation: "eye"
        case .anticipation: "arrow.up.forward"
        }
    }
}

extension LessonObservation {
    /// « Priorité à droite, Attention, 12:34, sans position » for VoiceOver.
    func spokenDescription(sessionStartedAt: Date) -> String {
        var parts = [theme.label, status.label, observedAt.sessionElapsed(since: sessionStartedAt)]
        parts.append(anchorPointID == nil ? "sans position" : "sur le trajet")
        if !note.isEmpty { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}

/// Large tactile tile for the reporting bubble: immediate spring feedback,
/// removed under Reduce Motion. Selection itself is announced by haptics.
struct DrivyTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(DrivyMotion.press(reduceMotion), value: configuration.isPressed)
    }
}

/// Theme pictogram on the status surface, with the status symbol as a badge:
/// the status never relies on color alone.
struct ObservationGlyph: View {
    let observation: LessonObservation
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: observation.theme.journeySymbol)
            .font(.headline)
            .foregroundStyle(observation.status.color)
            .frame(width: size, height: size)
            .background(observation.status.surface, in: Circle())
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: observation.status.symbol)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(DrivyTheme.surface)
                    .frame(width: 16, height: 16)
                    .background(observation.status.color, in: Circle())
                    .offset(x: 2, y: 2)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityHidden(true)
    }
}

struct ObservationRow: View {
    let observation: LessonObservation
    let sessionStartedAt: Date
    var showsNote = true

    var body: some View {
        HStack(alignment: .top, spacing: DrivySpacing.s) {
            ObservationGlyph(observation: observation)
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(observation.theme.label)
                    .font(.headline)
                    .foregroundStyle(DrivyTheme.text)
                Label(observation.status.label, systemImage: observation.status.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(observation.status.color)
                if showsNote && !observation.note.isEmpty {
                    Text(observation.note)
                        .font(.body)
                        .foregroundStyle(DrivyTheme.text)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DrivySpacing.xxs) {
                        elapsedLabel
                        Text("·").accessibilityHidden(true)
                        positionLabel
                    }
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        elapsedLabel
                        positionLabel
                    }
                }
                .font(.caption)
                .foregroundStyle(DrivyTheme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DrivySpacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(observation.spokenDescription(sessionStartedAt: sessionStartedAt))
    }

    private var elapsedLabel: some View {
        Text(observation.observedAt.sessionElapsed(since: sessionStartedAt))
            .monospacedDigit()
    }

    private var positionLabel: some View {
        Label(observation.anchorPointID == nil ? "Sans position" : "Sur le trajet",
              systemImage: observation.anchorPointID == nil ? "clock" : "mappin")
    }
}

/// Compact capsule of the replay rail: time, theme pictogram, status symbol.
/// Selection uses the shared selection look (accent soft + accent border).
struct ObservationChip: View {
    let observation: LessonObservation
    let sessionStartedAt: Date
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DrivySpacing.xs) {
                Image(systemName: observation.status.symbol)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(DrivyTheme.surface)
                    .frame(width: 20, height: 20)
                    .background(observation.status.color, in: Circle())
                    .accessibilityHidden(true)
                Image(systemName: observation.theme.journeySymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.text)
                    .accessibilityHidden(true)
                Text(observation.observedAt.sessionElapsed(since: sessionStartedAt))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DrivyTheme.text)
            }
            .padding(.horizontal, DrivySpacing.s)
            .frame(minHeight: 44)
            .background(isSelected ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted, in: Capsule())
            .overlay { Capsule().strokeBorder(isSelected ? DrivyTheme.accent : DrivyTheme.border, lineWidth: isSelected ? 1.5 : 0.5) }
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(DrivyTileButtonStyle())
        .accessibilityLabel(observation.spokenDescription(sessionStartedAt: sessionStartedAt))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Revoir ce passage")
    }
}

/// « 2 Attention · 1 À retravailler · 1 Point positif »: counts only, never a score.
struct ObservationStatusSummary: View {
    let count: (ObservationStatus) -> Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(spacing: DrivySpacing.xs))
        layout {
            ForEach(ObservationStatus.allCases) { status in
                HStack(spacing: DrivySpacing.xxs) {
                    Image(systemName: status.symbol)
                        .font(.caption.weight(.heavy))
                        .accessibilityHidden(true)
                    Text("\(count(status))").monospacedDigit()
                    Text(status.label)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status.color)
                .padding(.horizontal, DrivySpacing.xs)
                .padding(.vertical, DrivySpacing.xxs)
                .background(status.surface, in: Capsule())
                .fixedSize()
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The reporting bubble (E23): Signaler froze the instant; a theme then an explicit
/// status confirm. Opening, resizing or closing the bubble records nothing.
struct ObservationComposer: View {
    @Bindable var controller: SessionController
    let context: ObservationContext
    let sessionStartedAt: Date
    var onSaved: ((LessonObservation) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTheme: ObservationTheme?
    @State private var note = ""
    @State private var showsNote = false
    @State private var saving = false
    @State private var confirmsDiscard = false
    @State private var detent: PresentationDetent = .medium
    @FocusState private var noteFocused: Bool
    @AccessibilityFocusState private var focusedStep: Step?

    private enum Step: Hashable { case categories, statuses }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DrivySpacing.s), count: dynamicTypeSize.isAccessibilitySize ? 2 : 3)
    }
    private var stepTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .trailing).combined(with: .opacity)
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeading
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    if let theme = selectedTheme {
                        statusChoices(for: theme).transition(stepTransition)
                    } else {
                        categoryChoices.transition(stepTransition)
                    }
                    if !controller.isCapturing && !saving {
                        DrivyInlineMessage(
                            text: note.isEmpty
                                ? "Le trajet est arrêté. Ce signalement n’est pas enregistré."
                                : "Le trajet est arrêté. Ce signalement n’est pas enregistré ; vous pouvez copier la note avant de fermer.",
                            tone: .warning)
                    }
                    if let error = controller.errorMessage { InlineErrorView(message: error) }
                }
                .padding(.horizontal, DrivySpacing.l).padding(.top, DrivySpacing.xxs).padding(.bottom, DrivySpacing.l)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(DrivyTheme.surface)
        .animation(DrivyMotion.context(reduceMotion), value: selectedTheme)
        .sensoryFeedback(.selection, trigger: selectedTheme)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving || !note.isEmpty)
        .onAppear { if dynamicTypeSize.isAccessibilitySize { detent = .large } }
        .onChange(of: dynamicTypeSize) { _, size in if size.isAccessibilitySize { detent = .large } }
        .onChange(of: showsNote) { _, value in
            if value { detent = .large; noteFocused = controller.isCapturing }
        }
        .onChange(of: selectedTheme) { _, theme in
            focusedStep = theme == nil ? .categories : .statuses
        }
        .onChange(of: controller.isCapturing) { _, isCapturing in
            if !isCapturing {
                noteFocused = false
                detent = .large
                if !note.isEmpty { showsNote = true }
            }
        }
        .confirmationDialog("Abandonner cette note ?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Abandonner la note", role: .destructive) { dismiss() }
            Button("Continuer la saisie", role: .cancel) { }
        } message: { Text("Cette observation n’a pas encore été enregistrée.") }
    }

    private var sheetHeading: some View {
        HStack(alignment: .center, spacing: DrivySpacing.xs) {
            if selectedTheme != nil {
                Button { selectedTheme = nil; noteFocused = false } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        .foregroundStyle(DrivyTheme.text)
                        .frame(width: 48, height: 48).background(DrivyTheme.surfaceMuted, in: Circle())
                        .contentShape(Circle())
                }.buttonStyle(.plain).disabled(saving).accessibilityLabel("Revenir aux catégories")
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(selectedTheme?.label ?? "Signaler").font(.drivyTitle)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusedStep, equals: selectedTheme == nil ? .categories : .statuses)
                Label("\(context.observedAt.sessionElapsed(since: sessionStartedAt)) · \(context.anchorPointID == nil ? "Sans position" : "Sur le trajet") · Privé",
                      systemImage: context.anchorPointID == nil ? "clock" : "mappin")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Instant retenu \(context.observedAt.sessionElapsed(since: sessionStartedAt)), \(context.anchorPointID == nil ? "sans position" : "sur le trajet"), privé")
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if note.isEmpty { dismiss() } else { confirmsDiscard = true }
            } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold))
                    .foregroundStyle(DrivyTheme.text)
                    .frame(width: 48, height: 48).background(DrivyTheme.surfaceMuted, in: Circle())
                    .contentShape(Circle())
            }.buttonStyle(.plain).disabled(saving).accessibilityLabel("Fermer sans ajouter d’observation")
        }
        .padding(.horizontal, DrivySpacing.l).padding(.top, DrivySpacing.l).padding(.bottom, DrivySpacing.s)
    }

    private var categoryChoices: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: DrivySpacing.s) {
            ForEach(ObservationTheme.allCases) { theme in
                Button { selectedTheme = theme } label: {
                    VStack(spacing: DrivySpacing.xs) {
                        Image(systemName: theme.journeySymbol).font(.title2.weight(.semibold))
                            .foregroundStyle(DrivyTheme.accent).frame(width: 56, height: 56)
                            .background(DrivyTheme.accentSoft, in: Circle())
                            .accessibilityHidden(true)
                        Text(theme.label).font(.subheadline.weight(.semibold))
                            .foregroundStyle(DrivyTheme.text).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, DrivySpacing.s).padding(.horizontal, DrivySpacing.xxs)
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .top)
                    .background(DrivyTheme.canvas, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous)
                            .strokeBorder(DrivyTheme.border, lineWidth: 0.5)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                }
                .buttonStyle(DrivyTileButtonStyle())
                .disabled(saving || !controller.isCapturing)
                .accessibilityHint("Choisir ensuite le statut")
                .accessibilityIdentifier(theme == .priority ? "category-priorities" : "category-\(theme.rawValue)")
            }
        }
    }

    private func statusChoices(for theme: ObservationTheme) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            Text(saving ? "Enregistrement sur cet appareil…" : "Le choix enregistre.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.muted)
            if note.count > 1_000 {
                Text("Raccourcissez la note à 1 000 caractères avant de choisir un statut.")
                    .font(.footnote).foregroundStyle(DrivyTheme.danger)
            }
            ForEach(ObservationStatus.allCases) { status in
                Button { save(theme: theme, status: status) } label: {
                    HStack(spacing: DrivySpacing.s) {
                        Image(systemName: status.symbol).font(.title3.weight(.heavy))
                            .foregroundStyle(status.color).frame(width: 44, height: 44)
                            .background(DrivyTheme.surface, in: Circle())
                            .accessibilityHidden(true)
                        Text(status.label).font(.title3.weight(.semibold)).foregroundStyle(DrivyTheme.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DrivySpacing.m).padding(.vertical, DrivySpacing.xs)
                    .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                    .background(status.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                }
                .buttonStyle(DrivyTileButtonStyle())
                .disabled(saving || !controller.isCapturing || note.count > 1_000)
                .accessibilityHint("Enregistre l’observation sur cet appareil")
                .accessibilityIdentifier("status-\(status.rawValue)")
            }
            if saving { ProgressView().frame(maxWidth: .infinity).accessibilityHidden(true) }
            DisclosureGroup(isExpanded: $showsNote) {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    TextField("Un détail à retrouver au bilan", text: $note, axis: .vertical)
                        .lineLimit(3...6).focused($noteFocused).padding(DrivySpacing.s)
                        .background(DrivyTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
                        .accessibilityLabel("Note facultative").accessibilityIdentifier("observation-note").disabled(saving)
                    Text("Facultatif. Choisissez ensuite le statut pour enregistrer.")
                        .font(.caption).foregroundStyle(DrivyTheme.muted)
                    if note.count >= 900 {
                        Text("\(note.count) / 1 000 caractères")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(note.count > 1_000 ? DrivyTheme.danger : DrivyTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }.padding(.top, DrivySpacing.xs)
            } label: {
                Label(note.isEmpty ? "Ajouter une note (à l’arrêt)" : "Modifier la note", systemImage: "note.text")
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
            .padding(.top, DrivySpacing.xs)
            .accessibilityIdentifier("observation-note-disclosure")
        }
    }

    private func save(theme: ObservationTheme, status: ObservationStatus) {
        guard !saving else { return }
        noteFocused = false
        saving = true
        let observation = LessonObservation(id: context.id, observedAt: context.observedAt, theme: theme,
            status: status, note: note, anchorPointID: context.anchorPointID)
        Task {
            let saved = await controller.addObservation(theme: theme, status: status, note: note, context: context)
            saving = false
            if saved {
                onSaved?(observation)
                dismiss()
            }
        }
    }
}

/// Private observations of the journey being recorded, newest first: the last
/// report is the one the instructor wants to check.
struct ObservationListView: View {
    let session: DrivingSession
    @Environment(\.dismiss) private var dismiss

    private var stats: JourneyStats { JourneyStats(session: session) }

    var body: some View {
        NavigationStack {
            List {
                if session.observations.isEmpty {
                    ContentUnavailableView("Aucune observation", systemImage: "text.bubble",
                        description: Text("Touchez « Signaler » pendant le trajet. Chaque observation garde son heure, même sans GPS."))
                } else {
                    Section {
                        ObservationStatusSummary(count: stats.count)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: DrivySpacing.xs, leading: 0, bottom: DrivySpacing.xs, trailing: 0))
                    } footer: {
                        Text(session.isExample
                             ? "Exemple · données fictives."
                             : "Privées, sur cet appareil. Vous pourrez les revoir dans le replay et les reprendre dans le bilan.")
                    }
                    Section("Du plus récent au plus ancien") {
                        ForEach(session.observations.sorted { $0.observedAt > $1.observedAt }) { observation in
                            ObservationRow(observation: observation, sessionStartedAt: session.startedAt)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .navigationTitle(DrivySeanceText.observations(session.observations.count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
