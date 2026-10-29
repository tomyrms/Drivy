import XCTest
@testable import Drivy

@MainActor
final class MessagingOwnDevicesTests: XCTestCase {
    private let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1,
                                       apiBaseURL: "https://device-ui.example.invalid")
    private let current = MessagingOwnDevice(id: "LOCALDEVICE1", fingerprint: "local-public-fingerprint",
                                             isCurrent: true, isVerified: false)
    private let other = MessagingOwnDevice(id: "OTHERDEVICE1", fingerprint: "other-public-fingerprint",
                                           isCurrent: false, isVerified: false)

    private func keys(capability: MessagingDeviceVerificationSnapshot.Capability = .available) -> DeviceVerificationKeys {
        DeviceVerificationKeys(snapshot: MessagingDeviceVerificationSnapshot(localDevice: current, devices: [other], capability: capability))
    }

    func testComparisonIsRequiredBeforeSignature() async {
        let keys = keys()
        let model = MessagingOwnDevicesModel(scope: scope, keys: keys, currentScope: { [scope] in scope })
        await model.activate()
        model.select(other)
        await model.confirm()
        let calls = await keys.confirmationCount()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(model.verifiedDeviceID)
        XCTAssertFalse(model.canConfirm)
    }

    func testCancelComparisonNeverSigns() async {
        let keys = keys()
        let model = MessagingOwnDevicesModel(scope: scope, keys: keys, currentScope: { [scope] in scope })
        await model.activate()
        model.select(other)
        model.compared = true
        model.cancelComparison()
        await model.confirm()
        let calls = await keys.confirmationCount()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(model.selected)
    }

    func testSuccessfulConfirmationRequiresReloadedTrust() async {
        let keys = keys()
        let model = MessagingOwnDevicesModel(scope: scope, keys: keys, currentScope: { [scope] in scope })
        await model.activate()
        XCTAssertEqual(model.snapshot?.localDevice.fingerprint, current.fingerprint)
        model.select(other)
        model.compared = true
        await model.confirm()
        XCTAssertEqual(model.verifiedDeviceID, other.id)
        XCTAssertTrue(model.snapshot?.devices.first?.isVerified == true)
        XCTAssertNil(model.failure)
    }

    func testSuccessWithoutReloadedTrustIsNotShownAsVerified() async {
        let keys = keys()
        await keys.setPersistVerification(false)
        let model = MessagingOwnDevicesModel(scope: scope, keys: keys, currentScope: { [scope] in scope })
        await model.activate()
        model.select(other)
        model.compared = true
        await model.confirm()
        XCTAssertNil(model.verifiedDeviceID)
        XCTAssertNotNil(model.failure)
    }

    func testSignatureFailurePreservesComparisonForExplicitRetry() async {
        let keys = keys()
        await keys.setFailure(.unavailable)
        let model = MessagingOwnDevicesModel(scope: scope, keys: keys, currentScope: { [scope] in scope })
        await model.activate()
        model.select(other)
        model.compared = true
        await model.confirm()
        XCTAssertNil(model.verifiedDeviceID)
        XCTAssertNotNil(model.failure)
        XCTAssertFalse(model.working)
        await keys.setFailure(nil)
        await model.confirm()
        XCTAssertEqual(model.verifiedDeviceID, other.id)
    }

    func testMissingPrivateKeyBlocksConfirmationWithoutHidingLocalFingerprint() async {
        let keys = keys(capability: .originalDeviceRequired)
        let model = MessagingOwnDevicesModel(scope: scope, keys: keys, currentScope: { [scope] in scope })
        await model.activate()
        model.select(other)
        model.compared = true
        XCTAssertFalse(model.canConfirm)
        XCTAssertEqual(model.snapshot?.localDevice.fingerprint, current.fingerprint)
        await model.confirm()
        let calls = await keys.confirmationCount()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(model.verifiedDeviceID)
    }

    func testDoubleConfirmationDoesNotDuplicateSignature() async {
        let keys = keys()
        await keys.holdConfirmation()
        let model = MessagingOwnDevicesModel(scope: scope, keys: keys, currentScope: { [scope] in scope })
        await model.activate()
        model.select(other)
        model.compared = true
        let first = Task { await model.confirm() }
        await keys.waitForConfirmation()
        await model.confirm()
        let calls = await keys.confirmationCount()
        XCTAssertEqual(calls, 1)
        await keys.releaseConfirmation()
        await first.value
        XCTAssertEqual(model.verifiedDeviceID, other.id)
    }

    func testScopeChangedDuringConfirmationDropsLateSuccess() async {
        let keys = keys()
        await keys.holdConfirmation()
        let box = ScopeBox(scope)
        let model = MessagingOwnDevicesModel(scope: scope, keys: keys, currentScope: { box.value })
        await model.activate()
        model.select(other)
        model.compared = true
        let task = Task { await model.confirm() }
        await keys.waitForConfirmation()
        box.value = nil
        await keys.releaseConfirmation()
        await task.value
        XCTAssertNil(model.verifiedDeviceID)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.selected)
        XCTAssertNotNil(model.failure)
    }

    func testDismissalDuringConfirmationDropsLateSuccess() async {
        let keys = keys()
        await keys.holdConfirmation()
        let model = MessagingOwnDevicesModel(scope: scope, keys: keys, currentScope: { [scope] in scope })
        await model.activate()
        model.select(other)
        model.compared = true
        let task = Task { await model.confirm() }
        await keys.waitForConfirmation()
        model.invalidate()
        await keys.releaseConfirmation()
        await task.value
        XCTAssertNil(model.verifiedDeviceID)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.selected)
    }

    func testSettingsCompositionUsesLiveScopeBeforeConfirmation() async {
        let keys = keys()
        let box = ScopeBox(scope)
        let settings = MessagingSettingsView(keys: keys, scope: scope, currentScope: { box.value })
        let model = settings.makeDevicesModel(keys: keys)
        await model.activate()
        model.select(other)
        model.compared = true
        box.value = MessagingScope(accountID: scope.accountID, schoolID: UUID(), accessEpoch: 2,
                                   apiBaseURL: scope.apiBaseURL)
        XCTAssertFalse(model.canConfirm)
        await model.confirm()
        let calls = await keys.confirmationCount()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(model.verifiedDeviceID)
    }

    func testSettingsCompositionDropsLateSuccessAfterSignOut() async {
        let keys = keys()
        await keys.holdConfirmation()
        let box = ScopeBox(scope)
        let settings = MessagingSettingsView(keys: keys, scope: scope, currentScope: { box.value })
        let model = settings.makeDevicesModel(keys: keys)
        await model.activate()
        model.select(other)
        model.compared = true
        let task = Task { await model.confirm() }
        await keys.waitForConfirmation()
        box.value = nil
        await keys.releaseConfirmation()
        await task.value
        XCTAssertNil(model.verifiedDeviceID)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.selected)
        XCTAssertEqual(model.failure, .contextChanged)
    }

    func testLocalNameIsDurableBeforeDisplayAndDoesNotVerifyTheDevice() async {
        let keys = keys(), aliases = DeviceAliasMemory()
        let model = MessagingOwnDevicesModel(scope: scope, keys: keys, aliasStore: aliases, currentScope: { [scope] in scope })
        await model.activate()
        model.select(other)
        let saved = await model.saveAlias(" Téléphone de travail ", device: other)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.displayName(other), "Téléphone de travail")
        XCTAssertFalse(model.canConfirm)
        XCTAssertNil(model.verifiedDeviceID)
        let count = await keys.confirmationCount()
        XCTAssertEqual(count, 0)
        await model.refresh()
        XCTAssertEqual(model.alias(other), "Téléphone de travail")
        let removed = await model.saveAlias("  ", device: other)
        XCTAssertTrue(removed)
        XCTAssertNil(model.alias(other))
    }

    func testFailedNameStoragePreservesTheOldNameAndDoesNotBlockFingerprintComparison() async {
        let keys = keys(), aliases = DeviceAliasMemory()
        let model = MessagingOwnDevicesModel(scope: scope, keys: keys, aliasStore: aliases, currentScope: { [scope] in scope })
        await model.activate()
        _ = await model.saveAlias("Ancien nom", device: other)
        await aliases.setFailure(true)
        let saved = await model.saveAlias("Nouveau nom", device: other)
        XCTAssertFalse(saved)
        XCTAssertEqual(model.alias(other), "Ancien nom")
        XCTAssertNotNil(model.aliasError)
        model.select(other); model.compared = true
        XCTAssertTrue(model.canConfirm)
    }

    func testDuplicateNamesRemainDistinctAndAReplacedFingerprintDoesNotInheritTheName() async {
        let keys = keys(), aliases = DeviceAliasMemory()
        let model = MessagingOwnDevicesModel(scope: scope, keys: keys, aliasStore: aliases, currentScope: { [scope] in scope })
        await model.activate()
        _ = await model.saveAlias("Mon appareil", device: current)
        _ = await model.saveAlias("Mon appareil", device: other)
        XCTAssertEqual(model.displayName(current), model.displayName(other))
        XCTAssertNotEqual(model.reference(current), model.reference(other))
        let replaced = MessagingOwnDevice(id: other.id, fingerprint: "replacement-public-key", isCurrent: false, isVerified: false)
        await keys.replaceSnapshot(.init(localDevice: current, devices: [replaced], capability: .available))
        await model.refresh()
        XCTAssertNil(model.alias(replaced))
        XCTAssertFalse(model.canRename(other))
        XCTAssertTrue(model.canRename(replaced))
    }

    func testAliasScopeIncludesAccountSchoolEpochAndServer() throws {
        let original = try MessagingDeviceAliasRules.account(scope)
        let scopes = [
            MessagingScope(accountID: UUID(), schoolID: scope.schoolID, accessEpoch: 1, apiBaseURL: scope.apiBaseURL),
            MessagingScope(accountID: scope.accountID, schoolID: UUID(), accessEpoch: 1, apiBaseURL: scope.apiBaseURL),
            MessagingScope(accountID: scope.accountID, schoolID: scope.schoolID, accessEpoch: 2, apiBaseURL: scope.apiBaseURL),
            MessagingScope(accountID: scope.accountID, schoolID: scope.schoolID, accessEpoch: 1, apiBaseURL: "https://other.example.invalid")
        ]
        for changed in scopes { XCTAssertNotEqual(try MessagingDeviceAliasRules.account(changed), original) }
        XCTAssertTrue(MessagingDeviceAliasRules.valid(String(repeating: "👨‍👩‍👧", count: 64)))
        XCTAssertFalse(MessagingDeviceAliasRules.valid(String(repeating: "é", count: 65)))
        XCTAssertFalse(MessagingDeviceAliasRules.valid("Nom\navec une autre ligne"))
    }

    func testANameSavedAfterScopeChangeIsNeverShownInTheNewContext() async {
        let keys = keys(), aliases = DeviceAliasMemory()
        let box = ScopeBox(scope)
        let model = MessagingOwnDevicesModel(scope: scope, keys: keys, aliasStore: aliases, currentScope: { box.value })
        await model.activate()
        await aliases.holdWrite()
        let writing = Task { await model.saveAlias("Nom privé", device: other) }
        await aliases.waitForWrite()
        box.value = nil
        await aliases.releaseWrite()
        let saved = await writing.value
        XCTAssertFalse(saved)
        XCTAssertNil(model.snapshot)
        XCTAssertTrue(model.aliases.isEmpty)
        XCTAssertEqual(model.failure, .contextChanged)
    }

    private final class ScopeBox {
        var value: MessagingScope?
        init(_ value: MessagingScope) { self.value = value }
    }
}

