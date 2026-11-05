import CryptoKit
import Foundation
import Security
import UIKit
import XCTest
@testable import Drivy

/// Vocabulaire fermé des étapes du parcours média : aucun identifiant, nom, hash, URL,
/// jeton ni contenu n'est imprimé par ce test, même sur échec.
private enum MediaRelayStage {
    static let configuration = "CONFIGURATION"
    static let readiness = "READINESS"
    static let conversation = "CONVERSATION"
    static let readyA = "READY-A"
    static let readyB = "READY-B"
    static let image = "IMAGE"
    static let pdf = "PDF"
    static let reopen = "REOPEN"
    static let lost = "LOST-RESPONSE"
    static let resend = "RESEND"
    static let receive = "RECEIVE"
    static let deletion = "DELETION"
    static let crossSchool = "CROSS-SCHOOL"
}

private struct MediaRelayReadiness {
    static let fixture = "drivy-messaging-media-v1"
    static let legacyFixture = "drivy-messaging-relay-v1"

    let school: UUID
    let instructor: UUID
    let learner: UUID
    let foreignSchool: UUID
    let foreign: UUID
}

/// Échec de readiness : statut borné et nom fermé du champ divergent, jamais sa valeur.
private func mediaReadinessMismatch(status: Int, data: Data, _ expected: MediaRelayReadiness) -> String? {
    let boundedStatus = (100...599).contains(status) ? status : 0
    guard let raw = try? JSONSerialization.jsonObject(with: data), let object = raw as? [String: Any] else {
        return "statut=\(boundedStatus) champ=type"
    }
    guard (object["fixture"] as? String) == MediaRelayReadiness.legacyFixture,
          (object["ready"] as? Bool) == true else {
        return "statut=\(boundedStatus) champ=fixture"
    }
    guard let media = object["media"] as? [String: Any] else {
        return "statut=\(boundedStatus) champ=media"
    }
    let fields: [(String, String, String)] = [
        ("fixture", media["fixture"] as? String ?? "", MediaRelayReadiness.fixture),
        ("schoolId", media["schoolId"] as? String ?? "", expected.school.uuidString.lowercased()),
        ("instructorId", media["instructorId"] as? String ?? "", expected.instructor.uuidString.lowercased()),
        ("learnerId", media["learnerId"] as? String ?? "", expected.learner.uuidString.lowercased()),
        ("foreignSchoolId", media["foreignSchoolId"] as? String ?? "", expected.foreignSchool.uuidString.lowercased()),
        ("foreignId", media["foreignId"] as? String ?? "", expected.foreign.uuidString.lowercased())
    ]
    for (field, actual, value) in fields where actual != value {
        return "statut=\(boundedStatus) champ=media.\(field)"
    }
    return boundedStatus == 200 ? nil : "statut=\(boundedStatus)"
}

/// Traduction des refus en catégories fermées : aucun message brut ne sort du test.
private func mediaFailureLabel(_ error: any Error) -> String {
    if let failure = error as? MessagingMediaRuntimeFailure {
        switch failure {
        case .unavailable: return "RUNTIME-UNAVAILABLE"
        case .contextChanged: return "RUNTIME-CONTEXT"
        case .accessChanged: return "RUNTIME-ACCESS"
        case .protectionUnavailable: return "RUNTIME-PROTECTION"
        case .invalidContent: return "RUNTIME-CONTENT"
        case .invalidSize: return "RUNTIME-SIZE"
        case .invalidFormat: return "RUNTIME-FORMAT"
        case .unreadable: return "RUNTIME-READ"
        case .lockedPDF: return "RUNTIME-PDF"
        case .integrity: return "RUNTIME-INTEGRITY"
        case .removed: return "RUNTIME-REMOVED"
        case .membersChanged: return "RUNTIME-MEMBERS"
        case .alreadyInFlight: return "RUNTIME-IN-FLIGHT"
        case .resultUnknown: return "RUNTIME-UNKNOWN"
        }
    }
    if let failure = error as? MessagingMediaTransportFailure {
        switch failure {
        case .invalidIntent: return "TRANSPORT-INTENT"
        case .contextChanged: return "TRANSPORT-CONTEXT"
        case .accessChanged: return "TRANSPORT-ACCESS"
        case .deviceRequired: return "TRANSPORT-DEVICE"
        case .notFound: return "TRANSPORT-NOT-FOUND"
        case .purged: return "TRANSPORT-PURGED"
        case .alreadyAttached: return "TRANSPORT-ATTACHED"
        case .intentConflict: return "TRANSPORT-INTENT-CONFLICT"
        case .sizeConflict: return "TRANSPORT-SIZE"
        case .stateConflict: return "TRANSPORT-STATE"
        case .unavailable: return "TRANSPORT-UNAVAILABLE"
        case .invalidResponse: return "TRANSPORT-RESPONSE"
        case .integrityMismatch: return "TRANSPORT-INTEGRITY"
        case .tooLarge: return "TRANSPORT-TOO-LARGE"
        }
    }
    if error is MessagingDecryptionFailure { return "DECRYPTION" }
    if error is MessagingMediaCryptographyFailure { return "CRYPTO" }
    if error is MessagingMediaPreparationFailure { return "PREPARATION" }
    if error is CancellationError { return "CANCELLED" }
    if error is MessagingFailure { return "MESSAGING" }
    return "OTHER"
}

