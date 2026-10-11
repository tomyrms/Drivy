import SwiftUI

/// Champ de recherche Drivy : loupe, saisie, effacement. Posé au-dessus d’une liste, il reste en place quand le
/// clavier apparaît, là où une barre de recherche de navigation s’agrandit dans une feuille.
struct DrivySearchField: View {
    @Binding var text: String
    let prompt: String
    var focus: FocusState<Bool>.Binding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DrivySpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DrivyTheme.muted)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .focused(focus)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityAddTraits(.isSearchField)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DrivyTheme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
                .transition(.opacity)
            }
        }
        .font(.body)
        .padding(.leading, DrivySpacing.s)
        .frame(minHeight: 44)
        .background(DrivyTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
        .animation(DrivyMotion.feedback(reduceMotion), value: text.isEmpty)
    }
}

/// Choix d’un élève : recherche en tête, liste à hauteur stable, un toucher choisit. Dans la feuille de démarrage,
/// rien n’est poussé ni redimensionné ; dans le planning, la même liste se pousse (`SchoolLearnerSearchList`).
struct SchoolLearnerPicker: View {
    let learners: [SchoolLearner]
    let selectedID: UUID?
    let choose: (UUID) -> Void
    @State private var search = ""
    @State private var index: SchoolLearnerIndex
    @FocusState private var searching: Bool

    init(learners: [SchoolLearner], selectedID: UUID?, choose: @escaping (UUID) -> Void) {
        self.learners = learners
        self.selectedID = selectedID
        self.choose = choose
        _index = State(initialValue: SchoolLearnerIndex(learners: learners))
    }

    private var matches: [SchoolLearner] { index.filter(search) }

    var body: some View {
        let shown = matches
        List {
            ForEach(shown) { learner in
                let isSelected = learner.id == selectedID
                Button {
                    // Le clavier se retire avant le passage au récapitulatif : pas de double mouvement.
                    searching = false
                    choose(learner.id)
                } label: {
                    DrivyEntityRow(title: learner.displayName, leading: .avatar(learner.displayName), isSelected: isSelected)
                }
                .listRowInsets(EdgeInsets(top: DrivySpacing.xxs, leading: DrivySpacing.m, bottom: DrivySpacing.xxs, trailing: DrivySpacing.m))
                .listRowBackground(isSelected ? DrivyTheme.accentSoft : DrivyTheme.canvas)
                .listRowSeparatorTint(DrivyTheme.border)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("learner-row-\(learner.id.uuidString)")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .overlay {
            if shown.isEmpty { DrivyEmptyState(title: "Aucun élève trouvé", symbol: "magnifyingglass") }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            DrivySearchField(text: $search, prompt: "Rechercher un élève", focus: $searching)
                .padding(.horizontal, DrivySpacing.m)
                .padding(.vertical, DrivySpacing.s)
                .background(DrivyTheme.canvas)
                .accessibilityIdentifier("learner-search-field")
        }
        .onChange(of: learners) { _, values in index = SchoolLearnerIndex(learners: values) }
        .accessibilityIdentifier("learner-search-list")
    }
}

/// Noms repliés une fois (accents, casse) : la recherche ne replie plus toute la liste à chaque frappe.
struct SchoolLearnerIndex {
    private struct Entry {
        let learner: SchoolLearner
        let words: [Substring]
    }
    private let entries: [Entry]

    init(learners: [SchoolLearner]) {
        entries = learners.map { Entry(learner: $0, words: SchoolLearnerSearch.words(of: $0.displayName)) }
    }

    /// Même règle que `SchoolLearnerSearch.filter` : chaque mot saisi commence un mot du nom.
    func filter(_ query: String) -> [SchoolLearner] {
        let wanted = SchoolLearnerSearch.words(of: query)
        guard !wanted.isEmpty else { return entries.map { $0.learner } }
        return entries.filter { entry in
            wanted.allSatisfy { word in entry.words.contains { $0.hasPrefix(word) } }
        }.map { $0.learner }
    }
}
