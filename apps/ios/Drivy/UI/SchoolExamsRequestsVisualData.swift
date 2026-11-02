#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Examens (#54) et demandes de l'élève (#52) des écrans de contrôle : données fictives et lecture seule, comme le reste du harnais.
/// Le rôle choisit ce que l'école rend : le personnel gère et lit les résultats à renseigner, l'élève lit les siens.
extension SchoolVisualData {
    nonisolated static func examsAndRequestsObjects(root: String, learnerRole: Bool, screen: String?) -> [String: Any] {
        let null = NSNull()
        let learnerName = "Camille Perret"
        func exam(_ number: Int, kind: String, status: String, startsAt: String, attempt: Int?, needsResult: Bool = false,
                  note: String = "", escort: [String: Any]? = nil) -> [String: Any] {
            ["id": identifier(150 + number).uuidString, "trainingId": trainingID.uuidString, "kind": kind, "categoryCode": "B", "status": status,
             "startsAt": startsAt, "timeZone": "Europe/Zurich", "location": "Centre d’examen de Lausanne", "escort": escort ?? null,
             "resultNote": note, "resultRecordedAt": ["PASSED", "FAILED", "ABSENT"].contains(status) ? "2026-09-02T12:00:00Z" : null,
             "postponedToExamId": null, "attempt": attempt.map { $0 as Any } ?? null, "needsResult": needsResult, "version": 1,
             "createdAt": "2026-08-01T08:00:00Z"]
        }
        let theory = exam(1, kind: "THEORY", status: "PASSED", startsAt: "2026-08-12T09:00:00Z", attempt: 1)
        let failed = exam(2, kind: "PRACTICAL", status: "FAILED", startsAt: "2026-09-02T09:00:00Z", attempt: 1,
                          note: "Priorités à droite, regard dans les rétroviseurs")
        let waiting = exam(3, kind: "PRACTICAL", status: "SCHEDULED", startsAt: "2026-09-23T08:30:00Z", attempt: 2, needsResult: true,
            escort: ["instructorMembershipId": membershipID.uuidString, "startsAt": "2026-09-23T07:30:00Z", "endsAt": "2026-09-23T10:00:00Z"])
        let upcoming = exam(4, kind: "PRACTICAL", status: "SCHEDULED", startsAt: "2026-10-08T08:30:00Z", attempt: 2)
        let waitingID = waiting["id"] as? String ?? "", upcomingID = upcoming["id"] as? String ?? ""
        func summary(_ practicalScheduled: String?) -> [[String: Any]] {
            [["kind": "THEORY", "passed": true, "attempts": 1, "scheduledExamId": null],
             ["kind": "PRACTICAL", "passed": false, "attempts": 2, "scheduledExamId": practicalScheduled.map { $0 as Any } ?? null]]
        }
        let examState: [String: Any] = learnerRole
            ? ["trainingId": trainingID.uuidString, "canManage": false, "escortCandidates": [], "exams": [upcoming, failed, theory], "summary": summary(upcomingID)]
            : ["trainingId": trainingID.uuidString, "canManage": true,
               "escortCandidates": [["membershipId": membershipID.uuidString, "displayName": "Julien Rey"]],
               "exams": [waiting, failed, theory], "summary": summary(waitingID)]
        func listItem(_ value: [String: Any]) -> [String: Any] {
            ["exam": value, "learnerId": learnerID.uuidString, "learnerDisplayName": learnerName]
        }
        var objects: [String: Any] = [
            "\(root)/trainings/\(trainingID.uuidString)/exams": examState,
            "\(root)/exams?filter=PENDING_RESULT": ["filter": "PENDING_RESULT", "items": learnerRole ? [] : [listItem(waiting)]],
            "\(root)/exams?filter=UPCOMING": ["filter": "UPCOMING", "items": learnerRole ? [listItem(upcoming)] : []],
        ]

        // Demandes de l'élève (#52) sur la leçon planifiée.
        func request(kind: String, status: String, note: String, mine: Bool, late: Bool?, resolution: String? = nil) -> [String: Any] {
            ["id": identifier(160).uuidString, "lessonId": plannedLessonID.uuidString, "kind": kind, "status": status, "note": note, "mine": mine,
             "late": late.map { $0 as Any } ?? null, "deadlineAt": late == nil ? null : "2026-09-27T08:00:00Z", "cancellationHours": 24,
             "policyVersionId": identifier(50).uuidString, "resolvedAt": status == "PENDING" ? null : "2026-09-25T09:00:00Z",
             "resolutionNote": resolution.map { $0 as Any } ?? null, "version": 1, "createdAt": "2026-09-24T07:00:00Z"]
        }
        func requestState(requests: [[String: Any]], canRequest: Bool, blocked: String?) -> [String: Any] {
            ["lessonId": plannedLessonID.uuidString,
             "conditions": ["policyVersionId": identifier(50).uuidString, "policyVersion": 1,
                "cancellationPolicyText": "Prévenez l’école au moins 24 heures avant le début de la leçon.", "cancellationHours": 24, "lateAction": "CONTACT",
                "deadlineAt": "2026-09-27T08:00:00Z", "late": false, "canRequest": canRequest, "blockedReason": blocked.map { $0 as Any } ?? null] as [String: Any],
             "requests": requests]
        }
        let pendingForStaff = request(kind: "RESCHEDULE", status: "PENDING", note: "Plutôt mercredi après 16 h, ou jeudi toute la journée.", mine: false, late: false)
        let pendingOwn = request(kind: "CANCEL", status: "PENDING", note: "Je suis malade, je ne pourrai pas conduire.", mine: true, late: true)
        let refusedOwn = request(kind: "RESCHEDULE", status: "REFUSED", note: "Plutôt jeudi", mine: true, late: false, resolution: "Ce créneau est déjà pris")
        let lessonState: [String: Any]
        switch screen {
        case "lesson-request": lessonState = requestState(requests: [pendingForStaff], canRequest: false, blocked: "NOT_LEARNER")
        case "learner-lesson-request": lessonState = requestState(requests: [pendingOwn], canRequest: false, blocked: "REQUEST_PENDING")
        case "learner-lesson-refused": lessonState = requestState(requests: [refusedOwn], canRequest: true, blocked: nil)
        default: lessonState = requestState(requests: [], canRequest: learnerRole, blocked: learnerRole ? nil : "NOT_LEARNER")
        }
        objects["\(root)/lessons/\(plannedLessonID.uuidString)/change-requests"] = lessonState
        objects["\(root)/lesson-change-requests"] = ["items": learnerRole ? [] : [[
            "request": pendingForStaff,
            "lesson": ["id": plannedLessonID.uuidString, "plannedStart": "2026-09-28T08:00:00Z", "plannedEnd": "2026-09-28T08:50:00Z", "timeZone": "Europe/Zurich",
                       "version": 1, "instructorMembershipId": membershipID.uuidString, "learnerId": learnerID.uuidString, "learnerDisplayName": learnerName]]]]
        return objects
    }
}
#endif
