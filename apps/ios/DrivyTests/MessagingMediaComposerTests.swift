import Foundation
import XCTest
@testable import Drivy

@MainActor
final class MessagingMediaComposerTests: XCTestCase {
    func testCancelledImportLeavesNoSelectionOrError() async {
        let model = MessagingMediaComposerModel(runtime: MediaRuntimeDouble(), conversationID: UUID())
        await model.select { throw CancellationError() }
        XCTAssertNil(model.selection)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.preparing)
    }

    func testRefusedImportIsVisibleAndDoesNotEnableSending() async {
        let model = MessagingMediaComposerModel(runtime: MediaRuntimeDouble(), conversationID: UUID())
        await model.select { throw MessagingMediaImportFailure.invalidSize }
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.canSend)
    }

    func testUnknownDeliveryKeepsStableIntentionAndEmptyCaptionIsNil() async {
        let runtime = MediaRuntimeDouble()
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: UUID())
        await model.select { Self.input }
        model.caption = "  \n "
        await model.sendSelected(replyTo: nil)
        let pending = model.pendingItems.first
        XCTAssertNotNil(pending)
        XCTAssertNil(pending?.caption)
        XCTAssertNil(model.selection)
        XCTAssertEqual(model.failures[pending!.id], .resultUnknown)
        await runtime.confirmNext()
        await model.retry(pending!.id)
        XCTAssertTrue(model.pendingItems.isEmpty)
        XCTAssertNotNil(model.confirmation)
        let ids = await runtime.sentIDs
        XCTAssertEqual(ids, [pending!.id, pending!.id])
    }

    func testStorageFailureKeepsSelectionAndSameGestureIDForRetry() async {
        let runtime = MediaRuntimeDouble()
        await runtime.failStorage()
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: UUID())
        await model.select { Self.input }
        await model.sendSelected(replyTo: nil)
        XCTAssertNotNil(model.selection)
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.pendingItems.isEmpty)
        await runtime.allowStorage()
        await model.sendSelected(replyTo: nil)
        let ids = await runtime.enqueuedIDs
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(ids.first, ids.last)
    }

    func testRemovingNewSelectionDoesNotRemoveDurableIntention() async {
        let model = MessagingMediaComposerModel(runtime: MediaRuntimeDouble(), conversationID: UUID())
        await model.select { Self.input }
        await model.sendSelected(replyTo: nil)
        let first = model.pendingItems.first?.id
        await model.select { Self.input }
        model.removeSelection()
        XCTAssertNil(model.selection)
        XCTAssertEqual(model.pendingItems.first?.id, first)
    }

    func testLatePreparationAfterLeavingContextIsDiscarded() async throws {
        let gate = MediaInputGate()
        let model = MessagingMediaComposerModel(runtime: MediaRuntimeDouble(), conversationID: UUID())
        try await withHeldOperation("import before context exit", entered: { await gate.waiting },
            release: { await gate.finish(Self.input) },
            operation: { await model.select { await gate.read() } }) {
                XCTAssertTrue(model.preparing)
                model.suspend()
            }
        XCTAssertNil(model.selection)
        XCTAssertNil(model.preview)
        XCTAssertFalse(model.canSend)
    }

    func testDoubleGestureWhileSendingDoesNotEnqueueAgain() async throws {
        let runtime = MediaRuntimeDouble()
        await runtime.holdSend()
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: UUID())
        await model.select { Self.input }
        try await withHeldOperation("send", entered: { await runtime.sending },
            release: { await runtime.releaseSend() },
            operation: { await model.sendSelected(replyTo: nil) }) {
                await model.sendSelected(replyTo: nil)
                XCTAssertTrue(model.sending)
            }
        let ids = await runtime.enqueuedIDs
        XCTAssertEqual(ids.count, 1)
    }

    func testReloadRequiresExplicitResendAndVaultFailureIsVisible() async {
        let runtime = MediaRuntimeDouble()
        let conversation = UUID()
        let first = MessagingMediaComposerModel(runtime: runtime, conversationID: conversation)
        await first.select { Self.input }
        await first.sendSelected(replyTo: nil)
        let reopened = MessagingMediaComposerModel(runtime: runtime, conversationID: conversation)
        await reopened.load()
        XCTAssertEqual(reopened.pendingItems.count, 1)
        let ids = await runtime.sentIDs
        XCTAssertEqual(ids.count, 1)
        await runtime.failStorage()
        await reopened.load()
        XCTAssertNotNil(reopened.error)
        XCTAssertEqual(reopened.pendingItems.count, 1)
    }

    func testCleanupFailureStillShowsConfirmation() async {
        let runtime = MediaRuntimeDouble()
        await runtime.confirmNext(cleanupPending: true)
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: UUID())
        await model.select { Self.input }
        await model.sendSelected(replyTo: nil)
        XCTAssertNotNil(model.confirmation)
        XCTAssertTrue(model.cleanupPending)
        XCTAssertTrue(model.pendingItems.isEmpty)
    }

    func testReceivedMediaCanOpenAndRemovalClosesPreview() async throws {
        let message = try Self.message()
        let model = MessagingMediaComposerModel(runtime: MediaRuntimeDouble(), conversationID: message.conversationID)
        await model.open(message, stillVisible: { true })
        XCTAssertEqual(model.preview?.messageID, message.id)
        model.dismissRemovedPreview(visibleIDs: [])
        XCTAssertNil(model.preview)
    }

    func testDeletedReferenceCannotOpen() async throws {
        var message = try Self.message()
        message.meta.media = try .init(mediaID: UUID(), byteSize: 1, deleted: true)
        let model = MessagingMediaComposerModel(runtime: MediaRuntimeDouble(), conversationID: message.conversationID)
        await model.open(message, stillVisible: { true })
        XCTAssertNil(model.preview)
    }

    func testLateOpenAfterRemovalIsDiscarded() async throws {
        let runtime = MediaRuntimeDouble()
        await runtime.holdOpen()
        let message = try Self.message()
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: message.conversationID)
        var visible = true
        try await withHeldOperation("received media open", entered: { await runtime.opening },
            release: { await runtime.releaseOpen() },
            operation: { await model.open(message, stillVisible: { visible }) }) {
                visible = false
            }
        XCTAssertNil(model.preview)
        XCTAssertFalse(model.opening)
    }

    func testRemovingSelectionDuringOpenDiscardsResultAndAllowsNextOpen() async throws {
        let runtime = MediaRuntimeDouble()
        let messageB = try Self.message()
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: messageB.conversationID)
        // Keep a durable intention too: removing A must leave it alone.
        await model.select { Self.input }
        await model.sendSelected(replyTo: nil)
        let pendingID = try XCTUnwrap(model.pendingItems.first?.id)
        await model.select { Self.input }
        XCTAssertNotNil(model.selection)
        await runtime.holdOpen()
        try await withHeldOperation("B while A selected", entered: { await runtime.opening },
            release: { await runtime.releaseOpen() },
            operation: { await model.open(messageB, stillVisible: { true }) }) {
                XCTAssertTrue(model.opening)
                model.removeSelection()
                XCTAssertFalse(model.opening)
                XCTAssertNil(model.selection)
            }
        XCTAssertFalse(model.opening)
        XCTAssertNil(model.preview)
        XCTAssertEqual(model.pendingItems.map(\.id), [pendingID])
        let messageC = try Self.message(conversationID: messageB.conversationID)
        await model.open(messageC, stillVisible: { true })
        XCTAssertEqual(model.preview?.messageID, messageC.id)
        XCTAssertFalse(model.opening)
    }

    func testRemovingSelectionDuringPreparationDiscardsLateInput() async throws {
        let runtime = MediaRuntimeDouble()
        await runtime.holdPreparation()
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: UUID())
        try await withHeldOperation("preparation before removal", entered: { await runtime.preparing },
            release: { await runtime.releasePreparation() },
            operation: { await model.select { Self.input } }) {
                XCTAssertTrue(model.preparing)
                model.removeSelection()
                XCTAssertFalse(model.preparing)
            }
        XCTAssertNil(model.selection)
        XCTAssertNil(model.preview)
        XCTAssertFalse(model.preparing)
        await model.select { Self.input }
        XCTAssertTrue(model.canSend)
    }

    func testHeldOperationTimesOutWhenEntryNeverArrivesAndReleasesWaiter() async throws {
        let gate = MediaInputGate()
        var completed = false
        var observedFailure: Error?
        let returned = expectation(description: "missing entry produces a timeout")
        let probe = Task {
            do {
                try await withHeldOperation("missing entry", timeout: .milliseconds(30), entered: { false },
                    release: { await gate.finish(Self.input) }, operation: { _ = await gate.read(); completed = true }) {
                        XCTFail("The missing entry must not reach the assertions")
                    }
            } catch { observedFailure = error }
            returned.fulfill()
        }
        // Independent XCTest deadline: even a regression in waitFor must not hang this test.
        let result = await XCTWaiter.fulfillment(of: [returned], timeout: 2)
        probe.cancel()
        await gate.finish(Self.input)
        XCTAssertEqual(result, .completed)
        guard result == .completed else { return }
        XCTAssertEqual(observedFailure as? MediaWaitFailure, .timedOut("missing entry: entered"))
        try await waitFor("released waiter after timeout") { completed }
        // Cleanup before entry must also be latched, not lose the release signal.
        let early = MediaInputGate()
        await early.finish(Self.input)
        var earlyCompleted = false
        let reader = Task { _ = await early.read(); earlyCompleted = true }
        defer { reader.cancel() }
        try await waitFor("entry after early release") { earlyCompleted }
    }

    func testOldPickerResultAfterReopeningIsDiscarded() async {
        let model = MessagingMediaComposerModel(runtime: MediaRuntimeDouble(), conversationID: UUID())
        let oldContext = model.contextGeneration
        model.suspend()
        await model.load()
        await model.select(expectedGeneration: oldContext) { Self.input }
        XCTAssertNil(model.selection)
    }

    private static func message(conversationID: UUID = UUID()) throws -> MessagingWireMessage {
        var message = MessagingWireMessage(id: UUID(), conversationID: conversationID, schoolID: UUID(),
            senderID: UUID(), acceptedAt: Date(), ciphertext: nil)
        message.meta.media = try .init(mediaID: UUID(), byteSize: 1, deleted: false)
        return message
    }

    private static let input = MessagingImportedMedia(data: Data([1]), suggestedName: "Synthetic.png")

    private enum MediaWaitFailure: Error, Equatable {
        case timedOut(String)
    }

    /// Conditions are short actor/property reads, never the suspended operation itself.
    private func waitFor(_ label: String, timeout: Duration = .seconds(2),
                         condition: @MainActor () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw MediaWaitFailure.timedOut(label)
    }

    /// No task group: on failure, cancel and release without joining a potentially stuck operation.
    private func withHeldOperation(_ label: String, timeout: Duration = .seconds(2),
        entered: @MainActor () async -> Bool, release: @MainActor () async -> Void,
        operation: @escaping @MainActor () async -> Void,
        whileHeld: @escaping @MainActor () async throws -> Void) async throws {
        var completed = false
        let task = Task { await operation(); completed = true }
        var checks: Task<Void, Never>?
        do {
            try await waitFor(label + ": entered", timeout: timeout, condition: entered)
            var checksCompleted = false
            var checksFailure: Error?
            checks = Task {
                do { try await whileHeld() } catch { checksFailure = error }
                checksCompleted = true
            }
            try await waitFor(label + ": assertions", timeout: timeout) { checksCompleted }
            if let checksFailure { throw checksFailure }
            await release()
            try await waitFor(label + ": completed", timeout: timeout) { completed }
        } catch {
            task.cancel()
            checks?.cancel()
            await release()
            throw error
        }
    }
}

