import Foundation
import SwiftUI
import Testing
@testable import Drivy

/// Signalements configurables : catalogue, tuiles d’une leçon, corps envoyé, disposition de la grille.
/// Contrat : docs/implementation/signalements-configurables-20261012.md.
struct SchoolObservationThemeCatalogTests {
    @Test func embeddedCatalogIsTheOneOfTheContract() {
        let catalog = SchoolObservationThemeCatalog.embedded
        #expect(catalog.map(\.key) == ["vehicle", "observation", "right-priority", "signage", "give-way", "intersections",
            "speed", "placement", "manoeuvres", "motorway", "anticipation", "indicators", "following-distance", "braking", "lane-change",
            "moving-off", "bends", "eco-driving"])
        #expect(catalog.map(\.title) == ["Maîtrise du véhicule", "Observation et contrôles", "Priorité à droite", "Signalisation",
            "Céder le passage", "Intersections et giratoires", "Vitesse", "Placement sur la chaussée", "Manœuvres", "Autoroute",
            "Anticipation", "Clignotants", "Distance de sécurité", "Freinage", "Changement de voie",
            "Démarrage", "Virages", "Éco-conduite"])
        #expect(catalog.map(\.defaultPosition) == Array(catalog.indices))
        #expect(SchoolObservationThemeCatalog.keys.count == catalog.count)
        // Les douze premiers s’affichent à l’origine ; tout thème ajouté ensuite arrive masqué.
        #expect(catalog.allSatisfy { $0.visible == $0.defaultVisible })
        #expect(catalog.filter(\.visible).map(\.key) == Array(catalog.map(\.key).prefix(12)))
        #expect(catalog.first { $0.key == "moving-off" }?.competencyKeys == ["vehicule"])
        #expect(catalog.first { $0.key == "bends" }?.competencyKeys == ["placement"])
        #expect(catalog.first { $0.key == "eco-driving" }?.competencyKeys == ["vehicule"])
        #expect(catalog.first { $0.key == "manoeuvres" }?.competencyKeys == ["manoeuvres", "parking"])
        #expect(catalog.first { $0.key == "motorway" }?.competencyKeys == ["autoroute", "motorway"])
        #expect(catalog.first { $0.key == "indicators" }?.competencyKeys == ["observation"])
        // Chaque clé a son dessin : le résolveur de pictogramme connaît tout le catalogue.
        #expect(Set(catalog.map(\.key)) == Set(SchoolObservationPictogram.allCases.map(\.rawValue)))
    }

    @Test func anUnknownKeyIsIgnoredAndAMissingThemeReturnsToItsOriginalPlace() {
        var received = SchoolObservationThemeCatalog.embedded
        received.swapAt(0, 1)
        received[0].visible = false
        // « speed » manque (position d’origine 6) ; une clé d’un catalogue plus récent arrive en tête.
        received.removeAll { $0.key == "speed" }
        received.insert(SchoolObservationTheme(key: "tunnel", title: "Tunnels", competencyKeys: ["tunnel"], visible: true,
                                               defaultVisible: true, defaultPosition: received.count + 1), at: 0)
        let arranged = SchoolObservationThemeCatalog.arranged(received)
        #expect(arranged.count == SchoolObservationThemeCatalog.embedded.count && !arranged.contains { $0.key == "tunnel" })
        // La clé inconnue n’est pas perdue pour autant : elle sera renvoyée à l’école, en tête comme reçue.
        #expect(SchoolObservationThemeCatalog.foreign(in: received) == [SchoolObservationForeignTheme(key: "tunnel", visible: true, after: nil)])
        #expect(SchoolObservationThemeCatalog.unlisted(in: received) == ["speed"])
        #expect(Array(arranged.map(\.key).prefix(2)) == ["observation", "vehicle"])
        #expect(arranged.firstIndex { $0.key == "speed" } == 6)
        #expect(arranged.first { $0.key == "speed" }?.visible == true)
        #expect(arranged.first { $0.key == "observation" }?.visible == false)
    }

    @Test func aDuplicatedKeyCountsOnceAndAFullyHiddenListFallsBackToTheOrigin() {
        let catalog = SchoolObservationThemeCatalog.embedded
        #expect(SchoolObservationThemeCatalog.arranged(catalog + [catalog[0]]) == catalog)
        var hidden = catalog
        for index in hidden.indices { hidden[index].visible = false }
        #expect(SchoolObservationThemeCatalog.arranged(hidden) == catalog)
    }

    @Test func resetOrderKeepsTheChosenDisplayAndFullResetRestoresTheOrigin() {
        var themes = Array(SchoolObservationThemeCatalog.embedded.reversed())
        themes[0].visible = true // « lane-change », masqué à l’origine
        let ordered = SchoolObservationThemeCatalog.originalOrder(themes)
        #expect(ordered.map(\.key) == SchoolObservationThemeCatalog.embedded.map(\.key))
        #expect(ordered.last?.visible == true)
        #expect(SchoolObservationThemeCatalog.original(themes) == SchoolObservationThemeCatalog.embedded)
    }
}

struct SchoolLiveObservationTileTests {
    private static func competency(_ key: String, _ label: String, _ order: Int) -> SchoolCatalogCompetency {
        SchoolCatalogCompetency(id: UUID(), schoolId: ConfigurationFixture.schoolID, version: 1, curriculumVersionId: UUID(),
                                key: key, label: label, description: "", sortOrder: order)
    }

    /// Le référentiel fourni aux écoles : neuf compétences.
    private static let standard: [SchoolCatalogCompetency] = [
        competency("vehicule", "Maîtrise du véhicule", 1), competency("observation", "Observation et contrôles", 2),
        competency("priorites", "Priorités", 3), competency("intersections", "Intersections et giratoires", 4),
        competency("vitesse", "Adaptation de la vitesse", 5), competency("placement", "Placement sur la chaussée", 6),
        competency("manoeuvres", "Manœuvres", 7), competency("autoroute", "Autoroute", 8),
        competency("anticipation", "Anticipation et partage de la route", 9),
    ]

