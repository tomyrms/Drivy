import Foundation
import Network
import Observation

/// Observe seulement la disponibilité pendant l'écran Messages, sans tâche réseau permanente.
@MainActor @Observable final class MessagingConnectivity: @unchecked Sendable {
    private(set) var available = false
    private var monitor: NWPathMonitor?
    private var generation = 0

    func start() {
        guard monitor == nil else { return }
        generation += 1
        let activeGeneration = generation
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self, self.generation == activeGeneration else { return }
                self.available = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "fr.drivy.messaging.network"))
    }

    func stop() {
        generation += 1
        monitor?.cancel()
        monitor = nil
        available = false
    }
}
