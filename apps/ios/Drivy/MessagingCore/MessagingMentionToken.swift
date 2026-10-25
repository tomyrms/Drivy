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

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}
