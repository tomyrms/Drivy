import Foundation

/// Le trajet de cette leçon tel que l’appareil le connaît. Sans contrôleur de séance,
/// l’état reste inconnu : rien n’est proposé qui dépendrait du GPS de cet appareil.
enum SchoolLessonCaptureStatus: Equatable {
    case unknown, none, collecting, stopped

    @MainActor init(state: SchoolCaptureSessionController.State?, captureLessonID: UUID?, lessonID: UUID) {
        guard let state, captureLessonID == lessonID else { self = .none; return }
        switch state {
        case .preparing, .recording, .paused, .stopping: self = .collecting
        case .saved, .failed: self = .stopped
        case .idle: self = .none
        }
    }

    @MainActor init(controller: SchoolCaptureSessionController?, lessonID: UUID) {
        guard let controller else { self = .unknown; return }
        self.init(state: controller.captureID == nil ? nil : controller.state, captureLessonID: controller.lessonID, lessonID: lessonID)
    }

    /// Le constat attend l’arrêt du GPS de cette leçon.
    var permitsCompletion: Bool { self != .collecting }
}

/// Règles de l’écran unique d’une leçon. Toutes sont relues par le serveur ;
/// elles évitent seulement de proposer une action qu’il refuserait à coup sûr.
enum SchoolLessonHubRules {
    /// CAPTURE_START_WINDOW : le serveur n’autorise un départ qu’à 30 minutes près de l’horaire prévu.
    static func withinCaptureWindow(_ lesson: SchoolLesson, now: Date) -> Bool {
        guard let start = lesson.startsAt, let end = lesson.endsAt else { return false }
        return now >= start.addingTimeInterval(-1_800) && now < end.addingTimeInterval(1_800)
    }

    static func mayStartCapture(lesson: SchoolLesson, isAuthor: Bool, school: SchoolDetails?,
                                capture: SchoolLessonCaptureStatus, controllerCanPrepare: Bool, now: Date) -> Bool {
        guard isAuthor, lesson.status == "PLANNED", let school, school.id == lesson.schoolId,
              school.status == "ACTIVE", school.modules.gpsEnabled else { return false }
        return capture == .none && controllerCanPrepare && withinCaptureWindow(lesson, now: now)
    }

