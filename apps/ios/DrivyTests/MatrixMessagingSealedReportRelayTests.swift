import Foundation
import Security
import XCTest
@testable import Drivy

/// Signalement chiffré pour les administrateurs (#77), de bout en bout : SDK Matrix réel, HTTPS, Fastify, PostgreSQL.
/// Même relais jetable que `MatrixMessagingRelayIntegrationTests` ; une absence de relais est un échec, jamais un saut.
/// Classe distincte : le contrôle de preuve du relais exige exactement un cas dans la classe d'origine. Son nom la place
/// après elle, dont la précondition est qu'Alice n'ait encore publié aucune clé.
final class MatrixMessagingSealedReportRelayTests: XCTestCase {
    @MainActor private var stage = "CONFIGURATION"

    @MainActor
    func testSealedReportReachesAdministratorDevicesOnlyThroughTheRealRelay() async {
        do { try await exercise() }
        catch {
            // Vocabulaire fermé : le nom du cas d'échec ou le type de l'erreur, jamais sa description.
            let kind = (error as? MessagingFailure).map { "\($0)" } ?? String(describing: type(of: error))
            XCTFail("Relais interrompu : étape=\(stage), erreur=\(kind).")
        }
    }

    @MainActor
    private func exercise() async throws {
        let configured = ProcessInfo.processInfo.environment["DRIVY_RELAY_QUALIFICATION_URL"]
        guard let configured, let base = URL(string: configured),
              base.scheme == "https", ["localhost", "127.0.0.1"].contains(base.host ?? ""),
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              base.path.isEmpty, let port = base.port, (1024...65535).contains(port) else {
            XCTFail("Relais HTTPS loopback isolé obligatoire, configuration de qualification absente ou invalide.")
            return
        }
        let school = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let administrator = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
        let instructor = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
        let learner = UUID(uuidString: "20000000-0000-4000-8000-000000000003")!
        let adminScope = MessagingScope(accountID: administrator, schoolID: school, accessEpoch: 1, apiBaseURL: base.absoluteString)
        let aScope = MessagingScope(accountID: instructor, schoolID: school, accessEpoch: 1, apiBaseURL: base.absoluteString)
        let bScope = MessagingScope(accountID: learner, schoolID: school, accessEpoch: 1, apiBaseURL: base.absoluteString)
        let adminHTTP = MessagingHTTPTransport(baseURL: base, token: { "demo-admin" }, invalidate: { _ in false }, currentScope: { adminScope })
        let aHTTP = MessagingHTTPTransport(baseURL: base, token: { "demo-instructor" }, invalidate: { _ in false }, currentScope: { aScope })
        let bHTTP = MessagingHTTPTransport(baseURL: base, token: { "demo-alice" }, invalidate: { _ in false }, currentScope: { bScope })
        let adminRelay = MessagingCryptoHTTPRelay(baseURL: base, token: { "demo-admin" }, invalidate: { _ in false }, currentScope: { adminScope })
        let aRelay = MessagingCryptoHTTPRelay(baseURL: base, token: { "demo-instructor" }, invalidate: { _ in false }, currentScope: { aScope })
        let bRelay = MessagingCryptoHTTPRelay(baseURL: base, token: { "demo-alice" }, invalidate: { _ in false }, currentScope: { bScope })

        stage = "READINESS"
        let readiness = try await SchoolURLSessionTransport().send(URLRequest(url: base.appendingPathComponent("qualification/ready")))
        guard readiness.status == 200,
              let ready = try JSONSerialization.jsonObject(with: readiness.data) as? [String: Any],
              ready["fixture"] as? String == "drivy-messaging-relay-v1",
              ready["adminId"] as? String == administrator.uuidString.lowercased() else {
            XCTFail("Le relais ne correspond pas aux fixtures canoniques de qualification (administrateur absent).")
            return
        }

        stage = "VAULTS"
        let run = UUID().uuidString
        let keychains = ["admin", "A", "B"].map { SealedReportKeychain(namespace: "\(run).\($0)") }
        defer { keychains.forEach { $0.removeFixture() } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sealed-report-\(run)", isDirectory: true)
        let admin = try MatrixMessagingCryptography(scope: adminScope, relay: adminRelay,
            vault: MessagingCryptoVault(scope: adminScope, root: root.appendingPathComponent("admin"), keychain: keychains[0]))
        let a = try MatrixMessagingCryptography(scope: aScope, relay: aRelay,
            vault: MessagingCryptoVault(scope: aScope, root: root.appendingPathComponent("A"), keychain: keychains[1]))
        let b = try MatrixMessagingCryptography(scope: bScope, relay: bRelay,
            vault: MessagingCryptoVault(scope: bScope, root: root.appendingPathComponent("B"), keychain: keychains[2]))

        // Le moniteur écrit à l'élève : un vrai message chiffré, relu depuis PostgreSQL et déchiffré par l'élève.
        stage = "PRIVATE-MESSAGE"
        let conversation = try await aHTTP.privateConversation(scope: aScope, peerID: learner)
        let reportedText = "SYNTHETIC_REPORTED_MESSAGE_\(run)"
        let content = try MessagingPlainContent(text: reportedText).encoded()
        let aReady = await a.isAvailable(scope: aScope, conversationID: conversation)
        let bReady = await b.isAvailable(scope: bScope, conversationID: conversation)
        XCTAssertTrue(aReady)
        XCTAssertTrue(bReady)
        let encrypted = try await a.encrypt(content, mentions: [], scope: aScope, conversationID: conversation)
        let ack = try await aHTTP.send(scope: aScope, conversationID: conversation,
            body: MessagingSendDTO(clientMessageId: UUID(), ciphertext: encrypted, mentionPersonIds: []))
        let page = try await MessagingAPIClient(transport: bHTTP).messages(scope: bScope, conversationID: conversation, before: nil)
        guard let received = page.items.first(where: { $0.id == ack.serverMessageId }) else {
            XCTFail("L'élève doit relire le message du moniteur."); return
        }
        let clear = try await b.decrypt(received, scope: bScope)
        XCTAssertEqual(clear, content)

        // L'administrateur de l'école n'a encore aucun appareil : le signalement ne part pas, rien n'est dégradé.
        stage = "REPORT-WITHOUT-ADMIN-DEVICE"
        do {
            _ = try await b.sealForSchoolAdmins([clear], scope: bScope, conversationID: conversation)
            XCTFail("Aucun signalement ne part sans appareil d'administrateur.")
        } catch { XCTAssertEqual(error as? MessagingFailure, .noReportRecipient) }
        let before = try await adminHTTP.reports(scope: adminScope, status: nil, before: nil)
        XCTAssertTrue(before.reports.isEmpty)

        // L'administrateur ouvre Messages sur un appareil : ses clés sont publiées.
        stage = "ADMIN-DEVICE"
        let adminReady = await admin.isAvailable(scope: adminScope, conversationID: conversation)
        XCTAssertTrue(adminReady)

        stage = "SEAL-AND-POST"
        let sealed = try await b.sealForSchoolAdmins([clear], scope: bScope, conversationID: conversation)
        XCTAssertEqual(sealed.count, 1)
        XCTAssertNil(sealed[0].payload.range(of: Data(reportedText.utf8)), "Le transport ne doit pas contenir le texte signalé.")
        let reportID = UUID()
        let items = [MessagingReportItem(messageID: ack.serverMessageId, ciphertext: sealed[0])]
        try await bHTTP.report(scope: bScope, conversationID: conversation, clientReportID: reportID, items: items)
        // Reprise après réponse perdue : le même signalement n'en crée pas un second.
        try await bHTTP.report(scope: bScope, conversationID: conversation, clientReportID: reportID, items: items)

        stage = "ADMIN-LIST-AND-DECRYPT"
        let model = MessagingReportInboxModel(scope: adminScope, moderation: adminHTTP, cryptography: admin, currentScope: { adminScope })
        await model.load()
        XCTAssertEqual(model.availability, .available)
        XCTAssertEqual(model.reports.count, 1)
        guard let record = model.reports.first else { XCTFail("La boîte doit contenir le signalement."); return }
        XCTAssertEqual(record.reporterID, learner)
        XCTAssertEqual(record.status, .open)
        XCTAssertEqual(record.items.first?.messageID, ack.serverMessageId)
        XCTAssertEqual(record.items.first?.senderID, instructor)
        XCTAssertNil(record.items.first?.ciphertext.payload.range(of: Data(reportedText.utf8)))
        await model.open(record)
        let line = try XCTUnwrap(model.lines[record.id]?.first)
        XCTAssertEqual(line.text, reportedText, "L'administrateur doit déchiffrer le message signalé avec la clé reçue.")
        XCTAssertNil(line.unreadable)

        // Le signalement n'ouvre que le message choisi : la conversation privée reste fermée à l'administrateur.
        stage = "ADMIN-CANNOT-OPEN-CONVERSATION"
        do {
            _ = try await MessagingAPIClient(transport: adminHTTP).messages(scope: adminScope, conversationID: conversation, before: nil)
            XCTFail("L'administrateur ne doit pas lire la conversation privée.")
        } catch { XCTAssertEqual(error as? MessagingFailure, .conversationUnavailable) }

        // Un non-administrateur ne voit pas la boîte, et son appareil n'a pas la clé du signalement.
        stage = "NON-ADMIN-REFUSED"
        do {
            _ = try await aHTTP.reports(scope: aScope, status: nil, before: nil)
            XCTFail("Un moniteur n'est pas administrateur de cette école.")
        } catch { XCTAssertEqual(error as? MessagingFailure, .accessChanged) }
        do {
            _ = try await bHTTP.reports(scope: bScope, status: nil, before: nil)
            XCTFail("Le signalant ne lit pas la boîte des administrateurs.")
        } catch { XCTAssertEqual(error as? MessagingFailure, .accessChanged) }
        let asReported = MessagingWireMessage(id: ack.serverMessageId, conversationID: school, schoolID: school,
                                              senderID: learner, acceptedAt: Date(), ciphertext: sealed[0])
        do {
            _ = try await a.decrypt(asReported, scope: aScope)
            XCTFail("L'appareil du moniteur n'est pas destinataire du signalement.")
        } catch let failure as MessagingDecryptionFailure {
            XCTAssertEqual(failure.code, "D-NOKEY")
        } catch { XCTFail("Refus attendu avec un code de déchiffrement.") }

        // Traitement : le statut attendu est comparé côté serveur.
        stage = "STATUS"
        let handled = try await adminHTTP.setReportStatus(scope: adminScope, reportID: record.id, status: .handled, expected: .open)
        XCTAssertEqual(handled.status, .handled)
        XCTAssertEqual(handled.history.last?.from, .open)
        XCTAssertEqual(handled.history.last?.to, .handled)
        do {
            _ = try await adminHTTP.setReportStatus(scope: adminScope, reportID: record.id, status: .dismissed, expected: .open)
            XCTFail("Un statut attendu périmé doit être refusé.")
        } catch { XCTAssertEqual(error as? MessagingFailure, .stateConflict) }
        // Aucun contenu, clé ni jeton n'est affiché par ce test. Le simulateur est jetable.
    }
}

/// Trois appareils isolés dans le vrai Keychain du simulateur, comme dans le test d'origine.
private struct SealedReportKeychain: MessagingCryptoKeychain {
    let namespace: String
    private var fixtureService: String { "ch.drivy.qualification.sealed-report.\(namespace)" }
    func read(service: String, account: String) throws -> Data? {
        try MessagingSystemKeychain().read(service: fixtureService, account: account)
    }
    func add(service: String, account: String, data: Data) throws {
        try MessagingSystemKeychain().add(service: fixtureService, account: account, data: data)
    }
    func removeFixture() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: fixtureService] as CFDictionary)
    }
}
