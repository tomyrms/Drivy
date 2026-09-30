import MapKit
import SwiftUI

private extension ObservationStatus {
    /// Wire value of a school observation status (ATTENTION, TO_REWORK, POSITIVE).
    init?(schoolValue: String) {
        switch schoolValue {
        case "ATTENTION": self = .attention
        case "TO_REWORK": self = .toWorkOn
        case "POSITIVE": self = .positive
        default: return nil
        }
    }
}

/// Timeline of a private school replay, built once per loaded page set. Offsets are
/// seconds since the authorization; each fragment stays a separate polyline and the
/// time between fragments is a gap, never an interpolated route.
struct SchoolReplayTimeline {
    typealias Fragment = SchoolMapRouteFragment

    struct Sample {
        let offset: TimeInterval
        let coordinate: CLLocationCoordinate2D
        let fragmentIndex: Int
        let heading: Double?
    }

    struct Item: Identifiable {
        let id: UUID
        let offset: TimeInterval?
        let coordinate: CLLocationCoordinate2D?
        let status: ObservationStatus?
        let isMarker: Bool
        let text: String

        var title: String { isMarker ? "Moment à revoir" : text }
        var statusLabel: String { status?.label ?? "Repère" }
        var symbol: String { status?.symbol ?? "bookmark.fill" }
        var tone: DrivyTone { status?.tone ?? .neutral }
    }

    let start: Date
    let duration: TimeInterval
    let fragments: [Fragment]
    let samples: [Sample]
    let gaps: [ClosedRange<TimeInterval>]
    /// Observations with an instant, chronological; then those without an instant.
    let items: [Item]

    init(fragments source: [SchoolCaptureReplayFragment], observations: [SchoolPrivateGeoObservation],
         startsAt: Date?, endsAt: Date?, maxPointAge: TimeInterval = 15) {
        let observationDates = observations.compactMap(\.observedDate)
        let firstPointDate = source.first?.points.first.flatMap { SchoolLesson.date($0.capturedAt) }
        let origin = startsAt ?? firstPointDate ?? observationDates.min() ?? Date()
        var samples: [Sample] = []
        var built: [Fragment] = []
        var coordinateByKey: [String: CLLocationCoordinate2D] = [:]
        for (index, fragment) in source.enumerated() {
            // One date parse per fragment; the other points follow their monotonic elapsed time.
            guard let first = fragment.points.first, let base = SchoolLesson.date(first.capturedAt) else { continue }
            let baseOffset = base.timeIntervalSince(origin)
            var coordinates: [CLLocationCoordinate2D] = []
            var course = SchoolMapCourse()
            var previousOffset: TimeInterval?
            var part = 0
            coordinates.reserveCapacity(fragment.points.count)
            for point in fragment.points {
                let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                let offset = baseOffset + Double(point.elapsedMs - first.elapsedMs) / 1000
                if let previousOffset, offset - previousOffset > maxPointAge {
                    built.append(Fragment(id: "\(fragment.id):\(part)", coordinates: coordinates))
                    coordinates = []; part += 1
                }
                coordinates.append(coordinate)
                samples.append(Sample(offset: offset, coordinate: coordinate, fragmentIndex: index,
                    heading: course.receive(coordinate, at: offset, accuracy: point.accuracyMeters)))
                coordinateByKey["\(fragment.segmentID.uuidString):\(point.sequence)"] = coordinate
                previousOffset = offset
            }
            built.append(Fragment(id: "\(fragment.id):\(part)", coordinates: coordinates))
        }
        samples.sort { $0.offset < $1.offset }
        let observationOffsets = observationDates.map { $0.timeIntervalSince(origin) }
        let end = max(endsAt.map { $0.timeIntervalSince(origin) } ?? 0, samples.last?.offset ?? 0, observationOffsets.max() ?? 0)
        let total = max(1, end)

        var gaps: [ClosedRange<TimeInterval>] = []
        func clamp(_ value: TimeInterval) -> TimeInterval { min(total, max(0, value)) }
        if let first = samples.first, let last = samples.last {
            if clamp(first.offset) > maxPointAge { gaps.append(0...clamp(first.offset)) }
            for (previous, next) in zip(samples, samples.dropFirst()) {
                let lower = clamp(previous.offset), upper = clamp(next.offset)
                if upper > lower && (previous.fragmentIndex != next.fragmentIndex || upper - lower > maxPointAge) {
                    gaps.append(lower...upper)
                }
            }
            if total - clamp(last.offset) > maxPointAge { gaps.append(clamp(last.offset)...total) }
        } else {
            gaps = [0...total]
        }

        let items = observations.map { observation -> Item in
            var coordinate: CLLocationCoordinate2D?
            if let segment = observation.segmentId, let sequence = observation.pointSequence {
                coordinate = coordinateByKey["\(segment.uuidString):\(sequence)"]
            }
            return Item(id: observation.id, offset: observation.observedDate.map { $0.timeIntervalSince(origin) },
                        coordinate: coordinate, status: observation.eventStatus.flatMap { ObservationStatus(schoolValue: $0) },
                        isMarker: observation.isMarker, text: observation.text)
        }
        start = origin
        duration = total
        fragments = built
        self.samples = samples
        self.gaps = gaps
        self.items = items.enumerated().sorted { left, right in
            switch (left.element.offset, right.element.offset) {
            case let (l?, r?): return l == r ? left.offset < right.offset : l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return left.offset < right.offset
            }
        }.map(\.element)
    }

