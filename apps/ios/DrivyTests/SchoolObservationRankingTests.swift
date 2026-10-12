import Foundation
import Testing
@testable import Drivy

/// Classement intelligent des signalements : règle d’ordre, projection, store par adhésion, gel pendant la leçon.
/// Contrat : docs/implementation/classement-intelligent-ios-20261013.md.
struct SchoolObservationRankingOrderTests {
    /// Thèmes synthétiques : la règle ne suppose ni le catalogue ni un nombre de thèmes.
    private static func themes(_ count: Int, hidden: Set<Int> = []) -> [SchoolObservationTheme] {
        (0..<count).map { index in
            SchoolObservationTheme(key: "t\(String(format: "%02d", index + 1))", title: "Thème \(index + 1)",
                competencyKeys: ["c\(index)"], visible: !hidden.contains(index + 1), defaultVisible: true, defaultPosition: index)
        }
    }

    @Test(arguments: [5, 9, 12, 18, 30])
    func everyDisplayedThemeTakesItsRankWhateverTheirNumber(count: Int) {
        let manual = Self.themes(count)
        let order = Array(manual.map(\.key).reversed())
        let arranged = SchoolObservationRankingOrder.arranged(manual, order: order)
        #expect(arranged.map(\.key) == order)
        #expect(arranged.count == count && Set(arranged.map(\.key)) == Set(manual.map(\.key)))
        // Le dernier thème de l’ordre de l’école arrive en tête, même au-delà des neuf premiers.
        #expect(arranged.first?.key == manual.last?.key)
    }

    @Test(arguments: [5, 9, 12, 18, 30])
    func withoutAnOrderTheSchoolOrderIsUntouched(count: Int) {
        let manual = Self.themes(count, hidden: [2])
        #expect(SchoolObservationRankingOrder.arranged(manual, order: nil) == manual)
        #expect(SchoolObservationRankingOrder.arranged(manual, order: []) == manual)
    }

    @Test func theSeventeenthThemeOfTheSchoolCanBeRankedSecond() {
        let manual = Self.themes(18)
        var order = manual.map(\.key)
        let seventeenth = order.remove(at: 16)
        order.insert(seventeenth, at: 1)
        let arranged = SchoolObservationRankingOrder.arranged(manual, order: order)
        #expect(arranged[1].key == "t17" && arranged[0].key == "t01" && arranged[2].key == "t02")
        #expect(arranged.map(\.key) == order)
        // L’ordre de l’école, lui, n’a pas bougé.
        #expect(manual[16].key == "t17")
    }

    @Test func anUnknownADuplicatedOrAHiddenKeyIsIgnored() {
        let manual = Self.themes(6, hidden: [3])
        let arranged = SchoolObservationRankingOrder.arranged(manual, order: ["t05", "inconnu", "t03", "t05", "t01", "t02", "t04", "t06"])
        #expect(arranged.map(\.key) == ["t05", "t01", "t02", "t04", "t06", "t03"])
        #expect(arranged.count == manual.count)
    }

    @Test func aDisplayedThemeMissingFromTheOrderGoesAfterTheRankedOnes() {
        let manual = Self.themes(9)
        // « t02 » et « t07 » affichés depuis le dernier classement : en fin, dans l’ordre de l’école.
        let arranged = SchoolObservationRankingOrder.arranged(manual, order: ["t09", "t08", "t06", "t05", "t04", "t03", "t01"])
        #expect(arranged.map(\.key) == ["t09", "t08", "t06", "t05", "t04", "t03", "t01", "t02", "t07"])
    }

    @Test func hiddenThemesStayBehindInTheSchoolOrder() {
        let manual = Self.themes(12, hidden: [1, 6, 11])
        let displayed = manual.filter(\.visible).map(\.key)
        let arranged = SchoolObservationRankingOrder.arranged(manual, order: Array(displayed.reversed()))
        #expect(Array(arranged.map(\.key).prefix(9)) == Array(displayed.reversed()))
        #expect(Array(arranged.map(\.key).suffix(3)) == ["t01", "t06", "t11"])
        #expect(arranged.prefix(9).allSatisfy(\.visible) && arranged.suffix(3).allSatisfy { !$0.visible })
    }

    @Test func theCatalogueOfTheAppIsArrangedLikeAnyOtherList() {
        let manual = SchoolObservationThemeCatalog.embedded
        let displayed = manual.filter(\.visible).map(\.key)
        var order = displayed
        order.swapAt(0, 11)
        let arranged = SchoolObservationRankingOrder.arranged(manual, order: order)
        #expect(arranged.first?.key == "indicators" && arranged[11].key == "vehicle")
        #expect(Array(arranged.map(\.key).suffix(6)) == Array(manual.map(\.key).suffix(6)))
    }
}

struct SchoolObservationRankingProjectionTests {
    private let scope = ConfigurationFixture.scope()