    @Test func theOriginalConfigurationKeepsTheElevenTitlesInTheirOrderThenAddsIndicators() {
        let tiles = SchoolLiveObservationTheme.tiles(for: SchoolObservationThemeCatalog.embedded, competencies: Self.standard)
        // « Vitesse » et « Anticipation » restent les titres courts, pas le libellé de la compétence.
        #expect(tiles.map(\.title) == ["Maîtrise du véhicule", "Observation et contrôles", "Priorité à droite", "Signalisation",
            "Céder le passage", "Intersections et giratoires", "Vitesse", "Placement sur la chaussée", "Manœuvres", "Autoroute",
            "Anticipation", "Clignotants"])
        #expect(tiles.allSatisfy { $0.key != nil })
        #expect(Set(tiles.map(\.id)).count == tiles.count)
        #expect(tiles.first { $0.key == "indicators" }?.competency.key == "observation")
    }

    @Test func tilesFollowTheConfiguredOrderAndLeaveOutHiddenThemes() {
        var themes = SchoolObservationThemeCatalog.embedded
        themes.swapAt(0, 11) // « Clignotants » en tête
        themes[6].visible = false // « Vitesse » masqué
        themes[12].visible = true // « Distance de sécurité » affiché
        let tiles = SchoolLiveObservationTheme.tiles(for: themes, competencies: Self.standard)
        #expect(tiles.first?.title == "Clignotants")
        #expect(!tiles.contains { $0.key == "speed" })
        #expect(tiles.first { $0.key == "following-distance" }?.competency.key == "vitesse")
        // La compétence « vitesse » reste désignée par un thème masqué : aucune tuile générique ne la remplace.
        #expect(!tiles.contains { $0.key == nil })
        // Le contrôle d’un signalement accepte aussi les thèmes masqués.
        let all = SchoolLiveObservationTheme.tiles(for: themes, competencies: Self.standard, includingHidden: true)
        #expect(all.contains { $0.key == "speed" } && all.count == themes.count)
    }

    @Test func aThemeWhoseCompetencyIsAbsentIsLeftOutAndUnclaimedCompetenciesKeepAGenericTile() {
        let trailer = Self.competency("attelage", "Attelage et dételage", 2)
        let motorway = Self.competency("motorway", "Autoroute", 3)
        let tiles = SchoolLiveObservationTheme.tiles(for: SchoolObservationThemeCatalog.embedded,
            competencies: [Self.standard[0], trailer, motorway])
        // Thèmes configurés d’abord (ancienne clé « motorway » reconnue), tuile générique ensuite.
        #expect(tiles.map(\.title) == ["Maîtrise du véhicule", "Autoroute", "Attelage et dételage"])
        #expect(tiles.map(\.key) == ["vehicle", "motorway", nil])
        #expect(tiles.last?.competency.id == trailer.id)
    }

    @Test func aReferentialWithBothTheOldAndTheNewKeyLosesNoCompetency() {
        let manoeuvres = Self.competency("manoeuvres", "Manœuvres", 1), parking = Self.competency("parking", "Stationnement", 2)
        let tiles = SchoolLiveObservationTheme.tiles(for: SchoolObservationThemeCatalog.embedded, competencies: [manoeuvres, parking])
        #expect(tiles.map(\.title) == ["Manœuvres", "Stationnement"])
        #expect(tiles[0].competency.id == manoeuvres.id && tiles[1].key == nil && tiles[1].competency.id == parking.id)
    }
}

struct SchoolObservationThemeBodyTests {
    private func body(themeKey: String?) -> SchoolObservationBody {
        SchoolObservationBody(operationId: UUID(), draftId: nil, captureId: nil, segmentId: nil, pointSequence: nil,
            competencyId: UUID(), text: "Clignotants", origin: "LIVE", observedAt: "2026-10-12T08:00:00Z",
            eventKind: "QUALIFIED", eventStatus: "ATTENTION", themeKey: themeKey)
    }

