import ExyteChat
import SwiftUI

/// Préférence locale de comparaison (#182) : le fil Exyte et le fil actuel lisent le même workspace et la même
/// file d'envoi ; un seul des deux est affiché, aucun ne double une action.
enum MessagingThreadRenderer {
    static let exyteKey = "messaging.thread.exyte"
}

/// Actions du menu Exyte, calculées par message à partir des droits Drivy puis revérifiées à l'exécution.
/// Aucune n'est marquée destructive : l'alerte interne d'Exyte n'est pas traduite, la confirmation reste Drivy.
enum MessagingExyteMenuAction: String, CaseIterable, MessageMenuAction, Sendable {
    case reply, pin, unpin, copy, deleteForMe, deleteForEveryone

    static let customDataKey = "drivy.menu"

    func title() -> String {
        switch self {
        case .reply: "Répondre"
        case .pin: "Épingler"
        case .unpin: "Désépingler"
        case .copy: "Copier"
        case .deleteForMe: "Supprimer pour moi"
        case .deleteForEveryone: "Supprimer pour tous"
        }
    }

    func icon() -> Image {
        switch self {
        case .reply: Image(systemName: "arrowshape.turn.up.left")
        case .pin: Image(systemName: "pin")
        case .unpin: Image(systemName: "pin.slash")
        case .copy: Image(systemName: "doc.on.doc")
        case .deleteForMe: Image(systemName: "trash")
        case .deleteForEveryone: Image(systemName: "trash.slash")
        }
    }

    static func menuItems(for message: ExyteChat.Message) -> [MessagingExyteMenuAction] {
        message.customData[customDataKey] as? [MessagingExyteMenuAction] ?? []
    }
}

/// État de présentation du fil Exyte. Les builders d'Exyte sont capturés une fois par la liste : ils ne lisent
/// que ce modèle et le workspace, jamais une valeur figée au premier rendu.
@MainActor
@Observable final class MessagingExyteThreadModel {
    let workspace: MessagingWorkspace
    let composer: MessagingComposerModel
    let conversationID: UUID
    let isGeneral: Bool
    /// Mise en évidence brève après une citation, une épingle ou une recherche (identifiant serveur).
    private(set) var highlighted: UUID?
    var reporting = false
    var reportSelection: Set<UUID> = []
    private(set) var atBottom = true
    var unseenBelow = false
    private(set) var scrollRequest: ScrollToParams?
    private(set) var notice: String?
    var confirmDeleteForEveryone: MessagingWireMessage?
    var showPollComposer = false
    private(set) var loadingOlder = false

    init(workspace: MessagingWorkspace, composer: MessagingComposerModel, conversationID: UUID, isGeneral: Bool) {
        self.workspace = workspace
        self.composer = composer
        self.conversationID = conversationID
        self.isGeneral = isGeneral
    }

    private var access: MessagingConversationAccess { workspace.access(for: conversationID) }

    var items: [MessagingThreadItem] {
        MessagingThreadProjection.items(messages: workspace.visibleMessages(conversationID),
            pending: composer.visibleQueue, accountID: workspace.scope.accountID,
            clientIDs: MessagingThreadProjection.clientIDs(workspace.sendStates),
            pendingDates: composer.queuedDates, now: Date())
    }

    func item(_ displayID: String) -> MessagingThreadItem? { items.first { $0.id == displayID } }

    func displayID(for messageID: UUID) -> String? { items.first { $0.message?.id == messageID }?.id }

    // MARK: Modèle Exyte

