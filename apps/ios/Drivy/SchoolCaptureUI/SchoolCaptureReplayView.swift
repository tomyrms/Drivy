import MapKit
import SwiftUI

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
    @State private var player = SchoolReplayPlayer()
    @State private var selectedID: UUID?
    @State private var resetCameraID = UUID()
    @State private var followsPosition = true
    @State private var showsList = false
    /// Des pastilles sont cachées au-delà de ce bord du rail : lui seul s’estompe.
    @State private var railHidesLeading = false
    @State private var railHidesTrailing = false

    private var contentKey: String {
        "\(model.contentRevision):\(model.isComplete)"
    }
    /// Largeur maximale du libellé d’une pastille du rail : au-delà, il est tronqué.
    private static let chipTitleMaxWidth: CGFloat = 240
    /// Largeur du fondu aux bords du rail des observations.
    private static let railFadeWidth: CGFloat = 44

    var body: some View {
        Group {
            if let timeline, model.isComplete || !model.fragments.isEmpty {
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
        .onChange(of: reduceMotion, initial: true) { _, value in player.reduceMotion = value }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player.pause() } }
        .onAppear { player.onCross = { id in selectedID = id } }
        .onDisappear { player.pause() }
        .sheet(isPresented: $showsList) {
            if let timeline { listSheet(timeline) }
        }
    }

    private func rebuildTimeline() {
        // Une page de plus ne coupe pas la lecture : la tête garde son instant sur la nouvelle chronologie.
        let built = SchoolReplayTimeline(fragments: model.fragments, observations: model.observations,
                                         startsAt: model.startsAt, endsAt: model.endsAt, matched: model.matchedRoute)
        timeline = built
        player.load(built)
        if !model.observations.contains(where: { $0.id == selectedID }) { selectedID = nil }
    }

    // MARK: States

    @ViewBuilder private var loadingOrError: some View {
        VStack(spacing: 0) {
            header(floating: false)
                .padding(DrivySpacing.m)
            if model.isLoading || (model.errorMessage == nil && !model.isComplete) {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    DrivySkeletonBlock(height: DrivyMapLayout.accessibleMapHeight, radius: DrivyRadius.mapPanel, scalesWithText: false)
                    DrivySkeletonRows(count: 2)
                    DrivySkeletonBlock(height: 44)
                }
                .drivySkeleton("Ouverture du trajet…")
                .padding(DrivySpacing.m)
                .frame(maxWidth: DrivyMapLayout.accessibleMaxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            .overlay(alignment: .bottomTrailing) {
                if !timeline.samples.isEmpty {
                    controls(timeline, axis: .horizontal).padding(DrivySpacing.m)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header().padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.s)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .trailing, spacing: DrivySpacing.s) {
                    DrivyMapDock {
                        // Sur iPhone, l’observation choisie remplace le rail : le dock ne grandit
                        // pas et la carte garde sa place. Fermer le détail rend le rail.
                        Group {
                            if selectedID != nil, timeline.items.contains(where: { $0.id == selectedID }) {
                                selectedDetail(timeline)
                            } else {
                                rail(timeline)
                            }
                        }
                        // Le détail et le rail se remplacent en fondu ; la tête de lecture n’en est pas ralentie.
                        .animation(DrivyMotion.reveal(reduceMotion), value: selectedID)
                        playerPanel(timeline, showsList: true)
                        replayLoadingOrError
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
                    playerPanel(timeline, showsList: false)
                    replayLoadingOrError
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
                        .overlay(alignment: .bottomTrailing) { controls(timeline, axis: .horizontal).padding(DrivySpacing.m) }
                        .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
                }
                DrivyMapDock(floating: false) {
                    selectedDetail(timeline)
                    playerPanel(timeline, showsList: false)
                    replayLoadingOrError
                }
                observationList(timeline, closesSheet: false)
            }
            .padding(DrivySpacing.m)
            .frame(maxWidth: DrivyMapLayout.accessibleMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var replayLoadingOrError: some View {
        if model.isLoading {
            DrivyLoadingState(title: "Chargement de la suite…")
        } else if let error = model.errorMessage {
            SchoolErrorNotice(message: error, retry: model.isInvalidated ? nil : { Task { await model.load() } })
        }
    }

    @ViewBuilder
    private func mapArea(_ timeline: SchoolReplayTimeline) -> some View {
        if timeline.samples.isEmpty {
            DrivyMapPlaceholder(title: "Aucune position confirmée",
                message: model.pointCount > 0
                    ? "Le signal ne permet pas d’afficher le trajet. Les observations gardent leur heure."
                    : timeline.items.isEmpty ? "L’école n’a reconstruit aucune position pour ce trajet."
                    : "Les observations gardent leur heure. Retrouve-les sur la chronologie.")
        } else {
            SchoolReplayMap(timeline: timeline, player: player, selectedID: selectedID,
                resetCameraID: resetCameraID, followsPosition: $followsPosition, onSelect: select)
        }
    }

    private func controls(_ timeline: SchoolReplayTimeline, axis: Axis) -> some View {
        DrivyMapControls(followsPosition: $followsPosition, followLabel: "Suivre le replay dans le sens du trajet",
            canFollow: !timeline.samples.isEmpty, axis: axis) {
            followsPosition = false
            resetCameraID = UUID()
        }
    }

    // MARK: Dock

    @ViewBuilder
    private func selectedDetail(_ timeline: SchoolReplayTimeline) -> some View {
        if let item = timeline.items.first(where: { $0.id == selectedID }) {
            HStack(alignment: .top, spacing: DrivySpacing.s) {
                // Focus du dock : pastille pleine, le thème du signalement.
                SchoolObservationToken(glyph: item.glyph, tone: item.tone, side: DrivyLayout.tapTarget, filled: true)
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
                        .font(DrivyMapGlyph.control)
                        .foregroundStyle(DrivyTheme.muted)
                        .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
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
                .frame(minHeight: DrivyLayout.tapTarget, alignment: .leading)
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
                // Un bord ne s’estompe que s’il cache des pastilles : au repos la première est nette, en fin de course
                // la dernière aussi. Le fondu est large et progressif, il ne se lit pas comme une coupe.
                .mask {
                    HStack(spacing: 0) {
                        railFade(from: .leading, isActive: railHidesLeading)
                        Color.black
                        railFade(from: .trailing, isActive: railHidesTrailing)
                    }
                }
                .onScrollGeometryChange(for: [Bool].self) { geometry in
                    let start = geometry.contentOffset.x + geometry.contentInsets.leading
                    let end = geometry.contentSize.width + geometry.contentInsets.trailing
                        - geometry.contentOffset.x - geometry.containerSize.width
                    return [start > 2, end > 2]
                } action: { _, hidden in
                    withAnimation(DrivyMotion.feedback(reduceMotion)) {
                        railHidesLeading = hidden[0]; railHidesTrailing = hidden[1]
                    }
                }
                .padding(.horizontal, -DrivySpacing.m)
                .onChange(of: selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(DrivyMotion.context(reduceMotion)) { reader.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    /// Bord du rail : transparent au bord, plein vers l’intérieur, en courbe douce. Inactif, il est plein.
    private func railFade(from edge: HorizontalEdge, isActive: Bool) -> some View {
        let stops: [Gradient.Stop] = [.init(color: .clear, location: 0), .init(color: .black.opacity(0.18), location: 0.25),
                                      .init(color: .black.opacity(0.6), location: 0.6), .init(color: .black, location: 1)]
        return LinearGradient(stops: stops, startPoint: edge == .leading ? .leading : .trailing,
                              endPoint: edge == .leading ? .trailing : .leading)
            .overlay(Color.black.opacity(isActive ? 0 : 1))
            .frame(width: Self.railFadeWidth)
    }

    private func chip(_ item: SchoolReplayTimeline.Item, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DrivySpacing.xs) {
                SchoolObservationToken(glyph: item.glyph, tone: item.tone, side: 26)
                Text(item.offset.map { DrivyReplayScrubber.clock($0) } ?? "—")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                // Une note de relecture peut compter des centaines de caractères : la pastille garde une
                // ligne, le texte entier se lit dans le détail et par VoiceOver.
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(maxWidth: Self.chipTitleMaxWidth)
            }
            .foregroundStyle(DrivyTheme.text)
            .padding(.horizontal, DrivySpacing.s)
            .frame(minHeight: DrivyLayout.tapTarget)
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

    private func playerPanel(_ timeline: SchoolReplayTimeline, showsList: Bool) -> some View {
        var openList: (() -> Void)? = nil
        if showsList { openList = { player.pause(); self.showsList = true } }
        return SchoolReplayPlayerPanel(player: player, timeline: timeline, selectedID: $selectedID,
                                       openList: openList, select: select)
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
                                SchoolObservationToken(glyph: item.glyph, tone: item.tone)
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
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { showsList = false } } }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Playback

    private func select(_ item: SchoolReplayTimeline.Item) {
        selectedID = item.id
        if let value = item.offset { player.seek(to: value) }
    }
}

/// Scrubber and transport. Only this view follows the playhead: the rest of the screen
/// is not re-evaluated while the replay plays.
private struct SchoolReplayPlayerPanel: View {
    let player: SchoolReplayPlayer
    let timeline: SchoolReplayTimeline
    @Binding var selectedID: UUID?
    let openList: (() -> Void)?
    let select: (SchoolReplayTimeline.Item) -> Void

    var body: some View {
        let timed = timeline.timedItems
        let current = min(max(0, player.offset), timeline.duration)
        let inGap = !timeline.samples.isEmpty && timeline.sample(at: current) == nil
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivyReplayScrubber(
                offset: Binding(get: { player.offset }, set: { player.seek(to: $0) }),
                duration: timeline.duration,
                marks: timed.compactMap { item in
                    item.offset.map { DrivyTimelineMark(id: item.id, offset: $0, glyph: item.status?.glyph ?? item.glyph, theme: item.glyph,
                                                            tone: item.tone, label: item.title) }
                },
                gaps: timeline.gaps,
                selectedMarkID: selectedID,
                valueDescription: "\(DrivyReplayScrubber.clock(current)) sur \(DrivyReplayScrubber.clock(timeline.duration))\(inGap ? ", position indisponible" : "")",
                onScrubStart: { player.pause(); selectedID = nil },
                onSelectMark: { id in
                    if let item = timeline.items.first(where: { $0.id == id }) { select(item) }
                }
            )
            .accessibilityIdentifier("school-replay-timeline")
            if inGap {
                Label("Position indisponible à cet instant.", systemImage: "location.slash")
                    .font(.caption)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DrivyReplayTransport(
                isPlaying: player.isPlaying,
                speed: player.speed,
                canGoBack: adjacent(in: timed, forward: false) != nil,
                canGoForward: adjacent(in: timed, forward: true) != nil,
                togglePlay: {
                    if player.offset >= timeline.duration { player.seek(to: 0); selectedID = nil }
                    player.toggle()
                },
                cycleSpeed: { player.cycleSpeed() },
                previous: { if let item = adjacent(in: timed, forward: false) { select(item) } },
                next: { if let item = adjacent(in: timed, forward: true) { select(item) } },
                openList: openList
            )
        }
    }

    private func adjacent(in timed: [SchoolReplayTimeline.Item], forward: Bool) -> SchoolReplayTimeline.Item? {
        if let selectedID, let index = timed.firstIndex(where: { $0.id == selectedID }) {
            let target = index + (forward ? 1 : -1)
            return timed.indices.contains(target) ? timed[target] : nil
        }
        return forward
            ? timed.first { ($0.offset ?? 0) >= player.offset }
            : timed.last { ($0.offset ?? 0) < player.offset }
    }
}

/// Map of the school replay: one polyline per fragment, anchored observations, and the
/// playhead moving along the drawn line. Manual exploration suspends the follow mode.
private struct SchoolReplayMap: View {
    let timeline: SchoolReplayTimeline
    let player: SchoolReplayPlayer
    let selectedID: UUID?
    let resetCameraID: UUID
    @Binding var followsPosition: Bool
    let onSelect: (SchoolReplayTimeline.Item) -> Void

    var body: some View {
        DrivyRouteMapView(lines: timeline.mapLines, pins: pins, motion: player,
            isFollowing: followsPosition, cameraRequest: resetCameraID,
            onUserMovedMap: { followsPosition = false },
            onSelectPin: { id in
                if let item = timeline.items.first(where: { $0.id.uuidString == id }) { onSelect(item) }
            })
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Carte du trajet reconstruit par l’école")
        .accessibilityValue(timeline.mapGaps.isEmpty ? "" : "Portions sans mesure indiquées en pointillé")
    }

    private var pins: [DrivyRouteMapPin] {
        var result: [DrivyRouteMapPin] = []
        if let path = timeline.paths.first, let latitude = path.latitudes.first, let longitude = path.longitudes.first {
            result.append(DrivyRouteMapPin(id: "start", coordinate: .init(latitude: latitude, longitude: longitude),
                signature: "start", label: SchoolMapEndpointMarker.Kind.start.label, side: 22, priority: 200,
                content: AnyView(SchoolMapEndpointMarker(kind: .start))))
        }
        if timeline.samples.count > 1, let path = timeline.paths.last,
           let latitude = path.latitudes.last, let longitude = path.longitudes.last {
            result.append(DrivyRouteMapPin(id: "end", coordinate: .init(latitude: latitude, longitude: longitude),
                signature: "end", label: SchoolMapEndpointMarker.Kind.end.label, side: 22, priority: 210,
                content: AnyView(SchoolMapEndpointMarker(kind: .end))))
        }
        for item in timeline.items {
            guard let coordinate = item.coordinate else { continue }
            let selected = selectedID == item.id
            result.append(DrivyRouteMapPin(id: item.id.uuidString, coordinate: coordinate,
                signature: "\(item.glyph.key):\(item.statusLabel):\(selected)",
                label: "\(item.title), \(item.statusLabel)", isSelected: selected, isSelectable: true,
                side: DrivyLayout.tapTarget, priority: selected ? 450 : 400,
                content: AnyView(SchoolMapObservationMarker(glyph: item.glyph, tone: item.tone, badge: item.status?.glyph,
                    isSelected: selected))))
        }
        return result
    }
}
