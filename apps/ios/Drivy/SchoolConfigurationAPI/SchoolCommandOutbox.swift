import CryptoKit
import Darwin
import Foundation

struct SchoolCommandScope: Codable, Sendable, Equatable {
    let personID: UUID
    let schoolID: UUID
    let membershipID: UUID
    let accessEpoch: Int
    let apiBaseURL: String

    func belongsToWorkspace(_ other: SchoolCommandScope) -> Bool {
        personID == other.personID && schoolID == other.schoolID && apiBaseURL == other.apiBaseURL
    }
}

enum SchoolCommandKind: String, Codable, Sendable {
    case updateSchool, saveSetup, activate, saveDataPolicy
    case createInvitation, resendInvitation, revokeInvitation
    case createProfilePolicy, publishProfilePolicy, updateProfile, saveOnboarding, completeOnboarding
    case createOffering, createCurriculum, createCatalogPolicy, createTraining, createAssignment, updateMember
    case createLesson, moveLesson, cancelLesson, createCommercialTerms, createServiceProduct
    case createAvailabilityRule, updateAvailabilityRule, createClosure, removeAvailabilityRule, removeClosure
    case savePreparation, saveWish, completeLesson, saveReportDraft, publishReportDraft

    var isPlanning: Bool {
        switch self {
        case .createLesson, .moveLesson, .cancelLesson, .createCommercialTerms, .createServiceProduct,
             .createAvailabilityRule, .updateAvailabilityRule, .createClosure, .removeAvailabilityRule, .removeClosure: true
        default: false
        }
    }
    var isReport: Bool {
        switch self {
        case .savePreparation, .saveWish, .completeLesson, .saveReportDraft, .publishReportDraft: true
        default: false
        }
    }

    var isCatalog: Bool {
        switch self {
        case .createOffering, .createCurriculum, .createCatalogPolicy, .createTraining, .createAssignment, .updateMember: true
        default: false
        }
    }

    var isProfile: Bool {
        switch self {
        case .createProfilePolicy, .publishProfilePolicy, .updateProfile, .saveOnboarding, .completeOnboarding: true
        default: false
        }
    }

    var isConfiguration: Bool { !isInvitation && !isProfile && !isCatalog && !isPlanning && !isReport }

    var isInvitation: Bool {
        switch self {
        case .createInvitation, .resendInvitation, .revokeInvitation: true
        default: false
        }
    }

    var operationType: String {
        switch self {
        case .updateSchool: "UPDATE_SCHOOL"
        case .saveSetup: "SAVE_SCHOOL_SETUP"
        case .activate: "ACTIVATE_SCHOOL"
        case .saveDataPolicy: "ADOPT_SCHOOL_DATA_POLICY"
        case .createInvitation: "CREATE_INVITATION"
        case .resendInvitation: "RESEND_INVITATION"
        case .revokeInvitation: "REVOKE_INVITATION"
        case .createProfilePolicy: "CREATE_PROFILE_FIELD_POLICY"
        case .publishProfilePolicy: "PUBLISH_PROFILE_FIELD_POLICY"
        case .updateProfile: "UPDATE_ADMINISTRATIVE_PROFILE"
        case .saveOnboarding: "SAVE_ONBOARDING"
        case .completeOnboarding: "COMPLETE_ONBOARDING"
        case .createOffering: "CREATE_OFFERING_VERSION"
        case .createCurriculum: "CREATE_CURRICULUM_VERSION"
        case .createCatalogPolicy: "CREATE_SCHOOL_POLICY"
        case .createTraining: "CREATE_TRAINING"
        case .createAssignment: "CREATE_ASSIGNMENT"
        case .updateMember: "UPDATE_MEMBER"
        case .createLesson: "CREATE_LESSON"
        case .moveLesson: "MOVE_LESSON"
        case .cancelLesson: "CANCEL_LESSON"
        case .createCommercialTerms: "CREATE_COMMERCIAL_TERMS"
        case .createServiceProduct: "CREATE_SERVICE_PRODUCT"
        case .createAvailabilityRule: "CREATE_AVAILABILITY_RULE"
        case .updateAvailabilityRule: "UPDATE_AVAILABILITY_RULE"
        case .createClosure: "CREATE_CLOSURE"
        case .removeAvailabilityRule: "REMOVE_AVAILABILITY_RULE"
        case .removeClosure: "REMOVE_CLOSURE"
        case .savePreparation: "SAVE_PREPARATION"
        case .saveWish: "SAVE_WISH"
        case .completeLesson: "COMPLETE_LESSON"
        case .saveReportDraft: "SAVE_REPORT_DRAFT"
        case .publishReportDraft: "PUBLISH_REPORT_DRAFT"
        }
    }

