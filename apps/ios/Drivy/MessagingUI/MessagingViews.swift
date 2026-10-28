import SwiftUI

/// Liste des discussions de l'école : onglet Messages (#98), pile sur iPhone, liste et conversation sur iPad.
struct MessagingInboxView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var workspace: MessagingWorkspace
    @State private var connectivity = MessagingConnectivity()
    private let initialPeerID: UUID?
    @State private var route: Route?
    @State private var opening = false
    @State private var initialPeerAttempted = false
    @State private var query = ""
    @State private var choosesContact = false
    @State private var showsSettings = false

    fileprivate struct Route: Identifiable, Hashable {
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
    /// L’école de cette messagerie, dite seulement à un compte de plusieurs écoles (#176) ; elle vient de la portée
    /// avec laquelle l’entrée a été composée, jamais d’un cache d’une autre école.
    private let schoolName: String?

    init(workspace: MessagingWorkspace, initialPeerID: UUID? = nil, keys: (any MessagingKeyManagement)? = nil,
         schoolName: String? = nil, currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) {
        _workspace = State(initialValue: workspace)
        self.initialPeerID = initialPeerID
        self.keys = keys
        self.schoolName = schoolName
        self.currentScope = currentScope
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    inbox
                } detail: {
                    NavigationStack {
                        if let route {
                            conversation(route).id(route.id)
                        } else {
                            ContentUnavailableView("Aucune conversation ouverte", systemImage: "bubble.left.and.bubble.right")
                        }
                    }
                }
            } else {
                NavigationStack {
                    inbox.navigationDestination(item: $route) { conversation($0) }
                }
            }
        }
        .onAppear { connectivity.start() }
        .onDisappear { connectivity.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .onChange(of: connectivity.available) { _, available in
            if available { Task { await refresh() } }
        }
        .task { await initialLoad() }
    }

    // MARK: Liste

    /// L’absence est une ligne de la liste, comme dans Élèves (#140) : sous le général s’il est là, jamais par-dessus.
    @ViewBuilder private var inboxEmptyState: some View {
        Group {
            if searchFoundNothing {
                if workspace.canLoadMoreConversations {
                    // La recherche ne lit que les conversations chargées (#167) : jamais un « aucun résultat » définitif.
                    DrivyEmptyState(title: "Aucun résultat parmi les conversations chargées", symbol: "magnifyingglass",
                        actionTitle: "Chercher dans plus de conversations", action: { loadMoreConversations() })
                        .accessibilityIdentifier("messaging.search.partial")
                } else {
                    DrivyEmptyState(title: "Aucun résultat", symbol: "magnifyingglass",
                        actionTitle: "Effacer la recherche", action: { query = "" })
                }
            } else if workspace.hasLoadedConversations && query.isEmpty && privateConversations.isEmpty
                        && workspace.error == nil {
                if hasGeneral {
                    // Le général est là : il n’est pas « aucune conversation », seulement aucune conversation privée (#166).
                    DrivyEmptyState(title: "Aucune conversation privée", symbol: "person.2",
                        actionTitle: "Nouvelle conversation", action: { choosesContact = true })
                        .accessibilityIdentifier("messaging.inbox.noPrivate")
                } else {
                    DrivyEmptyState(title: "Aucune conversation", symbol: "bubble.left.and.bubble.right",
                        actionTitle: "Nouvelle conversation", action: { choosesContact = true })
                        .accessibilityIdentifier("messaging.inbox.empty")
                }
            }
        }
        .buttonStyle(.borderless)
        .listRowSeparator(.hidden)
        .drivyPlainRows()
    }

    private var searchFoundNothing: Bool { !query.isEmpty && visibleConversations.isEmpty && !generalMatchesQuery }
    private var hasGeneral: Bool { showsGeneralShortcut || workspace.conversations.contains { $0.kind == .schoolGeneral } }

    private func loadMoreConversations() {
        Task { await workspace.loadConversations(more: true); await workspace.loadPreviews() }
    }

    private var inbox: some View {
        List {
            if let error = workspace.error {
                Section {
                    VStack(alignment: .leading, spacing: DrivySpacing.s) {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(DrivyTheme.text)
                        Button("Réessayer") { Task { await reload() } }
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("messaging.error")
                }
            }
            if showsGeneralShortcut {
                Button { Task { await openGeneral() } } label: {
                    MessagingInboxRow(title: "Général", preview: nil, unread: 0, muted: false,
                                      photo: nil, isGeneral: true)
                }
                .buttonStyle(.plain)
                .listRowBackground(DrivyTheme.surface)
                .disabled(opening)
                .accessibilityIdentifier("messaging.general.open")
            }
            ForEach(visibleConversations) { item in
                Button { open(item) } label: {
                    MessagingInboxRow(title: item.kind == .schoolGeneral ? "Général" : item.title,
                        preview: workspace.preview(for: item.id),
                        unread: item.unreadCount ?? 0,
                        muted: (item.mutedUntil ?? .distantPast) > Date(),
                        photo: item.peerPersonID.flatMap { workspace.photos[$0] },
                        isGeneral: item.kind == .schoolGeneral)
                }
                .task(id: item.peerPersonID) {
                    if let peer = item.peerPersonID { await workspace.loadPhoto(peer) }
                }
                .buttonStyle(.plain)
                .listRowBackground(route?.id == item.id && horizontalSizeClass == .regular
                    ? DrivyTheme.accent.opacity(0.12) : DrivyTheme.surface)
                .accessibilityIdentifier(item.kind == .schoolGeneral ? "messaging.general.open" : "messaging.conversation.\(item.id)")
            }
            // En recherche aussi : la conversation cherchée peut être sur une page suivante (#167).
            if workspace.canLoadMoreConversations && !searchFoundNothing {
                Button(query.isEmpty ? "Charger plus" : "Chercher dans plus de conversations") { loadMoreConversations() }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("messaging.inbox.more-conversations")
            }
            if !(workspace.loading && !workspace.hasLoadedConversations) { inboxEmptyState }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DrivyTheme.surface.ignoresSafeArea())
        .toolbarBackground(DrivyTheme.surface, for: .navigationBar)
        .overlay {
            if workspace.loading && !workspace.hasLoadedConversations {
                ProgressView("Chargement")
            }
        }
        .navigationTitle("Messages")
        .messagingSchoolSubtitle(schoolName)
        .searchable(text: $query, prompt: "Rechercher une conversation")
        .refreshable { await reload() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { choosesContact = true } label: {
                    Label("Nouvelle conversation", systemImage: "square.and.pencil")
                }
                .disabled(opening)
                .accessibilityIdentifier("messaging.new")
            }
            // Une seule destination : l’engrenage y mène directement, comme celui du Profil.
            ToolbarItem(placement: .topBarLeading) {
                Button { showsSettings = true } label: {
                    Label("Paramètres de Messages", systemImage: "gearshape")
                }
                .accessibilityIdentifier("messaging.settings.open")
            }
        }
        .navigationDestination(isPresented: $showsSettings) {
            MessagingSettingsView(keys: keys, scope: workspace.scope, currentScope: currentScope)
        }
        .sheet(isPresented: $choosesContact) {
            MessagingContactPicker(workspace: workspace) { contact in
                choosesContact = false
                Task { await openPrivate(contact) }
            }
        }
    }

    private var privateConversations: [MessagingConversation] {
        workspace.conversations.filter { $0.kind != .schoolGeneral }
    }

    /// Le général apparaît une fois : sa ligne serveur s'il est listé, sinon un raccourci en tête.
    private var showsGeneralShortcut: Bool {
        !workspace.conversations.contains { $0.kind == .schoolGeneral } && generalMatchesQuery
    }

    private var generalMatchesQuery: Bool {
        query.isEmpty || "Général".range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Le serveur trie par identifiant : la vue range par dernier message connu, puis garde l'ordre reçu.
    private var visibleConversations: [MessagingConversation] {
        let indexed = workspace.conversations.enumerated().map { (offset: $0.offset, item: $0.element,
                                                                    preview: workspace.preview(for: $0.element.id)) }
        let filtered = indexed.filter { entry in
            guard !query.isEmpty else { return true }
            let title = entry.item.kind == .schoolGeneral ? "Général" : entry.item.title
            let haystack = [title, entry.preview?.text ?? ""]
            return haystack.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        return filtered.sorted { lhs, rhs in
            switch (lhs.preview?.date, rhs.preview?.date) {
            case let (l?, r?) where l != r: return l > r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.item)
    }

    @ViewBuilder private func conversation(_ selected: Route) -> some View {
        MessagingConversationView(workspace: workspace, conversationID: selected.id,
            title: selected.title, detail: selected.detail, lastSequence: selected.sequence,
            lastReadSequence: selected.readSequence, mutedUntil: selected.mutedUntil,
            readStateVersion: selected.readStateVersion, isGeneral: selected.isGeneral)
    }

    // MARK: Chargement

    private func initialLoad() async {
        if !workspace.hasLoadedConversations { await workspace.loadConversations() }
        await workspace.loadPreviews()
        await workspace.loadContacts()
        await workspace.refreshVisible()
        if let initialPeerID, !initialPeerAttempted {
            initialPeerAttempted = true
            // Une fiche ne contourne pas le contrôle serveur. La route s'ouvre uniquement après un PUT autorisé.
            if let id = await workspace.privateConversation(peerID: initialPeerID) {
                let contact = workspace.contacts.first { $0.id == initialPeerID }
                let known = workspace.conversations.first { $0.id == id }
                route = Route(id: id, title: contact?.displayName ?? known?.title ?? "Conversation privée",
                              detail: nil, sequence: known?.lastSequence ?? 0,
                              readSequence: known?.lastReadSequence ?? 0, mutedUntil: known?.mutedUntil,
                              readStateVersion: known?.readStateVersion ?? 0, isGeneral: false)
            }
        }
    }

    private func reload() async {
        await workspace.loadConversations()
        await workspace.loadPreviews()
        await workspace.loadContacts()
    }

    private func refresh() async {
        await workspace.refreshVisible(conversationID: route?.id)
        await workspace.loadPreviews()
    }

    // MARK: Ouverture

    private func open(_ item: MessagingConversation) {
        route = Route(id: item.id, title: item.kind == .schoolGeneral ? "Général" : item.title,
                      detail: item.identityDetail ?? (item.kind == .schoolGeneral ? schoolName : nil),
                      sequence: item.lastSequence, readSequence: item.lastReadSequence,
                      mutedUntil: item.mutedUntil, readStateVersion: item.readStateVersion,
                      isGeneral: item.kind == .schoolGeneral)
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
            route = Route(id: id, title: "Général", detail: schoolName, sequence: known?.lastSequence ?? 0,
                          readSequence: known?.lastReadSequence ?? 0, mutedUntil: known?.mutedUntil,
                          readStateVersion: known?.readStateVersion ?? 0, isGeneral: true)
        }
    }
}

// MARK: Cellule

private struct MessagingInboxRow: View {
    let title: String
    let preview: MessagingInboxPreview?
    let unread: Int
    let muted: Bool
    let photo: Data?
    let isGeneral: Bool

    var body: some View {
        HStack(alignment: .center, spacing: DrivySpacing.m) {
            avatar
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
                    Text(title).font(.headline).foregroundStyle(DrivyTheme.text).lineLimit(1)
                    Spacer(minLength: DrivySpacing.xs)
                    if let date = preview?.date {
                        Text(MessagingInboxDate.compact(date))
                            .font(.caption)
                            .foregroundStyle(unread > 0 ? DrivyTheme.accent : DrivyTheme.muted)
                    }
                }
                HStack(alignment: .top, spacing: DrivySpacing.xs) {
                    Text(previewText)
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .lineLimit(2)
                    Spacer(minLength: DrivySpacing.xs)
                    if muted {
                        Image(systemName: "bell.slash.fill").font(.caption).foregroundStyle(DrivyTheme.muted)
                    }
                    if unread > 0 {
                        Text(unread > 99 ? "99+" : unread.formatted())
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(muted ? DrivyTheme.muted : DrivyTheme.accent, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, DrivySpacing.xs)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var avatar: some View {
        if isGeneral {
            Image(systemName: "person.3.fill")
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.accent)
                .frame(width: 48, height: 48)
                .background(DrivyTheme.accent.opacity(0.14), in: Circle())
        } else {
            DrivyAvatar(name: title, size: 48, photo: photo)
        }
    }

    private var previewText: String {
        guard let preview, !preview.unavailable, let text = preview.text, !text.isEmpty else {
            // Raccourci du général sans aperçu : rien à annoncer.
            if isGeneral && self.preview == nil { return "" }
            return "Message chiffré"
        }
        return preview.fromMe ? "Toi : \(text)" : text
    }

    private var accessibilityText: String {
        var parts = [title]
        if unread > 0 { parts.append(unread == 1 ? "1 message non lu" : "\(unread) messages non lus") }
        if !previewText.isEmpty { parts.append(previewText) }
        if let date = preview?.date { parts.append(date.formatted(.relative(presentation: .named))) }
        if muted { parts.append("en sourdine") }
        return parts.joined(separator: ", ")
    }
}

enum MessagingInboxDate {
    /// Heure aujourd'hui, « hier », jour de la semaine, puis date courte.
    static func compact(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) { return "Hier" }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                              to: calendar.startOfDay(for: now)).day, days < 7, days > 0 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits))
    }
}