    private func ranking(school: UUID? = nil, id: UUID? = nil, membership: UUID? = nil, version: Int = 2,
                         mode: SchoolObservationRankingMode = .smart, order: [String] = ["speed", "vehicle"],
                         rankedOn: String? = "2026-10-12") -> SchoolObservationRanking {
        SchoolObservationRanking(id: id ?? ConfigurationFixture.membershipID, schoolId: school ?? ConfigurationFixture.schoolID,
            membershipId: membership ?? ConfigurationFixture.membershipID, version: version, mode: mode, order: order, rankedOn: rankedOn)
    }

    @Test func aProjectionOfThisMembershipIsAccepted() {
        #expect(ranking().isValid(for: scope))
        #expect(ranking(version: 1, mode: .manual, order: [], rankedOn: nil).isValid(for: scope))
    }

    @Test func anotherSchoolOrAnotherMembershipIsRefused() {
        #expect(!ranking(school: UUID()).isValid(for: scope))
        #expect(!ranking(membership: UUID()).isValid(for: scope))
        #expect(!ranking(id: UUID()).isValid(for: scope))
        #expect(!ranking(id: ConfigurationFixture.schoolID).isValid(for: scope))
    }

    @Test func aMalformedOrDuplicatedKeyIsRefused() {
        for key in ["", "Speed", "9speed", "-speed", "speed_limit", "vitesse é", String(repeating: "a", count: 41)] {
            #expect(!ranking(order: ["vehicle", key]).isValid(for: scope), "\(key)")
        }
        #expect(ranking(order: ["a", "right-priority", "t01", String(repeating: "a", count: 40)]).isValid(for: scope))
        #expect(!ranking(order: ["speed", "vehicle", "speed"]).isValid(for: scope))
    }

    @Test func theOrderIsEmptyInManualModeAndBoundedInSmartMode() {
        #expect(!ranking(mode: .manual, order: ["speed"]).isValid(for: scope))
        #expect(!ranking(mode: .smart, order: []).isValid(for: scope))
        #expect(ranking(order: (0..<64).map { "k\($0)" }).isValid(for: scope))
        #expect(!ranking(order: (0..<65).map { "k\($0)" }).isValid(for: scope))
        #expect(!ranking(version: 0).isValid(for: scope))
        #expect(!ranking(rankedOn: "12.10.2026").isValid(for: scope))
    }

    @Test func theProjectionAndTheBodyUseTheNamesOfTheContract() throws {
        let bytes = Data("""
        {"id":"\(ConfigurationFixture.membershipID.uuidString)","schoolId":"\(ConfigurationFixture.schoolID.uuidString)",\
        "membershipId":"\(ConfigurationFixture.membershipID.uuidString)","version":1,"mode":"MANUAL","order":[],"rankedOn":null}
        """.utf8)
        let decoded = try JSONDecoder().decode(SchoolObservationRanking.self, from: bytes)
        #expect(decoded.mode == .manual && decoded.order.isEmpty && decoded.rankedOn == nil && decoded.isValid(for: scope))
        let operation = UUID()
        let encoded = try JSONEncoder().encode(SchoolObservationRankingBody(operationId: operation, mode: .smart))
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == ["operationId", "mode"] && object["mode"] as? String == "SMART")
        #expect(UUID(uuidString: object["operationId"] as? String ?? "") == operation)
    }
}

/// Copie locale en mémoire.
@MainActor private final class RankingCacheStub: SchoolObservationRankingCache {
    var stored: SchoolObservationRanking?
    var writes = 0
    func read(scope: SchoolCommandScope) -> SchoolObservationRanking? { stored }
    func write(_ ranking: SchoolObservationRanking, scope: SchoolCommandScope) { stored = ranking; writes += 1 }
    func remove(scope: SchoolCommandScope) { stored = nil }
}

/// Horloge réglable du stockage des ordres figés.
@MainActor private final class RankingClock {
    var now = Date(timeIntervalSince1970: 1_791_000_000)
}

