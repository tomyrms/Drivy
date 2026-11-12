import SwiftUI

/// Réglage des signalements du compte : lesquels « Signaler » propose pendant une leçon, et dans quel ordre.
/// Liste groupée native, comme le Profil dont elle vient. Tout se règle pour son propre compte :
/// - l’ordre manuel est toujours modifiable (poignées et glisser-déposer du système, chaque changement part aussitôt) ;
/// - l’affichage ne l’est que si l’école le permet ; sinon les rangées se lisent seulement, avec la mention de l’école ;
/// - le classement intelligent se règle toujours : le service range alors « Signaler » d’après les usages du compte,
///   sans jamais réécrire l’ordre manuel, que l’on retrouve intact en le désactivant.
/// Rien ici ne modifie la configuration de l’école : cela se fait sur le web, par l’administration.
struct SchoolObservationThemeSettingsView: View {
    let store: SchoolObservationPreferencesStore
    /// Le compte administre l’école : il peut toujours rétablir l’ordre et la visibilité de référence.
    var isAdministrator = false
    @State private var showsPreview = false
    @State private var confirmsPresentationReset = false
    @State private var confirmsLearningReset = false
    @State private var showsAdoption = false
    /// Le choix d’une ancienne configuration se propose une fois par ouverture de l’écran.
    @State private var offeredAdoption = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Les rangées portent déjà leur espacement vertical : sans cela, la liste le double.
    private var rowInsets: EdgeInsets { EdgeInsets(top: 0, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m) }
    private var noticeInsets: EdgeInsets { EdgeInsets(top: DrivySpacing.xs, leading: 0, bottom: DrivySpacing.xs, trailing: 0) }

    private var reorders: Bool { store.canReorder && !store.isResetting }
    private var shownThemes: [SchoolObservationPreferencesTheme] { store.displayedThemes }
    /// Un compte de l’administration, ou une école qui laisse chacun régler son affichage.
    private var offersPresentationReset: Bool {
        store.canReorder && (isAdministrator || store.personalizationAllowed)
    }

