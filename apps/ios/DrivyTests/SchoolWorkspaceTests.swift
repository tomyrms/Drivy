import Foundation
import Testing
@testable import Drivy

@MainActor
struct SchoolWorkspaceTests {
    @Test func refreshingTheSchoolRecoversGPSWithoutSigningInAgainOrStartingCapture() async {
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["ADMIN", "INSTRUCTOR"], grants: [], accessEpoch: 1)
        let api = WorkspaceAPIStub(memberships: [membership])
        api.schoolHandler = { _ in HubFixture.school(gps: false) }
        let workspace = SchoolWorkspace(api: api), controller = SchoolCaptureSessionController()
        await workspace.loadAccount()
        let person = workspace.person
        let lesson = HubFixture.lesson(actualStart: "2026-09-28T12:00:00Z"), now = HubFixture.date("2026-09-28T12:05:00Z")
        #expect(!SchoolLessonHubRules.mayStartCapture(lesson: lesson, isAuthor: true, school: workspace.school,
            capture: .none, controllerCanPrepare: controller.canPrepareCapture, now: now))
        // Le portail change uniquement le module ; les droits et la connexion restent identiques.
        api.schoolHandler = { _ in HubFixture.school(gps: true) }
        workspace.willOpenManagement()
        await workspace.refreshOnForeground()
        #expect(workspace.person == person && workspace.membership == membership)
        #expect(SchoolLessonHubRules.mayStartCapture(lesson: lesson, isAuthor: true, school: workspace.school,
            capture: .none, controllerCanPrepare: controller.canPrepareCapture, now: now))
        #expect(controller.state == .idle && controller.captureID == nil)
        #expect(!workspace.requiresAuthentication && workspace.schoolError == nil)
        // Une panne de la relecture explicite conserve le réglage confirmé et affiche son erreur.
        api.schoolHandler = { _ in throw SchoolAPIError.unavailable }
        await workspace.refreshEntry()
        #expect(workspace.school?.modules.gpsEnabled == true && workspace.schoolError != nil)
        #expect(controller.state == .idle && controller.captureID == nil)
    }

    @Test(arguments: [["LEARNER"], ["ADMIN", "LEARNER"]], [false, true])
    func learnerTabsLoadTheirOwnDossierIncludingAnArchivedOneInsteadOfTheDirectory(roles: [String], archived: Bool) async {
        let membership = SchoolMembership(membershipId: UUID(), schoolId: WorkspaceFixture.firstSchool,
            schoolName: "École test A", roles: roles, grants: [], accessEpoch: 1)
        let api = WorkspaceAPIStub(memberships: [membership])
        let own = SchoolLearner(id: UUID(), schoolId: membership.schoolId, personId: api.person.personId, version: 1,
            displayName: "Élève responsable", contactEmail: nil, contactPhone: nil,
            archivedAt: archived ? "2026-10-01T00:00:00Z" : nil, profileReadiness: nil, profilePhotoDocumentId: nil)
        let directory = (0..<50).map { _ in WorkspaceFixture.learner(id: UUID()) }
        api.learnersHandler = { _, _, _ in .init(items: directory, nextCursor: "page-2") }
        api.ownLearnersHandler = { _ in .init(items: [own], nextCursor: nil) }
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        #expect(workspace.entryDestination == .learner)
        #expect(workspace.learners == [own])
        #expect(workspace.nextLearnersCursor == nil)
        #expect(api.ownLearnersCalls == 1 && api.learnerQueries.isEmpty)
        // La relecture silencieuse suit la même portée et ne remet jamais la première page administrative.
        await workspace.refreshLearners(minimumInterval: 0)
        #expect(workspace.learners == [own])
        #expect(api.ownLearnersCalls == 2 && api.learnerQueries.isEmpty)
    }

    @Test(arguments: [["INSTRUCTOR"], ["ADMIN", "INSTRUCTOR"], ["ADMIN", "INSTRUCTOR", "LEARNER"]])
    func instructorTabsKeepTheStaffListEvenWhenTheAccountIsAlsoALearner(roles: [String]) async {
        let membership = SchoolMembership(membershipId: UUID(), schoolId: WorkspaceFixture.firstSchool,
            schoolName: "École test A", roles: roles, grants: [], accessEpoch: 1)
        let api = WorkspaceAPIStub(memberships: [membership])
        let directory = [WorkspaceFixture.learner(), WorkspaceFixture.learner(id: UUID())]
        api.learnersHandler = { _, _, _ in .init(items: directory, nextCursor: "page-2") }
        api.ownLearnersHandler = { _ in .init(items: [], nextCursor: nil) }
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        await workspace.refreshLearners(minimumInterval: 0)
        #expect(workspace.entryDestination == .instructor)
        #expect(workspace.learners == directory)
        #expect(workspace.nextLearnersCursor == "page-2")
        #expect(api.ownLearnersCalls == (roles.contains("LEARNER") ? 1 : 0) && api.learnerQueries.count == 2)
    }

    @Test func aDualRoleAccountKeepsItsOwnDossierOutsideDirectorySearchAndSelection() async {
        let membership = SchoolMembership(membershipId: UUID(), schoolId: WorkspaceFixture.firstSchool,
            schoolName: "École test A", roles: ["INSTRUCTOR", "LEARNER"], grants: [], accessEpoch: 1)
        let api = WorkspaceAPIStub(memberships: [membership])
        let own = SchoolLearner(id: UUID(), schoolId: membership.schoolId, personId: api.person.personId, version: 1,
            displayName: "Mon dossier", contactEmail: nil, contactPhone: nil,
            archivedAt: "2026-10-01T00:00:00Z", profileReadiness: nil, profilePhotoDocumentId: nil)
        let assigned = WorkspaceFixture.learner(id: UUID())
        api.learnersHandler = { _, query, _ in .init(items: query.isEmpty ? [assigned] : [], nextCursor: nil) }
        api.ownLearnersHandler = { _ in .init(items: [own], nextCursor: nil) }
        api.learnerHandler = { _, _ in assigned }
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        #expect(workspace.entryDestination == .instructor && workspace.learners == [assigned])
        #expect(workspace.ownLearner == own && workspace.ownLearnerError == nil)
        workspace.selectLearner(assigned.id)
        await workspace.loadSelectedLearner()
        #expect(workspace.learner == assigned && workspace.ownLearner == own)
        await workspace.searchLearners("sans résultat")
        #expect(workspace.learners.isEmpty && workspace.ownLearner == own)
        api.ownLearnersHandler = { _ in throw SchoolAPIError.unavailable }
        await workspace.refreshOwnLearner(minimumInterval: 0)
        #expect(workspace.ownLearner == own && workspace.ownLearnerError != nil)
        // Une projection étrangère ne remplace jamais le dossier déjà autorisé.
        api.ownLearnersHandler = { _ in .init(items: [assigned], nextCursor: nil) }
        await workspace.refreshOwnLearner(minimumInterval: 0)
        #expect(workspace.ownLearner == own && workspace.ownLearnerError == SchoolAPIError.invalidResponse.localizedDescription)
        workspace.reset()
        #expect(workspace.ownLearner == nil && workspace.ownLearnerError == nil)
    }

    @Test func switchingSchoolsDropsTheOwnDossierAndRejectsItsLateResponse() async {
        let first = SchoolMembership(membershipId: UUID(), schoolId: WorkspaceFixture.firstSchool,
            schoolName: "École test A", roles: ["INSTRUCTOR", "LEARNER"], grants: [], accessEpoch: 1)
        let second = SchoolMembership(membershipId: UUID(), schoolId: WorkspaceFixture.secondSchool,
            schoolName: "École test B", roles: ["INSTRUCTOR", "LEARNER"], grants: [], accessEpoch: 1)
        let api = WorkspaceAPIStub(memberships: [first, second])
        func own(_ school: UUID) -> SchoolLearner {
            .init(id: UUID(), schoolId: school, personId: api.person.personId, version: 1, displayName: "Mon dossier",
                contactEmail: nil, contactPhone: nil, archivedAt: nil, profileReadiness: nil, profilePhotoDocumentId: nil)
        }
        let oldDossier = own(first.schoolId), currentDossier = own(second.schoolId)
        let held = WorkspaceResponse<SchoolPage<SchoolLearner>>()
        api.ownLearnersHandler = { school in
            if school == first.schoolId { return try await held.value() }
            return .init(items: [currentDossier], nextCursor: nil)
        }
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        let old = Task { await workspace.selectSchool(first) }
        await held.waitUntilRequested()
        await workspace.selectSchool(second)
        #expect(workspace.ownLearner == currentDossier)
        held.succeed(.init(items: [oldDossier], nextCursor: nil))
        await old.value
        #expect(workspace.membership == second && workspace.ownLearner == currentDossier)
        workspace.leaveSchool()
        #expect(workspace.ownLearner == nil && workspace.ownLearnerError == nil)
    }

    @Test func returningFromTheWebReadsActivationEvenWithTheSameMembership() async {
        let api = WorkspaceAPIStub(memberships: [WorkspaceFixture.adminMembership])
        api.schoolHandler = { WorkspaceFixture.school($0, status: "DRAFT") }
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        #expect(workspace.entryDestination == .prepareSchool)
        let reads = api.schoolReads
        workspace.willOpenManagement()
        api.schoolHandler = { WorkspaceFixture.school($0, status: "ACTIVE") }
        await workspace.refreshOnForeground()
        #expect(api.schoolReads == reads + 1)
        #expect(workspace.entryDestination == .management)
        #expect(workspace.membership == WorkspaceFixture.adminMembership)
        #expect(!workspace.isRefreshingEntry)
        // Le retour ordinaire suivant n'ajoute pas une lecture scolaire.
        await workspace.refreshOnForeground()
        #expect(api.schoolReads == reads + 1)
    }

    @Test func draftWithoutAdminAlsoSeesActivationAtTheNextForeground() async {
        let api = WorkspaceAPIStub()
        api.schoolHandler = { WorkspaceFixture.school($0, status: "DRAFT") }
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        #expect(workspace.entryDestination == .waitingForActivation)
        api.schoolHandler = { WorkspaceFixture.school($0, status: "ACTIVE") }
        await workspace.refreshOnForeground()
        #expect(workspace.entryDestination == .instructor)
        #expect(!workspace.learners.isEmpty)
    }

    @Test func failedReturnKeepsTheConfirmedStateAndRetriesInsteadOfInventingActivation() async {
        let api = WorkspaceAPIStub(memberships: [WorkspaceFixture.adminMembership])
        api.schoolHandler = { WorkspaceFixture.school($0, status: "DRAFT") }
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        workspace.willOpenManagement()
        api.meHandler = { throw SchoolAPIError.unavailable }
        let reads = api.schoolReads
        await workspace.refreshOnForeground()
        #expect(workspace.entryDestination == .prepareSchool)
        #expect(workspace.schoolError != nil)
        #expect(api.schoolReads == reads)
        api.meHandler = nil
        api.schoolHandler = { _ in throw SchoolAPIError.unavailable }
        await workspace.refreshOnForeground()
        #expect(workspace.entryDestination == .prepareSchool)
        #expect(workspace.schoolError != nil)
        api.schoolHandler = { WorkspaceFixture.school($0, status: "ACTIVE") }
        await workspace.refreshOnForeground()
        #expect(workspace.entryDestination == .management)
        #expect(workspace.schoolError == nil)
    }

    @Test func returnFromWebAppliesNewRolesOnceAndDoesNotRestoreRevokedAccess() async {
        let api = WorkspaceAPIStub(memberships: [WorkspaceFixture.adminMembership])
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        workspace.willOpenManagement()
        let previous = WorkspaceFixture.adminMembership
        let instructor = SchoolMembership(membershipId: previous.membershipId, schoolId: previous.schoolId,
            schoolName: previous.schoolName, roles: ["ADMIN", "INSTRUCTOR"], grants: [], accessEpoch: 2)
        api.meHandler = { SchoolPerson(personId: api.person.personId, version: 2, displayName: api.person.displayName,
            locale: "fr", memberships: [instructor]) }
        let reads = api.schoolReads
        await workspace.refreshOnForeground()
        #expect(workspace.entryDestination == .instructor)
        #expect(api.schoolReads == reads + 1)
        workspace.willOpenManagement()
        api.meHandler = { throw SchoolAPIError.forbidden }
        await workspace.refreshOnForeground()
        #expect(workspace.accessRevoked)
        #expect(workspace.membership == nil && workspace.school == nil && workspace.person == nil)
    }

    @Test func archivedSchoolAfterPortalReturnClosesTheFieldDestination() async {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        workspace.willOpenManagement()
        api.schoolHandler = { WorkspaceFixture.school($0, status: "ARCHIVED") }
        await workspace.refreshOnForeground()
        #expect(workspace.entryDestination == .archived)
    }

    @Test func theAdministrationReadsProfilesToCompleteSchoolWideAndEachRereadCorrectsThem() async {
        let api = WorkspaceAPIStub(memberships: [WorkspaceFixture.adminMembership])
        let first = WorkspaceFixture.learner(id: UUID(), name: "Incomplet A", readiness: "ACTION_REQUIRED")
        let second = WorkspaceFixture.learner(id: UUID(), name: "Incomplet B", readiness: "MINIMAL")
        api.learnersToCompleteHandler = { _ in [first, second] }
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        #expect(workspace.learnersToComplete == [first.id, second.id])
        // Le dossier complété puis relu éteint son point sans attendre une autre lecture de l’école.
        api.learnerHandler = { school, id in WorkspaceFixture.learner(id: id, school: school, name: "Incomplet A", readiness: "READY") }
        workspace.selectLearner(first.id)
        await workspace.loadSelectedLearner()
        #expect(workspace.learnersToComplete == [second.id])
        // Une panne garde ce qui a été lu : elle n’allume ni n’éteint rien.
        api.learnersToCompleteHandler = { _ in throw SchoolAPIError.unavailable }
        await workspace.refreshLearnersToComplete()
        #expect(workspace.learnersToComplete == [second.id])
        #expect(workspace.accountError == nil)
        // Complété ailleurs (web, autre appareil) : la relecture au retour dans l’app le retire.
        api.learnersToCompleteHandler = { _ in [] }
        await workspace.refreshLearnersToComplete()
        #expect(workspace.learnersToComplete == [])
    }

    @Test func anInstructorNeverReadsTheSchoolWideProfilesToComplete() async {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        await workspace.refreshLearnersToComplete()
        #expect(api.learnersToCompleteCalls == 0)
        #expect(workspace.learnersToComplete == nil)
    }

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

    @Test func returningToTheAppKeepsTheScreenAndOnlyARightsChangeReloadsTheSchool() async throws {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        let now = Date()
        let calls = RefreshCounter()
        api.meHandler = { calls.value += 1; throw SchoolAPIError.unavailable }
        // Within five minutes of the last read, nothing is asked.
        await workspace.refreshAccount(now: now.addingTimeInterval(10))
        #expect(calls.value == 0)
        // Offline: everything stays on screen, nothing is revoked.
        await workspace.refreshAccount(now: now.addingTimeInterval(400))
        #expect(calls.value == 1)
        #expect(workspace.person != nil && workspace.membership != nil && workspace.school != nil)
        #expect(workspace.accountError == nil && !workspace.accessRevoked && !workspace.isLoadingAccount)
        // Same rights: the school is not reloaded.
        let loadedSchool = workspace.school
        api.meHandler = { api.person }
        await workspace.refreshAccount(now: now.addingTimeInterval(800))
        #expect(workspace.school == loadedSchool && !workspace.isLoadingSchool)
        // A new access epoch reloads the school with the new membership.
        let promoted = SchoolMembership(membershipId: WorkspaceFixture.firstMembership.membershipId, schoolId: WorkspaceFixture.firstSchool,
            schoolName: "École test A", roles: ["INSTRUCTOR", "ADMIN"], grants: [], accessEpoch: 2)
        api.meHandler = { SchoolPerson(personId: api.person.personId, version: 2, displayName: "Compte de test", locale: "fr", memberships: [promoted]) }
        await workspace.refreshAccount(now: now.addingTimeInterval(1_200))
        #expect(workspace.membership?.accessEpoch == 2 && workspace.school != nil)
        // A refusal closes the account, as any read does.
        api.meHandler = { throw SchoolAPIError.forbidden }
        await workspace.refreshAccount(now: now.addingTimeInterval(1_600))
        #expect(workspace.person == nil && workspace.accessRevoked)
    }

    @Test func reloadingTheDossierKeepsItsTrainingsOnScreenUntilTheAnswerReplacesThem() async throws {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        workspace.selectLearner(WorkspaceFixture.learnerID)
        await workspace.loadSelectedLearner()
        let before = workspace.trainings
        #expect(before.count == 1)
        let held = WorkspaceResponse<SchoolPage<SchoolTraining>>()
        api.trainingsHandler = { _, _, _ in try await held.value() }
        let reload = Task { await workspace.loadTrainings() }
        await held.waitUntilRequested()
        // The screen (and the sheets it carries) depends on these rows: they stay while the list is read again.
        #expect(workspace.trainings == before)
        #expect(workspace.isLoadingTrainings)
        let fresh = WorkspaceFixture.training()
        held.succeed(.init(items: [fresh], nextCursor: nil))
        await reload.value
        #expect(workspace.trainings == [fresh])
        #expect(!workspace.isLoadingTrainings)
    }

    @Test func aFailedReloadOfTheTrainingsKeepsTheRowsAndSaysSo() async throws {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        workspace.selectLearner(WorkspaceFixture.learnerID)
        await workspace.loadSelectedLearner()
        let before = workspace.trainings
        api.trainingsHandler = { _, _, _ in throw SchoolAPIError.unavailable }
        await workspace.loadTrainings()
        #expect(workspace.trainings == before)
        #expect(workspace.trainingsError != nil)
        #expect(!workspace.isLoadingTrainings)
        #expect(!workspace.accessRevoked)
    }

    /// Tirer pour actualiser le dossier annulait la relecture en route : l’annulation s’affichait en
    /// « Le chargement a été interrompu ». Une lecture annulée n’est pas une panne : le dossier reste, sans erreur.
    @Test func aCancelledReloadOfTheDossierIsNotAnError() async throws {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        workspace.selectLearner(WorkspaceFixture.learnerID)
        await workspace.loadSelectedLearner()
        let learner = workspace.learner
        let trainings = workspace.trainings
        #expect(learner != nil && !trainings.isEmpty)
        api.learnerHandler = { _, _ in throw CancellationError() }
        await workspace.loadSelectedLearner()
        #expect(workspace.learner == learner && workspace.learnerError == nil && !workspace.isLoadingLearner)
        api.learnerHandler = nil
        api.trainingsHandler = { _, _, _ in throw URLError(.cancelled) }
        await workspace.loadSelectedLearner()
        #expect(workspace.trainings == trainings && workspace.trainingsError == nil && !workspace.isLoadingTrainings)
        // Une vraie panne reste dite, avec de quoi réessayer.
        api.trainingsHandler = { _, _, _ in throw SchoolAPIError.unavailable }
        await workspace.loadTrainings()
        #expect(workspace.trainingsError != nil)
    }

    @Test func refreshingAPartialTrainingListNeverMakesItLookComplete() async throws {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        api.trainingsHandler = { school, learner, _ in
            .init(items: [WorkspaceFixture.training(school: school, learner: learner)], nextCursor: "more-trainings")
        }
        await workspace.loadAccount()
        workspace.selectLearner(WorkspaceFixture.learnerID)
        await workspace.loadSelectedLearner()
        let held = WorkspaceResponse<SchoolPage<SchoolTraining>>()
        api.trainingsHandler = { _, _, _ in try await held.value() }
        let reload = Task { await workspace.loadTrainings() }
        await held.waitUntilRequested()
        // Le dossier ne doit pas basculer vers une formation unique tant qu'une autre page est connue.
        #expect(workspace.trainings.count == 1 && workspace.nextTrainingsCursor == "more-trainings")
        held.fail(SchoolAPIError.unavailable)
        await reload.value
        #expect(workspace.trainings.count == 1 && workspace.nextTrainingsCursor == "more-trainings")
        #expect(workspace.trainingsError != nil && !workspace.isLoadingTrainings)
    }

    @Test func reopeningTheOpenDossierShowsNoLoadingScreen() async throws {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        workspace.selectLearner(WorkspaceFixture.learnerID)
        await workspace.loadSelectedLearner()
        #expect(workspace.learner != nil)
        let again = Task { await workspace.loadSelectedLearner() }
        await Task.yield()
        #expect(workspace.learner != nil)
        #expect(!workspace.isLoadingLearner)
        await again.value
        #expect(workspace.learner?.id == WorkspaceFixture.learnerID)
        #expect(workspace.trainings.count == 1)
    }

    @Test func rereadingTheDossierUpdatesItsRowInTheLearnerListWithoutReorderingIt() async throws {
        let api = WorkspaceAPIStub()
        let before = WorkspaceFixture.learner(id: UUID(), name: "Élève précédent")
        let stale = WorkspaceFixture.learner(name: "Ancien nom")
        let after = WorkspaceFixture.learner(id: UUID(), name: "Élève suivant")
        api.learnersHandler = { _, _, _ in .init(items: [before, stale, after], nextCursor: "page-2") }
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        #expect(workspace.learners == [before, stale, after])
        let corrected = WorkspaceFixture.learner(name: "Nom corrigé", version: 2)
        api.learnerHandler = { _, _ in corrected }
        workspace.selectLearner(WorkspaceFixture.learnerID)
        await workspace.loadSelectedLearner()
        #expect(workspace.learner == corrected)
        // La liste Élèves montre déjà le nom relu, à la même place, et sa pagination n'a pas bougé.
        #expect(workspace.learners == [before, corrected, after])
        #expect(workspace.nextLearnersCursor == "page-2")
    }

    @Test func rereadingADossierAbsentFromTheListNeverAddsARow() async throws {
        let api = WorkspaceAPIStub()
        let listed = WorkspaceFixture.learner(id: UUID(), name: "Élève listé")
        api.learnersHandler = { _, _, _ in .init(items: [listed], nextCursor: nil) }
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        workspace.selectLearner(WorkspaceFixture.learnerID)
        await workspace.loadSelectedLearner()
        #expect(workspace.learner?.id == WorkspaceFixture.learnerID)
        #expect(workspace.learners == [listed])
    }

    @Test func rereadingTheAccountNeverEmptiesTheScreenWhileTheSameAccountIsSignedIn() async throws {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        workspace.selectLearner(WorkspaceFixture.learnerID)
        await workspace.loadSelectedLearner()
        let held = WorkspaceResponse<SchoolPerson>()
        api.meHandler = { try await held.value() }
        let reread = Task { await workspace.loadAccount() }
        await held.waitUntilRequested()
        // A sheet opened on this membership would be closed by any purge: nothing is cleared.
        #expect(workspace.person != nil && workspace.membership != nil && workspace.school != nil)
        #expect(workspace.learner?.id == WorkspaceFixture.learnerID)
        held.succeed(api.person)
        await reread.value
        #expect(workspace.membership == WorkspaceFixture.firstMembership)
        #expect(workspace.learner?.id == WorkspaceFixture.learnerID)
        #expect(workspace.accountError == nil && !workspace.accessRevoked)
    }

    @Test func retryingTheCurrentSchoolKeepsTheScopeButDropsItsLateAnswers() async throws {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        let membership = try #require(workspace.membership)
        let held = WorkspaceResponse<SchoolDetails>()
        api.schoolHandler = { _ in try await held.value() }
        let retry = Task { await workspace.selectSchool(membership) }
        await held.waitUntilRequested()
        #expect(workspace.membership == membership)
        #expect(workspace.person != nil)
        held.succeed(WorkspaceFixture.school(membership.schoolId))
        await retry.value
        #expect(workspace.school?.id == membership.schoolId && !workspace.isLoadingSchool)
    }

    @Test func retryingTheCurrentSchoolNeverLeavesTheOpenDossierLoadingForever() async throws {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        let membership = try #require(workspace.membership)
        workspace.selectLearner(WorkspaceFixture.learnerID)
        let held = WorkspaceResponse<SchoolLearner>()
        api.learnerHandler = { _, _ in try await held.value() }
        let reading = Task { await workspace.loadSelectedLearner() }
        await held.waitUntilRequested()
        #expect(workspace.isLoadingLearner && workspace.learner == nil)
        // Nouvel essai de l’école pendant la lecture du dossier : la réponse en vol sera écartée, le dossier est relu.
        api.learnerHandler = nil
        await workspace.selectSchool(membership)
        #expect(workspace.selectedLearnerID == WorkspaceFixture.learnerID)
        #expect(workspace.learner?.id == WorkspaceFixture.learnerID && !workspace.isLoadingLearner && !workspace.isLoadingTrainings)
        #expect(workspace.trainings.count == 1 && workspace.learnerError == nil)
        held.succeed(WorkspaceFixture.learner(name: "Réponse tardive"))
        await reading.value
        #expect(workspace.learner?.displayName == "Élève de test" && !workspace.isLoadingLearner)
    }

    @Test func aBriefNetworkFailureDoesNotPostponeTheNextAccountCheck() async throws {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        let now = Date()
        let calls = RefreshCounter()
        api.meHandler = { calls.value += 1; throw SchoolAPIError.unavailable }
        await workspace.refreshAccount(now: now.addingTimeInterval(400))
        await workspace.refreshAccount(now: now.addingTimeInterval(410))
        #expect(calls.value == 2)
    }

    @Test func closingTheAccountDropsTheSharedTrainingModel() async throws {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        let membership = WorkspaceFixture.firstMembership
        let scope = SchoolCommandScope(personID: api.person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: "https://api.example.test")
        let client = SchoolTrainingClient(baseURL: URL(string: "https://api.example.test")!, tokenSource: WorkspaceToken())
        let learner = UUID(), training = UUID()
        let first = SchoolTrainingModelCache.model(scope: scope, membership: membership, learnerID: learner, trainingID: training, client: client)
        #expect(first.isNew)
        workspace.reset()
        #expect(first.model.invalidated)
        let second = SchoolTrainingModelCache.model(scope: scope, membership: membership, learnerID: learner, trainingID: training, client: client)
        #expect(second.isNew && second.model !== first.model)
        SchoolTrainingModelCache.reset()
    }

    @Test(arguments: [false, true])
    func anOlderAccountRefreshCannotReplaceNewerRightsOrCloseTheCurrentAccount(fails: Bool) async {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        let held = WorkspaceResponse<SchoolPerson>()
        api.meHandler = { try await held.value() }
        let old = Task { await workspace.refreshAccount(minimumInterval: 0) }
        await held.waitUntilRequested()
        let membership = SchoolMembership(membershipId: WorkspaceFixture.firstMembership.membershipId,
            schoolId: WorkspaceFixture.firstSchool, schoolName: "École actualisée", roles: ["INSTRUCTOR", "ADMIN"],
            grants: [], accessEpoch: 2)
        let updated = SchoolPerson(personId: api.person.personId, version: 2, displayName: "Nom actualisé",
            locale: "fr", memberships: [membership])
        api.meHandler = { updated }
        await workspace.refreshAccount(minimumInterval: 0)
        if fails { held.fail(SchoolAPIError.forbidden) }
        else { held.succeed(api.person) }
        await old.value
        #expect(workspace.person == updated)
        #expect(workspace.membership == membership && workspace.school != nil)
        #expect(!workspace.accessRevoked && workspace.accountError == nil)
    }

    @Test func theGuidedWelcomeIsOfferedAtMostOnceAWeekPerMembership() throws {
        let defaults = try #require(UserDefaults(suiteName: "drivy-tests-onboarding-\(UUID().uuidString)"))
        let membership = UUID(), now = Date()
        #expect(!SchoolOnboardingDeferral.isDeferred(membership, now: now, defaults: defaults))
        SchoolOnboardingDeferral.record(membership, now: now, defaults: defaults)
        #expect(SchoolOnboardingDeferral.isDeferred(membership, now: now.addingTimeInterval(6 * 86_400), defaults: defaults))
        #expect(!SchoolOnboardingDeferral.isDeferred(membership, now: now.addingTimeInterval(7 * 86_400 + 1), defaults: defaults))
        #expect(!SchoolOnboardingDeferral.isDeferred(UUID(), now: now, defaults: defaults))
    }

    @Test func rereadingTheOpenDossierKeepsItWithoutALoadingState() async {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        workspace.selectLearner(WorkspaceFixture.learnerID)
        await workspace.loadSelectedLearner()
        #expect(workspace.learner?.id == WorkspaceFixture.learnerID)
        // Relecture silencieuse du même dossier : aucun indicateur de chargement, le dossier reste à l’écran.
        await workspace.loadSelectedLearner()
        #expect(!workspace.isLoadingLearner)
        #expect(workspace.learner?.id == WorkspaceFixture.learnerID)
    }

    @Test func silentLearnerRefreshKeepsSelectionAndLoadedPagesAndShowsANewLearner() async {
        let api = WorkspaceAPIStub()
        let first = WorkspaceFixture.learner(id: WorkspaceFixture.learnerID, name: "Première")
        let second = WorkspaceFixture.learner(id: UUID(), name: "Deuxième")
        let third = WorkspaceFixture.learner(id: UUID(), name: "Troisième")
        api.learnersHandler = { _, _, cursor in
            cursor == nil ? .init(items: [first, second], nextCursor: "page-2") : .init(items: [third], nextCursor: nil)
        }
        api.learnerHandler = { _, _ in first }
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        await workspace.loadMoreLearners()
        workspace.selectLearner(first.id)
        await workspace.loadSelectedLearner()
        #expect(workspace.learners == [first, second, third])
        let newcomer = WorkspaceFixture.learner(id: UUID(), name: "Arrivée")
        let renamed = WorkspaceFixture.learner(id: first.id, name: "Première corrigée", version: 2)
        api.learnersHandler = { _, _, cursor in
            #expect(cursor == nil)
            return .init(items: [newcomer, renamed], nextCursor: "page-2")
        }
        await workspace.refreshLearners(minimumInterval: 0)
        #expect(workspace.learners == [newcomer, renamed, second, third])
        #expect(workspace.selectedLearnerID == first.id)
        #expect(workspace.learner == first)
        #expect(workspace.nextLearnersCursor == nil)
        #expect(!workspace.isSearching && workspace.learnersError == nil)
    }

    @Test func silentLearnerRefreshIsBoundedAndSaysNothingOnFailure() async {
        let api = WorkspaceAPIStub()
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        let shown = workspace.learners
        let read = api.learnerQueries.count
        let now = Date()
        // La liste vient d’être lue : pas de seconde lecture dans la minute.
        await workspace.refreshLearners(now: now.addingTimeInterval(10))
        #expect(api.learnerQueries.count == read)
        await workspace.refreshLearners(now: now.addingTimeInterval(120))
        #expect(api.learnerQueries.count == read + 1)
        api.learnersHandler = { _, _, _ in throw SchoolAPIError.unavailable }
        await workspace.refreshLearners(now: now.addingTimeInterval(300))
        #expect(api.learnerQueries.count == read + 2)
        #expect(workspace.learnersError == nil)
        #expect(workspace.learners.map(\.id) == shown.map(\.id))
        // Une panne ne compte pas comme une lecture : l’occasion suivante réessaie sans attendre une minute.
        await workspace.refreshLearners(now: now.addingTimeInterval(310))
        #expect(api.learnerQueries.count == read + 3)
    }
}

