import Foundation
import Testing
@testable import Drivy

/// Appel, règlements et validation réactifs (#128-#130) : une file par élève, serveur synthétique sans réseau.
@MainActor struct SchoolCourseSheetQueueTests {
    private let schoolID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let seriesID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let occurrence = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!

    private func workspace(_ server: CourseSheetServer) async -> SchoolCourseAttendanceWorkspace {
        let client = SchoolCourseClient(baseURL: URL(string: "https://school.example.test")!, tokenSource: HubToken(), transport: server)
        let model = SchoolCourseAttendanceWorkspace(schoolID: schoolID, seriesID: seriesID, timeZone: "Europe/Zurich", client: client)
        await model.load()
        return model
    }

    private func row(_ model: SchoolCourseAttendanceWorkspace, _ enrollment: UUID) throws -> SchoolCourseSheetRow {
        try #require(model.rows.first { $0.enrollmentId == enrollment })
    }

    private func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aSlowLearnerNeverBlocksTheOthers() async throws {
        let server = CourseSheetServer()
        let model = await workspace(server)
        await server.hold(CourseSheetServer.first)
        model.submit(.attendance(enrollmentID: CourseSheetServer.first, occurrenceID: occurrence, status: .present, expectedVersion: nil), learnerName: "Alex")
        model.submit(.attendance(enrollmentID: CourseSheetServer.second, occurrenceID: occurrence, status: .absent, expectedVersion: nil), learnerName: "Zoé")
        await eventually { (try? row(model, CourseSheetServer.second).mark(occurrence)?.status) == .absent }
        #expect(try row(model, CourseSheetServer.second).mark(occurrence)?.status == .absent)
        // Choix affiché aussitôt, jamais présenté comme enregistré.
        let slow = try row(model, CourseSheetServer.first)
        #expect(model.displayedStatus(slow, occurrenceID: occurrence) == .present)
        #expect(slow.mark(occurrence)?.status == nil && model.isPending(slow, occurrenceID: occurrence))
        #expect(model.isSending)
        await server.release()
        await eventually { (try? row(model, CourseSheetServer.first).mark(occurrence)?.status) == .present }
        #expect(try row(model, CourseSheetServer.first).mark(occurrence)?.status == .present)
        // La réponse lente ne fait pas revenir la ligne de l’autre élève en arrière.
        #expect(try row(model, CourseSheetServer.second).mark(occurrence)?.status == .absent)
        #expect(!model.isSending && model.lanes.isEmpty)
    }

    @Test func quickChangesKeepOnlyTheLastChoiceAndTheNewVersion() async throws {
        let server = CourseSheetServer()
        let model = await workspace(server)
        await server.hold(CourseSheetServer.first)
        let learner = CourseSheetServer.first
        model.submit(.attendance(enrollmentID: learner, occurrenceID: occurrence, status: .present, expectedVersion: nil), learnerName: "Alex")
        await eventually { model.lanes[learner]?.first?.state == .sending }
        model.submit(.attendance(enrollmentID: learner, occurrenceID: occurrence, status: .absent, expectedVersion: nil), learnerName: "Alex")
        model.submit(.attendance(enrollmentID: learner, occurrenceID: occurrence, status: .excused, expectedVersion: nil), learnerName: "Alex")
        #expect(model.intents(for: learner).count == 2)
        let changing = try row(model, learner)
        #expect(model.displayedStatus(changing, occurrenceID: occurrence) == .excused)
        await server.release()
        await eventually { model.lanes.isEmpty }
        let sent = await server.attendance
        #expect(sent.map(\.status) == ["PRESENT", "EXCUSED"])
        // La seconde demande attend la version écrite par la première.
        #expect(sent.map(\.expectedVersion) == [nil, 1])
        #expect(try row(model, learner).mark(occurrence)?.status == .excused)
    }

