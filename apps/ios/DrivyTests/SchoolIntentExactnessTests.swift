import Foundation
import Testing
@testable import Drivy

/// Lot E de l'audit de confidentialité : intentions natives exactes et durables.
/// #438 : remplacement et migration d'époque en une seule écriture du coffre chiffré réel.
/// #431 : une édition de cours incertaine se rejoue à l'identique, ou bloque explicitement.
@MainActor struct SchoolIntentExactnessTests {
    private let schoolID = CourseReplayFixture.school
    private let seriesID = CourseReplayFixture.series
    private let personID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
    private let membershipID = CourseReplayFixture.instructor
    private let key = Data(repeating: 5, count: 32)

    private func scope(epoch: Int = 1) -> SchoolCommandScope {
        SchoolCommandScope(personID: personID, schoolID: schoolID, membershipID: membershipID, accessEpoch: epoch,
            apiBaseURL: "https://school.example.test")
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("intent-exactness-\(UUID().uuidString)", isDirectory: true)
    }

    private func intentCommand(_ operation: UUID = UUID(), series: UUID? = nil, epoch: Int = 1, title: String = "x") throws -> PendingSchoolCommand {
        var form = SchoolCourseForm(); form.title = title
        return try SchoolCourseEditorRecord(operationId: operation, intent: .draft, closing: false, key: "draft|k|\(title)", seriesId: series,
            form: form, newTypeTitle: "", newTypeDescription: "").command(scope: scope(epoch: epoch), createdAt: Date())
    }

    private func ids(_ store: EncryptedSchoolCourseIntentStore, epoch: Int = 1) throws -> Set<UUID> {
        Set(try store.commands(scope: scope(epoch: epoch)).map(\.id))
    }

    // MARK: #438 — une seule écriture atomique, avec le magasin durable réel

    private final class WriteCounter { var before = 0, after = 0 }

    @Test func aReplacementThatFailsBeforeTheWriteKeepsTheOldIntentAndTheOthers() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let old = try intentCommand(series: UUID(), title: "ancien"), other = try intentCommand(series: UUID(), title: "autre")
        try store.replace(nil, with: old); try store.replace(nil, with: other)
        let new = try intentCommand(series: old.routeResourceID, title: "nouveau")

        store.outbox.faultBeforeFileWrite = { throw URLError(.cannotWriteToFile) }
        #expect(throws: (any Error).self) { try store.replace(old, with: new) }

