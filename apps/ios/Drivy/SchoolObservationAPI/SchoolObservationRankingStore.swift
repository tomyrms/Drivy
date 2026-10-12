import Foundation
import Observation

/// Copie locale du classement d’une adhésion, pour ouvrir « Signaler » hors ligne avec le bon ordre et pour
/// que le mode ne clignote pas au lancement.
@MainActor protocol SchoolObservationRankingCache: AnyObject {
    func read(scope: SchoolCommandScope) -> SchoolObservationRanking?
    func write(_ ranking: SchoolObservationRanking, scope: SchoolCommandScope)
    func remove(scope: SchoolCommandScope)
}

/// Un fichier JSON par école et par adhésion dans Application Support. Un mode et des clés de thèmes : aucune
/// donnée de personne, donc aucun chiffrement. Perdre ce fichier ramène seulement à l’ordre de l’école jusqu’à
/// la prochaine lecture.
@MainActor final class SchoolObservationRankingFileCache: SchoolObservationRankingCache {
    private struct Stored: Codable {
        let format: Int
        let apiBaseURL: String
        let ranking: SchoolObservationRanking
    }
    private let directory: URL
    private let maximumBytes = 16_000

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SchoolObservationRanking", isDirectory: true)
    }

    func read(scope: SchoolCommandScope) -> SchoolObservationRanking? {
        guard let data = try? Data(contentsOf: file(for: scope)), data.count <= maximumBytes,
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.format == 1, stored.apiBaseURL == scope.apiBaseURL, stored.ranking.isValid(for: scope) else { return nil }
        return stored.ranking
    }

    func write(_ ranking: SchoolObservationRanking, scope: SchoolCommandScope) {
        guard ranking.isValid(for: scope) else { return }
        let stored = Stored(format: 1, apiBaseURL: scope.apiBaseURL, ranking: ranking)
        guard let data = try? JSONEncoder().encode(stored), data.count <= maximumBytes else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(for: scope), options: [.atomic])
    }

    func remove(scope: SchoolCommandScope) {
        try? FileManager.default.removeItem(at: file(for: scope))
    }

    private func file(for scope: SchoolCommandScope) -> URL {
        directory.appendingPathComponent("\(scope.schoolID.uuidString.lowercased())-\(scope.membershipID.uuidString.lowercased()).json")
    }
}

/// Classement des signalements d’un moniteur dans une école : l’état confirmé par l’école (ou, à défaut, sa copie
/// locale), et le mode proposé pendant l’envoi. Le classement automatique n’écrit jamais dans l’ordre de l’école :
/// le désactiver rend cet ordre tel quel.
@MainActor @Observable final class SchoolObservationRankingStore {
    static let changedNotice = "Le classement avait changé depuis un autre appareil. Voici son réglage actuel."
    static let unsavedMessage = "Classement non enregistré. Vérifie ta connexion puis réessaie."

    let scope: SchoolCommandScope
    /// Dernier état confirmé ; `nil` tant que ni l’école ni la copie locale n’en ont donné un.
    private(set) var ranking: SchoolObservationRanking?
    /// L’école a répondu pendant cette session et connaît le classement. Faux avant sa réponse, et après un 404
    /// (école plus ancienne) : le réglage est alors simplement absent de l’écran.
    private(set) var isAvailable = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var failureMessage: String?
    /// Une phrase due à un événement inhabituel : classement réglé entre-temps depuis un autre appareil.
    private(set) var notice: String?
    /// Ce que l’interrupteur montre pendant l’envoi ; jamais présenté comme enregistré.
    private(set) var proposal: SchoolObservationRankingMode?
    /// Augmente à chaque changement de mode confirmé par l’école à la demande de cet appareil.
    private(set) var confirmedChanges = 0

    private struct Attempt {
        let operation: UUID
        let version: Int
        let mode: SchoolObservationRankingMode
    }

