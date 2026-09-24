import Foundation

enum SchoolCaptureMutationKind: String, Codable, Sendable {
    case assessDevice, recordChoice, startCapture, uploadChunk, stopCapture, finalizeCapture
    var operationType: String {
        switch self {
        case .assessDevice: "ASSESS_CAPTURE_DEVICE"
        case .recordChoice: "RECORD_RECORDING_CHOICE"
        case .startCapture: "START_CAPTURE"
        case .uploadChunk: "UPLOAD_TRACK_CHUNK"
        case .stopCapture: "STOP_CAPTURE"
        case .finalizeCapture: "FINALIZE_CAPTURE"
        }
    }
    var resourceType: String {
        switch self {
        case .assessDevice: "DeviceAssessment"
        case .recordChoice: "RecordingChoice"
        default: "CaptureSession"
        }
    }
}

/// Intention à écrire dans le journal spécialisé AVANT émission. Les octets ne sont
/// pas reconstruits lors d’une reprise ; les preuves signées restent dans le coffre.
struct SchoolCapturePendingMutation: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let scope: SchoolCommandScope
    let kind: SchoolCaptureMutationKind
    let targetID: UUID
    let segmentID: UUID?
    let chunkIndex: Int?
    let expectedVersion: Int?
    let createdAt: Date
    let body: Data

    var operationType: String { kind.operationType }
    var isValid: Bool {
        guard scope.accessEpoch > 0, createdAt.timeIntervalSince1970.isFinite,
              !body.isEmpty, body.count <= 512 * 1024,
              let url = URLComponents(string: scope.apiBaseURL), url.scheme == "https",
              url.host?.isEmpty == false, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              let value = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              UUID(uuidString: value["operationId"] as? String ?? "") == id else { return false }
        if kind == .uploadChunk {
            guard segmentID != nil, let chunkIndex, (0..<1000).contains(chunkIndex), expectedVersion == nil,
                  let chunk = try? JSONDecoder().decode(SchoolCaptureChunkBody.self, from: body),
                  (0..<200).contains(chunk.segmentIndex), (1...1000).contains(chunk.points.count),
                  chunk.points.allSatisfy(\.isValid), SchoolLesson.date(chunk.segmentStartedAt) != nil,
                  chunk.contentHash.count == 64, chunk.contentHash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  !chunk.signedUploadAuthorization.isEmpty, chunk.signedUploadAuthorization.utf8.count <= 12_000 else { return false }
        } else {
            guard segmentID == nil, chunkIndex == nil else { return false }
            if kind == .startCapture || kind == .finalizeCapture {
                guard let expectedVersion, expectedVersion > 0 else { return false }
            } else if expectedVersion != nil { return false }
        }
        return true
    }

    func matches(_ receipt: SchoolOperationReceipt) -> Bool {
        guard receipt.operationId == id, receipt.commandType == operationType,
              receipt.resourceType == kind.resourceType, receipt.resourceVersion > 0,
              SchoolLesson.date(receipt.committedAt) != nil else { return false }
        switch kind {
        case .uploadChunk, .stopCapture, .finalizeCapture: return receipt.resourceId == targetID
        case .assessDevice, .recordChoice, .startCapture: return true
        }
    }

    static func make<Body: Encodable>(id: UUID, scope: SchoolCommandScope, kind: SchoolCaptureMutationKind,
                                       targetID: UUID, segmentID: UUID? = nil, chunkIndex: Int? = nil,
                                       expectedVersion: Int? = nil, body: Body) throws -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let value = Self(id: id, scope: scope, kind: kind, targetID: targetID, segmentID: segmentID,
                         chunkIndex: chunkIndex, expectedVersion: expectedVersion, createdAt: Date(), body: try encoder.encode(body))
        guard value.isValid else { throw SchoolCaptureFailure.invalidResponse }
        return value
    }
}

enum SchoolCaptureMutationResult: Sendable {
    case assessment(SchoolDeviceAssessment)
    case choice(SchoolRecordingChoice)
    case authorization(SchoolCaptureAuthorization)
    case chunk(SchoolCaptureChunkReceipt)
    case capture(SchoolCaptureSession)
}

struct SchoolRecordingChoiceBody: Codable, Sendable {
    let operationId: UUID
    let lessonId: UUID?
    let status: SchoolRecordingChoice.Status
    let noticeVersionId: UUID
    let source: SchoolRecordingChoice.Source
    func encode(to encoder: any Encoder) throws {
        var value = encoder.container(keyedBy: CodingKeys.self)
        try value.encode(operationId, forKey: .operationId)
        try value.encode(lessonId, forKey: .lessonId)
        try value.encode(status, forKey: .status)
        try value.encode(noticeVersionId, forKey: .noticeVersionId)
        try value.encode(source, forKey: .source)
    }
}

struct SchoolDeviceAssessmentBody: Codable, Sendable {
    let operationId: UUID
    let platform: String
    let deviceClass: String
    let modelCode: String
    let osVersion: String
    let appBuild: String
    let permission: String
    let preciseLocation: Bool
    let sampleAgeSeconds: Int?
    let horizontalAccuracyMeters: Double?
    let freeBytes: Int64
    let networkAvailable: Bool
    func encode(to encoder: any Encoder) throws {
        var value = encoder.container(keyedBy: CodingKeys.self)
        try value.encode(operationId, forKey: .operationId)
        try value.encode(platform, forKey: .platform)
        try value.encode(deviceClass, forKey: .deviceClass)
        try value.encode(modelCode, forKey: .modelCode)
        try value.encode(osVersion, forKey: .osVersion)
        try value.encode(appBuild, forKey: .appBuild)
        try value.encode(permission, forKey: .permission)
        try value.encode(preciseLocation, forKey: .preciseLocation)
        try value.encode(sampleAgeSeconds, forKey: .sampleAgeSeconds)
        try value.encode(horizontalAccuracyMeters, forKey: .horizontalAccuracyMeters)
        try value.encode(freeBytes, forKey: .freeBytes)
        try value.encode(networkAvailable, forKey: .networkAvailable)
    }
}

struct SchoolStartCaptureBody: Codable, Sendable {
    let operationId: UUID
    let deviceId: UUID
    let choiceId: UUID
    let choiceVersion: Int
    let noticeVersionId: UUID
    let explicitStartConfirmed: Bool
    let deviceAssessmentId: UUID
}

struct SchoolStopCaptureBody: Codable, Sendable {
    let operationId: UUID
    let stoppedAt: String
    let reason: String
    let segments: [SchoolCaptureManifest]
    let localCollectorStopped: Bool
}

struct SchoolFinalizeCaptureBody: Codable, Sendable {
    let operationId: UUID
    let segments: [SchoolCaptureManifest]
    let allowPartial: Bool
}

struct SchoolRecordingNotice: Decodable, Sendable {
    let noticeVersionId: UUID
    let noticeText: String
    let retentionText: String
    let contactEmail: String
    let approvedAt: String
}
