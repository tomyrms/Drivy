import Foundation
import Testing
@testable import Drivy

/// Cours collectifs (#38) : contrat de `apps/api/src/courses.ts`, sans réseau.
@MainActor struct SchoolCourseClientTests {
    private let schoolID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let seriesID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let typeID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    private let instructorID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

    private func seriesJSON(status: String = "DRAFT", publishedAt: String? = nil) -> Data {
        let published = publishedAt.map { "\"\($0)\"" } ?? "null"
        return Data("""
        {"id":"\(seriesID.uuidString.lowercased())","schoolId":"\(schoolID.uuidString.lowercased())","version":3,"status":"\(status)",
         "typeId":"\(typeID.uuidString.lowercased())","typeTitle":"Cours de sensibilisation","title":"Sensibilisation mars",
         "description":"Trois soirs","location":"Salle 2, rue du Lac 4","conditions":"Permis d’élève","teachingLanguage":null,
         "responsibleMembershipId":"\(instructorID.uuidString.lowercased())","responsibleDisplayName":"Camille Exemple",
         "capacity":12,"seatsTaken":2,"remainingSeats":10,"minParticipants":4,"policyVersion":1,"selfCancelHours":24,
         "selfCancellationDeadline":"2030-03-03T17:00:00.000Z","firstStartsAt":"2030-03-04T17:00:00.000Z","lastEndsAt":"2030-03-11T20:00:00.000Z",
         "totalMinutes":360,"publishedAt":\(published),"canManage":true,
         "occurrences":[
          {"id":"55555555-5555-4555-8555-555555555555","position":1,"startsAt":"2030-03-04T17:00:00.000Z","endsAt":"2030-03-04T20:00:00.000Z",
           "timeZone":"Europe/Zurich","instructorMembershipId":"\(instructorID.uuidString.lowercased())","instructorDisplayName":"Camille Exemple","attendanceRequired":true},
          {"id":"66666666-6666-4666-8666-666666666666","position":2,"startsAt":"2030-03-11T17:00:00.000Z","endsAt":"2030-03-11T20:00:00.000Z",
           "timeZone":"Europe/Zurich","instructorMembershipId":"\(instructorID.uuidString.lowercased())","instructorDisplayName":"Camille Exemple","attendanceRequired":false}]}
        """.utf8)
    }

    @Test func decodesARealisticSeries() throws {
        let series = try JSONDecoder().decode(SchoolCourseSeries.self, from: seriesJSON())
        #expect(series.id == seriesID && series.schoolId == schoolID && series.version == 3)
        #expect(series.isDraft && series.status == .draft)
        #expect(series.minParticipants == 4 && series.teachingLanguage == nil && series.publishedAt == nil)
        #expect(series.occurrences.count == 2)
        #expect(series.occurrences[1].attendanceRequired == false)
        #expect(series.occurrences[0].start == SchoolLesson.date("2030-03-04T17:00:00Z"))
        #expect(SchoolCourseClient.valid(series, schoolID: schoolID))
        #expect(!SchoolCourseClient.valid(series, schoolID: UUID()))
        let published = try JSONDecoder().decode(SchoolCourseSeries.self, from: seriesJSON(status: "PUBLISHED", publishedAt: "2030-01-01T08:00:00.000Z"))
        #expect(published.status == .published && !published.isDraft)
    }

