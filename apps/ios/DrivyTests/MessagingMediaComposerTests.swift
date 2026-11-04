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

    func testLatePreparationAfterLeavingContextIsDiscarded() async {
        let gate = MediaInputGate()
        let model = MessagingMediaComposerModel(runtime: MediaRuntimeDouble(), conversationID: UUID())
        let work = Task { await model.select { await gate.read() } }
        while !(await gate.waiting) { await Task.yield() }
        XCTAssertTrue(model.preparing)
        model.suspend()
        await gate.finish(Self.input)
        await work.value
        XCTAssertNil(model.selection)
        XCTAssertNil(model.preview)
        XCTAssertFalse(model.canSend)
    }

    func testDoubleGestureWhileSendingDoesNotEnqueueAgain() async {
        let runtime = MediaRuntimeDouble()
        await runtime.holdSend()
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: UUID())
        await model.select { Self.input }
        let first = Task { await model.sendSelected(replyTo: nil) }
        while !(await runtime.sending) { await Task.yield() }
        await model.sendSelected(replyTo: nil)
        XCTAssertTrue(model.sending)
        await runtime.releaseSend()
        await first.value
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
        let operation = Task { await model.open(message, stillVisible: { visible }) }
        while !(await runtime.opening) { await Task.yield() }
        visible = false
        await runtime.releaseOpen()
        await operation.value
        XCTAssertNil(model.preview)
        XCTAssertFalse(model.opening)
    }

    func testOldPickerResultAfterReopeningIsDiscarded() async {
        let model = MessagingMediaComposerModel(runtime: MediaRuntimeDouble(), conversationID: UUID())
        let oldContext = model.contextGeneration
        model.suspend()
        await model.load()
        await model.select(expectedGeneration: oldContext) { Self.input }
        XCTAssertNil(model.selection)
    }

    private static func message() throws -> MessagingWireMessage {
        var message = MessagingWireMessage(id: UUID(), conversationID: UUID(), schoolID: UUID(),
            senderID: UUID(), acceptedAt: Date(), ciphertext: nil)
        message.meta.media = try .init(mediaID: UUID(), byteSize: 1, deleted: false)
        return message
    }

    private static let input = MessagingImportedMedia(data: Data([1]), suggestedName: "Synthetic.png")
}

private actor MediaInputGate {
    var waiting = false
    private var continuation: CheckedContinuation<MessagingImportedMedia, Never>?
    func read() async -> MessagingImportedMedia {
        await withCheckedContinuation { continuation = $0; waiting = true }
    }
    func finish(_ input: MessagingImportedMedia) { continuation?.resume(returning: input); continuation = nil }
}

private actor MediaRuntimeDouble: MessagingMediaRuntime {
    var enqueuedIDs: [UUID] = []
    var sentIDs: [UUID] = []
    var sending = false
    var opening = false
    private var stored: [MessagingMediaPendingSnapshot] = []
    private var storageFailure = false
    private var confirmation = false
    private var cleanup = false
    private var held = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var openContinuation: CheckedContinuation<Void, Never>?
    private var openHeld = false
    func failStorage() { storageFailure = true }
    func allowStorage() { storageFailure = false }
    func confirmNext(cleanupPending: Bool = false) { confirmation = true; cleanup = cleanupPending }
    func holdSend() { held = true }
    func releaseSend() { continuation?.resume(); continuation = nil; held = false }
    func holdOpen() { openHeld = true }
    func releaseOpen() { openContinuation?.resume(); openContinuation = nil; openHeld = false }
    func prepare(_ data: Data, suggestedName: String) async throws -> MessagingPreparedMedia {
        MessagingPreparedMedia(data: data, mime: .png, name: suggestedName, width: 1, height: 1, thumbnail: nil)
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
        if held { await withCheckedContinuation { continuation = $0 } }
        sending = false
        guard confirmation, let item = stored.first(where: { $0.id == clientMessageID }) else { return .pending(.resultUnknown) }
        return .confirmed(MessagingAcknowledgement(clientMessageID: clientMessageID, serverMessageID: UUID(),
            conversationID: item.conversationID, schoolID: UUID(), acceptedAt: Date(), senderID: UUID()), cleanupPending: cleanup)
    }
    func recomposeAfterMembersChanged(clientMessageID: UUID) async -> MessagingMediaDelivery { await send(clientMessageID: clientMessageID) }
    func open(_ message: MessagingWireMessage) async throws -> MessagingPreparedMedia {
        opening = true
        if openHeld { await withCheckedContinuation { openContinuation = $0 } }
        opening = false
        return try await prepare(Data([1]), suggestedName: "Synthetic.png")
    }
    func invalidate() async {}
}
