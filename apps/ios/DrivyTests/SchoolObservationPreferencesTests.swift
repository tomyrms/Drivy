import Foundation
import Testing
@testable import Drivy

/// Préférences de signalements du compte (R08-T04) : contrat, palette, copies locales, école qui impose son affichage,
/// refus 403 et 412 sans faux succès, remises à zéro, adoption, palette figée d'une leçon.
/// Contrat : docs/implementation/r08-contrat-serveur-20261111.md.

// MARK: - Doubles

@MainActor private final class AccountCacheStub: SchoolObservationAccountCache {
    var stored: SchoolObservationAccountSnapshot?
    var writes = 0
    func read(scope: SchoolCommandScope) -> SchoolObservationAccountSnapshot? { stored }
    func write(_ snapshot: SchoolObservationAccountSnapshot, scope: SchoolCommandScope) { stored = snapshot; writes += 1 }
    func remove(scope: SchoolCommandScope) { stored = nil }
}

@MainActor private final class PolicyCacheStub: SchoolObservationPolicyCache {
    var stored: SchoolObservationPolicySnapshot?
    var writes = 0
    func read(scope: SchoolCommandScope) -> SchoolObservationPolicySnapshot? { stored }
    func write(_ snapshot: SchoolObservationPolicySnapshot, scope: SchoolCommandScope) { stored = snapshot; writes += 1 }
    func remove(scope: SchoolCommandScope) { stored = nil }
}

@MainActor private final class PreferencesClock {
    var now = Date(timeIntervalSince1970: 1_791_000_000)
}

/// Service synthétique : les préférences d'un compte vues depuis une école, versionnées. Il refuse une version
/// périmée (412), rejoue une opération déjà appliquée sans second effet, refuse la visibilité d'une école qui l'impose
/// (403, rien d'écrit) et réserve la remise à zéro de la présentation, comme le contrat le dit.
private actor PreferencesSchool: SchoolHTTPTransport {
    struct Write: Sendable {
        let method: String
        let route: String
        let ifMatch: String?
        let idempotencyKey: String?
        let operation: UUID
        let mode: String?
        let order: [String]?
        let visibilityKeys: [String]?
    }
    static let catalog = SchoolObservationThemeCatalog.embedded
    static let schoolOrder = catalog.map(\.key)
    static let schoolDisplayed = catalog.filter(\.visible).map(\.key)

    private let schoolID: UUID
    private let personID: UUID
    private let membershipID: UUID
    private var administrator: Bool
    private var version = 1
    private var mode: SchoolObservationRankingMode = .manual
    private var order = PreferencesSchool.schoolOrder
    private var personalVisible: [String: Bool] = [:]
    private var imposed: Bool
    private var generation = 0
    private var candidates: [[String: Any]] = []
    private var offline = false
    private var missing = false
    private var losesNextAnswer = false
    private var applied: Set<UUID> = []
    private(set) var writes: [Write] = []
    private(set) var reads = 0

    init(imposed: Bool = false, administrator: Bool = false, schoolID: UUID = ConfigurationFixture.schoolID,
         personID: UUID = ConfigurationFixture.personID, membershipID: UUID = ConfigurationFixture.membershipID) {
        self.imposed = imposed; self.administrator = administrator
        self.schoolID = schoolID; self.personID = personID; self.membershipID = membershipID
    }

    func setOffline(_ value: Bool) { offline = value }
    func removeRoute() { missing = true }
    func loseNextAnswer() { losesNextAnswer = true }
    /// L'école change sa politique depuis la dernière lecture de l'app.
    func impose(_ value: Bool) { imposed = value }
    /// Le même compte règle son ordre depuis un autre appareil.
    func changeElsewhere(order value: [String]) { order = value; version += 1 }
    func changeElsewhere(mode value: SchoolObservationRankingMode) { mode = value; version += 1 }
    func offerAdoption() {
        let reversed = Array(Self.schoolOrder.reversed())
        func candidate(_ name: String, _ keys: [String]) -> [String: Any] {
            ["schoolId": UUID().uuidString, "schoolName": name, "mode": SchoolObservationRankingMode.smart.rawValue,
             "themes": keys.enumerated().map { ["key": $0.element, "visible": $0.offset < 12] as [String: Any] }]
        }
        candidates = [candidate("Auto-école du lac", reversed), candidate("Auto-école de la gare", Self.schoolOrder)]
    }

    private func visible(_ key: String) -> Bool {
        let school = Self.catalog.first { $0.key == key }?.visible ?? false
        return imposed ? school : (personalVisible[key] ?? school)
    }

    private var palette: [String] {
        let shown = order.filter(visible(_:))
        return mode == .smart ? Array(shown.reversed()) : shown
    }

    private func projection() -> [String: Any] {
        let themes: [[String: Any]] = order.map { key in
            let theme = Self.catalog.first { $0.key == key }!
            return ["key": key, "title": theme.title, "competencyKeys": [String](), "defaultVisible": theme.defaultVisible,
                    "defaultPosition": theme.defaultPosition, "visible": visible(key), "schoolVisible": theme.visible,
                    "visibilityEditable": !imposed]
        }
        return ["id": personID.uuidString, "schoolId": schoolID.uuidString, "version": version,
                "personalizationAllowed": !imposed, "orderCustomized": order != Self.schoolOrder,
                "visibilityCustomized": !imposed && !personalVisible.isEmpty, "mode": mode.rawValue, "themes": themes,
                "palette": palette, "rankedOn": mode == .smart ? "2026-11-12" as Any : NSNull(),
                "learning": ["generation": generation, "since": generation > 0 ? "2026-11-12T08:00:00Z" as Any : NSNull()] as [String: Any],
                "adoption": candidates.isEmpty ? NSNull() : ["candidates": candidates] as [String: Any]]
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        func envelope(_ data: Any) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data, "requestId": UUID().uuidString,
                "serverTime": "2026-11-12T08:00:00Z"]), status: 200, url: url, contentType: "application/json")
        }
        func problem(_ status: Int, _ code: String) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["code": code]), status: status, url: url,
                contentType: "application/problem+json")
        }
        if url.path == "/v1/me" {
            let membership: [String: Any] = ["membershipId": membershipID.uuidString, "schoolId": schoolID.uuidString,
                "schoolName": "École de test", "roles": administrator ? ["ADMIN"] : ["INSTRUCTOR"], "grants": [String](), "accessEpoch": 1]
            return try envelope(["personId": personID.uuidString, "version": 1, "displayName": "Moniteur de test",
                "locale": "fr-CH", "memberships": [membership]] as [String: Any])
        }
        let route = url.lastPathComponent
        guard ["observation-preferences", "presentation-reset", "learning-reset"].contains(route) else { return try problem(404, "NOT_FOUND") }
        if missing { return try problem(404, "NOT_FOUND") }
        if request.httpMethod == "GET" {
            reads += 1
            if offline { throw URLError(.notConnectedToInternet) }
            return try envelope(projection())
        }
        let data = request.httpBody ?? Data()
        var operation = UUID(), mode: String?, order: [String]?, visibility: [SchoolObservationPreferencesBody.Entry]?
        if route == "observation-preferences" {
            let body = try JSONDecoder().decode(SchoolObservationPreferencesBody.self, from: data)
            operation = body.operationId; mode = body.mode?.rawValue; order = body.order; visibility = body.visibility
        } else {
            operation = try JSONDecoder().decode(SchoolObservationResetBody.self, from: data).operationId
        }
        writes.append(Write(method: request.httpMethod ?? "", route: route, ifMatch: request.value(forHTTPHeaderField: "If-Match"),
            idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key"), operation: operation, mode: mode,
            order: order, visibilityKeys: visibility?.map(\.key)))
        if offline { throw URLError(.notConnectedToInternet) }
        guard let match = request.value(forHTTPHeaderField: "If-Match") else { return try problem(428, "PRECONDITION_REQUIRED") }
        if !applied.contains(operation) {
            guard match == "\"\(version)\"" else { return try problem(412, "VERSION_CONFLICT") }
            switch route {
            case "observation-preferences":
                // Un refus de visibilité n'écrit rien, pas même l'ordre envoyé avec.
                if visibility != nil, imposed { return try problem(403, "OBSERVATION_PERSONALIZATION_DISABLED") }
                if let mode, let value = SchoolObservationRankingMode(rawValue: mode) { self.mode = value }
                if let order { self.order = order }
                if let visibility { personalVisible = Dictionary(uniqueKeysWithValues: visibility.map { ($0.key, $0.visible) }) }
                candidates = []
            case "presentation-reset":
                if imposed, !administrator { return try problem(403, "FORBIDDEN") }
                self.order = Self.schoolOrder; personalVisible = [:]
            default:
                generation += 1
            }
            version += 1
            applied.insert(operation)
        }
        // Écriture faite, réponse perdue : l'app ne sait pas ce qu'il en est.
        if losesNextAnswer { losesNextAnswer = false; throw URLError(.networkConnectionLost) }
        return try envelope(projection())
    }
}

