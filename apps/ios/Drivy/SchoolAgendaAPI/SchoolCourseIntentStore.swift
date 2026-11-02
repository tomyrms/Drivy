import Foundation

// Gestes de cours conservés sur l'appareil (#126, #128, #129, #130). Un geste est écrit dans un coffre chiffré avant son envoi et n'en
// sort qu'à la réponse de l'école : si l'app est arrêtée entre-temps, il revient « non confirmé » avec Réessayer (même opération :
// l'école ne l'enregistre pas deux fois) et Abandonner. Ce coffre est distinct de celui des commandes de l'école : marquer une
// présence n'attend ni ne bloque aucune autre écriture. Rien n'est jamais renvoyé sans le geste de la personne.

@MainActor
protocol SchoolCourseIntentStoring: AnyObject {
    /// Gestes conservés d'un cours pour ce compte et cette adhésion, le plus ancien d'abord.
    func commands(scope: SchoolCommandScope, seriesID: UUID) throws -> [PendingSchoolCommand]
    /// Tous les gestes de cours de ce compte et de cette école, pour dire dans les listes ce qui attend.
    func commands(scope: SchoolCommandScope) throws -> [PendingSchoolCommand]
    /// Écrit `new` ; retire d'abord `old` quand le geste change avant son envoi.
    func replace(_ old: PendingSchoolCommand?, with new: PendingSchoolCommand) throws
    func remove(_ command: PendingSchoolCommand) throws
}

/// Coffre et portée d'un compte dans une école, transmis aux espaces de cours.
struct SchoolCourseIntentPersistence {
    let store: any SchoolCourseIntentStoring
    let scope: SchoolCommandScope

    init(store: any SchoolCourseIntentStoring, scope: SchoolCommandScope) { self.store = store; self.scope = scope }

    /// Coffre de l'appareil pour ce compte et cette adhésion.
    @MainActor init(scope: SchoolCommandScope) { self.init(store: SchoolCourseIntentStores.shared, scope: scope) }
}

/// Un seul coffre par appareil ; les écrans de contrôle y mettent un coffre en mémoire.
@MainActor enum SchoolCourseIntentStores {
    static var shared: any SchoolCourseIntentStoring = EncryptedSchoolCourseIntentStore()
}

@MainActor
final class EncryptedSchoolCourseIntentStore: SchoolCourseIntentStoring {
    private let outbox: EncryptedSchoolCommandOutbox

    init(directory: URL? = nil, keyData: Data? = nil, vault: (any IdentityVault)? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SchoolCourseIntents", isDirectory: true)
        outbox = EncryptedSchoolCommandOutbox(directory: base, keyData: keyData, vault: vault)
    }

    func commands(scope: SchoolCommandScope) throws -> [PendingSchoolCommand] {
        var kept: [PendingSchoolCommand] = []
        for command in try outbox.pendingCommands(for: scope) where command.kind.isCourse && command.scope.sharesMembership(with: scope) {
            if command.scope == scope { kept.append(command); continue }
            // Même compte, même école, même adhésion : seule l'époque d'accès a avancé (une affectation de plus, par exemple).
            // L'école relit les droits au rejeu ; le geste suit la portée actuelle plutôt que de rester bloqué.
            let moved = PendingSchoolCommand(id: command.id, scope: scope, kind: command.kind, resourceVersion: command.resourceVersion,
                createdAt: command.createdAt, body: command.body, resourceID: command.resourceID, routeResourceID: command.routeResourceID)
            try outbox.remove(command)
            try outbox.save(moved)
            kept.append(moved)
        }
        return kept.sorted { $0.createdAt < $1.createdAt }
    }

    func commands(scope: SchoolCommandScope, seriesID: UUID) throws -> [PendingSchoolCommand] {
        try commands(scope: scope).filter { $0.routeResourceID == seriesID }
    }

    func replace(_ old: PendingSchoolCommand?, with new: PendingSchoolCommand) throws {
        if let old { try outbox.remove(old) }
        try outbox.save(new)
    }

    func remove(_ command: PendingSchoolCommand) throws { try outbox.remove(command) }
}

/// Coffre en mémoire : tests et écrans de contrôle, qui n'écrivent aucun fichier.
@MainActor
final class SchoolCourseIntentMemoryStore: SchoolCourseIntentStoring {
    private(set) var stored: [PendingSchoolCommand] = []
    /// Simule un appareil qui ne peut rien conserver.
    var refusesToStore = false

    func commands(scope: SchoolCommandScope) throws -> [PendingSchoolCommand] {
        stored.filter { $0.kind.isCourse && $0.scope.sharesMembership(with: scope) }.sorted { $0.createdAt < $1.createdAt }
    }

    func commands(scope: SchoolCommandScope, seriesID: UUID) throws -> [PendingSchoolCommand] {
        try commands(scope: scope).filter { $0.routeResourceID == seriesID }
    }

    func replace(_ old: PendingSchoolCommand?, with new: PendingSchoolCommand) throws {
        guard !refusesToStore else { throw SchoolConfigurationFailure.storage }
        if let old { stored.removeAll { $0.id == old.id } }
        stored.removeAll { $0.id == new.id }
        stored.append(new)
    }

