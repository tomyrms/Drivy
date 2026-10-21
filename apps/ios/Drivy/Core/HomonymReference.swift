import Foundation

/// Short, non-secret references that tell apart people sharing the same visible name
/// (two instructors called « Marie Rochat »). Derived from the technical identifier: it reveals
/// no personal data and never replaces the identifier as the key of an action.
/// Same rule as `person-reference.ts` on the web.
enum HomonymReference {
    private static let minimumLength = 4

    private static func fold(_ label: String) -> String {
        label.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_CH"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// For every identifier whose name is shared with another one, the shortest ending of the
    /// identifier (four characters at least) that differs from all its homonyms.
    static func references(_ records: [(id: UUID, label: String)]) -> [UUID: String] {
        var groups: [String: [UUID]] = [:]
        for record in records where !(groups[fold(record.label)]?.contains(record.id) ?? false) {
            groups[fold(record.label), default: []].append(record.id)
        }
        var result: [UUID: String] = [:]
        for ids in groups.values where ids.count > 1 {
            let values = ids.map { $0.uuidString.replacingOccurrences(of: "-", with: "").uppercased() }
            var length = minimumLength
            while length < 32 && Set(values.map { String($0.suffix(length)) }).count < values.count { length += 1 }
            for (id, value) in zip(ids, values) { result[id] = String(value.suffix(length)) }
        }
        return result
    }

    /// « Marie Rochat · Réf. A1B2 » when a homonym exists, the name alone otherwise.
    static func label(_ name: String, reference: String?) -> String {
        reference.map { "\(name) · Réf. \($0)" } ?? name
    }
}