        // Une nouvelle instance relit le fichier : l'ancien est intact, l'autre aussi, le nouveau est absent.
        let reopened = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        #expect(try ids(reopened) == [old.id, other.id])
    }

    @Test func aReplacementThatFailsAfterTheWriteLeavesTheNewIntentNeverNone() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let old = try intentCommand(series: UUID(), title: "ancien"), other = try intentCommand(series: UUID(), title: "autre")
        try store.replace(nil, with: old); try store.replace(nil, with: other)
        let new = try intentCommand(series: old.routeResourceID, title: "nouveau")

        store.outbox.faultAfterFileWrite = { throw URLError(.cannotWriteToFile) }
        #expect(throws: (any Error).self) { try store.replace(old, with: new) }

        // Le fichier est déjà écrit : le nouveau est là, l'ancien l'a quitté, l'autre est préservé. Jamais aucun des deux.
        let reopened = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        #expect(try ids(reopened) == [new.id, other.id])
    }

    @Test func aReplacementIsOneSingleWriteOfTheVault() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let old = try intentCommand(series: UUID(), title: "ancien")
        try store.replace(nil, with: old)
        let counter = WriteCounter()
        store.outbox.faultBeforeFileWrite = { counter.before += 1 }
        store.outbox.faultAfterFileWrite = { counter.after += 1 }
        try store.replace(old, with: try intentCommand(series: old.routeResourceID, title: "nouveau"))
        #expect(counter.before == 1 && counter.after == 1)
    }

    @Test func anEpochMigrationThatFailsLeavesEveryIntentOnceAndNoneLost() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let first = try intentCommand(series: UUID(), title: "un"), second = try intentCommand(series: UUID(), title: "deux")
        try store.replace(nil, with: first); try store.replace(nil, with: second)

        // Panne sur la première écriture de migration : rien n'a bougé, les deux restent à l'époque 1.
        store.outbox.faultBeforeFileWrite = { throw URLError(.cannotWriteToFile) }
        #expect(throws: (any Error).self) { _ = try store.commands(scope: scope(epoch: 2)) }
        let untouched = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        #expect(try untouched.commands(scope: scope(epoch: 1)).map(\.scope.accessEpoch) == [1, 1])

        // Panne à la seconde seulement : la première est migrée en entier, la seconde reste entière à l'ancienne époque.
        let counter = WriteCounter()
        store.outbox.faultBeforeFileWrite = {
            counter.before += 1
            if counter.before == 2 { throw URLError(.cannotWriteToFile) }
        }
        #expect(throws: (any Error).self) { _ = try store.commands(scope: scope(epoch: 2)) }
        let partial = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let kept = try partial.commands(scope: scope(epoch: 2))
        #expect(Set(kept.map(\.id)) == [first.id, second.id] && kept.count == 2)

        // Sans panne, la migration se termine : mêmes identités d'opération, toutes à l'époque 2.
        let finished = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let moved = try finished.commands(scope: scope(epoch: 2))
        #expect(Set(moved.map(\.id)) == [first.id, second.id] && moved.allSatisfy { $0.scope.accessEpoch == 2 })
    }

    @Test func replacingAnIntentNotInTheVaultFailsAndChangesNothing() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let kept = try intentCommand(series: UUID(), title: "gardé")
        try store.replace(nil, with: kept)
        let ghost = try intentCommand(series: UUID(), title: "fantôme")
        #expect(throws: (any Error).self) { try store.replace(ghost, with: try intentCommand(series: UUID(), title: "nouveau")) }
        #expect(try ids(EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)) == [kept.id])
    }

    @Test func aStaleReplacementIsRefusedByBothStoresButAnExactNewIntentStaysIdempotent() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let durable = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let memory = SchoolCourseIntentMemoryStore()
        let stores: [any SchoolCourseIntentStoring] = [durable, memory]
        for store in stores {
            let kept = try intentCommand(series: UUID(), title: "gardé")
            try store.replace(nil, with: kept)
            let old = try intentCommand(series: UUID(), title: "ancien"), new = try intentCommand(series: UUID(), title: "nouveau")
            // Ni l'ancienne ni la nouvelle : substitution périmée, rien n'est ajouté ni retiré.
            #expect(throws: (any Error).self) { try store.replace(old, with: new) }
            #expect(Set(try store.commands(scope: scope()).map(\.id)) == [kept.id])
            // Faute après écriture : la nouvelle, exacte, est déjà là et l'ancienne en est sortie. Rejouer réussit sans rien changer.
            try store.replace(nil, with: new)
            try store.replace(old, with: new)
            #expect(Set(try store.commands(scope: scope()).map(\.id)) == [kept.id, new.id])
            // Une nouvelle de même identité mais d'un autre contenu n'est pas « la même » : refusée, rien ne bouge.
            let other = try intentCommand(new.id, series: new.routeResourceID, title: "autre contenu")
            #expect(throws: (any Error).self) { try store.replace(old, with: other) }
            #expect(Set(try store.commands(scope: scope()).map(\.id)) == [kept.id, new.id])
        }
        #expect(try ids(EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)).count == 2)
    }

    // MARK: #431 — rejeu exact d'une édition de cours incertaine

    private let secondSession = "Titre modifié"

    private func series(_ version: Int, title: String, status: String = "DRAFT") throws -> SchoolCourseSeries {
        try JSONDecoder().decode(SchoolCourseSeries.self, from: CourseReplayFixture.seriesJSON(version: version, title: title, status: status))
    }

    private func editor(_ server: CourseReplayServer, store: any SchoolCourseIntentStoring, series: SchoolCourseSeries) -> SchoolCourseEditorWorkspace {
        SchoolCourseEditorWorkspace(schoolID: schoolID, membershipID: membershipID, timeZone: "Europe/Zurich",
            client: SchoolCourseClient(baseURL: URL(string: "https://school.example.test")!, tokenSource: HubToken(), transport: server),
            catalogue: nil, series: series, persistence: SchoolCourseIntentPersistence(store: store, scope: scope()))
    }

    @Test func aLostEditIsReplayedWithItsExactEnvelopeEvenWhenTheCourseMovedOn() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let server = CourseReplayServer(version: 3, title: "Titre")
        let first = editor(server, store: store, series: try series(3, title: "Titre"))
        await first.load()
        first.form.title = secondSession
        await server.loseNextWrite(applying: true)
        #expect(await first.saveDraft() == nil)
        #expect(first.hasUnconfirmedOperation)
        let sent = try #require(await server.writes.first)
        #expect(sent.ifMatch == "\"3\"")

        // L'école a appliqué l'édition (version 4) ; l'app redémarre et relit la série à la version 4.
        let reopened = editor(server, store: EncryptedSchoolCourseIntentStore(directory: folder, keyData: key),
            series: try series(4, title: secondSession))
        await reopened.load()
        #expect(reopened.hasUnconfirmedOperation && !reopened.replayBlocked && reopened.form.title == secondSession)
        await reopened.retryUnconfirmed()

        let replay = try #require(await server.writes.last)
        #expect(await server.writes.count == 2)
        // Identité canonique de l'API (version, opération, champs), pas égalité d'octets : le client réencode à chaque appel.
        #expect(replay.key == sent.key && replay.ifMatch == "\"3\"" && replay.identity == sent.identity)
        #expect((replay.fields["operationId"] as? String)?.lowercased() == sent.key?.lowercased())
        #expect(replay.fields["title"] as? String == secondSession)
        // Le reçu déjà appliqué est rapproché : aucune seconde mutation, la saisie est acquittée.
        #expect(await server.mutations == 1)
        #expect(!reopened.hasUnconfirmedOperation && reopened.series?.version == 4)
        #expect(try store.commands(scope: scope(), seriesID: seriesID).isEmpty)
    }

    @Test func aReplayRefusedForVersionKeepsTheTypedInputAndBlocksEveryResend() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let server = CourseReplayServer(version: 3, title: "Titre")
        let first = editor(server, store: store, series: try series(3, title: "Titre"))
        await first.load()
        first.form.title = secondSession
        await server.loseNextWrite(applying: false)
        #expect(await first.saveDraft() == nil)

        // Quelqu'un d'autre a modifié le cours entre-temps : version 4, titre différent.
        await server.otherEdit(title: "Autre titre")
        let reopened = editor(server, store: EncryptedSchoolCourseIntentStore(directory: folder, keyData: key),
            series: try series(4, title: "Autre titre"))
        await reopened.load()
        await reopened.retryUnconfirmed()

        #expect(await server.mutations == 1)   // la modification de l'autre personne, pas la nôtre
        let attempt = try #require(await server.writes.last)
        #expect(attempt.ifMatch == "\"3\"")     // jamais la version 4 relue
        #expect(reopened.replayBlocked && reopened.errorMessage == SchoolCourseEditorWorkspace.staleReplayMessage)
        #expect(reopened.hasUnconfirmedOperation && reopened.form.title == secondSession)
        #expect(!reopened.canSave && !reopened.canPublish)
        #expect(try store.commands(scope: scope(), seriesID: seriesID).count == 1)

        // Ni « Réessayer » ni « Enregistrer » ne repartent sur la version courante.
        let writes = await server.writes.count
        await reopened.retryUnconfirmed()
        #expect(await reopened.saveDraft() == nil)
        await reopened.publish()
        #expect(await server.writes.count == writes)

        // Abandonner relit le cours à jour : la saisie est jetée explicitement, rien n'est écrasé en silence.
        await reopened.abandonUnconfirmed()
        #expect(!reopened.replayBlocked && !reopened.hasUnconfirmedOperation)
        #expect(reopened.form.title == "Autre titre" && reopened.series?.version == 4)
        #expect(try store.commands(scope: scope(), seriesID: seriesID).isEmpty)
        #expect(await server.mutations == 1)
    }

    @Test func anOldIncompleteRecordBlocksTheReplayInsteadOfAdoptingTheCurrentVersion() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let server = CourseReplayServer(version: 4, title: "Autre titre")
        let current = try series(4, title: "Autre titre")
        var form = SchoolCourseForm(series: current); form.title = secondSession
        // Archive d'avant #431 : ni la version envoyée, ni le corps.
        let legacy = SchoolCourseEditorRecord(operationId: UUID(), intent: .draft, closing: true, key: "draft|old", seriesId: seriesID,
            form: form, newTypeTitle: "", newTypeDescription: "")
        #expect(!legacy.canReplayExactly)
        try store.replace(nil, with: legacy.command(scope: scope(), createdAt: Date()))

        let model = editor(server, store: store, series: current)
        await model.load()
        #expect(model.hasUnconfirmedOperation && model.replayBlocked)
        #expect(model.errorMessage == SchoolCourseEditorWorkspace.incompleteReplayMessage)
        #expect(model.form.title == secondSession)

        await model.retryUnconfirmed()
        #expect(await model.saveDraft() == nil)
        await model.publish()
        #expect(await server.writes.isEmpty)
        #expect(try store.commands(scope: scope(), seriesID: seriesID).count == 1)
    }

    @Test func aLostPublicationIsReplayedWithItsOriginalVersion() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let server = CourseReplayServer(version: 3, title: "Titre")
        let first = editor(server, store: store, series: try series(3, title: "Titre"))
        await first.load()
        await server.loseNextWrite(applying: true)
        await first.publish()
        #expect(first.hasUnconfirmedOperation)
        let sent = try #require(await server.writes.last)
        #expect(sent.path.hasSuffix("/publish") && sent.ifMatch == "\"3\"")

        let reopened = editor(server, store: EncryptedSchoolCourseIntentStore(directory: folder, keyData: key),
            series: try series(4, title: "Titre", status: "PUBLISHED"))
        await reopened.load()
        await reopened.retryUnconfirmed()
        let replay = try #require(await server.writes.last)
        #expect(await server.writes.count == 2 && replay.key == sent.key && replay.ifMatch == "\"3\"")
        #expect(await server.mutations == 1)
        #expect(!reopened.hasUnconfirmedOperation && reopened.finished?.version == 4)
        #expect(try store.commands(scope: scope(), seriesID: seriesID).isEmpty)
    }

    // MARK: #431 — blocage, comparaison, puis décision explicite

    /// Session 1 perd sa réponse sans que l'école applique l'édition ; quelqu'un d'autre modifie le cours (version 4) ;
    /// session 2 reprend la demande, qui reste bloquée. Rend le coffre de la session 2 et son éditeur.
    private func blockedEditor(_ server: CourseReplayServer, folder: URL, other: PendingSchoolCommand? = nil)
        async throws -> (editor: SchoolCourseEditorWorkspace, store: EncryptedSchoolCourseIntentStore, heldOperation: String) {
        let store = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let first = editor(server, store: store, series: try series(3, title: "Titre"))
        await first.load()
        first.form.title = secondSession
        await server.loseNextWrite(applying: false)
        #expect(await first.saveDraft() == nil)
        let held = try #require(await server.writes.first?.key)
        if let other { try store.replace(nil, with: other) }
        await server.otherEdit(title: "Autre titre")
        let reopenedStore = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let reopened = editor(server, store: reopenedStore, series: try series(4, title: "Autre titre"))
        await reopened.load()
        await reopened.retryUnconfirmed()
        #expect(reopened.replayBlocked && reopened.hasUnconfirmedOperation && reopened.form.title == secondSession)
        return (reopened, reopenedStore, held)
    }

    @Test func aBlockedEditIsComparedThenKeptOnTheReadVersionAsANewOperation() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let server = CourseReplayServer(version: 3, title: "Titre")
        let (reopened, store, held) = try await blockedEditor(server, folder: folder)
        #expect(await server.mutations == 1)

        // Comparer ne renvoie rien : la saisie reste figée et la demande bloquée reste dans le coffre.
        let writes = await server.writes.count
        await reopened.compareHeldInput()
        let comparison = try #require(reopened.reconciliation)
        #expect(comparison.differences.map(\.label) == ["Titre"] && comparison.canKeepMine)
        #expect(comparison.differences.first?.mine == secondSession && comparison.differences.first?.current == "Autre titre")
        #expect(await server.writes.count == writes && reopened.replayBlocked && reopened.form.title == secondSession)
        #expect(try ids(store).count == 1)

        // Décision explicite : une nouvelle opération sur la version relue (4), jamais la demande bloquée rejouée en 4.
        await reopened.keepMyInputOnCurrentVersion()
        let write = try #require(await server.writes.last)
        #expect(await server.writes.count == writes + 1)
        #expect(write.ifMatch == "\"4\"" && write.key != held && write.fields["title"] as? String == secondSession)
        #expect((write.fields["operationId"] as? String)?.lowercased() == write.key?.lowercased())
        #expect(await server.mutations == 2)
        #expect(!reopened.hasUnconfirmedOperation && !reopened.replayBlocked && reopened.reconciliation == nil)
        #expect(reopened.series?.version == 5 && reopened.series?.title == secondSession && reopened.errorMessage == nil)
        #expect(try ids(store).isEmpty)
    }

    @Test func keepingMineIsRefusedWithoutAComparisonAndNeverAdvancesTheVersionOnItsOwn() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let server = CourseReplayServer(version: 3, title: "Titre")
        let (reopened, store, _) = try await blockedEditor(server, folder: folder)
        let writes = await server.writes.count
        await reopened.keepMyInputOnCurrentVersion()           // pas de comparaison, pas de décision
        await reopened.retryUnconfirmed(); await reopened.publish(); _ = await reopened.saveDraft()
        #expect(await server.writes.count == writes && reopened.replayBlocked && reopened.reconciliation == nil)
        #expect(try ids(store).count == 1)
    }

    @Test func anOldArchiveWithoutBaseIsComparedWithoutInventingItsEditsThenKeptOnPurpose() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let server = CourseReplayServer(version: 4, title: "Autre titre")
        let current = try series(4, title: "Autre titre")
        var form = SchoolCourseForm(series: current); form.title = secondSession; form.location = "Salle B"
        let legacy = SchoolCourseEditorRecord(operationId: UUID(), intent: .draft, closing: true, key: "draft|old", seriesId: seriesID,
            form: form, newTypeTitle: "", newTypeDescription: "")
        try store.replace(nil, with: legacy.command(scope: scope(), createdAt: Date()))
        let model = editor(server, store: store, series: current)
        await model.load()
        #expect(model.replayBlocked && model.errorMessage == SchoolCourseEditorWorkspace.incompleteReplayMessage)

        await model.compareHeldInput()
        let comparison = try #require(model.reconciliation)
        // Deux états comparés, rien de plus : aucune « base » d'avant la saisie n'est reconstituée.
        #expect(Set(comparison.differences.map(\.label)) == ["Titre", "Lieu"] && comparison.canKeepMine)
        #expect(await server.writes.isEmpty && model.replayBlocked && model.form.title == secondSession)
        #expect(try ids(store) == [legacy.operationId])

        await model.keepMyInputOnCurrentVersion()
        let write = try #require(await server.writes.last)
        #expect(await server.writes.count == 1 && write.ifMatch == "\"4\"" && write.key?.lowercased() != legacy.operationId.uuidString.lowercased())
        #expect(write.fields["title"] as? String == secondSession && write.fields["location"] as? String == "Salle B")
        #expect(!model.hasUnconfirmedOperation && !model.replayBlocked && model.series?.version == 5)
        #expect(try ids(store).isEmpty)
    }

    @Test func abandoningABlockedEditStaysDistinctAndDiscardsOnlyAfterTheComparison() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let server = CourseReplayServer(version: 3, title: "Titre")
        let (reopened, store, _) = try await blockedEditor(server, folder: folder)
        await reopened.compareHeldInput()
        #expect(reopened.reconciliation != nil)
        await reopened.abandonUnconfirmed()
        #expect(!reopened.hasUnconfirmedOperation && reopened.reconciliation == nil && reopened.form.title == "Autre titre")
        #expect(reopened.errorMessage?.hasPrefix("Demande abandonnée") == true)
        #expect(await server.mutations == 1)
        #expect(try ids(store).isEmpty)
    }

    @Test func theFormComparisonNamesOnlyTheFieldsThatDiffer() throws {
        let current = SchoolCourseForm(series: try series(4, title: "Titre"))
        #expect(current.differences(from: current, catalogue: nil, timeZone: "Europe/Zurich").isEmpty)
        var mine = current; mine.capacity = 30; mine.description = "  nouvelle  "; mine.minParticipants = 2
        let labels = mine.differences(from: current, catalogue: nil, timeZone: "Europe/Zurich").map(\.label)
        #expect(labels == ["Description", "Capacité", "Minimum"])
        mine.occurrences[0].endsAt = mine.occurrences[0].endsAt.addingTimeInterval(1800)
        #expect(mine.differences(from: current, catalogue: nil, timeZone: "Europe/Zurich").map(\.label).last == "Séances")
    }

    // MARK: Abandon bloqué par le coffre — rien n'est annoncé, rien ne part

    @Test func anAbandonThatTheVaultCannotRecordKeepsTheReferenceTheInputAndEveryOtherIntent() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let server = CourseReplayServer(version: 3, title: "Titre")
        let bystander = try intentCommand(series: UUID(), title: "autre geste")
        let (reopened, store, _) = try await blockedEditor(server, folder: folder, other: bystander)
        let before = try ids(store)
        #expect(before.count == 2 && before.contains(bystander.id))

        let writes = await server.writes.count
        store.outbox.faultBeforeFileWrite = { throw URLError(.cannotWriteToFile) }
        await reopened.abandonUnconfirmed()

        #expect(reopened.hasUnconfirmedOperation && reopened.replayBlocked && reopened.form.title == secondSession)
        #expect(reopened.errorMessage == SchoolCourseEditorWorkspace.removalFailedMessage)
        #expect(reopened.errorMessage?.contains("abandonnée") == false)
        #expect(await server.writes.count == writes)
        // Ce que le fichier garde : la demande bloquée ET l'autre intention, pas un octet de moins.
        #expect(try ids(EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)) == before)

        // La même opération reste reprenable : une fois le coffre rétabli, l'abandon aboutit et ne retire que la sienne.
        store.outbox.faultBeforeFileWrite = nil
        await reopened.abandonUnconfirmed()
        #expect(!reopened.hasUnconfirmedOperation && reopened.errorMessage?.hasPrefix("Demande abandonnée") == true)
        #expect(try ids(store) == [bystander.id])
    }

    @Test func anUnblockedAbandonThatTheVaultCannotRecordIsNotAnnouncedEither() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let server = CourseReplayServer(version: 3, title: "Titre")
        let model = editor(server, store: store, series: try series(3, title: "Titre"))
        await model.load()
        model.form.title = secondSession
        await server.loseNextWrite(applying: false)
        #expect(await model.saveDraft() == nil && model.hasUnconfirmedOperation && !model.replayBlocked)

        store.outbox.faultBeforeFileWrite = { throw URLError(.cannotWriteToFile) }
        await model.abandonUnconfirmed()
        #expect(model.hasUnconfirmedOperation && model.errorMessage == SchoolCourseEditorWorkspace.removalFailedMessage)
        #expect(try ids(EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)).count == 1)
        // Pas de nouvel envoi non plus : la demande reste à reprendre.
        #expect(await server.writes.count == 1)
    }

    @Test func aServerReceiptIsNotALocalRemoval() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)
        let server = CourseReplayServer(version: 3, title: "Titre")
        let model = editor(server, store: store, series: try series(3, title: "Titre"))
        await model.load()
        model.form.title = secondSession
        let counter = WriteCounter()
        // Première écriture (conserver la demande) : réussie ; seconde (la retirer) : refusée.
        store.outbox.faultBeforeFileWrite = { counter.before += 1; if counter.before > 1 { throw URLError(.cannotWriteToFile) } }
        #expect(await model.saveDraft() == nil)

        #expect(await server.mutations == 1)                       // l'école a bien enregistré
        #expect(model.finished == nil && model.hasUnconfirmedOperation)   // mais la feuille ne se ferme pas
        #expect(model.errorMessage == SchoolCourseEditorWorkspace.removalFailedMessage)
        #expect(try ids(EncryptedSchoolCourseIntentStore(directory: folder, keyData: key)).count == 1)

        // Coffre rétabli : « Réessayer » rejoue la même enveloppe, l'école rend son reçu, la demande part enfin.
        store.outbox.faultBeforeFileWrite = nil
        await model.retryUnconfirmed()
        #expect(await server.mutations == 1 && !model.hasUnconfirmedOperation && model.finished != nil)
        #expect(try ids(store).isEmpty)
    }

    @Test func aRecordKnowsWhetherItCanBeReplayedExactly() throws {
        let body = SchoolCourseSeriesBody(operationId: UUID(), typeId: CourseReplayFixture.type, title: "t", description: "", location: "",
            conditions: "", teachingLanguage: nil, responsibleMembershipId: membershipID, capacity: 5, minParticipants: nil,
            timeZone: "Europe/Zurich", occurrences: [])
        func record(_ intent: SchoolCourseEditorRecord.Intent, series: UUID?, version: Int?, body: SchoolCourseSeriesBody?, operation: UUID) -> SchoolCourseEditorRecord {
            SchoolCourseEditorRecord(operationId: operation, intent: intent, closing: false, key: "k", seriesId: series, form: SchoolCourseForm(),
                newTypeTitle: "", newTypeDescription: "", baseVersion: version, seriesBody: body)
        }
        #expect(record(.type, series: nil, version: nil, body: nil, operation: UUID()).canReplayExactly)
        #expect(record(.draft, series: nil, version: nil, body: nil, operation: UUID()).canReplayExactly)   // création
        #expect(record(.draft, series: seriesID, version: 3, body: body, operation: body.operationId).canReplayExactly)
        #expect(!record(.draft, series: seriesID, version: nil, body: body, operation: body.operationId).canReplayExactly)
        #expect(!record(.draft, series: seriesID, version: 3, body: nil, operation: body.operationId).canReplayExactly)
        #expect(!record(.draft, series: seriesID, version: 3, body: body, operation: UUID()).canReplayExactly)   // corps d'une autre opération
        #expect(record(.publication, series: seriesID, version: 3, body: nil, operation: UUID()).canReplayExactly)
        #expect(!record(.publication, series: seriesID, version: nil, body: nil, operation: UUID()).canReplayExactly)
        // L'enveloppe survit à l'aller-retour du coffre.
        let kept = record(.draft, series: seriesID, version: 3, body: body, operation: body.operationId)
        #expect(try JSONDecoder().decode(SchoolCourseEditorRecord.self, from: JSONEncoder().encode(kept)) == kept)
    }
}

