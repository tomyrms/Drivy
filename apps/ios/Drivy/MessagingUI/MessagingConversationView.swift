import ExyteChat
import SwiftUI

/// Actions du menu Exyte, calculées par message à partir des droits Drivy puis revérifiées à l'exécution.
/// Le menu natif Drivy porte les rôles destructifs ; le menu interne d'Exyte n'est jamais ouvert.
enum MessagingExyteMenuAction: String, CaseIterable, MessageMenuAction, Sendable {
    case reply, pin, unpin, copy, deleteForMe, deleteForEveryone

    static let customDataKey = "drivy.menu"

    var isDeletion: Bool { self == .deleteForMe || self == .deleteForEveryone }
    var nativeRole: ButtonRole? { isDeletion ? .destructive : nil }
    var consequence: String? {
        switch self {
        case .deleteForMe: "Masque ce message pour ton compte. Les autres participants le gardent. Une confirmation suivra."
        case .deleteForEveryone: "Demande sa suppression pour tous les participants. Une confirmation suivra."
        default: nil
        }
    }

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

/// Repères de `MessageView` d'Exyte 3.3.0 : citation, auteur et états s'alignent sur la bulle de la bibliothèque.
private enum ExyteBubbleMetrics {
    static let screenEdge: CGFloat = 12
    static let spacing: CGFloat = 6
    static let status: CGFloat = 10
    static let opposite: CGFloat = 70
    static let avatar: CGFloat = 32
    static let radius: CGFloat = 20
}

/// État de présentation du fil. Les builders d'Exyte sont capturés une fois par la liste : ils ne lisent que ce
/// modèle et le workspace, jamais une valeur figée au premier rendu.
@MainActor
@Observable final class MessagingThreadModel {
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
    var confirmDeleteForMe: MessagingWireMessage?
    var confirmClosePoll: MessagingWireMessage?
    var votersFor: MessagingWireMessage?
    var showPollComposer = false
    struct MenuTarget: Identifiable { let id: String }
    var menuTarget: MenuTarget?
    private enum MenuChoice { case action(MessagingExyteMenuAction, String), reaction(String, String) }
    private var menuChoice: MenuChoice?
    private var menuGeneration = UUID()
    private(set) var loadingOlder = false
    /// Hauteur du pied (composeur, signalement), qu'Exyte place sous la liste : le bouton de retour reste au-dessus.
    private(set) var footerHeight: CGFloat = 0
    /// Déchiffrement tenté, réussi ou non : distingue « en cours » de « indisponible ».
    private(set) var attempted: Set<UUID> = []

    init(workspace: MessagingWorkspace, composer: MessagingComposerModel, conversationID: UUID, isGeneral: Bool) {
        self.workspace = workspace
        self.composer = composer
        self.conversationID = conversationID
        self.isGeneral = isGeneral
    }

    private var access: MessagingConversationAccess { workspace.access(for: conversationID) }
    private var accountID: UUID { workspace.scope.accountID }

    var items: [MessagingThreadItem] {
        MessagingThreadProjection.items(messages: workspace.visibleMessages(conversationID),
            pending: composer.visibleQueue, accountID: accountID,
            clientIDs: MessagingThreadProjection.clientIDs(workspace.sendStates),
            pendingDates: composer.queuedDates, now: Date())
    }

    func item(_ displayID: String) -> MessagingThreadItem? { items.first { $0.id == displayID } }

    func displayID(for messageID: UUID) -> String? { items.first { $0.message?.id == messageID }?.id }

    /// Message cité par une ligne, sauf si elle est supprimée : sa citation disparaît avec elle.
    func quotedID(_ item: MessagingThreadItem) -> UUID? {
        if let entry = item.pending { return entry.replyToMessageID }
        guard let wire = item.message, !wire.meta.deletedForEveryone,
              workspace.mutation(.deleteForEveryone, on: wire) == nil else { return nil }
        return wire.meta.replyToMessageID
    }

    /// Auteur et extrait du message cité ; « indisponible » ou « supprimé » sont dits, jamais devinés.
    func quote(_ id: UUID) -> (author: String?, summary: String, available: Bool) {
        guard let quoted = workspace.message(id, in: conversationID) else { return (nil, "Message indisponible", false) }
        let author = quoted.senderID == accountID ? "Vous" : workspace.displayName(quoted.senderID)
        if quoted.meta.deletedForEveryone { return (author, "Message supprimé", false) }
        guard let content = workspace.contents[id] else { return (author, "Message", true) }
        return (author, content.summary, true)
    }

    // MARK: Modèle Exyte

    /// Bulle, heure, coches d'état et réactions sont rendues par Exyte. Le texte déchiffré ne vit qu'en mémoire,
    /// sans aperçu de lien ni cache de la bibliothèque.
    func exyteMessage(_ item: MessagingThreadItem) -> ExyteChat.Message {
        let actions = menuActions(item)
        var message = ExyteChat.Message(id: item.id, user: user(item.senderID), status: status(item),
                                        createdAt: item.date, attributedText: text(item), reactions: reactions(item),
                                        customData: [MessagingExyteMenuAction.customDataKey: actions])
        // L'égalité d'Exyte ignore `customData` : une révision déterministe force la reconfiguration de la cellule
        // quand ses actions ou ses ajouts Drivy changent, sans changer d'identité.
        var hasher = Hasher()
        hasher.combine(actions)
        hasher.combine(reporting)
        hasher.combine(message.user.name)
        if let presentation = sendPresentation(item) {
            // Plusieurs états n'ont volontairement aucune coche Exyte : leurs libellés doivent quand même évoluer.
            hasher.combine(presentation.accessibilityLabel)
            hasher.combine(presentation.canRetry)
        }
        if let wire = item.message {
            hasher.combine(wire.meta.pinned)
            hasher.combine(wire.meta.replyToMessageID)
            hasher.combine(wire.meta.poll != nil)
        }
        message.triggerRedraw = Self.revision(hasher.finalize())
        return message
    }

    func user(_ personID: UUID) -> ExyteChat.User {
        ExyteChat.User(id: personID.uuidString, name: workspace.displayName(personID), avatarURL: nil,
                       isCurrentUser: personID == accountID)
    }

    private func text(_ item: MessagingThreadItem) -> AttributedString {
        if let entry = item.pending {
            let content = entry.recoveryContent.flatMap(MessagingPlainContent.decode)
            if let text = content?.text { return MessagingMentionToken.styled(text, names: workspace.knownDisplayNames) }
            return AttributedString(content?.summary ?? "Message")
        }
        guard let wire = item.message else { return AttributedString() }
        // L'effacement chez tous n'est annoncé qu'après la relecture serveur.
        if !wire.meta.deletedForEveryone, workspace.mutation(.deleteForEveryone, on: wire) != nil {
            return Self.notice("Suppression en cours")
        }
        if wire.meta.deletedForEveryone { return Self.notice("Message supprimé") }
        if let content = workspace.contents[wire.id] {
            if let text = content.text { return MessagingMentionToken.styled(text, names: workspace.knownDisplayNames) }
            return AttributedString(content.summary)
        }
        if let code = workspace.decryptionCodes[wire.id] { return Self.unreadable(code) }
        return Self.notice(attempted.contains(wire.id) ? "Message protégé indisponible" : "Déchiffrement…")
    }