    var resourceType: String {
        switch self {
        case .updateSchool, .activate: "School"
        case .saveSetup: "SchoolSetup"
        case .saveDataPolicy: "SchoolDataPolicy"
        case .createInvitation, .resendInvitation, .revokeInvitation: "Invitation"
        case .createProfilePolicy, .publishProfilePolicy: "ProfileFieldPolicy"
        case .updateProfile: "AdministrativeProfile"
        case .saveOnboarding, .completeOnboarding: "OnboardingProgress"
        case .createOffering: "Offering"
        case .createCurriculum: "Curriculum"
        case .createCatalogPolicy: "SchoolPolicy"
        case .createTraining: "Training"
        case .createAssignment: "Assignment"
        case .updateMember: "Member"
        case .createLesson, .moveLesson, .cancelLesson, .completeLesson: "Lesson"
        case .createCommercialTerms: "CommercialTermsVersion"
        case .createServiceProduct: "ServiceProductVersion"
        case .createAvailabilityRule, .updateAvailabilityRule, .removeAvailabilityRule: "AvailabilityRule"
        case .createClosure, .removeClosure: "Closure"
        case .savePreparation: "Preparation"
        case .saveWish: "Wish"
        case .saveReportDraft: "ReportDraft"
        case .publishReportDraft: "ReportRevision"
        }
    }
}

struct PendingSchoolCommand: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let scope: SchoolCommandScope
    let kind: SchoolCommandKind
    let resourceVersion: Int
    let createdAt: Date
    let body: Data
    // Absent in v1 G1B archives; creation has no server resource identifier yet.
    let resourceID: UUID?
    let routeResourceID: UUID?
    let expectedVersion: Int?

    var ifMatchVersion: Int { expectedVersion ?? resourceVersion }

    init(id: UUID, scope: SchoolCommandScope, kind: SchoolCommandKind, resourceVersion: Int,
         createdAt: Date, body: Data, resourceID: UUID? = nil, routeResourceID: UUID? = nil, expectedVersion: Int? = nil) {
        self.id = id; self.scope = scope; self.kind = kind; self.resourceVersion = resourceVersion
        self.createdAt = createdAt; self.body = body; self.resourceID = resourceID
        self.routeResourceID = routeResourceID; self.expectedVersion = expectedVersion
    }

    var hasValidTarget: Bool {
        if !kind.isProfile && !kind.isCatalog && !kind.isPlanning && !kind.isReport && (routeResourceID != nil || expectedVersion != nil) { return false }
        switch kind {
        case .createCommercialTerms, .createServiceProduct, .createAvailabilityRule, .createClosure:
            return resourceVersion == 0 && resourceID == nil && routeResourceID == nil && expectedVersion == nil
        case .createLesson:
            return resourceVersion == 0 && resourceID == nil && routeResourceID != nil && expectedVersion == nil
        case .moveLesson, .cancelLesson, .updateAvailabilityRule, .removeAvailabilityRule, .removeClosure, .completeLesson, .saveReportDraft:
            return resourceVersion > 0 && resourceID != nil && routeResourceID == nil && expectedVersion == nil
        case .savePreparation, .saveWish:
            return resourceVersion > 0 && resourceID != nil && routeResourceID != nil && expectedVersion == nil
        case .publishReportDraft:
            return resourceVersion == 0 && resourceID == nil && routeResourceID != nil && (expectedVersion ?? 0) > 0
        case .createOffering, .createCurriculum, .createCatalogPolicy:
            return resourceVersion == 0 && resourceID == nil && routeResourceID == nil && expectedVersion == nil
        case .createTraining, .createAssignment:
            return resourceVersion == 0 && resourceID == nil && routeResourceID != nil && expectedVersion == nil
        case .updateMember:
            return resourceVersion > 0 && resourceID != nil && routeResourceID == nil && expectedVersion == nil
        case .createProfilePolicy: return resourceVersion == 0 && resourceID == nil && routeResourceID == nil && ifMatchVersion > 0
        case .updateProfile: return resourceVersion > 0 && resourceID != nil && routeResourceID != nil && expectedVersion == nil
        case .publishProfilePolicy, .saveOnboarding, .completeOnboarding: return resourceVersion > 0 && resourceID != nil && routeResourceID == nil && expectedVersion == nil
        case .createInvitation: return resourceVersion == 0 && resourceID == nil
        case .resendInvitation, .revokeInvitation: return resourceVersion > 0 && resourceID != nil
        default: return resourceVersion > 0 && resourceID == nil
        }
    }

    func matches(_ receipt: SchoolOperationReceipt) -> Bool {
        guard hasValidTarget else { return false }
        let expectedID = kind.isConfiguration ? scope.schoolID : resourceID
        return receipt.operationId == id && receipt.commandType == kind.operationType
            && receipt.resourceType == kind.resourceType && receipt.resourceVersion > resourceVersion
            && (expectedID == nil || receipt.resourceId == expectedID)
    }
}

