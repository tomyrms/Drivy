import Foundation
import Observation

/// Textes courts des inscriptions aux cours collectifs, toujours dans le fuseau de l’école.
@MainActor enum SchoolCourseEnrollmentFormat {
    static func status(_ me: SchoolCourseLearnerState, zone: String, now: Date = Date()) -> String {
        switch me.state {
        case .available: return "Disponible"
        case .full: return "Complet"
        case .enrolled: return "Inscrit"
        case .waiting: return me.waitlistPosition.map { "En attente (rang \($0))" } ?? "En attente"
        case .offered:
            guard let expiry = me.offer?.expiry else { return "Place proposée" }
            return "Place proposée jusqu’à \(moment(expiry, zone: zone, now: now))"
        case .completed: return "Déjà effectué"
        case .cancelled: return "Annulé"
        case .closed: return "Inscriptions fermées"
        }
    }
    /// « 18:00 » le jour même, sinon « jeudi 3 mars à 18:00 ».
    static func moment(_ date: Date, zone: String, now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(identifier: zone) ?? .current
        calendar.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) { return SchoolDateCache.shared.string(from: date, zone: timeZone, format: "HH:mm") }
        return SchoolDateCache.shared.string(from: date, zone: timeZone, format: "EEEE d MMMM 'à' HH:mm")
    }
    /// Échéance exacte, avec l’année : « jeudi 3 mars 2030 à 18:00 ».
    static func deadline(_ date: Date, zone: String) -> String {
        SchoolDateCache.shared.string(from: date, zone: TimeZone(identifier: zone) ?? .current, format: "EEEE d MMMM yyyy 'à' HH:mm")
    }
    /// « 3 mars 2030 ».
    static func day(_ date: Date, zone: String) -> String {
        SchoolDateCache.shared.string(from: date, zone: TimeZone(identifier: zone) ?? .current, format: "d MMMM yyyy")
    }
    static func sessions(_ count: Int) -> String { count == 1 ? "la séance" : "les \(count) séances" }
    static func mailURL(_ email: String?, courseTitle: String) -> URL? {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty, email.contains("@"),
              !email.contains(where: { $0.isWhitespace || $0 == "?" || $0 == "&" }) else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"; components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: "Annulation : \(courseTitle)")]
        return components.url
    }
}

/// Opération en cours d’une intention : une réponse perdue se rejoue avec le même identifiant.
struct SchoolCourseOperationMemory {
    private var pending: (key: String, operation: UUID)?
    mutating func operation(for key: String) -> UUID {
        if let pending, pending.key == key { return pending.operation }
        let operation = UUID(); pending = (key, operation); return operation
    }
    mutating func settle() { pending = nil }
    /// Un refus motivé clôt l’opération ; une panne la garde pour la nouvelle tentative.
    mutating func fail(_ error: any Error) {
        if let failure = error as? SchoolPlanningFailure, failure.definitiveRejection || failure == .forbidden || failure == .notFound { pending = nil }
    }
}

/// Fiche d’un cours vue par l’élève : son état personnel et ses commandes.
@MainActor @Observable final class SchoolCourseLearnerWorkspace: Identifiable {
    let id = UUID()
    let schoolID: UUID
    let seriesID: UUID
    let timeZone: String
    let client: SchoolCourseClient
    private(set) var reply: SchoolCourseLearnerReply?
    private(set) var isLoading = false
    private(set) var isBusy = false
    var errorMessage: String?
    /// Dernière commande confirmée par l’école, annoncée une fois.
    private(set) var confirmation: String?
    @ObservationIgnored private var memory = SchoolCourseOperationMemory()
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    init(schoolID: UUID, seriesID: UUID, timeZone: String, client: SchoolCourseClient) {
        self.schoolID = schoolID; self.seriesID = seriesID; self.timeZone = timeZone; self.client = client
    }

    var series: SchoolCourseSeries? { reply?.series }
    var me: SchoolCourseLearnerState? { reply?.me }
    /// Le type de cours est suivi (prochaines sessions, #40) ; `nil` tant que l’école ne l’a pas dit.
    private(set) var following: Bool?
    private(set) var isUpdatingFollow = false

    /// Lecture séparée : une panne laisse seulement le bouton absent.
    func loadFollow() async {
        guard let typeID = series?.typeId, !isUpdatingFollow,
              let types = try? await client.follows(schoolID: schoolID), !Task.isCancelled else { return }
        following = types.contains(typeID)
    }

