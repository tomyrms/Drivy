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
                    if !sessions.filter({ !$0.isExample }).isEmpty {
                        Section("Sur cet appareil") {
                            ForEach(sessions.filter { !$0.isExample }) { session in
                                NavigationLink(value: session.id) {
                                    SessionHistoryRow(session: session)
                                }
                                .accessibilityIdentifier("history-session-\(session.id.uuidString)")
                            }
                        }
                    }
                    if !sessions.filter(\.isExample).isEmpty {
                        Section {
                            ForEach(sessions.filter(\.isExample)) { session in
                                NavigationLink(value: session.id) { SessionHistoryRow(session: session) }
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
}

private struct SessionHistoryRow: View {
    let session: DrivingSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hasRoute: Bool { session.usesGPS || !session.points.isEmpty }

    var body: some View {
        HStack(alignment: .center, spacing: DrivySpacing.s) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: hasRoute ? "point.topleft.down.to.point.bottomright.curvepath" : "note.text")
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
                Text("\(DrivySeanceText.observations(session.observations.count)) · \(session.isExample ? "Replay" : session.usesGPS ? "Avec GPS" : "Sans GPS")")
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
                if session.isExample {
                    DrivyStatusBadge(title: "Exemple fictif", symbol: "info.circle")
                } else if session.state == .interrupted {
                    DrivyStatusBadge(title: session.state.label, symbol: "exclamationmark.triangle", tone: .warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DrivySpacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

struct SummaryEditorView: View {
    @Bindable var controller: SessionController
    let sessionID: UUID
    let initialText: String
    let isExample: Bool
    @State private var text: String
    @State private var saving = false
    @State private var confirmsDiscard = false
    @Environment(\.dismiss) private var dismiss

    init(controller: SessionController, sessionID: UUID, initialText: String, isExample: Bool = false) {
        self.controller = controller
        self.sessionID = sessionID
        self.initialText = initialText
        self.isExample = isExample
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    if isExample {
                        DrivyStatusBadge(title: "Bilan d’exemple · contenu fictif", symbol: "info.circle")
                    }
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
