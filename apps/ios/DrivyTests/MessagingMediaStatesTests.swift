import Foundation
import XCTest
@testable import Drivy

/// États par pièce, projection des intentions dans le fil et états de la visionneuse (#476).
@MainActor
final class MessagingMediaStatesTests: XCTestCase {
    // MARK: Ouverture par pièce

    func testOpeningIsTrackedPerPieceAndSecondTapOnSamePieceIsIgnored() async throws {
        let runtime = StatesRuntimeDouble()
        let conversationID = UUID()
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: conversationID)
        let a = Self.message(conversationID)
        let b = Self.message(conversationID)
        await runtime.holdOpen()
        let first = Task { await model.open(a, stillVisible: { true }) }
        try await waitFor { await runtime.openCalls == 1 }
        XCTAssertTrue(model.isOpening(a.id))
        XCTAssertFalse(model.isOpening(b.id))
        await model.open(a, stillVisible: { true })
        let calls = await runtime.openCalls
        XCTAssertEqual(calls, 1)
        await runtime.releaseOpen()
        await first.value
        XCTAssertFalse(model.isOpening(a.id))
        guard case .ready = model.preview?.state else { return XCTFail("viewer should be ready") }
    }

    func testFailedOpenKeepsPerPieceFailureAndRetrySucceeds() async {
        let runtime = StatesRuntimeDouble()
        let conversationID = UUID()
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: conversationID)
        let a = Self.message(conversationID)
        await runtime.failOpen(.unreadable)
        await model.open(a, stillVisible: { true })
        guard case .failed(let message) = model.preview?.state else { return XCTFail("viewer should be failed") }
        XCTAssertFalse(message.isEmpty)
        guard case .failed(let failure)? = model.openState(for: a.id) else { return XCTFail("piece should be failed") }
        XCTAssertTrue(failure.canRetry)
        await runtime.failOpen(nil)
        await model.open(a, stillVisible: { true })
        guard case .ready = model.preview?.state else { return XCTFail("retry should reach ready") }
        XCTAssertNil(model.openState(for: a.id))
    }

    func testClosingDuringOpenCancelsAndLateResultIsIgnored() async throws {
        let runtime = StatesRuntimeDouble()
        let conversationID = UUID()
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: conversationID)
        let a = Self.message(conversationID)
        await runtime.holdOpen()
        let task = Task { await model.open(a, stillVisible: { true }) }
        try await waitFor { await runtime.openCalls == 1 }
        guard case .loading = model.preview?.state else { return XCTFail("viewer should be loading") }
        model.closePreview()
        XCTAssertNil(model.preview)
        XCTAssertFalse(model.isOpening(a.id))
        await runtime.releaseOpen()
        await task.value
        XCTAssertNil(model.preview)
    }

    func testSuspendDuringOpenDiscardsResult() async throws {
        let runtime = StatesRuntimeDouble()
        let conversationID = UUID()
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: conversationID)
        let a = Self.message(conversationID)
        await runtime.holdOpen()
        let task = Task { await model.open(a, stillVisible: { true }) }
        try await waitFor { await runtime.openCalls == 1 }
        model.suspend()
        await runtime.releaseOpen()
        await task.value
        XCTAssertNil(model.preview)
        XCTAssertNil(model.openState(for: a.id))
    }

    func testContextChangeDuringOpenClosesViewer() async {
        let runtime = StatesRuntimeDouble()
        let conversationID = UUID()
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: conversationID)
        await runtime.failOpen(.contextChanged)
        await model.open(Self.message(conversationID), stillVisible: { true })
        XCTAssertNil(model.preview)
    }

    func testRemovedPieceFailureIsNotRetryable() {
        let failure = MessagingMediaOpenFailure(MessagingMediaRuntimeFailure.removed)
        XCTAssertFalse(failure.canRetry)
        XCTAssertTrue(MessagingMediaOpenFailure(MessagingMediaRuntimeFailure.integrity).canRetry)
    }

    // MARK: Intentions dans le fil

    func testUnknownDeliveryIsProjectedToVerifyThenFailedWithTargetedRetry() async {
        let runtime = StatesRuntimeDouble()
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: UUID())
        await model.select { Self.input }
        await model.sendSelected(replyTo: nil)
        let entries = model.timelineEntries
        XCTAssertEqual(entries.count, 1)
        guard case .failed(.resultUnknown) = entries[0].phase else { return XCTFail("phase should be resultUnknown") }
        let presentation = MessagingMediaIntentionPresentation(entries[0].phase)
        XCTAssertNotNil(presentation.retryTitle)
        XCTAssertFalse(presentation.showsProgress)
    }

    func testConfirmedBubbleStaysUntilRealMessageThenIsPruned() async {
        let runtime = StatesRuntimeDouble()
        await runtime.confirmNext()
        let conversationID = UUID()
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: conversationID)
        await model.select { Self.input }
        await model.sendSelected(replyTo: nil)
        XCTAssertTrue(model.pendingItems.isEmpty)
        XCTAssertEqual(model.timelineEntries.count, 1)
        guard case .confirmed = model.timelineEntries[0].phase else { return XCTFail("phase should be confirmed") }
        let serverID = model.confirmedClientIDs.keys.first
        XCTAssertNotNil(serverID)
        model.reconcile(visibleMessageIDs: [serverID!])
        XCTAssertTrue(model.timelineEntries.isEmpty)
    }

    func testCleanupPendingStillReadsAsSuccess() {
        let presentation = MessagingMediaIntentionPresentation(.confirmed(cleanupPending: true))
        XCTAssertEqual(presentation.tone, .success)
        XCTAssertNil(presentation.text)
        XCTAssertNil(presentation.retryTitle)
    }

    func testPresentationMapping() {
        XCTAssertTrue(MessagingMediaIntentionPresentation(.sending).showsProgress)
        XCTAssertNotNil(MessagingMediaIntentionPresentation(.toVerify).retryTitle)
        XCTAssertNil(MessagingMediaIntentionPresentation(.failed(.contextChanged)).retryTitle)
        XCTAssertNil(MessagingMediaIntentionPresentation(.failed(.accessChanged)).retryTitle)
        XCTAssertNotNil(MessagingMediaIntentionPresentation(.failed(.membersChanged)).retryTitle)
    }

    // MARK: Projection

    func testProjectionDoesNotDoubleMediaPendingWhenRealMessageArrives() {
        let conversationID = UUID()
        let clientID = UUID()
        var real = Self.message(conversationID)
        real.meta.media = try? .init(mediaID: UUID(), byteSize: 1, deleted: false)
        let snapshot = MessagingMediaPendingSnapshot(clientMessageID: clientID, mediaID: UUID(),
            conversationID: conversationID, caption: nil, name: "Synthetic.png", mime: .png, byteSize: 1,
            createdAt: Date())
        let entry = MessagingMediaPendingEntry(snapshot: snapshot, phase: .confirmed(cleanupPending: false))
        let before = MessagingThreadProjection.items(messages: [], pending: [], mediaPending: [entry],
            accountID: UUID(), clientIDs: [:], pendingDates: [:], now: Date())
        XCTAssertEqual(before.map(\.id), [clientID.uuidString])
        let after = MessagingThreadProjection.items(messages: [real], pending: [], mediaPending: [entry],
            accountID: UUID(), clientIDs: [real.id: clientID], pendingDates: [:], now: Date())
        XCTAssertEqual(after.map(\.id), [clientID.uuidString])
        XCTAssertNotNil(after.first?.message)
    }

    // MARK: Aides

    private static func message(_ conversationID: UUID) -> MessagingWireMessage {
        var message = MessagingWireMessage(id: UUID(), conversationID: conversationID, schoolID: UUID(),
            senderID: UUID(), acceptedAt: Date(), ciphertext: nil)
        message.meta.media = try? .init(mediaID: UUID(), byteSize: 1, deleted: false)
        return message
    }

    private static let input = MessagingImportedMedia(data: Data([1]), suggestedName: "Synthetic.png")

    private func waitFor(timeout: Duration = .seconds(2), condition: @MainActor () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("condition not reached")
    }
}