/// École synthétique : le classement d’une adhésion et la configuration des signalements, tous deux versionnés.
/// Elle refuse une version périmée et rejoue une opération déjà appliquée sans second effet, comme le contrat le dit.
private actor RankingSchool: SchoolHTTPTransport {
    struct RankingWrite: Sendable {
        let operation: UUID
        let ifMatch: String?
        let idempotencyKey: String?
        let mode: SchoolObservationRankingMode
    }
    static let displayedKeys = SchoolObservationThemeCatalog.embedded.filter(\.visible).map(\.key)

    private let schoolID: UUID
    private let membershipID: UUID
    private var version = 1
    private var mode: SchoolObservationRankingMode
    private var order: [String]
    private var themes: SchoolObservationThemeSettings
    private var offline = false
    private var missing = false
    private var losesNextAnswer = false
    private var applied: Set<UUID> = []
    private(set) var rankingWrites: [RankingWrite] = []
    private(set) var themeWrites: [[String]] = []

    /// `order` : ce que l’école a calculé pour ce moniteur ; elle ne le rend qu’en mode `SMART`.
    init(schoolID: UUID = ConfigurationFixture.schoolID, membershipID: UUID = ConfigurationFixture.membershipID,
         mode: SchoolObservationRankingMode = .manual, order: [String]? = nil) {
        self.schoolID = schoolID; self.membershipID = membershipID; self.mode = mode
        self.order = order ?? Array(Self.displayedKeys.reversed())
        themes = SchoolObservationThemeSettings(id: schoolID, schoolId: schoolID, version: 1, canManage: true,
                                                themes: SchoolObservationThemeCatalog.embedded)
    }

    func setOffline(_ value: Bool) { offline = value }
    func removeRoute() { missing = true }
    func loseNextAnswer() { losesNextAnswer = true }
    /// Le classement du lendemain : un autre ordre, sans changement de mode ni de version.
    func rank(_ value: [String]) { order = value }
    /// Le même moniteur règle le classement depuis un autre appareil.
    func changeElsewhere(to value: SchoolObservationRankingMode) { mode = value; version += 1 }

    private func projection() -> [String: Any] {
        ["id": membershipID.uuidString, "schoolId": schoolID.uuidString, "membershipId": membershipID.uuidString,
         "version": version, "mode": mode.rawValue, "order": mode == .smart ? order : [String](),
         "rankedOn": mode == .smart ? "2026-10-12" as Any : NSNull()]
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        func envelope(_ data: Any) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data, "requestId": UUID().uuidString,
                "serverTime": "2026-10-13T08:00:00Z"]), status: 200, url: url, contentType: "application/json")
        }
        func problem(_ status: Int, _ code: String) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["code": code]), status: status, url: url,
                contentType: "application/problem+json")
        }
        if url.path == "/v1/me" {
            let membership: [String: Any] = ["membershipId": membershipID.uuidString, "schoolId": schoolID.uuidString,
                "schoolName": "École de test", "roles": ["INSTRUCTOR"], "grants": ["MANAGE_OBSERVATION_THEMES"], "accessEpoch": 1]
            return try envelope(["personId": ConfigurationFixture.personID.uuidString, "version": 1, "displayName": "Moniteur de test",
                "locale": "fr-CH", "memberships": [membership]] as [String: Any])
        }
        switch url.lastPathComponent {
        case "observation-ranking":
            if missing { return try problem(404, "NOT_FOUND") }
            if request.httpMethod == "PUT" {
                let body = try JSONDecoder().decode(SchoolObservationRankingBody.self, from: request.httpBody ?? Data())
                rankingWrites.append(RankingWrite(operation: body.operationId, ifMatch: request.value(forHTTPHeaderField: "If-Match"),
                    idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key"), mode: body.mode))
                if offline { throw URLError(.notConnectedToInternet) }
                guard let match = request.value(forHTTPHeaderField: "If-Match") else { return try problem(428, "PRECONDITION_REQUIRED") }
                if !applied.contains(body.operationId) {
                    guard match == "\"\(version)\"" else { return try problem(412, "VERSION_CONFLICT") }
                    mode = body.mode
                    version += 1
                    applied.insert(body.operationId)
                }
                // Écriture faite, réponse perdue : l’app ne sait pas ce qu’il en est.
                if losesNextAnswer { losesNextAnswer = false; throw URLError(.networkConnectionLost) }
            } else if offline {
                throw URLError(.notConnectedToInternet)
            }
            return try envelope(projection())
        case "observation-themes":
            if request.httpMethod == "PUT" {
                let body = try JSONDecoder().decode(SchoolObservationThemesBody.self, from: request.httpBody ?? Data())
                themeWrites.append(body.themes.map(\.key))
                if offline { throw URLError(.notConnectedToInternet) }
                guard request.value(forHTTPHeaderField: "If-Match") == "\"\(themes.version)\"" else { return try problem(412, "VERSION_CONFLICT") }
                let known = Dictionary(uniqueKeysWithValues: themes.themes.map { ($0.key, $0) })
                let next = body.themes.compactMap { entry -> SchoolObservationTheme? in
                    guard var theme = known[entry.key] else { return nil }
                    theme.visible = entry.visible
                    return theme
                }
                themes = SchoolObservationThemeSettings(id: schoolID, schoolId: schoolID, version: themes.version + 1,
                                                        canManage: true, themes: next)
            } else if offline {
                throw URLError(.notConnectedToInternet)
            }
            return try envelope(JSONSerialization.jsonObject(with: JSONEncoder().encode(themes)))
        default:
            return try problem(404, "NOT_FOUND")
        }
    }
}

