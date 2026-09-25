import SwiftUI

/// Which observations the replay shows: all by default, or some statuses / one theme.
struct JourneyObservationFilter: Equatable, Sendable {
    var statuses: Set<ObservationStatus> = []
    var theme: ObservationTheme? = nil

    var isActive: Bool { !statuses.isEmpty || theme != nil }

    func includes(_ observation: LessonObservation) -> Bool {
        (statuses.isEmpty || statuses.contains(observation.status)) && (theme == nil || observation.theme == theme)
    }
}

/// Pure replay rules, shared by the view and the tests. Offsets are seconds of
/// recorded time since the start of the journey (x1 = one recorded second).
enum JourneyReplay {
    /// Chronological order that keeps every identifier, including simultaneous events.
    static func ordered(_ observations: [LessonObservation],
                        filter: JourneyObservationFilter = JourneyObservationFilter()) -> [LessonObservation] {
        observations.enumerated()
            .filter { filter.includes($0.element) }
            .sorted { left, right in
                left.element.observedAt == right.element.observedAt
                    ? left.offset < right.offset
                    : left.element.observedAt < right.element.observedAt
            }
            .map(\.element)
    }

    static func offset(of observation: LessonObservation, startedAt: Date) -> TimeInterval {
        observation.observedAt.timeIntervalSince(startedAt)
    }

    /// Stretches of a GPS journey without a measured position: before the first
    /// point, between segments, between points further apart than `maxPointAge`,
    /// after the last point. A journey without GPS has no gap: it never promised positions.
    static func gaps(in session: DrivingSession, maxPointAge: TimeInterval = 15) -> [ClosedRange<TimeInterval>] {
        guard session.usesGPS || !session.points.isEmpty else { return [] }
        let duration = session.recordedDuration()
        let points = session.points.sorted { $0.timestamp < $1.timestamp }
        guard let firstPoint = points.first, let lastPoint = points.last else { return [0...duration] }
        func clamp(_ value: TimeInterval) -> TimeInterval { min(duration, max(0, value)) }
        var result: [ClosedRange<TimeInterval>] = []
        let first = clamp(firstPoint.timestamp.timeIntervalSince(session.startedAt))
        if first > maxPointAge { result.append(0...first) }
        for (previous, next) in zip(points, points.dropFirst()) {
            let start = clamp(previous.timestamp.timeIntervalSince(session.startedAt))
            let end = clamp(next.timestamp.timeIntervalSince(session.startedAt))
            if end > start && (previous.segmentID != next.segmentID || end - start > maxPointAge) {
                result.append(start...end)
            }
        }
        let last = clamp(lastPoint.timestamp.timeIntervalSince(session.startedAt))
        if duration - last > maxPointAge { result.append(last...duration) }
        return result
    }

    /// Previous / next observation: from the selected one when it is in the list,
    /// otherwise from the playhead.
    static func adjacent(in ordered: [LessonObservation], selectedID: UUID?, offset: TimeInterval,
                         startedAt: Date, forward: Bool) -> LessonObservation? {
        if let selectedID, let index = ordered.firstIndex(where: { $0.id == selectedID }) {
            let target = index + (forward ? 1 : -1)
            return ordered.indices.contains(target) ? ordered[target] : nil
        }
        return forward
            ? ordered.first { Self.offset(of: $0, startedAt: startedAt) >= offset }
            : ordered.last { Self.offset(of: $0, startedAt: startedAt) < offset }
    }

    /// The last observation the playhead passed while moving from `from` to `to`.
    static func crossed(in ordered: [LessonObservation], from: TimeInterval, to: TimeInterval,
                        startedAt: Date) -> LessonObservation? {
        guard to > from else { return nil }
        return ordered.last {
            let value = Self.offset(of: $0, startedAt: startedAt)
            return value > from && value <= to
        }
    }