    @Test func themeKeyIsEncodedOnlyWhenPresent() throws {
        let with = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(body(themeKey: "indicators"))) as? [String: Any])
        #expect(with["themeKey"] as? String == "indicators" && with["text"] as? String == "Clignotants")
        let without = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(body(themeKey: nil))) as? [String: Any])
        // Une école antérieure refuse un champ inconnu : ni clé, ni `null`.
        #expect(without["themeKey"] == nil)
        #expect(Set(without.keys) == ["operationId", "draftId", "captureId", "segmentId", "pointSequence", "competencyId", "text",
            "origin", "observedAt", "eventKind", "eventStatus"])
        #expect(body(themeKey: "indicators").isValid && body(themeKey: nil).isValid)
    }

    @Test func aThemeKeyNeedsACompetencyAndNeverQualifiesAMarker() {
        let marker = SchoolObservationBody(operationId: UUID(), draftId: nil, captureId: nil, segmentId: nil, pointSequence: nil,
            competencyId: nil, text: "Moment à revoir", origin: "LIVE", observedAt: "2026-10-12T08:00:00Z",
            eventKind: "MARKER", eventStatus: nil, themeKey: "indicators")
        #expect(!marker.isValid)
    }

    @Test func aRequestQueuedBeforeConfigurableThemesStillDecodesAndKeepsItsBytes() throws {
        let operation = UUID(), competency = UUID()
        let bytes = Data("""
        {"operationId":"\(operation.uuidString)","draftId":null,"captureId":null,"segmentId":null,"pointSequence":null,\
        "competencyId":"\(competency.uuidString)","text":"Priorité à droite","origin":"LIVE",\
        "observedAt":"2026-09-28T12:11:00Z","eventKind":"QUALIFIED","eventStatus":"ATTENTION"}
        """.utf8)
        let decoded = try JSONDecoder().decode(SchoolObservationBody.self, from: bytes)
        #expect(decoded.themeKey == nil && decoded.isValid && decoded.operationId == operation && decoded.competencyId == competency)
        let command = PendingSchoolCommand(id: operation, scope: ConfigurationFixture.scope(), kind: .createObservation,
            resourceVersion: 0, createdAt: Date(timeIntervalSince1970: 1_790_000_000), body: bytes, routeResourceID: HubFixture.lessonID)
        let restored = try JSONDecoder().decode(PendingSchoolCommand.self, from: JSONEncoder().encode(command))
        // La file garde les octets : la demande repart telle qu’elle a été écrite.
        #expect(restored == command && restored.body == bytes)
    }

    @Test func aReadObservationTakesItsThemeKeyWhenTheSchoolSendsOne() throws {
        func observation(_ extra: String) throws -> SchoolObservation {
            try JSONDecoder().decode(SchoolObservation.self, from: Data("""
            {"id":"\(UUID().uuidString)","schoolId":"\(HubFixture.schoolID.uuidString)","version":1,\
            "lessonId":"\(HubFixture.lessonID.uuidString)","trainingId":"\(HubFixture.trainingID.uuidString)","draftId":null,\
            "captureId":null,"segmentId":null,"pointSequence":null,"competencyId":"\(UUID().uuidString)",\
            "text":"Texte relu par le moniteur","origin":"LIVE","observedAt":"2026-10-12T08:00:00Z","eventKind":"QUALIFIED",\
            "eventStatus":"POSITIVE","authorMembershipId":"\(ConfigurationFixture.membershipID.uuidString)"\(extra)}
            """.utf8))
        }
        #expect(try observation(#","themeKey":"braking""#).themeKey == "braking")
        #expect(try observation(#","themeKey":null"#).themeKey == nil)
        #expect(try observation("").themeKey == nil)
        // Le dessin suit la clé, même après une relecture du texte et sans référentiel sous la main.
        #expect(try observation(#","themeKey":"braking""#).glyph() == SchoolObservationPictogram.braking.glyph)
    }

    @Test func theSavedConfigurationNamesEveryKeyOnceWithItsDisplay() throws {
        var themes = SchoolObservationThemeCatalog.embedded
        themes.swapAt(0, 2)
        themes[1].visible = false
        let operation = UUID()
        let body = SchoolObservationThemesBody(operationId: operation, themes: themes)
        #expect(body.isValid && body.themes.count == themes.count)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        #expect(Set(object.keys) == ["operationId", "themes"] && UUID(uuidString: object["operationId"] as? String ?? "") == operation)
        let entries = try #require(object["themes"] as? [[String: Any]])
        #expect(entries.first?["key"] as? String == "right-priority" && entries[1]["visible"] as? Bool == false)
        #expect(entries.allSatisfy { Set($0.keys) == ["key", "visible"] })
        for index in themes.indices { themes[index].visible = false }
        #expect(!SchoolObservationThemesBody(operationId: operation, themes: themes).isValid)
        let catalog = SchoolObservationThemeCatalog.embedded
        #expect(!SchoolObservationThemesBody(operationId: operation, themes: catalog + [catalog[0]]).isValid)
    }

    /// École au catalogue plus récent : ses thèmes inconnus repartent à leur place, sans jamais avoir été montrés.
    /// École plus ancienne : les thèmes qu’elle ne liste pas ne lui sont pas envoyés.
    @Test func theSavedListIsExactlyTheKeysTheSchoolListed() {
        var themes = SchoolObservationThemeCatalog.embedded
        let foreign = [SchoolObservationForeignTheme(key: "tunnel", visible: true, after: nil),
                       SchoolObservationForeignTheme(key: "night", visible: false, after: "signage"),
                       SchoolObservationForeignTheme(key: "rain", visible: true, after: "signage"),
                       SchoolObservationForeignTheme(key: "lost", visible: true, after: "retiré")]
        // « Signalisation » passe en tête : ses deux suivants inconnus la suivent, dans leur ordre.
        let signage = themes.remove(at: 3)
        themes.insert(signage, at: 0)
        let body = SchoolObservationThemesBody(operationId: UUID(), themes: themes, foreign: foreign,
                                               unlisted: ["moving-off", "bends", "eco-driving"])
        #expect(Array(body.themes.map(\.key).prefix(5)) == ["tunnel", "signage", "night", "rain", "vehicle"])
        #expect(body.themes.last?.key == "lost" && body.themes.first { $0.key == "night" }?.visible == false)
        #expect(body.isValid && body.themes.count == themes.count - 3 + foreign.count)
        #expect(!body.themes.contains { ["moving-off", "bends", "eco-driving"].contains($0.key) })
    }
}

struct SchoolSignalGridLayoutTests {
    private func layout(_ count: Int, width: CGFloat = 361, text: DynamicTypeSize = .large) -> SchoolSignalGridLayout {
        SchoolSignalGridLayout(tileCount: count, width: width, textSize: text)
    }

    @Test func fewTilesAreWideAndManyKeepTheCurrentTileWidth() {
        #expect(layout(1) == layout(1) && layout(1).columns == 1 && layout(1).rows == 1)
        #expect(layout(2).columns == 2 && layout(3).columns == 3 && layout(3).rows == 1)
        #expect(layout(4).columns == 2 && layout(4).rows == 2)
        #expect(layout(5).columns == 3 && layout(5).rows == 2)
        // Onze et douze tuiles : trois colonnes et quatre rangées, comme avant.
        #expect(layout(11).columns == 3 && layout(11).rows == 4 && layout(12).rows == 4)
        // Quinze tuiles : cinq rangées de trois sur un iPhone, quatre colonnes là où une tuile garde 100 pt.
        #expect(layout(15).columns == 3 && layout(15).rows == 5)
        #expect(layout(15, width: 480).columns == 4 && layout(15, width: 480).rows == 4)
        #expect(layout(15, width: 320).columns == 2)
        #expect(layout(0).rows == 0)
    }