private enum CourseReplayFixture {
    static let school = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let series = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static let type = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    static let instructor = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

    static func seriesJSON(version: Int, title: String, status: String) -> Data {
        let published = status == "PUBLISHED" ? "\"2030-01-01T08:00:00.000Z\"" : "null"
        return Data("""
        {"id":"\(series.uuidString.lowercased())","schoolId":"\(school.uuidString.lowercased())","version":\(version),"status":"\(status)",
         "typeId":"\(type.uuidString.lowercased())","typeTitle":"Sensibilisation","title":"\(title)",
         "description":"","location":"","conditions":"","teachingLanguage":null,
         "responsibleMembershipId":"\(instructor.uuidString.lowercased())","responsibleDisplayName":"Camille Exemple",
         "capacity":12,"seatsTaken":0,"remainingSeats":12,"minParticipants":null,"policyVersion":1,"selfCancelHours":24,
         "selfCancellationDeadline":"2030-03-03T17:00:00.000Z","firstStartsAt":"2030-03-04T17:00:00.000Z","lastEndsAt":"2030-03-04T20:00:00.000Z",
         "totalMinutes":180,"publishedAt":\(published),"canManage":true,
         "occurrences":[{"id":"55555555-5555-4555-8555-555555555555","position":1,"startsAt":"2030-03-04T17:00:00.000Z",
           "endsAt":"2030-03-04T20:00:00.000Z","timeZone":"Europe/Zurich","instructorMembershipId":"\(instructor.uuidString.lowercased())",
           "instructorDisplayName":"Camille Exemple","attendanceRequired":true}]}
        """.utf8)
    }

