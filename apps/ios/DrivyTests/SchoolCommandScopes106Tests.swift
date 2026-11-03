import Foundation
import Testing
@testable import Drivy

/// #106, tâches 1 à 3 : la barrière d'un écran est exactement la règle d'admission de la file.
///
/// Chaque site est vérifié sur des états réels de la file chiffrée : une commande en attente, puis la commande que
/// l'écran émettrait. L'écran ne doit jamais s'ouvrir pour une écriture que `save` refusera, et la réciproque est
/// vérifiée aussi pour les paires dont l'admission a été desserrée avec preuve côté API.
@MainActor struct SchoolCommandScopes106Tests {
    private let key = Data(repeating: 0x07, count: 32)
    private let scope = ConfigurationFixture.scope()

    // MARK: - Admission dans la file

    @Test func twoDistinctInvitationsCoexistAndTheSameInvitationStaysSequential() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.createInvitation))
            try store.save(command(.createInvitation))
            let target = UUID(), other = UUID()
            try store.save(command(.resendInvitation, resourceID: target, version: 2))
            try store.save(command(.resendInvitation, resourceID: other, version: 2))
            // Le renvoi et la révocation de la même invitation restent séquentiels.
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.revokeInvitation, resourceID: target, version: 2))
            }
            let reopened = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            #expect(try reopened.pendingCommands(for: scope).count == 4)
        }
    }

    /// `profiles.ts:122-161` ne vérifie que la version du dossier et de la personne ; `invitations.ts:385-415`
    /// n'en vérifie aucune et écrit une ligne d'invitation. Les deux peuvent donc coexister.
    @Test func anInvitationAndAProfileRecordDoNotShareAVersion() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.createInvitation))
            try store.save(command(.updateProfile, resourceID: UUID(),
                routeResourceID: ProfileFixture.learnerID, version: 1))
            try store.save(command(.saveOnboarding, resourceID: UUID(), version: 1))
            #expect(try store.pendingCommands(for: scope).count == 3)
        }
    }

    /// Une politique de champ avance la version de l'école (`profiles.ts:69`, `:208`, `:221`) : elle reste une
    /// barrière pour tout le reste, invitation comprise.
    @Test func aProfilePolicyStillBlocksAnInvitation() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.createProfilePolicy, version: 0, expectedVersion: 8))
            #expect(throws: SchoolConfigurationFailure.pendingCommand) { try store.save(command(.createInvitation)) }
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.updateProfile, resourceID: UUID(),
                    routeResourceID: ProfileFixture.learnerID, version: 1))
            }
        }
    }

    /// `capture-observations.ts:143-165` : la création ne vérifie aucune version et n'écrit que sa leçon, son
    /// brouillon et ses captures. Deux leçons différentes n'ont donc rien en commun.
    @Test func observationsOfDifferentLessonsDoNotShareALesson() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.createObservation, routeResourceID: UUID(), version: 0))
            try store.save(command(.createObservation, routeResourceID: UUID(), version: 0))
            // Une écriture de leçon reste une barrière pour un signalement.
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.completeLesson, resourceID: UUID(), version: 2))
            }
            #expect(try store.pendingCommands(for: scope).count == 2)
        }
    }

    @Test func aSchoolWriteStillBlocksEverything() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.updateSchool))
            #expect(throws: SchoolConfigurationFailure.pendingCommand) { try store.save(command(.createInvitation)) }
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.createObservation, routeResourceID: UUID(), version: 0))
            }
        }
    }

    @Test func theAdmissionProbeKeepsTheAccessEpochBarrier() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let invitation = try command(.createInvitation)
            try store.save(invitation)
            #expect(try store.pending(for: scope, refusing: .updateProfile,
                routeResourceID: ProfileFixture.learnerID) == nil)
            let later = ConfigurationFixture.scope(epoch: 2)
            #expect(try store.pending(for: later, refusing: .updateProfile,
                routeResourceID: ProfileFixture.learnerID) == invitation)
        }
    }

    // MARK: - Un test par site : écran ouvert <=> la file accepte

    @Test func startNowIsOfferedExactlyWhenTheQueueAcceptsIt() async throws {
        let states = try pendingStates()
        for state in states {
            try await inExperiment(state.pending) { store in
                let model = SchoolStartNowWorkspace(scope: state.screen, client: planningClient(), outbox: store)
                await model.load()
                let start = try command(.startLessonNow, scope: state.screen,
                    routeResourceID: HubFixture.trainingID, version: 0)
                #expect(model.canStart == accepts(store, start), "\(state.label)")
            }
        }
    }

    @Test func theDossierIsEditableExactlyWhenTheQueueAcceptsItsProfile() async throws {
        let states = try pendingStates()
        for state in states {
            try await inExperiment(state.pending) { store in
                let model = SchoolProfileWorkspace(scope: state.screen, roles: ["ADMIN"],
                    learnerID: ProfileFixture.learnerID, api: ProfileAPIStub(), outbox: store)
                await model.load()
                let profile = try command(.updateProfile, scope: state.screen, resourceID: ProfileFixture.profileID,
                    routeResourceID: ProfileFixture.learnerID, version: 1)
                let accepted = accepts(store, profile)
                #expect(model.canMutate == accepted, "\(state.label)")
                #expect(model.acceptsInput == accepted, "\(state.label)")
            }
        }
    }

    @Test func observationsAreOfferedExactlyWhenTheQueueAcceptsThem() async throws {
        let states = try pendingStates()
        for state in states {
            try await inExperiment(state.pending) { store in
                let model = SchoolObservationWorkspace(scope: state.screen, lessonID: HubFixture.lessonID,
                    client: observationClient(state.screen), outbox: store,
                    correctionStore: SchoolObservationCorrectionMemoryStore())
                await model.load()
                let observation = try command(.createObservation, scope: state.screen,
                    routeResourceID: HubFixture.lessonID, version: 0)
                #expect(model.canMutate == accepts(store, observation), "\(state.label)")
            }
        }
    }

    @Test func theInvitationFormIsOpenExactlyWhenTheQueueAcceptsAnInvitation() async throws {
        let states = try pendingStates()
        for state in states where state.pending.kind != .createInvitation {
            try await inExperiment(state.pending) { store in
                let api = InvitationAPIStub()
                api.items = [InvitationFixture.invitation()]
                let model = SchoolInvitationWorkspace(scope: state.screen, roles: ["ADMIN"], api: api, outbox: store)
                await model.load()
                let creation = try command(.createInvitation, scope: state.screen, version: 0)
                #expect(model.mayEdit == accepts(store, creation), "\(state.label)")
            }
        }
    }

    /// Une création dont l’issue reste inconnue ferme le formulaire : la file accepterait une autre création, mais
    /// le code de la première serait perdu. C’est la seule barrière volontairement plus stricte que la file, et elle
    /// ne peut pas produire le défaut inverse (saisir puis être refusé).
    @Test func anInvitationCreationWhoseOutcomeIsUnknownStillClosesTheForm() async throws {
        try await inExperiment(try command(.createInvitation)) { store in
            let api = InvitationAPIStub()
            let target = InvitationFixture.invitation()
            api.items = [target]
            let model = SchoolInvitationWorkspace(scope: scope, roles: ["ADMIN"], api: api, outbox: store)
            await model.load()
            #expect(!model.mayEdit && model.creationInProgressTitle == "Création en cours")
            let anotherCreation = try command(.createInvitation, version: 0)
            #expect(accepts(store, anotherCreation))
            #expect(!model.canManage(target))
            let resend = try command(.resendInvitation, resourceID: target.id, version: 2)
            #expect(accepts(store, resend))
        }
    }

    @Test func aResendIsOfferedExactlyWhenTheQueueAcceptsIt() async throws {
        let target = InvitationFixture.invitation()
        let other = InvitationFixture.invitation(id: UUID(), email: "b***@example.invalid")
        let cases = [(try command(.resendInvitation, resourceID: target.id, version: 2), "même invitation"),
                     (try command(.resendInvitation, resourceID: other.id, version: 2), "autre invitation"),
                     (try command(.createServiceProduct, version: 0), "tarif"),
                     (try command(.updateSchool), "école")]
        for (pending, label) in cases {
            try await inExperiment(pending) { store in
                let api = InvitationAPIStub()
                api.items = [target, other]
                let model = SchoolInvitationWorkspace(scope: scope, roles: ["ADMIN"], api: api, outbox: store)
                await model.load()
                let resend = try command(.resendInvitation, resourceID: target.id, version: 2)
                #expect(model.canManage(target) == accepts(store, resend), "\(label)")
            }
        }
    }

    @Test func aResendOfOneInvitationDoesNotCloseTheOthers() async throws {
        let api = InvitationAPIStub()
        let target = InvitationFixture.invitation()
        let other = InvitationFixture.invitation(id: UUID(), email: "b***@example.invalid")
        api.items = [target, other]
        let resend = try command(.resendInvitation, resourceID: target.id, version: 2)
        try await inExperiment(resend) { store in
            let model = SchoolInvitationWorkspace(scope: scope, roles: ["ADMIN"], api: api, outbox: store)
            await model.load()
            #expect(model.mayEdit && model.pending == resend)
            #expect(model.progressTitle(for: target) == "Renvoi en cours")
            // La même invitation attend sa réponse ; une autre invitation reste invitée et gérée.
            #expect(!model.canManage(target) && model.canManage(other))
        }
    }

    // MARK: - Outils

    /// États de file retenus pour les quatre écrans. `screen` est la portée de l'écran : l'état « ancienne époque »
    /// vient d'une commande d'époque 1 lue par un écran d'époque 2.
    private struct PendingState {
        let label: String
        let pending: PendingSchoolCommand
        let screen: SchoolCommandScope
    }

    private func pendingStates() throws -> [PendingState] {
        [
            PendingState(label: "invitation", pending: try command(.createInvitation), screen: scope),
            PendingState(label: "tarif", pending: try command(.createServiceProduct, version: 0), screen: scope),
            PendingState(label: "bilan d'une autre leçon",
                pending: try command(.completeLesson, resourceID: UUID(), version: 2), screen: scope),
            PendingState(label: "observation d'une autre leçon",
                pending: try command(.createObservation, routeResourceID: UUID(), version: 0), screen: scope),
            PendingState(label: "observation de cette leçon",
                pending: try command(.createObservation, routeResourceID: HubFixture.lessonID, version: 0), screen: scope),
            PendingState(label: "profil d'un autre élève",
                pending: try command(.updateProfile, resourceID: UUID(), routeResourceID: UUID(), version: 1),
                screen: scope),
            PendingState(label: "changement d'accès",
                pending: try command(.updateMember, resourceID: UUID(), version: 2), screen: scope),
            PendingState(label: "configuration de l'école", pending: try command(.updateSchool), screen: scope),
            PendingState(label: "ancienne époque", pending: try command(.createInvitation),
                screen: ConfigurationFixture.scope(epoch: 2))
        ]
    }

    private func inExperiment(_ pending: PendingSchoolCommand,
                              _ body: @MainActor (EncryptedSchoolCommandOutbox) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Scopes106-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
        try store.save(pending)
        try await body(store)
    }

    /// La commande que l'écran émettrait entre-t-elle réellement dans la file ? Même `save` que l'app.
    private func accepts(_ store: EncryptedSchoolCommandOutbox, _ candidate: PendingSchoolCommand) -> Bool {
        do { try store.save(candidate); return true } catch { return false }
    }

    private func command(_ kind: SchoolCommandKind, scope: SchoolCommandScope? = nil, resourceID: UUID? = nil,
                         routeResourceID: UUID? = nil, version: Int? = nil,
                         expectedVersion: Int? = nil) throws -> PendingSchoolCommand {
        let id = UUID()
        return PendingSchoolCommand(id: id, scope: scope ?? self.scope, kind: kind,
            resourceVersion: version ?? (kind == .createInvitation ? 0 : 1), createdAt: Date(),
            body: try JSONEncoder().encode(["operationId": id.uuidString]),
            resourceID: resourceID, routeResourceID: routeResourceID, expectedVersion: expectedVersion)
    }

    private func planningClient() -> SchoolPlanningClient {
        SchoolPlanningClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: LessonFinishServer())
    }

    private func observationClient(_ scope: SchoolCommandScope) -> SchoolObservationClient {
        SchoolObservationClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(),
            transport: ObservationReadServer())
    }

    private func inDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Scopes106-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
