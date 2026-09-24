import Foundation

// Le replay et la liste privée partagent exactement le même DTO canonique.
typealias SchoolObservation = SchoolPrivateGeoObservation

enum SchoolObservationStatus: String, CaseIterable, Sendable, Identifiable {
    case attention = "ATTENTION", toWorkOn = "TO_REWORK", positive = "POSITIVE"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .attention: "Attention"
        case .toWorkOn: "À retravailler"
        case .positive: "Point positif"
        }
    }
}

extension SchoolPrivateGeoObservation {
    var isMarker: Bool { eventKind == "MARKER" }
    var statusLabel: String? { eventStatus.flatMap(SchoolObservationStatus.init(rawValue:))?.label }
    var observedDate: Date? { observedAt.flatMap(SchoolLesson.date) }
    var hasPosition: Bool { captureId != nil }
    var hasValidObservation: Bool {
        guard version > 0, version <= 2_147_483_647,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.unicodeScalars.count <= 4000,
              (captureId == nil && segmentId == nil && pointSequence == nil)
                || (captureId != nil && segmentId != nil && pointSequence.map { (0...2_147_483_646).contains($0) } == true),
              origin == nil || ["LIVE", "REVIEW"].contains(origin!),
              eventKind == nil || ["MARKER", "QUALIFIED"].contains(eventKind!),
              eventStatus == nil || SchoolObservationStatus(rawValue: eventStatus!) != nil,
              observedAt == nil || observedDate != nil else { return false }
        if origin != "LIVE", draftId == nil { return false }
        if eventKind == "MARKER", origin != "LIVE" || competencyId != nil || eventStatus != nil { return false }
        if origin == "LIVE" {
            guard authorMembershipId != nil, observedDate != nil, eventKind != nil else { return false }
            if eventKind == "QUALIFIED", competencyId == nil || eventStatus == nil { return false }
        }
        return true
    }
}

struct SchoolObservationBody: Codable, Sendable, Equatable {
    let operationId: UUID
    let draftId: UUID?
    let captureId: UUID?
    let segmentId: UUID?
    let pointSequence: Int?
    let competencyId: UUID?
    let text: String
    let origin: String
    let observedAt: String?
    let eventKind: String?
    let eventStatus: String?

    var isValid: Bool {
        guard ["LIVE", "REVIEW"].contains(origin),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.unicodeScalars.count <= 4000,
              (captureId == nil && segmentId == nil && pointSequence == nil)
                || (captureId != nil && segmentId != nil && pointSequence.map { (0...2_147_483_646).contains($0) } == true),
              eventKind == nil || ["MARKER", "QUALIFIED"].contains(eventKind!),
              eventStatus == nil || SchoolObservationStatus(rawValue: eventStatus!) != nil,
              observedAt == nil || SchoolLesson.date(observedAt!) != nil else { return false }
        if origin == "REVIEW", draftId == nil { return false }
        if eventKind == "MARKER", origin != "LIVE" || competencyId != nil || eventStatus != nil { return false }
        if origin == "LIVE" {
            guard observedAt != nil, eventKind != nil else { return false }
            if eventKind == "QUALIFIED", competencyId == nil || eventStatus == nil { return false }
        }
        return true
    }

    enum CodingKeys: String, CodingKey {
        case operationId, draftId, captureId, segmentId, pointSequence, competencyId, text, origin, observedAt, eventKind, eventStatus
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(operationId, forKey: .operationId)
        // Ces cinq champs sont requis par le contrat, même sans GPS ou sans brouillon.
        try c.encode(draftId, forKey: .draftId); try c.encode(captureId, forKey: .captureId)
        try c.encode(segmentId, forKey: .segmentId); try c.encode(pointSequence, forKey: .pointSequence)
        try c.encode(competencyId, forKey: .competencyId); try c.encode(text, forKey: .text)
        try c.encode(origin, forKey: .origin); try c.encodeIfPresent(observedAt, forKey: .observedAt)
        try c.encodeIfPresent(eventKind, forKey: .eventKind); try c.encode(eventStatus, forKey: .eventStatus)
    }
}

struct SchoolRemoveObservationBody: Codable, Sendable, Equatable {
    let operationId: UUID
    let reason: String
    var isValid: Bool { !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reason.unicodeScalars.count <= 1000 }
}

enum SchoolObservationMutationResult: Sendable {
    case observation(SchoolObservation)
    case removed(UUID)
}

enum SchoolObservationFailure: Error, LocalizedError, Equatable {
    case unauthorized, forbidden, notFound, unavailable, invalidResponse, conflict, anchorNotReady, reviewRequired, uncertain
    case rejected(String)
    var errorDescription: String? {
        switch self {
        case .unauthorized: "Reconnectez-vous pour retrouver les observations privées."
        case .forbidden: "Votre accès à cette leçon a changé. La demande en attente reste conservée."
        case .notFound: "Cette observation n’est pas disponible avec vos droits actuels."
        case .unavailable: "L’école est momentanément inaccessible. La demande en attente reste conservée."
        case .invalidResponse: "La réponse ne peut pas être vérifiée. Conservez la demande pour vérifier son résultat."
        case .conflict: "L’observation a changé, notamment lors du constat. Relisez sa version avant de la modifier."
        case .anchorNotReady: "Le point de ce signalement attend encore son transfert. L’observation reste en attente."
        case .reviewRequired: "Un bilan existe déjà. Reprenez explicitement cette observation dans le brouillon après relecture."
        case .uncertain: "Le résultat reste à vérifier. Conservez cette demande et sa référence avant une autre modification."
        case .rejected(let message): message
        }
    }
    var permitsFreshCorrection: Bool {
        switch self { case .conflict, .reviewRequired, .rejected: true; default: false }
    }
}