@MainActor
private final class RefreshCounter { var value = 0 }

@MainActor
private final class WorkspaceToken: AccessTokenSource {
    func accessToken() async throws -> String { "test-token" }
}

@MainActor
private final class WorkspaceAPIStub: SchoolAPI {
    let person: SchoolPerson
    var meHandler: (() async throws -> SchoolPerson)?
    var schoolHandler: ((UUID) async throws -> SchoolDetails)?
    var learnersHandler: ((UUID, String, String?) async throws -> SchoolPage<SchoolLearner>)?
    var ownLearnersHandler: ((UUID) async throws -> SchoolPage<SchoolLearner>)?
    var ownLearnersCalls = 0
    var trainingsHandler: ((UUID, UUID, String?) async throws -> SchoolPage<SchoolTraining>)?
    var learnerHandler: ((UUID, UUID) async throws -> SchoolLearner)?
    var learnerQueries: [String] = []
    var schoolReads = 0
    var learnersToCompleteHandler: ((UUID) async throws -> [SchoolLearner])?
    var learnersToCompleteCalls = 0

    init(memberships: [SchoolMembership] = [WorkspaceFixture.firstMembership]) {
        person = SchoolPerson(personId: UUID(), version: 1, displayName: "Compte de test", locale: "fr", memberships: memberships)
    }
    func me() async throws -> SchoolPerson {
        if let meHandler { return try await meHandler() }
        return person
    }
    func school(id: UUID) async throws -> SchoolDetails {
        schoolReads += 1
        if let schoolHandler { return try await schoolHandler(id) }
        return WorkspaceFixture.school(id)
    }
    func learners(schoolID: UUID, query: String, cursor: String?) async throws -> SchoolPage<SchoolLearner> {
        learnerQueries.append(query)
        if let learnersHandler { return try await learnersHandler(schoolID, query, cursor) }
        return .init(items: [WorkspaceFixture.learner(school: schoolID)], nextCursor: nil)
    }
    func ownLearners(schoolID: UUID) async throws -> SchoolPage<SchoolLearner> {
        ownLearnersCalls += 1
        if let ownLearnersHandler { return try await ownLearnersHandler(schoolID) }
        return try await learners(schoolID: schoolID, query: "", cursor: nil)
    }
    func learnersToComplete(schoolID: UUID) async throws -> [SchoolLearner]? {
        learnersToCompleteCalls += 1
        guard let learnersToCompleteHandler else { return nil }
        return try await learnersToCompleteHandler(schoolID)
    }
    func learner(schoolID: UUID, id: UUID) async throws -> SchoolLearner {
        if let learnerHandler { return try await learnerHandler(schoolID, id) }
        return WorkspaceFixture.learner(id: id, school: schoolID)
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
    static let adminMembership = SchoolMembership(membershipId: UUID(), schoolId: firstSchool,
        schoolName: "École test A", roles: ["ADMIN"], grants: [], accessEpoch: 1)

    static func school(_ id: UUID, status: String = "ACTIVE") -> SchoolDetails {
        SchoolDetails(id: id, schoolId: id, version: 1, name: "École de test", timeZone: "Europe/Zurich",
            status: status, contactEmail: "ecole@example.test", contactPhone: nil, logoAssetId: nil,
            modules: .init(gpsEnabled: true, packsEnabled: false, collectiveCoursesEnabled: false, courseOffersVisibleByDefault: false), configurationVersion: 1)
    }
    static func learner(id: UUID = learnerID, school: UUID = firstSchool, name: String = "Élève de test", version: Int = 1,
                        readiness: String? = nil) -> SchoolLearner {
        SchoolLearner(id: id, schoolId: school, personId: UUID(), version: version, displayName: name,
            contactEmail: nil, contactPhone: nil, archivedAt: nil, profileReadiness: readiness, profilePhotoDocumentId: nil)
    }
    static func training(id: UUID = UUID(), school: UUID = firstSchool, learner: UUID = learnerID) -> SchoolTraining {
        SchoolTraining(id: id, schoolId: school, learnerId: learner, offeringId: UUID(), version: 1,
            categoryCode: "B", status: "ACTIVE", startedOn: "2026-09-24", closedOn: nil)
    }
}