    @ObservationIgnored private let client: SchoolObservationRankingClient
    @ObservationIgnored private let cache: any SchoolObservationRankingCache
    @ObservationIgnored private var refreshTask: Task<Bool, Never>?
    /// Augmente à chaque réponse d’écriture : une lecture partie avant ne remplace pas ce qu’elle a confirmé.
    @ObservationIgnored private var writeGeneration = 0
    /// Écriture dont le résultat est inconnu : la même opération se rejoue, sans effet double.
    @ObservationIgnored private var uncertain: Attempt?

    init(scope: SchoolCommandScope, client: SchoolObservationRankingClient, cache: (any SchoolObservationRankingCache)? = nil) {
        self.scope = scope; self.client = client
        let storage = cache ?? SchoolObservationRankingFileCache()
        self.cache = storage
        ranking = storage.read(scope: scope)
    }

    /// Mode confirmé ; l’ordre de l’école tant que rien ne dit autre chose.
    var mode: SchoolObservationRankingMode { ranking?.mode ?? .manual }
    /// Mode que l’écran montre : la proposition pendant l’envoi, sinon le mode confirmé.
    var displayedMode: SchoolObservationRankingMode { proposal ?? mode }
    /// L’ordre confirmé si le mode confirmé est `smart`, sinon `nil` : l’ordre de l’école s’applique.
    var effectiveOrder: [String]? {
        guard let ranking, ranking.mode == .smart, !ranking.order.isEmpty else { return nil }
        return ranking.order
    }
    var canRetry: Bool { uncertain != nil && !isSaving }

