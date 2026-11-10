import Foundation
import Observation

/// Une séance en cours de saisie. L’identifiant ne sert qu’à l’écran.
struct SchoolCourseOccurrenceDraft: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    var startsAt: Date
    var endsAt: Date
    var instructorID: UUID?
    var attendanceRequired: Bool
    init(id: UUID = UUID(), startsAt: Date, endsAt: Date, instructorID: UUID?, attendanceRequired: Bool = true) {
        self.id = id; self.startsAt = startsAt; self.endsAt = endsAt; self.instructorID = instructorID; self.attendanceRequired = attendanceRequired
    }
}

/// Saisie d’un cours collectif, contrôlée ici avant tout envoi avec les mêmes bornes que le serveur.
struct SchoolCourseForm: Equatable, Sendable, Codable {
    var typeID: UUID?
    var title = ""
    var description = ""
    var location = ""
    var conditions = ""
    /// Langue du cours, comme sur le web (#159) ; `nil` : non précisée. Une valeur inconnue reçue est conservée telle quelle.
    var teachingLanguage: String?
    var responsibleID: UUID?
    var capacity = 12
    var minParticipants: Int?
    var occurrences: [SchoolCourseOccurrenceDraft] = []

    static let maximumOccurrences = 64
    static let maximumOccurrenceSeconds: TimeInterval = 12 * 3600

    private static func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Premier problème de la saisie, en peu de mots ; `nil` quand le brouillon peut partir.
    func problem(now: Date = Date(), publishing: Bool = false) -> String? {
        if typeID == nil { return "Choisis un type de cours." }
        let title = Self.trimmed(title)
        if title.isEmpty { return "Indique un titre." }
        if title.utf16.count > 200 { return "Raccourcis le titre à 200 caractères." }
        if Self.trimmed(description).utf16.count > 4000 { return "Raccourcis la description à 4 000 caractères." }
        if Self.trimmed(location).utf16.count > 500 { return "Raccourcis le lieu à 500 caractères." }
        if Self.trimmed(conditions).utf16.count > 4000 { return "Raccourcis les conditions à 4 000 caractères." }
        if responsibleID == nil { return "Choisis un responsable." }
        if !(1...200).contains(capacity) { return "La capacité va de 1 à 200 places." }
        if let minParticipants, !(1...capacity).contains(minParticipants) { return "Le minimum ne peut pas dépasser la capacité." }
        if occurrences.isEmpty { return "Ajoute au moins une séance." }
        if occurrences.count > Self.maximumOccurrences { return "Un cours compte au plus 64 séances." }
        let sorted = occurrences.sorted { $0.startsAt < $1.startsAt }
        for (index, occurrence) in sorted.enumerated() {
            if occurrence.instructorID == nil { return "Choisis le moniteur de chaque séance." }
            if occurrence.endsAt <= occurrence.startsAt { return "Chaque séance doit finir après son début." }
            if occurrence.endsAt.timeIntervalSince(occurrence.startsAt) > Self.maximumOccurrenceSeconds { return "Une séance dure au plus 12 heures." }
            if index > 0, occurrence.startsAt < sorted[index - 1].endsAt { return "Deux séances se chevauchent." }
        }
        if publishing, let first = sorted.first, first.startsAt <= now { return "La première séance est déjà passée." }
        return nil
    }

    var sortedOccurrences: [SchoolCourseOccurrenceDraft] { occurrences.sorted { $0.startsAt < $1.startsAt } }
    var totalMinutes: Int { occurrences.reduce(0) { $0 + max(0, Int($1.endsAt.timeIntervalSince($1.startsAt) / 60)) } }

    /// Corps envoyé ; `nil` si la saisie est incomplète.
    func body(operationID: UUID, timeZone: String) -> SchoolCourseSeriesBody? {
        guard let typeID, let responsibleID else { return nil }
        let iso = ISO8601DateFormatter()
        let inputs = sortedOccurrences.compactMap { occurrence -> SchoolCourseOccurrenceInput? in
            guard let instructor = occurrence.instructorID else { return nil }
            return SchoolCourseOccurrenceInput(startsAt: iso.string(from: occurrence.startsAt), endsAt: iso.string(from: occurrence.endsAt),
                instructorMembershipId: instructor, attendanceRequired: occurrence.attendanceRequired)
        }
        guard inputs.count == occurrences.count else { return nil }
        return SchoolCourseSeriesBody(operationId: operationID, typeId: typeID, title: Self.trimmed(title),
            description: Self.trimmed(description), location: Self.trimmed(location), conditions: Self.trimmed(conditions),
            teachingLanguage: teachingLanguage, responsibleMembershipId: responsibleID, capacity: capacity, minParticipants: minParticipants,
            timeZone: timeZone, occurrences: inputs)
    }

    init() {}
    init(series: SchoolCourseSeries) {
        typeID = series.typeId; title = series.title; description = series.description; location = series.location
        conditions = series.conditions; responsibleID = series.responsibleMembershipId; capacity = series.capacity
        teachingLanguage = series.teachingLanguage
        minParticipants = series.minParticipants
        occurrences = series.occurrences.sorted { $0.position < $1.position }.compactMap { occurrence in
            guard let start = occurrence.start, let end = occurrence.end else { return nil }
            return SchoolCourseOccurrenceDraft(id: occurrence.id, startsAt: start, endsAt: end, instructorID: occurrence.instructorMembershipId,
                attendanceRequired: occurrence.attendanceRequired)
        }
    }
}

