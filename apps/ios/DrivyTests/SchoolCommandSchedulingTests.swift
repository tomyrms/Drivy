import CryptoKit
import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolCommandSchedulingTests {
    private let key = Data(repeating: 0x66, count: 32)
    private let scope = SchoolCommandScope(personID: UUID(uuidString: "10000000-0000-4000-8000-000000000106")!,
        schoolID: UUID(uuidString: "20000000-0000-4000-8000-000000000106")!,
        membershipID: UUID(uuidString: "30000000-0000-4000-8000-000000000106")!, accessEpoch: 1,
        apiBaseURL: "https://api.example.invalid")

    @Test func anInvitationDoesNotBlockIndependentPlanningPreferences() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let invitation = try command(.createInvitation), preferences = try command(.savePlanningDefaults)
            try store.save(invitation)
            #expect(try store.pending(for: scope, domain: .planningPreferences) == nil)
            try store.save(preferences)
            let reopened = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            #expect(try reopened.pendingCommands(for: scope) == [invitation, preferences])
            #expect(try reopened.pending(for: scope, domain: .invitations) == invitation)
            #expect(try reopened.pending(for: scope, domain: .planningPreferences) == preferences)
            #expect(try reopened.pending(for: scope, domain: .teaching) == nil)
            // Un ancien lecteur garde sa barrière prudente ; un ancien binaire refuse le format 3.
            #expect(try reopened.pending(for: scope) == invitation)
            let sealed = try Data(contentsOf: directory.appendingPathComponent("pending-v1.bin"))
            let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: SymmetricKey(data: key),
                                        authenticating: Data("drivy-school-commands-v1".utf8))
            let archive = try #require(JSONSerialization.jsonObject(with: clear) as? [String: Any])
            #expect(archive["version"] as? Int == 3)
            try reopened.remove(invitation)
            #expect(try store.pendingCommands(for: scope) == [preferences])
        }
    }

    @Test func sharedDomainAndSchoolBarrierStillRejectConflictingOperations() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let invitation = try command(.createInvitation)
            try store.save(invitation)
            #expect(throws: SchoolConfigurationFailure.pendingCommand) { try store.save(command(.createInvitation)) }
            #expect(throws: SchoolConfigurationFailure.pendingCommand) { try store.save(command(.updateSchool)) }
            #expect(try store.pending(for: scope, domain: .school) == invitation)
        }
    }

    @Test func changedRightsPreventCrossDomainReplayUntilTheOldRequestIsResolved() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let invitation = try command(.createInvitation)
            try store.save(invitation)
            let newScope = SchoolCommandScope(personID: scope.personID, schoolID: scope.schoolID,
                membershipID: scope.membershipID, accessEpoch: 2, apiBaseURL: scope.apiBaseURL)
            #expect(try store.pending(for: newScope, domain: .planningPreferences) == invitation)
            #expect(throws: SchoolConfigurationFailure.pendingCommand) { try store.save(command(.savePlanningDefaults, scope: newScope)) }
        }
    }

    /// #112 : les signalements d’une leçon s’alignent ; ceux d’une autre leçon, la fin de leçon ou une autre époque attendent.
    @Test func observationsOfOneLessonQueueAndStillBlockTheRestOfTeaching() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let lesson = UUID()
            let first = try observation(lesson), second = try observation(lesson)
            try store.save(first)
            try store.save(second)
            #expect(throws: SchoolConfigurationFailure.pendingCommand) { try store.save(observation(UUID())) }
            let completionID = UUID()
            let completion = PendingSchoolCommand(id: completionID, scope: scope, kind: .completeLesson, resourceVersion: 1,
                createdAt: Date(), body: try JSONSerialization.data(withJSONObject: ["operationId": completionID.uuidString]),
                resourceID: lesson)
            #expect(throws: SchoolConfigurationFailure.pendingCommand) { try store.save(completion) }
            let newScope = SchoolCommandScope(personID: scope.personID, schoolID: scope.schoolID,
                membershipID: scope.membershipID, accessEpoch: 2, apiBaseURL: scope.apiBaseURL)
            #expect(throws: SchoolConfigurationFailure.pendingCommand) { try store.save(observation(lesson, scope: newScope)) }
            // Une invitation reste indépendante du domaine pédagogique.
            try store.save(command(.createInvitation))
            let reopened = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            #expect(try reopened.pendingCommands(for: scope).prefix(2) == [first, second])
            #expect(try reopened.pending(for: scope, domain: .teaching) == first)
            try reopened.remove(first)
            #expect(try store.pending(for: scope, domain: .teaching) == second)
        }
    }

    private func observation(_ lesson: UUID, scope: SchoolCommandScope? = nil) throws -> PendingSchoolCommand {
        let id = UUID()
        return PendingSchoolCommand(id: id, scope: scope ?? self.scope, kind: .createObservation, resourceVersion: 0,
            createdAt: Date(), body: try JSONSerialization.data(withJSONObject: ["operationId": id.uuidString]),
            routeResourceID: lesson)
    }

    private func command(_ kind: SchoolCommandKind, scope: SchoolCommandScope? = nil) throws -> PendingSchoolCommand {
        let id = UUID(), scope = scope ?? self.scope
        return PendingSchoolCommand(id: id, scope: scope, kind: kind,
            resourceVersion: kind == .createInvitation ? 0 : 1, createdAt: Date(),
            body: try JSONSerialization.data(withJSONObject: ["operationId": id.uuidString]),
            resourceID: kind == .savePlanningDefaults ? scope.membershipID : nil)
    }
    private func inDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Scheduling-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
