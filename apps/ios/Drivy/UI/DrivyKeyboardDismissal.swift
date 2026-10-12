import SwiftUI
import UIKit

extension View {
    /// Un toucher hors d’un champ de saisie ferme le clavier, sans retenir ce toucher : un bouton touché reste un
    /// bouton touché. Pour un formulaire dont le champ multiligne garde « Retour » pour aller à la ligne et qui ne
    /// défile pas toujours : sans ce geste, rien ne fermait le clavier. Le texte saisi reste tel quel, rien n’est
    /// enregistré par la fermeture.
    func drivyDismissesKeyboardOnOutsideTap() -> some View {
        background(DrivyOutsideTapKeyboardDismissal().frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

/// Pose sur la fenêtre un geste de toucher qui n’annule aucun autre toucher et ignore ceux qui tombent dans un
/// champ de texte ; il ne vit que tant que la vue hôte est à l’écran.
private struct DrivyOutsideTapKeyboardDismissal: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {}

    static func dismantleUIView(_ uiView: HostView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class HostView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { coordinator?.attach(to: window) } else { coordinator?.detach() }
        }
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var recognizer: UITapGestureRecognizer?
        private weak var window: UIWindow?

        func attach(to window: UIWindow) {
            guard self.window !== window else { return }
            detach()
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            recognizer = tap
            self.window = window
        }

        func detach() {
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            window = nil
        }

        @objc private func tapped() {
            window?.endEditing(true)
        }

        /// Un toucher dans un champ (ou ses poignées de sélection) le laisse ouvert : seul l’extérieur ferme.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextView || current is UITextField { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
