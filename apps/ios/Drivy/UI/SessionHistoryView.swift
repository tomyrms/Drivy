import SwiftUI

struct SessionHistoryView: View {
    @Bindable var controller: SessionController

    private var sessions: [DrivingSession] {
        controller.sessions
            .filter { $0.state != .active }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        Group {
            if controller.isLoading {
                ProgressView("Ouverture des trajets…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessions.isEmpty, let error = controller.errorMessage {
                ContentUnavailableView {
                    Label("Historique indisponible", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    if !controller.isCapturing && !controller.isBusy {
                        DrivyRetryButton { Task { await controller.load() } }
                    }
                }
            } else if sessions.isEmpty {
                ContentUnavailableView {
                    Label("Aucun trajet terminé", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Terminez un trajet depuis Séance : il apparaîtra ici avec ses observations et votre bilan personnel.")
                }
            } else {
                List {
                    // Journeys whose bilan is still to write come first: the next useful gesture.
                    ownSection(title: "Bilan à écrire", sessions: ownSessions.filter { !JourneyStats(session: $0).hasSummary })
                    ownSection(title: "Bilan écrit", sessions: ownSessions.filter { JourneyStats(session: $0).hasSummary })
                    if !sessions.filter(\.isExample).isEmpty {
                        Section {
                            ForEach(sessions.filter(\.isExample)) { session in
                                NavigationLink(value: session.id) { JourneySummaryRow(session: session) }
                                    .accessibilityIdentifier("history-session-\(session.id.uuidString)")
                            }
                        } header: {
                            Text("Trajets d’exemple")
                        } footer: {
                            Text("Tracés, horaires et observations fictifs pour découvrir le replay.")
                        }
                    }
                    if let error = controller.errorMessage {
                        Section { InlineErrorView(message: error) }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(DrivyTheme.canvas)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DrivyTheme.canvas)
        .navigationTitle("Historique")
    }

    private var ownSessions: [DrivingSession] { sessions.filter { !$0.isExample } }

    @ViewBuilder
    private func ownSection(title: String, sessions: [DrivingSession]) -> some View {
        if !sessions.isEmpty {
            Section(title) {
                ForEach(sessions) { session in
                    NavigationLink(value: session.id) {
                        JourneySummaryRow(session: session)
                    }
                    .accessibilityIdentifier("history-session-\(session.id.uuidString)")
                }
            }
        }
    }
}

/// One journey in a list (history, home): date or title, duration, observations by
/// status, GPS mode, interruption and bilan state. Counts only, never a score.
struct JourneySummaryRow: View {
    let session: DrivingSession
    var showsChevron = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hasRoute: Bool { !session.points.isEmpty }
    private var stats: JourneyStats { JourneyStats(session: session) }

    var body: some View {
        HStack(alignment: .top, spacing: DrivySpacing.s) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: hasRoute ? "point.topleft.down.to.point.bottomright.curvepath" : session.usesGPS ? "location.slash" : "clock")
                    .font(.title3)
                    .foregroundStyle(hasRoute ? DrivyTheme.accent : DrivyTheme.muted)
                    .frame(width: 44, height: 44)
                    .background(hasRoute ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted,
                        in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                if let title = session.title {
                    Text(title).font(.headline).foregroundStyle(DrivyTheme.text)
                } else {
                    Text(session.startedAt, format: .dateTime.weekday(.abbreviated).day().month(.wide).hour().minute())
                        .font(.headline).foregroundStyle(DrivyTheme.text)
                }
                Text("\(DrivySeanceText.duration(stats.duration)) · \(DrivySeanceText.observations(stats.observationCount)) · \(session.isExample ? "Tracé fictif" : hasRoute ? "Avec GPS" : session.usesGPS ? "Aucune position" : "Sans GPS")")
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
                if stats.observationCount > 0 {
                    statusCounts
                }
                badges
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DrivyTheme.muted)
                    .frame(minHeight: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, DrivySpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    /// Symbol + count per status, only for the statuses present: a reminder, not a score.
    private var statusCounts: some View {
        HStack(spacing: DrivySpacing.s) {
            ForEach(ObservationStatus.allCases.filter { stats.count($0) > 0 }) { status in
                Label("\(stats.count(status)) \(status.label)", systemImage: status.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.color)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder private var badges: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xxs))
            : AnyLayout(HStackLayout(spacing: DrivySpacing.xs))
        layout {
            if session.isExample {
                DrivyStatusBadge(title: "Exemple fictif", symbol: "info.circle")
            } else if session.state == .interrupted {
                DrivyStatusBadge(title: "Interrompu · données conservées", symbol: "exclamationmark.triangle", tone: .warning)
            }
            DrivyStatusBadge(title: stats.hasSummary ? "Bilan écrit" : "Bilan à écrire",
                symbol: stats.hasSummary ? "checkmark.circle" : "square.and.pencil",
                tone: stats.hasSummary ? .success : .neutral)
        }
        .padding(.top, DrivySpacing.xxs)
    }
}

struct SummaryEditorView: View {
    @Bindable var controller: SessionController
    let sessionID: UUID
    let initialText: String
    let isExample: Bool
    let observations: [LessonObservation]
    let sessionStartedAt: Date?
    @State private var text: String
    @State private var saving = false
    @State private var confirmsDiscard = false
    @Environment(\.dismiss) private var dismiss

    init(controller: SessionController, sessionID: UUID, initialText: String, isExample: Bool = false,
         observations: [LessonObservation] = [], sessionStartedAt: Date? = nil) {
        self.controller = controller
        self.sessionID = sessionID
        self.initialText = initialText
        self.isExample = isExample
        self.observations = observations
        self.sessionStartedAt = sessionStartedAt
        _text = State(initialValue: initialText)
    }

    /// Plain lines the instructor may insert explicitly; nothing is added automatically.
    private var observationLines: String {
        observations.map { observation in
            let time = sessionStartedAt.map { observation.observedAt.sessionElapsed(since: $0) + " · " } ?? ""
            let note = observation.note.isEmpty ? "" : " — \(observation.note)"
            return "• \(time)\(observation.theme.label) : \(observation.status.label)\(note)"
        }.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    if isExample {
                        DrivyStatusBadge(title: "Bilan d’exemple · contenu fictif", symbol: "info.circle")
                    }
                    if !observations.isEmpty { observationReference }
                    Text("Notes du trajet")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    TextEditor(text: $text)
                        .frame(minHeight: 260)
                        .scrollContentBackground(.hidden)
                        .padding(DrivySpacing.s)
                        .background(DrivyTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
                        .accessibilityLabel("Texte du bilan personnel")
                        .accessibilityIdentifier("summary-text")
                        .disabled(saving)
                    if text.count > 10_000 {
                        Text("Limitez le bilan à 10 000 caractères pour l’enregistrer.")
                            .font(.footnote)
                            .foregroundStyle(DrivyTheme.danger)
                    }
                    if let error = controller.errorMessage {
                        InlineErrorView(message: error)
                    }
                    if saving {
                        ProgressView("Enregistrement du bilan…")
                    }
                    Label("Ce bilan reste sur cet appareil. Il n’est pas partagé avec l’école.", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .drivyPageContent(maxWidth: 680)
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Bilan personnel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        if text == initialText { dismiss() } else { confirmsDiscard = true }
                    }
                    .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(saving || text.count > 10_000)
                        .accessibilityIdentifier("save-summary")
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(saving || text != initialText)
        .confirmationDialog("Abandonner les modifications ?", isPresented: $confirmsDiscard) {
            Button("Abandonner les modifications", role: .destructive) { dismiss() }
            Button("Continuer la rédaction", role: .cancel) { }
        } message: {
            Text("Les modifications depuis l’ouverture de ce bilan ne sont pas enregistrées.")
        }
    }

    /// Observations of the journey as a reference while writing, with one explicit
    /// command to copy them into the text. The instructor keeps full control.
    private var observationReference: some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                Text("Observations du trajet")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(observations) { observation in
                    HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
                        Image(systemName: observation.status.symbol)
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(observation.status.color)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(observation.theme.label) · \(observation.status.label)")
                                .font(.subheadline.weight(.semibold))
                            if let sessionStartedAt {
                                Text(observation.observedAt.sessionElapsed(since: sessionStartedAt))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(DrivyTheme.muted)
                            }
                            if !observation.note.isEmpty {
                                Text(observation.note).font(.subheadline)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                Button {
                    let lines = observationLines
                    text = text.isEmpty ? lines : text + "\n\n" + lines
                } label: {
                    Label("Ajouter ces observations au texte", systemImage: "text.badge.plus")
                }
                .buttonStyle(DrivySecondaryButtonStyle())
                .disabled(saving)
                .accessibilityIdentifier("summary-insert-observations")
            }
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        Task {
            let saved = await controller.updateSummary(text, for: sessionID)
            saving = false
            if saved { dismiss() }
        }
    }
}