@MainActor
protocol SchoolCommandOutbox: AnyObject {
    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand?
    func save(_ command: PendingSchoolCommand) throws
    func remove(_ command: PendingSchoolCommand) throws
}

/// Persist before emission. Only encrypted bytes reach disk; an uncertain
/// command keeps the exact request and operation identifier across launches.
@MainActor
final class EncryptedSchoolCommandOutbox: SchoolCommandOutbox {
    private let directory: URL
    private let suppliedKey: Data?
    private let vault: any IdentityVault
    private let authenticatedData = Data("drivy-school-commands-v1".utf8)
    // JSON encodes request Data as base64, larger than the original request.
    private let maximumArchiveBytes = 14_000_000
    private var file: URL { directory.appendingPathComponent("pending-v1.bin") }

    init(directory: URL? = nil, keyData: Data? = nil, vault: (any IdentityVault)? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SchoolCommands", isDirectory: true)
        suppliedKey = keyData
        self.vault = vault ?? KeychainIdentityVault(service: "ch.drivy.school-commands.key-v1")
    }

    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand? {
        // Preserve uncertainty after rights change. The caller must compare the
        // full scope before retrying; another account never sees this command.
        try read().first { $0.scope.belongsToWorkspace(scope) }
    }

    func save(_ command: PendingSchoolCommand) throws {
        try validate(command)
        var commands = try read()
        if let existing = commands.first(where: { $0.scope.belongsToWorkspace(command.scope) || $0.id == command.id }) {
            guard existing == command else { throw SchoolConfigurationFailure.pendingCommand }
            try synchronize()
            return
        }
        guard commands.count < 50 else { throw SchoolConfigurationFailure.storage }
        commands.append(command)
        try write(commands)
    }

    func remove(_ command: PendingSchoolCommand) throws {
        var commands = try read()
        guard let index = commands.firstIndex(where: { $0.id == command.id }) else { return }
        guard commands[index] == command else { throw SchoolConfigurationFailure.storage }
        commands.remove(at: index)
        try write(commands)
    }