// MARK: Nouvelle conversation

private struct MessagingContactPicker: View {
    let workspace: MessagingWorkspace
    let choose: (MessagingContact) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// Tant que la lecture n’a pas répondu, rien n’est dit des contacts : « Aucun contact » n’est jamais une attente.
    @State private var loaded = false

    private var contacts: [MessagingContact] {
        let all = workspace.contacts.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        guard !query.isEmpty else { return all }
        return all.filter { $0.displayName.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(contacts) { contact in
                    Button { choose(contact) } label: {
                        HStack(spacing: DrivySpacing.m) {
                            DrivyAvatar(name: contact.displayName, size: 40, photo: workspace.photos[contact.id])
                            Text(contact.displayName).foregroundStyle(DrivyTheme.text)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(contact.displayName)
                    .task { if workspace.photos[contact.id] == nil { await workspace.loadPhoto(contact.id) } }
                }
                contactsState
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher")
            .navigationTitle("Nouvelle conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
            .task { await load() }
        }
        .accessibilityIdentifier("messaging.contacts")
    }

    private func load() async {
        await workspace.loadContacts()
        loaded = true
    }

    /// Attente, panne et vraie absence se distinguent (#140) ; une panne garde « Réessayer ».
    @ViewBuilder private var contactsState: some View {
        if contacts.isEmpty {
            Group {
                if !loaded {
                    DrivyLoadingState(title: "Chargement des contacts…")
                } else if workspace.contacts.isEmpty, let error = workspace.error {
                    SchoolErrorNotice(message: error.localizedDescription, retry: { loaded = false; Task { await load() } })
                } else if query.isEmpty {
                    DrivyEmptyState(title: "Aucun contact", symbol: "person.crop.circle.badge.questionmark")
                } else {
                    DrivyEmptyState(title: "Aucun résultat", symbol: "magnifyingglass",
                        actionTitle: "Effacer la recherche", action: { query = "" })
                }
            }
            .buttonStyle(.borderless)
            .listRowSeparator(.hidden)
            .drivyPlainRows()
        }
    }
}

private extension View {
    /// L’école sous le titre, seulement quand elle est utile à dire (#176).
    @ViewBuilder func messagingSchoolSubtitle(_ name: String?) -> some View {
        if let name, !name.isEmpty { navigationSubtitle(name) } else { self }
    }
}
