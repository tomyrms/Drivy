import ImageIO
import Observation
import SwiftUI

/// Image décodée à taille de miniature. `UIImage` est immuable une fois créée : le conteneur
/// permet de la rendre du fil de décodage au MainActor sans la sérialiser.
struct MessagingDecodedThumbnail: @unchecked Sendable {
    let image: UIImage
}

/// Décodage hors du `body` et hors du MainActor : ImageIO produit un bitmap déjà décodé
/// (`ShouldCacheImmediately`), borné à l'axe maximal des miniatures du cache.
enum MessagingThumbnailDecoder {
    static func decode(_ data: Data) -> MessagingDecodedThumbnail? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: MessagingMediaPreparer.maximumThumbnailAxis
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return MessagingDecodedThumbnail(image: UIImage(cgImage: cgImage))
    }
}

/// Chargeur des miniatures du fil (#473), un par conversation ouverte.
///
/// - **État par pièce jointe** : une `Slot` observable par message ; une cellule ne se
///   redessine que pour sa propre pièce.
/// - **Déclenchement par l'apparition** : rien n'est demandé au montage de l'historique.
///   `appear` met la pièce en tête de file ; `prefetch` ajoute des voisines en queue de file.
/// - **Concurrence bornée** : au plus `maximumConcurrent` demandes en vol, file bornée, une
///   seule demande par pièce (déduplication).
/// - **Mémoire bornée** : au plus `memoryLimit` images décodées ; les pièces visibles ne sont
///   jamais évincées. Une pièce évincée revient depuis le cache protégé, sans téléchargement.
/// - **Résultat tardif ignoré** : un billet par demande et une génération globale ; une
///   suppression, un retrait d'accès, une invalidation ou un changement de contexte rendent
///   le résultat sans effet, et `isAuthorized` est relu à l'arrivée.
@MainActor @Observable
final class MessagingMediaThumbnailLoader {
    static let defaultMaximumConcurrent = 3
    static let defaultMemoryLimit = 24
    static let defaultQueueLimit = 12

    /// État visible d'une pièce jointe.
    enum Phase: Equatable, Sendable {
        /// Rien n'a été demandé (ou la pièce a été évincée de la mémoire).
        case idle
        /// En file d'attente ou en cours : l'espace réservé affiche l'attente.
        case loading
        case loaded
        /// Refus ou échec ; `retryable` indique si une reprise ciblée a un sens.
        case unavailable(retryable: Bool)
    }

    @MainActor @Observable
    final class Slot {
        fileprivate(set) var phase: Phase = .idle
        fileprivate(set) var image: UIImage?
    }

    typealias Decode = @Sendable (Data) -> MessagingDecodedThumbnail?

    /// Relue à l'arrivée de chaque résultat : le message est-il encore visible et autorisé ?
    var isAuthorized: @MainActor (_ messageID: UUID) -> Bool = { _ in true }

    let maximumConcurrent: Int
    let memoryLimit: Int
    let queueLimit: Int

    @ObservationIgnored private let provider: (any MessagingMediaThumbnailProviding)?
    @ObservationIgnored private let decode: Decode
    @ObservationIgnored private var slots: [UUID: Slot] = [:]
    @ObservationIgnored private var wires: [UUID: MessagingWireMessage] = [:]
    @ObservationIgnored private var visible: Set<UUID> = []
    /// File d'attente : tête = prochaine demande.
    @ObservationIgnored private var queue: [UUID] = []
    @ObservationIgnored private var tickets: [UUID: UUID] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Billets encore en vol, y compris ceux dont le résultat sera ignoré : la borne de
    /// concurrence compte le travail réel, pas seulement le travail utile.
    @ObservationIgnored private var inflight: Set<UUID> = []
    /// Ordre d'usage des images décodées, la plus ancienne en tête.
    @ObservationIgnored private var loadedOrder: [UUID] = []
    @ObservationIgnored private var generation = UUID()

    init(provider: (any MessagingMediaThumbnailProviding)?,
         maximumConcurrent: Int = defaultMaximumConcurrent,
         memoryLimit: Int = defaultMemoryLimit,
         queueLimit: Int = defaultQueueLimit,
         decode: @escaping Decode = { MessagingThumbnailDecoder.decode($0) }) {
        self.provider = provider
        self.maximumConcurrent = max(1, maximumConcurrent)
        self.memoryLimit = max(1, memoryLimit)
        self.queueLimit = max(1, queueLimit)
        self.decode = decode
    }