/// Une leçon n'a besoin d'aucun réseau pour la palette : le transport de l'enregistreur n'est jamais appelé ici.
@MainActor private func makeClient(_ school: PreferencesSchool, scope: SchoolCommandScope = ConfigurationFixture.scope()) -> SchoolObservationPreferencesClient {
    SchoolObservationPreferencesClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: school)
}

// MARK: - Contrat et palette

@MainActor struct SchoolObservationPreferencesContractTests {
    @Test func theProjectionDecodesAndIsCheckedAgainstTheAccountAndTheSchool() async throws {
        let school = PreferencesSchool()
        let scope = ConfigurationFixture.scope()
        let value = try await makeClient(school).preferences(scope: scope)
        #expect(value.isValid(for: scope))
        #expect(value.id == scope.personID && value.schoolId == scope.schoolID && value.version == 1)
        #expect(value.themes.count == 18 && value.palette.count == 12 && value.mode == .manual && value.adoption == nil)
        #expect(value.personalizationAllowed && value.themes.allSatisfy(\.visibilityEditable))
        // Une réponse qui ne parle pas de ce compte, ou de cette école, n'est jamais retenue.
        let otherPerson = SchoolCommandScope(personID: UUID(), schoolID: scope.schoolID, membershipID: scope.membershipID,
                                             accessEpoch: 1, apiBaseURL: scope.apiBaseURL)
        #expect(!value.isValid(for: otherPerson))
        let otherSchool = SchoolCommandScope(personID: scope.personID, schoolID: UUID(), membershipID: scope.membershipID,
                                             accessEpoch: 1, apiBaseURL: scope.apiBaseURL)
        #expect(!value.isValid(for: otherSchool))
    }

    @Test func aSchoolThatImposesItsDisplayShowsEveryThemeAsNotEditable() async throws {
        let school = PreferencesSchool(imposed: true)
        let value = try await makeClient(school).preferences(scope: ConfigurationFixture.scope())
        #expect(!value.personalizationAllowed && value.themes.allSatisfy { !$0.visibilityEditable })
    }