    /// Geste explicite : l’autorisation système n’est demandée qu’en s’abonnant. Rien n’est annoncé avant l’école.
    func setFollow(_ value: Bool) async {
        guard let typeID = series?.typeId, !isUpdatingFollow else { return }
        isUpdatingFollow = true; errorMessage = nil; confirmation = nil; defer { isUpdatingFollow = false }
        if value { await SchoolPushCenter.shared.requestAuthorization() }
        do {
            following = try await client.setFollow(schoolID: schoolID, typeID: typeID, following: value)
            confirmation = value ? "Tu seras prévenu des prochaines sessions" : "Tu ne seras plus prévenu"
        } catch is CancellationError {
        } catch { errorMessage = Self.message(error) }
    }

    func load() async {
        guard !isLoading, !isBusy else { return }
        isLoading = true; defer { isLoading = false }
        do {
            reply = try await client.learnerView(schoolID: schoolID, seriesID: seriesID)
            if errorMessage != nil && reply != nil { errorMessage = nil }
            if following == nil { await loadFollow() }
        } catch is CancellationError {
        } catch { errorMessage = Self.message(error) }
    }

    /// Écrit la commande ; rien n’est annoncé avant la réponse de l’école.
    @discardableResult func perform(_ action: SchoolCourseLearnerAction) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true; errorMessage = nil; confirmation = nil; defer { isBusy = false }
        let operation = memory.operation(for: action.key)
        do {
            let result = try await client.act(action, schoolID: schoolID, seriesID: seriesID, operationID: operation)
            memory.settle(); reply = result
            confirmation = Self.done(action)
            onChange?()
            return true
        } catch is CancellationError { return false }
        catch {
            memory.fail(error)
            errorMessage = Self.message(error)
            // Un refus motivé dit que l’état a changé : la fiche se relit sans effacer le message.
            if let failure = error as? SchoolPlanningFailure, failure.definitiveRejection {
                let kept = errorMessage
                isBusy = false
                await load()
                errorMessage = kept
            }
            return false
        }
    }

    /// L’échéance d’annulation de la série est passée (accepter une place ne permettra plus d’annuler soi-même).
    func cancellationClosed(now: Date = Date()) -> Bool {
        guard let deadline = series.flatMap({ SchoolLesson.date($0.selfCancellationDeadline) }) else { return false }
        return deadline < now
    }

    private static func done(_ action: SchoolCourseLearnerAction) -> String {
        switch action {
        case .enroll, .accept: "Inscription confirmée"
        case .joinWaitlist: "Ajouté à la liste d’attente"
        case .leaveWaitlist: "Retiré de la liste d’attente"
        case .decline: "Place refusée"
        case .cancel: "Inscription annulée"
        }
    }
    static func message(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "L’école n’a pas pu répondre."
    }
}

/// Cours ouverts à l’élève et ses propositions actives, lues sans push.
@MainActor @Observable final class SchoolLearnerCoursesWorkspace: Identifiable {
    let id = UUID()
    let schoolID: UUID
    let timeZone: String
    let client: SchoolCourseClient
    private(set) var courses: [SchoolCourseSeries] = []
    private(set) var mine: SchoolCourseMine?
    /// Validations et progression personnelles ; aucun règlement.
    private(set) var progress: SchoolCourseProgress?
    /// Titres des cours déjà commencés, absents de la liste à venir.
    private(set) var startedTitles: [UUID: String] = [:]
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?

    init(schoolID: UUID, timeZone: String, client: SchoolCourseClient) {
        self.schoolID = schoolID; self.timeZone = timeZone; self.client = client
    }

    var offers: [SchoolCourseOffer] {
        (mine?.offers ?? []).filter { ($0.expiry ?? .distantPast) > Date() }
    }
    func offer(for seriesID: UUID) -> SchoolCourseOffer? { offers.first { $0.seriesId == seriesID } }
    func isEnrolled(_ seriesID: UUID) -> Bool {
        mine?.items.contains { $0.seriesId == seriesID && $0.status == .active } == true
    }
    func title(for seriesID: UUID) -> String? { courses.first { $0.id == seriesID }?.title ?? startedTitles[seriesID] }
    /// Inscriptions comptant des séances obligatoires.
    var tracked: [SchoolCourseProgress.Enrollment] { (progress?.enrollments ?? []).filter { $0.requirements.required > 0 } }