    /// Départ possible plus tard (ouverture de la fenêtre), toutes les autres conditions réunies.
    static func captureOpening(lesson: SchoolLesson, isAuthor: Bool, school: SchoolDetails?,
                               capture: SchoolLessonCaptureStatus, controllerCanPrepare: Bool, now: Date) -> Date? {
        guard let start = lesson.startsAt else { return nil }
        let opening = start.addingTimeInterval(-1_800)
        guard now < opening, mayStartCapture(lesson: lesson, isAuthor: isAuthor, school: school, capture: capture,
            controllerCanPrepare: controllerCanPrepare, now: opening) else { return nil }
        return opening
    }
    /// « 13:30 » si l’ouverture tombe aujourd’hui (fuseau de la leçon) ; sinon rien, la date de la leçon suffit.
    static func openingLabel(_ opening: Date, zone: String, now: Date) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .current
        guard calendar.isDate(opening, inSameDayAs: now) else { return nil }
        return time(opening, zone: zone)
    }
    /// LESSON_NOT_STARTED : le serveur refuse le constat plus de 15 minutes avant le début prévu.
    static func mayFinish(_ lesson: SchoolLesson, now: Date) -> Bool {
        guard lesson.status == "PLANNED", let start = lesson.startsAt else { return false }
        return now >= start.addingTimeInterval(-900)
    }
    /// Constat d’une observation : son statut, ou celui du repère posé d’une tuile pendant le trajet.
    static func status(of observation: SchoolObservation) -> SchoolObservationStatus? {
        if let status = observation.eventStatus.flatMap(SchoolObservationStatus.init(rawValue:)) { return status }
        return observation.isMarker ? SchoolObservationStatus(markerText: observation.text) : nil
    }

    static func mayManage(_ roles: [String]) -> Bool { roles.contains("ADMIN") || roles.contains("INSTRUCTOR") }
    static func mayMove(_ lesson: SchoolLesson, roles: [String], now: Date) -> Bool {
        mayManage(roles) && lesson.status == "PLANNED" && (lesson.startsAt.map { $0 > now } ?? false)
    }
    static func mayCancel(_ lesson: SchoolLesson, roles: [String]) -> Bool {
        mayManage(roles) && lesson.status == "PLANNED"
    }

    /// Début et fin proposés au constat : ceux du trajet de la leçon s’il existe, sinon l’horaire prévu ;
    /// jamais une fin à venir. Un arrêt local pas encore transmis vaut l’instant présent.
    static func completionTimes(lesson: SchoolLesson, captures: [SchoolCaptureSession], now: Date) -> (start: Date, end: Date) {
        let own = captures.filter { $0.lessonId == lesson.id }
        let capturedStart = own.compactMap { SchoolLesson.date($0.authorizedAt) }.min()
        let capturedEnd = own.compactMap { capture -> Date? in
            if let value = capture.stoppedAt ?? capture.cutoffAt { return SchoolLesson.date(value) }
            let expiry = SchoolLesson.date(capture.expiresAt)
            return capture.captureState == .authorized ? min(now, expiry ?? now) : expiry
        }.max()
        let end = min(capturedEnd ?? lesson.endsAt ?? now, now)
        let start = min(capturedStart ?? lesson.startsAt ?? end.addingTimeInterval(-3_000), end.addingTimeInterval(-60))
        return (start, end)
    }

    /// Situation proposée pour une compétence notée : le jour et le lieu de la leçon, modifiables.
    /// Proposition modifiable et facultative, limitée à 500 caractères.
    static func observationContext(for lesson: SchoolLesson) -> String {
        let date = lesson.actualStart.flatMap(SchoolLesson.date) ?? lesson.startsAt
        let day = date.map { format($0, zone: lesson.timeZone, template: "dMMMM") } ?? ""
        let place = lesson.meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = [day.isEmpty ? "Leçon" : "Leçon du \(day)", place].filter { !$0.isEmpty }.joined(separator: " · ")
        return String(String.UnicodeScalarView(text.unicodeScalars.prefix(500)))
    }

    /// Choisir un niveau ajoute la compétence avec sa situation proposée ; « Non observé » la retire.
    /// Une situation déjà écrite n’est jamais remplacée.
    static func observations(_ values: [SchoolReportObservation], setting level: String, for competencyID: UUID,
                             context: String) -> [SchoolReportObservation] {
        var result = values
        if level.isEmpty {
            result.removeAll { $0.competencyId == competencyID }
        } else if let index = result.firstIndex(where: { $0.competencyId == competencyID }) {
            result[index].level = level
            if result[index].context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result[index].context = context }
        } else {
            result.append(SchoolReportObservation(competencyId: competencyID, level: level, context: context))
        }
        return result
    }

    /// Choix « inchangé » d’une compétence dans le bilan : la valeur vide n’écrit aucune observation. Quand l’élève a déjà un niveau
    /// issu d’une autre leçon, il est rappelé ici comme point de départ ; il n’est jamais recopié dans le bilan de cette leçon
    /// (« pas encore vu » n’est pas une note, et un niveau non travaillé ce jour-là n’est pas une observation).
    static func unchangedChoiceLabel(current: SchoolReportProgressItem?) -> String {
        guard let current else { return "Pas encore vu" }
        return "Actuel : \(current.levelLabel)"
    }

    /// Texte d’une observation repris comme situation d’une compétence (500 caractères au plus).
    static func situation(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(String.UnicodeScalarView(text.unicodeScalars.prefix(500)))
    }

    /// Les observations restent des éléments distincts : les recopier dans le texte partagé rendrait
    /// leur action « Pour moi » inopérante sur cette copie. Les objectifs alimentent seulement le travail réalisé.
    static func completionReport(goals: [SchoolLessonGoal], observations: [SchoolObservation],
                                 competencies: [SchoolCatalogCompetency]) -> (workedOn: String, observationText: String) {
        let worked = goals.map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
        return (limited(worked, 4_000), "")
    }
    private static func limited(_ text: String, _ count: Int) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.prefix(count)))
    }

    /// « Lundi 28 septembre · 14:00 – 15:00 », dans le fuseau de la leçon.
    static func schedule(_ lesson: SchoolLesson) -> String? {
        guard let start = lesson.startsAt, let end = lesson.endsAt else { return nil }
        let day = format(start, zone: lesson.timeZone, template: "EEEEdMMMM")
        return "\(day.prefix(1).uppercased() + day.dropFirst()) · \(time(start, zone: lesson.timeZone)) – \(time(end, zone: lesson.timeZone))"
    }

    private static func time(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH"); formatter.timeZone = TimeZone(identifier: zone) ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    private static func format(_ date: Date, zone: String, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH"); formatter.timeZone = TimeZone(identifier: zone) ?? .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

/// Une relecture ne perd jamais la saisie ni ne la rebascule silencieusement sur une version concurrente.
/// Un contenu confirmé égal à la saisie est l'acquittement de notre enregistrement.
enum SchoolLessonRefreshPolicy: Equatable {
    case replace, keepEdits, conflict

    static func decide<Value: Equatable>(previous: Value?, edited: Value, received: Value?, discardingEdits: Bool) -> Self {
        guard !discardingEdits, let previous, previous != edited else { return .replace }
        if received == edited { return .replace }
        if received == previous { return .keepEdits }
        return .conflict
    }
}
