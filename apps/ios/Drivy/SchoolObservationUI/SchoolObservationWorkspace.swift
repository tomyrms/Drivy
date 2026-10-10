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
    /// Premier envoi d’une demande, juste après le geste : bref, il ne se présente pas comme une demande à vérifier.
    private(set) var isFirstSend = false
    private(set) var accessRevoked = false
    private(set) var errorMessage: String?
    private(set) var competenciesMessage: String?
    private(set) var draftMessage: String?
    private(set) var confirmation: String?
    @ObservationIgnored private let client: SchoolObservationClient
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var storageAccessible = false
    /// Enregistreur du dernier « Signaler » ouvert depuis cet écran.
    @ObservationIgnored private var live: SchoolLiveObservationRecorder?

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
    /// Signalement tout juste posé depuis cet écran, encore en cours d’envoi.
    private var liveSendInFlight: Bool { live?.isSettlingGesture == true }
    /// Demande restée en attente, sans envoi en cours : elle seule se montre et ferme les modifications.
    var pendingAwaitsReview: Bool { pending != nil && !(isBusy && isFirstSend) && !liveSendInFlight }
    /// Ce que l’écran présente. Une relecture ou un envoi bref laissent en place la liste, ses menus et la barre
    /// d’action ; l’écriture elle-même reste gardée par `canMutate`.
    var acceptsChanges: Bool {
        loaded && !accessRevoked && storageAccessible && !pendingAwaitsReview
            && ["PLANNED", "COMPLETED"].contains(lesson?.status ?? "")
    }
    var acceptsAdd: Bool {
        guard acceptsChanges, let lesson, observations.count < 100 else { return false }
        return lesson.status == "PLANNED" || (lesson.status == "COMPLETED" && draft?.basePublicationVersion == lesson.publicationVersion)
    }
    var canRetry: Bool {
        guard let pending else { return false }
        return !accessRevoked && !isBusy && !isLoading && pending.scope == scope
            && pending.kind.isObservation && pending.routeResourceID == lessonID
    }
    var pendingBelongsHere: Bool { pending?.kind.isObservation == true && pending?.routeResourceID == lessonID }
    /// Demande que l’école a déclaré ne pas connaître : rien n’a été enregistré, elle peut être renvoyée ou abandonnée.
    private(set) var absentPendingID: UUID?
    var pendingAbsent: Bool { pending != nil && pending?.id == absentPendingID }
    var pendingText: String {
        guard let pending, pendingBelongsHere else {
            guard let pending else { return "" }
            return "\(pending.waitingMessage(absent: false)) Ouvre la fiche de la leçon pour la vérifier."
        }
        if pending.observationUndoOperationID != nil { return "Annulation du signalement en attente. La création sera vérifiée avant son retrait." }
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
        // Une relecture n’empêche pas d’ouvrir la saisie : l’enregistrement reste gardé par `canMutate`.
        guard acceptsAdd, !isBusy, let lesson, !marker || lesson.status == "PLANNED" else { return nil }
        if lesson.status == "PLANNED" {
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return .init(original: nil, observedAt: formatter.string(from: instant), origin: "LIVE", draftID: nil, marker: marker)
        }
        return .init(original: nil, observedAt: nil, origin: "REVIEW", draftID: draft?.id, marker: false)
    }
    func edit(_ observation: SchoolObservation) -> SchoolObservationEditor? {
        guard acceptsChanges, !isBusy,
              observations.contains(where: { $0.id == observation.id && $0.version == observation.version }) else { return nil }
        return .init(original: observation, observedAt: observation.observedAt, origin: observation.origin ?? "REVIEW",
                     draftID: observation.draftId, marker: observation.isMarker)
    }
    func competencyLabel(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return competencies.first(where: { $0.id == id })?.displayLabel ?? "Compétence du référentiel"
    }
    func liveRecorder() -> SchoolLiveObservationRecorder? {
        guard acceptsAdd, !isBusy, lesson?.status == "PLANNED" else { return nil }
        // Le signalement précédent part encore : le même enregistreur ouvre la palette et fait attendre la seule
        // écriture suivante, comme pendant le trajet. Un nouvel enregistreur lirait cette demande comme un blocage.
        if let live, live.isSettlingGesture, live.acceptsSignal { return live }
        let recorder = SchoolLiveObservationRecorder(scope: scope, lessonID: lessonID, client: client, outbox: outbox,
            onSettlement: { [weak self] in
                guard let self, !self.accessRevoked else { return }
                // onDismiss peut avoir fini sa lecture avant la réponse d’envoi. Cette lecture
                // crée une nouvelle génération ; aucune réponse antérieure ne peut la remplacer.
                await self.load()
            })
        live = recorder
        return recorder
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
        isFirstSend = false; live = nil; absentPendingID = nil
    }

    func load() async {
        guard !accessRevoked, !isBusy else { return }
        generation = UUID(); let request = generation
        // Une relecture garde la liste, ses messages et sa barre d’action : `loaded` ne retombe qu’après un échec.
        isLoading = true; errorMessage = nil
        do { pending = try outbox.pending(for: scope); storageAccessible = true }
        catch { storageAccessible = false; errorMessage = SchoolConfigurationFailure.storage.localizedDescription }
        if pending?.id != absentPendingID { absentPendingID = nil }
        do {
            let current = try await authorizedLesson()
            let learner = try await client.reader.learner(schoolID: scope.schoolID, id: current.learnerId)
            let values = try await client.observations(scope: scope, lessonID: lessonID, trainingID: current.trainingId)
            guard valid(request) else { return }
            lesson = current; learnerName = learner.displayName; observations = values
            // Le référentiel et le brouillon ne conditionnent pas la lecture de la liste privée.
            do {
                let values = try await client.competencies(scope: scope, trainingID: current.trainingId)
                guard valid(request) else { return }
                competencies = values; competenciesMessage = nil
            }
            catch {
                guard valid(request) else { return }
                if isRevoked(error) { throw error }
                competencies = []; competenciesMessage = "Le référentiel est indisponible. Les repères simples restent possibles sans choisir de compétence."
            }
            guard valid(request) else { return }
            // Le brouillon connu reste en place pendant sa relecture : la barre d’action ne disparaît pas entre-temps.
            if current.status == "COMPLETED" {
                do {
                    let values = try await client.agenda.reportClient.drafts(schoolID: scope.schoolID, lessonID: lessonID)
                    guard valid(request) else { return }
                    guard values.count <= 1, values.allSatisfy({ $0.authorMembershipId == scope.membershipID }) else { throw SchoolObservationFailure.invalidResponse }
                    draft = values.first; draftMessage = nil
                } catch {
                    guard valid(request) else { return }
                    if isRevoked(error) { throw error }
                    draft = nil
                    draftMessage = "Le brouillon privé n’a pas pu être relu. Les observations enregistrées restent consultables."
                }
            } else {
                draft = nil; draftMessage = nil
            }
            guard valid(request) else { return }
            isLoading = false; loaded = true
        } catch {
            guard valid(request) else { return }
            // Relecture échouée : l’état de l’école n’est plus connu, les modifications attendent une relecture réussie.
            isLoading = false; loaded = false; competenciesMessage = nil; draftMessage = nil; fail(error)
        }
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
        guard canRetry, let command = rereadPending() else { return }
        let request = generation; isBusy = true; isFirstSend = false; errorMessage = nil
        do {
            try await client.verifyScope(scope)
            guard valid(request) else { return }
            _ = try await client.receipt(for: command)
            // Une preuve vérifiée reste acquittable même si l’écran a été fermé entre-temps.
            try outbox.remove(command)
            guard valid(request) else { return }
            pending = nil; isBusy = false
            confirmation = command.observationUndoOperationID != nil ? "Observation retirée." : "L’école confirme l’enregistrement de la demande."
            await load()
        } catch SchoolObservationFailure.notFound {
            // L’école répond sans ambiguïté qu’elle n’a pas ce reçu : ce n’est pas un retrait de droits.
            guard valid(request) else { return }
            var observationExists = false
            if command.observationUndoOperationID != nil {
                // Annulation en attente : la création peut exister sans son retrait. Elle seule décide.
                do { _ = try await client.receipt(for: command.withoutObservationUndo); observationExists = true }
                catch SchoolObservationFailure.notFound { }
                catch { guard valid(request) else { return }; isBusy = false; fail(error); return }
                guard valid(request) else { return }
            }
            isBusy = false
            if observationExists {
                errorMessage = "L’école a enregistré l’observation, pas encore son retrait. Renvoie la demande pour le terminer."
            } else {
                absentPendingID = command.id
            }
        } catch { guard valid(request) else { return }; isBusy = false; fail(error) }
    }
    /// Retire une demande que l’école ne connaît pas, puis relit la leçon : rien n’est supposé enregistré.
    func abandonPending() async {
        guard pendingAbsent, canRetry, let command = rereadPending(), command.id == absentPendingID else { return }
        do { try outbox.remove(command) }
        catch { storageAccessible = false; fail(error); return }
        pending = nil; absentPendingID = nil; errorMessage = nil; confirmation = nil
        await load()
    }
    func retryPending() async -> Bool {
        guard canRetry, let command = rereadPending() else { return false }
        return await transmit(command, fresh: false)
    }

    private func rereadPending() -> PendingSchoolCommand? {
        do {
            guard let current = try outbox.pending(for: scope), current.scope == scope,
                  current.kind.isObservation, current.routeResourceID == lessonID else { return nil }
            pending = current
            return current
        } catch { fail(error); return nil }
    }

    private func submit<Value: Encodable>(_ value: Value, operation: UUID, kind: SchoolCommandKind, resourceID: UUID?, version: Int) async -> Bool {
        guard canMutate else { return false }
        let request = generation; isBusy = true; isFirstSend = true; errorMessage = nil; confirmation = nil
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
        let request = generation; isBusy = true; isFirstSend = fresh; errorMessage = nil; confirmation = nil
        var sent = false
        do {
            _ = try await authorizedLesson()
            guard valid(request) else { return false }
            try outbox.save(command) // Barrière de durabilité aussi avant chaque reprise.
            sent = true
            _ = try await client.send(command, validateContinuation: { [self] in
                guard valid(request) else { throw CancellationError() }
            })
            try outbox.remove(command)
            guard valid(request) else { return true }
            pending = nil; isBusy = false
            confirmation = command.kind == .removeObservation || command.observationUndoOperationID != nil
                ? "Observation retirée." : "Observation enregistrée."
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
