import Foundation
import Testing
@testable import Drivy

/// #120 : parcours « rejoindre une école par lien » (`SchoolJoinWorkspace`).
/// Doubles synthétiques seulement : aucun réseau, aucun jeton réel, aucune donnée de personne.
@MainActor
struct SchoolJoinWorkspaceTests {
    // MARK: Aperçu du lien

    @Test func aValidLinkPreviewsTheSchoolWithoutGrantingAnything() async throws {
        let transport = JoinLinkTransport()
        let journal = JoinLinkJournalStub()
        let token = JoinLinkToken(subject: "synthetic-learner")
        let model = SchoolJoinWorkspace(client: JoinLinkFixture.client(transport, token),
                                        link: JoinLinkFixture.link, journal: journal)

        await model.load()
        #expect(model.isReady && model.canPreview)
        #expect(model.preview == nil && model.record == nil && model.member == nil)

        await model.inspect()
        #expect(model.preview == JoinLinkFixture.preview)
        #expect(model.link.isEmpty)
        // Un aperçu n'est ni une adhésion ni une écriture : rien au journal, aucun membre.
        #expect(journal.records.isEmpty)
        #expect(journal.current(JoinLinkFixture.principal) == nil)
        #expect(model.record == nil && model.member == nil)
        #expect(!model.isPending && !model.isConfirmed)
        // La notice doit être lue explicitement avant d'accepter ; le lien déjà consommé ne se relit pas.
        #expect(!model.canAccept)
        model.acknowledgesNotice = true
        #expect(model.canAccept && !model.canPreview)

        let bearer = try await token.accessToken()
        let requests = await transport.recorded()
        #expect(requests.count == 1)
        let preview = try #require(requests.first)
        #expect(preview.url?.path == "/v1/invitations/preview")
        #expect(preview.httpMethod == "POST")
        #expect(preview.value(forHTTPHeaderField: "Authorization") == "Bearer " + bearer)
        #expect(try JSONDecoder().decode([String: String].self, from: try #require(preview.httpBody))
            == ["token": JoinLinkFixture.token])
    }

    @Test func anExpiredRevokedOrUsedLinkIsExplainedAndStaysRetryable() async throws {
        let cases: [(code: String, failure: SchoolJoinFailure)] = [
            ("INVITATION_EXPIRED", .expired),
            ("INVITATION_REVOKED", .revoked),
            ("INVITATION_USED", .used)]
        for item in cases {
            let transport = JoinLinkTransport()
            await transport.setPreviewProblem(410, code: item.code)
            let journal = JoinLinkJournalStub()
            let model = SchoolJoinWorkspace(client: JoinLinkFixture.client(transport, JoinLinkToken(subject: "synthetic-learner")),
                                            link: JoinLinkFixture.link, journal: journal)
            await model.load()
            await model.inspect()
            #expect(model.preview == nil && model.member == nil)
            #expect(!model.isPending && !model.isConfirmed)
            #expect(model.errorMessage == item.failure.errorDescription)
            // Un lien refusé n'écrit rien, n'accepte rien, et reste relisible (« Continuer » à nouveau).
            #expect(journal.records.isEmpty)
            #expect(await transport.acceptCalls() == 0)
            #expect(model.canPreview && !model.canAccept)
        }
    }

    // MARK: Acceptation

    @Test func acceptingStoresTheIntentionBeforeItIsSentAndGrantsNothingYet() async throws {
        let transport = JoinLinkTransport()
        let journal = JoinLinkJournalStub()
        let model = SchoolJoinWorkspace(client: JoinLinkFixture.client(transport, JoinLinkToken(subject: "synthetic-learner")),
                                        link: JoinLinkFixture.link, journal: journal)
        await model.load()
        await model.inspect()
        model.acknowledgesNotice = true

        // L'envoi est retenu : on observe l'état exact au moment où la requête part.
        await transport.holdAccept()
        let sending = Task { await model.accept() }
        #expect(await until { await transport.acceptCalls() == 1 })

        // L'intention est déjà au journal, avec l'opération qui part réellement.
        let stored = try #require(journal.records.last)
        #expect(stored.receipt == nil && stored.body != nil)
        #expect(journal.current(stored.principal) == stored)
        let requests = await transport.recorded()
        let accept = try #require(requests.first { $0.url?.path == "/v1/invitations/accept" })
        #expect(accept.value(forHTTPHeaderField: "Idempotency-Key") == stored.operationID.uuidString)
        let sent = try JSONDecoder().decode(SchoolJoinBody.self, from: try #require(accept.httpBody))
        let saved = try JSONDecoder().decode(SchoolJoinBody.self, from: try #require(stored.body))
        #expect(sent == saved)
        #expect(sent.token == JoinLinkFixture.token)
        // Une demande partie n'est pas une adhésion : pas de reçu, pas de membre, pas d'accès.
        #expect(model.isBusy)
        #expect(!model.isConfirmed && model.member == nil)

        await transport.releaseAccept()
        await sending.value
        #expect(model.isConfirmed)
        #expect(model.member?.membershipId == JoinLinkFixture.membershipID)
        #expect(journal.current(stored.principal)?.receipt?.resourceId == JoinLinkFixture.membershipID)
    }

    @Test func aLostAnswerIsVerifiedWithTheSameOperationAndOneMembership() async throws {
        let transport = JoinLinkTransport()
        await transport.setAcceptFailure(true)
        let journal = JoinLinkJournalStub()
        let token = JoinLinkToken(subject: "synthetic-learner")
        let model = SchoolJoinWorkspace(client: JoinLinkFixture.client(transport, token),
                                        link: JoinLinkFixture.link, journal: journal)
        await model.load()
        await model.inspect()
        model.acknowledgesNotice = true
        await model.accept()

        #expect(model.isPending && !model.isConfirmed && model.member == nil)
        #expect(model.errorMessage == SchoolJoinFailure.unavailable.errorDescription)
        let pending = try #require(journal.records.last)
        #expect(pending.receipt == nil && pending.body != nil)
        #expect(await transport.acceptCalls() == 1)

        // Feuille rouverte : la même intention est montrée, et aucun autre lien ne peut être préparé.
        let reopened = SchoolJoinWorkspace(client: JoinLinkFixture.client(transport, token),
                                           link: JoinLinkFixture.link, journal: journal)
        await reopened.load()
        #expect(reopened.isReady && reopened.isPending)
        #expect(reopened.preview == pending.preview && reopened.link.isEmpty)
        #expect(!reopened.canPreview && !reopened.canAccept)

        // La vérification relit cette opération : aucun second envoi, une seule adhésion.
        await transport.setAcceptFailure(false)
        await reopened.verify()
        #expect(reopened.isConfirmed)
        #expect(reopened.member?.membershipId == JoinLinkFixture.membershipID)
        #expect(await transport.acceptCalls() == 1)
        let requests = await transport.recorded()
        let receipt = try #require(requests.first { $0.url?.path.contains("/operations/") == true })
        #expect(receipt.httpMethod == "GET")
        let expectedPath = "/v1/schools/\(JoinLinkFixture.schoolID.uuidString)/operations/\(pending.operationID.uuidString)"
        #expect(receipt.url?.path == expectedPath)
        #expect(Set(journal.records.map(\.operationID)) == [pending.operationID])
        #expect(journal.current(pending.principal)?.receipt?.resourceId == JoinLinkFixture.membershipID)
    }

    @Test func anUncertainIntentionIsResentIdenticallyOnRetry() async throws {
        let transport = JoinLinkTransport()
        await transport.setAcceptFailure(true)
        let journal = JoinLinkJournalStub()
        let model = SchoolJoinWorkspace(client: JoinLinkFixture.client(transport, JoinLinkToken(subject: "synthetic-learner")),
                                        link: JoinLinkFixture.link, journal: journal)
        await model.load()
        await model.inspect()
        model.acknowledgesNotice = true
        await model.accept()
        let pending = try #require(journal.records.last)
        #expect(model.isPending)

        await transport.setAcceptFailure(false)
        await model.retry()
        #expect(model.isConfirmed && model.member != nil)
        let requests = await transport.recorded()
        let accepts = requests.filter { $0.url?.path == "/v1/invitations/accept" }
        #expect(accepts.count == 2)
        // Même octets, même opération : un renvoi est la même demande.
        #expect(accepts[0].httpBody == accepts[1].httpBody)
        #expect(accepts[0].value(forHTTPHeaderField: "Idempotency-Key")
            == accepts[1].value(forHTTPHeaderField: "Idempotency-Key"))
        #expect(accepts[1].value(forHTTPHeaderField: "Idempotency-Key") == pending.operationID.uuidString)
        #expect(Set(journal.records.map(\.operationID)) == [pending.operationID])
    }

    @Test func aDoubleTapSendsASingleAcceptance() async throws {
        let transport = JoinLinkTransport()
        let journal = JoinLinkJournalStub()
        let model = SchoolJoinWorkspace(client: JoinLinkFixture.client(transport, JoinLinkToken(subject: "synthetic-learner")),
                                        link: JoinLinkFixture.link, journal: journal)
        await model.load()
        await model.inspect()
        model.acknowledgesNotice = true

        let first = Task { await model.accept() }
        let second = Task { await model.accept() }
        await first.value
        await second.value

        #expect(model.isConfirmed)
        #expect(await transport.acceptCalls() == 1)
        // Un seul aperçu de plus (la relecture avant envoi) : le second appui n'a rien préparé.
        #expect(await transport.previewCalls() == 2)
        #expect(Set(journal.records.map(\.operationID)).count == 1)

        // Un nouvel appui après confirmation n'émet rien non plus.
        await model.accept()
        #expect(await transport.acceptCalls() == 1)
    }

    // MARK: Changement de compte

    @Test func anotherAccountsIntentionIsNeitherShownNorReplayed() async throws {
        let transport = JoinLinkTransport()
        await transport.setAcceptFailure(true)
        let journal = JoinLinkJournalStub()
        let model = SchoolJoinWorkspace(client: JoinLinkFixture.client(transport, JoinLinkToken(subject: "synthetic-learner")),
                                        link: JoinLinkFixture.link, journal: journal)
        await model.load()
        await model.inspect()
        model.acknowledgesNotice = true
        await model.accept()
        let pending = try #require(journal.records.last)
        #expect(model.isPending)
        let emitted = await transport.recorded().count

        // Même appareil, autre compte : la feuille s'ouvre sans rien montrer de l'intention précédente.
        let other = SchoolJoinWorkspace(client: JoinLinkFixture.client(transport, JoinLinkToken(subject: "synthetic-instructor")),
                                        link: JoinLinkFixture.link, journal: journal)
        await other.load()
        #expect(other.isReady)
        #expect(other.record == nil && other.preview == nil && other.member == nil)
        #expect(!other.isPending && !other.isConfirmed && !other.canAccept)
        // Ni vérification ni renvoi : aucune requête ne part.
        await other.verify()
        await other.retry()
        let afterOther = await transport.recorded().count
        #expect(afterOther == emitted)
        // L'intention du premier compte reste intacte, sans reçu.
        #expect(try journal.load(for: pending.principal) == pending)
    }

    @Test func verifyingUnderAnotherSessionNeverSendsTheFirstAccountsIntention() async throws {
        let transport = JoinLinkTransport()
        await transport.setAcceptFailure(true)
        let journal = JoinLinkJournalStub()
        let token = JoinLinkToken(subject: "synthetic-learner")
        let model = SchoolJoinWorkspace(client: JoinLinkFixture.client(transport, token),
                                        link: JoinLinkFixture.link, journal: journal)
        await model.load()
        await model.inspect()
        model.acknowledgesNotice = true
        await model.accept()
        let pending = try #require(journal.records.last)
        let emitted = await transport.recorded().count

        // La session change sans recharger la feuille : l'intention appartient à l'autre compte.
        token.subject = "synthetic-instructor"
        await model.verify()
        let afterSwitch = await transport.recorded().count
        #expect(afterSwitch == emitted)
        #expect(model.errorMessage == SchoolJoinFailure.differentAccount.errorDescription)
        #expect(model.isPending && !model.isConfirmed)
        #expect(journal.current(pending.principal) == pending)
    }

    // MARK: Accès

    @Test func anAnswerWithoutAVerifiableReceiptGrantsNoAccess() async throws {
        let transport = JoinLinkTransport()
        // L'école répond 201 avec une adhésion, mais le reçu désigne une autre ressource : rien ne se confirme.
        await transport.setReceiptResourceID(UUID())
        let journal = JoinLinkJournalStub()
        let model = SchoolJoinWorkspace(client: JoinLinkFixture.client(transport, JoinLinkToken(subject: "synthetic-learner")),
                                        link: JoinLinkFixture.link, journal: journal)
        await model.load()
        await model.inspect()
        model.acknowledgesNotice = true
        await model.accept()

        #expect(!model.isConfirmed && model.member == nil)
        #expect(model.errorMessage == SchoolJoinFailure.invalidResponse.errorDescription)
        #expect(model.isPending)
        let stored = try #require(journal.records.last)
        // L'adhésion annoncée par la réponse n'est jamais reprise localement sans reçu concordant.
        #expect(stored.receipt == nil && journal.current(stored.principal)?.receipt == nil)
    }
}

