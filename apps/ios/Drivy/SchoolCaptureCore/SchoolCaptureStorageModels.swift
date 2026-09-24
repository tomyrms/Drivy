import Foundation

enum SchoolCaptureStorageFailure: Error, LocalizedError, Equatable {
    case unavailable, keyUnavailable, unsupportedSchema, invalidContext, missingCapture
    case alreadyActive, closed, invalidMeasurement, manifestSealed, uncertainCommand, changedScope, invalidReceipt, capacity

    var errorDescription: String? {
        switch self {
        case .unavailable: "L’écriture chiffrée de la capture n’a pas pu être confirmée."
        case .keyUnavailable: "La clé protégée de cette capture n’est pas accessible."
        case .unsupportedSchema: "Ce journal demande une version plus récente de Drivy."
        case .invalidContext: "Le contexte de cette capture n’est pas valide."
        case .missingCapture: "Cette capture n’est pas présente dans ce journal."
        case .alreadyActive: "Une capture doit être arrêtée avant d’en ouvrir une autre."
        case .closed: "Le collecteur de cette capture est arrêté."
        case .invalidMeasurement: "Cette mesure ne peut pas être rattachée au segment courant."
        case .manifestSealed: "Le manifeste de cette capture est déjà scellé."
        case .uncertainCommand: "Une opération déjà envoyée doit être rapprochée avec l’école."
        case .changedScope: "Les droits ont changé. Le journal conserve l’opération dans son contexte d’origine."
        case .invalidReceipt: "L’accusé reçu ne correspond pas à l’opération conservée."
        case .capacity: "La limite locale de cette capture est atteinte."
        }
    }
}

struct SchoolCaptureStoredSession: Codable, Sendable, Identifiable {
    enum LocalState: String, Codable, Sendable { case ready, recording, paused, stopped, interrupted }
    let id: UUID
    let scope: SchoolCommandScope
    let deviceID: UUID
    let authorization: SchoolCaptureAuthorization
    var serverCapture: SchoolCaptureSession
    var state: LocalState
    var stoppedAt: String?
    var stopOperationID: UUID?
    var manifest: [SchoolCaptureManifest]?
}

struct SchoolCaptureSegmentHandle: Codable, Sendable, Equatable {
    let captureID: UUID
    let segmentID: UUID
    let segmentIndex: Int
    let generationID: UUID
}

struct SchoolCaptureStoredSegment: Codable, Sendable, Identifiable {
    let id: UUID
    let handle: SchoolCaptureSegmentHandle
    let startedAt: String
    let reason: SchoolCaptureChunkBody.StartReason
    var pointCount: Int
    var chunkedPointCount: Int
    var chunkCount: Int
    var lastSequence: Int?
    var lastElapsedMs: Int?
    var lastCapturedAt: String?
    var endReason: SchoolCaptureManifest.EndReason?
    var endedAt: String?
}

// Mesure scolaire déjà rattachée au mapping d'horloge du segment. Ce type ne reçoit
// ni DrivingSession ni RecordedPoint G0 ; les parcours EXAMPLE n'ont aucun adaptateur.
struct SchoolCaptureMeasurement: Sendable {
    let capturedAt: String
    let elapsedMs: Int
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
}

struct SchoolCaptureQueuedMutation: Codable, Sendable, Identifiable {
    enum State: String, Codable, Sendable { case queued, attempted, acknowledged, refused }
    let mutation: SchoolCapturePendingMutation
    let deviceID: UUID
    var state: State
    var attemptCount: Int
    var resultBody: Data?
    var id: UUID { mutation.id }
}

struct SchoolCaptureStoredChunk: Codable, Sendable, Identifiable {
    let id: UUID
    let captureID: UUID
    let segmentID: UUID
    let index: Int
    let body: SchoolCaptureChunkBody
    var receipt: SchoolCaptureChunkReceipt?
}

enum SchoolCaptureLocalStopReason: String, Sendable {
    case lessonEnded = "LESSON_ENDED", userStop = "USER_STOP", learnerRefusal = "LEARNER_REFUSAL"
    case permissionLost = "PERMISSION_LOST", expired = "EXPIRED", deviceError = "DEVICE_ERROR"
    var segmentReason: SchoolCaptureManifest.EndReason {
        switch self {
        case .permissionLost: .permissionLost
        case .expired: .expired
        case .deviceError: .other
        default: .stop
        }
    }
}