@MainActor struct SchoolObservationRankingStoreTests {
    private func store(_ school: RankingSchool, scope: SchoolCommandScope? = nil,
                       cache: (any SchoolObservationRankingCache)? = nil) -> SchoolObservationRankingStore {
        let scope = scope ?? ConfigurationFixture.scope()
        let client = SchoolObservationRankingClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: school)
        let storage: any SchoolObservationRankingCache
        if let cache { storage = cache } else { storage = RankingCacheStub() }
        return SchoolObservationRankingStore(scope: scope, client: client, cache: storage)
    }

    private func settled(_ store: SchoolObservationRankingStore) async throws {
        try await HubFixture.wait { !store.isSaving }
    }

    @Test func beforeAnyAnswerTheSchoolOrderAppliesAndNothingCanBeSet() async {
        let school = RankingSchool()
        let model = store(school)
        #expect(model.ranking == nil && model.mode == .manual && model.effectiveOrder == nil && !model.isAvailable)
        model.setSmart(true)
        #expect(model.proposal == nil && !model.isSaving && model.displayedMode == .manual)
        let writes = await school.rankingWrites
        #expect(writes.isEmpty)
    }

    @Test func aReadMakesTheSettingAvailableAndKeepsACopy() async {
        let school = RankingSchool(), cache = RankingCacheStub()
        let model = store(school, cache: cache)
        let read = await model.refresh()
        #expect(read && model.isAvailable && model.mode == .manual && model.effectiveOrder == nil)
        #expect(model.ranking?.version == 1 && model.failureMessage == nil && model.notice == nil)
        #expect(cache.writes == 1 && cache.stored == model.ranking)
    }

    @Test func aSchoolThatDoesNotKnowTheRouteLeavesTheSettingAbsentWithoutAnyMessage() async {
        let school = RankingSchool(), cache = RankingCacheStub()
        await school.removeRoute()
        // Une copie d’avant (école revenue à une version plus ancienne) ne garde pas un ordre automatique.
        cache.stored = SchoolObservationRanking(id: ConfigurationFixture.membershipID, schoolId: ConfigurationFixture.schoolID,
            membershipId: ConfigurationFixture.membershipID, version: 4, mode: .smart, order: ["speed", "vehicle"], rankedOn: "2026-10-12")
        let model = store(school, cache: cache)
        #expect(model.effectiveOrder == ["speed", "vehicle"] && !model.isAvailable)
        let read = await model.refresh()
        #expect(!read && !model.isAvailable && model.failureMessage == nil && model.notice == nil)
        #expect(model.ranking == nil && model.effectiveOrder == nil && cache.stored == nil)
        model.setSmart(true)
        #expect(model.proposal == nil)
    }

    @Test func activatingShowsTheProposalThenTheOrderTheSchoolConfirms() async throws {
        let school = RankingSchool(), cache = RankingCacheStub()
        let model = store(school, cache: cache)
        await model.refresh()
        model.setSmart(true)
        // Dans le tour du geste : l’interrupteur montre la proposition, rien n’est encore confirmé.
        #expect(model.displayedMode == .smart && model.mode == .manual && model.isSaving && model.effectiveOrder == nil)
        try await settled(model)
        #expect(model.mode == .smart && model.proposal == nil && model.ranking?.version == 2 && model.failureMessage == nil)
        #expect(model.effectiveOrder == Array(RankingSchool.displayedKeys.reversed()) && model.confirmedChanges == 1)
        #expect(cache.stored?.mode == .smart && cache.stored?.version == 2)
        let writes = await school.rankingWrites
        #expect(writes.count == 1 && writes[0].ifMatch == "\"1\"" && writes[0].mode == .smart)
        #expect(writes[0].idempotencyKey == writes[0].operation.uuidString)
        // Désactiver rend l’ordre de l’école : plus aucun ordre automatique.
        model.setSmart(false)
        try await settled(model)
        #expect(model.mode == .manual && model.effectiveOrder == nil && model.ranking?.version == 3 && model.confirmedChanges == 2)
        let later = await school.rankingWrites
        #expect(later.count == 2 && later[1].ifMatch == "\"2\"" && later[1].mode == .manual)
    }

    @Test func aFailedSendReturnsToTheConfirmedStateAndRetriesTheSameOperation() async throws {
        let school = RankingSchool()
        let model = store(school)
        await model.refresh()
        let confirmed = model.ranking
        await school.setOffline(true)
        model.setSmart(true)
        #expect(model.displayedMode == .smart)
        try await HubFixture.wait { model.failureMessage != nil }
        #expect(model.failureMessage == SchoolObservationRankingStore.unsavedMessage && !model.isSaving)
        #expect(model.displayedMode == .manual && model.proposal == nil && model.ranking == confirmed && model.confirmedChanges == 0)
        #expect(model.canRetry)
        await school.setOffline(false)
        model.retry()
        #expect(model.displayedMode == .smart && model.failureMessage == nil)
        try await settled(model)
        #expect(model.mode == .smart && model.ranking?.version == 2 && !model.canRetry)
        let writes = await school.rankingWrites
        #expect(writes.count == 2 && writes[0].operation == writes[1].operation && writes[1].ifMatch == "\"1\"")
    }

    @Test func anUnknownResultIsReplayedWithTheSameOperationAndHasNoDoubleEffect() async throws {
        let school = RankingSchool()
        let model = store(school)
        await model.refresh()
        // L’école applique le changement, sa réponse se perd.
        await school.loseNextAnswer()
        model.setSmart(true)
        try await HubFixture.wait { model.failureMessage != nil }
        #expect(model.mode == .manual && model.ranking?.version == 1 && model.canRetry)
        model.retry()
        try await settled(model)
        #expect(model.mode == .smart && model.ranking?.version == 2 && model.failureMessage == nil)
        let writes = await school.rankingWrites
        #expect(writes.count == 2 && writes[0].operation == writes[1].operation)
        #expect(writes[0].ifMatch == "\"1\"" && writes[1].ifMatch == "\"1\"")
    }

    @Test func aVersionConflictRereadsShowsTheCurrentStateAndSaysItHadChanged() async throws {
        let school = RankingSchool()
        let model = store(school)
        await model.refresh()
        await school.changeElsewhere(to: .smart)
        model.setSmart(true)
        try await HubFixture.wait { model.notice != nil }
        #expect(model.notice == SchoolObservationRankingStore.changedNotice && model.failureMessage == nil && !model.isSaving)
        #expect(model.proposal == nil && model.mode == .smart && model.ranking?.version == 2 && !model.canRetry)
        // Le changement refusé n’a rien écrit ; un nouveau geste part de la version relue.
        model.setSmart(false)
        #expect(model.notice == nil)
        try await settled(model)
        #expect(model.mode == .manual && model.ranking?.version == 3)
        let writes = await school.rankingWrites
        #expect(writes.count == 2 && writes[0].ifMatch == "\"1\"" && writes[1].ifMatch == "\"2\"")
    }

    @Test func theLocalCopyGivesTheModeAndTheOrderAtLaunchBeforeTheSchoolAnswers() async throws {
        let school = RankingSchool(), cache = RankingCacheStub()
        let first = store(school, cache: cache)
        await first.refresh()
        first.setSmart(true)
        try await settled(first)
        // Autre lancement, école injoignable : « Signaler » garde l’ordre automatique, le réglage attend l’école.
        await school.setOffline(true)
        let relaunched = store(school, cache: cache)
        #expect(relaunched.mode == .smart && relaunched.effectiveOrder == first.effectiveOrder && !relaunched.isAvailable)
        let read = await relaunched.refresh()
        #expect(!read && relaunched.mode == .smart && relaunched.effectiveOrder == first.effectiveOrder)
        #expect(!relaunched.isAvailable && relaunched.failureMessage == nil)
    }

    @Test func twoMembershipsAndTwoSchoolsNeverShareTheirRanking() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ranking-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let mine = ConfigurationFixture.scope()
        let colleague = SchoolCommandScope(personID: UUID(), schoolID: mine.schoolID, membershipID: UUID(),
                                           accessEpoch: 1, apiBaseURL: mine.apiBaseURL)
        let otherSchoolID = UUID(), otherMembershipID = UUID()
        let elsewhere = SchoolCommandScope(personID: mine.personID, schoolID: otherSchoolID, membershipID: otherMembershipID,
                                           accessEpoch: 1, apiBaseURL: mine.apiBaseURL)
        let school = RankingSchool()
        let other = RankingSchool(schoolID: otherSchoolID, membershipID: otherMembershipID)
        let first = store(school, cache: SchoolObservationRankingFileCache(directory: directory))
        let second = store(other, scope: elsewhere, cache: SchoolObservationRankingFileCache(directory: directory))
        await first.refresh()
        await second.refresh()
        first.setSmart(true)
        try await settled(first)
        // Deux stores, deux fichiers : le mien est passé en automatique, l’autre école n’a pas bougé.
        #expect(first.mode == .smart && second.mode == .manual && second.effectiveOrder == nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(files == ["\(mine.schoolID.uuidString.lowercased())-\(mine.membershipID.uuidString.lowercased()).json",
                          "\(otherSchoolID.uuidString.lowercased())-\(otherMembershipID.uuidString.lowercased()).json"].sorted())
        let cache = SchoolObservationRankingFileCache(directory: directory)
        #expect(cache.read(scope: mine)?.mode == .smart && cache.read(scope: elsewhere)?.mode == .manual)
        // Un collègue de la même école n’a aucune copie : son ordre reste celui de l’école.
        #expect(cache.read(scope: colleague) == nil)
        let server = SchoolCommandScope(personID: mine.personID, schoolID: mine.schoolID, membershipID: mine.membershipID,
                                        accessEpoch: 1, apiBaseURL: "https://autre.example.invalid")
        #expect(cache.read(scope: server) == nil)
        cache.remove(scope: mine)
        #expect(cache.read(scope: mine) == nil && cache.read(scope: elsewhere) != nil)
    }
}

