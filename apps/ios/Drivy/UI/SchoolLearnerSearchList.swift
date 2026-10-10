import SwiftUI

/// Choix d’un élève dans une liste filtrée par la frappe : avec deux cents élèves, un menu déroulant ne suffit plus.
/// Se pousse dans la pile de navigation de l’écran qui choisit, et se referme sur le choix.
struct SchoolLearnerSearchList: View {
    let learners: [SchoolLearner]
    let selectedID: UUID?
    let choose: (UUID) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var matches: [SchoolLearner] { SchoolLearnerSearch.filter(learners, query: search) }

    var body: some View {
        List(matches) { learner in
            Button {
                choose(learner.id); dismiss()
            } label: {
                HStack(spacing: DrivySpacing.s) {
                    Text(learner.displayName)
                        .foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DrivySpacing.xs)
                    if learner.id == selectedID {
                        Image(systemName: "checkmark").foregroundStyle(DrivyTheme.accent).accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(learner.id == selectedID ? .isSelected : [])
        }
        .overlay { if matches.isEmpty { ContentUnavailableView.search(text: search) } }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher un élève")
        .autocorrectionDisabled()
        .navigationTitle("Élève").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("learner-search-list")
    }
}

enum SchoolLearnerSearch {
    /// Chaque mot saisi doit commencer un mot du nom, sans tenir compte des accents ni de la casse :
    /// « du mar » trouve « Marie Dupont ».
    static func filter(_ learners: [SchoolLearner], query: String) -> [SchoolLearner] {
        let wanted = words(of: query)
        guard !wanted.isEmpty else { return learners }
        return learners.filter { learner in
            let name = words(of: learner.displayName)
            return wanted.allSatisfy { word in name.contains { $0.hasPrefix(word) } }
        }
    }

    static func words(of text: String) -> [Substring] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_CH"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }
}
