import Foundation

/// L'état de transmission est distinct de la projection affichée et de l'autorisation métier.
enum ClientMutationState: Equatable, Sendable {
    case idle, queued, sending, unconfirmed, conflict, rejected, storageUnavailable
}
