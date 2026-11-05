import Foundation
import Observation

/// Où en est la preuve locale d'un envoi de planification (#106 L2).
enum SchoolCommandSendPhase: Sendable, Equatable {
    /// Le geste vient d'être conservé : aucune remise au transport n'a eu lieu.
    case waiting
    /// La mutation a été remise au transport : elle n'est plus annulable localement.
    case handedToTransport
    /// Le retrait de la commande a réussi : aucun transport ne peut plus reprendre ce geste.
    case cancelledBeforeSend
    /// Le retrait du coffre a échoué : l'émission reste fermée, le retrait peut être retenté.
    case cancellationStorageFailed
}

/// Verdict rendu par le geste « Annuler l'envoi ».
enum SchoolCommandCancellationResult: Sendable, Equatable {
    case cancelledBeforeSend, alreadyHandedToTransport, storageFailure
}

/// Refus local opposé à une émission qui n'appartient pas à cette admission.
enum SchoolCommandAdmissionFailure: Error, Sendable, Equatable {
    case cancelledBeforeSend, cancellationStorageFailed, wrongCommand
}

/// Preuve locale, vivante le temps d'un geste de planification : elle ne contient ni jeton, ni URL,
/// ni copie mutable du corps. Seules les commandes `createLesson` et `moveLesson` en reçoivent une.
/// Les trois transitions sont synchrones sur MainActor : aucun `await` ne sépare le verdict de l'état.
@MainActor @Observable
final class SchoolCommandSendAdmission {
    private(set) var phase: SchoolCommandSendPhase
    /// Identité complète de la commande d'origine : type, portée, octets, version et horodatage.
    private let command: PendingSchoolCommand

    init(command: PendingSchoolCommand) {
        self.command = command
        phase = .waiting
    }

    /// Vérifie que la commande est exactement celle admise, puis que l'émission reste ouverte.
    /// Aucune transition : un contrôle de préparation ne remet jamais la mutation au transport.
    func check(_ candidate: PendingSchoolCommand) throws {
        guard candidate == command else { throw SchoolCommandAdmissionFailure.wrongCommand }
        switch phase {
        case .waiting, .handedToTransport: return
        case .cancelledBeforeSend: throw SchoolCommandAdmissionFailure.cancelledBeforeSend
        case .cancellationStorageFailed: throw SchoolCommandAdmissionFailure.cancellationStorageFailed
        }
    }

    /// Dernière transition avant `transport.send`. Idempotente si la mutation est déjà remise :
    /// une répétition interne après 401 garde la même admission et ne redevient pas annulable.
    func handOff(_ candidate: PendingSchoolCommand) throws {
        try check(candidate)
        guard phase == .waiting else { return }
        phase = .handedToTransport
    }

    /// Ferme l'admission AVANT le retrait synchrone de la commande exacte. Le retrait qui échoue laisse
    /// l'émission fermée et peut être retenté ; il ne réécrit ni le corps, ni la version, ni l'horodatage.
    func cancel(removing: (PendingSchoolCommand) throws -> Void) -> SchoolCommandCancellationResult {
        switch phase {
        case .cancelledBeforeSend:
            return .cancelledBeforeSend
        case .handedToTransport:
            return .alreadyHandedToTransport
        case .waiting, .cancellationStorageFailed:
            phase = .cancelledBeforeSend
            do {
                try removing(command)
                return .cancelledBeforeSend
            } catch {
                phase = .cancellationStorageFailed
                return .storageFailure
            }
        }
    }
}
