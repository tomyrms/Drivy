#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Réponses fictives en mémoire pour la garde d'entrée ; aucune identité ou écriture réseau.
struct SchoolEntryVisualReview: View {
    static let screenNames: Set<String> = ["school-entry-draft-admin", "school-entry-draft-member", "school-entry-management", "school-entry-archived", "school-entry-resume"]
    @State private var workspace: SchoolWorkspace
    @State private var selectedTab: SchoolHomeTab = .session

    init(screen: String) {
        _workspace = State(initialValue: SchoolWorkspace(api: SchoolEntryVisualAPI(screen: screen)))
    }

    var body: some View {
        SchoolHomeView(workspace: workspace, openAccount: {},
            account: SchoolAccountActions(manageURL: URL(string: "https://visual.drivy.invalid/app/gestion/\(SchoolEntryVisualAPI.schoolID.uuidString.lowercased())/apercu"),
                openProfile: nil, openInvitations: nil, openJoinSchool: nil, signOut: {}), selectedTab: $selectedTab)
            .task { await workspace.loadAccount() }
    }
}

@MainActor private final class SchoolEntryVisualAPI: SchoolAPI {
    static let schoolID = UUID(uuidString: "10000000-0000-4000-8000-000000000601")!
    private let person: SchoolPerson
    private let screen: String
    private var schoolReads = 0

    init(screen: String) {
        self.screen = screen
        let roles = screen == "school-entry-draft-member" ? ["INSTRUCTOR"]
            : screen == "school-entry-resume" ? ["ADMIN", "INSTRUCTOR"] : ["ADMIN"]
        person = SchoolPerson(personId: UUID(uuidString: "10000000-0000-4000-8000-000000000602")!, version: 1,
            displayName: "Responsable exemple", locale: "fr", memberships: [SchoolMembership(
                membershipId: UUID(uuidString: "10000000-0000-4000-8000-000000000603")!, schoolId: Self.schoolID,
                schoolName: "École exemple", roles: roles, grants: [], accessEpoch: 1)])
    }

    func me() async throws -> SchoolPerson { person }
    func school(id: UUID) async throws -> SchoolDetails {
        guard id == Self.schoolID else { throw SchoolAPIError.notFound }
        schoolReads += 1
        let status = screen == "school-entry-archived" ? "ARCHIVED"
            : screen == "school-entry-management" || (screen == "school-entry-resume" && schoolReads > 1) ? "ACTIVE" : "DRAFT"
        return SchoolDetails(id: id, schoolId: id, version: schoolReads, name: "École exemple", timeZone: "Europe/Zurich",
            status: status, contactEmail: "contact@example.invalid", contactPhone: nil, logoAssetId: nil,
            modules: .init(gpsEnabled: false, packsEnabled: false, collectiveCoursesEnabled: false, courseOffersVisibleByDefault: false), configurationVersion: 1)
    }
    func learners(schoolID: UUID, query: String, cursor: String?) async throws -> SchoolPage<SchoolLearner> { .init(items: [], nextCursor: nil) }
    func learner(schoolID: UUID, id: UUID) async throws -> SchoolLearner { throw SchoolAPIError.notFound }
    func trainings(schoolID: UUID, learnerID: UUID, cursor: String?) async throws -> SchoolPage<SchoolTraining> { .init(items: [], nextCursor: nil) }
    func training(schoolID: UUID, id: UUID) async throws -> SchoolTraining { throw SchoolAPIError.notFound }
}
#endif