// MARK: - Support

enum JoinLinkFixture {
    static let schoolID = UUID(uuidString: "50000000-0000-4000-8000-000000000101")!
    static let membershipID = UUID(uuidString: "50000000-0000-4000-8000-000000000102")!
    static let invitationID = UUID(uuidString: "50000000-0000-4000-8000-000000000103")!
    static let personID = UUID(uuidString: "50000000-0000-4000-8000-000000000104")!
    static let subject = "synthetic-learner"
    static let token = String(repeating: "a", count: 43)
    static let link = "https://api.example.test/app/invitation#token=\(token)"
    static let expiresAt = "2026-12-01T10:00:00Z"
    static let committedAt = "2026-12-01T10:00:00Z"
    static let serverTime = "2026-12-01T10:00:00Z"
    static let configuration = AppConfiguration(apiBaseURL: URL(string: "https://api.example.test")!,
        issuer: URL(string: "https://id.example.test")!, clientID: "drivy-ios-tests", redirectURL: AppConfiguration.callback)
    static var principal: SchoolJoinPrincipal {
        SchoolJoinPrincipal(apiBaseURL: configuration.apiBaseURL.absoluteString,
            issuer: configuration.issuer.absoluteString, subject: subject)
    }
    static var preview: SchoolJoinPreview {
        SchoolJoinPreview(invitationId: invitationID, schoolId: schoolID, schoolName: "École exemple",
            roles: ["LEARNER"], maskedEmail: "e***@example.invalid", expiresAt: expiresAt,
            notice: SchoolJoinNotice(version: 1, noticeText: "Notice de test", retentionText: "Conservation de test",
                contactEmail: "ecole@example.invalid"))
    }
    @MainActor static func client(_ transport: JoinLinkTransport, _ token: JoinLinkToken) -> SchoolJoinClient {
        SchoolJoinClient(configuration: configuration, tokenSource: token, transport: transport)
    }
}