    /// Lecture du classement. Plusieurs appelants simultanés partagent la même requête.
    @discardableResult func refresh() async -> Bool {
        if let refreshTask { return await refreshTask.value }
        let task = Task { await self.read() }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func read() async -> Bool {
        let generation = writeGeneration
        isLoading = true
        defer { isLoading = false }
        do {
            let value = try await client.ranking(scope: scope)
            isAvailable = true
            // Une écriture en cours ou terminée entre-temps fait foi : sa réponse porte une version plus récente.
            guard !isSaving, generation == writeGeneration else { return true }
            confirm(value)
            return true
        } catch {
            guard !error.isRequestCancellation else { return false }
            let failure = (error as? SchoolObservationThemeFailure) ?? .unavailable
            // Aucun message pour une lecture : sans réponse de l’école, le réglage ne se montre pas.
            if failure == .notFound { forget() }
            else if failure == .forbidden { isAvailable = false }
            return false
        }
    }

    private func confirm(_ value: SchoolObservationRanking) {
        guard value != ranking else { return }
        ranking = value
        cache.write(value, scope: scope)
    }

    /// École qui ne connaît pas (ou plus) le classement : l’ordre de l’école s’applique, et la copie locale ne
    /// garde pas un ordre automatique que plus aucun écran ne permettrait de désactiver.
    private func forget() {
        isAvailable = false
        proposal = nil; uncertain = nil; failureMessage = nil; notice = nil
        guard ranking != nil else { return }
        ranking = nil
        cache.remove(scope: scope)
    }

    // MARK: Réglage

    func clearNotice() { notice = nil }

    /// Le changement part aussitôt. Un changement fait pendant un envoi le suit, avec la version qu’il confirme.
    func setSmart(_ enabled: Bool) {
        let target: SchoolObservationRankingMode = enabled ? .smart : .manual
        guard isAvailable, ranking != nil else { return }
        notice = nil
        if let uncertain, uncertain.mode != target { self.uncertain = nil }
        guard target != displayedMode else { return }
        proposal = target
        failureMessage = nil
        guard !isSaving else { return }
        isSaving = true
        Task { await self.send() }
    }

    /// « Réessayer » après un résultat inconnu : la même opération, avec la même version.
    func retry() {
        guard canRetry, let uncertain else { return }
        setSmart(uncertain.mode == .smart)
    }

    private func send() async {
        while let target = proposal, let confirmed = ranking, target != confirmed.mode {
            let attempt: Attempt
            if let uncertain, uncertain.mode == target, uncertain.version == confirmed.version {
                attempt = uncertain
            } else {
                attempt = Attempt(operation: UUID(), version: confirmed.version, mode: target)
            }
            uncertain = nil
            do {
                let value = try await client.save(scope: scope, version: attempt.version,
                    body: SchoolObservationRankingBody(operationId: attempt.operation, mode: attempt.mode))
                writeGeneration += 1
                isAvailable = true
                confirm(value)
                if value.mode == target { confirmedChanges += 1 }
                // Rien d’autre n’a été demandé entre-temps : l’envoi est terminé, quelle que soit la forme confirmée.
                if proposal == target { proposal = nil }
            } catch {
                writeGeneration += 1
                isSaving = false
                await settle(error, attempt: attempt)
                return
            }
        }
        proposal = nil
        isSaving = false
    }

    /// Retour à l’état confirmé. Rien n’est annoncé comme enregistré.
    private func settle(_ error: any Error, attempt: Attempt) async {
        proposal = nil
        guard !error.isRequestCancellation else { return }
        let failure = (error as? SchoolObservationThemeFailure) ?? .unavailable
        switch failure {
        case .conflict, .preconditionRequired:
            // Réglé ailleurs depuis la lecture : relire, montrer l’état actuel et le dire.
            // Lecture propre à ce refus : une lecture déjà partie pourrait dater d’avant le changement.
            if await read() { notice = Self.changedNotice }
            else { failureMessage = "Le classement n’a pas pu être relu. Réessaie dans un instant." }
        case .unauthorized:
            failureMessage = "Reconnecte-toi pour régler le classement intelligent."
        case .forbidden:
            isAvailable = false
            failureMessage = "Tes accès ne permettent plus de régler le classement intelligent."
        case .notFound:
            forget()
        case .unavailable, .invalidResponse:
            // Résultat inconnu : « Réessayer » renvoie la même opération.
            uncertain = attempt
            failureMessage = Self.unsavedMessage
        case .rejected:
            failureMessage = "L’école a refusé ce réglage. Recharge l’écran puis réessaie."
        }
    }
}

extension SchoolAgendaClient {
    /// Classement des signalements de ce compte dans l’école. `nil` pour un élève seul : il ne signale pas.
    func observationRankingStore(person: SchoolPerson?, membership: SchoolMembership?) -> SchoolObservationRankingStore? {
        guard let person, let membership,
              membership.roles.contains("ADMIN") || membership.roles.contains("INSTRUCTOR") else { return nil }
        return SchoolObservationRankingStores.store(for: scope(person: person, membership: membership), client: observationRankingClient)
    }
}

/// Un store par école, par adhésion et par accès, partagé par « Signaler » et l’écran de réglage.
@MainActor enum SchoolObservationRankingStores {
    private static var stores: [String: SchoolObservationRankingStore] = [:]
    /// Remplacée par les rendus de contrôle, qui n’écrivent rien sur l’appareil.
    static var makeCache: @MainActor () -> any SchoolObservationRankingCache = { SchoolObservationRankingFileCache() }

