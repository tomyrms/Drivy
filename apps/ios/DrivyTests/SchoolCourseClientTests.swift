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

    @Test func agendaListsOnlyTheSessionsOfTheDay() throws {
        let series = try JSONDecoder().decode(SchoolCourseSeries.self, from: seriesJSON())
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let day = try #require(SchoolLesson.date("2030-03-04T10:00:00Z"))
        let items = SchoolAgendaCourseItem.items([series], on: day, calendar: calendar)
        #expect(items.map(\.occurrence.position) == [1])
    }
}
