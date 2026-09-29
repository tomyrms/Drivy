import Foundation
import Observation

/// Trips of one school scope, newest first, page after page. The server decides which trips
/// this account reads; a late page never restores a closed or changed scope.
@MainActor @Observable final class SchoolTripsWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let client: SchoolCaptureClient
    let pageSize: Int
    private(set) var trips: [SchoolCaptureTrip] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var moreErrorMessage: String?
    private(set) var accessRevoked = false
    private(set) var loadedAt: Date?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var seenCursors: Set<String> = []
    @ObservationIgnored private var invalidated = false

    init(scope: SchoolCommandScope, client: SchoolCaptureClient, pageSize: Int = 50) {
        self.scope = scope; self.client = client; self.pageSize = pageSize
    }

    var isEmpty: Bool { hasLoaded && trips.isEmpty && errorMessage == nil }

    func load() async {
        guard !invalidated, !isLoading else { return }
        let request = UUID(); generation = request
        isLoading = true; isLoadingMore = false; errorMessage = nil; moreErrorMessage = nil
        defer { if current(request) { isLoading = false } }
        do {
            let page = try await client.captures(schoolID: scope.schoolID, limit: pageSize, scope: scope)
            guard current(request) else { return }
            trips = page.items; nextCursor = page.nextCursor; seenCursors = []
            hasLoaded = true; loadedAt = Date(); accessRevoked = false
        } catch {
            guard current(request) else { return }
            fail(error)
        }
    }

    func loadMore() async {
        guard !invalidated, !isLoading, !isLoadingMore, let cursor = nextCursor else { return }
        let request = generation
        isLoadingMore = true; moreErrorMessage = nil
        defer { if current(request) { isLoadingMore = false } }
        do {
            let page = try await client.captures(schoolID: scope.schoolID, cursor: cursor, limit: pageSize, scope: scope)
            guard current(request), nextCursor == cursor else { return }
            guard page.nextCursor != cursor,
                  page.nextCursor.map({ !seenCursors.contains($0) }) ?? true else { throw SchoolCaptureFailure.changed }
            seenCursors.insert(cursor)
            for trip in page.items {
                // A trip seen twice keeps its latest projection, never an older version.
                if let index = trips.firstIndex(where: { $0.id == trip.id }) {
                    if trip.capture.version >= trips[index].capture.version { trips[index] = trip }
                } else { trips.append(trip) }
            }
            nextCursor = page.nextCursor
        } catch {
            guard current(request) else { return }
            if Self.revokesAccess(error) { fail(error) }
            else { moreErrorMessage = Self.message(error) }
        }
    }

    func invalidate() {
        invalidated = true; generation = UUID()
        trips = []; nextCursor = nil; isLoading = false; isLoadingMore = false
        errorMessage = nil; moreErrorMessage = nil; seenCursors = []
    }

    /// Days in server order (newest first); inside a day, the server order is kept.
    func days(now: Date = Date()) -> [SchoolTripDay] { Self.days(trips, now: now) }

    static func days(_ trips: [SchoolCaptureTrip], now: Date) -> [SchoolTripDay] {
        var order: [String] = []
        var grouped: [String: (title: String, trips: [SchoolCaptureTrip])] = [:]
        for trip in trips {
            let key = dayKey(trip)
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = (dayTitle(trip, now: now), [])
            }
            grouped[key]?.trips.append(trip)
        }
        return order.compactMap { key in grouped[key].map { SchoolTripDay(id: key, title: $0.title, trips: $0.trips) } }
    }

    // MARK: Presentation

    static func calendar(_ trip: SchoolCaptureTrip) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_CH")
        calendar.timeZone = TimeZone(identifier: trip.lessonTimeZone) ?? .current
        return calendar
    }

    static func dayKey(_ trip: SchoolCaptureTrip) -> String {
        guard let date = trip.plannedStart else { return "?" }
        let parts = calendar(trip).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// « Aujourd’hui », « Hier », then the date in the lesson’s time zone.
    static func dayTitle(_ trip: SchoolCaptureTrip, now: Date) -> String {
        guard let date = trip.plannedStart else { return "Date indisponible" }
        let calendar = calendar(trip)
        if calendar.isDate(date, inSameDayAs: now) { return "Aujourd’hui" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Hier"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH")
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEEdMMMM" : "EEEEdMMMMyyyy")
        return formatter.string(from: date).capitalizedFirst
    }

    static func time(_ trip: SchoolCaptureTrip) -> String {
        SchoolTrainingFormatting.time(trip.lessonPlannedStart, zone: trip.lessonTimeZone)
    }

    /// Recorded duration of a stopped trip: « 48 min », « 1 h 05 ».
    static func duration(_ capture: SchoolCaptureSession) -> String? {
        guard let stopped = capture.stoppedAt ?? capture.cutoffAt, let end = SchoolLesson.date(stopped),
              let start = SchoolLesson.date(capture.authorizedAt), end > start else { return nil }
        let minutes = max(1, Int((end.timeIntervalSince(start) / 60).rounded()))
        return minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    /// Spoken form of the duration, without the « h » abbreviation.
    static func spokenDuration(_ capture: SchoolCaptureSession) -> String? {
        guard let stopped = capture.stoppedAt ?? capture.cutoffAt, let end = SchoolLesson.date(stopped),
              let start = SchoolLesson.date(capture.authorizedAt), end > start else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_CH")
        formatter.calendar = calendar
        return formatter.string(from: max(60, (end.timeIntervalSince(start) / 60).rounded() * 60))
    }

    /// A badge only for what is unusual: a trip still recording, incomplete, not sent, refused or withdrawn.
    static func badge(_ capture: SchoolCaptureSession) -> SchoolTripBadge? {
        switch capture.publicationState {
        case .withdrawn: return SchoolTripBadge(title: "Retiré", symbol: "minus.circle", tone: .neutral)
        case .deleted: return SchoolTripBadge(title: "Supprimé", symbol: "minus.circle", tone: .neutral)
        case .privateCapture, .published: break
        }
        if capture.captureState == .authorized { return SchoolTripBadge(title: "En cours", symbol: "record.circle", tone: .accent) }
        switch capture.syncState {
        case .synced: break
        case .partial: return SchoolTripBadge(title: "Partiel", symbol: "exclamationmark.circle", tone: .warning)
        case .localOnly, .uploading: return SchoolTripBadge(title: "Pas encore envoyé", symbol: "iphone.and.arrow.forward", tone: .warning)
        case .rejected: return SchoolTripBadge(title: "Envoi refusé", symbol: "xmark.octagon", tone: .danger)
        }
        if capture.captureState == .revoked || capture.captureState == .expired {
            return SchoolTripBadge(title: "Interrompu", symbol: "exclamationmark.circle", tone: .warning)
        }
        return nil
    }

    /// Only a trip the school reconstructed can be replayed.
    static func isReplayable(_ capture: SchoolCaptureSession) -> Bool {
        capture.publicationState == .privateCapture && capture.captureState != .authorized
            && (capture.syncState == .synced || capture.syncState == .partial)
    }

    /// The instructor is named only for an administrator reading someone else’s trip.
    func instructorName(_ trip: SchoolCaptureTrip, viewerRoles: [String]) -> String? {
        let name = trip.instructorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard viewerRoles.contains("ADMIN"), trip.capture.instructorMembershipId != scope.membershipID, !name.isEmpty else { return nil }
        return name
    }

    // MARK: Failures

    static func revokesAccess(_ error: Error) -> Bool {
        error as? SchoolCaptureFailure == .unauthorized || error as? SchoolCaptureFailure == .forbidden
    }

    private static func message(_ error: Error) -> String {
        if error is CancellationError { return "Le chargement a été interrompu. Réessayez." }
        switch error as? SchoolCaptureFailure {
        case .unauthorized: return "Reconnectez-vous pour retrouver vos trajets."
        case .forbidden, .notFound: return "Vos accès ont changé. Actualisez votre école."
        case .unavailable: return "Connexion impossible. Vérifiez le réseau puis réessayez."
        default: return "Les trajets n’ont pas pu être chargés. Réessayez."
        }
    }

    private func fail(_ error: Error) {
        if Self.revokesAccess(error) {
            accessRevoked = true; trips = []; nextCursor = nil; seenCursors = []
        }
        errorMessage = Self.message(error)
    }

    private func current(_ request: UUID) -> Bool { !invalidated && generation == request }
}

struct SchoolTripDay: Identifiable, Equatable {
    let id: String
    let title: String
    let trips: [SchoolCaptureTrip]
}

struct SchoolTripBadge: Equatable {
    let title: String
    let symbol: String
    let tone: DrivyTone
}
