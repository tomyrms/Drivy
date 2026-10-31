import Foundation

/// Une seule destination par avis. Les avis d’une autre invitation restent dans la liste ;
/// une panne de lecture globale suit le panneau visible lorsque la liste est masquée.
struct SchoolInvitationFeedbackPlacement {
    enum Surface: Equatable { case list, detail(UUID) }
    let visibleDetailID: UUID?
    let listIsVisible: Bool

    var reading: Surface {
        if !listIsVisible, let visibleDetailID { return .detail(visibleDetailID) }
        return .list
    }

    func operation(for invitationID: UUID?) -> Surface {
        if let invitationID, invitationID == visibleDetailID { return .detail(invitationID) }
        return .list
    }
}
