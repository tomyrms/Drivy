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
                Text("Observations : \(session.observations.count) · \(session.usesGPS ? "Avec GPS" : "Sans GPS")")
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct SessionDetailView: View {
    @Bindable var controller: SessionController
    let sessionID: UUID
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var selectedObservationID: UUID?
    @State private var replayOffset = 0.0
    @State private var isPlaying = false
    @State private var playbackSpeed = 1.0
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSummaryEditor = false
    @State private var confirmsDelete = false
    @State private var deleting = false

    private var session: DrivingSession? {
        if let selected = controller.selectedSession, selected.id == sessionID { return selected }
        return controller.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        Group {
            if let session {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        sessionHeading(session)
                        if !session.points.isEmpty {
                            replay(session)
                        } else {
                            DrivyPanel {
                                Label(session.usesGPS ? "Aucun trajet enregistré" : "Séance sans GPS", systemImage: "location.slash")
                                    .foregroundStyle(DrivyTheme.muted)
                            }
                        }
                        observations(session)
                        summary(session)
                        StorageCaption(message: controller.storageStatus)
                        if let error = controller.errorMessage {
                            InlineErrorView(message: error)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView("Séance indisponible", systemImage: "doc.questionmark", description: Text("Cette séance ne peut pas être ouverte pour le moment."))
            }
        }
        .background(DrivyTheme.canvas)
        .navigationTitle("Relire la séance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmsDelete = true
                } label: {
                    Label("Supprimer la séance", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .disabled(deleting || session == nil)
                .accessibilityIdentifier("delete-session")
            }
        }
        .confirmationDialog("Supprimer cette séance ?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Supprimer la séance", role: .destructive) {
                Task {
                    deleting = true
                    let deleted = await controller.deleteSession(sessionID)
                    deleting = false
                    if deleted { dismiss() }
                }
            }
            .accessibilityIdentifier("delete-session-confirm")
            Button("Conserver la séance", role: .cancel) { }
        } message: {
            Text("Le trajet, les observations et le bilan de cet essai seront supprimés de cet appareil. Cette action est définitive.")
        }
        .task { await controller.selectSession(sessionID) }
        .task(id: isPlaying) { await playReplay() }
        .onDisappear { isPlaying = false }
        .onChange(of: scenePhase) { _, phase in if phase != .active { isPlaying = false } }
        .sheet(isPresented: $showsSummaryEditor) {
            if let session {
                SummaryEditorView(controller: controller, sessionID: session.id, initialText: session.summary)
            }
        }
    }

    private func sessionHeading(_ session: DrivingSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.startedAt, format: .dateTime.day().month(.wide).year())
                .font(.title2.weight(.bold))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text(session.state.label)
                    Text(session.startedAt, format: .dateTime.hour().minute())
                    if let endedAt = session.endedAt {
                        Text(endedAt.sessionElapsed(since: session.startedAt)).monospacedDigit()
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.state.label)
                    Text(session.startedAt, format: .dateTime.hour().minute())
                }
            }
            .font(.subheadline)
            .foregroundStyle(DrivyTheme.muted)
            if session.state == .interrupted {
                Label("La séance a été interrompue. Seules les données enregistrées sont présentées.", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.warning)
            }
        }
    }

    private func replay(_ session: DrivingSession) -> some View {
        let duration = max(1, (session.endedAt ?? session.points.last?.timestamp ?? session.startedAt).timeIntervalSince(session.startedAt))
        let date = session.startedAt.addingTimeInterval(min(replayOffset, duration))
        let position = session.points.last { $0.timestamp <= date && date.timeIntervalSince($0.timestamp) <= 15 }
        return VStack(alignment: .leading, spacing: 0) {
            RouteMapView(session: session, selectedObservationID: $selectedObservationID, replayDate: date)
                .frame(height: sizeClass == .regular ? 400 : 300)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Replay")
                        .font(.headline)
                    Spacer()
                    Text(date.sessionElapsed(since: session.startedAt))
                        .monospacedDigit()
                        .font(.subheadline.weight(.medium))
                }
                Slider(value: $replayOffset, in: 0...duration, onEditingChanged: { editing in if editing { isPlaying = false } })
                    .accessibilityLabel("Instant du trajet")
                    .accessibilityValue(date.sessionElapsed(since: session.startedAt))
                    .accessibilityIdentifier("replay-timeline")
                HStack(spacing: 12) {
                    Button { jumpObservation(in: session, forward: false) } label: {
                        Image(systemName: "backward.end.fill").frame(width: 48, height: 48)
                    }.accessibilityLabel("Observation précédente").disabled(session.observations.isEmpty)
                    Spacer(minLength: 0)
                    Button {
                        if replayOffset >= duration { replayOffset = 0 }
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3).frame(width: 56, height: 56)
                            .foregroundStyle(DrivyTheme.onAccent)
                            .background(DrivyTheme.accent, in: Circle())
                    }.accessibilityLabel(isPlaying ? "Mettre le replay en pause" : "Lire le replay")
                    Spacer(minLength: 0)
                    Button { jumpObservation(in: session, forward: true) } label: {
                        Image(systemName: "forward.end.fill").frame(width: 48, height: 48)
                    }.accessibilityLabel("Observation suivante").disabled(session.observations.isEmpty)
                    Button { playbackSpeed = playbackSpeed == 1 ? 2 : playbackSpeed == 2 ? 4 : 1 } label: {
                        Text("×\(Int(playbackSpeed))").font(.subheadline.weight(.semibold)).frame(width: 44, height: 48)
                    }.accessibilityLabel("Vitesse du replay : \(Int(playbackSpeed)) fois")
                }.buttonStyle(.plain).foregroundStyle(DrivyTheme.accent)
                Group {
                    if let position {
                        Text("Dernière position : \(position.timestamp.sessionElapsed(since: session.startedAt)).")
                    } else {
                        Text("Aucune position disponible à cet instant.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(DrivyTheme.muted)
            }
            .padding(16)
            .background(DrivyTheme.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onChange(of: selectedObservationID) { _, id in
            if let observation = session.observations.first(where: { $0.id == id }) {
                isPlaying = false
                replayOffset = max(0, observation.observedAt.timeIntervalSince(session.startedAt))
            }
        }
    }

    @MainActor private func playReplay() async {
        guard isPlaying, let session else { return }
        let duration = max(1, (session.endedAt ?? session.points.last?.timestamp ?? session.startedAt).timeIntervalSince(session.startedAt))
        var previous = ContinuousClock.now
        while isPlaying && !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard isPlaying, !Task.isCancelled else { return }
            let now = ContinuousClock.now
            let elapsed = previous.duration(to: now).components
            previous = now
            replayOffset = min(duration, replayOffset + (Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) * playbackSpeed)
            if replayOffset >= duration { isPlaying = false }
        }
    }

    private func jumpObservation(in session: DrivingSession, forward: Bool) {
        isPlaying = false
        let ordered = session.observations.sorted { $0.observedAt < $1.observedAt }
        let target = forward
            ? ordered.first { $0.observedAt.timeIntervalSince(session.startedAt) > replayOffset + 0.1 }
            : ordered.last { $0.observedAt.timeIntervalSince(session.startedAt) < replayOffset - 0.1 }
        if let target {
            selectedObservationID = target.id
            replayOffset = max(0, target.observedAt.timeIntervalSince(session.startedAt))
        }
    }

    private func observations(_ session: DrivingSession) -> some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Observations")
                    .font(.title3.weight(.semibold))
                if session.observations.isEmpty {
                    Text("Aucune observation enregistrée pendant cette séance.")
                        .foregroundStyle(DrivyTheme.muted)
                } else {
                    ForEach(session.observations.sorted { $0.observedAt < $1.observedAt }) { observation in
                        Button {
                            isPlaying = false
                            selectedObservationID = observation.id
                            replayOffset = max(0, observation.observedAt.timeIntervalSince(session.startedAt))
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                ObservationRow(observation: observation, sessionStartedAt: session.startedAt)
                                if selectedObservationID == observation.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(DrivyTheme.accent)
                                        .padding(.top, 16)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedObservationID == observation.id ? [.isSelected] : [])
                        .accessibilityHint(observation.anchorPointID == nil ? "Sélectionner cette observation sans position" : "Revoir ce moment sur le trajet")
                        if observation.id != session.observations.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func summary(_ session: DrivingSession) -> some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: 16) {
                Label("Bilan de la séance", systemImage: "note.text")
                    .font(.title3.weight(.semibold))
                if session.summary.isEmpty {
                    Text("Ce que vous retenez de la séance et ce que vous souhaitez retravailler.")
                        .foregroundStyle(DrivyTheme.muted)
                } else {
                    Text(session.summary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("saved-summary")
                }
                Button { showsSummaryEditor = true } label: {
                    Label(session.summary.isEmpty ? "Rédiger le bilan" : "Modifier le bilan", systemImage: "square.and.pencil")
                }
                .buttonStyle(DrivySecondaryButtonStyle())
                .accessibilityIdentifier("edit-summary")
                Text("Ce bilan reste sur cet appareil. Il n’est pas publié.")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.muted)
            }
        }
    }
}

private struct SummaryEditorView: View {
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
            .navigationTitle("Bilan local")
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
