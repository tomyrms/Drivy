import Foundation
import Observation

typealias SchoolCaptureStartHandler = @MainActor (SchoolCaptureTransferCoordinator,
    any SchoolCaptureLocationProviding, SchoolCaptureStoredSession, SchoolCaptureLease,
    SchoolCaptureAuthorization, ContinuousClock.Instant) async throws -> Void

struct SchoolCaptureStartReview: Identifiable {
    let id = UUID()
    let lesson: SchoolLesson
    let learnerName: String
    let notice: SchoolRecordingNotice
    let choice: SchoolRecordingChoice
    let assessment: SchoolDeviceAssessment
    let pendingMutation: SchoolCapturePendingMutation?
}

/// AP154 remains an explicit, reviewed command; collection belongs to the app root.
@MainActor @Observable final class SchoolCapturePreparationWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let lessonID: UUID
    let client: SchoolCaptureClient
    let reader: any SchoolAPI
    let agenda: SchoolAgendaClient
    private(set) var lesson: SchoolLesson?
    private(set) var learner: SchoolLearner?
    private(set) var notice: SchoolRecordingNotice?
    private(set) var choice: SchoolRecordingChoice?
    private(set) var assessment: SchoolDeviceAssessment?
    private(set) var snapshot: SchoolCaptureDeviceSnapshot?
    private(set) var pending: [SchoolCaptureQueuedMutation] = []
    private(set) var isInstructor = false
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var isSampling = false
    private(set) var accessRevoked = false
    private(set) var contextIsCurrent = false
    private(set) var errorMessage: String?
    private(set) var noticeError: String?
    private(set) var storageError: String?
    private(set) var assessmentMessage: String?
    private(set) var store: SQLCipherSchoolCaptureStore?
    private(set) var captureStarted = false
    private(set) var startMessage: String?
    @ObservationIgnored private let journalProvider: @MainActor () async throws -> SQLCipherSchoolCaptureStore
    @ObservationIgnored private let onCaptureAuthorized: SchoolCaptureStartHandler?
    @ObservationIgnored private let onRefusalConfirmed: (@MainActor (UUID, UUID?) -> Void)?
    @ObservationIgnored private let canUseDiagnostic: @MainActor () -> Bool
    @ObservationIgnored private var startTransfer: SchoolCaptureTransferCoordinator?
    @ObservationIgnored private var source: (any SchoolCaptureLocationProviding)?
    @ObservationIgnored private var sourceTransferred = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var invalidated = false

    init(scope: SchoolCommandScope, lessonID: UUID, client: SchoolCaptureClient,
         reader: any SchoolAPI, agenda: SchoolAgendaClient, store: SQLCipherSchoolCaptureStore? = nil,
         journalProvider: @escaping @MainActor () async throws -> SQLCipherSchoolCaptureStore = { try await SQLCipherSchoolCaptureStore.openDefault() },
         onCaptureAuthorized: SchoolCaptureStartHandler? = nil,
         onRefusalConfirmed: (@MainActor (UUID, UUID?) -> Void)? = nil,
         canUseDiagnostic: @escaping @MainActor () -> Bool = { true }) {
        self.scope = scope
        self.lessonID = lessonID
        self.client = client
        self.reader = reader
        self.agenda = agenda
        self.store = store
        self.journalProvider = journalProvider
        self.onCaptureAuthorized = onCaptureAuthorized
        self.onRefusalConfirmed = onRefusalConfirmed
        self.canUseDiagnostic = canUseDiagnostic
    }

    var pendingAssessments: [SchoolCaptureQueuedMutation] { pending.filter { $0.mutation.kind == .assessDevice } }
    var pendingStarts: [SchoolCaptureQueuedMutation] { pending.filter { $0.mutation.kind == .startCapture } }
    var collectionIsIntegrated: Bool { onCaptureAuthorized != nil && onRefusalConfirmed != nil }
    var diagnosticIsAvailable: Bool { canUseDiagnostic() }
    var hasOldScope: Bool { pending.contains { $0.mutation.scope != scope } }
    var mayDiagnose: Bool {
        !invalidated && !sourceTransferred && diagnosticIsAvailable && !accessRevoked && contextIsCurrent && isInstructor && lesson?.status == "PLANNED"
            && !isLoading && !isBusy
    }
    var maySendAssessment: Bool {
        mayDiagnose && !isSampling && snapshot != nil && store != nil && storageError == nil
            && pendingAssessments.isEmpty && !hasOldScope
    }
    var mayOpenChoice: Bool { contextIsCurrent && !invalidated && !isLoading && !isBusy && store != nil && storageError == nil }
    var mayReviewStart: Bool {
        mayDiagnose && collectionIsIntegrated && !isSampling && storageError == nil && store != nil && !hasOldScope
            && pendingAssessments.isEmpty && pendingStarts.isEmpty && choice?.status == .allowed
            && choice?.noticeVersionId == notice?.noticeVersionId && assessment?.status == .qualified
            && snapshot?.permission.permitsLocation == true
            && assessment.flatMap { SchoolLesson.date($0.expiresAt) }.map { $0 > Date() } == true
    }
    var mayConfirmStart: Bool { mayDiagnose && collectionIsIntegrated && !isSampling && store != nil && storageError == nil }

    func learnerRefused(_ learnerID: UUID, lessonID: UUID?) {
        closeDiagnostic()
        onRefusalConfirmed?(learnerID, lessonID)
    }

    func closeDiagnostic() {
        source?.onEvent = nil
        source?.updateScope(nil)
        _ = source?.stop()
        source = nil
        snapshot = nil
        isSampling = false
    }

    /// A sheet can disappear while a fresh permission/sample preflight awaits HTTP.
    /// Invalidate that continuation before closing the source; admitted receipts may
    /// still be saved under their original scope, but cannot restart a diagnostic.
    func suspend() {
        generation = UUID()
        if !sourceTransferred { startTransfer?.invalidate() }
        startTransfer = nil
        closeDiagnostic()
        isBusy = false
        isLoading = false
    }

    /// Ownership passes before an awaited app-level adoption. The receiver must
    /// stop this source itself if adoption fails; dismissing this sheet cannot do so.
    func takeDiagnosticSourceForCapture() throws -> any SchoolCaptureLocationProviding {
        guard !invalidated, !sourceTransferred, contextIsCurrent, isInstructor, !isSampling,
              let source else { throw SchoolCaptureLocationFailure.invalidContext }
        self.source = nil
        sourceTransferred = true
        snapshot = nil
        return source
    }

    func invalidate() {
        invalidated = true
        generation = UUID()
        if !sourceTransferred { startTransfer?.invalidate() }
        startTransfer = nil
        closeDiagnostic()
        lesson = nil; learner = nil; notice = nil; choice = nil; assessment = nil
        pending = []; contextIsCurrent = false; isInstructor = false; isLoading = false; isBusy = false
        noticeError = nil; assessmentMessage = nil; storageError = nil
    }

    func load() async {
        guard !invalidated, !isBusy else { return }
        closeDiagnostic()
        generation = UUID()
        let request = generation
        isLoading = true; contextIsCurrent = false; errorMessage = nil; storageError = nil
        defer { if isCurrent(request) { isLoading = false } }
        do {
            if store == nil { store = try await journalProvider() }
            try await reloadQueue(request)
        } catch {
            guard isCurrent(request) else { return }
            storageError = "Le journal protégé n’est pas accessible. Aucun diagnostic ne sera envoyé."
        }
        guard isCurrent(request) else { return }
        do {
            let context = try await readContext()
            guard isCurrent(request) else { return }
            apply(context)
            if context.isInstructor && !sourceTransferred && diagnosticIsAvailable { snapshot = try? diagnosticSource().diagnosticSnapshot() }
            await loadChoice(request)
            if let assessment, isCurrent(request) { await refreshAssessment(assessment, request: request) }
        } catch {
            guard isCurrent(request) else { return }
            isLoading = false; fail(error)
        }
    }

    func requestPermission() async {
        guard mayDiagnose else { return }
        await performLocalDiagnostic { source in source.requestPermission() }
    }

    func requestSample() async {
        guard mayDiagnose, !isSampling else { return }
        await performLocalDiagnostic { source in
            try source.requestDiagnosticSample()
            self.isSampling = true
        }
    }

    private func performLocalDiagnostic(_ action: (any SchoolCaptureLocationProviding) throws -> Void) async {
        let request = generation
        isBusy = true; errorMessage = nil
        defer { if isCurrent(request) { isBusy = false } }
        do {
            let context = try await readContext()
            guard isCurrent(request) else { return }
            apply(context)
            guard context.isInstructor, context.lesson.status == "PLANNED" else { throw SchoolCaptureFailure.forbidden }
            guard diagnosticIsAvailable else { throw SchoolCaptureStorageFailure.alreadyActive }
            let source = diagnosticSource()
            try action(source)
            snapshot = try source.diagnosticSnapshot()
        } catch { if isCurrent(request) { fail(error) } }
    }

    /// The user explicitly sends metadata; coordinates and free space never leave this screen.
    func assess() async {
        guard maySendAssessment, let store else { return }
        let request = generation
        isBusy = true; errorMessage = nil; assessmentMessage = nil
        do {
            let context = try await readContext()
            guard isCurrent(request) else { return }
            apply(context)
            guard context.isInstructor, context.lesson.status == "PLANNED" else { throw SchoolCaptureFailure.forbidden }
            guard diagnosticIsAvailable else { throw SchoolCaptureStorageFailure.alreadyActive }
            try await reloadQueue(request)
            guard isCurrent(request) else { return }
            guard pendingAssessments.isEmpty, !hasOldScope else { throw SchoolCaptureStorageFailure.uncertainCommand }
            let operationID = UUID()
            // This successful fresh server round trip establishes current connectivity.
            let body = try diagnosticSource().diagnosticBody(operationID: operationID, networkAvailable: true)
            guard body.platform == "IOS", body.freeBytes == nil else { throw SchoolCaptureFailure.invalidResponse }
            let deviceID = await store.installationID()
            guard isCurrent(request) else { return }
            let mutation = try SchoolCapturePendingMutation.make(id: operationID, scope: scope,
                kind: .assessDevice, targetID: deviceID, body: body)
            try await store.stage(mutation)
            guard isCurrent(request) else { return }
            await send(mutation, request: request)
        } catch { await failedMutation(error, request: request) }
    }

    func mayResume(_ queued: SchoolCaptureQueuedMutation) -> Bool {
        mayDiagnose && storageError == nil && queued.mutation.scope == scope
            && queued.mutation.kind == .assessDevice && pendingAssessments.contains { $0.id == queued.id }
    }

    func resume(_ queued: SchoolCaptureQueuedMutation, verifyFirst: Bool) async {
        guard mayResume(queued) else { return }
        let request = generation
        isBusy = true; errorMessage = nil; assessmentMessage = nil
        do {
            let context = try await readContext()
            guard isCurrent(request) else { return }
            apply(context)
            guard context.isInstructor, context.lesson.status == "PLANNED" else { throw SchoolCaptureFailure.forbidden }
            let receipt: SchoolOperationReceipt?
            if verifyFirst { receipt = try await client.receipt(for: queued.mutation) }
            else { receipt = nil }
            guard isCurrent(request) else { return }
            await send(queued.mutation, request: request, receipt: receipt)
        } catch { await failedMutation(error, request: request) }
    }

    func mayReviewPendingStart(_ queued: SchoolCaptureQueuedMutation) -> Bool {
        mayDiagnose && collectionIsIntegrated && storageError == nil && !hasOldScope && !isSampling
            && queued.mutation.scope == scope && queued.mutation.targetID == lessonID
            && queued.mutation.kind == .startCapture && pendingStarts.contains { $0.id == queued.id }
    }
    func mayVerifyPendingStart(_ queued: SchoolCaptureQueuedMutation) -> Bool {
        !invalidated && contextIsCurrent && isInstructor && !isLoading && !isBusy && storageError == nil
            && queued.mutation.scope == scope && queued.mutation.targetID == lessonID
            && queued.mutation.kind == .startCapture && pendingStarts.contains { $0.id == queued.id }
    }

    func reviewStart(resuming queued: SchoolCaptureQueuedMutation? = nil) async -> SchoolCaptureStartReview? {
        if let queued { guard mayReviewPendingStart(queued) else { return nil } }
        else { guard mayReviewStart else { return nil } }
        let request = generation
        isBusy = true; errorMessage = nil; startMessage = nil
        defer { if isCurrent(request) { isBusy = false } }
        do {
            let review = try await freshStartReview(resuming: queued?.mutation)
            guard isCurrent(request) else { return nil }
            return review
        } catch { if isCurrent(request) { fail(error) }; return nil }
    }

    func confirmStart(_ review: SchoolCaptureStartReview, acknowledged: Bool) async -> Bool {
        guard acknowledged, mayConfirmStart, let store,
              let onCaptureAuthorized else { return false }
        let request = generation
        isBusy = true; errorMessage = nil; startMessage = nil
        var authorizationMayExist = false
        do {
            let fresh = try await freshStartReview(resuming: review.pendingMutation)
            guard isCurrent(request) else { return false }
            guard sameStartReview(review, fresh) else {
                throw SchoolCaptureFailure.rejected("La préparation a changé. Revenez à la leçon et relisez les informations avant de confirmer.")
            }
            guard diagnosticIsAvailable else { throw SchoolCaptureStorageFailure.alreadyActive }
            let local = try diagnosticSource().diagnosticSnapshot()
            guard local.permission.permitsLocation, local.modelCode == fresh.assessment.modelCode,
                  local.osVersion == fresh.assessment.osVersion, local.appBuild == fresh.assessment.appBuild else {
                throw SchoolCaptureLocationFailure.permissionRequired
            }
            try await reloadQueue(request)
            guard isCurrent(request) else { return false }
            guard !hasOldScope, pendingAssessments.isEmpty else { throw SchoolCaptureStorageFailure.uncertainCommand }
            let mutation: SchoolCapturePendingMutation
            if let existing = review.pendingMutation {
                guard pendingStarts.contains(where: { $0.mutation == existing }) else { throw SchoolCaptureStorageFailure.uncertainCommand }
                mutation = existing
            } else {
                guard pendingStarts.isEmpty else { throw SchoolCaptureStorageFailure.uncertainCommand }
                let deviceID = await store.installationID()
                guard isCurrent(request) else { return false }
                let operationID = UUID()
                let body = SchoolStartCaptureBody(operationId: operationID, deviceId: deviceID,
                    choiceId: fresh.choice.id, choiceVersion: fresh.choice.version, noticeVersionId: fresh.notice.noticeVersionId,
                    explicitStartConfirmed: true, deviceAssessmentId: fresh.assessment.id)
                mutation = try SchoolCapturePendingMutation.make(id: operationID, scope: scope, kind: .startCapture,
                    targetID: lessonID, expectedVersion: fresh.lesson.version, body: body)
            }
            try await store.stage(mutation)
            guard isCurrent(request) else { return false }
            let transfer = SchoolCaptureTransferCoordinator(scope: scope, client: client, store: store,
                stopCollection: { [weak self] _ in self?.closeDiagnostic() })
            startTransfer = transfer
            authorizationMayExist = true
            let result = try await transfer.transmit(operationID: mutation.id)
            guard isCurrent(request) else {
                await sealUnusedAuthorization(result, store: store)
                return false
            }
            switch result {
            case .authorization(let session, let lease, let authorization, let receivedAt):
                guard session.state == .ready, session.manifest == nil else { throw SchoolCaptureStorageFailure.closed }
                // Recreate only the diagnostic source, never a collecting segment.
                _ = diagnosticSource()
                let ownedSource = try takeDiagnosticSourceForCapture()
                startTransfer = nil // The app-level owner now controls this capability.
                try await onCaptureAuthorized(transfer, ownedSource, session, lease, authorization, receivedAt)
                guard isCurrent(request) else { return false }
                isBusy = false; captureStarted = true
                return true
            case .confirmed(.authorization(_)):
                startTransfer = nil
                try await reloadQueue(request)
                guard isCurrent(request) else { return false }
                isBusy = false
                startMessage = "Cette autorisation est déjà arrêtée ou expirée. Aucun GPS n’a démarré."
                return false
            default: throw SchoolCaptureFailure.invalidResponse
            }
        } catch {
            if authorizationMayExist && !sourceTransferred {
                await sealReadyAuthorization(store: store)
            }
            await failedMutation(error, request: request)
            return false
        }
    }

    func verifyStart(_ queued: SchoolCaptureQueuedMutation) async {
        guard mayVerifyPendingStart(queued), let store else { return }
        let request = generation
        isBusy = true; errorMessage = nil; startMessage = nil
        defer { if isCurrent(request) { isBusy = false } }
        do {
            _ = try await readContext()
            let receipt = try await client.receipt(for: queued.mutation)
            guard isCurrent(request) else { return }
            guard queued.mutation.matches(receipt) else { throw SchoolCaptureFailure.invalidResponse }
            let current = try await client.capture(schoolID: scope.schoolID, captureID: receipt.resourceId, scope: scope)
            guard isCurrent(request) else { return }
            guard current.lessonId == lessonID else { throw SchoolCaptureFailure.invalidResponse }
            if current.captureState != .authorized {
                let durable = try await store.markAttempted(id: queued.id, scope: scope)
                guard durable == queued.mutation, isCurrent(request) else { throw SchoolCaptureStorageFailure.invalidContext }
                let delivery = Task { try await client.send(durable) }
                let result = try await delivery.value
                guard case .authorization(let response) = result, response.capture.captureState != .authorized else {
                    throw SchoolCaptureFailure.invalidResponse
                }
                try await store.acknowledge(id: durable.id, scope: scope, result: result)
                guard isCurrent(request) else { return }
                try await reloadQueue(request)
                guard isCurrent(request) else { return }
                startMessage = "Cette demande est clôturée. Aucun GPS n’a été relancé."
            } else {
                startMessage = "L’école a confirmé la demande. Aucun GPS n’a démarré ici ; le départ exige toujours une nouvelle relecture et une confirmation."
            }
        } catch { if isCurrent(request) { fail(error) } }
    }

    private func freshStartReview(resuming mutation: SchoolCapturePendingMutation?) async throws -> SchoolCaptureStartReview {
        let context = try await readContext()
        guard context.isInstructor, context.lesson.status == "PLANNED", let store else { throw SchoolCaptureFailure.forbidden }
        let school = try await reader.school(id: scope.schoolID)
        guard school.status == "ACTIVE", school.modules.gpsEnabled else {
            throw SchoolCaptureFailure.rejected("Le GPS scolaire n’est pas activé dans cette école. La leçon peut continuer sans GPS.")
        }
        let notice = try await client.recordingNotice(schoolID: scope.schoolID)
        guard let choice = try await client.recordingChoice(schoolID: scope.schoolID, learnerID: context.learner.id, lessonID: lessonID),
              choice.status == .allowed, choice.noticeVersionId == notice.noticeVersionId else {
            throw SchoolCaptureFailure.rejected("Un accord correspondant à l’information actuelle de l’école est nécessaire pour démarrer le GPS.")
        }
        let deviceID = await store.installationID()
        let assessmentID: UUID
        if let mutation {
            guard mutation.scope == scope, mutation.kind == .startCapture, mutation.targetID == lessonID,
                  mutation.expectedVersion == context.lesson.version,
                  let body = try? JSONDecoder().decode(SchoolStartCaptureBody.self, from: mutation.body),
                  body.deviceId == deviceID, body.choiceId == choice.id, body.choiceVersion == choice.version,
                  body.noticeVersionId == notice.noticeVersionId, body.explicitStartConfirmed else {
                throw SchoolCaptureFailure.rejected("La leçon ou son choix a changé depuis cette demande. Son contenu reste conservé ; aucun départ n’est autorisé ici.")
            }
            assessmentID = body.deviceAssessmentId
        } else {
            guard let assessment else { throw SchoolCaptureFailure.rejected("Vérifiez d’abord cet appareil auprès de l’école.") }
            assessmentID = assessment.id
        }
        let checked = try await client.assessment(schoolID: scope.schoolID, deviceID: deviceID, assessmentID: assessmentID)
        guard checked.status == .qualified, checked.membershipId == scope.membershipID,
              SchoolLesson.date(checked.expiresAt).map({ $0 > Date() }) == true else {
            throw SchoolCaptureFailure.rejected("Un diagnostic courant et qualifié est nécessaire avant le départ.")
        }
        let current = try await readContext()
        guard current.isInstructor, current.lesson == context.lesson else { throw SchoolCaptureFailure.changed }
        return .init(lesson: current.lesson, learnerName: current.learner.displayName,
            notice: notice, choice: choice, assessment: checked, pendingMutation: mutation)
    }

    private func sameStartReview(_ lhs: SchoolCaptureStartReview, _ rhs: SchoolCaptureStartReview) -> Bool {
        lhs.lesson == rhs.lesson && lhs.learnerName == rhs.learnerName && lhs.choice == rhs.choice
            && lhs.assessment == rhs.assessment && lhs.pendingMutation == rhs.pendingMutation
            && lhs.notice.noticeVersionId == rhs.notice.noticeVersionId && lhs.notice.noticeText == rhs.notice.noticeText
            && lhs.notice.retentionText == rhs.notice.retentionText && lhs.notice.contactEmail == rhs.notice.contactEmail
            && lhs.notice.approvedAt == rhs.notice.approvedAt
    }

    private func sealUnusedAuthorization(_ result: SchoolCaptureTransferCoordinator.Result, store: SQLCipherSchoolCaptureStore) async {
        guard case .authorization(let session, _, _, _) = result, session.state == .ready else { return }
        // No collector ever opened. Keep a conservative durable stop under the original scope.
        _ = try? await store.stopAndSeal(captureID: session.id, scope: session.scope,
            stoppedAt: session.serverCapture.authorizedAt, reason: .deviceError)
    }

    private func sealReadyAuthorization(store: SQLCipherSchoolCaptureStore) async {
        guard let sessions = try? await store.sessions(scope: scope) else { return }
        for session in sessions where session.serverCapture.lessonId == lessonID && session.state == .ready && session.manifest == nil {
            _ = try? await store.stopAndSeal(captureID: session.id, scope: scope,
                stoppedAt: session.serverCapture.authorizedAt, reason: .deviceError)
        }
    }

    private func send(_ mutation: SchoolCapturePendingMutation, request: UUID, receipt: SchoolOperationReceipt? = nil) async {
        guard let store else { return }
        do {
            let durable = try await store.markAttempted(id: mutation.id, scope: scope)
            guard durable == mutation else { throw SchoolCaptureStorageFailure.invalidContext }
            guard isCurrent(request) else { return }
            let delivery = Task { try await client.send(durable) }
            let result = try await delivery.value
            guard case .assessment(let value) = result else { throw SchoolCaptureStorageFailure.invalidReceipt }
            if let receipt {
                guard durable.matches(receipt), receipt.resourceId == value.id, receipt.resourceVersion == value.version else {
                    throw SchoolCaptureStorageFailure.invalidReceipt
                }
            }
            try await store.acknowledge(id: durable.id, scope: durable.scope, result: result)
            guard isCurrent(request) else { return }
            try await reloadQueue(request)
            guard isCurrent(request) else { return }
            await refreshAssessment(value, request: request)
            if isCurrent(request) { isBusy = false }
        } catch { await failedMutation(error, request: request) }
    }

    private func refreshAssessment(_ value: SchoolDeviceAssessment, request: UUID) async {
        assessment = nil
        do {
            let refreshed = try await client.assessment(schoolID: scope.schoolID, deviceID: value.deviceId, assessmentID: value.id)
            _ = try await currentMembership()
            guard isCurrent(request) else { return }
            assessment = refreshed; assessmentMessage = nil
        } catch {
            guard isCurrent(request) else { return }
            assessmentMessage = "Le diagnostic a été enregistré, mais sa validité actuelle doit être vérifiée."
            fail(error)
        }
    }

    private func diagnosticSource() -> any SchoolCaptureLocationProviding {
        if let source { return source }
        let value = SchoolCaptureLocationSource()
        value.updateScope(scope)
        value.onEvent = { [weak self] event in
            guard let self, !self.invalidated else { return }
            if case .diagnosticChanged = event {
                self.isSampling = false
                if let source = self.source { self.snapshot = try? source.diagnosticSnapshot() }
            }
        }
        source = value
        return value
    }

    private struct Context {
        let lesson: SchoolLesson
        let learner: SchoolLearner
        let isInstructor: Bool
    }
    private func readContext() async throws -> Context {
        let member = try await currentMembership()
        let lesson = try await agenda.lesson(schoolID: scope.schoolID, id: lessonID)
        let learner = try await reader.learner(schoolID: scope.schoolID, id: lesson.learnerId)
        let assigned = member.roles.contains("INSTRUCTOR") && lesson.instructorMembershipId == member.membershipId
        let own = member.roles.contains("LEARNER") && learner.personId == scope.personID
        guard assigned || own else { throw SchoolCaptureFailure.forbidden }
        _ = try await currentMembership()
        return .init(lesson: lesson, learner: learner, isInstructor: assigned)
    }
    private func currentMembership() async throws -> SchoolMembership {
        let person = try await reader.me()
        guard person.personId == scope.personID,
              let member = person.memberships.first(where: { $0.membershipId == scope.membershipID }),
              member.schoolId == scope.schoolID, member.accessEpoch == scope.accessEpoch else { throw SchoolCaptureFailure.forbidden }
        return member
    }
    private func apply(_ value: Context) {
        lesson = value.lesson; learner = value.learner; isInstructor = value.isInstructor; contextIsCurrent = true
    }
    private func loadChoice(_ request: UUID) async {
        notice = nil; choice = nil; noticeError = nil
        guard let learner else { return }
        do {
            let notice = try await client.recordingNotice(schoolID: scope.schoolID)
            let choice = try await client.recordingChoice(schoolID: scope.schoolID, learnerID: learner.id, lessonID: lessonID)
            _ = try await currentMembership()
            guard isCurrent(request) else { return }
            self.notice = notice; self.choice = choice
        } catch {
            guard isCurrent(request) else { return }
            noticeError = (error as? LocalizedError)?.errorDescription ?? "Le choix GPS n’a pas pu être relu."
            if isAccessFailure(error) { fail(error) }
        }
    }
    private func reloadQueue(_ request: UUID) async throws {
        guard let store else { throw SchoolCaptureStorageFailure.unavailable }
        let deviceID = await store.installationID()
        let queue = try await store.pending(scope: scope, deviceID: deviceID)
        guard isCurrent(request) else { return }
        pending = queue
    }
    private func failedMutation(_ error: any Error, request: UUID) async {
        guard isCurrent(request) else { return }
        do { try await reloadQueue(request) }
        catch { if isCurrent(request) { storageError = "La demande conservée doit être vérifiée avant un nouvel envoi." } }
        guard isCurrent(request) else { return }
        isBusy = false; fail(error)
    }
    private func isCurrent(_ request: UUID) -> Bool { !invalidated && request == generation }
    private func isAccessFailure(_ error: any Error) -> Bool {
        if let value = error as? SchoolAgendaFailure {
            switch value { case .authentication, .forbidden: return true; default: break }
        }
        return error as? SchoolCaptureFailure == .unauthorized || error as? SchoolCaptureFailure == .forbidden
            || error as? SchoolAPIError == .unauthorized || error as? SchoolAPIError == .forbidden
            || error as? SchoolAPIError == .identityNotLinked
    }
    private func fail(_ error: any Error) {
        if isAccessFailure(error) { invalidate(); accessRevoked = true }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? "La préparation GPS n’a pas pu être vérifiée."
    }
}
