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