/// Espace Keychain synthétique propre à cette exécution : jamais la clé d'un autre scénario.
private struct MediaQualificationKeychain: MessagingCryptoKeychain {
    let namespace: String
    private var fixtureService: String { "ch.drivy.qualification.media.\(namespace)" }

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

    /// Contrôle d'absence après nettoyage : seule la fixture de cette exécution est interrogée.
    func isAbsent() -> Bool {
        var result: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: fixtureService,
                                    kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitAll]
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecItemNotFound
    }
}

/// Nettoyage et contrôle d'absence des espaces Keychain de cette exécution uniquement.
private enum MediaQualificationKeychainSpace {
    static func remove(service: String, account: String) -> OSStatus {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }

    static func isAbsent(service: String, account: String) -> Bool {
        var result: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitAll]
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecItemNotFound
    }
}

/// File d'intentions média du test : service Keychain **dédié à l'exécution**, vraie Keychain
/// et attributs de production attendus (non synchronisée, lisible appareil déverrouillé
/// uniquement). Le service global du produit n'est ni lu, ni écrit, ni supprimé ici.
private struct MediaQualificationOutboxKeyStore: MessagingMediaOutboxKeyStore {
    let service: String
    let account: String

    func key(create: Bool) throws -> SymmetricKey {
        if let existing = try existingKey() { return existing }
        guard create else { throw MessagingFailure.protectionUnavailable }
        var bytes = Data(count: 32)
        let random = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, 32, base)
        }
        guard random == errSecSuccess else { throw MessagingFailure.protectionUnavailable }
        let insert: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: bytes
        ]
        let added = SecItemAdd(insert as CFDictionary, nil)
        if added == errSecDuplicateItem {
            guard let existing = try existingKey() else { throw MessagingFailure.protectionUnavailable }
            return existing
        }
        guard added == errSecSuccess else { throw MessagingFailure.protectionUnavailable }
        return SymmetricKey(data: bytes)
    }

    /// Une clé existante dont la classe d'accessibilité ou la synchronisation ne correspond
    /// pas à l'exigence échoue fermé : elle n'est ni utilisée, ni remplacée, ni élargie.
    private func existingKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let attributes = result as? [String: Any],
              let accessible = attributes[kSecAttrAccessible as String] as? String,
              accessible == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String),
              let bytes = attributes[kSecValueData as String] as? Data, bytes.count == 32 else {
            throw MessagingFailure.protectionUnavailable
        }
        return SymmetricKey(data: bytes)
    }
}

/// Panne de **remise** contrôlée, jamais une panne du serveur : le POST réel est exécuté
/// jusqu'à son accusé durable, puis exactement une réponse réussie est jetée. Aucun faux
/// accusé n'est inventé et aucun effet serveur n'est simulé.
private actor LostResponseMediaSender: MessagingMediaMessageSending {
    private let upstream: any MessagingMediaMessageSending
    private var discardNextSuccess = false
    private(set) var discarded = 0
    /// Enveloppes réellement transmises au serveur, dans l'ordre des POST émis.
    private(set) var transmitted: [MessagingCiphertext] = []

    init(upstream: any MessagingMediaMessageSending) { self.upstream = upstream }

    func armOneLostResponse() { discardNextSuccess = true }

    func sendMedia(scope: MessagingScope, pending: MessagingPending,
                   media: MessagingMediaMessageIntent) async throws -> MessagingAcknowledgement {
        transmitted.append(pending.ciphertext)
        let acknowledgement = try await upstream.sendMedia(scope: scope, pending: pending, media: media)
        if discardNextSuccess {
            discardNextSuccess = false
            discarded += 1
            // Réponse acceptée par le serveur mais perdue pour l'appelant : le coordinateur
            // doit laisser le résultat inconnu, jamais un refus définitif ni un succès.
            throw MessagingFailure.unavailable
        }
        return acknowledgement
    }
}

