#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Écrans de contrôle « learners-boxes-* » (#447, #449) : le serveur fictif simule une lecture lente et, pour « learners-boxes-refresh »,
/// change entre deux lectures des boîtes de l'onglet Élèves.
///
/// - Tous les écrans : la première lecture des examens d'une formation arrive après une courte attente, comme une lecture lente. Le
///   dossier doit ouvrir l'examen visé quand elle arrive, sans défilement manuel ni attente côté produit.
/// - Avec `scriptsReads` — demandes : la 1re lecture donne neuf lignes ; les suivantes retirent la première et ajoutent une dixième ;
///   après un refus confirmé, la demande de la leçon planifiée n'y est plus. Examens : la 1re lecture donne neuf lignes, la 2e échoue
///   (panne locale), les suivantes retirent la première et ajoutent une dixième. Le refus d'une demande (POST) est accepté et rend l'état
///   refusé de la leçon planifiée.
///
/// Données fictives uniquement, comme le reste du harnais ; l'ordre des lectures est celui de l'écran (une lecture initiale par boîte).
final class SchoolBoxesScriptTransport: SchoolHTTPTransport, @unchecked Sendable {
    /// Durée de la première lecture des examens d'une formation (simulée par le harnais, jamais par le produit).
    static let slowExamStateSeconds = 2.0

    private let base: SchoolVisualTransport
    private let scriptsReads: Bool
    private let lock = NSLock()
    private var requestReads = 0
    private var examReads = 0
    private var stateReads = 0
    private var refused = false

    init(base: SchoolVisualTransport, scriptsReads: Bool) {
        self.base = base
        self.scriptsReads = scriptsReads
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url else { throw SchoolAPIError.invalidResponse }
        if scriptsReads, (request.httpMethod ?? "GET") == "POST", url.lastPathComponent == "refuse" { return try await refuse(request, url: url) }
        if (request.httpMethod ?? "GET") == "GET", url.lastPathComponent == "exams", url.pathComponents.contains("trainings"),
           nextStateRead() == 1 {
            try await Task.sleep(for: .seconds(Self.slowExamStateSeconds))
        }
        let response = try await base.send(request)
        guard scriptsReads else { return response }
        if url.lastPathComponent == "lesson-change-requests" {
            let (read, wasRefused) = nextRequestRead()
            return try rewrite(response, nameStem: "Élève demande") { items in
                if wasRefused { return items.filter { ($0["lesson"] as? [String: Any])?["id"] as? String != SchoolVisualData.plannedLessonID.uuidString } }
                return read == 1 ? items : Self.shifted(items, stem: "Élève demande", key: "lesson")
            }
        }
        if url.lastPathComponent == "exams", URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .contains(where: { $0.name == "filter" && $0.value == "PENDING_RESULT" }) == true {
            let read = nextExamRead()
            if read == 2 { throw SchoolAPIError.invalidResponse }
            return try rewrite(response, nameStem: "Élève examen") { read == 1 ? $0 : Self.shifted($0, stem: "Élève examen", key: "exam") }
        }
        return response
    }

    // Les compteurs se touchent par des fonctions synchrones : aucun verrou n'est tenu pendant un `await`.
    private func nextRequestRead() -> (Int, Bool) {
        lock.withLock { requestReads += 1; return (requestReads, refused) }
    }

    private func nextExamRead() -> Int {
        lock.withLock { examReads += 1; return examReads }
    }

    private func nextStateRead() -> Int {
        lock.withLock { stateReads += 1; return stateReads }
    }

    private func markRefused() {
        lock.withLock { refused = true }
    }

    private func refuse(_ request: URLRequest, url: URL) async throws -> SchoolHTTPResponse {
        markRefused()
        var parts = url.pathComponents
        guard let index = parts.firstIndex(of: "lesson-change-requests") else { throw SchoolAPIError.invalidResponse }
        parts.removeSubrange(index...)
        var read = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        read.path = (parts.joined(separator: "/").replacingOccurrences(of: "//", with: "/"))
            + "/lessons/\(SchoolVisualData.plannedLessonID.uuidString)/change-requests"
        var get = URLRequest(url: read.url!)
        get.httpMethod = "GET"
        let state = try await base.send(get)
        var envelope = try JSONSerialization.jsonObject(with: state.data) as? [String: Any] ?? [:]
        var data = envelope["data"] as? [String: Any] ?? [:]
        var requests = data["requests"] as? [[String: Any]] ?? []
        if !requests.isEmpty {
            requests[0]["status"] = "REFUSED"
            requests[0]["resolvedAt"] = "2026-09-25T09:00:00Z"
        }
        data["requests"] = requests
        envelope["data"] = data
        return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: envelope), status: 200, url: url, contentType: "application/json")
    }

    private func rewrite(_ response: SchoolHTTPResponse, nameStem: String, _ change: ([[String: Any]]) -> [[String: Any]]) throws -> SchoolHTTPResponse {
        guard var envelope = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              var data = envelope["data"] as? [String: Any], let items = data["items"] as? [[String: Any]] else { throw SchoolAPIError.invalidResponse }
        data["items"] = change(items)
        envelope["data"] = data
        return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: envelope), status: response.status, url: response.url,
            contentType: response.contentType)
    }

    /// Retire la première ligne et ajoute une dixième, sur le modèle de la deuxième.
    private static func shifted(_ items: [[String: Any]], stem: String, key: String) -> [[String: Any]] {
        guard items.count > 2 else { return items }
        var added = items[1]
        let id = SchoolVisualData.identifier(1_010).uuidString
        if key == "lesson" {
            var request = added["request"] as? [String: Any] ?? [:]
            var lesson = added["lesson"] as? [String: Any] ?? [:]
            request["id"] = id; lesson["learnerDisplayName"] = "\(stem) 10"
            added["request"] = request; added["lesson"] = lesson
        } else {
            var exam = added["exam"] as? [String: Any] ?? [:]
            exam["id"] = id; added["exam"] = exam; added["learnerDisplayName"] = "\(stem) 10"
        }
        return Array(items.dropFirst()) + [added]
    }
}
#endif