enum SchoolCourseFormat {
    /// « Annulation libre jusqu’à 24 h avant la première séance » ; sans délai, l’annulation reste libre jusqu’au début.
    static func cancellationSentence(hours: Int) -> String {
        hours == 0 ? "Annulation libre jusqu’au début de la première séance" : "Annulation libre jusqu’à \(hours) h avant la première séance"
    }
    /// « 7 h 30 » ; « 45 min » sous l’heure.
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest))"
    }
    static func seats(_ remaining: Int) -> String {
        remaining == 0 ? "Complet" : remaining == 1 ? "1 place restante" : "\(remaining) places restantes"
    }
}

@MainActor @Observable final class SchoolCourseEditorWorkspace: Identifiable {
    let id = UUID()
    let schoolID: UUID
    let membershipID: UUID
    let timeZone: String
    let client: SchoolCourseClient
    let selectedOccurrenceID: UUID?
    private(set) var selectedOccurrenceAvailable = true
    private(set) var accessUnavailable = false
    private(set) var catalogue: SchoolCourseCatalogue?
    /// Brouillon enregistré ; `nil` tant que rien n’a été écrit.
    private(set) var series: SchoolCourseSeries?
    var form = SchoolCourseForm()
    var newTypeTitle = ""
    /// Description du type, comme sur le web (#160) ; distincte de celle de la série.
    var newTypeDescription = ""
    private(set) var isLoading = false
    private(set) var isBusy = false
    var errorMessage: String?
    /// Fin réussie : la feuille se ferme et l’agenda se relit.
    private(set) var finished: SchoolCourseSeries?
    /// Une réponse perdue se rejoue avec la même opération, tant que la saisie n’a pas changé.
    @ObservationIgnored private var pending: (key: String, operation: UUID)?
    private enum Intent { case type, draft(closing: Bool), publication }
    @ObservationIgnored private var pendingIntent: Intent?
    @ObservationIgnored private var initialForm = SchoolCourseForm()
    /// Coffre des opérations de cet appareil (#127) ; sans lui (tests, aperçus), l'opération incertaine reste en mémoire.
    private let persistence: SchoolCourseIntentPersistence?
    @ObservationIgnored private var kept: PendingSchoolCommand?
    @ObservationIgnored private var didRestore = false
    /// Opération incertaine telle qu'elle est partie, ou reprise du coffre : son enveloppe (corps, version, opération)
    /// se rejoue à l'identique, même si le cours a changé depuis (#431).
    @ObservationIgnored private var sent: SchoolCourseEditorRecord?
    /// Pourquoi la reprise ne part pas (archive incomplète, ou cours modifié depuis) ; la saisie reste intacte (#431).
    private(set) var replayHold: String?
    var replayBlocked: Bool { replayHold != nil }
    static let incompleteReplayMessage = "Cette demande, gardée par une ancienne version de l’app, ne peut pas être rejouée telle quelle. Ta saisie est conservée : compare-la à la version à jour pour décider."
    static let staleReplayMessage = "Ce cours a changé depuis ta saisie, qui n’a pas été enregistrée. Elle est conservée : compare-la à la version à jour pour décider."
    static let removalFailedMessage = "Cet appareil n’a pas pu retirer cette demande : elle est conservée avec ta saisie. Réessaie."
    static let rereadFailedMessage = "Le cours n’a pas pu être relu. Réessaie."
    /// Comparaison de la saisie conservée et de la version à jour ; rien ne part tant que la personne n’a pas choisi (#431).
    private(set) var reconciliation: SchoolCourseReconciliation?

    init(schoolID: UUID, membershipID: UUID, timeZone: String, client: SchoolCourseClient,
         catalogue: SchoolCourseCatalogue?, series: SchoolCourseSeries? = nil, day: Date = Date(), selectedOccurrenceID: UUID? = nil,
         persistence: SchoolCourseIntentPersistence? = nil) {
        self.schoolID = schoolID; self.membershipID = membershipID; self.timeZone = timeZone; self.client = client
        self.catalogue = catalogue; self.series = series
        self.persistence = persistence
        self.selectedOccurrenceID = selectedOccurrenceID
        selectedOccurrenceAvailable = selectedOccurrenceID.map { selected in
            series?.occurrences.contains { $0.id == selected } == true
        } ?? true
        if let series { form = SchoolCourseForm(series: series) }
        else {
            form.responsibleID = membershipID
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
            let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            let proposed = max(start, Self.nextHour(after: Date(), calendar: calendar))
            form.occurrences = [SchoolCourseOccurrenceDraft(startsAt: proposed, endsAt: proposed.addingTimeInterval(3 * 3600),
                instructorID: Self.defaultInstructor(catalogue, membershipID: membershipID))]
        }
        applyCatalogueDefaults()
        initialForm = form
    }