    private static func notice(_ text: String) -> AttributedString {
        var value = AttributedString(text)
        value.inlinePresentationIntent = .emphasized
        value.foregroundColor = DrivyTheme.muted
        return value
    }

    /// Message illisible (#239) : l’explication d’abord ; le code, sans donnée personnelle, en petit pour le diagnostic.
    private static func unreadable(_ code: String) -> AttributedString {
        var detail = AttributedString("\nCode \(code)")
        detail.font = Font.caption
        detail.foregroundColor = DrivyTheme.muted
        return notice(MessagingDecryptionFailure.explanation(for: code)) + detail
    }

    /// Une réaction Exyte par personne : la bulle et l'aperçu du menu montrent qui a réagi.
    /// La mienne reste provisoire tant que le serveur ne l'a pas confirmée.
    private func reactions(_ item: MessagingThreadItem) -> [ExyteChat.Reaction] {
        guard let wire = item.message, !wire.meta.deletedForEveryone else { return [] }
        var result: [ExyteChat.Reaction] = []
        for (index, reaction) in wire.meta.reactions.enumerated() {
            let status = workspace.mutation(.reaction(reaction.emoji), on: wire)?.status
            for (offset, person) in reaction.personIDs.enumerated() {
                let provisional = person == accountID && status != nil && status != .confirmed
                result.append(ExyteChat.Reaction(id: "\(reaction.emoji)|\(person.uuidString)", user: user(person),
                    createdAt: wire.acceptedAt.addingTimeInterval(Double(index * 1_000 + offset)),
                    type: .emoji(reaction.emoji), status: provisional ? .sending : .sent))
            }
        }
        return result
    }

    /// Coches seulement pour un événement réel : accusé serveur pour « envoyé », reçu de lecture pour « lu ».
    private func status(_ item: MessagingThreadItem) -> ExyteChat.Message.Status? {
        if let presentation = sendPresentation(item) {
            if presentation.isAccepted { return .sent }
            if presentation.showsSendingIndicator { return .sending }
            // Exyte n'a pas d'état « résultat inconnu » : la ligne Drivy en porte l'icône, le texte et l'action.
            // Ni coche de succès, ni animation d'envoi, ni icône d'erreur qui renverrait aveuglément le message.
            return nil
        }
        guard let wire = item.message, wire.senderID == accountID, !wire.meta.deletedForEveryone else { return nil }
        let readers = workspace.readers(of: wire)
        return readers.isEmpty ? .sent : .readBy(readers.map(\.uuidString))
    }

