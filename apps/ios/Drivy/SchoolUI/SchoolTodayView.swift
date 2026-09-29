import MapKit
import SwiftUI

/// Aujourd’hui : la carte et la prochaine leçon. Un trajet se lance toujours depuis une leçon et son élève ;
/// sans leçon prévue, « Démarrer une leçon » en planifie une qui commence dans deux minutes.
struct SchoolTodayView: View {
    @Bindable var workspace: SchoolWorkspace
    let agendaClient: SchoolAgendaClient?
    let captureController: SchoolCaptureSessionController?
    @State private var lessons: [SchoolLesson] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var preparation: SchoolCapturePreparationWorkspace?
    @State private var planning: SchoolPlanningWorkspace?
    @State private var opened: SchoolLesson?
    @State private var camera: MapCameraPosition = .userLocation(fallback: .region(JourneyMapRegion.overview))

    private var scopeKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0)"
    }
    private var instructs: Bool {
        workspace.membership?.roles.contains("INSTRUCTOR") == true && workspace.school?.status == "ACTIVE"
    }
    /// Prochaine leçon encore à venir ou en cours aujourd’hui.
    private var next: SchoolLesson? {
        lessons.filter { $0.status == "PLANNED" && ($0.endsAt ?? .distantPast) > Date() }
            .min { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
    }

    var body: some View {
        Map(position: $camera) { UserAnnotation() }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls { MapUserLocationButton() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                card.padding(DrivySpacing.m).frame(maxWidth: 600)
            }
            .task(id: scopeKey) { await load() }
            .sheet(item: $preparation, onDismiss: { Task { await load() } }) { model in
                SchoolCapturePreparationView(model: model, schoolWorkspace: workspace)
            }
            .sheet(item: $planning, onDismiss: { Task { await load() } }) { model in
                SchoolPlanningView(model: model)
            }
            .sheet(item: $opened, onDismiss: { Task { await load() } }) { lesson in
                if let agendaClient {
                    NavigationStack {
                        SchoolLessonReportView(client: agendaClient.reportClient, schoolWorkspace: workspace, lessonID: lesson.id, learnerName: name(lesson))
                    }
                    .tint(DrivyTheme.accent)
                }
            }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            if let next {
                Button { opened = next } label: {
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(time(next)).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(DrivyTheme.text)
                        Text(name(next)).font(.headline).foregroundStyle(DrivyTheme.text)
                        Text(next.meetingPoint).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvrir la leçon")
                if instructs, next.instructorMembershipId == workspace.membership?.membershipId {
                    Button { start(next) } label: { Label("Démarrer", systemImage: "location.fill") }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                }
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("Aucune autre leçon aujourd’hui").font(.headline).foregroundStyle(DrivyTheme.text)
                if instructs {
                    Button { planNow() } label: { Label("Démarrer une leçon", systemImage: "plus") }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                }
            }
            if let error { SchoolErrorNotice(message: error, retry: { Task { await load() } }) }
        }
        .padding(DrivySpacing.m)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private func name(_ lesson: SchoolLesson) -> String {
        workspace.learners.first { $0.id == lesson.learnerId }?.displayName
            ?? (workspace.learner?.id == lesson.learnerId ? workspace.learner?.displayName : nil) ?? "Leçon de conduite"
    }
    private func time(_ lesson: SchoolLesson) -> String {
        guard let start = lesson.startsAt, let end = lesson.endsAt else { return "—" }
        let format = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "fr_CH"),
            timeZone: TimeZone(identifier: lesson.timeZone) ?? .current)
        return "\(start.formatted(format)) – \(end.formatted(format))"
    }

    private func start(_ lesson: SchoolLesson) {
        guard let agendaClient, let person = workspace.person, let membership = workspace.membership,
              lesson.instructorMembershipId == membership.membershipId else { return }
        preparation = agendaClient.capturePreparation(scope: agendaClient.scope(person: person, membership: membership),
            lessonID: lesson.id, controller: captureController)
    }
    private func planNow() {
        guard let agendaClient, let person = workspace.person, let membership = workspace.membership, instructs else { return }
        planning = SchoolPlanningWorkspace(scope: agendaClient.scope(person: person, membership: membership),
            client: agendaClient.planningClient, date: Date().addingTimeInterval(120))
    }

    @MainActor private func load() async {
        guard let agendaClient, let membership = workspace.membership else { lessons = []; return }
        let key = scopeKey
        isLoading = true; error = nil
        defer { if key == scopeKey { isLoading = false } }
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = calendar.startOfDay(for: Date()), dayEnd = dayStart.addingTimeInterval(86_400)
        do {
            var all: [SchoolLesson] = [], cursor: String?, pages = 0
            repeat {
                pages += 1
                let page = try await agendaClient.lessons(schoolID: membership.schoolId, from: dayStart, to: dayEnd, cursor: cursor)
                all.append(contentsOf: page.items); cursor = page.nextCursor
            } while cursor != nil && pages < 10
            guard key == scopeKey, !Task.isCancelled else { return }
            lessons = all
        } catch {
            guard key == scopeKey, !Task.isCancelled else { return }
            self.error = (error as? LocalizedError)?.errorDescription ?? "Les leçons du jour n’ont pas pu être chargées."
        }
    }
}
