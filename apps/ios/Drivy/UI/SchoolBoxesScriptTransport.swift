#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Écran de contrôle « learners-boxes-refresh » (#449) : le serveur fictif change entre deux lectures des boîtes de l'onglet Élèves.
///
/// - Demandes : la 1re lecture donne neuf lignes ; les suivantes retirent la première et ajoutent une dixième ; après un refus confirmé,
///   la demande de la leçon planifiée n'y est plus.
/// - Examens : la 1re lecture donne neuf lignes, la 2e échoue (panne locale), les suivantes retirent la première et ajoutent une dixième.
/// - Le refus d'une demande (POST) est accepté une fois et rend l'état refusé de la leçon planifiée.
///
/// Données fictives uniquement, comme le reste du harnais ; l'ordre des lectures est celui de l'écran (une lecture initiale par boîte).
final class SchoolBoxesScriptTransport: SchoolHTTPTransport, @unchecked Sendable {
    private let base: SchoolVisualTransport
    private let lock = NSLock()
    private var requestReads = 0
    private var examReads = 0
    private var refused = false

    init(base: SchoolVisualTransport) { self.base = base }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url else { throw SchoolAPIError.invalidResponse }
        if (request.httpMethod ?? "GET") == "POST", url.lastPathComponent == "refuse" { return try await refuse(request, url: url) }
        let response = try await base.send(request)
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

    /// Compte la lecture de demandes qui commence, sous verrou.
    private func nextRequestRead() -> (Int, Bool) {
        lock.lock(); defer { lock.unlock() }
        requestReads += 1
        return (requestReads, refused)
    }

    private func nextExamRead() -> Int {
        lock.lock(); defer { lock.unlock() }
        examReads += 1
        return examReads
    }

    private func refuse(_ request: URLRequest, url: URL) async throws -> SchoolHTTPResponse {
        lock.lock(); refused = true; lock.unlock()
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
