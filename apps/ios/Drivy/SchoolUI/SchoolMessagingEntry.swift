import SwiftUI

enum SchoolMessagingDevelopment {
    /// Opt-in à la compilation de l'IPA de qualification, jamais un argument activable par l'utilisateur.
    static var isQualificationBuild: Bool {
        #if DRIVY_MESSAGING_QUALIFICATION
        return true
        #else
        return false
        #endif
    }

    /// Accès de qualification distinct d'une activation générale et des autorisations serveur.
    static func permitted(arguments: [String], schoolIsActive: Bool) -> Bool {
        guard schoolIsActive else { return false }
        if isQualificationBuild { return true }
        #if DEBUG && targetEnvironment(simulator)
        return arguments.contains("-messaging-development")
        #else
        return false
        #endif
    }
}

/// Point d'intégration réversible pour #66. Rien n'est affiché si la composition n'est pas fournie.
/// La fermeture fabrique une vue dans le contexte exact, jamais une conversation par nom d'élève.
struct SchoolMessagingEntry: Sendable {
    let scopeID: String
    var isQualification: Bool = false
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
                    HStack(spacing: DrivySpacing.xs) {
                        Label(peerID == nil ? "Messages" : "Envoyer un message", systemImage: "bubble.left.and.bubble.right")
                        if entry.isQualification {
                            DrivyStatusBadge(title: "Test", tone: .accent)
                        }
                    }
                }
                .accessibilityLabel((peerID == nil ? "Messages" : "Envoyer un message") + (entry.isQualification ? ", Test" : ""))
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
