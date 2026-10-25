import Foundation

/// #104 : intentions locales posées par-dessus l'état confirmé par le serveur.
/// L'affichage local immédiat n'est jamais un succès serveur : le statut le distingue.
enum MessagingMutationKind: Hashable, Sendable {
    case reaction(String)
    case pin
    case vote
    case hideForMe
    case deleteForEveryone
}

/// Une cible = une intention : la dernière volonté de l'utilisateur remplace la précédente.
struct MessagingMutationKey: Hashable, Sendable {
    let conversationID: UUID
    let messageID: UUID
    let kind: MessagingMutationKind
}

/// État souhaité transmis tel quel (jamais une bascule) : un renvoi est idempotent.
enum MessagingMutationValue: Hashable, Sendable {
    case active(Bool)
    case options(Set<String>)
}

enum MessagingMutationStatus: Equatable, Sendable {
    /// Requête en vol, pas encore de signe de lenteur.
    case sending
    /// Au-delà de `MessagingMutationLatency.slow` sans réponse.
    case slow
    /// Au-delà de `MessagingMutationLatency.unconfirmed` sans réponse.
    case unconfirmed
    /// Hors connexion connu : renvoi automatique à la reconnexion.
    case offline
    /// Réponse perdue ou délai dépassé : l'opération a pu être enregistrée.
    case uncertain
    /// Acceptée par le serveur ; l'intention reste jusqu'à ce qu'une relecture la reflète.
    case confirmed

    var needsAttention: Bool { self == .unconfirmed || self == .uncertain }
}

struct MessagingMutationLatency: Sendable {
    /// Seuils UX proposés (#104), à valider dans le rendu : ni preuve d'échec ni déclencheur de renvoi.
    var slow: Duration = .seconds(5)
    var unconfirmed: Duration = .seconds(10)
}

struct MessagingPendingMutation: Equatable, Sendable {
    /// Identifiant stable de l'intention, conservé lors des renvois.
    let id: UUID
    var desired: MessagingMutationValue
    var startedAt: Date
    var status: MessagingMutationStatus
    var acknowledged: MessagingMutationValue? = nil
    var acknowledgedAt: Date? = nil
    /// Renouvelé à chaque nouvelle volonté ou reprise : les minuteries précédentes deviennent inertes.
    var clock = UUID()
}

/// Refus explicite affiché sur la bulle concernée seulement.
struct MessagingMutationRejection: Equatable, Sendable {
    let kind: MessagingMutationKind
    let failure: MessagingFailure

    var summary: String {
        switch kind {
        case .reaction: "Réaction non enregistrée"
        case .pin: "Épingle non enregistrée"
        case .vote: "Vote non enregistré"
        case .hideForMe, .deleteForEveryone: "Suppression non effectuée"
        }
    }
}

enum MessagingMutationProjection {
    /// Applique les intentions du message, dans l'ordre de leur début, sans jamais compter deux fois « moi ».
    static func apply(_ mutations: [MessagingMutationKey: MessagingPendingMutation], to message: MessagingWireMessage,
                      account: UUID) -> MessagingWireMessage {
        let own = mutations.filter { $0.key.messageID == message.id && $0.key.conversationID == message.conversationID }
        guard !own.isEmpty else { return message }
        var result = message
        for (key, mutation) in own.sorted(by: { $0.value.startedAt < $1.value.startedAt }) {
            result.meta = apply(key.kind, mutation.desired, to: result.meta, account: account)
        }
        return result
    }

    static func apply(_ kind: MessagingMutationKind, _ value: MessagingMutationValue, to meta: MessagingMessageMeta,
                      account: UUID) -> MessagingMessageMeta {
        var meta = meta
        guard !meta.deletedForEveryone else { return meta }
        switch (kind, value) {
        case (.reaction(let emoji), .active(let active)):
            var reactions = meta.reactions
            if let index = reactions.firstIndex(where: { $0.emoji == emoji }) {
                let people = reactions[index].personIDs
                if active, !people.contains(account) {
                    reactions[index] = MessagingReaction(emoji: emoji, personIDs: people + [account])
                } else if !active, people.contains(account) {
                    let rest = people.filter { $0 != account }
                    if rest.isEmpty { reactions.remove(at: index) } else { reactions[index] = MessagingReaction(emoji: emoji, personIDs: rest) }
                }
            } else if active {
                reactions.append(MessagingReaction(emoji: emoji, personIDs: [account]))
            }
            meta.reactions = reactions
        case (.pin, .active(let pinned)):
            meta.pinned = pinned
        case (.vote, .options(let chosen)):
            if let poll = meta.poll {
                meta.poll = MessagingPollState(allowsMultiple: poll.allowsMultiple, closed: poll.closed, creatorID: poll.creatorID,
                    options: poll.options.map { (option: MessagingPollState.Option) -> MessagingPollState.Option in
                        let voted = option.voterIDs.contains(account)
                        if chosen.contains(option.optionID) {
                            return voted ? option : .init(optionID: option.optionID, voterIDs: option.voterIDs + [account])
                        }
                        return voted ? .init(optionID: option.optionID, voterIDs: option.voterIDs.filter { $0 != account }) : option
                    })
            }
        default:
            break
        }
        return meta
    }

    /// Vrai si l'état serveur reflète déjà l'état souhaité (ou si la cible n'existe plus).
    static func isSatisfied(_ kind: MessagingMutationKind, _ value: MessagingMutationValue, by meta: MessagingMessageMeta,
                            account: UUID) -> Bool {
        if meta.deletedForEveryone { return true }
        switch (kind, value) {
        case (.reaction(let emoji), .active(let active)):
            return (meta.reactions.first { $0.emoji == emoji }?.personIDs.contains(account) ?? false) == active
        case (.pin, .active(let pinned)):
            return meta.pinned == pinned
        case (.vote, .options(let chosen)):
            guard let poll = meta.poll else { return true }
            return Set(poll.options.filter { $0.voterIDs.contains(account) }.map(\.optionID)) == chosen
        default:
            return false
        }
    }
}