    /// Seuls l'identité, l'auteur, la date et l'état d'envoi passent à Exyte : la bulle reste dessinée par Drivy,
    /// et aucun contenu déchiffré n'est confié à la bibliothèque.
    func exyteMessage(_ item: MessagingThreadItem) -> ExyteChat.Message {
        let accountID = workspace.scope.accountID
        let user = ExyteChat.User(id: item.senderID.uuidString, name: workspace.displayName(item.senderID),
                                  avatarURL: nil, isCurrentUser: item.senderID == accountID)
        let actions = menuActions(item)
        var message = ExyteChat.Message(id: item.id, user: user, status: status(item), createdAt: item.date,
                                        customData: [MessagingExyteMenuAction.customDataKey: actions])
        // L'égalité d'Exyte ignore `customData` : une révision déterministe force la reconfiguration de la cellule
        // quand ses actions ou sa mise en page changent, sans changer d'identité.
        var hasher = Hasher()
        hasher.combine(actions)
        hasher.combine(reporting)
        hasher.combine(item.startsGroup)
        hasher.combine(item.endsGroup)
        if let wire = item.message {
            hasher.combine(wire.meta.deletedForEveryone)
            hasher.combine(wire.meta.pinned)
            hasher.combine(workspace.contents[wire.id] != nil)
            hasher.combine(workspace.decryptionCodes[wire.id])
        }
        message.triggerRedraw = Self.revision(hasher.finalize())
        return message
    }

    private func status(_ item: MessagingThreadItem) -> ExyteChat.Message.Status? {
        if item.pending != nil { return .sending }
        guard let wire = item.message, wire.senderID == workspace.scope.accountID else { return nil }
        let readers = workspace.readers(of: wire)
        return readers.isEmpty ? .sent : .readBy(readers.map(\.uuidString))
    }

    private func menuActions(_ item: MessagingThreadItem) -> [MessagingExyteMenuAction] {
        guard !reporting else { return [] }
        guard let wire = item.message else { return pendingText(item) == nil ? [] : [.copy] }
        var actions: [MessagingExyteMenuAction] = []
        if !wire.meta.deletedForEveryone && access.canWrite {
            actions += [.reply, wire.meta.pinned ? .unpin : .pin]
        }
        if !wire.meta.deletedForEveryone, workspace.contents[wire.id]?.text != nil { actions.append(.copy) }
        actions.append(.deleteForMe)
        if !wire.meta.deletedForEveryone,
           MessagingPermissions.canDeleteForEveryone(senderID: wire.senderID, account: workspace.scope.accountID, access: access) {
            actions.append(.deleteForEveryone)
        }
        return actions
    }

    private func pendingText(_ item: MessagingThreadItem) -> String? {
        item.pending?.recoveryContent.flatMap(MessagingPlainContent.decode)?.text
    }

    private static func revision(_ value: Int) -> UUID? {
        let hex = String(UInt64(bitPattern: Int64(value)), radix: 16)
        let padded = String(repeating: "0", count: 16 - hex.count) + hex
        return UUID(uuidString: "00000000-0000-0000-\(padded.prefix(4))-\(padded.dropFirst(4))")
    }

    // MARK: Actions

    private func canInteract(_ message: MessagingWireMessage) -> Bool {
        !message.meta.deletedForEveryone && access.canWrite && !reporting
    }

    /// Les droits sont relus au moment de l'action : un menu resté ouvert n'élargit jamais l'accès.
    func perform(_ action: MessagingExyteMenuAction, displayID: String) {
        guard let item = item(displayID) else { return }
        switch action {
        case .copy:
            if let wire = item.message {
                guard !wire.meta.deletedForEveryone, let text = workspace.contents[wire.id]?.text else { return }
                UIPasteboard.general.string = text
            } else if let text = pendingText(item) {
                UIPasteboard.general.string = text
            }
        case .reply:
            guard let wire = item.message, canInteract(wire) else { return }
            composer.reply(to: wire)
        case .pin, .unpin:
            guard let wire = item.message, canInteract(wire) else { return }
            workspace.setPinned(wire, pinned: action == .pin)
        case .deleteForMe:
            guard let wire = item.message else { return }
            workspace.delete(wire, for: .me)
        case .deleteForEveryone:
            guard let wire = item.message, !wire.meta.deletedForEveryone,
                  MessagingPermissions.canDeleteForEveryone(senderID: wire.senderID, account: workspace.scope.accountID,
                                                             access: access) else { return }
            confirmDeleteForEveryone = wire
        }
    }

    func canReact(displayID: String) -> Bool {
        guard let wire = item(displayID)?.message else { return false }
        return canInteract(wire)
    }

