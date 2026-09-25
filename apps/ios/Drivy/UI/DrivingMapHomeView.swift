import CoreLocation
import MapKit
import Observation
import SwiftUI
import UIKit

/// The school agenda and the on-device journey are deliberately separate records.
struct DrivingMapHomeView: View {
    @Bindable var controller: SessionController
    let schoolName: String?
    let openLearners: () -> Void
    var agendaClient: SchoolAgendaClient? = nil
    var workspace: SchoolWorkspace? = nil
    var openAgenda: (() -> Void)? = nil
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var presentsStart = false
    @State private var presentsLive = false
    @State private var presentsHistory = false
    @State private var presentsMap = false
    @State private var pendingReplayID: UUID?
    @State private var historyPath: [UUID] = []
    @State private var upcoming: [SchoolLesson] = []
    @State private var agendaError: String?
    @State private var isLoadingAgenda = false
    @State private var agendaGeneration = UUID()

    private var scopeKey: String {
        "\(workspace?.person?.id.uuidString ?? ""):\(workspace?.membership?.id.uuidString ?? ""):\(workspace?.membership?.accessEpoch ?? 0)"
    }
    private var schoolZone: TimeZone { TimeZone(identifier: workspace?.school?.timeZone ?? "Europe/Zurich") ?? .current }
    private var exampleJourneys: [DrivingSession] {
        controller.sessions.filter { $0.isExample && $0.state != .active }.sorted { $0.startedAt > $1.startedAt }
    }
    /// Most recent journey recorded on this device, to resume its review or its bilan.
    private var lastJourney: DrivingSession? {
        controller.sessions.filter { !$0.isExample && $0.state != .active }.max { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                heading
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: DrivySpacing.xl) {
                        VStack(alignment: .leading, spacing: DrivySpacing.l) {
                            journeyCard
                            lastJourneySection
                        }
                        .frame(maxWidth: 480)
                        VStack(alignment: .leading, spacing: DrivySpacing.l) {
                            nextLessons
                            examplesSection
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    journeyCard
                    lastJourneySection
                    nextLessons
                    examplesSection
                }
                historyLink
            }
            .padding(.horizontal, DrivySpacing.page(sizeClass))
            .padding(.top, DrivySpacing.xs)
            .padding(.bottom, DrivySpacing.xl)
            .frame(maxWidth: 1050, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DrivyTheme.surface)
        .foregroundStyle(DrivyTheme.text)
        .navigationTitle("Séance")
        .navigationBarTitleDisplayMode(.large)
        .task(id: scopeKey) { await loadUpcoming() }
        .refreshable { await loadUpcoming() }
        .sheet(isPresented: $presentsStart, onDismiss: {
            if controller.activeSession != nil { presentsLive = true }
        }) { StartSessionView(controller: controller) }
        .fullScreenCover(isPresented: $presentsLive, onDismiss: openPendingReplay) {
            NavigationStack {
                LiveSessionView(controller: controller, openReplay: { id in pendingReplayID = id })
            }
            .tint(DrivyTheme.accent)
        }
        .sheet(isPresented: $presentsMap) { JourneyExploreMapView() }
        .sheet(isPresented: $presentsHistory) {
            NavigationStack(path: $historyPath) {
                SessionHistoryView(controller: controller)
                    .navigationDestination(for: UUID.self) { id in
                        SessionDetailView(controller: controller, sessionID: id)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fermer") { presentsHistory = false }
                        }
                    }
            }.tint(DrivyTheme.accent)
        }
    }

    /// The school is already named in the toolbar: the header only dates the day.
    private var heading: some View {
        DrivyContextHeader(context: nil,
            detail: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH"))).capitalizedFirst)
    }

    /// The one dominant decision of the screen: start a journey, or go back to the one running.
    private var journeyCard: some View {
        DrivyCard {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                if let session = controller.activeSession {
                    activeJourney(session)
                } else {
                    idleJourney
                }
                if let error = controller.errorMessage {
                    InlineErrorView(message: error, retry: retryStorage)
                }
            }
        }
    }

    @ViewBuilder
    private func activeJourney(_ session: DrivingSession) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            DrivyMapStatusLabel(status: journeyStatus, font: .subheadline.weight(.semibold))
            Text(controller.isCapturing ? "Trajet en cours" : "Sauvegarde à vérifier")
                .font(.drivyTitle)
                .fixedSize(horizontal: false, vertical: true)
            if controller.isCapturing {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = context.date.sessionElapsed(since: session.startedAt)
                    Text(elapsed)
                        .font(.drivyScreenTitle.monospacedDigit())
                        .accessibilityLabel("Durée du trajet")
                        .accessibilityValue(elapsed)
                }
            } else {
                Text("L’enregistrement s’est arrêté. Vérifiez la sauvegarde : les données déjà écrites sont conservées.")
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(DrivySeanceText.observations(session.observations.count) + " · privées", systemImage: "lock")
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.muted)
        }
        if controller.isCapturing && !session.points.isEmpty {
            Button(action: primaryAction) {
                RouteMapView(session: session, selectedObservationID: .constant(nil), showsControls: false,
                    showsEmptyState: false, showsOriginBadge: false, fitMargin: 1.6)
                    .allowsHitTesting(false)
                    .frame(height: DrivyMapLayout.previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
            }
            .buttonStyle(DrivyTileButtonStyle())
            .accessibilityLabel("Revenir au trajet en cours")
        }
        Button(action: primaryAction) {
            Label(controller.isCapturing ? "Revenir au trajet" : "Vérifier la sauvegarde",
                  systemImage: controller.isCapturing ? "arrow.up.forward.app" : "arrow.clockwise")
        }
        .buttonStyle(DrivyPrimaryButtonStyle())
        .disabled(controller.isBusy)
        .accessibilityIdentifier("resume-session")
    }

    @ViewBuilder
    private var idleJourney: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text("Prêt pour un trajet")
                .font(.drivyTitle)
                .fixedSize(horizontal: false, vertical: true)
            Text("Avec ou sans GPS. Signalez les moments à revoir, retrouvez-les dans le replay et le bilan. Tout reste privé sur cet appareil.")
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        if controller.isLoading {
            DrivyLoadingState(title: "Ouverture des trajets…")
        } else {
            Button { presentsStart = true } label: {
                Label("Commencer un trajet", systemImage: "plus")
            }
            .buttonStyle(DrivyPrimaryButtonStyle())
            .disabled(controller.isBusy || controller.errorMessage != nil)
            .accessibilityIdentifier("new-session")
        }
        Button { presentsMap = true } label: {
            Label("Explorer la carte", systemImage: "map")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DrivyTheme.accent)
        .accessibilityHint("Affiche la carte sans enregistrer de trajet")
    }

    /// Last journey recorded here: one tap back to its replay, its bilan state visible.
    @ViewBuilder
    private var lastJourneySection: some View {
        if controller.activeSession == nil, let session = lastJourney {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                DrivySectionHeader(title: "Dernier trajet")
                Button { openReplay(session.id) } label: {
                    JourneySummaryRow(session: session, showsChevron: true)
                        .padding(.vertical, DrivySpacing.s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DrivyRowButtonStyle())
                .accessibilityHint("Ouvrir le replay et le bilan de ce trajet")
                .accessibilityIdentifier("last-journey")
            }
        }
    }

    @ViewBuilder
    private var examplesSection: some View {
        if !exampleJourneys.isEmpty {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                DrivySectionHeader(title: "Découvrir le replay")
                Label("Exemples · tracés et observations fictifs", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                DrivyRowGroup {
                    ForEach(exampleJourneys.prefix(2)) { session in
                        Button { openReplay(session.id) } label: {
                            JourneySummaryRow(session: session, showsChevron: true)
                                .padding(.vertical, DrivySpacing.s)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(DrivyRowButtonStyle())
                        .accessibilityHint("Ouvrir le replay de cet exemple")
                    }
                }
            }
        }
    }

    private var nextLessons: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivySectionHeader(title: controller.activeSession == nil ? "À venir" : "Ensuite",
                actionTitle: openAgenda == nil ? nil : "Tout voir", action: openAgenda)
            if isLoadingAgenda {
                ProgressView("Ouverture de l’agenda…").frame(maxWidth: .infinity, minHeight: 90)
            } else if let agendaError {
                DrivyEmptyState(title: "Agenda indisponible", message: agendaError, symbol: "exclamationmark.triangle",
                    actionTitle: "Réessayer", action: { Task { await loadUpcoming() } })
            } else if upcoming.isEmpty {
                DrivyEmptyState(title: "Votre agenda est libre",
                    message: agendaClient == nil ? "Vos leçons apparaîtront ici lorsque votre école sera connectée." : "Aucune leçon prévue dans les sept prochains jours.",
                    symbol: "calendar",
                    actionTitle: openAgenda == nil ? nil : "Ouvrir l’agenda", action: openAgenda)
            } else {
                DrivyRowGroup {
                    ForEach(upcoming.prefix(3)) { lesson in upcomingRow(lesson) }
                }
            }
        }
    }

    private func upcomingRow(_ lesson: SchoolLesson) -> some View {
        HStack(alignment: .top, spacing: DrivySpacing.m) {
            DrivyTimeColumn(start: lessonTime(lesson.startsAt), end: lessonTime(lesson.endsAt))
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(workspace?.learners.first(where: { $0.id == lesson.learnerId })?.displayName ?? "Leçon de conduite")
                    .font(.headline).foregroundStyle(DrivyTheme.text)
                Text("\(lesson.durationMinutes) min · \(lessonDay(lesson.startsAt))").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                Text(lesson.meetingPoint).font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DrivySpacing.s)
        .accessibilityElement(children: .combine)
    }

    private var historyLink: some View {
        DrivyNavigationRow(title: "Trajets et bilans", detail: "Revoir les trajets, les observations et les bilans",
            symbol: "clock.arrow.circlepath", action: { historyPath = []; presentsHistory = true })
            .accessibilityIdentifier("map-history")
    }
    private var journeyStatus: DrivyMapStatus {
        guard let session = controller.activeSession else { return DrivyMapStatus(title: "GPS au choix", symbol: "location") }
        guard controller.isCapturing else {
            return DrivyMapStatus(title: "Sauvegarde à vérifier", symbol: "exclamationmark.triangle", tone: .warning)
        }
        return session.usesGPS ? controller.gpsStatus.mapStatus : DrivyMapStatus(title: "Sans GPS", symbol: "location.slash")
    }
    private var retryStorage: (() -> Void)? {
        guard !controller.isCapturing else { return nil }
        return { Task { await controller.load() } }
    }
    private func primaryAction() {
        if controller.activeSession != nil {
            if controller.isCapturing { presentsLive = true }
            else { Task { await controller.load() } }
        } else { presentsStart = true }
    }
    private func openReplay(_ id: UUID) {
        historyPath = [id]
        presentsHistory = true
    }
    private func openPendingReplay() {
        if let id = pendingReplayID { openReplay(id) }
        pendingReplayID = nil
    }
    private func lessonTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH"); formatter.timeZone = schoolZone; formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    private func lessonDay(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH"); formatter.timeZone = schoolZone; formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }
    @MainActor private func loadUpcoming() async {
        let request = UUID(); agendaGeneration = request
        upcoming = []; agendaError = nil
        guard let agendaClient, let membership = workspace?.membership else { isLoadingAgenda = false; return }
        let scope = scopeKey; isLoadingAgenda = true
        defer { if agendaGeneration == request { isLoadingAgenda = false } }
        let now = Date()
        do {
            var values: [SchoolLesson] = [], cursor: String?, seen = Set<String>()
            repeat {
                let page = try await agendaClient.lessons(schoolID: membership.schoolId, from: now, to: now.addingTimeInterval(7 * 86400), cursor: cursor)
                guard !Task.isCancelled, request == agendaGeneration, scope == scopeKey else { return }
                values.append(contentsOf: page.items); cursor = page.nextCursor
                if let cursor, !seen.insert(cursor).inserted { throw SchoolAgendaFailure.invalidResponse }
                guard values.count <= 10_000 else { throw SchoolAgendaFailure.invalidResponse }
            } while cursor != nil
            upcoming = values.filter { $0.status == "PLANNED" }.sorted { $0.plannedStart < $1.plannedStart }
        } catch {
            guard !Task.isCancelled, request == agendaGeneration, scope == scopeKey else { return }
            agendaError = (error as? LocalizedError)?.errorDescription ?? "L’agenda n’a pas pu être chargé."
        }
    }
}

