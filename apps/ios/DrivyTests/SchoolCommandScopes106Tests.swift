import Foundation
import Testing
@testable import Drivy

/// #106, tâches 1 à 3 : une écriture de l’école qui ne concerne pas l’écran ne le ferme plus.
/// Portées retenues : domaine pédagogique pour un départ, même leçon pour une observation, même dossier pour
/// un profil, même invitation pour un renvoi ou une révocation. Une commande réellement en conflit bloque encore.
@MainActor struct SchoolCommandScopes106Tests {
    private let key = Data(repeating: 0x07, count: 32)
    private let scope = ConfigurationFixture.scope()

    // MARK: - File des commandes

    @Test func twoDistinctInvitationsCoexistAndTheSameInvitationStaysSequential() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.createInvitation))
            try store.save(command(.createInvitation))
            let target = UUID(), other = UUID()
            let resend = try command(.resendInvitation, resourceID: target, version: 2)
            try store.save(resend)
            try store.save(command(.resendInvitation, resourceID: other, version: 2))
            // Le renvoi et la révocation de la même invitation restent séquentiels.
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.revokeInvitation, resourceID: target, version: 2))
            }
            // La file relue accepte les deux invitations distinctes : le format 3 reste valable.
            let reopened = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            #expect(try reopened.pendingCommands(for: scope).count == 4)
        }
    }

    @Test func aSchoolWriteStillBlocksAnInvitation() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.updateSchool))
            #expect(throws: SchoolConfigurationFailure.pendingCommand) { try store.save(command(.createInvitation)) }
        }
    }

    @Test func aFilteredReadKeepsTheAccessEpochBarrier() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let invitation = try command(.createInvitation)
            try store.save(invitation)
            #expect(try store.pending(for: scope, blockedBy: { _ in false }) == nil)
            #expect(try store.pending(for: scope, blockedBy: { $0.kind.isInvitation }) == invitation)
            // Une commande d’une autre époque d’accès reste une barrière, même quand elle ne nomme aucun conflit.
            let later = SchoolCommandScope(personID: scope.personID, schoolID: scope.schoolID,
                membershipID: scope.membershipID, accessEpoch: 2, apiBaseURL: scope.apiBaseURL)
            #expect(try store.pending(for: later, blockedBy: { _ in false }) == invitation)
        }
    }

    // MARK: - Départ (SchoolStartNowWorkspace)

    @Test func startNowOnlyWaitsForATeachingWrite() async throws {
        let unblocked = SchoolStartNowWorkspace(scope: scope, client: planningClient(),
            outbox: CommandQueueTestStub(try command(.createInvitation)))
        await unblocked.load()
        #expect(unblocked.canStart && unblocked.pending == nil && unblocked.blockingCommand == nil)

        let report = try command(.completeLesson, resourceID: HubFixture.lessonID, version: 2)
        let blocked = SchoolStartNowWorkspace(scope: scope, client: planningClient(), outbox: CommandQueueTestStub(report))
        await blocked.load()
        #expect(!blocked.canStart && blocked.blockingCommand == report)
    }

    // MARK: - Profil (SchoolProfileWorkspace)

    @Test func theDossierWaitsOnlyForItsOwnProfileWrite() async throws {
        let api = ProfileAPIStub()
        let unrelated = [try command(.createInvitation), try command(.createServiceProduct, version: 0),
            try command(.updateProfile, resourceID: UUID(), routeResourceID: UUID(), version: 1)]
        for pending in unrelated {
            let model = SchoolProfileWorkspace(scope: scope, roles: ["ADMIN"], learnerID: ProfileFixture.learnerID,
                api: api, outbox: CommandQueueTestStub(pending))
            await model.load()
            #expect(model.canMutate && model.acceptsInput && model.pending == nil)
        }

        let own = try ProfileFixture.command()
        let blocked = SchoolProfileWorkspace(scope: scope, roles: ["ADMIN"], learnerID: ProfileFixture.learnerID,
            api: api, outbox: CommandQueueTestStub(own))
        await blocked.load()
        #expect(!blocked.canMutate && !blocked.acceptsInput && blocked.pending == own)

        // `updateMember` avance l’époque d’accès : elle bloque le dossier le temps d’être résolue.
        let member = try command(.updateMember, resourceID: UUID(), version: 2)
        let epoch = SchoolProfileWorkspace(scope: scope, roles: ["ADMIN"], learnerID: ProfileFixture.learnerID,
            api: api, outbox: CommandQueueTestStub(member))
        await epoch.load()
        #expect(!epoch.canMutate && epoch.pending == member)
    }

    @Test func profilePolicyManagementKeepsOnlyItsOwnVersion() async throws {
        let api = ProfileAPIStub()
        let policy = PendingSchoolCommand(id: UUID(), scope: scope, kind: .createProfilePolicy, resourceVersion: 0,
            createdAt: Date(), body: try JSONEncoder().encode(["operationId": UUID().uuidString]), expectedVersion: 8)
        let blocked = SchoolProfileWorkspace(scope: scope, roles: ["ADMIN"], api: api, outbox: CommandQueueTestStub(policy))
        await blocked.load()
        #expect(!blocked.canMutate && blocked.pending == policy)

        let open = SchoolProfileWorkspace(scope: scope, roles: ["ADMIN"], api: api,
            outbox: CommandQueueTestStub(try command(.createInvitation)))
        await open.load()
        #expect(open.canMutate && open.pending == nil)
    }

    // MARK: - Observations (SchoolObservationWorkspace)

    @Test func observationsOnlyWaitForTheirOwnLesson() async throws {
        let unrelated = [try command(.createInvitation),
            try command(.createObservation, routeResourceID: UUID(), version: 0)]
        for pending in unrelated {
            let model = SchoolObservationWorkspace(scope: scope, lessonID: HubFixture.lessonID, client: observationClient(),
                outbox: CommandQueueTestStub(pending), correctionStore: SchoolObservationCorrectionMemoryStore())
            await model.load()
            #expect(model.loaded && model.canMutate && model.canAdd && model.pending == nil)
        }

        let report = try command(.completeLesson, resourceID: HubFixture.lessonID, version: 2)
        let blocked = SchoolObservationWorkspace(scope: scope, lessonID: HubFixture.lessonID, client: observationClient(),
            outbox: CommandQueueTestStub(report), correctionStore: SchoolObservationCorrectionMemoryStore())
        await blocked.load()
        #expect(!blocked.canMutate && blocked.pending == report && blocked.pendingAwaitsReview)
    }

    // MARK: - Invitations (SchoolInvitationWorkspace)

    @Test func aResendOfOneInvitationDoesNotCloseTheOthers() async throws {
        let api = InvitationAPIStub()
        let target = InvitationFixture.invitation()
        let other = InvitationFixture.invitation(id: UUID(), email: "b***@example.invalid")
        api.items = [target, other]
        let resend = try command(.resendInvitation, resourceID: target.id, version: 2)
        let model = SchoolInvitationWorkspace(scope: scope, roles: ["ADMIN"], api: api, outbox: CommandQueueTestStub(resend))
        await model.load()
        #expect(model.mayEdit && model.pending == resend)
        #expect(model.progressTitle(for: target) == "Renvoi en cours")
        // La même invitation attend sa réponse ; une autre invitation reste invitée et gérée.
        #expect(!model.canManage(target) && model.canManage(other))
    }

    @Test func anInvitationCreationWhoseOutcomeIsUnknownStillClosesTheForm() async throws {
        let model = SchoolInvitationWorkspace(scope: scope, roles: ["ADMIN"], api: InvitationAPIStub(),
            outbox: CommandQueueTestStub(try command(.createInvitation)))
        await model.load()
        #expect(!model.mayEdit && model.creationInProgressTitle == "Création en cours")
    }

    // MARK: - Outils

    /// File de plusieurs commandes, comme le coffre réel ; la clé de test n’est pas utilisée ici.
    @MainActor
    private final class CommandQueueTestStub: SchoolCommandOutbox {
        private var commands: [PendingSchoolCommand]
        init(_ commands: PendingSchoolCommand...) { self.commands = commands }
        func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand? {
            commands.first { $0.scope.belongsToWorkspace(scope) }
        }
        func pendingCommands(for scope: SchoolCommandScope) throws -> [PendingSchoolCommand] {
            commands.filter { $0.scope.belongsToWorkspace(scope) }
        }
        func save(_ command: PendingSchoolCommand) throws {
            if !commands.contains(where: { $0.id == command.id }) { commands.append(command) }
        }
        func remove(_ command: PendingSchoolCommand) throws {
            commands.removeAll { $0.id == command.id }
        }
    }

    private func command(_ kind: SchoolCommandKind, resourceID: UUID? = nil, routeResourceID: UUID? = nil,
                         version: Int? = nil) throws -> PendingSchoolCommand {
        let id = UUID()
        return PendingSchoolCommand(id: id, scope: scope, kind: kind,
            resourceVersion: version ?? (kind == .createInvitation ? 0 : 1), createdAt: Date(),
            body: try JSONEncoder().encode(["operationId": id.uuidString]),
            resourceID: resourceID, routeResourceID: routeResourceID)
    }

    private func planningClient() -> SchoolPlanningClient {
        SchoolPlanningClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: LessonFinishServer())
    }

    private func observationClient() -> SchoolObservationClient {
        SchoolObservationClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: ObservationReadServer())
    }

    private func inDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Scopes106-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
