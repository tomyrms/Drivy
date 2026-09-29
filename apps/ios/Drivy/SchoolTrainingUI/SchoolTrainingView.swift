import SwiftUI

enum SchoolTrainingSection: String, CaseIterable { case lessons = "Leçons", progress = "Progression" }

/// La formation ouverte depuis le dossier d’un élève (moniteur).
struct SchoolTrainingView: View {
    let client: SchoolTrainingClient
    @Bindable var workspace: SchoolWorkspace
    let learner: SchoolLearner
    let trainingID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SchoolTrainingScreen(client: client, workspace: workspace, learner: learner, trainingID: trainingID)
                .navigationTitle("Formation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        .tint(DrivyTheme.accent)
    }
}

/// Leçons et progression d’une formation. Les onglets de l’élève fixent la section ;
/// sans section fixée, un sélecteur passe de l’une à l’autre.
struct SchoolTrainingScreen: View {
    let client: SchoolTrainingClient
    @Bindable var workspace: SchoolWorkspace
    let learner: SchoolLearner
    let trainingID: UUID
    var section: SchoolTrainingSection? = nil
    @State private var model: SchoolTrainingWorkspace?

    private var scopeKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0):\(workspace.membership?.roles.joined(separator: ",") ?? ""):\(workspace.membership?.grants.joined(separator: ",") ?? ""):\(trainingID)"
    }
    var body: some View {
        Group {
            if let model, matches(model) {
                SchoolTrainingContent(model: model, workspace: workspace, learner: learner, fixedSection: section)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DrivyTheme.surface)
            }
        }
        .id(scopeKey)
        .task(id: scopeKey) {
            if let model, matches(model), model.trainingID == trainingID {
                // Une requête annulée par un changement d’onglet a pu laisser une erreur : relire sans effacer.
                if model.errorMessage != nil { await model.load(keepingCurrent: true) }
                return
            }
            model = nil
            guard let person = workspace.person, let membership = workspace.membership else { return }
            let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
                membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: client.baseURL.absoluteString)
            let shared = SchoolTrainingModelCache.model(scope: scope, membership: membership, learnerID: learner.id,
                trainingID: trainingID, client: client)
            model = shared.model
            if shared.isNew || shared.model.errorMessage != nil { await shared.model.load(keepingCurrent: !shared.isNew) }
        }
        .onChange(of: model?.accessRevoked) { _, revoked in
            if revoked == true { Task { await workspace.loadAccount() } }
        }
    }
    private func matches(_ model: SchoolTrainingWorkspace) -> Bool {
        model.scope.personID == workspace.person?.personId && model.scope.membershipID == workspace.membership?.membershipId
            && model.scope.accessEpoch == workspace.membership?.accessEpoch && model.membership.roles == workspace.membership?.roles
            && model.membership.grants == workspace.membership?.grants
    }
}

private struct OpenedLesson: Identifiable { let id: UUID }

