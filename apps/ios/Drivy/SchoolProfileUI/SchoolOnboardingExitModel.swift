import Foundation
import Observation

/// Le geste de sortie capture seulement les références des brouillons connus, jamais leurs champs.
/// Le store existant est synchrone : aucune suppression n'est différée après une nouvelle connexion.
@MainActor @Observable
final class SchoolOnboardingExitModel {
    private struct Target: Equatable {
        let scope: SchoolCommandScope
        let kind: SchoolOnboardingKind
    }
    private(set) var errorMessage: String?
    @ObservationIgnored private let store: any SchoolOnboardingDraftStore
    @ObservationIgnored private var failed: [Target] = []
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var closing = false

    init(store: any SchoolOnboardingDraftStore = EncryptedSchoolOnboardingDraftStore()) { self.store = store }

    func begin(person: SchoolPerson?, apiBaseURL: String?, liveWorkspace: SchoolProfileWorkspace?, mask: () -> Void) -> UUID {
        generation = UUID()
        closing = true
        errorMessage = nil
        var targets: [Target] = []
        if let person, let apiBaseURL {
            func append(_ scope: SchoolCommandScope, _ kind: SchoolOnboardingKind) {
                guard scope.personID == person.personId, scope.apiBaseURL == apiBaseURL else { return }
                let target = Target(scope: scope, kind: kind)
                if !targets.contains(target) { targets.append(target) }
            }
            for membership in person.memberships {
                let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
                    membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: apiBaseURL)
                // Les rôles actuels n'énumèrent pas les accueils déjà saisis sous cette portée.
                append(scope, .student)
                append(scope, .staff)
            }
            if let liveWorkspace, let kind = liveWorkspace.onboardingKind { append(liveWorkspace.scope, kind) }
        }
        liveWorkspace?.invalidate()
        mask()
        failed = remove(targets)
        return generation
    }

    func finish(_ ticket: UUID, revokePush: () async -> Void, closeIdentity: () async -> Void) async {
        guard ticket == generation, closing else { return }
        await revokePush()
        guard ticket == generation, closing else { return }
        await closeIdentity()
        guard ticket == generation, closing else { return }
        closing = false
        showResult()
    }

    func retry() {
        guard !closing, !failed.isEmpty else { return }
        failed = remove(failed)
        showResult()
    }

    /// Une nouvelle connexion peut réutiliser exactement les mêmes noms de fichiers.
    /// Les anciennes références ne sont donc plus utilisables, même après une autre déconnexion.
    func connectionStarted() {
        generation = UUID()
        closing = false
        failed = []
        errorMessage = nil
    }

    private func remove(_ targets: [Target]) -> [Target] {
        targets.filter { target in
            do {
                try store.remove(scope: target.scope, kind: target.kind, discardingUnreadable: true)
                return false
            } catch { return true }
        }
    }

    private func showResult() {
        errorMessage = failed.isEmpty ? nil
            : "La session est fermée dans l’app, mais le brouillon d’accueil n’a pas pu être effacé."
    }
}
