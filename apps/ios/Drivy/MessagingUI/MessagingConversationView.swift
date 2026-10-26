import SwiftUI

/// Conversation v2 : fil ancré en bas (anciens en haut, récents près du composeur), séparateurs de jour,
/// regroupement par auteur, envois en attente intégrés au fil, bandeau épinglé, recherche locale,
/// sélection pour signalement, lecture seule après la fin du lien (composeur masqué).
struct MessagingConversationView: View {
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
    @State private var selectedMentions: [MessagingMentionSelection] = []
    @State private var draft = ""
    @State private var draftReady = false
    @State private var draftFailure: String?
    @State private var queued: [MessagingPending] = []
    /// Échec avant la mise en file (protection indisponible, contexte changé) : le brouillon reste.
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
    @State private var highlighted: UUID?
    @State private var notice: String?
    @State private var atBottom = true
    @State private var unseenBelow = false
    @State private var loadingOlder = false
    @FocusState private var composerFocused: Bool

    private static let bottomID = "messaging.thread.bottom"
    /// Deux messages du même auteur à moins de cinq minutes forment un groupe.
    private static let groupWindow: TimeInterval = 300

    private var access: MessagingConversationAccess { workspace.access(for: conversationID) }
    /// Ordre ascendant : le plus ancien en haut, le plus récent en bas.
    private var messages: [MessagingWireMessage] { workspace.visibleMessages(conversationID) }

