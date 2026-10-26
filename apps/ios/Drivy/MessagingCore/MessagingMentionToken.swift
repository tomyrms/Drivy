import Foundation

/// Détection et insertion d'une mention `@` en cours de frappe (#101). Logique pure, testable.
enum MessagingMentionToken {
    /// Texte tapé après le dernier `@` en fin de brouillon, si ce `@` débute un mot et qu'aucun saut de ligne ne suit.
    /// Les espaces sont admis (prénom nom) jusqu'à 30 caractères.
    static func query(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at > text.startIndex {
            let before = text[text.index(before: at)]
            guard before.isWhitespace else { return nil }
        }
        let tail = text[text.index(after: at)...]
        guard !tail.contains(where: \.isNewline), tail.count <= 30, !tail.hasPrefix(" "),
              // Après insertion (`@Nom `) ou un espace final, la saisie de mention est terminée.
              !(tail.last?.isWhitespace ?? false) else { return nil }
        return String(tail)
    }

    /// Filtre insensible à la casse et aux accents, sur le début du nom ou de chaque mot.
    static func filter<T>(_ people: [T], query: String, name: KeyPath<T, String>) -> [T] {
        let q = fold(query)
        guard !q.isEmpty else { return people }
        return people.filter { person in
            let n = fold(person[keyPath: name])
            return n.hasPrefix(q) || n.split(separator: " ").contains { $0.hasPrefix(q) }
        }
    }

    /// Remplace le jeton en cours par `@Nom ` ; nil si aucun jeton.
    static func replacing(in text: String, with displayName: String) -> String? {
        guard query(in: text) != nil, let at = text.lastIndex(of: "@") else { return nil }
        return String(text[..<at]) + "@" + displayName + " "
    }

    /// Texte affiché avec chaque `@Nom` connu en gras. Les noms sont essayés du plus long au plus court.
    static func styled(_ text: String, names: [String]) -> AttributedString {
        var result = AttributedString(text)
        for range in mentionRanges(in: text, names: names) {
            guard let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }
        return result
    }

    /// Plages `@Nom` reconnues, sans chevauchement, `@` en début de mot.
    static func mentionRanges(in text: String, names: [String]) -> [Range<String.Index>] {
        let ordered = names.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        var ranges: [Range<String.Index>] = []
        var index = text.startIndex
        while let at = text[index...].firstIndex(of: "@") {
            let startsWord = at == text.startIndex || text[text.index(before: at)].isWhitespace
            let after = text.index(after: at)
            if startsWord, let name = ordered.first(where: { text[after...].hasPrefix($0) }) {
                let end = text.index(after, offsetBy: name.count)
                ranges.append(at..<end)
                index = end
            } else {
                index = after
            }
        }
        return ranges
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}
