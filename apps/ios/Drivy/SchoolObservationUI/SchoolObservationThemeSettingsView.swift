import SwiftUI

/// Réglage des signalements de l’école : lesquels « Signaler » propose pendant une leçon, et dans quel ordre.
/// Liste groupée native, comme le Profil dont elle vient : le mode d’édition permanent donne la poignée et le
/// glisser-déposer du système. Chaque changement part aussitôt ; l’écran montre la proposition pendant l’envoi
/// et revient à l’état confirmé par l’école si elle n’aboutit pas. L’entrée n’existe que pour qui peut gérer :
/// le droit vient de l’école, qui le revérifie à chaque écriture.
struct SchoolObservationThemeSettingsView: View {
    let store: SchoolObservationThemeStore
    @State private var showsPreview = false
    @State private var confirmsReset = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Les rangées portent déjà leur espacement vertical : sans cela, la liste le double.
    private var rowInsets: EdgeInsets { EdgeInsets(top: 0, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m) }
    private var noticeInsets: EdgeInsets { EdgeInsets(top: DrivySpacing.xs, leading: 0, bottom: DrivySpacing.xs, trailing: 0) }

    var body: some View {
        List {
            messages
            if store.configuration.isFromServer {
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
        // Poignées toujours visibles : réordonner est le geste principal de cet écran, pas un mode à ouvrir.
        .environment(\.editMode, .constant(.active))
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
            SchoolObservationThemePreviewSheet(themes: store.displayed)
        }
        .confirmationDialog("Rétablir les signalements d’origine et leur ordre ?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Rétablir", role: .destructive) { store.resetAll() }
            Button("Annuler", role: .cancel) { }
        }
        // Retour à l’état confirmé après un échec, ou configuration relue : les rangées glissent à leur place.
        .animation(DrivyMotion.context(reduceMotion), value: store.displayed.map(\.key))
        .onChange(of: store.saveState) { _, state in announce(state) }
        .onDisappear { store.clearNotice() }
        .task { _ = await store.refresh() }
        .accessibilityIdentifier("observation-themes")
    }

    // MARK: Messages

    /// Un message seulement pour l’inhabituel : un échec, une configuration changée ailleurs, une lecture impossible.
    @ViewBuilder private var messages: some View {
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

    // MARK: Thèmes

    private var themeSection: some View {
        let themes = store.displayed
        return Section {
            ForEach(themes) { theme in
                row(theme, position: (themes.firstIndex(of: theme) ?? 0) + 1, count: themes.count)
                    .listRowInsets(rowInsets)
            }
            .onMove { source, destination in
                var moved = store.displayed
                moved.move(fromOffsets: source, toOffset: destination)
                store.propose(moved)
            }
            .moveDisabled(!store.canEdit)
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                Text(countLabel).monospacedDigit()
                    .accessibilityIdentifier("observation-themes-count")
                Spacer(minLength: DrivySpacing.xs)
                saveStatus
            }
            .drivyFormSectionHeader()
        }
        .drivyFormRows()
    }

    private var countLabel: String {
        let visible = store.visibleCount
        return "\(visible) \(visible > 1 ? "affichés" : "affiché") sur \(store.displayed.count)"
    }

    /// L’interrupteur est la rangée : son libellé nomme le thème, son état dit s’il est proposé en leçon.
    /// « Monter » et « Descendre » font le même déplacement que la poignée, pour VoiceOver et la commande vocale.
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
        .accessibilityAction(named: "Monter") { move(theme, by: -1) }
        .accessibilityAction(named: "Descendre") { move(theme, by: 1) }
        .accessibilityIdentifier("observation-theme-\(theme.key)")
    }

    private func move(_ theme: SchoolObservationTheme, by delta: Int) {
        guard store.canEdit, let index = store.move(key: theme.key, by: delta) else { return }
        let spoken: String = "\(theme.title), position \(index + 1) sur \(store.displayed.count)"
        AccessibilityNotification.Announcement(spoken).post()
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

    /// Remettre l’ordre ne masque ni n’affiche rien : aucun accord demandé. Rétablir l’origine change aussi
    /// l’affichage : une seule question, puis l’envoi.
    private var resetSection: some View {
        Section {
            Button { store.resetOrder() } label: {
                Text("Réinitialiser l’ordre").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.drivyText)
            .disabled(!store.canEdit || store.isOriginalOrder)
            .listRowInsets(rowInsets)
            .accessibilityIdentifier("observation-themes-reset-order")
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
