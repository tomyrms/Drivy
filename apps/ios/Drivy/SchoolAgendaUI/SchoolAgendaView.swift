import SwiftUI

struct SchoolAgendaView: View {
    let client: SchoolAgendaClient
    @Bindable var workspace: SchoolWorkspace
    @State private var selectedDate = Date()
    @State private var lessons: [SchoolLesson] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var loadedScope: String?
    @State private var selectedLesson: SchoolLesson?

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
                HStack(alignment: .firstTextBaseline) {
                    Text(dateTitle).font(.title2.weight(.bold))
                    Spacer()
                    if !isLoading && error == nil {
                        Text(dailyLessons.count == 1 ? "1 leçon" : "\(dailyLessons.count) leçons")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                }
                if workspace.membership == nil {
                    ContentUnavailableView("Choisissez votre école", systemImage: "building.2", description: Text("Votre agenda apparaît après la sélection d’une école."))
                } else if isLoading {
                    ProgressView("Chargement de l’agenda…").frame(maxWidth: .infinity, minHeight: 160)
                } else if let error {
                    SchoolErrorNotice(message: error, retry: { Task { await loadWeek() } })
                } else if dailyLessons.isEmpty {
                    ContentUnavailableView("Une journée libre", systemImage: "calendar", description: Text("Aucune leçon planifiée pour cette date."))
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    VStack(spacing: 14) {
                        ForEach(dailyLessons) { lesson in
                            Button { selectedLesson = lesson } label: { lessonRow(lesson) }.buttonStyle(.plain)
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
        }
        .task(id: scopeKey) { selectedLesson = nil; await loadWeek() }
        .refreshable { await loadWeek() }
        .sheet(item: $selectedLesson) { lesson in
            SchoolLessonDetailView(client: client, schoolID: lesson.schoolId, lessonID: lesson.id, learnerName: learnerName(lesson))
        }
    }

    private var weekHeader: some View {
        HStack {
            Text(selectedDate.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_CH"))))
                .font(.title3.weight(.semibold))
            Spacer()
            Button { moveWeek(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Semaine précédente")
            Button { moveWeek(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .accessibilityLabel("Semaine suivante")
        }
    }

    private var dayPicker: some View {
        HStack(spacing: 4) {
            ForEach(weekDays, id: \.self) { day in
                let selected = calendar.isDate(day, inSameDayAs: selectedDate)
                Button { selectedDate = day } label: {
                    VStack(spacing: 9) {
                        Text(day.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "fr_CH"))))
                            .font(.caption.weight(.medium))
                        Text(String(calendar.component(.day, from: day))).font(.headline)
                        Circle().fill(hasLessons(on: day) ? (selected ? DrivyTheme.onAccent : DrivyTheme.accent) : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .foregroundStyle(selected ? DrivyTheme.onAccent : DrivyTheme.text)
                    .background(selected ? DrivyTheme.accent : DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH"))))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }

    private func lessonRow(_ lesson: SchoolLesson) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(time(lesson.startsAt)).font(.headline.monospacedDigit()).foregroundStyle(DrivyTheme.accent)
                Text(time(lesson.endsAt)).font(.caption.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
            }.frame(width: 52, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(lesson.status == "CANCELLED" ? DrivyTheme.border : DrivyTheme.accent).frame(width: 3)
            VStack(alignment: .leading, spacing: 7) {
                Text(learnerName(lesson)).font(.headline).foregroundStyle(DrivyTheme.text)
                Text("\(lesson.durationMinutes) min · \(lesson.statusLabel)").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                Label(lesson.meetingPoint, systemImage: "mappin.and.ellipse")
                    .font(.caption).foregroundStyle(DrivyTheme.muted).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private func learnerName(_ lesson: SchoolLesson) -> String { workspace.learners.first { $0.id == lesson.learnerId }?.displayName ?? "Leçon de conduite" }
    private func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    private func hasLessons(on day: Date) -> Bool { lessons.contains { $0.startsAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false } }
    private func moveWeek(_ offset: Int) { if let date = calendar.date(byAdding: .weekOfYear, value: offset, to: selectedDate) { selectedDate = date } }
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
    let schoolID: UUID
    let lessonID: UUID
    let learnerName: String
    @Environment(\.dismiss) private var dismiss
    @State private var lesson: SchoolLesson?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let lesson {
                        Text(learnerName).font(.largeTitle.weight(.bold))
                        Label(lesson.statusLabel, systemImage: lesson.status == "COMPLETED" ? "checkmark.circle" : "calendar")
                            .foregroundStyle(DrivyTheme.accent)
                        DrivyPanel {
                            VStack(alignment: .leading, spacing: 18) {
                                LessonInfoRow(title: "Date", value: lesson.startsAt?.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_CH"))) ?? "—")
                                LessonInfoRow(title: "Horaire", value: interval(lesson))
                                LessonInfoRow(title: "Durée", value: "\(lesson.durationMinutes) minutes")
                                LessonInfoRow(title: "Rendez-vous", value: lesson.meetingPoint)
                                LessonInfoRow(title: "Prix convenu", value: (Decimal(lesson.priceCentsSnapshot) / 100).formatted(.currency(code: "CHF")))
                            }
                        }
                        if lesson.permitWarning {
                            Label("Le permis d’élève reste à vérifier avant la conduite.", systemImage: "exclamationmark.shield")
                                .font(.subheadline).foregroundStyle(DrivyTheme.warning)
                        }
                    } else if let error { SchoolErrorNotice(message: error, retry: { Task { await load() } }) }
                    else { ProgressView("Ouverture de la leçon…").frame(maxWidth: .infinity, minHeight: 180) }
                }
                .padding(24).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.canvas)
            .navigationTitle("La leçon").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
            .task { await load() }
        }.tint(DrivyTheme.accent)
    }
    private func interval(_ lesson: SchoolLesson) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH"); formatter.timeZone = TimeZone(identifier: lesson.timeZone); formatter.dateFormat = "HH:mm"
        guard let start = lesson.startsAt, let end = lesson.endsAt else { return "—" }
        return formatter.string(from: start) + " – " + formatter.string(from: end)
    }
    @MainActor private func load() async {
        lesson = nil; error = nil
        do { lesson = try await client.lesson(schoolID: schoolID, id: lessonID) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? "La leçon n’a pas pu être chargée." }
    }
}

private struct LessonInfoRow: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(DrivyTheme.muted)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
