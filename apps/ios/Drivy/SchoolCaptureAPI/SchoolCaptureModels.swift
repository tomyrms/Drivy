import Foundation

// DTO du contrat AP152–160 / AP190–191. Aucune autorisation ne découle du décodage seul.
struct SchoolRecordingChoice: Codable, Sendable, Equatable, Identifiable {
    enum Status: String, Codable, Sendable { case allowed = "ALLOWED", refused = "REFUSED", unknown = "UNKNOWN" }
    enum Source: String, Codable, Sendable { case own = "SELF", verbal = "RECORDED_VERBAL" }
    let id: UUID
    let schoolId: UUID
    let version: Int
    let learnerId: UUID
    let lessonId: UUID?
    let status: Status
    let noticeVersionId: UUID
    let recordedBy: UUID
    let recordedAt: String
    let source: Source
}

struct SchoolCaptureSession: Codable, Sendable, Equatable, Identifiable {
    enum State: String, Codable, Sendable { case authorized = "AUTHORIZED", stopped = "STOPPED", revoked = "REVOKED", expired = "EXPIRED" }
    enum SyncState: String, Codable, Sendable { case localOnly = "LOCAL_ONLY", uploading = "UPLOADING", synced = "SYNCED", partial = "PARTIAL", rejected = "REJECTED" }
    enum PublicationState: String, Codable, Sendable { case privateCapture = "PRIVATE", published = "PUBLISHED", withdrawn = "WITHDRAWN", deleted = "DELETED" }
    let id: UUID
    let schoolId: UUID
    let version: Int
    let lessonId: UUID
    let learnerId: UUID
    let instructorMembershipId: UUID
    let deviceId: UUID
    let choiceId: UUID
    let authorizedAt: String
    let expiresAt: String
    let stoppedAt: String?
    let cutoffAt: String?
    let uploadDeadline: String
    let captureState: State
    let syncState: SyncState
    let publicationState: PublicationState
    let deviceAssessmentId: UUID

    var hasValidTimeline: Bool {
        guard version > 0, let start = SchoolLesson.date(authorizedAt),
              let expiry = SchoolLesson.date(expiresAt), let upload = SchoolLesson.date(uploadDeadline),
              start < expiry, expiry <= upload else { return false }
        if let stoppedAt, SchoolLesson.date(stoppedAt) == nil { return false }
        if let cutoffAt {
            guard let cutoff = SchoolLesson.date(cutoffAt), cutoff >= start, cutoff <= expiry else { return false }
        }
        return true
    }
}

struct SchoolCaptureAuthorization: Codable, Sendable {
    let capture: SchoolCaptureSession
    let signedCaptureAuthorization: String
    let serverTime: String
    let signedUploadAuthorization: String
}

struct SchoolDeviceAssessment: Codable, Sendable, Equatable, Identifiable {
    enum Status: String, Codable, Sendable { case qualified = "QUALIFIED", unsupported = "UNSUPPORTED", needsCheck = "NEEDS_CHECK" }
    let id: UUID
    let schoolId: UUID
    let version: Int
    let deviceId: UUID
    let membershipId: UUID
    let platform: String
    let deviceClass: String
    let modelCode: String
    let osVersion: String
    let appBuild: String
    let qualificationProfileVersion: String
    let status: Status
    let assessedAt: String
    let expiresAt: String
    let blockers: [SchoolActionBlocker]
}

struct SchoolCapturePoint: Codable, Sendable, Equatable {
    let sequence: Int
    let elapsedMs: Int
    let capturedAt: String
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double

    var isValid: Bool {
        (0...2_147_483_646).contains(sequence) && (0...10_800_000).contains(elapsedMs) && SchoolLesson.date(capturedAt) != nil
            && latitude.isFinite && longitude.isFinite && accuracyMeters.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude) && accuracyMeters >= 0
    }
}

struct SchoolCaptureChunkReceipt: Codable, Sendable, Equatable {
    let captureId: UUID
    let segmentId: UUID
    let chunkIndex: Int
    let contentHash: String
    let acknowledgedAt: String
    let duplicate: Bool
}

struct SchoolCaptureManifest: Codable, Sendable, Equatable {
    enum EndReason: String, Codable, Sendable {
        case stop = "STOP", pause = "PAUSE", appTerminated = "APP_TERMINATED", permissionLost = "PERMISSION_LOST"
        case signalLost = "SIGNAL_LOST", expired = "EXPIRED", other = "OTHER"
    }
    let segmentId: UUID
    let segmentIndex: Int
    let expectedChunkIndices: [Int]
    let expectedPointCount: Int
    let lastSequence: Int?
    let endReason: EndReason

    var isValid: Bool {
        guard segmentIndex >= 0, expectedPointCount >= 0, expectedChunkIndices.count <= 1000,
              Set(expectedChunkIndices).count == expectedChunkIndices.count,
              expectedChunkIndices.allSatisfy({ $0 >= 0 }) else { return false }
        if expectedPointCount == 0 { return expectedChunkIndices.isEmpty && lastSequence == nil }
        return !expectedChunkIndices.isEmpty && (lastSequence.map { $0 >= 0 } ?? false)
    }

    // Le contrat exige un null explicite pour un segment vide.
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(segmentId, forKey: .segmentId)
        try values.encode(segmentIndex, forKey: .segmentIndex)
        try values.encode(expectedChunkIndices, forKey: .expectedChunkIndices)
        try values.encode(expectedPointCount, forKey: .expectedPointCount)
        try values.encode(lastSequence, forKey: .lastSequence)
        try values.encode(endReason, forKey: .endReason)
    }
}

struct SchoolPrivateReplaySegment: Codable, Sendable, Equatable {
    let segmentId: UUID
    let segmentIndex: Int
    let points: [SchoolCapturePoint]
    let hasGapBefore: Bool
    let qualityLabel: String
    let continuesFromPreviousPage: Bool
    let continuesOnNextPage: Bool
}

struct SchoolPrivateGeoObservation: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let lessonId: UUID
    let trainingId: UUID
    let draftId: UUID?
    let captureId: UUID?
    let segmentId: UUID?
    let pointSequence: Int?
    let competencyId: UUID?
    let text: String
    let origin: String?
    let observedAt: String?
    let eventKind: String?
    let eventStatus: String?
    let authorMembershipId: UUID?
}

// Lecture privée dédiée : aucun repli vers cette route depuis une révision publiée.
struct SchoolPrivateReplayPage: Codable, Sendable {
    let captureId: UUID
    let quality: String
    let publicationState: SchoolCaptureSession.PublicationState
    let segments: [SchoolPrivateReplaySegment]
    let observations: [SchoolPrivateGeoObservation]
    let nextCursor: String?
    let generatedAt: String
    let reportRevisionId: UUID?
    let geometrySnapshotId: UUID?
}

struct SchoolCapturePublicKeys: Decodable, Sendable {
    struct Key: Decodable, Sendable {
        let kty: String
        let crv: String
        let x: String
        let kid: String
        let alg: String
        let use: String
    }
    let keys: [Key]
}
