import Foundation
import XCTest
@testable import Drivy

/// #475 : pièce choisie, légende = brouillon du champ principal, retrait, remplacement, anti double envoi.
/// Logique seule, sans vue ; NON EXÉCUTÉ localement (poste Windows), la preuve vient du runner Apple.
@MainActor
final class MessagingMediaComposerDraftTests: XCTestCase {
    private final class DraftBox { var text = "" }

    private static let photo = MessagingImportedMedia(data: Data([1]), suggestedName: "A.png")
    private static let other = MessagingImportedMedia(data: Data([1, 2]), suggestedName: "B.png")

    private func make(runtime: DraftRuntimeDouble = DraftRuntimeDouble(), draft: DraftBox? = nil) -> MessagingMediaComposerModel {
        let model = MessagingMediaComposerModel(runtime: runtime, conversationID: UUID())
        if let draft {
            model.draftChannel = MessagingCaptionChannel(read: { draft.text }, write: { draft.text = $0 })
        }
        return model
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<2000 where !condition() { try? await Task.sleep(for: .milliseconds(2)) }
    }

    func testSelectionKeepsExistingDraftAsCaptionWithoutDuplication() async {
        let draft = DraftBox(); draft.text = "Bonjour"
        let model = make(draft: draft)
        await model.select { Self.photo }
        XCTAssertNotNil(model.selection)
        XCTAssertEqual(model.caption, "Bonjour")
        XCTAssertEqual(draft.text, "Bonjour")
        model.caption = "Bonjour à tous"
        XCTAssertEqual(draft.text, "Bonjour à tous", "une seule valeur : le champ principal")
    }

    func testReplacementKeepsCaptionAndChangesTheIntentionID() async {
        let draft = DraftBox(); draft.text = "Ma légende"
        let model = make(draft: draft)
        await model.select { Self.photo }
        let first = model.selectionRevision
        await model.select { Self.other }
        XCTAssertEqual(model.selection?.name, "B.png")
        XCTAssertEqual(model.caption, "Ma légende")
        XCTAssertNotEqual(first, model.selectionRevision)
    }

    func testFailedReplacementKeepsPreviousSelectionAndCaption() async {
        let draft = DraftBox(); draft.text = "Légende"
        let model = make(draft: draft)
        await model.select { Self.photo }
        await model.select { throw MessagingMediaImportFailure.invalidSize }
        XCTAssertEqual(model.selection?.name, "A.png")
        XCTAssertEqual(model.caption, "Légende")
        XCTAssertNotNil(model.selectionError)
    }

    func testRemovalRestoresTheDraftAndSendsNothing() async {
        let runtime = DraftRuntimeDouble()
        let draft = DraftBox(); draft.text = "Brouillon utile"
        let model = make(runtime: runtime, draft: draft)
        await model.select { Self.photo }
        model.removeSelection()
        XCTAssertNil(model.selection)
        XCTAssertEqual(draft.text, "Brouillon utile")
        let calls = await runtime.enqueueCalls
        XCTAssertEqual(calls, 0)
    }

    func testRemovalWithoutChannelKeepsLocalCaption() async {
        let model = make()
        model.caption = "Locale"
        await model.select { Self.photo }
        model.removeSelection()
        XCTAssertEqual(model.caption, "Locale")
    }

    func testSendUsesTrimmedCaptionAndReplyThenClearsOnlyWhatWasSent() async {
        let runtime = DraftRuntimeDouble()
        let draft = DraftBox(); draft.text = "  Voici  "
        let model = make(runtime: runtime, draft: draft)
        let reply = UUID()
        await model.select { Self.photo }
        await model.sendSelected(replyTo: reply)
        let captions = await runtime.captions
        let replies = await runtime.replies
        XCTAssertEqual(captions, ["Voici"])
        XCTAssertEqual(replies, [reply])
        XCTAssertNil(model.selection)
        XCTAssertEqual(draft.text, "")
    }

    func testEmptyCaptionIsSentAsNil() async {
        let runtime = DraftRuntimeDouble()
        let model = make(runtime: runtime, draft: DraftBox())
        await model.select { Self.photo }
        await model.sendSelected(replyTo: nil)
        let captions = await runtime.captions
        XCTAssertEqual(captions, [nil])
    }

    func testTextTypedDuringEnqueueIsNotErased() async {
        let runtime = DraftRuntimeDouble()
        let draft = DraftBox(); draft.text = "Premier"
        let model = make(runtime: runtime, draft: draft)
        await model.select { Self.photo }
        await runtime.holdEnqueue()
        let task = Task { await model.sendSelected(replyTo: nil) }
        await waitUntil { model.sending }
        draft.text = "Premier puis suite"
        await runtime.releaseEnqueue()
        await task.value
        XCTAssertEqual(draft.text, "Premier puis suite")
    }

    func testNoDoubleSendWhileEnqueueIsInFlight() async {
        let runtime = DraftRuntimeDouble()
        let model = make(runtime: runtime, draft: DraftBox())
        await model.select { Self.photo }
        await runtime.holdEnqueue()
        let first = Task { await model.sendSelected(replyTo: nil) }
        await waitUntil { model.sending }
        XCTAssertFalse(model.canSend)
        await model.sendSelected(replyTo: nil)
        await runtime.releaseEnqueue()
        await first.value
        let calls = await runtime.enqueueCalls
        XCTAssertEqual(calls, 1)
    }

