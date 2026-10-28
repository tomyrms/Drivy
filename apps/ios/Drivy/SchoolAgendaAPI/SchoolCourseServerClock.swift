import Foundation
import Observation

/// Échéances de l'école : la date du téléphone n'intervient jamais. ContinuousClock
/// continue pendant la veille et résiste à une correction de l'horloge système.
@MainActor @Observable final class SchoolCourseServerClock {
    @ObservationIgnored private let instant: () -> ContinuousClock.Instant
    private var anchor: (date: Date, instant: ContinuousClock.Instant)?
    private var revision = 0

    init(instant: @escaping () -> ContinuousClock.Instant = { .now }) { self.instant = instant }

    var now: Date? {
        _ = revision
        guard let anchor else { return nil }
        return anchor.date.addingTimeInterval(Self.seconds(anchor.instant.duration(to: instant())))
    }

    func synchronize(serverTime: Date) {
        let received = instant()
        // Le serveur date l'enveloppe en fin de traitement : ajouter le trajet aller
        // et son attente ferait expirer une offre encore valable. Le serveur juge la commande.
        // Une réponse ancienne arrivant après une autre ne fait pas reculer l'estimation.
        anchor = (max(now ?? serverTime, serverTime), received)
    }

    /// Réveille aussi les écrans observateurs à l'échéance, même si la relecture échoue.
    func wait(until deadline: Date) async throws {
        while let now, deadline > now {
            try await Task.sleep(for: .seconds(deadline.timeIntervalSince(now)))
        }
        try Task.checkCancellation()
        revision += 1
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return max(0, Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
    }
}
