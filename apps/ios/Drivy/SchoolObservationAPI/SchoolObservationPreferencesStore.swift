import CryptoKit
import Foundation
import Observation

// MARK: - Copies locales

/// Ce que le compte a confirmé, commun à toutes ses écoles et à tous ses appareils : version, mode, ordre manuel,
/// borne d'apprentissage. Aucune notion d'école. Suit sa propre version, distincte de celle de la politique de l'école
/// (copie des thèmes de l'école, `SchoolObservationThemeFileCache`).
struct SchoolObservationAccountSnapshot: Codable, Sendable, Equatable {
    var version: Int
    var mode: SchoolObservationRankingMode
    /// Ordre manuel personnel, ou celui de l'école tant que le compte n'en a pas.
    var order: [String]
    var orderCustomized: Bool
    var rankedOn: String?
    var learningGeneration: Int
    var learningSince: String?

    init(_ value: SchoolObservationPreferences) {
        version = value.version; mode = value.mode; order = value.themes.map(\.key)
        orderCustomized = value.orderCustomized; rankedOn = value.rankedOn
        learningGeneration = value.learning.generation; learningSince = value.learning.since
    }
}

/// Ce que l'école ouverte fait de ces préférences, pour ce compte : sa politique, la visibilité effective de chaque
/// thème et la palette que le service en a tirée. Propre à une école ; jamais prise pour une préférence du compte.
struct SchoolObservationPolicySnapshot: Codable, Sendable, Equatable {
    var personalizationAllowed: Bool
    var visibilityCustomized: Bool
    var themes: [SchoolObservationPreferencesTheme]
    var palette: [String]

    init(_ value: SchoolObservationPreferences) {
        personalizationAllowed = value.personalizationAllowed; visibilityCustomized = value.visibilityCustomized
        themes = value.themes; palette = value.palette
    }
}

@MainActor protocol SchoolObservationAccountCache: AnyObject {
    func read(scope: SchoolCommandScope) -> SchoolObservationAccountSnapshot?
    func write(_ snapshot: SchoolObservationAccountSnapshot, scope: SchoolCommandScope)
    func remove(scope: SchoolCommandScope)
}

@MainActor protocol SchoolObservationPolicyCache: AnyObject {
    func read(scope: SchoolCommandScope) -> SchoolObservationPolicySnapshot?
    func write(_ snapshot: SchoolObservationPolicySnapshot, scope: SchoolCommandScope)
    func remove(scope: SchoolCommandScope)
}

/// Nom de fichier : l'origine de l'API (hachée) et l'identité, jamais l'une sans l'autre.
enum SchoolObservationCacheName {
    static func origin(_ apiBaseURL: String) -> String {
        SHA256.hash(data: Data(apiBaseURL.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}

/// Un fichier JSON par origine d'API et par compte dans Application Support. Un mode, des clés de thèmes, deux
/// numéros : aucune donnée de personne, donc aucun chiffrement. Perdre un fichier ramène seulement à l'ordre de
/// l'école jusqu'à la prochaine lecture.
@MainActor final class SchoolObservationAccountFileCache: SchoolObservationAccountCache {
    private struct Stored: Codable {
        let format: Int
        let apiBaseURL: String
        let personId: UUID
        let snapshot: SchoolObservationAccountSnapshot
    }
    static let folder = "SchoolObservationAccount"
    private let directory: URL
    private let maximumBytes = 16_000

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.folder, isDirectory: true)
    }

    func read(scope: SchoolCommandScope) -> SchoolObservationAccountSnapshot? {
        guard let data = try? Data(contentsOf: file(for: scope)), data.count <= maximumBytes,
              let stored = try? JSONDecoder().decode(Stored.self, from: data), stored.format == 1,
              stored.apiBaseURL == scope.apiBaseURL, stored.personId == scope.personID,
              stored.snapshot.version > 0, !stored.snapshot.order.isEmpty else { return nil }
        return stored.snapshot
    }

    func write(_ snapshot: SchoolObservationAccountSnapshot, scope: SchoolCommandScope) {
        guard snapshot.version > 0, !snapshot.order.isEmpty else { return }
        let stored = Stored(format: 1, apiBaseURL: scope.apiBaseURL, personId: scope.personID, snapshot: snapshot)
        guard let data = try? JSONEncoder().encode(stored), data.count <= maximumBytes else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(for: scope), options: [.atomic])
    }

