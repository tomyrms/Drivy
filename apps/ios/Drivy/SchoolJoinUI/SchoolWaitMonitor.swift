import Observation
import SwiftUI
import UIKit

/// Suivi de l’attente d’un envoi sur les feuilles d’accès : l’étape en cours, puis « la réponse tarde » au-delà
/// du seuil. Il n’accorde rien et ne décide rien : l’accès reste celui que le serveur a prouvé, l’interface explique
/// seulement l’attente. Une relance rejoue la fermeture du modèle, qui garde sa propre opération (même identifiant,
/// même intention du journal) : le moniteur ne crée jamais une nouvelle demande.
@MainActor @Observable final class SchoolWaitMonitor {
    enum Phase: Equatable { case idle, waiting, slow }

    /// Seuil indicatif de #105 pour le « lent » ; le premier palier (5 s) n’a pas d’affichage propre.
    static let slowThreshold: Duration = .seconds(10)

    private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { onPhase?(phase) } }
    }
    /// Appelé à chaque changement de phase : une annonce vocale par palier, jamais une répétition.
    @ObservationIgnored var onPhase: ((Phase) -> Void)?
    @ObservationIgnored private let slowAfter: Duration
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var token = 0

    init(slowAfter: Duration = SchoolWaitMonitor.slowThreshold,
         sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.slowAfter = slowAfter
        self.sleep = sleep
    }

    /// Lance l’envoi et mesure son attente.
    func run(_ operation: @escaping @MainActor () async -> Void) {
        watch?.cancel()
        token &+= 1
        let mine = token
        phase = .waiting
        let slowAfter = slowAfter, sleep = sleep
        watch = Task { [weak self] in
            do { try await sleep(slowAfter) } catch { return }
            guard let self, self.token == mine, self.phase == .waiting else { return }
            self.phase = .slow
        }
        task = Task { [weak self] in
            await operation()
            guard let self, self.token == mine else { return }
            self.watch?.cancel()
            self.phase = .idle
        }
    }

    /// Annule l’appel parti, attend sa fin, puis rejoue `again`. Celle-ci doit relire l’état du modèle et ne
    /// rien envoyer si la réponse est déjà arrivée.
    func retry(_ again: @escaping @MainActor () async -> Void) {
        let previous = task
        previous?.cancel()
        run {
            await previous?.value
            await again()
        }
    }

    func waitUntilIdle() async { await task?.value }
}

/// Ligne discrète au-dessus de l’action : la réponse tarde, et « Réessayer » quand la même opération peut repartir.
struct SchoolWaitLine: View {
    let monitor: SchoolWaitMonitor
    let retry: (() -> Void)?

    var body: some View {
        if monitor.phase == .slow {
            VStack(alignment: .leading, spacing: 0) {
                Label("La réponse tarde.", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("wait-slow")
                if let retry {
                    SchoolJoinTextLink(title: "Réessayer", isBusy: false, action: retry)
                        .accessibilityIdentifier("wait-retry")
                }
            }
        }
    }
}

private struct SchoolWaitAnnouncements: ViewModifier {
    let monitor: SchoolWaitMonitor
    let title: String

    func body(content: Content) -> some View {
        content.onChange(of: monitor.phase) { _, phase in
            switch phase {
            case .idle: break
            case .waiting: UIAccessibility.post(notification: .announcement, argument: title)
            case .slow: UIAccessibility.post(notification: .announcement, argument: "La réponse tarde.")
            }
        }
    }
}

extension View {
    /// Annonce une fois l’étape en attente, puis une fois son dépassement.
    func schoolWaitAnnouncements(_ monitor: SchoolWaitMonitor, title: String) -> some View {
        modifier(SchoolWaitAnnouncements(monitor: monitor, title: title))
    }
}