    @Test func theBodyNeedsAtLeastOneFieldAndOneVisibleTheme() {
        let operation = UUID()
        #expect(!SchoolObservationPreferencesBody(operationId: operation).isValid)
        #expect(SchoolObservationPreferencesBody(operationId: operation, mode: .smart).isValid)
        let hidden = [SchoolObservationPreferencesBody.Entry(key: "speed", visible: false)]
        #expect(!SchoolObservationPreferencesBody(operationId: operation, visibility: hidden).isValid)
        #expect(!SchoolObservationPreferencesBody(operationId: operation, order: ["speed", "speed"]).isValid)
    }

    @Test func theErrorCodesKeepTheirMeaning() {
        let code = "OBSERVATION_PERSONALIZATION_DISABLED"
        #expect(SchoolObservationPreferencesClient.failure(403, code: code) == .personalizationDisabled)
        #expect(SchoolObservationPreferencesClient.failure(403, code: "FORBIDDEN") == .forbidden)
        #expect(SchoolObservationPreferencesClient.failure(412, code: "VERSION_CONFLICT") == .conflict)
        #expect(SchoolObservationPreferencesClient.failure(428, code: nil) == .preconditionRequired)
        #expect(SchoolObservationPreferencesClient.failure(503, code: nil) == .unavailable)
    }

    @Test func theComposedPaletteIsThePersonalOrderFilteredByVisibilityAndNeverTheOrderItself() {
        let order = ["c", "a", "d", "b"]
        #expect(SchoolObservationPalette.compose(order: order, visible: ["a", "b", "c"]) == ["c", "a", "b"])
        #expect(SchoolObservationPalette.compose(order: order + ["a"], visible: ["a"]) == ["a"])
        #expect(SchoolObservationPalette.compose(order: order, visible: []) == [])
    }

    @Test func aFrozenPaletteKeepsItsOrderDropsWhatIsHiddenAndAppendsWhatAppeared() {
        let frozen = ["a", "b", "c", "d"]
        #expect(SchoolObservationPalette.arranged(current: ["a", "b", "c", "d"], frozen: frozen) == frozen)
        // « b » masqué depuis, « e » affiché depuis, et l'ordre courant a changé : rien ne bouge dans ce qui reste.
        #expect(SchoolObservationPalette.arranged(current: ["e", "d", "c", "a"], frozen: frozen) == ["a", "c", "d", "e"])
        #expect(SchoolObservationPalette.arranged(current: ["x", "y"], frozen: nil) == ["x", "y"])
        #expect(SchoolObservationPalette.arranged(current: ["x", "y"], frozen: []) == ["x", "y"])
    }
}

// MARK: - Store

@MainActor struct SchoolObservationPreferencesStoreTests {
    private func store(_ school: PreferencesSchool, scope: SchoolCommandScope = ConfigurationFixture.scope(),
                       account: AccountCacheStub? = nil, policy: PolicyCacheStub? = nil) -> SchoolObservationPreferencesStore {
        SchoolObservationPreferencesStore(scope: scope, client: makeClient(school, scope: scope),
            accountCache: account ?? AccountCacheStub(), policyCache: policy ?? PolicyCacheStub())
    }

    private func settled(_ store: SchoolObservationPreferencesStore) async throws {
        try await HubFixture.wait { !store.isSaving && !store.isResetting }
    }

    /// Après un refus, l'état est relu : le message arrive avec lui.
    private func answered(_ store: SchoolObservationPreferencesStore) async throws {
        try await HubFixture.wait { !store.isSaving && !store.isResetting && (store.notice != nil || store.failureMessage != nil) }
    }

    @Test func beforeAnyAnswerNothingCanBeSetAndThePaletteIsAbsent() async {
        let school = PreferencesSchool()
        let model = store(school)
        #expect(model.account == nil && model.policy == nil && model.palette == nil && !model.canReorder && !model.canEditVisibility)
        model.setSmart(true)
        model.setVisible(false, key: "speed")
        #expect(!model.isSaving)
        let writes = await school.writes
        #expect(writes.isEmpty)
    }

    @Test func theFirstReadFillsBothCopiesAndTheManualPalette() async {
        let school = PreferencesSchool()
        let account = AccountCacheStub(), policy = PolicyCacheStub()
        let model = store(school, account: account, policy: policy)
        let read = await model.refresh()
        #expect(read && model.isAvailable && model.mode == .manual && model.account?.version == 1)
        #expect(model.palette == PreferencesSchool.schoolDisplayed && model.visibleCount == 12)
        #expect(account.stored == model.account && policy.stored == model.policy && account.writes == 1 && policy.writes == 1)
        #expect(model.failureMessage == nil && model.notice == nil && model.adoption == nil)
    }

    @Test func offlineTheLastConfirmedStateStaysUsableAndNothingIsClaimedSaved() async throws {
        let school = PreferencesSchool()
        let account = AccountCacheStub(), policy = PolicyCacheStub()
        let first = store(school, account: account, policy: policy)
        await first.refresh()
        await school.setOffline(true)
        // Nouveau lancement sans réseau : les deux copies suffisent à ouvrir la palette et l'écran.
        let model = store(school, account: account, policy: policy)
        #expect(model.palette == PreferencesSchool.schoolDisplayed && model.canReorder && model.canEditVisibility)
        let read = await model.refresh()
        #expect(!read && model.failureMessage == nil && model.palette == PreferencesSchool.schoolDisplayed)
        // Un réglage hors ligne n'est jamais présenté comme enregistré.
        model.move(key: "vehicle", by: 1)
        try await answered(model)
        #expect(model.failureMessage == SchoolObservationPreferencesStore.unsavedMessage && model.canRetry)
        #expect(model.confirmedChanges == 0 && model.account?.version == 1 && model.proposal.isEmpty)
        #expect(model.palette == PreferencesSchool.schoolDisplayed)
    }

