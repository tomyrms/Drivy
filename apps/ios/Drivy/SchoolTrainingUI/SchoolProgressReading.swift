import Foundation

/// Lecture locale de la seule projection autorisée de la formation. Aucun chargement, classement pédagogique
/// nouveau ou stockage de la recherche : les groupes et les niveaux viennent des règles existantes.
struct SchoolProgressReading {
    let toWorkOn: [SchoolReportProgressItem]
    let independent: [SchoolReportProgressItem]
    let unseen: [SchoolCatalogCompetency]
    let isSearching: Bool
    let missingReferenceCount: Int
    private let labels: [UUID: String]

    var resultCount: Int { toWorkOn.count + independent.count + unseen.count }

    init(progress: SchoolReportProgress, curriculum: [SchoolCatalogCompetency], query: String) {
        let expectedIDs = Set(progress.items.map(\.id)).union(progress.unobservedCompetencyIds)
        let reference = curriculum.filter { expectedIDs.contains($0.id) }.sorted { $0.sortOrder < $1.sortOrder }
        let byID = Dictionary(reference.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        labels = byID.mapValues(\.displayLabel)
        missingReferenceCount = expectedIDs.subtracting(byID.keys).count
        let needle = Self.normalized(query)
        isSearching = !needle.isEmpty

        let matchingItems = progress.items.filter { item in
            let competency = byID[item.id]
            return needle.isEmpty || Self.normalized(competency?.label ?? item.label).contains(needle)
                || Self.normalized(competency?.displayLabel ?? item.displayLabel).contains(needle)
        }
        toWorkOn = SchoolProgressRules.toWorkOn(matchingItems)
        independent = SchoolProgressRules.independent(matchingItems, order: reference.map(\.id))
        let unseenIDs = Set(progress.unobservedCompetencyIds)
        unseen = reference.filter {
            unseenIDs.contains($0.id) && (needle.isEmpty || Self.normalized($0.label).contains(needle)
                || Self.normalized($0.displayLabel).contains(needle))
        }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func label(_ item: SchoolReportProgressItem) -> String { labels[item.id] ?? item.displayLabel }

    /// Une définition absente n’est ni inventée, ni remplacée par un bouton vide.
    static func definition(_ competency: SchoolCatalogCompetency) -> String? {
        let description = competency.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? nil : description
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr"))
    }
}
