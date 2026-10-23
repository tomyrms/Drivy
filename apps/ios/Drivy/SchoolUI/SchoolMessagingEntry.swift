import SwiftUI

enum SchoolMessagingDevelopment {
    /// Présentation de développement uniquement. Ce garde n'autorise ni E2EE ni activation serveur.
    static func permitted(arguments: [String], schoolIsActive: Bool) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        return schoolIsActive && arguments.contains("-messaging-development")
        #else
        return false
        #endif
    }
}

/// Point d'intégration réversible pour #66. Rien n'est affiché si la composition n'est pas fournie.
/// La fermeture fabrique une vue dans le contexte exact, jamais une conversation par nom d'élève.
struct SchoolMessagingEntry: Sendable {
    let scopeID: String
    let makeView: @MainActor @Sendable (UUID?) -> AnyView
}

private struct SchoolMessagingEntryKey: EnvironmentKey {
    static let defaultValue: SchoolMessagingEntry? = nil
}

extension EnvironmentValues {
    var schoolMessagingEntry: SchoolMessagingEntry? {
        get { self[SchoolMessagingEntryKey.self] }
        set { self[SchoolMessagingEntryKey.self] = newValue }
    }
}

struct SchoolMessagingEntryButton: View {
    private struct Route: Identifiable {
        let id: String
        let entry: SchoolMessagingEntry
        let peerID: UUID?
    }

    var peerID: UUID? = nil
    @Environment(\.schoolMessagingEntry) private var entry
    @State private var route: Route?

    var body: some View {
        Group {
            if let entry {
                Button {
                    route = Route(id: entry.scopeID, entry: entry, peerID: peerID)
                } label: {
                    Label(peerID == nil ? "Messages" : "Envoyer un message", systemImage: "bubble.left.and.bubble.right")
                }
                .accessibilityIdentifier(peerID == nil ? "messages-entry" : "learner-send-message")
            }
        }
        .sheet(item: $route) { route in
            route.entry.makeView(route.peerID).id(route.id)
        }
        .onChange(of: entry?.scopeID) { _, _ in route = nil }
        .onChange(of: peerID) { _, _ in route = nil }
    }
}
