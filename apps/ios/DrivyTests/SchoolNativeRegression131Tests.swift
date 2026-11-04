import Foundation
import Testing
@testable import Drivy

/// #131, lot R6 : non-régressions du verrou de la fiche de leçon après un refus définitif.
///
/// Le refus définitif retire la commande de la file, puis la barrière de l'écran est relue sur ce qui reste
/// (`rereadBlockingCommand`). Ces deux cas vérifient les deux bords de cette relecture : une autre commande réellement
/// bloquante garde la fiche fermée, et un coffre qui refuse le retrait ne rouvre rien.
@MainActor struct SchoolNativeRegression131Tests {
    @Test func aRefusedPermitReviewKeepsTheRemainingBlockingCommand() async throws {
        let outbox = RefusalQueueStub()
        let blocker = try pendingCommand(.completeLesson, resourceID: HubFixture.lessonID, version: 2)
        // La file reçoit une autre commande de la même leçon au moment du retrait : elle doit rester une barrière.
        outbox.afterRemoval = { _ in blocker }
        let model = workspace(server: HubServer(permitStatus: 403), outbox: outbox)
        await model.load()
        #expect(!(await model.recordPermitSeen()))
        #expect(outbox.removals.map(\.kind) == [.recordPermitCheck])
        #expect(outbox.values == [blocker])
        #expect(model.pending == blocker && model.blockingCommand == blocker)
        #expect(!model.canMutate)
    }

    @Test func aRefusedPermitReviewWhoseRemovalFailsKeepsTheLockAndTheCommand() async throws {
        let outbox = RefusalQueueStub()
        outbox.failRemovals = true
        let model = workspace(server: HubServer(permitStatus: 403), outbox: outbox)
        await model.load()
        #expect(!(await model.recordPermitSeen()))
        #expect(outbox.removals.isEmpty)
        #expect(outbox.values.count == 1 && outbox.values.first?.kind == .recordPermitCheck)
        // Le retrait a échoué : rien n'est rouvert, la demande conservée reste la barrière.
        #expect(model.pending == outbox.values.first && model.blockingCommand == outbox.values.first)
        #expect(!model.canMutate)
        #expect(model.errorMessage == SchoolConfigurationFailure.storage.localizedDescription)
    }

    private func workspace(server: HubServer, outbox: RefusalQueueStub) -> SchoolLessonReportWorkspace {
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        return SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership,
            lessonID: HubFixture.lessonID, client: client, outbox: outbox)
    }

    private func pendingCommand(_ kind: SchoolCommandKind, resourceID: UUID? = nil, routeResourceID: UUID? = nil,
                                version: Int, expectedVersion: Int? = nil) throws -> PendingSchoolCommand {
        let id = UUID()
        return PendingSchoolCommand(id: id, scope: ConfigurationFixture.scope(), kind: kind,
            resourceVersion: version, createdAt: Date(), body: try JSONEncoder().encode(["operationId": id.uuidString]),
            resourceID: resourceID, routeResourceID: routeResourceID, expectedVersion: expectedVersion)
    }
}

/// File de test à plusieurs entrées : elle reproduit la règle de `save`, permet d'injecter une commande restante au
/// moment d'un retrait réussi, et de refuser ce retrait comme un coffre inaccessible.
@MainActor
private final class RefusalQueueStub: SchoolCommandOutbox {
    var values: [PendingSchoolCommand]
    var removals: [PendingSchoolCommand] = []
    var failRemovals = false
    /// Commande ajoutée par un autre écran entre la lecture et le retrait.
    var afterRemoval: ((PendingSchoolCommand) -> PendingSchoolCommand?)?

    init(_ values: [PendingSchoolCommand] = []) { self.values = values }

    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand? { values.first }
    func pendingCommands(for scope: SchoolCommandScope) throws -> [PendingSchoolCommand] { values }

    func save(_ command: PendingSchoolCommand) throws {
        if let index = values.firstIndex(where: { $0.id == command.id }) {
            values[index] = command
            return
        }
        guard !values.contains(where: { $0.blocksQueueEntry(of: command) }) else {
            throw SchoolConfigurationFailure.pendingCommand
        }
        values.append(command)
    }

    func remove(_ command: PendingSchoolCommand) throws {
        if failRemovals { throw SchoolConfigurationFailure.storage }
        guard let index = values.firstIndex(where: { $0.id == command.id }), values[index] == command else {
            throw SchoolConfigurationFailure.storage
        }
        removals.append(command)
        values.remove(at: index)
        if let next = afterRemoval?(command) { values.append(next) }
    }
}
