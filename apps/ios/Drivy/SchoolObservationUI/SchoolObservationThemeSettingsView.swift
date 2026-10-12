import SwiftUI

/// Réglage des signalements : lesquels « Signaler » propose pendant une leçon, et dans quel ordre.
/// Liste groupée native, comme le Profil dont elle vient. Deux réglages distincts s’y rencontrent :
/// - l’ordre et l’affichage **de l’école**, pour qui peut les gérer (le droit vient de l’école, qui le revérifie à
///   chaque écriture) : poignées et glisser-déposer du système, chaque changement part aussitôt ;
/// - le **classement intelligent**, propre à chaque moniteur : l’école range alors ses signalements d’après ses
///   usages. La liste montre cet ordre automatique sans poignées ; il ne s’écrit jamais dans l’ordre de l’école,
///   que l’on retrouve intact en désactivant l’option.
/// Un moniteur sans droit de gestion lit la liste des thèmes affichés et règle seulement son classement.
struct SchoolObservationThemeSettingsView: View {
    let store: SchoolObservationThemeStore
    /// `nil` : pas de classement pour ce compte ; l’écran est alors celui de l’ordre de l’école seul.
    var ranking: SchoolObservationRankingStore? = nil
    @State private var showsPreview = false
    @State private var confirmsReset = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Les rangées portent déjà leur espacement vertical : sans cela, la liste le double.
    private var rowInsets: EdgeInsets { EdgeInsets(top: 0, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m) }
    private var noticeInsets: EdgeInsets { EdgeInsets(top: DrivySpacing.xs, leading: 0, bottom: DrivySpacing.xs, trailing: 0) }

    /// L’ordre montré est celui du classement : dès le geste, pendant l’envoi compris.
    private var isAutomatic: Bool { ranking?.displayedMode == .smart }
    /// Réordonner à la main : seulement l’ordre de l’école, par qui peut le gérer.
    private var reorders: Bool { store.canEdit && !isAutomatic }
    /// L’ordre montré : celui de l’école, ou son réarrangement automatique (affichés d’abord, masqués ensuite).
    /// `store.displayed` reste l’ordre de l’école : c’est lui, et lui seul, que les écritures envoient.
    private var shownThemes: [SchoolObservationTheme] {
        isAutomatic ? SchoolObservationRankingOrder.arranged(store.displayed, order: ranking?.effectiveOrder) : store.displayed
    }