    @Test func anUnconfirmedChangeIsRetriedWithTheSameOperation() async throws {
        let server = CourseSheetServer()
        let model = await workspace(server)
        await server.failNext()
        let learner = CourseSheetServer.first
        model.submit(.attendance(enrollmentID: learner, occurrenceID: occurrence, status: .present, expectedVersion: nil), learnerName: "Alex")
        await eventually { model.hasUnconfirmed }
        let waiting = try row(model, learner)
        let pending = try #require(model.unconfirmed(waiting))
        #expect(!model.isSending)
        #expect(model.displayedStatus(waiting, occurrenceID: occurrence) == .present)
        model.retry(learner)
        await eventually { model.lanes.isEmpty }
        let keys = await server.keys
        #expect(keys.count == 2 && keys[0] == keys[1] && keys[0] == pending.intent.id.uuidString)
        let recorded = await server.attendance
        #expect(recorded.count == 1)
        #expect(try row(model, learner).mark(occurrence)?.status == .present)
    }

    @Test func aPendingPaymentIsNeverCountedAsPaid() async throws {
        let server = CourseSheetServer()
        let model = await workspace(server)
        await server.hold(CourseSheetServer.first)
        let learner = CourseSheetServer.first
        model.submit(.payment(enrollmentID: learner, amountCents: 8000), learnerName: "Alex")
        model.submit(.payment(enrollmentID: learner, amountCents: 8000), learnerName: "Alex")
        // Deux versements identiques voulus restent deux demandes distinctes.
        let paying = try row(model, learner)
        #expect(model.pendingPayments(paying).count == 2)
        #expect(paying.payments.isEmpty)
        #expect(!model.canValidate(paying))
        await server.release()
        await eventually { model.lanes.isEmpty }
        #expect(try row(model, learner).payments.map(\.amountCents) == [8000, 8000])
        let keys = await server.keys
        #expect(Set(keys).count == 2)
    }

    @Test func aRefusalStopsOnlyThatChangeAndSaysWhy() async throws {
        let server = CourseSheetServer()
        let model = await workspace(server)
        await server.refuseNext()
        let learner = CourseSheetServer.first
        model.submit(.validate(enrollmentID: learner), learnerName: "Alex")
        await eventually { model.notices[learner] != nil }
        #expect(model.notices[learner]?.contains("Des séances obligatoires manquent.") == true)
        #expect(model.lanes.isEmpty && !model.hasUnconfirmed)
        model.clearNotice(learner)
        #expect(model.notices[learner] == nil)
    }
}