    func remove(scope: SchoolCommandScope) {
        try? FileManager.default.removeItem(at: file(for: scope))
    }

    private func file(for scope: SchoolCommandScope) -> URL {
        directory.appendingPathComponent("\(SchoolObservationCacheName.origin(scope.apiBaseURL))-\(scope.personID.uuidString.lowercased()).json")
    }
}

/// Un fichier JSON par origine d'API, par compte et par école.
@MainActor final class SchoolObservationPolicyFileCache: SchoolObservationPolicyCache {
    private struct Stored: Codable {
        let format: Int
        let apiBaseURL: String
        let personId: UUID
        let schoolId: UUID
        let snapshot: SchoolObservationPolicySnapshot
    }
    static let folder = "SchoolObservationPolicy"
    private let directory: URL
    private let maximumBytes = 64_000

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.folder, isDirectory: true)
    }

    func read(scope: SchoolCommandScope) -> SchoolObservationPolicySnapshot? {
        guard let data = try? Data(contentsOf: file(for: scope)), data.count <= maximumBytes,
              let stored = try? JSONDecoder().decode(Stored.self, from: data), stored.format == 1,
              stored.apiBaseURL == scope.apiBaseURL, stored.personId == scope.personID, stored.schoolId == scope.schoolID,
              !stored.snapshot.themes.isEmpty, !stored.snapshot.palette.isEmpty else { return nil }
        return stored.snapshot
    }

    func write(_ snapshot: SchoolObservationPolicySnapshot, scope: SchoolCommandScope) {
        guard !snapshot.themes.isEmpty, !snapshot.palette.isEmpty else { return }
        let stored = Stored(format: 1, apiBaseURL: scope.apiBaseURL, personId: scope.personID, schoolId: scope.schoolID, snapshot: snapshot)
        guard let data = try? JSONEncoder().encode(stored), data.count <= maximumBytes else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(for: scope), options: [.atomic])
    }

    func remove(scope: SchoolCommandScope) {
        try? FileManager.default.removeItem(at: file(for: scope))
    }

    private func file(for scope: SchoolCommandScope) -> URL {
        directory.appendingPathComponent("\(SchoolObservationCacheName.origin(scope.apiBaseURL))-\(scope.personID.uuidString.lowercased())-\(scope.schoolID.uuidString.lowercased()).json")
    }
}

// MARK: - Store

/// Les préférences de signalements d'un compte, vues depuis l'école ouverte : l'état confirmé par le service (ou, à
/// défaut, ses deux copies locales, l'une du compte, l'autre de la politique de l'école), et la proposition en cours
/// d'enregistrement. L'ordre et le mode sont toujours personnels ; la visibilité ne l'est que si l'école le permet.
/// Rien n'est annoncé comme enregistré avant la réponse du service.
@MainActor @Observable final class SchoolObservationPreferencesStore {
    enum Reset: Equatable, Sendable { case presentation, learning }

    static let changedNotice = "Tes réglages avaient changé. Voici ce qui est enregistré."
    static let policyNotice = "L’école impose désormais l’affichage des signalements. Voici ce qui est enregistré."
    static let lastVisibleNotice = "Au moins un signalement reste affiché."
    static let unsavedMessage = "Réglage non enregistré. Vérifie ta connexion puis réessaie."
    static let rereadMessage = "Les réglages n’ont pas pu être relus. Réessaie dans un instant."

