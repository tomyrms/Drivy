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