    static let catalogueJSON = Data("""
        {"schoolId":"\(school.uuidString.lowercased())","canManage":true,
         "types":[{"id":"\(type.uuidString.lowercased())","schoolId":"\(school.uuidString.lowercased())","stableKey":null,"title":"Sensibilisation",
           "description":"","version":1,"predefined":false}],
         "policy":{"version":1,"selfCancelHours":24,"offerResponseMinutes":null},
         "instructors":[{"membershipId":"\(instructor.uuidString.lowercased())","displayName":"Camille Exemple"}]}
        """.utf8)
}

/// École simulée : elle applique une écriture une seule fois par clé d'opération, rejoue sa réponse avant tout contrôle de
/// version (comme `apps/api`, où `schoolCommand` compare le reçu avant `work` et `checkVersion`), et refuse 412 VERSION_CONFLICT
/// une version périmée. Le reçu se décide sur l'identité canonique de l'API (`commands.ts`, `canonical({body, expectedVersion})`) :
/// clés triées, `expectedVersion` tiré de `If-Match`. Un octet de plus ou une clé dans un autre ordre ne change pas l'identité ;
/// une autre version, une autre opération ou un autre champ la change, et la même clé avec une autre identité est un 409.
private actor CourseReplayServer: SchoolHTTPTransport {
    struct Write: Equatable {
        let method: String, path: String, key: String?, ifMatch: String?, body: Data

        /// `canonical({ body, expectedVersion })` : jamais la comparaison brute des octets.
        var identity: String {
            let expected = ifMatch.flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "\""))) }
            let object: [String: Any] = ["body": (try? JSONSerialization.jsonObject(with: body)) ?? NSNull(),
                "expectedVersion": expected.map { $0 as Any } ?? NSNull()]
            let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
        var fields: [String: Any] { (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:] }
    }

    private(set) var writes: [Write] = []
    private(set) var mutations = 0
    private var version: Int
    private var title: String
    private var published = false
    private var lose = false
    private var applyWhenLost = false
    private var applied: (key: String, identity: String, version: Int)?

    init(version: Int, title: String) { self.version = version; self.title = title }

    func loseNextWrite(applying: Bool) { lose = true; applyWhenLost = applying }
    /// Une autre personne modifie le cours.
    func otherEdit(title: String) { version += 1; self.title = title; mutations += 1 }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        let method = request.httpMethod ?? "GET"
        if method == "GET" {
            return url.path.hasSuffix("course-catalogue") ? ok(CourseReplayFixture.catalogueJSON, url) : ok(seriesData(), url)
        }
        let write = Write(method: method, path: url.path, key: request.value(forHTTPHeaderField: "Idempotency-Key"),
            ifMatch: request.value(forHTTPHeaderField: "If-Match"), body: request.httpBody ?? Data())
        writes.append(write)
        if let applied, applied.key == write.key {
            if applied.identity == write.identity { return ok(seriesData(), url) }
            // Même clé d'opération, autre version ou autre corps : l'école ne rejoue pas, elle refuse.
            return SchoolHTTPResponse(data: Data("{\"code\":\"IDEMPOTENCY_CONFLICT\",\"title\":\"Opération déjà utilisée\"}".utf8), status: 409,
                url: url, contentType: "application/problem+json")
        }
        if lose && !applyWhenLost { lose = false; throw URLError(.networkConnectionLost) }
        guard write.ifMatch == "\"\(version)\"" else {
            return SchoolHTTPResponse(data: Data("{\"code\":\"VERSION_CONFLICT\",\"title\":\"Version périmée\"}".utf8), status: 412, url: url,
                contentType: "application/problem+json")
        }
        if url.path.hasSuffix("/publish") { published = true }
        else if let object = try? JSONSerialization.jsonObject(with: write.body) as? [String: Any], let newTitle = object["title"] as? String {
            title = newTitle
        }
        version += 1; mutations += 1
        applied = (write.key ?? "", write.identity, version)
        if lose { lose = false; throw URLError(.networkConnectionLost) }
        return ok(seriesData(), url)
    }

    private func seriesData() -> Data {
        CourseReplayFixture.seriesJSON(version: version, title: title, status: published ? "PUBLISHED" : "DRAFT")
    }

    private func ok(_ data: Data, _ url: URL) -> SchoolHTTPResponse {
        let envelope = Data("{\"requestId\":\"r1\",\"serverTime\":\"2030-01-01T00:00:00.000Z\",\"data\":".utf8) + data + Data("}".utf8)
        return SchoolHTTPResponse(data: envelope, status: 200, url: url, contentType: "application/json")
    }
}
