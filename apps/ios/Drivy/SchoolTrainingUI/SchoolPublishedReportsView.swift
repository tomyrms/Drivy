import SwiftUI

struct SchoolPublishedReportsView: View {
    let client: SchoolTrainingClient
    let schoolID: UUID
    let trainingID: UUID
    let lesson: SchoolLesson
    var competencies: [SchoolCatalogCompetency] = []
    @State private var revisions: [SchoolReportRevision] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var generation = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Les bilans de cette leçon").font(.largeTitle.bold())
                Text(SchoolTrainingFormatting.instant(lesson.plannedStart, zone: lesson.timeZone))
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                if isLoading { ProgressView("Ouverture des bilans…") }
                if let errorMessage { SchoolErrorNotice(message: errorMessage, retry: { Task { await load() } }) }
                if !isLoading && revisions.isEmpty && errorMessage == nil {
                    ContentUnavailableView("Pas encore de bilan partagé", systemImage: "doc.text", description: Text("Le moniteur doit publier le bilan avant qu’il apparaisse ici."))
                }
                ForEach(revisions) { revision in
                    NavigationLink {
                        SchoolPublishedRevisionView(client: client, schoolID: schoolID, trainingID: trainingID,
                            lessonID: lesson.id, revisionID: revision.id, competencies: competencies)
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top) {
                                Label(revision.id == revisions.first?.id ? "Dernière publication" : "Version \(revision.sequence)", systemImage: "doc.text")
                                    .font(.headline).foregroundStyle(DrivyTheme.accent)
                                Spacer(minLength: 12)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(DrivyTheme.muted)
                            }
                            Text(revision.nextStep).font(.body).foregroundStyle(DrivyTheme.text).lineLimit(3)
                            Text(SchoolTrainingFormatting.instant(revision.publishedAt, zone: lesson.timeZone))
                                .font(.caption).foregroundStyle(DrivyTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(DrivyTheme.canvas).navigationTitle("Bilans partagés").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear { generation = UUID(); revisions = [] }
    }
    private func load() async {
        generation = UUID(); let request = generation
        revisions = []; isLoading = true; errorMessage = nil
        do {
            guard lesson.schoolId == schoolID, lesson.trainingId == trainingID else { throw SchoolAPIError.invalidResponse }
            let values = try await client.reports.revisions(schoolID: schoolID, lessonID: lesson.id)
            guard request == generation, !Task.isCancelled else { return }
            revisions = values; isLoading = false
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            isLoading = false; errorMessage = SchoolTrainingAccess.message(error)
        }
    }
}

struct SchoolPublishedRevisionView: View {
    let client: SchoolTrainingClient
    let schoolID: UUID
    let trainingID: UUID
    let lessonID: UUID
    let revisionID: UUID
    let competencies: [SchoolCatalogCompetency]
    @State private var revision: SchoolReportRevision?
    @State private var lesson: SchoolLesson?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var generation = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isLoading { ProgressView("Ouverture du bilan…").frame(maxWidth: .infinity, minHeight: 100) }
                if let errorMessage { SchoolErrorNotice(message: errorMessage, retry: { Task { await load() } }) }
                if let revision, let lesson {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Bilan partagé", systemImage: "checkmark.seal").font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.accent)
                        Text(SchoolTrainingFormatting.day(lesson.plannedStart, zone: lesson.timeZone)).font(.largeTitle.bold())
                        Text("Publié le \(SchoolTrainingFormatting.instant(revision.publishedAt, zone: lesson.timeZone)) · Version \(revision.sequence)")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        if lesson.currentPublishedRevisionId != revision.id {
                            Label("Cette version est conservée dans l’historique.", systemImage: "clock.arrow.circlepath")
                                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        }
                    }
                    passage("Ce qui a été travaillé", text: revision.workedOn, symbol: "steeringwheel")
                    passage("Ce qui a été observé", text: revision.observationText, symbol: "eye")
                    passage("La prochaine étape", text: revision.nextStep, symbol: "arrow.turn.up.right")
                    if !revision.observations.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Appréciations").font(.title3.bold())
                            ForEach(revision.observations) { observation in
                                DrivyPanel {
                                    VStack(alignment: .leading, spacing: 10) {
                                        if let competency = competencies.first(where: { $0.id == observation.competencyId }) {
                                            Text(competency.label).font(.headline)
                                        }
                                        Text(observation.levelLabel).font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.accent)
                                        Text(observation.context).foregroundStyle(DrivyTheme.muted)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    if let reason = revision.correctionReason, !reason.isEmpty {
                        passage("Motif de la correction", text: reason, symbol: "pencil.line")
                    }
                }
            }
            .padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(DrivyTheme.canvas).navigationTitle("Bilan de leçon").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear { generation = UUID(); revision = nil; lesson = nil }
    }
    private func passage(_ title: String, text: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.title3.weight(.semibold))
            DrivyPanel { Text(text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func load() async {
        generation = UUID(); let request = generation
        revision = nil; lesson = nil; isLoading = true; errorMessage = nil
        do {
            let value = try await client.revision(schoolID: schoolID, id: revisionID)
            guard value.lessonId == lessonID else { throw SchoolAPIError.invalidResponse }
            let lesson = try await client.reports.agenda.lesson(schoolID: schoolID, id: value.lessonId)
            guard lesson.trainingId == trainingID else { throw SchoolAPIError.invalidResponse }
            guard request == generation, !Task.isCancelled else { return }
            revision = value; self.lesson = lesson; isLoading = false
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            isLoading = false; errorMessage = SchoolTrainingAccess.message(error)
        }
    }
}
