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
                } else { ProgressView("Ouverture de la formation…") }
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
            .padding(.horizontal, DrivySpacing.l)
            .padding(.vertical, DrivySpacing.m)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
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
                .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
            if let training = model.training {
                DrivyStatusBadge(title: SchoolPresentation.trainingStatus(training.status), symbol: "steeringwheel",
                    tone: training.status == "ACTIVE" ? .accent : training.status == "COMPLETED" ? .success : .neutral)
                if let date = training.startedOn {
                    Text("Depuis le \(SchoolPresentation.civilDate(date))").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                }
                if let date = training.closedOn {
                    Text("Clôturée le \(SchoolPresentation.civilDate(date))").font(.subheadline).foregroundStyle(DrivyTheme.muted)
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
        VStack(alignment: .leading, spacing: 24) {
            if model.lessonsLoaded && model.lessons.isEmpty && !model.isLoading {
                empty("Aucune leçon", text: "Aucun rendez-vous n’est enregistré pour cette formation.")
            }
            if !model.upcomingLessons.isEmpty {
                lessonGroup("Rendez-vous", values: model.upcomingLessons)
            }
            if !model.pastLessons.isEmpty { lessonGroup("Historique", values: model.pastLessons) }
            moreLessons
        }
    }
    private func lessonGroup(_ title: String, values: [SchoolLesson]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DrivySectionHeader(title: title)
            VStack(spacing: 0) {
                ForEach(values) { lesson in
                    NavigationLink {
                        SchoolTrainingLessonView(lesson: lesson, model: model, workspace: workspace, learnerName: learner.displayName)
                    } label: { SchoolTrainingLessonRow(lesson: lesson) }
                    .buttonStyle(.plain).accessibilityIdentifier("training-lesson-\(lesson.id.uuidString)")
                    Divider()
                }
            }
        }
    }
    private var reports: some View {
        VStack(alignment: .leading, spacing: 16) {
            DrivySectionHeader(title: "Bilans partagés")
            if model.canOpenPedagogicalContent {
                if model.lessonsLoaded && model.publishedLessons.isEmpty {
                    empty("Aucun bilan partagé", text: model.nextCursor == nil
                        ? "Les bilans apparaissent après leur publication par le moniteur."
                        : "Aucun bilan dans cette liste. Affichez les leçons suivantes pour poursuivre.")
                }
                ForEach(model.publishedLessons) { lesson in
                    NavigationLink {
                        SchoolPublishedReportsView(client: model.client, schoolID: model.scope.schoolID,
                            trainingID: model.trainingID, lesson: lesson, competencies: model.competencies)
                    } label: { SchoolTrainingLessonRow(lesson: lesson, showsReport: true) }
                    .buttonStyle(.plain)
                    Divider()
                }
                moreLessons
            } else { pedagogyStatus }
        }
    }
    private var progress: some View {
        VStack(alignment: .leading, spacing: 18) {
            DrivySectionHeader(title: "Parcours pédagogique")
            if let value = model.progress {
                if let error = model.progressError { SchoolErrorNotice(message: error, retry: { Task { await model.loadProgress() } }) }
                ForEach(value.items) { item in
                    NavigationLink {
                        SchoolPublishedRevisionView(client: model.client, schoolID: model.scope.schoolID,
                            trainingID: model.trainingID, lessonID: item.sourceLessonId, revisionID: item.sourceRevisionId,
                            competencies: model.competencies)
                    } label: { progressRow(item) }
                    .buttonStyle(.plain)
                    Divider()
                }
                ForEach(model.unobservedCompetencies) { competency in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(competency.label).font(.headline)
                        DrivyStatusBadge(title: "Non observé")
                        if !competency.description.isEmpty {
                            DisclosureGroup("Description de la compétence") {
                                Text(competency.description).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                                    .padding(.top, 8)
                            }.font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    Divider()
                }
                if value.items.isEmpty && value.unobservedCompetencyIds.isEmpty {
                    empty("Aucune compétence", text: "Le référentiel de cette formation ne contient aucune compétence.")
                } else if model.unobservedCompetencies.count < value.unobservedCompetencyIds.count {
                    Text("Certaines compétences non observées n’ont pas pu être chargées.").font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
            } else { pedagogyStatus }
        }
    }
    private func progressRow(_ item: SchoolReportProgressItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.label).font(.headline).foregroundStyle(DrivyTheme.text)
                DrivyStatusBadge(title: SchoolTrainingFormatting.level(item.level), tone: .accent)
                Text(item.context).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                Text(SchoolTrainingFormatting.instant(item.observedAt, zone: workspace.school?.timeZone ?? "Europe/Zurich"))
                    .font(.caption).foregroundStyle(DrivyTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
        }
        .padding(.vertical, 8).contentShape(Rectangle())
    }
    @ViewBuilder private var pedagogyStatus: some View {
        if let error = model.progressError { SchoolErrorNotice(message: error, retry: { Task { await model.loadProgress() } }) }
        else { ProgressView("Ouverture du parcours…").frame(maxWidth: .infinity, minHeight: 80) }
    }
    @ViewBuilder private var moreLessons: some View {
        if model.nextCursor != nil {
            Button { Task { await model.loadMore() } } label: {
                if model.isLoadingMore { ProgressView("Chargement…") } else { Text("Afficher les leçons suivantes") }
            }
            .buttonStyle(.bordered).frame(minHeight: 48).disabled(model.isLoadingMore)
        }
    }
    private func empty(_ title: String, text: String) -> some View {
        DrivyEmptyState(title: title, message: text, symbol: "tray")
    }
}

