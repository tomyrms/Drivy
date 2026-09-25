import SwiftUI

struct SchoolTrainingView: View {
    let client: SchoolTrainingClient
    @Bindable var workspace: SchoolWorkspace
    let learner: SchoolLearner
    let trainingID: UUID
    @State private var model: SchoolTrainingWorkspace?
    @Environment(\.dismiss) private var dismiss

    private var scopeKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0):\(workspace.membership?.roles.joined(separator: ",") ?? ""):\(workspace.membership?.grants.joined(separator: ",") ?? ""):\(trainingID)"
    }
    var body: some View {
        NavigationStack {
            Group {
                if let model, matches(model) {
                    SchoolTrainingContent(model: model, workspace: workspace, learner: learner)
                } else {
                    ProgressView("Ouverture de la formation…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DrivyTheme.surface)
                }
            }
            .navigationTitle("Formation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        .id(scopeKey)
        .tint(DrivyTheme.accent)
        .task(id: scopeKey) {
            model?.invalidate(); model = nil
            guard let person = workspace.person, let membership = workspace.membership else { return }
            let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
                membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: client.baseURL.absoluteString)
            let value = SchoolTrainingWorkspace(scope: scope, membership: membership, learnerID: learner.id, trainingID: trainingID, client: client)
            model = value; await value.load()
        }
        .onDisappear { model?.invalidate() }
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

private enum TrainingSection: String, CaseIterable { case lessons = "Leçons", reports = "Bilans", progress = "Parcours" }

private struct SchoolTrainingContent: View {
    @Bindable var model: SchoolTrainingWorkspace
    @Bindable var workspace: SchoolWorkspace
    let learner: SchoolLearner
    @State private var section: TrainingSection = .lessons
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                heading
                if model.isLoading { ProgressView("Chargement de la formation…").frame(maxWidth: .infinity, minHeight: 100) }
                if let error = model.errorMessage { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }
                if model.training != nil {
                    if model.hasPedagogicalRole { sectionPicker }
                    switch section {
                    case .lessons: lessons
                    case .reports: reports
                    case .progress: progress
                    }
                }
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface)
        .refreshable { await model.load() }
        .accessibilityIdentifier("training-dossier")
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            HStack(spacing: DrivySpacing.s) {
                DrivyAvatar(name: learner.displayName, size: 36)
                Text(learner.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
            }
            .accessibilityElement(children: .combine)
            Text(model.training.map { "Permis \($0.categoryCode)" } ?? "Votre formation")
                .font(.drivyScreenTitle).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let training = model.training {
                HStack(spacing: DrivySpacing.xs) {
                    DrivyStatusBadge(title: SchoolPresentation.trainingStatus(training.status), symbol: "steeringwheel",
                        tone: training.status == "ACTIVE" ? .accent : training.status == "COMPLETED" ? .success : .neutral)
                    if let date = training.closedOn {
                        Text("Clôturée le \(SchoolPresentation.civilDate(date))").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    } else if let date = training.startedOn {
                        Text("Depuis le \(SchoolPresentation.civilDate(date))").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                }
            }
        }
    }
    @ViewBuilder private var sectionPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            sections.pickerStyle(.menu).frame(minHeight: 48)
        } else {
            sections.pickerStyle(.segmented)
        }
    }
    private var sections: some View {
        Picker("Afficher", selection: $section) {
            ForEach(TrainingSection.allCases, id: \.self) { item in
                Text(item.rawValue).tag(item).accessibilityIdentifier("training-tab-\(item.rawValue)")
            }
        }
    }
    private var lessons: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if model.lessonsLoaded && model.lessons.isEmpty && !model.isLoading {
                empty("Aucune leçon", text: "Aucun rendez-vous n’est enregistré pour cette formation.", symbol: "calendar")
            }
            if !model.upcomingLessons.isEmpty {
                lessonGroup("À venir", values: model.upcomingLessons)
            }
            if !model.pastLessons.isEmpty { lessonGroup("Historique", values: model.pastLessons) }
            moreLessons
        }
    }
    private func lessonGroup(_ title: String, values: [SchoolLesson]) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            DrivySectionHeader(title: title)
            VStack(spacing: 0) {
                ForEach(values) { lesson in
                    NavigationLink {
                        SchoolTrainingLessonView(lesson: lesson, model: model, workspace: workspace, learnerName: learner.displayName)
                    } label: { SchoolTrainingLessonRow(lesson: lesson) }
                    .buttonStyle(DrivyRowButtonStyle()).accessibilityIdentifier("training-lesson-\(lesson.id.uuidString)")
                    Divider().overlay(DrivyTheme.border)
                }
            }
        }
    }
    private var reports: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            DrivySectionHeader(title: "Bilans partagés")
            if model.canOpenPedagogicalContent {
                if model.lessonsLoaded && model.publishedLessons.isEmpty {
                    empty("Aucun bilan partagé", text: model.nextCursor == nil
                        ? "Les bilans apparaissent ici après leur publication par le moniteur."
                        : "Aucun bilan dans cette liste. Affichez les leçons suivantes pour poursuivre.", symbol: "doc.text")
                }
                VStack(spacing: 0) {
                    ForEach(model.publishedLessons) { lesson in
                        NavigationLink {
                            SchoolPublishedReportsView(client: model.client, schoolID: model.scope.schoolID,
                                trainingID: model.trainingID, lesson: lesson, competencies: model.competencies)
                        } label: { SchoolTrainingLessonRow(lesson: lesson, showsReport: true) }
                        .buttonStyle(DrivyRowButtonStyle())
                        Divider().overlay(DrivyTheme.border)
                    }
                }
                if model.nextCursor != nil { moreLessons.padding(.top, DrivySpacing.m) }
            } else { pedagogyStatus }
        }
    }
    private var progress: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            DrivySectionHeader(title: "Parcours pédagogique")
            if let value = model.progress {
                if let error = model.progressError { SchoolErrorNotice(message: error, retry: { Task { await model.loadProgress() } }) }
                VStack(spacing: 0) {
                    ForEach(value.items) { item in
                        NavigationLink {
                            SchoolPublishedRevisionView(client: model.client, schoolID: model.scope.schoolID,
                                trainingID: model.trainingID, lessonID: item.sourceLessonId, revisionID: item.sourceRevisionId,
                                competencies: model.competencies)
                        } label: { progressRow(item) }
                        .buttonStyle(DrivyRowButtonStyle())
                        .accessibilityHint("Ouvre le bilan d’origine")
                        Divider().overlay(DrivyTheme.border)
                    }
                    ForEach(model.unobservedCompetencies) { competency in
                        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                            DrivyCompetencyNote(label: competency.label, level: "Non observé", tone: .neutral)
                            if !competency.description.isEmpty {
                                DisclosureGroup("Description de la compétence") {
                                    Text(competency.description).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, DrivySpacing.xs)
                                }
                                .font(.subheadline)
                                .frame(minHeight: 44)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, DrivySpacing.m)
                        Divider().overlay(DrivyTheme.border)
                    }
                }
                if value.items.isEmpty && value.unobservedCompetencyIds.isEmpty {
                    empty("Aucune compétence", text: "Le référentiel de cette formation ne contient aucune compétence.", symbol: "list.bullet")
                } else {
                    if model.unobservedCompetencies.count < value.unobservedCompetencyIds.count {
                        Text("Certaines compétences non observées n’ont pas pu être chargées.").font(.footnote).foregroundStyle(DrivyTheme.muted)
                            .padding(.top, DrivySpacing.s)
                    }
                    Text("Chaque appréciation garde sa date et son contexte. Aucun score global.")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DrivySpacing.s)
                }
            } else { pedagogyStatus }
        }
    }
    private func progressRow(_ item: SchoolReportProgressItem) -> some View {
        HStack(alignment: .top, spacing: DrivySpacing.m) {
            DrivyCompetencyNote(label: item.label, level: SchoolTrainingFormatting.level(item.level), context: item.context,
                date: SchoolTrainingFormatting.instant(item.observedAt, zone: workspace.school?.timeZone ?? "Europe/Zurich"))
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                .padding(.top, DrivySpacing.xxs)
                .accessibilityHidden(true)
        }
        .padding(.vertical, DrivySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var pedagogyStatus: some View {
        if let error = model.progressError { SchoolErrorNotice(message: error, retry: { Task { await model.loadProgress() } }) }
        else { ProgressView("Ouverture du parcours…").frame(maxWidth: .infinity, minHeight: 80) }
    }
    @ViewBuilder private var moreLessons: some View {
        if model.nextCursor != nil {
            Button { Task { await model.loadMore() } } label: {
                HStack(spacing: DrivySpacing.xs) {
                    if model.isLoadingMore { ProgressView() }
                    Text(model.isLoadingMore ? "Chargement des leçons suivantes…" : "Afficher les leçons suivantes")
                }
            }
            .buttonStyle(DrivySecondaryButtonStyle()).disabled(model.isLoadingMore)
        }
    }
    private func empty(_ title: String, text: String, symbol: String = "tray") -> some View {
        DrivyEmptyState(title: title, message: text, symbol: symbol)
    }
}

/// Same anatomy as the agenda row: time column, date, meta, state badge.
private struct SchoolTrainingLessonRow: View {
    let lesson: SchoolLesson
    var showsReport = false
    var body: some View {
        DrivyLessonRow(start: SchoolTrainingFormatting.time(lesson.plannedStart, zone: lesson.timeZone),
            end: SchoolTrainingFormatting.time(lesson.plannedEnd, zone: lesson.timeZone),
            title: SchoolTrainingFormatting.day(lesson.plannedStart, zone: lesson.timeZone),
            details: showsReport ? ["\(lesson.durationMinutes) min · bilan publié"] : ["\(lesson.durationMinutes) min", lesson.meetingPoint],
            badge: showsReport ? DrivyReportState.shared.badge : lesson.drivyState.rowBadge)
    }
}

private struct SchoolTrainingLessonView: View {
    let lesson: SchoolLesson
    @Bindable var model: SchoolTrainingWorkspace
    @Bindable var workspace: SchoolWorkspace
    let learnerName: String
    @State private var opensReport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    Text(SchoolTrainingFormatting.day(lesson.plannedStart, zone: lesson.timeZone)).font(.drivyScreenTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(learnerName).font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                    lesson.drivyState.badge
                }
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    DrivyRowGroup {
                        DrivyLessonFactRow(title: "Horaire", value: SchoolTrainingFormatting.time(lesson.plannedStart, zone: lesson.timeZone)
                            + " – " + SchoolTrainingFormatting.time(lesson.plannedEnd, zone: lesson.timeZone), monospaced: true)
                        DrivyLessonFactRow(title: "Durée", value: "\(lesson.durationMinutes) min", monospaced: true)
                        DrivyLessonFactRow(title: "Rendez-vous", value: lesson.meetingPoint)
                        DrivyLessonFactRow(title: "Prix convenu", value: SchoolCatalogFormatting.price(lesson.priceCentsSnapshot), monospaced: true)
                    }
                    Text("Horaires de la leçon · \(lesson.timeZone)").font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
                if model.canOpenPedagogicalContent {
                    VStack(spacing: DrivySpacing.s) {
                        Button { opensReport = true } label: {
                            Label(reportActionTitle, systemImage: "text.book.closed")
                        }.buttonStyle(DrivyPrimaryButtonStyle())
                        if lesson.currentPublishedRevisionId != nil {
                            NavigationLink {
                                SchoolPublishedReportsView(client: model.client, schoolID: model.scope.schoolID, trainingID: model.trainingID,
                                    lesson: lesson, competencies: model.competencies)
                            } label: { Label("Consulter les bilans partagés", systemImage: "doc.text") }
                            .buttonStyle(DrivySecondaryButtonStyle())
                        }
                    }
                }
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface).navigationTitle("Leçon").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $opensReport, onDismiss: { Task { await model.load() } }) {
            NavigationStack {
                SchoolLessonReportView(client: model.client.reports, schoolWorkspace: workspace, lessonID: lesson.id, learnerName: learnerName)
            }.tint(DrivyTheme.accent)
        }
    }
    /// Same wording as the agenda lesson sheet: prepare before, report after.
    private var reportActionTitle: String {
        switch lesson.status {
        case "PLANNED": "Préparer la leçon"
        case "COMPLETED": "Ouvrir le bilan"
        default: "Voir le suivi de la leçon"
        }
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
