import Foundation
import Observation

/// Copie locale de la configuration d’une école, pour ouvrir « Signaler » hors ligne avec l’ordre de l’école.
@MainActor protocol SchoolObservationThemeCache: AnyObject {
    func read(scope: SchoolCommandScope) -> SchoolObservationThemeConfiguration?
    func write(_ configuration: SchoolObservationThemeConfiguration, scope: SchoolCommandScope)
}

/// Un fichier JSON par école dans Application Support. Ordre et affichage des thèmes du catalogue : aucune donnée de
/// personne, donc aucun chiffrement, et rien de commun avec la file chiffrée des demandes. Perdre ce fichier
/// ramène seulement au repli embarqué jusqu’à la prochaine lecture.
@MainActor final class SchoolObservationThemeFileCache: SchoolObservationThemeCache {
    private struct Stored: Codable {
        let format: Int
        let apiBaseURL: String
        let schoolId: UUID
        let version: Int
        let themes: [SchoolObservationTheme]
        /// Absents d’une copie écrite avant leur ajout.
        var foreign: [SchoolObservationForeignTheme]? = nil
        var unlisted: [String]? = nil
    }
    private let directory: URL
    private let maximumBytes = 64_000

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SchoolObservationThemes", isDirectory: true)
    }

    func read(scope: SchoolCommandScope) -> SchoolObservationThemeConfiguration? {
        guard let data = try? Data(contentsOf: file(for: scope)), data.count <= maximumBytes,
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.format == 1, stored.apiBaseURL == scope.apiBaseURL, stored.schoolId == scope.schoolID,
              stored.version > 0, !stored.themes.isEmpty else { return nil }
        // Une copie écrite par une version qui connaissait moins de thèmes : les nouveaux ne sont pas réputés
        // connus de l’école avant sa prochaine réponse.
        let unlisted = Set(stored.unlisted ?? []).union(SchoolObservationThemeCatalog.unlisted(in: stored.themes))
        return SchoolObservationThemeConfiguration(themes: SchoolObservationThemeCatalog.arranged(stored.themes),
            version: stored.version, source: .server, foreign: stored.foreign ?? [],
            unlisted: unlisted.intersection(SchoolObservationThemeCatalog.keys))
    }

    func write(_ configuration: SchoolObservationThemeConfiguration, scope: SchoolCommandScope) {
        // Le repli embarqué ne s’écrit jamais : il passerait ensuite pour une réponse de l’école.
        guard configuration.isFromServer, configuration.version > 0 else { return }
        let stored = Stored(format: 1, apiBaseURL: scope.apiBaseURL, schoolId: scope.schoolID,
                            version: configuration.version, themes: configuration.themes,
                            foreign: configuration.foreign, unlisted: configuration.unlisted.sorted())
        guard let data = try? JSONEncoder().encode(stored), data.count <= maximumBytes else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(for: scope), options: [.atomic])
    }

    private func file(for scope: SchoolCommandScope) -> URL {
        directory.appendingPathComponent("\(scope.schoolID.uuidString.lowercased()).json")
    }
}

/// Configuration des signalements d’une école pour un compte : l’état confirmé par l’école (ou, à défaut, sa
/// copie locale, puis le repli embarqué), et la proposition en cours d’enregistrement de l’écran de gestion.
/// `canManage` ne vient que d’une réponse de l’école pendant cette session.
@MainActor @Observable final class SchoolObservationThemeStore {
    enum SaveState: Equatable { case idle, saving, saved, failed(String) }

    static let lastVisibleNotice = "Au moins un signalement reste affiché."
    static let changedNotice = "Les signalements avaient changé. Voici leur version actuelle."

    let scope: SchoolCommandScope
    /// Dernier état confirmé : c’est lui que « Signaler » photographie à son ouverture.
    private(set) var configuration: SchoolObservationThemeConfiguration
    private(set) var canManage = false
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var saveState: SaveState = .idle
    /// Une phrase due à un événement inhabituel : configuration changée ailleurs, dernier thème affiché.
    private(set) var notice: String?
    /// Ce que l’écran de gestion montre pendant l’envoi ; jamais présenté comme enregistré.
    private(set) var proposal: [SchoolObservationTheme]?

