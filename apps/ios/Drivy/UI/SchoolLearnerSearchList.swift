import SwiftUI

/// Choix d’un élève dans une liste filtrée par la frappe : avec deux cents élèves, un menu déroulant ne suffit plus.
/// Se pousse dans la pile de navigation de l’écran qui choisit, et se referme sur le choix. Même liste que la feuille
/// de démarrage (`SchoolLearnerPicker`) : recherche Drivy fixe, fonds de l’app, aucune barre qui s’agrandit.
struct SchoolLearnerSearchList: View {
    let learners: [SchoolLearner]
    let selectedID: UUID?
    let choose: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SchoolLearnerPicker(learners: learners, selectedID: selectedID) { id in
            choose(id); dismiss()
        }
        .background(DrivyTheme.canvas)
        .navigationTitle("Élève").navigationBarTitleDisplayMode(.inline)
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
