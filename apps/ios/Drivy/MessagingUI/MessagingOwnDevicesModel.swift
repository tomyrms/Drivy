import Foundation
import Observation

@MainActor
@Observable
final class MessagingOwnDevicesModel {
    enum Failure: Equatable {
        case loadFailed, verificationFailed, contextChanged
        var message: String {
            switch self {
            case .loadFailed: "Les appareils n’ont pas pu être chargés. Réessaie."
            case .verificationFailed: "La vérification n’a pas abouti. Réessaie après avoir comparé les empreintes."
            case .contextChanged: MessagingFailure.contextChanged.localizedDescription
            }
        }
    }

    let scope: MessagingScope
    private let keys: any MessagingKeyManagement
    private let currentScope: @MainActor @Sendable () -> MessagingScope?
    private var active = false
    private var generation = 0
    private(set) var snapshot: MessagingDeviceVerificationSnapshot?
    private(set) var selected: MessagingOwnDevice?
    private(set) var verifiedDeviceID: String?
    private(set) var failure: Failure?
    private(set) var working = false
    var compared = false

    init(scope: MessagingScope, keys: any MessagingKeyManagement,
         currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) {
        self.scope = scope
        self.keys = keys
        self.currentScope = currentScope
    }

    var canConfirm: Bool {
        guard active, currentScope() == scope, !working, compared,
              snapshot?.capability == .available, let selected, !selected.isCurrent,
              !selected.isVerified, !selected.fingerprint.isEmpty else { return false }
        return snapshot?.devices.contains(selected) == true && verifiedDeviceID == nil
    }

    func activate() async {
        active = true
        await refresh()
    }

    func refresh() async {
        guard active, !working else { return }
        generation += 1
        let token = generation
        guard accepts(token) else { return }
        working = true
        failure = nil
        defer { if generation == token { working = false } }
        do {
            let value = try await keys.deviceVerificationSnapshot(scope: scope)
            guard accepts(token) else { return }
            snapshot = value
            selected = nil
            compared = false
            verifiedDeviceID = nil
        } catch {
            guard accepts(token) else { return }
            snapshot = nil
            failure = error is CancellationError ? nil : .loadFailed
        }
    }

    func select(_ device: MessagingOwnDevice) {
        guard active, !working, currentScope() == scope, !device.isCurrent,
              snapshot?.devices.contains(device) == true else { return }
        selected = device
        compared = false
        verifiedDeviceID = nil
        failure = nil
    }

    func confirm() async {
        guard canConfirm, let target = selected else { return }
        generation += 1
        let token = generation
        working = true
        failure = nil
        verifiedDeviceID = nil
        defer { if generation == token { working = false } }
        do {
            try await keys.confirmOwnDevice(deviceID: target.id, fingerprint: target.fingerprint, scope: scope)
            guard accepts(token) else { return }
            let value = try await keys.deviceVerificationSnapshot(scope: scope)
            guard accepts(token) else { return }
            guard value.devices.contains(where: {
                $0.id == target.id && $0.fingerprint == target.fingerprint && $0.isVerified
            }) else { throw MessagingFailure.protectionUnavailable }
            snapshot = value
            verifiedDeviceID = target.id
        } catch {
            guard accepts(token) else { return }
            failure = error is CancellationError ? nil : .verificationFailed
        }
    }

    func cancelComparison() {
        generation += 1
        selected = nil
        compared = false
        verifiedDeviceID = nil
        failure = nil
        working = false
    }

    func invalidate() {
        active = false
        cancelComparison()
        snapshot = nil
    }

    private func accepts(_ token: Int) -> Bool {
        guard active, token == generation else { return false }
        guard currentScope() == scope else {
            invalidate()
            failure = .contextChanged
            return false
        }
        return true
    }
}