    /// Tout le catalogue affiché, sur les deux largeurs d’iPhone courantes (volet = écran − 32 pt) : trois colonnes,
    /// donc six rangées de seize à dix-huit tuiles. Quatre colonnes seulement là où une tuile garde 100 pt.
    @Test func theWholeCatalogueKeepsThreeColumnsOnAnIPhone() {
        let all = SchoolObservationThemeCatalog.embedded.count
        for width: CGFloat in [375 - 32, 430 - 32] {
            for count in 16...max(18, all) {
                #expect(layout(count, width: width).columns == 3 && layout(count, width: width).rows == (count + 2) / 3, "\(count) à \(width)")
            }
        }
        #expect(layout(16, width: 480).columns == 4 && layout(16, width: 480).rows == 4)
        #expect(layout(18, width: 480).rows == 5)
        // Aucune disposition ne perd de tuile ni ne descend sous la largeur minimale, de 1 à bien au-delà du catalogue.
        for count in 1...(all + 12) {
            for width: CGFloat in [320, 343, 398, 480, 640] {
                let value = layout(count, width: width)
                #expect(value.columns * value.rows >= count && value.columns * (value.rows - 1) < count)
                let tile = (width - 2 * SchoolSignalGridLayout.gutter - CGFloat(value.columns - 1) * SchoolSignalGridLayout.spacing) / CGFloat(value.columns)
                #expect(value.columns == 1 || tile >= SchoolSignalGridLayout.minimumTileWidth)
            }
        }
    }

    @Test func largeTextWidensTilesAndAccessibilitySizesUseOneColumn() {
        #expect(layout(12, text: .xxLarge).columns == 2)
        #expect(layout(12, text: .accessibility1).columns == 1 && layout(12, text: .accessibility1).rows == 12)
        #expect(layout(3, text: .accessibility3).columns == 1)
    }

    @Test func thePanelGrowsWithItsRowsAndFifteenTilesFitASmallPhone() {
        func height(_ count: Int) -> CGFloat {
            SchoolSignalGridLayout.estimatedPaletteHeight(tileCount: count, width: 361, textSize: .large)
        }
        #expect(height(1) < height(4) && height(4) < height(9) && height(9) < height(12) && height(12) < height(15))
        // Douze tuiles tiennent dans l’ancien budget du volet ; quinze dans la hauteur utile d’un iPhone de 667 pt.
        #expect(height(12) <= 520 && height(15) <= 615)
        #expect(height(11) == height(12) && height(13) == height(15))
        // Seize à dix-huit tuiles : une sixième rangée. Le volet dépasse alors un iPhone de 667 pt, où la grille défile.
        #expect(height(16) == height(18) && height(16) > height(15) && height(18) > 615)
    }
}

/// Copie locale en mémoire.
@MainActor private final class ThemeCacheStub: SchoolObservationThemeCache {
    var stored: SchoolObservationThemeConfiguration?
    var writes = 0
    func read(scope: SchoolCommandScope) -> SchoolObservationThemeConfiguration? { stored }
    func write(_ configuration: SchoolObservationThemeConfiguration, scope: SchoolCommandScope) { stored = configuration; writes += 1 }
}

/// École synthétique : une configuration versionnée, qui refuse une version périmée comme le contrat le dit.
private actor ThemeServer: SchoolHTTPTransport {
    struct Write: Sendable {
        let operation: UUID
        let ifMatch: String?
        let idempotencyKey: String?
        let keys: [String]
    }
    private var settings: SchoolObservationThemeSettings
    private var offline = false
    private var forbidsWrites = false
    private var missing = false
    private var applied: Set<UUID> = []
    private(set) var writes: [Write] = []
    private(set) var reads = 0

    /// `themes` : le catalogue de l’école, qui peut être plus récent ou plus ancien que celui de l’app.
    init(canManage: Bool = true, themes: [SchoolObservationTheme] = SchoolObservationThemeCatalog.embedded) {
        settings = SchoolObservationThemeSettings(id: ConfigurationFixture.schoolID, schoolId: ConfigurationFixture.schoolID,
            version: 1, canManage: canManage, themes: themes)
    }

    func current() -> SchoolObservationThemeSettings { settings }
    func setOffline(_ value: Bool) { offline = value }
    func forbidWrites() { forbidsWrites = true }
    func removeRoute() { missing = true }
    /// Une autre personne déplace « Clignotants » en tête.
    func changeElsewhere() {
        var themes = settings.themes
        if let index = themes.firstIndex(where: { $0.key == "indicators" }) {
            let theme = themes.remove(at: index)
            themes.insert(theme, at: 0)
        }
        settings = SchoolObservationThemeSettings(id: settings.id, schoolId: settings.schoolId, version: settings.version + 1,
            canManage: settings.canManage, themes: themes)
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        func envelope(_ data: Any) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data, "requestId": UUID().uuidString,
                "serverTime": "2026-10-12T08:00:00Z"]), status: 200, url: url, contentType: "application/json")
        }
        func problem(_ status: Int, _ code: String) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["code": code]), status: status, url: url,
                contentType: "application/problem+json")
        }
        if url.path == "/v1/me" {
            let membership: [String: Any] = ["membershipId": ConfigurationFixture.membershipID.uuidString,
                "schoolId": ConfigurationFixture.schoolID.uuidString, "schoolName": "École de test", "roles": ["INSTRUCTOR"],
                "grants": ["MANAGE_OBSERVATION_THEMES"], "accessEpoch": 1]
            return try envelope(["personId": ConfigurationFixture.personID.uuidString, "version": 1, "displayName": "Moniteur de test",
                "locale": "fr-CH", "memberships": [membership]] as [String: Any])
        }
        guard url.lastPathComponent == "observation-themes" else { return try problem(404, "NOT_FOUND") }
        if missing { return try problem(404, "NOT_FOUND") }
        if request.httpMethod == "PUT" {
            let body = try JSONDecoder().decode(SchoolObservationThemesBody.self, from: request.httpBody ?? Data())
            writes.append(Write(operation: body.operationId, ifMatch: request.value(forHTTPHeaderField: "If-Match"),
                idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key"), keys: body.themes.map(\.key)))
            if offline { throw URLError(.notConnectedToInternet) }
            if forbidsWrites { return try problem(403, "OBSERVATION_THEMES_ACCESS_REQUIRED") }
            guard let match = request.value(forHTTPHeaderField: "If-Match") else { return try problem(428, "PRECONDITION_REQUIRED") }
            // Un rejeu de la même opération rend la configuration actuelle, sans second effet.
            if !applied.contains(body.operationId) {
                // Comme l’école : toutes ses clés, chacune une fois, et aucune autre.
                guard body.themes.count == settings.themes.count,
                      Set(body.themes.map(\.key)) == Set(settings.themes.map(\.key)) else { return try problem(400, "INVALID_REQUEST") }
                guard match == "\"\(settings.version)\"" else { return try problem(412, "VERSION_CONFLICT") }
                let known = Dictionary(uniqueKeysWithValues: settings.themes.map { ($0.key, $0) })
                let themes = body.themes.compactMap { entry -> SchoolObservationTheme? in
                    guard var theme = known[entry.key] else { return nil }
                    theme.visible = entry.visible
                    return theme
                }
                settings = SchoolObservationThemeSettings(id: settings.id, schoolId: settings.schoolId, version: settings.version + 1,
                    canManage: settings.canManage, themes: themes)
                applied.insert(body.operationId)
            }
        } else {
            reads += 1
            if offline { throw URLError(.notConnectedToInternet) }
        }
        return try envelope(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)))
    }
}