/// Jeton synthétique : l'en-tête et la signature ne portent rien, seules les revendications de cloisonnement comptent.
@MainActor
final class JoinLinkToken: AccessTokenSource {
    var subject: String
    init(subject: String) { self.subject = subject }

    func accessToken() async throws -> String {
        let claims = Data("{\"iss\":\"https://id.example.test\",\"sub\":\"\(subject)\"}".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return "eyJhbGciOiJub25lIn0.\(claims).c3ludGhldGlj"
    }
}

/// Journal chiffré simulé : même contrat que `SchoolJoinJournal` (validation, une intention par compte, reçu immuable).
@MainActor
final class JoinLinkJournalStub: SchoolJoinStore {
    /// Chaque écriture, dans l'ordre : sert à prouver qu'une intention n'est créée qu'une fois.
    private(set) var records: [SchoolJoinRecord] = []
    private var byPrincipal: [String: SchoolJoinRecord] = [:]
    var failRead = false

    func load(for principal: SchoolJoinPrincipal) throws -> SchoolJoinRecord? {
        if failRead { throw SchoolJoinFailure.storage }
        return byPrincipal[principal.storageKey]
    }
    func current(_ principal: SchoolJoinPrincipal) -> SchoolJoinRecord? { byPrincipal[principal.storageKey] }

