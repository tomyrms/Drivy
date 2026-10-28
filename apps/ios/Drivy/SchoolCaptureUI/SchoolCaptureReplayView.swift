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
    /// Observation lue en entier (#234) ; la sélection et l’instant restent ceux du dock.
    @State private var reading: SchoolReplayTimeline.Item?
    /// Filtre des observations, commun au rail, à la liste, à la chronologie et à la carte (#236).
    @State private var filter = SchoolReplayObservationFilter()
    @FocusState private var searching: Bool
    @State private var showsTraceHelp = false
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
        .task(id: model.id) { await model.load() }
        .onChange(of: contentKey, initial: true) { _, _ in rebuildTimeline() }
        .onChange(of: reduceMotion, initial: true) { _, value in player.reduceMotion = value }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player.pause() } }
        // Suivi automatique pendant la lecture : seulement ce que le filtre laisse voir.
        .onAppear { player.onCross = { id in
            if let item = timeline?.items.first(where: { $0.id == id }), filter.matches(item) { selectedID = id }
        } }
        .onDisappear { player.pause(); model.stopLoading() }
        .sheet(isPresented: $showsList) {
            if let timeline { listSheet(timeline) }
        }
        .sheet(item: $reading) { item in fullTextSheet(item) }
    }

    private func rebuildTimeline() {
        // Une page de plus ne coupe pas la lecture : la tête garde son instant sur la nouvelle chronologie.
        let built = SchoolReplayTimeline(fragments: model.fragments, observations: model.observations,
                                         startsAt: model.startsAt, endsAt: model.endsAt, matched: model.matchedRoute)
        timeline = built
        player.load(built)
        selectedID = built.retainedSelection(selectedID)
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
        case "PARTIAL": return DrivyMapStatus(title: "Incomplet\(suffix)", symbol: "exclamationmark.circle", tone: .warning)
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
        } else {
            matchingNotice
        }
    }

    @ViewBuilder private var matchingNotice: some View {
        switch model.matchingState {
        case .idle, .loading:
            EmptyView()
        case .waitingForSync:
            DrivyLoadingState(title: "Synchronisation du trajet…")
        case .processing:
            DrivyLoadingState(title: "Ajustement à la route…")
        case .retrying:
            DrivyLoadingState(title: "Nouvel essai d’ajustement à la route…")
        case .matched, .noReliableMatch:
            HStack(spacing: 0) {
                Text(matchingCoverageLabel).font(.caption).foregroundStyle(DrivyTheme.muted)
                traceHelpButton
            }
        case .unavailable:
            SchoolErrorNotice(message: "Ajustement à la route indisponible. Le tracé GPS mesuré reste lisible.", retry: nil)
        case .deferred(let reason):
            SchoolErrorNotice(message: reason == "WAITING_FOR_SYNC"
                ? "Synchronisation encore en attente. Réessaie plus tard."
                : "Ajustement à la route différé. Le tracé GPS mesuré reste lisible.", retry: { Task { await model.load() } })
        case .failed:
            SchoolErrorNotice(message: "L’ajustement à la route n’a pas pu être chargé. Le tracé GPS mesuré reste lisible.",
                retry: { Task { await model.load() } })
        }
    }

    private var matchingCoverageLabel: String {
        switch timeline?.matchingCoverage.state ?? .none {
        case .full: "Tracé ajusté à la route"
        case .partial: "Tracé ajusté à la route en partie"
        case .none: "Tracé GPS mesuré, sans ajustement"
        }
    }

    /// Aide à la demande (#233) : ce que montre le tracé, sans encombrer la carte ni promettre une précision.
    private var traceHelpButton: some View {
        Button { showsTraceHelp = true } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(DrivyTheme.accent)
                .frame(minWidth: DrivyLayout.tapTarget, minHeight: DrivyLayout.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.vertical, -DrivySpacing.s)
        .accessibilityLabel("À propos du tracé")
        .accessibilityIdentifier("school-replay-trace-help")
        .popover(isPresented: $showsTraceHelp) {
            Text(SchoolReplayTraceHelp.text(incomplete: model.quality == "PARTIAL"))
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(idealWidth: 300, alignment: .leading)
                .padding(DrivySpacing.m)
                .presentationCompactAdaptation(.popover)
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
            SchoolReplayMap(timeline: timeline, items: filter.apply(timeline.items), player: player, selectedID: selectedID,
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
            // Lire le texte entier arrête la lecture : l’observation ne change pas pendant qu’on la lit (#234).
            SchoolReplaySelectedDetail(item: item, meta: meta(item), close: { selectedID = nil },
                                       readAll: { player.pause(); reading = item })
                .id(item.id)
        }
    }

    /// Texte entier d’une observation, au-dessus du replay : fermer rend le dock tel qu’il était.
    private func fullTextSheet(_ item: SchoolReplayTimeline.Item) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    HStack(alignment: .top, spacing: DrivySpacing.s) {
                        SchoolObservationToken(glyph: item.glyph, tone: item.tone, side: DrivyLayout.tapTarget, filled: true)
                        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                            Text(item.title).font(.headline)
                            Text(item.statusLabel).font(.subheadline.weight(.semibold)).foregroundStyle(item.tone.foreground)
                        }
                    }
                    if item.isMarker, item.text != item.title { Text(item.text).font(.body) }
                    Text(meta(item)).font(.caption.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .drivyPageContent()
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Observation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { reading = nil } } }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
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
            let items = filter.apply(timeline.items)
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: DrivySpacing.xs) {
                        if filter.isActive { activeFilterChip(shown: items.count, total: timeline.items.count) }
                        ForEach(items) { item in
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

    /// En tête du rail filtré : le compte et l’effacement, d’un appui ; le point de lecture ne bouge pas.
    private func activeFilterChip(shown: Int, total: Int) -> some View {
        Button { filter = SchoolReplayObservationFilter() } label: {
            HStack(spacing: DrivySpacing.xs) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill").foregroundStyle(DrivyTheme.accent)
                Text("\(shown) sur \(total)").font(.subheadline.weight(.semibold).monospacedDigit())
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(DrivyTheme.muted)
            }
            .foregroundStyle(DrivyTheme.text)
            .padding(.horizontal, DrivySpacing.s)
            .frame(minHeight: DrivyLayout.tapTarget)
            .background(DrivyTheme.accentSoft, in: Capsule())
            .overlay { Capsule().strokeBorder(DrivyTheme.accent, lineWidth: 1) }
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(DrivyTileButtonStyle())
        .accessibilityLabel("Filtre actif, \(shown) \(shown == 1 ? "observation" : "observations") sur \(total)")
        .accessibilityHint("Efface le filtre")
        .accessibilityIdentifier("school-replay-filter-clear")
    }

    private func playerPanel(_ timeline: SchoolReplayTimeline, showsList: Bool) -> some View {
        var openList: (() -> Void)? = nil
        if showsList { openList = { player.pause(); self.showsList = true } }
        return SchoolReplayPlayerPanel(player: player, timeline: timeline, timed: filter.apply(timeline.timedItems),
                                       selectedID: $selectedID, openList: openList, select: select, step: step)
    }

    // MARK: List

    private func observationList(_ timeline: SchoolReplayTimeline, closesSheet: Bool) -> some View {
        let items = filter.apply(timeline.items)
        let total = DrivySeanceText.observations(timeline.items.count)
        return VStack(alignment: .leading, spacing: DrivySpacing.s) {
            // Le serveur lie toute capture scolaire à l’affectation du moniteur et au diagnostic de son appareil.
            // La fiche relue est nécessaire ; le nom de l’élève dans l’en-tête ne dit jamais qui fournit les positions.
            if let capture = model.capture, capture.id == model.captureID, capture.schoolId == model.scope.schoolID {
                DisclosureGroup("Détails du trajet") {
                    Label("Position de l’appareil du moniteur", systemImage: "location")
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, DrivySpacing.xs)
                }
                .accessibilityIdentifier("replay-position-source")
            }
            DrivySectionHeader(title: filter.isActive ? "\(items.count) sur \(total)" : total)
            if timeline.items.count >= Self.filterThreshold { filterControls(timeline) }
            // Le filtre ne promet pas plus que ce qui est chargé.
            if filter.isActive && !model.isComplete {
                Text("Recherche dans la partie déjà chargée du trajet.").font(.caption).foregroundStyle(DrivyTheme.muted)
            }
            if timeline.items.isEmpty {
                DrivyEmptyState(title: "Aucune observation", symbol: "text.bubble")
            } else if items.isEmpty {
                DrivyEmptyState(title: "Aucune observation trouvée", symbol: "magnifyingglass")
                Button("Effacer le filtre") { filter = SchoolReplayObservationFilter() }
                    .buttonStyle(DrivySecondaryButtonStyle())
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
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

    /// En dessous, la liste se lit d’un coup d’œil : ni recherche ni filtre.
    private static let filterThreshold = 4

    @ViewBuilder private func filterControls(_ timeline: SchoolReplayTimeline) -> some View {
        DrivySearchField(text: $filter.query, prompt: "Rechercher une observation", focus: $searching)
            .accessibilityIdentifier("school-replay-search")
        let kinds = SchoolReplayObservationFilter.kinds(in: timeline.items)
        if kinds.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: DrivySpacing.xs) {
                    ForEach(kinds) { entry in kindChip(entry.kind, count: entry.count) }
                }
                .padding(.vertical, DrivySpacing.xxs)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func kindChip(_ kind: SchoolReplayObservationKind, count: Int) -> some View {
        let isOn = filter.kinds.contains(kind)
        return Button {
            if isOn { filter.kinds.remove(kind) } else { filter.kinds.insert(kind) }
        } label: {
            HStack(spacing: DrivySpacing.xs) {
                Text(kind.label).font(.subheadline)
                Text("\(count)").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(DrivyTheme.muted)
            }
            .foregroundStyle(DrivyTheme.text)
            .padding(.horizontal, DrivySpacing.s)
            .frame(minHeight: DrivyLayout.tapTarget)
            .background(isOn ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted, in: Capsule())
            .overlay {
                Capsule().strokeBorder(isOn ? DrivyTheme.accent : (contrast == .increased ? DrivyTheme.controlBorder : DrivyTheme.border),
                                       lineWidth: isOn ? 1.5 : 1)
            }
            .contentShape(Capsule())
            .fixedSize()
            .animation(DrivyMotion.feedback(reduceMotion), value: isOn)
        }
        .buttonStyle(DrivyTileButtonStyle())
        .accessibilityLabel("\(kind.label), \(count)")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
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

    /// Choisir une observation (pastille, carte, liste, repère) la donne à lire : la lecture s’arrête sur elle, sans
    /// la remplacer à la suivante ; « Lecture » reprend le suivi (#235).
    private func select(_ item: SchoolReplayTimeline.Item) {
        selectedID = player.selectObservation(item)
    }

    /// Précédente et suivante parcourent la chronologie sans arrêter la lecture.
    private func step(_ item: SchoolReplayTimeline.Item) {
        selectedID = item.id
        if let value = item.offset { player.seek(to: value) }
    }
}

/// Observation choisie, dans le dock. Titre et note gardent trois lignes pour ne pas cacher les commandes ; coupés,
/// « Voir tout » ouvre le texte entier sans quitter la sélection ni l’instant (#234).
private struct SchoolReplaySelectedDetail: View {
    let item: SchoolReplayTimeline.Item
    let meta: String
    let close: () -> Void
    let readAll: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var titleIsCut = false
    @State private var noteIsCut = false

    var body: some View {
        let limit = dynamicTypeSize.isAccessibilitySize ? nil : 3
        HStack(alignment: .top, spacing: DrivySpacing.s) {
            // Focus du dock : pastille pleine, le thème du signalement.
            SchoolObservationToken(glyph: item.glyph, tone: item.tone, side: DrivyLayout.tapTarget, filled: true)
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    SchoolReplayClampedText(text: item.title, font: .headline, lineLimit: limit, isCut: $titleIsCut)
                    Text(item.statusLabel)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(item.tone.foreground)
                    if item.isMarker, item.text != item.title {
                        SchoolReplayClampedText(text: item.text, font: .subheadline, lineLimit: limit, isCut: $noteIsCut)
                    }
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: DrivySpacing.s) {
                    Text(meta)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DrivyTheme.muted)
                    if titleIsCut || noteIsCut {
                        Spacer(minLength: 0)
                        Button("Voir tout", action: readAll)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DrivyTheme.accent)
                            .frame(minHeight: DrivyLayout.tapTarget)
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
                            .accessibilityHint("Met la lecture en pause et ouvre le texte complet")
                            .accessibilityIdentifier("school-replay-read-all")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: close) {
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

/// Texte limité à quelques lignes qui sait s’il est coupé : sa hauteur entière, mesurée en coulisse, dépasse la
/// hauteur affichée.
private struct SchoolReplayClampedText: View {
    let text: String
    let font: Font
    let lineLimit: Int?
    @Binding var isCut: Bool
    @State private var shown: CGFloat = 0
    @State private var full: CGFloat = 0

    var body: some View {
        Text(text).font(font)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shown = $0; update() }
            .background(alignment: .topLeading) {
                Text(text).font(font)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full = $0; update() }
            }
    }

    private func update() {
        let cut = lineLimit != nil && full > shown + 1
        if cut != isCut { isCut = cut }
    }
}

/// Scrubber and transport. Only this view follows the playhead: the rest of the screen
/// is not re-evaluated while the replay plays.
private struct SchoolReplayPlayerPanel: View {
    let player: SchoolReplayPlayer
    let timeline: SchoolReplayTimeline
    /// Observations datées que le filtre laisse voir ; les interruptions restent celles du trajet.
    let timed: [SchoolReplayTimeline.Item]
    @Binding var selectedID: UUID?
    let openList: (() -> Void)?
    let select: (SchoolReplayTimeline.Item) -> Void
    let step: (SchoolReplayTimeline.Item) -> Void

    var body: some View {
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
                previous: { if let item = adjacent(in: timed, forward: false) { step(item) } },
                next: { if let item = adjacent(in: timed, forward: true) { step(item) } },
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
    /// Observations à épingler, après filtre ; le tracé et ses départ et arrivée restent entiers.
    let items: [SchoolReplayTimeline.Item]
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
        for item in items {
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
