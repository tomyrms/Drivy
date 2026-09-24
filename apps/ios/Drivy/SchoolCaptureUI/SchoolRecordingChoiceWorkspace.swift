import Foundation
import Observation

struct SchoolRecordingChoiceReview: Identifiable, Sendable {
    let id = UUID()
    let lessonID: UUID
    let learnerID: UUID
    let learnerName: String
    let notice: SchoolRecordingNotice
    let previousChoice: SchoolRecordingChoice?
    let status: SchoolRecordingChoice.Status
    let source: SchoolRecordingChoice.Source
}

/// AP152/AP153 only. This screen has no collector, capture authorization or G0 adapter.
@MainActor @Observable final class SchoolRecordingChoiceWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let lessonID: UUID
    private(set) var lesson: SchoolLesson?
    private(set) var learner: SchoolLearner?
    private(set) var notice: SchoolRecordingNotice?
    private(set) var choice: SchoolRecordingChoice?
    private(set) var source: SchoolRecordingChoice.Source?
    private(set) var pending: [SchoolCaptureQueuedMutation] = []
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var accessRevoked = false
    private(set) var errorMessage: String?
    private(set) var storageError: String?
    private(set) var confirmation: String?
    private(set) var needsReload = true
    @ObservationIgnored private let client: SchoolCaptureClient
    @ObservationIgnored private let reader: any SchoolAPI
    @ObservationIgnored private let agenda: SchoolAgendaClient
    @ObservationIgnored private let onRefusalConfirmed: @MainActor (UUID, UUID?) -> Void
    @ObservationIgnored private var store: SQLCipherSchoolCaptureStore?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var invalidated = false

    init(scope: SchoolCommandScope, lessonID: UUID, client: SchoolCaptureClient,
         reader: any SchoolAPI, agenda: SchoolAgendaClient,
         onRefusalConfirmed: @escaping @MainActor (UUID, UUID?) -> Void,
         store: SQLCipherSchoolCaptureStore? = nil) {
        self.scope = scope; self.lessonID = lessonID; self.client = client
        self.reader = reader; self.agenda = agenda; self.store = store
        self.onRefusalConfirmed = onRefusalConfirmed
    }

    var relatedPending: [SchoolCaptureQueuedMutation] {
        pending.filter { queued in
            guard queued.mutation.kind == .recordChoice else { return false }
            if let learner { return queued.mutation.targetID == learner.id }
            let body = try? JSONDecoder().decode(SchoolRecordingChoiceBody.self, from: queued.mutation.body)
            return body?.lessonId == lessonID
        }
    }
    var hasOldScope: Bool { pending.contains { $0.mutation.scope != scope } }
    var mayChoose: Bool {
        !invalidated && !accessRevoked && !isLoading && !isBusy && !needsReload
            && store != nil && storageError == nil && source != nil && notice != nil
            && relatedPending.isEmpty && !hasOldScope
    }
    var verbalAgreementIsProtected: Bool { source == .verbal && choice?.source == .own && choice?.status == .refused }
    var currentChoiceLabel: String {
        guard let choice else { return "Choix non renseigné" }
        switch choice.status {
        case .allowed: return "Enregistrement GPS accepté"
        case .refused: return "Sans enregistrement GPS"
        case .unknown: return "Choix non renseigné"
        }
    }

    func invalidate() {
        invalidated = true; generation = UUID(); lesson = nil; learner = nil; notice = nil
        choice = nil; source = nil; pending = []; isLoading = false; isBusy = false; needsReload = true
    }

    func load() async {
        guard !invalidated, !isBusy else { return }
        generation = UUID(); let request = generation
        isLoading = true; needsReload = true; errorMessage = nil; storageError = nil
        do {
            if store == nil { store = try await SQLCipherSchoolCaptureStore.openDefault() }
            try await reloadQueue(request: request)
        } catch {
            guard request == generation, !invalidated else { return }
            storageError = "Le journal protégé n’est pas accessible. Vous pouvez lire le choix, mais pas en enregistrer un nouveau."
        }
        guard request == generation, !invalidated else { return }
        do {
            let context = try await loadContext()
            guard request == generation, !invalidated else { return }
            apply(context)
            isLoading = false; needsReload = false
        } catch {
            guard request == generation, !invalidated else { return }
            isLoading = false; fail(error)
        }
    }

    func review(_ status: SchoolRecordingChoice.Status) -> SchoolRecordingChoiceReview? {
        guard mayChoose, status != .unknown, let learner, let notice, let source,
              !(status == .allowed && verbalAgreementIsProtected) else { return nil }
        return .init(lessonID: lessonID, learnerID: learner.id, learnerName: learner.displayName,
                     notice: notice, previousChoice: choice, status: status, source: source)
    }

    func confirm(_ review: SchoolRecordingChoiceReview, acknowledged: Bool) async -> Bool {
        guard mayChoose, acknowledged, review.lessonID == lessonID, review.learnerID == learner?.id,
              review.status != .unknown, let store else { return false }
        if review.status == .refused { onRefusalConfirmed(review.learnerID, review.lessonID) }
        let request = generation; isBusy = true; errorMessage = nil; confirmation = nil
        do {
            // A freshly displayed notice and source are required before the FIRST send.
            // Retrying an admitted intention below never replaces its original bytes.
            let context = try await loadContext()
            guard request == generation, !invalidated else { return false }
            apply(context)
            guard context.learner.id == review.learnerID, context.source == review.source,
                  sameNotice(context.notice, review.notice), context.choice == review.previousChoice else {
                isBusy = false
                errorMessage = "La notice ou le choix a changé. Relisez les informations avant une nouvelle confirmation."
                return false
            }
            guard !(review.status == .allowed && verbalAgreementIsProtected) else { throw SchoolCaptureFailure.forbidden }
            try await reloadQueue(request: request)
            guard request == generation, !invalidated else { return false }
            guard relatedPending.isEmpty, !hasOldScope else { throw SchoolCaptureStorageFailure.uncertainCommand }
            let operationID = UUID()
            let body = SchoolRecordingChoiceBody(operationId: operationID, lessonId: lessonID,
                status: review.status, noticeVersionId: review.notice.noticeVersionId, source: review.source)
            let command = try SchoolCapturePendingMutation.make(id: operationID, scope: scope,
                kind: .recordChoice, targetID: review.learnerID, body: body)
            try await store.stage(command)
            guard request == generation, !invalidated else { return false }
            return await transmit(command, request: request)
        } catch {
            guard request == generation, !invalidated else { return false }
            await recoverQueueAfterFailure(request: request)
            isBusy = false; fail(error); return false
        }
    }

    func mayResume(_ queued: SchoolCaptureQueuedMutation) -> Bool {
        !invalidated && !accessRevoked && !isLoading && !isBusy && storageError == nil
            && queued.mutation.scope == scope && queued.mutation.kind == .recordChoice
            && relatedPending.contains { $0.id == queued.id }
    }
    func resend(_ queued: SchoolCaptureQueuedMutation, acknowledged: Bool) async -> Bool {
        guard mayResume(queued), acknowledged else { return false }
        if let body = try? JSONDecoder().decode(SchoolRecordingChoiceBody.self, from: queued.mutation.body), body.status == .refused {
            onRefusalConfirmed(queued.mutation.targetID, body.lessonId)
        }
        let request = generation; isBusy = true; errorMessage = nil; confirmation = nil
        return await transmit(queued.mutation, request: request)
    }
    func verify(_ queued: SchoolCaptureQueuedMutation) async {
        guard mayResume(queued) else { return }
        let request = generation; isBusy = true; errorMessage = nil; confirmation = nil
        do {
            // AP72 first: a missing receipt never authorizes another mutation.
            let receipt = try await client.receipt(for: queued.mutation)
            guard request == generation, !invalidated else { return }
            _ = await transmit(queued.mutation, request: request, provenReceipt: receipt)
        } catch {
            guard request == generation, !invalidated else { return }
            isBusy = false; fail(error)
        }
    }

    private func transmit(_ command: SchoolCapturePendingMutation, request: UUID,
                          provenReceipt: SchoolOperationReceipt? = nil) async -> Bool {
        guard let store else { isBusy = false; return false }
        do {
            let durable = try await store.markAttempted(id: command.id, scope: scope)
            guard durable == command else { throw SchoolCaptureStorageFailure.invalidContext }
            guard request == generation, !invalidated else { return false }
            let result = try await client.send(durable)
            guard case .choice(let recorded) = result else { throw SchoolCaptureStorageFailure.invalidReceipt }
            if let receipt = provenReceipt {
                guard durable.matches(receipt), receipt.resourceId == recorded.id,
                      receipt.resourceVersion == recorded.version else { throw SchoolCaptureStorageFailure.invalidReceipt }
            }
            // Even when the view closes, an admitted result is saved under its ORIGINAL scope.
            try await store.acknowledge(id: durable.id, scope: durable.scope, result: result)
            guard request == generation, !invalidated else { return true }
            try await reloadQueue(request: request)
            guard request == generation, !invalidated else { return true }
            isBusy = false
            confirmation = "Le choix a été enregistré par l’école."
            await load() // AP152 is the current choice, which may have changed since this operation.
            return true
        } catch {
            guard request == generation, !invalidated else { return false }
            await recoverQueueAfterFailure(request: request)
            isBusy = false; fail(error); return false
        }
    }

    private struct Context {
        let lesson: SchoolLesson
        let learner: SchoolLearner
        let notice: SchoolRecordingNotice
        let choice: SchoolRecordingChoice?
        let source: SchoolRecordingChoice.Source
    }
    private func loadContext() async throws -> Context {
        let member = try await currentMembership()
        let lesson = try await agenda.lesson(schoolID: scope.schoolID, id: lessonID)
        let learner = try await reader.learner(schoolID: scope.schoolID, id: lesson.learnerId)
        let source: SchoolRecordingChoice.Source
        if member.roles.contains("LEARNER"), learner.personId == scope.personID { source = .own }
        else if member.roles.contains("INSTRUCTOR") { source = .verbal }
        else { throw SchoolCaptureFailure.forbidden }
        let notice = try await client.recordingNotice(schoolID: scope.schoolID)
        let choice = try await client.recordingChoice(schoolID: scope.schoolID, learnerID: learner.id, lessonID: lessonID)
        _ = try await currentMembership()
        return .init(lesson: lesson, learner: learner, notice: notice, choice: choice, source: source)
    }
    private func currentMembership() async throws -> SchoolMembership {
        let person = try await reader.me()
        guard person.personId == scope.personID,
              let member = person.memberships.first(where: { $0.membershipId == scope.membershipID }),
              member.schoolId == scope.schoolID, member.accessEpoch == scope.accessEpoch else { throw SchoolCaptureFailure.forbidden }
        return member
    }
    private func apply(_ context: Context) {
        lesson = context.lesson; learner = context.learner; notice = context.notice
        choice = context.choice; source = context.source
    }
    private func reloadQueue(request: UUID) async throws {
        guard let store else { throw SchoolCaptureStorageFailure.unavailable }
        let deviceID = await store.installationID()
        let values = try await store.pending(scope: scope, deviceID: deviceID)
        guard request == generation, !invalidated else { return }
        pending = values
    }
    private func recoverQueueAfterFailure(request: UUID) async {
        do { try await reloadQueue(request: request) }
        catch {
            guard request == generation, !invalidated else { return }
            storageError = "La sauvegarde de la demande doit être vérifiée. Rouvrez cet écran avant de continuer."
        }
    }
    private func sameNotice(_ lhs: SchoolRecordingNotice, _ rhs: SchoolRecordingNotice) -> Bool {
        lhs.noticeVersionId == rhs.noticeVersionId && lhs.noticeText == rhs.noticeText
            && lhs.retentionText == rhs.retentionText && lhs.contactEmail == rhs.contactEmail && lhs.approvedAt == rhs.approvedAt
    }
    private func fail(_ error: any Error) {
        var revoked = error as? SchoolCaptureFailure == .unauthorized || error as? SchoolCaptureFailure == .forbidden
            || error as? SchoolAPIError == .unauthorized || error as? SchoolAPIError == .forbidden || error as? SchoolAPIError == .identityNotLinked
        if let agendaError = error as? SchoolAgendaFailure {
            switch agendaError { case .authentication, .forbidden: revoked = true; default: break }
        }
        if revoked { invalidate(); accessRevoked = true }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? "Le choix n’a pas pu être vérifié. Les demandes déjà sauvegardées restent conservées."
    }
}
