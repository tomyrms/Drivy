import Foundation
import Testing
@testable import Drivy

struct SchoolEntryDestinationTests {
    @Test func schoolActivationAlwaysPrecedesTheRoleTabs() {
        for roles in [["ADMIN"], ["ADMIN", "INSTRUCTOR"], ["ADMIN", "LEARNER"]] {
            #expect(SchoolEntryDestination.resolve(schoolStatus: "DRAFT", roles: roles) == .prepareSchool)
        }
        for roles in [["INSTRUCTOR"], ["LEARNER"], ["INSTRUCTOR", "LEARNER"]] {
            #expect(SchoolEntryDestination.resolve(schoolStatus: "DRAFT", roles: roles) == .waitingForActivation)
        }
        for roles in [["ADMIN"], ["INSTRUCTOR"], ["LEARNER"], ["ADMIN", "INSTRUCTOR"]] {
            #expect(SchoolEntryDestination.resolve(schoolStatus: "ARCHIVED", roles: roles) == .archived)
        }
    }

    @Test func activeAdministrationAndFieldRolesHaveDifferentDestinations() {
        #expect(SchoolEntryDestination.resolve(schoolStatus: "ACTIVE", roles: ["ADMIN"]) == .management)
        #expect(SchoolEntryDestination.resolve(schoolStatus: "ACTIVE", roles: ["INSTRUCTOR"]) == .instructor)
        #expect(SchoolEntryDestination.resolve(schoolStatus: "ACTIVE", roles: ["ADMIN", "INSTRUCTOR"]) == .instructor)
        #expect(SchoolEntryDestination.resolve(schoolStatus: "ACTIVE", roles: ["LEARNER"]) == .learner)
        #expect(SchoolEntryDestination.resolve(schoolStatus: "ACTIVE", roles: ["ADMIN", "LEARNER"]) == .learner)
        #expect(SchoolEntryDestination.resolve(schoolStatus: "ACTIVE", roles: []) == .unavailable)
        #expect(SchoolEntryDestination.resolve(schoolStatus: "UNKNOWN", roles: ["INSTRUCTOR"]) == .unavailable)
        #expect(SchoolEntryDestination.resolve(schoolStatus: nil, roles: ["ADMIN"]) == .loading)
        #expect(SchoolEntryDestination.resolve(schoolStatus: nil, roles: nil) == .chooseSchool)
    }

    @Test func personalWelcomeRequiresAnActiveSchoolAndAFieldRole() {
        for status in [nil, "DRAFT", "ARCHIVED", "UNKNOWN"] as [String?] {
            for roles in [["ADMIN", "INSTRUCTOR"], ["INSTRUCTOR"], ["LEARNER"]] {
                #expect(!SchoolEntryDestination.allowsPersonalOnboarding(schoolStatus: status, roles: roles))
            }
        }
        #expect(!SchoolEntryDestination.allowsPersonalOnboarding(schoolStatus: "ACTIVE", roles: ["ADMIN"]))
        #expect(SchoolEntryDestination.allowsPersonalOnboarding(schoolStatus: "ACTIVE", roles: ["INSTRUCTOR"]))
        #expect(SchoolEntryDestination.allowsPersonalOnboarding(schoolStatus: "ACTIVE", roles: ["LEARNER"]))
    }

    @Test func webPreparationUsesTheConfiguredOriginAndOnlyTheSchoolIdentifier() {
        let school = UUID(uuidString: "AAAAAAAA-1111-4111-8111-111111111111")!
        let configuration = AppConfiguration(apiBaseURL: URL(string: "https://drivy.example.test:8443/refonte")!,
            issuer: URL(string: "https://identity.example.test")!, clientID: "drivy-apple", redirectURL: AppConfiguration.callback)
        #expect(configuration.managementURL(schoolID: school)?.absoluteString == "https://drivy.example.test:8443/app/gestion/aaaaaaaa-1111-4111-8111-111111111111")
        #expect(configuration.managementURL(schoolID: school, preparation: true)?.absoluteString == "https://drivy.example.test:8443/app/gestion/aaaaaaaa-1111-4111-8111-111111111111/apercu")
        #expect(configuration.managementURL(schoolID: school, preparation: true)?.query == nil)
        #expect(configuration.managementURL(schoolID: school, preparation: true)?.fragment == nil)
    }

    @Test func GPSManagementOpensTheSchoolSettingDirectly() throws {
        let school = UUID(uuidString: "AAAAAAAA-1111-4111-8111-111111111111")!
        let configuration = AppConfiguration(apiBaseURL: URL(string: "https://drivy.example.test:8443/refonte")!,
            issuer: URL(string: "https://identity.example.test")!, clientID: "drivy-apple", redirectURL: AppConfiguration.callback)
        let url = try #require(configuration.gpsManagementURL(schoolID: school))
        #expect(url.absoluteString == "https://drivy.example.test:8443/app/gestion/aaaaaaaa-1111-4111-8111-111111111111/confidentialite?focus=school-gps")
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.queryItems == [URLQueryItem(name: "focus", value: "school-gps")])
        #expect(parts.fragment == nil && parts.user == nil && parts.password == nil)
    }
}
