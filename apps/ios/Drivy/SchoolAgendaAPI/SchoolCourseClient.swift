import Foundation

// Cours collectifs (#38) : extension hors canon, contrat dans apps/api/src/courses.ts.
// Les instants restent des chaînes ISO 8601 du serveur ; les dates se lisent par `SchoolLesson.date`.

struct SchoolCourseType: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolId: UUID?
    let stableKey: String?
    let title: String
    let description: String
    let version: Int
    let predefined: Bool
}

struct SchoolCoursePolicy: Codable, Sendable, Equatable {
    let version: Int
    let selfCancelHours: Int
    let offerResponseMinutes: Int?
}

struct SchoolCourseInstructor: Codable, Sendable, Equatable, Identifiable {
    let membershipId: UUID
    let displayName: String
    var id: UUID { membershipId }
}

struct SchoolCourseCatalogue: Codable, Sendable, Equatable {
    let schoolId: UUID
    let canManage: Bool
    let types: [SchoolCourseType]
    let policy: SchoolCoursePolicy
    let instructors: [SchoolCourseInstructor]
}

struct SchoolCourseOccurrence: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let position: Int
    let startsAt: String, endsAt: String
    let timeZone: String
    let instructorMembershipId: UUID
    let instructorDisplayName: String
    let attendanceRequired: Bool
    var start: Date? { SchoolLesson.date(startsAt) }
    var end: Date? { SchoolLesson.date(endsAt) }
}

struct SchoolCourseSeries: Codable, Sendable, Equatable, Identifiable {
    enum Status: String, Codable, Sendable { case draft = "DRAFT", published = "PUBLISHED", cancelled = "CANCELLED", closed = "CLOSED" }
    let id: UUID, schoolId: UUID
    let version: Int
    let status: Status
    let typeId: UUID
    let typeTitle: String
    let title: String, description: String, location: String, conditions: String
    let teachingLanguage: String?
    let responsibleMembershipId: UUID
    let responsibleDisplayName: String
    let capacity: Int, seatsTaken: Int, remainingSeats: Int
    let minParticipants: Int?
    let policyVersion: Int
    let selfCancelHours: Int
    let selfCancellationDeadline: String
    let firstStartsAt: String, lastEndsAt: String
    let totalMinutes: Int
    let publishedAt: String?
    let occurrences: [SchoolCourseOccurrence]
    let canManage: Bool

    var isDraft: Bool { status == .draft }
}

/// Une séance saisie, telle qu’envoyée au serveur.
struct SchoolCourseOccurrenceInput: Codable, Sendable, Equatable {
    let startsAt: String, endsAt: String
    let instructorMembershipId: UUID
    let attendanceRequired: Bool
}

/// Corps de POST et PUT `course-series` : `teachingLanguage` et `minParticipants` partent en `null` explicite.
struct SchoolCourseSeriesBody: Encodable, Sendable, Equatable {
    let operationId: UUID
    let typeId: UUID
    let title: String, description: String, location: String, conditions: String
    let teachingLanguage: String?
    let responsibleMembershipId: UUID
    let capacity: Int
    let minParticipants: Int?
    let timeZone: String
    let occurrences: [SchoolCourseOccurrenceInput]

    private enum CodingKeys: String, CodingKey {
        case operationId, typeId, title, description, location, conditions, teachingLanguage, responsibleMembershipId,
             capacity, minParticipants, timeZone, occurrences
    }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId, forKey: .operationId); try values.encode(typeId, forKey: .typeId)
        try values.encode(title, forKey: .title); try values.encode(description, forKey: .description)
        try values.encode(location, forKey: .location); try values.encode(conditions, forKey: .conditions)
        try values.encode(teachingLanguage, forKey: .teachingLanguage)
        try values.encode(responsibleMembershipId, forKey: .responsibleMembershipId)
        try values.encode(capacity, forKey: .capacity); try values.encode(minParticipants, forKey: .minParticipants)
        try values.encode(timeZone, forKey: .timeZone); try values.encode(occurrences, forKey: .occurrences)
    }
}

// Inscriptions (#39), file prioritaire (#40), annulations (#41) : contrat de apps/api/src/course-enrollments.ts.