    var isNew: Bool { series == nil }
    var focusedOccurrenceID: UUID? {
        guard !accessUnavailable, selectedOccurrenceAvailable, let selectedOccurrenceID,
              form.occurrences.contains(where: { $0.id == selectedOccurrenceID }) else { return nil }
        return selectedOccurrenceID
    }
    var selectionMessage: String? {
        !selectedOccurrenceAvailable && !accessUnavailable
            ? "Cette séance n’est plus disponible. Ferme le cours pour actualiser l’agenda." : nil
    }
    var types: [SchoolCourseType] { catalogue?.types ?? [] }
    var instructors: [SchoolCourseInstructor] { catalogue?.instructors ?? [] }
    var selfCancelHours: Int { catalogue?.policy.selfCancelHours ?? series?.selfCancelHours ?? 24 }
    var problem: String? { form.problem() }
    var canSave: Bool { !isBusy && !accessUnavailable && !replayBlocked && selectionMessage == nil && catalogue?.canManage == true && problem == nil }
    var canPublish: Bool { !isBusy && !accessUnavailable && !replayBlocked && selectionMessage == nil && catalogue?.canManage == true && form.problem(publishing: true) == nil }
    var publishProblem: String? { problem ?? form.problem(publishing: true) }
    var hasUnconfirmedOperation: Bool { pending != nil }

    func load() async {
        restoreKept()
        guard !isLoading else { return }
        let wasUnedited = !hasUnsavedChanges
        isLoading = true; defer { isLoading = false }
        do {
            catalogue = try await client.catalogue(schoolID: schoolID)
            // Une opération reprise garde sa saisie telle quelle : la changer changerait son identité, donc l'opération.
            if pending == nil { applyCatalogueDefaults() }
            if series == nil && wasUnedited { initialForm = form }
            if catalogue?.canManage == false { errorMessage = SchoolCourseClient.failure(403, "COURSE_ACCESS_REQUIRED").errorDescription }
            if let selectedOccurrenceID, let series {
                let fresh = try await client.series(schoolID: schoolID, id: series.id)
                guard !Task.isCancelled else { return }
                selectedOccurrenceAvailable = fresh.isDraft && fresh.occurrences.contains { $0.id == selectedOccurrenceID }
                if !hasUnsavedChanges && fresh.isDraft && pending == nil {
                    self.series = fresh; form = SchoolCourseForm(series: fresh)
                }
            }
        } catch is CancellationError { return }
        catch {
            if let failure = error as? SchoolPlanningFailure, [.unauthorized, .forbidden, .notFound].contains(failure) { accessUnavailable = true }
            if catalogue == nil || selectedOccurrenceID != nil { errorMessage = message(error) }
        }
    }

    func addOccurrence() {
        guard form.occurrences.count < SchoolCourseForm.maximumOccurrences else { return }
        let last = form.sortedOccurrences.last
        let start = last.map { $0.startsAt.addingTimeInterval(7 * 86_400) } ?? Date().addingTimeInterval(86_400)
        let length = last.map { $0.endsAt.timeIntervalSince($0.startsAt) } ?? 3 * 3600
        form.occurrences.append(SchoolCourseOccurrenceDraft(startsAt: start, endsAt: start.addingTimeInterval(length),
            instructorID: last?.instructorID ?? Self.defaultInstructor(catalogue, membershipID: membershipID),
            attendanceRequired: last?.attendanceRequired ?? true))
    }
    func removeOccurrence(_ id: UUID) {
        guard form.occurrences.count > 1 else { return }
        form.occurrences.removeAll { $0.id == id }
    }

    /// Nom et description dans les bornes du serveur (120 et 2 000 caractères).
    var canCreateType: Bool {
        let title = newTypeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isBusy && !title.isEmpty && title.utf16.count <= 120
            && newTypeDescription.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 2000
    }

    /// Type propre à l’école, créé sur place puis choisi. Une réponse perdue se rejoue avec la même opération : un
    /// nouvel essai ne crée pas un second type.
    @discardableResult func createType() async -> Bool {
        let title = newTypeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = newTypeDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canCreateType else { return false }
        pendingIntent = .type
        isBusy = true; errorMessage = nil; defer { isBusy = false }
        let key = "type|\(title)|\(description)"
        let operation = operationID(for: key)
        guard remember(.type, key: key, operation: operation) else { return false }
        do {
            let type = try await client.createType(schoolID: schoolID,
                body: SchoolCourseTypeBody(operationId: operation, title: title, description: description))
            // Le type créé est acquis côté école ; la demande ne quitte l'appareil que si son retrait durable a réussi.
            let cleared = clearPending()
            if let catalogue {
                self.catalogue = SchoolCourseCatalogue(schoolId: catalogue.schoolId, canManage: catalogue.canManage,
                    types: catalogue.types.filter { $0.id != type.id } + [type], policy: catalogue.policy, instructors: catalogue.instructors)
            }
            form.typeID = type.id
            guard cleared else { errorMessage = Self.removalFailedMessage; return false }
            newTypeTitle = ""; newTypeDescription = ""
            return true
        } catch { fail(error); return false }
    }

