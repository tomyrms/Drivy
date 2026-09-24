import SwiftUI

struct SchoolAgendaView: View {
    let client: SchoolAgendaClient
    @Bindable var workspace: SchoolWorkspace
    var captureController: SchoolCaptureSessionController? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedDate = Date()
    @State private var lessons: [SchoolLesson] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var loadedScope: String?
    @State private var selectedLesson: SchoolLesson?
    @State private var planningModel: SchoolPlanningWorkspace?
    @State private var setupModel: SchoolPlanningWorkspace?

    private var identityScope: String { "\(workspace.person?.id.uuidString ?? ""):\(workspace.membership?.id.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0)" }
    private var mayPlan: Bool { workspace.membership?.roles.contains(where: { ["ADMIN", "INSTRUCTOR"].contains($0) }) == true && workspace.school?.status == "ACTIVE" }

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.locale = Locale(identifier: "fr_CH")
        result.firstWeekday = 2
        result.timeZone = TimeZone(identifier: workspace.school?.timeZone ?? "Europe/Zurich") ?? .current
        return result
    }
    private var weekStart: Date { calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? calendar.startOfDay(for: selectedDate) }
    private var weekDays: [Date] { (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) } }
    private var dailyLessons: [SchoolLesson] {
        guard loadedScope == scopeKey else { return [] }
        return lessons.filter { lesson in lesson.startsAt.map { calendar.isDate($0, inSameDayAs: selectedDate) } ?? false }
            .sorted { $0.plannedStart < $1.plannedStart }
    }
    private var scopeKey: String { "\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0):\(weekStart.timeIntervalSince1970)" }
    private var dateTitle: String {
        if calendar.isDateInToday(selectedDate) { return "Aujourd’hui" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH"); formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: selectedDate).capitalized
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                weekHeader
                dayPicker
                dayHeading
                if workspace.membership == nil {
                    ContentUnavailableView("Choisissez votre école", systemImage: "building.2", description: Text("Votre agenda apparaît après la sélection d’une école."))
                } else if isLoading || (loadedScope != scopeKey && error == nil) {
                    ProgressView("Chargement de l’agenda…").frame(maxWidth: .infinity, minHeight: 160)
                } else if let error {
                    SchoolErrorNotice(message: error, retry: { Task { await loadWeek() } })
                } else if dailyLessons.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Aucune leçon ce jour.").foregroundStyle(DrivyTheme.muted)
                        Button("Jour suivant", systemImage: "arrow.right") {
                            if let next = calendar.date(byAdding: .day, value: 1, to: selectedDate) { selectedDate = next }
                        }.frame(minHeight: 44)
                    }.padding(.vertical, 16)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(dailyLessons) { lesson in
                            Button { selectedLesson = lesson } label: { lessonRow(lesson) }.buttonStyle(.plain)
                            Divider().overlay(DrivyTheme.border)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 800, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DrivyTheme.canvas)
        .navigationTitle("Agenda")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Aujourd’hui") { selectedDate = Date() }.font(.subheadline.weight(.medium))
            }
            if mayPlan {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { setupModel = newPlanningModel() } label: { Label("Réglages du planning", systemImage: "slider.horizontal.3") }
                }
            }
        }
        .task(id: scopeKey) { selectedLesson = nil; await loadWeek() }
        .refreshable { await loadWeek() }
        .sheet(item: $selectedLesson) { lesson in
            SchoolLessonDetailView(client: client, workspace: workspace, schoolID: lesson.schoolId,
                lessonID: lesson.id, learnerName: learnerName(lesson), captureController: captureController)
        }
        .sheet(item: $planningModel, onDismiss: { Task { await loadWeek() } }) { model in SchoolPlanningView(model: model) }
        .sheet(item: $setupModel, onDismiss: { Task { await loadWeek() } }) { model in SchoolPlanningSetupView(model: model) }
        .onChange(of: identityScope) { _, _ in
            planningModel?.invalidate(); setupModel?.invalidate(); planningModel = nil; setupModel = nil; selectedLesson = nil
        }
    }

    private var weekHeader: some View {
        HStack {
            Text(formattedDay(selectedDate, template: "MMMM yyyy"))
                .font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { moveWeek(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Semaine précédente")
            Button { moveWeek(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .accessibilityLabel("Semaine suivante")
        }
    }

    private var dayHeading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(dateTitle).font(.title2.weight(.bold)).fixedSize()
                Spacer(minLength: 12)
                if mayPlan { planButton }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(dateTitle).font(.title2.weight(.bold))
                if mayPlan { planButton }
            }
        }
    }
    private var planButton: some View {
        Button { planningModel = newPlanningModel() } label: {
            Label("Planifier", systemImage: "plus").font(.body.weight(.semibold)).frame(minHeight: 44).fixedSize()
        }
        .accessibilityLabel("Planifier une leçon")
        .accessibilityIdentifier("agenda-plan-lesson")
    }
    @ViewBuilder private var dayPicker: some View {
        if typeSize.isAccessibilitySize { compactDayPicker }
        else {
            ViewThatFits(in: .horizontal) {
                weekStrip
                compactDayPicker
            }
        }
    }
    private var compactDayPicker: some View {
        DatePicker("Choisir un jour", selection: $selectedDate, displayedComponents: .date)
            .environment(\.timeZone, calendar.timeZone)
            .environment(\.calendar, calendar)
            .environment(\.locale, Locale(identifier: "fr_CH"))
    }
    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(weekDays, id: \.self) { day in
                let selected = calendar.isDate(day, inSameDayAs: selectedDate)
                Button { selectedDate = day } label: {
                    VStack(spacing: 9) {
                        Text(formattedDay(day, template: "EEEEE"))
                            .font(.caption.weight(.medium))
                        Text(String(calendar.component(.day, from: day))).font(.headline)
                        Circle().fill(hasLessons(on: day) ? (selected ? DrivyTheme.onAccent : DrivyTheme.accent) : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(minWidth: 44, maxWidth: .infinity, minHeight: 76)
                    .foregroundStyle(selected ? DrivyTheme.onAccent : DrivyTheme.text)
                    .background(selected ? DrivyTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(formattedDay(day, template: "EEEE d MMMM"))
                .accessibilityValue(hasLessons(on: day) ? "Contient des leçons" : "")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }

    private func lessonRow(_ lesson: SchoolLesson) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(time(lesson.startsAt)) – \(time(lesson.endsAt))")
                        .font(.headline.monospacedDigit()).foregroundStyle(DrivyTheme.accent)
                    lessonSummary(lesson)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(time(lesson.startsAt)).font(.headline.monospacedDigit()).foregroundStyle(DrivyTheme.accent)
                        Text(time(lesson.endsAt)).font(.caption.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                    }.fixedSize(horizontal: true, vertical: false)
                    lessonSummary(lesson)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                        .padding(.top, 4).accessibilityHidden(true)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 20).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
    private func lessonSummary(_ lesson: SchoolLesson) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(learnerName(lesson)).font(.headline).foregroundStyle(DrivyTheme.text)
            Text("\(lesson.durationMinutes) min · \(lesson.statusLabel)").font(.subheadline)
                .foregroundStyle(lesson.status == "CANCELLED" ? DrivyTheme.warning : DrivyTheme.muted)
            Text(lesson.meetingPoint).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func learnerName(_ lesson: SchoolLesson) -> String { workspace.learners.first { $0.id == lesson.learnerId }?.displayName ?? "Leçon de conduite" }
    private func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    private func formattedDay(_ date: Date, template: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH"); formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
    private func hasLessons(on day: Date) -> Bool {
        loadedScope == scopeKey && lessons.contains { $0.startsAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
    }
    private func moveWeek(_ offset: Int) { if let date = calendar.date(byAdding: .weekOfYear, value: offset, to: selectedDate) { selectedDate = date } }
    private func newPlanningModel() -> SchoolPlanningWorkspace? {
        guard let person = workspace.person, let membership = workspace.membership, mayPlan else { return nil }
        let day = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let proposed = max(day, Date().addingTimeInterval(3600))
        return SchoolPlanningWorkspace(scope: client.scope(person: person, membership: membership), client: client.planningClient, date: proposed)
    }
    @MainActor private func loadWeek() async {
        let id = UUID(); requestID = id; lessons = []; error = nil; loadedScope = nil
        guard let schoolID = workspace.membership?.schoolId, let end = calendar.date(byAdding: .day, value: 7, to: weekStart) else { isLoading = false; return }
        let start = weekStart, scope = scopeKey
        isLoading = true
        defer { if requestID == id { isLoading = false } }
        do {
            var all: [SchoolLesson] = [], cursor: String?, seen = Set<String>()
            repeat {
                let page = try await client.lessons(schoolID: schoolID, from: start, to: end, cursor: cursor)
                guard !Task.isCancelled, requestID == id, scopeKey == scope else { return }
                all.append(contentsOf: page.items); cursor = page.nextCursor
                if let cursor, !seen.insert(cursor).inserted { throw SchoolAgendaFailure.invalidResponse }
                if all.count > 10_000 { throw SchoolAgendaFailure.invalidResponse }
            } while cursor != nil
            guard Set(all.map(\.id)).count == all.count else { throw SchoolAgendaFailure.invalidResponse }
            lessons = all; loadedScope = scope
        } catch {
            guard !Task.isCancelled, requestID == id else { return }
            self.error = (error as? LocalizedError)?.errorDescription ?? "L’agenda n’a pas pu être chargé."
        }
    }
}

private struct SchoolLessonDetailView: View {
    let client: SchoolAgendaClient
    @Bindable var workspace: SchoolWorkspace
    let schoolID: UUID
    let lessonID: UUID
    let learnerName: String
    var captureController: SchoolCaptureSessionController? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var lesson: SchoolLesson?
    @State private var error: String?
    @State private var planningRoute: PlanningRoute?
    @State private var showsReport = false
    @State private var capturePreparation: SchoolCapturePreparationWorkspace?
    @State private var mayPrepareCapture = false

    private struct PlanningRoute: Identifiable {
        let id = UUID()
        let model: SchoolPlanningWorkspace
        let cancelling: Bool
    }

    private var identityScope: String { "\(workspace.person?.id.uuidString ?? ""):\(workspace.membership?.id.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0)" }
    private var mayManage: Bool { workspace.membership?.schoolId == schoolID && workspace.membership?.roles.contains(where: { ["ADMIN", "INSTRUCTOR"].contains($0) }) == true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let lesson {
                        Text(learnerName).font(.title.weight(.bold))
                        Label(lesson.statusLabel, systemImage: lesson.status == "COMPLETED" ? "checkmark.circle" : "calendar")
                            .foregroundStyle(lesson.status == "CANCELLED" ? DrivyTheme.warning : lesson.status == "COMPLETED" ? DrivyTheme.success : DrivyTheme.muted)
                        VStack(spacing: 0) {
                            LessonInfoRow(title: "Date", value: lessonDate(lesson))
                            Divider()
                            LessonInfoRow(title: "Horaire", value: interval(lesson))
                            Divider()
                            LessonInfoRow(title: "Durée", value: "\(lesson.durationMinutes) minutes")
                            Divider()
                            LessonInfoRow(title: "Rendez-vous", value: lesson.meetingPoint)
                            Divider()
                            LessonInfoRow(title: "Prix convenu", value: (Decimal(lesson.priceCentsSnapshot) / 100).formatted(.currency(code: "CHF")))
                        }
                        if lesson.permitWarning {
                            Label("Le permis d’élève reste à vérifier avant la conduite.", systemImage: "exclamationmark.shield")
                                .font(.subheadline).foregroundStyle(DrivyTheme.warning)
                        }
                        lessonActions(lesson)
                    } else if let error { SchoolErrorNotice(message: error, retry: { Task { await load() } }) }
                    else { ProgressView("Ouverture de la leçon…").frame(maxWidth: .infinity, minHeight: 180) }
                }
                .padding(24).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.canvas)
            .navigationTitle("Leçon").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
            .task { await load() }
            .sheet(item: $planningRoute, onDismiss: { Task { await load() } }) { route in
                SchoolPlanningView(model: route.model, cancelling: route.cancelling)
            }
            .sheet(isPresented: $showsReport, onDismiss: { Task { await load() } }) {
                NavigationStack {
                    SchoolLessonReportView(client: client.reportClient, schoolWorkspace: workspace, lessonID: lessonID, learnerName: learnerName)
                }.tint(DrivyTheme.accent)
            }
            .sheet(item: $capturePreparation) { model in
                SchoolCapturePreparationView(model: model, schoolWorkspace: workspace)
            }
            .onChange(of: identityScope) { _, _ in
                capturePreparation?.invalidate(); capturePreparation = nil; mayPrepareCapture = false
                planningRoute?.model.invalidate(); planningRoute = nil; showsReport = false; lesson = nil; dismiss()
            }
        }.tint(DrivyTheme.accent)
    }
    private func lessonActions(_ lesson: SchoolLesson) -> some View {
        VStack(spacing: 12) {
            if mayPrepareCapture {
                Button { openCapturePreparation() } label: { Label("Préparer le GPS", systemImage: "location.circle") }
                    .buttonStyle(DrivySecondaryButtonStyle()).accessibilityIdentifier("lesson-prepare-gps")
            }
            if workspace.membership?.roles.contains(where: { ["INSTRUCTOR", "LEARNER"].contains($0) }) == true {
                Button { showsReport = true } label: {
                    Label(workspace.membership?.roles.contains("INSTRUCTOR") == true
                          ? (lesson.status == "COMPLETED" ? "Bilans et suivi" : "Préparer et suivre la leçon")
                          : (lesson.status == "COMPLETED" ? "Lire le bilan" : "Voir le suivi de ma leçon"), systemImage: "text.book.closed")
                }.buttonStyle(DrivyPrimaryButtonStyle())
            }
            if mayManage && lesson.status == "PLANNED" {
                if let start = lesson.startsAt, start > Date() {
                    Button { openPlanning(lesson, cancelling: false) } label: { Label("Déplacer la leçon", systemImage: "calendar.badge.clock") }
                        .buttonStyle(DrivySecondaryButtonStyle())
                }
                Button("Annuler la leçon", role: .destructive) { openPlanning(lesson, cancelling: true) }.frame(minHeight: 48)
            }
        }
    }
    private func openPlanning(_ lesson: SchoolLesson, cancelling: Bool) {
        guard let person = workspace.person, let membership = workspace.membership, mayManage else { return }
        let model = SchoolPlanningWorkspace(scope: client.scope(person: person, membership: membership), client: client.planningClient, lesson: lesson)
        planningRoute = PlanningRoute(model: model, cancelling: cancelling)
    }
    private func openCapturePreparation() {
        guard mayPrepareCapture, let person = workspace.person, let membership = workspace.membership,
              membership.schoolId == schoolID else { return }
        let scope = client.scope(person: person, membership: membership)
        if let captureController {
            let handler: SchoolCaptureStartHandler = { transfer, source, session, lease, authorization, receivedAt in
                try await captureController.adoptAndStart(transfer: transfer, source: source, session: session,
                    lease: lease, authorization: authorization, receivedAt: receivedAt)
            }
            capturePreparation = SchoolCapturePreparationWorkspace(scope: scope, lessonID: lessonID,
                client: client.captureClient, reader: client.reader, agenda: client,
                journalProvider: { try await captureController.journal() }, onCaptureAuthorized: handler,
                onRefusalConfirmed: { learnerID, lessonID in captureController.learnerRefused(learnerID: learnerID, lessonID: lessonID) },
                canUseDiagnostic: { captureController.canPrepareCapture })
        } else {
            capturePreparation = SchoolCapturePreparationWorkspace(scope: scope, lessonID: lessonID,
                client: client.captureClient, reader: client.reader, agenda: client)
        }
    }
    private func interval(_ lesson: SchoolLesson) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH"); formatter.timeZone = TimeZone(identifier: lesson.timeZone); formatter.dateFormat = "HH:mm"
        guard let start = lesson.startsAt, let end = lesson.endsAt else { return "—" }
        return formatter.string(from: start) + " – " + formatter.string(from: end)
    }
    private func lessonDate(_ lesson: SchoolLesson) -> String {
        guard let date = lesson.startsAt else { return "—" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH")
        formatter.timeZone = TimeZone(identifier: lesson.timeZone); formatter.dateStyle = .long
        return formatter.string(from: date)
    }
    @MainActor private func load() async {
        lesson = nil; error = nil; mayPrepareCapture = false
        let scope = identityScope
        do {
            let loaded = try await client.lesson(schoolID: schoolID, id: lessonID)
            guard identityScope == scope, !Task.isCancelled else { return }
            lesson = loaded
            if let member = workspace.membership, member.roles.contains("INSTRUCTOR"), member.membershipId == loaded.instructorMembershipId {
                mayPrepareCapture = true
            } else if workspace.membership?.roles.contains("LEARNER") == true {
                let learner = try? await client.reader.learner(schoolID: schoolID, id: loaded.learnerId)
                guard identityScope == scope, !Task.isCancelled else { return }
                mayPrepareCapture = learner?.personId == workspace.person?.personId && learner != nil
            }
        }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? "La leçon n’a pas pu être chargée." }
    }
}

private struct LessonInfoRow: View {
    let title: String
    let value: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    Text(value).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(title).foregroundStyle(DrivyTheme.muted)
                    Spacer(minLength: 0)
                    Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
                }
            }
        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 14)
            .accessibilityElement(children: .combine)
    }
}
