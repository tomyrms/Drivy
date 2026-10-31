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

    // MARK: Messagerie (#74)

    @Test func decodesMessagingPreferencesWhenTheAPIAnnouncesThem() throws {
        let json = Data(#"{"version":2,"courseOffers":true,"courseReminders":true,"courseChanges":true,"courseStaffAlerts":true,"messagingPrivate":true,"messagingGeneral":false,"messagingMentions":true}"#.utf8)
        let preferences = try JSONDecoder().decode(SchoolNotificationPreferences.self, from: json)
        #expect(preferences.supportsMessaging)
        #expect(SchoolNotificationCategory.messagingPrivate.value(in: preferences))
        #expect(!SchoolNotificationCategory.messagingGeneral.value(in: preferences))
        #expect(SchoolNotificationCategory.messagingMentions.value(in: preferences))
    }

    @Test func anOlderAPIAnswerKeepsTheDefaultsAndHidesMessaging() throws {
        let json = Data(#"{"version":3,"courseOffers":true,"courseReminders":false,"courseChanges":true,"courseStaffAlerts":false}"#.utf8)
        let preferences = try JSONDecoder().decode(SchoolNotificationPreferences.self, from: json)
        #expect(!preferences.supportsMessaging)
        #expect(SchoolNotificationCategory.messagingPrivate.value(in: preferences))
        #expect(!SchoolNotificationCategory.messagingGeneral.value(in: preferences))
        #expect(SchoolNotificationCategory.messagingMentions.value(in: preferences))
    }

    @Test func encodesMessagingChoicesOnlyWhenTheyAreKnown() throws {
        let legacy = try JSONDecoder().decode(SchoolNotificationPreferencesBody.self,
            from: Data(#"{"courseOffers":false,"courseReminders":true,"courseChanges":true,"courseStaffAlerts":true}"#.utf8))
        #expect(legacy.messagingPrivate == nil)
        let legacyObject = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        #expect(Set(legacyObject.keys) == ["courseOffers", "courseReminders", "courseChanges", "courseStaffAlerts"])
        let full = SchoolNotificationPreferences(version: 5, courseOffers: true, courseReminders: true, courseChanges: true,
            courseStaffAlerts: true, messagingPrivate: false, messagingGeneral: true, messagingMentions: true)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(full.body)) as? [String: Any])
        #expect(Set(object.keys) == ["courseOffers", "courseReminders", "courseChanges", "courseStaffAlerts",
                                     "messagingPrivate", "messagingGeneral", "messagingMentions"])
        #expect(object["messagingPrivate"] as? Bool == false && object["messagingGeneral"] as? Bool == true)
    }

    @Test func aSavedAnswerMustReflectEveryFieldThatWasSent() {
        let sent = SchoolNotificationPreferencesBody(courseOffers: true, courseReminders: true, courseChanges: true,
            courseStaffAlerts: true, messagingPrivate: false, messagingGeneral: false, messagingMentions: true)
        var saved = sent
        #expect(sent.isReflected(in: saved))
        saved.messagingPrivate = true
        #expect(!sent.isReflected(in: saved))
        // Une réponse sans messagerie ne prouve pas l'écriture d'un champ de messagerie envoyé.
        let withoutMessaging = SchoolNotificationPreferencesBody(courseOffers: true, courseReminders: true, courseChanges: true, courseStaffAlerts: true)
        #expect(!sent.isReflected(in: withoutMessaging))
        // Un corps sans messagerie n'exige rien d'elle.
        #expect(withoutMessaging.isReflected(in: sent))
    }

    private func messagingInfo(school: UUID, conversation: UUID, kind: String = "MESSAGING") -> [AnyHashable: Any] {
        ["kind": kind, "schoolId": school.uuidString.lowercased(), "conversationId": conversation.uuidString.lowercased(),
         "sequence": 4, "category": "MESSAGING_PRIVATE"]
    }

    @Test func readsTheSchoolAndConversationOfAMessagingAlert() {
        let school = UUID(), conversation = UUID(), received = Date(timeIntervalSince1970: 1_000)
        let target = SchoolPushCenter.messagingTarget(in: messagingInfo(school: school, conversation: conversation), receivedAt: received)
        #expect(target == MessagingNotificationTarget(schoolID: school, conversationID: conversation, receivedAt: received))
        #expect(SchoolPushCenter.messagingTarget(in: messagingInfo(school: school, conversation: conversation, kind: "COURSE")) == nil)
        #expect(SchoolPushCenter.messagingTarget(in: ["kind": "MESSAGING", "schoolId": school.uuidString.lowercased()]) == nil)
        #expect(SchoolPushCenter.messagingTarget(in: ["kind": "MESSAGING", "schoolId": "pas-un-uuid",
                                                       "conversationId": conversation.uuidString.lowercased()]) == nil)
        #expect(SchoolPushCenter.messagingTarget(in: ["seriesId": conversation.uuidString.lowercased()]) == nil)
        // Une alerte de cours garde son chemin.
        #expect(SchoolPushCenter.seriesID(in: messagingInfo(school: school, conversation: conversation)) == nil)
    }

    @Test func aMessagingAlertOpensMessagesOnlyForTheCurrentSchoolOutsideATrip() {
        let school = UUID(), other = UUID(), now = Date(timeIntervalSince1970: 5_000)
        let target = MessagingNotificationTarget(schoolID: school, conversationID: UUID(), receivedAt: now)
        func outcome(_ current: UUID?, available: Bool = true, trip: Bool = false, at date: Date = now) -> MessagingNotificationOpening.Outcome {
            MessagingNotificationOpening.outcome(for: target, currentSchoolID: current, messagesAvailable: available,
                                                 tripInProgress: trip, now: date)
        }
        #expect(outcome(school) == .open)
        #expect(outcome(other) == .otherSchool)
        // L'école ou Messages ne sont pas encore prêts : la demande attend sans rien ouvrir.
        #expect(outcome(nil) == .wait)
        #expect(outcome(school, available: false) == .wait)
        // Pas de fil de discussion sur un trajet en cours.
        #expect(outcome(school, trip: true) == .discard)
        // Une alerte touchée il y a trop longtemps n'ouvre rien à l'ouverture d'une autre session.
        #expect(outcome(school, at: now.addingTimeInterval(MessagingNotificationTarget.validity + 1)) == .discard)
        #expect(outcome(school, at: now.addingTimeInterval(MessagingNotificationTarget.validity)) == .open)
    }

    @Test func theTouchedConversationIsKeptUntilItIsConsumed() {
        let center = SchoolPushCenter.shared
        let target = MessagingNotificationTarget(schoolID: UUID(), conversationID: UUID())
        center.open(messaging: target)
        #expect(center.pendingMessagingTarget == target)
        #expect(center.consumePendingMessagingTarget() == target)
        #expect(center.pendingMessagingTarget == nil)
        #expect(center.consumePendingMessagingTarget() == nil)
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