    /// Écrit le brouillon ; le succès n’est annoncé qu’après la réponse de l’école.
    @discardableResult func saveDraft(closing: Bool = true) async -> SchoolCourseSeries? {
        guard canSave else { return nil }
        pendingIntent = .draft(closing: closing)
        isBusy = true; errorMessage = nil; defer { isBusy = false }
        return await writeDraft(closing: closing)
    }

    /// Enregistre d’abord la saisie si elle a changé, puis publie.
    func publish() async {
        guard canPublish else { return }
        pendingIntent = .publication
        isBusy = true; errorMessage = nil; defer { isBusy = false }
        // Publication incertaine reprise : même version, même opération, que le cours ait changé ou non depuis (#431).
        if let record = sent, record.intent == .publication, record.operationId == pending?.operation {
            guard record.canReplayExactly, let seriesID = record.seriesId, let version = record.baseVersion else {
                hold(Self.incompleteReplayMessage); return
            }
            do {
                let published = try await client.publish(schoolID: schoolID, seriesID: seriesID, version: version, operationID: record.operationId)
                series = published
                guard clearPending() else { errorMessage = Self.removalFailedMessage; return }
                finished = published
            } catch {
                if (error as? SchoolPlanningFailure) == .conflict { hold(Self.staleReplayMessage) } else { fail(error) }
            }
            return
        }
        var written = series
        if written == nil || hasUnsavedChanges { written = await writeDraft(closing: false) }
        guard let draft = written else { return }
        let key = "publish|\(draft.id)|\(draft.version)"
        let operation = operationID(for: key)
        guard remember(.publication, key: key, operation: operation, baseVersion: draft.version) else { return }
        do {
            let published = try await client.publish(schoolID: schoolID, seriesID: draft.id, version: draft.version, operationID: operation)
            series = published
            guard clearPending() else { errorMessage = Self.removalFailedMessage; return }
            finished = published
        } catch { fail(error) }
    }

    var hasUnsavedChanges: Bool {
        if !newTypeTitle.isEmpty { return true }
        guard let series else { return initialForm.comparable != form.comparable || !newTypeTitle.isEmpty }
        return SchoolCourseForm(series: series).comparable != form.comparable
    }

    /// Les champs restent figés après une réponse perdue : ce bouton reprend exactement l’intention précédente.
    func retryUnconfirmed() async {
        guard pending != nil, !isBusy, !replayBlocked else { return }
        // Opération reprise après un arrêt de l'app : le catalogue n'est pas encore relu, et rien ne part sans lui.
        if catalogue == nil { await load() }
        switch pendingIntent {
        case .type: await createType()
        case .draft(let closing): _ = await saveDraft(closing: closing)
        case .publication: await publish()
        case nil: break
        }
    }

    private func writeDraft(closing: Bool) async -> SchoolCourseSeries? {
        let seriesID: UUID?, version: Int?, body: SchoolCourseSeriesBody, replaying: Bool
        if let record = sent, record.intent == .draft, record.operationId == pending?.operation,
           record.form.comparable == form.comparable {
            // Rejeu : l'enveloppe exacte de la première tentative, jamais recalculée sur le cours relu (#431).
            guard record.canReplayExactly,
                  let exact = record.seriesBody ?? (record.seriesId == nil ? form.body(operationID: record.operationId, timeZone: timeZone) : nil)
            else { hold(Self.incompleteReplayMessage); return nil }
            seriesID = record.seriesId; version = record.baseVersion; body = exact; replaying = true
        } else {
            guard let key = draftKey(form, series: series) else { return nil }
            let operation = operationID(for: key)
            guard let fresh = form.body(operationID: operation, timeZone: timeZone) else { return nil }
            guard remember(.draft, closing: closing, key: key, operation: operation, baseVersion: series?.version, body: fresh) else { return nil }
            seriesID = series?.id; version = series?.version; body = fresh; replaying = false
        }
        return await sendDraft(seriesID: seriesID, version: version, body: body, closing: closing, replaying: replaying)
    }

    /// Identité de l'intention d'un brouillon : la même saisie sur la même version désigne la même opération.
    private func draftKey(_ form: SchoolCourseForm, series: SchoolCourseSeries?) -> String? {
        guard let probe = form.body(operationID: Self.zero, timeZone: timeZone), let signature = try? JSONEncoder().encode(probe) else { return nil }
        return "draft|\(series?.id.uuidString ?? "new")|\(series?.version ?? 0)|" + signature.base64EncodedString()
    }

    private func sendDraft(seriesID: UUID?, version: Int?, body: SchoolCourseSeriesBody, closing: Bool, replaying: Bool) async -> SchoolCourseSeries? {
        do {
            let saved = try await client.save(schoolID: schoolID, seriesID: seriesID, version: version, body: body)
            series = saved
            // Réponse de l'école acquise, retrait local à part : sans retrait durable, la demande reste à reprendre.
            guard clearPending() else { errorMessage = Self.removalFailedMessage; return nil }
            if closing { finished = saved }
            return saved
        } catch {
            // Rejeu refusé pour version : l'opération n'a pas été appliquée et le cours a changé. Rien n'est envoyé sur la
            // version récente ; la demande et la saisie restent, à comparer puis à choisir explicitement (#431).
            if replaying, (error as? SchoolPlanningFailure) == .conflict { hold(Self.staleReplayMessage); return nil }
            fail(error); return nil
        }
    }

