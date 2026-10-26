import Foundation
import Observation

enum SchoolNotificationCategory: String, Codable, CaseIterable, Sendable {
    case courseOffers, courseReminders, courseChanges, courseStaffAlerts

    func value(in preferences: SchoolNotificationPreferences) -> Bool {
        switch self {
        case .courseOffers: preferences.courseOffers
        case .courseReminders: preferences.courseReminders
        case .courseChanges: preferences.courseChanges
        case .courseStaffAlerts: preferences.courseStaffAlerts
        }
    }
    func apply(_ value: Bool, to preferences: inout SchoolNotificationPreferences) {
        switch self {
        case .courseOffers: preferences.courseOffers = value
        case .courseReminders: preferences.courseReminders = value
        case .courseChanges: preferences.courseChanges = value
        case .courseStaffAlerts: preferences.courseStaffAlerts = value
        }
    }
}

struct SchoolNotificationIntent: Codable, Sendable, Equatable {
    let id: UUID
    let value: Bool
}

struct SchoolNotificationAttempt: Codable, Sendable, Equatable {
    let base: SchoolNotificationPreferences
    let body: SchoolNotificationPreferencesBody
    let intentIDs: [SchoolNotificationCategory: UUID]
}

struct SchoolNotificationIntentJournal: Codable, Sendable, Equatable {
    var intents: [SchoolNotificationCategory: SchoolNotificationIntent] = [:]
    var attempt: SchoolNotificationAttempt?
}

@MainActor protocol SchoolNotificationPreferencesAPI {
    func preferences(contextIsCurrent: @escaping @MainActor () -> Bool) async throws -> SchoolNotificationPreferences
    func save(_ body: SchoolNotificationPreferencesBody, version: Int,
              contextIsCurrent: @escaping @MainActor () -> Bool) async throws -> SchoolNotificationPreferences
}
extension SchoolNotificationClient: SchoolNotificationPreferencesAPI {}

@MainActor protocol SchoolNotificationIntentStore {
    func read(for scope: AccountIntentScope) throws -> SchoolNotificationIntentJournal?
    func save(_ journal: SchoolNotificationIntentJournal, for scope: AccountIntentScope) throws
}
extension EncryptedAccountIntentStore: SchoolNotificationIntentStore where Value == SchoolNotificationIntentJournal {}

/// Quatre préférences partagent une version serveur : une seule requête à la fois, mais la saisie reste libre.
/// Le modèle vit au-delà de sa vue ; aucune fermeture d'écran n'annule une requête déjà partie.
@MainActor @Observable final class SchoolNotificationSettingsModel {
    let scope: AccountIntentScope
    private(set) var confirmed: SchoolNotificationPreferences?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var state: ClientMutationState = .idle
    private(set) var errorMessage: String?
    private(set) var refreshedAt: Date?
    private var journal = SchoolNotificationIntentJournal()
    @ObservationIgnored private let api: any SchoolNotificationPreferencesAPI
    @ObservationIgnored private let store: any SchoolNotificationIntentStore
    @ObservationIgnored private let contextIsCurrent: @MainActor () -> Bool
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var warning: Task<Void, Never>?
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var restored = false
    @ObservationIgnored private var durable = true
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var readRevision = 0

    init(scope: AccountIntentScope, api: any SchoolNotificationPreferencesAPI,
         store: any SchoolNotificationIntentStore = EncryptedAccountIntentStore<SchoolNotificationIntentJournal>(purpose: "notification-preferences"),
         contextIsCurrent: @escaping @MainActor () -> Bool) {
        self.scope = scope; self.api = api; self.store = store; self.contextIsCurrent = contextIsCurrent
    }

    var isCurrent: Bool { !invalidated && contextIsCurrent() }
    var preferences: SchoolNotificationPreferences? {
        guard isCurrent, var value = confirmed else { return nil }
        for (category, intent) in journal.intents { category.apply(intent.value, to: &value) }
        return value
    }
    var hasPendingChanges: Bool { !journal.intents.isEmpty || journal.attempt != nil }
    func isPending(_ category: SchoolNotificationCategory) -> Bool { journal.intents[category] != nil }

