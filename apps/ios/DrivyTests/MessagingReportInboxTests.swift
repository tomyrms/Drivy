import XCTest
@testable import Drivy

/// Boîte des signalements (#77) : droit relu par le serveur, déchiffrement local, statut et conflits.
@MainActor
final class MessagingReportInboxTests: XCTestCase {
    private let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 3, apiBaseURL: "https://api.example.invalid")

    private func record(status: MessagingReportStatus = .open, messages: [UUID] = [UUID()]) -> MessagingReportRecord {
        MessagingReportRecord(id: UUID(), conversationID: UUID(), conversationKind: "PRIVATE", reporterID: UUID(),
            reporterName: "Léa Fixture", createdAt: Date(timeIntervalSince1970: 1_793_450_000), status: status,
            statusUpdatedAt: nil,
            items: messages.map { MessagingReportEnvelope(messageID: $0, senderID: UUID(), senderName: "Marc Fixture",
                sequence: 2, acceptedAt: Date(timeIntervalSince1970: 1_793_449_000),
                ciphertext: MessagingCiphertext(scheme: "synthetic", keyID: "fixture", payload: Data([1, 2, 3]))) },
            history: [])
    }

    private func model(_ moderation: ReportModerationStub, crypto: any MessagingCryptography = ReportDecryptionStub(),
                       current: MessagingScope? = nil) -> MessagingReportInboxModel {
        let value = current ?? scope
        return MessagingReportInboxModel(scope: scope, moderation: moderation, cryptography: crypto, currentScope: { value })
    }

    func testAdministratorSeesTheInboxAndItsOpenCount() async {
        let first = record(), second = record(status: .handled)
        let moderation = ReportModerationStub(pages: [MessagingReportPage(reports: [first, second], nextCursor: nil, openCount: 1)])
        let inbox = model(moderation)
        XCTAssertEqual(inbox.availability, .unknown)
        await inbox.probe()
        XCTAssertEqual(inbox.availability, .available)
        XCTAssertEqual(inbox.openCount, 1)
        XCTAssertEqual(inbox.reports.map(\.id), [first.id, second.id])
        // Une seule lecture pour savoir : un second probe ne relit rien.
        await inbox.probe()
        let reads = await moderation.reads
        XCTAssertEqual(reads, 1)
    }

    func testRefusedAccessHidesTheEntryWithoutAnError() async {
        let moderation = ReportModerationStub(pages: [], listFailure: .accessChanged)
        let inbox = model(moderation)
        await inbox.probe()
        XCTAssertEqual(inbox.availability, .hidden)
        XCTAssertNil(inbox.failure)
        XCTAssertTrue(inbox.reports.isEmpty)
    }

    func testAnUnavailableServiceNeverRevealsTheEntry() async {
        let moderation = ReportModerationStub(pages: [], listFailure: .unavailable)
        let inbox = model(moderation)
        await inbox.probe()
        XCTAssertEqual(inbox.availability, .unknown)
        XCTAssertEqual(inbox.failure, .unavailable)
    }

    func testMessagesAreDecryptedLocallyAndAnUnreadableOneIsSaidAsSuch() async {
        let readable = UUID(), unreadable = UUID()
        let report = record(messages: [readable, unreadable])
        let crypto = ReportDecryptionStub(texts: [readable: "Texte signalé"], failures: [unreadable: "D-NOKEY"])
        let inbox = model(ReportModerationStub(pages: [MessagingReportPage(reports: [report], nextCursor: nil, openCount: 1)]), crypto: crypto)
        await inbox.load()
        await inbox.open(report)
        let lines = inbox.lines[report.id] ?? []
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.first { $0.id == readable }?.text, "Texte signalé")
        XCTAssertNil(lines.first { $0.id == readable }?.unreadable)
        let missing = lines.first { $0.id == unreadable }
        XCTAssertNil(missing?.text)
        XCTAssertEqual(missing?.unreadable, MessagingDecryptionFailure.explanation(for: "D-NOKEY"))
        // Le message se déchiffre dans le salon de l'école, authentifié par le signalant.
        let seen = await crypto.seen
        XCTAssertEqual(Set(seen.map(\.conversationID)), [scope.schoolID])
        XCTAssertEqual(Set(seen.map(\.senderID)), [report.reporterID])
    }

    func testStatusChangeSendsTheStatusTheAdministratorSawAndUpdatesTheCount() async {
        let report = record()
        let moderation = ReportModerationStub(pages: [MessagingReportPage(reports: [report], nextCursor: nil, openCount: 1)])
        let inbox = model(moderation)
        await inbox.load()
        await inbox.setStatus(report, to: .handled)
        let calls = await moderation.statusCalls
        XCTAssertEqual(calls, [ReportModerationStub.StatusCall(report: report.id, status: .handled, expected: .open)])
        XCTAssertEqual(inbox.reports.first?.status, .handled)
        XCTAssertEqual(inbox.openCount, 0)
        XCTAssertNil(inbox.statusFailures[report.id])
    }

    func testStaleStatusReloadsTheListAndSaysSoInsteadOfOverwriting() async {
        let report = record()
        var changedElsewhere = report
        changedElsewhere.status = .dismissed
        let moderation = ReportModerationStub(
            pages: [MessagingReportPage(reports: [report], nextCursor: nil, openCount: 1),
                    MessagingReportPage(reports: [changedElsewhere], nextCursor: nil, openCount: 0)],
            statusFailure: .stateConflict)
        let inbox = model(moderation)
        await inbox.load()
        await inbox.setStatus(report, to: .handled)
        XCTAssertEqual(inbox.statusFailures[report.id], .stateConflict)
        XCTAssertEqual(inbox.reports.first?.status, .dismissed)
        XCTAssertEqual(inbox.openCount, 0)
    }

    func testRightRemovedDuringTheVisitHidesTheInboxAndKeepsNothing() async {
        let report = record()
        let moderation = ReportModerationStub(pages: [MessagingReportPage(reports: [report], nextCursor: nil, openCount: 1)],
                                              statusFailure: .accessChanged)
        let inbox = model(moderation)
        await inbox.load()
        await inbox.setStatus(report, to: .handled)
        XCTAssertEqual(inbox.availability, .hidden)
        XCTAssertTrue(inbox.reports.isEmpty)
        XCTAssertTrue(inbox.lines.isEmpty)
    }

    func testAnotherContextNeverFillsTheInbox() async {
        let moderation = ReportModerationStub(pages: [MessagingReportPage(reports: [record()], nextCursor: nil, openCount: 1)])
        let other = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: "https://api.example.invalid")
        let inbox = model(moderation, current: other)
        await inbox.load()
        XCTAssertTrue(inbox.reports.isEmpty)
        XCTAssertEqual(inbox.availability, .unknown)
    }
}