@MainActor struct SchoolObservationThemeStoreTests {
    private func store(_ server: ThemeServer, cache: ThemeCacheStub? = nil) -> SchoolObservationThemeStore {
        let scope = ConfigurationFixture.scope()
        let client = SchoolObservationThemeClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: server)
        return SchoolObservationThemeStore(scope: scope, client: client, cache: cache ?? ThemeCacheStub())
    }

    private func settled(_ store: SchoolObservationThemeStore) async throws {
        try await HubFixture.wait { store.saveState != .saving }
    }

    @Test func beforeAnyAnswerTheEmbeddedCatalogIsUsedAndNothingCanBeManaged() async {
        let server = ThemeServer()
        let model = store(server)
        #expect(model.configuration == .embedded && !model.configuration.isFromServer)
        #expect(!model.canManage && !model.canEdit)
        model.setVisible(false, key: "vehicle")
        #expect(model.displayed == SchoolObservationThemeCatalog.embedded && model.saveState == .idle)
        #expect(await server.writes.isEmpty)
    }

    @Test func aReadIsKeptForOfflineUseAndTheRightIsNeverTakenFromTheCopy() async {
        let server = ThemeServer(), cache = ThemeCacheStub()
        let model = store(server, cache: cache)
        #expect(await model.refresh())
        #expect(model.configuration.isFromServer && model.configuration.version == 1 && model.canManage && model.canEdit)
        #expect(cache.writes == 1 && cache.stored == model.configuration)
        // Autre session, école injoignable : la copie sert à « Signaler », le droit attend la réponse de l’école.
        await server.setOffline(true)
        let offline = store(server, cache: cache)
        #expect(offline.configuration.isFromServer && !offline.canManage)
        #expect(!(await offline.refresh()))
        #expect(offline.configuration == model.configuration && offline.loadError != nil && !offline.canEdit)
    }

    @Test func aSchoolThatDoesNotKnowTheRouteLeavesTheEmbeddedCatalog() async {
        let server = ThemeServer(), cache = ThemeCacheStub()
        await server.removeRoute()
        let model = store(server, cache: cache)
        #expect(!(await model.refresh()))
        #expect(model.configuration == .embedded && !model.canManage && cache.writes == 0)
    }

    @Test func aMemberWithoutTheRightReadsTheConfigurationButCannotChangeIt() async {
        let server = ThemeServer(canManage: false)
        let model = store(server)
        #expect(await model.refresh())
        #expect(model.configuration.isFromServer && !model.canManage && !model.canEdit)
        model.setVisible(false, key: "vehicle")
        model.resetAll()
        #expect(model.proposal == nil && model.saveState == .idle)
        #expect(await server.writes.isEmpty)
    }

    @Test func aChangeLeavesAtOnceAndIsOnlyConfirmedByTheSchool() async throws {
        let server = ThemeServer(), cache = ThemeCacheStub()
        let model = store(server, cache: cache)
        await model.refresh()
        model.setVisible(false, key: "vehicle")
        // Dans le tour du geste : l’écran montre la proposition, rien n’est encore confirmé.
        #expect(model.saveState == .saving && model.displayed.first?.visible == false && model.visibleCount == 11)
        #expect(model.configuration.themes.first?.visible == true && model.configuration.version == 1)
        try await settled(model)
        #expect(model.saveState == .saved && model.proposal == nil)
        #expect(model.configuration.version == 2 && model.configuration.themes.first?.visible == false)
        #expect(cache.stored?.version == 2)
        let writes = await server.writes
        #expect(writes.count == 1 && writes[0].ifMatch == "\"1\"" && writes[0].idempotencyKey == writes[0].operation.uuidString)
        #expect(writes[0].keys == SchoolObservationThemeCatalog.embedded.map(\.key))
    }

    @Test func changesMadeDuringASendFollowItWithTheConfirmedVersion() async throws {
        let server = ThemeServer()
        let model = store(server)
        await model.refresh()
        model.setVisible(false, key: "vehicle")
        model.setVisible(true, key: "braking")
        #expect(model.move(key: "indicators", by: -1) == 10)
        try await settled(model)
        #expect(model.saveState == .saved)
        let latest = await server.current()
        #expect(model.configuration.themes == latest.themes && model.configuration.version == latest.version)
        #expect(latest.themes.first?.visible == false)
        #expect(latest.themes.first(where: { $0.key == "braking" })?.visible == true)
        #expect(latest.themes.firstIndex(where: { $0.key == "indicators" }) == 10)
        // Chaque envoi porte la version que le précédent a confirmée.
        let writes = await server.writes
        #expect(!writes.isEmpty && writes.compactMap(\.ifMatch) == writes.indices.map { "\"\($0 + 1)\"" })
    }

    @Test func aVersionConflictRereadsShowsTheCurrentConfigurationAndSaysItHadChanged() async throws {
        let server = ThemeServer()
        let model = store(server)
        await model.refresh()
        await server.changeElsewhere()
        model.setVisible(false, key: "vehicle")
        try await HubFixture.wait { model.saveState != .saving && model.notice != nil }
        let current = await server.current()
        #expect(model.notice == SchoolObservationThemeStore.changedNotice && model.saveState == .idle)
        #expect(model.proposal == nil && model.displayed == current.themes && model.configuration.version == 2)
        #expect(model.displayed.first?.key == "indicators")
        // Le changement refusé n’a rien écrit ; il se refait sur la configuration relue.
        #expect(model.displayed.first { $0.key == "vehicle" }?.visible == true)
        model.setVisible(false, key: "vehicle")
        #expect(model.notice == nil)
        try await settled(model)
        #expect(model.saveState == .saved && model.configuration.version == 3)
    }

    @Test func aNetworkFailureReturnsToTheConfirmedStateAndRetriesTheSameOperation() async throws {
        let server = ThemeServer()
        let model = store(server)
        await model.refresh()
        let confirmed = model.configuration
        await server.setOffline(true)
        model.setVisible(false, key: "vehicle")
        try await settled(model)
        guard case .failed = model.saveState else { Issue.record("L’échec n’est pas annoncé : \(model.saveState)"); return }
        #expect(model.configuration == confirmed && model.displayed == confirmed.themes && model.proposal == nil)
        #expect(model.canRetry)
        await server.setOffline(false)
        model.retry()
        #expect(model.saveState == .saving)
        try await settled(model)
        #expect(model.saveState == .saved && model.configuration.version == 2 && !model.canRetry)
        #expect(model.configuration.themes.first?.visible == false)
        let writes = await server.writes
        #expect(writes.count == 2 && writes[0].operation == writes[1].operation && writes[1].ifMatch == "\"1\"")
    }

    @Test func aWithdrawnRightStopsEditingAndNothingIsShownAsSaved() async throws {
        let server = ThemeServer()
        let model = store(server)
        await model.refresh()
        await server.forbidWrites()
        model.setVisible(false, key: "vehicle")
        try await settled(model)
        guard case .failed = model.saveState else { Issue.record("Le refus n’est pas annoncé : \(model.saveState)"); return }
        #expect(!model.canManage && !model.canEdit && !model.canRetry)
        #expect(model.displayed.first?.visible == true && model.configuration.version == 1)
        model.setVisible(false, key: "observation")
        #expect(model.proposal == nil)
        #expect(await server.writes.count == 1)
    }

    @Test func theLastDisplayedThemeCannotBeHidden() async {
        let server = ThemeServer()
        let model = store(server)
        await model.refresh()
        var themes = model.displayed
        for index in themes.indices { themes[index].visible = false }
        model.propose(themes)
        #expect(model.notice == SchoolObservationThemeStore.lastVisibleNotice && model.proposal == nil && model.saveState == .idle)
        #expect(await server.writes.isEmpty)
    }

    @Test func resetOrderAndFullResetAreOneWriteEach() async throws {
        let server = ThemeServer()
        let model = store(server)
        await model.refresh()
        #expect(model.isOriginalOrder && model.isOriginal)
        model.move(key: "vehicle", by: 1)
        model.setVisible(true, key: "braking")
        try await settled(model)
        #expect(!model.isOriginalOrder && !model.isOriginal)
        let before = await server.writes.count
        model.resetOrder()
        try await settled(model)
        #expect(model.isOriginalOrder && !model.isOriginal && model.displayed.first { $0.key == "braking" }?.visible == true)
        #expect(await server.writes.count == before + 1)
        model.resetAll()
        try await settled(model)
        #expect(model.isOriginal && model.configuration.themes == SchoolObservationThemeCatalog.embedded)
        #expect(await server.writes.count == before + 2)
    }

    /// École au catalogue plus récent que l’app : le thème inconnu n’est jamais montré, mais chaque écriture le
    /// renvoie à sa place, sans quoi l’école refuserait la liste (400).
    @Test func aThemeUnknownToThisVersionIsNeverShownAndAlwaysSentBack() async throws {
        var themes = SchoolObservationThemeCatalog.embedded
        themes.insert(SchoolObservationTheme(key: "tunnel", title: "Tunnels", competencyKeys: ["tunnel"], visible: true,
                                             defaultVisible: true, defaultPosition: themes.count), at: 3)
        let server = ThemeServer(themes: themes), cache = ThemeCacheStub()
        let model = store(server, cache: cache)
        await model.refresh()
        #expect(model.displayed.map(\.key) == SchoolObservationThemeCatalog.embedded.map(\.key))
        #expect(model.configuration.foreign == [SchoolObservationForeignTheme(key: "tunnel", visible: true, after: "right-priority")])
        #expect(model.configuration.unlisted.isEmpty && cache.stored?.foreign == model.configuration.foreign)
        // « Priorité à droite » descend d’un rang : « Tunnels » la suit.
        #expect(model.move(key: "right-priority", by: 1) == 3)
        try await settled(model)
        #expect(model.saveState == .saved && model.configuration.version == 2)
        let firstWrites = await server.writes
        let sent = try #require(firstWrites.last).keys
        #expect(sent.count == themes.count && Array(sent[2...4]) == ["signage", "right-priority", "tunnel"])
        let kept = await server.current()
        #expect(kept.themes.first { $0.key == "tunnel" }?.visible == true)
        #expect(model.displayed.count == SchoolObservationThemeCatalog.embedded.count && !model.displayed.contains { $0.key == "tunnel" })
        // Tout rétablir ne perd pas davantage la clé inconnue.
        model.resetAll()
        try await settled(model)
        let laterWrites = await server.writes
        let restored = try #require(laterWrites.last).keys
        #expect(model.saveState == .saved && restored.contains("tunnel") && restored.count == themes.count)
    }

    /// École plus ancienne que l’app : elle ne reçoit que les clés qu’elle liste ; les thèmes qu’elle ignore
    /// restent masqués, ne se règlent pas et ne sont jamais nommés par une observation.
    @Test func aSchoolWithAnOlderCatalogueOnlyReceivesTheKeysItListed() async throws {
        let listed = Array(SchoolObservationThemeCatalog.embedded.prefix(15))
        let server = ThemeServer(themes: listed)
        let model = store(server)
        await model.refresh()
        #expect(model.displayed.count == SchoolObservationThemeCatalog.embedded.count)
        #expect(model.configuration.unlisted == ["moving-off", "bends", "eco-driving"])
        #expect(!model.configuration.sendsThemeKey("moving-off") && model.configuration.sendsThemeKey("vehicle"))
        #expect(!model.configuration.sendsThemeKey(nil) && !SchoolObservationThemeConfiguration.embedded.sendsThemeKey("vehicle"))
        model.setVisible(true, key: "moving-off")
        #expect(model.proposal == nil && model.saveState == .idle)
        model.setVisible(false, key: "vehicle")
        try await settled(model)
        #expect(model.saveState == .saved && model.configuration.themes.first?.visible == false)
        let writes = await server.writes
        #expect(writes.count == 1 && writes[0].keys == listed.map(\.key))
        #expect(model.displayed.first { $0.key == "moving-off" }?.visible == false)
    }

    @Test func aCopyWrittenBeforeNewThemesDoesNotAssumeTheSchoolKnowsThem() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("themes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SchoolObservationThemeFileCache(directory: directory), scope = ConfigurationFixture.scope()
        let older = SchoolObservationThemeConfiguration(themes: Array(SchoolObservationThemeCatalog.embedded.prefix(15)),
                                                        version: 3, source: .server)
        cache.write(older, scope: scope)
        let read = try #require(cache.read(scope: scope))
        #expect(read.themes.count == SchoolObservationThemeCatalog.embedded.count && read.version == 3 && read.isFromServer)
        #expect(read.unlisted == ["moving-off", "bends", "eco-driving"] && !read.sendsThemeKey("bends"))
        // Les thèmes étrangers et non listés survivent à la copie.
        let foreign = [SchoolObservationForeignTheme(key: "tunnel", visible: false, after: "vehicle")]
        let full = SchoolObservationThemeConfiguration(themes: SchoolObservationThemeCatalog.embedded, version: 4, source: .server,
                                                       foreign: foreign, unlisted: ["eco-driving"])
        cache.write(full, scope: scope)
        #expect(cache.read(scope: scope) == full)
    }

    @Test func theFileCopyBelongsToItsSchoolAndNeverStoresTheEmbeddedFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("themes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SchoolObservationThemeFileCache(directory: directory), scope = ConfigurationFixture.scope()
        #expect(cache.read(scope: scope) == nil)
        cache.write(.embedded, scope: scope)
        #expect(cache.read(scope: scope) == nil)
        var themes = SchoolObservationThemeCatalog.embedded
        themes.swapAt(0, 14)
        let saved = SchoolObservationThemeConfiguration(themes: themes, version: 4, source: .server)
        cache.write(saved, scope: scope)
        #expect(cache.read(scope: scope) == saved)
        let other = SchoolCommandScope(personID: scope.personID, schoolID: UUID(), membershipID: scope.membershipID,
                                       accessEpoch: 1, apiBaseURL: scope.apiBaseURL)
        #expect(cache.read(scope: other) == nil)
        let elsewhere = SchoolCommandScope(personID: scope.personID, schoolID: scope.schoolID, membershipID: scope.membershipID,
                                           accessEpoch: 1, apiBaseURL: "https://autre.example.invalid")
        #expect(cache.read(scope: elsewhere) == nil)
    }
}