struct SchoolCourseEnrollment: Codable, Sendable, Equatable, Identifiable {
    enum Status: String, Codable, Sendable { case active = "ACTIVE", cancelled = "CANCELLED" }
    let id: UUID, seriesId: UUID, learnerId: UUID
    let version: Int
    let status: Status
    let source: String
    let policyVersion: Int
    let selfCancelHours: Int
    let selfCancelDeadline: String
    let canSelfCancel: Bool
    let createdAt: String
    let cancelledAt: String?
    let cancelKind: String?
    let cancelReason: String?
    var deadline: Date? { SchoolLesson.date(selfCancelDeadline) }
}

struct SchoolCourseOffer: Codable, Sendable, Equatable, Identifiable {
    let id: UUID, seriesId: UUID
    let expiresAt: String
    let status: String
    var expiry: Date? { SchoolLesson.date(expiresAt) }
}

/// État personnel de l’élève appelant pour une série : jamais de liste nominative.
struct SchoolCourseLearnerState: Codable, Sendable, Equatable {
    enum State: String, Codable, Sendable {
        case available = "AVAILABLE", full = "FULL", enrolled = "ENROLLED", waiting = "WAITING", offered = "OFFERED"
        case completed = "COMPLETED", cancelled = "CANCELLED", closed = "CLOSED"
    }
    let learnerId: UUID?
    let state: State
    let enrollment: SchoolCourseEnrollment?
    let offer: SchoolCourseOffer?
    let waitlistPosition: Int?
    let waitlistEnabled: Bool
    let contactEmail: String?
}

/// Réponse de la lecture `me` et de chaque commande de l’élève.
struct SchoolCourseLearnerReply: Codable, Sendable, Equatable {
    let series: SchoolCourseSeries
    let me: SchoolCourseLearnerState
}

/// Inscriptions et propositions actives de l’élève dans l’école.
struct SchoolCourseMine: Codable, Sendable, Equatable {
    let items: [SchoolCourseEnrollment]
    let offers: [SchoolCourseOffer]
}

/// Ligne nominative réservée au personnel habilité.
struct SchoolCourseRosterEnrollment: Decodable, Sendable, Equatable, Identifiable {
    let enrollment: SchoolCourseEnrollment
    let learnerDisplayName: String
    var id: UUID { enrollment.id }
    private enum CodingKeys: String, CodingKey { case learnerDisplayName }
    init(enrollment: SchoolCourseEnrollment, learnerDisplayName: String) {
        self.enrollment = enrollment; self.learnerDisplayName = learnerDisplayName
    }
    init(from decoder: any Decoder) throws {
        enrollment = try SchoolCourseEnrollment(from: decoder)
        learnerDisplayName = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .learnerDisplayName)
    }
}

struct SchoolCourseWaitlistEntry: Codable, Sendable, Equatable, Identifiable {
    let id: UUID, learnerId: UUID
    let learnerDisplayName: String
    let position: Int
    let status: String
    let queuedAt: String
    let offerExpiresAt: String?
}

struct SchoolCourseRoster: Decodable, Sendable, Equatable {
    let items: [SchoolCourseRosterEnrollment]
    let waitlist: [SchoolCourseWaitlistEntry]
    var active: [SchoolCourseRosterEnrollment] { items.filter { $0.enrollment.status == .active } }
}

/// Commandes de l’élève ; toutes rendent `{series, me}`.
enum SchoolCourseLearnerAction: Equatable, Sendable {
    case enroll, joinWaitlist, leaveWaitlist
    case accept(offerID: UUID), decline(offerID: UUID)
    case cancel(enrollmentID: UUID, version: Int)

    /// Clé stable d’une même intention : une nouvelle tentative reprend la même opération.
    var key: String {
        switch self {
        case .enroll: "enroll"
        case .joinWaitlist: "waitlist"
        case .leaveWaitlist: "waitlist-leave"
        case .accept(let id): "accept|\(id)"
        case .decline(let id): "decline|\(id)"
        case .cancel(let id, let version): "cancel|\(id)|\(version)"
        }
    }
}

/// Abonnements « prochaines sessions » (#40) : contrat de apps/api/src/notification-preferences.ts.
struct SchoolCourseFollows: Codable, Sendable, Equatable { let typeIds: [UUID] }
struct SchoolCourseFollowReply: Codable, Sendable, Equatable { let typeId: UUID; let following: Bool }