    /// Vrai si la composition fournit la capacité de miniature.
    var isSupported: Bool { provider != nil }

    /// Nombre de demandes réellement en vol (borné par `maximumConcurrent`).
    var inflightCount: Int { inflight.count }
    var queuedCount: Int { queue.count }
    var decodedCount: Int { loadedOrder.count }

    func slot(for messageID: UUID) -> Slot {
        if let slot = slots[messageID] { return slot }
        let slot = Slot()
        slots[messageID] = slot
        return slot
    }

    // MARK: Demandes

    /// La cellule apparaît : la pièce passe devant les voisines.
    func appear(_ message: MessagingWireMessage) {
        let id = message.id
        visible.insert(id)
        wires[id] = message
        let slot = slot(for: id)
        guard provider != nil else {
            if slot.phase == .idle { slot.phase = .unavailable(retryable: false) }
            return
        }
        switch slot.phase {
        case .loaded: touch(id)
        case .idle: enqueue(id, front: true)
        case .loading:
            // Déjà en file par prefetch : la pièce visible passe devant.
            if queue.contains(id) { queue.removeAll { $0 == id }; queue.insert(id, at: 0) }
        case .unavailable: break
        }
    }

    /// Voisine d'une cellule visible : file d'attente seulement, jamais devant une pièce visible.
    func prefetch(_ message: MessagingWireMessage) {
        let id = message.id
        guard provider != nil else { return }
        let slot = slot(for: id)
        guard slot.phase == .idle else { return }
        wires[id] = message
        enqueue(id, front: false)
    }

    /// La cellule disparaît : une demande encore en file est retirée ; une demande en vol
    /// va à son terme (le résultat remplit le cache protégé et la mémoire bornée).
    func disappear(_ messageID: UUID) {
        visible.remove(messageID)
        if queue.contains(messageID) {
            queue.removeAll { $0 == messageID }
            slots[messageID]?.phase = .idle
        }
        if slots[messageID]?.phase != .loading { wires[messageID] = nil }
    }

    /// Reprise ciblée d'une pièce indisponible, sur geste explicite.
    func retry(_ messageID: UUID) {
        guard provider != nil, let slot = slots[messageID],
              slot.phase == .unavailable(retryable: true), wires[messageID] != nil else { return }
        slot.phase = .idle
        enqueue(messageID, front: true)
    }

    // MARK: Invalidation

    /// Retire les pièces qui ne sont plus des médias visibles du fil (suppression, retrait
    /// d'accès, révocation) : tâche annulée, image libérée, résultat tardif sans effet.
    func discard(keeping messageIDs: Set<UUID>) {
        for id in Array(slots.keys) where !messageIDs.contains(id) { discard(id) }
    }

    func discard(_ messageID: UUID) {
        queue.removeAll { $0 == messageID }
        tickets[messageID] = nil
        tasks[messageID]?.cancel()
        tasks[messageID] = nil
        loadedOrder.removeAll { $0 == messageID }
        visible.remove(messageID)
        wires[messageID] = nil
        if let slot = slots.removeValue(forKey: messageID) {
            slot.phase = .idle
            slot.image = nil
        }
    }

    /// Changement de contexte, retrait d'accès ou invalidation du runtime : tout est
    /// annulé, toutes les images sont libérées, aucun résultat en vol n'est appliqué.
    func suspend() {
        generation = UUID()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        tickets.removeAll()
        queue.removeAll()
        loadedOrder.removeAll()
        // Une cellule encore à l'écran ne reste jamais sur une attente sans fin : elle passe à
        // « indisponible » avec reprise ciblée (la demande repart sur geste, avec le contexte courant).
        for (id, slot) in slots {
            slot.image = nil
            if visible.contains(id), wires[id] != nil {
                slot.phase = .unavailable(retryable: true)
            } else {
                slot.phase = .idle
                wires[id] = nil
                visible.remove(id)
            }
        }
        wires = wires.filter { visible.contains($0.key) }
    }

    // MARK: File et exécution

    private func enqueue(_ id: UUID, front: Bool) {
        let slot = slot(for: id)
        guard slot.phase == .idle else { return }
        slot.phase = .loading
        if front { queue.insert(id, at: 0) } else { queue.append(id) }
        trimQueue()
        pump()
    }

