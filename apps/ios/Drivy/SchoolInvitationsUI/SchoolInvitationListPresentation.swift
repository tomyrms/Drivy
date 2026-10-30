import Foundation

enum SchoolInvitationListFilter: String, CaseIterable, Identifiable, Hashable {
    case all, pending, accepted, expired, revoked
    var id: Self { self }
    var label: String {
        switch self {
        case .all: "Toutes"
        case .pending: "En attente"
        case .accepted: "Acceptées ou utilisées"
        case .expired: "Échues"
        case .revoked: "Révoquées"
        }
    }
    func includes(_ status: SchoolInvitationStatus) -> Bool {
        switch self {
        case .all: true
        case .pending: status == .pending
        case .accepted: status == .accepted
        case .expired: status == .expired
        case .revoked: status == .revoked
        }
    }
}

/// Presentation of the authorized projection only. No invitation token or one-time code is searchable.
enum SchoolInvitationListPresentation {
    static func shortReference(_ id: UUID) -> String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").suffix(4))
    }

    static func references(_ invitations: [SchoolInvitation], previous: [UUID: String]) -> [UUID: String] {
        // Only references sharing the same ending need extending. Filtering never changes this set.
        let collisions = HomonymReference.references(invitations.map { ($0.id, shortReference($0.id)) })
        return Dictionary(uniqueKeysWithValues: invitations.map { invitation in
            let candidate = collisions[invitation.id] ?? shortReference(invitation.id)
            let old = previous[invitation.id]
            // Keep the longer spelling if a collision disappears on refresh or renewal.
            return (invitation.id, old.map { $0.count > candidate.count ? $0 : candidate } ?? candidate)
        })
    }

    static func status(_ invitation: SchoolInvitation, now: Date) -> SchoolInvitationStatus {
        guard invitation.status == .pending, let expiry = SchoolInvitation.date(invitation.expiresAt), expiry <= now else {
            return invitation.status
        }
        return .expired
    }

    static func statusLabel(_ invitation: SchoolInvitation, now: Date) -> String {
        let displayed = status(invitation, now: now)
        // A passed local deadline does not invent a server-confirmed state transition.
        if invitation.status == .pending && displayed == .expired { return "Échéance passée" }
        if displayed == .pending { return "En attente" }
        return invitation.isCode ? InvitationPresentation.codeStatus(displayed) : displayed.label
    }

    static func deadline(_ invitation: SchoolInvitation, timeZone: String?) -> String {
        guard SchoolInvitation.date(invitation.expiresAt) != nil else { return "Échéance indisponible" }
        guard let timeZone, TimeZone(identifier: timeZone) != nil else { return "Fuseau de l’école indisponible" }
        return invitation.expirationLabel(timeZone: timeZone)
    }

    static func activeDeadline(_ invitation: SchoolInvitation, now: Date, timeZone: String?) -> String? {
        guard status(invitation, now: now) == .pending else { return nil }
        let value = deadline(invitation, timeZone: timeZone)
        guard SchoolInvitation.date(invitation.expiresAt) != nil,
              let timeZone, TimeZone(identifier: timeZone) != nil else { return value }
        return "Jusqu’au \(value)"
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CH"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func matches(_ invitation: SchoolInvitation, training: String?, reference: String, query: String) -> Bool {
        let words = normalized(query).split(separator: " ")
        let authorizedText = normalized([
            InvitationPresentation.title(invitation, training: training), invitation.roleLabel,
            training ?? "", "Réf. \(reference)", invitation.id.uuidString
        ].joined(separator: " "))
        return words.allSatisfy { authorizedText.contains($0) }
    }
}