struct JourneyExploreMapView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var satellite = false
    @State private var camera: MapCameraPosition = .region(JourneyMapRegion.overview)
    @State private var location = JourneyMapLocationPermission()
    @Namespace private var mapScope
    var body: some View {
        NavigationStack {
            Map(position: $camera, scope: mapScope) {
                if location.wasRequested && location.isAuthorized { UserAnnotation() }
            }
                .mapStyle(satellite ? .hybrid(elevation: .flat) : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .mapControls { MapCompass(scope: mapScope); MapScaleView(scope: mapScope) }
                .mapScope(mapScope)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        if location.isDenied {
                            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                                Label("Position non autorisée", systemImage: "location.slash")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DrivyTheme.warning)
                                Text("La carte reste consultable sans votre position.")
                                    .font(.caption).foregroundStyle(DrivyTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    Link("Ouvrir les réglages", destination: url)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DrivyTheme.accent)
                                        .frame(minHeight: 44)
                                }
                            }
                            .padding(.horizontal, DrivySpacing.m).padding(.vertical, DrivySpacing.s)
                            .drivyMapPanel()
                        }
                        Spacer()
                        Button {
                            location.request()
                            if location.isAuthorized { centerOnUser() }
                        } label: {
                            Image(systemName: "location").font(.title3).frame(width: 48, height: 48)
                                .foregroundStyle(DrivyTheme.accent)
                                .drivyLegibleMapControl(in: Circle())
                        }.buttonStyle(.plain).accessibilityLabel("Afficher ma position")
                            .accessibilityHint("Centre la carte sans enregistrer de trajet")
                            .accessibilityIdentifier("map-locate")
                    }.padding(DrivySpacing.m)
                }
                .onChange(of: location.isAuthorized) { _, allowed in if allowed && location.wasRequested { centerOnUser() } }
                .navigationTitle("Explorer la carte").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { satellite.toggle() } label: { Label("Changer de carte", systemImage: "square.3.layers.3d") }
                            .accessibilityIdentifier("map-style")
                    }
                }
        }.tint(DrivyTheme.accent)
    }
    private func centerOnUser() { camera = .userLocation(followsHeading: false, fallback: .region(JourneyMapRegion.overview)) }
}

@MainActor @Observable private final class JourneyMapLocationPermission: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var wasRequested = false
    private(set) var status: CLAuthorizationStatus = .notDetermined
    @ObservationIgnored private let manager = CLLocationManager()
    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var isDenied: Bool { status == .denied || status == .restricted }
    override init() { super.init(); status = manager.authorizationStatus; manager.delegate = self }
    func request() { wasRequested = true; status = manager.authorizationStatus; if status == .notDetermined { manager.requestWhenInUseAuthorization() } }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { status = manager.authorizationStatus }
}