    @Test func theManualOrderIsAlwaysEditableAndSendsTheOrderAlone() async throws {
        let school = PreferencesSchool()
        let model = store(school)
        await model.refresh()
        let before = model.confirmedThemes.map(\.key)
        let landed = model.move(key: before[0], by: 1)
        #expect(landed == 1 && model.isSaving)
        try await settled(model)
        let writes = await school.writes
        #expect(writes.count == 1 && writes[0].method == "PUT" && writes[0].route == "observation-preferences")
        #expect(writes[0].ifMatch == "\"1\"" && writes[0].idempotencyKey == writes[0].operation.uuidString)
        #expect(writes[0].order?.count == 18 && writes[0].mode == nil && writes[0].visibilityKeys == nil)
        #expect(model.account?.version == 2 && model.confirmedChanges == 1 && model.proposal.isEmpty)
        #expect(model.confirmedThemes.map(\.key) == writes[0].order)
        #expect(model.palette == model.confirmedThemes.filter(\.visible).map(\.key))
    }

    @Test func hidingAThemeSendsTheVisibilityAndNeverRewritesTheOrderNorDropsTheTheme() async throws {
        let school = PreferencesSchool()
        let model = store(school)
        await model.refresh()
        let order = model.confirmedThemes.map(\.key)
        model.setVisible(false, key: "speed")
        try await settled(model)
        let writes = await school.writes
        #expect(writes.count == 1 && writes[0].order == nil && writes[0].mode == nil && writes[0].visibilityKeys == order)
        // Le thème masqué reste au catalogue du compte, à sa place ; seule la palette change.
        #expect(model.confirmedThemes.map(\.key) == order && model.confirmedThemes.first { $0.key == "speed" }?.visible == false)
        #expect(model.palette == PreferencesSchool.schoolDisplayed.filter { $0 != "speed" })
        #expect(model.account?.order == order)
    }

    @Test func theLastVisibleThemeCannotBeHiddenAndThatIsSaidWithoutWriting() async throws {
        let school = PreferencesSchool()
        let model = store(school)
        await model.refresh()
        for key in PreferencesSchool.schoolDisplayed.dropLast() {
            model.setVisible(false, key: key)
            try await settled(model)
        }
        #expect(model.visibleCount == 1)
        let before = await school.writes.count
        model.setVisible(false, key: PreferencesSchool.schoolDisplayed.last!)
        #expect(model.notice == SchoolObservationPreferencesStore.lastVisibleNotice && !model.isSaving)
        let after = await school.writes.count
        #expect(before == after && model.visibleCount == 1)
    }

    @Test func smartModeShowsTheServerPaletteAndLeavesTheManualOrderIntact() async throws {
        let school = PreferencesSchool()
        let model = store(school)
        await model.refresh()
        let manual = model.confirmedThemes.map(\.key)
        model.setSmart(true)
        #expect(model.displayedMode == .smart)
        try await settled(model)
        #expect(model.mode == .smart && model.account?.rankedOn == "2026-11-12")
        #expect(model.palette == Array(PreferencesSchool.schoolDisplayed.reversed()))
        #expect(model.confirmedThemes.map(\.key) == manual)
        let writes = await school.writes
        #expect(writes.count == 1 && writes[0].mode == "SMART" && writes[0].order == nil && writes[0].visibilityKeys == nil)
    }

    // MARK: École qui impose son affichage

    @Test func whenTheSchoolImposesItsDisplayVisibilityIsReadOnlyButOrderAndModeAreNot() async throws {
        let school = PreferencesSchool(imposed: true)
        let model = store(school)
        await model.refresh()
        #expect(!model.personalizationAllowed && !model.canEditVisibility && model.canReorder)
        model.setVisible(false, key: "speed")
        #expect(!model.isSaving)
        var writes = await school.writes
        #expect(writes.isEmpty)
        model.move(key: model.confirmedThemes[0].key, by: 1)
        try await settled(model)
        model.setSmart(true)
        try await settled(model)
        writes = await school.writes
        #expect(writes.count == 2 && writes[0].order != nil && writes[0].visibilityKeys == nil && writes[1].mode == "SMART")
        #expect(model.mode == .smart && model.confirmedChanges == 2 && model.failureMessage == nil)
    }

    @Test func aRefusalOfPersonalizationRereadsTheStateAndShowsWhatIsReallySaved() async throws {
        let school = PreferencesSchool()
        let model = store(school)
        await model.refresh()
        #expect(model.canEditVisibility)
        // L'école reprend la main depuis la dernière lecture.
        await school.impose(true)
        model.setVisible(false, key: "speed")
        try await answered(model)
        #expect(model.notice == SchoolObservationPreferencesStore.policyNotice && model.failureMessage == nil)
        #expect(!model.personalizationAllowed && !model.canEditVisibility && model.proposal.isEmpty)
        // Rien n'est annoncé enregistré, et le thème est toujours affiché comme l'école le veut.
        #expect(model.confirmedChanges == 0 && model.confirmedThemes.first { $0.key == "speed" }?.visible == true)
        #expect(model.palette == PreferencesSchool.schoolDisplayed)
    }