    static func store(for scope: SchoolCommandScope, client: @autoclosure () -> SchoolObservationRankingClient) -> SchoolObservationRankingStore {
        let key = "\(scope.apiBaseURL)|\(scope.schoolID.uuidString)|\(scope.personID.uuidString)|\(scope.membershipID.uuidString)|\(scope.accessEpoch)"
        if let existing = stores[key] { return existing }
        let created = SchoolObservationRankingStore(scope: scope, client: client(), cache: makeCache())
        stores[key] = created
        return created
    }
}

// MARK: - Ordre figé d’une leçon

/// L’ordre automatique pris pour une leçon : il ne bouge plus jusqu’à sa fin, même si l’app passe en
/// arrière-plan, est tuée, ou si le moniteur reprend une leçon interrompue. Des identifiants de leçon et des
/// clés de thèmes : aucune donnée de personne.
@MainActor protocol SchoolLessonSignalOrderStore: AnyObject {
    func order(for lessonID: UUID) -> [String]?
    func freeze(_ order: [String], lessonID: UUID)
}

/// Sans fichier : rendus de contrôle, tests, et repli d’un enregistreur créé sans stockage.
@MainActor final class SchoolLessonSignalOrderMemoryStore: SchoolLessonSignalOrderStore {
    private var orders: [UUID: [String]] = [:]
    func order(for lessonID: UUID) -> [String]? { orders[lessonID] }
    func freeze(_ order: [String], lessonID: UUID) { orders[lessonID] = order }
}

/// Un seul fichier JSON dans Application Support, chaque entrée portant son école et son adhésion. Relu à
/// chaque appel : deux enregistreurs de la même leçon (reprise) voient le même ordre. Ne garde que quelques
/// leçons récentes.
@MainActor final class SchoolLessonSignalOrderFileStore: SchoolLessonSignalOrderStore {
    static let maximumAge: TimeInterval = 3 * 24 * 60 * 60
    static let maximumEntries = 20

    private struct Entry: Codable {
        let apiBaseURL: String
        let schoolId: UUID
        let membershipId: UUID
        let lessonId: UUID
        let order: [String]
        let frozenAt: Date
    }
    private struct Stored: Codable {
        let format: Int
        var entries: [Entry]
    }

    private let scope: SchoolCommandScope
    private let file: URL
    private let now: @MainActor () -> Date
    private let maximumBytes = 128_000

    init(scope: SchoolCommandScope, directory: URL? = nil, now: @escaping @MainActor () -> Date = { Date() }) {
        self.scope = scope; self.now = now
        file = (directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("SchoolLessonSignalOrders.json")
    }

    func order(for lessonID: UUID) -> [String]? {
        let instant = now()
        return entries().first { owns($0) && $0.lessonId == lessonID && isRecent($0, at: instant) }?.order
    }

    func freeze(_ order: [String], lessonID: UUID) {
        guard (1...64).contains(order.count), order.allSatisfy(SchoolObservationRanking.isWellFormed(key:)) else { return }
        let instant = now()
        var kept = entries().filter { isRecent($0, at: instant) && !(owns($0) && $0.lessonId == lessonID) }
        kept.append(Entry(apiBaseURL: scope.apiBaseURL, schoolId: scope.schoolID, membershipId: scope.membershipID,
                          lessonId: lessonID, order: order, frozenAt: instant))
        // Les plus récentes d’abord, puis seulement les dernières leçons.
        kept.sort { $0.frozenAt > $1.frozenAt }
        let stored = Stored(format: 1, entries: Array(kept.prefix(Self.maximumEntries)))
        guard let data = try? JSONEncoder().encode(stored), data.count <= maximumBytes else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: [.atomic])
    }

    private func owns(_ entry: Entry) -> Bool {
        entry.apiBaseURL == scope.apiBaseURL && entry.schoolId == scope.schoolID && entry.membershipId == scope.membershipID
    }

    private func isRecent(_ entry: Entry, at instant: Date) -> Bool {
        instant.timeIntervalSince(entry.frozenAt) <= Self.maximumAge
    }

    private func entries() -> [Entry] {
        guard let data = try? Data(contentsOf: file), data.count <= maximumBytes,
              let stored = try? JSONDecoder().decode(Stored.self, from: data), stored.format == 1 else { return [] }
        return stored.entries
    }
}

/// Fabrique du stockage des ordres figés, remplacée par les rendus de contrôle, qui n’écrivent rien sur l’appareil.
@MainActor enum SchoolLessonSignalOrderStores {
    static var make: @MainActor (SchoolCommandScope) -> any SchoolLessonSignalOrderStore = { SchoolLessonSignalOrderFileStore(scope: $0) }
}
