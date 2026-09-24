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
    @State private var confirmsStop = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            contextTime
                            Text("· Sur cet appareil")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            contextTime
                            Text("Sur cet appareil")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)

                    if let theme = selectedTheme {
                        statusChoices(for: theme)
                    } else {
                        categoryChoices
                    }
                    if let error = controller.errorMessage {
                        InlineErrorView(message: error)
                    }
                }
                .padding(20)
                .frame(maxWidth: 580)
                .frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.surface)
            .navigationTitle(selectedTheme?.label ?? "Signaler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedTheme != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            selectedTheme = nil
                        } label: {
                            Label("Catégories", systemImage: "chevron.left")
                        }
                        .disabled(saving)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer", systemImage: "xmark") {
                        if note.isEmpty { dismiss() } else { confirmsDiscard = true }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(saving)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Arrêter la séance", role: .destructive) { confirmsStop = true }
                        .frame(minHeight: 48)
                        .disabled(!controller.isCapturing)
                }
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving || !note.isEmpty)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selectedTheme)
        .confirmationDialog("Abandonner cette note ?", isPresented: $confirmsDiscard) {
            Button("Abandonner la note", role: .destructive) { dismiss() }
            Button("Continuer la saisie", role: .cancel) { }
        } message: {
            Text("Cette observation n’a pas encore été enregistrée.")
        }
        .confirmationDialog("Terminer cette séance ?", isPresented: $confirmsStop, titleVisibility: .visible) {
            Button("Terminer la séance", role: .destructive) {
                controller.stopSession()
                dismiss()
            }
            Button("Continuer la saisie", role: .cancel) { }
        } message: {
            Text("La capture s’arrêtera. L’observation ouverte n’est pas enregistrée et sera abandonnée.")
        }
    }

    private var contextTime: some View {
        Label(context.observedAt.sessionElapsed(since: sessionStartedAt), systemImage: context.anchorPointID == nil ? "clock" : "mappin")
            .monospacedDigit()
    }

    private var categoryChoices: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 240 : 130), spacing: 12)],
            spacing: 16
        ) {
            ForEach(ObservationTheme.allCases) { theme in
                Button { selectedTheme = theme } label: {
                    VStack(spacing: 12) {
                        Image(systemName: theme.symbol)
                            .font(.title2)
                            .frame(width: 52, height: 52)
                            .background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 18))
                        Text(theme.label)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(DrivyTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(theme == .priority ? "category-priorities" : "category-\(theme.rawValue)")
            }
        }
    }

    private func statusChoices(for theme: ObservationTheme) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            DisclosureGroup(isExpanded: $showsNote) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Un détail à retrouver au bilan", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(12)
                        .background(DrivyTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Note facultative")
                        .accessibilityIdentifier("observation-note")
                        .disabled(saving)
                    if note.count > 1_000 {
                        Text("Limitez la note à 1 000 caractères pour l’enregistrer.")
                            .font(.footnote)
                            .foregroundStyle(DrivyTheme.danger)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label(note.isEmpty ? "Ajouter une note" : "Note saisie", systemImage: "note.text")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("observation-note-disclosure")

            ForEach(ObservationStatus.allCases) { status in
                Button { save(theme: theme, status: status) } label: {
                    HStack(spacing: 16) {
                        Image(systemName: status.symbol)
                            .font(.headline)
                            .foregroundStyle(status.color)
                            .frame(width: 36, height: 36)
                            .background(DrivyTheme.surfaceMuted, in: Circle())
                        Text(status.label)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DrivyTheme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(saving || !controller.isCapturing || note.count > 1_000)
                .accessibilityHint("Enregistre l’observation sur cet appareil")
                .accessibilityIdentifier("status-\(status.rawValue)")
                if status != ObservationStatus.allCases.last { Divider() }
            }
            if saving {
                ProgressView("Enregistrement…")
            } else if !controller.isCapturing {
                Text("La séance est arrêtée. Cette note n’est pas enregistrée ; vous pouvez la copier avant de fermer.")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.warning)
            } else {
                Text("Choisir un statut enregistre l’observation.")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.muted)
            }
        }
    }

    private func save(theme: ObservationTheme, status: ObservationStatus) {
        guard !saving else { return }
        saving = true
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
