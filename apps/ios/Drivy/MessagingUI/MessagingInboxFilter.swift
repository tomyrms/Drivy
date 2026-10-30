import Foundation

/// Projection du seul compteur autorisé. Une borne de séquence ne permet pas de compter les messages reçus.
enum MessagingInboxReadCategory: Equatable {
    case unread, read, unknown

    init(serverUnreadCount: Int?) {
        guard let count = serverUnreadCount, count >= 0 else { self = .unknown; return }
        self = count > 0 ? .unread : .read
    }
}

enum MessagingInboxFilter: String, CaseIterable, Identifiable {
    case all, unread
    var id: Self { self }
    var title: String { self == .all ? "Toutes" : "Non lus" }

    /// Les inconnus restent accessibles dans une section distincte, sans être présentés comme lus ou non lus.
    func includes(serverUnreadCount: Int?) -> Bool {
        self == .all || MessagingInboxReadCategory(serverUnreadCount: serverUnreadCount) != .read
    }

    static func matches(query: String, title: String, preview: String?) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || [title, preview ?? ""].contains {
            $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