    func menuActions(_ item: MessagingThreadItem) -> [MessagingExyteMenuAction] {
        guard !reporting else { return [] }
        guard let wire = item.message else { return pendingText(item) == nil ? [] : [.copy] }
        var actions: [MessagingExyteMenuAction] = []
        if !wire.meta.deletedForEveryone && access.canWrite {
            actions.append(.reply)
            if !isGeneral || access.isGroupAdmin { actions.append(wire.meta.pinned ? .unpin : .pin) }
        }
        if !wire.meta.deletedForEveryone, workspace.contents[wire.id]?.text != nil { actions.append(.copy) }
        actions.append(.deleteForMe)
        if !wire.meta.deletedForEveryone,
           MessagingPermissions.canDeleteForEveryone(senderID: wire.senderID, account: accountID, access: access) {
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

    // MARK: Accessibilité

    /// Une bulle = un élément VoiceOver : auteur, texte, heure, réactions et état réel.
    func accessibilityLabel(_ item: MessagingThreadItem) -> String {
        var parts = [item.senderID == accountID ? "Vous" : workspace.displayName(item.senderID),
                     String(text(item).characters), item.date.formatted(date: .omitted, time: .shortened)]
        if let wire = item.message {
            if wire.meta.pinned { parts.append("épinglé") }
            let reactions = wire.meta.reactions.map { reaction in
                "\(MessagingReactionPalette.label(reaction.emoji)) \(reaction.personIDs.count)"
                    + (reaction.personIDs.contains(accountID) ? ", vous avez réagi" : "")
                    + Self.syncSuffix(workspace.mutation(.reaction(reaction.emoji), on: wire)?.status)
            }
            if !reactions.isEmpty { parts.append("réactions : " + reactions.joined(separator: " ; ")) }
            let readers = wire.senderID == accountID ? workspace.readers(of: wire) : []
            if !readers.isEmpty {
                parts.append(isGeneral ? "lu par " + readers.map(workspace.displayName).joined(separator: ", ") : "lu")
            }
        } else if let presentation = sendPresentation(item) {
            parts.append(presentation.accessibilityLabel)
        }
        return parts.joined(separator: ", ")
    }

    /// Réaction encore provisoire : son état est lu avec elle, jamais présenté comme confirmé.
    private static func syncSuffix(_ status: MessagingMutationStatus?) -> String {
        switch status {
        case .sending?, .slow?: ", en cours de synchronisation"
        case .unconfirmed?, .uncertain?: ", modification non confirmée"
        case .offline?: ", en attente de connexion"
        case .storageFailed?: ", modification non conservée"
        default: ""
        }
    }

    func sendPresentation(_ item: MessagingThreadItem) -> MessagingSendPresentation? {
        item.pending.map { MessagingSendPresentation(status: workspace.sendStatus($0.clientMessageID)) }
    }

    func needsSendRetry(_ item: MessagingThreadItem) -> Bool {
        sendPresentation(item)?.canRetry == true
    }

    // MARK: Actions

    private func canInteract(_ message: MessagingWireMessage) -> Bool {
        !message.meta.deletedForEveryone && access.canWrite && !reporting
    }

    /// Les droits sont relus au moment de l'action : un menu resté ouvert n'élargit jamais l'accès.
    func perform(_ action: MessagingExyteMenuAction, displayID: String) {
        guard let item = item(displayID), menuActions(item).contains(action) else { return }
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
            confirmDeleteForMe = wire
        case .deleteForEveryone:
            guard let wire = item.message, !wire.meta.deletedForEveryone,
                  MessagingPermissions.canDeleteForEveryone(senderID: wire.senderID, account: accountID, access: access)
            else { return }
            confirmDeleteForEveryone = wire
        }
    }

    func canReact(displayID: String) -> Bool {
        guard let wire = item(displayID)?.message else { return false }
        return canInteract(wire)
    }

    /// Le menu ferme avant cet appel ; l'intention est posée sans attendre le réseau.
    func react(_ reaction: ReactionType, displayID: String) {
        guard case .emoji(let emoji) = reaction, MessagingReactionPalette.all.contains(emoji),
              let wire = item(displayID)?.message, canInteract(wire) else { return }
        workspace.toggleReaction(emoji, on: wire)
    }

    /// Appui sur les réactions d'une bulle : retire la mienne, ou reprend la seule réaction présente.
    /// Faux quand le choix est ambigu (plusieurs réactions) : le menu s'ouvre alors sur la palette.
    func tapReactions(displayID: String) -> Bool {
        guard let wire = item(displayID)?.message, canInteract(wire) else { return true }
        let mine = wire.meta.reactions.filter { $0.personIDs.contains(accountID) }.map(\.emoji)
        let present = wire.meta.reactions.map(\.emoji)
        guard let emoji = mine.count == 1 ? mine.first : (mine.isEmpty && present.count == 1 ? present.first : nil)
        else { return false }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        workspace.toggleReaction(emoji, on: wire)
        return true
    }

    /// Le clavier ferme avant la feuille native. Une fermeture/changement de contexte annule l'ouverture différée.
    func openMenu(displayID: String) {
        guard let item = item(displayID), !menuActions(item).isEmpty else { return }
        menuGeneration = UUID()
        let generation = menuGeneration
        menuChoice = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard composer.isFocused else { menuTarget = MenuTarget(id: displayID); return }
        composer.blur()
        Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(320)) } catch { return }
            guard generation == menuGeneration, let current = self.item(displayID), !menuActions(current).isEmpty else { return }
            menuTarget = MenuTarget(id: displayID)
        }
    }

    func chooseMenuAction(_ action: MessagingExyteMenuAction, displayID: String) {
        guard menuTarget?.id == displayID else { return }
        menuChoice = .action(action, displayID); menuTarget = nil
    }

    func chooseMenuReaction(_ emoji: String, displayID: String) {
        guard menuTarget?.id == displayID else { return }
        menuChoice = .reaction(emoji, displayID); menuTarget = nil
    }

    /// Une confirmation ne concurrence pas la présentation du menu. Les droits sont relus après sa fermeture.
    func completeMenuChoice() {
        let choice = menuChoice; menuChoice = nil
        switch choice {
        case .action(let action, let displayID): perform(action, displayID: displayID)
        case .reaction(let emoji, let displayID): react(.emoji(emoji), displayID: displayID)
        case nil: break
        }
    }

    func cancelMenu() {
        menuGeneration = UUID(); menuChoice = nil; menuTarget = nil
        confirmDeleteForEveryone = nil; confirmDeleteForMe = nil; confirmClosePoll = nil
    }

    func confirmDeletion(_ reviewed: MessagingWireMessage, for scope: MessagingDeletionScope) {
        guard let current = items.first(where: { $0.message?.id == reviewed.id }),
              menuActions(current).contains(scope == .me ? .deleteForMe : .deleteForEveryone), let message = current.message else { return }
        workspace.delete(message, for: scope)
    }

    func reply(displayID: String) {
        guard let wire = item(displayID)?.message, canInteract(wire) else { return }
        composer.reply(to: wire)
    }

    /// Même envoi, même identifiant : jamais un second message.
    func retrySend(displayID: String) {
        guard let item = item(displayID), needsSendRetry(item), let entry = item.pending else { return }
        composer.retry(entry)
    }

    func decrypt(_ message: MessagingWireMessage) async {
        _ = await workspace.content(for: message)
        attempted.insert(message.id)
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

    func footerResized(_ height: CGFloat) {
        if abs(height - footerHeight) > 0.5 { footerHeight = height }
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

/// Conversation (#182) : liste, bulles, heure, coches, réactions et avatars d'Exyte Chat,
/// aux couleurs Drivy ; composeur, sondages, citations, droits, E2EE, file protégée et états d'envoi restent Drivy.
struct MessagingConversationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var pinnedBannerHeight = DrivyLayout.tapTarget
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
    @State private var thread: MessagingThreadModel
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
        _thread = State(initialValue: MessagingThreadModel(workspace: workspace, composer: composer,
                                                           conversationID: conversationID, isGeneral: isGeneral))
    }

    private var composer: MessagingComposerModel { thread.composer }
    private var confirmationPresented: Binding<Bool> {
        Binding(get: { thread.confirmDeleteForEveryone != nil || thread.confirmDeleteForMe != nil || thread.confirmClosePoll != nil },
            set: { if !$0 { thread.confirmDeleteForEveryone = nil; thread.confirmDeleteForMe = nil; thread.confirmClosePoll = nil } })
    }
    private var confirmationTitle: String {
        if thread.confirmDeleteForEveryone != nil { return "Supprimer pour tout le monde ?" }
        if thread.confirmDeleteForMe != nil { return "Supprimer pour moi ?" }
        return "Clore le sondage ?"
    }

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
        .sheet(item: $thread.menuTarget, onDismiss: { thread.completeMenuChoice() }) { target in
            MessagingMessageMenu(thread: thread, displayID: target.id)
        }
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
        .sheet(item: $thread.votersFor) { message in
            // Présentée par la conversation, pas depuis la cellule : état du sondage relu à l'ouverture.
            if let poll = (workspace.message(message.id, in: conversationID) ?? message).meta.poll {
                MessagingPollVotersSheet(workspace: workspace, poll: poll, content: workspace.contents[message.id]?.poll)
            }
        }
        .navigationDestination(isPresented: $showMembers) { MessagingMembersView(workspace: workspace) }
        .alert("Signalement transmis", isPresented: $reportSent) { Button("OK") {} }
        .confirmationDialog(confirmationTitle, isPresented: confirmationPresented, titleVisibility: .visible) {
            if let message = thread.confirmDeleteForEveryone {
                Button("Supprimer pour tout le monde", role: .destructive) { thread.confirmDeletion(message, for: .everyone) }
            } else if let message = thread.confirmDeleteForMe {
                Button("Supprimer pour moi", role: .destructive) { thread.confirmDeletion(message, for: .me) }
            } else if let message = thread.confirmClosePoll {
                Button("Clore le sondage", role: .destructive) { Task { await workspace.closePoll(message) } }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            if thread.confirmDeleteForEveryone != nil {
                Text("Le contenu sera retiré de cette conversation pour tous les participants. Les copies déjà reçues ne peuvent pas être effacées ici.")
            } else if thread.confirmDeleteForMe != nil {
                Text("Ce message sera masqué pour ton compte. Les autres participants le garderont.")
            }
        }
    }

    private var lifecycle: MessagingThreadLifecycle {
        MessagingThreadLifecycle(workspace: workspace, thread: thread, connectivity: connectivity,
                                 conversationID: conversationID, scenePhase: scenePhase)
    }

    // MARK: Fil

    @ViewBuilder private var chat: some View {
        let thread = thread
        let pinned = !workspace.pinnedMessages(conversationID).isEmpty
        ChatView(messages: thread.items.map(thread.exyteMessage), chatType: .conversation, replyMode: .quote,
                 // La composition reste Drivy ; toute éventuelle reprise Exyte revalide l'état de la même intention.
                 didSendMessage: { draft in if let id = draft.id { thread.retrySend(displayID: id) } },
                 messageBuilder: { params in MessagingThreadRow(thread: thread, params: params) },
                 inputViewBuilder: { _ in MessagingThreadFooter(thread: thread, onReported: { reportSent = true }) },
                 messageMenuAction: { (action: MessagingExyteMenuAction, _, message) in
                     thread.perform(action, displayID: message.id)
                 })
            .showDateHeaders(true)
            .dateHeaderBuilder { date in MessagingDaySeparator(date: date) }
            .mainHeaderBuilder { MessagingOlderMessagesButton(thread: thread) }
            .enableLoadMoreOlderMessages(hasMoreToLoad: workspace.canLoadMoreMessages(conversationID),
                                         handleClosure: { await thread.loadOlder() },
                                         loadingIndicatorBuilder: { ProgressView().padding(DrivySpacing.s) })
            .showMessageTimeView(true)
            .showUsername(false)
            .showAvatar(isGeneral)
            .avatarSize(avatarSize: ExyteBubbleMetrics.avatar)
            .avatarBuilder { user in MessagingThreadAvatar(workspace: workspace, user: user) }
            .showScrollToBottomButton(false)
            .showNetworkConnectionProblem(false)
            // La ligne ouvre le menu natif Drivy ; aucune alerte ni suppression par défaut d'Exyte.
            .showMessageMenuOnLongPress(false)
            .linkPreviewsEnabled(false)
            .setAvailableInputs([.text])
            .keyboardDismissMode(.interactive)
            .setMessageFont(UIFont.preferredFont(forTextStyle: .body))
            .messageMenuAnimationDuration(reduceMotion ? 0.1 : 0.15)
            .contentInsets(top: pinned ? pinnedBannerHeight : 0)
            .onContentOffsetChange { thread.offsetChanged($0) }
            .scrollTo(thread.scrollRequest)
            .onMessageReaction(didReactTo: { message, draft in thread.react(draft.type, displayID: message.id) },
                               canReactTo: { thread.canReact(displayID: $0.id) },
                               availableReactionsFor: { _ in MessagingReactionPalette.all.map { ReactionType.emoji($0) } },
                               allowEmojiSearchFor: { _ in false },
                               shouldShowOverviewFor: { !$0.reactions.isEmpty })
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
            .padding(.bottom, thread.footerHeight + DrivySpacing.s)
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
                // Une seule action, celle de l’état affiché (#168) : la demande en cours prime sur l’état serveur connu,
                // une sourdine échue se lit comme active. Le menu se recalcule à chaque ouverture.
                if let until = workspace.displayedMutedUntil(conversationID, fallback: mutedUntil), until > Date() {
                    Button {
                        Task { await workspace.unsilence(conversationID: conversationID,
                            fallbackSequence: lastReadSequence, fallbackVersion: readStateVersion) }
                    } label: {
                        Label("Réactiver les notifications", systemImage: "bell")
                        Text("En sourdine jusqu’à \(MessagingMuteFormat.until(until))")
                    }
                    .accessibilityIdentifier("messaging.mute.off")
                } else {
                    // Durées validées à l’essai du 28 octobre : toutes datées, aucune sourdine sans fin (règle nouvelle).
                    Menu("Mettre en sourdine", systemImage: "bell.slash") {
                        ForEach(MessagingMuteFormat.durations, id: \.seconds) { choice in
                            Button(choice.label) {
                                Task { await workspace.silence(conversationID: conversationID,
                                    fallbackSequence: lastReadSequence, until: Date().addingTimeInterval(choice.seconds),
                                    fallbackVersion: readStateVersion) }
                            }
                        }
                    }
                    .accessibilityIdentifier("messaging.mute.on")
                }
            }
            .accessibilityIdentifier("messaging.options")
        }
    }
}

