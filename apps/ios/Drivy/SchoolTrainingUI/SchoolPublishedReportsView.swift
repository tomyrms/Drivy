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
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(SchoolTrainingFormatting.day(lesson.plannedStart, zone: lesson.timeZone)).font(.drivyScreenTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Leçon de \(SchoolTrainingFormatting.time(lesson.plannedStart, zone: lesson.timeZone)) · \(lesson.durationMinutes) min")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                }
                if isLoading { ProgressView("Ouverture des bilans…").frame(maxWidth: .infinity, alignment: .leading) }
                if let errorMessage { SchoolErrorNotice(message: errorMessage, retry: { Task { await load() } }) }
                if !isLoading && revisions.isEmpty && errorMessage == nil {
                    DrivyEmptyState(title: "Pas encore de bilan partagé",
                        message: "Le bilan s’affichera ici quand le moniteur l’aura publié.", symbol: "doc.text")
                }
                if !revisions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(revisions) { revision in
                            NavigationLink {
                                SchoolPublishedRevisionView(client: client, schoolID: schoolID, trainingID: trainingID,
                                    lessonID: lesson.id, revisionID: revision.id, competencies: competencies)
                            } label: {
                                DrivyLessonRow(start: SchoolTrainingFormatting.time(revision.publishedAt, zone: lesson.timeZone),
                                    title: "Version \(revision.sequence) · \(SchoolTrainingFormatting.day(revision.publishedAt, zone: lesson.timeZone))",
                                    details: ["Prochaine étape : \(revision.nextStep)"],
                                    badge: (revision.id == lesson.currentPublishedRevisionId ? DrivyReportState.shared : DrivyReportState.historical).badge)
                            }
                            .buttonStyle(DrivyRowButtonStyle())
                            Divider().overlay(DrivyTheme.border)
                        }
                    }
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
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                if isLoading { ProgressView("Ouverture du bilan…").frame(maxWidth: .infinity, minHeight: 100) }
                if let errorMessage { SchoolErrorNotice(message: errorMessage, retry: { Task { await load() } }) }
                if let revision, let lesson {
                    VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                        Text(SchoolTrainingFormatting.day(lesson.plannedStart, zone: lesson.timeZone)).font(.drivyScreenTitle)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("Version \(revision.sequence) · publiée le \(SchoolTrainingFormatting.instant(revision.publishedAt, zone: lesson.timeZone))")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        (lesson.currentPublishedRevisionId == revision.id ? DrivyReportState.shared : DrivyReportState.historical).badge
                        if lesson.currentPublishedRevisionId != revision.id {
                            Text("Une version plus récente de ce bilan a été publiée.")
                                .font(.footnote).foregroundStyle(DrivyTheme.muted)
                        }
                    }
                    DrivyReportBody(nextStep: revision.nextStep, workedOn: revision.workedOn, observationText: revision.observationText)
                    if !revision.observations.isEmpty {
                        VStack(alignment: .leading, spacing: DrivySpacing.s) {
                            DrivySectionHeader(title: "Compétences observées")
                            DrivyRowGroup {
                                ForEach(revision.observations) { observation in
                                    DrivyCompetencyNote(label: competencies.first(where: { $0.id == observation.competencyId })?.label ?? "Compétence indisponible",
                                        level: observation.levelLabel, context: observation.context)
                                        .padding(.vertical, DrivySpacing.s)
                                }
                            }
                        }
                    }
                    if let reason = revision.correctionReason, !reason.isEmpty {
                        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                            Text("Motif de la correction").font(.drivySection).accessibilityAddTraits(.isHeader)
                            Text(reason).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface).navigationTitle("Bilan de leçon").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear { generation = UUID(); revision = nil; lesson = nil }
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
