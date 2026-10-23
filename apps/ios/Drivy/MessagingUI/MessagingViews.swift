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

    init(workspace: MessagingWorkspace, initialPeerID: UUID? = nil) {
        _workspace = State(initialValue: workspace)
        self.initialPeerID = initialPeerID
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
                    ForEach(workspace.conversations) { item in
                        Button {
                            route = Route(id: item.id, title: item.title, detail: item.identityDetail,
                                          sequence: item.lastSequence, readSequence: item.lastReadSequence,
                                          mutedUntil: item.mutedUntil, readStateVersion: item.readStateVersion,
                                          isGeneral: item.kind == .schoolGeneral)
                        } label: {
                            HStack {
                                // Composant local à initiales, sans photo ni accès au profil.
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

struct MessagingConversationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var connectivity = MessagingConnectivity()
    let workspace: MessagingWorkspace
    let conversationID: UUID
    let title: String
    let detail: String?
    let lastSequence: Int
    let lastReadSequence: Int
    let mutedUntil: Date?
    let readStateVersion: Int
    let isGeneral: Bool
    @State private var selectedMentions: [MessagingMentionSelection] = []
    @State private var showMentionPicker = false
    @State private var draft = ""
    @State private var draftReady = false
    @State private var draftFailure: String?
    @State private var queued: [MessagingPending] = []
    @State private var deliveryLabel: String?
    @State private var sending = false

    var body: some View {
        VStack {
            List {
                if let error = workspace.error { Text(error.localizedDescription).foregroundStyle(.secondary) }
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                if let until = (workspace.readStates[conversationID].map(\.mutedUntil) ?? mutedUntil), until > Date() {
                    Text("En sourdine").font(.caption).foregroundStyle(.secondary)
                }
                if workspace.canLoadMoreMessages(conversationID) {
                    Button("Charger les messages précédents") { Task { await workspace.loadMessages(conversationID, more: true) } }
                }
                ForEach(workspace.messages[conversationID] ?? []) { message in
                    MessagingMessageRow(workspace: workspace, message: message)
                }
                ForEach(queued, id: \.clientMessageID) { entry in
                    HStack {
                        Text("En attente d'envoi").font(.caption)
                        Spacer()
                        Button("Réessayer") { Task { await retry(entry) } }
                    }
                }
                if let deliveryLabel { Text(deliveryLabel).font(.caption).accessibilityIdentifier("messaging.delivery") }
                if let draftFailure { Text(draftFailure).font(.caption).foregroundStyle(.red) }
            }
            if isGeneral && !selectedMentions.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(selectedMentions, id: \.personID) { mention in
                            Button("Retirer @\(mention.displayName)") {
                                selectedMentions.removeAll { $0.personID == mention.personID }
                            }
                            .font(.caption)
                        }
                    }
                }
                .contentMargins(.horizontal, 12)
            }
            HStack {
                if isGeneral {
                    Button("Mentionner", systemImage: "at") { showMentionPicker = true }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Choisir des mentions")
                }
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5).accessibilityLabel("Rédiger un message")
                Button("Envoyer", systemImage: "arrow.up.circle.fill") { Task { await send() } }
                    .labelStyle(.iconOnly)
                    .disabled(sending || !draftReady || draftFailure != nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(title)
        .onAppear { connectivity.start() }
        .onDisappear { connectivity.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await workspace.refreshVisible(conversationID: conversationID) } }
        }
        .onChange(of: connectivity.available) { _, available in
            if available { Task { await workspace.refreshVisible(conversationID: conversationID) } }
        }
        .onChange(of: workspace.error) { _, failure in
            if failure == .contextChanged || failure == .accessChanged {
                draft = ""; queued = []; selectedMentions = []; draftReady = false
            }
        }
        .onChange(of: workspace.resumeGeneration) { _, _ in
            Task {
                guard workspace.error != .accessChanged && workspace.error != .contextChanged else { return }
                do { queued = try await workspace.outbox.pending(currentScope: workspace.scope)
                    .filter { $0.conversationID == conversationID } }
                catch { deliveryLabel = (error as? MessagingFailure ?? .protectionUnavailable).localizedDescription }
            }
        }
        .sheet(isPresented: $showMentionPicker) {
            NavigationStack {
                List(workspace.generalMembers) { person in
                    Button {
                        if selectedMentions.contains(where: { $0.personID == person.id }) {
                            selectedMentions.removeAll { $0.personID == person.id }
                        } else if selectedMentions.count < 8 {
                            selectedMentions.append(MessagingMentionSelection(personID: person.id,
                                displayName: person.displayName))
                        }
                    } label: {
                        HStack {
                            Text(person.displayName)
                            Spacer()
                            if selectedMentions.contains(where: { $0.personID == person.id }) { Image(systemName: "checkmark") }
                        }
                    }
                }
                .navigationTitle("Mentionner")
                .toolbar { Button("Terminé") { showMentionPicker = false } }
            }
            .task { await workspace.loadGeneralMembers() }
        }
        .toolbar {
            Menu("Options", systemImage: "ellipsis.circle") {
                Button("Marquer comme lu") {
                    Task {
                        let latest = workspace.conversations.first { $0.id == conversationID }?.lastSequence ?? lastSequence
                        await workspace.markRead(conversationID: conversationID, sequence: latest)
                    }
                }
                Button("Mettre en sourdine une heure") {
                    Task { await workspace.silence(conversationID: conversationID,
                        fallbackSequence: lastReadSequence, until: Date().addingTimeInterval(3_600),
                        fallbackVersion: readStateVersion) }
                }
                Button("Réactiver les notifications") {
                    Task { await workspace.unsilence(conversationID: conversationID,
                        fallbackSequence: lastReadSequence, fallbackVersion: readStateVersion) }
                }
            }
        }
        .task {
            if isGeneral { await workspace.loadGeneralMembers() }
            if !workspace.hasLoadedMessages(conversationID) { await workspace.loadMessages(conversationID) }
            do {
                draft = try await workspace.loadDraft(conversationID)
                queued = try await workspace.outbox.pending(currentScope: workspace.scope)
                    .filter { $0.conversationID == conversationID }
                draftReady = true
            } catch { draftFailure = (error as? MessagingFailure ?? .protectionUnavailable).localizedDescription }
        }
        .task(id: draft) {
            guard draftReady else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                try await workspace.saveDraft(draft, conversationID: conversationID)
                draftFailure = nil
            } catch is CancellationError {} catch {
                draftFailure = (error as? MessagingFailure ?? .protectionUnavailable).localizedDescription
            }
        }
    }

    private func send() async {
        guard !sending, draftReady else { return }
        sending = true
        defer { sending = false }
        let submitted = draft
        let submittedMentions = selectedMentions.map(\.personID)
        do {
            // La file chiffrée sur disque précède toute tentative réseau.
            let entry = try await workspace.outbox.enqueue(text: submitted, conversationID: conversationID,
                mentions: submittedMentions, currentScope: workspace.scope)
            queued.append(entry)
            if selectedMentions.map(\.personID) == submittedMentions { selectedMentions = [] }
            if draft == submitted {
                draft = ""
                try await workspace.saveDraft("", conversationID: conversationID)
                // Une frappe pendant l'écriture vide restaure immédiatement le nouveau brouillon.
                if !draft.isEmpty { try await workspace.saveDraft(draft, conversationID: conversationID) }
            }
            deliveryLabel = "En attente d'envoi"
            await retry(entry)
        } catch {
            deliveryLabel = (error as? MessagingFailure ?? .protectionUnavailable).localizedDescription
        }
    }

    private func retry(_ entry: MessagingPending) async {
        switch await workspace.outbox.retry(entry, currentScope: workspace.scope) {
        case .waiting: deliveryLabel = "En attente d'envoi"
        case .accepted:
            deliveryLabel = "Envoyé au serveur"
            queued.removeAll { $0.clientMessageID == entry.clientMessageID }
            await workspace.loadMessages(conversationID)
        case .failed(let failure): deliveryLabel = "Échec : \(failure.localizedDescription)"
        }
    }
}

private struct MessagingMessageRow: View {
    let workspace: MessagingWorkspace
    let message: MessagingWireMessage
    @State private var plaintext: String?
    var body: some View {
        Text(plaintext ?? "Message protégé indisponible")
            .textSelection(.enabled)
            .task(id: message.id) { plaintext = await workspace.text(for: message) }
    }
}
