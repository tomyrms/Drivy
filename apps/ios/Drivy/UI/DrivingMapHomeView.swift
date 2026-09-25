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
    @State private var liveSessionID: UUID?
    @State private var historyPath: [UUID] = []
    @State private var upcoming: [SchoolLesson] = []
    @State private var agendaError: String?
    @State private var isLoadingAgenda = false
    @State private var agendaGeneration = UUID()
    @State private var previewSelection: UUID?

    private var scopeKey: String {
        "\(workspace?.person?.id.uuidString ?? ""):\(workspace?.membership?.id.uuidString ?? ""):\(workspace?.membership?.accessEpoch ?? 0)"
    }
    private var schoolZone: TimeZone { TimeZone(identifier: workspace?.school?.timeZone ?? "Europe/Zurich") ?? .current }
    private var exampleJourneys: [DrivingSession] {
        controller.sessions.filter { $0.isExample && $0.state != .active }.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                heading
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 32) {
                        primaryContent.frame(maxWidth: 460)
                        nextLessons.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    primaryContent
                    nextLessons
                }
                historyLink
            }
            .padding(.horizontal, DrivySpacing.page(sizeClass))
            .padding(.top, 8)
            .padding(.bottom, 28)
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
            if let session = controller.activeSession {
                liveSessionID = session.id
                presentsLive = true
            }
        }) { StartSessionView(controller: controller) }
        .fullScreenCover(isPresented: $presentsLive, onDismiss: openSavedJourney) {
            NavigationStack { LiveSessionView(controller: controller) }.tint(DrivyTheme.accent)
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

    @ViewBuilder private var primaryContent: some View {
        if controller.activeSession == nil && !exampleJourneys.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exampleJourneys.count == 1 ? "Un trajet à découvrir" : "Deux trajets à découvrir").font(.title2.weight(.bold))
                    Text("Exemples · tracés et observations fictifs")
                        .font(.caption).foregroundStyle(DrivyTheme.muted)
                }
                ForEach(exampleJourneys.prefix(2)) { session in
                    exampleJourneyCard(session)
                }
                HStack(spacing: 12) {
                    Button(action: primaryAction) {
                        Label("Commencer un trajet", systemImage: "plus")
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(controller.isBusy || controller.errorMessage != nil)
                    .accessibilityIdentifier("new-session")
                    Button { presentsMap = true } label: {
                        Image(systemName: "map")
                            .font(.title3)
                            .frame(width: 52, height: 52)
                            .foregroundStyle(DrivyTheme.accent)
                            .background(DrivyTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Explorer la carte")
                }
                if let error = controller.errorMessage { InlineErrorView(message: error, retry: retryStorage) }
            }
        } else { journeyCard }
    }

    private func exampleJourneyCard(_ session: DrivingSession) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        return Button {
            historyPath = [session.id]
            presentsHistory = true
        } label: {
            layout {
                RouteMapView(session: session, selectedObservationID: .constant(nil), showsControls: false,
                    showsEmptyState: false, showsOriginBadge: false)
                    .allowsHitTesting(false)
                    .frame(width: 104, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.title ?? "Trajet d’exemple")
                        .font(.headline)
                        .foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(session.observations.count) observations")
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                    Label("Voir le replay", systemImage: "play.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DrivyTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DrivyTheme.canvas, in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous).strokeBorder(DrivyTheme.border, lineWidth: 0.5) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(session.title ?? "Trajet"), exemple fictif, \(session.observations.count) observations")
        .accessibilityHint("Ouvrir le replay de cet exemple")
    }

    private var heading: some View {
        DrivyContextHeader(context: schoolName,
            detail: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH"))).capitalizedFirst)
    }

    private var journeyCard: some View {
        DrivyCard {
            VStack(alignment: .leading, spacing: DrivySpacing.l - 4) {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    DrivyStatusDot(title: journeyStatus, tone: controller.isCapturing ? .accent : .neutral)
                    Text(controller.activeSession == nil ? "Votre prochain trajet" : "Trajet en cours")
                        .font(.title.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    if let session = controller.activeSession {
                        HStack(spacing: DrivySpacing.xs) {
                            if controller.isCapturing {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Text(context.date.sessionElapsed(since: session.startedAt)).monospacedDigit()
                                }
                                Text("·").accessibilityHidden(true)
                            }
                            Text("\(session.observations.count) observation\(session.observations.count == 1 ? "" : "s")")
                        }.font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    } else {
                        Text("Le parcours et les moments à retenir.")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                }
                mapPreview
                if controller.isLoading {
                    ProgressView("Ouverture des trajets…").frame(maxWidth: .infinity, minHeight: 52)
                } else {
                    Button(action: primaryAction) {
                        Label(controller.activeSession == nil ? "Commencer un trajet" : controller.isCapturing ? "Revenir à la carte" : "Vérifier la sauvegarde",
                              systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(controller.isBusy || (controller.activeSession == nil && controller.errorMessage != nil))
                    .accessibilityIdentifier(controller.activeSession == nil ? "new-session" : "resume-session")
                }
                if let error = controller.errorMessage {
                    InlineErrorView(message: error, retry: retryStorage)
                }
            }
        }
    }

    private var mapPreview: some View {
        Button {
            if controller.activeSession != nil && controller.isCapturing { primaryAction() }
            else { presentsMap = true }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let session = controller.activeSession, !session.points.isEmpty {
                    RouteMapView(session: session, selectedObservationID: $previewSelection, showsControls: false, showsEmptyState: false)
                        .allowsHitTesting(false)
                } else {
                    Map(initialPosition: .region(JourneyMapRegion.overview), interactionModes: [])
                        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                        .mapControls { }
                        .allowsHitTesting(false)
                }
                Label(controller.isCapturing ? "Ouvrir" : "Explorer", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DrivyTheme.text)
                    .padding(.horizontal, DrivySpacing.s).padding(.vertical, 9)
                    .drivyMapControl(in: Capsule())
                    .padding(DrivySpacing.s)
            }
            .frame(height: 168)
            .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(controller.isCapturing ? "Revenir au trajet en cours" : "Explorer la carte")
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
        DrivyNavigationRow(title: "Trajets et bilans", detail: "Retrouver les moments enregistrés",
            symbol: "clock.arrow.circlepath", action: { historyPath = []; presentsHistory = true })
            .accessibilityIdentifier("map-history")
    }
    private var journeyStatus: String {
        guard let session = controller.activeSession else { return "GPS au choix" }
        guard controller.isCapturing else { return "Sauvegarde à vérifier" }
        return session.usesGPS ? controller.gpsStatus.label : "Sans GPS"
    }
    private var retryStorage: (() -> Void)? {
        guard !controller.isCapturing else { return nil }
        return { Task { await controller.load() } }
    }
    private func primaryAction() {
        if let session = controller.activeSession {
            if controller.isCapturing { liveSessionID = session.id; presentsLive = true }
            else { Task { await controller.load() } }
        } else { presentsStart = true }
    }
    private func openSavedJourney() {
        if controller.activeSession == nil, let id = liveSessionID, controller.selectedSession?.id == id {
            historyPath = [id]; presentsHistory = true
        }
        liveSessionID = nil
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
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Position non autorisée").font(.subheadline.weight(.medium))
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    Link("Ouvrir les réglages", destination: url).font(.subheadline)
                                }
                            }.padding(14).background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                        }
                        Spacer()
                        Button {
                            location.request()
                            if location.isAuthorized { centerOnUser() }
                        } label: {
                            Image(systemName: "location").font(.title3).frame(width: 48, height: 48)
                                .foregroundStyle(DrivyTheme.accent)
                                .drivyMapControl(in: Circle())
                        }.buttonStyle(.plain).accessibilityLabel("Afficher ma position")
                            .accessibilityHint("Centre la carte sans enregistrer de trajet")
                            .accessibilityIdentifier("map-locate")
                    }.padding(16)
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
