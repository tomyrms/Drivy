import MapKit
import SwiftUI

/// Read-only school replay. The projection below contains only the validated AP160
/// measurements; it neither interpolates positions nor joins server fragments.
struct SchoolCaptureReplayView: View {
    @Bindable var model: SchoolCaptureReplayWorkspace
    @Bindable var workspace: SchoolWorkspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var projection = SchoolReplayProjection()
    @State private var observations: [SchoolReplayObservation] = []
    @State private var selectedObservationID: UUID?
    @State private var replayOffset = 0.0
    @State private var isPlaying = false
    @State private var playbackSpeed = 1.0
    @State private var followsPosition = false
    @State private var resetCameraID = UUID()
    @State private var sheet: ReplaySheet?

    private enum ReplaySheet: String, Identifiable {
        case observations, information
        var id: String { rawValue }
    }

    private var currentScope: SchoolCommandScope? {
        guard let person = workspace.person, let member = workspace.membership,
              member.roles.contains("INSTRUCTOR") else { return nil }
        return SchoolCommandScope(personID: person.personId, schoolID: member.schoolId,
            membershipID: member.membershipId, accessEpoch: member.accessEpoch,
            apiBaseURL: model.client.baseURL.absoluteString)
    }
    private var mayRead: Bool { currentScope == model.scope }
    private var start: Date? { model.startsAt }
    private var duration: TimeInterval { max(0, (model.endsAt ?? start ?? .distantPast).timeIntervalSince(start ?? .distantPast)) }
    private var replayDate: Date? { start?.addingTimeInterval(min(replayOffset, duration)) }
    private var currentPoint: SchoolReplayPoint? { replayDate.flatMap { projection.point(at: $0) } }
    private var selected: SchoolReplayObservation? { observations.first { $0.id == selectedObservationID } }
    private var learnerName: String {
        guard let capture = model.capture else { return "Replay" }
        if workspace.learner?.id == capture.learnerId { return workspace.learner?.displayName ?? "Trajet de leçon" }
        return workspace.learners.first { $0.id == capture.learnerId }?.displayName ?? "Trajet de leçon"
    }

