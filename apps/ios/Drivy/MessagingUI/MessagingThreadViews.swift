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
    /// Recherche par nom dans les membres déjà autorisés (#171), sans casse ni accents ; rien d’autre n’est lu.
    @State private var query = ""

    private var isAdmin: Bool { workspace.members.first { $0.id == workspace.scope.accountID }?.isGroupAdmin ?? false }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func matches(_ member: MessagingMember) -> Bool {
        trimmedQuery.isEmpty || member.displayName.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
    private var shownMembers: [MessagingMember] { workspace.members.filter(matches) }
    private var shownRemoved: [MessagingMember] { isAdmin ? workspace.removedMembers.filter(matches) : [] }
    /// Repères des homonymes, la fin de l’identifiant : un appui agit toujours sur la bonne personne.
    private var references: [UUID: String] {
        HomonymReference.references((workspace.members + workspace.removedMembers).map { ($0.id, $0.displayName) })
    }
    /// La liste est lue en entier : le total est exact.
    private var countLabel: String {
        let total = workspace.members.count
        let noun = total == 1 ? "membre" : "membres"
        return trimmedQuery.isEmpty ? "\(total) \(noun)" : "\(shownMembers.count) sur \(total) \(noun)"
    }

    var body: some View {
        let homonyms = references
        List {
            if let failure = workspace.actionError {
                Text(failure.localizedDescription).foregroundStyle(DrivyTheme.danger).accessibilityIdentifier("messaging.members.error")
            }
            if !trimmedQuery.isEmpty && shownMembers.isEmpty && shownRemoved.isEmpty {
                DrivyEmptyState(title: "Aucun résultat", symbol: "magnifyingglass",
                    actionTitle: "Effacer la recherche", action: { query = "" })
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("messaging.members.noResult")
            }
            Section {
                ForEach(shownMembers) { member in
                    Button { profile = member } label: {
                        HStack(spacing: 12) {
                            DrivyAvatar(name: member.displayName, size: 40, photo: workspace.photos[member.id])
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.displayName).foregroundStyle(DrivyTheme.text)
                                if let reference = homonyms[member.id] {
                                    Text("Réf. \(reference)").font(.caption).foregroundStyle(DrivyTheme.muted)
                                }
                            }
                            Spacer()
                            if workspace.isInProgress(MessagingWorkspace.memberOperation(member.id)) {
                                Text("En cours").font(.caption).foregroundStyle(DrivyTheme.muted)
                                    .accessibilityIdentifier("messaging.members.inProgress")
                            } else if member.isGroupAdmin {
                                Text("Admin").font(.caption).foregroundStyle(DrivyTheme.muted)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel([member.displayName, homonyms[member.id].map { "Réf. \($0)" },
                                         member.isGroupAdmin ? "administrateur du groupe" : nil].compactMap { $0 }.joined(separator: ", "))
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
            } header: {
                Text(countLabel).accessibilityIdentifier("messaging.members.count")
            }
            if !shownRemoved.isEmpty {
                Section("Retirés") {
                    ForEach(shownRemoved) { member in
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
        .searchable(text: $query, prompt: "Rechercher un membre")
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
                // Une seule ligne compacte, flottante, sans bloc pleine largeur (retour du porteur).
                HStack(spacing: DrivySpacing.xs) {
                    Image(systemName: "pin.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DrivyTheme.accent)
                        .accessibilityHidden(true)
                    Text(workspace.contents[current.id]?.summary ?? "Message épinglé")
                        .lineLimit(1).font(.footnote).foregroundStyle(DrivyTheme.text)
                    if pinned.count > 1 {
                        Text("\(min(index, pinned.count - 1) + 1)/\(pinned.count)")
                            .font(.caption2.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                    }
                }
                .padding(.horizontal, DrivySpacing.s).padding(.vertical, 6)
                .background(DrivyTheme.surfaceRaised, in: Capsule())
                .overlay(Capsule().stroke(DrivyTheme.border, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .frame(maxWidth: 320)
                .padding(.top, DrivySpacing.xxs)
                .frame(minHeight: DrivyLayout.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Message épinglé : \(workspace.contents[current.id]?.summary ?? "")")
            .accessibilityHint(pinned.count > 1 ? "Affiche le message, puis le suivant au prochain appui" : "Affiche le message")
            .accessibilityIdentifier("messaging.pinned")
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
    /// La confirmation est présentée par la conversation, pas depuis la cellule de la liste.
    let onClose: () -> Void

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
            if workspace.mutation(.vote, on: message).map({ $0.status != .confirmed }) == true {
                // Totaux provisoires : jamais présentés comme confirmés.
                Text("Vote en cours d'enregistrement").font(.caption2).foregroundStyle(DrivyTheme.textTertiary)
                    .accessibilityIdentifier("messaging.poll.pending")
            }
            ForEach(poll.options, id: \.id) { option in
                let votes = state.options.first { $0.optionID == option.id }?.voterIDs.count ?? 0
                let chosen = myVotes.contains(option.id)
                Button {
                    let next = MessagingPollRules.toggled(myVotes, option: option.id, allowsMultiple: state.allowsMultiple)
                    workspace.vote(message, optionIDs: next)
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
                    // #142 : toute la ligne est touchable, sur au moins 44 pt.
                    .frame(minHeight: DrivyLayout.tapTarget)
                    .contentShape(Rectangle())
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
                    .frame(minHeight: DrivyLayout.tapTarget)
                Spacer()
                if workspace.isInProgress(MessagingWorkspace.pollCloseOperation(message.id)) {
                    Text("Clôture en cours").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        .accessibilityIdentifier("messaging.poll.closing")
                } else if MessagingPermissions.canClosePoll(state, account: workspace.scope.accountID, access: access) {
                    Button("Clore", role: .destructive, action: onClose).font(.subheadline)
                        .frame(minWidth: DrivyLayout.tapTarget, minHeight: DrivyLayout.tapTarget)
                }
            }
        }
        .accessibilityIdentifier("messaging.poll")
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
    /// La recherche dont `results` est la réponse : « Aucun résultat » n’est dit qu’une fois elle terminée.
    @State private var searchedQuery: String?

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
                        .accessibilityIdentifier("messaging.search.result")
                    }
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty && results.isEmpty && searchedQuery == query {
                        DrivyEmptyState(title: "Aucun résultat", symbol: "magnifyingglass",
                            actionTitle: "Effacer la recherche", action: { query = "" })
                            .buttonStyle(.borderless)
                    }
                } header: {
                    Text(conversationTitle.map { "Dans « \($0) »" } ?? "Dans cette conversation")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher dans cette conversation")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let found = await workspace.search(query, conversationID: conversationID)
                guard !Task.isCancelled else { return }
                results = found
                searchedQuery = query
            }
            .navigationTitle("Rechercher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Fermer") { dismiss() } }
            .accessibilityIdentifier("messaging.search")
        }
    }
}
