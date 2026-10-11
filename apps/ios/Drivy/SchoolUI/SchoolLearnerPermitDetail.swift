import SwiftUI

/// Profil → un permis : où retrouver ses leçons et sa progression, puis ce que l’école dit de la formation. Les
/// séances et les compétences ne sont pas recopiées ici : chaque ligne ouvre l’onglet qui les porte, sur ce permis.
struct SchoolLearnerPermitDetail: View {
    let title: String
    let training: SchoolTraining?
    let model: SchoolTrainingWorkspace
    /// Affectations lues pour cette formation ; `nil` : pas lues, aucun moniteur n’est alors nommé.
    let assignments: [SchoolAssignment]?
    /// Ouvre Leçons ou Progression sur ce permis.
    let open: ((SchoolHomeTab) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Les chiffres ne se donnent qu’une fois toutes les leçons lues.
    private var overview: SchoolTrainingOverview? {
        guard model.lessonsLoaded, model.nextCursor == nil, model.training != nil else { return nil }
        return SchoolTrainingOverview.make(lessons: model.lessons, progress: model.progress)
    }

    private var instructors: [String] {
        guard let assignments else { return [] }
        return SchoolTrainingOverview.assignedInstructors(assignments: assignments, lessons: model.lessons, now: Date())
    }

    var body: some View {
        let figures = overview
        List {
            if figures == nil, let error = model.errorMessage {
                Section {
                    SchoolErrorNotice(message: error, retry: { Task { await model.load(keepingCurrent: true) } })
                }
                .drivyFormRows()
            }
            if let open {
                Section {
                    DrivyNavigationRow(title: "Leçons", detail: figures?.summary) { open(.lessons) }
                        .accessibilityIdentifier("profile-permit-lessons")
                    DrivyNavigationRow(title: "Progression", detail: figures?.autonomySummary) { open(.progress) }
                        .accessibilityIdentifier("profile-permit-progress")
                }
                .listRowInsets(EdgeInsets(top: 0, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m))
                .drivyFormRows()
            }
            Section {
                formation(figures)
            } header: {
                Text("Formation").drivyFormSectionHeader()
            }
            .drivyFormRows()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .animation(DrivyMotion.reveal(reduceMotion), value: figures)
        .refreshable { await model.load(keepingCurrent: true) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("learner-permit-detail")
    }

    /// État de la formation, début, moniteurs affectés, dernière leçon : ce que le profil ne répète plus par permis.
    @ViewBuilder private func formation(_ overview: SchoolTrainingOverview?) -> some View {
        if let training {
            DrivyKeyValueRow(title: "État", value: SchoolPresentation.trainingStatus(training.status))
            if let started = training.startedOn {
                DrivyKeyValueRow(title: "Début", value: SchoolPresentation.civilDate(started))
            }
        }
        let names = instructors
        if !names.isEmpty {
            // Un nom par ligne : ce sont les moniteurs que l’école affecte à cette formation, pas un référent.
            DrivyKeyValueRow(title: names.count == 1 ? "Moniteur affecté" : "Moniteurs affectés",
                value: names.joined(separator: "\n"))
        }
        if let last = overview?.lastCompleted {
            DrivyKeyValueRow(title: "Dernière leçon", value: SchoolTrainingFormatting.day(last.plannedStart, zone: last.timeZone))
        }
    }
}
