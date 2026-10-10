import SwiftUI
import UIKit

/// Rideau de marque du démarrage d’un trajet. Il vit dans sa propre fenêtre, au-dessus des feuilles : il apparaît
/// en fondu dès le geste, cache l’enchaînement des écrans (feuille refermée, préparation, carte) et s’efface en
/// fondu quand le trajet est prêt, ou tout de suite quand une action de la personne est nécessaire.
/// Les alertes du système (autorisation de localisation) restent au-dessus de lui.
@MainActor @Observable final class DrivyLaunchCurtain {
    static let shared = DrivyLaunchCurtain()

    /// Début de la séquence ; elle ne se rejoue pas tant que le rideau reste montré.
    private(set) var start: Date?
    /// Étape en cours, annoncée seulement aux technologies d’assistance.
    var step: String?
    /// Sortie en cours : le symbole s’efface le premier, le fond le suit et découvre l’écran prêt.
    private(set) var isLeaving = false
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
        // Garde-fou : un rideau oublié bloquerait toute l’app. Aucun départ ne dure aussi longtemps.
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            // Arrêté par `hide()` : il ne reste pas en attente quarante secondes après chaque départ.
            do { try await Task.sleep(for: .seconds(40)) } catch { return }
            guard let self, token == self.generation else { return }
            await self.hide()
        }
    }

    /// Efface le rideau. `afterSequence` laisse la séquence se terminer, puis attend `ready` (la première
    /// position sur la carte, par exemple) sans dépasser `atMost` secondes.
    func hide(afterSequence: Bool = false, waitingFor ready: (@MainActor () -> Bool)? = nil, atMost: Double = 5) async {
        guard let window, let start else { return }
        let token = generation
        if afterSequence {
            let remaining = DrivyLaunchTimeline.duration - Date().timeIntervalSince(start)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            if let ready {
                let deadline = Date().addingTimeInterval(atMost)
                while token == generation, !ready(), Date() < deadline {
                    // Une tâche annulée ne dort plus : sans cette sortie, l’attente tournerait à vide sur le fil principal.
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
                }
            }
        }
        guard token == generation, self.window === window else { return }
        generation += 1
        watchdog?.cancel(); watchdog = nil
        // Le contenu reste dessiné pendant le fondu : le vider ici couperait net le symbole et le fond.
        self.window = nil; step = nil
        isLeaving = true
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: reduceMotion ? 0.3 : 0.45, delay: reduceMotion ? 0 : 0.1, options: [.curveEaseInOut, .beginFromCurrentState]) {
            window.alpha = 0
        } completion: { _ in
            window.isHidden = true
            // Un nouveau départ lancé pendant le fondu garde sa séquence.
            if self.window == nil { self.start = nil; self.isLeaving = false }
        }
    }
}

private struct DrivyLaunchCurtainView: View {
    let curtain: DrivyLaunchCurtain

    var body: some View {
        if let start = curtain.start {
            SchoolTripLaunchScreen(start: start, step: curtain.step, isLeaving: curtain.isLeaving)
        } else {
            Color.clear
        }
    }
}