    /// Une lecture simultanée est dédupliquée ; une ancienne lecture ne remplace jamais un PUT confirmé.
    /// Réouvrir la page conserve sa projection en mémoire, puis revalide seulement cet endpoint.
    func load() async {
        guard isCurrent, !isLoading, !isSaving else { return }
        if !restored {
            do {
                journal = try store.read(for: scope) ?? .init()
                guard journal.intents.count <= SchoolNotificationCategory.allCases.count,
                      journal.attempt.map({ $0.base.version > 0 && $0.intentIDs.count <= SchoolNotificationCategory.allCases.count }) ?? true else {
                    throw SchoolConfigurationFailure.storage
                }
                restored = true; durable = true
            } catch { storageFailed(); return }
        }
        let expected = generation
        readRevision += 1; let revision = readRevision
        isLoading = true
        defer { if generation == expected { isLoading = false } }
        do {
            let fresh = try await api.preferences(contextIsCurrent: { [weak self] in self?.isCurrent == true })
            guard isCurrent, generation == expected, readRevision == revision else { return }
            guard fresh.version >= (confirmed?.version ?? journal.attempt?.base.version ?? 1) else {
                throw SchoolPlanningFailure.invalidResponse
            }
            confirmed = fresh; refreshedAt = Date()
            reconcile(fresh)
            guard persist() else { return }
            errorMessage = nil; state = hasPendingChanges ? .queued : .idle
            schedule()
        } catch {
            guard isCurrent, generation == expected else { return }
            handleReadFailure(error)
        }
    }

    /// Le dernier choix apparaît sans attendre le réseau. La barrière chiffrée précède tout envoi.
    func set(_ category: SchoolNotificationCategory, _ value: Bool) {
        guard isCurrent, let preferences, category.value(in: preferences) != value else { return }
        journal.intents[category] = .init(id: UUID(), value: value)
        // Une intention en vol reste intacte, même si le prochain choix revient à la valeur confirmée.
        if journal.attempt == nil, let confirmed, category.value(in: confirmed) == value {
            journal.intents.removeValue(forKey: category)
        }
        guard persist() else { return }
        errorMessage = nil
        state = isSaving ? .sending : (hasPendingChanges ? .queued : .idle)
        schedule()
    }

    func retry() async {
        guard isCurrent, !isSaving else { return }
        // Une lecture illisible ne doit jamais être remplacée par un journal vide.
        if !restored { await load(); return }
        guard persist() else { return }
        await load()
    }

    func invalidate() {
        invalidated = true; generation = UUID(); readRevision += 1
        work?.cancel(); work = nil; warning?.cancel(); warning = nil
        confirmed = nil; journal = .init(); isLoading = false; isSaving = false
        state = .idle; errorMessage = nil; refreshedAt = nil
    }

    private func schedule() {
        guard isCurrent, durable, confirmed != nil, hasPendingChanges, work == nil else { return }
        work = Task { [weak self] in await self?.drain() }
    }

