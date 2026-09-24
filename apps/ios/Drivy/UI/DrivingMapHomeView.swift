import CoreLocation
import MapKit
import Observation
import SwiftUI
import UIKit

/// The map is an explorable background, not a claim that a lesson or GPS capture exists.
/// SchoolHomeView owns the surrounding navigation stack and account toolbar.
struct DrivingMapHomeView: View {
    @Bindable var controller: SessionController
    let schoolName: String?
    let openLearners: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var mapScope
    @State private var location = MapHomeLocationPermission()
    @State private var camera: MapCameraPosition = .region(Self.overview)
    @State private var satellite = false
    @State private var presentsStart = false
    @State private var presentsLive = false
    @State private var presentsHistory = false
    @State private var liveSessionID: UUID?
    @State private var historyPath: [UUID] = []

    // Geographic overview only; never displayed as the person's current position.
    private static let overview = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.8, longitude: 8.2),
        span: MKCoordinateSpan(latitudeDelta: 2.7, longitudeDelta: 4.5)
    )

    private var showsUserLocation: Bool {
        location.isAuthorized && (location.wasRequested || controller.activeSession?.usesGPS == true)
    }

    var body: some View {
        Map(position: $camera, scope: mapScope) {
            if showsUserLocation { UserAnnotation() }
        }
        .mapStyle(satellite ? .hybrid(elevation: .flat) : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { }
        .accessibilityLabel("Carte à explorer")
        .accessibilityHint("Aucun trajet n’est enregistré avant le démarrage volontaire d’une séance.")
        .overlay(alignment: .topTrailing) { mapTools.padding(16) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView { departureCard }
                        .frame(maxWidth: 460, maxHeight: 360)
                        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                } else {
                    departureCard.frame(maxWidth: 460)
                }
                if sizeClass == .regular { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, 8)
        }
        .mapScope(mapScope)
        .tint(DrivyTheme.accent)
        .foregroundStyle(DrivyTheme.text)
        .navigationTitle("Séance")
        .navigationBarTitleDisplayMode(.inline)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: controller.activeSession?.id)
        .onChange(of: location.isAuthorized) { _, allowed in
            if allowed && location.wasRequested { centerOnUser() }
        }
        .sheet(isPresented: $presentsStart, onDismiss: {
            if let session = controller.activeSession {
                liveSessionID = session.id
                presentsLive = true
            }
        }) {
            StartSessionView(controller: controller)
        }
        .fullScreenCover(isPresented: $presentsLive, onDismiss: {
            // The controller exposes selectedSession only after the finish write succeeds.
            // Closing a live map keeps recording; only a finished, persisted session opens its review.
            if controller.activeSession == nil,
               let id = liveSessionID,
               controller.selectedSession?.id == id {
                historyPath = [id]
                presentsHistory = true
            }
            liveSessionID = nil
        }) {
            NavigationStack { LiveSessionView(controller: controller) }
                .tint(DrivyTheme.accent)
        }
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
            }
            .tint(DrivyTheme.accent)
        }
    }

    private var mapTools: some View {
        VStack(spacing: 12) {
            Button { satellite.toggle() } label: {
                Image(systemName: satellite ? "map" : "square.3.layers.3d")
                    .font(.title3.weight(.medium))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .background(DrivyTheme.surface, in: Circle())
            .accessibilityLabel(satellite ? "Afficher le plan" : "Afficher la vue satellite")
            .accessibilityIdentifier("map-style")

            if showsUserLocation {
                MapUserLocationButton(scope: mapScope)
                    .mapControlVisibility(.visible)
                    .frame(minWidth: 48, minHeight: 48)
                    .background(DrivyTheme.surface, in: Circle())
                    .accessibilityLabel("Centrer sur ma position")
            } else {
                Button {
                    location.request()
                    if location.isAuthorized { centerOnUser() }
                } label: {
                    Image(systemName: "location")
                        .font(.title3.weight(.medium))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .background(DrivyTheme.surface, in: Circle())
                .accessibilityLabel("Afficher ma position")
                .accessibilityHint("Demande l’accès à votre position pour centrer la carte, sans enregistrer de trajet.")
                .accessibilityIdentifier("map-locate")
            }
            MapCompass(scope: mapScope)
                .mapControlVisibility(.visible)
                .frame(minWidth: 48, minHeight: 48)
        }
        .shadow(color: .black.opacity(0.10), radius: 12, y: 3)
    }

    private var departureCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: controller.activeSession == nil ? "steeringwheel" : "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.title2)
                    .foregroundStyle(DrivyTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    if let schoolName, !schoolName.isEmpty {
                        Text(schoolName).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                    Text(controller.activeSession == nil ? "Prêt à prendre la route ?" : controller.isCapturing ? "Votre trajet est en cours" : "Enregistrement à vérifier")
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if let session = controller.activeSession {
                activeStatus(session)
            } else {
                Text("Gardez le trajet, les moments importants et votre bilan.")
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if controller.isLoading {
                ProgressView("Ouverture des trajets…").frame(maxWidth: .infinity, minHeight: 52)
            } else {
                Button(action: primaryAction) {
                    Label(controller.activeSession == nil ? "Commencer un trajet" : controller.isCapturing ? "Revenir à la carte" : "Vérifier la sauvegarde",
                          systemImage: controller.activeSession == nil ? "arrow.up.right" : "arrow.right")
                }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(controller.isBusy || (controller.activeSession == nil && controller.errorMessage != nil))
                .accessibilityIdentifier(controller.activeSession == nil ? "new-session" : "resume-session")
            }

            HStack(spacing: 12) {
                Button {
                    historyPath = []
                    presentsHistory = true
                } label: {
                    Label("Historique", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .accessibilityIdentifier("map-history")
                Button(action: openLearners) {
                    Label("Dossiers", systemImage: "person.2")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(DrivyTheme.accent)

            if location.wasRequested && location.isDenied {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Position indisponible. La carte et les trajets sans GPS restent accessibles.")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                    if let settings = URL(string: UIApplication.openSettingsURLString) {
                        Link("Ouvrir les réglages de localisation", destination: settings)
                            .font(.footnote.weight(.medium))
                            .frame(minHeight: 44)
                    }
                }
            }
            if let error = controller.errorMessage {
                InlineErrorView(message: error, retry: controller.isCapturing ? nil : {
                    Task { await controller.load() }
                })
            }
            Label("Trajets conservés sur cet appareil", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(DrivyTheme.muted)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(DrivyTheme.border, lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.08), radius: 20, y: 5)
    }

    private func activeStatus(_ session: DrivingSession) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Label(session.usesGPS ? controller.gpsStatus.label : "Sans GPS", systemImage: session.usesGPS ? "location" : "location.slash")
                Spacer(minLength: 0)
                if controller.isCapturing {
                    TimelineView(.periodic(from: .now, by: 1)) { time in
                        Text(time.date.sessionElapsed(since: session.startedAt)).monospacedDigit()
                    }
                }
            }
            Text(session.usesGPS ? controller.gpsStatus.label : "Sans GPS")
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(DrivyTheme.accent)
    }

    private func primaryAction() {
        if let session = controller.activeSession {
            if controller.isCapturing {
                liveSessionID = session.id
                presentsLive = true
            } else {
                Task { await controller.load() }
            }
        } else {
            presentsStart = true
        }
    }

    private func centerOnUser() {
        camera = .userLocation(followsHeading: false, fallback: .region(Self.overview))
    }
}

/// Display-only permission; recording continues to belong exclusively to SessionController.
@MainActor
@Observable
private final class MapHomeLocationPermission: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var wasRequested = false
    private(set) var status: CLAuthorizationStatus = .notDetermined
    @ObservationIgnored private let manager = CLLocationManager()

    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var isDenied: Bool { status == .denied || status == .restricted }

    override init() {
        super.init()
        status = manager.authorizationStatus
        manager.delegate = self
    }

    func request() {
        wasRequested = true
        status = manager.authorizationStatus
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
    }
}
