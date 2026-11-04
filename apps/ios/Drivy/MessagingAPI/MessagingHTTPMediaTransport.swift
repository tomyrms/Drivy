import Foundation
import CryptoKit

/// Plafonds de lecture d'une réponse média (#97, contrat §3.4/§4.5).
///
/// Le flux chiffré média est borné à 4 Mio + 8 Kio (plafond de corps de la route plus la
/// marge d'en-têtes) ; le reçu JSON, beaucoup plus petit, reste sous 16 Kio. Aucune de ces
/// bornes ne modifie le transport ordinaire, qui garde ses 2 Mio.
enum MessagingMediaResponseCeiling: Sendable, Equatable {
    case media
    case envelope

    static let mediaLimit = 4_194_304 + 8_192
    static let envelopeLimit = 16_384

    var byteLimit: Int {
        switch self {
        case .media: return Self.mediaLimit
        case .envelope: return Self.envelopeLimit
        }
    }
}

/// Réponse bornée d'un échange média : statut, URL finale, en-têtes utiles et corps déjà plafonné.
///
/// Seuls les en-têtes nommés par le contrat sont conservés : aucune sérialisation intégrale
/// des en-têtes, aucun corps de refus au-delà du plafond demandé.
struct MessagingMediaHTTPResponse: Sendable, Equatable {
    let status: Int
    let url: URL
    let contentType: String?
    /// `Content-Length` déclaré par le serveur, `nil` s'il est absent ou illisible.
    let declaredByteSize: Int?
    let schoolID: String?
    let accessEpoch: String?
    let sha256: String?
    let body: Data
}

/// Fil injectable du transport média : c'est la seule porte réseau, et elle reçoit
/// toujours le plafond de lecture à appliquer.
protocol MessagingMediaHTTPWire: Sendable {
    func send(_ request: URLRequest, ceiling: MessagingMediaResponseCeiling) async throws -> MessagingMediaHTTPResponse
}

/// Aucune redirection n'est suivie, même vers le même hôte : aucun jeton n'est transféré ailleurs.
final class MessagingMediaNoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Tâche de flux rendue capturable par un `withTaskCancellationHandler` : `URLSessionDataTask`
/// n'est pas `Sendable`, alors que `cancel()` est documenté comme immédiat et thread-safe.
private final class MessagingMediaStreamTask: @unchecked Sendable {
    private let task: URLSessionDataTask

    init(_ task: URLSessionDataTask) { self.task = task }
    func cancel() { task.cancel() }
}

