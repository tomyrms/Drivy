import Observation
import SwiftUI
import UIKit

/// Suivi de l’attente d’un envoi sur les feuilles d’accès : l’étape en cours, puis « la réponse tarde » au-delà
/// du seuil. Il n’accorde rien et ne décide rien : l’accès reste celui que le serveur a prouvé, l’interface explique
/// seulement l’attente. Une relance rejoue la fermeture du modèle, qui garde sa propre opération (même identifiant,
/// même intention du journal) : le moniteur ne crée jamais une nouvelle demande.
@MainActor @Observable final class SchoolWaitMonitor {
    enum Phase: Equatable {
        case idle, waiting, pending, slow

        func announcement(title: String) -> String? {
            switch self {
            case .idle: nil
            case .waiting: title
            case .pending: "Demande en cours"
            case .slow: "La réponse tarde."
            }
        }
    }

    /// Seuils de présentation indicatifs : aucune preuve de réception ni de résultat.
    static let pendingThreshold: Duration = .seconds(5)
    static let slowThreshold: Duration = .seconds(10)

    private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { onPhase?(phase) } }
    }
    /// Appelé à chaque changement de phase : une annonce vocale par palier, jamais une répétition.
    @ObservationIgnored var onPhase: ((Phase) -> Void)?
    @ObservationIgnored private let slowAfter: Duration
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void
    @ObservationIgnored private let now: @MainActor () -> ContinuousClock.Instant
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var token = 0

    init(slowAfter: Duration = SchoolWaitMonitor.slowThreshold,
         sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.slowAfter = slowAfter
        self.sleep = sleep
        self.now = now
    }

    /// Lance l’envoi et mesure son attente.
    func run(_ operation: @escaping @MainActor () async -> Void) {
        watch?.cancel()
        token &+= 1
        let mine = token
        phase = .waiting
        let slowAfter = slowAfter, sleep = sleep, now = now
        let started = now()
        watch = Task { [weak self] in
            // Échéances depuis le même départ : un réveil tardif ne repousse pas le second palier.
            for (delay, next) in [(min(Self.pendingThreshold, slowAfter), Phase.pending), (slowAfter, Phase.slow)] {
                do {
                    try await sleep(max(.zero, delay - started.duration(to: now())))
                    try Task.checkCancellation()
                } catch { return }
                guard let self, self.token == mine, self.phase != .idle else { return }
                self.phase = next
            }
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

/// Ligne discrète dès 5 s ; à 10 s, « Réessayer » seulement si le modèle fournit cette action.
struct SchoolWaitLine: View {
    let monitor: SchoolWaitMonitor
    let retry: (() -> Void)?

    var body: some View {
        if monitor.phase == .pending || monitor.phase == .slow {
            VStack(alignment: .leading, spacing: 0) {
                Label(monitor.phase == .slow ? "La réponse tarde." : "Demande en cours", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(monitor.phase == .slow ? "wait-slow" : "wait-pending")
                if monitor.phase == .slow, let retry {
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
            guard phase == monitor.phase, let announcement = phase.announcement(title: title) else { return }
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }
}

extension View {
    /// Annonce l’action, puis chacun des deux paliers, sans déplacer le focus.
    func schoolWaitAnnouncements(_ monitor: SchoolWaitMonitor, title: String) -> some View {
        modifier(SchoolWaitAnnouncements(monitor: monitor, title: title))
    }
}