    /// Ce que l'écran montre pendant l'envoi : jamais présenté comme enregistré.
    struct Proposal: Equatable, Sendable {
        var mode: SchoolObservationRankingMode?
        var order: [String]?
        /// Seulement les thèmes dont l'affichage change.
        var visibility: [String: Bool]?
        var isEmpty: Bool { mode == nil && order == nil && visibility == nil }
    }

    private struct Draft: Equatable {
        let mode: SchoolObservationRankingMode?
        let order: [String]?
        let visibility: [SchoolObservationPreferencesBody.Entry]?
    }
    private enum Action: Equatable {
        case save(Draft)
        case reset(Reset)
    }
    private struct Attempt {
        let operation: UUID
        let version: Int
        let action: Action
    }

    let scope: SchoolCommandScope
    /// Dernier état confirmé du compte ; `nil` tant que ni le service ni la copie locale n'en ont donné un.
    private(set) var account: SchoolObservationAccountSnapshot?
    /// Dernière politique confirmée de l'école ouverte pour ce compte.
    private(set) var policy: SchoolObservationPolicySnapshot?
    /// Configurations héritées à choisir, tant que le compte n'a rien enregistré. Jamais mise en cache.
    private(set) var adoption: SchoolObservationAdoption?
    /// Le service a répondu pendant cette session et connaît les préférences. Faux avant sa réponse, et après un 404 ou
    /// un 403 : le réglage est alors absent de l'écran.
    private(set) var isAvailable = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isResetting = false
    private(set) var failureMessage: String?
    /// Une phrase due à un événement inhabituel : réglage changé ailleurs, politique de l'école modifiée.
    private(set) var notice: String?
    private(set) var proposal = Proposal()
    /// Augmente à chaque commande confirmée par le service à la demande de cet appareil.
    private(set) var confirmedChanges = 0
    /// La dernière remise à zéro confirmée, pour l'annoncer.
    private(set) var lastConfirmedReset: Reset?

    @ObservationIgnored private let client: SchoolObservationPreferencesClient
    @ObservationIgnored private let accountCache: any SchoolObservationAccountCache
    @ObservationIgnored private let policyCache: any SchoolObservationPolicyCache
    @ObservationIgnored private var refreshTask: Task<Bool, Never>?
    /// Augmente à chaque réponse d'écriture : une lecture partie avant ne remplace pas ce qu'elle a confirmé.
    @ObservationIgnored private var writeGeneration = 0
    /// Commande dont le résultat est inconnu : la même opération se rejoue, sans effet double.
    @ObservationIgnored private var uncertain: Attempt?

    init(scope: SchoolCommandScope, client: SchoolObservationPreferencesClient,
         accountCache: (any SchoolObservationAccountCache)? = nil, policyCache: (any SchoolObservationPolicyCache)? = nil) {
        self.scope = scope; self.client = client
        let accounts = accountCache ?? SchoolObservationAccountFileCache()
        let policies = policyCache ?? SchoolObservationPolicyFileCache()
        self.accountCache = accounts; self.policyCache = policies
        account = accounts.read(scope: scope)
        policy = policies.read(scope: scope)
    }

    // MARK: Lecture de l'état

    /// Mode confirmé ; manuel tant que rien ne dit autre chose.
    var mode: SchoolObservationRankingMode { account?.mode ?? .manual }
    var displayedMode: SchoolObservationRankingMode { proposal.mode ?? mode }
    var personalizationAllowed: Bool { policy?.personalizationAllowed ?? false }
    /// La visibilité ne se modifie que si l'école le permet, d'après sa dernière politique confirmée. Sans réseau, un
    /// réglage reste possible mais n'est jamais annoncé comme enregistré : il se rejoue au retour du service.
    var canEditVisibility: Bool { personalizationAllowed && policy != nil }
    var canReorder: Bool { account != nil && policy != nil }
    var hasLearningReset: Bool { account != nil }
    var canRetry: Bool { uncertain != nil && !isSaving }
    var isBusy: Bool { isSaving || isResetting }