/// Cycle de vie de la conversation : chargement, brouillon protégé, lecture réelle, reprise et contexte actif.
private struct MessagingThreadLifecycle: ViewModifier {
    let workspace: MessagingWorkspace
    let thread: MessagingThreadModel
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
            .task(id: thread.atBottom) {
                MessagingActiveConversation.set(schoolID: workspace.scope.schoolID, conversationID: conversationID,
                                                atBottom: thread.atBottom)
            }
            .onAppear { connectivity.start() }
            .onDisappear { thread.cancelMenu(); connectivity.stop(); MessagingActiveConversation.clear(conversationID) }
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
                if failure == .contextChanged || failure == .accessChanged { thread.cancelMenu(); composer.reset() }
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

/// Ligne du fil : bulle Exyte (ou carte de sondage de même forme), avec les ajouts Drivy alignés sur elle :
/// auteur dans le général, citation qui mène au message, épingle, états de synchronisation, sélection.
private struct MessagingThreadRow: View {
    let thread: MessagingThreadModel
    let params: MessageBuilderParameters
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Glisser vers la gauche : la bulle suit le doigt, la réponse part au relâcher une fois le seuil franchi.
    @State private var swipe: CGFloat = 0
    @State private var swipeArmed = false
    private static let swipeThreshold: CGFloat = 48

    private var workspace: MessagingWorkspace { thread.workspace }

