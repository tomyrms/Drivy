import Foundation

enum SchoolCaptureLocationFailure: Error, LocalizedError {
    case permissionRequired, invalidContext, invalidPolicy, alreadyRunning, foregroundRequired, insufficientStorage, diagnosticUnavailable
    var errorDescription: String? {
        switch self {
        case .permissionRequired: "La permission de localisation requise n’est pas disponible. La leçon reste accessible sans GPS."
        case .invalidContext: "Le contexte de capture doit être vérifié avant de démarrer."
        case .invalidPolicy: "Les paramètres du collecteur ne sont pas valides."
        case .alreadyRunning: "Le collecteur doit être arrêté avant un nouveau départ."
        case .foregroundRequired: "Le départ GPS doit être confirmé dans l’application au premier plan."
        case .insufficientStorage: "L’espace disponible ne permet pas de démarrer cette capture locale."
        case .diagnosticUnavailable: "Le diagnostic de cet appareil n’est pas disponible."
        }
    }
}

enum SchoolCaptureLocationPermission: Sendable, Equatable {
    case notDetermined, denied, restricted, foreground, background
    var permitsLocation: Bool { self == .foreground || self == .background }
    var assessmentValue: String {
        switch self {
        case .foreground: "FOREGROUND"
        case .background: "BACKGROUND"
        default: "NONE"
        }
    }
}

// Paramètres techniques explicites à éprouver avec le profil physique. Ce type ne
// représente ni une qualification serveur ni une promesse de fréquence/précision.
struct SchoolCaptureLocationPolicy: Sendable {
    let maximumCallbackAgeSeconds: TimeInterval
    let maximumClockDriftSeconds: TimeInterval
    let signalGapSeconds: TimeInterval
    let minimumFreeBytes: Int64
    let requiresPreciseLocation: Bool
    let allowsBackground: Bool
    let distanceFilterMeters: Double

    init(maximumCallbackAgeSeconds: TimeInterval = 120, maximumClockDriftSeconds: TimeInterval = 1,
         signalGapSeconds: TimeInterval = 60, minimumFreeBytes: Int64 = 256 * 1024 * 1024,
         requiresPreciseLocation: Bool = true, allowsBackground: Bool = true, distanceFilterMeters: Double = 3) throws {
        guard maximumCallbackAgeSeconds.isFinite, (1...300).contains(maximumCallbackAgeSeconds),
              maximumClockDriftSeconds.isFinite, (0.05...5).contains(maximumClockDriftSeconds),
              signalGapSeconds.isFinite, (5...300).contains(signalGapSeconds),
              minimumFreeBytes >= 1_048_576, distanceFilterMeters.isFinite,
              (0...100).contains(distanceFilterMeters) else { throw SchoolCaptureLocationFailure.invalidPolicy }
        self.maximumCallbackAgeSeconds = maximumCallbackAgeSeconds
        self.maximumClockDriftSeconds = maximumClockDriftSeconds
        self.signalGapSeconds = signalGapSeconds
        self.minimumFreeBytes = minimumFreeBytes
        self.requiresPreciseLocation = requiresPreciseLocation
        self.allowsBackground = allowsBackground
        self.distanceFilterMeters = distanceFilterMeters
    }
}

// Référence prise dès réception de la réponse AP154 contrôlée. Elle ne se persiste
// pas et ne remplace pas le début de requête monotone utilisé par le bail signé.
struct SchoolCaptureClockReference: Sendable {
    let serverTime: Date
    let receivedAt: ContinuousClock.Instant
    init(serverTime: String, receivedAt: ContinuousClock.Instant) throws {
        guard let date = SchoolLesson.date(serverTime) else { throw SchoolCaptureLocationFailure.invalidContext }
        self.serverTime = date
        self.receivedAt = receivedAt
    }
}

struct SchoolCaptureLocationSegment: Sendable {
    let id: UUID
    let captureID: UUID
    let scope: SchoolCommandScope
    let startedAt: String
    let lease: SchoolCaptureLease
    let policy: SchoolCaptureLocationPolicy
    let wallStartedAt: Date
    let monotonicStartedAt: ContinuousClock.Instant
    let mappedStartedAt: Date

    // L'initialiseur est partagé avec l'adaptateur dans le même module ; la source
    // vérifie à nouveau bail, portée et génération avant tout appel système.
    init(id: UUID, captureID: UUID, scope: SchoolCommandScope, startedAt: String, lease: SchoolCaptureLease,
         policy: SchoolCaptureLocationPolicy, wallStartedAt: Date, monotonicStartedAt: ContinuousClock.Instant,
         mappedStartedAt: Date) {
        self.id = id; self.captureID = captureID; self.scope = scope; self.startedAt = startedAt
        self.lease = lease; self.policy = policy; self.wallStartedAt = wallStartedAt
        self.monotonicStartedAt = monotonicStartedAt; self.mappedStartedAt = mappedStartedAt
    }

    func mappedDate(at instant: ContinuousClock.Instant) -> Date {
        mappedStartedAt.addingTimeInterval(max(0, SchoolCaptureLocationTime.seconds(monotonicStartedAt.duration(to: instant))))
    }
}

struct SchoolCaptureLocationStop: Sendable {
    let handle: SchoolCaptureSegmentHandle
    let stoppedAt: String
}

enum SchoolCaptureLocationInterruption: Sendable {
    case permissionLost, precisionReduced, expired, scopeChanged, signalLost, clockChanged, systemPaused, deviceFailure, storageLow
    var segmentEndReason: SchoolCaptureManifest.EndReason {
        switch self {
        case .permissionLost, .precisionReduced: .permissionLost
        case .expired: .expired
        case .signalLost, .systemPaused: .signalLost
        default: .other
        }
    }
    var stopReason: SchoolCaptureLocalStopReason {
        switch self {
        case .permissionLost, .precisionReduced: .permissionLost
        case .expired: .expired
        default: .deviceError
        }
    }
}

enum SchoolCaptureLocationEvent: Sendable {
    case diagnosticChanged
    case measurements(handle: SchoolCaptureSegmentHandle, values: [SchoolCaptureMeasurement])
    case interrupted(SchoolCaptureLocationInterruption, SchoolCaptureLocationStop)
}

struct SchoolCaptureDeviceSnapshot: Sendable {
    let permission: SchoolCaptureLocationPermission
    let preciseLocation: Bool
    let deviceClass: String
    let modelCode: String
    let osVersion: String
    let appBuild: String
    let sampleAgeSeconds: Int?
    let horizontalAccuracyMeters: Double?
    // Strictement local : cette valeur n'entre pas dans une commande AP190.
    let availableBytesLocally: Int64?
}

enum SchoolCaptureLocationTime {
    static func seconds(_ duration: Duration) -> TimeInterval {
        let value = duration.components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
    static func millisecondDate(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1000) / 1000)
    }
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