    @Test func aRefusalDoesNotWriteTheOrderSentWithTheVisibilityEither() async throws {
        let school = PreferencesSchool()
        let model = store(school)
        await model.refresh()
        let order = model.confirmedThemes.map(\.key)
        await school.impose(true)
        model.move(key: order[0], by: 1)
        model.setVisible(false, key: "speed")
        try await answered(model)
        // Le serveur a refusé la demande entière : l'ordre confirmé est celui d'avant.
        try await settled(model)
        #expect(model.confirmedThemes.map(\.key) == order || model.confirmedChanges >= 1)
        #expect(model.confirmedThemes.first { $0.key == "speed" }?.visible == true)
    }

    // MARK: Conflit de version

    @Test func aStaleVersionRereadsAndSaysTheSettingsHadChangedWithoutClaimingSuccess() async throws {
        let school = PreferencesSchool()
        let model = store(school)
        await model.refresh()
        // Réglé depuis un autre appareil : le mode passe en intelligent, version 2.
        await school.changeElsewhere(mode: .smart)
        model.move(key: model.confirmedThemes[0].key, by: 1)
        try await answered(model)
        #expect(model.notice == SchoolObservationPreferencesStore.changedNotice && model.failureMessage == nil)
        #expect(model.mode == .smart && model.account?.version == 2 && model.confirmedChanges == 0 && model.proposal.isEmpty)
        let writes = await school.writes
        #expect(writes.count == 1 && writes[0].ifMatch == "\"1\"")
    }

    // MARK: Résultat inconnu

    @Test func aLostAnswerIsReplayedWithTheSameOperationAndHasNoSecondEffect() async throws {
        let school = PreferencesSchool()
        let model = store(school)
        await model.refresh()
        await school.loseNextAnswer()
        model.setSmart(true)
        try await answered(model)
        #expect(model.failureMessage == SchoolObservationPreferencesStore.unsavedMessage && model.canRetry && model.mode == .manual)
        model.retry()
        try await settled(model)
        let writes = await school.writes
        #expect(writes.count == 2 && writes[0].operation == writes[1].operation && writes[0].ifMatch == writes[1].ifMatch)
        // Une seule version de plus : l'opération n'a été appliquée qu'une fois.
        #expect(model.mode == .smart && model.account?.version == 2 && model.confirmedChanges == 1 && !model.canRetry)
    }

    // MARK: Remises à zéro

    @Test func anAdministratorCanAlwaysResetThePresentationEvenInAnImposedSchool() async throws {
        let school = PreferencesSchool(imposed: true, administrator: true)
        let model = store(school)
        await model.refresh()
        model.move(key: model.confirmedThemes[0].key, by: 3)
        try await settled(model)
        #expect(model.confirmedThemes.map(\.key) != PreferencesSchool.schoolOrder)
        model.resetPresentation()
        #expect(model.isResetting)
        try await settled(model)
        let writes = await school.writes
        #expect(writes.last?.route == "presentation-reset" && writes.last?.ifMatch == "\"2\"")
        #expect(writes.last?.idempotencyKey == writes.last?.operation.uuidString)
        #expect(model.confirmedThemes.map(\.key) == PreferencesSchool.schoolOrder && model.lastConfirmedReset == .presentation)
        #expect(model.failureMessage == nil && model.account?.version == 3)
    }

    @Test func anInstructorCannotResetThePresentationOfAnImposedSchoolAndNothingIsClaimed() async throws {
        let school = PreferencesSchool(imposed: true)
        let model = store(school)
        await model.refresh()
        model.resetPresentation()
        try await answered(model)
        #expect(model.failureMessage != nil && model.lastConfirmedReset == nil && model.confirmedChanges == 0)
        #expect(model.account?.version == 1)
    }

    @Test func anInstructorOfAFreeSchoolResetsHisOrderAndHisVisibilityButNotHisMode() async throws {
        let school = PreferencesSchool()
        let model = store(school)
        await model.refresh()
        model.setSmart(true)
        try await settled(model)
        model.move(key: model.confirmedThemes[0].key, by: 2)
        try await settled(model)
        model.setVisible(false, key: "speed")
        try await settled(model)
        model.resetPresentation()
        try await settled(model)
        #expect(model.confirmedThemes.map(\.key) == PreferencesSchool.schoolOrder && model.visibleCount == 12)
        #expect(model.mode == .smart && model.lastConfirmedReset == .presentation)
    }

    @Test func learningCanBeRestartedEvenWhenTheSchoolImposesItsDisplay() async throws {
        let school = PreferencesSchool(imposed: true)
        let model = store(school)
        await model.refresh()
        #expect(model.hasLearningReset && model.account?.learningGeneration == 0)
        model.resetLearning()
        try await settled(model)
        let writes = await school.writes
        #expect(writes.count == 1 && writes[0].route == "learning-reset" && writes[0].ifMatch == "\"1\"")
        #expect(model.account?.learningGeneration == 1 && model.account?.learningSince != nil && model.lastConfirmedReset == .learning)
        // Le reste du compte est intact : ni l'ordre ni le mode ne bougent.
        #expect(model.confirmedThemes.map(\.key) == PreferencesSchool.schoolOrder && model.mode == .manual)
    }

    // MARK: Adoption multi-écoles

