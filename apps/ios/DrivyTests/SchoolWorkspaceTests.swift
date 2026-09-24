import Foundation
import Testing
@testable import Drivy

@MainActor
struct SchoolWorkspaceTests {
    @Test func aDraftSchoolDoesNotRequestActiveSchoolDossiers() async {
        let api = WorkspaceAPIStub()
        api.schoolHandler = { WorkspaceFixture.school($0, status: "DRAFT") }
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        #expect(workspace.school?.status == "DRAFT")
        #expect(workspace.membership != nil)
        #expect(api.learnerQueries.isEmpty)
        #expect(workspace.learners.isEmpty)
        #expect(workspace.accountError == nil)
    }

    @Test func switchingSchoolPurgesImmediatelyAndIgnoresItsLateResponse() async throws {
        let api = WorkspaceAPIStub(memberships: [WorkspaceFixture.firstMembership, WorkspaceFixture.secondMembership])
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        let held = WorkspaceResponse<SchoolDetails>()
        api.schoolHandler = { id in
            if id == WorkspaceFixture.firstSchool { return try await held.value() }
            return WorkspaceFixture.school(id)
        }
        api.learnersHandler = { school, _, _ in .init(items: [WorkspaceFixture.learner(school: school)], nextCursor: nil) }
        let old = Task { await workspace.selectSchool(WorkspaceFixture.firstMembership) }
        await held.waitUntilRequested()
        #expect(workspace.school == nil)
        await workspace.selectSchool(WorkspaceFixture.secondMembership)
        held.succeed(WorkspaceFixture.school(WorkspaceFixture.firstSchool))
        await old.value
        #expect(workspace.school?.id == WorkspaceFixture.secondSchool)
        #expect(workspace.learners.allSatisfy { $0.schoolId == WorkspaceFixture.secondSchool })
        #expect(!workspace.isLoadingSchool)
    }

    @Test func anOlderSearchCannotReplaceTheLatestSearchResults() async throws {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        let held = WorkspaceResponse<SchoolPage<SchoolLearner>>()
        let latest = WorkspaceFixture.learner(name: "Résultat récent")
        api.learnersHandler = { _, query, _ in
            if query == "ancien" { return try await held.value() }
            return .init(items: [latest], nextCursor: nil)
        }
        let old = Task { await workspace.searchLearners("ancien") }
        await held.waitUntilRequested()
        await workspace.searchLearners("récent")
        held.succeed(.init(items: [WorkspaceFixture.learner(name: "Ancien résultat")], nextCursor: nil))
        await old.value
        #expect(workspace.searchText == "récent")
        #expect(workspace.learners == [latest])
        #expect(!workspace.isSearching)
    }

    @Test func paginationKeepsItsQueryAndUpdatesDuplicateRowsWithoutRepeatingThem() async {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        let first = WorkspaceFixture.learner(id: UUID(), name: "Première")
        let duplicate = WorkspaceFixture.learner(id: UUID(), name: "Deuxième")
        let changed = WorkspaceFixture.learner(id: duplicate.id, name: "Deuxième corrigée", version: 2)
        let third = WorkspaceFixture.learner(id: UUID(), name: "Troisième")
        api.learnersHandler = { _, query, cursor in
            #expect(query == "élève")
            return cursor == nil
                ? .init(items: [first, duplicate], nextCursor: "page-2")
                : .init(items: [changed, third], nextCursor: nil)
        }
        await workspace.searchLearners(" élève ")
        await workspace.loadMoreLearners()
        #expect(workspace.learners == [first, changed, third])
        #expect(workspace.nextLearnersCursor == nil)
        #expect(workspace.learnersError == nil)
    }

    @Test func latePaginationCannotAppendRowsAfterChangingSchool() async throws {
        let api = WorkspaceAPIStub(memberships: [WorkspaceFixture.firstMembership, WorkspaceFixture.secondMembership])
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        let held = WorkspaceResponse<SchoolPage<SchoolLearner>>()
        api.learnersHandler = { school, _, cursor in
            if school == WorkspaceFixture.firstSchool, cursor != nil { return try await held.value() }
            return .init(items: [WorkspaceFixture.learner(school: school)], nextCursor: school == WorkspaceFixture.firstSchool ? "next" : nil)
        }
        await workspace.selectSchool(WorkspaceFixture.firstMembership)
        let oldPage = Task { await workspace.loadMoreLearners() }
        await held.waitUntilRequested()
        await workspace.selectSchool(WorkspaceFixture.secondMembership)
        held.succeed(.init(items: [WorkspaceFixture.learner(name: "Ancienne page")], nextCursor: "third"))
        await oldPage.value
        #expect(workspace.learners.count == 1)
        #expect(workspace.learners.first?.schoolId == WorkspaceFixture.secondSchool)
        #expect(workspace.nextLearnersCursor == nil)
        #expect(!workspace.isLoadingMoreLearners)
    }