    /// Le catalogue dans l'ordre manuel personnel confirmé, avec la visibilité effective de l'école ouverte.
    var confirmedThemes: [SchoolObservationPreferencesTheme] {
        guard let policy else { return [] }
        let byKey = Dictionary(policy.themes.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var result = (account?.order ?? []).compactMap { byKey[$0] }
        let placed = Set(result.map(\.key))
        result.append(contentsOf: policy.themes.filter { !placed.contains($0.key) })
        return result
    }

    /// Ce que l'écran de réglage montre : l'état confirmé, avec la proposition en cours par-dessus.
    var displayedThemes: [SchoolObservationPreferencesTheme] {
        var themes = confirmedThemes
        if let order = proposal.order {
            let byKey = Dictionary(themes.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            var arranged = order.compactMap { byKey[$0] }
            let placed = Set(arranged.map(\.key))
            arranged.append(contentsOf: themes.filter { !placed.contains($0.key) })
            themes = arranged
        }
        if let overlay = proposal.visibility {
            themes = themes.map { theme in
                var value = theme
                if let visible = overlay[theme.key] { value.visible = visible }
                return value
            }
        }
        return themes
    }

    var visibleCount: Int { displayedThemes.filter(\.visible).count }

    /// Ce que « Signaler » affiche : l'ordre personnel filtré par la visibilité effective de l'école ouverte. En mode
    /// intelligent, l'ordre vient du service (la palette de sa dernière lecture) ; en mode manuel, il se recompose
    /// des deux copies, ce qui suit aussi un ordre réglé depuis une autre école. `nil` : rien n'a été confirmé.
    var palette: [String]? {
        guard let policy else { return nil }
        if account?.mode == .smart { return policy.palette.isEmpty ? nil : policy.palette }
        let visible = Set(policy.themes.filter(\.visible).map(\.key))
        let composed = SchoolObservationPalette.compose(order: confirmedThemes.map(\.key), visible: visible)
        return composed.isEmpty ? nil : composed
    }

    // MARK: Lecture

    /// Lecture des préférences. Plusieurs appelants simultanés partagent la même requête.
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
            let value = try await client.preferences(scope: scope)
            isAvailable = true
            // Une écriture en cours ou terminée entre-temps fait foi : sa réponse porte une version plus récente.
            guard !isSaving, !isResetting, generation == writeGeneration else { return true }
            confirm(value)
            return true
        } catch {
            guard !error.isRequestCancellation else { return false }
            let failure = (error as? SchoolObservationPreferencesFailure) ?? .unavailable
            // Aucun message pour une lecture : sans réponse du service, le réglage ne se montre pas.
            switch failure {
            case .notFound, .forbidden: forgetSchool()
            case .unauthorized: isAvailable = false
            default: break
            }
            return false
        }
    }

    private func confirm(_ value: SchoolObservationPreferences) {
        let nextAccount = SchoolObservationAccountSnapshot(value)
        let nextPolicy = SchoolObservationPolicySnapshot(value)
        if nextAccount != account {
            account = nextAccount
            accountCache.write(nextAccount, scope: scope)
        }
        if nextPolicy != policy {
            policy = nextPolicy
            policyCache.write(nextPolicy, scope: scope)
        }
        adoption = value.adoption
    }

    /// École qui ne connaît pas (ou plus) ces préférences, ou accès révoqué : la copie de sa politique ne sert plus,
    /// et la palette revient à la configuration de l'école. Les préférences du compte, elles, restent au compte.
    private func forgetSchool() {
        isAvailable = false
        proposal = Proposal(); uncertain = nil; failureMessage = nil; notice = nil; adoption = nil
        guard policy != nil else { return }
        policy = nil
        policyCache.remove(scope: scope)
    }

    func clearNotice() { notice = nil }

    // MARK: Réglage

    func setSmart(_ enabled: Bool) {
        propose(Proposal(mode: enabled ? .smart : .manual))
    }