/// Parcours média réel : Swift → HTTPS jetable → Fastify → PostgreSQL → destinataire.
///
/// Le relais, la base et les certificats sont ceux du harnais de qualification existant
/// (`scripts/ios/relay-qualification.sh`) ; ce test ne démarre aucun service, ne contourne
/// ni TLS ni ATS, et échoue — jamais ne saute — quand `DRIVY_RELAY_QUALIFICATION_URL`
/// manque. Aucune primitive crypto, aucun transport et aucun téléchargement n'est doublé ;
/// seule la remise de **une** réponse est interrompue pour éprouver l'idempotence.
///
/// Les identités média sont synthétiques, dédiées et distinctes de celles du scénario texte :
/// elles vivent dans leur propre école et ne partagent ni compte, ni conversation, ni appareil.
/// Les deux appareils sont publiés **avant** le premier chiffrement émetteur, et chaque espace
/// Keychain (file, cache, chiffrement) porte un service propre à l'exécution, nettoyé et
/// contrôlé absent en fin de parcours — jamais le service global du produit.
///
/// Bornes : chaque échange réseau est borné par les délais URLSession du transport média
/// (20 s par requête, 30 s par ressource) et par la durée de vie bornée du relais jetable ;
/// aucune attente de condition sans échéance n'est utilisée.
@MainActor
final class MessagingMediaRealRelayTests: XCTestCase {
    private var stage = MediaRelayStage.configuration

    private func enter(_ next: String) { stage = next }

    func testRealRelayMediaJourney() async {
        do { try await exerciseRealRelay() }
        catch {
            XCTFail("Parcours média interrompu : étape=\(stage), catégorie=\(mediaFailureLabel(error)).")
        }
    }

    // MARK: Fixtures locales

