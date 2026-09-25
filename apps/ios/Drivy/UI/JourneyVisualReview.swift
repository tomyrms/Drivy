#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// An isolated simulator screenshot harness. Not compiled into the device IPA.
/// Coordinates and observations below are synthetic and never reach an API.
struct JourneyVisualReview: View {
    let screen: String
    @State private var controller: SessionController?
    @State private var replayID: UUID?
    @State private var report: ReportRoute?
    @State private var failure: String?

    private struct ReportRoute: Identifiable {
        let controller: SessionController
        let context: ObservationContext
        let sessionStartedAt: Date
        var id: UUID { context.id }
    }

    var body: some View {
        Group {
            if ["catalog", "dossier", "bilan"].contains(screen) {
                SchoolVisualReview(screen: screen)
            } else if let controller {
                NavigationStack {
                    switch screen {
                    case "live", "report", "without-gps":
                        LiveSessionView(controller: controller)
                    case "replay":
                        if let replayID { SessionDetailView(controller: controller, sessionID: replayID) }
                    case "finish":
                        if let replayID, let session = controller.sessions.first(where: { $0.id == replayID }) {
                            JourneyFinishView(controller: controller, session: session, openReplay: {}, close: {})
                        }
                    case "journey-history":
                        SessionHistoryView(controller: controller)
                    default:
                        DrivingMapHomeView(controller: controller, schoolName: "École · exemple visuel", openLearners: {})
                    }
                }
            } else if let failure {
                ContentUnavailableView("Capture indisponible", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else { ProgressView("Préparation visuelle…") }
        }
        .environment(\.locale, Locale(identifier: "fr_CH"))
        .tint(DrivyTheme.accent)
        .sheet(item: $report) { route in
            ObservationComposer(controller: route.controller, context: route.context, sessionStartedAt: route.sessionStartedAt)
        }
        .task { await prepare() }
    }

    @MainActor private func prepare() async {
        guard !["catalog", "dossier", "bilan"].contains(screen) else { return }
        guard controller == nil else { return }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DrivyVisual-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = try SQLCipherSessionStore(url: directory.appendingPathComponent("visual.sqlite"), key: Data(repeating: 0xAC, count: 32), protectFiles: false)
            let source = VisualLocationSource()
            let model = SessionController(store: store, location: source)
            if ["replay", "finish", "journey-history"].contains(screen) {
                let session = DrivingSession(startedAt: Date().addingTimeInterval(-900), usesGPS: true)
                try await store.create(session)
                let segmentID = UUID()
                for (index, coordinate) in Self.coordinates.enumerated() {
                    let date = session.startedAt.addingTimeInterval(Double(index) * 90)
                    let point = RecordedPoint(id: UUID(), timestamp: date, receivedAt: date,
                        latitude: coordinate.0, longitude: coordinate.1, accuracy: 5, segmentID: segmentID)
                    try await store.append(point, to: session.id)
                    if [2, 5, 8].contains(index) {
                        try await store.append(LessonObservation(id: UUID(), observedAt: date, theme: index == 5 ? .priority : .observation,
                            status: index == 2 ? .toWorkOn : index == 5 ? .attention : .positive, note: "", anchorPointID: point.id), to: session.id)
                    }
                }
                try await store.finish(session.id, at: session.startedAt.addingTimeInterval(900), state: .completed)
                replayID = session.id
                await model.load()
            } else {
                await model.load()
                await model.startSession(useGPS: screen != "without-gps")
                if screen != "without-gps" {
                    let now = Date()
                    source.onEvent?(.samples(Self.coordinates.enumerated().map { index, coordinate in
                        LocationSample(timestamp: now.addingTimeInterval(Double(index) * 0.001), latitude: coordinate.0, longitude: coordinate.1, horizontalAccuracy: 5)
                    }))
                    await model.awaitPendingWrites()
                }
                if let session = model.activeSession {
                    for (index, theme) in [ObservationTheme.observation, .priority, .anticipation].enumerated() {
                        let point = session.points.dropFirst(index * 3).first
                        let context = ObservationContext(id: UUID(), sessionID: session.id,
                            observedAt: point?.timestamp ?? Date(), anchorPointID: point?.id)
                        await model.addObservation(theme: theme, status: index == 0 ? .toWorkOn : index == 1 ? .attention : .positive, note: "", context: context)
                    }
                }
            }
            controller = model
            if screen == "report" {
                try await Task.sleep(for: .milliseconds(400))
                if let session = model.activeSession, let context = model.beginObservation() {
                    report = ReportRoute(controller: model, context: context, sessionStartedAt: session.startedAt)
                }
            }
        } catch { failure = error.localizedDescription }
    }

    private static let coordinates: [(Double, Double)] = [
        (46.9901, 6.9303), (46.9904, 6.9305), (46.9907, 6.9307),
        (46.9910, 6.9309), (46.9913, 6.9311), (46.9915, 6.9313),
        (46.9913, 6.9320), (46.9911, 6.9327), (46.9909, 6.9334),
        (46.9907, 6.9341)
    ]
}

@MainActor private final class VisualLocationSource: LocationSource {
    var permission: LocationPermission { .allowed }
    var onEvent: (@MainActor (LocationEvent) -> Void)?
    func requestPermission() { }
    func start() { }
    func stop() { }
}
#endif