    func testStorageFailureKeepsSelectionAndCaptionAndAnnouncesNoSuccess() async {
        let runtime = DraftRuntimeDouble()
        await runtime.failStorage()
        let draft = DraftBox(); draft.text = "À garder"
        let model = make(runtime: runtime, draft: draft)
        await model.select { Self.photo }
        await model.sendSelected(replyTo: nil)
        XCTAssertNotNil(model.selection)
        XCTAssertEqual(draft.text, "À garder")
        XCTAssertNil(model.confirmation)
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.canSend)
    }

    func testLateImportAfterRemovalIsDiscardedAndCaptionStays() async {
        let draft = DraftBox(); draft.text = "Texte"
        let model = make(draft: draft)
        let gate = ImportGate()
        let task = Task { await model.select { await gate.read() } }
        await waitUntil { model.preparing }
        model.removeSelection()
        await gate.finish(Self.photo)
        await task.value
        XCTAssertNil(model.selection)
        XCTAssertEqual(draft.text, "Texte")
    }

    func testSuspendDoesNotWipeTheDraftOwnedByTheComposer() async {
        let draft = DraftBox(); draft.text = "Brouillon"
        let model = make(draft: draft)
        await model.select { Self.photo }
        model.suspend()
        XCTAssertNil(model.selection)
        XCTAssertEqual(draft.text, "Brouillon")
    }

    func testPickerCancellationIsNotAnErrorButRefusalAndInterruptionAreDistinct() async {
        let model = make()
        await model.select { throw CancellationError() }
        XCTAssertNil(model.error); XCTAssertNil(model.selectionError)
        await model.select { throw MessagingMediaImportFailure.invalidSize }
        let refused = model.selectionError
        XCTAssertEqual(refused, model.error)
        await model.select { throw CocoaError(.fileReadNoSuchFile) }
        let interrupted = model.selectionError
        XCTAssertNotNil(refused); XCTAssertNotNil(interrupted)
        XCTAssertNotEqual(refused, interrupted)
        XCTAssertTrue(interrupted?.hasPrefix("Fichier indisponible") == true)
    }

    func testAccessibilityLabelsAreShortAndFrench() {
        XCTAssertEqual(MessagingComposerAttachmentText.accessibilityLabel(name: "Cours.jpg", mime: .jpeg, byteSize: 10), "Photo, Cours.jpg")
        let pdf = MessagingComposerAttachmentText.accessibilityLabel(name: "Plan.pdf", mime: .pdf, byteSize: 2048)
        XCTAssertTrue(pdf.hasPrefix("Document PDF, Plan.pdf, "))
    }
}

private actor ImportGate {
    private var continuation: CheckedContinuation<MessagingImportedMedia, Never>?
    private var released: MessagingImportedMedia?
    func read() async -> MessagingImportedMedia {
        if let released { return released }
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ value: MessagingImportedMedia) {
        released = value
        continuation?.resume(returning: value); continuation = nil
    }
}

private actor DraftRuntimeDouble: MessagingMediaRuntime {
    private(set) var enqueueCalls = 0
    private(set) var captions: [String?] = []
    private(set) var replies: [UUID?] = []
    private var storageFailure = false
    private var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func failStorage() { storageFailure = true }
    func holdEnqueue() { held = true }
    func releaseEnqueue() {
        held = false
        let pending = waiting; waiting = []
        for continuation in pending { continuation.resume() }
    }
    func prepare(_ data: Data, suggestedName: String) async throws -> MessagingPreparedMedia {
        MessagingPreparedMedia(data: data, mime: .png, name: suggestedName, width: 1, height: 1, thumbnail: nil)
    }
    func enqueue(_ prepared: MessagingPreparedMedia, clientMessageID: UUID, conversationID: UUID,
                 caption: String?, mentionPersonIDs: [UUID], replyToMessageID: UUID?) async throws -> MessagingMediaPendingSnapshot {
        enqueueCalls += 1
        captions.append(caption); replies.append(replyToMessageID)
        if held { await withCheckedContinuation { waiting.append($0) } }
        if storageFailure { throw MessagingMediaRuntimeFailure.protectionUnavailable }
        return MessagingMediaPendingSnapshot(clientMessageID: clientMessageID, mediaID: UUID(),
            conversationID: conversationID, caption: caption, name: prepared.name, mime: prepared.mime,
            byteSize: prepared.data.count, createdAt: Date())
    }
    func pending(conversationID: UUID) async throws -> [MessagingMediaPendingSnapshot] { [] }
    func send(clientMessageID: UUID) async -> MessagingMediaDelivery { .pending(.resultUnknown) }
    func recomposeAfterMembersChanged(clientMessageID: UUID) async -> MessagingMediaDelivery { .pending(.resultUnknown) }
    func open(_ message: MessagingWireMessage) async throws -> MessagingPreparedMedia {
        try await prepare(Data([1]), suggestedName: "Synthetic.png")
    }
    func invalidate() async {}
}