    /// Exyte ferme le menu avant cet appel (#102) ; l'intention est posée sans attendre le réseau.
    func react(_ reaction: ReactionType, displayID: String) {
        guard case .emoji(let emoji) = reaction, MessagingReactionPalette.all.contains(emoji),
              let wire = item(displayID)?.message, canInteract(wire) else { return }
        let workspace = workspace
        Task { @MainActor in
            // Laisse l'aperçu se refermer avant que la réaction locale ne change la mise en page.
            try? await Task.sleep(for: .milliseconds(250))
            workspace.toggleReaction(emoji, on: wire)
        }
    }

    func toggleReport(_ id: UUID) {
        if reportSelection.contains(id) { reportSelection.remove(id) } else { reportSelection.insert(id) }
    }

    // MARK: Défilement

    /// Liste inversée : un décalage nul est le bas du fil.
    func offsetChanged(_ offset: CGFloat) {
        let bottom = offset < 48
        if bottom != atBottom { atBottom = bottom }
        if bottom && unseenBelow { unseenBelow = false }
    }

    func scrollToNewest() {
        unseenBelow = false
        request(ScrollToParams(.newestMessage))
    }

    /// La demande est retirée après sa prise en compte : la même cible peut être redemandée.
    private func request(_ params: ScrollToParams) {
        scrollRequest = params
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            if scrollRequest == params { scrollRequest = nil }
        }
    }

    /// Les anciens messages s'ajoutent au-dessus ; Exyte garde le premier message visible à sa place.
    func loadOlder() async {
        guard !loadingOlder, workspace.canLoadMoreMessages(conversationID) else { return }
        loadingOlder = true
        await workspace.loadMessages(conversationID, more: true)
        loadingOlder = false
    }

    /// Citation, épingle ou recherche : charge le contexte si besoin, puis met le message brièvement en évidence.
    func jump(to id: UUID) async {
        var pages = 0
        while displayID(for: id) == nil, workspace.canLoadMoreMessages(conversationID), pages < 10 {
            await workspace.loadMessages(conversationID, more: true)
            pages += 1
        }
        guard let target = displayID(for: id) else {
            await show(notice: "Message indisponible")
            return
        }
        // Laisse la feuille de recherche se refermer : un défilement lancé pendant sa disparition est perdu.
        try? await Task.sleep(for: .milliseconds(350))
        request(ScrollToParams(messageID: target, position: .middle))
        highlighted = id
        try? await Task.sleep(for: .milliseconds(1_500))
        if highlighted == id { highlighted = nil }
    }

    func show(notice text: String) async {
        notice = text
        AccessibilityNotification.Announcement(text).post()
        try? await Task.sleep(for: .seconds(3))
        if notice == text { notice = nil }
    }
}