    private func hold(_ message: String) {
        replayHold = message; errorMessage = message
    }

    private static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private func operationID(for key: String) -> UUID {
        if let pending, pending.key == key { return pending.operation }
        let operation = UUID(); pending = (key, operation); return operation
    }
    private func fail(_ error: any Error) {
        if error is CancellationError { return }
        // Un refus motivé clôt l’opération ; une réponse perdue garde la même pour la nouvelle tentative.
        if let failure = error as? SchoolPlanningFailure, failure.definitiveRejection || failure == .forbidden, !clearPending() {
            errorMessage = "\(message(error)) \(Self.removalFailedMessage)"
            return
        }
        errorMessage = message(error)
    }

    // MARK: Conservation sur l'appareil (#127)

    /// Écrit l'opération et la saisie dans le coffre avant l'envoi. Faux : rien n'a pu être conservé, l'opération ne part pas.
    private func remember(_ intent: SchoolCourseEditorRecord.Intent, closing: Bool = false, key: String, operation: UUID,
                          baseVersion: Int? = nil, body: SchoolCourseSeriesBody? = nil) -> Bool {
        // Même opération reprise : elle est déjà conservée, avec la même saisie et la même enveloppe (sa clé la désigne).
        if sent?.operationId == operation { return true }
        let record = SchoolCourseEditorRecord(operationId: operation, intent: intent, closing: closing, key: key, seriesId: series?.id,
            form: form, newTypeTitle: newTypeTitle, newTypeDescription: newTypeDescription, baseVersion: baseVersion, seriesBody: body)
        guard let persistence else { sent = record; return true }
        do {
            let command = try record.command(scope: persistence.scope, createdAt: Date())
            try persistence.store.replace(kept, with: command)
            kept = command; sent = record
            return true
        } catch {
            pending = nil
            errorMessage = SchoolCourseIntentPersistence.unkeptMessage
            return false
        }
    }

    /// L'école a répondu (ou refusé) : l'opération quitte le coffre.
    /// Faux : le coffre n'a pas pu retirer l'opération ; elle reste alors entière (référence, saisie, blocage) pour être
    /// reprise ou abandonnée. Un reçu de l'école ne vaut jamais suppression locale acquise.
    @discardableResult private func clearPending() -> Bool {
        if let persistence, let command = kept {
            do { try persistence.store.remove(command) } catch { return false }
            kept = nil
        }
        pending = nil; sent = nil; replayHold = nil; reconciliation = nil
        return true
    }

    /// Opération laissée par une session précédente : sa saisie revient telle quelle, à reprendre ou à abandonner par la personne.
    /// Rien n'est renvoyé de soi-même ; reprendre rejoue la même opération, que l'école n'enregistre pas deux fois.
    private func restoreKept() {
        guard let persistence, !didRestore else { return }
        didRestore = true
        guard let commands = try? persistence.store.commands(scope: persistence.scope, seriesID: series?.id ?? membershipID),
              let command = commands.first(where: { $0.kind == .courseEditorIntent }) else { return }
        guard pending == nil, let record = try? JSONDecoder().decode(SchoolCourseEditorRecord.self, from: command.body),
              record.operationId == command.id, record.seriesId == series?.id else {
            try? persistence.store.remove(command)
            return
        }
        kept = command; sent = record
        form = record.form; newTypeTitle = record.newTypeTitle; newTypeDescription = record.newTypeDescription
        pending = (record.key, record.operationId)
        switch record.intent {
        case .type: pendingIntent = .type
        case .draft: pendingIntent = .draft(closing: record.closing)
        case .publication: pendingIntent = .publication
        }
        if record.canReplayExactly { errorMessage = SchoolCourseIntentPersistence.restoredMessage }
        else { hold(Self.incompleteReplayMessage) }
    }

    /// Abandonne la demande à reprendre ; l'école l'a peut-être reçue, l'agenda se relit pour le montrer.
    /// Le geste verrouille l'éditeur de bout en bout (lecture comprise) : ni comparaison, ni « Enregistrer ma saisie », ni
    /// réessai, ni second abandon ne peuvent remplacer l'intention conservée pendant qu'il attend la réponse de l'école.
    func abandonUnconfirmed() async {
        guard pending != nil, !isBusy else { return }
        isBusy = true
        let abandoned = await abandonLocked()
        isBusy = false
        if abandoned { await load() }
    }

    /// Vrai quand la demande a été retirée du coffre. Le retrait vise l'intention capturée au départ : si elle a changé
    /// entre-temps, rien n'est retiré.
    private func abandonLocked() async -> Bool {
        let captured = kept, capturedOperation = pending?.operation
        // Demande bloquée : la saisie est jetée et le cours se relit à sa version actuelle avant que quoi que ce soit reparte (#431).
        // Rien n'est annoncé ni remplacé tant que le coffre n'a pas retiré la demande.
        var fresh: SchoolCourseSeries?
        if replayBlocked, let current = series {
            do { fresh = try await client.series(schoolID: schoolID, id: current.id) }
            catch is CancellationError { return false }
            catch { errorMessage = Self.rereadFailedMessage; return false }
            guard !Task.isCancelled else { return false }
        }
        guard kept?.id == captured?.id, pending?.operation == capturedOperation else { return false }
        guard clearPending() else { errorMessage = Self.removalFailedMessage; return false }
        if let fresh {
            series = fresh; form = SchoolCourseForm(series: fresh); initialForm = form
            newTypeTitle = ""; newTypeDescription = ""
        }
        pendingIntent = nil
        errorMessage = "Demande abandonnée. L’école l’a peut-être reçue : vérifie l’agenda avant d’enregistrer à nouveau."
        return true
    }