    private func read() throws -> [PendingSchoolCommand] {
        do {
            let manager = FileManager.default
            guard manager.fileExists(atPath: directory.path) else { return [] }
            guard try manager.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else {
                throw SchoolConfigurationFailure.storage
            }
            guard manager.fileExists(atPath: file.path) else { return [] }
            let attributes = try manager.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let bytes = attributes[.size] as? NSNumber, bytes.intValue <= maximumArchiveBytes else {
                throw SchoolConfigurationFailure.storage
            }
            let encrypted = try Data(contentsOf: file)
            guard encrypted.count <= maximumArchiveBytes else { throw SchoolConfigurationFailure.storage }
            let box = try AES.GCM.SealedBox(combined: encrypted)
            let clear = try AES.GCM.open(box, using: key(create: false), authenticating: authenticatedData)
            let archive = try JSONDecoder().decode(Archive.self, from: clear)
            guard archive.version == 1, archive.commands.count <= 50,
                  Set(archive.commands.map(\.id)).count == archive.commands.count else { throw SchoolConfigurationFailure.storage }
            for (index, command) in archive.commands.enumerated() {
                try validate(command)
                guard !archive.commands.prefix(index).contains(where: { $0.scope.belongsToWorkspace(command.scope) }) else {
                    throw SchoolConfigurationFailure.storage
                }
            }
            return archive.commands
        } catch { throw SchoolConfigurationFailure.storage }
    }

    private func write(_ commands: [PendingSchoolCommand]) throws {
        do {
            let data = try JSONEncoder().encode(Archive(version: 1, commands: commands))
            guard data.count + 28 <= maximumArchiveBytes else { throw SchoolConfigurationFailure.storage }
            let box = try AES.GCM.seal(data, using: key(create: true), authenticating: authenticatedData)
            guard let encrypted = box.combined else { throw SchoolConfigurationFailure.storage }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            var protectedDirectory = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedDirectory.setResourceValues(values)
            try encrypted.write(to: file, options: [.atomic, .completeFileProtection])
            try synchronize()
        } catch { throw SchoolConfigurationFailure.storage }
    }

    private func validate(_ command: PendingSchoolCommand) throws {
        let scope = command.scope
        guard command.hasValidTarget, scope.accessEpoch > 0,
              command.createdAt.timeIntervalSince1970.isFinite,
              !command.body.isEmpty, command.body.count <= 200_000,
              scope.apiBaseURL.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let endpoint = URLComponents(string: scope.apiBaseURL), endpoint.scheme == "https",
              let host = endpoint.host, !host.isEmpty, endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil,
              let payload = try? JSONSerialization.jsonObject(with: command.body) as? [String: Any],
              let operation = payload["operationId"] as? String, UUID(uuidString: operation) == command.id else {
            throw SchoolConfigurationFailure.storage
        }
    }

    private func synchronize() throws {
        // Atomic replacement plus a storage barrier precede every emission,
        // including a retry after a previous barrier error. No plaintext temp.
        try file.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw SchoolConfigurationFailure.storage }
            let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            guard descriptor >= 0 else { throw SchoolConfigurationFailure.storage }
            defer { Darwin.close(descriptor) }
            guard Darwin.fcntl(descriptor, F_FULLFSYNC) == 0 else { throw SchoolConfigurationFailure.storage }
        }
        try directory.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw SchoolConfigurationFailure.storage }
            let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_DIRECTORY)
            guard descriptor >= 0 else { throw SchoolConfigurationFailure.storage }
            defer { Darwin.close(descriptor) }
            guard Darwin.fsync(descriptor) == 0 else { throw SchoolConfigurationFailure.storage }
        }
    }

    private func key(create: Bool) throws -> SymmetricKey {
        if let suppliedKey {
            guard suppliedKey.count == 32 else { throw SchoolConfigurationFailure.storage }
            return SymmetricKey(data: suppliedKey)
        }
        if let data = try vault.read() {
            guard data.count == 32 else { throw SchoolConfigurationFailure.storage }
            return SymmetricKey(data: data)
        }
        guard create else { throw SchoolConfigurationFailure.storage }
        let generated = SymmetricKey(size: .bits256)
        try vault.write(generated.withUnsafeBytes { Data($0) })
        return generated
    }

    private struct Archive: Codable {
        let version: Int
        let commands: [PendingSchoolCommand]
    }
}
