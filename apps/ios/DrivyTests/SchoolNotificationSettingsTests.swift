import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolNotificationSettingsTests {
    private let scope = AccountIntentScope(personID: UUID(uuidString: "10000000-0000-4000-8000-000000000119")!,
                                           apiBaseURL: "https://api.example.invalid")

    @Test func rapidChangesKeepTheLatestChoiceWhileThePreviousRequestIsWaiting() async throws {
        let api = NotificationSettingsTestAPI(), store = NotificationSettingsTestStore()
        let model = make(api, store)
        await model.load()
        model.set(.courseOffers, false)
        try await until { api.requests.count == 1 }
        #expect(model.preferences?.courseOffers == false)
        model.set(.courseReminders, false)
        model.set(.courseOffers, true)
        #expect(model.preferences?.courseOffers == true && model.preferences?.courseReminders == false)
        #expect(api.requests.count == 1)
        api.succeed()
        try await until { api.requests.count == 2 }
        #expect(model.preferences?.courseOffers == true)
        #expect(api.requests[1].version == 2 && api.requests[1].body.courseOffers && !api.requests[1].body.courseReminders)
        api.succeed()
        try await until { !model.isSaving }
        #expect(!model.hasPendingChanges && model.confirmed?.version == 3)
        #expect(store.value?.intents.isEmpty == true && store.value?.attempt == nil)
    }

    @Test func conflictRebasesOnlyLocalChoicesAndKeepsTheOtherDevicesChanges() async throws {
        let api = NotificationSettingsTestAPI(), store = NotificationSettingsTestStore()
        let model = make(api, store)
        await model.load(); model.set(.courseOffers, false)
        try await until { api.requests.count == 1 }
        api.current = .init(version: 2, courseOffers: true, courseReminders: false, courseChanges: true, courseStaffAlerts: true)
        api.fail(.conflict)
        try await until { api.requests.count == 2 }
        #expect(api.requests[1].version == 2)
        #expect(!api.requests[1].body.courseOffers && !api.requests[1].body.courseReminders)
        api.succeed()
        try await until { !model.isSaving }
        #expect(model.preferences?.courseReminders == false && model.preferences?.courseOffers == false)
    }

    @Test func eighthConfirmedWriteDoesNotLeaveAFalseConflict() async throws {
        let api = NotificationSettingsTestAPI(), store = NotificationSettingsTestStore()
        let model = make(api, store)
        await model.load(); model.set(.courseOffers, false)
        for index in 1...8 {
            try await until { api.requests.count == index }
            if index < 8 { model.set(.courseOffers, index % 2 == 1) }
            api.succeed()
        }
        try await until { !model.isSaving }
        #expect(!model.hasPendingChanges && model.state == .idle && model.errorMessage == nil)
    }

    @Test func lostReplyIsReconciledByReadWithoutASecondWrite() async throws {
        let api = NotificationSettingsTestAPI(), store = NotificationSettingsTestStore()
        let model = make(api, store)
        await model.load(); model.set(.courseOffers, false)
        try await until { api.requests.count == 1 }
        api.applyLastWrite(); api.fail(.unavailable)
        try await until { !model.isSaving }
        #expect(model.state == .unconfirmed && model.preferences?.courseOffers == false)
        #expect(store.value?.attempt != nil)
        await model.retry()
        #expect(!model.hasPendingChanges && model.confirmed?.courseOffers == false)
        #expect(api.requests.count == 1)
    }

    @Test func retryUsesTheExactUncertainBodyBeforeSendingANewerChoice() async throws {
        let api = NotificationSettingsTestAPI(), store = NotificationSettingsTestStore()
        let model = make(api, store)
        await model.load(); model.set(.courseOffers, false)
        try await until { api.requests.count == 1 }
        api.fail(.invalidResponse)
        try await until { !model.isSaving }
        let original = try #require(store.value?.attempt)
        await model.retry()
        try await until { api.requests.count == 2 }
        #expect(api.requests[1].body == original.body && api.requests[1].version == original.base.version)
        model.set(.courseOffers, true)
        api.succeed()
        try await until { api.requests.count == 3 }
        #expect(api.requests[2].version == 2 && api.requests[2].body.courseOffers)
        api.succeed(); try await until { !model.isSaving }
        #expect(model.preferences?.courseOffers == true && !model.hasPendingChanges)
    }

    @Test func storageFailurePreservesTheChoiceWithoutSendingIt() async throws {
        let api = NotificationSettingsTestAPI(), store = NotificationSettingsTestStore()
        let model = make(api, store)
        await model.load(); store.failWrites = true
        model.set(.courseOffers, false)
        #expect(model.preferences?.courseOffers == false && model.state == .storageUnavailable)
        #expect(api.requests.isEmpty)
        store.failWrites = false
        await model.retry()
        try await until { api.requests.count == 1 }
        api.succeed(); try await until { !model.isSaving }
        #expect(!model.hasPendingChanges)
    }

    @Test func reopeningRecoversAnUncertainRequestAndKeepsNewerIntents() async throws {
        let api = NotificationSettingsTestAPI(), store = NotificationSettingsTestStore()
        let first = make(api, store)
        await first.load(); first.set(.courseOffers, false)
        try await until { api.requests.count == 1 }
        first.set(.courseReminders, false)
        api.applyLastWrite(); api.fail(.unavailable)
        try await until { !first.isSaving }
        first.invalidate()
        let reopened = make(api, store)
        await reopened.load()
        try await until { api.requests.count == 2 }
        #expect(!api.requests[1].body.courseOffers && !api.requests[1].body.courseReminders)
        #expect(api.requests[1].version == 2)
        api.succeed(); try await until { !reopened.isSaving }
        #expect(!reopened.hasPendingChanges)
    }

    @Test func oldAccountReplyCannotRestoreDataOrSendQueuedChanges() async throws {
        let api = NotificationSettingsTestAPI(), store = NotificationSettingsTestStore()
        let model = make(api, store)
        await model.load(); model.set(.courseOffers, false)
        try await until { api.requests.count == 1 }
        model.set(.courseReminders, false)
        model.invalidate(); api.succeed()
        for _ in 0..<50 { await Task.yield() }
        #expect(model.preferences == nil && api.requests.count == 1)
        #expect(store.value?.attempt != nil)
    }

    @Test func refreshedPageKeepsItsDataAndDeduplicatesTheSameRead() async throws {
        let api = NotificationSettingsTestAPI(), store = NotificationSettingsTestStore()
        let model = make(api, store)
        await model.load()
        api.suspendRead = true
        let refresh = Task { await model.load() }
        try await until { api.readWaiter != nil }
        #expect(model.preferences != nil && model.isLoading)
        await model.load()
        #expect(api.reads == 2)
        api.completeRead(.failure(.unavailable)); await refresh.value
        #expect(model.preferences != nil && model.errorMessage != nil)
    }

    @Test func lateReadDoesNotReplaceAWriteOrItsNewerLocalChoice() async throws {
        let api = NotificationSettingsTestAPI(), store = NotificationSettingsTestStore()
        let model = make(api, store)
        await model.load(); let stale = api.current
        api.suspendRead = true
        let refresh = Task { await model.load() }
        try await until { api.readWaiter != nil }
        model.set(.courseOffers, false)
        try await until { api.requests.count == 1 }
        api.succeed(); try await until { !model.isSaving }
        api.completeRead(.success(stale)); await refresh.value
        #expect(model.confirmed?.version == 2 && model.preferences?.courseOffers == false)
    }

    @Test func unreadableJournalNeverGetsOverwrittenByAnEmptyOne() async {
        let api = NotificationSettingsTestAPI(), store = NotificationSettingsTestStore()
        store.failReads = true
        let model = make(api, store)
        await model.load(); await model.retry()
        #expect(model.state == .storageUnavailable && store.writes == 0 && api.reads == 0)
    }

    private func make(_ api: NotificationSettingsTestAPI, _ store: NotificationSettingsTestStore) -> SchoolNotificationSettingsModel {
        SchoolNotificationSettingsModel(scope: scope, api: api, store: store, contextIsCurrent: { true })
    }
    private func until(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<2_000 {
            if predicate() { return }
            await Task.yield()
        }
        try #require(predicate(), "Le traitement asynchrone attendu n'est pas arrivé.")
    }
}

