import SwiftUI
import UIKit

/// Rideau de marque du démarrage d’un trajet. Il vit dans sa propre fenêtre, au-dessus des feuilles : il apparaît
/// en fondu dès le geste, cache l’enchaînement des écrans (feuille refermée, préparation, carte) et s’efface en
/// fondu quand le trajet est prêt, ou tout de suite quand une action de la personne est nécessaire.
/// Les alertes du système (autorisation de localisation) restent au-dessus de lui.
@MainActor @Observable final class DrivyLaunchCurtain {
    static let shared = DrivyLaunchCurtain()
    /// Le rideau ne se lève pas avant que le symbole soit assemblé (tige posée, anneau arrivé) : plus tôt, il
    /// clignoterait. Au-delà, il ne reste que le temps des opérations réelles, jamais la séquence entière.
    static let minimumShown = 1.1
    /// Un rideau oublié bloquerait toute l’app : sans étape franchie pendant ce délai, il se lève.
    static let watchdogDelay = 40.0

    /// Début de la séquence ; elle ne se rejoue pas tant que le rideau reste montré.
    private(set) var start: Date?
    /// Étape en cours, annoncée seulement aux technologies d’assistance.
    var step: String?
    /// Sortie en cours : le symbole s’efface le premier, le fond le suit et découvre l’écran prêt.
    private(set) var isLeaving = false
    /// Avancement du départ, de 0 à 1 : il ne recule jamais et se remplit à la levée du rideau.
    private(set) var progress = 0.0
    /// Durée du mouvement vers `progress` : longue pendant l’attente de la première position.
    private(set) var progressDuration = 0.5
    @ObservationIgnored private var window: UIWindow?
    @ObservationIgnored private var generation = 0
    /// Garde-fou du rideau montré ; arrêté dès que le rideau s’efface.
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    var isShown: Bool { window != nil }

    func show() {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        generation += 1
        let token = generation
        start = Date()
        isLeaving = false
        progress = 0.08; progressDuration = 0.5
        // Le clavier d’un champ encore actif resterait au-dessus du rideau.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let host = UIHostingController(rootView: DrivyLaunchCurtainView(curtain: self))
        host.view.backgroundColor = .clear
        host.view.accessibilityViewIsModal = true
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 1)
        window.rootViewController = host
        window.alpha = 0
        window.isHidden = false
        self.window = window
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) { window.alpha = 1 }
        armWatchdog(token)
    }

    /// Garde-fou réarmé à chaque étape franchie : un départ lent mais vivant n’est pas coupé, un rideau oublié l’est.
    private func armWatchdog(_ token: Int) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            // Arrêté par `hide()` : il ne reste pas en attente après chaque départ.
            do { try await Task.sleep(for: .seconds(Self.watchdogDelay)) } catch { return }
            guard let self, token == self.generation else { return }
            await self.hide()
        }
    }

    /// Fait avancer la barre vers `value`, sans jamais reculer.
    func advance(to value: Double, over duration: Double = 0.5) {
        guard window != nil, value > progress else { return }
        progressDuration = duration
        progress = min(1, value)
        armWatchdog(generation)
    }

    /// Une étape du départ est franchie ; le dernier quart reste au trajet confirmé et à sa première position.
    func advanceStep() {
        advance(to: min(0.75, progress + 0.14))
        // La barre plafonne, pas le garde-fou : chaque étape franchie le repousse.
        if window != nil { armWatchdog(generation) }
    }

    /// Efface le rideau. `afterSequence` (départ abouti) laisse le symbole s’assembler (`minimumShown`), puis
    /// attend `ready` (la première position du trajet, par exemple) sans dépasser `atMost` secondes après l’appel.
    func hide(afterSequence: Bool = false, waitingFor ready: (@MainActor () -> Bool)? = nil, atMost: Double = 7) async {
        guard let window, let start else { return }
        let token = generation
        if afterSequence {
            // Sept secondes au plus après la demande : au-delà, l’écran dit lui-même qu’il attend une position.
            let deadline = Date().addingTimeInterval(atMost)
            advance(to: 0.85)
            let remaining = Self.minimumShown - Date().timeIntervalSince(start)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            if let ready {
                // La barre avance doucement pendant l’attente, sans jamais se dire terminée avant la position.
                if token == generation, !ready() { advance(to: 0.97, over: max(0.5, deadline.timeIntervalSinceNow)) }
                var waited = false
                while token == generation, !ready(), Date() < deadline {
                    waited = true
                    // Une tâche annulée ne dort plus : sans cette sortie, l’attente tournerait à vide sur le fil principal.
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
                }
                // La carte vient de recevoir sa première position : un instant pour qu’elle se dessine sous le rideau.
                if waited, token == generation, ready() { try? await Task.sleep(for: .milliseconds(400)) }
            }
        }
        guard token == generation, self.window === window else { return }
        generation += 1
        watchdog?.cancel(); watchdog = nil
        // Le contenu reste dessiné pendant le fondu : le vider ici couperait net le symbole et le fond.
        self.window = nil; step = nil
        // Un départ abouti remplit la barre ; un refus la laisse où elle en est.
        if afterSequence { progressDuration = 0.25; progress = 1 }
        isLeaving = true
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: reduceMotion ? 0.3 : 0.45, delay: reduceMotion ? 0 : 0.1, options: [.curveEaseInOut, .beginFromCurrentState]) {
            window.alpha = 0
        } completion: { _ in
            window.isHidden = true
            // Un nouveau départ lancé pendant le fondu garde sa séquence.
            if self.window == nil { self.start = nil; self.isLeaving = false; self.progress = 0 }
        }
    }
}

private struct DrivyLaunchCurtainView: View {
    let curtain: DrivyLaunchCurtain

    var body: some View {
        if let start = curtain.start {
            SchoolTripLaunchScreen(start: start, step: curtain.step, isLeaving: curtain.isLeaving,
                progress: curtain.progress, progressDuration: curtain.progressDuration)
        } else {
            Color.clear
        }
    }
}