    @Test func encodesNullsExplicitlyInTheSeriesCommand() throws {
        let operation = UUID()
        let body = SchoolCourseSeriesBody(operationId: operation, typeId: typeID, title: "Cours", description: "", location: "",
            conditions: "", teachingLanguage: nil, responsibleMembershipId: instructorID, capacity: 10, minParticipants: nil,
            timeZone: "Europe/Zurich", occurrences: [SchoolCourseOccurrenceInput(startsAt: "2030-03-04T17:00:00Z", endsAt: "2030-03-04T20:00:00Z",
                instructorMembershipId: instructorID, attendanceRequired: true)])
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        #expect(Set(object.keys) == ["operationId", "typeId", "title", "description", "location", "conditions", "teachingLanguage",
            "responsibleMembershipId", "capacity", "minParticipants", "timeZone", "occurrences"])
        #expect(object["teachingLanguage"] is NSNull && object["minParticipants"] is NSNull)
        #expect((object["operationId"] as? String).flatMap(UUID.init(uuidString:)) == operation)
        let sessions = try #require(object["occurrences"] as? [[String: Any]])
        #expect(Set(sessions[0].keys) == ["startsAt", "endsAt", "instructorMembershipId", "attendanceRequired"])
    }

    @Test func formValidationMirrorsTheServerBounds() throws {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        var form = SchoolCourseForm()
        #expect(form.problem() == "Choisis un type de cours.")
        form.typeID = typeID; form.title = "  "
        #expect(form.problem() == "Indique un titre.")
        form.title = "Sensibilisation"; form.responsibleID = instructorID
        #expect(form.problem() == "Ajoute au moins une séance.")
        form.occurrences = [SchoolCourseOccurrenceDraft(startsAt: start, endsAt: start.addingTimeInterval(3 * 3600), instructorID: instructorID)]
        #expect(form.problem(now: start.addingTimeInterval(-60)) == nil)
        form.minParticipants = 13
        #expect(form.problem() == "Le minimum ne peut pas dépasser la capacité.")
        form.minParticipants = 4
        form.occurrences.append(SchoolCourseOccurrenceDraft(startsAt: start.addingTimeInterval(3600), endsAt: start.addingTimeInterval(5 * 3600), instructorID: instructorID))
        #expect(form.problem() == "Deux séances se chevauchent.")
        form.occurrences[1] = SchoolCourseOccurrenceDraft(startsAt: start.addingTimeInterval(86_400), endsAt: start.addingTimeInterval(86_400 + 13 * 3600), instructorID: instructorID)
        #expect(form.problem() == "Une séance dure au plus 12 heures.")
        form.occurrences[1].endsAt = start.addingTimeInterval(86_400 + 2 * 3600)
        #expect(form.problem(now: start.addingTimeInterval(-60)) == nil)
        #expect(form.problem(now: start.addingTimeInterval(60), publishing: true) == "La première séance est déjà passée.")
        #expect(form.totalMinutes == 300)
        let body = try #require(form.body(operationID: UUID(), timeZone: "Europe/Zurich"))
        #expect(body.occurrences.count == 2 && body.minParticipants == 4 && body.title == "Sensibilisation")
    }

    @Test func draftRoundTripsThroughTheForm() throws {
        let series = try JSONDecoder().decode(SchoolCourseSeries.self, from: seriesJSON())
        let form = SchoolCourseForm(series: series)
        #expect(form.typeID == typeID && form.capacity == 12 && form.minParticipants == 4 && form.occurrences.count == 2)
        #expect(form.totalMinutes == series.totalMinutes)
    }

    @Test func wordingStaysShort() {
        #expect(SchoolCourseFormat.cancellationSentence(hours: 24) == "Annulation libre jusqu’à 24 h avant la première séance")
        #expect(SchoolCourseFormat.duration(minutes: 450) == "7 h 30")
        #expect(SchoolCourseFormat.duration(minutes: 45) == "45 min")
        #expect(SchoolCourseFormat.seats(0) == "Complet")
        #expect(SchoolCourseClient.failure(409, "COURSE_INSTRUCTOR_CONFLICT") == .rejected("Un moniteur a déjà un rendez-vous pendant une séance. Le brouillon est conservé."))
        #expect(SchoolCourseClient.failure(412, "VERSION_CONFLICT") == .conflict)
    }

    // MARK: Inscriptions (#39-#41)

    private let enrollmentID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
    private let learnerID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
    private let offerID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!

    private func enrollmentJSON(status: String = "ACTIVE", canSelfCancel: Bool = true) -> String {
        """
        {"id":"\(enrollmentID.uuidString.lowercased())","seriesId":"\(seriesID.uuidString.lowercased())","learnerId":"\(learnerID.uuidString.lowercased())",
         "version":2,"status":"\(status)","source":"SELF","policyVersion":1,"selfCancelHours":24,"selfCancelDeadline":"2030-03-03T17:00:00.000Z",
         "canSelfCancel":\(canSelfCancel),"createdAt":"2030-01-02T08:00:00.000Z","cancelledAt":null,"cancelKind":null,"cancelReason":null}
        """
    }
    private func replyJSON(state: String, enrollment: String = "null", offer: String = "null", position: String = "null",
                           waitlist: Bool = true, email: String = "\"ecole@example.ch\"") -> Data {
        let series = String(decoding: seriesJSON(status: "PUBLISHED", publishedAt: "2030-01-01T08:00:00.000Z"), as: UTF8.self)
        return Data("""
        {"series":\(series),"me":{"learnerId":"\(learnerID.uuidString.lowercased())","state":"\(state)","enrollment":\(enrollment),
         "offer":\(offer),"waitlistPosition":\(position),"waitlistEnabled":\(waitlist),"contactEmail":\(email)}}
        """.utf8)
    }

    @Test func decodesEveryLearnerState() throws {
        let decoder = JSONDecoder()
        let states: [(String, SchoolCourseLearnerState.State)] = [("AVAILABLE", .available), ("FULL", .full), ("COMPLETED", .completed),
            ("CANCELLED", .cancelled), ("CLOSED", .closed)]
        for (raw, state) in states {
            let reply = try decoder.decode(SchoolCourseLearnerReply.self, from: replyJSON(state: raw))
            #expect(reply.me.state == state && reply.series.id == seriesID && reply.me.enrollment == nil)
            #expect(SchoolCourseClient.valid(reply.series, schoolID: schoolID))
        }
        let enrolled = try decoder.decode(SchoolCourseLearnerReply.self, from: replyJSON(state: "ENROLLED", enrollment: enrollmentJSON(canSelfCancel: false)))
        let enrollment = try #require(enrolled.me.enrollment)
        #expect(enrolled.me.state == .enrolled && enrollment.id == enrollmentID && enrollment.version == 2)
        #expect(enrollment.status == .active && !enrollment.canSelfCancel && enrollment.deadline == SchoolLesson.date("2030-03-03T17:00:00Z"))
        #expect(enrolled.me.contactEmail == "ecole@example.ch")

        let waiting = try decoder.decode(SchoolCourseLearnerReply.self, from: replyJSON(state: "WAITING", position: "3"))
        #expect(waiting.me.state == .waiting && waiting.me.waitlistPosition == 3)
        #expect(SchoolCourseEnrollmentFormat.status(waiting.me, zone: "Europe/Zurich") == "En attente (rang 3)")

        let offer = "{\"id\":\"\(offerID.uuidString.lowercased())\",\"seriesId\":\"\(seriesID.uuidString.lowercased())\",\"expiresAt\":\"2030-03-01T17:30:00.000Z\",\"status\":\"ACTIVE\"}"
        let offered = try decoder.decode(SchoolCourseLearnerReply.self, from: replyJSON(state: "OFFERED", offer: offer, email: "null"))
        #expect(offered.me.state == .offered && offered.me.offer?.id == offerID && offered.me.contactEmail == nil)
        // 17:30 UTC = 18:30 à Zurich en hiver : l’heure suit le fuseau de l’école.
        let sameDay = try #require(SchoolLesson.date("2030-03-01T08:00:00Z"))
        #expect(SchoolCourseEnrollmentFormat.status(offered.me, zone: "Europe/Zurich", now: sameDay) == "Place proposée jusqu’à 18:30")

        let words: [(SchoolCourseLearnerState.State, String)] = [(.available, "Disponible"), (.full, "Complet"), (.enrolled, "Inscrit"),
            (.completed, "Déjà effectué"), (.cancelled, "Annulé")]
        for (state, word) in words {
            let me = SchoolCourseLearnerState(learnerId: learnerID, state: state, enrollment: nil, offer: nil, waitlistPosition: nil,
                waitlistEnabled: false, contactEmail: nil)
            #expect(SchoolCourseEnrollmentFormat.status(me, zone: "Europe/Zurich") == word)
        }
    }

    @Test func decodesMineAndTheStaffRoster() throws {
        let mine = try JSONDecoder().decode(SchoolCourseMine.self, from: Data("""
        {"items":[\(enrollmentJSON())],"offers":[]}
        """.utf8))
        #expect(mine.items.map(\.id) == [enrollmentID] && mine.offers.isEmpty)
        let roster = try JSONDecoder().decode(SchoolCourseRoster.self, from: Data("""
        {"items":[{\(enrollmentJSON().dropFirst().dropLast()),"learnerDisplayName":"Alex Exemple"},
                  {\(enrollmentJSON(status: "CANCELLED").dropFirst().dropLast()),"learnerDisplayName":"Sam Exemple"}],
         "waitlist":[{"id":"\(offerID.uuidString.lowercased())","learnerId":"\(learnerID.uuidString.lowercased())","learnerDisplayName":"Lou",
           "position":1,"status":"WAITING","queuedAt":"2030-01-03T08:00:00.000Z","offerExpiresAt":null}]}
        """.utf8))
        #expect(roster.items.count == 2 && roster.active.map(\.learnerDisplayName) == ["Alex Exemple"])
        #expect(roster.waitlist.first?.position == 1 && roster.waitlist.first?.offerExpiresAt == nil)
    }

    @Test func encodesEnrollmentCommands() throws {
        let operation = UUID()
        let plain = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SchoolCoursePublishBody(operationId: operation))) as? [String: Any])
        #expect(Set(plain.keys) == ["operationId"])
        let enroll = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            SchoolCourseStaffEnrollBody(operationId: operation, learnerId: learnerID))) as? [String: Any])
        #expect(Set(enroll.keys) == ["operationId", "learnerId"])
        #expect((enroll["learnerId"] as? String).flatMap(UUID.init(uuidString:)) == learnerID)
        let cancel = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            SchoolCourseStaffCancelBody(operationId: operation, reason: "Malade"))) as? [String: Any])
        #expect(Set(cancel.keys) == ["operationId", "reason"] && cancel["reason"] as? String == "Malade")
    }

    @Test func retriesKeepTheSameOperation() {
        var memory = SchoolCourseOperationMemory()
        let first = memory.operation(for: SchoolCourseLearnerAction.enroll.key)
        memory.fail(SchoolPlanningFailure.unavailable)
        #expect(memory.operation(for: SchoolCourseLearnerAction.enroll.key) == first)
        memory.fail(SchoolPlanningFailure.rejected("Ce cours est complet."))
        #expect(memory.operation(for: SchoolCourseLearnerAction.enroll.key) != first)
        #expect(SchoolCourseLearnerAction.cancel(enrollmentID: enrollmentID, version: 2).key
            != SchoolCourseLearnerAction.cancel(enrollmentID: enrollmentID, version: 3).key)
        #expect(SchoolCourseClient.failure(409, "COURSE_SELF_CANCEL_CLOSED") == .rejected("Le délai d’annulation est passé."))
    }

    @Test func contactMailNeedsARealAddress() {
        #expect(SchoolCourseEnrollmentFormat.mailURL(nil, courseTitle: "Cours")  == nil)
        #expect(SchoolCourseEnrollmentFormat.mailURL("  ", courseTitle: "Cours") == nil)
        #expect(SchoolCourseEnrollmentFormat.mailURL("ecole@example.ch", courseTitle: "Cours")?.scheme == "mailto")
    }

    @Test func agendaListsOnlyTheSessionsOfTheDay() throws {
        let series = try JSONDecoder().decode(SchoolCourseSeries.self, from: seriesJSON())
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let day = try #require(SchoolLesson.date("2030-03-04T10:00:00Z"))
        let items = SchoolAgendaCourseItem.items([series], on: day, calendar: calendar)
        #expect(items.map(\.occurrence.position) == [1])
    }
}