    func remove(_ command: PendingSchoolCommand) throws { stored.removeAll { $0.id == command.id } }
}

// MARK: Feuille d'un cours : appel, règlements, validation

/// Geste de la feuille d'un cours tel qu'il est conservé. `sent` dit si la version attendue a déjà été figée pour l'envoi.
struct SchoolCourseSheetRecord: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case attendance, payment, validate, voidPayment, revokeCompletion }

    let operationId: UUID
    let kind: Kind
    let enrollmentId: UUID
    let learnerName: String
    let sent: Bool
    var occurrenceId: UUID? = nil
    var status: SchoolCourseAttendanceStatus? = nil
    var expectedVersion: Int? = nil
    var amountCents: Int64? = nil
    /// Règlement ou validation visé par une annulation.
    var targetId: UUID? = nil
    var reason: String? = nil

    init(_ intent: SchoolCourseSheetIntent) {
        operationId = intent.id; learnerName = intent.learnerName; sent = intent.sent
        switch intent.action {
        case .attendance(let enrollment, let occurrence, let mark, let version):
            kind = .attendance; enrollmentId = enrollment; occurrenceId = occurrence; status = mark; expectedVersion = version
        case .payment(let enrollment, let cents):
            kind = .payment; enrollmentId = enrollment; amountCents = cents
        case .validate(let enrollment):
            kind = .validate; enrollmentId = enrollment
        case .voidPayment(let enrollment, let payment, let why):
            kind = .voidPayment; enrollmentId = enrollment; targetId = payment; reason = why
        case .revokeCompletion(let enrollment, let completion, let why):
            kind = .revokeCompletion; enrollmentId = enrollment; targetId = completion; reason = why
        }
    }

    /// `nil` quand l'archive ne dit pas tout ce que le geste exige : il est alors écarté, jamais deviné.
    var action: SchoolCourseSheetAction? {
        switch kind {
        case .attendance:
            guard let occurrenceId, let status else { return nil }
            return .attendance(enrollmentID: enrollmentId, occurrenceID: occurrenceId, status: status, expectedVersion: expectedVersion)
        case .payment:
            guard let amountCents, amountCents > 0 else { return nil }
            return .payment(enrollmentID: enrollmentId, amountCents: amountCents)
        case .validate:
            return .validate(enrollmentID: enrollmentId)
        case .voidPayment:
            guard let targetId, let reason else { return nil }
            return .voidPayment(enrollmentID: enrollmentId, paymentID: targetId, reason: reason)
        case .revokeCompletion:
            guard let targetId, let reason else { return nil }
            return .revokeCompletion(enrollmentID: enrollmentId, completionID: targetId, reason: reason)
        }
    }

    func command(scope: SchoolCommandScope, seriesID: UUID, createdAt: Date) throws -> PendingSchoolCommand {
        PendingSchoolCommand(id: operationId, scope: scope, kind: .courseSheetIntent, resourceVersion: 0, createdAt: createdAt,
            body: try JSONEncoder().encode(self), resourceID: enrollmentId, routeResourceID: seriesID)
    }
}

// MARK: Inscription de l'élève

/// Demande de l'élève sur un cours (#126) telle qu'elle est conservée.
struct SchoolCourseLearnerRecord: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case enroll, joinWaitlist, leaveWaitlist, accept, decline, cancel }

    let operationId: UUID
    let kind: Kind
    var offerId: UUID? = nil
    var enrollmentId: UUID? = nil
    var version: Int? = nil

    init(action: SchoolCourseLearnerAction, operation: UUID) {
        operationId = operation
        switch action {
        case .enroll: kind = .enroll
        case .joinWaitlist: kind = .joinWaitlist
        case .leaveWaitlist: kind = .leaveWaitlist
        case .accept(let offer): kind = .accept; offerId = offer
        case .decline(let offer): kind = .decline; offerId = offer
        case .cancel(let enrollment, let current): kind = .cancel; enrollmentId = enrollment; version = current
        }
    }

    var action: SchoolCourseLearnerAction? {
        switch kind {
        case .enroll: return .enroll
        case .joinWaitlist: return .joinWaitlist
        case .leaveWaitlist: return .leaveWaitlist
        case .accept:
            guard let offerId else { return nil }
            return .accept(offerID: offerId)
        case .decline:
            guard let offerId else { return nil }
            return .decline(offerID: offerId)
        case .cancel:
            guard let enrollmentId, let version, version > 0 else { return nil }
            return .cancel(enrollmentID: enrollmentId, version: version)
        }
    }

    func command(scope: SchoolCommandScope, seriesID: UUID, createdAt: Date) throws -> PendingSchoolCommand {
        PendingSchoolCommand(id: operationId, scope: scope, kind: .courseLearnerIntent, resourceVersion: 0, createdAt: createdAt,
            body: try JSONEncoder().encode(self), resourceID: seriesID, routeResourceID: seriesID)
    }
}

extension SchoolCourseIntentPersistence {
    static let restoredMessage = "Geste conservé sur cet appareil, pas encore confirmé par l’école."
    static let unkeptMessage = "Cet appareil ne peut pas conserver ce geste : il n’a pas été envoyé."
}