    func save(_ record: SchoolJoinRecord) throws {
        guard record.isValid, record.receipt == nil else { throw SchoolJoinFailure.storage }
        if let existing = byPrincipal[record.principal.storageKey] {
            if existing.operationID == record.operationID { guard existing == record else { throw SchoolJoinFailure.pending } }
            else { guard existing.receipt != nil else { throw SchoolJoinFailure.pending } }
        }
        records.append(record)
        byPrincipal[record.principal.storageKey] = record
    }

    func confirm(_ record: SchoolJoinRecord, receipt: SchoolOperationReceipt) throws -> SchoolJoinRecord {
        guard record.matches(receipt), byPrincipal[record.principal.storageKey] == record else { throw SchoolJoinFailure.storage }
        let confirmed = record.confirmed(by: receipt)
        byPrincipal[record.principal.storageKey] = confirmed
        return confirmed
    }

    func removeFreshRejection(_ record: SchoolJoinRecord) throws {
        guard record.receipt == nil, byPrincipal[record.principal.storageKey] == record else { throw SchoolJoinFailure.storage }
        byPrincipal[record.principal.storageKey] = nil
    }
}

actor JoinLinkTransport: SchoolHTTPTransport {
    private var requests: [URLRequest] = []
    private var previewProblem: (status: Int, code: String)?
    private var acceptProblem: (status: Int, code: String)?
    private var acceptFails = false
    private var receiptResourceID = JoinLinkFixture.membershipID
    private var acceptHolds = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func recorded() -> [URLRequest] { requests }
    func previewCalls() -> Int { requests.filter { $0.url?.path == "/v1/invitations/preview" }.count }
    func acceptCalls() -> Int { requests.filter { $0.url?.path == "/v1/invitations/accept" }.count }

    func setPreviewProblem(_ status: Int, code: String) { previewProblem = (status, code) }
    func setAcceptProblem(_ status: Int, code: String) { acceptProblem = (status, code) }
    func setAcceptFailure(_ value: Bool) { acceptFails = value }
    func setReceiptResourceID(_ value: UUID) { receiptResourceID = value }

    func holdAccept() { acceptHolds = true }
    func releaseAccept() {
        acceptHolds = false
        let pending = waiters; waiters = []
        for waiter in pending { waiter.resume() }
    }
    private func gate() async {
        if acceptHolds { await withCheckedContinuation { waiters.append($0) } }
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        requests.append(request)
        guard let url = request.url else { throw URLError(.badURL) }
        switch url.path {
        case "/v1/invitations/preview":
            if let previewProblem { return problem(url, status: previewProblem.status, code: previewProblem.code) }
            let notice: [String: Any] = ["version": 1, "noticeText": "Notice de test",
                "retentionText": "Conservation de test", "contactEmail": "ecole@example.invalid"]
            let value: [String: Any] = [
                "invitationId": JoinLinkFixture.invitationID.uuidString,
                "schoolId": JoinLinkFixture.schoolID.uuidString,
                "schoolName": "École exemple",
                "roles": ["LEARNER"],
                "maskedEmail": "e***@example.invalid",
                "expiresAt": JoinLinkFixture.expiresAt,
                "notice": notice]
            return try envelope(url, status: 200, data: value)
        case "/v1/invitations/accept":
            await gate()
            if acceptFails { throw URLError(.networkConnectionLost) }
            if let acceptProblem { return problem(url, status: acceptProblem.status, code: acceptProblem.code) }
            return try envelope(url, status: 201, data: membership)
        case "/v1/me":
            let value: [String: Any] = [
                "personId": JoinLinkFixture.personID.uuidString,
                "version": 1,
                "displayName": "Élève exemple",
                "locale": "fr-CH",
                "memberships": [membership]]
            return try envelope(url, status: 200, data: value)
        case let path where path.hasPrefix("/v1/schools/") && path.contains("/operations/"):
            let operationID = UUID(uuidString: url.lastPathComponent) ?? UUID()
            let value: [String: Any] = [
                "operationId": operationID.uuidString,
                "commandType": "ACCEPT_INVITATION",
                "resourceType": "Membership",
                "resourceId": receiptResourceID.uuidString,
                "committedAt": JoinLinkFixture.committedAt,
                "resourceVersion": 1]
            return try envelope(url, status: 200, data: value)
        default:
            return problem(url, status: 404, code: "NOT_FOUND")
        }
    }

    private var membership: [String: Any] {
        ["membershipId": JoinLinkFixture.membershipID.uuidString,
         "schoolId": JoinLinkFixture.schoolID.uuidString,
         "schoolName": "École exemple",
         "roles": ["LEARNER"],
         "grants": [String](),
         "accessEpoch": 1]
    }

    private func envelope(_ url: URL, status: Int, data: [String: Any]) throws -> SchoolHTTPResponse {
        let payload: [String: Any] = ["data": data, "requestId": UUID().uuidString,
            "serverTime": JoinLinkFixture.serverTime]
        let body = try JSONSerialization.data(withJSONObject: payload)
        return SchoolHTTPResponse(data: body, status: status, url: url, contentType: "application/json")
    }

    private func problem(_ url: URL, status: Int, code: String) -> SchoolHTTPResponse {
        SchoolHTTPResponse(data: Data("{\"code\":\"\(code)\"}".utf8), status: status, url: url,
            contentType: "application/problem+json")
    }
}

/// Attend un état sans jamais bloquer indéfiniment : au-delà de quelques secondes, l'assertion échoue.
@MainActor
private func until(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<600 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}
