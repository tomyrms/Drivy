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
    private(set) var errorMessage: String?
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
        if !enabled { isLocked = false; errorMessage = nil }
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
    func sessionEnded() { isLocked = false; errorMessage = nil }

    func unlock() async {
        guard isLocked, !isUnlocking else { return }
        isUnlocking = true; errorMessage = nil
        defer { isUnlocking = false }
        let context = LAContext()
        context.localizedCancelTitle = "Annuler"
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Ouvrir Drivy") { success, _ in
                continuation.resume(returning: success)
            }
        }
        if granted { isLocked = false }
        else { errorMessage = "Le déverrouillage n’a pas abouti. Réessaie avec la reconnaissance biométrique ou le code de l’appareil." }
    }
}

struct AppLockView: View {
    let lock: AppLock
    var automaticallyUnlocks = true
    @ScaledMetric(relativeTo: .largeTitle) private var plate: CGFloat = 96

    var body: some View {
        // The lock sits in the optical centre of the screen; the error, when there is
        // one, stays next to it and the single action stays at the bottom.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: DrivySpacing.l) {
                    Image(systemName: "lock.fill")
                        .font(.largeTitle)
                        .foregroundStyle(DrivyTheme.muted)
                        .frame(width: plate, height: plate)
                        .background(DrivyTheme.surfaceMuted, in: Circle())
                        .accessibilityHidden(true)
                    Text("Drivy verrouillé")
                        .font(.drivyTitle)
                        .foregroundStyle(DrivyTheme.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let error = lock.errorMessage { SchoolErrorNotice(message: error) }
                }
                .frame(maxWidth: .infinity)
                .drivyPageContent(maxWidth: DrivyLayout.narrowColumn)
                .frame(minHeight: proxy.size.height)
            }
        }
        .background(DrivyTheme.surface)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DrivyStickyActionBar {
                Button {
                    Task { await lock.unlock() }
                } label: {
                    DrivyBusyLabel(title: "Déverrouiller", busyTitle: "Déverrouillage…", isBusy: lock.isUnlocking)
                }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(lock.isUnlocking)
                .accessibilityIdentifier("app-unlock")
            }
        }
        .task { if automaticallyUnlocks { await lock.unlock() } }
    }
}