    @Test func losingCurrentAccessPurgesAccountSchoolAndSelectedDetails() async {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        workspace.selectLearner(WorkspaceFixture.learnerID)
        await workspace.loadSelectedLearner()
        #expect(workspace.learner != nil)
        api.learnersHandler = { _, _, _ in throw SchoolAPIError.forbidden }
        await workspace.searchLearners("")
        #expect(workspace.person == nil)
        #expect(workspace.school == nil)
        #expect(workspace.membership == nil)
        #expect(workspace.learners.isEmpty)
        #expect(workspace.learner == nil)
        #expect(workspace.trainings.isEmpty)
        #expect(workspace.training == nil)
        #expect(workspace.accountError != nil)
        #expect(!workspace.requiresAuthentication)
    }

    @Test func lateUnauthorizedFromOldSchoolDoesNotPurgeTheNewSchool() async throws {
        let api = WorkspaceAPIStub(memberships: [WorkspaceFixture.firstMembership, WorkspaceFixture.secondMembership])
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        await workspace.selectSchool(WorkspaceFixture.firstMembership)
        let held = WorkspaceResponse<SchoolPage<SchoolLearner>>()
        api.learnersHandler = { school, _, _ in
            if school == WorkspaceFixture.firstSchool { return try await held.value() }
            return .init(items: [WorkspaceFixture.learner(school: school)], nextCursor: nil)
        }
        let old = Task { await workspace.searchLearners("ancien") }
        await held.waitUntilRequested()
        await workspace.selectSchool(WorkspaceFixture.secondMembership)
        held.fail(SchoolAPIError.unauthorized)
        await old.value
        #expect(workspace.person != nil)
        #expect(workspace.school?.id == WorkspaceFixture.secondSchool)
        #expect(!workspace.requiresAuthentication)
        #expect(workspace.accountError == nil)
    }

    @Test func signingOutDiscardsAnAccountResponseAlreadyInFlight() async throws {
        let api = WorkspaceAPIStub()
        let held = WorkspaceResponse<SchoolPerson>()
        api.meHandler = { try await held.value() }
        let workspace = SchoolWorkspace(api: api)
        let pending = Task { await workspace.loadAccount() }
        await held.waitUntilRequested()
        workspace.reset()
        held.succeed(api.person)
        await pending.value
        #expect(workspace.person == nil)
        #expect(workspace.school == nil)
        #expect(workspace.learners.isEmpty)
        #expect(!workspace.isLoadingAccount)
    }

    @Test func oldTrainingListCannotAppearInAnotherLearnersDossier() async throws {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        let first = WorkspaceFixture.learnerID
        let second = UUID()
        let held = WorkspaceResponse<SchoolPage<SchoolTraining>>()
        api.trainingsHandler = { school, learner, _ in
            if learner == first { return try await held.value() }
            return .init(items: [WorkspaceFixture.training(school: school, learner: learner)], nextCursor: nil)
        }
        workspace.selectLearner(first)
        let old = Task { await workspace.loadSelectedLearner() }
        await held.waitUntilRequested()
        workspace.selectLearner(second)
        #expect(workspace.learner == nil)
        #expect(workspace.trainings.isEmpty)
        await workspace.loadSelectedLearner()
        held.succeed(.init(items: [WorkspaceFixture.training(learner: first)], nextCursor: nil))
        await old.value
        #expect(workspace.learner?.id == second)
        #expect(workspace.trainings.count == 1)
        #expect(workspace.trainings.first?.learnerId == second)
    }

    @Test func typingClearsPreviousResultsBeforeTheDebounceAndResetCancelsIt() async {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        #expect(!workspace.learners.isEmpty)
        let callsBefore = api.learnerQueries.count
        workspace.selectLearner(WorkspaceFixture.learnerID)
        workspace.setSearchText("nouveau")
        #expect(workspace.learners.isEmpty)
        #expect(workspace.selectedLearnerID == nil)
        #expect(workspace.isSearching)
        workspace.reset()
        await Task.yield()
        #expect(api.learnerQueries.count == callsBefore)
        #expect(workspace.searchText.isEmpty)
    }