    @ObservationIgnored private let client: SchoolObservationThemeClient
    @ObservationIgnored private let cache: any SchoolObservationThemeCache
    @ObservationIgnored private var refreshTask: Task<Bool, Never>?
    @ObservationIgnored private var isSaving = false
    /// Augmente à chaque réponse d’écriture : une lecture partie avant ne remplace pas ce qu’elle a confirmé.
    @ObservationIgnored private var writeGeneration = 0
    /// Écriture dont le résultat est inconnu : la même opération se rejoue, sans effet double.
    @ObservationIgnored private var uncertain: (operation: UUID, version: Int, themes: [SchoolObservationTheme])?

    init(scope: SchoolCommandScope, client: SchoolObservationThemeClient, cache: (any SchoolObservationThemeCache)? = nil) {
        self.scope = scope; self.client = client
        let storage = cache ?? SchoolObservationThemeFileCache()
        self.cache = storage
        configuration = storage.read(scope: scope) ?? .embedded
    }

    var displayed: [SchoolObservationTheme] { proposal ?? configuration.themes }
    var visibleCount: Int { displayed.filter(\.visible).count }
    var canEdit: Bool { canManage && configuration.isFromServer }
    var canRetry: Bool { uncertain != nil && !isSaving }
    var isOriginalOrder: Bool { displayed.map(\.key) == SchoolObservationThemeCatalog.originalOrder(displayed).map(\.key) }
    var isOriginal: Bool { displayed == SchoolObservationThemeCatalog.original(displayed) }