private actor DeviceVerificationKeys: MessagingKeyManagement {
    private var value: MessagingDeviceVerificationSnapshot
    private var failure: MessagingFailure?
    private var persistVerification = true
    private var count = 0
    private var hold = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    init(snapshot: MessagingDeviceVerificationSnapshot) { value = snapshot }
    func replaceSnapshot(_ snapshot: MessagingDeviceVerificationSnapshot) { value = snapshot }
    func setFailure(_ failure: MessagingFailure?) { self.failure = failure }
    func setPersistVerification(_ value: Bool) { persistVerification = value }
    func confirmationCount() -> Int { count }
    func holdConfirmation() { hold = true }
    func waitForConfirmation() async {
        if count > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func releaseConfirmation() { continuation?.resume(); continuation = nil; hold = false }
    func deviceVerificationSnapshot(scope: MessagingScope) -> MessagingDeviceVerificationSnapshot { value }
    func ownDevices(scope: MessagingScope) -> [MessagingOwnDevice] { [value.localDevice] + value.devices }
    func confirmOwnDevice(deviceID: String, fingerprint: String, scope: MessagingScope) async throws {
        count += 1
        if hold {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                started?.resume()
                started = nil
            }
        } else { started?.resume(); started = nil }
        if let failure { throw failure }
        guard value.devices.contains(where: { $0.id == deviceID && $0.fingerprint == fingerprint }) else {
            throw MessagingFailure.protectionUnavailable
        }
        if persistVerification {
            value = MessagingDeviceVerificationSnapshot(localDevice: value.localDevice,
                devices: value.devices.map { device in
                    MessagingOwnDevice(id: device.id, fingerprint: device.fingerprint, isCurrent: false,
                                       isVerified: device.id == deviceID || device.isVerified)
                }, capability: value.capability)
        }
    }
    func enableBackup(scope: MessagingScope) throws -> String { throw MessagingFailure.protectionUnavailable }
    func restoreBackup(recoveryKey: String, scope: MessagingScope) throws -> (imported: Int, failed: Int) {
        throw MessagingFailure.protectionUnavailable
    }
    func backupPending(scope: MessagingScope) -> Bool { false }
}

private actor DeviceAliasMemory: MessagingDeviceAliases {
    private var names: [String: String] = [:]
    private var fails = false
    private var held = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func setFailure(_ value: Bool) { fails = value }
    func holdWrite() { held = true }
    func waitForWrite() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func releaseWrite() { continuation?.resume(); continuation = nil; held = false }
    func load(scope: MessagingScope) throws -> [String: String] {
        if fails { throw MessagingFailure.protectionUnavailable }
        return names
    }
    func set(_ name: String, device: MessagingOwnDevice, scope: MessagingScope) async throws -> [String: String] {
        if held { await withCheckedContinuation { continuation = $0; started?.resume(); started = nil } }
        if fails { throw MessagingFailure.protectionUnavailable }
        let identity = MessagingDeviceAliasRules.identity(device)
        if name.isEmpty { names.removeValue(forKey: identity) } else { names[identity] = name }
        return names
    }
}
