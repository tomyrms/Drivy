import Foundation
import Observation

/// Le contexte est capturé au geste, jamais à la validation du formulaire.
struct SchoolObservationEditor: Identifiable {
    let id = UUID()
    let original: SchoolObservation?
    let observedAt: String?
    let origin: String
    let draftID: UUID?
    let marker: Bool
}

@MainActor @Observable final class SchoolObservationWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let lessonID: UUID
    private(set) var lesson: SchoolLesson?
    private(set) var learnerName = ""
    private(set) var observations: [SchoolObservation] = []
    private(set) var competencies: [SchoolCatalogCompetency] = []
    private(set) var draft: SchoolReportDraft?
    private(set) var pending: PendingSchoolCommand?
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var loaded = false
    private(set) var accessRevoked = false
    private(set) var errorMessage: String?
    private(set) var competenciesMessage: String?
    private(set) var draftMessage: String?
    private(set) var confirmation: String?
    @ObservationIgnored private let client: SchoolObservationClient
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var storageAccessible = false

    init(scope: SchoolCommandScope, lessonID: UUID, client: SchoolObservationClient,
         outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope; self.lessonID = lessonID; self.client = client; self.outbox = outbox
    }

    var canMutate: Bool {
        loaded && !isLoading && !isBusy && !accessRevoked && storageAccessible && pending == nil
            && ["PLANNED", "COMPLETED"].contains(lesson?.status ?? "")
    }
    var canAdd: Bool {
        guard canMutate, let lesson, observations.count < 100 else { return false }
        return lesson.status == "PLANNED" || (lesson.status == "COMPLETED" && draft?.basePublicationVersion == lesson.publicationVersion)
    }
    var canRetry: Bool {
        guard let pending else { return false }
        return !accessRevoked && !isBusy && !isLoading && pending.scope == scope
            && pending.kind.isObservation && pending.routeResourceID == lessonID
    }
    var pendingBelongsHere: Bool { pending?.kind.isObservation == true && pending?.routeResourceID == lessonID }
    var pendingText: String {
        guard let pending, pendingBelongsHere else { return "Une demande d’un autre écran est conservée pour cette école. Retrouvez cet écran pour vérifier son résultat." }
        if pending.kind == .removeObservation,
           let body = try? JSONDecoder().decode(SchoolRemoveObservationBody.self, from: pending.body) { return "Retrait demandé\n\nMotif : \(body.reason)" }
        guard let body = try? JSONDecoder().decode(SchoolObservationBody.self, from: pending.body) else { return "Demande conservée. Son résultat reste à vérifier." }
        let kind = body.origin == "REVIEW" ? "Note de relecture" : (body.eventKind == "MARKER" ? "Repère" : "Observation de compétence")
        var details = [kind]
        if let time = timeLabel(body.observedAt) { details.append(time) }
        if let label = competencyLabel(body.competencyId) { details.append(label) }
        if let status = body.eventStatus.flatMap(SchoolObservationStatus.init(rawValue:)) { details.append(status.label) }
        details.append(body.captureId == nil ? "Sans position GPS" : "Position déjà enregistrée, conservée sans modification")
        details.append(body.text)
        return details.joined(separator: "\n\n")
    }

    func begin(marker: Bool) -> SchoolObservationEditor? {
        // Date() est prise avant tout réseau ou présentation de feuille.
        let instant = Date()
        guard canAdd, let lesson, !marker || lesson.status == "PLANNED" else { return nil }
        if lesson.status == "PLANNED" {
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return .init(original: nil, observedAt: formatter.string(from: instant), origin: "LIVE", draftID: nil, marker: marker)
        }
        return .init(original: nil, observedAt: nil, origin: "REVIEW", draftID: draft?.id, marker: false)
    }
    func edit(_ observation: SchoolObservation) -> SchoolObservationEditor? {
        guard canMutate, observations.contains(where: { $0.id == observation.id && $0.version == observation.version }) else { return nil }
        return .init(original: observation, observedAt: observation.observedAt, origin: observation.origin ?? "REVIEW",
                     draftID: observation.draftId, marker: observation.isMarker)
    }
    func competencyLabel(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return competencies.first(where: { $0.id == id })?.label ?? "Compétence du référentiel"
    }
    func timeLabel(_ value: String?) -> String? {
        guard let value, let date = SchoolLesson.date(value) else { return nil }
        let format = DateFormatter(); format.locale = Locale(identifier: "fr_CH")
        format.timeZone = TimeZone(identifier: lesson?.timeZone ?? "Europe/Zurich")
        format.dateStyle = .medium; format.timeStyle = .medium
        return format.string(from: date)
    }
    func invalidate() {
        generation = UUID(); accessRevoked = true; loaded = false; isLoading = false; isBusy = false
        lesson = nil; learnerName = ""; observations = []; competencies = []; draft = nil; pending = nil
        storageAccessible = false; confirmation = nil; competenciesMessage = nil; draftMessage = nil
    }

    func load() async {
        guard !accessRevoked, !isBusy else { return }
        generation = UUID(); let request = generation
        isLoading = true; loaded = false; errorMessage = nil; competenciesMessage = nil; draftMessage = nil
        do { pending = try outbox.pending(for: scope); storageAccessible = true }
        catch { storageAccessible = false; errorMessage = SchoolConfigurationFailure.storage.localizedDescription }
        do {
            let current = try await authorizedLesson()
            let learner = try await client.reader.learner(schoolID: scope.schoolID, id: current.learnerId)
            let values = try await client.observations(scope: scope, lessonID: lessonID, trainingID: current.trainingId)
            guard valid(request) else { return }
            lesson = current; learnerName = learner.displayName; observations = values
            // Le référentiel et le brouillon ne conditionnent pas la lecture de la liste privée.
            do {
                let values = try await client.competencies(scope: scope, trainingID: current.trainingId)
                guard valid(request) else { return }; competencies = values
            }
            catch {
                guard valid(request) else { return }
                if isRevoked(error) { throw error }
                competencies = []; competenciesMessage = "Le référentiel est indisponible. Les repères simples restent possibles sans choisir de compétence."
            }
            guard valid(request) else { return }
            draft = nil
            if current.status == "COMPLETED" {
                do {
                    let values = try await client.agenda.reportClient.drafts(schoolID: scope.schoolID, lessonID: lessonID)
                    guard valid(request) else { return }
                    guard values.count <= 1, values.allSatisfy({ $0.authorMembershipId == scope.membershipID }) else { throw SchoolObservationFailure.invalidResponse }
                    draft = values.first
                } catch {
                    guard valid(request) else { return }
                    if isRevoked(error) { throw error }
                    draftMessage = "Le brouillon privé n’a pas pu être relu. Les observations enregistrées restent consultables."
                }
            }
            guard valid(request) else { return }
            isLoading = false; loaded = true
        } catch { guard valid(request) else { return }; isLoading = false; fail(error) }
    }

    func save(_ editor: SchoolObservationEditor, text: String, marker: Bool, competencyID: UUID?, status: SchoolObservationStatus?) async -> Bool {
        guard canMutate else { return false }
        if editor.original == nil, !canAdd { return false }
        let competency = marker ? nil : competencyID
        // Une compétence inconnue peut être conservée telle quelle, jamais attribuée par supposition.
        if let competency, !competencies.contains(where: { $0.id == competency }), competency != editor.original?.competencyId { return false }
        let savedText: String
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { savedText = text }
        else if editor.origin == "LIVE", marker { savedText = "Moment à revoir" }
        else if editor.origin == "LIVE", let label = competencies.first(where: { $0.id == competency })?.label { savedText = label }
        else { return false }
        let operation = UUID()
        let body = SchoolObservationBody(operationId: operation, draftId: editor.draftID,
            captureId: editor.original?.captureId, segmentId: editor.original?.segmentId,
            pointSequence: editor.original?.pointSequence, competencyId: competency, text: savedText,
            origin: editor.origin, observedAt: editor.observedAt,
            eventKind: editor.origin == "LIVE" ? (marker ? "MARKER" : "QUALIFIED") : editor.original?.eventKind,
            eventStatus: marker ? nil : status?.rawValue)
        guard body.isValid else { return false }
        return await submit(body, operation: operation, kind: editor.original == nil ? .createObservation : .updateObservation,
                            resourceID: editor.original?.id, version: editor.original?.version ?? 0)
    }
    func remove(_ observation: SchoolObservation, reason: String) async -> Bool {
        guard canMutate else { return false }
        let operation = UUID()
        let body = SchoolRemoveObservationBody(operationId: operation, reason: reason)
        guard body.isValid else { return false }
        return await submit(body, operation: operation,
                            kind: .removeObservation, resourceID: observation.id, version: observation.version)
    }
    func verifyPending() async {
        guard canRetry, let command = pending else { return }
        let request = generation; isBusy = true; errorMessage = nil
        do {
            try await client.verifyScope(scope)
            guard valid(request) else { return }
            _ = try await client.receipt(for: command)
            // Une preuve vérifiée reste acquittable même si l’écran a été fermé entre-temps.
            try outbox.remove(command)
            guard valid(request) else { return }
            pending = nil; isBusy = false; confirmation = "L’école confirme l’enregistrement de la demande."
            await load()
        } catch { guard valid(request) else { return }; isBusy = false; fail(error) }
    }
    func retryPending() async -> Bool {
        guard canRetry, let command = pending else { return false }
        return await transmit(command, fresh: false)
    }

    private func submit<Value: Encodable>(_ value: Value, operation: UUID, kind: SchoolCommandKind, resourceID: UUID?, version: Int) async -> Bool {
        guard canMutate else { return false }
        let request = generation; isBusy = true; errorMessage = nil; confirmation = nil
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let command = PendingSchoolCommand(id: operation, scope: scope, kind: kind, resourceVersion: version,
                createdAt: Date(), body: try encoder.encode(value), resourceID: resourceID, routeResourceID: lessonID)
            do { try outbox.save(command); pending = command }
            catch {
                storageAccessible = false
                pending = try? outbox.pending(for: scope)
                throw error
            }
            return await transmit(command, fresh: true)
        } catch { guard valid(request) else { return false }; isBusy = false; fail(error); return false }
    }
    private func transmit(_ command: PendingSchoolCommand, fresh: Bool) async -> Bool {
        guard !accessRevoked, command.scope == scope, command.routeResourceID == lessonID else { return false }
        let request = generation; isBusy = true; errorMessage = nil; confirmation = nil
        var sent = false
        do {
            _ = try await authorizedLesson()
            guard valid(request) else { return false }
            try outbox.save(command) // Barrière de durabilité aussi avant chaque reprise.
            sent = true
            _ = try await client.send(command)
            try outbox.remove(command)
            guard valid(request) else { return true }
            pending = nil; isBusy = false
            confirmation = command.kind == .removeObservation ? "Observation retirée." : "Observation privée enregistrée."
            await load(); return true
        } catch {
            if fresh && sent, let refusal = error as? SchoolObservationFailure, refusal.permitsFreshCorrection {
                do { try outbox.remove(command) }
                catch { guard valid(request) else { return false }; isBusy = false; storageAccessible = false; fail(error); return false }
                guard valid(request) else { return false }
                pending = nil
                if refusal == .conflict || refusal == .reviewRequired { loaded = false }
            }
            guard valid(request) else { return false }
            isBusy = false; fail(error); return false
        }
    }
    private func authorizedLesson() async throws -> SchoolLesson {
        try await client.verifyScope(scope)
        let value = try await client.agenda.lesson(schoolID: scope.schoolID, id: lessonID)
        guard value.schoolId == scope.schoolID, value.id == lessonID,
              value.instructorMembershipId == scope.membershipID else { throw SchoolObservationFailure.forbidden }
        return value
    }
    private func valid(_ request: UUID) -> Bool { request == generation && !accessRevoked }
    private func isRevoked(_ error: any Error) -> Bool {
        if SchoolTrainingAccess.isRevoked(error) || error as? SchoolAPIError == .identityNotLinked { return true }
        if let error = error as? SchoolObservationFailure { return error == .unauthorized || error == .forbidden }
        if let error = error as? SchoolAgendaFailure {
            switch error { case .authentication, .forbidden: return true; default: return false }
        }
        return false
    }
    private func fail(_ error: any Error) {
        if isRevoked(error) { invalidate() }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? SchoolObservationFailure.unavailable.localizedDescription
    }
}
