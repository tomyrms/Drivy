import XCTest
import SwiftUI
@testable import Drivy

final class MessagingEntryTests: XCTestCase {
    @MainActor
    func testMessagingEntryIsAbsentUnlessExplicitlyComposed() {
        XCTAssertNil(EnvironmentValues().schoolMessagingEntry)
    }

    func testInactiveSchoolIsDeniedInEveryBuild() {
        for arguments in [[], ["-messaging-development"], ["-messaging-ui-fixture"]] {
            XCTAssertFalse(SchoolMessagingDevelopment.permitted(arguments: arguments, schoolIsActive: false))
        }
    }

    func testQualificationBuildDoesNotNeedSimulatorOrLaunchArguments() {
        #if DRIVY_MESSAGING_QUALIFICATION
        XCTAssertTrue(SchoolMessagingDevelopment.isQualificationBuild)
        XCTAssertTrue(SchoolMessagingDevelopment.permitted(arguments: [], schoolIsActive: true))
        #else
        XCTAssertFalse(SchoolMessagingDevelopment.isQualificationBuild)
        XCTAssertFalse(SchoolMessagingDevelopment.permitted(arguments: [], schoolIsActive: true))
        XCTAssertFalse(SchoolMessagingDevelopment.permitted(arguments: ["-messaging-qualification"], schoolIsActive: true))
        XCTAssertFalse(SchoolMessagingDevelopment.permitted(arguments: ["-messaging-ui-fixture"], schoolIsActive: true))
        #endif
    }

    func testDevelopmentLaunchArgumentNeverEnablesOrdinaryDeviceBuild() {
        #if DRIVY_MESSAGING_QUALIFICATION || (DEBUG && targetEnvironment(simulator))
        XCTAssertTrue(SchoolMessagingDevelopment.permitted(arguments: ["-messaging-development"], schoolIsActive: true))
        #else
        XCTAssertFalse(SchoolMessagingDevelopment.permitted(arguments: ["-messaging-development"], schoolIsActive: true))
        #endif
    }

    @MainActor
    func testCompositionRequiresCurrentScopeAndMatchingPermittedURL() {
        let url = URL(string: "https://messaging.example.invalid/")!
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: url.absoluteString)
        let token = MessagingEntryToken()
        XCTAssertNil(MessagingDevelopmentEntry.make(scope: scope, baseURL: url, tokenSource: token,
            arguments: ["-messaging-development"], currentScope: { nil }))
        let changed = MessagingScope(accountID: scope.accountID, schoolID: scope.schoolID,
            accessEpoch: 2, apiBaseURL: scope.apiBaseURL)
        XCTAssertNil(MessagingDevelopmentEntry.make(scope: scope, baseURL: url, tokenSource: token,
            arguments: ["-messaging-development"], currentScope: { changed }))
        XCTAssertNil(MessagingDevelopmentEntry.make(scope: scope,
            baseURL: URL(string: "https://other.example.invalid/")!, tokenSource: token,
            arguments: ["-messaging-development"], currentScope: { scope }))
        let insecureURL = URL(string: "http://messaging.example.invalid/")!
        let insecure = MessagingScope(accountID: scope.accountID, schoolID: scope.schoolID,
            accessEpoch: 1, apiBaseURL: insecureURL.absoluteString)
        XCTAssertNil(MessagingDevelopmentEntry.make(scope: insecure, baseURL: insecureURL, tokenSource: token,
            arguments: ["-messaging-development"], currentScope: { insecure }))
        XCTAssertEqual(token.requests, 0, "La composition ne doit pas demander de jeton avant ouverture")
    }

    @MainActor
    func testQualificationCompositionExistsWithoutLaunchArgumentsAndIsMarkedTest() throws {
        let url = URL(string: "https://messaging.example.invalid/")!
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: url.absoluteString)
        let token = MessagingEntryToken()
        let entry = MessagingDevelopmentEntry.make(scope: scope, baseURL: url, tokenSource: token,
            arguments: [], currentScope: { scope })
        #if DRIVY_MESSAGING_QUALIFICATION
        XCTAssertTrue(try XCTUnwrap(entry).isQualification)
        #else
        XCTAssertNil(entry)
        #endif
        XCTAssertEqual(token.requests, 0)
    }
}

@MainActor private final class MessagingEntryToken: AccessTokenSource {
    private(set) var requests = 0
    func accessToken() async throws -> String {
        requests += 1
        throw MessagingFailure.accessChanged
    }
}
