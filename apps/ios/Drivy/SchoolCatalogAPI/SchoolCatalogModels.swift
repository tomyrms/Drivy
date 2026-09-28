import Foundation

protocol SchoolCatalogRecord: Codable, Sendable, Equatable, Identifiable where ID == UUID {
    var schoolId: UUID { get }
    var version: Int { get }
}

struct SchoolOffering: SchoolCatalogRecord {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let offeringKey: String
    let categoryCode: String
    let curriculumVersionId: UUID
    let policyVersionId: UUID
    let enabled: Bool
    let defaultDurationMinutes: Int
    let defaultPriceCents: Int64
}
struct SchoolCatalogCompetency: SchoolCatalogRecord {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let curriculumVersionId: UUID
    let key: String
    let label: String
    let description: String
    let sortOrder: Int
}
struct SchoolCurriculum: SchoolCatalogRecord {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let categoryCode: String
    let revision: Int
    let approved: Bool
    let competencies: [SchoolCatalogCompetency]
}
struct SchoolCatalogPolicy: SchoolCatalogRecord {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let categoryCode: String
    let procedureText: String
    let cancellationPolicyText: String
    let sourceUrls: [String]
    let approved: Bool
    let approvedAt: String?
}
struct SchoolMember: SchoolCatalogRecord {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let personId: UUID
    let displayName: String
    let status: String
    let roles: [String]
    let grants: [String]
    let accessEpoch: Int
}
struct SchoolAssignment: SchoolCatalogRecord {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let trainingId: UUID
    let instructorMembershipId: UUID
    let validFrom: String
    let validUntil: String?
}
extension SchoolTraining: SchoolCatalogRecord {}

struct SchoolCreateTraining: Encodable {
    let operationId: UUID
    let learnerId: UUID
    let offeringId: UUID
    let startedOn: String?
}
struct SchoolCreateAssignment: Encodable {
    let operationId: UUID
    let instructorMembershipId: UUID
    let validFrom: String
    let validUntil: String?
}
struct SchoolCreateOffering: Encodable {
    let operationId: UUID
    let offeringKey: String
    let categoryCode: String
    let curriculumVersionId: UUID
    let enabled: Bool
    let defaultDurationMinutes: Int
    let defaultPriceCents: Int64
    let policyVersionId: UUID
}
struct SchoolCreateCompetency: Codable, Equatable {
    let key: String
    let label: String
    let description: String
    let sortOrder: Int
}
struct SchoolCreateCurriculum: Encodable {
    let operationId: UUID
    let categoryCode: String
    let approved: Bool
    let approvalReason: String
    let competencies: [SchoolCreateCompetency]
}
struct SchoolCreateCatalogPolicy: Encodable {
    let operationId: UUID
    let categoryCode: String
    let procedureText: String
    let cancellationPolicyText: String
    let sourceUrls: [String]
    let approved: Bool
    let approvalReason: String
}

enum SchoolCatalogResult: Sendable {
    case offering(SchoolOffering), curriculum(SchoolCurriculum), policy(SchoolCatalogPolicy)
    case training(SchoolTraining), assignment(SchoolAssignment), member(SchoolMember)
    var id: UUID { switch self {
        case .offering(let v): v.id; case .curriculum(let v): v.id; case .policy(let v): v.id
        case .training(let v): v.id; case .assignment(let v): v.id; case .member(let v): v.id
    } }
    var schoolID: UUID { switch self {
        case .offering(let v): v.schoolId; case .curriculum(let v): v.schoolId; case .policy(let v): v.schoolId
        case .training(let v): v.schoolId; case .assignment(let v): v.schoolId; case .member(let v): v.schoolId
    } }
    var version: Int { switch self {
        case .offering(let v): v.version; case .curriculum(let v): v.version; case .policy(let v): v.version
        case .training(let v): v.version; case .assignment(let v): v.version; case .member(let v): v.version
    } }
}

@MainActor protocol SchoolCatalogAPI: AnyObject {
    func school(id: UUID) async throws -> SchoolDetails
    func offerings(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolOffering>
    func curricula(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolCurriculum>
    func policies(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolCatalogPolicy>
    func members(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolMember>
    func trainings(schoolID: UUID, learnerID: UUID, cursor: String?) async throws -> SchoolPage<SchoolTraining>
    func assignments(schoolID: UUID, trainingID: UUID, cursor: String?) async throws -> SchoolPage<SchoolAssignment>
    func operation(schoolID: UUID, id: UUID) async throws -> SchoolOperationReceipt
    func send(_ command: PendingSchoolCommand) async throws -> SchoolCatalogResult
}

enum SchoolCatalogFailure: Error, LocalizedError, Equatable {
    case unauthorized, forbidden, notFound, unavailable, invalidResponse, operationUnknown, pending, conflict, reauthentication
    case rejected(String)
    var errorDescription: String? { switch self {
        case .unauthorized: "Reconnectez-vous pour retrouver cet espace. Toute demande en attente reste conservée."
        case .forbidden: "Vos accès ne permettent plus cette opération dans l’école."
        case .notFound: "Cette information n’est pas disponible avec vos accès actuels."
        case .unavailable: "L’école est momentanément inaccessible. Votre demande reste conservée jusqu’à confirmation."
        case .invalidResponse: "La réponse de l’école ne peut pas être vérifiée."
        case .operationUnknown: "Le résultat reste à vérifier. La référence de votre demande est conservée."
        case .pending: "Vérifiez la demande en attente avant une autre modification."
        case .conflict: "Les informations ont changé. Rechargez et relisez avant de confirmer."
        case .reauthentication: "Reconnectez-vous avec le même compte pour confirmer ce changement de droits."
        case .rejected(let message): message
    } }
    var permitsFreshCorrection: Bool {
        switch self { case .rejected, .conflict: true; default: false }
    }
}

enum SchoolCatalogFormatting {
    static func price(_ cents: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_CH")
        formatter.numberStyle = .currency
        formatter.currencyCode = "CHF"
        return formatter.string(from: NSDecimalNumber(decimal: Decimal(cents) / 100)) ?? "Prix indisponible"
    }
    static func cents(_ text: String) -> Int64? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let wholeText = parts.first, !wholeText.isEmpty,
              wholeText.utf8.allSatisfy({ (48...57).contains($0) }), let whole = Int64(wholeText),
              whole <= 90_071_992_547_409 else { return nil }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= 2, fraction.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        let minor = fraction.isEmpty ? 0 : Int64(fraction + (fraction.count == 1 ? "0" : ""))!
        let result = whole * 100 + minor
        return result <= 9_007_199_254_740_991 ? result : nil
    }
    static func civilDate(_ date: Date, timeZone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