struct SchoolCourseStaffEnrollBody: Encodable, Sendable, Equatable { let operationId: UUID; let learnerId: UUID }
struct SchoolCourseStaffCancelBody: Encodable, Sendable, Equatable { let operationId: UUID; let reason: String }

struct SchoolCourseTypeBody: Encodable, Sendable, Equatable { let operationId: UUID; let title: String; let description: String }
struct SchoolCoursePublishBody: Encodable, Sendable, Equatable { let operationId: UUID }
struct SchoolCourseCapacityBody: Encodable, Sendable, Equatable { let operationId: UUID; let capacity: Int }

// Appel (#42), règlements sur place (#81), validation (#82) : contrat de apps/api/src/course-facts.ts.

enum SchoolCourseAttendanceStatus: String, Codable, Sendable, CaseIterable { case present = "PRESENT", absent = "ABSENT", excused = "EXCUSED" }

struct SchoolCourseRequirements: Codable, Sendable, Equatable {
    let required: Int, present: Int, missing: Int
}

struct SchoolCourseSheetRights: Codable, Sendable, Equatable {
    let canTakeAttendance: Bool, canRecordPayment: Bool, canValidate: Bool
}

/// Présence d’un élève à une séance : `status == nil` tant que rien n’est saisi (jamais déduit).
struct SchoolCourseAttendanceMark: Codable, Sendable, Equatable {
    let occurrenceId: UUID
    let status: SchoolCourseAttendanceStatus?
    let version: Int?
    let recordedAt: String?
}

struct SchoolCoursePayment: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let amountCents: Int64
    let recordedAt: String
    let note: String?
    let voidedAt: String?
    let voidReason: String?
}

struct SchoolCourseCompletion: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let validatedAt: String
    let seriesId: UUID?
    let revokedAt: String?
}

struct SchoolCourseSheetRow: Codable, Sendable, Equatable, Identifiable {
    let enrollmentId: UUID, learnerId: UUID
    let learnerDisplayName: String
    let status: SchoolCourseEnrollment.Status
    let cancelledAt: String?
    let attendance: [SchoolCourseAttendanceMark]
    let requirements: SchoolCourseRequirements
    let payments: [SchoolCoursePayment]
    let completion: SchoolCourseCompletion?
    var id: UUID { enrollmentId }
    func mark(_ occurrenceID: UUID) -> SchoolCourseAttendanceMark? { attendance.first { $0.occurrenceId == occurrenceID } }
}

/// Feuille du cours pour le personnel, droits de l’appelant relus par le serveur.
struct SchoolCourseSheet: Codable, Sendable, Equatable {
    let series: SchoolCourseSeries
    let rights: SchoolCourseSheetRights
    let rows: [SchoolCourseSheetRow]
    var active: [SchoolCourseSheetRow] { rows.filter { $0.status == .active } }
}

/// Progression de l’élève appelant : ni règlement ni autre participant.
struct SchoolCourseProgress: Codable, Sendable, Equatable {
    struct Completion: Codable, Sendable, Equatable, Identifiable {
        let id: UUID, typeId: UUID
        let typeTitle: String
        let validatedAt: String
        let seriesId: UUID?
    }
    struct Mark: Codable, Sendable, Equatable { let occurrenceId: UUID; let status: SchoolCourseAttendanceStatus }
    struct Enrollment: Codable, Sendable, Equatable, Identifiable {
        let enrollmentId: UUID, seriesId: UUID
        let requirements: SchoolCourseRequirements
        let attendance: [Mark]
        var id: UUID { enrollmentId }
    }
    let completions: [Completion]
    let enrollments: [Enrollment]
}