    private func drain() async {
        guard isCurrent, durable else { work = nil; return }
        let expected = generation
        isSaving = true; state = .sending
        warning?.cancel()
        warning = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.isCurrent, self.isSaving, self.generation == expected else { return }
            self.state = .unconfirmed
            self.errorMessage = "La synchronisation prend plus de temps. Tes choix restent conservés."
        }
        defer {
            if generation == expected {
                isSaving = false; work = nil; warning?.cancel(); warning = nil
                if !hasPendingChanges, durable { state = .idle }
            }
        }
        // La borne évite une boucle infinie si un autre appareil écrit continuellement.
        for _ in 0..<8 {
            guard isCurrent, generation == expected, durable, let base = confirmed, hasPendingChanges else { return }
            if journal.attempt == nil {
                guard let projected = preferences else { return }
                journal.attempt = .init(base: base, body: projected.body, intentIDs: journal.intents.mapValues(\.id))
                guard persist() else { return }
            }
            guard let attempt = journal.attempt else { return }
            readRevision += 1
            do {
                let reply = try await api.save(attempt.body, version: attempt.base.version,
                                              contextIsCurrent: { [weak self] in self?.isCurrent == true })
                guard isCurrent, generation == expected else { return }
                confirmed = reply; refreshedAt = Date()
                settle(attempt)
                guard persist() else { return }
                errorMessage = nil; state = .sending
            } catch {
                guard isCurrent, generation == expected else { return }
                if error as? SchoolPlanningFailure == .conflict {
                    do {
                        let fresh = try await api.preferences(contextIsCurrent: { [weak self] in self?.isCurrent == true })
                        guard isCurrent, generation == expected else { return }
                        guard fresh.version >= attempt.base.version else { throw SchoolPlanningFailure.invalidResponse }
                        confirmed = fresh; refreshedAt = Date(); reconcile(fresh)
                        guard persist() else { return }
                        state = .conflict
                        errorMessage = "Tes préférences ont changé ailleurs. Les autres choix ont été conservés."
                        continue
                    } catch {
                        guard isCurrent, generation == expected else { return }
                        handleReadFailure(error); return
                    }
                }
                if let failure = error as? SchoolPlanningFailure, case .rejected = failure {
                    settle(attempt)
                    guard persist() else { return }
                    state = .rejected
                    errorMessage = Self.message(error)
                } else if error as? SchoolPlanningFailure == .unauthorized || error as? SchoolPlanningFailure == .forbidden {
                    confirmed = nil; state = .unconfirmed; errorMessage = Self.message(error)
                } else {
                    state = .unconfirmed
                    errorMessage = "Modification non confirmée. Vérifie la synchronisation pour reprendre."
                }
                return
            }
        }
        state = .conflict
        errorMessage = "Tes préférences changent sur un autre appareil. Vérifie-les avant de reprendre."
    }

    /// If-Match rend la répétition de la même version sûre. Un GET n'affirme jamais que notre PUT a réussi :
    /// il confirme seulement les valeurs effectivement présentes, puis préserve les choix locaux plus récents.
    private func reconcile(_ fresh: SchoolNotificationPreferences) {
        if let attempt = journal.attempt {
            // Version identique : une reprise réutilise exactement le corps et la précondition de l'intention.
            if fresh.version == attempt.base.version { return }
            for (category, id) in attempt.intentIDs {
                if let intent = journal.intents[category], intent.id == id,
                   category.value(in: fresh) == intent.value {
                    journal.intents.removeValue(forKey: category)
                }
            }
            journal.attempt = nil
        }
        for (category, intent) in journal.intents where category.value(in: fresh) == intent.value {
            journal.intents.removeValue(forKey: category)
        }
    }

    private func settle(_ attempt: SchoolNotificationAttempt) {
        for (category, id) in attempt.intentIDs where journal.intents[category]?.id == id {
            journal.intents.removeValue(forKey: category)
        }
        journal.attempt = nil
    }
    @discardableResult private func persist() -> Bool {
        do { try store.save(journal, for: scope); durable = true; return true }
        catch { storageFailed(); return false }
    }
    private func storageFailed() {
        durable = false; state = .storageUnavailable
        errorMessage = "Ces choix ne sont pas conservés sur cet appareil. Garde cet écran ouvert et réessaie."
    }
    private func handleReadFailure(_ error: any Error) {
        if error as? SchoolPlanningFailure == .unauthorized || error as? SchoolPlanningFailure == .forbidden {
            confirmed = nil
        }
        if hasPendingChanges { state = .unconfirmed }
        errorMessage = Self.message(error)
    }
    static func message(_ error: any Error) -> String {
        if error as? SchoolPlanningFailure == .conflict { return "Tes préférences ont changé ailleurs. Vérifie-les." }
        return (error as? LocalizedError)?.errorDescription ?? "L’école n’a pas pu répondre."
    }
}

/// Un seul compte en mémoire, quatre booléens confirmés, au plus quatre intentions et un PUT.
/// Le passage d'une école à l'autre conserve ces préférences personnelles ; une déconnexion les purge.
@MainActor enum SchoolNotificationSettingsCache {
    private static var cached: SchoolNotificationSettingsModel?
    static func model(scope: AccountIntentScope, client: SchoolNotificationClient,
                      contextIsCurrent: @escaping @MainActor () -> Bool) -> SchoolNotificationSettingsModel {
        if let cached, cached.scope == scope, cached.isCurrent { return cached }
        reset()
        let model = SchoolNotificationSettingsModel(scope: scope, api: client, contextIsCurrent: contextIsCurrent)
        cached = model
        return model
    }
    static func reset() { cached?.invalidate(); cached = nil }
}