    var body: some View {
        NavigationStack {
            Group {
                if mayRead {
                    GeometryReader { geometry in
                        if dynamicTypeSize.isAccessibilitySize { accessibleReplay }
                        else if geometry.size.width >= 760 { wideReplay }
                        else { compactReplay }
                    }
                } else {
                    ContentUnavailableView("Accès au trajet indisponible", systemImage: "lock",
                        description: Text("Revenez aux trajets de l’école pour relire vos accès."))
                        .safeAreaInset(edge: .top) { closeButton.frame(maxWidth: .infinity, alignment: .leading).padding(16) }
                }
            }
            .background(DrivyTheme.canvas)
            .foregroundStyle(DrivyTheme.text)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(DrivyTheme.accent)
        .task {
            guard mayRead else { purge(); return }
            if model.capture == nil && !model.isComplete { await reload() }
        }
        .task(id: isPlaying) { await playReplay() }
        .onChange(of: currentScope) { _, scope in
            if scope != model.scope { purge(); dismiss() }
        }
        .onChange(of: model.pointCount, initial: true) { _, _ in updateProjection() }
        .onChange(of: model.observations, initial: true) { _, _ in updateObservations() }
        .onChange(of: model.capture == nil) { _, empty in
            if empty { clearPresentation() }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { isPlaying = false } }
        .onDisappear { isPlaying = false }
        .sheet(item: $sheet) { destination in
            NavigationStack {
                Group {
                    if mayRead && model.capture != nil {
                        if destination == .observations { observationList }
                        else { informationList }
                    } else {
                        ContentUnavailableView("Trajet indisponible", systemImage: "lock")
                    }
                }
                .navigationTitle(destination == .observations ? "Observations du trajet" : "Détails du trajet")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { sheet = nil } } }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var compactReplay: some View {
        map
            .safeAreaInset(edge: .top, spacing: 0) { header.padding(.horizontal, 16).padding(.top, 8) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .trailing, spacing: 12) {
                    if model.pointCount > 0 { mapControls }
                    dock
                }.padding(.horizontal, 16).padding(.bottom, 12)
            }
    }

    private var wideReplay: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    dock
                    if !observations.isEmpty { observationRows }
                }.padding(20)
            }.frame(width: 360).background(DrivyTheme.canvas)
            map.overlay(alignment: .bottomTrailing) {
                if model.pointCount > 0 { mapControls.padding(24) }
            }
        }
    }

    private var accessibleReplay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                map.frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 20))
                if model.pointCount > 0 { mapControls.frame(maxWidth: .infinity, alignment: .trailing) }
                dock
                if !observations.isEmpty { observationRows }
            }.padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var map: some View {
        if model.capture != nil && !projection.fragments.isEmpty {
            SchoolReplayMap(projection: projection, observations: observations, currentPoint: currentPoint,
                selectedID: $selectedObservationID, followsPosition: $followsPosition, resetCameraID: resetCameraID,
                select: select)
        } else {
            VStack(spacing: 12) {
                if model.isLoading { ProgressView("Ouverture du trajet…") }
                else {
                    Image(systemName: "location.slash").font(.title2).accessibilityHidden(true)
                    Text(model.errorMessage == nil && model.isComplete ? "Aucune position enregistrée" : "Carte indisponible")
                        .font(.title3.weight(.semibold))
                }
            }
            .foregroundStyle(DrivyTheme.muted)
            .multilineTextAlignment(.center)
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DrivyTheme.canvas)
        }
    }

    private var closeButton: some View {
        Button { purge(); dismiss() } label: {
            Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 44, height: 44)
        }.buttonStyle(.plain).accessibilityLabel("Retour aux trajets de l’école")
    }

    private var header: some View {
        HStack(spacing: 4) {
            closeButton
            VStack(alignment: .leading, spacing: 4) {
                Text(learnerName).font(.headline).fixedSize(horizontal: false, vertical: true)
                Label(start.map { "Privé · \($0.formatted(.dateTime.day().month(.abbreviated)))" } ?? "Replay privé", systemImage: "lock")
                    .font(.caption).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { isPlaying = false; sheet = .information } label: {
                Image(systemName: "info.circle").font(.title3).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Détails du trajet").disabled(model.capture == nil)
        }
        .padding(.horizontal, 6).padding(.vertical, 10)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private var dock: some View {
        VStack(alignment: .leading, spacing: 12) {
            loadingState
            if model.capture != nil {
                observationButton
                if duration > 0 && (!projection.points.isEmpty || !observations.isEmpty) {
                    timeline
                    playbackControls
                }
            }
        }.padding(16).background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder private var loadingState: some View {
        if let error = model.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Label(model.pointCount > 0 ? "Chargement incomplet" : "Trajet indisponible", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.warning)
                Text(error).font(.footnote).fixedSize(horizontal: false, vertical: true)
                Button("Réessayer") { Task { await reload() } }
                    .frame(minHeight: 44).disabled(model.isLoading)
            }
        } else if model.isLoading {
            ProgressView(model.pointCount == 0 ? "Lecture du trajet…" : "Chargement de la suite…")
                .font(.footnote)
        }
        if model.quality == "PARTIAL" {
            Label("Trajet partiel", systemImage: "exclamationmark.circle")
                .font(.footnote).foregroundStyle(DrivyTheme.warning)
        }
        if projection.fragments.contains(where: { $0.lowAccuracy }) {
            Label("Précision réduite · portions en pointillés", systemImage: "location.circle")
                .font(.footnote).foregroundStyle(DrivyTheme.muted)
        }
    }

    private var observationButton: some View {
        Button { isPlaying = false; sheet = .observations } label: {
            HStack(spacing: 10) {
                Image(systemName: selected?.symbol ?? "list.bullet")
                    .font(.title3).foregroundStyle(selected?.color ?? DrivyTheme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected?.title ?? "Observations du trajet").font(.headline)
                    if let selected {
                        Text(selected.source.text).font(.subheadline)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        Text(observationCaption(selected)).font(.caption).foregroundStyle(DrivyTheme.muted)
                    } else {
                        Text(observations.isEmpty ? (model.isComplete ? "Aucune observation liée à ce trajet"
                            : model.isLoading ? "Lecture en cours" : "Aucune observation chargée")
                            : "\(observations.count) observation\(observations.count == 1 ? "" : "s")")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !observations.isEmpty { Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
            }.foregroundStyle(DrivyTheme.text).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(observations.isEmpty)
        .accessibilityHint("Ouvrir la liste et lire le texte complet")
    }

    private var timeline: some View {
        VStack(spacing: 4) {
            Slider(value: $replayOffset, in: 0...max(1, duration), onEditingChanged: { editing in
                if editing { isPlaying = false; selectedObservationID = nil }
            })
            .accessibilityLabel("Instant du trajet")
            .accessibilityValue(elapsed(replayOffset))
            .accessibilityIdentifier("school-replay-timeline")
            timelineTicks
            HStack { Text(elapsed(replayOffset)); Spacer(); Text(elapsed(duration)) }
                .font(.caption.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
            if let point = currentPoint {
                Text("Position enregistrée à \(point.date.formatted(.dateTime.hour().minute().second()))")
                    .font(.caption).foregroundStyle(DrivyTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("Aucune position à cet instant", systemImage: "location.slash")
                    .font(.caption).foregroundStyle(DrivyTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var timelineTicks: some View {
        Canvas { context, size in
            guard let start, duration > 0 else { return }
            var previousEnd = start
            for fragment in projection.fragments {
                if let first = fragment.start, first > previousEnd {
                    let left = min(1, max(0, previousEnd.timeIntervalSince(start) / duration))
                    let right = min(1, max(0, first.timeIntervalSince(start) / duration))
                    let width = max(0, size.width - 28)
                    context.fill(Path(CGRect(x: 14 + CGFloat(left) * width, y: 2,
                        width: CGFloat(right - left) * width, height: 3)), with: .color(DrivyTheme.muted.opacity(0.3)))
                }
                if let end = fragment.end { previousEnd = end }
            }
            let tail = min(1, max(0, previousEnd.timeIntervalSince(start) / duration))
            if tail < 1 {
                let width = max(0, size.width - 28)
                context.fill(Path(CGRect(x: 14 + CGFloat(tail) * width, y: 2,
                    width: CGFloat(1 - tail) * width, height: 3)), with: .color(DrivyTheme.muted.opacity(0.3)))
            }
            for observation in observations {
                guard let date = observation.date else { continue }
                let fraction = date.timeIntervalSince(start) / duration
                guard (0...1).contains(fraction) else { continue }
                let x = 14 + CGFloat(fraction) * max(0, size.width - 28)
                let selected = observation.id == selectedObservationID
                context.fill(Path(roundedRect: CGRect(x: x - 1.5, y: 0, width: 3, height: selected ? 8 : 5), cornerRadius: 1),
                    with: .color(observation.color))
            }
        }.frame(height: 8).accessibilityHidden(true)
    }

    private var playbackControls: some View {
        HStack(spacing: 0) {
            Button { if let item = adjacentObservation(forward: false) { select(item.id) } } label: {
                Image(systemName: "backward.end").frame(maxWidth: .infinity, minHeight: 48)
            }.accessibilityLabel("Observation précédente").disabled(adjacentObservation(forward: false) == nil)
            Button {
                if replayOffset >= duration { replayOffset = 0 }
                selectedObservationID = nil; isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.title3)
                    .frame(width: 56, height: 56).foregroundStyle(DrivyTheme.onAccent)
                    .background(DrivyTheme.accent, in: Circle()).frame(maxWidth: .infinity)
            }.accessibilityLabel(isPlaying ? "Mettre le replay en pause" : "Lire le replay")
            Button { if let item = adjacentObservation(forward: true) { select(item.id) } } label: {
                Image(systemName: "forward.end").frame(maxWidth: .infinity, minHeight: 48)
            }.accessibilityLabel("Observation suivante").disabled(adjacentObservation(forward: true) == nil)
            Menu {
                ForEach([1, 2, 4], id: \.self) { speed in
                    Button { playbackSpeed = Double(speed) } label: {
                        if Int(playbackSpeed) == speed { Label("×\(speed)", systemImage: "checkmark") }
                        else { Text("×\(speed)") }
                    }
                }
            } label: {
                Text("×\(Int(playbackSpeed))").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
            }.accessibilityLabel("Vitesse de lecture : \(Int(playbackSpeed)) fois")
        }.buttonStyle(.plain)
    }

    private var mapControls: some View {
        HStack(spacing: 8) {
            Button { followsPosition.toggle() } label: {
                Image(systemName: followsPosition ? "location.fill" : "location")
                    .foregroundStyle(followsPosition ? DrivyTheme.accent : DrivyTheme.text)
                    .frame(width: 48, height: 48).background(DrivyTheme.surface, in: Circle())
            }
            .disabled(currentPoint == nil && !followsPosition)
            .accessibilityLabel(followsPosition ? "Arrêter le suivi de position" : "Suivre la position du replay")
            .accessibilityAddTraits(followsPosition ? [.isSelected] : [])
            Button { followsPosition = false; resetCameraID = UUID() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 48, height: 48).background(DrivyTheme.surface, in: Circle())
            }.accessibilityLabel("Voir tout le trajet")
        }.font(.title3).buttonStyle(.plain)
    }

    private var observationList: some View {
        ScrollViewReader { reader in
            ScrollView { observationRows.padding(20) }
                .background(DrivyTheme.canvas)
                .onAppear { if let selectedObservationID { reader.scrollTo(selectedObservationID, anchor: .center) } }
        }
    }

    private var observationRows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(observations) { observation in
                Button { select(observation.id); sheet = nil } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: observation.symbol).foregroundStyle(observation.color).frame(width: 22)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(observation.title).font(.subheadline.weight(.semibold))
                            Text(observation.source.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            Text(observationCaption(observation)).font(.caption).foregroundStyle(DrivyTheme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if observation.id == selectedObservationID {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(DrivyTheme.accent).accessibilityHidden(true)
                        }
                    }.padding(.vertical, 16).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).id(observation.id)
                .accessibilityAddTraits(observation.id == selectedObservationID ? [.isSelected] : [])
                Divider()
            }
        }
    }

    private var informationList: some View {
        List {
            Section {
                if let start { LabeledContent("Début", value: start.formatted(.dateTime.day().month().year().hour().minute())) }
                if let end = model.endsAt { LabeledContent("Fin disponible", value: end.formatted(.dateTime.hour().minute().second())) }
                LabeledContent("Positions chargées", value: "\(model.pointCount)")
                LabeledContent("Lecture", value: model.isComplete ? "Chargement terminé" : "Chargement incomplet")
                if let quality = model.quality {
                    LabeledContent("Trajet", value: quality == "PARTIAL" ? "Partiel" : "Synchronisé")
                }
            }
            Section("Précision et interruptions") {
                Text("Les portions du trajet restent séparées après une coupure. Pendant une lacune, aucune position n’est reconstruite.")
                if projection.fragments.contains(where: { $0.lowAccuracy }) {
                    Label("Les portions en pointillés ont une précision réduite.", systemImage: "location.circle")
                        .foregroundStyle(DrivyTheme.warning)
                }
            }
            Section {
                Label("Ce trajet et ses observations restent privés. Ils ne sont pas publiés avec un bilan.", systemImage: "lock")
                Text("Les observations sans position sont accessibles depuis la leçon et son bilan.")
            }.font(.subheadline)
        }
    }

    private func observationCaption(_ observation: SchoolReplayObservation) -> String {
        let time = observation.date?.formatted(.dateTime.hour().minute().second()) ?? "Horaire non renseigné"
        return observation.point == nil ? "\(time) · Position indisponible" : time
    }

    private func select(_ id: UUID) {
        guard mayRead, let observation = observations.first(where: { $0.id == id }) else { return }
        selectedObservationID = id
        if let date = observation.date, let start { replayOffset = min(duration, max(0, date.timeIntervalSince(start))) }
    }

    private func adjacentObservation(forward: Bool) -> SchoolReplayObservation? {
        if let index = observations.firstIndex(where: { $0.id == selectedObservationID }) {
            let selectedOffset = observations[index].date.flatMap { date in start.map { min(duration, max(0, date.timeIntervalSince($0))) } }
            if selectedOffset == nil || abs((selectedOffset ?? 0) - replayOffset) < 0.001 {
                let next = index + (forward ? 1 : -1)
                return observations.indices.contains(next) ? observations[next] : nil
            }
        }
        guard let replayDate else { return forward ? observations.first : observations.last }
        return forward ? observations.first(where: { $0.date.map { $0 >= replayDate } ?? false })
            : observations.last(where: { $0.date.map { $0 < replayDate } ?? false })
    }

    private func updateProjection() {
        guard mayRead, model.capture != nil else { clearPresentation(); return }
        projection.update(model.fragments)
        updateObservations()
    }
    private func updateObservations() {
        guard mayRead, model.capture != nil else { observations = []; return }
        observations = model.observations.map { source in
            let key = source.segmentId.flatMap { segment in source.pointSequence.map { SchoolReplayPoint.Key(segment: segment, sequence: $0) } }
            let point = source.captureId == model.captureID ? key.flatMap { projection.anchors[$0] } : nil
            return SchoolReplayObservation(source: source, date: source.observedDate, point: point)
        }
        if let selectedObservationID, !observations.contains(where: { $0.id == selectedObservationID }) { self.selectedObservationID = nil }
    }
    private func clearPresentation() {
        isPlaying = false; sheet = nil; followsPosition = false
        selectedObservationID = nil; replayOffset = 0
        projection = SchoolReplayProjection(); observations = []
    }
    @MainActor private func reload() async {
        guard mayRead, !model.isLoading else { return }
        clearPresentation()
        await model.load()
        // Rebuild even when a refresh returns the same point count. The reader
        // may coalesce intermediate empty states into a single view update.
        if mayRead { updateProjection() }
    }
    private func purge() { clearPresentation(); model.invalidate() }
    private func elapsed(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    @MainActor private func playReplay() async {
        guard isPlaying, mayRead, model.capture != nil else { return }
        var previous = ContinuousClock.now
        while isPlaying && !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard isPlaying, mayRead, model.capture != nil, !Task.isCancelled else { return }
            let now = ContinuousClock.now
            let delta = previous.duration(to: now).components
            previous = now
            replayOffset = min(duration, replayOffset + (Double(delta.seconds) + Double(delta.attoseconds) / 1e18) * playbackSpeed)
            if replayOffset >= duration { isPlaying = false }
        }
    }
}

private struct SchoolReplayPoint: Identifiable {
    struct Key: Hashable { let segment: UUID; let sequence: Int }
    let id: Key
    let fragmentID: String
    let date: Date
    let coordinate: CLLocationCoordinate2D
}

private struct SchoolReplayFragment: Identifiable {
    let id: String
    var coordinates: [CLLocationCoordinate2D] = []
    var lowAccuracy = false
    var start: Date?
    var end: Date?
}

/// Append-only projection while AP160 pages arrive. Dates and geometry are not
/// rebuilt on every playback tick, and seeking uses a binary search.
private struct SchoolReplayProjection {
    var fragments: [SchoolReplayFragment] = []
    var points: [SchoolReplayPoint] = []
    var anchors: [SchoolReplayPoint.Key: SchoolReplayPoint] = [:]
    private var fragmentIndices: [String: Int] = [:]

    mutating func update(_ source: [SchoolCaptureReplayFragment]) {
        if source.isEmpty { self = Self(); return }
        for fragment in source {
            let index: Int
            if let existing = fragmentIndices[fragment.id] { index = existing }
            else {
                index = fragments.count; fragmentIndices[fragment.id] = index
                fragments.append(SchoolReplayFragment(id: fragment.id))
            }
            fragments[index].lowAccuracy = fragment.qualityLabel == "LOW_ACCURACY"
            let saved = fragments[index].coordinates.count
            for sourcePoint in fragment.points.dropFirst(saved) {
                guard let date = SchoolLesson.date(sourcePoint.capturedAt) else { continue }
                let point = SchoolReplayPoint(id: .init(segment: fragment.segmentID, sequence: sourcePoint.sequence),
                    fragmentID: fragment.id, date: date,
                    coordinate: CLLocationCoordinate2D(latitude: sourcePoint.latitude, longitude: sourcePoint.longitude))
                points.append(point); anchors[point.id] = point
                fragments[index].coordinates.append(point.coordinate)
                if fragments[index].start == nil { fragments[index].start = date }
                fragments[index].end = date
            }
        }
    }

    func point(at date: Date) -> SchoolReplayPoint? {
        var low = 0, high = points.count
        while low < high {
            let middle = low + (high - low) / 2
            if points[middle].date <= date { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        let point = points[low - 1]
        guard let index = fragmentIndices[point.fragmentID], let end = fragments[index].end, date <= end else { return nil }
        return point
    }
}

private struct SchoolReplayObservation: Identifiable {
    let source: SchoolPrivateGeoObservation
    let date: Date?
    let point: SchoolReplayPoint?
    var id: UUID { source.id }
    var title: String { source.isMarker ? "Moment à revoir" : source.statusLabel ?? "Observation" }
    var symbol: String {
        switch source.eventStatus {
        case "ATTENTION": "exclamationmark"
        case "TO_REWORK": "arrow.clockwise"
        case "POSITIVE": "checkmark"
        default: "bookmark"
        }
    }
    var color: Color {
        switch source.eventStatus {
        case "ATTENTION": DrivyTheme.danger
        case "TO_REWORK": DrivyTheme.warning
        case "POSITIVE": DrivyTheme.success
        default: DrivyTheme.accent
        }
    }
}

private struct SchoolReplayMap: View {
    let projection: SchoolReplayProjection
    let observations: [SchoolReplayObservation]
    let currentPoint: SchoolReplayPoint?
    @Binding var selectedID: UUID?
    @Binding var followsPosition: Bool
    let resetCameraID: UUID
    let select: (UUID) -> Void
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $camera) {
            ForEach(projection.fragments) { fragment in
                if fragment.coordinates.count > 1 {
                    MapPolyline(coordinates: fragment.coordinates).stroke(DrivyTheme.surface, lineWidth: 9)
                    MapPolyline(coordinates: fragment.coordinates)
                        .stroke(fragment.lowAccuracy ? DrivyTheme.warning : DrivyTheme.accent,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: fragment.lowAccuracy ? [5, 6] : []))
                } else if let coordinate = fragment.coordinates.first {
                    Annotation("Position enregistrée", coordinate: coordinate) {
                        Circle().fill(DrivyTheme.accent).frame(width: 8, height: 8)
                    }.annotationTitles(.hidden)
                }
            }
            ForEach(observations) { observation in
                if let point = observation.point {
                    Annotation(observation.title, coordinate: point.coordinate) {
                        Button { select(observation.id) } label: {
                            Image(systemName: observation.symbol)
                                .font(selectedID == observation.id ? .body.weight(.semibold) : .caption2.weight(.bold))
                                .foregroundStyle(observation.color)
                                .frame(width: selectedID == observation.id ? 36 : 22, height: selectedID == observation.id ? 36 : 22)
                                .background(DrivyTheme.surface, in: Circle())
                                .overlay(Circle().stroke(observation.color, lineWidth: selectedID == observation.id ? 2 : 1.5))
                                .frame(width: 44, height: 44).contentShape(Circle())
                        }.buttonStyle(.plain).accessibilityLabel("\(observation.title), \(observation.source.text)")
                    }.annotationTitles(.hidden)
                }
            }
            if let currentPoint {
                Annotation("Position enregistrée", coordinate: currentPoint.coordinate) {
                    Circle().fill(DrivyTheme.accent).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 3)).padding(8)
                        .background(DrivyTheme.accent.opacity(0.18), in: Circle())
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { }
        .onChange(of: camera.positionedByUser) { _, manual in if manual { followsPosition = false } }
        .onChange(of: followsPosition) { _, follows in if follows { followPoint() } }
        .onChange(of: currentPoint?.id) { _, _ in if followsPosition { followPoint() } }
        .onChange(of: resetCameraID) { _, _ in camera = .automatic }
        .accessibilityLabel("Carte du trajet privé")
    }

    private func followPoint() {
        guard let currentPoint else { return }
        camera = .region(MKCoordinateRegion(center: currentPoint.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)))
    }
}