/// Conversation présentée par Exyte Chat (#182) : liste inversée, pagination, menu et clavier d'Exyte ;
/// bulles, composeur, droits, E2EE, file protégée et états d'envoi restent ceux de Drivy.
struct MessagingExyteConversationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var thread: MessagingExyteThreadModel
    @State private var showSearch = false
    @State private var showMembers = false
    @State private var reportSent = false

    init(workspace: MessagingWorkspace, conversationID: UUID, title: String, detail: String?, lastSequence: Int,
         lastReadSequence: Int, mutedUntil: Date?, readStateVersion: Int, isGeneral: Bool) {
        self.workspace = workspace
        self.conversationID = conversationID
        self.title = title
        self.detail = detail
        self.lastSequence = lastSequence
        self.lastReadSequence = lastReadSequence
        self.mutedUntil = mutedUntil
        self.readStateVersion = readStateVersion
        self.isGeneral = isGeneral
        let composer = MessagingComposerModel(workspace: workspace, conversationID: conversationID)
        _thread = State(initialValue: MessagingExyteThreadModel(workspace: workspace, composer: composer,
                                                                conversationID: conversationID, isGeneral: isGeneral))
    }

    private var composer: MessagingComposerModel { thread.composer }

    var body: some View {
        VStack(spacing: 0) {
            MessagingConversationStatusStrip(workspace: workspace, conversationID: conversationID,
                                             detail: detail, mutedUntil: mutedUntil)
            chat
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        MessagingPinnedBanner(workspace: workspace, pinned: workspace.pinnedMessages(conversationID)) { id in
                            Task { await thread.jump(to: id) }
                        }
                        noticeView
                    }
                }
                .overlay(alignment: .bottomTrailing) { jumpToBottom }
        }
        .background(DrivyTheme.canvas.ignoresSafeArea())
        .toolbarBackground(DrivyTheme.canvas, for: .navigationBar)
        .navigationTitle(thread.reporting ? "Signaler" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .modifier(lifecycle)
        .sheet(isPresented: $thread.showPollComposer) {
            MessagingPollComposer { poll, multiple in
                await composer.send(MessagingPlainContent(poll: poll), pollAllowsMultiple: multiple)
            }
        }
        .sheet(isPresented: $showSearch) {
            // La feuille se ferme depuis ici : avec `.searchable` actif, `dismiss()` ne fermait que le champ.
            MessagingSearchView(workspace: workspace, conversationID: conversationID, conversationTitle: title) { id in
                showSearch = false
                Task { await thread.jump(to: id) }
            }
        }
        .navigationDestination(isPresented: $showMembers) { MessagingMembersView(workspace: workspace) }
        .alert("Signalement transmis", isPresented: $reportSent) { Button("OK") {} }
        .confirmationDialog("Supprimer pour tout le monde ?",
                            isPresented: Binding(get: { thread.confirmDeleteForEveryone != nil },
                                                 set: { if !$0 { thread.confirmDeleteForEveryone = nil } }),
                            titleVisibility: .visible, presenting: thread.confirmDeleteForEveryone) { message in
            Button("Supprimer pour tout le monde", role: .destructive) { workspace.delete(message, for: .everyone) }
        }
    }

    private var lifecycle: MessagingExyteLifecycle {
        MessagingExyteLifecycle(workspace: workspace, thread: thread, connectivity: connectivity,
                                conversationID: conversationID, scenePhase: scenePhase)
    }

    // MARK: Fil

    @ViewBuilder private var chat: some View {
        let thread = thread
        let pinned = !workspace.pinnedMessages(conversationID).isEmpty
        ChatView(messages: thread.items.map(thread.exyteMessage), chatType: .conversation, replyMode: .quote,
                 didSendMessage: { _ in },
                 messageBuilder: { params in MessagingExyteRow(thread: thread, displayID: params.message.id) },
                 inputViewBuilder: { _ in MessagingExyteFooter(thread: thread, onReported: { reportSent = true }) },
                 messageMenuAction: { (action: MessagingExyteMenuAction, _, message) in
                     thread.perform(action, displayID: message.id)
                 })
            .showDateHeaders(true)
            .dateHeaderBuilder { date in MessagingDaySeparator(date: date) }
            .mainHeaderBuilder { MessagingExyteOlderButton(thread: thread) }
            .enableLoadMoreOlderMessages(hasMoreToLoad: workspace.canLoadMoreMessages(conversationID),
                                         handleClosure: { await thread.loadOlder() },
                                         loadingIndicatorBuilder: { ProgressView().padding(DrivySpacing.s) })
            .showScrollToBottomButton(false)
            .showNetworkConnectionProblem(false)
            .showMessageMenuOnLongPress(!thread.reporting)
            .linkPreviewsEnabled(false)
            .setAvailableInputs([.text])
            .keyboardDismissMode(.interactive)
            .setMessageFont(UIFont.preferredFont(forTextStyle: .body))
            .messageMenuAnimationDuration(reduceMotion ? 0.1 : 0.25)
            .contentInsets(top: pinned ? DrivyLayout.tapTarget : 0)
            .onContentOffsetChange { thread.offsetChanged($0) }
            .scrollTo(thread.scrollRequest)
            .onMessageReaction(didReactTo: { message, draft in thread.react(draft.type, displayID: message.id) },
                               canReactTo: { thread.canReact(displayID: $0.id) },
                               availableReactionsFor: { _ in MessagingReactionPalette.all.map { ReactionType.emoji($0) } },
                               allowEmojiSearchFor: { _ in false },
                               shouldShowOverviewFor: { _ in false })
            .localization(.drivy)
            .chatTheme(.drivy)
    }

    @ViewBuilder private var noticeView: some View {
        if let notice = thread.notice {
            Label(notice, systemImage: "exclamationmark.bubble")
                .font(.footnote)
                .foregroundStyle(DrivyTheme.text)
                .padding(.horizontal, DrivySpacing.s).padding(.vertical, DrivySpacing.xs)
                .background(DrivyTheme.surfaceRaised, in: Capsule())
                .overlay(Capsule().stroke(DrivyTheme.border))
                .padding(.top, DrivySpacing.xs)
                .transition(.opacity)
                .accessibilityIdentifier("messaging.notice")
        }
    }

    @ViewBuilder private var jumpToBottom: some View {
        if !thread.atBottom {
            let unseen = thread.unseenBelow
            Button { thread.scrollToNewest() } label: {
                HStack(spacing: DrivySpacing.xxs) {
                    Image(systemName: "arrow.down")
                    if unseen { Text("Nouveaux messages").font(.footnote.weight(.semibold)) }
                }
                .foregroundStyle(unseen ? DrivyTheme.onAccent : DrivyTheme.accent)
                .padding(.horizontal, unseen ? DrivySpacing.s : 0)
                .frame(minWidth: DrivyLayout.tapTarget, minHeight: DrivyLayout.tapTarget)
                .background(unseen ? AnyShapeStyle(DrivyTheme.accentFill) : AnyShapeStyle(DrivyTheme.surfaceRaised), in: Capsule())
                .overlay(Capsule().stroke(DrivyTheme.border, lineWidth: unseen ? 0 : 1))
                .shadow(color: DrivyTheme.shadow.opacity(0.12), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DrivySpacing.m)
            // Au-dessus du composeur, qu'Exyte place sous la liste.
            .padding(.bottom, DrivyLayout.tapTarget + DrivySpacing.l)
            .accessibilityLabel(unseen ? "Nouveaux messages, revenir en bas" : "Revenir en bas")
            .accessibilityIdentifier("messaging.scroll.bottom")
            .transition(.opacity)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Rechercher", systemImage: "magnifyingglass") { showSearch = true }
                .accessibilityIdentifier("messaging.search.open")
            Menu("Options", systemImage: "ellipsis.circle") {
                if isGeneral { Button("Membres", systemImage: "person.3") { showMembers = true } }
                Button("Signaler des messages", systemImage: "exclamationmark.bubble") { thread.reporting = true }
                Divider()
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
}

/// Cycle de vie de la conversation : chargement, brouillon protégé, lecture réelle, reprise et contexte actif.
private struct MessagingExyteLifecycle: ViewModifier {
    let workspace: MessagingWorkspace
    let thread: MessagingExyteThreadModel
    let connectivity: MessagingConnectivity
    let conversationID: UUID
    let scenePhase: ScenePhase

    private var composer: MessagingComposerModel { thread.composer }
    /// Dernier message reçu (hors envois locaux), pour décider du suivi du bas.
    private var lastDelivered: MessagingWireMessage? { workspace.visibleMessages(conversationID).last }

    func body(content: Content) -> some View {
        content
            // Lecture : application active ET bas du fil affiché, jamais la seule préparation d'une cellule.
            .task(id: scenePhase == .active && thread.atBottom ? workspace.lastReadableSequence(conversationID) : nil) {
                if scenePhase == .active, thread.atBottom, let seq = workspace.lastReadableSequence(conversationID) {
                    await workspace.conversationViewed(conversationID, upTo: seq)
                }
            }
            // Après la mise à jour de la vue : une bascule de rendu ne voit pas son contexte effacé par l'ancien fil.
            .task(id: thread.atBottom) {
                MessagingActiveConversation.set(schoolID: workspace.scope.schoolID, conversationID: conversationID,
                                                atBottom: thread.atBottom)
            }
            .onAppear { connectivity.start() }
            .onDisappear { connectivity.stop(); MessagingActiveConversation.clear(conversationID) }
            .onChange(of: lastDelivered?.id) { _, _ in
                guard let last = lastDelivered else { return }
                if last.senderID == workspace.scope.accountID {
                    if !thread.atBottom { thread.scrollToNewest() }
                } else if !thread.atBottom {
                    thread.unseenBelow = true
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await workspace.refreshVisible(conversationID: conversationID) } }
            }
            .onChange(of: connectivity.available) { _, available in
                workspace.setNetworkAvailable(available)
                if available { Task { await workspace.refreshVisible(conversationID: conversationID) } }
            }
            .onChange(of: workspace.error) { _, failure in
                if failure == .contextChanged || failure == .accessChanged { composer.reset() }
            }
            .onChange(of: workspace.resumeGeneration) { _, _ in Task { await composer.resume() } }
            .task {
                if thread.isGeneral { await workspace.loadGeneralMembers(); await workspace.loadMembers() }
                if !workspace.hasLoadedMessages(conversationID) { await workspace.loadMessages(conversationID) }
                await composer.load()
            }
            .task(id: composer.draft) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await composer.persistDraft()
            }
    }
}

/// Ligne du fil : la bulle Drivy (contenu, sondage, réactions, accusés, états de synchronisation) dans la cellule Exyte.
private struct MessagingExyteRow: View {
    let thread: MessagingExyteThreadModel
    let displayID: String

    var body: some View {
        if let item = thread.item(displayID) {
            content(item)
                .padding(.top, item.startsGroup ? DrivySpacing.xs : 2)
                .padding(.horizontal, DrivySpacing.s)
                .frame(maxWidth: DrivyLayout.readingColumn)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func content(_ item: MessagingThreadItem) -> some View {
        switch item.source {
        case .message(let message):
            let bubble = MessagingBubble(workspace: thread.workspace, message: message, isGeneral: thread.isGeneral,
                selecting: thread.reporting, selected: thread.reportSelection.contains(message.id),
                showsAuthor: item.startsGroup, showsMeta: item.endsGroup, highlighted: thread.highlighted == message.id,
                showsNativeMenu: false,
                onReply: { thread.composer.reply(to: message) },
                onJump: { id in Task { await thread.jump(to: id) } })
            if thread.reporting && !message.meta.deletedForEveryone {
                Button { thread.toggleReport(message.id) } label: { bubble }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(thread.reportSelection.contains(message.id) ? [.isSelected] : [])
                    .accessibilityHint("Sélectionne ce message pour le signalement")
            } else {
                bubble
            }
        case .pending(let entry):
            MessagingPendingBubble(entry: entry, status: thread.workspace.sendStatus(entry.clientMessageID)) {
                thread.composer.retry(entry)
            }
            .padding(.top, 2)
        }
    }
}

/// Bouton explicite, accessible, en tête du fil : la pagination automatique d'Exyte reste un raccourci.
private struct MessagingExyteOlderButton: View {
    let thread: MessagingExyteThreadModel

    var body: some View {
        if thread.workspace.canLoadMoreMessages(thread.conversationID) {
            Button {
                Task { await thread.loadOlder() }
            } label: {
                HStack(spacing: DrivySpacing.xs) {
                    if thread.loadingOlder { ProgressView().controlSize(.small) }
                    Text("Charger les messages précédents")
                }
                .font(.subheadline)
                .frame(minHeight: DrivyLayout.tapTarget)
                .padding(.horizontal, DrivySpacing.m)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DrivyTheme.accent)
            .disabled(thread.loadingOlder)
            .padding(.vertical, DrivySpacing.xs)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Pied du fil : composeur Drivy, barre de signalement ou lecture seule. Un seul champ, un seul focus.
private struct MessagingExyteFooter: View {
    let thread: MessagingExyteThreadModel
    let onReported: () -> Void

    private var workspace: MessagingWorkspace { thread.workspace }

    var body: some View {
        Group {
            if thread.reporting {
                reportBar
            } else if workspace.access(for: thread.conversationID).isReadOnly {
                // Fin du lien : l'historique reste lisible, aucun envoi possible.
                Label("Lecture seule", systemImage: "lock")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .frame(maxWidth: .infinity).padding()
                    .accessibilityIdentifier("messaging.readonly")
            } else {
                MessagingExyteComposer(thread: thread, composer: thread.composer)
            }
        }
        // #100 : fond Drivy continu jusqu'au bord, clavier compris ; seul le fond déborde.
        .background(DrivyTheme.surface.ignoresSafeArea(.container, edges: .bottom)
            .ignoresSafeArea(.keyboard, edges: .bottom))
    }

    private var reportBar: some View {
        HStack {
            Button("Annuler") {
                Task {
                    if await workspace.abandonReport(conversationID: thread.conversationID) {
                        thread.reporting = false
                        thread.reportSelection = []
                    }
                }
            }
            .frame(minHeight: DrivyLayout.tapTarget)
            Spacer()
            Button("Transmettre (\(thread.reportSelection.count))") {
                let selected = workspace.visibleMessages(thread.conversationID).filter { thread.reportSelection.contains($0.id) }
                Task {
                    if await workspace.report(selected, conversationID: thread.conversationID) {
                        thread.reporting = false; thread.reportSelection = []; onReported()
                    }
                }
            }
            .bold()
            .frame(minHeight: DrivyLayout.tapTarget)
            .disabled(thread.reportSelection.isEmpty)
            .accessibilityIdentifier("messaging.report.send")
        }
        .padding(.horizontal, DrivySpacing.m)
    }
}

private struct MessagingExyteComposer: View {
    let thread: MessagingExyteThreadModel
    @Bindable var composer: MessagingComposerModel
    @FocusState private var focused: Bool

    private var workspace: MessagingWorkspace { thread.workspace }

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            if let failure = composer.deliveryLabel ?? composer.draftFailure {
                Text(failure)
                    .font(.footnote).foregroundStyle(DrivyTheme.danger)
                    .padding(.horizontal, DrivySpacing.s)
                    .accessibilityIdentifier(composer.deliveryLabel != nil ? "messaging.delivery" : "messaging.draft.error")
            }
            if let replyTo = composer.replyTo { replyPreview(replyTo) }
            if thread.isGeneral, let query = composer.mentionQuery { mentionSuggestions(query) }
            HStack(alignment: .bottom, spacing: DrivySpacing.xs) {
                Menu {
                    Button("Sondage", systemImage: "chart.bar.xaxis") { thread.showPollComposer = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DrivyTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(DrivyTheme.surfaceMuted, in: Circle())
                        .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Plus d'options")
                .accessibilityIdentifier("messaging.compose.more")
                TextField("Message", text: $composer.draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .foregroundStyle(DrivyTheme.text)
                    .padding(.horizontal, DrivySpacing.s)
                    .padding(.vertical, 10)
                    .frame(minHeight: DrivyLayout.tapTarget)
                    .background(DrivyTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityLabel("Rédiger un message")
                    .accessibilityIdentifier("messaging.compose.text")
                Button {
                    Task { if await composer.sendText() { thread.scrollToNewest() } }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(composer.canSend ? DrivyTheme.onAccent : DrivyTheme.disabledText)
                        .frame(width: 36, height: 36)
                        .background(composer.canSend ? DrivyTheme.accentFill : DrivyTheme.disabledSurface, in: Circle())
                        .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Envoyer")
                .disabled(!composer.canSend)
            }
        }
        .padding(.horizontal, DrivySpacing.xs)
        .padding(.vertical, DrivySpacing.xs)
        .onChange(of: composer.focusRequest) { _, _ in focused = true }
    }

    private func replyPreview(_ message: MessagingWireMessage) -> some View {
        HStack(spacing: DrivySpacing.xs) {
            RoundedRectangle(cornerRadius: 1.5).fill(DrivyTheme.accent).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Réponse à \(workspace.displayName(message.senderID))").font(.caption.bold()).foregroundStyle(DrivyTheme.accent)
                Text(workspace.contents[message.id]?.summary ?? "Message").font(.caption).lineLimit(1).foregroundStyle(DrivyTheme.muted)
            }
            Spacer(minLength: 0)
            Button("Annuler la réponse", systemImage: "xmark.circle.fill") { composer.replyTo = nil }
                .labelStyle(.iconOnly).foregroundStyle(DrivyTheme.muted)
                .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
        }
        .padding(.leading, DrivySpacing.s)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messaging.reply.preview")
    }

    private func mentionSuggestions(_ query: String) -> some View {
        let people = MessagingMentionToken.filter(workspace.generalMembers.filter { $0.id != workspace.scope.accountID },
                                                   query: query, name: \.displayName)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(people.prefix(6)) { person in
                    Button { composer.insertMention(person) } label: {
                        HStack(spacing: DrivySpacing.s) {
                            DrivyAvatar(name: person.displayName, size: 28, photo: workspace.photos[person.id])
                            Text(person.displayName).foregroundStyle(DrivyTheme.text)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, DrivySpacing.s)
                        .frame(minHeight: DrivyLayout.tapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mentionner \(person.displayName)")
                }
                if people.isEmpty {
                    Text("Aucun participant").font(.footnote).foregroundStyle(DrivyTheme.muted)
                        .padding(DrivySpacing.s)
                }
            }
        }
        .frame(maxHeight: 6 * DrivyLayout.tapTarget)
        .fixedSize(horizontal: false, vertical: true)
        .background(DrivyTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Participants à mentionner")
        .accessibilityIdentifier("messaging.mention.suggestions")
        .task { if workspace.generalMembers.isEmpty { await workspace.loadGeneralMembers() } }
    }
}

/// Séparateur de jour, en tête de chaque section d'Exyte.
struct MessagingDaySeparator: View {
    let date: Date

    var body: some View {
        Text(Self.label(date))
            .font(.caption.weight(.semibold))
            .foregroundStyle(DrivyTheme.muted)
            .padding(.horizontal, DrivySpacing.s).padding(.vertical, DrivySpacing.xxs)
            .background(DrivyTheme.surfaceMuted, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.top, DrivySpacing.m).padding(.bottom, DrivySpacing.xxs)
            .accessibilityAddTraits(.isHeader)
    }

    static func label(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(date) { return "Hier" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide).year())
    }
}

/// Bandeau d'état de la conversation : erreurs, détail, sourdine et sa synchronisation.
struct MessagingConversationStatusStrip: View {
    let workspace: MessagingWorkspace
    let conversationID: UUID
    let detail: String?
    let mutedUntil: Date?

    var body: some View {
        let muted = workspace.displayedMutedUntil(conversationID, fallback: mutedUntil).map { $0 > Date() } ?? false
        let muteStatus = workspace.muteAttention(conversationID)
        if workspace.error != nil || workspace.actionError != nil || detail != nil || muted || muteStatus != nil {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                if let error = workspace.error {
                    Text(error.localizedDescription).font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
                if let failure = workspace.actionError {
                    Button { workspace.clearActionError() } label: {
                        Label(failure.localizedDescription, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(DrivyTheme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Masque l'erreur")
                    .accessibilityIdentifier("messaging.action.error")
                }
                HStack(spacing: DrivySpacing.xs) {
                    if let detail { Text(detail).font(.caption).foregroundStyle(DrivyTheme.muted) }
                    if let muteStatus, muteStatus != .confirmed {
                        if muteStatus.needsAttention {
                            Button { workspace.retryMute(conversationID) } label: {
                                Label(muteStatus == .storageFailed ? "Sourdine non conservée · Réessayer" : "Sourdine non confirmée · Réessayer",
                                      systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                                    .font(.caption).foregroundStyle(DrivyTheme.muted)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("messaging.mute.retry")
                        } else {
                            Label(muteStatus == .offline ? "Sourdine en attente de connexion" : "Modification de la sourdine…",
                                  systemImage: muteStatus == .offline ? "wifi.slash" : "clock")
                                .font(.caption).foregroundStyle(DrivyTheme.muted)
                        }
                    } else if muted {
                        Label("En sourdine", systemImage: "bell.slash").font(.caption).foregroundStyle(DrivyTheme.muted)
                    }
                }
            }
            .padding(.horizontal, DrivySpacing.m).padding(.vertical, DrivySpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DrivyTheme.surface)
        }
    }
}
