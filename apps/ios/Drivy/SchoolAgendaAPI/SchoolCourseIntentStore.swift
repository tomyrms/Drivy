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
    /// Écrit `new` ; retire d'abord `old` quand le geste change avant son envoi. Un geste de l'élève qui partagerait
    /// la série ou l'obligation de formation d'un geste conservé est refusé (`SchoolConfigurationFailure.pendingCommand`,
    /// #106 tâche 5), et rien n'est retiré dans ce cas.
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
    /// Le coffre chiffré sous-jacent ; les tests y posent leurs pannes d'écriture.
    let outbox: EncryptedSchoolCommandOutbox

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
            // Un seul instantané chiffré (#438) : la migration d'époque garde l'ancien geste ou le nouveau, jamais aucun.
            try outbox.replace(command, with: moved)
            kept.append(moved)
        }
        return kept.sorted { $0.createdAt < $1.createdAt }
    }

    func commands(scope: SchoolCommandScope, seriesID: UUID) throws -> [PendingSchoolCommand] {
        try commands(scope: scope).filter { $0.routeResourceID == seriesID }
    }

    func replace(_ old: PendingSchoolCommand?, with new: PendingSchoolCommand) throws {
        // Le coffre applique la règle d'admission des gestes de l'élève : la même série attend, deux séries de gestes
        // d'agrégats disjoints entrent ensemble (#106, tâche 5). Admission et remplacement se font dans une seule
        // écriture atomique : rien n'est retiré si `new` est refusé ou n'a pas pu être écrit (#438).
        try outbox.replace(old, with: new, refusing: { SchoolCourseLearnerLane.blocks(new, $0) })
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
        // Même règle que le coffre chiffré : les deux implémentations ne peuvent pas diverger (#106, tâche 5).
        if try commands(scope: new.scope).contains(where: { $0.id != old?.id && SchoolCourseLearnerLane.blocks(new, $0) }) {
            throw SchoolConfigurationFailure.pendingCommand
        }
        // Même sémantique que le coffre chiffré : une substitution périmée (ni l'ancienne ni la nouvelle) est refusée ;
        // la nouvelle déjà présente à l'identique reste acceptée (idempotence après une faute après écriture).
        if let old, !stored.contains(where: { $0.id == old.id }), !stored.contains(new) { throw SchoolConfigurationFailure.storage }
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

// MARK: Agrégats d'un geste de l'élève (#106, tâche 5)

/// Règle d'admission des gestes de l'élève dans le coffre, tirée de `apps/api/src/course-enrollments.ts` et de
/// `apps/api/migrations/043_course_enrollment_waitlist_cancellation.sql`. Un geste n'entre que si aucun geste conservé
/// ne lit ou n'écrit le même agrégat.
///
/// - La **série** : chaque route la verrouille — `course_queue_advance` (`043:47`), `course_join_waitlist` (`:149`),
///   `course_leave_waitlist` (`:168`), `course_accept_offer` (`:183`), `course_decline_offer` (`:195`),
///   `course_cancel_enrollment` (`:212`) — et c'est elle qui porte les places (`course_seats_taken`), la file, les
///   propositions de place et la version d'inscription (`course-enrollments.ts:220-223`). Deux gestes sur la même série
///   se suivent, le second attendant la réponse du premier.
/// - L'**obligation de formation de l'élève** : `drivy.course_learner_admissible` (`043:21-32`) refuse une inscription
///   active dans une autre série publiée du **même type** de cours (et un cours du type déjà effectué). Elle est lue par
///   l'inscription (`043:122`), la file (`:157`) et l'acceptation d'une place (`:187`), et changée par la désinscription
///   (`:223`). Le type du cours n'est pas dans le coffre : deux gestes qui la lisent ou la changent restent donc
///   séquentiels, faute de preuve de disjonction.
/// - Le **retrait de la file** (`:174`) et le **refus d'une place** (`:197-199`) ne touchent que les lignes de leur
///   série et ne lisent ni ne changent cette obligation : ils partent avec les gestes des autres séries.
///
/// Les autres genres du coffre (feuille d'un cours, éditeur) restent hors de cette règle : ils ont leurs propres
/// agrégats et ne sont jamais retenus par un geste de l'élève.
enum SchoolCourseLearnerLane {
    /// Vrai quand le geste conservé `kept` doit passer avant `new`.
    static func blocks(_ new: PendingSchoolCommand, _ kept: PendingSchoolCommand) -> Bool {
        guard new.kind == .courseLearnerIntent, kept.kind == .courseLearnerIntent else { return false }
        // Même série : place, file d'attente et version d'inscription sont un seul agrégat.
        if let series = new.routeResourceID, series == kept.routeResourceID { return true }
        // Corps illisible : rien ne prouve la disjonction, la paire attend (comme une empreinte inconnue).
        guard let mine = intent(of: new), let theirs = intent(of: kept) else { return true }
        return mine.obligesTraining && theirs.obligesTraining
    }

    /// Genre du geste conservé, relu dans son corps ; `nil` quand l'archive ne dit pas tout (jamais deviné).
    static func intent(of command: PendingSchoolCommand) -> SchoolCourseLearnerRecord.Kind? {
        guard let record = try? JSONDecoder().decode(SchoolCourseLearnerRecord.self, from: command.body),
              record.operationId == command.id, record.action != nil else { return nil }
        return record.kind
    }
}

extension SchoolCourseLearnerRecord.Kind {
    /// Ce que la route lit ou change de l'obligation de formation de l'élève (`043:21-32`, `:122`, `:157`, `:187`, `:223`).
    var obligesTraining: Bool {
        switch self {
        case .enroll, .joinWaitlist, .accept, .cancel: true
        case .leaveWaitlist, .decline: false
        }
    }
}

// MARK: Éditeur de cours (#127)

/// Opération incertaine de l'éditeur (type, brouillon ou publication) avec la saisie qui l'accompagne : après un arrêt de l'app, la même
/// opération se rejoue sur la même saisie, et l'école ne l'enregistre pas deux fois. La saisie jamais envoyée n'est pas conservée.
struct SchoolCourseEditorRecord: Codable, Equatable, Sendable {
    enum Intent: String, Codable, Sendable { case type, draft, publication }

    let operationId: UUID
    let intent: Intent
    /// Vrai : la feuille se ferme à la réponse (« Enregistrer »), faux : elle reste ouverte (brouillon écrit avant une publication).
    let closing: Bool
    /// Identité de l'intention : la même clé désigne la même opération.
    let key: String
    /// `nil` : création d'un cours qui n'existe pas encore.
    let seriesId: UUID?
    let form: SchoolCourseForm
    let newTypeTitle: String
    let newTypeDescription: String
    /// Version de la série envoyée dans `If-Match` : brouillon d'un cours existant, ou brouillon publié (#431).
    /// `nil` pour une création, ou pour une archive d'avant #431 qui ne l'a pas conservée.
    var baseVersion: Int? = nil
    /// Corps canonique tel qu'il est parti (#431) : avec `baseVersion` et `operationId`, l'enveloppe exacte à rejouer.
    /// L'école rejoue la réponse d'une opération déjà appliquée seulement pour le même corps et la même version.
    var seriesBody: SchoolCourseSeriesBody? = nil

    /// Vrai quand le geste conserve de quoi repartir à l'identique. Une archive ancienne qui n'a pas gardé la version
    /// ou le corps d'une modification n'est jamais reconstruite avec la version courante : elle bloque le rejeu.
    var canReplayExactly: Bool {
        switch intent {
        case .type: true
        case .draft:
            seriesId == nil || (baseVersion.map { $0 > 0 } == true && seriesBody?.operationId == operationId)
        case .publication:
            seriesId != nil && baseVersion.map { $0 > 0 } == true
        }
    }

    func command(scope: SchoolCommandScope, createdAt: Date) throws -> PendingSchoolCommand {
        // Un cours en création n'a pas d'identifiant : l'adhésion de la personne désigne son brouillon.
        PendingSchoolCommand(id: operationId, scope: scope, kind: .courseEditorIntent, resourceVersion: 0, createdAt: createdAt,
            body: try JSONEncoder().encode(self), resourceID: seriesId ?? operationId, routeResourceID: seriesId ?? scope.membershipID)
    }
}

extension SchoolCourseIntentPersistence {
    static let restoredMessage = "Geste conservé sur cet appareil, pas encore confirmé par l’école."
    static let unkeptMessage = "Cet appareil ne peut pas conserver ce geste : il n’a pas été envoyé."
}
