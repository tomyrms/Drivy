import Foundation
import SQLCipher

// La connexion C reste dans cet acteur ; son propriétaire privé la ferme à sa libération.
actor SQLCipherSessionStore: SessionStore {
    private let database: CipherConnection
    private let url: URL
    private let protectFiles: Bool

    static func openDefault() throws -> SQLCipherSessionStore {
        let url = try ProtectedStorage.directory().appendingPathComponent("sessions.sqlite")
        let exists = FileManager.default.fileExists(atPath: url.path)
        let key = try DeviceKeyStore.loadOrCreate(databaseExists: exists)
        return try SQLCipherSessionStore(url: url, key: key)
    }

    // Les clés et chemins injectés servent aux tests, jamais à un stockage alternatif de production.
    init(url: URL, key: Data, protectFiles: Bool = true) throws {
        guard key.count == 32 else { throw SessionError.keyUnavailable }
        self.url = url
        self.protectFiles = protectFiles
        if protectFiles { try ProtectedStorage.protectDatabaseFiles(at: url) }
        let database = try CipherConnection(url: url, key: key)
        let version = try database.integer("PRAGMA user_version")
        guard version <= 2 else { throw SessionError.unsupportedSchema }
        if version == 0 {
            try database.transaction {
                try database.execute("""
                    CREATE TABLE session (
                        id TEXT PRIMARY KEY NOT NULL, started_at REAL NOT NULL,
                        state TEXT NOT NULL CHECK(state IN ('active','completed','interrupted')),
                        data BLOB NOT NULL
                    );
                    CREATE UNIQUE INDEX one_active_session ON session(state) WHERE state='active';
                    CREATE TABLE point (
                        id TEXT PRIMARY KEY NOT NULL, session_id TEXT NOT NULL REFERENCES session(id),
                        timestamp REAL NOT NULL, data BLOB NOT NULL,
                        UNIQUE(session_id, timestamp)
                    );
                    CREATE INDEX point_order ON point(session_id,timestamp);
                    CREATE TABLE observation (
                        id TEXT PRIMARY KEY NOT NULL, session_id TEXT NOT NULL REFERENCES session(id),
                        observed_at REAL NOT NULL, data BLOB NOT NULL
                    );
                    CREATE INDEX observation_order ON observation(session_id,observed_at);
                    PRAGMA user_version=1;
                    """)
            }
        }
        if version < 2 {
            try database.transaction {
                try database.execute("""
                    CREATE TABLE example_installation (
                        id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL CHECK(version>0),
                        installed_at REAL NOT NULL
                    );
                    PRAGMA user_version=2;
                    """)
            }
        }
        if protectFiles { try ProtectedStorage.protectDatabaseFiles(at: url) }
        self.database = database
    }

    func sessions() throws -> [DrivingSession] {
        try database.records("SELECT data FROM session ORDER BY started_at DESC", as: DrivingSession.self)
            .map { try hydrated($0) }
    }

    func session(id: UUID) throws -> DrivingSession { try hydrated(metadata(id)) }

    func create(_ session: DrivingSession) throws {
        guard session.origin == .recorded, session.state == .active, session.points.isEmpty, session.observations.isEmpty else {
            throw SessionError.sessionClosed
        }
        try write {
            guard try database.integer("SELECT COUNT(*) FROM session WHERE state='active'") == 0 else {
                throw SessionError.sessionAlreadyActive
            }
            try database.execute("INSERT INTO session(id,started_at,state,data) VALUES(?,?,?,?)",
                [.text(session.id.uuidString), .number(session.startedAt.timeIntervalSince1970),
                 .text(session.state.rawValue), .blob(try JSONEncoder().encode(session))])
        }
    }

    // L'installation entière, y compris son reçu, partage un commit chiffré. Le reçu est conservé
    // lors d'une suppression de séance : une mise à jour ou un redémarrage ne la ressuscite pas.
    func installExamplesIfNeeded(now: Date = Date()) throws {
        try write {
            guard try database.integer("SELECT COUNT(*) FROM example_installation WHERE id=1") == 0 else { return }
            for example in try ExampleJourneys.make(now: now) {
                guard example.isExample, !example.usesGPS, example.state == .completed,
                      let end = example.endedAt, end > example.startedAt, end <= now,
                      !example.points.isEmpty, example.points.count <= 5_000 else { throw SessionError.invalidPoint }
                var metadata = example
                metadata.points = []; metadata.observations = []
                try database.execute("INSERT INTO session(id,started_at,state,data) VALUES(?,?,?,?)",
                    [.text(example.id.uuidString), .number(example.startedAt.timeIntervalSince1970),
                     .text(example.state.rawValue), .blob(try JSONEncoder().encode(metadata))])
                let pointIDs = Set(example.points.map(\.id))
                guard pointIDs.count == example.points.count else { throw SessionError.invalidPoint }
                var previous = example.startedAt.addingTimeInterval(-1)
                for point in example.points {
                    guard point.latitude.isFinite, point.longitude.isFinite,
                          (-90...90).contains(point.latitude), (-180...180).contains(point.longitude),
                          point.timestamp >= example.startedAt, point.timestamp <= end,
                          point.timestamp > previous, point.receivedAt == point.timestamp,
                          point.accuracy == -1 else { throw SessionError.invalidPoint }
                    try database.execute("INSERT INTO point(id,session_id,timestamp,data) VALUES(?,?,?,?)",
                        [.text(point.id.uuidString), .text(example.id.uuidString), .number(point.timestamp.timeIntervalSince1970),
                         .blob(try JSONEncoder().encode(point))])
                    previous = point.timestamp
                }
                for observation in example.observations {
                    guard observation.note.count <= 1_000, observation.observedAt >= example.startedAt,
                          observation.observedAt <= end,
                          observation.anchorPointID.map({ pointIDs.contains($0) }) ?? true else { throw SessionError.invalidObservation }
                    try database.execute("INSERT INTO observation(id,session_id,observed_at,data) VALUES(?,?,?,?)",
                        [.text(observation.id.uuidString), .text(example.id.uuidString), .number(observation.observedAt.timeIntervalSince1970),
                         .blob(try JSONEncoder().encode(observation))])
                }
            }
            try database.execute("INSERT INTO example_installation(id,version,installed_at) VALUES(1,?,?)",
                [.number(Double(ExampleJourneys.version)), .number(now.timeIntervalSince1970)])
        }
    }

    func append(_ point: RecordedPoint, to sessionID: UUID) throws {
        try write {
            let session = try metadata(sessionID)
            guard session.state == .active, session.usesGPS else { throw SessionError.sessionClosed }
            guard point.latitude.isFinite, point.longitude.isFinite, point.accuracy.isFinite,
                  (-90...90).contains(point.latitude), (-180...180).contains(point.longitude),
                  (0...100).contains(point.accuracy), point.timestamp >= session.startedAt,
                  point.receivedAt >= point.timestamp.addingTimeInterval(-2) else { throw SessionError.invalidPoint }
            let existing = try database.records("SELECT data FROM point WHERE id=? AND session_id=?",
                [.text(point.id.uuidString), .text(sessionID.uuidString)], as: RecordedPoint.self)
            if let first = existing.first {
                guard first == point else { throw SessionError.invalidPoint }
                return
            }
            try database.execute("INSERT INTO point(id,session_id,timestamp,data) VALUES(?,?,?,?)",
                [.text(point.id.uuidString), .text(sessionID.uuidString),
                 .number(point.timestamp.timeIntervalSince1970), .blob(try JSONEncoder().encode(point))])
        }
    }

    func append(_ observation: LessonObservation, to sessionID: UUID) throws {
        try write {
            let session = try metadata(sessionID)
            guard session.state == .active else { throw SessionError.sessionClosed }
            guard observation.note.count <= 1_000, observation.observedAt >= session.startedAt else {
                throw SessionError.invalidObservation
            }
            if let anchor = observation.anchorPointID {
                let points = try database.records("SELECT data FROM point WHERE id=? AND session_id=?",
                    [.text(anchor.uuidString), .text(sessionID.uuidString)], as: RecordedPoint.self)
                guard let point = points.first, point.timestamp <= observation.observedAt,
                      observation.observedAt.timeIntervalSince(point.timestamp) <= 15 else {
                    throw SessionError.invalidObservation
                }
            }
            let existing = try database.records("SELECT data FROM observation WHERE id=? AND session_id=?",
                [.text(observation.id.uuidString), .text(sessionID.uuidString)], as: LessonObservation.self)
            if let first = existing.first {
                guard first == observation else { throw SessionError.invalidObservation }
                return
            }
            try database.execute("INSERT INTO observation(id,session_id,observed_at,data) VALUES(?,?,?,?)",
                [.text(observation.id.uuidString), .text(sessionID.uuidString),
                 .number(observation.observedAt.timeIntervalSince1970), .blob(try JSONEncoder().encode(observation))])
        }
    }

    func finish(_ id: UUID, at date: Date, state: SessionState) throws {
        guard state != .active else { throw SessionError.sessionClosed }
        try write {
            var session = try metadata(id)
            guard session.state == .active else { return }
            session.endedAt = max(date, session.startedAt)
            session.state = state
            try saveMetadata(session)
        }
    }

    func updateSummary(_ text: String, for id: UUID) throws {
        guard text.count <= 10_000 else { throw SessionError.invalidObservation }
        try write {
            var session = try metadata(id)
            session.summary = text
            try saveMetadata(session)
        }
    }

    func recoverInterruptedSessions() throws {
        try write {
            for var session in try database.records("SELECT data FROM session WHERE state='active'", as: DrivingSession.self) {
                // L’instant de fermeture forcée est inconnu : retenir le dernier fait durable.
                let full = try hydrated(session)
                session.endedAt = ([session.startedAt] + full.points.map(\.timestamp) + full.observations.map(\.observedAt)).max()
                session.state = .interrupted
                try saveMetadata(session)
            }
        }
    }

    func deleteSession(_ id: UUID) throws {
        try write {
            let session = try metadata(id)
            guard session.state != .active else { throw SessionError.sessionStillActive }
            try database.execute("DELETE FROM observation WHERE session_id=?", [.text(id.uuidString)])
            try database.execute("DELETE FROM point WHERE session_id=?", [.text(id.uuidString)])
            try database.execute("DELETE FROM session WHERE id=?", [.text(id.uuidString)])
        }
        // secure_delete efface les cellules ; ce checkpoint retire aussi les anciennes pages du WAL.
        guard try database.integer("PRAGMA wal_checkpoint(TRUNCATE)") == 0 else { throw SessionError.storageUnavailable }
    }

    private func metadata(_ id: UUID) throws -> DrivingSession {
        guard let session = try database.records("SELECT data FROM session WHERE id=?",
            [.text(id.uuidString)], as: DrivingSession.self).first else { throw SessionError.missingSession }
        return session
    }

    private func hydrated(_ metadata: DrivingSession) throws -> DrivingSession {
        var result = metadata
        result.points = try database.records("SELECT data FROM point WHERE session_id=? ORDER BY timestamp,id",
            [.text(metadata.id.uuidString)], as: RecordedPoint.self)
        result.observations = try database.records("SELECT data FROM observation WHERE session_id=? ORDER BY observed_at,id",
            [.text(metadata.id.uuidString)], as: LessonObservation.self)
        return result
    }

    private func saveMetadata(_ session: DrivingSession) throws {
        try database.execute("UPDATE session SET state=?,data=? WHERE id=?",
            [.text(session.state.rawValue), .blob(try JSONEncoder().encode(session)), .text(session.id.uuidString)])
    }

    private func write(_ body: () throws -> Void) throws {
        if protectFiles { try ProtectedStorage.protectDatabaseFiles(at: url) }
        try database.transaction(body)
        // Les fichiers annexes héritent du dossier protégé ; vérifier aussi leur politique explicite.
        if protectFiles { try ProtectedStorage.protectDatabaseFiles(at: url) }
    }
}
