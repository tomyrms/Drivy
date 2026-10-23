import SwiftUI

/// Membres du général : nom et photo uniquement (décision 2). Un appui ouvre le profil.
struct MessagingMembersView: View {
    let workspace: MessagingWorkspace
    @State private var profile: MessagingMember?
    @State private var pendingRemoval: MessagingMember?

    private var isAdmin: Bool { workspace.members.first { $0.id == workspace.scope.accountID }?.isGroupAdmin ?? false }

    var body: some View {
        List {
            if let failure = workspace.actionError {
                Text(failure.localizedDescription).foregroundStyle(.red).accessibilityIdentifier("messaging.members.error")
            }
            ForEach(workspace.members) { member in
                Button { profile = member } label: {
                    HStack(spacing: 12) {
                        DrivyAvatar(name: member.displayName, size: 40, photo: workspace.photos[member.id])
                        Text(member.displayName).foregroundStyle(.primary)
                        Spacer()
                        if member.isGroupAdmin {
                            Text("Admin").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(member.isGroupAdmin ? "\(member.displayName), administrateur du groupe" : member.displayName)
                .accessibilityHint("Ouvre le profil")
                .task { if member.hasPhoto { await workspace.loadPhoto(member.id) } }
                .swipeActions {
                    if isAdmin && member.id != workspace.scope.accountID {
                        Button("Retirer", role: .destructive) { pendingRemoval = member }
                        Button(member.isGroupAdmin ? "Retirer admin" : "Nommer admin") {
                            Task { await workspace.setGroupAdmin(member.id, admin: !member.isGroupAdmin) }
                        }
                    }
                }
                .contextMenu {
                    if isAdmin && member.id != workspace.scope.accountID {
                        Button(member.isGroupAdmin ? "Retirer des administrateurs" : "Nommer administrateur",
                               systemImage: "person.badge.shield.checkmark") {
                            Task { await workspace.setGroupAdmin(member.id, admin: !member.isGroupAdmin) }
                        }
                        Button("Retirer du général", systemImage: "person.badge.minus", role: .destructive) { pendingRemoval = member }
                    }
                }
            }
        }
        .navigationTitle("Membres")
        .accessibilityIdentifier("messaging.members")
        .task { await workspace.loadMembers() }
        .refreshable { await workspace.loadMembers() }
        .sheet(item: $profile) { member in
            MessagingMemberProfileView(member: member, photo: workspace.photos[member.id])
        }
        .confirmationDialog("Retirer du général ?", isPresented: Binding(get: { pendingRemoval != nil },
                                                                         set: { if !$0 { pendingRemoval = nil } }),
                            presenting: pendingRemoval) { member in
            Button("Retirer \(member.displayName)", role: .destructive) {
                Task { await workspace.removeMember(member.id) }
            }
        }
    }
}

/// Profil visible depuis le général : uniquement le nom et la photo (#64, décision 2).
struct MessagingMemberProfileView: View {
    let member: MessagingMember
    let photo: Data?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DrivyAvatar(name: member.displayName, size: 120, photo: photo)
                Text(member.displayName).font(.title2.bold()).multilineTextAlignment(.center)
                if member.isGroupAdmin { Text("Administrateur du groupe").foregroundStyle(.secondary) }
                Spacer()
            }
            .padding(.top, 32)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("messaging.member.profile")
            .toolbar { Button("Fermer") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Bandeau des messages épinglés : un appui fait défiler vers le message.
struct MessagingPinnedBanner: View {
    let workspace: MessagingWorkspace
    let pinned: [MessagingWireMessage]
    let onSelect: (UUID) -> Void
    @State private var index = 0

    var body: some View {
        if !pinned.isEmpty {
            let current = pinned[min(index, pinned.count - 1)]
            Button {
                onSelect(current.id)
                index = (index + 1) % pinned.count
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pin.fill").foregroundStyle(.tint).accessibilityHidden(true)
                    Text(workspace.contents[current.id]?.summary ?? "Message épinglé")
                        .lineLimit(1).font(.subheadline)
                    Spacer()
                    if pinned.count > 1 {
                        Text("\(min(index, pinned.count - 1) + 1)/\(pinned.count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Message épinglé : \(workspace.contents[current.id]?.summary ?? "")")
            .accessibilityHint(pinned.count > 1 ? "Affiche le message, puis le suivant au prochain appui" : "Affiche le message")
            .accessibilityIdentifier("messaging.pinned")
        }
    }
}

/// Bulle d'un message : citation, contenu ou sondage, réactions, accusés de lecture.
struct MessagingBubble: View {
    let workspace: MessagingWorkspace
    let message: MessagingWireMessage
    let isGeneral: Bool
    var selecting = false
    var selected = false
    let onReply: () -> Void
    let onJump: (UUID) -> Void
    @State private var content: MessagingPlainContent?
    @State private var loaded = false
    @State private var confirmDeleteEveryone = false
    @State private var votersFor: MessagingPollState?

    private var mine: Bool { message.senderID == workspace.scope.accountID }
    private var access: MessagingConversationAccess { workspace.access(for: message.conversationID) }

    var body: some View {
        HStack(alignment: .top) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                if isGeneral && !mine {
                    Text(workspace.displayName(message.senderID)).font(.caption.bold()).foregroundStyle(.secondary)
                }
                bubble
                if !message.meta.reactions.isEmpty { reactions }
                if mine, !message.meta.deletedForEveryone { receipt }
            }
            if !mine { Spacer(minLength: 40) }
        }
        .listRowSeparator(.hidden)
        .task(id: message.id) {
            if !message.meta.deletedForEveryone { content = await workspace.content(for: message) }
            loaded = true
        }
        .contextMenu { if !selecting { menu } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messaging.message")
        .confirmationDialog("Supprimer pour tout le monde ?", isPresented: $confirmDeleteEveryone) {
            Button("Supprimer pour tout le monde", role: .destructive) {
                Task { await workspace.delete(message, for: .everyone) }
            }
        }
        .sheet(item: Binding(get: { votersFor.map { MessagingPollVotersSheet.Item(poll: $0) } },
                             set: { if $0 == nil { votersFor = nil } })) { item in
            MessagingPollVotersSheet(workspace: workspace, poll: item.poll, content: content?.poll)
        }
    }

    @ViewBuilder private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let replyID = message.meta.replyToMessageID { quote(replyID) }
            if message.meta.deletedForEveryone {
                Label("Message supprimé", systemImage: "nosign").italic().foregroundStyle(.secondary)
                    .accessibilityIdentifier("messaging.deleted")
            } else if let poll = content?.poll, let state = message.meta.poll {
                MessagingPollCard(workspace: workspace, message: message, poll: poll, state: state,
                                  onShowVoters: { votersFor = state })
            } else if let text = content?.text {
                Text(text).textSelection(.enabled)
            } else if loaded {
                Label("Message protégé indisponible", systemImage: "lock").foregroundStyle(.secondary)
            } else {
                ProgressView().accessibilityLabel("Déchiffrement")
            }
            HStack(spacing: 4) {
                if message.meta.pinned { Image(systemName: "pin.fill").accessibilityLabel("Épinglé") }
                Text(message.acceptedAt, style: .time)
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(mine ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private func quote(_ id: UUID) -> some View {
        let quoted = workspace.message(id, in: message.conversationID)
        let summary: String = {
            guard let quoted else { return "Message indisponible" }
            if quoted.meta.deletedForEveryone { return "Message supprimé" }
            return workspace.contents[id]?.summary ?? "Message"
        }()
        return Button { onJump(id) } label: {
            HStack(spacing: 6) {
                Rectangle().fill(.tint).frame(width: 3)
                VStack(alignment: .leading) {
                    if let quoted { Text(workspace.displayName(quoted.senderID)).font(.caption.bold()) }
                    Text(summary).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("En réponse à : \(summary)")
        .accessibilityHint("Affiche le message cité")
    }

    private var reactions: some View {
        HStack(spacing: 4) {
            ForEach(message.meta.reactions, id: \.emoji) { reaction in
                let reacted = reaction.personIDs.contains(workspace.scope.accountID)
                Button { Task { await workspace.toggleReaction(reaction.emoji, on: message) } } label: {
                    Text("\(reaction.emoji) \(reaction.personIDs.count)").font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(reacted ? Color.accentColor.opacity(0.25) : Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!access.canWrite)
                .accessibilityLabel("\(MessagingReactionPalette.label(reaction.emoji)), \(reaction.personIDs.count)"
                    + (reacted ? ", dont vous" : ""))
                .accessibilityHint(reaction.personIDs.map(workspace.displayName).joined(separator: ", "))
            }
        }
    }

    @ViewBuilder private var receipt: some View {
        let readers = workspace.readers(of: message)
        if !readers.isEmpty {
            let label = isGeneral ? "Lu par \(readers.count)" : "Lu"
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .accessibilityLabel(isGeneral ? "Lu par \(readers.map(workspace.displayName).joined(separator: ", "))" : "Lu")
                .accessibilityIdentifier("messaging.read")
        }
    }

    @ViewBuilder private var menu: some View {
        if !message.meta.deletedForEveryone && access.canWrite {
            Menu("Réagir", systemImage: "face.smiling") {
                ForEach(MessagingReactionPalette.all, id: \.self) { emoji in
                    Button("\(emoji) \(MessagingReactionPalette.label(emoji))") {
                        Task { await workspace.toggleReaction(emoji, on: message) }
                    }
                }
            }
            Button("Répondre", systemImage: "arrowshape.turn.up.left", action: onReply)
            Button(message.meta.pinned ? "Désépingler" : "Épingler", systemImage: message.meta.pinned ? "pin.slash" : "pin") {
                Task { await workspace.setPinned(message, pinned: !message.meta.pinned) }
            }
        }
        if let text = content?.text, !message.meta.deletedForEveryone {
            Button("Copier", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
        }
        Button("Supprimer pour moi", systemImage: "trash", role: .destructive) {
            Task { await workspace.delete(message, for: .me) }
        }
        if !message.meta.deletedForEveryone,
           MessagingPermissions.canDeleteForEveryone(senderID: message.senderID, account: workspace.scope.accountID, access: access) {
            Button("Supprimer pour tout le monde", systemImage: "trash.slash", role: .destructive) { confirmDeleteEveryone = true }
        }
    }
}

/// Sondage : choix unique par défaut, multiple si le créateur l'a activé. Un appui sur son choix le retire.
struct MessagingPollCard: View {
    let workspace: MessagingWorkspace
    let message: MessagingWireMessage
    let poll: MessagingPlainContent.Poll
    let state: MessagingPollState
    let onShowVoters: () -> Void
    @State private var confirmClose = false

    private var access: MessagingConversationAccess { workspace.access(for: message.conversationID) }
    private var myVotes: Set<String> {
        Set(state.options.filter { $0.voterIDs.contains(workspace.scope.accountID) }.map(\.optionID))
    }
    private var total: Int { Set(state.options.flatMap(\.voterIDs)).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(poll.question, systemImage: "chart.bar.xaxis").font(.headline)
            Text(state.closed ? "Sondage clos" : (state.allowsMultiple ? "Plusieurs choix possibles" : "Un seul choix"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(poll.options, id: \.id) { option in
                let votes = state.options.first { $0.optionID == option.id }?.voterIDs.count ?? 0
                let chosen = myVotes.contains(option.id)
                Button {
                    let next = MessagingPollRules.toggled(myVotes, option: option.id, allowsMultiple: state.allowsMultiple)
                    Task { await workspace.vote(message, optionIDs: next) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: chosen ? (state.allowsMultiple ? "checkmark.square.fill" : "checkmark.circle.fill")
                                                     : (state.allowsMultiple ? "square" : "circle"))
                                .foregroundStyle(chosen ? Color.accentColor : .secondary)
                            Text(option.label).foregroundStyle(.primary)
                            Spacer()
                            Text(votes.formatted()).foregroundStyle(.secondary)
                        }
                        ProgressView(value: total == 0 ? 0 : Double(votes) / Double(total)).accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!MessagingPermissions.canVote(state, access: access))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(option.label), \(votes) vote\(votes > 1 ? "s" : "")")
                .accessibilityValue(chosen ? "Choisi" : "")
                .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(MessagingPermissions.canVote(state, access: access) ? (chosen ? "Retire votre vote" : "Vote pour cette option") : "")
            }
            HStack {
                Button("Voir les votes", action: onShowVoters).font(.subheadline)
                Spacer()
                if MessagingPermissions.canClosePoll(state, account: workspace.scope.accountID, access: access) {
                    Button("Clore", role: .destructive) { confirmClose = true }.font(.subheadline)
                }
            }
        }
        .accessibilityIdentifier("messaging.poll")
        .confirmationDialog("Clore le sondage ?", isPresented: $confirmClose) {
            Button("Clore le sondage", role: .destructive) { Task { await workspace.closePoll(message) } }
        }
    }
}

/// Votants nominatifs par option, visibles des participants.
struct MessagingPollVotersSheet: View {
    struct Item: Identifiable { let poll: MessagingPollState; var id: String { poll.creatorID.uuidString + poll.options.map(\.optionID).joined() } }
    let workspace: MessagingWorkspace
    let poll: MessagingPollState
    let content: MessagingPlainContent.Poll?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(poll.options, id: \.optionID) { option in
                Section(content?.options.first { $0.id == option.optionID }?.label ?? option.optionID) {
                    if option.voterIDs.isEmpty {
                        Text("Aucun vote").foregroundStyle(.secondary)
                    }
                    ForEach(option.voterIDs, id: \.self) { person in
                        HStack {
                            DrivyAvatar(name: workspace.displayName(person), size: 32, photo: workspace.photos[person])
                            Text(workspace.displayName(person))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle(content?.question ?? "Votes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Fermer") { dismiss() } }
        }
    }
}

/// Création d'un sondage : question, options, choix multiple optionnel.
struct MessagingPollComposer: View {
    let onCreate: (MessagingPlainContent.Poll, Bool) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var options = ["", ""]
    @State private var multiple = false
    @State private var sending = false
    @FocusState private var focused: Int?

    private var poll: MessagingPlainContent.Poll? { MessagingPollRules.validated(question: question, options: options) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("Question", text: $question, axis: .vertical)
                        .accessibilityIdentifier("messaging.poll.question")
                }
                Section("Options") {
                    ForEach(options.indices, id: \.self) { index in
                        TextField("Option \(index + 1)", text: $options[index])
                            .focused($focused, equals: index)
                            .accessibilityIdentifier("messaging.poll.option.\(index)")
                    }
                    .onDelete { set in if options.count - set.count >= 2 { options.remove(atOffsets: set) } }
                    if options.count < MessagingPollRules.maxOptions {
                        Button("Ajouter une option", systemImage: "plus") {
                            options.append(""); focused = options.count - 1
                        }
                    }
                }
                Section {
                    Toggle("Plusieurs choix", isOn: $multiple).accessibilityIdentifier("messaging.poll.multiple")
                }
            }
            .navigationTitle("Sondage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Envoyer") {
                        guard let poll else { return }
                        sending = true
                        Task {
                            if await onCreate(poll, multiple) { dismiss() }
                            sending = false
                        }
                    }
                    .disabled(poll == nil || sending)
                    .accessibilityIdentifier("messaging.poll.send")
                }
            }
        }
    }
}

/// Recherche locale dans l'historique déchiffré stocké sur l'appareil.
struct MessagingSearchView: View {
    let workspace: MessagingWorkspace
    let conversationID: UUID
    let onSelect: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MessagingHistoryEntry] = []

    var body: some View {
        NavigationStack {
            List(results) { entry in
                Button { onSelect(entry.messageID); dismiss() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(workspace.displayName(entry.senderID)).font(.caption.bold())
                            Spacer()
                            Text(entry.acceptedAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(entry.content.summary).lineLimit(3).foregroundStyle(.primary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .overlay {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty && results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                results = await workspace.search(query, conversationID: conversationID)
            }
            .navigationTitle("Rechercher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Fermer") { dismiss() } }
            .accessibilityIdentifier("messaging.search")
        }
    }
}