    /// Relit le cours et montre ce qui diffère de la saisie conservée. Aucune écriture, aucun `If-Match` avancé : la saisie
    /// reste figée. Une ancienne archive sans base ne dit pas ce qui avait été modifié : seules les différences avec la
    /// version à jour sont montrées, jamais « mes » modifications supposées.
    func compareHeldInput() async {
        guard replayBlocked, !isBusy, let id = series?.id ?? sent?.seriesId else { return }
        isBusy = true; defer { isBusy = false }
        do {
            let fresh = try await client.series(schoolID: schoolID, id: id)
            guard !Task.isCancelled else { return }
            reconciliation = SchoolCourseReconciliation(current: fresh,
                differences: form.differences(from: SchoolCourseForm(series: fresh), catalogue: catalogue, timeZone: timeZone),
                canKeepMine: fresh.isDraft && catalogue?.canManage == true)
            errorMessage = replayHold
        } catch is CancellationError { return }
        catch { errorMessage = Self.rereadFailedMessage }
    }

    /// Décision : la saisie conservée devient une nouvelle opération sur la version relue, remplaçant la demande bloquée en
    /// une seule écriture du coffre. La demande bloquée n'est jamais rejouée et la version relue n'est jamais prise en silence.
    func keepMyInputOnCurrentVersion() async {
        guard let reconciliation, reconciliation.canKeepMine, replayBlocked, !isBusy else { return }
        if let problem = form.problem() { errorMessage = problem; return }
        let fresh = reconciliation.current, operation = UUID()
        guard let key = draftKey(form, series: fresh), let body = form.body(operationID: operation, timeZone: timeZone) else { return }
        isBusy = true; errorMessage = nil; defer { isBusy = false }
        let record = SchoolCourseEditorRecord(operationId: operation, intent: .draft, closing: false, key: key, seriesId: fresh.id,
            form: form, newTypeTitle: newTypeTitle, newTypeDescription: newTypeDescription, baseVersion: fresh.version, seriesBody: body)
        if let persistence {
            do {
                let command = try record.command(scope: persistence.scope, createdAt: Date())
                try persistence.store.replace(kept, with: command)
                kept = command
            } catch {
                errorMessage = SchoolCourseIntentPersistence.unkeptMessage
                return
            }
        }
        sent = record; pending = (key, operation); pendingIntent = .draft(closing: false)
        series = fresh; replayHold = nil; self.reconciliation = nil
        _ = await sendDraft(seriesID: fresh.id, version: fresh.version, body: body, closing: false, replaying: false)
    }
    private func message(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "L’école n’a pas pu enregistrer ce cours."
    }
    private func applyCatalogueDefaults() {
        guard let catalogue else { return }
        if form.typeID == nil || !catalogue.types.contains(where: { $0.id == form.typeID }) {
            form.typeID = series?.typeId ?? catalogue.types.first?.id
        }
        if series == nil, form.title.isEmpty, let type = catalogue.types.first(where: { $0.id == form.typeID }) { form.title = type.title }
        let fallback = Self.defaultInstructor(catalogue, membershipID: membershipID)
        for index in form.occurrences.indices where form.occurrences[index].instructorID == nil { form.occurrences[index].instructorID = fallback }
    }
    private static func defaultInstructor(_ catalogue: SchoolCourseCatalogue?, membershipID: UUID) -> UUID? {
        guard let catalogue else { return nil }
        if catalogue.instructors.contains(where: { $0.membershipId == membershipID }) { return membershipID }
        return catalogue.instructors.count == 1 ? catalogue.instructors.first?.membershipId : nil
    }
    private static func nextHour(after date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.end ?? date
    }
}

private extension SchoolCourseForm {
    /// Comparaison sans les identifiants d’écran des séances.
    var comparable: String {
        let iso = ISO8601DateFormatter()
        let sessions = sortedOccurrences.map { "\(iso.string(from: $0.startsAt))/\(iso.string(from: $0.endsAt))/\($0.instructorID?.uuidString ?? "")/\($0.attendanceRequired)" }
        let parts: [String] = [typeID?.uuidString ?? "", title.trimmingCharacters(in: .whitespacesAndNewlines),
            description.trimmingCharacters(in: .whitespacesAndNewlines), location.trimmingCharacters(in: .whitespacesAndNewlines),
            conditions.trimmingCharacters(in: .whitespacesAndNewlines), responsibleID?.uuidString ?? "", String(capacity),
            minParticipants.map(String.init) ?? "", teachingLanguage ?? ""]
        return (parts + sessions).joined(separator: "|")
    }
}