    var timedItems: [Item] { items.filter { $0.offset != nil } }

    /// Measured position at an instant: the last sample at most `maxPointAge` old (binary search).
    func sample(at offset: TimeInterval, maxPointAge: TimeInterval = 15) -> Sample? {
        var low = 0, high = samples.count
        while low < high {
            let middle = (low + high) / 2
            if samples[middle].offset <= offset { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        let candidate = samples[low - 1]
        // A known interruption is empty, even when the previous point is recent.
        if low < samples.count, offset > candidate.offset,
           samples[low].fragmentIndex != candidate.fragmentIndex || samples[low].offset - candidate.offset > maxPointAge {
            return nil
        }
        return offset - candidate.offset <= maxPointAge ? candidate : nil
    }
}

enum SchoolReplayFormatting {
    /// The replay uses the lesson's civil time, never the device's current time zone.
    static func startLabel(_ date: Date?, lessonTimeZone: String?) -> String? {
        guard let date, let lessonTimeZone, let zone = TimeZone(identifier: lessonTimeZone) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "d MMM 'à' HH:mm"
        return formatter.string(from: date)
    }
}

/// Private replay of a school capture for the assigned instructor (E24): same anatomy
/// as the personal replay. Only what the school reconstructed is drawn; gaps stay gaps.
struct SchoolCaptureReplayView: View {
    @Bindable var model: SchoolCaptureReplayWorkspace
    let learnerName: String
    let lessonTimeZone: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var timeline: SchoolReplayTimeline?
    @State private var offset: TimeInterval = 0
    @State private var isPlaying = false
    @State private var speed = 1
    @State private var selectedID: UUID?
    @State private var resetCameraID = UUID()
    @State private var followsPosition = true
    @State private var showsList = false

    private var contentKey: String {
        "\(model.fragments.count):\(model.pointCount):\(model.observations.count):\(model.isComplete)"
    }

    var body: some View {
        Group {
            if let timeline, model.isComplete || (!model.fragments.isEmpty && !model.isLoading) {
                GeometryReader { geometry in
                    if dynamicTypeSize.isAccessibilitySize {
                        accessibleLayout(timeline)
                    } else if geometry.size.width >= DrivyMapLayout.sidebarBreakpoint {
                        wideLayout(timeline)
                    } else {
                        compactLayout(timeline)
                    }
                }
            } else {
                loadingOrError
            }
        }
        .background(DrivyTheme.canvas)
        .foregroundStyle(DrivyTheme.text)
        .tint(DrivyTheme.accent)
        .task { await model.load() }
        .onChange(of: contentKey, initial: true) { _, _ in rebuildTimeline() }
        .task(id: isPlaying) { await play() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { isPlaying = false } }
        .onDisappear { isPlaying = false }
        .sheet(isPresented: $showsList) {
            if let timeline { listSheet(timeline) }
        }
    }

    private func rebuildTimeline() {
        timeline = SchoolReplayTimeline(fragments: model.fragments, observations: model.observations,
                                        startsAt: model.startsAt, endsAt: model.endsAt)
    }

    // MARK: States

    @ViewBuilder private var loadingOrError: some View {
        VStack(spacing: 0) {
            header(floating: false)
                .padding(DrivySpacing.m)
            if model.isLoading || (model.errorMessage == nil && !model.isComplete) {
                DrivyLoadingState(title: "Ouverture du trajet…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.errorMessage {
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    SchoolErrorNotice(message: error, retry: model.isInvalidated ? nil : { Task { await model.load() } })
                }
                .padding(DrivySpacing.m)
                .frame(maxWidth: DrivyMapLayout.accessibleMaxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var status: DrivyMapStatus {
        let day = SchoolReplayFormatting.startLabel(model.startsAt, lessonTimeZone: lessonTimeZone)
        let suffix = day.map { " · \($0)" } ?? ""
        switch model.quality ?? "" {
        case "PARTIAL": return DrivyMapStatus(title: "Partiel\(suffix)", symbol: "exclamationmark.circle", tone: .warning)
        default: return DrivyMapStatus(title: day ?? "Trajet", symbol: "point.topleft.down.to.point.bottomright.curvepath")
        }
    }

    private func header(floating: Bool = true) -> some View {
        DrivyMapHeader(title: learnerName, status: status,
            leading: .close(label: "Fermer le replay") { dismiss() }, floating: floating)
    }

    // MARK: Layouts

    private func compactLayout(_ timeline: SchoolReplayTimeline) -> some View {
        mapArea(timeline)
            .safeAreaInset(edge: .top, spacing: 0) {
                header().padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.s)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .trailing, spacing: DrivySpacing.s) {
                    if !timeline.samples.isEmpty { controls(timeline, axis: .horizontal) }
                    DrivyMapDock {
                        // Sur iPhone, l’observation choisie remplace le rail : le dock ne grandit
                        // pas et la carte garde sa place. Fermer le détail rend le rail.
                        if selectedID != nil, timeline.items.contains(where: { $0.id == selectedID }) {
                            selectedDetail(timeline)
                        } else {
                            rail(timeline)
                        }
                        player(timeline, showsList: true)
                        if let error = model.errorMessage { DrivyInlineMessage(text: error, tone: .warning) }
                    }
                }
                .padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.s)
            }
    }

    private func wideLayout(_ timeline: SchoolReplayTimeline) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DrivySpacing.l) {
                        header(floating: false)
                        observationList(timeline, closesSheet: false)
                    }
                    .padding(DrivySpacing.m)
                }
                DrivyMapDock(floating: false) {
                    selectedDetail(timeline)
                    player(timeline, showsList: false)
                    if let error = model.errorMessage { DrivyInlineMessage(text: error, tone: .warning) }
                }
                .padding(DrivySpacing.m)
            }
            .frame(width: DrivyMapLayout.sidebarWidth)
            .background(DrivyTheme.canvas)
            mapArea(timeline)
                .overlay(alignment: .bottomTrailing) {
                    if !timeline.samples.isEmpty { controls(timeline, axis: .vertical).padding(DrivySpacing.l) }
                }
        }
    }

    private func accessibleLayout(_ timeline: SchoolReplayTimeline) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                header(floating: false)
                if !timeline.samples.isEmpty {
                    mapArea(timeline)
                        .frame(height: DrivyMapLayout.accessibleMapHeight)
                        .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
                }
                DrivyMapDock(floating: false) {
                    selectedDetail(timeline)
                    player(timeline, showsList: false)
                }
                observationList(timeline, closesSheet: false)
            }
            .padding(DrivySpacing.m)
            .frame(maxWidth: DrivyMapLayout.accessibleMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func mapArea(_ timeline: SchoolReplayTimeline) -> some View {
        if timeline.samples.isEmpty {
            DrivyMapPlaceholder(title: "Aucune position confirmée",
                message: timeline.items.isEmpty
                    ? "L’école n’a reconstruit aucune position pour ce trajet."
                    : "Les observations gardent leur heure. Retrouve-les sur la chronologie.")
        } else {
            SchoolReplayMap(timeline: timeline, current: timeline.sample(at: offset), selectedID: $selectedID,
                resetCameraID: resetCameraID, followsPosition: $followsPosition, onSelect: select)
        }
    }

    private func controls(_ timeline: SchoolReplayTimeline, axis: Axis) -> some View {
        DrivyMapControls(followsPosition: $followsPosition, followLabel: "Suivre le replay dans le sens du trajet",
            canFollow: timeline.sample(at: offset) != nil, axis: axis) {
            followsPosition = false
            resetCameraID = UUID()
        }
    }

    // MARK: Dock

    @ViewBuilder
    private func selectedDetail(_ timeline: SchoolReplayTimeline) -> some View {
        if let item = timeline.items.first(where: { $0.id == selectedID }) {
            HStack(alignment: .top, spacing: DrivySpacing.s) {
                // Focus du dock : pastille pleine, comme les tuiles du signalement.
                Image(systemName: item.symbol)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(item.tone == .neutral ? DrivyTheme.text : item.tone.background)
                    .frame(width: 44, height: 44)
                    .background(item.tone == .neutral ? item.tone.background : item.tone.foreground, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.statusLabel)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(item.tone.foreground)
                    if item.isMarker, item.text != item.title {
                        Text(item.text).font(.subheadline)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(meta(item))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DrivyTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button { selectedID = nil } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DrivyTheme.muted)
                        .frame(width: 44, height: 44)
                        .background(DrivyTheme.surfaceMuted, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(DrivyTileButtonStyle())
                .accessibilityLabel("Fermer l’observation")
            }
        }
    }

    private func meta(_ item: SchoolReplayTimeline.Item) -> String {
        let time = item.offset.map { DrivyReplayScrubber.clock($0) } ?? "Heure non renseignée"
        // « Sur le trajet » est le cas normal : seule l’exception s’écrit.
        return item.coordinate == nil ? "\(time) · Sans position" : time
    }

    @ViewBuilder
    private func rail(_ timeline: SchoolReplayTimeline) -> some View {
        if timeline.items.isEmpty {
            Label("Aucune observation pour ce trajet", systemImage: "text.bubble")
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.muted)
                .frame(minHeight: 44, alignment: .leading)
        } else {
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: DrivySpacing.xs) {
                        ForEach(timeline.items) { item in
                            chip(item, isSelected: item.id == selectedID) { select(item) }
                                .id(item.id)
                        }
                    }
                    .padding(.vertical, DrivySpacing.xxs)
                }
                .scrollIndicators(.hidden)
                // Le rail va jusqu’aux bords du dock : les pastilles défilent sans être coupées net
                // au retrait, et la première reste alignée sur le contenu.
                .contentMargins(.horizontal, DrivySpacing.m, for: .scrollContent)
                .padding(.horizontal, -DrivySpacing.m)
                .onChange(of: selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(DrivyMotion.context(reduceMotion)) { reader.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private func chip(_ item: SchoolReplayTimeline.Item, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DrivySpacing.xs) {
                Image(systemName: item.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(item.tone.foreground)
                    .frame(width: 24, height: 24)
                    .background(item.tone.background, in: Circle())
                    .accessibilityHidden(true)
                Text(item.offset.map { DrivyReplayScrubber.clock($0) } ?? "—")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(item.title)
                    .font(.subheadline)
            }
            .foregroundStyle(DrivyTheme.text)
            .padding(.horizontal, DrivySpacing.s)
            .frame(minHeight: 44)
            .background(isSelected ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted, in: Capsule())
            .overlay {
                // Filet léger au repos ; Contraste accru le remplace par la bordure de contrôle.
                Capsule().strokeBorder(isSelected ? DrivyTheme.accent : (contrast == .increased ? DrivyTheme.controlBorder : DrivyTheme.border),
                                       lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(Capsule())
            .fixedSize()
            .animation(DrivyMotion.feedback(reduceMotion), value: isSelected)
        }
        .buttonStyle(DrivyTileButtonStyle())
        .accessibilityLabel("\(item.title), \(item.statusLabel), \(meta(item))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func player(_ timeline: SchoolReplayTimeline, showsList: Bool) -> some View {
        let timed = timeline.timedItems
        let current = min(max(0, offset), timeline.duration)
        let inGap = !timeline.samples.isEmpty && timeline.sample(at: current) == nil
        var openList: (() -> Void)? = nil
        if showsList { openList = { isPlaying = false; self.showsList = true } }
        return VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivyReplayScrubber(
                offset: $offset,
                duration: timeline.duration,
                marks: timed.compactMap { item in
                    item.offset.map { DrivyTimelineMark(id: item.id, offset: $0, symbol: item.symbol, tone: item.tone, label: item.title) }
                },
                gaps: timeline.gaps,
                selectedMarkID: selectedID,
                valueDescription: "\(DrivyReplayScrubber.clock(current)) sur \(DrivyReplayScrubber.clock(timeline.duration))\(inGap ? ", aucune position mesurée" : "")",
                onScrubStart: { isPlaying = false; selectedID = nil },
                onSelectMark: { id in
                    if let item = timeline.items.first(where: { $0.id == id }) { select(item) }
                }
            )
            .accessibilityIdentifier("school-replay-timeline")
            if inGap {
                Label("Aucune position mesurée pendant cette interruption.", systemImage: "location.slash")
                    .font(.caption)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DrivyReplayTransport(
                isPlaying: isPlaying,
                speed: speed,
                canGoBack: adjacent(in: timed, forward: false) != nil,
                canGoForward: adjacent(in: timed, forward: true) != nil,
                togglePlay: {
                    if offset >= timeline.duration { offset = 0; selectedID = nil }
                    isPlaying.toggle()
                },
                cycleSpeed: { speed = speed == 1 ? 2 : speed == 2 ? 4 : 1 },
                previous: { if let item = adjacent(in: timed, forward: false) { select(item) } },
                next: { if let item = adjacent(in: timed, forward: true) { select(item) } },
                openList: openList
            )
        }
    }

    // MARK: List

    private func observationList(_ timeline: SchoolReplayTimeline, closesSheet: Bool) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            DrivySectionHeader(title: DrivySeanceText.observations(timeline.items.count))
            if timeline.items.isEmpty {
                DrivyEmptyState(title: "Aucune observation", symbol: "text.bubble")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(timeline.items) { item in
                        Button {
                            select(item)
                            if closesSheet { showsList = false }
                        } label: {
                            HStack(alignment: .top, spacing: DrivySpacing.s) {
                                Image(systemName: item.symbol)
                                    .font(.headline)
                                    .foregroundStyle(item.tone.foreground)
                                    .frame(width: 36, height: 36)
                                    .background(item.tone.background, in: Circle())
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                                    Text(item.title).font(.headline).foregroundStyle(DrivyTheme.text)
                                    Text(item.statusLabel).font(.subheadline).foregroundStyle(item.tone.foreground)
                                    if item.isMarker, item.text != item.title { Text(item.text).font(.body) }
                                    Text(meta(item)).font(.caption.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if item.id == selectedID {
                                    Image(systemName: "checkmark.circle.fill").font(.title3)
                                        .foregroundStyle(DrivyTheme.accent).accessibilityHidden(true)
                                }
                            }
                            .padding(.vertical, DrivySpacing.xs)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(DrivyRowButtonStyle())
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(item.id == selectedID ? [.isSelected] : [])
                        Divider().overlay(DrivyTheme.border)
                    }
                }
            }
        }
    }

    private func listSheet(_ timeline: SchoolReplayTimeline) -> some View {
        NavigationStack {
            ScrollView { observationList(timeline, closesSheet: true).drivyPageContent() }
                .background(DrivyTheme.surface)
                .navigationTitle("Observations")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { showsList = false } } }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Playback

    private func select(_ item: SchoolReplayTimeline.Item) {
        selectedID = item.id
        if let value = item.offset, let timeline { offset = min(timeline.duration, max(0, value)) }
    }

    private func adjacent(in timed: [SchoolReplayTimeline.Item], forward: Bool) -> SchoolReplayTimeline.Item? {
        if let selectedID, let index = timed.firstIndex(where: { $0.id == selectedID }) {
            let target = index + (forward ? 1 : -1)
            return timed.indices.contains(target) ? timed[target] : nil
        }
        return forward
            ? timed.first { ($0.offset ?? 0) >= offset }
            : timed.last { ($0.offset ?? 0) < offset }
    }

    @MainActor private func play() async {
        guard isPlaying else { return }
        var previous = ContinuousClock.now
        while isPlaying && !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard isPlaying, !Task.isCancelled, let timeline else { return }
            let now = ContinuousClock.now
            let elapsed = previous.duration(to: now).components
            previous = now
            let before = min(offset, timeline.duration)
            let after = min(timeline.duration, before + (Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) * Double(speed))
            offset = after
            if let crossed = timeline.timedItems.last(where: { ($0.offset ?? -1) > before && ($0.offset ?? -1) <= after }) {
                selectedID = crossed.id
            }
            if after >= timeline.duration { isPlaying = false }
        }
    }
}

/// Map of the school replay: separate polylines per fragment, anchored observations,
/// the measured position at the playhead. Manual exploration suspends the follow mode.
private struct SchoolReplayMap: View {
    let timeline: SchoolReplayTimeline
    let current: SchoolReplayTimeline.Sample?
    @Binding var selectedID: UUID?
    let resetCameraID: UUID
    @Binding var followsPosition: Bool
    let onSelect: (SchoolReplayTimeline.Item) -> Void
    @State private var camera: MapCameraPosition = .automatic
    @State private var mapHeading = 0.0
    @State private var followDistance = 650.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Map(position: $camera) {
            ForEach(timeline.fragments) { fragment in
                if fragment.line.pointCount > 1 {
                    MapPolyline(fragment.line).stroke(DrivyTheme.routeHalo, lineWidth: 11)
                    MapPolyline(fragment.line).stroke(DrivyTheme.route, lineWidth: 6)
                } else if let coordinate = fragment.firstCoordinate {
                    Annotation("Position enregistrée", coordinate: coordinate) {
                        Circle().fill(DrivyTheme.route).frame(width: 8, height: 8)
                    }.annotationTitles(.hidden)
                }
            }
            ForEach(timeline.items.filter { $0.coordinate != nil }) { item in
                if let coordinate = item.coordinate {
                    Annotation(item.title, coordinate: coordinate) {
                        Button { onSelect(item) } label: { marker(item) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.title), \(item.statusLabel)")
                            .accessibilityAddTraits(selectedID == item.id ? [.isSelected] : [])
                    }.annotationTitles(.hidden)
                }
            }
            if let current {
                Annotation("Position enregistrée", coordinate: current.coordinate) {
                    SchoolMapPositionMarker(course: current.heading, mapHeading: mapHeading)
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { }
        .onAppear { if followsPosition, current != nil { follow() } else { fitRoute() } }
        .onMapCameraChange(frequency: .continuous) { context in
            mapHeading = context.camera.heading
            if camera.positionedByUser { followDistance = min(2500, max(180, context.camera.distance)) }
        }
        .onChange(of: camera.positionedByUser) { _, byUser in if byUser { followsPosition = false } }
        .onChange(of: followsPosition) { _, follows in if follows { follow() } }
        .onChange(of: current?.offset) { _, _ in if followsPosition && !camera.positionedByUser { follow() } }
        .onChange(of: resetCameraID) { _, _ in followsPosition = false; fitRoute() }
        .accessibilityLabel("Carte du trajet reconstruit par l’école")
    }

    private func marker(_ item: SchoolReplayTimeline.Item) -> some View {
        let selected = selectedID == item.id
        return Image(systemName: item.symbol)
            .font(selected ? .body.weight(.bold) : .caption.weight(.bold))
            .foregroundStyle(selected ? DrivyTheme.onAccent : item.tone.foreground)
            .frame(width: selected ? 40 : 26, height: selected ? 40 : 26)
            .background(selected ? DrivyTheme.accent : DrivyTheme.surface, in: Circle())
            .overlay(Circle().strokeBorder(selected ? DrivyTheme.routeHalo : item.tone.foreground, lineWidth: selected ? 3 : 2))
            .shadow(color: DrivyTheme.shadow.opacity(0.25), radius: 3, y: 1)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .animation(DrivyMotion.context(reduceMotion), value: selected)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }

    private func follow() {
        guard let current else { return }
        withAnimation(reduceMotion ? nil : .linear(duration: 0.25)) {
            camera = .camera(MapCamera(centerCoordinate: current.coordinate, distance: followDistance,
                heading: current.heading ?? mapHeading, pitch: 0))
        }
    }

    private func fitRoute() {
        let mapPoints = timeline.samples.map { MKMapPoint($0.coordinate) }
        guard let minX = mapPoints.map(\.x).min(), let maxX = mapPoints.map(\.x).max(),
              let minY = mapPoints.map(\.y).min(), let maxY = mapPoints.map(\.y).max() else { return }
        let center = MKMapPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let minimumSpan = MKMapPointsPerMeterAtLatitude(center.coordinate.latitude) * 160
        let width = max(maxX - minX, minimumSpan) * 1.2
        let height = max(maxY - minY, minimumSpan) * 1.2
        camera = .rect(MKMapRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
    }
}
