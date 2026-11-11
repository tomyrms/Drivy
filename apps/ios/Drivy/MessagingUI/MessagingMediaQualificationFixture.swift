#if DEBUG && targetEnvironment(simulator)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Observation

/// Opt-in report boundary only. No file bytes, real encryption, identity or persistence proof.
@MainActor @Observable
final class MessagingReportQualificationWitness {
    var summary = "prepared=0;post=0;ack=0;removed=0;files=0;selection=-"
}

struct MessagingReportQualificationCrypto: MessagingCryptography, MessagingContentProvenanceDecryption {
    let fallback: any MessagingCryptography
    static let matrixScheme = "drivy.ui-fixture.report-matrix"

    static func sample(_ id: UUID) throws -> MessagingMediaContentV3? {
        let photoIDs = [MessagingQualificationIDs.message(1, 23), MessagingQualificationIDs.message(1, 25)]
        let pdfIDs = [MessagingQualificationIDs.message(1, 24), MessagingQualificationIDs.message(1, 26)]
        guard photoIDs.contains(id) || pdfIDs.contains(id),
              let media = try MessagingMediaQualificationSamples.attachment(
                MessagingQualificationIDs.message(1, photoIDs.contains(id) ? 23 : 24)) else { return nil }
        let caption: String? = id == photoIDs[0] ? "Photo de l’exercice fictif"
            : id == pdfIDs[1] ? "Consignes du cours fictif" : nil
        return try MessagingMediaContentV3(text: caption, media: media)
    }

    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { false }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        throw MessagingFailure.protectionUnavailable
    }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data {
        try await fallback.decrypt(ciphertext, scope: scope, conversationID: conversationID)
    }
    func decryptContent(_ message: MessagingWireMessage, scope: MessagingScope) async throws -> MessagingDecryptedContent {
        guard message.schoolID == scope.schoolID, let ciphertext = message.ciphertext else {
            throw MessagingFailure.protectionUnavailable
        }
        if ciphertext.scheme == Self.matrixScheme { return .matrixContent(ciphertext.payload) }
        guard ciphertext.scheme == MessagingQualificationIDs.ciphertextScheme else {
            throw MessagingFailure.protectionUnavailable
        }
        if let sample = try Self.sample(message.id) {
            return .matrixContent(try MessagingMediaContent.messageContent(sample, mentions: nil))
        }
        return .legacyBody(try await fallback.decrypt(message, scope: scope))
    }
}

