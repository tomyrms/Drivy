import Foundation
import UserNotifications

/// Nettoyage des alertes et du badge après une lecture confirmée par le serveur (#103).
protocol MessagingNotificationCleaning: Sendable {
    /// Retire seulement les alertes livrées de cette école + conversation dont la séquence est couverte.
    func removeDelivered(schoolID: UUID, conversationID: UUID, upTo sequence: Int) async
    /// Part messagerie du badge ; les autres sources gardent la leur.
    func setMessagingBadge(_ count: Int) async
}

struct SystemMessagingNotifications: MessagingNotificationCleaning {
    func removeDelivered(schoolID: UUID, conversationID: UUID, upTo sequence: Int) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let ids = Self.identifiersToRemove(delivered.map { ($0.request.identifier, $0.request.content.userInfo) },
                                           schoolID: schoolID, conversationID: conversationID, upTo: sequence)
        if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
    }

    func setMessagingBadge(_ count: Int) async {
        let total = await DrivyBadge.shared.set(.messaging, count)
        try? await UNUserNotificationCenter.current().setBadgeCount(total)
    }

    /// Charge utile de apps/api/src/messaging-notifications.ts (`messagingPushPayload`).
    /// Sans `kind` MESSAGING, sans contexte identique ou sans séquence lisible : on ne touche à rien
    /// (cours collectifs, autres conversations, alertes plus récentes que la borne).
    static func identifiersToRemove(_ delivered: [(String, [AnyHashable: Any])], schoolID: UUID,
                                    conversationID: UUID, upTo sequence: Int) -> [String] {
        delivered.compactMap { id, info in
            guard info["kind"] as? String == "MESSAGING",
                  (info["schoolId"] as? String).flatMap(UUID.init(uuidString:)) == schoolID,
                  (info["conversationId"] as? String).flatMap(UUID.init(uuidString:)) == conversationID,
                  let seq = (info["sequence"] as? Int) ?? (info["sequence"] as? NSNumber)?.intValue,
                  seq >= 1, seq <= sequence else { return nil }
            return id
        }
    }
}

/// Alerte de messagerie touchée (#74) : l'école et la conversation de la charge `MESSAGING`, rien d'autre.
/// La charge ne transporte aucun contenu ; ouvrir la conversation relit les droits auprès de l'école.
struct MessagingNotificationTarget: Equatable, Sendable {
    let schoolID: UUID
    let conversationID: UUID
    let receivedAt: Date

    /// Délai pendant lequel un toucher peut encore attendre que l'app soit prête (démarrage à froid, connexion).
    static let validity: TimeInterval = 120