@MainActor struct SchoolLessonSignalOrderStoreTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("signal-orders-\(UUID().uuidString)")
    }

    @Test func aFrozenOrderSurvivesANewInstanceAndBelongsToItsMembership() {
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
        let elsewhere = SchoolCommandScope(personID: scope.personID, schoolID: UUID(), membershipID: scope.membershipID,
                                           accessEpoch: 1, apiBaseURL: scope.apiBaseURL)
        #expect(SchoolLessonSignalOrderFileStore(scope: elsewhere, directory: folder).order(for: lesson) == nil)
        // Un ordre mal formé ne s’écrit pas.
        relaunched.freeze(["Pas Une Clé"], lessonID: lesson)
        #expect(first.order(for: lesson) == ["speed", "vehicle"])
    }

    @Test func onlyAFewRecentLessonsAreKept() {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = RankingClock()
        let store = SchoolLessonSignalOrderFileStore(scope: ConfigurationFixture.scope(), directory: folder, now: { clock.now })
        let lessons = (0..<25).map { _ in UUID() }
        for lesson in lessons {
            store.freeze(["speed"], lessonID: lesson)
            clock.now = clock.now.addingTimeInterval(60)
        }
        #expect(lessons.prefix(5).allSatisfy { store.order(for: $0) == nil })
        #expect(lessons.suffix(20).allSatisfy { store.order(for: $0) == ["speed"] })
        // Trois jours plus tard, plus rien n’est une leçon en cours.
        clock.now = clock.now.addingTimeInterval(SchoolLessonSignalOrderFileStore.maximumAge + 1)
        #expect(lessons.allSatisfy { store.order(for: $0) == nil })
        let recent = UUID()
        store.freeze(["vehicle"], lessonID: recent)
        #expect(store.order(for: recent) == ["vehicle"])
    }
}