/// Session dédiée aux médias : éphémère, sans cache ni cookie, sans écriture disque,
/// et lecture en flux borné AVANT toute allocation disproportionnée.
///
/// La limite de 2 Mio du transport ordinaire n'est ni élargie ni modifiée : ce wire
/// n'est utilisé que par `MessagingHTTPMediaTransport`.
actor MessagingMediaURLSessionTransport: MessagingMediaHTTPWire {
    private let session: URLSession

    /// Configuration par défaut : mêmes délais que le transport existant, aucune trace locale.
    init(configuration: URLSessionConfiguration = MessagingMediaURLSessionTransport.makeConfiguration()) {
        // Les garanties sont appliquées ici, quelle que soit la configuration reçue : un
        // appelant (tests sur `URLProtocol`) ne peut pas réactiver cache ou cookies par erreur.
        Self.harden(configuration)
        session = URLSession(configuration: configuration, delegate: MessagingMediaNoRedirects(), delegateQueue: nil)
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        return configuration
    }

    /// Aucun cache, aucun cookie, aucune réponse locale réutilisée.
    static func harden(_ configuration: URLSessionConfiguration) {
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    }

    func send(_ request: URLRequest, ceiling: MessagingMediaResponseCeiling) async throws -> MessagingMediaHTTPResponse {
        let (bytes, response) = try await session.bytes(for: request)
        // La tâche qui alimente le flux s'annule seule : toute sortie prématurée l'arrête,
        // sans annuler ni interrompre les autres requêtes du même transport.
        let stream = MessagingMediaStreamTask(bytes.task)
        guard let http = response as? HTTPURLResponse, let url = http.url else {
            stream.cancel()
            throw MessagingMediaTransportFailure.invalidResponse
        }
        let limit = ceiling.byteLimit
        let declared = Self.declaredByteSize(http)
        // Longueur annoncée : refus avant toute accumulation, dans les deux sources
        // (en-tête et couche réseau) car une réponse fragmentée peut n'annoncer qu'une des deux.
        if let declared, declared < 0 || declared > limit {
            stream.cancel()
            throw MessagingMediaTransportFailure.tooLarge
        }
        if http.expectedContentLength > Int64(limit) {
            stream.cancel()
            throw MessagingMediaTransportFailure.tooLarge
        }
        var body = Data()
        if let declared, declared > 0 { body.reserveCapacity(declared) }
        do {
            // L'annulation ne dépend pas de la coopération de l'itérateur : le gestionnaire
            // annule la tâche URLSession dès l'annulation de l'appelant, même sans nouvel octet.
            try await withTaskCancellationHandler {
                for try await byte in bytes {
                    guard body.count < limit else { throw MessagingMediaTransportFailure.tooLarge }
                    body.append(byte)
                }
            } onCancel: {
                stream.cancel()
            }
        } catch {
            // Dépassement pendant la lecture ou annulation appelante : le flux est arrêté
            // avant que la tâche sous-jacente ne continue à consommer le réseau.
            stream.cancel()
            if error.isRequestCancellation { throw CancellationError() }
            throw error
        }
        if Task.isCancelled {
            stream.cancel()
            throw CancellationError()
        }
        return MessagingMediaHTTPResponse(status: http.statusCode, url: url,
            contentType: http.value(forHTTPHeaderField: "Content-Type"),
            declaredByteSize: declared,
            schoolID: http.value(forHTTPHeaderField: "X-Drivy-School-Id"),
            accessEpoch: http.value(forHTTPHeaderField: "X-Drivy-Access-Epoch"),
            sha256: http.value(forHTTPHeaderField: "X-Drivy-Media-Sha256"),
            body: body)
    }

    private static func declaredByteSize(_ response: HTTPURLResponse) -> Int? {
        guard let raw = response.value(forHTTPHeaderField: "Content-Length") else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespaces))
    }
}

