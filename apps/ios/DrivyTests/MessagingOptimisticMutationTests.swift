import XCTest
@testable import Drivy

/// #104 : intentions locales, réponses lentes, refus, relectures intercalées. Doubles synthétiques uniquement.
@MainActor
final class MessagingOptimisticMutationTests: XCTestCase {
    private let school = UUID(), account = UUID(), conversation = UUID(), other = UUID(), messageID = UUID()
    private var scope: MessagingScope { MessagingScope(accountID: account, schoolID: school, accessEpoch: 1) }
    private let latency = MessagingMutationLatency(slow: .seconds(60), unconfirmed: .seconds(120))

    private func wire(reactions: [MessagingReaction] = [], pinned: Bool = false, poll: MessagingPollState? = nil) -> MessagingWireMessage {
        var meta = MessagingMessageMeta(sequence: 1)
        meta.reactions = reactions; meta.pinned = pinned; meta.poll = poll
        return MessagingWireMessage(id: messageID, conversationID: conversation, schoolID: school, senderID: other,
            acceptedAt: Date(timeIntervalSince1970: 1), ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: Data("m".utf8)),
            meta: meta)
    }

    private func make(_ actions: GatedActions, service: MutableService, current: MutationScopeBox? = nil) async -> MessagingWorkspace {
        let box = current ?? MutationScopeBox(scope)
        let workspace = MessagingWorkspace(scope: scope, service: service, actions: actions,
                                           mutationLatency: latency, currentScope: { box.value })
        await workspace.loadMessages(conversation)
        return workspace
    }

    private func until(_ condition: @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition non atteinte", file: file, line: line)
    }

    private func thumbs(_ workspace: MessagingWorkspace) -> [UUID] {
        workspace.message(messageID, in: conversation)?.meta.reactions.first { $0.emoji == "👍" }?.personIDs ?? []
    }

    func testReactionAppearsImmediatelyBeforeServerAnswers() async {
        let actions = GatedActions(holding: true)
        let service = MutableService(wire(reactions: [MessagingReaction(emoji: "👍", personIDs: [other])]))
        let workspace = await make(actions, service: service)
        workspace.toggleReaction("👍", on: wire())
        XCTAssertEqual(Set(thumbs(workspace)), [other, account])
        XCTAssertEqual(workspace.visibleMessages(conversation).first?.meta.reactions.first?.personIDs.count, 2)
        XCTAssertEqual(workspace.mutation(.reaction("👍"), on: wire())?.status, .sending)
        await actions.releaseAll()
    }

    func testAddThenRemoveDuringFlightEndsRemovedWithFinalInactiveRequest() async {
        let actions = GatedActions(holding: true)
        let service = MutableService(wire())
        let workspace = await make(actions, service: service)
        workspace.toggleReaction("👍", on: wire())
        await until { await actions.calls.count == 1 }
        workspace.toggleReaction("👍", on: wire())
        XCTAssertTrue(thumbs(workspace).isEmpty)
        await actions.releaseAll()
        await until { await actions.calls.count == 2 }
        await until { workspace.pendingMutations.isEmpty }
        let calls = await actions.calls
        XCTAssertEqual(calls, ["reaction 👍 true", "reaction 👍 false"])
        XCTAssertTrue(thumbs(workspace).isEmpty)
    }

    func testRejectionRemovesOnlyThatIntention() async {
        let actions = GatedActions(holding: false)
        await actions.fail(emoji: "❤️", with: .stateConflict)
        let service = MutableService(wire(reactions: [MessagingReaction(emoji: "😂", personIDs: [other])]))
        let workspace = await make(actions, service: service)
        workspace.setPinned(wire(), pinned: true)
        workspace.toggleReaction("❤️", on: wire())
        await until { workspace.rejection(for: self.messageID) != nil }
        XCTAssertNil(workspace.mutation(.reaction("❤️"), on: wire()))
        XCTAssertEqual(workspace.message(messageID, in: conversation)?.meta.reactions.map(\.emoji), ["😂"])
        XCTAssertEqual(workspace.rejection(for: messageID)?.failure, .stateConflict)
        XCTAssertNil(workspace.actionError)
    }

    func testTimeoutIsUncertainAndRetrySendsSameDesiredState() async {
        let actions = GatedActions(holding: false)
        await actions.fail(emoji: "👍", with: .unavailable)
        let workspace = await make(actions, service: MutableService(wire()))
        workspace.toggleReaction("👍", on: wire())
        await until { workspace.mutation(.reaction("👍"), on: self.wire())?.status == .uncertain }
        XCTAssertEqual(thumbs(workspace), [account])
        await actions.fail(emoji: "👍", with: nil)
        workspace.retryMutations(for: wire())
        await until { workspace.mutation(.reaction("👍"), on: self.wire())?.status == .confirmed }
        let calls = await actions.calls
        XCTAssertEqual(calls, ["reaction 👍 true", "reaction 👍 true"])
    }

    func testInterleavedServerReloadDoesNotEraseIntention() async {
        let actions = GatedActions(holding: true)
        let service = MutableService(wire())
        let workspace = await make(actions, service: service)
        workspace.toggleReaction("👍", on: wire())
        await workspace.loadMessages(conversation)
        XCTAssertEqual(thumbs(workspace), [account])
        await actions.releaseAll()
    }

    func testConfirmationNeverDoubleCounts() async {
        let actions = GatedActions(holding: true)
        let service = MutableService(wire(reactions: [MessagingReaction(emoji: "👍", personIDs: [other])]))
        let workspace = await make(actions, service: service)
        workspace.toggleReaction("👍", on: wire())
        await service.set(wire(reactions: [MessagingReaction(emoji: "👍", personIDs: [other, account])]))
        await actions.releaseAll()
        await until { workspace.pendingMutations.isEmpty }
        XCTAssertEqual(thumbs(workspace).count, 2)
        XCTAssertEqual(workspace.visibleMessages(conversation).first?.meta.reactions.first?.personIDs.count, 2)
    }

    func testOfflineWaitsThenResendsOnReconnect() async {
        let actions = GatedActions(holding: false)
        let workspace = await make(actions, service: MutableService(wire()))
        workspace.setNetworkAvailable(false)
        workspace.toggleReaction("👍", on: wire())
        XCTAssertEqual(workspace.mutation(.reaction("👍"), on: wire())?.status, .offline)
        let before = await actions.calls
        XCTAssertTrue(before.isEmpty)
        workspace.setNetworkAvailable(true)
        await until { await actions.calls == ["reaction 👍 true"] }
    }

    func testContextChangeClearsIntentionsAndNeverReplays() async {
        let actions = GatedActions(holding: true)
        let box = MutationScopeBox(scope)
        let workspace = await make(actions, service: MutableService(wire()), current: box)
        workspace.toggleReaction("👍", on: wire())
        await until { await actions.calls.count == 1 }
        box.value = nil
        await actions.releaseAll()
        await until { workspace.pendingMutations.isEmpty }
        XCTAssertEqual(workspace.error, .contextChanged)
        workspace.toggleReaction("👍", on: wire())
        try? await Task.sleep(for: .milliseconds(30))
        let calls = await actions.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(workspace.pendingMutations.isEmpty)
    }

    func testVoteAndPinAreProjectedImmediately() async {
        let actions = GatedActions(holding: true)
        let poll = MessagingPollState(allowsMultiple: false, closed: false, creatorID: other,
            options: [.init(optionID: "o1", voterIDs: [account]), .init(optionID: "o2", voterIDs: [])])
        let workspace = await make(actions, service: MutableService(wire(poll: poll)))
        workspace.vote(wire(poll: poll), optionIDs: ["o2"])
        workspace.setPinned(wire(), pinned: true)
        let projected = workspace.message(messageID, in: conversation)
        XCTAssertEqual(projected?.meta.poll?.options.map(\.voterIDs), [[], [account]])
        XCTAssertEqual(projected?.meta.pinned, true)
        XCTAssertEqual(workspace.pinnedMessages(conversation).count, 1)
        await actions.releaseAll()
        await until { await actions.calls.count == 2 }
        let calls = await actions.calls
        XCTAssertEqual(Set(calls), ["vote o2", "pin true"])
    }

    func testDeleteForMeHidesAtOnceAndForEveryoneWaitsForServer() async {
        let actions = GatedActions(holding: true)
        let workspace = await make(actions, service: MutableService(wire()))
        workspace.delete(wire(), for: .everyone)
        XCTAssertEqual(workspace.visibleMessages(conversation).first?.meta.deletedForEveryone, false)
        XCTAssertNotNil(workspace.mutation(.deleteForEveryone, on: wire()))
        workspace.delete(wire(), for: .me)
        XCTAssertTrue(workspace.visibleMessages(conversation).isEmpty)
        await actions.releaseAll()
    }
}

