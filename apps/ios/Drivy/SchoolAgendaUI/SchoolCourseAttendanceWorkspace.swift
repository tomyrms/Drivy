import Foundation
import Observation

enum SchoolCourseParticipantMode: String, CaseIterable, Identifiable {
    case attendance, payments, validation
    var id: String { rawValue }
    var title: String {
        switch self { case .attendance: "Appel"; case .payments: "Règlements"; case .validation: "Validation" }
    }
    static func available(_ rights: SchoolCourseSheetRights?) -> [Self] {
        guard let rights else { return [] }
        let modes: [Self?] = [rights.canTakeAttendance ? .attendance : nil, rights.canRecordPayment ? .payments : nil,
                             rights.canValidate ? .validation : nil]
        return modes.compactMap { $0 }
    }
}

/// Commandes de la feuille d’un cours ; la clé décrit l’intention pour rejouer la même opération.
enum SchoolCourseSheetAction: Equatable, Sendable {
    case attendance(enrollmentID: UUID, occurrenceID: UUID, status: SchoolCourseAttendanceStatus, expectedVersion: Int?)
    case payment(enrollmentID: UUID, amountCents: Int64)
    case validate(enrollmentID: UUID)
    case voidPayment(enrollmentID: UUID, paymentID: UUID, reason: String)
    case revokeCompletion(enrollmentID: UUID, completionID: UUID, reason: String)

