import SwiftUI

/// A map first replay of the points and observations actually saved on this device.
struct SessionDetailView: View {
    @Bindable var controller: SessionController
    let sessionID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedObservationID: UUID?
    @State private var replayOffset = 0.0
    @State private var isPlaying = false
    @State private var playbackSpeed = 1.0
    @State private var sheet: ReplaySheet?
    @State private var confirmsDelete = false
    @State private var deleting = false
    @State private var resetCameraID = UUID()
    @State private var followsPosition = false

    private enum ReplaySheet: String, Identifiable {
        case observations, summary, information
        var id: String { rawValue }
    }

    private var session: DrivingSession? {
        if let selected = controller.selectedSession, selected.id == sessionID { return selected }
        return controller.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        Group {
            if let session {
                GeometryReader { geometry in
                    if dynamicTypeSize.isAccessibilitySize {
                        accessibleReplay(session)
                    } else if geometry.size.width >= 760 {
                        wideReplay(session)
                    } else {
                        compactReplay(session)
                    }
                }
            } else {
                ContentUnavailableView("Trajet indisponible", systemImage: "doc.questionmark", description: Text(controller.errorMessage ?? "Ce trajet ne peut pas être ouvert pour le moment."))
                    .safeAreaInset(edge: .top) { closeButton.padding(DrivySpacing.m).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        .background(DrivyTheme.canvas)
        .foregroundStyle(DrivyTheme.text)
        .toolbar(.hidden, for: .navigationBar)
        .tint(DrivyTheme.accent)
        .confirmationDialog("Supprimer ce trajet ?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Supprimer le trajet", role: .destructive) {
                Task {
                    isPlaying = false
                    deleting = true
                    let deleted = await controller.deleteSession(sessionID)
                    deleting = false
                    if deleted { dismiss() }
                }
            }
            .accessibilityIdentifier("delete-session-confirm")
            Button("Conserver le trajet", role: .cancel) { }
        } message: {
            Text("Le trajet, les observations et le bilan seront supprimés de cet appareil. Cette action est définitive.")
        }
        .task { await controller.selectSession(sessionID) }
        .task(id: isPlaying) { await playReplay() }
        .onDisappear { isPlaying = false }
        .onChange(of: scenePhase) { _, phase in if phase != .active { isPlaying = false } }
        .onChange(of: selectedObservationID) { _, id in
            if let session, let observation = session.observations.first(where: { $0.id == id }) {
                seek(to: observation, in: session)
            }
        }
        .sheet(item: $sheet) { destination in
            if let session {
                switch destination {
                case .observations:
                    observationSheet(session)
                case .summary:
                    SummaryEditorView(controller: controller, sessionID: session.id, initialText: session.summary, isExample: session.isExample)
                case .information:
                    informationSheet(session)
                }
            }
        }
    }

    private func compactReplay(_ session: DrivingSession) -> some View {
        replayBackground(session)
            .safeAreaInset(edge: .top, spacing: 0) {
                replayHeader(session)
                    .padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.s)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .trailing, spacing: DrivySpacing.s) {
                    if !session.points.isEmpty { mapControls(session) }
                    replayDock(session)
                }
                .padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.s)
            }
    }

    private func wideReplay(_ session: DrivingSession) -> some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    replayHeader(session, floating: false)
                    replayDock(session, floating: false)
                    if !session.observations.isEmpty {
                        DrivySectionHeader(title: "Observations").padding(.top, DrivySpacing.xs)
                        observationsPreview(session)
                    }
                }
                .padding(DrivySpacing.m)
            }
            .frame(width: DrivyMapLayout.sidebarWidth)
            .background(DrivyTheme.canvas)
            replayBackground(session)
                .overlay(alignment: .bottomTrailing) {
                    if !session.points.isEmpty { mapControls(session).padding(DrivySpacing.l) }
                }
        }
    }

    private func accessibleReplay(_ session: DrivingSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                replayHeader(session, floating: false)
                replayBackground(session)
                    .frame(height: DrivyMapLayout.accessibleMapHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
                if !session.points.isEmpty { mapControls(session).frame(maxWidth: .infinity, alignment: .trailing) }
                replayDock(session, floating: false)
                if !session.observations.isEmpty {
                    DrivySectionHeader(title: "Observations")
                    observationsPreview(session)
                }
            }
            .padding(DrivySpacing.m)
            .frame(maxWidth: DrivyMapLayout.accessibleMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func replayBackground(_ session: DrivingSession) -> some View {
        if session.points.isEmpty {
            DrivyMapPlaceholder(
                title: session.usesGPS ? "Aucune position enregistrée" : "Trajet sans GPS",
                message: session.observations.isEmpty
                    ? "Aucune observation n’a été ajoutée pendant ce trajet."
                    : "Retrouvez les observations dans la chronologie, avec leur heure.")
        } else {
            RouteMapView(
                session: session,
                selectedObservationID: $selectedObservationID,
                replayDate: replayDate(session),
                showsControls: false,
                showsEmptyState: false,
                resetCameraID: resetCameraID,
                followsPosition: $followsPosition,
                showsOriginBadge: false
            )
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(DrivyTheme.text)
                .frame(width: 44, height: 44)
                .background(DrivyTheme.surfaceMuted, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retour à l’historique")
    }

    private func replayStatus(_ session: DrivingSession) -> DrivyMapStatus {
        if session.isExample { return DrivyMapStatus(title: "Exemple · données fictives", symbol: "info.circle") }
        let day = session.startedAt.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_CH")))
        if session.state == .interrupted {
            return DrivyMapStatus(title: "Privé · \(day) · interrompu", symbol: "exclamationmark.triangle", tone: .warning)
        }
        return DrivyMapStatus(title: "Privé · \(day)", symbol: "lock")
    }

    private func replayHeader(_ session: DrivingSession, floating: Bool = true) -> some View {
        DrivyMapHeader(
            title: session.title ?? "Replay",
            status: replayStatus(session),
            leading: .back(label: "Retour à l’historique") { dismiss() },
            floating: floating
        ) {
            Button { isPlaying = false; sheet = .summary } label: {
                Label("Bilan", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.accent)
                    .padding(.horizontal, DrivySpacing.s)
                    .frame(minHeight: 44)
                    .background(DrivyTheme.accentSoft, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ouvrir le bilan personnel")
            .accessibilityIdentifier("edit-summary")
            Menu {
                Button { isPlaying = false; sheet = .information } label: {
                    Label("Détails du trajet", systemImage: "info.circle")
                }
                Divider()
                Button(role: .destructive) { isPlaying = false; confirmsDelete = true } label: {
                    Label("Supprimer le trajet", systemImage: "trash")
                }
                .disabled(deleting)
                .accessibilityIdentifier("delete-session")
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DrivyTheme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Options du replay")
        }
    }

    private func mapControls(_ session: DrivingSession) -> some View {
        DrivyMapControls(followsPosition: $followsPosition,
            followLabel: "Suivre la position du replay",
            canFollow: currentPoint(session) != nil) {
            followsPosition = false
            resetCameraID = UUID()
        }
    }

    private func replayDock(_ session: DrivingSession, floating: Bool = true) -> some View {
        DrivyMapDock(floating: floating) {
            selectedMoment(session)
            if !session.points.isEmpty || !session.observations.isEmpty {
                timeline(session)
                transportControls(session)
            }
            if let error = controller.errorMessage { InlineErrorView(message: error) }
        }
    }

    /// The observation under the playhead, or the entry to the list: always one
    /// clear subject in the dock (LECON.html « observation sélectionnée »).
    @ViewBuilder
    private func selectedMoment(_ session: DrivingSession) -> some View {
        let selected = session.observations.first { $0.id == selectedObservationID }
        if session.observations.isEmpty {
            Label("Aucune observation pendant ce trajet", systemImage: "list.bullet")
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.muted)
                .frame(minHeight: 44, alignment: .leading)
        } else {
            Button {
                isPlaying = false
                sheet = .observations
            } label: {
                HStack(alignment: .center, spacing: DrivySpacing.s) {
                    Image(systemName: selected?.theme.journeySymbol ?? "list.bullet")
                        .font(.title3)
                        .foregroundStyle(selected?.status.color ?? DrivyTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(selected?.status.surface ?? DrivyTheme.accentSoft, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(selected?.theme.label ?? DrivySeanceText.observations(session.observations.count))
                            .font(.headline)
                            .foregroundStyle(DrivyTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let selected {
                            HStack(spacing: DrivySpacing.xxs) {
                                Text(selected.status.label).foregroundStyle(selected.status.color)
                                Text("·").accessibilityHidden(true)
                                Text(selected.observedAt.sessionElapsed(since: session.startedAt)).monospacedDigit()
                                Image(systemName: "lock").imageScale(.small).accessibilityHidden(true)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DrivyTheme.muted)
                            if !selected.note.isEmpty {
                                Text(selected.note).font(.subheadline).foregroundStyle(DrivyTheme.text)
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text("Choisissez une observation pour revoir ce passage")
                                .font(.caption)
                                .foregroundStyle(DrivyTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DrivyTheme.muted)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(DrivyRowButtonStyle())
            .accessibilityLabel(selected.map { "\($0.theme.label), \($0.status.label), \($0.observedAt.sessionElapsed(since: session.startedAt))" } ?? DrivySeanceText.observations(session.observations.count))
            .accessibilityValue(selected?.note ?? "")
            .accessibilityHint("Ouvrir les observations du trajet")
        }
    }

    private func timeline(_ session: DrivingSession) -> some View {
        VStack(spacing: DrivySpacing.xxs) {
            Slider(value: $replayOffset, in: 0...duration(session), onEditingChanged: { editing in
                if editing { isPlaying = false; selectedObservationID = nil }
            })
            .accessibilityLabel("Instant du trajet")
            .accessibilityValue("\(replayDate(session).sessionElapsed(since: session.startedAt)) sur \(totalLabel(session))")
            .accessibilityIdentifier("replay-timeline")
            observationTicks(session)
            HStack(alignment: .firstTextBaseline) {
                Text(replayDate(session).sessionElapsed(since: session.startedAt))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DrivyTheme.text)
                Spacer()
                Text(totalLabel(session))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DrivyTheme.muted)
            }
            .accessibilityHidden(true)
            if !session.points.isEmpty && currentPoint(session) == nil {
                Label("Position indisponible à cet instant", systemImage: "location.slash")
                    .font(.caption)
                    .foregroundStyle(DrivyTheme.muted)
                    .padding(.top, DrivySpacing.xxs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func totalLabel(_ session: DrivingSession) -> String {
        session.startedAt.addingTimeInterval(duration(session)).sessionElapsed(since: session.startedAt)
    }

    private func observationTicks(_ session: DrivingSession) -> some View {
        let totalDuration = duration(session)
        let selectedID = selectedObservationID
        return Canvas { context, size in
            for observation in session.observations {
                let progress = min(1, max(0, observation.observedAt.timeIntervalSince(session.startedAt) / totalDuration))
                let x = 14 + CGFloat(progress) * max(0, size.width - 28)
                let selected = selectedID == observation.id
                let rect = CGRect(x: x - (selected ? 2 : 1), y: 0, width: selected ? 4 : 2, height: selected ? 10 : 6)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(observation.status.color))
            }
        }
        .frame(height: session.observations.isEmpty ? 0 : 10)
        .accessibilityHidden(true)
    }

    private func transportControls(_ session: DrivingSession) -> some View {
        HStack(spacing: 0) {
            Button { jumpObservation(in: session, forward: false) } label: {
                Image(systemName: "backward.end.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Observation précédente")
            .disabled(adjacentObservation(in: session, forward: false) == nil)
            Button {
                if replayOffset >= duration(session) { replayOffset = 0 }
                selectedObservationID = nil
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 56, height: 56)
                    .foregroundStyle(DrivyTheme.onAccent)
                    .background(DrivyTheme.accent, in: Circle())
                    .contentShape(Circle())
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel(isPlaying ? "Mettre le replay en pause" : "Lire le replay")
            Button { jumpObservation(in: session, forward: true) } label: {
                Image(systemName: "forward.end.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Observation suivante")
            .disabled(adjacentObservation(in: session, forward: true) == nil)
            Menu {
                ForEach([1, 2, 4], id: \.self) { speed in
                    Button { playbackSpeed = Double(speed) } label: {
                        if Int(playbackSpeed) == speed { Label("×\(speed)", systemImage: "checkmark") }
                        else { Text("×\(speed)") }
                    }
                }
            } label: {
                Text("×\(Int(playbackSpeed))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Vitesse de lecture : \(Int(playbackSpeed)) fois")
        }
        .buttonStyle(.plain)
        .foregroundStyle(DrivyTheme.text)
    }

    private func observationSheet(_ session: DrivingSession) -> some View {
        NavigationStack {
            Group {
                if session.observations.isEmpty {
                    ContentUnavailableView("Aucune observation", systemImage: "text.bubble", description: Text("Aucune observation n’a été ajoutée pendant ce trajet."))
                } else {
                    ScrollViewReader { reader in
                        ScrollView {
                            observationsPreview(session).drivyPageContent()
                        }
                        .onAppear {
                            if let selectedObservationID { reader.scrollTo(selectedObservationID, anchor: .center) }
                        }
                    }
                }
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Observations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { sheet = nil } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func observationsPreview(_ session: DrivingSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(orderedObservations(in: session)) { observation in
                Button {
                    selectedObservationID = observation.id
                    seek(to: observation, in: session)
                    sheet = nil
                } label: {
                    HStack(alignment: .center, spacing: DrivySpacing.xs) {
                        ObservationRow(observation: observation, sessionStartedAt: session.startedAt)
                        if selectedObservationID == observation.id {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(DrivyTheme.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DrivyRowButtonStyle())
                .accessibilityAddTraits(selectedObservationID == observation.id ? [.isSelected] : [])
                .id(observation.id)
                .accessibilityHint(observation.anchorPointID == nil ? "Revoir cet instant sans position" : "Revoir ce moment sur le trajet")
                Divider().overlay(DrivyTheme.border)
            }
        }
    }

    private func informationSheet(_ session: DrivingSession) -> some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Date", value: session.startedAt.formatted(.dateTime.day().month(.wide).year()))
                    LabeledContent("Début", value: session.startedAt.formatted(.dateTime.hour().minute()))
                    LabeledContent("Durée", value: session.startedAt.addingTimeInterval(duration(session)).sessionElapsed(since: session.startedAt))
                    LabeledContent("État", value: session.state.label)
                    LabeledContent("Localisation", value: session.isExample ? "Tracé fictif" : session.usesGPS ? "Avec GPS" : "Sans GPS")
                }
                if session.isExample {
                    Section("Données d’exemple") {
                        Text(session.provenance ?? "Ce parcours et ses observations sont fictifs. Ils servent à découvrir le replay ; aucun déplacement réel n’a été enregistré.")
                    }
                }
                if session.state == .interrupted {
                    Section {
                        Label("L’enregistrement a été interrompu. Seules les données sauvegardées sont présentées.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(DrivyTheme.warning)
                    }
                }
                Section {
                    Label("Le trajet, les observations et le bilan restent sur cet appareil. Ils ne sont pas partagés avec l’école.", systemImage: "lock")
                    StorageCaption(message: controller.storageStatus)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .navigationTitle("Détails du trajet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { sheet = nil } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func duration(_ session: DrivingSession) -> TimeInterval {
        max(1, (session.endedAt ?? session.points.last?.timestamp ?? session.observations.last?.observedAt ?? session.startedAt).timeIntervalSince(session.startedAt))
    }

    private func replayDate(_ session: DrivingSession) -> Date {
        session.startedAt.addingTimeInterval(min(replayOffset, duration(session)))
    }

    private func currentPoint(_ session: DrivingSession) -> RecordedPoint? {
        let date = replayDate(session)
        return session.points.last { $0.timestamp <= date && date.timeIntervalSince($0.timestamp) <= 15 }
    }

    private func seek(to observation: LessonObservation, in session: DrivingSession) {
        replayOffset = min(duration(session), max(0, observation.observedAt.timeIntervalSince(session.startedAt)))
    }

    private func orderedObservations(in session: DrivingSession) -> [LessonObservation] {
        session.observations.enumerated().sorted { left, right in
            if left.element.observedAt == right.element.observedAt { return left.offset < right.offset }
            return left.element.observedAt < right.element.observedAt
        }.map { $0.element }
    }

    private func adjacentObservation(in session: DrivingSession, forward: Bool) -> LessonObservation? {
        let ordered = orderedObservations(in: session)
        if let index = ordered.firstIndex(where: { $0.id == selectedObservationID }),
           abs(ordered[index].observedAt.timeIntervalSince(session.startedAt) - replayOffset) < 0.001 {
            let nextIndex = index + (forward ? 1 : -1)
            return ordered.indices.contains(nextIndex) ? ordered[nextIndex] : nil
        }
        return forward
            ? ordered.first { $0.observedAt.timeIntervalSince(session.startedAt) >= replayOffset }
            : ordered.last { $0.observedAt.timeIntervalSince(session.startedAt) < replayOffset }
    }

    private func jumpObservation(in session: DrivingSession, forward: Bool) {
        if let target = adjacentObservation(in: session, forward: forward) {
            selectedObservationID = target.id
            seek(to: target, in: session)
        }
    }

    @MainActor private func playReplay() async {
        guard isPlaying, let session else { return }
        var previous = ContinuousClock.now
        while isPlaying && !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard isPlaying, !Task.isCancelled else { return }
            let now = ContinuousClock.now
            let elapsed = previous.duration(to: now).components
            previous = now
            replayOffset = min(duration(session), replayOffset + (Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) * playbackSpeed)
            if replayOffset >= duration(session) { isPlaying = false }
        }
    }
}
