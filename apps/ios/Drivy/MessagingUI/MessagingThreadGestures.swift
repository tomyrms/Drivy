import SwiftUI
import UIKit

/// Glisser vers la gauche pour répondre. Ne démarre que pour un mouvement horizontal vers la gauche : un mouvement
/// vertical le fait échouer aussitôt et la liste défile. Mesures en coordonnées de fenêtre, car la liste d'Exyte est
/// retournée et la fenêtre ne l'est pas.
struct MessagingReplySwipeGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeUIGestureRecognizer(context: Context) -> LeftSwipeRecognizer {
        let recognizer = LeftSwipeRecognizer(target: nil, action: nil)
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: LeftSwipeRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: LeftSwipeRecognizer, context: Context) {
        switch recognizer.state {
        case .changed: onChanged(recognizer.translation(in: recognizer.view?.window).x)
        case .ended, .cancelled, .failed: onEnded()
        default: break
        }
    }

    final class LeftSwipeRecognizer: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
        override init(target: Any?, action: Selector?) {
            super.init(target: target, action: action)
            delegate = self
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let speed = velocity(in: view?.window)
            return speed.x < 0 && abs(speed.x) > abs(speed.y) * 1.2
        }

        /// La liste attend l'échec du glisser avant de défiler.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

/// Appui long court qui ouvre le menu dès qu'il est reconnu, sans attendre que le doigt se lève.
struct MessagingMenuPressGesture: UIGestureRecognizerRepresentable {
    static let duration: TimeInterval = 0.25
    let isEnabled: Bool
    let action: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer(target: nil, action: nil)
        recognizer.minimumPressDuration = Self.duration
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        if recognizer.state == .began { action() }
    }
}
