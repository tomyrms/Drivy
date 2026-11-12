import Foundation
@testable import Drivy

/// Attente bornée de la disponibilité du relais de qualification (127.0.0.1:18443), commune aux classes de tests qui
/// s'y connectent. Cause traitée : sur un runner chargé, la poignée de main TLS du premier appel peut prendre ~10 s
/// (journal du run 43286133550) et la réponse arriver après le délai de 20 s d'une requête ; l'échec était alors
/// définitif alors que le relais, lui, répondait (le script de démarrage l'avait déjà sondé). On ne retente que les
/// erreurs de transport transitoires (délai dépassé, connexion refusée ou coupée), jamais un statut HTTP ni une
/// divergence de fixture : ces cas restent des échecs immédiats. Au bout du dernier essai, l'erreur d'origine est
/// relancée telle quelle, donc le diagnostic « étape=READINESS, transport=… » reste le même. Journal : numéros d'essai
/// seulement, ni URL, ni corps, ni en-tête.
enum RelayReadinessWait {
    /// Essais supplémentaires après l'échec initial : au pire 3 × (20 s + 2 s), soit environ 66 s de plus.
    static let additionalAttempts = 3
    static let pauseBetweenAttempts: Duration = .seconds(2)

    /// Délai, connexion refusée ou perdue : le relais n'est peut-être pas encore prêt ou est saturé.
    static func isTransient(_ error: any Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [-1001, -1004, -1005].contains(nsError.code)
    }

    /// Relance la sonde de disponibilité avec une session neuve par essai (aucune connexion à moitié établie réutilisée).
    static func retry(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        var lastError: (any Error)?
        for attempt in 1...additionalAttempts {
            try await Task.sleep(for: pauseBetweenAttempts)
            print("L2 readiness retry : essai \(attempt + 1)/\(additionalAttempts + 1)")
            do {
                return try await SchoolURLSessionTransport().send(request)
            } catch {
                guard isTransient(error) else { throw error }
                lastError = error
            }
        }
        throw lastError ?? CancellationError()
    }

    /// Premier essai direct, puis essais bornés seulement si l'échec est transitoire.
    static func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        do {
            return try await SchoolURLSessionTransport().send(request)
        } catch {
            guard isTransient(error) else { throw error }
            return try await retry(request)
        }
    }
}
