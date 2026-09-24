import CryptoKit
import Foundation

// La connexion non Sendable reste confinée dans cet acteur. Aucun appel réseau,
// aucune source GPS et aucun accès au magasin G0 ne sont effectués ici.
actor SQLCipherSchoolCaptureStore {
    private let database: CipherConnection
    private let url: URL
    private let protectFiles: Bool
    private let deviceID: UUID
    private var leases: [UUID: SchoolCaptureLease] = [:]
    private var leaseScopes: [UUID: SchoolCommandScope] = [:]
    private let chunkSize = 250

    static func openDefault() async throws -> SQLCipherSchoolCaptureStore {
        try await Task.detached(priority: .utility) {
            let directory = try SchoolCaptureProtectedStorage.directory()
            let url = directory.appendingPathComponent("capture-v1.sqlite")
            let exists = ["", "-wal", "-shm", "-journal"].contains {
                FileManager.default.fileExists(atPath: url.path + $0)
            }
            let key = try SchoolCaptureProtectedStorage.loadOrCreateKey(databaseExists: exists)
            return try SQLCipherSchoolCaptureStore(url: url, key: key)
        }.value
    }

    init(url: URL, key: Data, protectFiles: Bool = true, installationID: UUID = UUID()) throws {
        guard key.count == 32 else { throw SchoolCaptureStorageFailure.keyUnavailable }
        self.url = url
        self.protectFiles = protectFiles
        if protectFiles { try ProtectedStorage.protectDatabaseFiles(at: url) }
        let database = try CipherConnection(url: url, key: key)
        try database.execute("PRAGMA fullfsync=ON; PRAGMA checkpoint_fullfsync=ON;")
        let version = try database.integer("PRAGMA user_version")
        guard version <= 1 else { throw SchoolCaptureStorageFailure.unsupportedSchema }
        if version == 0 {
            try database.transaction {
                let lockedVersion = try database.integer("PRAGMA user_version")
                guard lockedVersion <= 1 else { throw SchoolCaptureStorageFailure.unsupportedSchema }
                if lockedVersion == 1 { return }
                try database.execute("""
                    CREATE TABLE installation(id INTEGER PRIMARY KEY CHECK(id=1),data BLOB NOT NULL);
                    CREATE TABLE capture(id TEXT PRIMARY KEY,workspace TEXT NOT NULL,device_id TEXT NOT NULL,state TEXT NOT NULL,data BLOB NOT NULL);
                    CREATE UNIQUE INDEX one_local_collector ON capture(device_id) WHERE state IN('ready','recording','paused');
                    CREATE TABLE segment(id TEXT PRIMARY KEY,capture_id TEXT NOT NULL REFERENCES capture(id),segment_index INTEGER NOT NULL,state TEXT NOT NULL,data BLOB NOT NULL,UNIQUE(capture_id,segment_index));
                    CREATE UNIQUE INDEX one_open_segment ON segment(capture_id) WHERE state='open';
                    CREATE TABLE sample(segment_id TEXT NOT NULL REFERENCES segment(id),sequence INTEGER NOT NULL,data BLOB NOT NULL,PRIMARY KEY(segment_id,sequence));
                    CREATE TABLE chunk(id TEXT PRIMARY KEY,capture_id TEXT NOT NULL REFERENCES capture(id),segment_id TEXT NOT NULL REFERENCES segment(id),chunk_index INTEGER NOT NULL,data BLOB NOT NULL,UNIQUE(segment_id,chunk_index));
                    CREATE TABLE mutation(id TEXT PRIMARY KEY,workspace TEXT NOT NULL,scope_hash TEXT NOT NULL,device_id TEXT NOT NULL,kind TEXT NOT NULL,target_id TEXT NOT NULL,state TEXT NOT NULL,created_at REAL NOT NULL,data BLOB NOT NULL);
                    CREATE INDEX mutation_queue ON mutation(workspace,device_id,state,created_at);
                    PRAGMA user_version=1;
                    """)
                try database.execute("INSERT INTO installation(id,data) VALUES(1,?)", [.blob(try JSONEncoder().encode(installationID))])
            }
        }
        guard let storedDevice = try database.records("SELECT data FROM installation WHERE id=1", as: UUID.self).first else {
            throw SchoolCaptureStorageFailure.unavailable
        }
        deviceID = storedDevice
        if protectFiles { try ProtectedStorage.protectDatabaseFiles(at: url) }
        self.database = database
    }

    func installationID() -> UUID { deviceID }

    func invalidateLeases(scope: SchoolCommandScope? = nil) {
        guard let scope else { leases.removeAll(); leaseScopes.removeAll(); return }
        for id in leaseScopes.filter({ $0.value == scope }).keys {
            leases.removeValue(forKey: id)
            leaseScopes.removeValue(forKey: id)
        }
    }

    func stage(_ mutation: SchoolCapturePendingMutation) throws {
        try write { try insertMutation(mutation) }
    }

    // Les opérations d'un ancien epoch restent visibles comme opérations à rapprocher.
    // markAttempted refuse leur émission sous un autre scope : aucun rebinding implicite.
    func pending(scope: SchoolCommandScope, deviceID requestedDevice: UUID) throws -> [SchoolCaptureQueuedMutation] {
        guard requestedDevice == deviceID else { throw SchoolCaptureStorageFailure.invalidContext }
        return try database.records("SELECT data FROM mutation WHERE workspace=? AND device_id=? AND state IN('queued','attempted') ORDER BY created_at,id",
            [.text(workspace(scope)), .text(deviceID.uuidString)], as: SchoolCaptureQueuedMutation.self)
    }

    func queuedMutation(id: UUID, scope: SchoolCommandScope) throws -> SchoolCaptureQueuedMutation {
        try mutation(id, scope: scope)
    }

    @discardableResult
    func markAttempted(id: UUID, scope: SchoolCommandScope) throws -> SchoolCapturePendingMutation {
        var result: SchoolCapturePendingMutation?
        try write {
            var queued = try mutation(id, scope: scope)
            guard queued.state == .queued || queued.state == .attempted else { throw SchoolCaptureStorageFailure.uncertainCommand }
            if queued.mutation.kind == .uploadChunk {
                let capture = try session(queued.mutation.targetID, scope: scope)
                guard capture.serverCapture.publicationState == .privateCapture else { throw SchoolCaptureStorageFailure.closed }
                let body = try JSONDecoder().decode(SchoolCaptureChunkBody.self, from: queued.mutation.body)
                try validateUploadBounds(body, capture: capture)
            }
            queued.state = .attempted
            queued.attemptCount += 1
            try save(queued)
            result = queued.mutation
        }
        guard let result else { throw SchoolCaptureStorageFailure.unavailable }
        return result
    }

    func acknowledge(id: UUID, scope: SchoolCommandScope, result: SchoolCaptureMutationResult) throws {
        if case .authorization(let authorization) = result, authorization.capture.captureState != .authorized {
            leases.removeValue(forKey: authorization.capture.id)
        }
        try write {
            var queued = try mutation(id, scope: scope)
            guard queued.state != .queued else { throw SchoolCaptureStorageFailure.invalidReceipt }
            let bytes = try resultData(result, for: queued.mutation)
            switch result {
            case .authorization(let authorization):
                // Une réponse tardive terminale rapproche AP154 sans installer de bail.
                // AUTHORIZED exige toujours acceptAuthorization et sa preuve vérifiée.
                let remote = authorization.capture
                guard remote.captureState != .authorized else { throw SchoolCaptureStorageFailure.invalidReceipt }
                let existing = try database.records("SELECT data FROM capture WHERE id=?", [.text(remote.id.uuidString)], as: SchoolCaptureStoredSession.self).first
                if var existing {
                    guard existing.scope == scope, existing.deviceID == deviceID,
                          existing.serverCapture.lessonId == remote.lessonId else { throw SchoolCaptureStorageFailure.invalidContext }
                    if remote.version >= existing.serverCapture.version { existing.serverCapture = remote; try save(existing) }
                } else {
                    let capture = SchoolCaptureStoredSession(id: remote.id, scope: scope, deviceID: deviceID,
                        authorization: authorization, serverCapture: remote, state: .interrupted,
                        stoppedAt: remote.stoppedAt ?? remote.cutoffAt, stopOperationID: nil, manifest: nil)
                    try insert(capture)
                }
            case .chunk(let receipt):
                var chunk = try storedChunk(id)
                guard receipt.captureId == chunk.captureID, receipt.segmentId == chunk.segmentID,
                      receipt.chunkIndex == chunk.index, receipt.contentHash == chunk.body.contentHash,
                      SchoolLesson.date(receipt.acknowledgedAt) != nil else { throw SchoolCaptureStorageFailure.invalidReceipt }
                if let previous = chunk.receipt {
                    guard previous.captureId == receipt.captureId, previous.segmentId == receipt.segmentId,
                          previous.chunkIndex == receipt.chunkIndex, previous.contentHash == receipt.contentHash,
                          previous.acknowledgedAt == receipt.acknowledgedAt else { throw SchoolCaptureStorageFailure.invalidReceipt }
                } else {
                    chunk.receipt = receipt
                    try database.execute("UPDATE chunk SET data=? WHERE id=?", [.blob(try encoded(chunk)), .text(id.uuidString)])
                }
            case .capture(let projection):
                var capture = try session(projection.id, scope: scope)
                guard projection.lessonId == capture.serverCapture.lessonId,
                      projection.deviceId == deviceID, projection.instructorMembershipId == scope.membershipID,
                      projection.captureState != .authorized else { throw SchoolCaptureStorageFailure.invalidReceipt }
                if projection.version >= capture.serverCapture.version { capture.serverCapture = projection; try save(capture) }
            case .assessment, .choice: break
            }
            queued.state = .acknowledged
            queued.resultBody = bytes
            try save(queued)
        }
    }

    func recordFinalizationRefusal(id: UUID, scope: SchoolCommandScope, code: String) throws {
        guard ["VERSION_CONFLICT", "CAPTURE_INCOMPLETE"].contains(code) else { throw SchoolCaptureStorageFailure.invalidReceipt }
        try write {
            var queued = try mutation(id, scope: scope)
            guard queued.mutation.kind == .finalizeCapture, queued.state == .attempted else {
                throw SchoolCaptureStorageFailure.invalidReceipt
            }
            queued.state = .refused
            queued.resultBody = try JSONEncoder().encode(["code": code])
            try save(queued)
        }
    }

    func acceptAuthorization(operationID: UUID, authorization: SchoolCaptureAuthorization, lease: SchoolCaptureLease,
                             scope: SchoolCommandScope, deviceID requestedDevice: UUID) throws -> SchoolCaptureStoredSession {
        let remote = authorization.capture
        guard requestedDevice == deviceID, lease.deviceID == deviceID, remote.deviceId == deviceID,
              lease.personID == scope.personID, lease.schoolID == scope.schoolID, lease.captureID == remote.id,
              remote.schoolId == scope.schoolID, remote.instructorMembershipId == scope.membershipID,
              remote.captureState == .authorized, remote.publicationState == .privateCapture,
              remote.stoppedAt == nil, remote.cutoffAt == nil, remote.hasValidTimeline,
              lease.permitsCollection() else { throw SchoolCaptureStorageFailure.invalidContext }
        var installed: SchoolCaptureStoredSession?
        var isNew = false
        try write {
            var queued = try mutation(operationID, scope: scope)
            guard queued.state != .queued, queued.mutation.kind == .startCapture,
                  queued.mutation.targetID == remote.lessonId else { throw SchoolCaptureStorageFailure.invalidReceipt }
            let body = try JSONDecoder().decode(SchoolStartCaptureBody.self, from: queued.mutation.body)
            guard body.deviceId == deviceID, body.choiceId == remote.choiceId,
                  body.deviceAssessmentId == remote.deviceAssessmentId else { throw SchoolCaptureStorageFailure.invalidReceipt }
            let existing = try database.records("SELECT data FROM capture WHERE id=?", [.text(remote.id.uuidString)], as: SchoolCaptureStoredSession.self).first
            if let existing {
                guard existing.scope == scope, existing.deviceID == deviceID,
                      existing.serverCapture.lessonId == remote.lessonId else { throw SchoolCaptureStorageFailure.invalidContext }
                installed = existing
            } else {
                guard try count("SELECT CAST(COUNT(*) AS TEXT) FROM capture WHERE state IN('ready','recording','paused')") == 0 else {
                    throw SchoolCaptureStorageFailure.alreadyActive
                }
                let capture = SchoolCaptureStoredSession(id: remote.id, scope: scope, deviceID: deviceID, authorization: authorization,
                    serverCapture: remote, state: .ready, stoppedAt: nil, stopOperationID: nil, manifest: nil)
                try insert(capture)
                installed = capture
                isNew = true
            }
            queued.state = .acknowledged
            queued.resultBody = try encoded(authorization)
            try save(queued)
        }
        guard let installed else { throw SchoolCaptureStorageFailure.unavailable }
        // Une ligne déjà présente après relance ne restaure jamais une capacité mémoire.
        if isNew { leases[remote.id] = lease; leaseScopes[remote.id] = scope }
        return installed
    }

    func sessions(scope: SchoolCommandScope) throws -> [SchoolCaptureStoredSession] {
        let values = try database.records("SELECT data FROM capture WHERE workspace=? AND device_id=? ORDER BY rowid DESC",
            [.text(workspace(scope)), .text(deviceID.uuidString)], as: SchoolCaptureStoredSession.self)
        return values.filter { $0.scope == scope }
    }

    /// PARTIAL peut aussi désigner une coupure serveur avant AP158. Seul son
    /// accusé conservé prouve qu'une finalisation a réellement été confirmée.
    func acknowledgedFinalizations(scope: SchoolCommandScope) throws -> [UUID: SchoolCaptureSession] {
        let rows = try database.records("SELECT data FROM mutation WHERE workspace=? AND kind=? AND state='acknowledged' ORDER BY created_at",
            [.text(workspace(scope)), .text(SchoolCaptureMutationKind.finalizeCapture.rawValue)], as: SchoolCaptureQueuedMutation.self)
        var result: [UUID: SchoolCaptureSession] = [:]
        for row in rows where row.mutation.scope == scope {
            guard let bytes = row.resultBody, let capture = try? JSONDecoder().decode(SchoolCaptureSession.self, from: bytes),
                  capture.id == row.mutation.targetID, capture.schoolId == scope.schoolID,
                  capture.syncState == .synced || capture.syncState == .partial else { throw SchoolCaptureStorageFailure.invalidReceipt }
            result[capture.id] = capture
        }
        return result
    }

    func storedSession(captureID: UUID, scope: SchoolCommandScope) throws -> SchoolCaptureStoredSession {
        try session(captureID, scope: scope)
    }

    // AP155 relu après upload ou conflit de version. Il actualise la projection,
    // jamais le manifeste local ni une capacité de collecte après relance.
    @discardableResult
    func reconcileProjection(_ projection: SchoolCaptureSession, scope: SchoolCommandScope) throws -> SchoolCaptureStoredSession {
        if projection.captureState != .authorized { leases.removeValue(forKey: projection.id) }
        var result: SchoolCaptureStoredSession?
        try write {
            var capture = try session(projection.id, scope: scope)
            let previous = capture.serverCapture
            guard projection.hasValidTimeline, projection.version >= previous.version,
                  projection.schoolId == scope.schoolID, projection.lessonId == previous.lessonId,
                  projection.learnerId == previous.learnerId, projection.instructorMembershipId == scope.membershipID,
                  projection.deviceId == deviceID, projection.choiceId == previous.choiceId,
                  projection.deviceAssessmentId == previous.deviceAssessmentId,
                  projection.authorizedAt == previous.authorizedAt, projection.expiresAt == previous.expiresAt,
                  projection.uploadDeadline == previous.uploadDeadline,
                  previous.captureState == .authorized || projection.captureState != .authorized else {
                throw SchoolCaptureStorageFailure.invalidReceipt
            }
            capture.serverCapture = projection
            try save(capture)
            result = capture
        }
        guard let result else { throw SchoolCaptureStorageFailure.unavailable }
        return result
    }

    func beginSegment(captureID: UUID, scope: SchoolCommandScope, startedAt: String,
                      reason: SchoolCaptureChunkBody.StartReason) throws -> SchoolCaptureSegmentHandle {
        var handle: SchoolCaptureSegmentHandle?
        try write {
            var capture = try session(captureID, scope: scope)
            try requireLease(capture)
            guard capture.manifest == nil, capture.state == .ready || capture.state == .paused,
                  let start = SchoolLesson.date(startedAt), let authorizationStart = SchoolLesson.date(capture.serverCapture.authorizedAt),
                  let expiry = SchoolLesson.date(capture.serverCapture.expiresAt), start >= authorizationStart, start < expiry else {
                throw SchoolCaptureStorageFailure.closed
            }
            let previous = try segments(captureID)
            guard previous.count < 200, (previous.isEmpty && reason == .start) || (!previous.isEmpty && reason != .start),
                  previous.allSatisfy({ $0.endReason != nil }) else { throw SchoolCaptureStorageFailure.invalidContext }
            if let last = previous.last, let ended = last.endedAt.flatMap(SchoolLesson.date) {
                guard start >= ended else { throw SchoolCaptureStorageFailure.invalidMeasurement }
            }
            let value = SchoolCaptureSegmentHandle(captureID: captureID, segmentID: UUID(), segmentIndex: previous.count, generationID: UUID())
            let segment = SchoolCaptureStoredSegment(id: value.segmentID, handle: value, startedAt: startedAt, reason: reason,
                pointCount: 0, chunkedPointCount: 0, chunkCount: 0, lastSequence: nil, lastElapsedMs: nil,
                lastCapturedAt: nil, endReason: nil, endedAt: nil)
            try database.execute("INSERT INTO segment(id,capture_id,segment_index,state,data) VALUES(?,?,?,?,?)",
                [.text(value.segmentID.uuidString), .text(captureID.uuidString), .number(Double(value.segmentIndex)), .text("open"), .blob(try encoded(segment))])
            capture.state = .recording
            try save(capture)
            handle = value
        }
        guard let handle else { throw SchoolCaptureStorageFailure.unavailable }
        return handle
    }

    @discardableResult
    func append(measurements: [SchoolCaptureMeasurement], handle: SchoolCaptureSegmentHandle,
                scope: SchoolCommandScope) throws -> Int {
        guard !measurements.isEmpty, measurements.count <= 1000 else { throw SchoolCaptureStorageFailure.invalidMeasurement }
        var admitted = 0
        try write {
            let capture = try session(handle.captureID, scope: scope)
            try requireLease(capture)
            var segment = try segment(handle)
            guard capture.state == .recording, capture.manifest == nil, segment.endReason == nil,
                  let start = SchoolLesson.date(segment.startedAt), let expiry = SchoolLesson.date(capture.serverCapture.expiresAt) else {
                throw SchoolCaptureStorageFailure.closed
            }
            let total = try count("SELECT CAST(COUNT(*) AS TEXT) FROM sample s JOIN segment g ON g.id=s.segment_id WHERE g.capture_id=?", [.text(capture.id.uuidString)])
            guard total + measurements.count <= 100_000 else { throw SchoolCaptureStorageFailure.capacity }
            for measured in measurements {
                let point = SchoolCapturePoint(sequence: segment.pointCount, elapsedMs: measured.elapsedMs, capturedAt: measured.capturedAt,
                    latitude: measured.latitude, longitude: measured.longitude, accuracyMeters: measured.accuracyMeters)
                guard point.isValid, point.elapsedMs <= 10_800_000, let at = SchoolLesson.date(point.capturedAt),
                      at >= start, at < expiry,
                      abs(at.timeIntervalSince(start) * 1000 - Double(point.elapsedMs)) <= 1,
                      segment.lastElapsedMs.map({ point.elapsedMs > $0 }) ?? true,
                      segment.lastCapturedAt.flatMap(SchoolLesson.date).map({ at > $0 }) ?? true else {
                    throw SchoolCaptureStorageFailure.invalidMeasurement
                }
                try database.execute("INSERT INTO sample(segment_id,sequence,data) VALUES(?,?,?)",
                    [.text(segment.id.uuidString), .number(Double(point.sequence)), .blob(try encoded(point))])
                segment.pointCount += 1
                segment.lastSequence = point.sequence
                segment.lastElapsedMs = point.elapsedMs
                segment.lastCapturedAt = point.capturedAt
                admitted += 1
            }
            try flush(&segment, capture: capture, all: false)
            try save(segment)
        }
        return admitted
    }

    func sealSegment(handle: SchoolCaptureSegmentHandle, scope: SchoolCommandScope, endedAt: String,
                     reason: SchoolCaptureManifest.EndReason) throws {
        try write {
            var capture = try session(handle.captureID, scope: scope)
            var segment = try segment(handle)
            if segment.endReason != nil { return }
            guard capture.manifest == nil else { throw SchoolCaptureStorageFailure.manifestSealed }
            try seal(&segment, capture: capture, endedAt: endedAt, reason: reason)
            capture.state = .paused
            try save(capture)
        }
    }

    @discardableResult
    func stopAndSeal(captureID: UUID, scope: SchoolCommandScope, stoppedAt: String,
                     reason: SchoolCaptureLocalStopReason) throws -> SchoolCapturePendingMutation {
        // La capacité mémoire est retirée même si le disque refuse ensuite le scellement.
        leases.removeValue(forKey: captureID)
        var result: SchoolCapturePendingMutation?
        try write {
            var capture = try session(captureID, scope: scope)
            if let operationID = capture.stopOperationID { result = try mutation(operationID, scope: scope).mutation; return }
            result = try sealCapture(&capture, stoppedAt: stoppedAt, reason: reason, interrupted: false)
        }
        guard let result else { throw SchoolCaptureStorageFailure.unavailable }
        return result
    }

    // Après relance, on connaît le dernier fait durable, pas l'heure physique de fermeture.
    // La borne conservatrice exclusive suit ce fait d'une milliseconde et ne dépasse pas le bail.
    func recoverInterrupted(deviceID requestedDevice: UUID) throws {
        guard requestedDevice == deviceID else { throw SchoolCaptureStorageFailure.invalidContext }
        // Le scellement ne divulgue aucune donnée et ne dépend pas de droits réseau.
        // Il garde le scope d'origine même si le compte courant ou son epoch a changé.
        let candidates = try database.records("SELECT data FROM capture WHERE device_id=? AND state IN('ready','recording','paused')",
            [.text(deviceID.uuidString)], as: SchoolCaptureStoredSession.self)
        for candidate in candidates { leases.removeValue(forKey: candidate.id) }
        try write {
            for var capture in candidates {
                guard capture.stopOperationID == nil, let authorized = SchoolLesson.date(capture.serverCapture.authorizedAt),
                      let expiry = SchoolLesson.date(capture.serverCapture.expiresAt) else { throw SchoolCaptureStorageFailure.invalidContext }
                let rows = try segments(capture.id)
                let durableBoundaries = rows.flatMap { [SchoolLesson.date($0.startedAt), $0.endedAt.flatMap(SchoolLesson.date)] }.compactMap { $0 }
                let lastPoint = rows.compactMap { $0.lastCapturedAt.flatMap(SchoolLesson.date) }.max()
                let knownEnd = (durableBoundaries + [authorized] + (lastPoint.map { [$0.addingTimeInterval(0.001)] } ?? [])).max() ?? authorized
                let end = min(knownEnd, expiry)
                _ = try sealCapture(&capture, stoppedAt: Self.timestamp(end), reason: .deviceError, interrupted: true)
            }
        }
    }

    @discardableResult
    func stageFinalization(captureID: UUID, scope: SchoolCommandScope, expectedVersion: Int,
                           allowPartial: Bool) throws -> SchoolCapturePendingMutation {
        var result: SchoolCapturePendingMutation?
        try write {
            let capture = try session(captureID, scope: scope)
            guard let manifest = capture.manifest, let stopID = capture.stopOperationID,
                  try mutation(stopID, scope: scope).state == .acknowledged,
                  capture.serverCapture.version == expectedVersion,
                  capture.serverCapture.captureState != .authorized else { throw SchoolCaptureStorageFailure.closed }
            let allChunks = try database.records("SELECT data FROM chunk WHERE capture_id=? ORDER BY segment_id,chunk_index",
                [.text(captureID.uuidString)], as: SchoolCaptureStoredChunk.self)
            guard allowPartial || allChunks.allSatisfy({ $0.receipt != nil }) else { throw SchoolCaptureStorageFailure.uncertainCommand }
            let existing = try database.records("SELECT data FROM mutation WHERE workspace=? AND kind=? AND target_id=? AND state IN('queued','attempted') ORDER BY created_at LIMIT 1",
                [.text(workspace(scope)), .text(SchoolCaptureMutationKind.finalizeCapture.rawValue), .text(captureID.uuidString)], as: SchoolCaptureQueuedMutation.self).first
            if let existing, existing.mutation.scope != scope { throw SchoolCaptureStorageFailure.changedScope }
            if let existing {
                guard let body = try? JSONDecoder().decode(SchoolFinalizeCaptureBody.self, from: existing.mutation.body),
                      body.allowPartial == allowPartial else { throw SchoolCaptureStorageFailure.uncertainCommand }
                result = existing.mutation; return
            }
            let operationID = UUID(), body = SchoolFinalizeCaptureBody(operationId: operationID, segments: manifest, allowPartial: allowPartial)
            let command = try SchoolCapturePendingMutation.make(id: operationID, scope: scope, kind: .finalizeCapture,
                targetID: captureID, expectedVersion: expectedVersion, body: body)
            try insertMutation(command, generated: true)
            result = command
        }
        guard let result else { throw SchoolCaptureStorageFailure.unavailable }
        return result
    }

    private func sealCapture(_ capture: inout SchoolCaptureStoredSession, stoppedAt: String,
                             reason: SchoolCaptureLocalStopReason, interrupted: Bool) throws -> SchoolCapturePendingMutation {
        guard let stopped = SchoolLesson.date(stoppedAt), let authorized = SchoolLesson.date(capture.serverCapture.authorizedAt),
              stopped >= authorized else { throw SchoolCaptureStorageFailure.invalidContext }
        var rows = try segments(capture.id)
        for index in rows.indices where rows[index].endReason == nil {
            try seal(&rows[index], capture: capture, endedAt: stoppedAt, reason: interrupted ? .appTerminated : reason.segmentReason)
        }
        let manifest = rows.map { SchoolCaptureManifest(segmentId: $0.id, segmentIndex: $0.handle.segmentIndex,
            expectedChunkIndices: Array(0..<$0.chunkCount), expectedPointCount: $0.pointCount,
            lastSequence: $0.lastSequence, endReason: $0.endReason ?? .other) }
        guard manifest.allSatisfy(\.isValid), manifest.count <= 200 else { throw SchoolCaptureStorageFailure.invalidContext }
        let operationID = UUID(), body = SchoolStopCaptureBody(operationId: operationID, stoppedAt: stoppedAt,
            reason: reason.rawValue, segments: manifest, localCollectorStopped: true)
        let mutation = try SchoolCapturePendingMutation.make(id: operationID, scope: capture.scope, kind: .stopCapture,
            targetID: capture.id, body: body)
        capture.state = interrupted ? .interrupted : .stopped
        capture.stoppedAt = stoppedAt
        capture.stopOperationID = operationID
        capture.manifest = manifest
        try save(capture)
        try insertMutation(mutation, generated: true)
        return mutation
    }

    private func seal(_ segment: inout SchoolCaptureStoredSegment, capture: SchoolCaptureStoredSession,
                      endedAt: String, reason: SchoolCaptureManifest.EndReason) throws {
        guard let end = SchoolLesson.date(endedAt), let start = SchoolLesson.date(segment.startedAt), end >= start,
              segment.lastCapturedAt.flatMap(SchoolLesson.date).map({ $0 < end }) ?? true else {
            throw SchoolCaptureStorageFailure.invalidMeasurement
        }
        try flush(&segment, capture: capture, all: true)
        segment.endReason = reason
        segment.endedAt = endedAt
        try save(segment)
    }

    private func flush(_ segment: inout SchoolCaptureStoredSegment, capture: SchoolCaptureStoredSession, all: Bool) throws {
        while segment.chunkedPointCount < segment.pointCount && (all || segment.pointCount - segment.chunkedPointCount >= chunkSize) {
            guard segment.chunkCount < 1000,
                  try count("SELECT CAST(COUNT(*) AS TEXT) FROM chunk WHERE capture_id=?", [.text(capture.id.uuidString)]) < 2000 else {
                throw SchoolCaptureStorageFailure.capacity
            }
            let points = try database.records("SELECT data FROM sample WHERE segment_id=? AND sequence>=? ORDER BY sequence LIMIT 250",
                [.text(segment.id.uuidString), .number(Double(segment.chunkedPointCount))], as: SchoolCapturePoint.self)
            let operationID = UUID(), body = try SchoolCaptureChunkEncoding.makeBody(operationID: operationID,
                segmentIndex: segment.handle.segmentIndex, startedAt: segment.startedAt, reason: segment.reason,
                points: points, signedUploadAuthorization: capture.authorization.signedUploadAuthorization)
            let mutation = try SchoolCapturePendingMutation.make(id: operationID, scope: capture.scope, kind: .uploadChunk,
                targetID: capture.id, segmentID: segment.id, chunkIndex: segment.chunkCount, body: body)
            let chunk = SchoolCaptureStoredChunk(id: operationID, captureID: capture.id, segmentID: segment.id,
                index: segment.chunkCount, body: body, receipt: nil)
            try database.execute("INSERT INTO chunk(id,capture_id,segment_id,chunk_index,data) VALUES(?,?,?,?,?)",
                [.text(operationID.uuidString), .text(capture.id.uuidString), .text(segment.id.uuidString),
                 .number(Double(segment.chunkCount)), .blob(try encoded(chunk))])
            try insertMutation(mutation, generated: true)
            segment.chunkCount += 1
            segment.chunkedPointCount += points.count
        }
    }

    private func requireLease(_ capture: SchoolCaptureStoredSession) throws {
        guard capture.serverCapture.captureState == .authorized, let lease = leases[capture.id], lease.permitsCollection() else {
            throw SchoolCaptureStorageFailure.closed
        }
    }

    private func validateUploadBounds(_ body: SchoolCaptureChunkBody, capture: SchoolCaptureStoredSession) throws {
        guard let expiry = SchoolLesson.date(capture.serverCapture.expiresAt) else { throw SchoolCaptureStorageFailure.invalidContext }
        let cutoffs: [Date?] = [expiry, capture.stoppedAt.flatMap(SchoolLesson.date), capture.serverCapture.cutoffAt.flatMap(SchoolLesson.date)]
        let cutoff = cutoffs.compactMap { $0 }.min() ?? expiry
        guard body.points.allSatisfy({ SchoolLesson.date($0.capturedAt).map { $0 < cutoff } ?? false }) else {
            throw SchoolCaptureStorageFailure.closed
        }
    }

    private func insertMutation(_ value: SchoolCapturePendingMutation, generated: Bool = false) throws {
        guard value.isValid else { throw SchoolCaptureStorageFailure.invalidContext }
        if let existing = try database.records("SELECT data FROM mutation WHERE id=?", [.text(value.id.uuidString)], as: SchoolCaptureQueuedMutation.self).first {
            guard existing.mutation == value else { throw SchoolCaptureStorageFailure.uncertainCommand }
            return
        }
        let scopeHash = SHA256.hash(data: try encoded(value.scope)).map { String(format: "%02x", $0) }.joined()
        if !generated {
            guard try count("SELECT CAST(COUNT(*) AS TEXT) FROM mutation WHERE workspace=? AND state IN('queued','attempted') AND scope_hash<>?",
                [.text(workspace(value.scope)), .text(scopeHash)]) == 0 else { throw SchoolCaptureStorageFailure.changedScope }
        }
        // Un changement de droits ou une file pleine ne doit pas empêcher le fait
        // local d'arrêt. markAttempted garde le contrôle de portée lors de l'émission.
        if !generated {
            guard try count("SELECT CAST(COUNT(*) AS TEXT) FROM mutation WHERE workspace=? AND state IN('queued','attempted')",
                [.text(workspace(value.scope))]) < 5000 else { throw SchoolCaptureStorageFailure.capacity }
        }
        if !generated {
            switch value.kind {
            case .uploadChunk, .stopCapture, .finalizeCapture: throw SchoolCaptureStorageFailure.invalidContext
            case .assessDevice:
                guard value.targetID == deviceID else { throw SchoolCaptureStorageFailure.invalidContext }
                guard try count("SELECT CAST(COUNT(*) AS TEXT) FROM mutation WHERE workspace=? AND kind=? AND target_id=? AND state IN('queued','attempted')",
                    [.text(workspace(value.scope)), .text(value.kind.rawValue), .text(value.targetID.uuidString)]) == 0 else {
                    throw SchoolCaptureStorageFailure.uncertainCommand
                }
            case .startCapture:
                let body = try JSONDecoder().decode(SchoolStartCaptureBody.self, from: value.body)
                guard body.deviceId == deviceID, body.explicitStartConfirmed,
                      try count("SELECT CAST(COUNT(*) AS TEXT) FROM capture WHERE state IN('ready','recording','paused')") == 0,
                      try count("SELECT CAST(COUNT(*) AS TEXT) FROM mutation WHERE kind=? AND state IN('queued','attempted')",
                        [.text(SchoolCaptureMutationKind.startCapture.rawValue)]) == 0 else { throw SchoolCaptureStorageFailure.alreadyActive }
            case .recordChoice:
                guard try count("SELECT CAST(COUNT(*) AS TEXT) FROM mutation WHERE workspace=? AND kind=? AND target_id=? AND state IN('queued','attempted')",
                    [.text(workspace(value.scope)), .text(value.kind.rawValue), .text(value.targetID.uuidString)]) == 0 else {
                    throw SchoolCaptureStorageFailure.uncertainCommand
                }
            }
        }
        let queued = SchoolCaptureQueuedMutation(mutation: value, deviceID: deviceID, state: .queued, attemptCount: 0, resultBody: nil)
        try database.execute("INSERT INTO mutation(id,workspace,scope_hash,device_id,kind,target_id,state,created_at,data) VALUES(?,?,?,?,?,?,?,?,?)",
            [.text(value.id.uuidString), .text(workspace(value.scope)), .text(scopeHash), .text(deviceID.uuidString),
             .text(value.kind.rawValue), .text(value.targetID.uuidString), .text(queued.state.rawValue),
             .number(value.createdAt.timeIntervalSince1970), .blob(try encoded(queued))])
    }

    private func resultData(_ result: SchoolCaptureMutationResult, for mutation: SchoolCapturePendingMutation) throws -> Data {
        switch result {
        case .assessment(let value):
            guard mutation.kind == .assessDevice, value.schoolId == mutation.scope.schoolID,
                  value.deviceId == mutation.targetID, value.membershipId == mutation.scope.membershipID else { throw SchoolCaptureStorageFailure.invalidReceipt }
            return try encoded(value)
        case .choice(let value):
            guard mutation.kind == .recordChoice, value.schoolId == mutation.scope.schoolID,
                  value.learnerId == mutation.targetID else { throw SchoolCaptureStorageFailure.invalidReceipt }
            return try encoded(value)
        case .authorization(let value):
            let remote = value.capture
            guard mutation.kind == .startCapture, remote.hasValidTimeline,
                  remote.schoolId == mutation.scope.schoolID, remote.lessonId == mutation.targetID,
                  remote.deviceId == deviceID, remote.instructorMembershipId == mutation.scope.membershipID,
                  remote.publicationState == .privateCapture, SchoolLesson.date(value.serverTime) != nil else {
                throw SchoolCaptureStorageFailure.invalidReceipt
            }
            let body = try JSONDecoder().decode(SchoolStartCaptureBody.self, from: mutation.body)
            guard body.deviceId == deviceID, body.choiceId == remote.choiceId,
                  body.deviceAssessmentId == remote.deviceAssessmentId else { throw SchoolCaptureStorageFailure.invalidReceipt }
            return try encoded(value)
        case .chunk(let value):
            guard mutation.kind == .uploadChunk, value.captureId == mutation.targetID,
                  value.segmentId == mutation.segmentID, value.chunkIndex == mutation.chunkIndex else { throw SchoolCaptureStorageFailure.invalidReceipt }
            return try encoded(value)
        case .capture(let value):
            guard mutation.kind == .stopCapture || mutation.kind == .finalizeCapture,
                  value.hasValidTimeline, value.schoolId == mutation.scope.schoolID,
                  value.id == mutation.targetID else { throw SchoolCaptureStorageFailure.invalidReceipt }
            return try encoded(value)
        }
    }

    private func session(_ id: UUID, scope: SchoolCommandScope) throws -> SchoolCaptureStoredSession {
        guard let row = try database.records("SELECT data FROM capture WHERE id=?", [.text(id.uuidString)], as: SchoolCaptureStoredSession.self).first,
              row.scope.belongsToWorkspace(scope), row.deviceID == deviceID else { throw SchoolCaptureStorageFailure.missingCapture }
        guard row.scope == scope else { throw SchoolCaptureStorageFailure.changedScope }
        return row
    }
    private func segment(_ handle: SchoolCaptureSegmentHandle) throws -> SchoolCaptureStoredSegment {
        guard let row = try database.records("SELECT data FROM segment WHERE id=?", [.text(handle.segmentID.uuidString)], as: SchoolCaptureStoredSegment.self).first,
              row.handle == handle else { throw SchoolCaptureStorageFailure.closed }
        return row
    }
    private func segments(_ captureID: UUID) throws -> [SchoolCaptureStoredSegment] {
        try database.records("SELECT data FROM segment WHERE capture_id=? ORDER BY segment_index", [.text(captureID.uuidString)], as: SchoolCaptureStoredSegment.self)
    }
    private func storedChunk(_ id: UUID) throws -> SchoolCaptureStoredChunk {
        guard let row = try database.records("SELECT data FROM chunk WHERE id=?", [.text(id.uuidString)], as: SchoolCaptureStoredChunk.self).first else {
            throw SchoolCaptureStorageFailure.invalidReceipt
        }
        return row
    }
    private func mutation(_ id: UUID, scope: SchoolCommandScope) throws -> SchoolCaptureQueuedMutation {
        guard let row = try database.records("SELECT data FROM mutation WHERE id=?", [.text(id.uuidString)], as: SchoolCaptureQueuedMutation.self).first,
              row.deviceID == deviceID, row.mutation.scope.belongsToWorkspace(scope) else { throw SchoolCaptureStorageFailure.invalidContext }
        guard row.mutation.scope == scope else { throw SchoolCaptureStorageFailure.changedScope }
        return row
    }
    private func insert(_ capture: SchoolCaptureStoredSession) throws {
        try database.execute("INSERT INTO capture(id,workspace,device_id,state,data) VALUES(?,?,?,?,?)",
            [.text(capture.id.uuidString), .text(workspace(capture.scope)), .text(deviceID.uuidString),
             .text(capture.state.rawValue), .blob(try encoded(capture))])
    }
    private func save(_ capture: SchoolCaptureStoredSession) throws {
        try database.execute("UPDATE capture SET state=?,data=? WHERE id=?", [.text(capture.state.rawValue), .blob(try encoded(capture)), .text(capture.id.uuidString)])
    }
    private func save(_ segment: SchoolCaptureStoredSegment) throws {
        try database.execute("UPDATE segment SET state=?,data=? WHERE id=?", [.text(segment.endReason == nil ? "open" : "sealed"), .blob(try encoded(segment)), .text(segment.id.uuidString)])
    }
    private func save(_ mutation: SchoolCaptureQueuedMutation) throws {
        try database.execute("UPDATE mutation SET state=?,data=? WHERE id=?", [.text(mutation.state.rawValue), .blob(try encoded(mutation)), .text(mutation.id.uuidString)])
    }
    private func count(_ sql: String, _ values: [SQLValue] = []) throws -> Int {
        guard let value = try database.records(sql, values, as: Int.self).first else { throw SchoolCaptureStorageFailure.unavailable }
        return value
    }
    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    private func workspace(_ scope: SchoolCommandScope) -> String {
        SHA256.hash(data: Data("\(scope.apiBaseURL)|\(scope.personID.uuidString)|\(scope.schoolID.uuidString)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    private func write(_ body: () throws -> Void) throws {
        if protectFiles { try ProtectedStorage.protectDatabaseFiles(at: url) }
        try database.transaction(body)
        if protectFiles { try ProtectedStorage.protectDatabaseFiles(at: url) }
    }
    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
