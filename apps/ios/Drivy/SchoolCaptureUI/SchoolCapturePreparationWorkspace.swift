import Foundation
import Observation

/// Préparation d'une vraie leçon. Aucune commande AP154 et aucun segment GPS ici.
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
    @ObservationIgnored private var source: (any SchoolCaptureLocationProviding)?
    @ObservationIgnored private var sourceTransferred = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var invalidated = false

    init(scope: SchoolCommandScope, lessonID: UUID, client: SchoolCaptureClient,
         reader: any SchoolAPI, agenda: SchoolAgendaClient, store: SQLCipherSchoolCaptureStore? = nil) {
        self.scope = scope
        self.lessonID = lessonID
        self.client = client
        self.reader = reader
        self.agenda = agenda
        self.store = store
    }

    var pendingAssessments: [SchoolCaptureQueuedMutation] { pending.filter { $0.mutation.kind == .assessDevice } }
    var hasOldScope: Bool { pending.contains { $0.mutation.scope != scope } }
    var mayDiagnose: Bool {
        !invalidated && !sourceTransferred && !accessRevoked && contextIsCurrent && isInstructor && lesson?.status == "PLANNED"
            && !isLoading && !isBusy
    }
    var maySendAssessment: Bool {
        mayDiagnose && !isSampling && snapshot != nil && store != nil && storageError == nil
            && pendingAssessments.isEmpty && !hasOldScope
    }
    var mayOpenChoice: Bool { contextIsCurrent && !invalidated && !isLoading && !isBusy }

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
        closeDiagnostic()
        isBusy = false
        isLoading = false
    }

    /// Ownership passes before an awaited app-level adoption. The receiver must
    /// stop this source itself if adoption fails; dismissing this sheet cannot do so.
    func takeDiagnosticSourceForCapture() throws -> any SchoolCaptureLocationProviding {
        guard mayDiagnose, !isSampling, let source else { throw SchoolCaptureLocationFailure.invalidContext }
        self.source = nil
        sourceTransferred = true
        snapshot = nil
        return source
    }

    func invalidate() {
        invalidated = true
        generation = UUID()
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
            if store == nil { store = try await SQLCipherSchoolCaptureStore.openDefault() }
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
            if context.isInstructor && !sourceTransferred { snapshot = try? diagnosticSource().diagnosticSnapshot() }
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

    private func send(_ mutation: SchoolCapturePendingMutation, request: UUID, receipt: SchoolOperationReceipt? = nil) async {
        guard let store else { return }
        do {
            let durable = try await store.markAttempted(id: mutation.id, scope: scope)
            guard durable == mutation else { throw SchoolCaptureStorageFailure.invalidContext }
            guard isCurrent(request) else { return }
            let result = try await client.send(durable)
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
