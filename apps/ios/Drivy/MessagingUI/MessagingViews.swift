import SwiftUI

/// Composant réversible, non inséré dans les onglets tant que #66 n'a pas validé la navigation.
struct MessagingInboxView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var workspace: MessagingWorkspace
    @State private var connectivity = MessagingConnectivity()
    private let initialPeerID: UUID?
    @State private var route: Route?
    @State private var opening = false
    @State private var initialPeerAttempted = false

    private struct Route: Identifiable, Hashable {
        let id: UUID
        let title: String
        let detail: String?
        let sequence: Int
        let readSequence: Int
        let mutedUntil: Date?
        let readStateVersion: Int
        let isGeneral: Bool
    }

    private let keys: (any MessagingKeyManagement)?
    private let currentScope: @MainActor @Sendable () -> MessagingScope?

    init(workspace: MessagingWorkspace, initialPeerID: UUID? = nil, keys: (any MessagingKeyManagement)? = nil,
         currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) {
        _workspace = State(initialValue: workspace)
        self.initialPeerID = initialPeerID
        self.keys = keys
        self.currentScope = currentScope
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = workspace.error {
                    ContentUnavailableView("Messages indisponibles", systemImage: "lock.shield",
                        description: Text(error.localizedDescription))
                        .accessibilityIdentifier("messaging.error")
                }
                Section("Discussions") {
                    Button { Task { await openGeneral() } } label: {
                        Label("Général de l'école", systemImage: "person.3")
                    }
                    .disabled(opening)
                    NavigationLink {
                        MessagingMembersView(workspace: workspace)
                    } label: {
                        Label("Membres du général", systemImage: "person.2.circle")
                    }
                    .accessibilityIdentifier("messaging.members.open")
                    ForEach(workspace.conversations) { item in
                        Button {
                            route = Route(id: item.id, title: item.title, detail: item.identityDetail,
                                          sequence: item.lastSequence, readSequence: item.lastReadSequence,
                                          mutedUntil: item.mutedUntil, readStateVersion: item.readStateVersion,
                                          isGeneral: item.kind == .schoolGeneral)
                        } label: {
                            HStack {
                                // Photo de l'interlocuteur seulement si le serveur l'a exposée (#64).
                                DrivyAvatar(name: item.title, size: 42).accessibilityHidden(true)
                                VStack(alignment: .leading) {
                                    Text(item.title).font(.headline)
                                    if let detail = item.identityDetail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if let unread = item.unreadCount, unread > 0 {
                                    Text(unread.formatted()).font(.caption.bold()).padding(6)
                                        .background(.tint, in: Capsule())
                                        .accessibilityLabel("\(unread) messages non lus")
                                }
                            }
                        }
                    }
                    if workspace.canLoadMoreConversations {
                        Button("Charger plus de conversations") { Task { await workspace.loadConversations(more: true) } }
                    }
                    if workspace.hasLoadedConversations && workspace.conversations.isEmpty {
                        Text("Aucune conversation").foregroundStyle(.secondary)
                    }
                }
                Section("Contacts autorisés") {
                    ForEach(workspace.contacts) { contact in
                        Button { Task { await openPrivate(contact) } } label: {
                            Text(contact.displayName)
                        }
                        .disabled(opening)
                    }
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        MessagingSettingsView(keys: keys, scope: workspace.scope, currentScope: currentScope)
                    } label: {
                        Label("Réglages", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("messaging.settings.open")
                }
            }
            .onAppear { connectivity.start() }
            .onDisappear { connectivity.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await workspace.refreshVisible(conversationID: route?.id) } }
            }
            .onChange(of: connectivity.available) { _, available in
                if available { Task { await workspace.refreshVisible(conversationID: route?.id) } }
            }
            .overlay { if workspace.loading && !workspace.hasLoadedConversations { ProgressView("Chargement") } }
            .refreshable { await workspace.loadConversations(); await workspace.loadContacts() }
            .task {
                if !workspace.hasLoadedConversations { await workspace.loadConversations() }
                await workspace.loadContacts()
                await workspace.refreshVisible()
                if let initialPeerID, !initialPeerAttempted {
                    initialPeerAttempted = true
                    // Une fiche ne contourne pas le contrôle serveur. La route s'ouvre uniquement après un PUT autorisé.
                    if let id = await workspace.privateConversation(peerID: initialPeerID) {
                        let contact = workspace.contacts.first { $0.id == initialPeerID }
                        route = Route(id: id, title: contact?.displayName ?? "Conversation privée",
                                      detail: nil,
                                      sequence: 0, readSequence: 0, mutedUntil: nil,
                                      readStateVersion: 0, isGeneral: false)
                    }
                }
            }
            .navigationDestination(item: $route) { selected in
                MessagingConversationView(workspace: workspace, conversationID: selected.id,
                    title: selected.title, detail: selected.detail, lastSequence: selected.sequence,
                    lastReadSequence: selected.readSequence, mutedUntil: selected.mutedUntil,
                    readStateVersion: selected.readStateVersion, isGeneral: selected.isGeneral)
            }
        }
    }

    private func openPrivate(_ contact: MessagingContact) async {
        opening = true; defer { opening = false }
        if let id = await workspace.privateConversation(peerID: contact.id) {
            let known = workspace.conversations.first { $0.id == id }
            route = Route(id: id, title: contact.displayName,
                detail: nil, sequence: known?.lastSequence ?? 0,
                readSequence: known?.lastReadSequence ?? 0, mutedUntil: known?.mutedUntil,
                readStateVersion: known?.readStateVersion ?? 0, isGeneral: false)
        }
    }

    private func openGeneral() async {
        opening = true; defer { opening = false }
        if let id = await workspace.generalConversation() {
            let known = workspace.conversations.first { $0.id == id }
            route = Route(id: id, title: "Général", detail: nil, sequence: known?.lastSequence ?? 0,
                          readSequence: known?.lastReadSequence ?? 0, mutedUntil: known?.mutedUntil,
                          readStateVersion: known?.readStateVersion ?? 0, isGeneral: true)
        }
    }
}
