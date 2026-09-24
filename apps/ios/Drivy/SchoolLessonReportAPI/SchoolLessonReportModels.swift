import Foundation

struct SchoolLessonGoal: Codable, Sendable, Equatable {
    var label: String
    var competencyId: UUID?
    var context: String?
}
struct SchoolPlannedWaypoint: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let label: String
    let latitude: Double
    let longitude: Double
    let note: String?
}
struct SchoolLessonPreparation: SchoolCatalogRecord {
    let id: UUID, schoolId: UUID, lessonId: UUID
    let version: Int
    let goals: [SchoolLessonGoal]
    let administrativeCheckNote: String?
    let plannedWaypoints: [SchoolPlannedWaypoint]
}
struct SchoolLearnerWish: SchoolCatalogRecord {
    let id: UUID, schoolId: UUID, trainingId: UUID
    let version: Int
    let lessonId: UUID?
    let text: String
}
struct SchoolReportObservation: Codable, Sendable, Equatable, Identifiable {
    let competencyId: UUID
    var level: String
    var context: String
    var id: UUID { competencyId }
    var levelLabel: String {
        switch level {
        case "DISCOVERING": "En découverte"
        case "GUIDED": "Avec accompagnement"
        case "INDEPENDENT": "En autonomie"
        default: "À vérifier"
        }
    }
}
struct SchoolReportDraft: SchoolCatalogRecord {
    let id: UUID, schoolId: UUID, lessonId: UUID, authorMembershipId: UUID
    let version: Int, basePublicationVersion: Int
    let workedOn: String, observationText: String, nextStep: String
    let observations: [SchoolReportObservation]
    let attachmentIds: [UUID]
    let geoObservationIds: [UUID]?
}
struct SchoolReportRevision: SchoolCatalogRecord {
    let id: UUID, schoolId: UUID, lessonId: UUID, authorMembershipId: UUID
    let version: Int, sequence: Int
    let publishedAt: String
    let workedOn: String, observationText: String, nextStep: String
    let observations: [SchoolReportObservation]
    let attachmentIds: [UUID]
    let correctionReason: String?
    // La projection G2 ne publie aucune capture ni annotation séparée. Une réponse plus riche
    // devra être interprétée par un client qui connaît le protocole, jamais masquée silencieusement.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); schoolId = try c.decode(UUID.self, forKey: .schoolId)
        lessonId = try c.decode(UUID.self, forKey: .lessonId); authorMembershipId = try c.decode(UUID.self, forKey: .authorMembershipId)
        version = try c.decode(Int.self, forKey: .version); sequence = try c.decode(Int.self, forKey: .sequence)
        publishedAt = try c.decode(String.self, forKey: .publishedAt)
        workedOn = try c.decode(String.self, forKey: .workedOn); observationText = try c.decode(String.self, forKey: .observationText)
        nextStep = try c.decode(String.self, forKey: .nextStep); observations = try c.decode([SchoolReportObservation].self, forKey: .observations)
        attachmentIds = try c.decode([UUID].self, forKey: .attachmentIds); correctionReason = try c.decode(String?.self, forKey: .correctionReason)
        let capture = try c.decodeNil(forKey: .capturePublication)
        let annotations = try c.nestedUnkeyedContainer(forKey: .textObservations)
        guard capture, annotations.isAtEnd, attachmentIds.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Contenu publié nécessitant une version plus récente de l’application."))
        }
    }
    enum CodingKeys: String, CodingKey {
        case id, schoolId, lessonId, authorMembershipId, version, sequence, publishedAt
        case workedOn, observationText, nextStep, observations, attachmentIds, correctionReason, capturePublication, textObservations
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(schoolId, forKey: .schoolId); try c.encode(lessonId, forKey: .lessonId)
        try c.encode(authorMembershipId, forKey: .authorMembershipId); try c.encode(version, forKey: .version); try c.encode(sequence, forKey: .sequence)
        try c.encode(publishedAt, forKey: .publishedAt); try c.encode(workedOn, forKey: .workedOn); try c.encode(observationText, forKey: .observationText)
        try c.encode(nextStep, forKey: .nextStep); try c.encode(observations, forKey: .observations); try c.encode(attachmentIds, forKey: .attachmentIds)
        try c.encode(correctionReason, forKey: .correctionReason); try c.encodeNil(forKey: .capturePublication); try c.encode([UUID](), forKey: .textObservations)
    }
}
struct SchoolLessonCharge: Codable, Sendable, Equatable, Identifiable {
    let id: UUID, schoolId: UUID, accountId: UUID
    let version: Int
    let kind: String
    let amountSignedCents: Int64
    let reason: String?
}
struct SchoolLessonAccount: Codable, Sendable, Equatable, Identifiable {
    let id: UUID, ownerId: UUID
    let ownerType: String
    let lessonId: UUID?
    let version: Int
    let currency: String
    let plannedPriceCents: Int64, chargeCents: Int64, netReceivedCents: Int64, balanceCents: Int64
    let charges: [SchoolLessonCharge]
}
struct SchoolReportProgressItem: Codable, Sendable, Equatable, Identifiable {
    let competencyId: UUID, sourceLessonId: UUID, sourceRevisionId: UUID
    let label: String, level: String, context: String, observedAt: String
    var id: UUID { competencyId }
}
struct SchoolReportProgress: Codable, Sendable, Equatable {
    let trainingId: UUID
    let items: [SchoolReportProgressItem]
    let unobservedCompetencyIds: [UUID]
    let computedAt: String
}
struct SchoolCompleteLesson: Encodable {
    let operationId: UUID
    let actualStart: String, actualEnd: String
    let workedOn: String, observationText: String, nextStep: String, anomalyReason: String
}
struct SchoolSavePreparation: Encodable {
    let operationId: UUID
    let goals: [SchoolLessonGoal]
    let administrativeCheckNote: String
    // Omission volontaire de plannedWaypoints : les repères existants sont conservés.
}
struct SchoolSaveWish: Encodable {
    let operationId: UUID
    let text: String
    // L'association éventuelle à une leçon demeure inchangée.
}
struct SchoolSaveReport: Encodable {
    let operationId: UUID
    let workedOn: String, observationText: String, nextStep: String
    let observations: [SchoolReportObservation]
    let attachmentIds: [UUID] = []
}
struct SchoolPublishReport: Encodable {
    let operationId: UUID
    let expectedPublicationVersion: Int
    let correctionReason: String?
    enum CodingKeys: String, CodingKey { case operationId, expectedPublicationVersion, correctionReason, captureSelection, textObservationSelection }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(operationId, forKey: .operationId); try c.encode(expectedPublicationVersion, forKey: .expectedPublicationVersion)
        try c.encode(correctionReason, forKey: .correctionReason)
        try c.encodeNil(forKey: .captureSelection); try c.encode([UUID](), forKey: .textObservationSelection)
    }
}
