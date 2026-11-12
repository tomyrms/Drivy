import Foundation

/// L’instantané de leçon : l’ordre de la palette « Signaler » pris pour une leçon en mode intelligent. Il ne bouge
/// plus jusqu’à sa fin, même si l’app passe en arrière-plan, est tuée, ou si le moniteur reprend une leçon
/// interrompue. Distinct des préférences du compte et de la politique de l’école : un changement distant n’y
/// touche pas. Des identifiants de leçon et des clés de thèmes : aucune donnée de personne.
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

/// Un seul fichier JSON dans Application Support, chaque entrée portant son API, son compte, son école et son
/// adhésion. Relu à chaque appel : deux enregistreurs de la même leçon (reprise) voient le même ordre. Ne garde
/// que quelques leçons récentes. Format 2 : les entrées du format 1 (ordre du classement par adhésion, non filtré
/// par la visibilité) ne sont pas relues.
@MainActor final class SchoolLessonSignalOrderFileStore: SchoolLessonSignalOrderStore {
    static let maximumAge: TimeInterval = 3 * 24 * 60 * 60
    static let maximumEntries = 20
    private static let format = 2

    private struct Entry: Codable {
        let apiBaseURL: String
        let personId: UUID
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
        guard (1...64).contains(order.count), order.allSatisfy(SchoolObservationKey.isWellFormed(_:)) else { return }
        let instant = now()
        var kept = entries().filter { isRecent($0, at: instant) && !(owns($0) && $0.lessonId == lessonID) }
        kept.append(Entry(apiBaseURL: scope.apiBaseURL, personId: scope.personID, schoolId: scope.schoolID,
                          membershipId: scope.membershipID, lessonId: lessonID, order: order, frozenAt: instant))
        // Les plus récentes d’abord, puis seulement les dernières leçons.
        kept.sort { $0.frozenAt > $1.frozenAt }
        let stored = Stored(format: Self.format, entries: Array(kept.prefix(Self.maximumEntries)))
        guard let data = try? JSONEncoder().encode(stored), data.count <= maximumBytes else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: [.atomic])
    }

    /// Déconnexion : plus aucune leçon n’est en cours pour personne sur cet appareil.
    static func removeAll(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: base.appendingPathComponent("SchoolLessonSignalOrders.json"))
    }

    private func owns(_ entry: Entry) -> Bool {
        entry.apiBaseURL == scope.apiBaseURL && entry.personId == scope.personID
            && entry.schoolId == scope.schoolID && entry.membershipId == scope.membershipID
    }

    private func isRecent(_ entry: Entry, at instant: Date) -> Bool {
        instant.timeIntervalSince(entry.frozenAt) <= Self.maximumAge
    }

    private func entries() -> [Entry] {
        guard let data = try? Data(contentsOf: file), data.count <= maximumBytes,
              let stored = try? JSONDecoder().decode(Stored.self, from: data), stored.format == Self.format else { return [] }
        return stored.entries
    }
}

/// Fabrique du stockage des ordres figés, remplacée par les rendus de contrôle, qui n’écrivent rien sur l’appareil.
@MainActor enum SchoolLessonSignalOrderStores {
    static var make: @MainActor (SchoolCommandScope) -> any SchoolLessonSignalOrderStore = { SchoolLessonSignalOrderFileStore(scope: $0) }
}
