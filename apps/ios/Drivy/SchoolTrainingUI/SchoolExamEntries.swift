import SwiftUI

// Entrées vers les examens (#54) : le prochain examen de l'élève au-dessus de ses leçons, et, pour le personnel, les examens dont la
// date est passée et dont le résultat reste à renseigner. Lecture seule : les écritures vivent dans la section « Examens » d'une formation.

/// Libellé court d'un examen pour une liste : « Examen pratique · tentative 2 ».
enum SchoolExamText {
    static func title(_ exam: SchoolExam) -> String {
        let base: String
        switch exam.examKind {
        case .theory: base = "Examen théorique"
        case .practical: base = "Examen pratique"
        case nil: base = "Examen"
        }
        guard let attempt = exam.attempt, attempt > 1 else { return base }
        return "\(base) · tentative \(attempt)"
    }

    /// « Examen pratique · mar. 4 mars, 10:00 » dans le fuseau de l'examen.
    @MainActor static func summary(_ exam: SchoolExam) -> String {
        guard let date = exam.date else { return title(exam) }
        return "\(title(exam)) · \(SchoolDateFormat.template("EEEdMMMjmm", date, zone: exam.timeZone))"
    }
}

/// Le prochain examen de l'élève : une ligne au-dessus de Leçons, absente tant qu'aucun examen n'est prévu.
struct SchoolLearnerExamEntry: ViewModifier {
    let client: SchoolExamClient?
    let schoolID: UUID?
    @Environment(\.scenePhase) private var scenePhase
    @State private var next: SchoolExamListItem?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let next {
                    DrivyEntityRow(title: "Prochain examen", meta: SchoolExamText.summary(next.exam), leading: .symbol("checkmark.seal"))
                        .padding(.horizontal, DrivySpacing.m).padding(.vertical, DrivySpacing.xs)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("learner-next-exam")
                }
            }
            .task(id: schoolID) { await load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await load() } }
            }
    }

    private func load() async {
        guard let client, let schoolID else { next = nil; return }
        // Une panne ne retire pas la dernière lecture : l'examen prévu reste affiché, la ligne n'invente rien.
        guard let items = try? await client.list(schoolID: schoolID, filter: .upcoming) else { return }
        next = items.first
    }
}

extension View {
    func schoolLearnerExams(client: SchoolExamClient?, schoolID: UUID?) -> some View {
        modifier(SchoolLearnerExamEntry(client: client, schoolID: schoolID))
    }
}

/// Lecture des examens à renseigner pour la liste des élèves du personnel.
@MainActor @Observable final class SchoolPendingExamsModel {
    private(set) var items: [SchoolExamListItem] = []

    func load(client: SchoolExamClient?, schoolID: UUID?) async {
        guard let client, let schoolID else { items = []; return }
        // Une panne garde la dernière lecture : ne rien afficher de plus n'est pas dire qu'il n'y a rien à renseigner.
        guard let loaded = try? await client.list(schoolID: schoolID, filter: .pendingResult) else { return }
        items = loaded
    }
}

/// Les examens à renseigner, en tête de la liste d'élèves : chaque ligne ouvre le dossier de l'élève.
struct SchoolPendingExamRows: View {
    let items: [SchoolExamListItem]
    let open: (UUID) -> Void

    var body: some View {
        if !items.isEmpty {
            Text("Examens à renseigner")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.muted)
                .accessibilityAddTraits(.isHeader)
                .listRowSeparator(.hidden)
                .drivyPlainRows()
            ForEach(items.prefix(8)) { item in
                Button { open(item.learnerId) } label: {
                    DrivyEntityRow(title: item.learnerDisplayName.isEmpty ? "Élève" : item.learnerDisplayName,
                        meta: SchoolExamText.summary(item.exam), leading: .symbol("exclamationmark.circle"), showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.learnerDisplayName), \(SchoolExamText.summary(item.exam)), résultat à renseigner")
                .accessibilityIdentifier("pending-exam-\(item.exam.id.uuidString)")
                .listRowSeparator(.hidden)
                .drivyPlainRows()
            }
            if items.count > 8 {
                Text("\(items.count - 8) autres examens à renseigner")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.muted)
                    .listRowSeparator(.hidden)
                    .drivyPlainRows()
            }
        }
    }
}
