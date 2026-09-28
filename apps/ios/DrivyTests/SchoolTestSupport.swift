import Foundation
import Testing
@testable import Drivy

// Outbox et données de test partagées par les suites de l’école.
@MainActor
final class ConfigurationOutboxStub: SchoolCommandOutbox {
    var value: PendingSchoolCommand?
    var saves: [PendingSchoolCommand] = []
    var removals: [PendingSchoolCommand] = []
    var failSave = false
    var failRead = false
    init(value: PendingSchoolCommand? = nil) { self.value = value }
    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand? {
        if failRead { throw SchoolConfigurationFailure.storage }
        return value
    }
    func save(_ command: PendingSchoolCommand) throws {
        if failSave { throw SchoolConfigurationFailure.storage }
        if let value, value != command { throw SchoolConfigurationFailure.pendingCommand }
        saves.append(command)
        value = command
    }
    func remove(_ command: PendingSchoolCommand) throws {
        guard value == command else { throw SchoolConfigurationFailure.storage }
        removals.append(command)
        value = nil
    }
}

enum ConfigurationFixture {
    static let schoolID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
    static let personID = UUID(uuidString: "30000000-0000-4000-8000-000000000002")!
    static let membershipID = UUID(uuidString: "30000000-0000-4000-8000-000000000003")!
    static let timestamp = "2026-09-24T15:00:00Z"
    static func scope(epoch: Int = 1) -> SchoolCommandScope {
        .init(personID: personID, schoolID: schoolID, membershipID: membershipID, accessEpoch: epoch, apiBaseURL: "https://api.example.invalid")
    }
    static func school(version: Int = 1, name: String = "École de test", status: String = "DRAFT") -> SchoolDetails {
        .init(id: schoolID, schoolId: schoolID, version: version, name: name, timeZone: "Europe/Zurich", status: status,
            contactEmail: "ecole@example.invalid", contactPhone: nil, logoAssetId: nil,
            modules: .init(gpsEnabled: false, packsEnabled: false, collectiveCoursesEnabled: false, courseOffersVisibleByDefault: false), configurationVersion: version)
    }
    static func policy(approved: Bool = false) -> SchoolDataPolicy {
        .init(id: schoolID, schoolId: schoolID, version: 1, status: approved ? "APPROVED" : "DRAFT",
            noticeText: approved ? "Information rédigée et adoptée." : "", retentionText: approved ? "Conservation définie et adoptée." : "",
            contactEmail: approved ? "ecole@example.invalid" : nil, approvedAt: approved ? timestamp : nil,
            approvedByMembershipId: approved ? membershipID : nil)
    }
    static func readiness(version: Int = 1, ready: Bool = true) -> SchoolReadiness {
        let blocker = SchoolActionBlocker(code: "SCHOOL_NOT_ACTIVE", message: "École à activer", field: nil, purpose: nil, resourceId: nil, destinationKey: nil)
        return .init(schoolId: schoolID, configurationVersion: version, computedAt: timestamp,
            capabilities: ["CAN_USE_WORKSPACE", "CAN_PLAN_LESSON", "CAN_CAPTURE", "CAN_PUBLISH_COURSE"].map {
                .init(capability: $0, ready: false, blockers: [blocker])
            }, activationReady: ready, activationBlockers: ready ? [] : [SchoolActionBlocker(code: "POLICY_REVIEW_REQUIRED",
                message: "Les textes d’information et de conservation doivent être adoptés.", field: nil, purpose: nil, resourceId: nil, destinationKey: "DATA")])
    }
    static func setup(version: Int = 1) -> SchoolSetup {
        .init(id: schoolID, schoolId: schoolID, version: version, status: "IN_PROGRESS", currentStep: "IDENTITY",
            completedSteps: [], lastSavedAt: timestamp, configuredByMembershipId: membershipID, readiness: readiness())
    }
    static func command() throws -> PendingSchoolCommand {
        let id = UUID()
        return .init(id: id, scope: scope(), kind: .updateSchool, resourceVersion: 1, createdAt: Date(),
            body: try JSONEncoder().encode(SchoolIdentityCommand(operationId: id, name: "Nom en attente", timeZone: "Europe/Zurich",
                contactEmail: "ecole@example.invalid", contactPhone: nil, impactConfirmed: true)))
    }
    static func receipt(_ command: PendingSchoolCommand) -> SchoolOperationReceipt {
        .init(operationId: command.id, commandType: "UPDATE_SCHOOL", resourceType: "School", resourceId: command.scope.schoolID,
            committedAt: timestamp, resourceVersion: command.resourceVersion + 1)
    }
}
