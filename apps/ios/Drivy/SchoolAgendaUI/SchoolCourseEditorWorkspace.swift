import Foundation
import Observation

/// Une séance en cours de saisie. L’identifiant ne sert qu’à l’écran.
struct SchoolCourseOccurrenceDraft: Identifiable, Equatable, Sendable {
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
struct SchoolCourseForm: Equatable, Sendable {
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

    init(schoolID: UUID, membershipID: UUID, timeZone: String, client: SchoolCourseClient,
         catalogue: SchoolCourseCatalogue?, series: SchoolCourseSeries? = nil, day: Date = Date(), selectedOccurrenceID: UUID? = nil) {
        self.schoolID = schoolID; self.membershipID = membershipID; self.timeZone = timeZone; self.client = client
        self.catalogue = catalogue; self.series = series
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
    var canSave: Bool { !isBusy && !accessUnavailable && selectionMessage == nil && catalogue?.canManage == true && problem == nil }
    var canPublish: Bool { !isBusy && !accessUnavailable && selectionMessage == nil && catalogue?.canManage == true && form.problem(publishing: true) == nil }
    var publishProblem: String? { problem ?? form.problem(publishing: true) }
    var hasUnconfirmedOperation: Bool { pending != nil }

    func load() async {
        guard !isLoading else { return }
        let wasUnedited = !hasUnsavedChanges
        isLoading = true; defer { isLoading = false }
        do {
            catalogue = try await client.catalogue(schoolID: schoolID)
            applyCatalogueDefaults()
            if series == nil && wasUnedited { initialForm = form }
            if catalogue?.canManage == false { errorMessage = SchoolCourseClient.failure(403, "COURSE_ACCESS_REQUIRED").errorDescription }
            if let selectedOccurrenceID, let series {
                let fresh = try await client.series(schoolID: schoolID, id: series.id)
                guard !Task.isCancelled else { return }
                selectedOccurrenceAvailable = fresh.isDraft && fresh.occurrences.contains { $0.id == selectedOccurrenceID }
                if !hasUnsavedChanges && fresh.isDraft {
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
        let operation = operationID(for: "type|\(title)|\(description)")
        do {
            let type = try await client.createType(schoolID: schoolID,
                body: SchoolCourseTypeBody(operationId: operation, title: title, description: description))
            pending = nil
            if let catalogue {
                self.catalogue = SchoolCourseCatalogue(schoolId: catalogue.schoolId, canManage: catalogue.canManage,
                    types: catalogue.types.filter { $0.id != type.id } + [type], policy: catalogue.policy, instructors: catalogue.instructors)
            }
            form.typeID = type.id; newTypeTitle = ""; newTypeDescription = ""
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
        var written = series
        if written == nil || hasUnsavedChanges { written = await writeDraft(closing: false) }
        guard let draft = written else { return }
        let operation = operationID(for: "publish|\(draft.id)|\(draft.version)")
        do {
            let published = try await client.publish(schoolID: schoolID, seriesID: draft.id, version: draft.version, operationID: operation)
            pending = nil; series = published; finished = published
        } catch { fail(error) }
    }

    var hasUnsavedChanges: Bool {
        if !newTypeTitle.isEmpty { return true }
        guard let series else { return initialForm.comparable != form.comparable || !newTypeTitle.isEmpty }
        return SchoolCourseForm(series: series).comparable != form.comparable
    }

    /// Les champs restent figés après une réponse perdue : ce bouton reprend exactement l’intention précédente.
    func retryUnconfirmed() async {
        guard pending != nil, !isBusy else { return }
        switch pendingIntent {
        case .type: await createType()
        case .draft(let closing): _ = await saveDraft(closing: closing)
        case .publication: await publish()
        case nil: break
        }
    }

    private func writeDraft(closing: Bool) async -> SchoolCourseSeries? {
        guard let probe = form.body(operationID: UUID(), timeZone: timeZone),
              let signature = try? JSONEncoder().encode(SchoolCourseSeriesBody(operationId: Self.zero, typeId: probe.typeId, title: probe.title,
                description: probe.description, location: probe.location, conditions: probe.conditions, teachingLanguage: probe.teachingLanguage,
                responsibleMembershipId: probe.responsibleMembershipId, capacity: probe.capacity, minParticipants: probe.minParticipants,
                timeZone: probe.timeZone, occurrences: probe.occurrences)) else { return nil }
        let key = "draft|\(series?.id.uuidString ?? "new")|\(series?.version ?? 0)|" + signature.base64EncodedString()
        let operation = operationID(for: key)
        guard let body = form.body(operationID: operation, timeZone: timeZone) else { return nil }
        do {
            let saved = try await client.save(schoolID: schoolID, seriesID: series?.id, version: series?.version, body: body)
            pending = nil; series = saved
            if closing { finished = saved }
            return saved
        } catch { fail(error); return nil }
    }

    private static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private func operationID(for key: String) -> UUID {
        if let pending, pending.key == key { return pending.operation }
        let operation = UUID(); pending = (key, operation); return operation
    }
    private func fail(_ error: any Error) {
        if error is CancellationError { return }
        // Un refus motivé clôt l’opération ; une réponse perdue garde la même pour la nouvelle tentative.
        if let failure = error as? SchoolPlanningFailure, failure.definitiveRejection || failure == .forbidden { pending = nil }
        errorMessage = message(error)
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

    init(schoolID: UUID, client: SchoolCourseClient, series: SchoolCourseSeries, learners: [SchoolLearner] = [], selectedOccurrenceID: UUID? = nil) {
        self.schoolID = schoolID; self.client = client; self.series = series; capacity = series.capacity
        self.selectedOccurrenceID = selectedOccurrenceID
        roster = series.canManage && series.status == .published
            ? SchoolCourseRosterWorkspace(schoolID: schoolID, seriesID: series.id, client: client, learners: learners) : nil
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
}