    /// Measured point shown at an instant: the last point at most `maxPointAge` old, never interpolated.
    static func point(at offset: TimeInterval, in session: DrivingSession, maxPointAge: TimeInterval = 15) -> RecordedPoint? {
        let date = session.startedAt.addingTimeInterval(offset)
        return session.points.last { $0.timestamp <= date && date.timeIntervalSince($0.timestamp) <= maxPointAge }
    }
}

/// Replay of a journey saved on this device: map, timeline and observations stay
/// synchronized. Selecting an observation moves the playhead, never the manual framing.
struct SessionDetailView: View {
    @Bindable var controller: SessionController
    let sessionID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedObservationID: UUID?
    @State private var autoSelectedID: UUID?
    @State private var replayOffset = 0.0
    @State private var isPlaying = false
    @State private var playbackSpeed = 1
    @State private var filter = JourneyObservationFilter()
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
                    } else if geometry.size.width >= DrivyMapLayout.sidebarBreakpoint {
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
            guard let id else { return }
            if id == autoSelectedID { autoSelectedID = nil; return }
            if let session, let observation = session.observations.first(where: { $0.id == id }) {
                seek(to: observation, in: session)
            }
        }
        .onChange(of: filter) { _, newFilter in
            if let session, let selected = session.observations.first(where: { $0.id == selectedObservationID }),
               !newFilter.includes(selected) {
                selectedObservationID = nil
            }
        }
        .sheet(item: $sheet) { destination in
            if let session {
                switch destination {
                case .observations:
                    observationSheet(session)
                case .summary:
                    SummaryEditorView(controller: controller, sessionID: session.id, initialText: session.summary,
                        isExample: session.isExample, observations: JourneyReplay.ordered(session.observations),
                        sessionStartedAt: session.startedAt)
                case .information:
                    informationSheet(session)
                }
            }
        }
    }

    // MARK: Layouts

    private func compactReplay(_ session: DrivingSession) -> some View {
        replayBackground(session)
            .safeAreaInset(edge: .top, spacing: 0) {
                replayHeader(session)
                    .padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.s)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .trailing, spacing: DrivySpacing.s) {
                    if !session.points.isEmpty { mapControls(session, axis: .horizontal) }
                    DrivyMapDock {
                        selectedDetail(session)
                        observationRail(session)
                        player(session, showsListButton: true)
                        if let error = controller.errorMessage { InlineErrorView(message: error) }
                    }
                }
                .padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.s)
            }
    }

    private func wideReplay(_ session: DrivingSession) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: DrivySpacing.l) {
                            replayHeader(session, floating: false)
                            summaryBlock(session)
                            observationsSection(session, closesSheet: false)
                        }
                        .padding(DrivySpacing.m)
                    }
                    .onChange(of: selectedObservationID) { _, id in
                        guard let id else { return }
                        withAnimation(DrivyMotion.context(reduceMotion)) { reader.scrollTo(id, anchor: .center) }
                    }
                }
                DrivyMapDock(floating: false) {
                    selectedDetail(session)
                    player(session, showsListButton: false)
                    if let error = controller.errorMessage { InlineErrorView(message: error) }
                }
                .padding(DrivySpacing.m)
            }
            .frame(width: DrivyMapLayout.sidebarWidth)
            .background(DrivyTheme.canvas)
            replayBackground(session)
                .overlay(alignment: .bottomTrailing) {
                    if !session.points.isEmpty { mapControls(session, axis: .vertical).padding(DrivySpacing.l) }
                }
        }
    }

    private func accessibleReplay(_ session: DrivingSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                replayHeader(session, floating: false)
                if !session.points.isEmpty {
                    replayBackground(session)
                        .frame(height: DrivyMapLayout.accessibleMapHeight)
                        .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
                    mapControls(session, axis: .horizontal).frame(maxWidth: .infinity, alignment: .trailing)
                }
                DrivyMapDock(floating: false) {
                    selectedDetail(session)
                    player(session, showsListButton: false)
                    if let error = controller.errorMessage { InlineErrorView(message: error) }
                }
                summaryBlock(session)
                observationsSection(session, closesSheet: false)
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
                    : "Les observations gardent leur heure. Retrouvez-les sur la chronologie.",
                symbol: session.usesGPS ? "location.slash" : "clock")
        } else {
            RouteMapView(
                session: session,
                selectedObservationID: $selectedObservationID,
                replayDate: session.startedAt.addingTimeInterval(clampedOffset(session)),
                showsControls: false,
                showsEmptyState: false,
                resetCameraID: resetCameraID,
                followsPosition: $followsPosition,
                showsOriginBadge: false,
                visibleObservationIDs: filter.isActive ? Set(orderedObservations(session).map(\.id)) : nil
            )
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(DrivyTheme.text)
                .frame(width: 48, height: 48)
                .background(DrivyTheme.surfaceMuted, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retour à l’historique")
    }

    // MARK: Header

    private func replayStatus(_ session: DrivingSession) -> DrivyMapStatus {
        if session.isExample { return DrivyMapStatus(title: "Exemple · données fictives", symbol: "info.circle") }
        let day = session.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "fr_CH")))
        let mode = session.usesGPS ? "" : " · sans GPS"
        if session.state == .interrupted {
            return DrivyMapStatus(title: "Interrompu · \(day)\(mode)", symbol: "exclamationmark.triangle", tone: .warning)
        }
        return DrivyMapStatus(title: "Privé · \(day)\(mode)", symbol: "lock")
    }

    private func replayHeader(_ session: DrivingSession, floating: Bool = true) -> some View {
        let hasSummary = JourneyStats(session: session).hasSummary
        return DrivyMapHeader(
            title: session.title ?? "Trajet · \(DrivySeanceText.duration(session.recordedDuration()))",
            status: replayStatus(session),
            leading: .back(label: "Retour à l’historique") { dismiss() },
            floating: floating
        ) {
            Button { isPlaying = false; sheet = .summary } label: {
                Label("Bilan", systemImage: hasSummary ? "checkmark.circle.fill" : "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.accent)
                    .padding(.horizontal, DrivySpacing.s)
                    .frame(minHeight: 44)
                    .background(DrivyTheme.accentSoft, in: Capsule())
                    .contentShape(Capsule())
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasSummary ? "Modifier le bilan personnel" : "Écrire le bilan personnel")
            .accessibilityIdentifier("edit-summary")
            Menu {
                Button { isPlaying = false; sheet = .observations } label: {
                    Label("Observations et bilan", systemImage: "list.bullet")
                }
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
                    .background(DrivyTheme.surfaceMuted, in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Options du replay")
        }
    }

    private func mapControls(_ session: DrivingSession, axis: Axis) -> some View {
        DrivyMapControls(followsPosition: $followsPosition,
            followLabel: "Suivre la position du replay",
            canFollow: currentPoint(session) != nil,
            axis: axis) {
            followsPosition = false
            resetCameraID = UUID()
        }
    }

    // MARK: Dock

    /// The observation under review: theme, status, instant, position, note.
    @ViewBuilder
    private func selectedDetail(_ session: DrivingSession) -> some View {
        if let selected = session.observations.first(where: { $0.id == selectedObservationID }) {
            HStack(alignment: .top, spacing: DrivySpacing.s) {
                ObservationGlyph(observation: selected, size: 36)
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(selected.theme.label)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    DrivyStatusBadge(title: selected.status.label, symbol: selected.status.symbol, tone: selected.status.tone)
                    Label("\(selected.observedAt.sessionElapsed(since: session.startedAt)) · \(selected.anchorPointID == nil ? "Sans position" : "Sur le trajet")",
                          systemImage: selected.anchorPointID == nil ? "clock" : "mappin")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DrivyTheme.muted)
                    if !selected.note.isEmpty {
                        Text(selected.note)
                            .font(.subheadline)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(selected.spokenDescription(sessionStartedAt: session.startedAt))
                Button { selectedObservationID = nil } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DrivyTheme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Désélectionner l’observation")
            }
        }
    }

    /// Horizontal rail of observations: one tap moves map and playhead to the passage.
    @ViewBuilder
    private func observationRail(_ session: DrivingSession) -> some View {
        let ordered = orderedObservations(session)
        if session.observations.isEmpty {
            Label("Aucune observation pendant ce trajet", systemImage: "text.bubble")
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.muted)
                .frame(minHeight: 44, alignment: .leading)
        } else {
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: DrivySpacing.xs) {
                        filterMenu(session)
                        if ordered.isEmpty {
                            Button("Aucune pour ce filtre · Tout afficher") { filter = JourneyObservationFilter() }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DrivyTheme.accent)
                                .frame(minHeight: 44)
                        }
                        ForEach(ordered) { observation in
                            ObservationChip(observation: observation, sessionStartedAt: session.startedAt,
                                isSelected: observation.id == selectedObservationID) {
                                select(observation, in: session)
                            }
                            .id(observation.id)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selectedObservationID) { _, id in
                    guard let id else { return }
                    withAnimation(DrivyMotion.context(reduceMotion)) { reader.scrollTo(id, anchor: .center) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Observations du trajet")
        }
    }

    private func filterMenu(_ session: DrivingSession) -> some View {
        let themes = ObservationTheme.allCases.filter { theme in session.observations.contains { $0.theme == theme } }
        return Menu {
            Section("Statut") {
                ForEach(ObservationStatus.allCases) { status in
                    Toggle(isOn: statusBinding(status)) {
                        Label(status.label, systemImage: status.symbol)
                    }
                }
            }
            Section("Thème") {
                Picker("Thème", selection: $filter.theme) {
                    Text("Tous les thèmes").tag(ObservationTheme?.none)
                    ForEach(themes) { theme in
                        Label(theme.label, systemImage: theme.journeySymbol).tag(Optional(theme))
                    }
                }
            }
            if filter.isActive {
                Button { filter = JourneyObservationFilter() } label: {
                    Label("Tout afficher", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.title3)
                .foregroundStyle(filter.isActive ? DrivyTheme.accent : DrivyTheme.text)
                .frame(width: 44, height: 44)
                .background(filter.isActive ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted, in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel(filter.isActive ? "Filtrer les observations, filtre actif" : "Filtrer les observations")
        .accessibilityIdentifier("replay-filter")
    }

    private func statusBinding(_ status: ObservationStatus) -> Binding<Bool> {
        Binding(get: { filter.statuses.contains(status) }, set: { included in
            if included { filter.statuses.insert(status) } else { filter.statuses.remove(status) }
        })
    }

    private func player(_ session: DrivingSession, showsListButton: Bool) -> some View {
        let ordered = orderedObservations(session)
        let total = session.recordedDuration()
        let offset = clampedOffset(session)
        let inGap = session.usesGPS && !session.points.isEmpty && currentPoint(session) == nil
        var openList: (() -> Void)? = nil
        if showsListButton { openList = { isPlaying = false; sheet = .observations } }
        return VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivyReplayScrubber(
                offset: $replayOffset,
                duration: total,
                marks: ordered.map { observation in
                    DrivyTimelineMark(id: observation.id,
                        offset: JourneyReplay.offset(of: observation, startedAt: session.startedAt),
                        symbol: observation.status.symbol, tone: observation.status.tone,
                        label: observation.theme.label)
                },
                gaps: JourneyReplay.gaps(in: session),
                selectedMarkID: selectedObservationID,
                valueDescription: "\(DrivyReplayScrubber.clock(offset)) sur \(DrivyReplayScrubber.clock(total))\(inGap ? ", aucune position mesurée" : "")",
                onScrubStart: {
                    isPlaying = false
                    selectedObservationID = nil
                },
                onSelectMark: { id in
                    if let observation = session.observations.first(where: { $0.id == id }) { select(observation, in: session) }
                }
            )
            .accessibilityIdentifier("replay-timeline")
            if inGap {
                Label("Aucune position mesurée pendant cette interruption.", systemImage: "location.slash")
                    .font(.caption)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DrivyReplayTransport(
                isPlaying: isPlaying,
                speed: playbackSpeed,
                canGoBack: JourneyReplay.adjacent(in: ordered, selectedID: selectedObservationID, offset: offset,
                    startedAt: session.startedAt, forward: false) != nil,
                canGoForward: JourneyReplay.adjacent(in: ordered, selectedID: selectedObservationID, offset: offset,
                    startedAt: session.startedAt, forward: true) != nil,
                togglePlay: {
                    if replayOffset >= total { replayOffset = 0; selectedObservationID = nil }
                    isPlaying.toggle()
                },
                cycleSpeed: { playbackSpeed = playbackSpeed == 1 ? 2 : playbackSpeed == 2 ? 4 : 1 },
                previous: { jumpObservation(in: session, forward: false) },
                next: { jumpObservation(in: session, forward: true) },
                openList: openList
            )
        }
    }

    // MARK: Observations and bilan

    private func summaryBlock(_ session: DrivingSession) -> some View {
        let hasSummary = JourneyStats(session: session).hasSummary
        return DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
                    Text("Bilan personnel")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: DrivySpacing.xs)
                    DrivyStatusBadge(title: hasSummary ? "Écrit" : "À écrire",
                        symbol: hasSummary ? "checkmark.circle" : "square.and.pencil",
                        tone: hasSummary ? .success : .neutral)
                }
                if hasSummary {
                    Text(session.summary)
                        .font(.body)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 6)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("saved-summary")
                } else {
                    Text("Reprenez les observations pour noter ce qui a été travaillé et la prochaine étape.")
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(hasSummary ? "Modifier le bilan" : "Écrire le bilan") { isPlaying = false; sheet = .summary }
                    .buttonStyle(DrivySecondaryButtonStyle())
                Label(session.isExample ? "Bilan d’exemple · contenu fictif" : "Privé sur cet appareil · non partagé",
                      systemImage: session.isExample ? "info.circle" : "lock")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.muted)
            }
        }
    }

    private func observationsSection(_ session: DrivingSession, closesSheet: Bool) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            DrivySectionHeader(title: DrivySeanceText.observations(session.observations.count))
            if session.observations.isEmpty {
                DrivyEmptyState(title: "Aucune observation", message: "Aucune observation n’a été ajoutée pendant ce trajet.",
                    symbol: "text.bubble")
            } else {
                statusFilterBar(session)
                let ordered = orderedObservations(session)
                if ordered.isEmpty {
                    DrivyEmptyState(title: "Aucune observation pour ce filtre", message: "Les autres observations restent disponibles.",
                        symbol: "line.3.horizontal.decrease.circle", actionTitle: "Tout afficher") { filter = JourneyObservationFilter() }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ordered) { observation in
                        Button {
                            select(observation, in: session)
                            if closesSheet { sheet = nil }
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
                        .accessibilityHint(observation.anchorPointID == nil ? "Revoir cet instant sans position" : "Revoir ce passage sur le trajet")
                        .id(observation.id)
                        Divider().overlay(DrivyTheme.border)
                    }
                }
            }
        }
    }

    private func statusFilterBar(_ session: DrivingSession) -> some View {
        let stats = JourneyStats(session: session)
        return ScrollView(.horizontal) {
            HStack(spacing: DrivySpacing.xs) {
                filterChip(title: "Toutes", symbol: nil, isSelected: filter.statuses.isEmpty) {
                    filter.statuses = []
                }
                ForEach(ObservationStatus.allCases) { status in
                    filterChip(title: "\(status.label) · \(stats.count(status))", symbol: status.symbol,
                               isSelected: filter.statuses.contains(status)) {
                        if filter.statuses.contains(status) { filter.statuses.remove(status) } else { filter.statuses.insert(status) }
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(title: String, symbol: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DrivySpacing.xxs) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.heavy)).accessibilityHidden(true) }
                Text(title).monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? DrivyTheme.accent : DrivyTheme.text)
            .padding(.horizontal, DrivySpacing.s)
            .frame(minHeight: 44)
            .background(isSelected ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted, in: Capsule())
            .overlay { Capsule().strokeBorder(isSelected ? DrivyTheme.accent : DrivyTheme.border, lineWidth: isSelected ? 1.5 : 0.5) }
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(DrivyTileButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func observationSheet(_ session: DrivingSession) -> some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: DrivySpacing.l) {
                        summaryBlock(session)
                        observationsSection(session, closesSheet: true)
                    }
                    .drivyPageContent()
                }
                .onAppear {
                    if let selectedObservationID { reader.scrollTo(selectedObservationID, anchor: .center) }
                }
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Observations et bilan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { sheet = nil } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func informationSheet(_ session: DrivingSession) -> some View {
        let stats = JourneyStats(session: session)
        return NavigationStack {
            List {
                Section {
                    LabeledContent("Date", value: session.startedAt.formatted(.dateTime.day().month(.wide).year()))
                    LabeledContent("Début", value: session.startedAt.formatted(.dateTime.hour().minute()))
                    LabeledContent("Durée", value: DrivySeanceText.duration(stats.duration))
                    LabeledContent("État", value: session.state.label)
                    LabeledContent("Localisation", value: session.isExample ? "Tracé fictif" : session.usesGPS ? "Avec GPS" : "Sans GPS")
                    LabeledContent("Observations", value: "\(stats.observationCount) · \(stats.locatedCount) sur le trajet")
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

    // MARK: Playback

    private func orderedObservations(_ session: DrivingSession) -> [LessonObservation] {
        JourneyReplay.ordered(session.observations, filter: filter)
    }

    private func clampedOffset(_ session: DrivingSession) -> TimeInterval {
        min(max(0, replayOffset), session.recordedDuration())
    }

    private func currentPoint(_ session: DrivingSession) -> RecordedPoint? {
        JourneyReplay.point(at: clampedOffset(session), in: session)
    }

    private func seek(to observation: LessonObservation, in session: DrivingSession) {
        replayOffset = min(session.recordedDuration(), max(0, JourneyReplay.offset(of: observation, startedAt: session.startedAt)))
    }

    private func select(_ observation: LessonObservation, in session: DrivingSession) {
        autoSelectedID = nil
        selectedObservationID = observation.id
        seek(to: observation, in: session)
    }

    private func jumpObservation(in session: DrivingSession, forward: Bool) {
        if let target = JourneyReplay.adjacent(in: orderedObservations(session), selectedID: selectedObservationID,
                                               offset: clampedOffset(session), startedAt: session.startedAt, forward: forward) {
            select(target, in: session)
        }
    }

    @MainActor private func playReplay() async {
        guard isPlaying else { return }
        var previous = ContinuousClock.now
        while isPlaying && !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard isPlaying, !Task.isCancelled, let session else { return }
            let now = ContinuousClock.now
            let elapsed = previous.duration(to: now).components
            previous = now
            let total = session.recordedDuration()
            let before = min(replayOffset, total)
            let after = min(total, before + (Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) * Double(playbackSpeed))
            replayOffset = after
            // The observation the playhead passes becomes the subject of the dock, without pausing.
            if let crossed = JourneyReplay.crossed(in: orderedObservations(session), from: before, to: after,
                                                   startedAt: session.startedAt), crossed.id != selectedObservationID {
                autoSelectedID = crossed.id
                selectedObservationID = crossed.id
            }
            if after >= total { isPlaying = false }
        }
    }
}