    /// La file reste bornée : on retire d'abord les voisines (fin de file) qui ne sont pas visibles.
    private func trimQueue() {
        while queue.count > queueLimit,
              let index = queue.lastIndex(where: { !visible.contains($0) }) {
            let dropped = queue.remove(at: index)
            slots[dropped]?.phase = .idle
            wires[dropped] = nil
        }
    }

    private func pump() {
        guard let provider else { return }
        while inflight.count < maximumConcurrent, !queue.isEmpty {
            let id = queue.removeFirst()
            guard let wire = wires[id], let slot = slots[id] else { continue }
            guard isAuthorized(id) else {
                // Retiré, supprimé ou révoqué : jamais redemandé ; si la cellule est encore là,
                // l'état est explicite plutôt qu'une attente.
                slot.phase = visible.contains(id) ? .unavailable(retryable: false) : .idle
                continue
            }
            start(id, wire: wire, provider: provider)
        }
    }

    private func start(_ id: UUID, wire: MessagingWireMessage,
                       provider: any MessagingMediaThumbnailProviding) {
        let ticket = UUID()
        let epoch = generation
        let decode = self.decode
        tickets[id] = ticket
        inflight.insert(ticket)
        tasks[id] = Task { [weak self] in
            let outcome: Outcome
            do {
                let data = try await provider.thumbnail(for: wire)
                try Task.checkCancellation()
                let decoded = await Task.detached(priority: .utility) { decode(data) }.value
                try Task.checkCancellation()
                outcome = decoded.map { .image($0) } ?? .failed(retryable: false)
            } catch is CancellationError {
                outcome = .cancelled
            } catch let failure as MessagingMediaRuntimeFailure {
                outcome = .failed(retryable: Self.isRetryable(failure))
            } catch {
                outcome = .failed(retryable: true)
            }
            self?.finish(id, ticket: ticket, epoch: epoch, outcome: outcome)
        }
    }

    private enum Outcome: Sendable {
        case image(MessagingDecodedThumbnail)
        case failed(retryable: Bool)
        case cancelled
    }

    private func finish(_ id: UUID, ticket: UUID, epoch: UUID, outcome: Outcome) {
        // Le travail réel est terminé : la place de concurrence est rendue dans tous les cas.
        guard inflight.remove(ticket) != nil else { return }
        defer { pump() }
        // Résultat tardif : supprimé, évincé, invalidé ou remplacé depuis la demande.
        guard epoch == generation, tickets[id] == ticket else { return }
        tickets[id] = nil
        tasks[id] = nil
        guard let slot = slots[id] else { return }
        switch outcome {
        case .cancelled:
            // Annulation extérieure alors que la cellule est toujours là : on redemande.
            slot.phase = .idle
            if visible.contains(id), wires[id] != nil { enqueue(id, front: true) }
            return
        case .failed(let retryable):
            slot.phase = .unavailable(retryable: retryable)
        case .image(let decoded):
            guard isAuthorized(id) else {
                slot.image = nil
                slot.phase = visible.contains(id) ? .unavailable(retryable: false) : .idle
                wires[id] = nil
                return
            }
            slot.image = decoded.image
            slot.phase = .loaded
            loadedOrder.removeAll { $0 == id }
            loadedOrder.append(id)
            evictIfNeeded()
        }
        if !visible.contains(id), slot.phase != .unavailable(retryable: true) { wires[id] = nil }
    }

    private func touch(_ id: UUID) {
        guard loadedOrder.contains(id) else { return }
        loadedOrder.removeAll { $0 == id }
        loadedOrder.append(id)
    }

    /// Évince les plus anciennes images non visibles ; une pièce visible n'est jamais retirée.
    private func evictIfNeeded() {
        while loadedOrder.count > memoryLimit,
              let evictable = loadedOrder.first(where: { !visible.contains($0) }) {
            loadedOrder.removeAll { $0 == evictable }
            if let slot = slots[evictable] {
                slot.image = nil
                slot.phase = .idle
            }
            wires[evictable] = nil
        }
    }

    /// Reprise utile seulement si l'échec peut être transitoire.
    static func isRetryable(_ failure: MessagingMediaRuntimeFailure) -> Bool {
        switch failure {
        case .unavailable, .unreadable, .protectionUnavailable, .resultUnknown: true
        default: false
        }
    }
}