private struct SchoolTrainingContent: View {
    @Bindable var model: SchoolTrainingWorkspace
    @Bindable var workspace: SchoolWorkspace
    let learner: SchoolLearner
    let fixedSection: SchoolTrainingSection?
    @State private var chosenSection: SchoolTrainingSection = .lessons
    @State private var opened: OpenedLesson?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var section: SchoolTrainingSection { fixedSection ?? chosenSection }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                if fixedSection == nil { heading }
                if model.isLoading && model.training == nil { ProgressView().frame(maxWidth: .infinity, minHeight: 100) }
                if let error = model.errorMessage { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }
                if model.training != nil {
                    if fixedSection == nil && model.hasPedagogicalRole { sectionPicker }
                    switch section {
                    case .lessons: lessons
                    case .progress: progress
                    }
                }
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface)
        .refreshable { await model.load(keepingCurrent: true) }
        .accessibilityIdentifier("training-dossier")
        .sheet(item: $opened, onDismiss: { Task { await model.load(keepingCurrent: true) } }) { lesson in
            NavigationStack {
                SchoolLessonReportView(client: model.client.reports, schoolWorkspace: workspace, lessonID: lesson.id, learnerName: learner.displayName,
                    isNextPlanned: lesson.id == model.upcomingLessons.first?.id)
            }
            .tint(DrivyTheme.accent)
        }
    }
    private var heading: some View {
        HStack(spacing: DrivySpacing.m) {
            DrivyAvatar(name: learner.displayName, size: 44)
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(model.training.map { "Permis \($0.categoryCode)" } ?? "Formation")
                    .font(.drivyTitle).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(learner.displayName).font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
            Spacer(minLength: 0)
            if let training = model.training, training.status != "ACTIVE" {
                DrivyStatusBadge(title: SchoolPresentation.trainingStatus(training.status))
            }
        }
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var sectionPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            sections.pickerStyle(.menu).frame(minHeight: 48)
        } else {
            sections.pickerStyle(.segmented)
        }
    }
    private var sections: some View {
        Picker("Afficher", selection: $chosenSection) {
            ForEach(SchoolTrainingSection.allCases, id: \.self) { item in
                Text(item.rawValue).tag(item).accessibilityIdentifier("training-tab-\(item.rawValue)")
            }
        }
    }
    private var lessons: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if model.lessonsLoaded && model.lessons.isEmpty && !model.isLoading {
                DrivyEmptyState(title: "Aucune leçon", symbol: "calendar")
            }
            if !model.upcomingLessons.isEmpty { lessonGroup("À venir", values: model.upcomingLessons) }
            if !model.pastLessons.isEmpty { lessonGroup("Passées", values: model.pastLessons) }
            moreLessons
        }
    }
    private func lessonGroup(_ title: String, values: [SchoolLesson]) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            DrivySectionHeader(title: title)
            VStack(spacing: 0) {
                ForEach(values) { lesson in
                    Button { opened = OpenedLesson(id: lesson.id) } label: { SchoolTrainingLessonRow(lesson: lesson) }
                        .buttonStyle(DrivyRowButtonStyle())
                        .disabled(!model.canOpenPedagogicalContent)
                        .accessibilityIdentifier("training-lesson-\(lesson.id.uuidString)")
                    Divider().overlay(DrivyTheme.border)
                }
            }
        }
    }
    private var progress: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            if let value = model.progress {
                if let error = model.progressError { SchoolErrorNotice(message: error, retry: { Task { await model.loadProgress() } }) }
                VStack(spacing: 0) {
                    ForEach(value.items) { item in
                        Button { opened = OpenedLesson(id: item.sourceLessonId) } label: { progressRow(item) }
                            .buttonStyle(DrivyRowButtonStyle())
                            .accessibilityHint("Ouvre la leçon")
                        Divider().overlay(DrivyTheme.border)
                    }
                    ForEach(model.unobservedCompetencies) { competency in
                        DrivyCompetencyNote(label: competency.label, level: "Pas encore vu", tone: .neutral)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, DrivySpacing.m)
                        Divider().overlay(DrivyTheme.border)
                    }
                }
                if value.items.isEmpty && value.unobservedCompetencyIds.isEmpty {
                    DrivyEmptyState(title: "Aucune compétence", symbol: "list.bullet")
                }
            } else if let error = model.progressError {
                SchoolErrorNotice(message: error, retry: { Task { await model.loadProgress() } })
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }
    private func progressRow(_ item: SchoolReportProgressItem) -> some View {
        HStack(alignment: .top, spacing: DrivySpacing.m) {
            DrivyCompetencyNote(label: item.label, level: SchoolTrainingFormatting.level(item.level), context: item.context,
                date: SchoolTrainingFormatting.day(item.observedAt, zone: workspace.school?.timeZone ?? "Europe/Zurich"))
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                .padding(.top, DrivySpacing.xxs)
                .accessibilityHidden(true)
        }
        .padding(.vertical, DrivySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var moreLessons: some View {
        if model.nextCursor != nil {
            Button { Task { await model.loadMore() } } label: {
                HStack(spacing: DrivySpacing.xs) {
                    if model.isLoadingMore { ProgressView() }
                    Text("Afficher plus")
                }
            }
            .buttonStyle(DrivySecondaryButtonStyle()).disabled(model.isLoadingMore)
        }
    }
}

/// Même anatomie que la ligne d’agenda : heure, jour, lieu ; un badge seulement pour l’inhabituel.
private struct SchoolTrainingLessonRow: View {
    let lesson: SchoolLesson
    var body: some View {
        DrivyLessonRow(start: SchoolTrainingFormatting.time(lesson.plannedStart, zone: lesson.timeZone),
            end: SchoolTrainingFormatting.time(lesson.plannedEnd, zone: lesson.timeZone),
            title: SchoolTrainingFormatting.day(lesson.plannedStart, zone: lesson.timeZone),
            details: [lesson.meetingPoint],
            badge: lesson.drivyState.isUnusual ? lesson.drivyState.badge : nil)
    }
}

enum SchoolTrainingFormatting {
    static func level(_ code: String) -> String {
        switch code { case "DISCOVERING": "En découverte"; case "GUIDED": "Avec accompagnement"; case "INDEPENDENT": "En autonomie"; default: "À vérifier" }
    }
    static func instant(_ value: String, zone: String) -> String { format(value, zone: zone, template: "d MMMM yyyy HHmm") }
    static func day(_ value: String, zone: String) -> String { format(value, zone: zone, template: "d MMMM yyyy") }
    static func time(_ value: String, zone: String) -> String { format(value, zone: zone, template: "HHmm") }
    private static func format(_ value: String, zone: String, template: String) -> String {
        guard let date = SchoolLesson.date(value), let timeZone = TimeZone(identifier: zone) else { return "Date indisponible" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH"); formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template); return formatter.string(from: date)
    }
}