    /// Les thèmes que « Signaler » affiche, dans l’ordre où il les affiche.
    private var previewThemes: [SchoolObservationTheme] {
        let byKey = Dictionary(store.confirmedThemes.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return (store.palette ?? []).compactMap { key in
            guard var theme = byKey[key]?.asTheme else { return nil }
            theme.visible = true
            return theme
        }
    }

    var body: some View {
        List {
            messages
            smartSection
            if store.policy != nil, store.account != nil {
                themeSection
                resetSection
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
        // Poignées visibles sans mode à ouvrir : l’ordre manuel se règle toujours.
        .environment(\.editMode, .constant(reorders ? .active : .inactive))
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .navigationTitle("Signalements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Aperçu") { showsPreview = true }
                    .disabled(previewThemes.isEmpty)
                    .accessibilityIdentifier("observation-themes-preview")
            }
        }
        .sheet(isPresented: $showsPreview) {
            SchoolObservationThemePreviewSheet(themes: previewThemes)
        }
        // Même forme que les autres confirmations de Drivy : une alerte, un titre, ce qui change, Annuler puis le verbe.
        .alert("Rétablir l’ordre et la visibilité ?", isPresented: $confirmsPresentationReset) {
            Button("Annuler", role: .cancel) { }
            Button("Rétablir", role: .destructive) { store.resetPresentation() }
                .accessibilityIdentifier("observation-themes-confirm-reset")
        } message: {
            Text("Ton ordre et ton affichage reviennent à ceux de l’école. Cela ne change que ton compte.")
        }
        .alert("Recommencer l’apprentissage ?", isPresented: $confirmsLearningReset) {
            Button("Annuler", role: .cancel) { }
            Button("Recommencer", role: .destructive) { store.resetLearning() }
                .accessibilityIdentifier("observation-learning-confirm-reset")
        } message: {
            Text("Le classement intelligent repart de zéro, sans tenir compte de tes signalements passés.")
        }
        // Plusieurs écoles, des réglages différents : la personne choisit, le service ne le fait jamais à sa place.
        .confirmationDialog("Reprendre quels réglages ?", isPresented: $showsAdoption, titleVisibility: .visible) {
            ForEach(store.adoption?.candidates ?? []) { candidate in
                Button(candidate.schoolName) { store.adopt(candidate) }
            }
            Button("Pas maintenant", role: .cancel) { }
        }
        // Retour à l’état confirmé après un échec, configuration relue, changement de mode : les rangées glissent à leur place.
        .animation(DrivyMotion.context(reduceMotion), value: shownThemes.map(\.key))
        .animation(DrivyMotion.context(reduceMotion), value: store.displayedMode)
        .onChange(of: store.confirmedChanges) { _, _ in announceConfirmed() }
        .onChange(of: store.failureMessage) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
        .onChange(of: store.adoption) { _, _ in offerAdoptionOnce() }
        .onDisappear { store.clearNotice() }
        .task {
            _ = await store.refresh()
            offerAdoptionOnce()
        }
        .accessibilityIdentifier("observation-themes")
    }

    private func offerAdoptionOnce() {
        guard !offeredAdoption, store.adoption != nil else { return }
        offeredAdoption = true
        showsAdoption = true
    }

    // MARK: Messages

    /// Un message seulement pour l’inhabituel : un échec, un réglage changé ailleurs, une lecture impossible.
    @ViewBuilder private var messages: some View {
        if let message = store.failureMessage {
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
        } else if !store.isLoading, store.policy == nil || store.account == nil {
            Section {
                SchoolErrorNotice(message: "Les signalements n’ont pas pu être chargés.",
                                  retry: { Task { await store.refresh() } })
                    .listRowInsets(noticeInsets)
            }
            .drivyClearRow()
        }
    }

    // MARK: Classement intelligent

    /// L’interrupteur montre la proposition pendant l’envoi, puis l’état que le service confirme.
    @ViewBuilder private var smartSection: some View {
        if store.canReorder {
            Section {
                Toggle(isOn: Binding(get: { store.displayedMode == .smart }, set: { store.setSmart($0) })) {
                    Text("Classement intelligent")
                        .foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, DrivySpacing.xs)
                }
                .drivyControlTint()
                .frame(minHeight: DrivyLayout.tapTarget)
                .disabled(store.isResetting)
                .listRowInsets(rowInsets)
                .accessibilityIdentifier("observation-ranking-smart")
            }
            .drivyFormRows()
        }
    }

    // MARK: Thèmes

    private var themeSection: some View {
        let themes = shownThemes
        let move: ((IndexSet, Int) -> Void)? = reorders ? { source, destination in
            store.move(fromOffsets: source, toOffset: destination)
        } : nil
        return Section {
            ForEach(themes) { theme in
                row(theme, position: (themes.firstIndex(of: theme) ?? 0) + 1, count: themes.count)
                    .listRowInsets(rowInsets)
            }
            .onMove(perform: move)
            .moveDisabled(!reorders)
        } header: {
            // Compteur et mention sur une ligne quand elle tient ; sinon la mention passe dessous.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                    countText
                    managedText
                    Spacer(minLength: DrivySpacing.xs)
                    saveStatus
                }
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                        countText
                        Spacer(minLength: DrivySpacing.xs)
                        saveStatus
                    }
                    managedText
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

    /// Seule indication de l’école dans la liste : l’affichage qu’elle impose, discrète, à côté du compteur.
    @ViewBuilder private var managedText: some View {
        if !store.canEditVisibility {
            Text("Géré par l’école")
                .accessibilityIdentifier("observation-themes-managed")
        }
    }

    private var countLabel: String {
        let visible = store.visibleCount
        return "\(visible) \(visible > 1 ? "affichés" : "affiché") sur \(shownThemes.count)"
    }