private actor MediaInputGate {
    var waiting = false
    private var continuation: CheckedContinuation<MessagingImportedMedia, Never>?
    private var releasedInput: MessagingImportedMedia?
    func read() async -> MessagingImportedMedia {
        if let releasedInput { return releasedInput }
        return await withCheckedContinuation { continuation = $0; waiting = true }
    }
    func finish(_ input: MessagingImportedMedia) {
        releasedInput = input
        continuation?.resume(returning: input); continuation = nil
    }
}

private actor MediaRuntimeDouble: MessagingMediaRuntime {
    var enqueuedIDs: [UUID] = []
    var sentIDs: [UUID] = []
    var sending = false
    var opening = false
    var preparing = false
    private var stored: [MessagingMediaPendingSnapshot] = []
    private var storageFailure = false
    private var confirmation = false
    private var cleanup = false
    private var held = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var openContinuations: [CheckedContinuation<Void, Never>] = []
    private var openHeld = false
    private var preparationHeld = false
    private var preparationContinuations: [CheckedContinuation<Void, Never>] = []
    func failStorage() { storageFailure = true }
    func allowStorage() { storageFailure = false }
    func confirmNext(cleanupPending: Bool = false) { confirmation = true; cleanup = cleanupPending }
    func holdSend() { held = true }
    func releaseSend() {
        held = false
        let waiting = continuations; continuations = []
        for continuation in waiting { continuation.resume() }
    }
    func holdOpen() { openHeld = true }
    func releaseOpen() {
        openHeld = false
        let waiting = openContinuations; openContinuations = []
        for continuation in waiting { continuation.resume() }
    }
    func holdPreparation() { preparationHeld = true }
    func releasePreparation() {
        preparationHeld = false
        let waiting = preparationContinuations; preparationContinuations = []
        for continuation in waiting { continuation.resume() }
    }
    func prepare(_ data: Data, suggestedName: String) async throws -> MessagingPreparedMedia {
        preparing = true
        if preparationHeld { await withCheckedContinuation { preparationContinuations.append($0) } }
        preparing = false
        return MessagingPreparedMedia(data: data, mime: .png, name: suggestedName, width: 1, height: 1, thumbnail: nil)
    }
    func enqueue(_ prepared: MessagingPreparedMedia, clientMessageID: UUID, conversationID: UUID,
                 caption: String?, mentionPersonIDs: [UUID], replyToMessageID: UUID?) async throws -> MessagingMediaPendingSnapshot {
        enqueuedIDs.append(clientMessageID)
        if storageFailure { throw MessagingMediaRuntimeFailure.protectionUnavailable }
        let item = MessagingMediaPendingSnapshot(clientMessageID: clientMessageID, mediaID: UUID(),
            conversationID: conversationID, caption: caption, name: prepared.name, mime: prepared.mime,
            byteSize: prepared.data.count, createdAt: Date())
        stored.append(item)
        return item
    }
    func pending(conversationID: UUID) async throws -> [MessagingMediaPendingSnapshot] {
        if storageFailure { throw MessagingMediaRuntimeFailure.protectionUnavailable }
        return stored.filter { $0.conversationID == conversationID }
    }
    func send(clientMessageID: UUID) async -> MessagingMediaDelivery {
        sentIDs.append(clientMessageID); sending = true
        if held { await withCheckedContinuation { continuations.append($0) } }
        sending = false
        guard confirmation, let item = stored.first(where: { $0.id == clientMessageID }) else { return .pending(.resultUnknown) }
        return .confirmed(MessagingAcknowledgement(clientMessageID: clientMessageID, serverMessageID: UUID(),
            conversationID: item.conversationID, schoolID: UUID(), acceptedAt: Date(), senderID: UUID()), cleanupPending: cleanup)
    }
    func recomposeAfterMembersChanged(clientMessageID: UUID) async -> MessagingMediaDelivery { await send(clientMessageID: clientMessageID) }
    func open(_ message: MessagingWireMessage) async throws -> MessagingPreparedMedia {
        opening = true
        if openHeld { await withCheckedContinuation { openContinuations.append($0) } }
        opening = false
        return try await prepare(Data([1]), suggestedName: "Synthetic.png")
    }
    func invalidate() async {}
}
