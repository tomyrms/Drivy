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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                heading
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 32) {
                        journeyCard.frame(maxWidth: 460)
                        nextLessons.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    journeyCard
                    nextLessons
                }
                historyLink
            }
            .padding(.horizontal, sizeClass == .regular ? 32 : 24)
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

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let schoolName, !schoolName.isEmpty {
                Text(schoolName).font(.subheadline.weight(.medium)).foregroundStyle(DrivyTheme.muted)
            }
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH")))
                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
        }
    }

    private var journeyCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Circle().fill(controller.isCapturing ? DrivyTheme.accent : DrivyTheme.muted).frame(width: 6, height: 6)
                    Text(journeyStatus).font(.caption.weight(.semibold))
                }.foregroundStyle(controller.isCapturing ? DrivyTheme.accent : DrivyTheme.muted)
                Text(controller.activeSession == nil ? "Votre prochain trajet" : "Trajet en cours")
                    .font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                if let session = controller.activeSession {
                    HStack(spacing: 8) {
                        if controller.isCapturing {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(context.date.sessionElapsed(since: session.startedAt)).monospacedDigit()
                            }
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
        .padding(20)
        .background(DrivyTheme.canvas, in: RoundedRectangle(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(DrivyTheme.border.opacity(0.75), lineWidth: 0.5) }
    }

    private var mapPreview: some View {
        Button { presentsMap = true } label: {
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
                Label("Explorer", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(DrivyTheme.surface, in: Capsule()).padding(12)
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Explorer la carte")
    }

    private var nextLessons: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("À venir").font(.title3.weight(.bold))
                Spacer()
                if let openAgenda { Button("Tout voir", action: openAgenda).font(.subheadline.weight(.semibold)).frame(minHeight: 44) }
            }
            if isLoadingAgenda {
                ProgressView("Ouverture de l’agenda…").frame(maxWidth: .infinity, minHeight: 90)
            } else if let agendaError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(agendaError).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    Button("Réessayer") { Task { await loadUpcoming() } }.frame(minHeight: 44)
                }
            } else if upcoming.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "calendar").font(.title2).foregroundStyle(DrivyTheme.muted)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Votre agenda est libre").font(.headline)
                        Text(agendaClient == nil ? "Vos leçons apparaîtront ici lorsque votre école sera connectée." : "Aucune leçon prévue dans les sept prochains jours.")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.vertical, 12)
            } else {
                ForEach(upcoming.prefix(3)) { lesson in
                    upcomingRow(lesson)
                    if lesson.id != upcoming.prefix(3).last?.id { Divider() }
                }
            }
        }
    }

    private func upcomingRow(_ lesson: SchoolLesson) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(lessonTime(lesson.startsAt)).font(.headline.monospacedDigit())
                Text(lessonTime(lesson.endsAt)).font(.caption.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
            }.frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(workspace?.learners.first(where: { $0.id == lesson.learnerId })?.displayName ?? "Leçon de conduite").font(.headline)
                Text("\(lesson.durationMinutes) min · \(lessonDay(lesson.startsAt))").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                Text(lesson.meetingPoint).font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }

    private var historyLink: some View {
        Button {
            historyPath = []; presentsHistory = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath").font(.title3).frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Trajets et bilans").font(.headline).foregroundStyle(DrivyTheme.text)
                    Text("Retrouver les moments enregistrés").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }.padding(.vertical, 16).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(DrivyTheme.muted).accessibilityIdentifier("map-history")
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
                                .background(DrivyTheme.surface, in: Circle())
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
