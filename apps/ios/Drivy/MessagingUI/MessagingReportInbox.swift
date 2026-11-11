import Foundation
import Observation

/// Ce qu'un administrateur peut savoir d'une pièce jointe signalée, sans jamais en recevoir les octets.
///
/// Le modèle de présentation ne porte **ni clé de fichier, ni IV, ni hash, ni URL** : la clé reste dans
/// l'enveloppe chiffrée qui n'est lisible que par les appareils destinataires. La vue du lot UI compose
/// le libellé à partir de ces seuls champs.
struct MessagingReportAttachment: Equatable, Sendable {
    enum Nature: String, Equatable, Sendable {
        case photo
        case pdf
    }

    let nature: Nature
    /// Nom déjà assaini par le contenu Matrix (jamais un chemin).
    let name: String
    /// Légende du message, `nil` quand il n'y en a pas.
    let caption: String?
    /// État de cette livraison : les octets de la pièce ne sont pas transmis aux administrateurs.
    let bytesTransmitted: Bool
}

/// Un message signalé, lisible seulement après un déchiffrement local sur l'appareil de l'administrateur.
struct MessagingReportLine: Identifiable, Equatable, Sendable {
    let id: UUID
    let senderName: String?
    let date: Date?
    /// Contenu du message ; nil quand cet appareil ne peut pas le lire.
    let text: String?
    /// Pièce jointe annoncée sans ses octets ; `nil` pour un texte ou un sondage.
    let media: MessagingReportAttachment?
    /// Phrase fixe qui dit pourquoi le message n'est pas lisible : jamais un contenu inventé.
    let unreadable: String?
}

/// Boîte des signalements de l'école (#77). Le serveur est seul juge du droit : un refus masque l'entrée, il n'est pas
/// une erreur à afficher. Le contenu des messages choisis arrive chiffré et n'est déchiffré qu'ici, à la demande.
@MainActor
@Observable final class MessagingReportInboxModel {
    enum Availability: Equatable { case unknown, hidden, available }

    let scope: MessagingScope
    private let moderation: any MessagingThreadActions
    private let cryptography: any MessagingCryptography
    private let currentScope: @MainActor @Sendable () -> MessagingScope?

    private(set) var availability: Availability = .unknown
    private(set) var reports: [MessagingReportRecord] = []
    private(set) var openCount = 0
    private(set) var nextCursor: UUID?
    private(set) var loading = false
    private(set) var failure: MessagingFailure?
    /// Signalements dont le statut est en cours de modification.
    private(set) var changing: Set<UUID> = []
    private(set) var opening: Set<UUID> = []
    private(set) var lines: [UUID: [MessagingReportLine]] = [:]
    private(set) var statusFailures: [UUID: MessagingFailure] = [:]

    init(scope: MessagingScope, moderation: any MessagingThreadActions, cryptography: any MessagingCryptography,
         currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) {
        self.scope = scope
        self.moderation = moderation
        self.cryptography = cryptography
        self.currentScope = currentScope
    }

    /// Une seule lecture pour savoir si l'entrée « Signalements » existe pour cette personne.
    func probe() async {
        guard availability == .unknown, !loading else { return }
        await load()
    }

    func load(more: Bool = false) async {
        guard !loading, !more || nextCursor != nil else { return }
        loading = true
        defer { loading = false }
        let cursor = more ? nextCursor : nil
        do {
            let page = try await moderation.reports(scope: scope, status: nil, before: cursor)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            if more {
                let known = Set(reports.map(\.id))
                reports += page.reports.filter { !known.contains($0.id) }
            } else {
                reports = page.reports
            }
            nextCursor = page.nextCursor
            openCount = page.openCount
            availability = .available
            failure = nil
        } catch MessagingFailure.accessChanged {
            // 403 : pas administrateur de l'école, ou droit retiré. Aucun reste de liste n'est gardé.
            availability = .hidden
            reports = []; lines = [:]; nextCursor = nil; openCount = 0; failure = nil
        } catch is CancellationError {
            return
        } catch let error as MessagingFailure {
            if error != .contextChanged { failure = error }
        } catch {
            failure = .unavailable
        }
    }