@MainActor private final class MutationScopeBox: Sendable {
    var value: MessagingScope?
    init(_ value: MessagingScope?) { self.value = value }
}

private actor MutableService: MessagingService {
    private var current: MessagingWireMessage
    init(_ message: MessagingWireMessage) { current = message }
    func set(_ message: MessagingWireMessage) { current = message }
    func conversations(scope: MessagingScope, cursor: String?) async throws -> MessagingPage<MessagingConversation> {
        MessagingPage(items: [], nextCursor: nil)
    }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) async throws -> MessagingPage<MessagingWireMessage> {
        MessagingPage(items: [current], nextCursor: nil)
    }
    func send(scope: MessagingScope, pending: MessagingPending) async throws -> MessagingAcknowledgement { throw MessagingFailure.unavailable }
}

/// Retient chaque requête jusqu'à `releaseAll` quand `holding` ; échecs programmables par emoji.
private actor GatedActions: MessagingThreadActions {
    private(set) var calls: [String] = []
    private var holding: Bool
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var failures: [String: MessagingFailure] = [:]
    init(holding: Bool) { self.holding = holding }

    func fail(emoji: String, with failure: MessagingFailure?) { failures[emoji] = failure }
    func releaseAll() {
        holding = false
        let pending = waiters; waiters = []
        for waiter in pending { waiter.resume() }
    }
    private func gate(_ call: String) async {
        calls.append(call)
        if holding { await withCheckedContinuation { waiters.append($0) } }
    }

    func delete(scope: MessagingScope, conversationID: UUID, messageID: UUID, for deletion: MessagingDeletionScope) async throws {
        await gate("delete \(deletion.rawValue)")
    }
    func setReaction(scope: MessagingScope, conversationID: UUID, messageID: UUID, emoji: String, active: Bool) async throws {
        await gate("reaction \(emoji) \(active)")
        if let failure = failures[emoji] { throw failure }
    }
    func setPinned(scope: MessagingScope, conversationID: UUID, messageID: UUID, pinned: Bool) async throws { await gate("pin \(pinned)") }
    func vote(scope: MessagingScope, conversationID: UUID, messageID: UUID, optionIDs: [String]) async throws {
        await gate("vote \(optionIDs.joined(separator: ","))")
    }
    func closePoll(scope: MessagingScope, conversationID: UUID, messageID: UUID) async throws { await gate("close") }
    func setGroupAdmin(scope: MessagingScope, personID: UUID, admin: Bool) async throws {}
    func removeGeneralMember(scope: MessagingScope, personID: UUID) async throws {}
    func reinstateGeneralMember(scope: MessagingScope, personID: UUID) async throws {}
    func members(scope: MessagingScope) async throws -> [MessagingMember] { [] }
    func removedMembers(scope: MessagingScope) async throws -> [MessagingMember] { [] }
    func report(scope: MessagingScope, conversationID: UUID, clientReportID: UUID, items: [MessagingReportItem]) async throws {}
}