/// Référentiel d’une leçon pour l’enregistreur : les neuf compétences fournies aux écoles, que les douze
/// thèmes affichés à l’origine précisent toutes (aucune tuile générique).
private actor RankingLessonTransport: SchoolHTTPTransport {
    static let offeringID = UUID(uuidString: "72000000-0000-4000-8000-000000000002")!
    static let curriculumID = UUID(uuidString: "72000000-0000-4000-8000-000000000003")!
    static func competency(_ number: Int, _ key: String, _ label: String) -> SchoolCatalogCompetency {
        SchoolCatalogCompetency(id: UUID(uuidString: "72000000-0000-4000-8000-0000000001\(String(format: "%02d", number))")!,
            schoolId: HubFixture.schoolID, version: 1, curriculumVersionId: curriculumID, key: key, label: label,
            description: "", sortOrder: number)
    }
    static let competencies = [competency(1, "vehicule", "Maîtrise du véhicule"), competency(2, "observation", "Observation et contrôles"),
        competency(3, "priorites", "Priorités"), competency(4, "intersections", "Intersections et giratoires"),
        competency(5, "vitesse", "Adaptation de la vitesse"), competency(6, "placement", "Placement sur la chaussée"),
        competency(7, "manoeuvres", "Manœuvres"), competency(8, "autoroute", "Autoroute"),
        competency(9, "anticipation", "Anticipation et partage de la route")]
    private let fallback = HubServer()

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        func response(_ value: some Encodable) throws -> SchoolHTTPResponse {
            var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            if value is SchoolTraining, var training = data as? [String: Any] {
                training["startedOn"] = NSNull(); training["closedOn"] = NSNull(); data = training
            }
            if var page = data as? [String: Any], page["items"] != nil {
                page["nextCursor"] = NSNull(); data = page
            }
            return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data,
                "requestId": UUID().uuidString, "serverTime": "2026-10-13T08:00:00Z"]), status: 200, url: url, contentType: "application/json")
        }
        if url.pathComponents.dropLast().last == "trainings" {
            return try response(SchoolTraining(id: HubFixture.trainingID, schoolId: HubFixture.schoolID,
                learnerId: HubFixture.learnerID, offeringId: Self.offeringID, version: 1, categoryCode: "B",
                status: "ACTIVE", startedOn: nil, closedOn: nil))
        }
        if url.lastPathComponent == "offerings" {
            return try response(SchoolPage(items: [SchoolOffering(id: Self.offeringID, schoolId: HubFixture.schoolID,
                version: 1, offeringKey: "B", categoryCode: "B", curriculumVersionId: Self.curriculumID,
                policyVersionId: UUID(), enabled: true, defaultDurationMinutes: 50, defaultPriceCents: 9000)], nextCursor: nil))
        }
        if url.lastPathComponent == "curricula" {
            return try response(SchoolPage(items: [SchoolCurriculum(id: Self.curriculumID, schoolId: HubFixture.schoolID,
                version: 1, categoryCode: "B", revision: 1, approved: true, competencies: Self.competencies)], nextCursor: nil))
        }
        return try await fallback.send(request)
    }
}

/// L’ordre automatique est pris une fois par leçon : il ne bouge plus jusqu’à sa fin.
@MainActor struct SchoolLiveObservationRankingFreezeTests {
    private static let manual = RankingSchool.displayedKeys
    private static let first = Array(RankingSchool.displayedKeys.reversed())
    /// Le classement du lendemain : « Clignotants » passe en tête.
    private static let second = ["indicators"] + RankingSchool.displayedKeys.filter { $0 != "indicators" }

