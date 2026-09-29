import Foundation
import Observation

/// Joining a school with the code handed over by an instructor: type it, see the school, join.
/// The intention is stored before it is sent; an uncertain answer is verified with the same request.
@MainActor @Observable final class SchoolCodeJoinWorkspace: Identifiable {
    let id = UUID()
    let client: SchoolJoinClient
    /// What the person typed, formatted `XXXX-XXXX` by the field.
    var code = ""
    private(set) var preview: SchoolCodePreview?
    private(set) var record: SchoolCodeJoinRecord?
    private(set) var isBusy = false
    private(set) var isReady = false
    private(set) var errorMessage: String?
    /// Joined, but the school still has to open the invited training.
    private(set) var trainingNotOpened = false
    @ObservationIgnored private let store: any SchoolCodeJoinStore
    @ObservationIgnored private var principal: SchoolJoinPrincipal?
    @ObservationIgnored private var previewedCode: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var invalidated = false

    init(client: SchoolJoinClient, store: (any SchoolCodeJoinStore)? = nil) {
        self.client = client
        self.store = store ?? SchoolCodeJoinJournal()
    }

    var member: SchoolMembership? { record?.membership }
    var isPending: Bool { record != nil && record?.membership == nil }
    var isConfirmed: Bool { record?.membership != nil }
    var normalizedCode: String? { SchoolInvitationCode.normalized(code) }
    var isMistyped: Bool { SchoolInvitationCode.isMistyped(code) }
    var canPreview: Bool { isReady && !invalidated && !isBusy && !isPending && !isConfirmed && normalizedCode != nil }
    var canAccept: Bool { isReady && !invalidated && !isBusy && !isPending && !isConfirmed && preview != nil && previewedCode != nil }

    func load() async {
        guard !invalidated, !isBusy else { return }
        let request = generation
        isBusy = true; errorMessage = nil; isReady = false
        do {
            let principal = try await client.principal()
            var saved = try store.load(for: principal)
            guard current(request) else { return }
            if let joined = saved, joined.membership != nil {
                // Joined earlier: nothing is left to verify, the account already shows the school.
                try? store.remove(joined); saved = nil
            }
            self.principal = principal
            record = saved; preview = saved?.preview; isReady = true; isBusy = false
        } catch {
            guard current(request) else { return }
            isBusy = false; errorMessage = Self.message(error)
        }
    }

    func inspect() async {
        guard canPreview, let principal, let code = normalizedCode else { return }
        let request = generation
        isBusy = true; errorMessage = nil; preview = nil; previewedCode = nil
        do {
            let value = try await client.previewCode(code, principal: principal)
            guard current(request) else { return }
            preview = value; previewedCode = code; isBusy = false
        } catch {
            guard current(request) else { return }
            isBusy = false; errorMessage = Self.message(error)
        }
    }

    func accept() async {
        guard canAccept, let principal, let shown = preview, let code = previewedCode else { return }
        let request = generation
        isBusy = true; errorMessage = nil
        let record: SchoolCodeJoinRecord
        do {
            // The schools of the account before sending: how a lost answer can be recognised later.
            let known = try await client.memberships(principal: principal).map(\.schoolId)
            guard current(request) else { return }
            record = try SchoolCodeJoinRecord.make(principal: principal, preview: shown, code: code, knownSchoolIDs: known)
            try store.save(record)
            self.record = record; isBusy = false
        } catch {
            guard current(request) else { return }
            isBusy = false; errorMessage = Self.message(error)
            if error as? SchoolJoinFailure == .storage || error as? SchoolJoinFailure == .pending { isReady = false }
            return
        }
        await transmit(record, firstAttempt: true)
    }

    /// Sends the same request again; the school answers with the membership it created, once.
    func verify() async {
        guard let record, record.membership == nil else { return }
        await transmit(record, firstAttempt: false)
    }

    func anotherCode() {
        guard !invalidated, !isBusy, !isPending else { return }
        if let record, record.membership != nil { try? store.remove(record) }
        preview = nil; previewedCode = nil; record = nil; code = ""; errorMessage = nil; trainingNotOpened = false
    }

    func invalidate() {
        invalidated = true; generation = UUID()
        code = ""; preview = nil; previewedCode = nil; record = nil; isBusy = false; isReady = false; trainingNotOpened = false
    }

    private func transmit(_ record: SchoolCodeJoinRecord, firstAttempt: Bool) async {
        guard !invalidated, !isBusy, record.membership == nil else { return }
        let request = generation
        isBusy = true; errorMessage = nil
        do {
            let answer = try await client.acceptCode(record)
            confirm(record, membership: answer.membership, request: request)
            if current(request) { trainingNotOpened = answer.trainingNotOpened }
        } catch let failure as SchoolJoinFailure where failure.permitsFreshCorrection {
            if !firstAttempt {
                // The code no longer answers. If the first request went through, the school is
                // now one of the account’s: that is the confirmation.
                let memberships: [SchoolMembership]
                do { memberships = try await client.memberships(principal: record.principal) }
                catch { finish(error, request); return }
                if let joined = record.joined(among: memberships) {
                    confirm(record, membership: joined, request: request)
                    return
                }
            }
            // Refused and not joined: the intention is over.
            guard current(request) else { return }
            do { try store.remove(record) }
            catch { isBusy = false; errorMessage = SchoolJoinFailure.storage.localizedDescription; return }
            self.record = nil; preview = nil; previewedCode = nil
            isBusy = false; errorMessage = failure.codeMessage
        } catch {
            finish(error, request)
        }
    }

    private func confirm(_ record: SchoolCodeJoinRecord, membership: SchoolMembership, request: UUID) {
        let confirmed = record.confirmed(by: membership)
        // The membership exists at the school. If this write fails, the pending record is
        // verified again next time and the school answers with the same membership.
        try? store.save(confirmed)
        guard current(request) else { return }
        self.record = confirmed; previewedCode = nil; code = ""; isBusy = false
    }

    private func finish(_ error: Error, _ request: UUID) {
        guard current(request) else { return }
        isBusy = false; errorMessage = Self.message(error)
    }

    private func current(_ request: UUID) -> Bool { !invalidated && generation == request }

    static func message(_ error: Error) -> String {
        if let failure = error as? SchoolJoinFailure { return failure.codeMessage }
        return (error as? LocalizedError)?.errorDescription ?? "La demande n’a pas abouti. Réessayez."
    }
}