/// École synthétique : deux élèves, une séance commencée. Peut retenir les demandes d’un élève, perdre une réponse
/// ou refuser une validation.
actor CourseSheetServer: SchoolHTTPTransport {
    static let first = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!
    static let second = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000002")!
    struct Attendance: Equatable { let status: String; let expectedVersion: Int? }

    private var marks: [UUID: (status: String, version: Int)] = [:]
    private var payments: [UUID: [Int64]] = [:]
    private var held: UUID?
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var failing = false
    private var refusing = false
    private var replies: [String: Data] = [:]
    private(set) var attendance: [Attendance] = []
    private(set) var keys: [String] = []

    func hold(_ enrollment: UUID) { held = enrollment }
    func release() { held = nil; waiting.forEach { $0.resume() }; waiting = [] }
    func failNext() { failing = true }
    func refuseNext() { refusing = true }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        let parts = Array(url.pathComponents.dropFirst(4))
        guard (request.httpMethod ?? "GET") != "GET" else { return reply(url, sheet()) }
        let enrollment = UUID(uuidString: parts[1])!
        let key = request.value(forHTTPHeaderField: "Idempotency-Key") ?? ""
        keys.append(key)
        if held == enrollment { await withCheckedContinuation { waiting.append($0) } }
        if failing {
            failing = false
            // Écrit puis réponse perdue : la reprise doit rendre la même réponse, sans doublon.
            _ = apply(parts, request, enrollment: enrollment, key: key)
            throw URLError(.networkConnectionLost)
        }
        if refusing {
            refusing = false
            let problem = Data(#"{"code":"COURSE_REQUIREMENTS_MISSING","title":"Missing"}"#.utf8)
            return SchoolHTTPResponse(data: problem, status: 409, url: url, contentType: "application/problem+json")
        }
        if let replay = replies[key] { return SchoolHTTPResponse(data: replay, status: status(parts), url: url, contentType: "application/json") }
        let data = apply(parts, request, enrollment: enrollment, key: key)
        return SchoolHTTPResponse(data: data, status: status(parts), url: url, contentType: "application/json")
    }

    private func status(_ parts: [String]) -> Int { ["payments", "validate"].contains(parts.last ?? "") ? 201 : 200 }

    private func apply(_ parts: [String], _ request: URLRequest, enrollment: UUID, key: String) -> Data {
        let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
        if parts.contains("attendance"), let status = body["status"] as? String {
            attendance.append(Attendance(status: status, expectedVersion: body["expectedVersion"] as? Int))
            marks[enrollment] = (status, (marks[enrollment]?.version ?? 0) + 1)
        } else if parts.last == "payments", let cents = body["amountCents"] as? Int {
            payments[enrollment, default: []].append(Int64(cents))
        }
        let data = envelope(sheet())
        replies[key] = data
        return data
    }

    private func reply(_ url: URL, _ sheet: String) -> SchoolHTTPResponse {
        SchoolHTTPResponse(data: envelope(sheet), status: 200, url: url, contentType: "application/json")
    }

    private func envelope(_ sheet: String) -> Data {
        Data(#"{"data":\#(sheet),"requestId":"course-sheet","serverTime":"2030-03-04T18:00:00Z"}"#.utf8)
    }

    private func sheet() -> String {
        let rows = [(Self.first, "Alex Exemple"), (Self.second, "Zoé Exemple")].map { id, name in
            let mark = marks[id].map { #"{"occurrenceId":"55555555-5555-4555-8555-555555555555","status":"\#($0.status)","version":\#($0.version),"recordedAt":"2030-03-04T17:05:00.000Z"}"# }
                ?? #"{"occurrenceId":"55555555-5555-4555-8555-555555555555","status":null,"version":null,"recordedAt":null}"#
            let present = marks[id]?.status == "PRESENT" ? 1 : 0
            let paid = (payments[id] ?? []).enumerated().map { index, cents in
                #"{"id":"bbbbbbbb-0000-4000-8000-\#(String(format: "%012d", index + 1))","amountCents":\#(cents),"recordedAt":"2030-03-04T17:10:00.000Z","note":null,"voidedAt":null,"voidReason":null}"#
            }.joined(separator: ",")
            return #"{"enrollmentId":"\#(id.uuidString.lowercased())","learnerId":"\#(UUID().uuidString.lowercased())","learnerDisplayName":"\#(name)","status":"ACTIVE","cancelledAt":null,"attendance":[\#(mark)],"requirements":{"required":1,"present":\#(present),"missing":\#(1 - present)},"payments":[\#(paid)],"completion":null}"#
        }.joined(separator: ",")
        return #"{"series":\#(Self.series),"rights":{"canTakeAttendance":true,"canRecordPayment":true,"canValidate":true},"rows":[\#(rows)]}"#
    }

    private static let series = """
    {"id":"22222222-2222-4222-8222-222222222222","schoolId":"11111111-1111-4111-8111-111111111111","version":3,"status":"PUBLISHED",
     "typeId":"33333333-3333-4333-8333-333333333333","typeTitle":"Cours de sensibilisation","title":"Sensibilisation mars",
     "description":"Trois soirs","location":"Salle 2","conditions":"Permis d’élève","teachingLanguage":null,
     "responsibleMembershipId":"44444444-4444-4444-8444-444444444444","responsibleDisplayName":"Camille Exemple",
     "capacity":12,"seatsTaken":2,"remainingSeats":10,"minParticipants":1,"policyVersion":1,"selfCancelHours":24,
     "selfCancellationDeadline":"2020-03-03T17:00:00.000Z","firstStartsAt":"2020-03-04T17:00:00.000Z","lastEndsAt":"2020-03-04T20:00:00.000Z",
     "totalMinutes":180,"publishedAt":"2020-01-01T08:00:00.000Z","canManage":true,
     "occurrences":[{"id":"55555555-5555-4555-8555-555555555555","position":1,"startsAt":"2020-03-04T17:00:00.000Z","endsAt":"2020-03-04T20:00:00.000Z",
       "timeZone":"Europe/Zurich","instructorMembershipId":"44444444-4444-4444-8444-444444444444","instructorDisplayName":"Camille Exemple","attendanceRequired":true}]}
    """
}