private actor StatesRuntimeDouble: MessagingMediaRuntime {
    var openCalls = 0
    private var stored: [MessagingMediaPendingSnapshot] = []
    private var confirmation = false
    private var openHeld = false
    private var openContinuations: [CheckedContinuation<Void, Never>] = []
    private var openFailure: MessagingMediaRuntimeFailure?
    func holdOpen() { openHeld = true }
    func releaseOpen() {
        openHeld = false
        let waiting = openContinuations; openContinuations = []
        for continuation in waiting { continuation.resume() }
    }
    func failOpen(_ failure: MessagingMediaRuntimeFailure?) { openFailure = failure }
    func confirmNext() { confirmation = true }
    func prepare(_ data: Data, suggestedName: String) async throws -> MessagingPreparedMedia {
        MessagingPreparedMedia(data: data, mime: .png, name: suggestedName, width: 1, height: 1, thumbnail: nil)
    }
    func enqueue(_ prepared: MessagingPreparedMedia, clientMessageID: UUID, conversationID: UUID,
                 caption: String?, mentionPersonIDs: [UUID], replyToMessageID: UUID?) async throws -> MessagingMediaPendingSnapshot {
        let item = MessagingMediaPendingSnapshot(clientMessageID: clientMessageID, mediaID: UUID(),
            conversationID: conversationID, caption: caption, name: prepared.name, mime: prepared.mime,
            byteSize: prepared.data.count, createdAt: Date())
        stored.append(item)
        return item
    }
    func pending(conversationID: UUID) async throws -> [MessagingMediaPendingSnapshot] {
        stored.filter { $0.conversationID == conversationID }
    }
    func send(clientMessageID: UUID) async -> MessagingMediaDelivery {
        guard confirmation, let item = stored.first(where: { $0.id == clientMessageID }) else { return .pending(.resultUnknown) }
        stored.removeAll { $0.id == clientMessageID }
        return .confirmed(MessagingAcknowledgement(clientMessageID: clientMessageID, serverMessageID: UUID(),
            conversationID: item.conversationID, schoolID: UUID(), acceptedAt: Date(), senderID: UUID()), cleanupPending: false)
    }
    func recomposeAfterMembersChanged(clientMessageID: UUID) async -> MessagingMediaDelivery { await send(clientMessageID: clientMessageID) }
    func open(_ message: MessagingWireMessage) async throws -> MessagingPreparedMedia {
        openCalls += 1
        if openHeld { await withCheckedContinuation { openContinuations.append($0) } }
        if let openFailure { throw openFailure }
        return try await prepare(Data([1]), suggestedName: "Synthetic.png")
    }
    func invalidate() async {}
}
