import Foundation
import Testing
@testable import Drivy

/// Préférences de notification et appareils push : contrat de `apps/api/src/notification-preferences.ts`, sans réseau.
@MainActor struct SchoolNotificationTests {
    /// Profil signé synthétique : octets PKCS#7 autour d’une plist en clair, comme `embedded.mobileprovision`.
    private func profile(_ environment: String?) -> Data {
        let entitlements = environment.map { "<key>aps-environment</key><string>\($0)</string>" } ?? ""
        let plist = #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Entitlements</key><dict>"#
            + entitlements + "</dict></dict></plist>"
        return Data([0x30, 0x82, 0x01, 0x00]) + Data(plist.utf8) + Data([0xA0, 0x00])
    }

    @Test func readsTheAPNsEnvironmentFromTheSigningProfile() {
        #expect(SchoolPushEnvironment.provisioned(in: profile("production")) == .production)
        #expect(SchoolPushEnvironment.provisioned(in: profile("development")) == .sandbox)
        #expect(SchoolPushEnvironment.provisioned(in: profile(nil)) == nil)
        #expect(SchoolPushEnvironment.provisioned(in: Data([0x00, 0x01])) == nil)
    }
    @Test func decodesPreferencesWithTheirVersion() throws {
        let json = Data(#"{"version":3,"courseOffers":true,"courseReminders":false,"courseChanges":true,"courseStaffAlerts":false}"#.utf8)
        let preferences = try JSONDecoder().decode(SchoolNotificationPreferences.self, from: json)
        #expect(preferences.version == 3)
        #expect(preferences.courseOffers && !preferences.courseReminders && preferences.courseChanges && !preferences.courseStaffAlerts)
    }

    @Test func rejectsPreferencesMissingAField() {
        let json = Data(#"{"version":1,"courseOffers":true,"courseReminders":true,"courseChanges":true}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(SchoolNotificationPreferences.self, from: json) }
    }

    @Test func encodesTheBodyWithoutVersion() throws {
        var preferences = SchoolNotificationPreferences(version: 4, courseOffers: true, courseReminders: true,
                                                        courseChanges: true, courseStaffAlerts: true)
        preferences.courseReminders = false
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences.body)) as? [String: Any])
        #expect(Set(object.keys) == ["courseOffers", "courseReminders", "courseChanges", "courseStaffAlerts"])
        #expect(object["courseReminders"] as? Bool == false)
        #expect(object["courseOffers"] as? Bool == true)
    }

    @Test func formatsTheDeviceTokenAsLowercaseHex() throws {
        let bytes = Data((0..<32).map { UInt8($0 + 10) })
        let token = try #require(SchoolPushToken.hex(bytes))
        #expect(token.count == 64)
        #expect(token.hasPrefix("0a0b0c"))
        #expect(token.hasSuffix("29"))
        #expect(token == token.lowercased())
        #expect(SchoolPushToken.valid(token))
    }

    @Test func refusesTokensOutsideTheServerBounds() {
        #expect(SchoolPushToken.hex(Data(repeating: 0xAB, count: 31)) == nil)
        #expect(SchoolPushToken.hex(Data(repeating: 0xAB, count: 101)) == nil)
        #expect(SchoolPushToken.hex(Data(repeating: 0xAB, count: 100)) != nil)
        #expect(!SchoolPushToken.valid(String(repeating: "A", count: 64)))
        #expect(!SchoolPushToken.valid(String(repeating: "g", count: 64)))
    }

    @Test func encodesTheDeviceBodyWithItsEnvironment() throws {
        let token = String(repeating: "ab", count: 32)
        let body = SchoolPushDeviceBody(token: token, environment: .sandbox)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        #expect(object["token"] as? String == token)
        #expect(object["environment"] as? String == "SANDBOX")
        #expect(SchoolPushEnvironment.production.rawValue == "PRODUCTION")
    }

    @Test func picksTheEnvironmentOfTheBuild() {
        #if DEBUG
        #expect(SchoolPushEnvironment.current == .sandbox)
        #else
        #expect(SchoolPushEnvironment.current == .production)
        #endif
    }

    @Test func readsTheSeriesOfANotification() {
        let id = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        #expect(SchoolPushCenter.seriesID(in: ["seriesId": id.uuidString.lowercased(), "category": "COURSE_OFFER"]) == id)
        #expect(SchoolPushCenter.seriesID(in: ["seriesId": NSNull()]) == nil)
        #expect(SchoolPushCenter.seriesID(in: ["seriesId": "pas-un-uuid"]) == nil)
        #expect(SchoolPushCenter.seriesID(in: [:]) == nil)
    }

    @Test func decodesFollowReplies() throws {
        let type = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let follows = try JSONDecoder().decode(SchoolCourseFollows.self, from: Data(#"{"typeIds":["\#(type.uuidString.lowercased())"]}"#.utf8))
        #expect(follows.typeIds == [type])
        let reply = try JSONDecoder().decode(SchoolCourseFollowReply.self,
            from: Data(#"{"typeId":"\#(type.uuidString.lowercased())","following":false}"#.utf8))
        #expect(reply.typeId == type && !reply.following)
    }
}