    /// Glisser-déposer : le même déplacement que « Monter » et « Descendre ».
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var keys = displayedThemes.map(\.key)
        keys.move(fromOffsets: source, toOffset: destination)
        propose(Proposal(order: keys))
    }

    /// « Monter » (−1) et « Descendre » (+1), pour VoiceOver et le clavier. Rend la nouvelle position.
    @discardableResult func move(key: String, by delta: Int) -> Int? {
        var keys = displayedThemes.map(\.key)
        guard canReorder, !isResetting, let index = keys.firstIndex(of: key), keys.indices.contains(index + delta), delta != 0 else { return nil }
        let moved = keys.remove(at: index)
        keys.insert(moved, at: index + delta)
        propose(Proposal(order: keys))
        return displayedThemes.firstIndex { $0.key == key }
    }

    func setVisible(_ visible: Bool, key: String) {
        guard canEditVisibility, !isResetting,
              let theme = displayedThemes.first(where: { $0.key == key }), theme.visible != visible else { return }
        if !visible, visibleCount <= 1 { notice = Self.lastVisibleNotice; return }
        propose(Proposal(visibility: [key: visible]))
    }

    /// Reprise d'une ancienne configuration choisie par la personne : le mode, l'ordre, et l'affichage si l'école
    /// l'autorise. Une configuration qui ne couvre pas le catalogue ne reprend que le mode.
    func adopt(_ candidate: SchoolObservationAdoptionCandidate) {
        guard isAvailable, !isBusy else { return }
        let known = confirmedThemes.map(\.key)
        let covers = candidate.themes.count == known.count && Set(candidate.themes.map(\.key)) == Set(known)
        var next = Proposal(mode: candidate.mode)
        if covers {
            next.order = candidate.themes.map(\.key)
            if canEditVisibility, candidate.themes.contains(where: \.visible) {
                next.visibility = Dictionary(candidate.themes.map { ($0.key, $0.visible) }, uniquingKeysWith: { first, _ in first })
            }
        }
        propose(next)
    }

    /// Fusionne la demande dans la proposition en cours. Le changement part aussitôt ; un changement fait pendant un
    /// envoi le suit, avec la version qu'il confirme.
    private func propose(_ change: Proposal) {
        guard !isResetting, account != nil, policy != nil else { return }
        notice = nil; failureMessage = nil
        if let mode = change.mode { proposal.mode = mode }
        if let order = change.order { proposal.order = order }
        if let overlay = change.visibility {
            var merged = proposal.visibility ?? [:]
            for (key, visible) in overlay { merged[key] = visible }
            proposal.visibility = merged
        }
        normalize()
        guard !proposal.isEmpty, !isSaving else { return }
        isSaving = true
        Task { await self.send() }
    }

    /// Retire de la proposition ce que l'état confirmé dit déjà.
    private func normalize() {
        if proposal.mode == mode { proposal.mode = nil }
        let confirmed = confirmedThemes
        if proposal.order == confirmed.map(\.key) { proposal.order = nil }
        if var overlay = proposal.visibility {
            for theme in confirmed where overlay[theme.key] == theme.visible { overlay[theme.key] = nil }
            proposal.visibility = overlay.isEmpty ? nil : overlay
        }
    }

    private func draft() -> Draft? {
        normalize()
        guard !proposal.isEmpty else { return nil }
        var entries: [SchoolObservationPreferencesBody.Entry]?
        if let overlay = proposal.visibility, personalizationAllowed {
            let list = confirmedThemes.map { SchoolObservationPreferencesBody.Entry(key: $0.key, visible: overlay[$0.key] ?? $0.visible) }
            if list.contains(where: \.visible) { entries = list }
        }
        let value = Draft(mode: proposal.mode, order: proposal.order, visibility: entries)
        if value.mode == nil, value.order == nil, value.visibility == nil { proposal = Proposal(); return nil }
        return value
    }

    // MARK: Envoi

    private func send() async {
        while let draft = draft() {
            guard let version = account?.version else { break }
            let attempt: Attempt
            if let uncertain, uncertain.action == .save(draft), uncertain.version == version {
                attempt = uncertain
            } else {
                attempt = Attempt(operation: UUID(), version: version, action: .save(draft))
            }
            uncertain = nil
            let sent = proposal
            do {
                let value = try await client.save(scope: scope, version: version,
                    body: SchoolObservationPreferencesBody(operationId: attempt.operation, mode: draft.mode, order: draft.order,
                                                           visibility: draft.visibility))
                writeGeneration += 1
                confirm(value)
                confirmedChanges += 1
                lastConfirmedReset = nil
                // Rien d'autre n'a été demandé entre-temps : l'envoi est terminé, quelle que soit la forme confirmée.
                if proposal == sent { proposal = Proposal() }
            } catch {
                writeGeneration += 1
                isSaving = false
                await settle(error, attempt: attempt)
                return
            }
        }
        proposal = Proposal()
        isSaving = false
    }

    // MARK: Remises à zéro

    /// Ordre et visibilité de référence de l'école ouverte copiés sur le compte. Le droit est relu par le service.
    func resetPresentation() { startReset(.presentation) }

    /// Nouvelle borne d'apprentissage. Accessible même quand l'école impose sa visibilité.
    func resetLearning() { startReset(.learning) }

    private func startReset(_ kind: Reset) {
        guard account != nil, !isBusy else { return }
        notice = nil; failureMessage = nil
        isResetting = true
        Task { await self.sendReset(kind) }
    }

    private func sendReset(_ kind: Reset) async {
        guard let version = account?.version else { isResetting = false; return }
        let attempt: Attempt
        if let uncertain, uncertain.action == .reset(kind), uncertain.version == version {
            attempt = uncertain
        } else {
            attempt = Attempt(operation: UUID(), version: version, action: .reset(kind))
        }
        uncertain = nil
        do {
            let value: SchoolObservationPreferences
            switch kind {
            case .presentation: value = try await client.resetPresentation(scope: scope, version: version, operationId: attempt.operation)
            case .learning: value = try await client.resetLearning(scope: scope, version: version, operationId: attempt.operation)
            }
            writeGeneration += 1
            proposal = Proposal()
            confirm(value)
            confirmedChanges += 1
            lastConfirmedReset = kind
            isResetting = false
        } catch {
            writeGeneration += 1
            isResetting = false
            await settle(error, attempt: attempt)
        }
    }

    /// « Réessayer » après un résultat inconnu : la même opération, avec la même version.
    func retry() {
        guard canRetry, let uncertain else { return }
        failureMessage = nil
        switch uncertain.action {
        case .save:
            isSaving = true
            Task { await self.resend(uncertain) }
        case .reset(let kind):
            guard !isBusy else { return }
            isResetting = true
            Task { await self.sendReset(kind) }
        }
    }

    private func resend(_ attempt: Attempt) async {
        // La proposition annulée par l'échec est reconstruite depuis la commande dont le résultat est inconnu.
        guard case .save(let draft) = attempt.action else { isSaving = false; return }
        uncertain = attempt
        if let mode = draft.mode { proposal.mode = mode }
        if let order = draft.order { proposal.order = order }
        if let entries = draft.visibility {
            let confirmed = Dictionary(confirmedThemes.map { ($0.key, $0.visible) }, uniquingKeysWith: { first, _ in first })
            var overlay: [String: Bool] = [:]
            for entry in entries where confirmed[entry.key] != entry.visible { overlay[entry.key] = entry.visible }
            proposal.visibility = overlay.isEmpty ? nil : overlay
        }
        await send()
    }

    /// Retour à l'état confirmé. Rien n'est annoncé comme enregistré.
    private func settle(_ error: any Error, attempt: Attempt) async {
        proposal = Proposal()
        guard !error.isRequestCancellation else { return }
        let failure = (error as? SchoolObservationPreferencesFailure) ?? .unavailable
        switch failure {
        case .conflict, .preconditionRequired:
            // Réglé ailleurs depuis la lecture : relire, montrer l'état actuel et le dire.
            // Lecture propre à ce refus : une lecture déjà partie pourrait dater d'avant le changement.
            if await read() { notice = Self.changedNotice } else { failureMessage = Self.rereadMessage }
        case .personalizationDisabled:
            // L'école a repris la main depuis la lecture : rien n'a été écrit, la lecture dit ce qui l'est.
            if await read() { notice = Self.policyNotice } else { failureMessage = Self.rereadMessage }
        case .unauthorized:
            failureMessage = "Reconnecte-toi pour régler les signalements."
        case .forbidden:
            forgetSchool()
            failureMessage = "Tes accès ne permettent plus de régler les signalements."
        case .notFound:
            forgetSchool()
        case .unavailable, .invalidResponse:
            // Résultat inconnu : « Réessayer » renvoie la même opération.
            uncertain = attempt
            failureMessage = Self.unsavedMessage
        case .rejected:
            failureMessage = "Le service a refusé ce réglage. Recharge l’écran puis réessaie."
        }
    }
}