    /// `nil` hors d'une alerte `MESSAGING` complète : les alertes de cours gardent leur propre chemin.
    init?(userInfo: [AnyHashable: Any], receivedAt: Date = Date()) {
        guard userInfo["kind"] as? String == "MESSAGING",
              let school = (userInfo["schoolId"] as? String).flatMap(UUID.init(uuidString:)),
              let conversation = (userInfo["conversationId"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
        self.schoolID = school; self.conversationID = conversation; self.receivedAt = receivedAt
    }

    init(schoolID: UUID, conversationID: UUID, receivedAt: Date = Date()) {
        self.schoolID = schoolID; self.conversationID = conversationID; self.receivedAt = receivedAt
    }

    func isFresh(at now: Date) -> Bool { now.timeIntervalSince(receivedAt) <= Self.validity }
}

/// Ce que l'app fait d'un toucher sur une alerte de messagerie, avant toute lecture du serveur.
/// Le droit de voir la conversation n'est jamais décidé ici : l'onglet Messages ne l'ouvre que si l'école la liste.
enum MessagingNotificationOpening {
    enum Outcome: Equatable {
        /// Passer sur l'onglet Messages, qui relit la liste auprès de l'école avant d'ouvrir la conversation.
        case open
        /// Messages ou l'école courante ne sont pas encore prêts : la demande attend, dans la limite de sa validité.
        case wait
        /// Alerte d'une autre école que celle ouverte : refus expliqué, rien n'est ouvert.
        case otherSchool
        /// Trajet en cours, ou demande trop ancienne : rien ne s'ouvre et la demande est oubliée.
        case discard
    }

    static func outcome(for target: MessagingNotificationTarget, currentSchoolID: UUID?, messagesAvailable: Bool,
                        tripInProgress: Bool, now: Date = Date()) -> Outcome {
        guard target.isFresh(at: now), !tripInProgress else { return .discard }
        guard messagesAvailable, let currentSchoolID else { return .wait }
        return currentSchoolID == target.schoolID ? .open : .otherSchool
    }

    static let unavailableMessage = "Cette conversation n’est plus accessible."
    static let otherSchoolMessage = "Cette alerte concerne une autre école. Choisis cette école pour ouvrir la conversation."
}

/// Conversation affichée au premier plan, lue par le délégué de notifications (#103) :
/// pas de seconde bannière pour un message de cette conversation quand son bas est visible.
enum MessagingActiveConversation {
    /// `atBottom` : le bas du fil est affiché, l'app est active. `covered` : une feuille ou un écran le recouvre (#445).
    struct State: Equatable, Sendable {
        let schoolID: UUID; let conversationID: UUID; let atBottom: Bool
        var covered = false
    }
    /// Lecture autorisée de la séquence visée : vrai seulement si elle est disponible, visible et confirmée par le serveur.
    typealias Absorber = @Sendable (_ sequence: Int) async -> Bool
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: State?
    nonisolated(unsafe) private static var absorber: Absorber?

    static func set(schoolID: UUID, conversationID: UUID, atBottom: Bool, covered: Bool = false, absorb: Absorber? = nil) {
        lock.lock(); defer { lock.unlock() }
        current = State(schoolID: schoolID, conversationID: conversationID, atBottom: atBottom, covered: covered)
        absorber = absorb
    }
    static func clear(_ conversationID: UUID) {
        lock.lock(); defer { lock.unlock() }
        if current?.conversationID == conversationID { current = nil; absorber = nil }
    }
    /// Candidate à la suppression : alerte messagerie de la conversation active, bas du fil affiché, rien ne le recouvre.
    /// Ce n'est jamais une décision suffisante (#445) : voir `absorbs`.
    static func suppresses(_ info: [AnyHashable: Any]) -> Bool {
        lock.lock(); let state = current; lock.unlock()
        return suppresses(info, state: state)
    }
    static func suppresses(_ info: [AnyHashable: Any], state: State?) -> Bool {
        guard let state, state.atBottom, !state.covered, info["kind"] as? String == "MESSAGING",
              (info["schoolId"] as? String).flatMap(UUID.init(uuidString:)) == state.schoolID,
              (info["conversationId"] as? String).flatMap(UUID.init(uuidString:)) == state.conversationID else { return false }
        return true
    }

    /// Séquence portée par la charge (`messagingPushPayload`) ; absente ou invalide : l'alerte reste.
    static func sequence(in info: [AnyHashable: Any]) -> Int? {
        guard let value = (info["sequence"] as? Int) ?? (info["sequence"] as? NSNumber)?.intValue, value >= 1 else { return nil }
        return value
    }

    /// #445 : la bannière de premier plan n'est retirée qu'après une lecture autorisée de la séquence visée.
    /// Lecture échouée, séquence indisponible, feuille recouvrante ou fil quitté entre-temps : l'alerte est gardée.
    static func absorbs(_ info: [AnyHashable: Any]) async -> Bool {
        lock.lock(); let state = current; let absorb = absorber; lock.unlock()
        guard suppresses(info, state: state), let sequence = sequence(in: info), let absorb else { return false }
        guard await absorb(sequence) else { return false }
        // Le fil a pu être recouvert, défilé ou quitté pendant la lecture : mieux vaut une alerte de plus qu'une alerte perdue.
        lock.lock(); let after = current; lock.unlock()
        return after == state
    }
}

/// Badge d'app agrégé : chaque source publie sa part, le système reçoit la somme.
actor DrivyBadge {
    enum Source: Hashable, Sendable { case messaging, other(String) }
    static let shared = DrivyBadge()
    private var parts: [Source: Int] = [:]
    func set(_ source: Source, _ count: Int) -> Int {
        parts[source] = max(0, count)
        return parts.values.reduce(0, +)
    }
}