/// Une séance de cours telle que la liste du jour l’affiche.
struct SchoolAgendaCourseItem: Identifiable, Equatable, Sendable {
    let series: SchoolCourseSeries
    let occurrence: SchoolCourseOccurrence
    var id: UUID { occurrence.id }

    /// Séances autorisées qui commencent ce jour ; leur statut reste visible, même après annulation.
    static func items(_ series: [SchoolCourseSeries], on day: Date, calendar: Calendar) -> [SchoolAgendaCourseItem] {
        series.flatMap { course in course.occurrences.map { SchoolAgendaCourseItem(series: course, occurrence: $0) } }
            .filter { item in item.occurrence.start.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
            .sorted {
                if $0.occurrence.start != $1.occurrence.start { return ($0.occurrence.start ?? .distantPast) < ($1.occurrence.start ?? .distantPast) }
                return $0.id.uuidString < $1.id.uuidString
            }
    }
}

/// Fiche d’un cours publié : seule la capacité se change ici.
@MainActor @Observable final class SchoolCourseDetailWorkspace: Identifiable {
    let id = UUID()
    let schoolID: UUID
    let client: SchoolCourseClient
    let selectedOccurrenceID: UUID?
    private(set) var accessUnavailable = false
    private(set) var series: SchoolCourseSeries
    var capacity: Int
    private(set) var isBusy = false
    var errorMessage: String?
    @ObservationIgnored private var pending: (capacity: Int, version: Int, operation: UUID)?
    /// Inscrits et file, seulement pour qui gère un cours publié.
    let roster: SchoolCourseRosterWorkspace?
    /// Coffre des gestes de la feuille des participants (#128 à #130) ; absent dans les tests et les aperçus.
    let persistence: SchoolCourseIntentPersistence?

    init(schoolID: UUID, client: SchoolCourseClient, series: SchoolCourseSeries, learners: [SchoolLearner] = [],
         learnerPages: SchoolCourseLearnerPageReader? = nil, selectedOccurrenceID: UUID? = nil,
         persistence: SchoolCourseIntentPersistence? = nil) {
        self.schoolID = schoolID; self.client = client; self.series = series; capacity = series.capacity
        self.selectedOccurrenceID = selectedOccurrenceID
        self.persistence = persistence
        roster = series.canManage && series.status == .published
            ? SchoolCourseRosterWorkspace(schoolID: schoolID, seriesID: series.id, client: client, learners: learners,
                learnerPages: learnerPages) : nil
        roster?.onChange = { [weak self] in await self?.refresh() }
    }
    var minimumCapacity: Int { min(200, max(1, series.seatsTaken, series.minParticipants ?? 1)) }
    var focusedOccurrenceID: UUID? {
        guard !accessUnavailable, let selectedOccurrenceID, series.occurrences.contains(where: { $0.id == selectedOccurrenceID }) else { return nil }
        return selectedOccurrenceID
    }
    var selectionMessage: String? {
        selectedOccurrenceID != nil && focusedOccurrenceID == nil && !accessUnavailable
            ? "Cette séance n’est plus disponible. Ferme le cours pour actualiser l’agenda." : nil
    }
    var canChangeCapacity: Bool {
        !accessUnavailable && selectionMessage == nil && series.canManage && series.status == .published && !isBusy && capacity != series.capacity && (minimumCapacity...200).contains(capacity)
    }

    func refresh() async {
        guard !isBusy else { return }
        do {
            let fresh = try await client.series(schoolID: schoolID, id: series.id)
            guard !Task.isCancelled else { return }
            if capacity == series.capacity { capacity = fresh.capacity }
            series = fresh; errorMessage = nil; accessUnavailable = false
        } catch is CancellationError { return }
        catch {
            if let failure = error as? SchoolPlanningFailure, [.unauthorized, .forbidden, .notFound].contains(failure) { accessUnavailable = true }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Le cours n’a pas pu être actualisé."
        }
    }
    func changeCapacity() async {
        guard canChangeCapacity else { return }
        isBusy = true; errorMessage = nil; defer { isBusy = false }
        let operation: UUID
        if let pending, pending.capacity == capacity, pending.version == series.version { operation = pending.operation }
        else { operation = UUID(); pending = (capacity, series.version, operation) }
        do {
            series = try await client.changeCapacity(schoolID: schoolID, seriesID: series.id, version: series.version,
                operationID: operation, capacity: capacity)
            pending = nil; capacity = series.capacity
        } catch is CancellationError {
        } catch {
            if let failure = error as? SchoolPlanningFailure, failure.definitiveRejection { pending = nil }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "La capacité n’a pas pu être changée."
        }
    }
}

/// Langues proposées pour un cours, les mêmes que le web et que le contrat (`fr`, `de`, `it`, `en`).
struct SchoolCourseLanguage: Identifiable {
    let id: String
    let label: String

    static let all = [SchoolCourseLanguage(id: "fr", label: "Français"), SchoolCourseLanguage(id: "de", label: "Allemand"),
                      SchoolCourseLanguage(id: "it", label: "Italien"), SchoolCourseLanguage(id: "en", label: "Anglais")]