extension SchoolAgendaClient {
    /// Préférences de signalements de ce compte depuis l'école ouverte. `nil` pour un élève seul : il ne signale pas.
    func observationPreferencesStore(person: SchoolPerson?, membership: SchoolMembership?) -> SchoolObservationPreferencesStore? {
        guard let person, let membership,
              membership.roles.contains("ADMIN") || membership.roles.contains("INSTRUCTOR") else { return nil }
        return SchoolObservationPreferencesStores.store(for: scope(person: person, membership: membership),
                                                        client: observationPreferencesClient)
    }
}

/// Un store par école, par adhésion et par accès, partagé par « Signaler » et l'écran de réglage.
@MainActor enum SchoolObservationPreferencesStores {
    private static var stores: [String: SchoolObservationPreferencesStore] = [:]
    /// Remplacées par les rendus de contrôle, qui n'écrivent rien sur l'appareil.
    static var makeAccountCache: @MainActor () -> any SchoolObservationAccountCache = { SchoolObservationAccountFileCache() }
    static var makePolicyCache: @MainActor () -> any SchoolObservationPolicyCache = { SchoolObservationPolicyFileCache() }

    static func store(for scope: SchoolCommandScope, client: @autoclosure () -> SchoolObservationPreferencesClient) -> SchoolObservationPreferencesStore {
        let key = "\(scope.apiBaseURL)|\(scope.schoolID.uuidString)|\(scope.personID.uuidString)|\(scope.membershipID.uuidString)|\(scope.accessEpoch)"
        if let existing = stores[key] { return existing }
        removeLegacyFilesOnce()
        let created = SchoolObservationPreferencesStore(scope: scope, client: client(), accountCache: makeAccountCache(), policyCache: makePolicyCache())
        stores[key] = created
        return created
    }

    /// Déconnexion : plus aucun réglage, aucune politique ni aucun ordre figé d'un compte ne reste sur l'appareil ni en
    /// mémoire. Le compte suivant repart de ce que son école lui rend.
    static func purgeAll() {
        stores.removeAll()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for folder in [SchoolObservationAccountFileCache.folder, SchoolObservationPolicyFileCache.folder, legacyFolders[0], legacyFolders[1]] {
            try? FileManager.default.removeItem(at: base.appendingPathComponent(folder, isDirectory: true))
        }
        SchoolLessonSignalOrderFileStore.removeAll()
        SchoolObservationThemeStores.purgeAll()
    }

    /// Dossiers d'avant R08 : le classement par école et par adhésion, et les thèmes par école sans identité. Ils ne
    /// doivent plus passer pour des préférences ; ils sont effacés au premier usage.
    private static let legacyFolders = ["SchoolObservationRanking", "SchoolObservationThemes"]
    private static var legacyRemoved = false

    private static func removeLegacyFilesOnce() {
        guard !legacyRemoved else { return }
        legacyRemoved = true
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for folder in legacyFolders {
            try? FileManager.default.removeItem(at: base.appendingPathComponent(folder, isDirectory: true))
        }
    }
}
