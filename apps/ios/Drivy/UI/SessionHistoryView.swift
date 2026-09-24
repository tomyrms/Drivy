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
                ProgressView("Ouverture des séances…")
            } else if sessions.isEmpty {
                ContentUnavailableView {
                    Label("Vos séances, ici", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Retrouvez vos trajets, les moments importants et vos bilans après chaque séance.")
                }
            } else {
                List {
                    Section {
                        ForEach(sessions) { session in
                            NavigationLink(value: session.id) {
                                SessionHistoryRow(session: session)
                            }
                            .accessibilityIdentifier("history-session-\(session.id.uuidString)")
                        }
                    } header: {
                        Text("Sur cet appareil")
                    }
                    if let error = controller.errorMessage {
                        Section { InlineErrorView(message: error) }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DrivyTheme.canvas)
        .navigationTitle("Historique")
    }
}

private struct SessionHistoryRow: View {
    let session: DrivingSession

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: session.usesGPS ? "point.topleft.down.to.point.bottomright.curvepath" : "note.text")
                .font(.title3)
                .foregroundStyle(DrivyTheme.accent)
                .frame(width: 44, height: 44)
                .background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(session.startedAt, format: .dateTime.day().month(.wide).hour().minute())
                    .font(.headline)
                Text(session.state.label)
                    .font(.subheadline)
                    .foregroundStyle(session.state == .interrupted ? DrivyTheme.warning : DrivyTheme.muted)
                Text("\(session.observations.count) observation\(session.observations.count == 1 ? "" : "s") · \(session.usesGPS ? "Avec GPS" : "Sans GPS")")
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct SummaryEditorView: View {
    @Bindable var controller: SessionController
    let sessionID: UUID
    let initialText: String
    @State private var text: String
    @State private var saving = false
    @State private var confirmsDiscard = false
    @Environment(\.dismiss) private var dismiss

    init(controller: SessionController, sessionID: UUID, initialText: String) {
        self.controller = controller
        self.sessionID = sessionID
        self.initialText = initialText
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Votre bilan")
                        .font(.headline)
                    Text("Les points travaillés, ce que vous avez observé et la prochaine étape.")
                        .foregroundStyle(DrivyTheme.muted)
                    TextEditor(text: $text)
                        .frame(minHeight: 260)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("Texte du bilan local")
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
                        ProgressView("Enregistrement…")
                    }
                    Text("Enregistrement sur cet appareil uniquement.")
                        .font(.footnote)
                        .foregroundStyle(DrivyTheme.muted)
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.canvas)
            .navigationTitle("Bilan de la séance")
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
