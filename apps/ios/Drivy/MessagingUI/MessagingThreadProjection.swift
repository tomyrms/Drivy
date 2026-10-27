import Foundation

/// Ligne du fil, indépendante du moteur d'affichage (#182). L'identité d'affichage reste celle de l'envoi local
/// après l'accusé : la bulle en attente devient le message confirmé sans disparaître ni sauter.
struct MessagingThreadItem: Identifiable, Sendable {
    enum Source: Sendable {
        case message(MessagingWireMessage)
        case pending(MessagingPending)
    }

    let id: String
    let source: Source
    let senderID: UUID
    /// Date d'acceptation serveur ; pour un envoi en attente, moment de sa rédaction.
    let date: Date

    var message: MessagingWireMessage? {
        if case .message(let message) = source { return message }
        return nil
    }

    var pending: MessagingPending? {
        if case .pending(let entry) = source { return entry }
        return nil
    }
}

enum MessagingThreadProjection {
    /// Ordre ascendant : messages serveur dans l'ordre reçu, puis envois en attente dans l'ordre de la file.
    /// Les identités sont uniques : un doublon (accusé et relecture simultanés) garde la version serveur.
    /// - Parameters:
    ///   - clientIDs: message serveur → envoi local qui l'a produit, connu après l'accusé.
    ///   - pendingDates: première présentation de chaque envoi en attente, pour un placement stable.
    static func items(messages: [MessagingWireMessage], pending: [MessagingPending], accountID: UUID,
                      clientIDs: [UUID: UUID], pendingDates: [UUID: Date], now: Date) -> [MessagingThreadItem] {
        var seen: Set<String> = []
        var result: [MessagingThreadItem] = []
        result.reserveCapacity(messages.count + pending.count)
        for message in messages {
            let id = (clientIDs[message.id] ?? message.id).uuidString
            guard seen.insert(id).inserted else { continue }
            result.append(MessagingThreadItem(id: id, source: .message(message), senderID: message.senderID,
                                              date: message.acceptedAt))
        }
        // Un envoi en attente reste sous le dernier message reçu, même mis en file avant lui hors connexion.
        let floor = messages.last?.acceptedAt ?? .distantPast
        for entry in pending {
            let id = entry.clientMessageID.uuidString
            guard seen.insert(id).inserted else { continue }
            result.append(MessagingThreadItem(id: id, source: .pending(entry), senderID: accountID,
                                              date: max(pendingDates[entry.clientMessageID] ?? now, floor)))
        }
        return result
    }

    /// Accusés connus de la session : identifiant serveur → identifiant local.
    static func clientIDs(_ states: [UUID: MessagingWorkspace.SendStatus]) -> [UUID: UUID] {
        var map: [UUID: UUID] = [:]
        for (client, status) in states {
            if case .accepted(let server) = status { map[server] = client }
        }
        return map
    }
}
