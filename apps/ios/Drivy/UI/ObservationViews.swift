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
}

struct ObservationRow: View {
    let observation: LessonObservation
    let sessionStartedAt: Date
    var showsNote = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: observation.status.symbol)
                .font(.headline)
                .frame(width: 36, height: 36)
                .foregroundStyle(observation.status.color)
                .background(DrivyTheme.surfaceMuted, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(observation.theme.label)
                    .font(.headline)
                    .foregroundStyle(DrivyTheme.text)
                Text(observation.status.label)
                    .font(.subheadline)
                    .foregroundStyle(observation.status.color)
                if showsNote && !observation.note.isEmpty {
                    Text(observation.note)
                        .font(.body)
                        .foregroundStyle(DrivyTheme.text)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        elapsedLabel
                        Text("·")
                        positionLabel
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        elapsedLabel
                        positionLabel
                    }
                }
                .font(.caption)
                .foregroundStyle(DrivyTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
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
        Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 2 : 3)
    }
    var body: some View {
        VStack(spacing: 0) {
            sheetHeading
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let theme = selectedTheme { statusChoices(for: theme) }
                    else { categoryChoices }
                    if !controller.isCapturing && !saving {
                        Text(note.isEmpty
                             ? "Le trajet est arrêté. Ce signalement n’est pas enregistré."
                             : "Le trajet est arrêté. Ce signalement n’est pas enregistré ; vous pouvez copier la note avant de fermer.")
                            .font(.footnote).foregroundStyle(DrivyTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = controller.errorMessage { InlineErrorView(message: error) }
                }
                .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }
        .background(DrivyTheme.surface)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selectedTheme)
        .presentationDetents([.height(440), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
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
        HStack(alignment: .center, spacing: 8) {
            if selectedTheme != nil {
                Button { selectedTheme = nil; noteFocused = false } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                }.buttonStyle(.plain).disabled(saving).accessibilityLabel("Catégories")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedTheme?.label ?? "Signaler").font(.title3.weight(.bold))
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
                Image(systemName: "xmark").font(.body.weight(.medium))
                    .frame(width: 44, height: 44).background(DrivyTheme.surfaceMuted, in: Circle())
            }.buttonStyle(.plain).disabled(saving).accessibilityLabel("Fermer le signalement")
        }
        .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 18)
        .foregroundStyle(DrivyTheme.text)
    }

    private var categoryChoices: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: columns, alignment: .center, spacing: 14) {
                ForEach(ObservationTheme.allCases) { theme in
                    Button { selectedTheme = theme } label: {
                        VStack(spacing: 11) {
                            Image(systemName: theme.journeySymbol).font(.title2.weight(.regular))
                                .foregroundStyle(DrivyTheme.accent).frame(width: 52, height: 52)
                                .background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 17))
                            Text(theme.label).font(.caption.weight(.semibold))
                                .foregroundStyle(DrivyTheme.text).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100, alignment: .top)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier(theme == .priority ? "category-priorities" : "category-\(theme.rawValue)")
                }
            }
        }
    }

    private func statusChoices(for theme: ObservationTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if note.count > 1_000 {
                Text("Raccourcissez la note à 1 000 caractères avant de choisir un statut.")
                    .font(.footnote).foregroundStyle(DrivyTheme.danger).padding(.bottom, 12)
            }
            ForEach(ObservationStatus.allCases) { status in
                Button { save(theme: theme, status: status) } label: {
                    HStack(spacing: 16) {
                        Image(systemName: status.symbol).font(.body.weight(.medium))
                            .foregroundStyle(status.color).frame(width: 38, height: 38)
                            .background(status.color.opacity(0.10), in: Circle())
                        Text(status.label).font(.body.weight(.semibold)).foregroundStyle(DrivyTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 72).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .disabled(saving || !controller.isCapturing || note.count > 1_000)
                    .accessibilityHint("Enregistre l’observation sur cet appareil")
                    .accessibilityIdentifier("status-\(status.rawValue)")
                if status != ObservationStatus.allCases.last { Divider().padding(.leading, 54) }
            }
            if saving { ProgressView("Enregistrement…").frame(maxWidth: .infinity).padding(.top, 12) }
            else if controller.isCapturing {
                Text("Le choix enregistre.").font(.caption).foregroundStyle(DrivyTheme.muted)
                    .frame(maxWidth: .infinity).padding(.top, 12)
            }
            DisclosureGroup(isExpanded: $showsNote) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Un détail à retrouver au bilan", text: $note, axis: .vertical)
                        .lineLimit(3...6).focused($noteFocused).padding(14)
                        .background(DrivyTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Note facultative").accessibilityIdentifier("observation-note").disabled(saving)
                    if note.count >= 900 {
                        Text("\(note.count) / 1 000 caractères")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(note.count > 1_000 ? DrivyTheme.danger : DrivyTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }.padding(.top, 8)
            } label: {
                Label(note.isEmpty ? "Ajouter une note" : "Modifier la note", systemImage: "note.text")
                    .font(.subheadline).frame(minHeight: 44)
            }.padding(.top, 12).accessibilityIdentifier("observation-note-disclosure")
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
                            Label("Observations d’exemple · données fictives", systemImage: "info.circle")
                                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        }
                    }
                    ForEach(session.observations.sorted { $0.observedAt < $1.observedAt }) { observation in
                        ObservationRow(observation: observation, sessionStartedAt: session.startedAt)
                    }
                }
            }
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