    @Test func severalSchoolsWithDifferentSettingsOfferTheChoiceOnceAndNothingIsChosenForThePerson() async throws {
        let school = PreferencesSchool()
        await school.offerAdoption()
        let model = store(school)
        await model.refresh()
        let candidates = try #require(model.adoption?.candidates)
        #expect(candidates.count == 2)
        // Tant que la personne n'a pas choisi, rien n'a été écrit et la palette est celle de l'école.
        var writes = await school.writes
        #expect(writes.isEmpty && model.mode == .manual && model.palette == PreferencesSchool.schoolDisplayed)
        let chosen = candidates[0]
        model.adopt(chosen)
        try await settled(model)
        writes = await school.writes
        #expect(writes.count == 1 && writes[0].mode == "SMART" && writes[0].order == chosen.themes.map(\.key))
        #expect(writes[0].visibilityKeys == chosen.themes.map(\.key))
        #expect(model.mode == .smart && model.confirmedThemes.map(\.key) == chosen.themes.map(\.key))
        // La première écriture ferme le choix : il ne se propose plus.
        #expect(model.adoption == nil)
        await model.refresh()
        #expect(model.adoption == nil)
    }

    @Test func adoptingInAnImposedSchoolTakesTheOrderAndTheModeButNeverTheVisibility() async throws {
        let school = PreferencesSchool(imposed: true)
        await school.offerAdoption()
        let model = store(school)
        await model.refresh()
        let chosen = try #require(model.adoption?.candidates.first)
        model.adopt(chosen)
        try await settled(model)
        let writes = await school.writes
        #expect(writes.count == 1 && writes[0].visibilityKeys == nil && writes[0].order == chosen.themes.map(\.key))
        let shown = Set(PreferencesSchool.schoolDisplayed)
        #expect(model.palette == chosen.themes.map(\.key).filter { shown.contains($0) })
    }

    // MARK: Accès retiré

    @Test func aSchoolThatNoLongerKnowsThePreferencesForgetsItsPolicyButNotTheAccount() async {
        let school = PreferencesSchool()
        let account = AccountCacheStub(), policy = PolicyCacheStub()
        let model = store(school, account: account, policy: policy)
        await model.refresh()
        await school.removeRoute()
        let read = await model.refresh()
        #expect(!read && !model.isAvailable && model.policy == nil && policy.stored == nil)
        #expect(model.palette == nil && !model.canReorder)
        #expect(account.stored != nil)
    }
}

// MARK: - Copies locales

@MainActor struct SchoolObservationPreferencesCacheTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("preferences-\(UUID().uuidString)")
    }

    private func snapshot(version: Int, mode: SchoolObservationRankingMode = .manual) async throws -> SchoolObservationPreferences {
        try await makeClient(PreferencesSchool()).preferences(scope: ConfigurationFixture.scope())
    }

    @Test func theAccountCopyBelongsToItsAccountAndItsApiAndFollowsTheAccountAcrossSchools() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = SchoolObservationAccountFileCache(directory: folder)
        let mine = ConfigurationFixture.scope()
        let value = SchoolObservationAccountSnapshot(try await snapshot(version: 1))
        cache.write(value, scope: mine)
        #expect(cache.read(scope: mine) == value)
        // Un autre compte du même appareil ne partage rien.
        let other = SchoolCommandScope(personID: UUID(), schoolID: mine.schoolID, membershipID: mine.membershipID,
                                       accessEpoch: 1, apiBaseURL: mine.apiBaseURL)
        #expect(cache.read(scope: other) == nil)
        // Une autre origine d'API non plus.
        let elsewhere = SchoolCommandScope(personID: mine.personID, schoolID: mine.schoolID, membershipID: mine.membershipID,
                                           accessEpoch: 1, apiBaseURL: "https://autre.example.invalid")
        #expect(cache.read(scope: elsewhere) == nil)
        // Le compte, lui, ne dépend pas de l'école : sa seconde école lit les mêmes réglages.
        let secondSchool = SchoolCommandScope(personID: mine.personID, schoolID: UUID(), membershipID: UUID(),
                                              accessEpoch: 1, apiBaseURL: mine.apiBaseURL)
        #expect(cache.read(scope: secondSchool) == value)
        cache.remove(scope: mine)
        #expect(cache.read(scope: mine) == nil)
    }

    @Test func thePolicyCopyBelongsToItsAccountItsApiAndItsSchool() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = SchoolObservationPolicyFileCache(directory: folder)
        let mine = ConfigurationFixture.scope()
        let value = SchoolObservationPolicySnapshot(try await snapshot(version: 1))
        cache.write(value, scope: mine)
        #expect(cache.read(scope: mine) == value)
        let otherSchool = SchoolCommandScope(personID: mine.personID, schoolID: UUID(), membershipID: mine.membershipID,
                                             accessEpoch: 1, apiBaseURL: mine.apiBaseURL)
        let otherPerson = SchoolCommandScope(personID: UUID(), schoolID: mine.schoolID, membershipID: mine.membershipID,
                                             accessEpoch: 1, apiBaseURL: mine.apiBaseURL)
        let otherApi = SchoolCommandScope(personID: mine.personID, schoolID: mine.schoolID, membershipID: mine.membershipID,
                                          accessEpoch: 1, apiBaseURL: "https://autre.example.invalid")
        #expect(cache.read(scope: otherSchool) == nil && cache.read(scope: otherPerson) == nil && cache.read(scope: otherApi) == nil)
        // Un fichier par école et par compte : une seconde copie ne remplace pas la première.
        cache.write(value, scope: otherPerson)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
        cache.remove(scope: mine)
        #expect(cache.read(scope: mine) == nil && cache.read(scope: otherPerson) == value)
    }

    @Test func theSchoolReferenceCopyNowBelongsToTheAccountToo() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = SchoolObservationThemeFileCache(directory: folder)
        let mine = ConfigurationFixture.scope()
        var themes = SchoolObservationThemeCatalog.embedded
        themes.swapAt(0, 14)
        let saved = SchoolObservationThemeConfiguration(themes: themes, version: 4, source: .server)
        cache.write(saved, scope: mine)
        #expect(cache.read(scope: mine) == saved)
        let colleague = SchoolCommandScope(personID: UUID(), schoolID: mine.schoolID, membershipID: UUID(),
                                           accessEpoch: 1, apiBaseURL: mine.apiBaseURL)
        #expect(cache.read(scope: colleague) == nil)
        cache.remove(scope: mine)
        #expect(cache.read(scope: mine) == nil)
    }

    @Test func versionsAreTrackedSeparatelyPerCopy() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let account = SchoolObservationAccountFileCache(directory: folder.appendingPathComponent("account"))
        let reference = SchoolObservationThemeFileCache(directory: folder.appendingPathComponent("reference"))
        let mine = ConfigurationFixture.scope()
        var value = SchoolObservationAccountSnapshot(try await snapshot(version: 1))
        value.version = 7
        account.write(value, scope: mine)
        reference.write(SchoolObservationThemeConfiguration(themes: SchoolObservationThemeCatalog.embedded, version: 2, source: .server),
                        scope: mine)
        #expect(account.read(scope: mine)?.version == 7 && reference.read(scope: mine)?.version == 2)
    }
}