    /// Affichage modifiable : l’interrupteur est la rangée, son libellé nomme le thème, son état dit s’il est proposé
    /// en leçon. Affichage imposé : une rangée de lecture, qui dit seulement si le thème est masqué.
    /// « Monter » et « Descendre » font le même déplacement que la poignée, pour VoiceOver et la commande vocale.
    @ViewBuilder private func row(_ theme: SchoolObservationPreferencesTheme, position: Int, count: Int) -> some View {
        if store.canEditVisibility {
            Toggle(isOn: Binding(get: { theme.visible }, set: { store.setVisible($0, key: theme.key) })) {
                label(theme)
            }
            .drivyControlTint()
            .frame(minHeight: DrivyLayout.tapTarget)
            .disabled(store.isResetting)
            .accessibilityHint("Position \(position) sur \(count)")
            .accessibilityActions { moveActions(theme) }
            .accessibilityIdentifier("observation-theme-\(theme.key)")
        } else {
            HStack(spacing: DrivySpacing.s) {
                label(theme)
                Spacer(minLength: DrivySpacing.xs)
                if !theme.visible {
                    Text("Masqué")
                        .font(.footnote)
                        .foregroundStyle(DrivyTheme.muted)
                }
            }
            .frame(minHeight: DrivyLayout.tapTarget)
            .accessibilityElement(children: .combine)
            .accessibilityValue("Position \(position) sur \(count)")
            .accessibilityActions { moveActions(theme) }
            .accessibilityIdentifier("observation-theme-\(theme.key)")
        }
    }

    private func label(_ theme: SchoolObservationPreferencesTheme) -> some View {
        HStack(spacing: DrivySpacing.s) {
            DrivyObservationGlyphImage(glyph: theme.asTheme.glyph)
                .foregroundStyle(theme.visible ? DrivyTheme.accent : DrivyTheme.textTertiary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(theme.title)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DrivySpacing.xs)
    }

    @ViewBuilder private func moveActions(_ theme: SchoolObservationPreferencesTheme) -> some View {
        if reorders {
            Button("Monter") { move(theme, by: -1) }
            Button("Descendre") { move(theme, by: 1) }
        }
    }

    private func move(_ theme: SchoolObservationPreferencesTheme, by delta: Int) {
        guard reorders, let index = store.move(key: theme.key, by: delta) else { return }
        let spoken: String = "\(theme.title), position \(index + 1) sur \(shownThemes.count)"
        AccessibilityNotification.Announcement(spoken).post()
    }

    // MARK: État d’enregistrement

    /// Discret, sur la ligne du compteur. « Enregistré » ne s’annonce qu’après la réponse du service ; un échec
    /// se dit plus haut, avec sa reprise.
    @ViewBuilder private var saveStatus: some View {
        if store.isSaving || store.isResetting {
            HStack(spacing: DrivySpacing.xxs) {
                ProgressView().controlSize(.small)
                Text("Enregistrement…")
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("observation-themes-saving")
        }
    }

    private func announceConfirmed() {
        let spoken: String
        switch store.lastConfirmedReset {
        case .presentation: spoken = "Ordre et visibilité rétablis"
        case .learning: spoken = "Apprentissage recommencé"
        case nil: spoken = "Enregistré"
        }
        AccessibilityNotification.Announcement(spoken).post()
    }

    // MARK: Remises à zéro

    /// Deux actions rares, en bas de l’écran. Rétablir l’ordre et la visibilité ne touche que ce compte ; « Recommencer
    /// l’apprentissage » reste disponible même quand l’école impose son affichage.
    @ViewBuilder private var resetSection: some View {
        if offersPresentationReset || store.hasLearningReset {
            Section {
                if offersPresentationReset {
                    Button { confirmsPresentationReset = true } label: {
                        Text("Rétablir l’ordre et la visibilité").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.drivyText)
                    .disabled(store.isBusy)
                    .listRowInsets(rowInsets)
                    .accessibilityIdentifier("observation-themes-reset-all")
                }
                if store.hasLearningReset {
                    Button { confirmsLearningReset = true } label: {
                        Text("Recommencer l’apprentissage du classement intelligent")
                            .font(.footnote)
                            .foregroundStyle(DrivyTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: DrivyLayout.tapTarget)
                    .disabled(store.isBusy)
                    .listRowInsets(rowInsets)
                    .accessibilityIdentifier("observation-learning-reset")
                }
            }
            .drivyFormRows()
        }
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