    /// La progression ne bloque pas la liste : une panne la laisse simplement absente.
    func loadProgress() async {
        guard let fresh = try? await client.progress(schoolID: schoolID), !Task.isCancelled else { return }
        progress = fresh
        for enrollment in fresh.enrollments where title(for: enrollment.seriesId) == nil {
            if let series = try? await client.series(schoolID: schoolID, id: enrollment.seriesId) { startedTitles[series.id] = series.title }
        }
    }

    /// Propositions seulement : le bandeau se relit souvent, la liste à l’ouverture.
    func refreshOffers() async {
        guard let fresh = try? await client.mine(schoolID: schoolID), !Task.isCancelled else { return }
        mine = fresh
    }
    func load(now: Date = Date()) async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let items = try await client.series(schoolID: schoolID, from: now, to: now.addingTimeInterval(366 * 86_400))
            let personal = try await client.mine(schoolID: schoolID)
            courses = items.filter { $0.status == .published }
            mine = personal; hasLoaded = true; errorMessage = nil
        } catch is CancellationError {
        } catch { errorMessage = SchoolCourseLearnerWorkspace.message(error) }
        await loadProgress()
    }
}

/// Inscrits et file d’un cours publié, pour le personnel habilité (droits relus par le serveur).
@MainActor @Observable final class SchoolCourseRosterWorkspace {
    let schoolID: UUID
    let seriesID: UUID
    let client: SchoolCourseClient
    /// Élèves actifs déjà lus par l’app, proposés à l’inscription.
    let learners: [SchoolLearner]
    private(set) var roster: SchoolCourseRoster?
    private(set) var isLoading = false
    private(set) var isBusy = false
    var errorMessage: String?
    private(set) var confirmation: String?
    @ObservationIgnored private var memory = SchoolCourseOperationMemory()
    @ObservationIgnored var onChange: (@MainActor () async -> Void)?

    init(schoolID: UUID, seriesID: UUID, client: SchoolCourseClient, learners: [SchoolLearner]) {
        self.schoolID = schoolID; self.seriesID = seriesID; self.client = client
        self.learners = learners.filter { $0.archivedAt == nil }.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    /// Élèves sans inscription active ni place en file.
    var candidates: [SchoolLearner] {
        let taken = Set((roster?.active.map(\.enrollment.learnerId) ?? []) + (roster?.waitlist.map(\.learnerId) ?? []))
        return learners.filter { !taken.contains($0.id) }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do { roster = try await client.roster(schoolID: schoolID, seriesID: seriesID); errorMessage = nil }
        catch is CancellationError {}
        catch { errorMessage = SchoolCourseLearnerWorkspace.message(error) }
    }

    @discardableResult func enroll(_ learner: SchoolLearner) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true; errorMessage = nil; confirmation = nil; defer { isBusy = false }
        let operation = memory.operation(for: "staff-enroll|\(learner.id)")
        do {
            _ = try await client.staffEnroll(schoolID: schoolID, seriesID: seriesID, learnerID: learner.id, operationID: operation)
            memory.settle(); confirmation = "\(learner.displayName) est inscrit"
        } catch is CancellationError { return false }
        catch { memory.fail(error); errorMessage = SchoolCourseLearnerWorkspace.message(error); return false }
        await reloadAfterChange()
        return true
    }

    @discardableResult func cancel(_ row: SchoolCourseRosterEnrollment, reason: String) async -> Bool {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !reason.isEmpty, reason.count <= 1000 else { return false }
        isBusy = true; errorMessage = nil; confirmation = nil; defer { isBusy = false }
        let operation = memory.operation(for: "staff-cancel|\(row.enrollment.id)|\(row.enrollment.version)|\(reason)")
        do {
            _ = try await client.staffCancel(schoolID: schoolID, enrollmentID: row.enrollment.id, version: row.enrollment.version,
                reason: reason, operationID: operation)
            memory.settle(); confirmation = "Inscription annulée"
        } catch is CancellationError { return false }
        catch { memory.fail(error); errorMessage = SchoolCourseLearnerWorkspace.message(error); return false }
        await reloadAfterChange()
        return true
    }

    private func reloadAfterChange() async {
        isLoading = false
        await load()
        await onChange?()
    }
}