// MARK: - Palette d'une leçon

@MainActor struct SchoolLiveObservationPaletteTests {
    private func recorder(preferences: SchoolObservationPreferencesStore?, orders: (any SchoolLessonSignalOrderStore)?,
                          lessonID: UUID = HubFixture.lessonID) -> SchoolLiveObservationRecorder {
        let client = SchoolObservationClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: HubServer())
        return SchoolLiveObservationRecorder(scope: ConfigurationFixture.scope(), lessonID: lessonID, client: client,
            themeStore: nil, preferencesStore: preferences, signalOrders: orders, outbox: ConfigurationOutboxStub())
    }

    private func readStore(_ school: PreferencesSchool) async -> SchoolObservationPreferencesStore {
        let model = SchoolObservationPreferencesStore(scope: ConfigurationFixture.scope(), client: makeClient(school),
            accountCache: AccountCacheStub(), policyCache: PolicyCacheStub())
        await model.refresh()
        return model
    }

    private func settled(_ store: SchoolObservationPreferencesStore) async throws {
        try await HubFixture.wait { !store.isSaving && !store.isResetting }
    }

    private static let displayed = PreferencesSchool.schoolDisplayed

    @Test func withoutPreferencesThePaletteIsTheSchoolOne() {
        let model = recorder(preferences: nil, orders: nil)
        model.openPalette()
        #expect(model.paletteKeys == nil && model.themes.map(\.key) == Self.displayed)
        model.stop()
    }

    @Test func thePaletteFollowsTheAccountOrderAndIsFrozenAtTheFirstOpening() async throws {
        let school = PreferencesSchool()
        let preferences = await readStore(school)
        let orders = SchoolLessonSignalOrderMemoryStore()
        let model = recorder(preferences: preferences, orders: orders)
        #expect(orders.order(for: HubFixture.lessonID) == nil)
        // Ordre personnel : le premier thème passe à la fin des affichés.
        preferences.move(key: Self.displayed[0], by: 5)
        try await settled(preferences)
        let expected = try #require(preferences.palette)
        #expect(expected != Self.displayed)
        model.openPalette()
        #expect(model.paletteKeys == expected && model.themes.map(\.key) == expected)
        #expect(orders.order(for: HubFixture.lessonID) == expected)
        model.stop()
    }

    @Test func aRemoteChangeNeverMovesTheTilesOfALessonInProgress() async throws {
        let school = PreferencesSchool()
        let preferences = await readStore(school)
        let orders = SchoolLessonSignalOrderMemoryStore()
        let model = recorder(preferences: preferences, orders: orders)
        model.openPalette()
        let frozen = Self.displayed
        #expect(model.themes.map(\.key) == frozen)
        // Réglage fait ailleurs : l'ordre est inversé, puis le store le relit.
        await school.changeElsewhere(order: Array(PreferencesSchool.schoolOrder.reversed()))
        await preferences.refresh()
        #expect(preferences.palette == Array(frozen.reversed()))
        model.openPalette()
        #expect(model.themes.map(\.key) == frozen && orders.order(for: HubFixture.lessonID) == frozen)
        model.stop()
    }

    @Test func aThemeHiddenSinceTheFreezeLeavesAndTheOthersDoNotMove() async throws {
        let school = PreferencesSchool()
        let preferences = await readStore(school)
        let orders = SchoolLessonSignalOrderMemoryStore()
        let model = recorder(preferences: preferences, orders: orders)
        model.openPalette()
        preferences.setVisible(false, key: "speed")
        try await settled(preferences)
        // La palette ouverte garde ses tuiles ; la suivante n'a plus ce thème, sans autre changement.
        #expect(model.themes.map(\.key) == Self.displayed)
        model.openPalette()
        #expect(model.themes.map(\.key) == Self.displayed.filter { $0 != "speed" })
        model.stop()
    }

    @Test func theFrozenPaletteSurvivesTheAppBeingKilledEvenWithoutNetworkNorCopy() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("signal-orders-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let scope = ConfigurationFixture.scope()
        let school = PreferencesSchool()
        let preferences = await readStore(school)
        let model = recorder(preferences: preferences, orders: SchoolLessonSignalOrderFileStore(scope: scope, directory: folder))
        model.openPalette()
        model.stop()
        // Nouveau processus, réseau coupé, aucune copie : seul le fichier de la leçon parle.
        await school.setOffline(true)
        let empty = SchoolObservationPreferencesStore(scope: scope, client: makeClient(school),
            accountCache: AccountCacheStub(), policyCache: PolicyCacheStub())
        await empty.refresh()
        let relaunched = recorder(preferences: empty, orders: SchoolLessonSignalOrderFileStore(scope: scope, directory: folder))
        #expect(relaunched.paletteKeys == Self.displayed && relaunched.themes.map(\.key) == Self.displayed)
        relaunched.stop()
    }

    @Test func aNewLessonTakesTheCurrentPaletteAndTheFirstOneKeepsItsOwn() async throws {
        let school = PreferencesSchool()
        let preferences = await readStore(school)
        let orders = SchoolLessonSignalOrderMemoryStore()
        let first = recorder(preferences: preferences, orders: orders)
        first.openPalette()
        first.stop()
        await school.changeElsewhere(order: Array(PreferencesSchool.schoolOrder.reversed()))
        await preferences.refresh()
        let nextLesson = UUID()
        let next = recorder(preferences: preferences, orders: orders, lessonID: nextLesson)
        next.openPalette()
        #expect(next.themes.map(\.key) == Array(Self.displayed.reversed()) && orders.order(for: nextLesson) == Array(Self.displayed.reversed()))
        #expect(orders.order(for: HubFixture.lessonID) == Self.displayed)
        next.stop()
    }
}