    var body: some View {
        VStack(spacing: 0) {
            statusStrip
            ScrollViewReader { proxy in
                thread(proxy)
                    .overlay(alignment: .top) {
                        // Épinglé en pastille flottante au-dessus du fil : il ne pousse plus le contenu.
                        VStack(spacing: 0) {
                            MessagingPinnedBanner(workspace: workspace, pinned: workspace.pinnedMessages(conversationID)) { scrollTarget = $0 }
                            noticeView
                        }
                    }
                    .overlay(alignment: .bottomTrailing) { jumpToBottom(proxy) }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        // #100 : fond Drivy continu jusqu'au bord, clavier compris ; seul le fond déborde.
                        footer.background(DrivyTheme.surface.ignoresSafeArea(.container, edges: .bottom)
                            .ignoresSafeArea(.keyboard, edges: .bottom))
                    }
                    .onChange(of: scrollTarget) { _, target in
                        guard let target else { return }
                        scrollTarget = nil
                        Task { await jump(to: target, proxy: proxy) }
                    }
                    .onChange(of: messages.last?.id) { _, _ in
                        if atBottom || messages.last?.senderID == workspace.scope.accountID {
                            scrollToBottom(proxy, animated: true)
                        } else {
                            unseenBelow = true
                        }
                    }
                    .onChange(of: queued.count) { old, new in
                        if new > old { scrollToBottom(proxy, animated: true) }
                    }
                    .onChange(of: composerFocused) { _, focused in
                        guard focused, atBottom else { return }
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            scrollToBottom(proxy, animated: true)
                        }
                    }
            }
        }
        .background(DrivyTheme.canvas.ignoresSafeArea())
        .toolbarBackground(DrivyTheme.canvas, for: .navigationBar)
        .navigationTitle(reporting ? "Signaler" : title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase == .active && atBottom ? workspace.lastReadableSequence(conversationID) : nil) { if scenePhase == .active, atBottom, let seq = workspace.lastReadableSequence(conversationID) { await workspace.conversationViewed(conversationID, upTo: seq) } }
        .onAppear { connectivity.start(); MessagingActiveConversation.set(schoolID: workspace.scope.schoolID, conversationID: conversationID, atBottom: atBottom) }
        .onDisappear { connectivity.stop(); MessagingActiveConversation.clear(conversationID) }
        .onChange(of: atBottom) { _, bottom in MessagingActiveConversation.set(schoolID: workspace.scope.schoolID, conversationID: conversationID, atBottom: bottom) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await workspace.refreshVisible(conversationID: conversationID) } }
        }
        .onChange(of: connectivity.available) { _, available in
            workspace.setNetworkAvailable(available)
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
        .sheet(isPresented: $showPollComposer) {
            MessagingPollComposer { poll, multiple in
                await send(MessagingPlainContent(poll: poll), pollAllowsMultiple: multiple)
            }
        }
        .sheet(isPresented: $showSearch) {
            // La feuille se ferme depuis ici : avec `.searchable` actif, `dismiss()` ne fermait que le champ.
            MessagingSearchView(workspace: workspace, conversationID: conversationID, conversationTitle: title) {
                showSearch = false
                scrollTarget = $0
            }
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

    // MARK: - Fil

    private func thread(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if workspace.canLoadMoreMessages(conversationID) {
                    Button {
                        Task { await loadOlder(proxy) }
                    } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            if loadingOlder { ProgressView().controlSize(.small) }
                            Text("Charger les messages précédents")
                        }
                        .font(.subheadline)
                        .frame(minHeight: DrivyLayout.tapTarget)
                        .padding(.horizontal, DrivySpacing.m)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DrivyTheme.accent)
                    .disabled(loadingOlder)
                    .padding(.vertical, DrivySpacing.xs)
                }
                ForEach(rows) { row in
                    if let day = row.dayBreak { daySeparator(day) }
                    rowView(row)
                        .padding(.top, row.startsGroup ? DrivySpacing.xs : 2)
                        .id(row.message.id)
                }
                ForEach(queued.filter { !workspace.isDelivered($0) }, id: \.clientMessageID) { entry in
                    MessagingPendingBubble(entry: entry, status: workspace.sendStatus(entry.clientMessageID)) {
                        retry(entry)
                    }
                    .padding(.top, 2)
                    .id(entry.clientMessageID)
                }
                Color.clear.frame(height: DrivySpacing.xs).id(Self.bottomID)
            }
            .padding(.horizontal, DrivySpacing.s)
            .frame(maxWidth: DrivyLayout.readingColumn)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(DrivyTheme.canvas)
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(distanceToBottom: geometry.contentSize.height - geometry.visibleRect.maxY,
                          contentHeight: geometry.contentSize.height,
                          containerHeight: geometry.containerSize.height)
        } action: { old, new in
            // Une variation de taille (clavier, rotation, déchiffrement, réaction) ne fait jamais quitter le bas.
            if atBottom && (old.containerHeight != new.containerHeight || old.contentHeight != new.contentHeight) && !loadingOlder {
                if new.distanceToBottom > 1 { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                return
            }
            atBottom = new.distanceToBottom < 48
            if atBottom { unseenBelow = false }
        }
    }

    private struct ScrollMetrics: Equatable {
        let distanceToBottom: CGFloat
        let contentHeight: CGFloat
        let containerHeight: CGFloat
    }

    private struct ThreadRow: Identifiable {
        let message: MessagingWireMessage
        let dayBreak: Date?
        let startsGroup: Bool
        let endsGroup: Bool
        var id: UUID { message.id }
    }

    private var rows: [ThreadRow] {
        let list = messages
        let calendar = Calendar.current
        func grouped(_ a: MessagingWireMessage, _ b: MessagingWireMessage) -> Bool {
            a.senderID == b.senderID && calendar.isDate(a.acceptedAt, inSameDayAs: b.acceptedAt)
                && abs(b.acceptedAt.timeIntervalSince(a.acceptedAt)) < Self.groupWindow
        }
        return list.indices.map { index in
            let message = list[index]
            let previous = index > list.startIndex ? list[index - 1] : nil
            let next = index < list.endIndex - 1 ? list[index + 1] : nil
            let newDay = previous.map { !calendar.isDate($0.acceptedAt, inSameDayAs: message.acceptedAt) } ?? true
            return ThreadRow(message: message,
                             dayBreak: newDay ? message.acceptedAt : nil,
                             startsGroup: newDay || previous.map { !grouped($0, message) } ?? true,
                             endsGroup: next.map { !grouped(message, $0) } ?? true)
        }
    }

    private func daySeparator(_ date: Date) -> some View {
        Text(Self.dayLabel(date))
            .font(.caption.weight(.semibold))
            .foregroundStyle(DrivyTheme.muted)
            .padding(.horizontal, DrivySpacing.s).padding(.vertical, DrivySpacing.xxs)
            .background(DrivyTheme.surfaceMuted, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.top, DrivySpacing.m).padding(.bottom, DrivySpacing.xxs)
            .accessibilityAddTraits(.isHeader)
    }

    private static func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(date) { return "Hier" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide).year())
    }

    @ViewBuilder private func rowView(_ row: ThreadRow) -> some View {
        let message = row.message
        let bubble = MessagingBubble(workspace: workspace, message: message, isGeneral: isGeneral,
            selecting: reporting, selected: reportSelection.contains(message.id),
            showsAuthor: row.startsGroup, showsMeta: row.endsGroup, highlighted: highlighted == message.id,
            onReply: { replyTo = message; composerFocused = true }, onJump: { scrollTarget = $0 })
        if reporting && !message.meta.deletedForEveryone {
            Button {
                if reportSelection.contains(message.id) { reportSelection.remove(message.id) } else { reportSelection.insert(message.id) }
            } label: { bubble }
            .buttonStyle(.plain)
            .accessibilityAddTraits(reportSelection.contains(message.id) ? [.isSelected] : [])
            .accessibilityHint("Sélectionne ce message pour le signalement")
        } else {
            bubble
        }
    }

    @ViewBuilder private var statusStrip: some View {
        let muted = workspace.displayedMutedUntil(conversationID, fallback: mutedUntil).map { $0 > Date() } ?? false
        if workspace.error != nil || workspace.actionError != nil || detail != nil || muted {
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
                    if muted {
                        Label("En sourdine", systemImage: "bell.slash").font(.caption).foregroundStyle(DrivyTheme.muted)
                    }
                }
            }
            .padding(.horizontal, DrivySpacing.m).padding(.vertical, DrivySpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DrivyTheme.surface)
        }
    }

    @ViewBuilder private var noticeView: some View {
        if let notice {
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

    @ViewBuilder private func jumpToBottom(_ proxy: ScrollViewProxy) -> some View {
        if !atBottom {
            Button { scrollToBottom(proxy, animated: true) } label: {
                HStack(spacing: DrivySpacing.xxs) {
                    Image(systemName: "arrow.down")
                    if unseenBelow { Text("Nouveaux messages").font(.footnote.weight(.semibold)) }
                }
                .foregroundStyle(unseenBelow ? DrivyTheme.onAccent : DrivyTheme.accent)
                .padding(.horizontal, unseenBelow ? DrivySpacing.s : 0)
                .frame(minWidth: DrivyLayout.tapTarget, minHeight: DrivyLayout.tapTarget)
                .background(unseenBelow ? AnyShapeStyle(DrivyTheme.accentFill) : AnyShapeStyle(DrivyTheme.surfaceRaised), in: Capsule())
                .overlay(Capsule().stroke(DrivyTheme.border, lineWidth: unseenBelow ? 0 : 1))
                .shadow(color: DrivyTheme.shadow.opacity(0.12), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .padding(DrivySpacing.m)
            .accessibilityLabel(unseenBelow ? "Nouveaux messages, revenir en bas" : "Revenir en bas")
            .accessibilityIdentifier("messaging.scroll.bottom")
            .transition(.opacity)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        withAnimation(animated ? DrivyMotion.settle(reduceMotion) : nil) {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
        unseenBelow = false
    }

    /// Les anciens messages arrivent au-dessus : le premier message lu reste à sa place.
    private func loadOlder(_ proxy: ScrollViewProxy) async {
        guard !loadingOlder else { return }
        let anchor = messages.first?.id
        loadingOlder = true
        await workspace.loadMessages(conversationID, more: true)
        if let anchor {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(anchor, anchor: .top) }
        }
        // La variation de hauteur arrive après ce cycle : garder le drapeau le temps que la
        // correction d'ancrage ne soit pas prise pour un suivi du bas du fil.
        try? await Task.sleep(for: .milliseconds(400))
        loadingOlder = false
    }

    /// Citation, épingle ou recherche : charge le contexte si besoin, puis met le message brièvement en évidence.
    private func jump(to id: UUID, proxy: ScrollViewProxy) async {
        var pages = 0
        while !messages.contains(where: { $0.id == id }), workspace.canLoadMoreMessages(conversationID), pages < 10 {
            await workspace.loadMessages(conversationID, more: true)
            pages += 1
        }
        guard messages.contains(where: { $0.id == id }) else {
            await show(notice: "Message indisponible")
            return
        }
        // Laisse la feuille de recherche se refermer : un défilement lancé pendant sa disparition est perdu.
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(DrivyMotion.settle(reduceMotion)) { proxy.scrollTo(id, anchor: .center) }
        // Deuxième passe après le rendu paresseux du voisinage, sinon la cible reste hors écran.
        try? await Task.sleep(for: .milliseconds(250))
        proxy.scrollTo(id, anchor: .center)
        withAnimation(DrivyMotion.feedback(reduceMotion)) { highlighted = id }
        try? await Task.sleep(for: .milliseconds(1_500))
        if highlighted == id { withAnimation(DrivyMotion.settle(reduceMotion)) { highlighted = nil } }
    }

    private func show(notice text: String) async {
        withAnimation(DrivyMotion.feedback(reduceMotion)) { notice = text }
        AccessibilityNotification.Announcement(text).post()
        try? await Task.sleep(for: .seconds(3))
        if notice == text { withAnimation(DrivyMotion.feedback(reduceMotion)) { notice = nil } }
    }

    // MARK: - Pied

    @ViewBuilder private var footer: some View {
        if reporting {
            HStack {
                Button("Annuler") {
                    Task {
                        if await workspace.abandonReport(conversationID: conversationID) {
                            reporting = false
                            reportSelection = []
                        }
                    }
                }
                .frame(minHeight: DrivyLayout.tapTarget)
                Spacer()
                Button("Transmettre (\(reportSelection.count))") {
                    let selected = messages.filter { reportSelection.contains($0.id) }
                    Task {
                        if await workspace.report(selected, conversationID: conversationID) {
                            reporting = false; reportSelection = []; reportSent = true
                        }
                    }
                }
                .bold()
                .frame(minHeight: DrivyLayout.tapTarget)
                .disabled(reportSelection.isEmpty)
                .accessibilityIdentifier("messaging.report.send")
            }
            .padding(.horizontal, DrivySpacing.m)
        } else if access.isReadOnly {
            // Fin du lien : l'historique reste lisible, aucun envoi possible.
            Label("Lecture seule", systemImage: "lock")
                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                .frame(maxWidth: .infinity).padding()
                .accessibilityIdentifier("messaging.readonly")
        } else {
            composer
        }
    }

    private var canSend: Bool {
        !sending && draftReady && draftFailure == nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            if let failure = deliveryLabel ?? draftFailure {
                Text(failure)
                    .font(.footnote).foregroundStyle(DrivyTheme.danger)
                    .padding(.horizontal, DrivySpacing.s)
                    .accessibilityIdentifier(deliveryLabel != nil ? "messaging.delivery" : "messaging.draft.error")
            }
            if let replyTo { replyPreview(replyTo) }
            if isGeneral, let query = mentionQuery { mentionSuggestions(query) }
            HStack(alignment: .bottom, spacing: DrivySpacing.xs) {
                Menu {
                    Button("Sondage", systemImage: "chart.bar.xaxis") { showPollComposer = true }
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
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .foregroundStyle(DrivyTheme.text)
                    .padding(.horizontal, DrivySpacing.s)
                    .padding(.vertical, 10)
                    .frame(minHeight: DrivyLayout.tapTarget)
                    .background(DrivyTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityLabel("Rédiger un message")
                    .accessibilityIdentifier("messaging.compose.text")
                    .onChange(of: draft) { _, text in
                        // Une mention effacée du texte n'est plus envoyée (#101).
                        selectedMentions.removeAll { !text.contains("@\($0.displayName)") }
                    }
                Button {
                    Task { _ = await send(MessagingPlainContent(text: draft)) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(canSend ? DrivyTheme.onAccent : DrivyTheme.disabledText)
                        .frame(width: 36, height: 36)
                        .background(canSend ? DrivyTheme.accentFill : DrivyTheme.disabledSurface, in: Circle())
                        .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Envoyer")
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, DrivySpacing.xs)
        .padding(.vertical, DrivySpacing.xs)
    }

    private func replyPreview(_ message: MessagingWireMessage) -> some View {
        HStack(spacing: DrivySpacing.xs) {
            RoundedRectangle(cornerRadius: 1.5).fill(DrivyTheme.accent).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Réponse à \(workspace.displayName(message.senderID))").font(.caption.bold()).foregroundStyle(DrivyTheme.accent)
                Text(workspace.contents[message.id]?.summary ?? "Message").font(.caption).lineLimit(1).foregroundStyle(DrivyTheme.muted)
            }
            Spacer(minLength: 0)
            Button("Annuler la réponse", systemImage: "xmark.circle.fill") { self.replyTo = nil }
                .labelStyle(.iconOnly).foregroundStyle(DrivyTheme.muted)
                .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
        }
        .padding(.leading, DrivySpacing.s)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messaging.reply.preview")
    }

    /// Jeton `@xxx` en cours de frappe à la fin du brouillon (#101), nil sinon.
    private var mentionQuery: String? { MessagingMentionToken.query(in: draft) }

    private func mentionSuggestions(_ query: String) -> some View {
        let people = MessagingMentionToken.filter(workspace.generalMembers.filter { $0.id != workspace.scope.accountID },
                                                   query: query, name: \.displayName)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(people.prefix(6)) { person in
                    Button { insertMention(person) } label: {
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

    private func insertMention(_ person: MessagingContact) {
        guard let replaced = MessagingMentionToken.replacing(in: draft, with: person.displayName) else { return }
        draft = replaced
        if !selectedMentions.contains(where: { $0.personID == person.id }) && selectedMentions.count < 8 {
            selectedMentions.append(MessagingMentionSelection(personID: person.id, displayName: person.displayName))
        }
        composerFocused = true
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Rechercher", systemImage: "magnifyingglass") { showSearch = true }
                .accessibilityIdentifier("messaging.search.open")
            Menu("Options", systemImage: "ellipsis.circle") {
                if isGeneral { Button("Membres", systemImage: "person.3") { showMembers = true } }
                Button("Signaler des messages", systemImage: "exclamationmark.bubble") { reporting = true }
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

    // MARK: - Envoi

    /// La file chiffrée sur disque précède toute tentative réseau. `sending` ne couvre que la mise en file
    /// durable : l'envoi réseau part ensuite dans la file FIFO du workspace, sans bloquer le compositeur.
    private func send(_ content: MessagingPlainContent, pollAllowsMultiple: Bool = false) async -> Bool {
        guard !sending, draftReady, access.canWrite else { return false }
        sending = true
        let isText = content.poll == nil
        let submitted = draft
        let submittedMentions = selectedMentions.map(\.personID)
        do {
            let entry = try await workspace.enqueue(content: content, conversationID: conversationID,
                mentions: submittedMentions, replyTo: replyTo?.id, pollAllowsMultiple: pollAllowsMultiple)
            deliveryLabel = nil
            queued.append(entry)
            replyTo = nil
            if selectedMentions.map(\.personID) == submittedMentions { selectedMentions = [] }
            if isText && draft == submitted { draft = "" }
            sending = false
            workspace.scheduleSend(entry)
            if isText {
                // Brouillon vidé après la mise en file durable ; la saisie suivante reste protégée.
                try? await workspace.saveDraft(draft, conversationID: conversationID)
            }
            return true
        } catch {
            sending = false
            deliveryLabel = MessagingDiagnostics.shared.describe(error as? MessagingFailure ?? .protectionUnavailable)
            return false
        }
    }

    private func retry(_ entry: MessagingPending) {
        workspace.retrySend(entry)
    }
}

/// Envoi encore dans la file protégée : bulle sortante avec son état réel. « Envoyé » seulement après l'accusé.
struct MessagingPendingBubble: View {
    let entry: MessagingPending
    let status: MessagingWorkspace.SendStatus?
    let onRetry: () -> Void

    private var summary: String {
        entry.recoveryContent.flatMap(MessagingPlainContent.decode)?.summary ?? "Message"
    }

    private var refused: MessagingFailure? {
        if case .failed(let failure)? = status { return failure }
        return nil
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: DrivySpacing.xxs) {
            // Même bulle qu'un message envoyé : pas de contour pointillé qui clignote pendant l'envoi normal.
            // Seul un vrai problème (refus) change la bulle ; les autres états restent sur la ligne d'état.
            Text(summary)
                .foregroundStyle(DrivyTheme.text)
                .padding(.horizontal, DrivySpacing.s).padding(.vertical, DrivySpacing.xs)
                .background(DrivyTheme.accentSoft, in: MessagingBubbleShape(mine: true, tail: true))
                .overlay(MessagingBubbleShape(mine: true, tail: true)
                    .stroke(refused == nil ? Color.clear : DrivyTheme.danger, lineWidth: 1))
                .opacity(quiet ? 1 : 0.85)
            stateLine.font(.caption2)
                .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.2), value: quiet)
        .padding(.leading, 56)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messaging.pending")
    }

    /// Envoi normal en cours (moins de 5 s) ou accepté : aucune mention d'état, la bulle est déjà à sa place.
    private var quiet: Bool {
        switch status {
        case .queued?, .sending?, .accepted?, nil: true
        default: false
        }
    }

    @ViewBuilder private var stateLine: some View {
        switch status {
        case .failed(let failure)?:
            HStack(spacing: DrivySpacing.xs) {
                Label("Échec", systemImage: "exclamationmark.circle")
                    .foregroundStyle(DrivyTheme.danger)
                    .accessibilityLabel("Échec : \(MessagingDiagnostics.shared.describe(failure))")
                retryButton
            }
        case .unconfirmed?, .uncertain?:
            HStack(spacing: DrivySpacing.xs) {
                Label("Non confirmé", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundStyle(DrivyTheme.muted)
                    .accessibilityLabel("Envoi non confirmé")
                retryButton
            }
        case .offline?:
            Label("En attente de connexion", systemImage: "wifi.slash").foregroundStyle(DrivyTheme.muted)
        case .slow?:
            Label("Envoi…", systemImage: "clock").foregroundStyle(DrivyTheme.muted)
        case .accepted?:
            // Coche discrète le temps que le message serveur remplace la bulle.
            Image(systemName: "checkmark").foregroundStyle(DrivyTheme.textTertiary)
                .accessibilityLabel("Envoyé")
                .accessibilityIdentifier("messaging.pending.sent")
        case .sending?, .queued?, nil:
            // Rien à lire pendant un envoi normal ; VoiceOver annonce l'état.
            Color.clear.frame(height: 0).accessibilityLabel("Envoi en cours")
        }
    }

    private var retryButton: some View {
        Button("Réessayer", action: onRetry)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DrivyTheme.accent)
            .frame(minHeight: DrivyLayout.tapTarget)
            .accessibilityHint("Renvoie le même message")
            .accessibilityIdentifier("messaging.pending.retry")
    }
}
