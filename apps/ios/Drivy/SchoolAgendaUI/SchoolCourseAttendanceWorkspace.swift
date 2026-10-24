import Foundation
import Observation

/// Commandes de la feuille d’un cours ; la clé décrit l’intention pour rejouer la même opération.
enum SchoolCourseSheetAction: Equatable, Sendable {
    case attendance(enrollmentID: UUID, occurrenceID: UUID, status: SchoolCourseAttendanceStatus, expectedVersion: Int?)
    case payment(enrollmentID: UUID, amountCents: Int64)
    case validate(enrollmentID: UUID)

    var key: String {
        switch self {
        case .attendance(let e, let o, let s, let v): "attendance|\(e)|\(o)|\(s.rawValue)|\(v.map(String.init) ?? "new")"
        case .payment(let e, let cents): "payment|\(e)|\(cents)"
        case .validate(let e): "validate|\(e)"
        }
    }
    var enrollmentID: UUID {
        switch self {
        case .attendance(let e, _, _, _), .payment(let e, _), .validate(let e): e
        }
    }
}

enum SchoolCourseSheetFormat {
    static func title(_ status: SchoolCourseAttendanceStatus) -> String {
        switch status {
        case .present: "Présent"
        case .absent: "Absent"
        case .excused: "Excusé"
        }
    }
    /// « 2 sur 3 séances obligatoires ».
    static func progress(_ requirements: SchoolCourseRequirements) -> String {
        let noun = requirements.required == 1 ? "séance obligatoire" : "séances obligatoires"
        return "\(requirements.present) sur \(requirements.required) \(noun)"
    }
}

/// Appel d’un cours publié : une commande par toucher, état relu du serveur après chaque écriture.
@MainActor @Observable final class SchoolCourseAttendanceWorkspace: Identifiable {
    let id = UUID()
    let schoolID: UUID
    let seriesID: UUID
    let timeZone: String
    let client: SchoolCourseClient
    private(set) var sheet: SchoolCourseSheet?
    private(set) var isLoading = false
    /// Élève dont une commande est en cours : bloque tout autre envoi.
    private(set) var busyEnrollment: UUID?
    var occurrenceID: UUID?
    var errorMessage: String?
    private(set) var confirmation: String?
    @ObservationIgnored private var memory = SchoolCourseOperationMemory()
    @ObservationIgnored var onChange: (@MainActor () async -> Void)?

    init(schoolID: UUID, seriesID: UUID, timeZone: String, client: SchoolCourseClient) {
        self.schoolID = schoolID; self.seriesID = seriesID; self.timeZone = timeZone; self.client = client
    }

    var isBusy: Bool { busyEnrollment != nil }
    var rights: SchoolCourseSheetRights? { sheet?.rights }
    var rows: [SchoolCourseSheetRow] {
        (sheet?.active ?? []).sorted { $0.learnerDisplayName.localizedCompare($1.learnerDisplayName) == .orderedAscending }
    }
    /// Séances déjà commencées, la plus récente en dernier.
    func startedOccurrences(now: Date = Date()) -> [SchoolCourseOccurrence] {
        (sheet?.series.occurrences ?? []).filter { ($0.start ?? .distantFuture) <= now }.sorted { $0.position < $1.position }
    }
    var occurrence: SchoolCourseOccurrence? {
        guard let occurrenceID else { return nil }
        return sheet?.series.occurrences.first { $0.id == occurrenceID }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let fresh = try await client.sheet(schoolID: schoolID, seriesID: seriesID)
            apply(fresh)
            errorMessage = nil
        } catch is CancellationError {
        } catch { errorMessage = SchoolCourseLearnerWorkspace.message(error) }
    }

    func canValidate(_ row: SchoolCourseSheetRow) -> Bool {
        rights?.canValidate == true && row.completion == nil && row.requirements.required > 0 && row.requirements.missing == 0
    }

    /// Écrit la commande ; aucune confirmation avant la réponse de l’école.
    @discardableResult func perform(_ action: SchoolCourseSheetAction, learnerName: String) async -> Bool {
        guard !isBusy else { return false }
        busyEnrollment = action.enrollmentID; errorMessage = nil; confirmation = nil
        defer { busyEnrollment = nil }
        let operation = memory.operation(for: action.key)
        do {
            let fresh: SchoolCourseSheet
            switch action {
            case .attendance(let e, let o, let status, let version):
                fresh = try await client.recordAttendance(schoolID: schoolID, seriesID: seriesID, enrollmentID: e, occurrenceID: o,
                    body: SchoolCourseAttendanceBody(operationId: operation, status: status, expectedVersion: version, note: nil))
                confirmation = "\(learnerName) : \(SchoolCourseSheetFormat.title(status))"
            case .payment(let e, let cents):
                fresh = try await client.recordPayment(schoolID: schoolID, seriesID: seriesID, enrollmentID: e,
                    body: SchoolCoursePaymentBody(operationId: operation, amountCents: cents, note: nil))
                confirmation = "Règlement de \(SchoolCatalogFormatting.price(cents)) enregistré"
            case .validate(let e):
                fresh = try await client.validate(schoolID: schoolID, seriesID: seriesID, enrollmentID: e,
                    body: SchoolCourseValidateBody(operationId: operation, note: nil))
                confirmation = "Cours validé pour \(learnerName)"
            }
            memory.settle(); apply(fresh)
            await onChange?()
            return true
        } catch is CancellationError { return false }
        catch {
            memory.fail(error)
            let message = SchoolCourseLearnerWorkspace.message(error)
            errorMessage = message
            // Un refus motivé dit que la feuille a changé : elle se relit sans effacer le message.
            if let failure = error as? SchoolPlanningFailure, failure.definitiveRejection {
                busyEnrollment = nil
                await load()
                errorMessage = message
            }
            return false
        }
    }

    private func apply(_ fresh: SchoolCourseSheet) {
        sheet = fresh
        if occurrenceID == nil || !fresh.series.occurrences.contains(where: { $0.id == occurrenceID }) {
            occurrenceID = startedOccurrences().last?.id
        }
    }
}