/// `expectedVersion` et `note` partent en `null` explicite.
struct SchoolCourseAttendanceBody: Encodable, Sendable, Equatable {
    let operationId: UUID
    let status: SchoolCourseAttendanceStatus
    let expectedVersion: Int?
    let note: String?
    private enum CodingKeys: String, CodingKey { case operationId, status, expectedVersion, note }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId, forKey: .operationId); try values.encode(status, forKey: .status)
        try values.encode(expectedVersion, forKey: .expectedVersion); try values.encode(note, forKey: .note)
    }
}
struct SchoolCoursePaymentBody: Encodable, Sendable, Equatable {
    let operationId: UUID
    let amountCents: Int64
    let note: String?
    private enum CodingKeys: String, CodingKey { case operationId, amountCents, note }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId, forKey: .operationId); try values.encode(amountCents, forKey: .amountCents)
        try values.encode(note, forKey: .note)
    }
}
struct SchoolCourseValidateBody: Encodable, Sendable, Equatable {
    let operationId: UUID
    let note: String?
    private enum CodingKeys: String, CodingKey { case operationId, note }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId, forKey: .operationId); try values.encode(note, forKey: .note)
    }
}

@MainActor final class SchoolCourseClient {
    let baseURL: URL
    let serverClock: SchoolCourseServerClock
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport
    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport(),
         serverClock: SchoolCourseServerClock = SchoolCourseServerClock()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
        self.serverClock = serverClock
    }

    func catalogue(schoolID: UUID) async throws -> SchoolCourseCatalogue {
        let result: SchoolCourseCatalogue = try await request(schoolID, ["course-catalogue"])
        guard result.schoolId == schoolID, result.policy.selfCancelHours >= 0,
              result.types.allSatisfy({ $0.version > 0 && ($0.schoolId == nil || $0.schoolId == schoolID) }),
              Set(result.types.map(\.id)).count == result.types.count else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    func series(schoolID: UUID, from: Date, to: Date) async throws -> [SchoolCourseSeries] {
        let iso = ISO8601DateFormatter()
        let page: Items = try await request(schoolID, ["course-series"], query: [
            URLQueryItem(name: "from", value: iso.string(from: from)), URLQueryItem(name: "to", value: iso.string(from: to))])
        guard page.items.allSatisfy({ Self.valid($0, schoolID: schoolID) }),
              Set(page.items.map(\.id)).count == page.items.count else { throw SchoolPlanningFailure.invalidResponse }
        return page.items
    }
    func series(schoolID: UUID, id: UUID) async throws -> SchoolCourseSeries {
        let result: SchoolCourseSeries = try await request(schoolID, ["course-series", id.uuidString])
        guard result.id == id, Self.valid(result, schoolID: schoolID) else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    func createType(schoolID: UUID, body: SchoolCourseTypeBody) async throws -> SchoolCourseType {
        let result: SchoolCourseType = try await command(schoolID, ["course-types"], method: "POST", body: body, operation: body.operationId, version: nil)
        guard result.schoolId == schoolID, !result.predefined, result.version > 0 else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    /// Création (version `nil`) ou réécriture d’un brouillon (`If-Match`).
    func save(schoolID: UUID, seriesID: UUID?, version: Int?, body: SchoolCourseSeriesBody) async throws -> SchoolCourseSeries {
        let path = seriesID.map { ["course-series", $0.uuidString] } ?? ["course-series"]
        let result: SchoolCourseSeries = try await command(schoolID, path, method: seriesID == nil ? "POST" : "PUT", body: body,
            operation: body.operationId, version: seriesID == nil ? nil : version)
        guard Self.valid(result, schoolID: schoolID), seriesID == nil || result.id == seriesID, result.isDraft else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    func publish(schoolID: UUID, seriesID: UUID, version: Int, operationID: UUID) async throws -> SchoolCourseSeries {
        let result: SchoolCourseSeries = try await command(schoolID, ["course-series", seriesID.uuidString, "publish"], method: "POST",
            body: SchoolCoursePublishBody(operationId: operationID), operation: operationID, version: version)
        guard result.id == seriesID, Self.valid(result, schoolID: schoolID), result.status == .published else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    func changeCapacity(schoolID: UUID, seriesID: UUID, version: Int, operationID: UUID, capacity: Int) async throws -> SchoolCourseSeries {
        let result: SchoolCourseSeries = try await command(schoolID, ["course-series", seriesID.uuidString, "capacity"], method: "POST",
            body: SchoolCourseCapacityBody(operationId: operationID, capacity: capacity), operation: operationID, version: version)
        guard result.id == seriesID, Self.valid(result, schoolID: schoolID), result.capacity == capacity else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }

    // MARK: Inscriptions

    /// État de l’élève appelant ; la lecture fait aussi avancer la file côté serveur.
    func learnerView(schoolID: UUID, seriesID: UUID) async throws -> SchoolCourseLearnerReply {
        let result: SchoolCourseLearnerReply = try await request(schoolID, ["course-series", seriesID.uuidString, "me"])
        guard result.series.id == seriesID, Self.valid(result.series, schoolID: schoolID) else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    func mine(schoolID: UUID) async throws -> SchoolCourseMine {
        try await request(schoolID, ["course-enrollments", "me"])
    }
    /// `seriesID` : la série visée (celle de la proposition pour accepter ou refuser).
    func act(_ action: SchoolCourseLearnerAction, schoolID: UUID, seriesID: UUID, operationID: UUID) async throws -> SchoolCourseLearnerReply {
        let body = SchoolCoursePublishBody(operationId: operationID)
        let path: [String], expected: Int, version: Int?
        switch action {
        case .enroll: path = ["course-series", seriesID.uuidString, "enroll"]; expected = 201; version = nil
        case .joinWaitlist: path = ["course-series", seriesID.uuidString, "waitlist"]; expected = 201; version = nil
        case .leaveWaitlist: path = ["course-series", seriesID.uuidString, "waitlist", "leave"]; expected = 200; version = nil
        case .accept(let offer): path = ["course-offers", offer.uuidString, "accept"]; expected = 201; version = nil
        case .decline(let offer): path = ["course-offers", offer.uuidString, "decline"]; expected = 200; version = nil
        case .cancel(let enrollment, let current): path = ["course-enrollments", enrollment.uuidString, "cancel"]; expected = 200; version = current
        }
        let result: SchoolCourseLearnerReply = try await command(schoolID, path, method: "POST", body: body, operation: operationID,
            version: version, expected: expected)
        guard result.series.id == seriesID, Self.valid(result.series, schoolID: schoolID) else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    /// Inscrits et file, nominatifs : personnel habilité seulement (relu par le serveur).
    func roster(schoolID: UUID, seriesID: UUID) async throws -> SchoolCourseRoster {
        let result: SchoolCourseRoster = try await request(schoolID, ["course-series", seriesID.uuidString, "enrollments"])
        guard result.items.allSatisfy({ $0.enrollment.seriesId == seriesID }) else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    func staffEnroll(schoolID: UUID, seriesID: UUID, learnerID: UUID, operationID: UUID) async throws -> SchoolCourseEnrollment {
        let result: SchoolCourseEnrollment = try await command(schoolID, ["course-series", seriesID.uuidString, "enrollments"], method: "POST",
            body: SchoolCourseStaffEnrollBody(operationId: operationID, learnerId: learnerID), operation: operationID, version: nil, expected: 201)
        guard result.seriesId == seriesID, result.learnerId == learnerID else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    func staffCancel(schoolID: UUID, enrollmentID: UUID, version: Int, reason: String, operationID: UUID) async throws -> SchoolCourseEnrollment {
        let result: SchoolCourseEnrollment = try await command(schoolID, ["course-enrollments", enrollmentID.uuidString, "staff-cancel"], method: "POST",
            body: SchoolCourseStaffCancelBody(operationId: operationID, reason: reason), operation: operationID, version: version, expected: 200)
        guard result.id == enrollmentID, result.status == .cancelled else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }

    // MARK: Appel, règlements, validation

    /// Feuille nominative : personnel habilité seulement ; les droits viennent du serveur.
    func sheet(schoolID: UUID, seriesID: UUID) async throws -> SchoolCourseSheet {
        let result: SchoolCourseSheet = try await request(schoolID, ["course-series", seriesID.uuidString, "sheet"])
        return try Self.checked(result, schoolID: schoolID, seriesID: seriesID)
    }
    func recordAttendance(schoolID: UUID, seriesID: UUID, enrollmentID: UUID, occurrenceID: UUID,
                          body: SchoolCourseAttendanceBody) async throws -> SchoolCourseSheet {
        let result: SchoolCourseSheet = try await command(schoolID, ["course-enrollments", enrollmentID.uuidString, "attendance", occurrenceID.uuidString],
            method: "PUT", body: body, operation: body.operationId, version: nil, expected: 200)
        return try Self.checked(result, schoolID: schoolID, seriesID: seriesID)
    }
    func recordPayment(schoolID: UUID, seriesID: UUID, enrollmentID: UUID, body: SchoolCoursePaymentBody) async throws -> SchoolCourseSheet {
        let result: SchoolCourseSheet = try await command(schoolID, ["course-enrollments", enrollmentID.uuidString, "payments"],
            method: "POST", body: body, operation: body.operationId, version: nil, expected: 201)
        return try Self.checked(result, schoolID: schoolID, seriesID: seriesID)
    }
    func voidPayment(schoolID: UUID, seriesID: UUID, paymentID: UUID, reason: String, operationID: UUID) async throws -> SchoolCourseSheet {
        let result: SchoolCourseSheet = try await command(schoolID, ["course-payments", paymentID.uuidString, "void"],
            method: "POST", body: SchoolCourseStaffCancelBody(operationId: operationID, reason: reason), operation: operationID, version: nil, expected: 200)
        return try Self.checked(result, schoolID: schoolID, seriesID: seriesID)
    }
    func validate(schoolID: UUID, seriesID: UUID, enrollmentID: UUID, body: SchoolCourseValidateBody) async throws -> SchoolCourseSheet {
        let result: SchoolCourseSheet = try await command(schoolID, ["course-enrollments", enrollmentID.uuidString, "validate"],
            method: "POST", body: body, operation: body.operationId, version: nil, expected: 201)
        return try Self.checked(result, schoolID: schoolID, seriesID: seriesID)
    }
    func revokeCompletion(schoolID: UUID, seriesID: UUID, completionID: UUID, reason: String, operationID: UUID) async throws -> SchoolCourseSheet {
        let result: SchoolCourseSheet = try await command(schoolID, ["course-completions", completionID.uuidString, "revoke"],
            method: "POST", body: SchoolCourseStaffCancelBody(operationId: operationID, reason: reason), operation: operationID, version: nil, expected: 200)
        return try Self.checked(result, schoolID: schoolID, seriesID: seriesID)
    }
    /// Progression de l’élève appelant.
    func progress(schoolID: UUID) async throws -> SchoolCourseProgress {
        let result: SchoolCourseProgress = try await request(schoolID, ["course-progress", "me"])
        guard result.enrollments.allSatisfy({ Self.valid($0.requirements) }),
              result.completions.allSatisfy({ SchoolLesson.date($0.validatedAt) != nil }) else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }

    // MARK: Prochaines sessions (#40) : indépendant de l’inscription et de la file

    /// Types de cours que l’élève appelant suit dans l’école.
    func follows(schoolID: UUID) async throws -> Set<UUID> {
        let result: SchoolCourseFollows = try await request(schoolID, ["course-follows", "me"])
        return Set(result.typeIds)
    }
    /// Suivre (PUT) ou ne plus suivre (POST `unfollow`) un type ; rend l’état écrit par l’école.
    func setFollow(schoolID: UUID, typeID: UUID, following: Bool) async throws -> Bool {
        let path = ["course-follows", "me", typeID.uuidString] + (following ? [] : ["unfollow"])
        let result: SchoolCourseFollowReply = try await send(schoolID, path, query: [], method: following ? "PUT" : "POST",
            body: nil, operation: nil, version: nil, expected: 200)
        guard result.typeId == typeID, result.following == following else { throw SchoolPlanningFailure.invalidResponse }
        return result.following
    }

    static func valid(_ requirements: SchoolCourseRequirements) -> Bool {
        requirements.required >= 0 && requirements.present >= 0 && requirements.missing >= 0
            && requirements.present + requirements.missing == requirements.required
    }
    static func checked(_ sheet: SchoolCourseSheet, schoolID: UUID, seriesID: UUID) throws -> SchoolCourseSheet {
        let occurrences = Set(sheet.series.occurrences.map(\.id))
        guard sheet.series.id == seriesID, valid(sheet.series, schoolID: schoolID),
              Set(sheet.rows.map(\.enrollmentId)).count == sheet.rows.count,
              sheet.rows.allSatisfy({ row in
                  valid(row.requirements) && row.payments.allSatisfy { $0.amountCents >= 0 }
                      && row.attendance.allSatisfy { occurrences.contains($0.occurrenceId) && ($0.status == nil) == ($0.version == nil) }
              }) else { throw SchoolPlanningFailure.invalidResponse }
        return sheet
    }

    static func valid(_ series: SchoolCourseSeries, schoolID: UUID) -> Bool {
        guard series.schoolId == schoolID, series.version > 0, (1...200).contains(series.capacity),
              series.seatsTaken >= 0, series.remainingSeats >= 0, !series.occurrences.isEmpty else { return false }
        return series.occurrences.allSatisfy { occurrence in
            guard let start = occurrence.start, let end = occurrence.end else { return false }
            return end > start && TimeZone(identifier: occurrence.timeZone) != nil
        }
    }

    /// Refus propres aux cours ; le reste suit la planification des leçons.
    static func failure(_ status: Int, _ code: String?, title: String? = nil) -> SchoolPlanningFailure {
        let messages = [
            "COURSE_ACCESS_REQUIRED": "Tu n’as pas le droit de gérer les cours de cette école.",
            "COURSE_INSTRUCTOR_CONFLICT": "Un moniteur a déjà un rendez-vous pendant une séance. Le brouillon est conservé.",
            "COURSE_OCCURRENCES_OVERLAP": "Deux séances de ce cours se chevauchent.",
            "COURSE_OCCURRENCES_REQUIRED": "Ajoute au moins une séance.",
            "COURSE_IN_PAST": "La première séance est déjà passée.",
            "COURSE_NOT_DRAFT": "Ce cours est déjà publié.",
            "COURSE_TYPE_UNKNOWN": "Choisis un type de cours de l’école.",
            "COURSE_TYPE_EXISTS": "Un type de cours porte déjà ce nom.",
            "COURSE_CAPACITY_BELOW_TAKEN": "La capacité ne peut pas descendre sous les places déjà prises.",
            "COURSE_CAPACITY_BELOW_MINIMUM": "La capacité doit rester au moins égale au minimum.",
            "INSTRUCTOR_NOT_ACTIVE": "Choisis un moniteur actif de l’école.",
            "RESPONSIBLE_NOT_ACTIVE": "Choisis un responsable actif de l’école.",
            "COURSE_ALREADY_COMPLETED": "Ce cours est déjà effectué.",
            "COURSE_ALREADY_ENROLLED": "Déjà inscrit à ce cours.",
            "COURSE_EQUIVALENT_ENROLLED": "Déjà inscrit à une autre session de ce cours.",
            "COURSE_NOT_OPEN": "Ce cours n’accepte plus d’inscriptions.",
            "COURSE_STARTED": "Ce cours a déjà commencé.",
            "COURSE_FULL": "Ce cours est complet.",
            "COURSE_OFFER_EXPIRED": "Cette place n’est plus disponible.",
            "COURSE_WAITLIST_DISABLED": "La liste d’attente n’est pas ouverte.",
            "COURSE_SEATS_AVAILABLE": "Des places sont libres : l’inscription est directe.",
            "COURSE_ENROLLMENT_CLOSED": "Cette inscription est déjà annulée.",
            "COURSE_SELF_CANCEL_CLOSED": "Le délai d’annulation est passé.",
            "COURSE_REASON_REQUIRED": "Indique le motif.",
            "COURSE_NOT_PUBLISHED": "Ce cours n’est pas publié.",
            "COURSE_SCHEDULE_CONFLICT": "Un rendez-vous existe déjà pendant une séance de ce cours.",
            "COURSE_OCCURRENCE_NOT_STARTED": "Cette séance n’a pas encore commencé.",
            "COURSE_PAYMENT_VOIDED": "Ce règlement est déjà annulé.",
            "COURSE_NO_REQUIRED_OCCURRENCE": "Ce cours n’a aucune séance obligatoire.",
            "COURSE_REQUIREMENTS_MISSING": "Des séances obligatoires manquent.",
            "COURSE_COMPLETION_REVOKED": "Cette validation est déjà retirée."
        ]
        if (400...499).contains(status), let code, let message = messages[code] { return .rejected(message) }
        return SchoolPlanningClient.failure(status, code, title: title)
    }

    private struct Items: Decodable { let items: [SchoolCourseSeries] }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: String; let serverTime: String }
    private struct Problem: Decodable { let code: String; let title: String? }

    private func request<Value: Decodable>(_ schoolID: UUID, _ path: [String], query: [URLQueryItem] = []) async throws -> Value {
        try await send(schoolID, path, query: query, method: "GET", body: nil, operation: nil, version: nil, expected: 200)
    }
    private func command<Value: Decodable, Body: Encodable>(_ schoolID: UUID, _ path: [String], method: String, body: Body,
                                                            operation: UUID, version: Int?, expected expectedStatus: Int? = nil) async throws -> Value {
        let data: Data
        do { data = try JSONEncoder().encode(body) } catch { throw SchoolPlanningFailure.invalidResponse }
        // Une création répond 201, une commande sur une ressource existante 200 ; la rejouer rend la même réponse.
        let expected = expectedStatus ?? (method == "POST" && version == nil ? 201 : 200)
        return try await send(schoolID, path, query: [], method: method, body: data, operation: operation, version: version, expected: expected)
    }
    private func send<Value: Decodable>(_ schoolID: UUID, _ path: [String], query: [URLQueryItem], method: String, body: Data?,
                                        operation: UUID?, version: Int?, expected: Int) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolPlanningFailure.invalidResponse }
        var url = baseURL
        for part in ["v1", "schools", schoolID.uuidString] + path { url.appendPathComponent(part) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw SchoolPlanningFailure.invalidResponse }
        if !query.isEmpty { components.queryItems = query }
        guard let target = components.url else { throw SchoolPlanningFailure.invalidResponse }
        let token = try await accessToken()
        do { return try await perform(target, method: method, body: body, operation: operation, version: version, expected: expected, token: token) }
        catch SchoolPlanningFailure.unauthorized {
            guard !Task.isCancelled else { throw SchoolPlanningFailure.unauthorized }
            // Un seul renouvellement forcé, même opération et même clé d’idempotence (le 401 précède tout traitement).
            guard await tokenSource.invalidateAccessToken(token) else { throw SchoolPlanningFailure.unauthorized }
            let renewed = try await accessToken()
            guard renewed != token else { throw SchoolPlanningFailure.unauthorized }
            return try await perform(target, method: method, body: body, operation: operation, version: version, expected: expected, token: renewed)
        }
    }
    private func accessToken() async throws -> String {
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolPlanningFailure.unauthorized }
        catch { throw error.unlessCancelled(SchoolPlanningFailure.unavailable) }
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolPlanningFailure.unauthorized }
        return token
    }
    private func perform<Value: Decodable>(_ target: URL, method: String, body: Data?, operation: UUID?, version: Int?,
                                           expected: Int, token: String) async throws -> Value {
        try Task.checkCancellation()
        var request = URLRequest(url: target)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let operation { request.setValue(operation.uuidString, forHTTPHeaderField: "Idempotency-Key") }
        if let version { request.setValue("\"\(version)\"", forHTTPHeaderField: "If-Match") }
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) } catch { throw error.unlessCancelled(SchoolPlanningFailure.unavailable) }
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolPlanningFailure.invalidResponse }
        // Un refus reçu reste connu même si l'appelant a annulé sa lecture : il
        // doit pouvoir retirer les données dont l'accès vient d'être refusé.
        if [401, 403, 404].contains(response.status) {
            throw SchoolPlanningClient.failure(response.status, nil)
        }
        try Task.checkCancellation()
        let contentType = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard response.status == expected else {
            let problem = contentType == "application/problem+json" ? (try? JSONDecoder().decode(Problem.self, from: response.data)) : nil
            throw Self.failure(response.status, problem?.code, title: problem?.title)
        }
        guard contentType == "application/json" else { throw SchoolPlanningFailure.invalidResponse }
        do {
            let result = try JSONDecoder().decode(Envelope<Value>.self, from: response.data)
            guard !result.requestId.isEmpty, let serverTime = SchoolLesson.date(result.serverTime) else { throw SchoolPlanningFailure.invalidResponse }
            serverClock.synchronize(serverTime: serverTime)
            return result.data
        } catch { throw SchoolPlanningFailure.invalidResponse }
    }
}