private struct SchoolTrainingLessonRow: View {
    let lesson: SchoolLesson
    var showsReport = false
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: showsReport ? "doc.text" : "calendar")
                .font(.title3).foregroundStyle(DrivyTheme.muted).frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(SchoolTrainingFormatting.day(lesson.plannedStart, zone: lesson.timeZone)).font(.headline)
                Text(SchoolTrainingFormatting.time(lesson.plannedStart, zone: lesson.timeZone) + " · \(lesson.durationMinutes) min")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            if showsReport {
                DrivyStatusBadge(title: "Partagé", symbol: "checkmark", tone: .success)
            } else if lesson.status != "PLANNED" {
                DrivyStatusBadge(title: lesson.statusLabel, tone: lesson.status == "COMPLETED" ? .success : .warning)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted).padding(.top, 6)
        }
        .foregroundStyle(DrivyTheme.text).padding(.vertical, DrivySpacing.m).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    Text(SchoolTrainingFormatting.day(lesson.plannedStart, zone: lesson.timeZone)).font(.largeTitle.bold())
                    Text(learnerName).font(.title3).foregroundStyle(DrivyTheme.muted)
                    DrivyStatusBadge(title: lesson.statusLabel, symbol: "calendar",
                        tone: lesson.status == "PLANNED" ? .accent : lesson.status == "COMPLETED" ? .success : .warning)
                }
                DrivyRowGroup {
                    lessonFact(SchoolTrainingFormatting.time(lesson.plannedStart, zone: lesson.timeZone) + " · \(lesson.durationMinutes) min", symbol: "clock")
                    lessonFact(lesson.meetingPoint, symbol: "mappin.and.ellipse")
                    lessonFact(SchoolCatalogFormatting.price(lesson.priceCentsSnapshot), symbol: "tag")
                }
                Text("Horaires de la leçon · \(lesson.timeZone)").font(.caption).foregroundStyle(DrivyTheme.muted)
                if model.canOpenPedagogicalContent {
                    Button { opensReport = true } label: {
                        Label(lesson.status == "PLANNED" ? "Préparer cette leçon" : "Ouvrir le suivi de la leçon", systemImage: "text.book.closed")
                    }.buttonStyle(DrivyPrimaryButtonStyle())
                    if lesson.currentPublishedRevisionId != nil {
                        NavigationLink {
                            SchoolPublishedReportsView(client: model.client, schoolID: model.scope.schoolID, trainingID: model.trainingID,
                                lesson: lesson, competencies: model.competencies)
                        } label: { Label("Consulter les bilans partagés", systemImage: "doc.text").frame(minHeight: 48) }
                    }
                }
            }
            .padding(.horizontal, DrivySpacing.l).padding(.vertical, DrivySpacing.m)
            .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(DrivyTheme.surface).navigationTitle("Leçon").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $opensReport, onDismiss: { Task { await model.load() } }) {
            NavigationStack {
                SchoolLessonReportView(client: model.client.reports, schoolWorkspace: workspace, lessonID: lesson.id, learnerName: learnerName)
            }
        }
    }
}

private func lessonFact(_ text: String, symbol: String) -> some View {
    HStack(spacing: DrivySpacing.m) {
        Image(systemName: symbol).font(.body).foregroundStyle(DrivyTheme.muted).frame(width: 28).accessibilityHidden(true)
        Text(text).font(.body).foregroundStyle(DrivyTheme.text).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
    }
    .padding(.vertical, DrivySpacing.s)
    .frame(minHeight: 48)
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