/// Un lot qui ne dépend pas de la crypto réelle : seul le contrat de scellement par défaut compte ici.
@MainActor
final class MessagingReportSealingDefaultTests: XCTestCase {
    func testASealingWithoutASharedSessionSealsEachContentInOrder() async throws {
        let sealing = OrderRecordingSealing()
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1)
        let sealed = try await sealing.sealForSchoolAdmins([Data("a".utf8), Data("b".utf8), Data("c".utf8)],
                                                           scope: scope, conversationID: UUID())
        XCTAssertEqual(sealed.map(\.keyID), ["a", "b", "c"])
    }
}

private struct OrderRecordingSealing: MessagingReportSealing {
    func sealForSchoolAdmins(_ plaintext: Data, scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        MessagingCiphertext(scheme: "TEST_ONLY", keyID: String(decoding: plaintext, as: UTF8.self), payload: plaintext)
    }
}

private actor ReportModerationStub: MessagingThreadActions {
    struct StatusCall: Equatable { let report: UUID; let status: MessagingReportStatus; let expected: MessagingReportStatus }
    private var pages: [MessagingReportPage]
    private let listFailure: MessagingFailure?
    private let statusFailure: MessagingFailure?
    private(set) var reads = 0
    private(set) var statusCalls: [StatusCall] = []

    init(pages: [MessagingReportPage], listFailure: MessagingFailure? = nil, statusFailure: MessagingFailure? = nil) {
        self.pages = pages; self.listFailure = listFailure; self.statusFailure = statusFailure
    }

    func reports(scope: MessagingScope, status: MessagingReportStatus?, before: UUID?) async throws -> MessagingReportPage {
        reads += 1
        if let listFailure { throw listFailure }
        guard !pages.isEmpty else { throw MessagingFailure.unavailable }
        return pages.count > 1 ? pages.removeFirst() : pages[0]
    }

    func setReportStatus(scope: MessagingScope, reportID: UUID, status: MessagingReportStatus,
                         expected: MessagingReportStatus) async throws -> MessagingReportStatusChange {
        statusCalls.append(StatusCall(report: reportID, status: status, expected: expected))
        if let statusFailure { throw statusFailure }
        return MessagingReportStatusChange(reportID: reportID, status: status, statusUpdatedAt: nil, history: [])
    }

    func delete(scope: MessagingScope, conversationID: UUID, messageID: UUID, for deletion: MessagingDeletionScope) async throws {}
    func setReaction(scope: MessagingScope, conversationID: UUID, messageID: UUID, emoji: String, active: Bool) async throws {}
    func setPinned(scope: MessagingScope, conversationID: UUID, messageID: UUID, pinned: Bool) async throws {}
    func vote(scope: MessagingScope, conversationID: UUID, messageID: UUID, optionIDs: [String]) async throws {}
    func closePoll(scope: MessagingScope, conversationID: UUID, messageID: UUID) async throws {}
    func setGroupAdmin(scope: MessagingScope, personID: UUID, admin: Bool) async throws {}
    func removeGeneralMember(scope: MessagingScope, personID: UUID) async throws {}
    func reinstateGeneralMember(scope: MessagingScope, personID: UUID) async throws {}
    func members(scope: MessagingScope) async throws -> [MessagingMember] { [] }
    func removedMembers(scope: MessagingScope) async throws -> [MessagingMember] { [] }
    func report(scope: MessagingScope, conversationID: UUID, clientReportID: UUID, items: [MessagingReportItem]) async throws {}
}

private actor ReportDecryptionStub: MessagingCryptography {
    struct Seen: Equatable { let messageID: UUID; let conversationID: UUID; let senderID: UUID }
    private let texts: [UUID: String]
    private let failures: [UUID: String]
    private(set) var seen: [Seen] = []

    init(texts: [UUID: String] = [:], failures: [UUID: String] = [:]) { self.texts = texts; self.failures = failures }

    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { true }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        throw MessagingFailure.protectionUnavailable
    }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data {
        throw MessagingFailure.protectionUnavailable
    }
    func decrypt(_ message: MessagingWireMessage, scope: MessagingScope) async throws -> Data {
        seen.append(Seen(messageID: message.id, conversationID: message.conversationID, senderID: message.senderID))
        if let code = failures[message.id] { throw MessagingDecryptionFailure(code: code) }
        return Data((texts[message.id] ?? "").utf8)
    }
}