/// Référentiel d’une leçon pour l’enregistreur : compétences du catalogue et une compétence propre à l’école.
private actor ThemeLessonTransport: SchoolHTTPTransport {
    static let offeringID = UUID(uuidString: "71000000-0000-4000-8000-000000000002")!
    static let curriculumID = UUID(uuidString: "71000000-0000-4000-8000-000000000003")!
    static func competency(_ number: Int, _ key: String, _ label: String) -> SchoolCatalogCompetency {
        SchoolCatalogCompetency(id: UUID(uuidString: "71000000-0000-4000-8000-0000000001\(String(format: "%02d", number))")!,
            schoolId: HubFixture.schoolID, version: 1, curriculumVersionId: curriculumID, key: key, label: label,
            description: "", sortOrder: number)
    }
    static let competencies = [competency(1, "vehicule", "Maîtrise du véhicule"), competency(2, "observation", "Observation et contrôles"),
        competency(3, "vitesse", "Adaptation de la vitesse"), competency(4, "attelage", "Attelage et dételage")]
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
                "requestId": UUID().uuidString, "serverTime": "2026-10-12T08:00:00Z"]), status: 200, url: url, contentType: "application/json")
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

@MainActor struct SchoolLiveObservationThemeSnapshotTests {
    private func themeStore(_ server: ThemeServer) -> SchoolObservationThemeStore {
        let scope = ConfigurationFixture.scope()
        return SchoolObservationThemeStore(scope: scope, client: SchoolObservationThemeClient(baseURL: URL(string: scope.apiBaseURL)!,
            tokenSource: HubToken(), transport: server), cache: ThemeCacheStub())
    }

