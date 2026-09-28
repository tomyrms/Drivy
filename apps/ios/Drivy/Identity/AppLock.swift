import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// Face ID, Touch ID ou le code de l'appareil rouvrent l'app après une longue absence.
/// La session reste dans le Trousseau : le verrou masque seulement l'interface.
@MainActor
@Observable
final class AppLock {
    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isUnlocking = false
    private(set) var hasAnsweredOffer: Bool

    @ObservationIgnored private let store: UserDefaults
    @ObservationIgnored private var backgroundedAt: Date?
    /// Changer d'app pendant une leçon ne doit pas redemander Face ID à chaque retour.
    @ObservationIgnored private let gracePeriod: TimeInterval = 5 * 60

    private static let enabledKey = "drivy.appLock.enabled"
    private static let offerKey = "drivy.appLock.offerAnswered"

    init(store: UserDefaults = .standard) {
        self.store = store
        let enabled = store.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        // Verrouillé dès le lancement : aucun écran de l'école n'apparaît avant le déverrouillage.
        isLocked = enabled
        hasAnsweredOffer = store.bool(forKey: Self.offerKey)
    }

    /// Nom du capteur de l'appareil, ou nil s'il n'y en a pas (le réglage est alors masqué).
    var biometryName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return nil
        }
    }

    var shouldOffer: Bool { !hasAnsweredOffer && biometryName != nil }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        store.set(enabled, forKey: Self.enabledKey)
        if !enabled { isLocked = false }
    }

    func answerOffer(enable: Bool) {
        hasAnsweredOffer = true
        store.set(true, forKey: Self.offerKey)
        setEnabled(enable)
    }

    func didEnterBackground() { backgroundedAt = Date() }

    func didBecomeActive(authenticated: Bool) {
        defer { backgroundedAt = nil }
        guard isEnabled, authenticated, let since = backgroundedAt,
              Date().timeIntervalSince(since) >= gracePeriod else { return }
        isLocked = true
    }

    /// Sans session, il n'y a rien à protéger : l'écran de connexion reste accessible.
    func sessionEnded() { isLocked = false }

    func unlock() async {
        guard isLocked, !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        let context = LAContext()
        context.localizedCancelTitle = "Annuler"
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Ouvrir Drivy") { success, _ in
                continuation.resume(returning: success)
            }
        }
        if granted { isLocked = false }
    }
}

struct AppLockView: View {
    let lock: AppLock

    var body: some View {
        VStack(spacing: DrivySpacing.xl) {
            Spacer()
            Image(systemName: "map.fill")
                .font(.system(size: 48))
                .foregroundStyle(DrivyTheme.accent)
                .accessibilityHidden(true)
            Text("Drivy")
                .font(.drivyScreenTitle)
                .foregroundStyle(DrivyTheme.text)
            Spacer()
            Button {
                Task { await lock.unlock() }
            } label: {
                Label("Déverrouiller", systemImage: lock.biometryName == "Touch ID" ? "touchid" : "faceid")
            }
            .buttonStyle(DrivyPrimaryButtonStyle())
            .disabled(lock.isUnlocking)
            .accessibilityIdentifier("app-unlock")
            .padding(.horizontal, DrivySpacing.l)
            .padding(.bottom, DrivySpacing.xl)
            .frame(maxWidth: 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DrivyTheme.surface)
        .task { await lock.unlock() }
    }
}
