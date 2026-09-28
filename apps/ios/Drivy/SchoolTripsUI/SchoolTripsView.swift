import SwiftUI

/// Trajets : ceux du moniteur, ou tous ceux de l’école pour l’administration (le serveur décide).
/// Les trajets arrêtés sur cet appareil et pas encore reçus par l’école restent en tête, « À envoyer ».
struct SchoolTripsView: View {
    @Bindable var workspace: SchoolWorkspace
    let agendaClient: SchoolAgendaClient
    var captureController: SchoolCaptureSessionController? = nil
    @State private var model: SchoolTripsWorkspace?
    @State private var uploads: SchoolCaptureHistoryWorkspace?
    @State private var replay: SchoolTripReplayRoute?

    private var scopeKey: String {
        [workspace.person?.personId.uuidString, workspace.membership?.membershipId.uuidString,
         workspace.membership.map { String($0.accessEpoch) }, workspace.school?.status].map { $0 ?? "" }.joined(separator: ":")
    }

    private var roles: [String] { workspace.membership?.roles ?? [] }

    var body: some View {
        Group {
            if let model {
                SchoolTripsList(model: model, uploads: uploads, roles: roles, learnerName: learnerName,
                    open: open, refresh: refresh)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(DrivyTheme.canvas)
            }
        }
        .navigationTitle("Trajets")
        .navigationBarTitleDisplayMode(.large)
        .task(id: scopeKey) { await prepare() }
        .onAppear {
            // Coming back to the tab after a lesson shows the trip that just ended.
            if let loadedAt = model?.loadedAt, Date().timeIntervalSince(loadedAt) > 30 { Task { await refresh() } }
        }
        .fullScreenCover(item: $replay) { route in
            SchoolCaptureReplayView(model: route.model, learnerName: route.learnerName)
        }
    }

    private func prepare() async {
        model?.invalidate(); uploads?.invalidate(); replay = nil
        model = nil; uploads = nil
        guard let person = workspace.person, let membership = workspace.membership, workspace.school != nil else { return }
        let scope = agendaClient.scope(person: person, membership: membership)
        let trips = SchoolTripsWorkspace(scope: scope, client: agendaClient.captureClient)
        model = trips
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

private struct SchoolTripsList: View {
    @Bindable var model: SchoolTripsWorkspace
    let uploads: SchoolCaptureHistoryWorkspace?
    let roles: [String]
    let learnerName: (UUID) -> String
    let open: (SchoolCaptureTrip) -> Void
    let refresh: () async -> Void

    private var hasUploads: Bool { !(uploads?.pendingUploads.isEmpty ?? true) }

    var body: some View {
        List {
            if let uploads, hasUploads {
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
            }
            ForEach(model.days()) { day in
                Section {
                    ForEach(day.trips) { trip in
                        SchoolTripRow(trip: trip, instructorName: model.instructorName(trip, viewerRoles: roles), open: open)
                    }
                } header: {
                    Text(day.title).accessibilityAddTraits(.isHeader)
                }
            }
            if model.nextCursor != nil && model.errorMessage == nil {
                Section { nextPage }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DrivyTheme.canvas)
        .overlay {
            if model.isEmpty && !hasUploads {
                ContentUnavailableView("Aucun trajet", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
        }
        .refreshable { await refresh() }
    }

    @ViewBuilder private var nextPage: some View {
        if let error = model.moreErrorMessage {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(DrivyTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                DrivyRetryButton { Task { await model.loadMore() } }
            }
            .padding(.vertical, DrivySpacing.xs)
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