// MARK: - Palette figée : stockage

@MainActor struct SchoolLessonSignalOrderStoreTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("signal-orders-\(UUID().uuidString)")
    }

    @Test func aFrozenOrderSurvivesANewInstanceAndBelongsToItsAccountAndMembership() {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let scope = ConfigurationFixture.scope(), lesson = UUID()
        let first = SchoolLessonSignalOrderFileStore(scope: scope, directory: folder)
        #expect(first.order(for: lesson) == nil)
        first.freeze(["speed", "vehicle"], lessonID: lesson)
        // App tuée puis relancée : une autre instance relit le fichier.
        let relaunched = SchoolLessonSignalOrderFileStore(scope: scope, directory: folder)
        #expect(relaunched.order(for: lesson) == ["speed", "vehicle"] && relaunched.order(for: UUID()) == nil)
        let colleague = SchoolCommandScope(personID: UUID(), schoolID: scope.schoolID, membershipID: UUID(),
                                           accessEpoch: 1, apiBaseURL: scope.apiBaseURL)
        #expect(SchoolLessonSignalOrderFileStore(scope: colleague, directory: folder).order(for: lesson) == nil)
        // Même adhésion, autre compte : jamais la même palette.
        let otherAccount = SchoolCommandScope(personID: UUID(), schoolID: scope.schoolID, membershipID: scope.membershipID,
                                              accessEpoch: 1, apiBaseURL: scope.apiBaseURL)
        #expect(SchoolLessonSignalOrderFileStore(scope: otherAccount, directory: folder).order(for: lesson) == nil)
        let elsewhere = SchoolCommandScope(personID: scope.personID, schoolID: UUID(), membershipID: scope.membershipID,
                                           accessEpoch: 1, apiBaseURL: scope.apiBaseURL)
        #expect(SchoolLessonSignalOrderFileStore(scope: elsewhere, directory: folder).order(for: lesson) == nil)
        // Un ordre mal formé ne s'écrit pas.
        relaunched.freeze(["Pas Une Clé"], lessonID: lesson)
        #expect(first.order(for: lesson) == ["speed", "vehicle"])
    }

    @Test func onlyAFewRecentLessonsAreKept() {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = PreferencesClock()
        let store = SchoolLessonSignalOrderFileStore(scope: ConfigurationFixture.scope(), directory: folder, now: { clock.now })
        let lessons = (0..<25).map { _ in UUID() }
        for lesson in lessons {
            store.freeze(["speed"], lessonID: lesson)
            clock.now = clock.now.addingTimeInterval(60)
        }
        #expect(lessons.prefix(5).allSatisfy { store.order(for: $0) == nil })
        #expect(lessons.suffix(20).allSatisfy { store.order(for: $0) == ["speed"] })
        // Trois jours plus tard, plus rien n'est une leçon en cours.
        clock.now = clock.now.addingTimeInterval(SchoolLessonSignalOrderFileStore.maximumAge + 1)
        #expect(lessons.allSatisfy { store.order(for: $0) == nil })
        let recent = UUID()
        store.freeze(["vehicle"], lessonID: recent)
        #expect(store.order(for: recent) == ["vehicle"])
    }

    @Test func signingOutRemovesEveryFrozenPalette() {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let scope = ConfigurationFixture.scope(), lesson = UUID()
        SchoolLessonSignalOrderFileStore(scope: scope, directory: folder).freeze(["speed"], lessonID: lesson)
        SchoolLessonSignalOrderFileStore.removeAll(directory: folder)
        #expect(SchoolLessonSignalOrderFileStore(scope: scope, directory: folder).order(for: lesson) == nil)
    }
}
