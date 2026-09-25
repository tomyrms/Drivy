import SwiftUI

extension ObservationStatus {
    var symbol: String {
        switch self {
        case .attention: "exclamationmark"
        case .toWorkOn: "xmark"
        case .positive: "checkmark"
        }
    }

    var color: Color {
        switch self {
        case .attention: DrivyTheme.warning
        case .toWorkOn: DrivyTheme.danger
        case .positive: DrivyTheme.success
        }
    }

    var surface: Color {
        switch self {
        case .attention: DrivyTheme.warningSurface
        case .toWorkOn: DrivyTheme.dangerSurface
        case .positive: DrivyTheme.successSurface
        }
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

struct ObservationRow: View {
    let observation: LessonObservation
    let sessionStartedAt: Date
    var showsNote = true

    var body: some View {
        HStack(alignment: .top, spacing: DrivySpacing.s) {
            Image(systemName: observation.theme.journeySymbol)
                .font(.headline)
                .frame(width: 36, height: 36)
                .foregroundStyle(observation.status.color)
                .background(observation.status.surface, in: Circle())
                .accessibilityHidden(true)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DrivySpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var elapsedLabel: some View {
        Text(observation.observedAt.sessionElapsed(since: sessionStartedAt))
            .monospacedDigit()
    }

    private var positionLabel: some View {
        Text(observation.anchorPointID == nil ? "Sans position" : "Sur le trajet")
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

struct ObservationComposer: View {
    @Bindable var controller: SessionController
    let context: ObservationContext
    let sessionStartedAt: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTheme: ObservationTheme?
    @State private var note = ""
    @State private var showsNote = false
    @State private var saving = false
    @State private var confirmsDiscard = false
    @State private var detent: PresentationDetent = .height(440)
    @FocusState private var noteFocused: Bool
    @AccessibilityFocusState private var focusedStep: Step?

    private enum Step: Hashable { case categories, statuses }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DrivySpacing.s), count: dynamicTypeSize.isAccessibilitySize ? 2 : 3)
    }
    var body: some View {
        VStack(spacing: 0) {
            sheetHeading
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    if let theme = selectedTheme { statusChoices(for: theme) }
                    else { categoryChoices }
                    if !controller.isCapturing && !saving {
                        DrivyInlineMessage(
                            text: note.isEmpty
                                ? "Le trajet est arrêté. Ce signalement n’est pas enregistré."
                                : "Le trajet est arrêté. Ce signalement n’est pas enregistré ; vous pouvez copier la note avant de fermer.",
                            tone: .warning)
                    }
                    if let error = controller.errorMessage { InlineErrorView(message: error) }
                }
                .padding(.horizontal, DrivySpacing.l).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.l)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }
        .background(DrivyTheme.surface)
        .animation(DrivyMotion.context(reduceMotion), value: selectedTheme)
        .sensoryFeedback(.selection, trigger: selectedTheme)
        .presentationDetents([.height(440), .large], selection: $detent)
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
                        .frame(width: 44, height: 44).background(DrivyTheme.surfaceMuted, in: Circle())
                        .contentShape(Circle())
                }.buttonStyle(.plain).disabled(saving).accessibilityLabel("Revenir aux catégories")
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(selectedTheme?.label ?? "Signaler").font(.drivySection)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusedStep, equals: selectedTheme == nil ? .categories : .statuses)
                Label("\(context.observedAt.sessionElapsed(since: sessionStartedAt)) · Privé · \(context.anchorPointID == nil ? "Sans position" : "Sur le trajet")",
                      systemImage: context.anchorPointID == nil ? "clock" : "mappin")
                    .font(.caption).foregroundStyle(DrivyTheme.muted).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if note.isEmpty { dismiss() } else { confirmsDiscard = true }
            } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold))
                    .frame(width: 44, height: 44).background(DrivyTheme.surfaceMuted, in: Circle())
                    .contentShape(Circle())
            }.buttonStyle(.plain).disabled(saving).accessibilityLabel("Fermer sans ajouter d’observation")
        }
        .padding(.horizontal, DrivySpacing.l).padding(.top, DrivySpacing.l).padding(.bottom, DrivySpacing.m)
        .foregroundStyle(DrivyTheme.text)
    }

    private var categoryChoices: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            LazyVGrid(columns: columns, alignment: .center, spacing: DrivySpacing.s) {
                ForEach(ObservationTheme.allCases) { theme in
                    Button { selectedTheme = theme } label: {
                        VStack(spacing: DrivySpacing.xs) {
                            Image(systemName: theme.journeySymbol).font(.title.weight(.medium))
                                .foregroundStyle(DrivyTheme.accent).frame(width: 64, height: 64)
                                .background(DrivyTheme.accentSoft, in: Circle())
                            Text(theme.label).font(.subheadline.weight(.semibold))
                                .foregroundStyle(DrivyTheme.text).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 108, alignment: .top)
                        .contentShape(Rectangle())
                    }.buttonStyle(DrivyTileButtonStyle())
                        .accessibilityIdentifier(theme == .priority ? "category-priorities" : "category-\(theme.rawValue)")
                }
            }
        }
    }

    private func statusChoices(for theme: ObservationTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if note.count > 1_000 {
                Text("Raccourcissez la note à 1 000 caractères avant de choisir un statut.")
                    .font(.footnote).foregroundStyle(DrivyTheme.danger).padding(.bottom, DrivySpacing.s)
            }
            let statusLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: DrivySpacing.s))
                : AnyLayout(HStackLayout(alignment: .top, spacing: DrivySpacing.s))
            statusLayout {
                ForEach(ObservationStatus.allCases) { status in
                    Button { save(theme: theme, status: status) } label: {
                        VStack(spacing: DrivySpacing.xs) {
                            Image(systemName: status.symbol).font(.drivyTitle)
                                .foregroundStyle(status.color).frame(width: 52, height: 52)
                                .background(DrivyTheme.surface, in: Circle())
                            Text(status.label).font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.text)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, DrivySpacing.m).padding(.horizontal, DrivySpacing.xs)
                        .frame(maxWidth: .infinity, minHeight: 128)
                        .background(status.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                    }.buttonStyle(DrivyTileButtonStyle())
                        .disabled(saving || !controller.isCapturing || note.count > 1_000)
                        .accessibilityHint("Enregistre l’observation sur cet appareil")
                        .accessibilityIdentifier("status-\(status.rawValue)")
                }
            }
            if saving { ProgressView("Enregistrement de l’observation…").frame(maxWidth: .infinity).padding(.top, DrivySpacing.s) }
            else if controller.isCapturing {
                Text("Un appui sur le statut enregistre l’observation.").font(.caption).foregroundStyle(DrivyTheme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.top, DrivySpacing.s)
            }
            DisclosureGroup(isExpanded: $showsNote) {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    TextField("Un détail à retrouver au bilan", text: $note, axis: .vertical)
                        .lineLimit(3...6).focused($noteFocused).padding(DrivySpacing.s)
                        .background(DrivyTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
                        .accessibilityLabel("Note facultative").accessibilityIdentifier("observation-note").disabled(saving)
                    if note.count >= 900 {
                        Text("\(note.count) / 1 000 caractères")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(note.count > 1_000 ? DrivyTheme.danger : DrivyTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }.padding(.top, DrivySpacing.xs)
            } label: {
                Label(note.isEmpty ? "Ajouter une note" : "Modifier la note", systemImage: "note.text")
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }.padding(.top, DrivySpacing.s).accessibilityIdentifier("observation-note-disclosure")
        }
    }
    private func save(theme: ObservationTheme, status: ObservationStatus) {
        guard !saving else { return }
        noteFocused = false; saving = true
        Task {
            let saved = await controller.addObservation(theme: theme, status: status, note: note, context: context)
            saving = false
            if saved { dismiss() }
        }
    }
}
struct ObservationListView: View {
    let session: DrivingSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if session.observations.isEmpty {
                    ContentUnavailableView("Aucune observation", systemImage: "text.bubble", description: Text("Les observations enregistrées apparaîtront ici, même sans GPS."))
                } else {
                    if session.isExample {
                        Section {
                            DrivyStatusBadge(title: "Exemple · données fictives", symbol: "info.circle")
                        }
                    }
                    ForEach(session.observations.sorted { $0.observedAt < $1.observedAt }) { observation in
                        ObservationRow(observation: observation, sessionStartedAt: session.startedAt)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .navigationTitle("Observations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
