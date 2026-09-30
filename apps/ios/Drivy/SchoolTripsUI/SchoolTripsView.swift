import SwiftUI

/// Trajets : ceux du moniteur, ou tous ceux de l’école pour l’administration (le serveur décide).
/// Les trajets arrêtés sur cet appareil et pas encore reçus par l’école restent en tête, « À envoyer ».
/// Vit dans l’onglet Profil : `header` apporte les sections du compte, au-dessus des trajets.
struct SchoolTripsView<Header: View>: View {
    @Bindable var workspace: SchoolWorkspace
    let agendaClient: SchoolAgendaClient
    var captureController: SchoolCaptureSessionController?
    let header: Header
    @State private var filter: SchoolTripFilter = .all
    @State private var model: SchoolTripsWorkspace?
    @State private var uploads: SchoolCaptureHistoryWorkspace?
    @State private var replay: SchoolTripReplayRoute?
    /// Portée du modèle en place : la vue qui réapparaît (onglet, replay plein écran refermé) ne le recrée pas.
    @State private var preparedKey: String?

    init(workspace: SchoolWorkspace, agendaClient: SchoolAgendaClient,
         captureController: SchoolCaptureSessionController? = nil, @ViewBuilder header: () -> Header) {
        _workspace = Bindable(workspace)
        self.agendaClient = agendaClient
        self.captureController = captureController
        self.header = header()
    }

    private var scopeKey: String {
        [workspace.person?.personId.uuidString, workspace.membership?.membershipId.uuidString,
         workspace.membership.map { String($0.accessEpoch) }, workspace.school?.status].map { $0 ?? "" }.joined(separator: ":")
    }

    private var roles: [String] { workspace.membership?.roles ?? [] }

    var body: some View {
        Group {
            if let model {
                SchoolTripsList(model: model, uploads: uploads, roles: roles, filter: $filter, header: header,
                    learnerName: learnerName, open: open, refresh: refresh)
            } else {
                // The account stays reachable while the school loads or when it cannot be read.
                List {
                    header
                    Section { DrivyLoadingState(title: "Chargement des trajets…") }
                        .drivyFormRows()
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: DrivyLayout.formColumn)
                .frame(maxWidth: .infinity)
                .background(DrivyTheme.canvas)
            }
        }
        .task(id: scopeKey) {
            if preparedKey == scopeKey, let model {
                if model.loadedAt == nil { await refresh() }
                return
            }
            await prepare()
        }
        .onAppear {
            // Coming back to the tab after a lesson shows the trip that just ended.
            if let loadedAt = model?.loadedAt, Date().timeIntervalSince(loadedAt) > 30 { Task { await refresh() } }
        }
        .onChange(of: captureController?.finalizedSyncState) { _, state in
            if state == .synced || state == .partial { Task { await refresh() } }
        }
        .fullScreenCover(item: $replay) { route in
            SchoolCaptureReplayView(model: route.model, learnerName: route.learnerName)
        }
    }

    private func prepare() async {
        let key = scopeKey
        preparedKey = nil
        model?.invalidate(); uploads?.invalidate(); replay = nil
        model = nil; uploads = nil; filter = .all
        guard let person = workspace.person, let membership = workspace.membership, workspace.school != nil else { return }
        let scope = agendaClient.scope(person: person, membership: membership)
        let trips = SchoolTripsWorkspace(scope: scope, client: agendaClient.captureClient)
        model = trips; preparedKey = key
        if let captureController, membership.roles.contains("INSTRUCTOR"), workspace.school?.status != "ARCHIVED" {
            uploads = SchoolCaptureHistoryWorkspace(scope: scope, client: agendaClient.captureClient, owner: captureController)
        }
        await refresh()
    }

    private func refresh() async {
        guard let model else { return }
        let local = uploads
        await model.load()
        await local?.load()
    }

    private func open(_ trip: SchoolCaptureTrip) {
        guard let model, SchoolTripsWorkspace.isReplayable(trip.capture) else { return }
        replay = SchoolTripReplayRoute(model: SchoolCaptureReplayWorkspace(scope: model.scope, client: model.client, captureID: trip.id),
            learnerName: trip.learnerName.isEmpty ? "Trajet" : trip.learnerName)
    }

    private func learnerName(_ learnerID: UUID) -> String {
        if let name = model?.trips.first(where: { $0.capture.learnerId == learnerID })?.learnerName, !name.isEmpty { return name }
        if workspace.learner?.id == learnerID, let name = workspace.learner?.displayName { return name }
        return workspace.learners.first { $0.id == learnerID }?.displayName ?? "Élève"
    }
}

struct SchoolTripReplayRoute: Identifiable {
    let model: SchoolCaptureReplayWorkspace
    let learnerName: String
    var id: UUID { model.id }
}

private struct SchoolTripsList<Header: View>: View {
    @Bindable var model: SchoolTripsWorkspace
    let uploads: SchoolCaptureHistoryWorkspace?
    let roles: [String]
    @Binding var filter: SchoolTripFilter
    let header: Header
    let learnerName: (UUID) -> String
    let open: (SchoolCaptureTrip) -> Void
    let refresh: () async -> Void

    private var hasUploads: Bool { !(uploads?.pendingUploads.isEmpty ?? true) }
    private var hasUploadError: Bool { uploads?.errorMessage != nil }
    /// Only the administration reads other instructors’ trips, so only it narrows them.
    private var canFilter: Bool { roles.contains("ADMIN") }
    private var isInstructor: Bool { roles.contains("INSTRUCTOR") }
    private var instructors: [SchoolTripInstructor] { model.otherInstructors() }