    private func rankingStore(_ school: RankingSchool) -> SchoolObservationRankingStore {
        let scope = ConfigurationFixture.scope()
        return SchoolObservationRankingStore(scope: scope, client: SchoolObservationRankingClient(baseURL: URL(string: scope.apiBaseURL)!,
            tokenSource: HubToken(), transport: school), cache: RankingCacheStub())
    }

    private func themeStore(_ school: RankingSchool) -> SchoolObservationThemeStore {
        let scope = ConfigurationFixture.scope()
        return SchoolObservationThemeStore(scope: scope, client: SchoolObservationThemeClient(baseURL: URL(string: scope.apiBaseURL)!,
            tokenSource: HubToken(), transport: school), cache: RankingThemeCacheStub())
    }

    private func recorder(themes: SchoolObservationThemeStore, ranking: SchoolObservationRankingStore?,
                          orders: (any SchoolLessonSignalOrderStore)?, lessonID: UUID = HubFixture.lessonID) -> SchoolLiveObservationRecorder {
        let client = SchoolObservationClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: RankingLessonTransport())
        return SchoolLiveObservationRecorder(scope: ConfigurationFixture.scope(), lessonID: lessonID, client: client,
            themeStore: themes, rankingStore: ranking, signalOrders: orders, outbox: ConfigurationOutboxStub())
    }

    /// École en mode automatique, lue une première fois par les deux stores.
    private func smartSchool() async -> (school: RankingSchool, themes: SchoolObservationThemeStore, ranking: SchoolObservationRankingStore) {
        let school = RankingSchool(mode: .smart, order: Self.first)
        let themes = themeStore(school), ranking = rankingStore(school)
        await themes.refresh()
        await ranking.refresh()
        return (school, themes, ranking)
    }

    private func reranked(_ school: RankingSchool, _ ranking: SchoolObservationRankingStore) async throws {
        await school.rank(Self.second)
        try await HubFixture.wait {
            await ranking.refresh()
            return ranking.effectiveOrder == Self.second
        }
    }

    @Test func inManualModeTilesKeepTheSchoolOrderAndNothingIsFrozen() async {
        let school = RankingSchool()
        let themes = themeStore(school), ranking = rankingStore(school)
        await themes.refresh()
        await ranking.refresh()
        let orders = SchoolLessonSignalOrderMemoryStore()
        let model = recorder(themes: themes, ranking: ranking, orders: orders)
        await model.loadCompetencies()
        model.openPalette()
        #expect(model.signalOrder == nil && orders.order(for: HubFixture.lessonID) == nil)
        #expect(model.themes.compactMap(\.key) == Self.manual)
        model.stop()
    }

    @Test func theOrderIsFrozenAtTheFirstOpeningAndALaterRankingMovesNothing() async throws {
        let (school, themes, ranking) = await smartSchool()
        let orders = SchoolLessonSignalOrderMemoryStore()
        let model = recorder(themes: themes, ranking: ranking, orders: orders)
        await model.loadCompetencies()
        // Rien n’est figé avant la première ouverture de « Signaler ».
        #expect(orders.order(for: HubFixture.lessonID) == nil)
        model.openPalette()
        #expect(orders.order(for: HubFixture.lessonID) == Self.first && model.signalOrder == Self.first)
        #expect(model.themes.compactMap(\.key) == Self.first && model.themes.count == 12)
        // L’école reclasse (le lendemain) ; la relecture le rapporte au store.
        try await reranked(school, ranking)
        model.openPalette()
        #expect(model.signalOrder == Self.first && model.themes.compactMap(\.key) == Self.first)
        #expect(orders.order(for: HubFixture.lessonID) == Self.first)
        model.stop()
    }

    @Test func aNewRecorderForTheSameLessonFindsTheSameOrderAndAnotherLessonTakesTheNewOne() async throws {
        let (school, themes, ranking) = await smartSchool()
        let orders = SchoolLessonSignalOrderMemoryStore()
        let model = recorder(themes: themes, ranking: ranking, orders: orders)
        model.openPalette()
        model.stop()
        try await reranked(school, ranking)
        // Leçon interrompue puis reprise : un autre enregistreur, la même leçon, le même ordre dès sa création.
        let resumed = recorder(themes: themes, ranking: ranking, orders: orders)
        #expect(resumed.signalOrder == Self.first)
        await resumed.loadCompetencies()
        resumed.openPalette()
        #expect(resumed.signalOrder == Self.first && resumed.themes.compactMap(\.key) == Self.first)
        resumed.stop()
        // La leçon suivante part du dernier classement, sans toucher à celui de la première.
        let nextLesson = UUID()
        let next = recorder(themes: themes, ranking: ranking, orders: orders, lessonID: nextLesson)
        next.openPalette()
        #expect(next.signalOrder == Self.second && orders.order(for: nextLesson) == Self.second)
        #expect(orders.order(for: HubFixture.lessonID) == Self.first)
        next.stop()
    }

    @Test func theFrozenOrderSurvivesTheAppBeingKilled() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("signal-orders-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let (school, themes, ranking) = await smartSchool()
        let scope = ConfigurationFixture.scope()
        let model = recorder(themes: themes, ranking: ranking, orders: SchoolLessonSignalOrderFileStore(scope: scope, directory: folder))
        model.openPalette()
        model.stop()
        try await reranked(school, ranking)
        // Nouveau processus : nouveau stockage sur le même fichier, nouvel enregistreur.
        let relaunched = recorder(themes: themes, ranking: ranking, orders: SchoolLessonSignalOrderFileStore(scope: scope, directory: folder))
        relaunched.openPalette()
        #expect(relaunched.signalOrder == Self.first)
        relaunched.stop()
    }

    @Test func withoutAStorageTheOrderStillHoldsForThisRecorder() async throws {
        let (school, themes, ranking) = await smartSchool()
        let model = recorder(themes: themes, ranking: ranking, orders: nil)
        model.openPalette()
        try await reranked(school, ranking)
        model.openPalette()
        #expect(model.signalOrder == Self.first)
        model.stop()
    }

    @Test func switchingToManualDuringTheLessonAppliesAtTheNextOpeningAndKeepsTheFrozenOrderAside() async throws {
        let (school, themes, ranking) = await smartSchool()
        let orders = SchoolLessonSignalOrderMemoryStore()
        let model = recorder(themes: themes, ranking: ranking, orders: orders)
        await model.loadCompetencies()
        model.openPalette()
        #expect(model.themes.compactMap(\.key) == Self.first)
        // Geste volontaire du moniteur, dans les Paramètres, pendant la leçon.
        ranking.setSmart(false)
        try await HubFixture.wait { !ranking.isSaving && ranking.mode == .manual }
        // La palette déjà ouverte ne bouge pas ; l’ordre de l’école s’applique à l’ouverture suivante.
        #expect(model.themes.compactMap(\.key) == Self.first)
        model.openPalette()
        #expect(model.signalOrder == nil && model.themes.compactMap(\.key) == Self.manual)
        // De retour en automatique pendant la même leçon : l’ordre figé, pas celui du jour.
        await school.rank(Self.second)
        ranking.setSmart(true)
        try await HubFixture.wait { !ranking.isSaving && ranking.mode == .smart }
        #expect(ranking.effectiveOrder == Self.second)
        model.openPalette()
        #expect(model.signalOrder == Self.first && model.themes.compactMap(\.key) == Self.first)
        model.stop()
    }

    /// Masquer ou afficher un thème depuis le gel : le masqué disparaît à l’ouverture suivante, l’affiché arrive en
    /// fin. Et l’écriture faite depuis le mode automatique envoie l’ordre de l’école, jamais l’ordre automatique.
    @Test func aThemeHiddenOrDisplayedSinceTheFreezeLeavesOrJoinsTheEndAndTheSchoolOrderIsSentIntact() async throws {
        let (school, themes, ranking) = await smartSchool()
        let orders = SchoolLessonSignalOrderMemoryStore()
        let model = recorder(themes: themes, ranking: ranking, orders: orders)
        await model.loadCompetencies()
        model.openPalette()
        let speed = try #require(model.themes.first { $0.key == "speed" })
        // L’écran de réglage, en ordre automatique : la liste montrée n’est pas celle qui part.
        let shown = SchoolObservationRankingOrder.arranged(themes.displayed, order: ranking.effectiveOrder)
        #expect(shown.map(\.key) != themes.displayed.map(\.key))
        themes.setVisible(false, key: "speed")
        themes.setVisible(true, key: "braking")
        try await HubFixture.wait { themes.saveState != .saving }
        #expect(themes.saveState == .saved)
        let writes = await school.themeWrites
        #expect(!writes.isEmpty && writes.allSatisfy { $0 == SchoolObservationThemeCatalog.embedded.map(\.key) })
        #expect(themes.configuration.themes.map(\.key) == SchoolObservationThemeCatalog.embedded.map(\.key))
        // La palette ouverte garde ses tuiles ; l’ouverture suivante suit l’affichage, dans l’ordre figé.
        #expect(model.themes.compactMap(\.key) == Self.first)
        model.openPalette()
        #expect(model.signalOrder == Self.first)
        #expect(model.themes.compactMap(\.key) == Self.first.filter { $0 != "speed" } + ["braking"])
        // Masquer n’est qu’un réglage d’affichage : le thème choisi avant reste recevable.
        #expect(model.record(theme: speed, status: .attention, at: HubFixture.date("2026-10-13T08:00:00Z")))
        model.stop()
    }
}

/// Copie locale des thèmes en mémoire, propre à cette suite.
@MainActor private final class RankingThemeCacheStub: SchoolObservationThemeCache {
    var stored: SchoolObservationThemeConfiguration?
    func read(scope: SchoolCommandScope) -> SchoolObservationThemeConfiguration? { stored }
    func write(_ configuration: SchoolObservationThemeConfiguration, scope: SchoolCommandScope) { stored = configuration }
}
