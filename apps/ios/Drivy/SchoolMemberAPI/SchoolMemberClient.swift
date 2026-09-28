import Foundation

struct SchoolUpdateMemberCommand: Encodable {
    let operationId: UUID
    let roles: [String]
    let grants: [String]
    let reason: String
}

enum SchoolMemberRole: String, CaseIterable, Identifiable {
    case admin = "ADMIN", instructor = "INSTRUCTOR", learner = "LEARNER"
    var id: String { rawValue }
    var label: String {
        switch self { case .admin: "Administration"; case .instructor: "Moniteur"; case .learner: "Élève" }
    }
    var explanation: String {
        switch self {
        case .admin: "Gérer l’école, ses membres et les dossiers administratifs."
        case .instructor: "Accompagner les élèves affectés à ses formations."
        case .learner: "Accéder à son propre dossier et à ses leçons."
        }
    }
}

enum SchoolMemberGrant: String, CaseIterable, Identifiable {
    case permitReview = "permit_review", cashRecord = "cash_record"
    case catalog = "CONFIGURE_CATALOG", sell = "SELL_SERVICES", courses = "MANAGE_COURSES"
    case attendance = "TAKE_ATTENDANCE", requirement = "VALIDATE_REQUIREMENT", regulatory = "REVIEW_REGULATORY_PROFILE"
    case archives = "MANAGE_LEARNER_ARCHIVES", metrics = "VIEW_SCHOOL_METRICS", financial = "VIEW_FINANCIAL_METRICS", export = "EXPORT_MANAGEMENT"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .permitReview: "Vérifier les permis"
        case .cashRecord: "Enregistrer les encaissements"
        case .catalog: "Configurer les prestations et tarifs"
        case .sell: "Vendre les prestations"
        case .courses: "Organiser les cours collectifs"
        case .attendance: "Consigner les présences"
        case .requirement: "Valider les exigences"
        case .regulatory: "Revoir les profils réglementaires"
        case .archives: "Gérer les archives des élèves"
        case .metrics: "Consulter les indicateurs de l’école"
        case .financial: "Consulter les indicateurs financiers"
        case .export: "Exporter les données de gestion"
        }
    }
}

@MainActor final class SchoolMemberClient {
    let baseURL: URL
    let reader: DrivyAPIClient
    private let catalog: SchoolCatalogClient
    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL
        reader = DrivyAPIClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
        catalog = SchoolCatalogClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
    }
    func members(schoolID: UUID) async throws -> [SchoolMember] {
        var records: [SchoolMember] = [], cursor: String?, cursors = Set<String>()
        repeat {
            let page = try await catalog.members(schoolID: schoolID, cursor: cursor)
            records.append(contentsOf: page.items); cursor = page.nextCursor
            guard records.count <= 10_000 else { throw SchoolCatalogFailure.invalidResponse }
            if let cursor, !cursors.insert(cursor).inserted { throw SchoolCatalogFailure.invalidResponse }
        } while cursor != nil
        guard Set(records.map(\.id)).count == records.count else { throw SchoolCatalogFailure.invalidResponse }
        return records.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
    func send(_ command: PendingSchoolCommand) async throws -> SchoolMember {
        guard command.kind == .updateMember else { throw SchoolCatalogFailure.invalidResponse }
        let result = try await catalog.send(command)
        guard case .member(let member) = result else { throw SchoolCatalogFailure.invalidResponse }
        return member
    }
    func receipt(_ command: PendingSchoolCommand) async throws -> SchoolOperationReceipt {
        let value = try await catalog.operation(schoolID: command.scope.schoolID, id: command.id)
        guard command.matches(value) else { throw SchoolCatalogFailure.invalidResponse }
        return value
    }
    func learner(schoolID: UUID, personID: UUID) async throws -> SchoolLearner? {
        var cursor: String?, seen = Set<String>(), count = 0
        repeat {
            let page = try await reader.learners(schoolID: schoolID, query: "", cursor: cursor)
            count += page.items.count
            guard count <= 10_000 else { throw SchoolCatalogFailure.invalidResponse }
            if let learner = page.items.first(where: { $0.personId == personID }) { return learner }
            cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw SchoolCatalogFailure.invalidResponse }
        } while cursor != nil
        return nil
    }
}