@MainActor private final class NotificationSettingsTestStore: SchoolNotificationIntentStore {
    var value: SchoolNotificationIntentJournal?
    var failWrites = false, failReads = false, writes = 0
    func read(for scope: AccountIntentScope) throws -> SchoolNotificationIntentJournal? {
        if failReads { throw SchoolConfigurationFailure.storage }
        return value
    }
    func save(_ journal: SchoolNotificationIntentJournal, for scope: AccountIntentScope) throws {
        if failWrites { throw SchoolConfigurationFailure.storage }
        writes += 1; value = journal
    }
}

@MainActor private final class NotificationSettingsTestAPI: SchoolNotificationPreferencesAPI {
    struct Request { let body: SchoolNotificationPreferencesBody; let version: Int }
    var current = SchoolNotificationPreferences(version: 1, courseOffers: true, courseReminders: true,
                                                 courseChanges: true, courseStaffAlerts: true)
    var requests: [Request] = [], reads = 0
    var waiter: CheckedContinuation<SchoolNotificationPreferences, any Error>?
    var readWaiter: CheckedContinuation<SchoolNotificationPreferences, any Error>?
    var suspendRead = false

    func preferences(contextIsCurrent: @escaping @MainActor () -> Bool) async throws -> SchoolNotificationPreferences {
        reads += 1
        if suspendRead { return try await withCheckedThrowingContinuation { readWaiter = $0 } }
        return current
    }
    func save(_ body: SchoolNotificationPreferencesBody, version: Int,
              contextIsCurrent: @escaping @MainActor () -> Bool) async throws -> SchoolNotificationPreferences {
        requests.append(.init(body: body, version: version))
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }
    func applyLastWrite() {
        guard let last = requests.last else { return }
        current = .init(version: last.version + 1, courseOffers: last.body.courseOffers,
                        courseReminders: last.body.courseReminders, courseChanges: last.body.courseChanges,
                        courseStaffAlerts: last.body.courseStaffAlerts)
    }
    func succeed() { applyLastWrite(); let pending = waiter; waiter = nil; pending?.resume(returning: current) }
    func fail(_ error: SchoolPlanningFailure) { let pending = waiter; waiter = nil; pending?.resume(throwing: error) }
    func completeRead(_ result: Result<SchoolNotificationPreferences, SchoolPlanningFailure>) {
        let pending = readWaiter; readWaiter = nil; suspendRead = false
        switch result {
        case .success(let value): pending?.resume(returning: value)
        case .failure(let error): pending?.resume(throwing: error)
        }
    }
}