/// In-memory substitute for controlled boundaries, while the real workspace orders prepare → HTTP → remove.
/// POST is refused unless its exact envelopes and selection have first been prepared. No durable-store claim.
actor MessagingReportQualificationBoundary: MessagingProtectedReports, MessagingReportSealing, MessagingTypedReportSealing {
    private let scope: MessagingScope
    private let witness: MessagingReportQualificationWitness
    private var pending: MessagingPendingReport?
    private var prepared = 0, posts = 0, acknowledgements = 0, removed = 0, files = 0
    private var selection = "-"

    init(scope: MessagingScope, witness: MessagingReportQualificationWitness) {
        self.scope = scope; self.witness = witness
    }
    func pendingReport(conversationID: UUID, scope: MessagingScope) throws -> MessagingPendingReport? {
        guard scope == self.scope else { throw MessagingFailure.contextChanged }
        return pending?.conversationID == conversationID ? pending : nil
    }
    func prepareReport(_ candidate: MessagingPendingReport, scope: MessagingScope) async throws -> MessagingPendingReport {
        guard scope == self.scope else { throw MessagingFailure.contextChanged }
        if let pending, pending.conversationID == candidate.conversationID, pending.messageIDs == candidate.messageIDs { return pending }
        pending = candidate; prepared += 1
        await publish()
        return candidate
    }
    func removeReport(conversationID: UUID, clientReportID: UUID, scope: MessagingScope) async throws {
        guard scope == self.scope else { throw MessagingFailure.contextChanged }
        if pending?.conversationID == conversationID, pending?.clientReportID == clientReportID {
            pending = nil; removed += 1
            await publish()
        }
    }
    func sealForSchoolAdmins(_ plaintext: Data, scope: MessagingScope, conversationID: UUID) throws -> MessagingCiphertext {
        guard scope == self.scope else { throw MessagingFailure.contextChanged }
        return MessagingCiphertext(scheme: MessagingQualificationIDs.ciphertextScheme, keyID: "fixture", payload: plaintext)
    }
    func sealReport(_ payloads: [MessagingReportPayload], scope: MessagingScope, conversationID: UUID) throws -> [MessagingCiphertext] {
        guard scope == self.scope else { throw MessagingFailure.contextChanged }
        return try payloads.map { payload in
            switch payload {
            case .legacy(let data):
                return try sealForSchoolAdmins(data, scope: scope, conversationID: conversationID)
            case .media(let media):
                return MessagingCiphertext(scheme: MessagingReportQualificationCrypto.matrixScheme, keyID: "fixture",
                    payload: try MessagingMediaContent.messageContent(media, mentions: nil))
            }
        }
    }
    func accept(_ body: Data?) async throws {
        struct Item: Decodable { let messageId: UUID; let ciphertext: MessagingCiphertext }
        struct Body: Decodable { let clientReportId: UUID; let conversationId: UUID; let items: [Item] }
        posts += 1
        await publish()
        guard let body, let request = try? JSONDecoder().decode(Body.self, from: body), let pending,
              request.clientReportId == pending.clientReportID, request.conversationId == pending.conversationID,
              request.items.map({ MessagingReportItem(messageID: $0.messageId, ciphertext: $0.ciphertext) }) == pending.items else {
            throw MessagingFailure.invalidResponse
        }
        selection = request.items.compactMap { Int($0.messageId.uuidString.suffix(12), radix: 16) }
            .sorted().map(String.init).joined(separator: ",")
        acknowledgements += 1
        await publish()
    }
    func recordFileRequest() async { files += 1; await publish() }
    private func publish() async {
        let summary = "prepared=\(prepared);post=\(posts);ack=\(acknowledgements);removed=\(removed);files=\(files);selection=\(selection)"
        await MainActor.run { witness.summary = summary }
    }
}

/// Synthetic bytes only, generated in memory. No file, identity, socket or persistence.
enum MessagingMediaQualificationSamples {
    private struct GenerationFailure: Error {}

    static func photo() throws -> MessagingImportedMedia {
        let width = 240, height = 160
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw GenerationFailure() }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 80, y: 40, width: 80, height: 80))
        guard let image = context.makeImage() else { throw GenerationFailure() }
        guard let bytes = CFDataCreateMutable(kCFAllocatorDefault, 0),
              let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)
        else { throw GenerationFailure() }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GenerationFailure() }
        return MessagingImportedMedia(data: try copied(bytes), suggestedName: "Photo synthétique.png")
    }

    static func pdf() throws -> MessagingImportedMedia {
        var bounds = CGRect(x: 0, y: 0, width: 320, height: 440)
        guard let bytes = CFDataCreateMutable(kCFAllocatorDefault, 0),
              let consumer = CGDataConsumer(data: bytes),
              let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { throw GenerationFailure() }
        for page in 0..<2 {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(bounds)
            context.setFillColor(CGColor(gray: 0.2, alpha: 1))
            context.fill(CGRect(x: 32, y: 330, width: 200, height: 20))
            context.fill(CGRect(x: 32, y: 280, width: CGFloat(100 + page * 60), height: 12))
            context.endPDFPage()
        }
        context.closePDF()
        return MessagingImportedMedia(data: try copied(bytes), suggestedName: "Document synthétique.pdf")
    }

    private static func copied(_ bytes: CFData) throws -> Data {
        guard let pointer = CFDataGetBytePtr(bytes) else { throw GenerationFailure() }
        return Data(bytes: pointer, count: CFDataGetLength(bytes))
    }

    static func received(_ id: UUID) throws -> MessagingImportedMedia? {
        if id == MessagingQualificationIDs.message(1, 23) { return try photo() }
        if id == MessagingQualificationIDs.message(1, 24) { return try pdf() }
        return nil
    }

    static func attachment(_ id: UUID) throws -> MessagingMediaAttachment? {
        guard let sample = try received(id) else { return nil }
        let prepared = try MessagingMediaPreparer().prepare(sample.data, suggestedName: sample.suggestedName)
        // Explicit synthetic metadata, never a real key or cryptographic proof.
        let info = MessagingMediaEncryptionInfo(key: Data(repeating: 1, count: 32),
            iv: Data(repeating: 0, count: 16), sha256: Data(repeating: 2, count: 32))
        return try MessagingMediaAttachment(id: id, size: sample.data.count, mime: prepared.mime,
            name: prepared.name, width: prepared.width, height: prepared.height, file: info)
    }
}

