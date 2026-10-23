import SwiftUI

/// Conversation v2 : bandeau épinglé, bulles riches, réponse citée, sondages, recherche locale,
/// sélection pour signalement, lecture seule après la fin du lien (composeur masqué).
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
    @State private var replyTo: MessagingWireMessage?
    @State private var showPollComposer = false
    @State private var showSearch = false
    @State private var showMembers = false
    @State private var reporting = false
    @State private var reportSelection: Set<UUID> = []
    @State private var reportSent = false
    @State private var scrollTarget: UUID?

    private var access: MessagingConversationAccess { workspace.access(for: conversationID) }

    var body: some View {
        VStack(spacing: 0) {
            MessagingPinnedBanner(workspace: workspace, pinned: workspace.pinnedMessages(conversationID)) { scrollTarget = $0 }
            ScrollViewReader { proxy in
                List {
                    if let error = workspace.error { Text(error.localizedDescription).foregroundStyle(.secondary) }
                    if let failure = workspace.actionError {
                        Text(failure.localizedDescription).foregroundStyle(.red)
                            .accessibilityIdentifier("messaging.action.error")
                            .onTapGesture { workspace.clearActionError() }
                    }
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    if let until = (workspace.readStates[conversationID].map(\.mutedUntil) ?? mutedUntil), until > Date() {
                        Text("En sourdine").font(.caption).foregroundStyle(.secondary)
                    }
                    if workspace.canLoadMoreMessages(conversationID) {
                        Button("Charger les messages précédents") { Task { await workspace.loadMessages(conversationID, more: true) } }
                    }
                    ForEach(workspace.visibleMessages(conversationID)) { message in
                        row(message).id(message.id)
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
                .listStyle(.plain)
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation { proxy.scrollTo(target, anchor: .center) }
                    scrollTarget = nil
                }
            }
            footer
        }
        .navigationTitle(reporting ? "Signaler" : title)
        .navigationBarTitleDisplayMode(.inline)
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
                draft = ""; queued = []; selectedMentions = []; draftReady = false; replyTo = nil
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
        .sheet(isPresented: $showMentionPicker) { mentionPicker }
        .sheet(isPresented: $showPollComposer) {
            MessagingPollComposer { poll, multiple in
                await send(MessagingPlainContent(poll: poll), pollAllowsMultiple: multiple)
            }
        }
        .sheet(isPresented: $showSearch) {
            MessagingSearchView(workspace: workspace, conversationID: conversationID) { scrollTarget = $0 }
        }
        .navigationDestination(isPresented: $showMembers) { MessagingMembersView(workspace: workspace) }
        .alert("Signalement transmis", isPresented: $reportSent) { Button("OK") {} }
        .toolbar { toolbar }
        .task {
            if isGeneral { await workspace.loadGeneralMembers(); await workspace.loadMembers() }
            if !workspace.hasLoadedMessages(conversationID) { await workspace.loadMessages(conversationID) }
            do {
                draft = try await workspace.loadDraft(conversationID)
                queued = try await workspace.outbox.pending(currentScope: workspace.scope)
                    .filter { $0.conversationID == conversationID }
                draftReady = true
            } catch { draftFailure = (error as? MessagingFailure ?? .protectionUnavailable).localizedDescription }
        }
        .task(id: draft) {
            guard draftReady, access.canWrite else { return }
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

    @ViewBuilder private func row(_ message: MessagingWireMessage) -> some View {
        let bubble = MessagingBubble(workspace: workspace, message: message, isGeneral: isGeneral,
            selecting: reporting, selected: reportSelection.contains(message.id),
            onReply: { replyTo = message }, onJump: { scrollTarget = $0 })
        if reporting && !message.meta.deletedForEveryone {
            Button {
                if reportSelection.contains(message.id) { reportSelection.remove(message.id) } else { reportSelection.insert(message.id) }
            } label: { bubble }
            .buttonStyle(.plain)
            .accessibilityAddTraits(reportSelection.contains(message.id) ? [.isSelected] : [])
            .accessibilityHint("Sélectionne ce message pour le signalement")
        } else {
            bubble
                .swipeActions(edge: .leading) {
                    if access.canWrite && !message.meta.deletedForEveryone && !reporting {
                        Button("Répondre", systemImage: "arrowshape.turn.up.left") { replyTo = message }.tint(.accentColor)
                    }
                }
        }
    }

    @ViewBuilder private var footer: some View {
        if reporting {
            HStack {
                Button("Annuler") { reporting = false; reportSelection = []; workspace.abandonReport(conversationID: conversationID) }
                Spacer()
                Button("Transmettre (\(reportSelection.count))") {
                    let selected = workspace.visibleMessages(conversationID).filter { reportSelection.contains($0.id) }
                    Task {
                        if await workspace.report(selected, conversationID: conversationID) {
                            reporting = false; reportSelection = []; reportSent = true
                        }
                    }
                }
                .bold()
                .disabled(reportSelection.isEmpty)
                .accessibilityIdentifier("messaging.report.send")
            }
            .padding()
            .background(.bar)
        } else if access.isReadOnly {
            // Fin du lien : l'historique reste lisible, aucun envoi possible.
            Label("Lecture seule", systemImage: "lock")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding()
                .background(.bar)
                .accessibilityIdentifier("messaging.readonly")
        } else {
            composer
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let replyTo {
                HStack {
                    Rectangle().fill(.tint).frame(width: 3)
                    VStack(alignment: .leading) {
                        Text(workspace.displayName(replyTo.senderID)).font(.caption.bold())
                        Text(workspace.contents[replyTo.id]?.summary ?? "Message").font(.caption).lineLimit(1).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Annuler la réponse", systemImage: "xmark.circle.fill") { self.replyTo = nil }
                        .labelStyle(.iconOnly).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("messaging.reply.preview")
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
            }
            HStack(alignment: .bottom) {
                Menu {
                    Button("Sondage", systemImage: "chart.bar.xaxis") { showPollComposer = true }
                    if isGeneral { Button("Mentionner", systemImage: "at") { showMentionPicker = true } }
                } label: {
                    Image(systemName: "plus.circle").font(.title2)
                }
                .accessibilityLabel("Plus d'options")
                .accessibilityIdentifier("messaging.compose.more")
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Rédiger un message")
                    .accessibilityIdentifier("messaging.compose.text")
                Button("Envoyer", systemImage: "arrow.up.circle.fill") {
                    Task { _ = await send(MessagingPlainContent(text: draft)) }
                }
                .labelStyle(.iconOnly).font(.title2)
                .disabled(sending || !draftReady || draftFailure != nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(.bar)
    }

    private var mentionPicker: some View {
        NavigationStack {
            List(workspace.generalMembers) { person in
                Button {
                    if selectedMentions.contains(where: { $0.personID == person.id }) {
                        selectedMentions.removeAll { $0.personID == person.id }
                    } else if selectedMentions.count < 8 {
                        selectedMentions.append(MessagingMentionSelection(personID: person.id, displayName: person.displayName))
                    }
                } label: {
                    HStack {
                        Text(person.displayName)
                        Spacer()
                        if selectedMentions.contains(where: { $0.personID == person.id }) { Image(systemName: "checkmark") }
                    }
                }
                .accessibilityAddTraits(selectedMentions.contains(where: { $0.personID == person.id }) ? [.isSelected] : [])
            }
            .navigationTitle("Mentionner")
            .toolbar { Button("Terminé") { showMentionPicker = false } }
        }
        .task { await workspace.loadGeneralMembers() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Rechercher", systemImage: "magnifyingglass") { showSearch = true }
                .accessibilityIdentifier("messaging.search.open")
            Menu("Options", systemImage: "ellipsis.circle") {
                if isGeneral { Button("Membres", systemImage: "person.3") { showMembers = true } }
                Button("Signaler des messages", systemImage: "exclamationmark.bubble") { reporting = true }
                Divider()
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
            .accessibilityIdentifier("messaging.options")
        }
    }

    /// La file chiffrée sur disque précède toute tentative réseau.
    private func send(_ content: MessagingPlainContent, pollAllowsMultiple: Bool = false) async -> Bool {
        guard !sending, draftReady, access.canWrite else { return false }
        sending = true
        defer { sending = false }
        let isText = content.poll == nil
        let submitted = draft
        let submittedMentions = selectedMentions.map(\.personID)
        do {
            let entry = try await workspace.enqueue(content: content, conversationID: conversationID,
                mentions: submittedMentions, replyTo: replyTo?.id, pollAllowsMultiple: pollAllowsMultiple)
            queued.append(entry)
            replyTo = nil
            if selectedMentions.map(\.personID) == submittedMentions { selectedMentions = [] }
            if isText && draft == submitted {
                draft = ""
                try await workspace.saveDraft("", conversationID: conversationID)
                if !draft.isEmpty { try await workspace.saveDraft(draft, conversationID: conversationID) }
            }
            deliveryLabel = "En attente d'envoi"
            await retry(entry)
            return true
        } catch {
            deliveryLabel = (error as? MessagingFailure ?? .protectionUnavailable).localizedDescription
            return false
        }
    }

    private func retry(_ entry: MessagingPending) async {
        switch await workspace.outbox.retry(entry, currentScope: workspace.scope) {
        case .waiting: deliveryLabel = "En attente d'envoi"
        case .accepted:
            deliveryLabel = nil
            queued.removeAll { $0.clientMessageID == entry.clientMessageID }
            await workspace.loadMessages(conversationID)
        case .failed(let failure): deliveryLabel = "Échec : \(failure.localizedDescription)"
        }
    }
}