    /// Langue enregistrée dite à l’élève (#221) : « Cours en allemand ». Rien si l’école ne l’a pas précisée, jamais
    /// une langue par défaut ; un code hors catalogue garde son nom système, ou son code.
    static func phrase(for code: String?) -> String? {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else { return nil }
        if let known = all.first(where: { $0.id == code }) { return "Cours en \(known.label.lowercased())" }
        if let name = Locale(identifier: "fr_CH").localizedString(forLanguageCode: code), name.lowercased() != code.lowercased() {
            return "Cours en \(name.lowercased())"
        }
        return "Langue : \(code.uppercased())"
    }
}

/// Saisie conservée face à la version à jour du cours (#431).
struct SchoolCourseReconciliation {
    let current: SchoolCourseSeries
    let differences: [SchoolCourseFieldDifference]
    /// Faux quand le cours n'est plus un brouillon ou que les droits manquent : seule la version à jour reste.
    let canKeepMine: Bool
}

struct SchoolCourseFieldDifference: Identifiable, Equatable, Sendable {
    let label: String
    let mine: String
    let current: String
    var id: String { label }
}

extension SchoolCourseForm {
    /// Champs dont la valeur diffère de `current`. Pas de base : on compare deux états, on ne devine pas qui a changé quoi.
    /// La différence se décide sur les valeurs métier (identifiants, dates réelles) ; le libellé français ne sert qu'à
    /// l'affichage. Deux personnes ou deux types de même nom restent donc une différence, dite « autre » plutôt que montrée
    /// identique, et aucun identifiant brut n'est exposé.
    func differences(from current: SchoolCourseForm, catalogue: SchoolCourseCatalogue?, timeZone: String) -> [SchoolCourseFieldDifference] {
        func text(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "—" : trimmed
        }
        func type(_ id: UUID?) -> String {
            guard let id else { return "—" }
            return catalogue?.types.first { $0.id == id }?.title ?? "Type introuvable"
        }
        func person(_ id: UUID?) -> String {
            guard let id else { return "—" }
            return catalogue?.instructors.first { $0.membershipId == id }?.displayName ?? "Moniteur introuvable"
        }
        /// Même libellé pour deux identités distinctes : la saisie le dit.
        func pair(_ label: String, _ mine: UUID?, _ theirs: UUID?, _ format: (UUID?) -> String, other: String) -> SchoolCourseFieldDifference? {
            guard mine != theirs else { return nil }
            let a = format(mine), b = format(theirs)
            return SchoolCourseFieldDifference(label: label, mine: a == b ? "\(a) (\(other))" : a, current: b)
        }
        func line(_ occurrence: SchoolCourseOccurrenceDraft, suffix: String = "") -> String {
            "\(SchoolPlanningFormat.instant(occurrence.startsAt, zone: timeZone)) · "
                + SchoolCourseFormat.duration(minutes: max(0, Int(occurrence.endsAt.timeIntervalSince(occurrence.startsAt) / 60)))
                + " · \(person(occurrence.instructorID))\(suffix)" + (occurrence.attendanceRequired ? "" : " · présence facultative")
        }
        func same(_ a: SchoolCourseOccurrenceDraft, _ b: SchoolCourseOccurrenceDraft) -> Bool {
            Int(a.startsAt.timeIntervalSince1970) == Int(b.startsAt.timeIntervalSince1970)
                && Int(a.endsAt.timeIntervalSince1970) == Int(b.endsAt.timeIntervalSince1970)
                && a.instructorID == b.instructorID && a.attendanceRequired == b.attendanceRequired
        }
        var result: [SchoolCourseFieldDifference] = []
        func add(_ label: String, _ mine: String, _ theirs: String) {
            if mine != theirs { result.append(SchoolCourseFieldDifference(label: label, mine: mine, current: theirs)) }
        }
        if let d = pair("Type", typeID, current.typeID, type, other: "autre type") { result.append(d) }
        add("Titre", text(title), text(current.title))
        add("Description", text(description), text(current.description))
        add("Lieu", text(location), text(current.location))
        add("Conditions", text(conditions), text(current.conditions))
        add("Langue", teachingLanguage ?? "—", current.teachingLanguage ?? "—")
        if let d = pair("Responsable", responsibleID, current.responsibleID, person, other: "autre compte") { result.append(d) }
        add("Capacité", String(capacity), String(current.capacity))
        add("Minimum", minParticipants.map(String.init) ?? "—", current.minParticipants.map(String.init) ?? "—")
        let mine = sortedOccurrences, theirs = current.sortedOccurrences
        let identical = mine.count == theirs.count && zip(mine, theirs).allSatisfy(same)
        if !identical {
            let mineLines = mine.enumerated().map { index, occurrence -> String in
                // Même ligne lue, mais autre moniteur de même nom : la différence est nommée.
                if index < theirs.count, occurrence.instructorID != theirs[index].instructorID,
                   person(occurrence.instructorID) == person(theirs[index].instructorID) { return line(occurrence, suffix: " (autre compte)") }
                return line(occurrence)
            }
            result.append(SchoolCourseFieldDifference(label: "Séances", mine: mineLines.joined(separator: "\n"),
                current: theirs.map { line($0) }.joined(separator: "\n")))
        }
        return result
    }
}