    @Test func crossSchoolPayloadNeverEntersTheDisplayedProjection() async {
        let api = WorkspaceAPIStub()
        api.learnersHandler = { _, _, _ in .init(items: [WorkspaceFixture.learner(school: WorkspaceFixture.secondSchool)], nextCursor: nil) }
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        #expect(workspace.learners.isEmpty)
        #expect(workspace.learnersError == SchoolAPIError.invalidResponse.localizedDescription)
    }
}

@MainActor
private final class WorkspaceAPIStub: SchoolAPI {
    let person: SchoolPerson
    var meHandler: (() async throws -> SchoolPerson)?
    var schoolHandler: ((UUID) async throws -> SchoolDetails)?
    var learnersHandler: ((UUID, String, String?) async throws -> SchoolPage<SchoolLearner>)?
    var trainingsHandler: ((UUID, UUID, String?) async throws -> SchoolPage<SchoolTraining>)?
    var learnerQueries: [String] = []

    init(memberships: [SchoolMembership] = [WorkspaceFixture.firstMembership]) {
        person = SchoolPerson(personId: UUID(), version: 1, displayName: "Compte de test", locale: "fr", memberships: memberships)
    }
    func me() async throws -> SchoolPerson {
        if let meHandler { return try await meHandler() }
        return person
    }
    func school(id: UUID) async throws -> SchoolDetails {
        if let schoolHandler { return try await schoolHandler(id) }
        return WorkspaceFixture.school(id)
    }
    func learners(schoolID: UUID, query: String, cursor: String?) async throws -> SchoolPage<SchoolLearner> {
        learnerQueries.append(query)
        if let learnersHandler { return try await learnersHandler(schoolID, query, cursor) }
        return .init(items: [WorkspaceFixture.learner(school: schoolID)], nextCursor: nil)
    }
    func learner(schoolID: UUID, id: UUID) async throws -> SchoolLearner {
        WorkspaceFixture.learner(id: id, school: schoolID)
    }
    func trainings(schoolID: UUID, learnerID: UUID, cursor: String?) async throws -> SchoolPage<SchoolTraining> {
        if let trainingsHandler { return try await trainingsHandler(schoolID, learnerID, cursor) }
        return .init(items: [WorkspaceFixture.training(school: schoolID, learner: learnerID)], nextCursor: nil)
    }
    func training(schoolID: UUID, id: UUID) async throws -> SchoolTraining {
        WorkspaceFixture.training(id: id, school: schoolID)
    }
}

@MainActor
private final class WorkspaceResponse<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, any Error>?
    private var requested: CheckedContinuation<Void, Never>?
    func value() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            requested?.resume()
            requested = nil
        }
    }
    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { requested = $0 }
    }
    func succeed(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
    func fail(_ error: any Error) { continuation?.resume(throwing: error); continuation = nil }
}

private enum WorkspaceFixture {
    static let firstSchool = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    static let secondSchool = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
    static let learnerID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    static let firstMembership = SchoolMembership(membershipId: UUID(), schoolId: firstSchool,
        schoolName: "École test A", roles: ["INSTRUCTOR"], grants: [], accessEpoch: 1)
    static let secondMembership = SchoolMembership(membershipId: UUID(), schoolId: secondSchool,
        schoolName: "École test B", roles: ["INSTRUCTOR"], grants: [], accessEpoch: 1)

    static func school(_ id: UUID, status: String = "ACTIVE") -> SchoolDetails {
        SchoolDetails(id: id, schoolId: id, version: 1, name: "École de test", timeZone: "Europe/Zurich",
            status: status, contactEmail: "ecole@example.test", contactPhone: nil, logoAssetId: nil,
            modules: .init(gpsEnabled: true, packsEnabled: false, collectiveCoursesEnabled: false, courseOffersVisibleByDefault: false), configurationVersion: 1)
    }
    static func learner(id: UUID = learnerID, school: UUID = firstSchool, name: String = "Élève de test", version: Int = 1) -> SchoolLearner {
        SchoolLearner(id: id, schoolId: school, personId: UUID(), version: version, displayName: name,
            contactEmail: nil, contactPhone: nil, archivedAt: nil, profileReadiness: nil, profilePhotoDocumentId: nil)
    }
    static func training(id: UUID = UUID(), school: UUID = firstSchool, learner: UUID = learnerID) -> SchoolTraining {
        SchoolTraining(id: id, schoolId: school, learnerId: learner, offeringId: UUID(), version: 1,
            categoryCode: "B", status: "ACTIVE", startedOn: "2026-09-24", closedOn: nil)
    }
}
