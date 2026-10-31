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
    private let aliasStore: any MessagingDeviceAliases
    private let currentScope: @MainActor @Sendable () -> MessagingScope?
    private var active = false
    private var generation = 0
    private(set) var snapshot: MessagingDeviceVerificationSnapshot?
    private(set) var selected: MessagingOwnDevice?
    private(set) var verifiedDeviceID: String?
    private(set) var failure: Failure?
    private(set) var working = false
    private(set) var aliases: [String: String] = [:]
    private(set) var aliasError: String?
    var compared = false

    init(scope: MessagingScope, keys: any MessagingKeyManagement,
         aliasStore: any MessagingDeviceAliases = MessagingKeychainDeviceAliases(),
         currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) {
        self.scope = scope
        self.keys = keys
        self.aliasStore = aliasStore
        self.currentScope = currentScope
    }

    func alias(_ device: MessagingOwnDevice) -> String? { aliases[MessagingDeviceAliasRules.identity(device)] }
    func displayName(_ device: MessagingOwnDevice) -> String { alias(device) ?? "Appareil" }
    func reference(_ device: MessagingOwnDevice) -> String {
        let devices = (snapshot?.devices ?? []) + (snapshot.map { [$0.localDevice] } ?? [])
        var length = min(6, device.id.count)
        while length < device.id.count,
              devices.contains(where: { $0.id != device.id && $0.id.suffix(length) == device.id.suffix(length) }) { length += 1 }
        return String(device.id.suffix(length))
    }
    func canRename(_ device: MessagingOwnDevice) -> Bool {
        let devices = (snapshot?.devices ?? []) + (snapshot.map { [$0.localDevice] } ?? [])
        return active && currentScope() == scope && !working && !device.fingerprint.isEmpty
            && devices.contains { $0.id == device.id && $0.fingerprint == device.fingerprint }
    }
    func saveAlias(_ text: String, device: MessagingOwnDevice) async -> Bool {
        guard canRename(device) else { return false }
        let name = MessagingDeviceAliasRules.normalized(text)
        guard MessagingDeviceAliasRules.valid(name) else {
            aliasError = "Choisis un nom de 64 caractères au maximum, sur une seule ligne."; return false
        }
        generation += 1
        let token = generation
        working = true; aliasError = nil
        defer { if generation == token { working = false } }
        do {
            let saved = try await aliasStore.set(name, device: device, scope: scope)
            guard accepts(token) else { return false }
            aliases = saved
            return true
        } catch {
            guard accepts(token) else { return false }
            aliasError = "Le nom local n’a pas pu être enregistré. Réessaie."
            return false
        }
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
            do {
                let names = try await aliasStore.load(scope: scope)
                guard accepts(token) else { return }
                aliases = names; aliasError = nil
            } catch {
                guard accepts(token) else { return }
                aliases = [:]
                aliasError = "Les noms locaux ne sont pas disponibles. Les identifiants et empreintes restent consultables."
            }
        } catch {
            guard accepts(token) else { return }
            snapshot = nil
            aliases = [:]
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
        aliases = [:]; aliasError = nil
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