    /// Déchiffre les messages choisis, un par un, sur cet appareil. Un message illisible est dit tel quel.
    ///
    /// La provenance est celle de l'événement authentifié : un contenu Matrix structuré n'est jamais
    /// deviné depuis un `body` legacy, donc un ancien texte qui ressemble à du JSON reste du texte.
    func open(_ report: MessagingReportRecord) async {
        guard lines[report.id] == nil, !opening.contains(report.id) else { return }
        opening.insert(report.id)
        defer { opening.remove(report.id) }
        var result: [MessagingReportLine] = []
        for item in report.items {
            guard currentScope() == scope else { return }
            // L'auteur de l'enveloppe est le signalant : c'est lui qui a chiffré, dans le salon de signalement de l'école.
            let wire = MessagingWireMessage(id: item.messageID, conversationID: scope.schoolID, schoolID: scope.schoolID,
                                            senderID: report.reporterID, acceptedAt: report.createdAt, ciphertext: item.ciphertext)
            do {
                let content = try await Self.content(of: wire, cryptography: cryptography, scope: scope)
                guard currentScope() == scope else { return }
                result.append(MessagingReportLine(id: item.messageID, senderName: item.senderName, date: item.acceptedAt,
                                                  text: content.summary, media: Self.attachment(of: content),
                                                  unreadable: nil))
            } catch let failure as MessagingDecryptionFailure {
                let code = MessagingDiagnostics.isSafe(failure.code) ? failure.code : "D-X"
                result.append(MessagingReportLine(id: item.messageID, senderName: item.senderName, date: item.acceptedAt,
                                                  text: nil, media: nil,
                                                  unreadable: MessagingDecryptionFailure.explanation(for: code)))
            } catch is CancellationError {
                return
            } catch {
                result.append(MessagingReportLine(id: item.messageID, senderName: item.senderName, date: item.acceptedAt,
                                                  text: nil, media: nil,
                                                  unreadable: MessagingDecryptionFailure.explanation(for: "D-X")))
            }
        }
        guard currentScope() == scope else { return }
        lines[report.id] = result
    }

    /// Contenu d'un message signalé, selon la provenance rendue par la crypto.
    ///
    /// Un double sans provenance garde le décodeur legacy : il ne fabrique alors jamais de média.
    private static func content(of wire: MessagingWireMessage, cryptography: any MessagingCryptography,
                                scope: MessagingScope) async throws -> MessagingPlainContent {
        guard let provenance = cryptography as? any MessagingContentProvenanceDecryption else {
            let bytes = try await cryptography.decrypt(wire, scope: scope)
            guard let content = MessagingPlainContent.decode(bytes) else { throw MessagingFailure.invalidResponse }
            return content
        }
        let decrypted = try await provenance.decryptContent(wire, scope: scope)
        let content: MessagingPlainContent?
        switch decrypted.provenance {
        case .matrixContent: content = MessagingPlainContent.decodeMatrixContent(decrypted.bytes)
        case .legacyBody: content = MessagingPlainContent.decode(decrypted.bytes)
        }
        guard let content else { throw MessagingFailure.invalidResponse }
        return content
    }

    /// Métadonnées présentables d'une pièce jointe : nature, nom, légende. Jamais de clé, d'IV ni d'URL.
    private static func attachment(of content: MessagingPlainContent) -> MessagingReportAttachment? {
        guard let media = content.media else { return nil }
        let caption = content.text.flatMap { text -> String? in
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }
        return MessagingReportAttachment(nature: media.mime == .pdf ? .pdf : .photo,
                                         name: media.name, caption: caption, bytesTransmitted: false)
    }

    /// Changement de statut : le statut attendu est celui que cette personne voit ; un statut périmé relit la liste.
    func setStatus(_ report: MessagingReportRecord, to status: MessagingReportStatus) async {
        guard status != report.status, !changing.contains(report.id) else { return }
        changing.insert(report.id)
        defer { changing.remove(report.id) }
        statusFailures[report.id] = nil
        do {
            let change = try await moderation.setReportStatus(scope: scope, reportID: report.id, status: status,
                                                              expected: report.status)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            apply(change)
        } catch MessagingFailure.stateConflict {
            statusFailures[report.id] = .stateConflict
            await load()
        } catch MessagingFailure.accessChanged {
            // Droit retiré pendant la consultation : la boîte disparaît, rien n'a été modifié.
            availability = .hidden
            reports = []; lines = [:]; nextCursor = nil; openCount = 0
        } catch is CancellationError {
            return
        } catch let error as MessagingFailure {
            if error != .contextChanged { statusFailures[report.id] = error }
        } catch {
            statusFailures[report.id] = .unavailable
        }
    }

    private func apply(_ change: MessagingReportStatusChange) {
        guard let index = reports.firstIndex(where: { $0.id == change.reportID }) else { return }
        let previous = reports[index].status
        reports[index].status = change.status
        reports[index].statusUpdatedAt = change.statusUpdatedAt
        reports[index].history = change.history
        if previous == .open && change.status != .open { openCount = max(0, openCount - 1) }
        if previous != .open && change.status == .open { openCount += 1 }
    }
}
