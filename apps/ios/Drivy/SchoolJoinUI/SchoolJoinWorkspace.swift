import Foundation
import Observation

@MainActor @Observable final class SchoolJoinWorkspace: Identifiable {
    let id = UUID()
    let client: SchoolJoinClient
    var link = ""
    var acknowledgesNotice = false
    private(set) var preview: SchoolJoinPreview?
    private(set) var record: SchoolJoinRecord?
    private(set) var member: SchoolMembership?
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var isReady = false
    @ObservationIgnored private let journal = SchoolJoinJournal()
    @ObservationIgnored private var principal: SchoolJoinPrincipal?
    @ObservationIgnored private var previewToken: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var invalidated = false

    init(client: SchoolJoinClient, link: String? = nil) { self.client = client; self.link = link ?? "" }
    var isPending: Bool { record != nil && record?.receipt == nil }
    var isConfirmed: Bool { record?.receipt != nil }
    var canPreview: Bool { isReady && !invalidated && !isBusy && !isPending && !link.isEmpty }
    var canAccept: Bool { isReady && !invalidated && !isBusy && !isPending && !isConfirmed && preview != nil && acknowledgesNotice }
    func invalidate() {
        invalidated = true; generation = UUID(); link = ""; previewToken = nil; preview = nil
        record = nil; member = nil; acknowledgesNotice = false; isBusy = false; isReady = false
    }
    func load() async {
        guard !invalidated, !isBusy else { return }
        let request = generation; isBusy = true; errorMessage = nil; isReady = false
        do {
            let principal = try await client.principal()
            let saved = try journal.load(for: principal)
            guard request == generation, !invalidated else { return }
            self.principal = principal; isReady = true; isBusy = false
            if saved?.receipt != nil && !link.isEmpty {
                record = nil; preview = nil
            } else {
                record = saved; preview = saved?.preview
                if saved != nil { link = "" }
                if let saved, let receipt = saved.receipt { await readCurrentMember(saved, receipt: receipt) }
            }
        } catch { guard request == generation else { return }; isBusy = false; errorMessage = SchoolTrainingAccess.message(error) }
    }
    func inspect() async {
        guard canPreview, let principal else { return }
        let request = generation; isBusy = true; errorMessage = nil; preview = nil; acknowledgesNotice = false
        do {
            let token = try SchoolJoinClient.token(from: link, configuration: client.configuration)
            let value = try await client.preview(token: token, principal: principal)
            guard request == generation, !invalidated else { return }
            preview = value; previewToken = token; link = ""; record = nil; member = nil; isBusy = false
        } catch { guard request == generation else { return }; isBusy = false; previewToken = nil; errorMessage = SchoolTrainingAccess.message(error) }
    }
    func accept() async {
        guard canAccept, let principal, let shown = preview, let token = previewToken else { return }
        let request = generation; isBusy = true; errorMessage = nil
        do {
            // A notice/role/token rotation must be shown and acknowledged again, never silently adopted.
            let current = try await client.preview(token: token, principal: principal)
            guard request == generation, !invalidated else { return }
            guard current == shown else {
                preview = current; acknowledgesNotice = false; isBusy = false
                errorMessage = "L’invitation a changé. Relisez les informations avant de confirmer."; return
            }
            let id = UUID(); let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let record = SchoolJoinRecord(version: 1, principal: principal, operationID: id, preview: shown, createdAt: Date(),
                body: try encoder.encode(SchoolJoinBody(operationId: id, token: token)), receipt: nil)
            try journal.save(record); self.record = record; isBusy = false
        } catch {
            guard request == generation else { return }
            isBusy = false; errorMessage = SchoolTrainingAccess.message(error)
            if error as? SchoolJoinFailure == .storage || error as? SchoolJoinFailure == .pending { isReady = false }
            return
        }
        await transmit(firstAttempt: true)
    }
    func retry() async { await transmit(firstAttempt: false) }
    func verify() async {
        guard !invalidated, !isBusy, let record else { return }
        let request = generation; isBusy = true; errorMessage = nil
        do {
            let receipt = try await client.receipt(record)
            let confirmed: SchoolJoinRecord
            if record.receipt == nil { confirmed = try journal.confirm(record, receipt: receipt) }
            else { confirmed = record }
            guard request == generation, !invalidated else { return }
            self.record = confirmed; previewToken = nil; isBusy = false
            await readCurrentMember(confirmed, receipt: receipt)
        } catch { guard request == generation else { return }; isBusy = false; errorMessage = SchoolTrainingAccess.message(error) }
    }
    func anotherInvitation() {
        guard !invalidated, !isBusy, !isPending else { return }
        preview = nil; record = nil; member = nil; previewToken = nil; acknowledgesNotice = false; link = ""; errorMessage = nil
    }
    private func transmit(firstAttempt: Bool) async {
        guard !invalidated, !isBusy, let record, record.receipt == nil else { return }
        let request = generation; isBusy = true; errorMessage = nil
        var receivedSuccess = false
        do {
            try journal.save(record)
            let membership = try await client.accept(record)
            receivedSuccess = true
            let receipt = try await client.receipt(record)
            guard receipt.resourceId == membership.membershipId else { throw SchoolJoinFailure.invalidResponse }
            let confirmed = try journal.confirm(record, receipt: receipt)
            guard request == generation, !invalidated else { return }
            self.record = confirmed; previewToken = nil; isBusy = false
            await readCurrentMember(confirmed, receipt: receipt)
        } catch {
            guard request == generation, !invalidated else { return }
            if firstAttempt && !receivedSuccess, let failure = error as? SchoolJoinFailure, failure.permitsFreshCorrection {
                do { try journal.removeFreshRejection(record); self.record = nil; preview = nil; previewToken = nil; acknowledgesNotice = false }
                catch { isBusy = false; errorMessage = SchoolJoinFailure.storage.localizedDescription; return }
            }
            isBusy = false; errorMessage = SchoolTrainingAccess.message(error)
        }
    }
    private func readCurrentMember(_ record: SchoolJoinRecord, receipt: SchoolOperationReceipt) async {
        guard !invalidated, !isBusy else { return }
        let request = generation; isBusy = true; member = nil
        do {
            let value = try await client.currentMember(record, receipt: receipt)
            guard request == generation, !invalidated else { return }
            member = value; isBusy = false
        } catch { guard request == generation else { return }; isBusy = false; errorMessage = SchoolTrainingAccess.message(error) }
    }
}
