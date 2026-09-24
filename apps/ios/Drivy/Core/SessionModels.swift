import Foundation

enum SessionState: String, Codable, Sendable {
    case active, completed, interrupted

    var label: String {
        switch self {
        case .active: "En cours"
        case .completed: "Terminée"
        case .interrupted: "Interrompue"
        }
    }
}

enum SessionOrigin: String, Codable, Sendable {
    case recorded = "RECORDED"
    case example = "EXAMPLE"
}

enum ObservationTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case priority, parking, signs, roundabout, observation, anticipation
    var id: String { rawValue }
    var label: String {
        switch self {
        case .observation: "Observation"
        case .priority: "Priorité à droite"
        case .parking: "Stationnement"
        case .signs: "Signalisation"
        case .roundabout: "Giratoire"
        case .anticipation: "Anticipation"
        }
    }
    var symbol: String {
        switch self {
        case .observation: "eye"
        case .priority: "exclamationmark.triangle"
        case .parking: "parkingsign.circle"
        case .signs: "signpost.right"
        case .roundabout: "arrow.trianglehead.2.clockwise.rotate.90"
        case .anticipation: "arrow.up.forward"
        }
    }
}

enum ObservationStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case attention, toWorkOn, positive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .attention: "Attention"
        case .toWorkOn: "À retravailler"
        case .positive: "Point positif"
        }
    }
}

enum GPSStatus: Equatable, Sendable {
    case inactive, requestingPermission, waitingForPosition, recording, denied, interrupted
    var label: String {
        switch self {
        case .inactive: "Sans GPS"
        case .requestingPermission: "Autorisation GPS demandée"
        case .waitingForPosition: "En attente de position"
        case .recording: "GPS actif"
        case .denied: "GPS non autorisé"
        case .interrupted: "GPS interrompu"
        }
    }
}

struct RecordedPoint: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let receivedAt: Date
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let segmentID: UUID
}

struct LessonObservation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let observedAt: Date
    let theme: ObservationTheme
    let status: ObservationStatus
    let note: String
    let anchorPointID: UUID?
}

struct ObservationContext: Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let observedAt: Date
    let anchorPointID: UUID?
}

struct DrivingSession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    let usesGPS: Bool
    let origin: SessionOrigin
    let title: String?
    let provenance: String?
    var state: SessionState
    var points: [RecordedPoint]
    var observations: [LessonObservation]
    var summary: String
    var isExample: Bool { origin == .example }

    init(id: UUID = UUID(), startedAt: Date = Date(), usesGPS: Bool,
         origin: SessionOrigin = .recorded, title: String? = nil, provenance: String? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.usesGPS = usesGPS
        self.origin = origin
        self.title = title
        self.provenance = provenance
        self.state = .active
        self.points = []
        self.observations = []
        self.summary = ""
    }

    // Les séances existantes restent des enregistrements ; leur origine n'est jamais réécrite en exemple.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        endedAt = try values.decodeIfPresent(Date.self, forKey: .endedAt)
        usesGPS = try values.decode(Bool.self, forKey: .usesGPS)
        origin = try values.decodeIfPresent(SessionOrigin.self, forKey: .origin) ?? .recorded
        title = try values.decodeIfPresent(String.self, forKey: .title)
        provenance = try values.decodeIfPresent(String.self, forKey: .provenance)
        state = try values.decode(SessionState.self, forKey: .state)
        points = try values.decode([RecordedPoint].self, forKey: .points)
        observations = try values.decode([LessonObservation].self, forKey: .observations)
        summary = try values.decode(String.self, forKey: .summary)
    }
}

enum SessionError: Error, LocalizedError, Equatable, Sendable {
    case storageUnavailable, encryptionUnavailable, keyUnavailable, unsupportedSchema
    case sessionClosed, sessionAlreadyActive, sessionStillActive, invalidObservation, invalidPoint, missingSession

    var errorDescription: String? {
        switch self {
        case .storageUnavailable: "La sauvegarde locale est indisponible. La capture est arrêtée. Les données déjà enregistrées sont conservées."
        case .encryptionUnavailable: "Le stockage chiffré n’a pas pu être vérifié. Aucune donnée ne sera enregistrée en clair."
        case .keyUnavailable: "La clé de cet appareil est inaccessible. Déverrouillez l’appareil puis réessayez. Aucune clé de remplacement n’a été créée pour les données existantes."
        case .unsupportedSchema: "Ces données proviennent d’une version plus récente de Drivy. Elles sont conservées sans modification."
        case .sessionClosed: "Cette séance est arrêtée. Aucune nouvelle position ou observation n’a été ajoutée."
        case .sessionAlreadyActive: "Une séance est déjà ouverte sur cet appareil."
        case .sessionStillActive: "Arrêtez la séance avant de la supprimer."
        case .invalidObservation: "L’observation est invalide ou dépasse 1 000 caractères."
        case .invalidPoint: "Cette mesure GPS ne peut pas être conservée."
        case .missingSession: "Cette séance n’est plus disponible."
        }
    }
}

protocol SessionStore: Sendable {
    func sessions() async throws -> [DrivingSession]
    func session(id: UUID) async throws -> DrivingSession
    func create(_ session: DrivingSession) async throws
    func append(_ point: RecordedPoint, to sessionID: UUID) async throws
    func append(_ observation: LessonObservation, to sessionID: UUID) async throws
    func finish(_ id: UUID, at date: Date, state: SessionState) async throws
    func updateSummary(_ text: String, for id: UUID) async throws
    func recoverInterruptedSessions() async throws
    func deleteSession(_ id: UUID) async throws
}