    private func recorder(_ outbox: ConfigurationOutboxStub, themes: SchoolObservationThemeStore?) -> SchoolLiveObservationRecorder {
        let client = SchoolObservationClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: ThemeLessonTransport())
        return SchoolLiveObservationRecorder(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID,
            client: client, themeStore: themes, outbox: outbox)
    }

    @Test func anOpenPaletteKeepsItsTilesWhileTheSchoolChangesTheConfiguration() async throws {
        let server = ThemeServer()
        let store = themeStore(server)
        await store.refresh()
        let model = recorder(ConfigurationOutboxStub(), themes: store)
        await model.loadCompetencies()
        model.openPalette()
        let opened = model.themes
        #expect(opened.map(\.title) == ["Maîtrise du véhicule", "Observation et contrôles", "Vitesse", "Clignotants", "Attelage et dételage"])
        // Quelqu’un déplace « Clignotants » en tête ; la lecture lancée à l’ouverture, ou une autre, le rapporte.
        await server.changeElsewhere()
        try await HubFixture.wait {
            await store.refresh()
            return store.configuration.version == 2
        }
        #expect(store.configuration.themes.first?.key == "indicators")
        // La palette ouverte ne bouge pas : même instantané, mêmes tuiles, même ordre.
        #expect(model.themeConfiguration.version == 1 && model.themes == opened)
        // À l’ouverture suivante seulement.
        model.openPalette()
        #expect(model.themeConfiguration.version == 2 && model.themes.first?.title == "Clignotants")
        model.stop()
    }

    @Test func theThemeKeyLeavesOnlyWithAConfigurationReadFromTheSchool() async throws {
        let server = ThemeServer()
        let store = themeStore(server)
        await store.refresh()
        let outbox = ConfigurationOutboxStub()
        let model = recorder(outbox, themes: store)
        await model.loadCompetencies()
        model.openPalette()
        let indicators = try #require(model.themes.first { $0.key == "indicators" })
        #expect(model.record(theme: indicators, status: .attention, at: HubFixture.date("2026-10-12T08:00:00Z")))
        let body = try JSONDecoder().decode(SchoolObservationBody.self, from: try #require(outbox.value).body)
        // Le texte reste le titre de la tuile ; la clé dit le thème, la compétence reste celle du référentiel.
        #expect(body.themeKey == "indicators" && body.text == "Clignotants" && body.isValid)
        #expect(body.competencyId == ThemeLessonTransport.competencies[1].id && body.eventKind == "QUALIFIED")
        model.stop()
    }

    /// École plus ancienne que l’app : un thème qu’elle ne liste pas s’enregistre sans clé, pour ne pas être refusé.
    @Test func aThemeTheSchoolDoesNotListIsRecordedWithoutItsKey() async throws {
        let store = themeStore(ThemeServer(themes: Array(SchoolObservationThemeCatalog.embedded.prefix(15))))
        await store.refresh()
        let outbox = ConfigurationOutboxStub()
        let model = recorder(outbox, themes: store)
        await model.loadCompetencies()
        model.openPalette()
        #expect(model.themeConfiguration.isFromServer && model.themeConfiguration.unlisted.contains("moving-off"))
        let movingOff = SchoolLiveObservationTheme(competency: ThemeLessonTransport.competencies[0], title: "Démarrage", key: "moving-off")
        #expect(model.record(theme: movingOff, status: .attention, at: Date()))
        let bytes = try #require(outbox.value).body
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(object["themeKey"] == nil && object["text"] as? String == "Démarrage")
        model.stop()
    }

    @Test func withoutAnAnswerFromTheSchoolNoThemeKeyIsSent() async throws {
        for store in [nil, themeStore(ThemeServer())] as [SchoolObservationThemeStore?] {
            let outbox = ConfigurationOutboxStub()
            let model = recorder(outbox, themes: store)
            await model.loadCompetencies()
            #expect(!model.themeConfiguration.isFromServer)
            let indicators = try #require(model.themes.first { $0.key == "indicators" })
            #expect(model.record(theme: indicators, status: .positive, at: Date()))
            let bytes = try #require(outbox.value).body
            let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            #expect(object["themeKey"] == nil && object["text"] as? String == "Clignotants")
            model.stop()
        }
    }

    @Test func aGenericTileSendsNoKeyAndAHiddenThemeIsStillAccepted() async throws {
        let server = ThemeServer()
        let store = themeStore(server)
        await store.refresh()
        let outbox = ConfigurationOutboxStub()
        let model = recorder(outbox, themes: store)
        await model.loadCompetencies()
        model.openPalette()
        // « Distance de sécurité » est masqué à l’origine : pas de tuile, mais le signalement reste recevable.
        #expect(!model.themes.contains { $0.key == "following-distance" })
        let hidden = SchoolLiveObservationTheme(competency: ThemeLessonTransport.competencies[2], title: "Distance de sécurité",
                                                key: "following-distance")
        // Un thème rattaché à une compétence qui n’est pas la sienne n’est pas recevable.
        let mismatched = SchoolLiveObservationTheme(competency: ThemeLessonTransport.competencies[0], title: "Distance de sécurité",
                                                    key: "following-distance")
        #expect(!model.record(theme: mismatched, status: .attention, at: Date()) && outbox.value == nil)
        let generic = try #require(model.themes.last)
        #expect(generic.key == nil && generic.title == "Attelage et dételage")
        #expect(model.record(theme: generic, status: .attention, at: Date()))
        let body = try JSONDecoder().decode(SchoolObservationBody.self, from: try #require(outbox.value).body)
        #expect(body.themeKey == nil && body.text == "Attelage et dételage")
        model.stop()
        let second = ConfigurationOutboxStub()
        let other = recorder(second, themes: store)
        await other.loadCompetencies()
        other.openPalette()
        #expect(other.record(theme: hidden, status: .toWorkOn, at: Date()))
        let kept = try JSONDecoder().decode(SchoolObservationBody.self, from: try #require(second.value).body)
        #expect(kept.themeKey == "following-distance" && kept.text == "Distance de sécurité")
        other.stop()
    }
}