/// Transport média (#97, T2b2) : frère de `MessagingHTTPTransport.request` pour un corps et
/// une réponse binaires.
///
/// Mêmes en-têtes de contexte, même jeton, mêmes vérifications de scope avant et après
/// chaque attente, même renouvellement unique sur 401. Aucun nouvel essai sur délai dépassé,
/// 5xx, 404 ou 409 ; aucun nouvel identifiant média ni nouveau chiffré.
///
/// Ce transport est une primitive : il n'est branché ni à la file, ni au coffre, ni à l'UI.
actor MessagingHTTPMediaTransport: MessagingMediaTransport {
    /// Plafond du chiffré déposé : 4 Mio, identique à la primitive crypto et au serveur.
    static let maximumByteSize = 4_194_304

    private enum Operation {
        static let put = "MEDIA-PUT"
        static let get = "MEDIA-GET"
        static let delete = "MEDIA-DELETE"
    }

    private let baseURL: URL
    /// Identifiant d'appareil déclaré, fourni explicitement par l'appelant : jamais inventé,
    /// jamais cherché implicitement. Ce n'est pas une preuve de possession cryptographique.
    private let deviceID: String
    private let wire: any MessagingMediaHTTPWire
    private let token: @MainActor @Sendable () async throws -> String
    private let invalidate: @MainActor @Sendable (String) async -> Bool
    private let currentScope: @MainActor @Sendable () -> MessagingScope?
    private let diagnostics: MessagingDiagnostics

    init(baseURL: URL, deviceID: String, wire: any MessagingMediaHTTPWire = MessagingMediaURLSessionTransport(),
         diagnostics: MessagingDiagnostics = .shared,
         token: @escaping @MainActor @Sendable () async throws -> String,
         invalidate: @escaping @MainActor @Sendable (String) async -> Bool,
         currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) {
        self.baseURL = baseURL
        self.deviceID = deviceID
        self.wire = wire
        self.diagnostics = diagnostics
        self.token = token
        self.invalidate = invalidate
        self.currentScope = currentScope
    }

    @MainActor
    static func using(baseURL: URL, deviceID: String, tokenSource: any AccessTokenSource,
                      wire: any MessagingMediaHTTPWire = MessagingMediaURLSessionTransport(),
                      diagnostics: MessagingDiagnostics = .shared,
                      currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) -> MessagingHTTPMediaTransport {
        MessagingHTTPMediaTransport(baseURL: baseURL, deviceID: deviceID, wire: wire, diagnostics: diagnostics,
            token: { try await tokenSource.accessToken() },
            invalidate: { await tokenSource.invalidateAccessToken($0) }, currentScope: currentScope)
    }

    // MARK: Dépôt

    func upload(_ sealed: MessagingSealedMedia, scope: MessagingScope,
                conversationID: UUID) async throws -> MessagingMediaReceipt {
        let byteSize = sealed.ciphertext.count
        guard byteSize >= 1, byteSize <= Self.maximumByteSize else {
            throw fail(.invalidIntent, operation: Operation.put, cause: "M-SIZE")
        }
        // Sceau, informations et hash sont contrôlés AVANT émission (T2a) : un objet incohérent
        // ne part pas et aucun octet nouveau n'est produit.
        guard Self.isConsistentSeal(sealed) else {
            throw fail(.invalidIntent, operation: Operation.put, cause: "M-HASH")
        }
        guard Self.isValidDeviceID(deviceID) else {
            throw fail(.invalidIntent, operation: Operation.put, cause: "M-DEVICE")
        }
        let digest = Self.hex(SHA256.hash(data: sealed.ciphertext))
        let target = try await start(scope: scope, conversationID: conversationID,
                                     mediaID: sealed.mediaID, operation: Operation.put)
        let response = try await exchange(method: "PUT", target: target, scope: scope,
                                          body: sealed.ciphertext, accept: "application/json",
                                          ceiling: .envelope, operation: Operation.put)
        return try receipt(from: response, target: target, sealed: sealed, digest: digest,
                           byteSize: byteSize, scope: scope)
    }

    /// Vérifie l'enveloppe du dépôt : identité, taille, hash du chiffré, état et contexte.
    /// `ATTACHED` est une reconnaissance de dépôt, pas une preuve de publication.
    private func receipt(from response: MessagingMediaHTTPResponse, target: URL, sealed: MessagingSealedMedia,
                         digest: String, byteSize: Int, scope: MessagingScope) throws -> MessagingMediaReceipt {
        guard response.status == 200 else {
            throw fail(Self.statusFailure(response), operation: Operation.put)
        }
        guard response.url == target, Self.isJSON(response.contentType) else {
            throw fail(.invalidResponse, operation: Operation.put)
        }
        guard let envelope = try? JSONDecoder().decode(UploadEnvelope.self, from: response.body) else {
            throw fail(.invalidResponse, operation: Operation.put)
        }
        guard envelope.context.schoolId == scope.schoolID,
              envelope.context.actorPersonId == scope.accountID,
              envelope.context.accessEpoch == scope.accessEpoch else {
            throw fail(.contextChanged, operation: Operation.put)
        }
        guard envelope.data.mediaId == sealed.mediaID, envelope.data.byteSize == byteSize else {
            throw fail(.invalidResponse, operation: Operation.put, cause: "M-INTEGRITY")
        }
        guard Self.isHexDigest(envelope.data.sha256) else {
            throw fail(.invalidResponse, operation: Operation.put, cause: "M-HASH")
        }
        guard envelope.data.sha256 == digest else {
            throw fail(.integrityMismatch, operation: Operation.put)
        }
        let state: MessagingMediaReceipt.State
        switch envelope.data.state {
        case "UPLOADED": state = .uploaded
        case "ATTACHED": state = .attached
        case "PURGED": throw fail(.purged, operation: Operation.put)
        default: throw fail(.invalidResponse, operation: Operation.put)
        }
        return MessagingMediaReceipt(mediaID: sealed.mediaID, byteSize: byteSize, sha256: digest, state: state)
    }

    // MARK: Téléchargement

    func download(mediaID: UUID, scope: MessagingScope, conversationID: UUID) async throws -> Data {
        guard Self.isValidDeviceID(deviceID) else {
            throw fail(.invalidIntent, operation: Operation.get, cause: "M-DEVICE")
        }
        let target = try await start(scope: scope, conversationID: conversationID,
                                     mediaID: mediaID, operation: Operation.get)
        let response = try await exchange(method: "GET", target: target, scope: scope,
                                          body: nil, accept: "application/octet-stream",
                                          ceiling: .media, operation: Operation.get)
        guard response.status == 200 else {
            throw fail(Self.statusFailure(response), operation: Operation.get)
        }
        guard response.url == target, Self.isOctetStream(response.contentType) else {
            throw fail(.invalidResponse, operation: Operation.get)
        }
        guard let rawSchool = response.schoolID, let school = UUID(uuidString: rawSchool) else {
            throw fail(.invalidResponse, operation: Operation.get)
        }
        guard school == scope.schoolID else {
            throw fail(.contextChanged, operation: Operation.get)
        }
        guard let rawEpoch = response.accessEpoch, let epoch = Int(rawEpoch) else {
            throw fail(.invalidResponse, operation: Operation.get)
        }
        guard epoch == scope.accessEpoch else {
            throw fail(.contextChanged, operation: Operation.get)
        }
        guard let sha = response.sha256?.lowercased(), Self.isHexDigest(sha) else {
            throw fail(.invalidResponse, operation: Operation.get, cause: "M-HASH")
        }
        guard let declared = response.declaredByteSize else {
            throw fail(.invalidResponse, operation: Operation.get, cause: "M-SIZE")
        }
        let body = response.body
        guard declared <= Self.maximumByteSize, body.count <= Self.maximumByteSize else {
            throw fail(.tooLarge, operation: Operation.get)
        }
        guard declared >= 1, body.count >= 1 else {
            throw fail(.invalidResponse, operation: Operation.get, cause: "M-SIZE")
        }
        guard declared == body.count else {
            throw fail(.invalidResponse, operation: Operation.get, cause: "M-SIZE")
        }
        // Le hash HTTP ne prouve que la correspondance du chiffré au dépôt :
        // l'authenticité est portée par l'enveloppe Megolm, vérifiée par
        // `MessagingMediaCryptography.open` chez le futur consommateur. Rien de partiel n'est rendu.
        guard Self.hex(SHA256.hash(data: body)) == sha else {
            throw fail(.integrityMismatch, operation: Operation.get)
        }
        return body
    }

    // MARK: Annulation

    func cancel(mediaID: UUID, scope: MessagingScope, conversationID: UUID) async throws {
        guard Self.isValidDeviceID(deviceID) else {
            throw fail(.invalidIntent, operation: Operation.delete, cause: "M-DEVICE")
        }
        let target = try await start(scope: scope, conversationID: conversationID,
                                     mediaID: mediaID, operation: Operation.delete)
        let response = try await exchange(method: "DELETE", target: target, scope: scope,
                                          body: nil, accept: "application/json",
                                          ceiling: .envelope, operation: Operation.delete)
        guard response.status == 200 else {
            throw fail(Self.statusFailure(response), operation: Operation.delete)
        }
        guard response.url == target, Self.isJSON(response.contentType) else {
            throw fail(.invalidResponse, operation: Operation.delete)
        }
        guard let envelope = try? JSONDecoder().decode(CancelEnvelope.self, from: response.body) else {
            throw fail(.invalidResponse, operation: Operation.delete)
        }
        guard envelope.context.schoolId == scope.schoolID,
              envelope.context.actorPersonId == scope.accountID,
              envelope.context.accessEpoch == scope.accessEpoch else {
            throw fail(.contextChanged, operation: Operation.delete)
        }
        guard envelope.data.deleted, envelope.data.mediaId == mediaID else {
            throw fail(.invalidResponse, operation: Operation.delete)
        }
    }

    // MARK: Échange

    /// Le scope est vérifié avant l'attente du jeton, avant chaque émission, après la réponse,
    /// puis à chaque tour : une réponse tardive d'un contexte quitté n'est jamais rendue.
    private func exchange(method: String, target: URL, scope: MessagingScope, body: Data?, accept: String,
                          ceiling: MessagingMediaResponseCeiling,
                          operation: String) async throws -> MessagingMediaHTTPResponse {
        var bearer = try await accessToken(scope: scope, operation: operation)
        for attempt in 0...1 {
            guard Self.isValidBearer(bearer) else {
                throw fail(.accessChanged, operation: operation)
            }
            try Task.checkCancellation()
            try await verifyCurrent(scope)
            let request = self.request(target, method: method, scope: scope, bearer: bearer,
                                       body: body, accept: accept)
            let response: MessagingMediaHTTPResponse
            do {
                response = try await wire.send(request, ceiling: ceiling)
            } catch {
                // Priorité : annulation de l'appelant, puis contexte quitté, puis mapping fermé.
                if error.isRequestCancellation || Task.isCancelled { throw CancellationError() }
                try await verifyCurrent(scope)
                if let failure = error as? MessagingMediaTransportFailure {
                    throw fail(failure, operation: operation)
                }
                throw fail(.unavailable, operation: operation)
            }
            try Task.checkCancellation()
            try await verifyCurrent(scope)
            if response.status == 401, attempt == 0 {
                // Le booléen est conservé hors du `guard` : un refus de renouvellement ne
                // dispense ni du contrôle d'annulation ni de celui du contexte, qui priment
                // tous deux sur le retour du 401.
                let renewed = await invalidate(bearer)
                try Task.checkCancellation()
                try await verifyCurrent(scope)
                if renewed {
                    bearer = try await accessToken(scope: scope, operation: operation)
                    continue
                }
                return response
            }
            return response
        }
        throw fail(.accessChanged, operation: operation)
    }

    /// Attente du jeton, fermée. Le scope est vérifié **juste avant** la source ; en sortie
    /// d'attente, la priorité est : annulation, puis contexte quitté, puis mapping fermé.
    /// Une erreur brute ou un refus ne dispense donc pas de recontrôler le contexte.
    /// Aucun `NSError`, `userInfo`, domaine ni texte libre ne traverse cette frontière.
    private func accessToken(scope: MessagingScope, operation: String) async throws -> String {
        try Task.checkCancellation()
        try await verifyCurrent(scope)
        let value: String
        do {
            value = try await token()
        } catch {
            if Task.isCancelled || error.isRequestCancellation { throw CancellationError() }
            try await verifyCurrent(scope)
            if let failure = error as? MessagingMediaTransportFailure { throw failure }
            if let identity = error as? IdentityFailure, case .reauthentication = identity {
                throw fail(.accessChanged, operation: operation)
            }
            throw fail(.unavailable, operation: operation)
        }
        if Task.isCancelled { throw CancellationError() }
        try await verifyCurrent(scope)
        return value
    }

    /// Construit l'URL média uniquement avec la base contrôlée et des UUID, puis vérifie
    /// l'origine, le scope et le contexte courant.
    private func start(scope: MessagingScope, conversationID: UUID, mediaID: UUID,
                       operation: String) async throws -> URL {
        try Task.checkCancellation()
        try await verifyCurrent(scope)
        guard let target = await Self.target(baseURL: baseURL, scope: scope,
                                             conversationID: conversationID, mediaID: mediaID) else {
            throw fail(.contextChanged, operation: operation)
        }
        try await verifyCurrent(scope)
        return target
    }

    private static func target(baseURL: URL, scope: MessagingScope,
                               conversationID: UUID, mediaID: UUID) async -> URL? {
        guard scope.apiBaseURL == baseURL.absoluteString else { return nil }
        guard await DrivyAPIClient.permits(baseURL), let origin = baseURL.host else { return nil }
        var url = baseURL
        for part in ["v1", "schools", scope.schoolID.uuidString, "messaging",
                     "conversations", conversationID.uuidString, "media", mediaID.uuidString] {
            url.appendPathComponent(part)
        }
        guard let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?.url,
              target.host == origin, await DrivyAPIClient.permits(target) else { return nil }
        return target
    }

    private func request(_ target: URL, method: String, scope: MessagingScope, bearer: String,
                         body: Data?, accept: String) -> URLRequest {
        var request = URLRequest(url: target)
        request.httpMethod = method
        request.httpBody = body
        if let body {
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue(scope.accountID.uuidString.lowercased(), forHTTPHeaderField: "X-Drivy-Expected-Person-Id")
        request.setValue(String(scope.accessEpoch), forHTTPHeaderField: "X-Drivy-Expected-Access-Epoch")
        request.setValue(deviceID, forHTTPHeaderField: "X-Drivy-Device-Id")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private func verifyCurrent(_ scope: MessagingScope) async throws {
        guard await currentScope() == scope else {
            throw MessagingMediaTransportFailure.contextChanged
        }
    }

    // MARK: Enveloppes et codes

    private struct UploadEnvelope: Decodable {
        struct Receipt: Decodable { let mediaId: UUID; let byteSize: Int; let sha256: String; let state: String }
        struct Context: Decodable { let schoolId: UUID; let actorPersonId: UUID; let accessEpoch: Int }
        let data: Receipt
        let context: Context
        let requestId: UUID
        let serverTime: String
    }

    private struct CancelEnvelope: Decodable {
        struct Receipt: Decodable { let mediaId: UUID; let deleted: Bool }
        struct Context: Decodable { let schoolId: UUID; let actorPersonId: UUID; let accessEpoch: Int }
        let data: Receipt
        let context: Context
        let requestId: UUID
        let serverTime: String
    }

    private struct Problem: Decodable { let code: String }

    private static func statusFailure(_ response: MessagingMediaHTTPResponse) -> MessagingMediaTransportFailure {
        let code = (try? JSONDecoder().decode(Problem.self, from: response.body))?.code
        switch response.status {
        case 401: return .accessChanged
        case 403: return code == "MESSAGING_DEVICE_REQUIRED" ? .deviceRequired : .accessChanged
        case 404: return .notFound
        case 409:
            switch code {
            case "MEDIA_PURGED": return .purged
            case "MEDIA_ALREADY_ATTACHED": return .alreadyAttached
            case "MEDIA_INTENT_CONFLICT": return .intentConflict
            case "MEDIA_SIZE_MISMATCH": return .sizeConflict
            default: return .stateConflict
            }
        case 400, 415: return .invalidIntent
        case 413: return .tooLarge
        case 408, 429: return .unavailable
        case 500...599: return .unavailable
        default: return .invalidResponse
        }
    }

    // MARK: Diagnostics (catégories fixes uniquement)

    /// Un seul code par tentative : la cause, jamais ses conséquences. Le vocabulaire est figé
    /// par le contrat §3.11 (`MEDIA-PUT/GET/DELETE` et `M-SIZE/M-HASH/M-DEVICE/M-PURGED/
    /// M-INTEGRITY/M-STATE`) : aucun identifiant, hash, URL, chemin ni message libre.
    private func fail(_ failure: MessagingMediaTransportFailure, operation: String,
                      cause: String? = nil) -> MessagingMediaTransportFailure {
        diagnostics.recordIfEmpty(Self.diagnostic(operation, cause ?? Self.cause(for: failure)))
        return failure
    }

    private static func diagnostic(_ operation: String, _ cause: String?) -> String {
        guard let cause else { return operation }
        return "\(operation)-\(cause)"
    }

    private static func cause(for failure: MessagingMediaTransportFailure) -> String? {
        switch failure {
        case .purged: return "M-PURGED"
        case .deviceRequired: return "M-DEVICE"
        case .integrityMismatch: return "M-INTEGRITY"
        case .tooLarge: return "M-SIZE"
        case .invalidResponse, .invalidIntent, .stateConflict, .alreadyAttached: return "M-STATE"
        case .contextChanged, .accessChanged, .notFound, .intentConflict, .sizeConflict, .unavailable: return nil
        }
    }

    // MARK: Contrôles locaux

    /// Le sceau est cohérent quand les informations validées (T2a) portent exactement le
    /// SHA-256 du chiffré : rien n'est réémis si l'objet et ses octets ont divergé.
    private static func isConsistentSeal(_ sealed: MessagingSealedMedia) -> Bool {
        guard let material = try? sealed.info.validatedMaterial() else { return false }
        return material.sha256 == Data(SHA256.hash(data: sealed.ciphertext))
    }

    /// Appareil déclaré : `[A-Z0-9]{10,32}`, comme le relais de clés et le serveur.
    static func isValidDeviceID(_ value: String) -> Bool {
        (10...32).contains(value.utf8.count) && value.utf8.allSatisfy {
            ($0 >= 65 && $0 <= 90) || ($0 >= 48 && $0 <= 57)
        }
    }

    /// Porteur ASCII sans CRLF : un jeton contenant un saut de ligne n'est jamais envoyé.
    private static func isValidBearer(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { $0 > 32 && $0 < 127 }
    }

    private static func isHexDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }

    private static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func isJSON(_ contentType: String?) -> Bool {
        contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json"
    }

    private static func isOctetStream(_ contentType: String?) -> Bool {
        contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/octet-stream"
    }
}