    /// Lecture de la configuration. Plusieurs appelants simultanés partagent la même requête.
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
            let value = try await client.settings(scope: scope)
            canManage = value.canManage
            loadError = nil
            // Une écriture en cours ou terminée entre-temps fait foi : sa réponse porte une version plus récente.
            guard !isSaving, generation == writeGeneration else { return true }
            confirm(value)
            return true
        } catch {
            guard !error.isRequestCancellation else { return false }
            let failure = (error as? SchoolObservationThemeFailure) ?? .unavailable
            if failure == .forbidden || failure == .unauthorized { canManage = false }
            loadError = failure.errorDescription
            return false
        }
    }

    private func confirm(_ value: SchoolObservationThemeSettings) {
        canManage = value.canManage
        let next = SchoolObservationThemeConfiguration.server(value.themes, version: value.version)
        guard next != configuration else { return }
        configuration = next
        cache.write(next, scope: scope)
    }

    // MARK: Gestion

    func setVisible(_ visible: Bool, key: String) {
        var themes = displayed
        // Un thème que l’école ne liste pas encore ne se règle pas : elle refuserait sa clé.
        guard !configuration.unlisted.contains(key),
              let index = themes.firstIndex(where: { $0.key == key }), themes[index].visible != visible else { return }
        themes[index].visible = visible
        propose(themes)
    }

    /// « Monter » (−1) et « Descendre » (+1) : le même déplacement que le glisser, pour VoiceOver et le clavier.
    @discardableResult func move(key: String, by delta: Int) -> Int? {
        var themes = displayed
        guard let index = themes.firstIndex(where: { $0.key == key }), themes.indices.contains(index + delta), delta != 0 else { return nil }
        let theme = themes.remove(at: index)
        themes.insert(theme, at: index + delta)
        propose(themes)
        return displayed.firstIndex(where: { $0.key == key })
    }

    func resetOrder() { propose(SchoolObservationThemeCatalog.originalOrder(displayed)) }
    func resetAll() { propose(SchoolObservationThemeCatalog.original(displayed)) }
    func clearNotice() { notice = nil }

    func retry() {
        guard canRetry, let uncertain else { return }
        propose(uncertain.themes)
    }

    /// Chaque changement part aussitôt. Un changement fait pendant un envoi le suit, avec la version qu’il confirme.
    func propose(_ themes: [SchoolObservationTheme]) {
        guard canEdit, themes.count == configuration.themes.count,
              Set(themes.map(\.key)) == Set(configuration.themes.map(\.key)) else { return }
        guard themes.contains(where: \.visible) else { notice = Self.lastVisibleNotice; return }
        notice = nil
        if let uncertain, uncertain.themes != themes { self.uncertain = nil }
        guard themes != displayed else { return }
        proposal = themes
        saveState = .saving
        guard !isSaving else { return }
        isSaving = true
        Task { await self.send() }
    }

    private func send() async {
        while let target = proposal, target != configuration.themes {
            let attempt: (operation: UUID, version: Int, themes: [SchoolObservationTheme])
            if let uncertain, uncertain.themes == target, uncertain.version == configuration.version {
                attempt = uncertain
            } else {
                attempt = (UUID(), configuration.version, target)
            }
            uncertain = nil
            do {
                let value = try await client.save(scope: scope, version: attempt.version,
                    body: SchoolObservationThemesBody(operationId: attempt.operation, themes: target,
                                                      foreign: configuration.foreign, unlisted: configuration.unlisted))
                writeGeneration += 1
                confirm(value)
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
        saveState = .saved
    }

    /// Retour à l’état confirmé. Rien n’est annoncé comme enregistré.
    private func settle(_ error: any Error, attempt: (operation: UUID, version: Int, themes: [SchoolObservationTheme])) async {
        proposal = nil
        let failure = (error as? SchoolObservationThemeFailure) ?? .unavailable
        switch failure {
        case .conflict, .preconditionRequired:
            // Changée ailleurs depuis la lecture : la relire, la montrer et le dire.
            saveState = .idle
            // Lecture propre à ce refus : une lecture déjà partie pourrait dater d’avant le changement.
            if await read() { notice = Self.changedNotice }
            else { saveState = .failed(failure.errorDescription ?? Self.changedNotice) }
        case .forbidden, .unauthorized:
            canManage = false
            saveState = .failed(failure.errorDescription ?? "")
        case .unavailable, .invalidResponse:
            // Résultat inconnu : « Réessayer » renvoie la même opération.
            uncertain = attempt
            saveState = .failed("Modification non enregistrée. Vérifie ta connexion puis réessaie.")
        case .notFound, .rejected:
            saveState = .failed(failure.errorDescription ?? "")
        }
    }
}

extension SchoolAgendaClient {
    /// Signalements de l’école pour ce compte. `nil` pour un élève seul : l’école ne lui lit pas cette configuration.
    func observationThemeStore(person: SchoolPerson?, membership: SchoolMembership?) -> SchoolObservationThemeStore? {
        guard let person, let membership,
              membership.roles.contains("ADMIN") || membership.roles.contains("INSTRUCTOR") else { return nil }
        return SchoolObservationThemeStores.store(for: scope(person: person, membership: membership), client: observationThemeClient)
    }
}

/// Un store par école et par accès, partagé par « Signaler », le Profil et l’écran de gestion.
@MainActor enum SchoolObservationThemeStores {
    private static var stores: [String: SchoolObservationThemeStore] = [:]
    /// Remplacée par les rendus de contrôle, qui n’écrivent rien sur l’appareil.
    static var makeCache: @MainActor () -> any SchoolObservationThemeCache = { SchoolObservationThemeFileCache() }

    static func store(for scope: SchoolCommandScope, client: @autoclosure () -> SchoolObservationThemeClient) -> SchoolObservationThemeStore {
        let key = "\(scope.apiBaseURL)|\(scope.schoolID.uuidString)|\(scope.personID.uuidString)|\(scope.membershipID.uuidString)|\(scope.accessEpoch)"
        if let existing = stores[key] { return existing }
        let created = SchoolObservationThemeStore(scope: scope, client: client(), cache: makeCache())
        stores[key] = created
        return created
    }
}