    var body: some View {
        List {
            messages
            rankingSection
            if store.configuration.isFromServer {
                if store.canEdit {
                    themeSection
                    resetSection
                } else {
                    readOnlySection
                }
            } else if store.isLoading {
                Section {
                    DrivySkeletonRows(count: 6, lines: 1).drivySkeleton("Chargement des signalements…")
                        .listRowInsets(noticeInsets)
                }
                .drivyClearRow()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // Poignées visibles sans mode à ouvrir quand l’ordre se règle à la main ; aucune en ordre automatique.
        .environment(\.editMode, .constant(reorders ? .active : .inactive))
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .navigationTitle("Signalements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Aperçu") { showsPreview = true }
                    .disabled(!store.configuration.isFromServer)
                    .accessibilityIdentifier("observation-themes-preview")
            }
        }
        .sheet(isPresented: $showsPreview) {
            SchoolObservationThemePreviewSheet(themes: shownThemes)
        }
        .confirmationDialog("Rétablir les signalements d’origine et leur ordre ?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Rétablir", role: .destructive) { store.resetAll() }
            Button("Annuler", role: .cancel) { }
        }
        // Retour à l’état confirmé après un échec, configuration relue, changement de mode : les rangées glissent à leur place.
        .animation(DrivyMotion.context(reduceMotion), value: shownThemes.map(\.key))
        .animation(DrivyMotion.context(reduceMotion), value: isAutomatic)
        .onChange(of: store.saveState) { _, state in announce(state) }
        .onChange(of: ranking?.confirmedChanges) { _, _ in announceRanking() }
        .onChange(of: ranking?.failureMessage) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
        .onDisappear {
            store.clearNotice()
            ranking?.clearNotice()
        }
        .task { _ = await store.refresh() }
        .task { _ = await ranking?.refresh() }
        .accessibilityIdentifier("observation-themes")
    }

    // MARK: Messages

    /// Un message seulement pour l’inhabituel : un échec, un réglage changé ailleurs, une lecture impossible.
    @ViewBuilder private var messages: some View {
        if let ranking {
            if let message = ranking.failureMessage {
                Section {
                    SchoolErrorNotice(message: message, retry: ranking.canRetry ? { ranking.retry() } : nil)
                        .listRowInsets(noticeInsets)
                }
                .drivyClearRow()
            } else if let notice = ranking.notice {
                Section {
                    DrivyInlineMessage(text: notice, tone: .warning)
                        .listRowInsets(noticeInsets)
                }
                .drivyClearRow()
            }
        }
        if case .failed(let message) = store.saveState {
            Section {
                SchoolErrorNotice(message: message, retry: store.canRetry ? { store.retry() } : nil)
                    .listRowInsets(noticeInsets)
            }
            .drivyClearRow()
        } else if let notice = store.notice {
            Section {
                DrivyInlineMessage(text: notice, tone: .warning)
                    .listRowInsets(noticeInsets)
            }
            .drivyClearRow()
        } else if !store.isLoading, !store.canEdit, let error = store.loadError {
            Section {
                SchoolErrorNotice(message: error, retry: { Task { await store.refresh() } })
                    .listRowInsets(noticeInsets)
            }
            .drivyClearRow()
        }
    }

    // MARK: Classement intelligent

    /// Absent tant que l’école n’a pas répondu, et pour une école qui ne connaît pas encore le classement.
    /// L’interrupteur montre la proposition pendant l’envoi, puis l’état que l’école confirme.
    @ViewBuilder private var rankingSection: some View {
        if let ranking, ranking.isAvailable {
            Section {
                Toggle(isOn: Binding(get: { ranking.displayedMode == .smart }, set: { ranking.setSmart($0) })) {
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text("Classement intelligent")
                            .foregroundStyle(DrivyTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Organise automatiquement vos signalements selon vos habitudes d’utilisation.")
                            .font(.footnote)
                            .foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, DrivySpacing.xs)
                }
                .drivyControlTint()
                .frame(minHeight: DrivyLayout.tapTarget)
                .listRowInsets(rowInsets)
                .accessibilityIdentifier("observation-ranking-smart")
            }
            .drivyFormRows()
        }
    }

    private func announceRanking() {
        guard let ranking else { return }
        let spoken = ranking.mode == .smart ? "Classement intelligent activé" : "Classement intelligent désactivé"
        AccessibilityNotification.Announcement(spoken).post()
    }

    // MARK: Thèmes

    private var themeSection: some View {
        let themes = shownThemes
        // Aucun déplacement en ordre automatique : ni poignée, ni glisser-déposer.
        let move: ((IndexSet, Int) -> Void)? = reorders ? { source, destination in
            var moved = store.displayed
            moved.move(fromOffsets: source, toOffset: destination)
            store.propose(moved)
        } : nil
        return Section {
            ForEach(themes) { theme in
                row(theme, position: (themes.firstIndex(of: theme) ?? 0) + 1, count: themes.count)
                    .listRowInsets(rowInsets)
            }
            .onMove(perform: move)
            .moveDisabled(!reorders)
        } header: {
            // Compteur et indication sur une ligne quand elle tient ; sinon l’indication passe dessous.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                    countText
                    automaticText
                    Spacer(minLength: DrivySpacing.xs)
                    saveStatus
                }
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                        countText
                        Spacer(minLength: DrivySpacing.xs)
                        saveStatus
                    }
                    automaticText
                }
            }
            .drivyFormSectionHeader()
        }
        .drivyFormRows()
    }

    private var countText: some View {
        Text(countLabel).monospacedDigit()
            .accessibilityIdentifier("observation-themes-count")
    }

    /// Seule indication du mode dans la liste : discrète, à côté du compteur.
    @ViewBuilder private var automaticText: some View {
        if isAutomatic {
            Text("Ordre automatique")
                .accessibilityIdentifier("observation-themes-automatic")
        }
    }

    private var countLabel: String {
        let visible = store.visibleCount
        return "\(visible) \(visible > 1 ? "affichés" : "affiché") sur \(store.displayed.count)"
    }

    /// L’interrupteur est la rangée : son libellé nomme le thème, son état dit s’il est proposé en leçon. Il reste
    /// actif en ordre automatique : afficher ou masquer un thème modifie la configuration de l’école, envoyée
    /// dans son ordre à elle (`store.setVisible` part de `store.displayed`).
    /// « Monter » et « Descendre » font le même déplacement que la poignée, pour VoiceOver et la commande vocale ;
    /// ils n’existent pas en ordre automatique.
    private func row(_ theme: SchoolObservationTheme, position: Int, count: Int) -> some View {
        Toggle(isOn: Binding(get: { theme.visible }, set: { store.setVisible($0, key: theme.key) })) {
            HStack(spacing: DrivySpacing.s) {
                DrivyObservationGlyphImage(glyph: theme.glyph)
                    .foregroundStyle(theme.visible ? DrivyTheme.accent : DrivyTheme.textTertiary)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(theme.title)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, DrivySpacing.xs)
        }
        .drivyControlTint()
        .frame(minHeight: DrivyLayout.tapTarget)
        // Un thème que l’école ne liste pas encore (école plus ancienne que l’app) reste masqué et ne se règle pas.
        .disabled(!store.canEdit || store.configuration.unlisted.contains(theme.key))
        .accessibilityHint("Position \(position) sur \(count)")
        .accessibilityActions {
            if reorders {
                Button("Monter") { move(theme, by: -1) }
                Button("Descendre") { move(theme, by: 1) }
            }
        }
        .accessibilityIdentifier("observation-theme-\(theme.key)")
    }

    private func move(_ theme: SchoolObservationTheme, by delta: Int) {
        guard reorders, let index = store.move(key: theme.key, by: delta) else { return }
        let spoken: String = "\(theme.title), position \(index + 1) sur \(store.displayed.count)"
        AccessibilityNotification.Announcement(spoken).post()
    }

    // MARK: Lecture seule

    /// Moniteur sans droit de gestion : les thèmes que « Signaler » lui propose, dans l’ordre montré. Des rangées
    /// simples : ni interrupteur grisé, ni poignée.
    private var readOnlySection: some View {
        let themes = shownThemes.filter(\.visible)
        return Section {
            ForEach(themes) { theme in
                HStack(spacing: DrivySpacing.s) {
                    DrivyObservationGlyphImage(glyph: theme.glyph)
                        .foregroundStyle(DrivyTheme.accent)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                    Text(theme.title)
                        .foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, DrivySpacing.xs)
                .frame(minHeight: DrivyLayout.tapTarget)
                .listRowInsets(rowInsets)
                .accessibilityElement(children: .combine)
                .accessibilityValue("Position \((themes.firstIndex(of: theme) ?? 0) + 1) sur \(themes.count)")
                .accessibilityIdentifier("observation-theme-\(theme.key)")
            }
        } header: {
            if isAutomatic {
                Text("Ordre automatique")
                    .drivyFormSectionHeader()
                    .accessibilityIdentifier("observation-themes-automatic")
            }
        }
        .drivyFormRows()
    }

    // MARK: État d’enregistrement

    /// Discret, sur la ligne du compteur. « Enregistré » ne s’écrit qu’après la réponse de l’école ; un échec
    /// se dit plus haut, avec sa reprise.
    @ViewBuilder private var saveStatus: some View {
        switch store.saveState {
        case .saving:
            HStack(spacing: DrivySpacing.xxs) {
                ProgressView().controlSize(.small)
                Text("Enregistrement…")
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("observation-themes-saving")
        case .saved:
            Label("Enregistré", systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .accessibilityIdentifier("observation-themes-saved")
        case .idle, .failed:
            EmptyView()
        }
    }

    private func announce(_ state: SchoolObservationThemeStore.SaveState) {
        switch state {
        case .saved: AccessibilityNotification.Announcement("Enregistré").post()
        case .failed(let message): AccessibilityNotification.Announcement(message).post()
        case .idle, .saving: break
        }
    }

    // MARK: Réinitialisation

    /// Remettre l’ordre ne masque ni n’affiche rien : aucun accord demandé ; sans objet en ordre automatique.
    /// Rétablir l’origine change aussi l’affichage : une seule question, puis l’envoi.
    private var resetSection: some View {
        Section {
            if !isAutomatic {
                Button { store.resetOrder() } label: {
                    Text("Réinitialiser l’ordre").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.drivyText)
                .disabled(!store.canEdit || store.isOriginalOrder)
                .listRowInsets(rowInsets)
                .accessibilityIdentifier("observation-themes-reset-order")
            }
            Button { confirmsReset = true } label: {
                Text("Rétablir la configuration d’origine").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.drivyText)
            .disabled(!store.canEdit || store.isOriginal)
            .listRowInsets(rowInsets)
            .accessibilityIdentifier("observation-themes-reset-all")
        }
        .drivyFormRows()
    }
}

/// La grille telle que « Signaler » la montre en leçon, à sa taille réelle, pour les thèmes affichés.
/// Une formation n’y montre que les thèmes dont elle enseigne la compétence.
struct SchoolObservationThemePreviewSheet: View {
    let themes: [SchoolObservationTheme]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Hauteur de la grille de la leçon, plus la barre de titre de la feuille.
    private var height: CGFloat {
        SchoolSignalGridLayout.estimatedPaletteHeight(tileCount: themes.filter(\.visible).count,
            width: SchoolSignalGridLayout.assumedWidth, textSize: dynamicTypeSize)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                SchoolSignalGridPreview(themes: themes)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(DrivyTheme.surface)
            .navigationTitle("Aperçu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .tint(DrivyTheme.accent)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(height), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(DrivyTheme.surface)
    }
}