    var body: some View {
        if let item = thread.item(params.message.id) {
            let mine = item.senderID == workspace.scope.accountID
            let highlighted = item.message.map { thread.highlighted == $0.id } ?? false
            selectable(item) {
                VStack(spacing: 2) {
                    if thread.isGeneral, !mine, params.positionInGroup == .first || params.positionInGroup == .single {
                        Text(workspace.displayName(item.senderID))
                            .font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                            .padding(.horizontal, ExyteBubbleMetrics.screenEdge)
                            .modifier(BubbleAligned(mine: mine, isGeneral: thread.isGeneral))
                            .accessibilityHidden(true)
                    }
                    bubble(item, mine: mine)
                    MessagingThreadStateLine(thread: thread, item: item)
                        .modifier(BubbleAligned(mine: mine, isGeneral: thread.isGeneral))
                }
                .offset(x: swipe)
                .overlay(alignment: .trailing) { swipeHint }
            }
            .padding(.vertical, 2)
            .gesture(MessagingReplySwipeGesture(isEnabled: thread.canReact(displayID: item.id),
                                                onChanged: { swipeChanged($0) },
                                                onEnded: { swipeEnded(item.id) }))
            .gesture(MessagingMenuPressGesture(isEnabled: !thread.reporting) {
                thread.openMenu(displayID: item.id)
            })
            .background(highlighted ? DrivyTheme.accentSoft : Color.clear,
                        in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
            .animation(DrivyMotion.settle(reduceMotion), value: highlighted)
            .task(id: item.message?.id) {
                if let wire = item.message, !wire.meta.deletedForEveryone, workspace.contents[wire.id] == nil {
                    await thread.decrypt(wire)
                }
            }
        }
    }

    @ViewBuilder private func bubble(_ item: MessagingThreadItem, mine: Bool) -> some View {
        if let wire = item.message, !wire.meta.deletedForEveryone, workspace.mutation(.deleteForEveryone, on: wire) == nil,
           let poll = workspace.contents[wire.id]?.poll, let state = wire.meta.poll {
            MessagingThreadPollBubble(thread: thread, message: wire, poll: poll, state: state, mine: mine,
                                      showsAvatar: params.positionInGroup == .last || params.positionInGroup == .single,
                                      quotedID: wire.meta.replyToMessageID)
                .accessibilityAction(named: "Voir les votes") { thread.votersFor = wire }
                .accessibilityActions { actions(item) }
        } else if let quoted = thread.quotedID(item) {
            MessagingReplyBubble(thread: thread, item: item, message: params.message, quotedID: quoted, mine: mine,
                                 showsAvatar: params.positionInGroup == .last || params.positionInGroup == .single,
                                 topPadding: bubbleTopPadding) { actions(item) }
                .accessibilityElement(children: .contain)
        } else {
            let hasReactions = !(item.message?.meta.reactions.isEmpty ?? true)
            params.defaultMessageView()
                // Les pastilles de réaction d'Exyte n'ont pas d'action : une zone transparente posée sur toute leur
                // bande, au-dessus de la bulle, retire ma réaction (ou reprend la seule présente) sans passer par le
                // menu. Posée par-dessus, elle reçoit l'appui quelle que soit la façon dont la bulle traite les touchers.
                .overlay(alignment: .top) {
                    if hasReactions && !thread.reporting {
                        Color.clear
                            .frame(height: reactionBand)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !thread.tapReactions(displayID: item.id) { thread.openMenu(displayID: item.id) }
                            }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(thread.accessibilityLabel(item))
                .accessibilityIdentifier(item.pending == nil ? "messaging.message" : "messaging.pending")
                .accessibilityActions { actions(item) }
        }
    }

    /// Hauteur de la bande des réactions dans `MessageView` d'Exyte 3.3.0 : marge haute de la ligne, puis pastilles
    /// (ligne de texte + 2 × 6 pt), dont le bas chevauche la bulle.
    private var reactionBand: CGFloat {
        bubbleTopPadding + (UIFont.preferredFont(forTextStyle: .body).lineHeight + 12) * 0.8
    }

    /// Marge haute de `MessageView` : plus grande en tête d'un groupe d'auteur, sauf en tête de journée.
    private var bubbleTopPadding: CGFloat {
        let groupTop = params.positionInGroup == .first || params.positionInGroup == .single
        let dayTop = params.positionInMessagesSection == .first || params.positionInMessagesSection == .single
        return groupTop && !dayTop ? 8 : 4
    }

    @ViewBuilder private var swipeHint: some View {
        if swipe < 0 {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(swipeArmed ? DrivyTheme.accent : DrivyTheme.muted)
                .scaleEffect(swipeArmed ? 1.1 : 0.85)
                .opacity(min(1, -swipe / Self.swipeThreshold))
                .padding(.trailing, DrivySpacing.m)
                .accessibilityHidden(true)
        }
    }

    private func swipeChanged(_ translation: CGFloat) {
        let pull = min(0, translation)
        // Résistance au-delà du seuil : le geste reste court et lisible.
        swipe = pull > -Self.swipeThreshold ? pull : -Self.swipeThreshold + (pull + Self.swipeThreshold) * 0.3
        let armed = pull <= -Self.swipeThreshold
        if armed != swipeArmed {
            swipeArmed = armed
            if armed { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
    }

    private func swipeEnded(_ displayID: String) {
        if swipeArmed { thread.reply(displayID: displayID) }
        swipeArmed = false
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { swipe = 0 }
    }

    /// Mêmes actions que le menu et le glisser, accessibles sans geste.
    @ViewBuilder private func actions(_ item: MessagingThreadItem) -> some View {
        if thread.canReact(displayID: item.id) {
            Button("Répondre") { thread.reply(displayID: item.id) }
            ForEach(MessagingReactionPalette.all, id: \.self) { emoji in
                Button("Réagir : \(MessagingReactionPalette.label(emoji))") { thread.react(.emoji(emoji), displayID: item.id) }
            }
        }
        ForEach(thread.menuActions(item).filter { $0 != .reply }, id: \.self) { action in
            Button(action.title(), role: action.nativeRole) { thread.perform(action, displayID: item.id) }
                .accessibilityHint(action.consequence ?? "")
        }
        if let wire = item.message, workspace.mutationAttention(for: wire)?.needsAttention == true {
            Button("Réessayer la synchronisation") { workspace.retryMutations(for: wire) }
        }
        if thread.needsSendRetry(item) {
            Button("Réessayer l'envoi") { thread.retrySend(displayID: item.id) }
        }
    }

    @ViewBuilder private func selectable<Content: View>(_ item: MessagingThreadItem,
                                                        @ViewBuilder content: () -> Content) -> some View {
        if thread.reporting, let wire = item.message, !wire.meta.deletedForEveryone {
            let selected = thread.reportSelection.contains(wire.id)
            Button { thread.toggleReport(wire.id) } label: {
                HStack(spacing: 0) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? DrivyTheme.accent : DrivyTheme.muted)
                        .font(.title3)
                        .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
                        .padding(.leading, DrivySpacing.xs)
                        .accessibilityHidden(true)
                    content()
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityHint("Sélectionne ce message pour le signalement")
        } else {
            content()
        }
    }
}

/// Aligne un ajout Drivy sur le bord de la bulle Exyte (avatar, coche d'état et marge opposée compris).
private struct BubbleAligned: ViewModifier {
    let mine: Bool
    let isGeneral: Bool

    func body(content: Content) -> some View {
        let avatar = isGeneral && !mine ? ExyteBubbleMetrics.avatar + ExyteBubbleMetrics.spacing : 0
        let status = mine ? ExyteBubbleMetrics.status + ExyteBubbleMetrics.spacing : 0
        content
            .padding(.leading, mine ? ExyteBubbleMetrics.opposite : ExyteBubbleMetrics.screenEdge + avatar)
            .padding(.trailing, mine ? ExyteBubbleMetrics.screenEdge + status : ExyteBubbleMetrics.opposite)
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
}

/// Citation intégrée en tête de bulle : bandeau d'accent, auteur, une ou deux lignes du message cité.
/// Un appui mène au message cité, chargé au besoin.
private struct MessagingQuoteBlock: View {
    let thread: MessagingThreadModel
    let quotedID: UUID
    let mine: Bool

    var body: some View {
        let quote = thread.quote(quotedID)
        Button { Task { await thread.jump(to: quotedID) } } label: {
            HStack(spacing: 0) {
                Rectangle().fill(DrivyTheme.accent).frame(width: 4)
                VStack(alignment: .leading, spacing: 1) {
                    if let author = quote.author {
                        Text(author).font(.footnote.weight(.semibold)).foregroundStyle(DrivyTheme.accent).lineLimit(1)
                    }
                    Text(quote.summary).font(.footnote).italic(!quote.available)
                        .foregroundStyle(DrivyTheme.muted).lineLimit(2)
                }
                .padding(.horizontal, DrivySpacing.xs).padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Teinte de la bulle porteuse : accent pour mes messages, surface claire pour les autres.
            .background(mine ? DrivyTheme.accent.opacity(0.12) : DrivyTheme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("En réponse à \(quote.author ?? "un message") : \(quote.summary)")
        .accessibilityHint("Affiche le message cité")
        .task(id: quotedID) {
            let workspace = thread.workspace
            if let quoted = workspace.message(quotedID, in: thread.conversationID), !quoted.meta.deletedForEveryone,
               workspace.contents[quotedID] == nil {
                await thread.decrypt(quoted)
            }
        }
    }
}

/// Bulle d'une réponse, dessinée par Drivy aux mesures de `MessageView` d'Exyte 3.3.0 (rayon, marges, heure, coches,
/// réactions) : la citation fait partie de la bulle au lieu de flotter au-dessus.
private struct MessagingReplyBubble<Actions: View>: View {
    let thread: MessagingThreadModel
    let item: MessagingThreadItem
    let message: ExyteChat.Message
    let quotedID: UUID
    let mine: Bool
    let showsAvatar: Bool
    let topPadding: CGFloat
    @ViewBuilder let actions: () -> Actions

    private static var timeFont: Font { Font(UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: 10))) }
    private var reactionSize: CGFloat {
        ("🙃" as NSString).size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .body)]).width + 12
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: ExyteBubbleMetrics.spacing) {
            if thread.isGeneral && !mine {
                Group {
                    if showsAvatar {
                        MessagingThreadAvatar(workspace: thread.workspace, user: message.user)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: ExyteBubbleMetrics.avatar, height: ExyteBubbleMetrics.avatar)
            }
            VStack(alignment: mine ? .leading : .trailing, spacing: -reactionSize / 3) {
                if !message.reactions.isEmpty {
                    MessagingReactionChips(reactions: message.reactions, mine: mine, size: reactionSize) { emoji in
                        thread.react(.emoji(emoji), displayID: item.id)
                    }
                    .offset(x: mine ? -reactionSize / 2 : reactionSize / 2)
                    .zIndex(1)
                }
                bubble
            }
            if mine {
                status.frame(width: ExyteBubbleMetrics.status, height: ExyteBubbleMetrics.status)
            }
        }
        .padding(.top, topPadding)
        .padding(.horizontal, ExyteBubbleMetrics.screenEdge)
        .padding(mine ? .leading : .trailing, ExyteBubbleMetrics.opposite)
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var bubble: some View {
        MatchWidthStack(spacing: 0) {
            MessagingQuoteBlock(thread: thread, quotedID: quotedID, mine: mine)
                .padding([.top, .horizontal], 6)
            ZStack(alignment: .bottomTrailing) {
                // Espace réservé en fin de texte : l'heure se pose sur la dernière ligne, ou en dessous si elle est pleine.
                Text(message.attributedText + AttributedString("\u{2003}\u{2003}"))
                    .font(.body)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                Text(message.createdAt, format: .dateTime.hour().minute())
                    .font(Self.timeFont)
                    .foregroundStyle(DrivyTheme.textTertiary)
                    .padding(.trailing, 12)
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(thread.accessibilityLabel(item))
            .accessibilityIdentifier(item.pending == nil ? "messaging.message" : "messaging.pending")
            .accessibilityActions(actions)
        }
        .background(mine ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: ExyteBubbleMetrics.radius, style: .continuous))
    }

    /// Mêmes coches qu'Exyte. Les états non confirmés et les refus sont portés par la ligne Drivy, sans coche.
    @ViewBuilder private var status: some View {
        let images = ChatTheme.drivy.images.message
        switch message.status {
        case .sending?: statusImage(images.sending, DrivyTheme.muted)
        case .sent?: statusImage(images.sent, DrivyTheme.muted)
        case .delivered?: statusImage(images.delivered, DrivyTheme.muted)
        case .readBy?: statusImage(images.read, DrivyTheme.accent)
        case .error?:
            statusImage(images.error, DrivyTheme.danger)
        case nil: Color.clear
        }
    }

    /// Même dimensionnement que `MessageStatusView` d'Exyte : icône ajustée dans 40 × 10 pt, posée dans la colonne
    /// de 10 pt ; la double coche garde ainsi sa largeur naturelle, comme sur les bulles sans citation.
    private func statusImage(_ image: Image, _ color: Color) -> some View {
        image.renderingMode(.template).resizable().aspectRatio(contentMode: .fit).foregroundStyle(color).frame(width: 40)
    }
}

/// Pastilles de réaction au dessin d'Exyte, mais touchables : un appui ajoute ou retire cette réaction.
private struct MessagingReactionChips: View {
    let reactions: [ExyteChat.Reaction]
    let mine: Bool
    let size: CGFloat
    let onTap: (String) -> Void

    private static let limit = 5

    var body: some View {
        let sorted = reactions.sorted { $0.createdAt > $1.createdAt }
        let overflow = sorted.count > Self.limit
        let shown = overflow ? Array(sorted.prefix(Self.limit - 1)) : sorted
        // Pastilles côte à côte (#142) : en se chevauchant, l’appui au bord de l’une pouvait viser sa voisine. Chacune
        // reçoit l’appui sur 44 pt de haut, sans agrandir la bande ni déplacer la bulle.
        HStack(spacing: 2) {
            if !mine && overflow { chip("+\(sorted.count - Self.limit + 1)", own: false, sending: false) }
            ForEach(mine ? shown : Array(shown.reversed()), id: \.id) { reaction in
                if case .emoji(let emoji) = reaction.type {
                    Button { onTap(emoji) } label: {
                        chip(emoji, own: reaction.user.isCurrentUser, sending: reaction.status == .sending)
                            .contentShape(MessagingTallHitShape(height: DrivyLayout.tapTarget))
                    }
                    .buttonStyle(.plain)
                }
            }
            if mine && overflow { chip("+\(sorted.count - Self.limit + 1)", own: false, sending: false) }
        }
        .accessibilityHidden(true)
    }

    private func chip(_ text: String, own: Bool, sending: Bool) -> some View {
        Text(text)
            .font(.body)
            .opacity(sending ? 0.7 : 1)
            .padding(6)
            .background(Circle().fill(own ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted))
            .overlay(Circle().stroke(DrivyTheme.canvas, style: StrokeStyle(lineWidth: 2, dash: sending ? [4, 3] : [])))
    }
}

/// Empile ses éléments à la largeur du plus large, bornée par la place offerte : la bulle épouse son contenu et la
/// citation s'étend sur toute la largeur de la bulle.
private struct MatchWidthStack: Layout {
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = matchedWidth(for: proposal, subviews: subviews)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }

    private func matchedWidth(for proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        guard let available = proposal.width else { return ideal }
        return min(ideal, available)
    }
}

/// Sondage dans une bulle de même forme et des mêmes couleurs que les bulles Exyte.
private struct MessagingThreadPollBubble: View {
    let thread: MessagingThreadModel
    let message: MessagingWireMessage
    let poll: MessagingPlainContent.Poll
    let state: MessagingPollState
    let mine: Bool
    let showsAvatar: Bool
    let quotedID: UUID?

    var body: some View {
        HStack(alignment: .bottom, spacing: ExyteBubbleMetrics.spacing) {
            if thread.isGeneral && !mine {
                Group {
                    if showsAvatar {
                        MessagingThreadAvatar(workspace: thread.workspace, user: thread.user(message.senderID))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: ExyteBubbleMetrics.avatar, height: ExyteBubbleMetrics.avatar)
            }
            VStack(alignment: .trailing, spacing: DrivySpacing.xxs) {
                if let quotedID { MessagingQuoteBlock(thread: thread, quotedID: quotedID, mine: mine) }
                MessagingPollCard(workspace: thread.workspace, message: message, poll: poll, state: state,
                                  onShowVoters: { thread.votersFor = message },
                                  onClose: { thread.confirmClosePoll = message })
                Text(message.acceptedAt, style: .time).font(.caption2).foregroundStyle(DrivyTheme.textTertiary)
            }
            .frame(minWidth: 220)
            .padding(DrivySpacing.s)
            .background(mine ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted,
                        in: RoundedRectangle(cornerRadius: ExyteBubbleMetrics.radius, style: .continuous))
            if mine { Color.clear.frame(width: ExyteBubbleMetrics.status) }
        }
        .padding(.horizontal, ExyteBubbleMetrics.screenEdge)
        .padding(mine ? .leading : .trailing, ExyteBubbleMetrics.opposite)
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
}

/// Avatar du général : photo obtenue par le chargeur autorisé de Drivy, jamais une URL confiée à Exyte.
private struct MessagingThreadAvatar: View {
    let workspace: MessagingWorkspace
    let user: ExyteChat.User

    var body: some View {
        let id = UUID(uuidString: user.id)
        DrivyAvatar(name: user.name, size: ExyteBubbleMetrics.avatar, photo: id.flatMap { workspace.photo(for: $0) })
            .task(id: user.id) {
                if let id, workspace.members.first(where: { $0.id == id })?.hasPhoto == true {
                    await workspace.loadPhoto(id)
                }
            }
            .accessibilityHidden(true)
    }
}

/// États Drivy sous la bulle : épingle, synchronisation lente, hors connexion, refus, envoi à reprendre.
private struct MessagingThreadStateLine: View {
    let thread: MessagingThreadModel
    let item: MessagingThreadItem

    private var workspace: MessagingWorkspace { thread.workspace }

    var body: some View {
        if let message = item.message {
            let mine = item.senderID == workspace.scope.accountID
            VStack(alignment: .leading, spacing: 2) {
                if message.meta.pinned {
                    Label("Épinglé", systemImage: "pin.fill")
                        .font(.caption2).foregroundStyle(DrivyTheme.textTertiary)
                        .accessibilityHidden(true)
                }
                mutationStatus(message)
            }
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            // « Synchronisation… » est posée en surimpression, sous la ligne, et ne compte pas dans sa hauteur : la liste est
            // ancrée en bas, une hauteur ajoutée ici faisait monter la bulle de 13 pt à la cinquième seconde, au moment
            // où un appui sur la bande des réactions pouvait tomber (échecs des 28 et 31 octobre).
            .overlay(alignment: mine ? .bottomTrailing : .bottomLeading) {
                syncIndicator(message).alignmentGuide(.bottom) { $0[.top] }
            }
        } else if let entry = item.pending {
            pendingStatus(entry)
        }
    }

    /// Lenteur (au-delà de 5 s, sans refus ni reprise à proposer) : indication seule, sans place réservée dans la ligne.
    @ViewBuilder private func syncIndicator(_ message: MessagingWireMessage) -> some View {
        if workspace.rejection(for: message.id) == nil, workspace.mutationAttention(for: message) == .slow {
            Label("Synchronisation…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2).foregroundStyle(DrivyTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("En cours de synchronisation")
                .accessibilityIdentifier("messaging.mutation.slow")
        }
    }

    /// Rien sous 5 s, puis lenteur (en surimpression, voir `syncIndicator`), puis reprise proposée.
    @ViewBuilder private func mutationStatus(_ message: MessagingWireMessage) -> some View {
        if let rejection = workspace.rejection(for: message.id) {
            // Refus de l’école (#177) : l’intention est déjà retirée, il n’y a rien à renvoyer. L’appui ouvre
            // l’explication ; un conflit propose d’actualiser, et masquer est un geste à part.
            Menu {
                Section(rejection.failure.localizedDescription) {
                    if rejection.failure == .stateConflict {
                        Button("Actualiser la conversation", systemImage: "arrow.clockwise") {
                            Task {
                                await workspace.refreshVisible(conversationID: message.conversationID)
                                workspace.clearRejection(message.id)
                            }
                        }
                    }
                    Button("Masquer", systemImage: "eye.slash") { workspace.clearRejection(message.id) }
                        .accessibilityIdentifier("messaging.mutation.rejected.dismiss")
                }
            } label: {
                Label(rejection.summary, systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(DrivyTheme.danger)
                    .contentShape(Rectangle().inset(by: -14))
            }
            .accessibilityLabel(rejection.summary)
            .accessibilityValue(rejection.failure.localizedDescription)
            .accessibilityHint("Ouvre l’explication")
            .accessibilityIdentifier("messaging.mutation.rejected")
        } else if let status = workspace.mutationAttention(for: message) {
            switch status {
            case .slow:
                EmptyView()
            case .offline:
                Label("En attente de connexion", systemImage: "wifi.slash")
                    .font(.caption2).foregroundStyle(DrivyTheme.textTertiary)
                    .accessibilityIdentifier("messaging.mutation.offline")
            case .unconfirmed, .uncertain:
                // Sans confirmation, ce n’est pas un refus : « Réessayer » renvoie la même intention (#104, #177).
                Button { workspace.retryMutations(for: message) } label: {
                    Label("Modification non confirmée · Réessayer", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.caption2).foregroundStyle(DrivyTheme.muted)
                        .contentShape(Rectangle().inset(by: -14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Modification non confirmée")
                .accessibilityHint("Renvoie la même modification")
                .accessibilityIdentifier("messaging.mutation.retry")
            case .storageFailed:
                Button { workspace.retryMutations(for: message) } label: {
                    Label("Modification non conservée · Réessayer", systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(DrivyTheme.danger)
                        .contentShape(Rectangle().inset(by: -14))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Réessaie de conserver la modification sur cet appareil avant de la synchroniser")
                .accessibilityIdentifier("messaging.mutation.storageFailed")
            default:
                EmptyView()
            }
        }
    }

    /// Envoi normal (moins de 5 s) : seule la coche d'Exyte parle. Un vrai problème est nommé et réessayable.
    @ViewBuilder private func pendingStatus(_ entry: MessagingPending) -> some View {
        let presentation = MessagingSendPresentation(status: workspace.sendStatus(entry.clientMessageID))
        if let failure = presentation.failure {
            // L’appui sur « Échec » ouvre l’explication (#177). Un refus qui demande d’abord une correction (accès,
            // appareils, protection) ne propose pas de renvoi aveugle ; le message reste conservé sur l’appareil.
            let description = MessagingDiagnostics.shared.describe(failure)
            HStack(spacing: DrivySpacing.xs) {
                Menu {
                    Section(description) {
                        if presentation.canRetry {
                            Button("Réessayer", systemImage: "arrow.clockwise") { thread.retrySend(displayID: item.id) }
                        }
                    }
                } label: {
                    Label(presentation.label ?? "Échec", systemImage: presentation.symbol).foregroundStyle(DrivyTheme.danger)
                        .contentShape(Rectangle().inset(by: -14))
                }
                .accessibilityLabel("Échec : \(description)")
                .accessibilityHint("Ouvre l’explication")
                .accessibilityIdentifier("messaging.pending.failure")
                if presentation.canRetry { retryButton }
            }
            .font(.caption2)
        } else if let label = presentation.label {
            HStack(spacing: DrivySpacing.xs) {
                Label(label, systemImage: presentation.symbol)
                    .foregroundStyle(DrivyTheme.muted)
                    .accessibilityLabel(presentation.accessibilityLabel)
                    .accessibilityIdentifier("messaging.pending.status")
                if presentation.canRetry { retryButton }
            }
            .font(.caption2)
        }
    }

    private var retryButton: some View {
        Button("Réessayer") { thread.retrySend(displayID: item.id) }
            .font(.caption.weight(.semibold))
            .foregroundStyle(DrivyTheme.accent)
            .frame(minHeight: DrivyLayout.tapTarget)
            .accessibilityHint("Renvoie le même message")
            .accessibilityIdentifier("messaging.pending.retry")
    }
}

/// Bouton explicite, accessible, en tête du fil : la pagination automatique d'Exyte reste un raccourci.
private struct MessagingOlderMessagesButton: View {
    let thread: MessagingThreadModel

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
private struct MessagingThreadFooter: View {
    let thread: MessagingThreadModel
    let onReported: () -> Void
    /// Transmettre un signalement est un acte explicite : la personne voit d'abord qui le lira et ce qu'il contient (#77).
    @State private var confirmingReport = false

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
                MessagingThreadComposer(thread: thread, composer: thread.composer)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { thread.footerResized($0) }
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
            Button("Transmettre (\(thread.reportSelection.count))") { confirmingReport = true }
            .bold()
            .frame(minHeight: DrivyLayout.tapTarget)
            .disabled(thread.reportSelection.isEmpty)
            .accessibilityIdentifier("messaging.report.send")
        }
        .padding(.horizontal, DrivySpacing.m)
        .confirmationDialog("Transmettre aux administrateurs de l'école ?", isPresented: $confirmingReport,
                            titleVisibility: .visible) {
            Button("Transmettre") {
                let selected = workspace.visibleMessages(thread.conversationID).filter { thread.reportSelection.contains($0.id) }
                Task {
                    if await workspace.report(selected, conversationID: thread.conversationID) {
                        thread.reporting = false; thread.reportSelection = []; onReported()
                    }
                }
            }
            .accessibilityIdentifier("messaging.report.confirm")
            Button("Annuler", role: .cancel) {}
        } message: {
            let count = thread.reportSelection.count
            let noun = count == 1 ? "ce message" : "ces \(count) messages"
            Text("Les administrateurs de l'école pourront lire \(noun), avec leur auteur et leur date. Le reste de la conversation ne leur est pas montré.")
        }
    }
}

private struct MessagingThreadComposer: View {
    let thread: MessagingThreadModel
    @Bindable var composer: MessagingComposerModel
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: composer.replyTo?.id)
        .onChange(of: composer.focusRequest) { _, _ in focused = true }
        .onChange(of: composer.blurRequest) { _, _ in focused = false }
        .onChange(of: focused) { _, value in composer.isFocused = value }
    }

    /// Même dessin que la citation dans la bulle : on voit déjà la réponse telle qu'elle partira.
    private func replyPreview(_ message: MessagingWireMessage) -> some View {
        let quote = thread.quote(message.id)
        let title = message.senderID == workspace.scope.accountID
            ? "Répondre à votre message" : "Répondre à \(quote.author ?? "ce message")"
        return HStack(spacing: DrivySpacing.xs) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DrivyTheme.accent)
                .frame(width: DrivyLayout.tapTarget)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                Rectangle().fill(DrivyTheme.accent).frame(width: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.footnote.weight(.semibold)).foregroundStyle(DrivyTheme.accent).lineLimit(1)
                    Text(quote.summary).font(.footnote).italic(!quote.available)
                        .foregroundStyle(DrivyTheme.muted).lineLimit(1)
                }
                .padding(.horizontal, DrivySpacing.xs).padding(.vertical, 6)
                Spacer(minLength: 0)
            }
            .background(DrivyTheme.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
            Button("Annuler la réponse", systemImage: "xmark.circle.fill") { composer.replyTo = nil }
                .labelStyle(.iconOnly).foregroundStyle(DrivyTheme.muted)
                .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
        }
        .fixedSize(horizontal: false, vertical: true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) : \(quote.summary)")
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
                            DrivyAvatar(name: person.displayName, size: 28, photo: workspace.photo(for: person.id))
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
                    // Lire l’erreur et la masquer sont deux choses (#177) : le texte se lit, la croix masque.
                    HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
                        Label(failure.localizedDescription, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(DrivyTheme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("messaging.action.error")
                        Button { workspace.clearActionError() } label: {
                            Image(systemName: "xmark")
                                .font(.footnote.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                                .contentShape(Rectangle().inset(by: -14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Masquer l’erreur")
                        .accessibilityIdentifier("messaging.action.error.dismiss")
                    }
                }
                HStack(spacing: DrivySpacing.xs) {
                    if let detail { Text(detail).font(.caption).foregroundStyle(DrivyTheme.muted) }
                    if let muteStatus, muteStatus != .confirmed {
                        if muteStatus.needsAttention {
                            Button { workspace.retryMute(conversationID) } label: {
                                Label(muteStatus == .storageFailed ? "Sourdine non conservée · Réessayer" : "Sourdine non confirmée · Réessayer",
                                      systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                                    .font(.caption).foregroundStyle(DrivyTheme.muted)
                                    .contentShape(Rectangle().inset(by: -14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("messaging.mute.retry")
                        } else {
                            Label(muteStatus == .offline ? "Sourdine en attente de connexion" : "Modification de la sourdine…",
                                  systemImage: muteStatus == .offline ? "wifi.slash" : "clock")
                                .font(.caption).foregroundStyle(DrivyTheme.muted)
                        }
                    } else if muted, let until = workspace.displayedMutedUntil(conversationID, fallback: mutedUntil) {
                        // La durée restante, comme dans le menu (#168).
                        Label("En sourdine jusqu’à \(MessagingMuteFormat.until(until))", systemImage: "bell.slash")
                            .font(.caption).foregroundStyle(DrivyTheme.muted)
                            .accessibilityIdentifier("messaging.mute.until")
                    }
                }
            }
            .padding(.horizontal, DrivySpacing.m).padding(.vertical, DrivySpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DrivyTheme.surface)
        }
    }
}

/// Fin d’une sourdine : l’heure aujourd’hui, le jour et l’heure au-delà (#168).
enum MessagingMuteFormat {
    struct Choice { let label: String; let seconds: TimeInterval }

    static let durations = [Choice(label: "1 heure", seconds: 3_600),
                            Choice(label: "8 heures", seconds: 8 * 3_600),
                            Choice(label: "1 jour", seconds: 24 * 3_600)]

    static func until(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}

/// Zone d’appui haute de `height`, centrée sur la vue, sans largeur ajoutée : deux pastilles voisines ne se
/// disputent jamais un appui (#142).
private struct MessagingTallHitShape: Shape {
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        let extra = max(0, (height - rect.height) / 2)
        return Path(rect.insetBy(dx: 0, dy: -extra))
    }
}