    /// PNG synthétique 1×1 RGB, sans métadonnée personnelle.
    ///
    /// Même base64 que `scripts/messaging-media-relay-qualification.test.mjs`, où les CRC de
    /// chaque chunk et la décompression zlib du flux IDAT sont réellement vérifiés. Ces
    /// contrôles ne remplacent pas le décodage ImageIO de la future exécution Apple.
    private var tinyPNG: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mNQaFAAAAGEAMFfsCuZAAAAAElFTkSuQmCC")!
    }

    /// PDF synthétique rendu en mémoire : aucune page réelle, aucun fichier, aucun lien.
    private func syntheticPDF() -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 120))
        return renderer.pdfData { context in
            context.beginPage()
            ("FIXTURE PDF SYNTHETIQUE" as NSString)
                .draw(at: CGPoint(x: 12, y: 12), withAttributes: nil)
        }
    }

    private let mediaSchool = UUID(uuidString: "1a000000-0000-4000-8000-000000000097")!
    private let mediaForeignSchool = UUID(uuidString: "1a000000-0000-4000-8000-000000000098")!
    private let mediaInstructor = UUID(uuidString: "2a000000-0000-4000-8000-000000000097")!
    private let mediaLearner = UUID(uuidString: "2a000000-0000-4000-8000-000000000098")!
    private let mediaForeign = UUID(uuidString: "2a000000-0000-4000-8000-000000000099")!

    private var readiness: MediaRelayReadiness {
        MediaRelayReadiness(school: mediaSchool, instructor: mediaInstructor, learner: mediaLearner,
                            foreignSchool: mediaForeignSchool, foreign: mediaForeign)
    }

    // MARK: Parcours

    private func exerciseRealRelay() async throws {
        enter(MediaRelayStage.configuration)
        let configured = ProcessInfo.processInfo.environment["DRIVY_RELAY_QUALIFICATION_URL"]
        guard let configured, let base = URL(string: configured),
              base.scheme == "https", ["localhost", "127.0.0.1"].contains(base.host ?? ""),
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              base.path.isEmpty, let port = base.port, (1024...65535).contains(port) else {
            XCTFail("Relais HTTPS loopback isolé obligatoire, configuration de qualification absente ou invalide.")
            return
        }

        // 1. Readiness : prouve l'école média dédiée, sans changer les champs canoniques.
        enter(MediaRelayStage.readiness)
        let probe = try await SchoolURLSessionTransport()
            .send(URLRequest(url: base.appendingPathComponent("qualification/ready")))
        if let mismatch = mediaReadinessMismatch(status: probe.status, data: probe.data, readiness) {
            XCTFail("Le relais ne correspond pas aux fixtures média : \(mismatch).")
            return
        }

        let aScope = MessagingScope(accountID: mediaInstructor, schoolID: mediaSchool,
                                    accessEpoch: 1, apiBaseURL: base.absoluteString)
        let bScope = MessagingScope(accountID: mediaLearner, schoolID: mediaSchool,
                                    accessEpoch: 1, apiBaseURL: base.absoluteString)
        let aToken = "media-fixture-instructor"
        let bToken = "media-fixture-learner"
        let aHTTP = MessagingHTTPTransport(baseURL: base, token: { aToken }, invalidate: { _ in false },
                                           currentScope: { aScope })
        let bHTTP = MessagingHTTPTransport(baseURL: base, token: { bToken }, invalidate: { _ in false },
                                           currentScope: { bScope })
        let apiA = MessagingAPIClient(transport: aHTTP)
        let apiB = MessagingAPIClient(transport: bHTTP)

        enter(MediaRelayStage.conversation)
        // Conversation autorisée par les relations réelles (formation + affectation), pas par le test.
        let conversation = try await aHTTP.privateConversation(scope: aScope, peerID: mediaLearner)

        let run = UUID().uuidString
        let keychainA = MediaQualificationKeychain(namespace: "\(run).A")
        let keychainB = MediaQualificationKeychain(namespace: "\(run).B")
        let outboxServiceA = "ch.drivy.qualification.media.outbox.\(run).A"
        let outboxServiceB = "ch.drivy.qualification.media.outbox.\(run).B"
        let cacheServiceA = "ch.drivy.qualification.media.cache.\(run).A"
        let cacheServiceB = "ch.drivy.qualification.media.cache.\(run).B"
        // Comptes dédiés : le nettoyage porte exactement sur service+account créés ici, jamais
        // sur le service global du produit ni sur un espace d'application réel.
        let outboxAccount = "media-outbox-key"
        let cacheAccount = "cache-key"
        let outboxAStore = MediaQualificationOutboxKeyStore(service: outboxServiceA, account: outboxAccount)
        let outboxBStore = MediaQualificationOutboxKeyStore(service: outboxServiceB, account: outboxAccount)
        defer {
            keychainA.removeFixture(); keychainB.removeFixture()
            for (service, account) in [(outboxServiceA, outboxAccount), (outboxServiceB, outboxAccount),
                                       (cacheServiceA, cacheAccount), (cacheServiceB, cacheAccount)] {
                _ = MediaQualificationKeychainSpace.remove(service: service, account: account)
            }
        }

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("media-relay-\(run)", isDirectory: true)
        let rootA = root.appendingPathComponent("A", isDirectory: true)
        let rootB = root.appendingPathComponent("B", isDirectory: true)
        try fileManager.createDirectory(at: rootA, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rootB, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let aOutbox = try MessagingProtectedMediaOutbox(scope: aScope, root: rootA,
            keyStore: outboxAStore,
            fileSystem: SystemMediaOutboxFileSystem(), limits: .standard)
        let aCacheNamespace = MessagingMediaCacheKeychain(service: cacheServiceA, account: cacheAccount)
        let aCache = try MessagingProtectedMediaCache(scope: aScope, anchor: rootA,
            maximumScopeBytes: MessagingProtectedMediaCache.maximumScopeByteSize,
            keyProvider: { mayCreate in
                try MessagingProtectedMediaCache.keychainKey(mayCreate: mayCreate, namespace: aCacheNamespace)
            })
        let bOutbox = try MessagingProtectedMediaOutbox(scope: bScope, root: rootB,
            keyStore: outboxBStore,
            fileSystem: SystemMediaOutboxFileSystem(), limits: .standard)
        let bCacheNamespace = MessagingMediaCacheKeychain(service: cacheServiceB, account: cacheAccount)
        let bCache = try MessagingProtectedMediaCache(scope: bScope, anchor: rootB,
            maximumScopeBytes: MessagingProtectedMediaCache.maximumScopeByteSize,
            keyProvider: { mayCreate in
                try MessagingProtectedMediaCache.keychainKey(mayCreate: mayCreate, namespace: bCacheNamespace)
            })

        // Deux vraies machines Matrix, deux coffres et deux espaces Keychain distincts.
        let aVault = try MessagingCryptoVault(scope: aScope, root: rootA.appendingPathComponent("crypto"),
                                              keychain: keychainA)
        let bVault = try MessagingCryptoVault(scope: bScope, root: rootB.appendingPathComponent("crypto"),
                                              keychain: keychainB)
        let aCrypto = try MatrixMessagingCryptography(scope: aScope, relay: MessagingCryptoHTTPRelay(
            baseURL: base, token: { aToken }, invalidate: { _ in false }, currentScope: { aScope }), vault: aVault)
        let bCrypto = try MatrixMessagingCryptography(scope: bScope, relay: MessagingCryptoHTTPRelay(
            baseURL: base, token: { bToken }, invalidate: { _ in false }, currentScope: { bScope }), vault: bVault)

        enter(MediaRelayStage.readyA)
        guard await aCrypto.isAvailable(scope: aScope, conversationID: conversation) else {
            XCTFail("Publication des clés de l'émetteur impossible sur le relais média."); return
        }
        // Les transports média portent l'identifiant d'appareil réellement enregistré.
        let aFactory: MessagingMediaTransportFactory = {
            let deviceID = try await aCrypto.currentDeviceID(scope: aScope)
            return MessagingHTTPMediaTransport(baseURL: base, deviceID: deviceID, token: { aToken },
                                               invalidate: { _ in false }, currentScope: { aScope })
        }

        // Les DEUX appareils sont publiés avant le premier chiffrement émetteur : une session
        // Megolm ne couvre que les appareils connus au moment du partage, et ce parcours nominal
        // n'a ensuite aucune émission A capable de rattraper une inscription tardive. Le
        // scénario historique couvre séparément ce cas d'inscription tardive, sans hypothèse ici.
        enter(MediaRelayStage.readyB)
        guard await bCrypto.isAvailable(scope: bScope, conversationID: conversation) else {
            XCTFail("Publication des clés du destinataire impossible sur le relais média."); return
        }
        let bFactory: MessagingMediaTransportFactory = {
            let deviceID = try await bCrypto.currentDeviceID(scope: bScope)
            return MessagingHTTPMediaTransport(baseURL: base, deviceID: deviceID, token: { bToken },
                                               invalidate: { _ in false }, currentScope: { bScope })
        }
        let bMedia = MessagingMediaCoordinator(scope: bScope, preparer: MessagingMediaPreparer(),
            cryptography: AESCTRMediaCryptography(), outbox: bOutbox, cache: bCache,
            encryption: bCrypto, sending: apiB, transportFactory: bFactory, currentScope: { bScope })

        let lostSender = LostResponseMediaSender(upstream: apiA)
        let aMedia = MessagingMediaCoordinator(scope: aScope, preparer: MessagingMediaPreparer(),
            cryptography: AESCTRMediaCryptography(), outbox: aOutbox, cache: aCache,
            encryption: aCrypto, sending: lostSender, transportFactory: aFactory, currentScope: { aScope })

        // 2. Image synthétique : préparation, mise en file, envoi, reçu serveur.
        enter(MediaRelayStage.image)
        let image = try await aMedia.prepare(tinyPNG, suggestedName: "fixture-image.png")
        XCTAssertEqual(image.data, tinyPNG, "L'original image reste octet pour octet.")
        XCTAssertEqual(image.mime, .png)
        XCTAssertNotNil(image.thumbnail, "La miniature locale est produite en mémoire.")
        let imageClientID = UUID()
        let imageSnapshot = try await aMedia.enqueue(image, clientMessageID: imageClientID,
            conversationID: conversation, caption: nil, mentionPersonIDs: [], replyToMessageID: nil)
        XCTAssertNil(imageSnapshot.caption)
        let imageDelivery = await aMedia.send(clientMessageID: imageClientID)
        guard case .confirmed(let imageAck, let imageCleanupPending) = imageDelivery else {
            if case .pending(let failure) = imageDelivery {
                XCTFail("Envoi image non confirmé : catégorie=\(mediaFailureLabel(failure)).")
            }
            return
        }
        XCTAssertFalse(imageCleanupPending, "Le nettoyage local doit être prouvé après un reçu valide.")
        XCTAssertEqual(imageAck.senderID, mediaInstructor)
        XCTAssertEqual(imageAck.conversationID, conversation)

        // 3. PDF synthétique : mise en file puis réouverture du coffre média et du coordinateur.
        enter(MediaRelayStage.pdf)
        let pdfData = syntheticPDF()
        let pdfCaption = "Légende média synthétique"
        let pdf = try await aMedia.prepare(pdfData, suggestedName: "fixture-document.pdf")
        XCTAssertEqual(pdf.mime, .pdf)
        XCTAssertNil(pdf.width)
        let pdfClientID = UUID()
        let pdfSnapshot = try await aMedia.enqueue(pdf, clientMessageID: pdfClientID,
            conversationID: conversation, caption: pdfCaption, mentionPersonIDs: [], replyToMessageID: nil)

        let entriesBefore = try await aOutbox.entries(scope: aScope)
        let durableBefore = try XCTUnwrap(entriesBefore.first { $0.mediaID == pdfSnapshot.mediaID })
        XCTAssertEqual(durableBefore.sealed.ciphertext.count, pdfSnapshot.byteSize)

        enter(MediaRelayStage.reopen)
        // Nouveaux objets sur les mêmes racines et les mêmes espaces Keychain : le coffre média
        // se rouvre, sans recréer d'identifiant ni de sceau. La machine Megolm reste la même
        // instance (deux écrivains sur le même magasin scellé ne sont pas ouverts en parallèle).
        let reopenedOutbox = try MessagingProtectedMediaOutbox(scope: aScope, root: rootA,
            keyStore: outboxAStore,
            fileSystem: SystemMediaOutboxFileSystem(), limits: .standard)
        let reopenedCache = try MessagingProtectedMediaCache(scope: aScope, anchor: rootA,
            maximumScopeBytes: MessagingProtectedMediaCache.maximumScopeByteSize,
            keyProvider: { mayCreate in
                try MessagingProtectedMediaCache.keychainKey(mayCreate: mayCreate, namespace: aCacheNamespace)
            })
        let reopenedMedia = MessagingMediaCoordinator(scope: aScope, preparer: MessagingMediaPreparer(),
            cryptography: AESCTRMediaCryptography(), outbox: reopenedOutbox, cache: reopenedCache,
            encryption: aCrypto, sending: lostSender, transportFactory: aFactory, currentScope: { aScope })
        let reopenedPending = try await reopenedMedia.pending(conversationID: conversation)
        let reopenedSnapshot = try XCTUnwrap(reopenedPending.first { $0.clientMessageID == pdfClientID })
        XCTAssertEqual(reopenedSnapshot.mediaID, pdfSnapshot.mediaID, "Le mediaID ne change pas à la réouverture.")
        XCTAssertEqual(reopenedSnapshot.byteSize, pdfSnapshot.byteSize)
        let entriesReopened = try await reopenedOutbox.entries(scope: aScope)
        let durableReopened = try XCTUnwrap(entriesReopened.first { $0.mediaID == pdfSnapshot.mediaID })
        XCTAssertTrue(durableReopened.sealed == durableBefore.sealed, "Le sceau et ses octets sont identiques.")
        XCTAssertTrue(durableReopened.messageCiphertext == durableBefore.messageCiphertext,
                      "L'enveloppe Megolm durable n'est pas réémise à la réouverture.")

        // 4. Réponse perdue après un POST réellement accepté : renvoi idempotent.
        enter(MediaRelayStage.lost)
        await lostSender.armOneLostResponse()
        let lostDelivery = await reopenedMedia.send(clientMessageID: pdfClientID)
        guard case .pending(let lostFailure) = lostDelivery else {
            XCTFail("Une réponse perdue ne doit jamais être annoncée comme un succès."); return
        }
        XCTAssertEqual(lostFailure, .resultUnknown, "Une réponse perdue laisse le résultat inconnu, jamais un refus définitif.")
        let discarded = await lostSender.discarded
        XCTAssertEqual(discarded, 1, "Exactement une réponse réussie est jetée.")

        let afterLoss = try await apiA.messages(scope: aScope, conversationID: conversation, before: nil)
        let carryingAfterLoss = afterLoss.items.filter { $0.meta.media?.mediaID == pdfSnapshot.mediaID }
        guard carryingAfterLoss.count == 1, let firstServerID = carryingAfterLoss.first?.id else {
            XCTFail("Le POST réellement accepté doit laisser exactement un message serveur pour ce média.")
            return
        }
        // Enveloppe durable mesurée APRÈS la perte de réponse et AVANT toute reprise : c'est
        // elle que le renvoi doit réutiliser, sans réchiffrement.
        let entriesAfterLoss = try await reopenedOutbox.entries(scope: aScope)
        let envelopeAfterLoss = try XCTUnwrap(entriesAfterLoss
            .first { $0.mediaID == pdfSnapshot.mediaID }?.messageCiphertext)
        XCTAssertTrue(envelopeAfterLoss == durableBefore.messageCiphertext,
                      "La perte de réponse ne modifie pas l'enveloppe persistée.")

        enter(MediaRelayStage.resend)
        let resentDelivery = await reopenedMedia.send(clientMessageID: pdfClientID)
        guard case .confirmed(let pdfAck, let pdfCleanupPending) = resentDelivery else {
            if case .pending(let failure) = resentDelivery {
                XCTFail("Renvoi du PDF non confirmé : catégorie=\(mediaFailureLabel(failure)).")
            }
            return
        }
        XCTAssertFalse(pdfCleanupPending)
        XCTAssertEqual(pdfAck.serverMessageID, firstServerID, "Le renvoi retrouve le même message serveur.")
        let afterResend = try await apiA.messages(scope: aScope, conversationID: conversation, before: nil)
        XCTAssertEqual(afterResend.items.filter { $0.meta.media?.mediaID == pdfSnapshot.mediaID }.count, 1,
                       "Un seul message serveur porte ce média après le renvoi.")
        // Enveloppes réellement transmises par les deux POST du décorateur transparent.
        let transmitted = await lostSender.transmitted
        XCTAssertEqual(transmitted.count, 2, "Deux POST réels ont été émis : perdu puis renvoyé.")
        XCTAssertTrue(transmitted.first == durableBefore.messageCiphertext
                      && transmitted.last == durableBefore.messageCiphertext,
                      "Les deux émissions portent l'enveloppe persistée, sans réchiffrement.")
        // Le reçu valide et le nettoyage prouvé ont retiré l'intention de la file.
        let entriesAfterResend = try await reopenedOutbox.entries(scope: aScope)
        XCTAssertTrue(entriesAfterResend.filter { $0.mediaID == pdfSnapshot.mediaID }.isEmpty,
                      "Une intention confirmée et nettoyée ne reste pas dans la file.")

        // 5. Destinataire : relecture serveur, provenance v3, mediaRef, ouverture réelle.
        enter(MediaRelayStage.receive)
        let page = try await apiB.messages(scope: bScope, conversationID: conversation, before: nil)
        guard let imageMessage = page.items.first(where: { $0.id == imageAck.serverMessageID }),
              let pdfMessage = page.items.first(where: { $0.id == pdfAck.serverMessageID }) else {
            XCTFail("Le destinataire doit relire les deux messages acceptés via PostgreSQL."); return
        }
        XCTAssertEqual(imageMessage.senderID, mediaInstructor)
        XCTAssertEqual(imageMessage.meta.media?.mediaID, imageSnapshot.mediaID)
        XCTAssertEqual(imageMessage.meta.media?.byteSize, imageSnapshot.byteSize)
        XCTAssertEqual(imageMessage.meta.media?.deleted, false)
        XCTAssertEqual(pdfMessage.meta.media?.mediaID, pdfSnapshot.mediaID)
        XCTAssertEqual(pdfMessage.meta.media?.byteSize, pdfSnapshot.byteSize)

        // Provenance explicite : contenu Matrix v3, jamais un repli heuristique.
        for (message, expectedID) in [(imageMessage, imageSnapshot.mediaID), (pdfMessage, pdfSnapshot.mediaID)] {
            let decrypted = try await bCrypto.decryptContent(message, scope: bScope)
            XCTAssertEqual(decrypted.provenance, .matrixContent, "La provenance doit être Matrix explicite.")
            let content = try XCTUnwrap(MessagingPlainContent.decodeMatrixContent(decrypted.bytes))
            XCTAssertEqual(content.media?.id, expectedID)
        }
        let decryptedPDF = try await bCrypto.decryptContent(pdfMessage, scope: bScope)
        let pdfContent = try XCTUnwrap(MessagingPlainContent.decodeMatrixContent(decryptedPDF.bytes))
        XCTAssertEqual(pdfContent.text, pdfCaption, "La légende vient du contenu chiffré, pas du serveur.")
        XCTAssertEqual(pdfContent.media?.name, "fixture-document.pdf")
        XCTAssertEqual(pdfContent.media?.mime, .pdf)
        XCTAssertEqual(pdfContent.media?.size, pdfSnapshot.byteSize)

        let receivedImage = try await bMedia.open(imageMessage)
        XCTAssertEqual(receivedImage.data, tinyPNG, "Le destinataire retrouve l'original image exact.")
        XCTAssertEqual(receivedImage.mime, .png)
        XCTAssertEqual(receivedImage.name, "fixture-image.png")
        XCTAssertEqual(receivedImage.width, image.width)
        XCTAssertEqual(receivedImage.height, image.height)

        let receivedPDF = try await bMedia.open(pdfMessage)
        XCTAssertEqual(receivedPDF.data, pdfData, "Le destinataire retrouve l'original PDF exact.")
        XCTAssertEqual(receivedPDF.mime, .pdf)
        XCTAssertEqual(receivedPDF.name, "fixture-document.pdf")
        XCTAssertNil(receivedPDF.width)

        // 6. Suppression pour tous : tombstone serveur, ouverture refusée, purge ciblée du cache.
        enter(MediaRelayStage.deletion)
        let cachedBeforeDeletion = try await bCache.data(mediaID: imageSnapshot.mediaID, scope: bScope)
        XCTAssertNotNil(cachedBeforeDeletion, "La pièce reçue a été mise en cache scellé après validation.")
        try await aHTTP.delete(scope: aScope, conversationID: conversation,
                               messageID: imageAck.serverMessageID, for: .everyone)
        let tombstonePage = try await apiB.messages(scope: bScope, conversationID: conversation, before: nil)
        guard let tombstone = tombstonePage.items.first(where: { $0.id == imageAck.serverMessageID }) else {
            XCTFail("Le destinataire doit relire le tombstone du message supprimé."); return
        }
        XCTAssertTrue(tombstone.meta.deletedForEveryone)
        XCTAssertNil(tombstone.ciphertext, "Aucune enveloppe n'est servie après suppression pour tous.")
        XCTAssertEqual(tombstone.meta.media?.deleted, true)
        do {
            _ = try await bMedia.open(tombstone)
            XCTFail("Un message supprimé ne doit jamais rendre son ancien contenu.")
        } catch {
            XCTAssertTrue(error as? MessagingMediaRuntimeFailure == .removed,
                          "Le refus vient du tombstone serveur.")
        }
        // Un ancien snapshot (objet d'avant suppression, référence non marquée) ne doit plus
        // rendre les octets non plus : le cache ne contourne jamais une suppression connue.
        do {
            _ = try await bMedia.open(imageMessage)
            XCTFail("Un ancien snapshot ne doit pas resservir un média supprimé.")
        } catch {
            XCTAssertTrue(error as? MessagingMediaRuntimeFailure == .removed,
                          "Le média purgé n'est plus servi, même depuis un snapshot antérieur.")
        }
        // Exigence du contrat corrigé (#97 correction1) : la suppression connue purge l'entrée
        // de cache ciblée. Cette attente peut rester rouge sur la base 62850171 et sera
        // qualifiée au candidat corrigé ; elle n'est pas abaissée pour autant.
        let cachedAfterDeletion = try await bCache.data(mediaID: imageSnapshot.mediaID, scope: bScope)
        XCTAssertNil(cachedAfterDeletion, "La purge ciblée après suppression retire l'entrée de cache.")
        let downloadAfterDeletion = MessagingHTTPMediaTransport(baseURL: base,
            deviceID: try await bCrypto.currentDeviceID(scope: bScope), token: { bToken },
            invalidate: { _ in false }, currentScope: { bScope })
        do {
            _ = try await downloadAfterDeletion.download(mediaID: imageSnapshot.mediaID, scope: bScope,
                                                         conversationID: conversation)
            XCTFail("Les octets purgés ne doivent plus être téléchargeables.")
        } catch {
            XCTAssertTrue(error as? MessagingMediaTransportFailure == .notFound,
                          "La purge serveur répond un refus uniforme.")
        }

        // 7. Droits inter-écoles : le même compte, hors de son école, est refusé par le serveur.
        enter(MediaRelayStage.crossSchool)
        let foreignScope = MessagingScope(accountID: mediaLearner, schoolID: mediaForeignSchool,
                                          accessEpoch: 1, apiBaseURL: base.absoluteString)
        let foreignTransport = MessagingHTTPMediaTransport(baseURL: base,
            deviceID: try await bCrypto.currentDeviceID(scope: bScope), token: { bToken },
            invalidate: { _ in false }, currentScope: { foreignScope })
        do {
            _ = try await foreignTransport.download(mediaID: pdfSnapshot.mediaID, scope: foreignScope,
                                                    conversationID: conversation)
            XCTFail("Un compte hors de l'école ne doit pas télécharger le média.")
        } catch {
            XCTAssertTrue(error as? MessagingMediaTransportFailure == .accessChanged,
                          "Le refus inter-écoles vient des droits serveur, sans élargissement.")
        }

        // 8. Nettoyage vérifié : seules les clés Keychain de cette exécution sont supprimées,
        // et leur absence est constatée. Le service global du produit n'est ni lu ni modifié.
        let outboxRemovals = [MediaQualificationKeychainSpace.remove(service: outboxServiceA, account: outboxAccount),
                              MediaQualificationKeychainSpace.remove(service: outboxServiceB, account: outboxAccount)]
        let cacheRemovals = [MediaQualificationKeychainSpace.remove(service: cacheServiceA, account: cacheAccount),
                             MediaQualificationKeychainSpace.remove(service: cacheServiceB, account: cacheAccount)]
        keychainA.removeFixture()
        keychainB.removeFixture()
        for status in outboxRemovals + cacheRemovals {
            XCTAssertTrue(status == errSecSuccess || status == errSecItemNotFound,
                          "Le nettoyage d'une clé de fixture réussit ou constate son absence.")
        }
        XCTAssertTrue(MediaQualificationKeychainSpace.isAbsent(service: outboxServiceA, account: outboxAccount))
        XCTAssertTrue(MediaQualificationKeychainSpace.isAbsent(service: outboxServiceB, account: outboxAccount))
        XCTAssertTrue(MediaQualificationKeychainSpace.isAbsent(service: cacheServiceA, account: cacheAccount))
        XCTAssertTrue(MediaQualificationKeychainSpace.isAbsent(service: cacheServiceB, account: cacheAccount))
        XCTAssertTrue(keychainA.isAbsent(), "L'espace Keychain chiffrement A est nettoyé.")
        XCTAssertTrue(keychainB.isAbsent(), "L'espace Keychain chiffrement B est nettoyé.")

        // La fixture média n'a jamais servi les identités canoniques du scénario texte.
        XCTAssertNotEqual(mediaSchool, UUID(uuidString: "10000000-0000-4000-8000-000000000001"))
        XCTAssertNotEqual(mediaLearner, UUID(uuidString: "20000000-0000-4000-8000-000000000003"))
    }
}