/// Used ONLY by the opt-in media fixture. The original decrypt-only crypto is unchanged.
struct MessagingMediaQualificationCrypto: MessagingCryptography, MessagingContentProvenanceDecryption {
    let fallback: any MessagingCryptography
    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { false }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        throw MessagingFailure.protectionUnavailable
    }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data {
        try await fallback.decrypt(ciphertext, scope: scope, conversationID: conversationID)
    }
    func decryptContent(_ message: MessagingWireMessage, scope: MessagingScope) async throws -> MessagingDecryptedContent {
        guard message.schoolID == scope.schoolID,
              message.ciphertext?.scheme == MessagingQualificationIDs.ciphertextScheme else { throw MessagingFailure.protectionUnavailable }
        if let media = try MessagingMediaQualificationSamples.attachment(message.id) {
            return .matrixContent(try MessagingMediaContent.messageContent(.init(text: nil, media: media), mentions: nil))
        }
        return .legacyBody(try await fallback.decrypt(message, scope: scope))
    }
}

actor MessagingMediaQualificationRuntime: MessagingMediaRuntime {
    private let scope: MessagingScope
    private let reportBoundary: MessagingReportQualificationBoundary?
    private let slow: Bool
    private var unknownOnce: Bool
    private var items: [UUID: MessagingMediaPendingSnapshot] = [:]
    init(scope: MessagingScope, arguments: [String], reportBoundary: MessagingReportQualificationBoundary? = nil) {
        self.scope = scope
        self.reportBoundary = reportBoundary
        slow = arguments.contains("-messaging-ui-media-slow")
        unknownOnce = arguments.contains("-messaging-ui-media-unknown-once")
    }
    func prepare(_ data: Data, suggestedName: String) async throws -> MessagingPreparedMedia {
        if slow { try await Task.sleep(for: .seconds(3)) }
        return try MessagingMediaPreparer().prepare(data, suggestedName: suggestedName)
    }
    func enqueue(_ prepared: MessagingPreparedMedia, clientMessageID: UUID, conversationID: UUID,
                 caption: String?, mentionPersonIDs: [UUID], replyToMessageID: UUID?) async throws -> MessagingMediaPendingSnapshot {
        if let item = items[clientMessageID] { return item }
        let item = MessagingMediaPendingSnapshot(clientMessageID: clientMessageID, mediaID: UUID(),
            conversationID: conversationID, caption: caption, name: prepared.name,
            mime: prepared.mime, byteSize: prepared.data.count, createdAt: Date())
        items[item.id] = item
        return item
    }
    func pending(conversationID: UUID) async throws -> [MessagingMediaPendingSnapshot] {
        items.values.filter { $0.conversationID == conversationID }.sorted { $0.createdAt < $1.createdAt }
    }
    func send(clientMessageID: UUID) async -> MessagingMediaDelivery {
        if slow { try? await Task.sleep(for: .seconds(2)) }
        if unknownOnce { unknownOnce = false; return .pending(.resultUnknown) }
        guard let item = items.removeValue(forKey: clientMessageID) else { return .pending(.removed) }
        return .confirmed(MessagingAcknowledgement(clientMessageID: clientMessageID, serverMessageID: UUID(),
            conversationID: item.conversationID, schoolID: scope.schoolID, acceptedAt: Date(), senderID: scope.accountID), cleanupPending: false)
    }
    func recomposeAfterMembersChanged(clientMessageID: UUID) async -> MessagingMediaDelivery { await send(clientMessageID: clientMessageID) }
    func open(_ message: MessagingWireMessage) async throws -> MessagingPreparedMedia {
        if let reportBoundary { await reportBoundary.recordFileRequest() }
        guard !message.meta.deletedForEveryone, message.meta.media?.deleted == false,
              let input = try MessagingMediaQualificationSamples.received(message.id) else { throw MessagingMediaRuntimeFailure.removed }
        return try await prepare(input.data, suggestedName: input.suggestedName)
    }
    func invalidate() async {}
}
#endif
