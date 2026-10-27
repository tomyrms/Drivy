#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Panne synthétique du coffre ; aucune clé ni donnée réelle n'est lue.
@MainActor final class SchoolVisualUnavailableReportDrafts: SchoolReportLocalDraftStore {
    func read(scope: SchoolCommandScope, draftID: UUID) throws -> SchoolReportLocalDraft? { nil }
    func save(_ draft: SchoolReportLocalDraft, scope: SchoolCommandScope) throws { throw SchoolConfigurationFailure.storage }
    func remove(scope: SchoolCommandScope, draftID: UUID) throws { throw SchoolConfigurationFailure.storage }
}
#endif