    /// A filter whose instructor left the loaded trips falls back to everything.
    private var activeFilter: SchoolTripFilter {
        switch filter {
        case .all: return .all
        case .mine: return isInstructor ? .mine : .all
        case .instructor(let id): return instructors.contains { $0.id == id } ? filter : .all
        }
    }

    private var filterTitle: String {
        switch activeFilter {
        case .all: return "Tous les trajets"
        case .mine: return "Mes trajets"
        case .instructor(let id): return instructors.first { $0.id == id }?.name ?? "Tous les trajets"
        }
    }

    private var tripsHeading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.m) {
                headingTitle
                Spacer(minLength: DrivySpacing.xs)
                filterMenu
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                headingTitle
                filterMenu
            }
        }
    }

    private var headingTitle: some View {
        Text("Trajets")
            .font(.drivySection).foregroundStyle(DrivyTheme.text)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var filterMenu: some View {
        if canFilter {
            Menu {
                Picker("Trajets", selection: Binding(get: { activeFilter }, set: { filter = $0 })) {
                    Text("Tous les trajets").tag(SchoolTripFilter.all)
                    if isInstructor { Text("Mes trajets").tag(SchoolTripFilter.mine) }
                    ForEach(instructors) { instructor in
                        Text(instructor.name).tag(SchoolTripFilter.instructor(instructor.id))
                    }
                }
            } label: {
                Label(filterTitle, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Filtrer les trajets")
            .accessibilityValue(filterTitle)
            .accessibilityIdentifier("trips-filter")
        }
    }

    var body: some View {
        let days = model.days(filter: activeFilter)
        return List {
            header
            Section { tripsHeading }
                .listRowInsets(EdgeInsets(top: DrivySpacing.s, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m))
                .listRowBackground(Color.clear)
            if let uploads, hasUploads || hasUploadError {
                SchoolCaptureUploadsSection(model: uploads, learnerName: learnerName,
                    onChange: { Task { await model.load() } })
            }
            if let error = model.errorMessage {
                Section {
                    SchoolErrorNotice(message: error, retry: model.accessRevoked ? nil : { Task { await refresh() } })
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if model.isLoading && model.trips.isEmpty {
                Section { DrivyLoadingState(title: "Chargement des trajets…") }
                    .drivyFormRows()
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.trips) { trip in
                        SchoolTripRow(trip: trip, instructorName: model.instructorName(trip, viewerRoles: roles), open: open)
                            // La rangée porte déjà son propre espacement vertical : sans cela, la liste le double.
                            .listRowInsets(EdgeInsets(top: 0, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m))
                    }
                } header: {
                    Text(day.title)
                        .font(.headline).foregroundStyle(DrivyTheme.text).textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                }
                .drivyFormRows()
            }
            if days.isEmpty && model.hasLoaded && !model.isLoading && model.errorMessage == nil && !hasUploads && !hasUploadError
                && (model.isEmpty || model.nextCursor == nil) {
                Section {
                    ContentUnavailableView("Aucun trajet", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("trips-empty")
                }
                .listRowBackground(Color.clear)
            }
            if model.nextCursor != nil && model.errorMessage == nil {
                Section { nextPage }
                    .drivyFormRows()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // Sur iPad, la liste reste une colonne lisible au lieu de s’étirer d’un bord à l’autre.
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .accessibilityIdentifier("profile-list")
        .refreshable { await refresh() }
    }

    @ViewBuilder private var nextPage: some View {
        if let error = model.moreErrorMessage {
            SchoolErrorNotice(message: error, retry: { Task { await model.loadMore() } })
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        } else {
            DrivyLoadingState(title: "Chargement des trajets précédents…")
                .task(id: model.nextCursor) { await model.loadMore() }
        }
    }
}

private struct SchoolTripRow: View {
    let trip: SchoolCaptureTrip
    let instructorName: String?
    let open: (SchoolCaptureTrip) -> Void

    private var replayable: Bool { SchoolTripsWorkspace.isReplayable(trip.capture) }
    private var title: String { trip.learnerName.isEmpty ? "Élève" : trip.learnerName }
    private var badge: SchoolTripBadge? { SchoolTripsWorkspace.badge(trip.capture) }
    private var detail: String? {
        let parts = [SchoolTripsWorkspace.duration(trip.capture), instructorName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if replayable {
                Button { open(trip) } label: { content }
                    .accessibilityHint("Revoir le trajet")
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(replayable ? .isButton : [])
        .accessibilityIdentifier("school-trip-\(trip.id.uuidString)")
    }

    private var content: some View {
        DrivyLessonRow(start: SchoolTripsWorkspace.time(trip), title: title, details: detail.map { [$0] } ?? [],
            badge: badge.map { DrivyStatusBadge(title: $0.title, symbol: $0.symbol, tone: $0.tone) },
            showsChevron: replayable)
    }

    private var spokenLabel: String {
        var parts = [title, SchoolTripsWorkspace.time(trip)]
        if let duration = SchoolTripsWorkspace.spokenDuration(trip.capture) { parts.append(duration) }
        if let instructorName { parts.append("avec \(instructorName)") }
        if let badge { parts.append(badge.title) }
        return parts.joined(separator: ", ")
    }
}
