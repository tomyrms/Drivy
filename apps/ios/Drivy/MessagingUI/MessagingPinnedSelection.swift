import Foundation

/// Sélection par identité : une nouvelle page ou un désépinglage ne décale pas silencieusement la cible (#241).
struct MessagingPinnedSelection: Equatable {
    private(set) var selectedID: UUID?

    func current(in ids: [UUID]) -> UUID? {
        if let selectedID, ids.contains(selectedID) { return selectedID }
        return ids.first
    }

    mutating func reconcile(with ids: [UUID]) {
        selectedID = current(in: ids)
    }

    mutating func advance(in ids: [UUID], backwards: Bool = false) {
        guard let current = current(in: ids), let index = ids.firstIndex(of: current) else {
            selectedID = nil
            return
        }
        selectedID = ids[(index + (backwards ? ids.count - 1 : 1)) % ids.count]
    }
}