    var key: String {
        switch self {
        case .attendance(let e, let o, let s, let v): "attendance|\(e)|\(o)|\(s.rawValue)|\(v.map(String.init) ?? "new")"
        case .payment(let e, let cents): "payment|\(e)|\(cents)"
        case .validate(let e): "validate|\(e)"
        case .voidPayment(_, let p, let r): "void|\(p)|\(r)"
        case .revokeCompletion(_, let c, let r): "revoke|\(c)|\(r)"
        }
    }
    var enrollmentID: UUID {
        switch self {
        case .attendance(let e, _, _, _), .payment(let e, _), .validate(let e), .voidPayment(let e, _, _), .revokeCompletion(let e, _, _): e
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
    /// Motif obligatoire, borné comme au serveur (1 à 1000 caractères après rognage).
    static func reason(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.utf16.count > 1000 ? nil : trimmed
    }
    /// « 2 sur 3 séances obligatoires ».
    static func progress(_ requirements: SchoolCourseRequirements) -> String {
        let noun = requirements.required == 1 ? "séance obligatoire" : "séances obligatoires"
        return "\(requirements.present) sur \(requirements.required) \(noun)"
    }
}

/// Changement saisi sur la feuille d’un cours (#128-#130). Son identifiant est l’`operationId` : une reprise
/// renvoie exactement la même demande, figée au premier envoi.
struct SchoolCourseSheetIntent: Identifiable, Equatable {
    enum State: Equatable {
        case queued, sending
        /// Panne ou réponse perdue : peut-être enregistré, jamais présenté comme un refus.
        case uncertain(String)
    }
    let id: UUID
    var action: SchoolCourseSheetAction
    let learnerName: String
    var sent = false
    var state: State = .queued

    var occurrenceID: UUID? {
        if case .attendance(_, let occurrence, _, _) = action { return occurrence }
        return nil
    }
    var attendanceStatus: SchoolCourseAttendanceStatus? {
        if case .attendance(_, _, let status, _) = action { return status }
        return nil
    }
}

/// Annonce VoiceOver ponctuelle ; l’identifiant permet d’annoncer deux fois le même texte.
struct SchoolCourseAnnouncement: Equatable {
    let id = UUID()
    let text: String
}

/// Appel, règlements et validation d’un cours publié. Chaque élève a sa propre file : marquer dix présences
/// n’attend pas chaque aller-retour, et un envoi lent ou en échec ne bloque que la ligne concernée. Les demandes
/// d’un même élève partent dans l’ordre (la validation dépend des présences). Une réponse ne remplace que la
/// ligne de son élève ; rien n’est présenté comme enregistré avant la réponse de l’école.
@MainActor @Observable final class SchoolCourseAttendanceWorkspace: Identifiable {
    let id = UUID()
    let schoolID: UUID
    let seriesID: UUID
    let timeZone: String
    let client: SchoolCourseClient
    private(set) var sheet: SchoolCourseSheet?
    private(set) var isLoading = false
    var occurrenceID: UUID?
    /// Erreur de lecture de la feuille ; les erreurs d’envoi restent sur la ligne concernée.
    var errorMessage: String?
    private(set) var announcement: SchoolCourseAnnouncement?
    /// Demandes en cours ou à reprendre, par inscription.
    private(set) var lanes: [UUID: [SchoolCourseSheetIntent]] = [:]
    /// Refus de l’école, affiché sur la ligne jusqu’à ce qu’on le masque.
    private(set) var notices: [UUID: String] = [:]
    @ObservationIgnored private var running: Set<UUID> = []
    @ObservationIgnored private var rowStamps: [UUID: Int] = [:]
    @ObservationIgnored private var stamp = 0
    @ObservationIgnored private var reloadRequested = false
    @ObservationIgnored var onChange: (@MainActor () async -> Void)?

    init(schoolID: UUID, seriesID: UUID, timeZone: String, client: SchoolCourseClient) {
        self.schoolID = schoolID; self.seriesID = seriesID; self.timeZone = timeZone; self.client = client
    }

    var rights: SchoolCourseSheetRights? { sheet?.rights }
    var rows: [SchoolCourseSheetRow] {
        (sheet?.active ?? []).sorted { $0.learnerDisplayName.localizedCompare($1.learnerDisplayName) == .orderedAscending }
    }
    /// Des demandes partent encore : la feuille ne se ferme pas sous elles.
    var isSending: Bool { lanes.values.contains { $0.contains { $0.state == .queued || $0.state == .sending } } }
    /// Une demande attend une reprise.
    var hasUnconfirmed: Bool { lanes.values.contains { $0.contains { if case .uncertain = $0.state { true } else { false } } } }

    /// Séances déjà commencées, la plus récente en dernier.
    func startedOccurrences(now: Date = Date()) -> [SchoolCourseOccurrence] {
        (sheet?.series.occurrences ?? []).filter { ($0.start ?? .distantFuture) <= now }.sorted { $0.position < $1.position }
    }
    var occurrence: SchoolCourseOccurrence? {
        guard let occurrenceID else { return nil }
        return sheet?.series.occurrences.first { $0.id == occurrenceID }
    }

    func load() async {
        guard !isLoading else { reloadRequested = true; return }
        isLoading = true; defer { isLoading = false }
        repeat {
            reloadRequested = false
            let since = stamp
            do {
                let fresh = try await client.sheet(schoolID: schoolID, seriesID: seriesID)
                apply(fresh, keepingRowsNewerThan: since)
                errorMessage = nil
            } catch is CancellationError { return
            } catch { errorMessage = SchoolCourseLearnerWorkspace.message(error) }
        } while reloadRequested
    }

    // MARK: Projection

    func intents(for enrollmentID: UUID) -> [SchoolCourseSheetIntent] { lanes[enrollmentID] ?? [] }

    /// Présence affichée : la dernière demande en cours prime sur l’état enregistré.
    func displayedStatus(_ row: SchoolCourseSheetRow, occurrenceID: UUID) -> SchoolCourseAttendanceStatus? {
        intents(for: row.enrollmentId).last { $0.occurrenceID == occurrenceID }?.attendanceStatus
            ?? row.mark(occurrenceID)?.status
    }
    func isPending(_ row: SchoolCourseSheetRow, occurrenceID: UUID) -> Bool {
        intents(for: row.enrollmentId).contains { $0.occurrenceID == occurrenceID }
    }
    /// Règlements saisis, pas encore confirmés : jamais comptés dans le montant payé.
    func pendingPayments(_ row: SchoolCourseSheetRow) -> [SchoolCourseSheetIntent] {
        intents(for: row.enrollmentId).filter { if case .payment = $0.action { true } else { false } }
    }
    func isVoiding(_ paymentID: UUID, in row: SchoolCourseSheetRow) -> Bool {
        intents(for: row.enrollmentId).contains { if case .voidPayment(_, paymentID, _) = $0.action { true } else { false } }
    }
    func isValidating(_ row: SchoolCourseSheetRow) -> Bool {
        intents(for: row.enrollmentId).contains { if case .validate = $0.action { true } else { false } }
    }
    func isRevoking(_ row: SchoolCourseSheetRow) -> Bool {
        intents(for: row.enrollmentId).contains { if case .revokeCompletion = $0.action { true } else { false } }
    }
    /// Première demande de la ligne à reprendre, avec sa raison.
    func unconfirmed(_ row: SchoolCourseSheetRow) -> (intent: SchoolCourseSheetIntent, message: String)? {
        guard let head = lanes[row.enrollmentId]?.first, case .uncertain(let message) = head.state else { return nil }
        return (head, message)
    }
    func isSending(_ row: SchoolCourseSheetRow) -> Bool {
        intents(for: row.enrollmentId).contains { $0.state == .queued || $0.state == .sending }
    }

    /// Validation possible sur les seules présences confirmées, sans demande en cours pour cet élève.
    func canValidate(_ row: SchoolCourseSheetRow) -> Bool {
        rights?.canValidate == true && row.completion == nil && row.requirements.required > 0
            && row.requirements.missing == 0 && intents(for: row.enrollmentId).isEmpty
    }

    // MARK: Commandes

    /// Retour immédiat : la demande rejoint la file de l’élève et part dès que la précédente a répondu.
    /// Deux présences successives pour la même séance, la seconde pas encore partie, ne font qu’une demande.
    func submit(_ action: SchoolCourseSheetAction, learnerName: String) {
        let enrollmentID = action.enrollmentID
        notices[enrollmentID] = nil
        var lane = lanes[enrollmentID] ?? []
        if case .attendance(_, let occurrence, let status, _) = action,
           let index = lane.lastIndex(where: { $0.occurrenceID == occurrence }), !lane[index].sent, lane[index].state == .queued {
            let confirmed = sheet?.rows.first { $0.enrollmentId == enrollmentID }?.mark(occurrence)?.status
            let earlier = lane[..<index].last { $0.occurrenceID == occurrence }?.attendanceStatus ?? confirmed
            if earlier == status { lane.remove(at: index) } else { lane[index].action = action }
        } else {
            lane.append(SchoolCourseSheetIntent(id: UUID(), action: action, learnerName: learnerName))
        }
        lanes[enrollmentID] = lane.isEmpty ? nil : lane
        drain(enrollmentID)
    }

    /// Même demande, même opération : l’école ne l’enregistre pas deux fois.
    func retry(_ enrollmentID: UUID) {
        guard var lane = lanes[enrollmentID], let head = lane.first, case .uncertain = head.state else { return }
        lane[0].state = .queued
        lanes[enrollmentID] = lane
        drain(enrollmentID)
    }

    /// Abandonne la demande à reprendre ; elle a pu être enregistrée, la feuille est donc relue.
    func abandon(_ enrollmentID: UUID) {
        guard var lane = lanes[enrollmentID], let head = lane.first, case .uncertain = head.state else { return }
        lane.removeFirst()
        lanes[enrollmentID] = lane.isEmpty ? nil : lane
        Task {
            await load()
            drain(enrollmentID)
        }
    }

    func clearNotice(_ enrollmentID: UUID) { notices[enrollmentID] = nil }

    private func drain(_ enrollmentID: UUID) {
        guard !running.contains(enrollmentID), lanes[enrollmentID]?.first?.state == .queued else { return }
        running.insert(enrollmentID)
        Task { await run(enrollmentID) }
    }

    private func run(_ enrollmentID: UUID) async {
        defer { running.remove(enrollmentID) }
        var changed = false
        while let head = lanes[enrollmentID]?.first, head.state == .queued {
            var intent = head
            if !intent.sent {
                guard let prepared = prepared(intent.action) else {
                    // Déjà dans l’état voulu (autre opérateur, retour en arrière) : rien à envoyer.
                    remove(intent.id, from: enrollmentID)
                    continue
                }
                intent.action = prepared
                intent.sent = true
            }
            intent.state = .sending
            update(intent, in: enrollmentID)
            do {
                let fresh = try await execute(intent.action, operation: intent.id)
                remove(intent.id, from: enrollmentID)
                applyRow(enrollmentID, from: fresh)
                announcement = SchoolCourseAnnouncement(text: confirmation(intent))
                changed = true
            } catch is CancellationError {
                intent.state = .uncertain(SchoolPlanningFailure.unavailable.localizedDescription)
                update(intent, in: enrollmentID)
                return
            } catch {
                let message = SchoolCourseLearnerWorkspace.message(error)
                if let failure = error as? SchoolPlanningFailure,
                   failure.definitiveRejection || failure == .forbidden || failure == .notFound {
                    // Refus de l’école : la demande s’arrête, la ligne dit pourquoi, la feuille est relue.
                    remove(intent.id, from: enrollmentID)
                    notices[enrollmentID] = refusal(intent, message)
                    announcement = SchoolCourseAnnouncement(text: notices[enrollmentID] ?? message)
                    await load()
                } else {
                    intent.state = .uncertain(message)
                    update(intent, in: enrollmentID)
                    announcement = SchoolCourseAnnouncement(text: "\(intent.learnerName) : non confirmé")
                    return
                }
            }
        }
        if changed { await onChange?() }
    }

    /// Fige la version attendue au premier envoi ; `nil` quand la présence est déjà celle demandée.
    private func prepared(_ action: SchoolCourseSheetAction) -> SchoolCourseSheetAction? {
        guard case .attendance(let enrollmentID, let occurrence, let status, _) = action else { return action }
        let mark = sheet?.rows.first { $0.enrollmentId == enrollmentID }?.mark(occurrence)
        if mark?.status == status { return nil }
        return .attendance(enrollmentID: enrollmentID, occurrenceID: occurrence, status: status, expectedVersion: mark?.version)
    }

    private func execute(_ action: SchoolCourseSheetAction, operation: UUID) async throws -> SchoolCourseSheet {
        switch action {
        case .attendance(let e, let o, let status, let version):
            try await client.recordAttendance(schoolID: schoolID, seriesID: seriesID, enrollmentID: e, occurrenceID: o,
                body: SchoolCourseAttendanceBody(operationId: operation, status: status, expectedVersion: version, note: nil))
        case .payment(let e, let cents):
            try await client.recordPayment(schoolID: schoolID, seriesID: seriesID, enrollmentID: e,
                body: SchoolCoursePaymentBody(operationId: operation, amountCents: cents, note: nil))
        case .validate(let e):
            try await client.validate(schoolID: schoolID, seriesID: seriesID, enrollmentID: e,
                body: SchoolCourseValidateBody(operationId: operation, note: nil))
        case .voidPayment(_, let p, let reason):
            try await client.voidPayment(schoolID: schoolID, seriesID: seriesID, paymentID: p, reason: reason, operationID: operation)
        case .revokeCompletion(_, let c, let reason):
            try await client.revokeCompletion(schoolID: schoolID, seriesID: seriesID, completionID: c, reason: reason, operationID: operation)
        }
    }

    private func confirmation(_ intent: SchoolCourseSheetIntent) -> String {
        switch intent.action {
        case .attendance(_, _, let status, _): "\(intent.learnerName) : \(SchoolCourseSheetFormat.title(status))"
        case .payment(_, let cents): "Règlement de \(SchoolCatalogFormatting.price(cents)) enregistré"
        case .validate: "Cours validé pour \(intent.learnerName)"
        case .voidPayment: "Règlement annulé pour \(intent.learnerName)"
        case .revokeCompletion: "Validation retirée pour \(intent.learnerName)"
        }
    }

    private func refusal(_ intent: SchoolCourseSheetIntent, _ message: String) -> String {
        switch intent.action {
        case .attendance(_, _, let status, _): "\(SchoolCourseSheetFormat.title(status)) non enregistré : \(message)"
        case .payment(_, let cents): "Règlement de \(SchoolCatalogFormatting.price(cents)) non enregistré : \(message)"
        case .validate: "Validation refusée : \(message)"
        case .voidPayment: "Annulation du règlement refusée : \(message)"
        case .revokeCompletion: "Retrait de la validation refusé : \(message)"
        }
    }

    private func update(_ intent: SchoolCourseSheetIntent, in enrollmentID: UUID) {
        guard let index = lanes[enrollmentID]?.firstIndex(where: { $0.id == intent.id }) else { return }
        lanes[enrollmentID]?[index] = intent
    }

    private func remove(_ intentID: UUID, from enrollmentID: UUID) {
        lanes[enrollmentID]?.removeAll { $0.id == intentID }
        if lanes[enrollmentID]?.isEmpty == true { lanes[enrollmentID] = nil }
    }

    /// Seule la ligne de l’élève concerné est remplacée : une feuille lue avant l’écriture d’un autre élève
    /// ne fait pas revenir sa ligne en arrière.
    private func applyRow(_ enrollmentID: UUID, from fresh: SchoolCourseSheet) {
        stamp += 1
        rowStamps[enrollmentID] = stamp
        guard let current = sheet else { return apply(fresh, keepingRowsNewerThan: stamp) }
        let incoming = fresh.rows.first { $0.enrollmentId == enrollmentID }
        var rows = current.rows.compactMap { $0.enrollmentId == enrollmentID ? incoming : $0 }
        if let incoming, !current.rows.contains(where: { $0.enrollmentId == enrollmentID }) { rows.append(incoming) }
        sheet = SchoolCourseSheet(series: current.series, rights: fresh.rights, rows: rows)
    }

    private func apply(_ fresh: SchoolCourseSheet, keepingRowsNewerThan since: Int) {
        var rows = fresh.rows
        if let current = sheet {
            for (enrollmentID, rowStamp) in rowStamps where rowStamp > since {
                guard let kept = current.rows.first(where: { $0.enrollmentId == enrollmentID }) else { continue }
                if let index = rows.firstIndex(where: { $0.enrollmentId == enrollmentID }) { rows[index] = kept } else { rows.append(kept) }
            }
        }
        sheet = SchoolCourseSheet(series: fresh.series, rights: fresh.rights, rows: rows)
        if occurrenceID == nil || !fresh.series.occurrences.contains(where: { $0.id == occurrenceID }) {
            occurrenceID = startedOccurrences().last?.id
        }
    }
}
