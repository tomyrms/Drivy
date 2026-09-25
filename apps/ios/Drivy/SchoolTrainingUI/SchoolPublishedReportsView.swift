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
                Text("Bilans partagés").font(.drivyScreenTitle)
                Text(SchoolTrainingFormatting.instant(lesson.plannedStart, zone: lesson.timeZone))
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                if isLoading { ProgressView("Ouverture des bilans…") }
                if let errorMessage { SchoolErrorNotice(message: errorMessage, retry: { Task { await load() } }) }
                if !isLoading && revisions.isEmpty && errorMessage == nil {
                    DrivyEmptyState(title: "Pas encore de bilan",
                        message: "Le moniteur n’a pas encore partagé de bilan pour cette leçon.", symbol: "doc.text")
                }
                ForEach(revisions) { revision in
                    NavigationLink {
                        SchoolPublishedRevisionView(client: client, schoolID: schoolID, trainingID: trainingID,
                            lessonID: lesson.id, revisionID: revision.id, competencies: competencies)
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .center) {
                                if revision.id == lesson.currentPublishedRevisionId {
                                    DrivyStatusBadge(title: "Bilan actuel", symbol: "checkmark", tone: .success)
                                } else {
                                    DrivyStatusBadge(title: "Version \(revision.sequence)")
                                }
                                Spacer(minLength: 12)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(DrivyTheme.muted)
                            }
                            Text(revision.nextStep).font(.body).foregroundStyle(DrivyTheme.text).lineLimit(3)
                            Text(SchoolTrainingFormatting.instant(revision.publishedAt, zone: lesson.timeZone))
                                .font(.caption).foregroundStyle(DrivyTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, DrivySpacing.m)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DrivyRowButtonStyle())
                    Divider()
                }
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface).navigationTitle("Bilans partagés").navigationBarTitleDisplayMode(.inline)
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
                    VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                        if lesson.currentPublishedRevisionId != revision.id {
                            DrivyStatusBadge(title: "Version conservée dans l’historique", symbol: "clock.arrow.circlepath")
                        } else {
                            DrivyStatusBadge(title: "Bilan partagé", symbol: "checkmark", tone: .success)
                        }
                        Text(SchoolTrainingFormatting.day(lesson.plannedStart, zone: lesson.timeZone)).font(.drivyScreenTitle)
                        Text("Publié le \(SchoolTrainingFormatting.instant(revision.publishedAt, zone: lesson.timeZone)) · Version \(revision.sequence)")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                    nextStepCard(revision.nextStep)
                    passage("Travail réalisé", text: revision.workedOn)
                    passage("À retenir", text: revision.observationText)
                    if !revision.observations.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            DrivySectionHeader(title: "Appréciations")
                            ForEach(revision.observations) { observation in
                                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                                    Text(competencies.first(where: { $0.id == observation.competencyId })?.label ?? "Compétence indisponible")
                                        .font(.headline)
                                    DrivyStatusBadge(title: observation.levelLabel, tone: .accent)
                                    Text(observation.context).foregroundStyle(DrivyTheme.muted).fixedSize(horizontal: false, vertical: true)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, DrivySpacing.s)
                                Divider()
                            }
                        }
                    }
                    if let reason = revision.correctionReason, !reason.isEmpty {
                        passage("Motif de la correction", text: reason)
                    }
                }
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface).navigationTitle("Bilan de leçon").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear { generation = UUID(); revision = nil; lesson = nil }
    }
    /// The next step is what the learner acts on: it leads the report.
    private func nextStepCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Label("Prochaine étape", systemImage: "arrow.forward.circle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.accent)
            Text(text).font(.body).foregroundStyle(DrivyTheme.text)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .padding(DrivySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
        .accessibilityElement(children: .combine)
    }
    private func passage(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text(title).font(.drivySection).accessibilityAddTraits(.isHeader)
            Text(text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
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
