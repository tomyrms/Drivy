import SwiftUI

/// Membres du général : nom et photo uniquement (décision 2). Un appui ouvre le profil.
struct MessagingMembersView: View {
    let workspace: MessagingWorkspace
    @State private var profile: MessagingMember?
    /// Une seule confirmation à la fois : deux `confirmationDialog` sur la même vue
    /// se neutralisent (seul le dernier attaché se présente de façon fiable).
    private enum PendingAction: Identifiable {
        case remove(MessagingMember)
        case reinstate(MessagingMember)
        var id: String {
            switch self {
            case .remove(let m): "remove-\(m.id)"
            case .reinstate(let m): "reinstate-\(m.id)"
            }
        }
        var title: String {
            switch self {
            case .remove: "Retirer du général ?"
            case .reinstate: "Réintégrer dans le général ?"
            }
        }
    }
    @State private var pending: PendingAction?

    private var isAdmin: Bool { workspace.members.first { $0.id == workspace.scope.accountID }?.isGroupAdmin ?? false }

    var body: some View {
        List {
            if let failure = workspace.actionError {
                Text(failure.localizedDescription).foregroundStyle(DrivyTheme.danger).accessibilityIdentifier("messaging.members.error")
            }
            ForEach(workspace.members) { member in
                Button { profile = member } label: {
                    HStack(spacing: 12) {
                        DrivyAvatar(name: member.displayName, size: 40, photo: workspace.photos[member.id])
                        Text(member.displayName).foregroundStyle(DrivyTheme.text)
                        Spacer()
                        if member.isGroupAdmin {
                            Text("Admin").font(.caption).foregroundStyle(DrivyTheme.muted)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(member.isGroupAdmin ? "\(member.displayName), administrateur du groupe" : member.displayName)
                .accessibilityHint("Ouvre le profil")
                .task { if member.hasPhoto { await workspace.loadPhoto(member.id) } }
                .swipeActions {
                    if isAdmin && member.id != workspace.scope.accountID {
                        Button("Retirer", role: .destructive) { pending = .remove(member) }
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
                        Button("Retirer du général", systemImage: "person.badge.minus", role: .destructive) { pending = .remove(member) }
                    }
                }
            }
            if isAdmin && !workspace.removedMembers.isEmpty {
                Section("Retirés") {
                    ForEach(workspace.removedMembers) { member in
                        HStack(spacing: 12) {
                            DrivyAvatar(name: member.displayName, size: 40, photo: workspace.photos[member.id])
                            Text(member.displayName).foregroundStyle(DrivyTheme.muted)
                            Spacer()
                            Button("Réintégrer") { pending = .reinstate(member) }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Réintégrer \(member.displayName)")
                                .accessibilityIdentifier("messaging.members.reinstate")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("\(member.displayName), retiré du général")
                        .task { if member.hasPhoto { await workspace.loadPhoto(member.id) } }
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
        .confirmationDialog(pending?.title ?? "", isPresented: Binding(get: { pending != nil },
                                                                       set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible,
                            presenting: pending) { action in
            switch action {
            case .remove(let member):
                Button("Retirer \(member.displayName)", role: .destructive) {
                    Task { await workspace.removeMember(member.id) }
                }
                .accessibilityIdentifier("messaging.members.confirmRemove")
            case .reinstate(let member):
                Button("Réintégrer \(member.displayName)") {
                    Task { await workspace.reinstateMember(member.id) }
                }
                .accessibilityIdentifier("messaging.members.confirmReinstate")
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
                if member.isGroupAdmin { Text("Administrateur du groupe").foregroundStyle(DrivyTheme.muted) }
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
                HStack(spacing: DrivySpacing.s) {
                    RoundedRectangle(cornerRadius: 1.5).fill(DrivyTheme.accent).frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DrivySpacing.xxs) {
                            Image(systemName: "pin.fill").accessibilityHidden(true)
                            Text(pinned.count > 1 ? "Épinglé \(min(index, pinned.count - 1) + 1)/\(pinned.count)" : "Épinglé")
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.accent)
                        Text(workspace.contents[current.id]?.summary ?? "Message épinglé")
                            .lineLimit(1).font(.subheadline).foregroundStyle(DrivyTheme.text)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DrivySpacing.m).padding(.vertical, DrivySpacing.xs)
                .frame(maxWidth: .infinity, minHeight: DrivyLayout.tapTarget)
                .background(DrivyTheme.surface)
                .overlay(alignment: .bottom) { Rectangle().fill(DrivyTheme.border).frame(height: 0.5) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Message épinglé : \(workspace.contents[current.id]?.summary ?? "")")
            .accessibilityHint(pinned.count > 1 ? "Affiche le message, puis le suivant au prochain appui" : "Affiche le message")
            .accessibilityIdentifier("messaging.pinned")
        }
    }
}

/// Forme d'une bulle : coins arrondis, coin côté auteur resserré sur le dernier message d'un groupe.
/// L'émis et le reçu se distinguent par l'alignement et ce coin, pas seulement par la couleur.
struct MessagingBubbleShape: Shape {
    let mine: Bool
    let tail: Bool

    func path(in rect: CGRect) -> Path {
        let large: CGFloat = 18
        let small: CGFloat = tail ? 4 : 18
        let radii = RectangleCornerRadii(topLeading: large,
                                         bottomLeading: mine ? large : small,
                                         bottomTrailing: mine ? small : large,
                                         topTrailing: large)
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: rect)
    }
}

/// Bulle d'un message : citation, contenu ou sondage, réactions, accusés de lecture.
struct MessagingBubble: View {
    let workspace: MessagingWorkspace
    let message: MessagingWireMessage
    let isGeneral: Bool
    var selecting = false
    var selected = false
    /// Premier message d'un groupe : l'auteur s'affiche (général seulement).
    var showsAuthor = true
    /// Dernier message d'un groupe : heure et accusés s'affichent.
    var showsMeta = true
    /// Mise en évidence brève après une citation, une épingle ou une recherche.
    var highlighted = false
    let onReply: () -> Void
    let onJump: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var content: MessagingPlainContent?
    @State private var loaded = false
    /// Un seul dialogue par bulle : deux `confirmationDialog` sur la même vue se neutralisent.
    private enum BubbleDialog { case deleteEveryone, react }
    @State private var dialog: BubbleDialog?
    @State private var votersFor: MessagingPollState?

    private var mine: Bool { message.senderID == workspace.scope.accountID }
    private var access: MessagingConversationAccess { workspace.access(for: message.conversationID) }
    private var canInteract: Bool { !message.meta.deletedForEveryone && access.canWrite && !selecting }

    var body: some View {
        HStack(alignment: .bottom, spacing: DrivySpacing.xs) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? DrivyTheme.accent : DrivyTheme.muted)
                    .font(.title3)
                    .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
                    .accessibilityHidden(true)
            }
            if mine { Spacer(minLength: 56) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                if isGeneral && !mine && showsAuthor {
                    Text(workspace.displayName(message.senderID))
                        .font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                        .padding(.horizontal, DrivySpacing.s)
                }
                bubble
                    .contextMenu { if !selecting { menu } }
                if !message.meta.reactions.isEmpty { reactions.padding(.top, -6).padding(.horizontal, DrivySpacing.xs) }
                if showsMeta || message.meta.pinned { meta.padding(.horizontal, DrivySpacing.xs) }
            }
            if !mine { Spacer(minLength: 56) }
        }
        .padding(.vertical, 2)
        .background(highlighted ? DrivyTheme.accentSoft : Color.clear,
                    in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
        .animation(DrivyMotion.settle(reduceMotion), value: highlighted)
        .task(id: message.id) {
            if !message.meta.deletedForEveryone { content = await workspace.content(for: message) }
            loaded = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messaging.message")
        .accessibilityActions {
            if canInteract {
                Button("Répondre", action: onReply)
                Button("Réagir") { dialog = .react }
            }
            if let text = content?.text, !message.meta.deletedForEveryone, !selecting {
                Button("Copier") { UIPasteboard.general.string = text }
            }
            if canInteract {
                Button(message.meta.pinned ? "Désépingler" : "Épingler") {
                    Task { await workspace.setPinned(message, pinned: !message.meta.pinned) }
                }
            }
        }
        .confirmationDialog(dialog == .react ? "Réagir" : "Supprimer pour tout le monde ?",
                            isPresented: Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } })) {
            if dialog == .react {
                ForEach(MessagingReactionPalette.all, id: \.self) { emoji in
                    Button("\(emoji) \(MessagingReactionPalette.label(emoji))") {
                        react(emoji)
                    }
                }
            } else {
                Button("Supprimer pour tout le monde", role: .destructive) {
                    Task { await workspace.delete(message, for: .everyone) }
                }
            }
        }
        .sheet(item: Binding(get: { votersFor.map { MessagingPollVotersSheet.Item(poll: $0) } },
                             set: { if $0 == nil { votersFor = nil } })) { item in
            MessagingPollVotersSheet(workspace: workspace, poll: item.poll, content: content?.poll)
        }
    }

    @ViewBuilder private var bubble: some View {
        let shape = MessagingBubbleShape(mine: mine, tail: showsMeta)
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            if let replyID = message.meta.replyToMessageID { quote(replyID) }
            if message.meta.deletedForEveryone {
                Label("Message supprimé", systemImage: "nosign").italic().foregroundStyle(DrivyTheme.muted)
                    .accessibilityIdentifier("messaging.deleted")
            } else if let poll = content?.poll, let state = message.meta.poll {
                MessagingPollCard(workspace: workspace, message: message, poll: poll, state: state,
                                  onShowVoters: { votersFor = state })
                    .frame(minWidth: 220)
            } else if let text = content?.text {
                Text(text).foregroundStyle(DrivyTheme.text).textSelection(.enabled)
            } else if loaded, let code = workspace.decryptionCodes[message.id] {
                Label("Illisible sur cet appareil · \(code)", systemImage: "lock").foregroundStyle(DrivyTheme.muted)
                    .accessibilityIdentifier("messaging.undecryptable")
            } else if loaded {
                Label("Message protégé indisponible", systemImage: "lock").foregroundStyle(DrivyTheme.muted)
            } else {
                ProgressView().accessibilityLabel("Déchiffrement")
            }
        }
        .padding(.horizontal, DrivySpacing.s).padding(.vertical, DrivySpacing.xs)
        .background(mine ? DrivyTheme.accentSoft : DrivyTheme.surfaceRaised, in: shape)
        .overlay(shape.stroke(mine ? Color.clear : DrivyTheme.border, lineWidth: 0.5))
        .contentShape(.contextMenuPreview, shape)
    }

    private var meta: some View {
        HStack(spacing: DrivySpacing.xxs) {
            if message.meta.pinned {
                Image(systemName: "pin.fill").accessibilityLabel("Épinglé")
            }
            if showsMeta {
                Text(message.acceptedAt, style: .time)
                if mine, !message.meta.deletedForEveryone { receipt }
            }
        }
        .font(.caption2).foregroundStyle(DrivyTheme.textTertiary)
    }

    private func quote(_ id: UUID) -> some View {
        let quoted = workspace.message(id, in: message.conversationID)
        let summary: String = {
            guard let quoted else { return "Message indisponible" }
            if quoted.meta.deletedForEveryone { return "Message supprimé" }
            return workspace.contents[id]?.summary ?? "Message"
        }()
        return Button { onJump(id) } label: {
            HStack(spacing: DrivySpacing.xs) {
                RoundedRectangle(cornerRadius: 1.5).fill(DrivyTheme.accent).frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    if let quoted {
                        Text(workspace.displayName(quoted.senderID)).font(.caption.bold()).foregroundStyle(DrivyTheme.accent)
                    }
                    Text(summary).font(.caption).lineLimit(2).foregroundStyle(DrivyTheme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(DrivySpacing.xs)
            .background(DrivyTheme.surfaceMuted.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("En réponse à : \(summary)")
        .accessibilityHint("Affiche le message cité")
    }

    /// Agrégats collés sous la bulle : emoji et nombre, ma réaction cernée d'accent.
    private var reactions: some View {
        HStack(spacing: DrivySpacing.xxs) {
            ForEach(message.meta.reactions, id: \.emoji) { reaction in
                let reacted = reaction.personIDs.contains(workspace.scope.accountID)
                Button { Task { await workspace.toggleReaction(reaction.emoji, on: message) } } label: {
                    HStack(spacing: 3) {
                        Text(reaction.emoji)
                        Text(reaction.personIDs.count.formatted())
                            .font(.caption.weight(reacted ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(reacted ? DrivyTheme.accent : DrivyTheme.muted)
                    }
                    .font(.caption)
                    .padding(.horizontal, DrivySpacing.xs).padding(.vertical, 3)
                    .background(reacted ? DrivyTheme.accentSoft : DrivyTheme.surfaceRaised, in: Capsule())
                    .overlay(Capsule().stroke(reacted ? DrivyTheme.accent : DrivyTheme.border, lineWidth: reacted ? 1.5 : 0.5))
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!access.canWrite)
                .accessibilityLabel("\(MessagingReactionPalette.label(reaction.emoji)), \(reaction.personIDs.count)"
                    + (reacted ? ", vous avez réagi" : ""))
                .accessibilityAddTraits(reacted ? [.isSelected] : [])
                .accessibilityHint(reaction.personIDs.map(workspace.displayName).joined(separator: ", "))
            }
        }
    }

    @ViewBuilder private var receipt: some View {
        let readers = workspace.readers(of: message)
        if !readers.isEmpty {
            let label = isGeneral ? "· Lu par \(readers.count)" : "· Lu"
            Text(label)
                .accessibilityLabel(isGeneral ? "Lu par \(readers.map(workspace.displayName).joined(separator: ", "))" : "Lu")
                .accessibilityIdentifier("messaging.read")
        }
    }

    /// Ne bloque jamais l'action d'un menu : la requête part après la fermeture.
    private func react(_ emoji: String) {
        let workspace = workspace, message = message
        Task { @MainActor in
            // Laisse l'aperçu se refermer avant que la relecture du fil ne change sa mise en page.
            try? await Task.sleep(for: .milliseconds(350))
            await workspace.toggleReaction(emoji, on: message)
        }
    }

    @ViewBuilder private var menu: some View {
        if !message.meta.deletedForEveryone && access.canWrite {
            // #102 : réactions rapides en tête du menu. L'action lance une tâche détachée et rend la main
            // aussitôt, le menu et l'aperçu se ferment sans attendre le serveur ; un échec s'affiche
            // dans la conversation (actionError) sans rouvrir le menu ni déplacer le fil.
            ControlGroup {
                ForEach(MessagingReactionPalette.all, id: \.self) { emoji in
                    let reacted = message.meta.reactions.first { $0.emoji == emoji }?
                        .personIDs.contains(workspace.scope.accountID) ?? false
                    Button {
                        react(emoji)
                    } label: {
                        Text(emoji)
                    }
                    .accessibilityLabel(MessagingReactionPalette.label(emoji) + (reacted ? ", vous avez réagi" : ""))
                }
            }
            .controlGroupStyle(.palette)
            Button("Répondre", systemImage: "arrowshape.turn.up.left", action: onReply)
            Button(message.meta.pinned ? "Désépingler" : "Épingler", systemImage: message.meta.pinned ? "pin.slash" : "pin") {
                Task { await workspace.setPinned(message, pinned: !message.meta.pinned) }
            }
        }
        if let text = content?.text, !message.meta.deletedForEveryone {
            Button("Copier", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
        }
        Divider()
        Button("Supprimer pour moi", systemImage: "trash", role: .destructive) {
            Task { await workspace.delete(message, for: .me) }
        }
        if !message.meta.deletedForEveryone,
           MessagingPermissions.canDeleteForEveryone(senderID: message.senderID, account: workspace.scope.accountID, access: access) {
            Button("Supprimer pour tout le monde", systemImage: "trash.slash", role: .destructive) { dialog = .deleteEveryone }
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
                .font(.caption).foregroundStyle(DrivyTheme.muted)
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
                                .foregroundStyle(chosen ? DrivyTheme.accent : DrivyTheme.muted)
                            Text(option.label).foregroundStyle(DrivyTheme.text)
                            Spacer()
                            Text(votes.formatted()).foregroundStyle(DrivyTheme.muted)
                        }
                        ProgressView(value: total == 0 ? 0 : Double(votes) / Double(total))
                            .tint(chosen ? DrivyTheme.accent : DrivyTheme.rail)
                            .accessibilityHidden(true)
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
                        Text("Aucun vote").foregroundStyle(DrivyTheme.muted)
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

/// Recherche locale dans l'historique déchiffré stocké sur l'appareil, limitée à cette conversation.
struct MessagingSearchView: View {
    let workspace: MessagingWorkspace
    let conversationID: UUID
    var conversationTitle: String? = nil
    let onSelect: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MessagingHistoryEntry] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(results) { entry in
                        Button { onSelect(entry.messageID); dismiss() } label: {
                            HStack(alignment: .top, spacing: DrivySpacing.s) {
                                DrivyAvatar(name: workspace.displayName(entry.senderID), size: 32, photo: workspace.photos[entry.senderID])
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(workspace.displayName(entry.senderID)).font(.subheadline.weight(.semibold))
                                            .foregroundStyle(DrivyTheme.text)
                                        Spacer()
                                        Text(entry.acceptedAt, format: .dateTime.day().month().hour().minute())
                                            .font(.caption).foregroundStyle(DrivyTheme.muted)
                                    }
                                    Text(entry.content.summary).font(.subheadline).lineLimit(3).foregroundStyle(DrivyTheme.text)
                                }
                            }
                            .padding(.vertical, DrivySpacing.xxs)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text(conversationTitle.map { "Dans « \($0) »" } ?? "Dans cette conversation")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .overlay {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty && results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher dans cette conversation")
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
