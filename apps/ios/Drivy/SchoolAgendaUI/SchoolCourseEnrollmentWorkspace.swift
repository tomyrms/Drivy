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
            // Échéance passée sur cet appareil : la fiche se relit, l’école dit la suite (#224).
            if expiry <= now { return "Délai de réponse passé" }
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
    static func cancellationMessage(_ count: Int) -> String {
        count == 1 ? "Ton inscription à la séance sera annulée." : "Ton inscription aux \(count) séances sera annulée."
    }
    static func mailURL(_ email: String?, courseTitle: String) -> URL? {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty, email.contains("@"),
              !email.contains(where: { $0.isWhitespace || $0 == "?" || $0 == "&" }) else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"; components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: "Annulation : \(courseTitle)")]
        return components.url
    }
}

/// Geste qui rend une place ou un rang (#223), confirmé avec sa conséquence réelle : refuser passe la place à la
/// personne suivante et sort de la liste d’attente ; la quitter perd le rang, et la rejoindre repart en dernier.
enum SchoolCourseRelease: Equatable {
    case decline(offerID: UUID)
    case leaveWaitlist(rank: Int?)

    var action: SchoolCourseLearnerAction {
        switch self {
        case .decline(let offerID): .decline(offerID: offerID)
        case .leaveWaitlist: .leaveWaitlist
        }
    }
    var title: String {
        switch self {
        case .decline: "Refuser la place ?"
        case .leaveWaitlist: "Quitter la liste d’attente ?"
        }
    }
    var confirmTitle: String {
        switch self {
        case .decline: "Refuser la place"
        case .leaveWaitlist: "Quitter la liste"
        }
    }
    var keepTitle: String {
        switch self {
        case .decline: "Garder la proposition"
        case .leaveWaitlist: "Rester en attente"
        }
    }
    func message(courseTitle: String?) -> String {
        let course = courseTitle.map { " pour « \($0) »" } ?? ""
        switch self {
        case .decline:
            return "La place proposée\(course) passera à la personne suivante et tu quitteras la liste d’attente."
        case .leaveWaitlist(let rank):
            return "Tu perdras ton rang\(rank.map { " (\($0))" } ?? "")\(course). Si tu la rejoins plus tard, tu repasseras en dernier."
        }
    }
    /// La proposition ou l’attente vue à l’ouverture est toujours celle de la fiche ; l’échéance reste arbitrée par l’école.
    func isCurrent(in me: SchoolCourseLearnerState?) -> Bool {
        guard let me else { return false }
        switch self {
        case .decline(let offerID): return me.state == .offered && me.offer?.id == offerID
        case .leaveWaitlist: return me.state == .waiting
        }
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

/// Demande de l’élève partie vers l’école (#126) : son identifiant est l’`operationId`, conservé pour toute reprise.
struct SchoolCourseLearnerPending: Equatable {
    enum State: Equatable {
        case sending
        /// Panne ou réponse perdue : peut-être enregistrée ; jamais présentée comme acquise ni comme refusée.
        case uncertain(String)
    }
    let action: SchoolCourseLearnerAction
    let operation: UUID
    var state: State = .sending

    /// Ce qui est en cours, sans annoncer le résultat.
    var title: String {
        switch action {
        case .enroll: "Inscription en cours"
        case .joinWaitlist: "Ajout à la liste d’attente en cours"
        case .leaveWaitlist: "Retrait de la liste d’attente en cours"
        case .accept: "Acceptation de la place en cours"
        case .decline: "Refus de la place en cours"
        case .cancel: "Annulation de l’inscription en cours"
        }
    }
    var unconfirmedTitle: String {
        switch action {
        case .enroll: "Inscription non confirmée"
        case .joinWaitlist: "Liste d’attente non confirmée"
        case .leaveWaitlist: "Retrait non confirmé"
        case .accept: "Acceptation non confirmée"
        case .decline: "Refus non confirmé"
        case .cancel: "Annulation non confirmée"
        }
    }
}

/// Fiche d’un cours vue par l’élève : son état personnel et ses commandes. Une demande part sans retenir l’écran :
/// la fiche et sa confirmation se ferment aussitôt, l’état affiché reste celui de l’école et la demande en cours
/// est dite à part, jusqu’à la réponse. Fermer la fiche ne la perd pas (#126).
@MainActor @Observable final class SchoolCourseLearnerWorkspace: Identifiable {
    let id = UUID()
    let schoolID: UUID
    let seriesID: UUID
    let timeZone: String
    let client: SchoolCourseClient
    private(set) var reply: SchoolCourseLearnerReply?
    private(set) var isLoading = false
    /// Demande en cours ou à reprendre ; une seule à la fois pour un cours : la série est l'agrégat (place, file
    /// d'attente, version d'inscription), le second geste attend la réponse du premier. Une fiche par cours : deux
    /// séries distinctes envoient ensemble, sauf obligation de formation partagée (#106, tâche 5).
    private(set) var pending: SchoolCourseLearnerPending?
    var errorMessage: String?
    /// Dernière commande confirmée par l’école, annoncée une fois.
    private(set) var confirmation: String?
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    /// Coffre des demandes de cet appareil (#126) ; sans lui (tests, aperçus), la demande reste en mémoire.
    private let persistence: SchoolCourseIntentPersistence?
    @ObservationIgnored private var kept: PendingSchoolCommand?
    /// Refus du coffre qui n'est pas une panne : un autre geste de l'élève attend sa réponse (#106, tâche 5).
    @ObservationIgnored private var refusal: String?
    @ObservationIgnored private var didRestore = false

    init(schoolID: UUID, seriesID: UUID, timeZone: String, client: SchoolCourseClient, persistence: SchoolCourseIntentPersistence? = nil) {
        self.schoolID = schoolID; self.seriesID = seriesID; self.timeZone = timeZone; self.client = client
        self.persistence = persistence
    }

    /// Une demande part : les autres gestes attendent sa réponse.
    var isBusy: Bool { pending != nil }
    var isSending: Bool { pending?.state == .sending }
    var series: SchoolCourseSeries? { reply?.series }
    var me: SchoolCourseLearnerState? { reply?.me }
    var serverNow: Date { client.serverClock.now ?? .distantFuture }
    var offerAvailable: Bool {
        me?.state == .offered && (me?.offer?.expiry ?? .distantPast) > serverNow
    }

    func waitForOfferExpiry() async {
        guard let expiry = me?.offer?.expiry else { return }
        do { try await client.serverClock.wait(until: expiry) } catch { return }
        await load()
    }
    /// Le type de cours est suivi (prochaines sessions, #40) ; `nil` tant que l’école ne l’a pas dit.
    private(set) var following: Bool?
    private(set) var isUpdatingFollow = false
    private(set) var isLoadingFollow = false
    /// La lecture du suivi a échoué : la ligne le dit et propose « Réessayer », sans rien abonner ni désabonner (#161).
    private(set) var followReadFailed = false

    /// Lecture séparée : une panne ne touche que cette ligne, le reste de la fiche reste utilisable.
    func loadFollow() async {
        guard let typeID = series?.typeId, !isUpdatingFollow, !isLoadingFollow else { return }
        isLoadingFollow = true; defer { isLoadingFollow = false }
        do {
            let types = try await client.follows(schoolID: schoolID)
            guard !Task.isCancelled, series?.typeId == typeID else { return }
            following = types.contains(typeID); followReadFailed = false
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { followReadFailed = true }
        }
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
        restoreKeptRequest()
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            reply = try await client.learnerView(schoolID: schoolID, seriesID: seriesID)
            if errorMessage != nil && reply != nil { errorMessage = nil }
            if following == nil { await loadFollow() }
        } catch is CancellationError {
        } catch {
            if let failure = error as? SchoolPlanningFailure, [.unauthorized, .forbidden, .notFound].contains(failure) {
                reply = nil; following = nil
            }
            errorMessage = Self.message(error)
        }
    }

    /// Retour immédiat : la demande part, l’écran reste libre. Double appui : une seule demande.
    func submit(_ action: SchoolCourseLearnerAction) {
        guard pending == nil else { return }
        switch action {
        case .accept(let offerID), .decline(let offerID):
            guard offerAvailable, me?.offer?.id == offerID else {
                errorMessage = "Le délai pour répondre est passé."
                return
            }
        default: break
        }
        errorMessage = nil; confirmation = nil; refusal = nil
        let request = SchoolCourseLearnerPending(action: action, operation: UUID())
        // Écrite avant tout : une demande que l'appareil ne peut pas conserver n'est pas envoyée.
        guard keep(request) else { errorMessage = refusal ?? SchoolCourseIntentPersistence.unkeptMessage; refusal = nil; return }
        pending = request
        Task { await send() }
    }

    /// Même demande, même opération : l’école ne l’enregistre pas deux fois.
    func retryPending() {
        guard let current = pending, case .uncertain = current.state else { return }
        pending?.state = .sending
        Task { await send() }
    }

    /// Elle a peut-être été enregistrée : la fiche est relue pour montrer l’état réel.
    func abandonPending() async {
        guard let current = pending, case .uncertain = current.state else { return }
        pending = nil; release()
        await load()
        onChange?()
    }

    private func send() async {
        guard let current = pending, current.state == .sending else { return }
        do {
            let result = try await client.act(current.action, schoolID: schoolID, seriesID: seriesID, operationID: current.operation)
            guard pending?.operation == current.operation else { return }
            pending = nil; release(); reply = result
            confirmation = Self.done(current.action)
            onChange?()
        } catch {
            guard pending?.operation == current.operation else { return }
            let message = Self.message(error)
            let failure = error as? SchoolPlanningFailure
            if let failure, [.unauthorized, .forbidden, .notFound].contains(failure) {
                pending = nil; release(); reply = nil; following = nil; errorMessage = message
            } else if let failure, failure.definitiveRejection {
                // Refus motivé : la demande s’arrête et la fiche se relit sans effacer la raison.
                pending = nil; release()
                await load()
                errorMessage = message
            } else {
                pending?.state = .uncertain(error is CancellationError ? SchoolPlanningFailure.unavailable.localizedDescription : message)
            }
        }
    }

    // MARK: Conservation sur l'appareil (#126)

    /// Écrit la demande dans le coffre avant son envoi. Faux : rien n'a pu être conservé, la demande ne part pas.
    private func keep(_ request: SchoolCourseLearnerPending) -> Bool {
        guard let persistence else { return true }
        do {
            let command = try SchoolCourseLearnerRecord(action: request.action, operation: request.operation)
                .command(scope: persistence.scope, seriesID: seriesID, createdAt: Date())
            try persistence.store.replace(kept, with: command)
            kept = command
            return true
        } catch {
            // Un autre geste de l'élève attend sa réponse : celui-ci ne part pas et le dit avec le message du coffre
            // (même série, ou obligation de formation du même type de cours, #106 tâche 5). Une panne reste « non conservé ».
            if let failure = error as? SchoolConfigurationFailure, failure == .pendingCommand { refusal = failure.errorDescription }
            return false
        }
    }

    /// L'école a répondu (ou refusé) : la demande quitte le coffre. Un reste éventuel reviendrait en « non confirmé », et rejouer
    /// la même opération rend la réponse déjà enregistrée sans second effet.
    private func release() {
        guard let persistence, let command = kept else { return }
        kept = nil
        try? persistence.store.remove(command)
    }

    /// Demande laissée par une session précédente : à reprendre ou à abandonner par l'élève, jamais renvoyée d'elle-même.
    func restoreKeptRequest() {
        guard let persistence, !didRestore, pending == nil else { return }
        didRestore = true
        guard let commands = try? persistence.store.commands(scope: persistence.scope, seriesID: seriesID),
              let command = commands.first(where: { $0.kind == .courseLearnerIntent }),
              let record = try? JSONDecoder().decode(SchoolCourseLearnerRecord.self, from: command.body),
              record.operationId == command.id, let action = record.action else { return }
        kept = command
        pending = SchoolCourseLearnerPending(action: action, operation: command.id,
            state: .uncertain(SchoolCourseIntentPersistence.restoredMessage))
    }

    /// L’échéance d’annulation de la série est passée (accepter une place ne permettra plus d’annuler soi-même).
    func cancellationClosed(now: Date? = nil) -> Bool {
        guard let deadline = series.flatMap({ SchoolLesson.date($0.selfCancellationDeadline) }) else { return false }
        return deadline < (now ?? serverNow)
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
    /// Séries autorisées encore suivies, même si leur première séance est passée.
    private(set) var followedSeries: [UUID: SchoolCourseSeries] = [:]
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?

    /// Coffre des demandes de cet appareil (#126) : une demande laissée par une session précédente se dit dans la liste.
    private let persistence: SchoolCourseIntentPersistence?
    @ObservationIgnored private var didRestore = false

    init(schoolID: UUID, timeZone: String, client: SchoolCourseClient, persistence: SchoolCourseIntentPersistence? = nil) {
        self.schoolID = schoolID; self.timeZone = timeZone; self.client = client
        self.persistence = persistence
    }

    /// Propositions encore ouvertes, la plus proche échéance d’abord.
    var offers: [SchoolCourseOffer] {
        (mine?.offers ?? []).filter { ($0.expiry ?? .distantPast) > (client.serverClock.now ?? .distantFuture) }
            .sorted { ($0.expiry ?? .distantFuture) < ($1.expiry ?? .distantFuture) }
    }

    func waitForNextOfferExpiry() async {
        guard let expiry = offers.first?.expiry else { return }
        try? await client.serverClock.wait(until: expiry)
    }

    /// Fiches ouvertes dans ce contexte : rouvrir un cours retrouve sa demande en cours (#126).
    @ObservationIgnored private var details: [UUID: SchoolCourseLearnerWorkspace] = [:]
    func detail(for seriesID: UUID) -> SchoolCourseLearnerWorkspace {
        if let existing = details[seriesID] { return existing }
        let course = SchoolCourseLearnerWorkspace(schoolID: schoolID, seriesID: seriesID, timeZone: timeZone, client: client,
            persistence: persistence)
        details[seriesID] = course
        return course
    }
    /// Demande en cours sur ce cours, pour la dire dans les listes.
    func pending(for seriesID: UUID) -> SchoolCourseLearnerPending? { details[seriesID]?.pending }
    func offer(for seriesID: UUID) -> SchoolCourseOffer? { offers.first { $0.seriesId == seriesID } }
    func isEnrolled(_ seriesID: UUID) -> Bool {
        mine?.items.contains { $0.seriesId == seriesID && $0.status == .active } == true
    }
    func title(for seriesID: UUID) -> String? { courses.first { $0.id == seriesID }?.title ?? startedTitles[seriesID] }
    var activeEnrollments: [SchoolCourseEnrollment] { (mine?.items ?? []).filter { $0.status == .active } }
    var availableCourses: [SchoolCourseSeries] {
        let engaged = Set(activeEnrollments.map(\.seriesId) + offers.map(\.seriesId))
        return courses.filter { !engaged.contains($0.id) }
    }
    func series(for seriesID: UUID) -> SchoolCourseSeries? {
        courses.first { $0.id == seriesID } ?? followedSeries[seriesID]
    }
    func nextOccurrence(for seriesID: UUID, now: Date = Date()) -> SchoolCourseOccurrence? {
        series(for: seriesID)?.occurrences.filter { ($0.end ?? .distantPast) > now }
            .min { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }
    func nextEnrollment(now: Date = Date()) -> SchoolCourseEnrollment? {
        activeEnrollments.filter { nextOccurrence(for: $0.seriesId, now: now) != nil }
            .min { (nextOccurrence(for: $0.seriesId, now: now)?.start ?? .distantFuture)
                < (nextOccurrence(for: $1.seriesId, now: now)?.start ?? .distantFuture) }
    }
    /// Inscriptions comptant des séances obligatoires.
    var tracked: [SchoolCourseProgress.Enrollment] { (progress?.enrollments ?? []).filter { $0.requirements.required > 0 } }

    /// La progression ne bloque pas la liste : une panne la laisse simplement absente.
    func loadProgress() async {
        if let fresh = try? await client.progress(schoolID: schoolID), !Task.isCancelled { progress = fresh }
        guard !Task.isCancelled else { return }
        let seriesIDs = Set(activeEnrollments.map(\.seriesId) + (progress?.enrollments.map(\.seriesId) ?? [])
            + (progress?.completions.compactMap(\.seriesId) ?? []))
        followedSeries = followedSeries.filter { seriesIDs.contains($0.key) }
        startedTitles = startedTitles.filter { seriesIDs.contains($0.key) }
        for seriesID in seriesIDs where !courses.contains(where: { $0.id == seriesID }) {
            guard !Task.isCancelled else { return }
            if let series = try? await client.series(schoolID: schoolID, id: seriesID), !Task.isCancelled {
                startedTitles[series.id] = series.title; followedSeries[series.id] = series
            }
        }
    }

    /// Propositions seulement : le bandeau se relit souvent, la liste à l’ouverture.
    func refreshOffers() async {
        guard let fresh = try? await client.mine(schoolID: schoolID), !Task.isCancelled else { return }
        mine = fresh
    }
    /// Demandes laissées par une session précédente : leur cours les dit dans la liste dès l'ouverture.
    private func restoreKeptRequests() {
        guard let persistence, !didRestore else { return }
        didRestore = true
        guard let commands = try? persistence.store.commands(scope: persistence.scope) else { return }
        for seriesID in Set(commands.filter { $0.kind == .courseLearnerIntent }.compactMap(\.routeResourceID)) {
            detail(for: seriesID).restoreKeptRequest()
        }
    }

    func load(now: Date = Date()) async {
        restoreKeptRequests()
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

/// Une page de l’annuaire des élèves de l’école, lue au nom du compte : le serveur en filtre le contenu selon ses droits.
typealias SchoolCourseLearnerPageReader = @MainActor (_ cursor: String?) async throws -> SchoolPage<SchoolLearner>

/// Inscrits et file d’un cours publié, pour le personnel habilité (droits relus par le serveur).
@MainActor @Observable final class SchoolCourseRosterWorkspace {
    /// Lecture de l’annuaire qui alimente le sélecteur d’élèves.
    enum CandidateRead: Equatable {
        /// Pas encore commencée.
        case idle
        case loading
        /// Toutes les pages sont lues : la liste est celle que le serveur montre à ce compte.
        case complete
        /// Une page a échoué : les noms déjà lus restent proposés, la lecture se reprend.
        case failed(String)
    }

    /// Au-delà, la lecture s’arrête plutôt que de boucler sur un curseur.
    static let maximumDirectory = 10_000

    let schoolID: UUID
    let seriesID: UUID
    let client: SchoolCourseClient
    /// Élèves actifs proposés à l’inscription : ceux que l’app avait déjà, puis tout l’annuaire une fois lu.
    private(set) var learners: [SchoolLearner]
    private(set) var candidateRead: CandidateRead
    private(set) var roster: SchoolCourseRoster?
    private(set) var isLoading = false
    private(set) var isBusy = false
    var errorMessage: String?
    private(set) var confirmation: String?
    /// Un refus explicite d’accès (401/403/404) a purgé les inscrits (#426) ; seule une lecture autorisée le lève.
    private(set) var accessRevoked = false
    /// Change à chaque refus : une lecture ou une réponse partie avant lui ne remet rien à l’écran.
    @ObservationIgnored private var accessEpoch = 0
    @ObservationIgnored private var memory = SchoolCourseOperationMemory()
    @ObservationIgnored var onChange: (@MainActor () async -> Void)?
    /// Les élèves déjà lus par l’app : première page de l’annuaire, parfois filtrée par une recherche. Jamais présumés complets.
    private let seed: [SchoolLearner]
    private let learnerPages: SchoolCourseLearnerPageReader?

    /// Sans `learnerPages` (aperçus, tests), `learners` est tenu pour complet.
    init(schoolID: UUID, seriesID: UUID, client: SchoolCourseClient, learners: [SchoolLearner],
         learnerPages: SchoolCourseLearnerPageReader? = nil) {
        self.schoolID = schoolID; self.seriesID = seriesID; self.client = client
        self.seed = learners; self.learnerPages = learnerPages
        self.learners = Self.visible(learners)
        candidateRead = learnerPages == nil ? .complete : .idle
    }

    /// Dossiers actifs, sans doublon, dans l’ordre alphabétique.
    static func visible(_ learners: [SchoolLearner]) -> [SchoolLearner] {
        var seen = Set<UUID>()
        return learners.filter { $0.archivedAt == nil && seen.insert($0.id).inserted }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    /// Élèves sans inscription active ni place en file.
    var candidates: [SchoolLearner] {
        // Accès retiré : aucun nom n'est proposé, quelle que soit la lecture qui les aurait rapportés.
        guard !accessRevoked else { return [] }
        let taken = Set((roster?.active.map(\.enrollment.learnerId) ?? []) + (roster?.waitlist.map(\.learnerId) ?? []))
        return learners.filter { !taken.contains($0.id) }
    }

    /// Lit tout l’annuaire, page après page : aucun élève admissible n’est écarté par la taille d’une page. Les noms déjà lus
    /// restent proposés pendant la suite ; une panne les garde et se reprend. Une lecture complète n’est pas refaite.
    func loadCandidates() async {
        guard !accessRevoked, let learnerPages, candidateRead != .loading, candidateRead != .complete else { return }
        // Une page ou une erreur arrivée après un refus (époque changée) n'écrit ni noms ni état de lecture.
        let epoch = accessEpoch
        candidateRead = .loading
        var read: [SchoolLearner] = [], cursor: String?, seen = Set<String>()
        do {
            repeat {
                let page = try await learnerPages(cursor)
                guard epoch == accessEpoch else { return }
                try Task.checkCancellation()
                read.append(contentsOf: page.items); cursor = page.nextCursor
                guard read.count <= Self.maximumDirectory else { throw SchoolPlanningFailure.invalidResponse }
                if let cursor, !seen.insert(cursor).inserted { throw SchoolPlanningFailure.invalidResponse }
                if cursor != nil { learners = Self.visible(seed + read) }
            } while cursor != nil
            guard epoch == accessEpoch else { return }
            learners = Self.visible(read)
            candidateRead = .complete
        } catch {
            guard epoch == accessEpoch else { return }
            learners = Self.visible(seed + read)
            // Sélecteur refermé pendant la lecture : ni panne ni lecture complète.
            if error is CancellationError || Task.isCancelled { candidateRead = .idle; return }
            candidateRead = .failed(SchoolCourseLearnerWorkspace.message(error))
        }
    }

    /// Reprend la lecture après une panne.
    func retryCandidates() async {
        guard !accessRevoked, case .failed = candidateRead else { return }
        candidateRead = .idle
        await loadCandidates()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        let epoch = accessEpoch
        do {
            let fresh = try await client.roster(schoolID: schoolID, seriesID: seriesID)
            guard epoch == accessEpoch else { return }
            if accessRevoked { restoreCandidatesIfNeeded() }
            roster = fresh; accessRevoked = false; errorMessage = nil
        }
        catch is CancellationError {}
        catch {
            guard epoch == accessEpoch else { return }
            if SchoolCourseAccess.isDenied(error) { revokeAccess(error) }
            else { errorMessage = SchoolCourseLearnerWorkspace.message(error) }
        }
    }

    /// Refus explicite : inscrits, file, confirmation et élèves proposés disparaissent, et plus aucune action n’est offerte.
    /// Une panne transitoire n’arrive jamais ici : elle garde le contenu autorisé et le dit.
    private func revokeAccess(_ error: any Error) {
        accessEpoch += 1
        accessRevoked = true
        roster = nil; confirmation = nil; learners = []; candidateRead = learnerPages == nil ? .complete : .idle
        errorMessage = SchoolCourseLearnerWorkspace.message(error)
    }

    /// Les élèves proposés reviennent avec l’accès, relus ou repris de ce que l’app avait.
    private func restoreCandidatesIfNeeded() {
        guard learners.isEmpty, !seed.isEmpty else { return }
        learners = Self.visible(seed)
    }

    @discardableResult func enroll(_ learner: SchoolLearner) async -> Bool {
        guard !isBusy, !accessRevoked else { return false }
        isBusy = true; errorMessage = nil; confirmation = nil; defer { isBusy = false }
        let epoch = accessEpoch
        let operation = memory.operation(for: "staff-enroll|\(learner.id)")
        do {
            _ = try await client.staffEnroll(schoolID: schoolID, seriesID: seriesID, learnerID: learner.id, operationID: operation)
            memory.settle()
            guard epoch == accessEpoch else { return false }
            confirmation = "\(learner.displayName) est inscrit"
        } catch is CancellationError { return false }
        catch {
            guard epoch == accessEpoch else { return false }
            memory.fail(error)
            if SchoolCourseAccess.isDenied(error) { revokeAccess(error) }
            else { errorMessage = SchoolCourseLearnerWorkspace.message(error) }
            return false
        }
        await reloadAfterChange()
        return true
    }

    @discardableResult func cancel(_ row: SchoolCourseRosterEnrollment, reason: String) async -> Bool {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !accessRevoked, !reason.isEmpty, reason.count <= 1000 else { return false }
        isBusy = true; errorMessage = nil; confirmation = nil; defer { isBusy = false }
        let epoch = accessEpoch
        let operation = memory.operation(for: "staff-cancel|\(row.enrollment.id)|\(row.enrollment.version)|\(reason)")
        do {
            _ = try await client.staffCancel(schoolID: schoolID, enrollmentID: row.enrollment.id, version: row.enrollment.version,
                reason: reason, operationID: operation)
            memory.settle()
            guard epoch == accessEpoch else { return false }
            confirmation = "Inscription annulée"
        } catch is CancellationError { return false }
        catch {
            guard epoch == accessEpoch else { return false }
            memory.fail(error)
            if SchoolCourseAccess.isDenied(error) { revokeAccess(error) }
            else { errorMessage = SchoolCourseLearnerWorkspace.message(error) }
            return false
        }
        await reloadAfterChange()
        return true
    }

    private func reloadAfterChange() async {
        isLoading = false
        await load()
        await onChange?()
    }
}
