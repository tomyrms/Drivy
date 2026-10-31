#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Les vrais écrans, des transports et journaux exclusivement en mémoire.
/// Aucune connexion OIDC, requête réseau ou permission GPS n'est demandée.
struct SchoolAccountVisualReview: View {
    static let screenNames: Set<String> = ["sign-in", "sign-in-error", "sign-in-network-error", "sign-in-attempts", "sign-in-loading", "sign-in-unconfigured", "sign-in-recovery-ready", "sign-in-recovery-error", "account", "app-lock", "app-privacy",
        "access-code", "access-register", "access-register-long", "access-register-narrow", "access-opening", "school-opening",
        "join-code", "join-code-preview", "join-code-error", "join-code-pending", "join-code-confirmed",
        "join-link", "join-link-preview", "profile", "profile-error", "profile-instructor", "onboarding-welcome", "onboarding-information",
        "onboarding-formation", "onboarding-gps", "onboarding-review", "onboarding-ready", "onboarding-staff", "onboarding-known-identity"]
    let screen: String
    @State private var context: SchoolVisualContext?
    @State private var codeModel: SchoolCodeJoinWorkspace?
    @State private var linkModel: SchoolJoinWorkspace?
    @State private var profileModel: SchoolProfileWorkspace?
    @State private var accessModel: SchoolAccessWorkspace?
    @State private var openingModel: SchoolOpeningWorkspace?
    @State private var lock = AppLock(store: UserDefaults(suiteName: "ch.drivy.visual-review.lock")!)
    @State private var error: String?
    @State private var signInFailure: IdentityFailure?

    init(screen: String) {
        self.screen = screen
        let failure: IdentityFailure? = switch screen {
        case "sign-in-error": .invalidCredentials
        case "sign-in-network-error": .unavailable
        case "sign-in-attempts": .attempts
        default: nil
        }
        _signInFailure = State(initialValue: failure)
    }

    var body: some View {
        Group {
            if screen.hasPrefix("sign-in") {
                NavigationStack {
                    SchoolSignInLanding(isConfigured: screen != "sign-in-unconfigured", isWorking: screen == "sign-in-loading",
                        errorMessage: signInFailure?.localizedDescription,
                        signIn: { _, _ in }, joinWithCode: {}, clearError: { signInFailure = nil },
                        recoveryClient: recoveryClient, credentialsRejected: signInFailure == .invalidCredentials)
                        .navigationTitle("Drivy")
                }
            } else if screen == "app-lock" {
                AppLockView(lock: lock, automaticallyUnlocks: false)
            } else if screen == "app-privacy" {
                AppPrivacyShield()
            } else if let accessModel {
                SchoolAccessCodeView(model: accessModel)
                    // Fenêtre synthétique étroite, sans prétendre qualifier le multitâche réel d’iPadOS.
                    .frame(maxWidth: screen == "access-register-narrow" ? 320 : .infinity)
                    .frame(maxWidth: .infinity)
            } else if let openingModel {
                SchoolOpeningView(model: openingModel, openSchool: { _ in })
            } else if let codeModel {
                SchoolCodeJoinView(model: codeModel, openSchool: { _ in }, useLink: {}, loadsOnAppear: false)
            } else if let linkModel {
                SchoolJoinView(model: linkModel, openSchool: { _ in }, loadsOnAppear: false)
            } else if let profileModel {
                if screen.hasPrefix("onboarding-") {
                    SchoolOnboardingView(model: profileModel, trainings: context?.workspace.trainings ?? [],
                        loadsOnAppear: false, startsWithInformation: screen == "onboarding-information")
                } else if let context, profileModel.isOwnProfile {
                    // L’élève lit son dossier dans « Mon profil », sous son compte Drivy.
                    SchoolMyProfileView(workspace: context.workspace, dossier: profileModel, loadsDossierOnAppear: false)
                } else { SchoolProfileView(model: profileModel, loadsOnAppear: false) }
            } else if let context, screen == "account" {
                SchoolAccountView(isAuthenticated: true, workspace: context.workspace, manageURL: nil,
                    openProfile: {}, openInvitations: {}, openJoinSchool: {}, signOut: {})
            } else if let error {
                ContentUnavailableView("Rendu indisponible", systemImage: "exclamationmark.triangle", description: Text(error))
            } else { ProgressView("Préparation du rendu…") }
        }
        .task {
            guard context == nil, codeModel == nil, linkModel == nil, profileModel == nil, accessModel == nil, openingModel == nil else { return }
            do { try await prepare() } catch { self.error = error.localizedDescription }
        }
    }

    private var recoveryClient: SchoolAccountRecoveryClient {
        let configuration = AppConfiguration(apiBaseURL: URL(string: "https://visual.drivy.invalid")!,
            issuer: URL(string: "https://visual.drivy.invalid/identity")!, clientID: "visual", redirectURL: AppConfiguration.callback)
        return SchoolAccountRecoveryClient(configuration: configuration,
            transport: SchoolRecoveryVisualTransport(available: screen == "sign-in-recovery-ready", fails: screen == "sign-in-recovery-error"))
    }

    @MainActor private func prepare() async throws {
        if screen.hasPrefix("sign-in") || screen == "app-lock" || screen == "app-privacy" { return }
        if screen.hasPrefix("access-") || screen == "school-opening" {
            // Écrans de compte : aucun envoi, le modèle est posé directement dans l’état à regarder.
            let configuration = AppConfiguration(apiBaseURL: URL(string: "https://visual.drivy.invalid")!,
                issuer: URL(string: "https://visual.drivy.invalid/identity")!, clientID: "visual", redirectURL: AppConfiguration.callback)
            if screen == "school-opening" {
                openingModel = SchoolOpeningWorkspace(client: SchoolOpeningClient(configuration: configuration, tokenSource: SchoolAccountVisualToken()),
                                                      code: "K7Q4-MX2P", displayName: "Camille Rochat", email: "camille@example.invalid")
                return
            }
            let model = SchoolAccessWorkspace(client: SchoolAccountClient(configuration: configuration),
                                              identity: IdentitySession(configuration: configuration))
            switch screen {
            case "access-register", "access-register-long", "access-register-narrow":
                model.review(SchoolAccessPreview(kind: .learnerInvitation, schoolName: "Auto-école Horizon", expiresAt: "2026-10-22T12:00:00Z"),
                             input: .code("K7Q4-MX2P"))
                if screen != "access-register" {
                    model.firstName = "Jean-Baptiste Alexandre"
                    model.lastName = "De la Roche Montferrand"
                    model.email = "exemple@example.invalid"
                }
            case "access-opening":
                model.review(SchoolAccessPreview(kind: .schoolOpening, schoolName: nil, expiresAt: "2026-10-22T12:00:00Z"), input: .code("K7Q4-MX2P"))
            default:
                model.codeText = "K7Q4-MX2P"
            }
            accessModel = model
            return
        }
        if screen.hasPrefix("join-") {
            let configuration = AppConfiguration(apiBaseURL: URL(string: "https://visual.drivy.invalid")!,
                issuer: URL(string: "https://visual.drivy.invalid/identity")!, clientID: "visual", redirectURL: AppConfiguration.callback)
            let client = SchoolJoinClient(configuration: configuration, tokenSource: SchoolAccountVisualToken(),
                transport: SchoolAccountVisualJoinTransport(screen: screen))
            if screen.hasPrefix("join-code") {
                let model = SchoolCodeJoinWorkspace(client: client, store: SchoolAccountVisualCodeStore())
                await model.load()
                if screen != "join-code" { model.code = "ABCD-EFGH"; await model.inspect() }
                if screen == "join-code-pending" || screen == "join-code-confirmed" { await model.accept() }
                codeModel = model
            } else {
                let model = SchoolJoinWorkspace(client: client, journal: SchoolAccountVisualLinkStore())
                await model.load()
                if screen == "join-link-preview" {
                    model.link = "https://visual.drivy.invalid/app/invitation#token=" + String(repeating: "a", count: 43)
                    await model.inspect()
                }
                linkModel = model
            }
            return
        }
        let value = try await SchoolVisualData.prepare()
        context = value
        guard screen != "account", let school = value.workspace.school else { return }
        let scope = SchoolCommandScope(personID: SchoolVisualData.personID, schoolID: school.id,
            membershipID: SchoolVisualData.membershipID, accessEpoch: 1, apiBaseURL: "https://visual.drivy.invalid")
        let api = SchoolAccountVisualProfileAPI(school: school, scope: scope, screen: screen)
        let isStaff = screen == "onboarding-staff"
        let isInstructorProfile = screen == "profile-instructor"
        let outbox: any SchoolCommandOutbox = screen == "onboarding-known-identity" ? SchoolWelcomeVisualOutbox() : SchoolVisualOutbox()
        let model = SchoolProfileWorkspace(scope: scope, roles: isStaff || isInstructorProfile ? ["INSTRUCTOR"] : ["LEARNER"],
            learnerID: isStaff ? nil : SchoolVisualData.learnerID,
            isOwnProfile: !isInstructorProfile, onboardingKind: isInstructorProfile ? nil : (isStaff ? .staff : .student),
            api: api, outbox: outbox)
        await model.load()
        profileModel = model
    }
}

@MainActor private final class SchoolAccountVisualToken: AccessTokenSource {
    func accessToken() async throws -> String {
        let claims = try JSONSerialization.data(withJSONObject: ["iss": "https://visual.drivy.invalid/identity", "sub": "visual-only"])
        let encoded = claims.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "visual.\(encoded).not-a-real-signature"
    }
}

private struct SchoolAccountVisualJoinTransport: SchoolHTTPTransport {
    let screen: String
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url, url.host == "visual.drivy.invalid" else { throw SchoolJoinFailure.invalidResponse }
        if screen == "join-code-error" {
            return SchoolHTTPResponse(data: Data("{\"code\":\"INVITATION_CODE_INVALID\"}".utf8), status: 404,
                url: url, contentType: "application/problem+json")
        }
        if url.lastPathComponent == "accept", screen == "join-code-pending" { throw URLError(.notConnectedToInternet) }
        let membershipID = UUID(uuidString: "10000000-0000-4000-8000-000000000003")!
        let schoolID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let result: Data
        if url.lastPathComponent == "accept" {
            result = try JSONEncoder().encode(SchoolMembership(membershipId: membershipID,
                schoolId: schoolID, schoolName: "Auto-école du Val-de-Ruz", roles: ["LEARNER"], grants: [], accessEpoch: 1))
        } else if url.path.contains("/code/") {
            result = try JSONEncoder().encode(SchoolCodePreview(schoolName: "Auto-école du Val-de-Ruz", roles: ["LEARNER"],
                trainingCategoryCode: "B", expiresAt: "2026-10-06T10:00:00Z", trainingCategoryCodes: ["B", "A1"],
                profileIdentity: .init(firstName: "Camille", lastName: "Martin")))
        } else {
            result = try JSONEncoder().encode(SchoolJoinPreview(invitationId: UUID(uuidString: "10000000-0000-4000-8000-000000000009")!, schoolId: schoolID,
                schoolName: "Auto-école du Val-de-Ruz", roles: ["LEARNER"], maskedEmail: "c***@example.invalid", expiresAt: "2026-10-06T10:00:00Z",
                notice: SchoolJoinNotice(version: 1, noticeText: "Notice fictive : les leçons, trajets et bilans sont visibles dans votre dossier.",
                    retentionText: "La durée de conservation est fixée par l’école.", contactEmail: "contact@example.invalid"),
                profileIdentity: .init(firstName: "Camille", lastName: "Martin")))
        }
        let envelope = try JSONSerialization.data(withJSONObject: ["data": JSONSerialization.jsonObject(with: result),
            "requestId": UUID().uuidString, "serverTime": "2026-09-29T10:00:00Z"])
        return SchoolHTTPResponse(data: envelope, status: url.lastPathComponent == "accept" ? 201 : 200, url: url, contentType: "application/json")
    }
}

@MainActor private final class SchoolAccountVisualCodeStore: SchoolCodeJoinStore {
    private var value: SchoolCodeJoinRecord?
    func load(for principal: SchoolJoinPrincipal) throws -> SchoolCodeJoinRecord? { value?.principal == principal ? value : nil }
    func save(_ record: SchoolCodeJoinRecord) throws { value = record }
    func remove(_ record: SchoolCodeJoinRecord) throws { value = nil }
}

@MainActor private final class SchoolAccountVisualLinkStore: SchoolJoinStore {
    private var value: SchoolJoinRecord?
    func load(for principal: SchoolJoinPrincipal) throws -> SchoolJoinRecord? { value?.principal == principal ? value : nil }
    func save(_ record: SchoolJoinRecord) throws { value = record }
    func confirm(_ record: SchoolJoinRecord, receipt: SchoolOperationReceipt) throws -> SchoolJoinRecord {
        let result = record.confirmed(by: receipt); value = result; return result
    }
    func removeFreshRejection(_ record: SchoolJoinRecord) throws { value = nil }
}

@MainActor private final class SchoolAccountVisualProfileAPI: SchoolProfileAPI {
    let schoolValue: SchoolDetails
    let scope: SchoolCommandScope
    let screen: String
    private var savedWelcome: SchoolOnboarding?
    init(school: SchoolDetails, scope: SchoolCommandScope, screen: String) { schoolValue = school; self.scope = scope; self.screen = screen }
    func school(id: UUID) async throws -> SchoolDetails {
        if screen == "profile-error" { throw SchoolProfileFailure.unavailable }
        return schoolValue
    }
    func policies(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolProfilePolicy> {
        let rules: [SchoolProfileRule] = [
            .init(field: .firstName, requirement: .required, stage: .join, purposeCode: .identification, explanation: "Identifier votre dossier scolaire."),
            .init(field: .lastName, requirement: .required, stage: .join, purposeCode: .identification, explanation: "Identifier votre dossier scolaire."),
            .init(field: .contactEmail, requirement: .optional, stage: .optional, purposeCode: .lessonContact, explanation: "Vous contacter au sujet d’une leçon."),
            .init(field: .contactPhone, requirement: .optional, stage: .optional, purposeCode: .lessonContact, explanation: "Vous contacter au sujet d’une leçon.")]
        return SchoolPage(items: [.init(id: SchoolVisualData.policyID, schoolId: schoolID, version: 1, status: "PUBLISHED",
            effectiveFrom: "2026-09-24T10:00:00Z", fields: rules, noticeVersionId: SchoolVisualData.policyID, approvedByMembershipId: scope.membershipID)], nextCursor: nil)
    }
    func notice(schoolID: UUID, id: UUID?) async throws -> SchoolDataPolicy {
        SchoolDataPolicy(id: SchoolVisualData.policyID, schoolId: schoolID, version: 1, status: "APPROVED",
            noticeText: "Notice fictive : l’école utilise ces informations pour préparer les leçons.",
            retentionText: "La durée de conservation est fixée par l’école.", contactEmail: "contact@example.invalid",
            approvedAt: "2026-09-24T10:00:00Z", approvedByMembershipId: scope.membershipID, noticeVersionId: SchoolVisualData.policyID)
    }
    func profile(schoolID: UUID, learnerID: UUID) async throws -> SchoolAdministrativeProfile {
        SchoolAdministrativeProfile(id: SchoolVisualData.learnerID, schoolId: schoolID, version: 1, learnerId: learnerID,
            firstName: "Camille", lastName: "Perret", birthDate: nil, postalAddress: nil, contactEmail: "camille@example.invalid",
            contactPhone: nil, profilePhotoDocumentId: nil, updatedAt: "2026-09-24T10:00:00Z", enteredByMembershipId: scope.membershipID,
            entrySource: "SELF", policyVersionId: SchoolVisualData.policyID)
    }
    func readiness(schoolID: UUID, learnerID: UUID, action: String) async throws -> SchoolLearnerReadiness {
        .init(learnerId: learnerID, action: action, resourceId: nil, ready: true, blockers: [], policyVersionId: SchoolVisualData.policyID, computedAt: "2026-09-24T10:00:00Z")
    }
    func onboarding(schoolID: UUID, kind: SchoolOnboardingKind) async throws -> SchoolOnboarding {
        if let savedWelcome { return savedWelcome }
        let step: SchoolOnboardingStep
        switch screen {
        case "onboarding-formation": step = .formations
        case "onboarding-gps": step = .device
        case "onboarding-review", "onboarding-ready", "profile": step = .review
        default: step = .identity
        }
        return .init(id: SchoolVisualData.revisionID, schoolId: schoolID, version: 1, personId: scope.personID, membershipId: scope.membershipID,
            kind: kind, status: screen == "onboarding-ready" || screen == "profile" ? "COMPLETED" : "IN_PROGRESS", currentStep: step,
            skippedOptionalSteps: [], policyVersionId: SchoolVisualData.policyID, lastSavedAt: "2026-09-24T10:00:00Z",
            pendingActions: [], returnDestinationKey: nil, returnResourceId: nil)
    }
    func operation(schoolID: UUID, id: UUID) async throws -> SchoolOperationReceipt { throw SchoolProfileFailure.operationUnknown }
    func send(_ command: PendingSchoolCommand) async throws -> SchoolProfileResult {
        if ProcessInfo.processInfo.environment["DRIVY_VISUAL_FORBID_PROFILE_WRITES"] == "1" {
            preconditionFailure("Une lecture de confidentialité a tenté une écriture dans la fixture.")
        }
        guard screen == "onboarding-known-identity" else { throw SchoolProfileFailure.unavailable }
        precondition(command.kind == .saveOnboarding, "Ce parcours ne doit ni renvoyer les noms déjà connus ni terminer l’accueil à la place de l’élève.")
        struct StepCommand: Decodable { let kind: SchoolOnboardingKind; let currentStep: SchoolOnboardingStep }
        let body = try JSONDecoder().decode(StepCommand.self, from: command.body)
        let previous = try await onboarding(schoolID: scope.schoolID, kind: body.kind)
        guard command.resourceVersion == previous.version else { throw SchoolProfileFailure.conflict }
        let value = SchoolOnboarding(id: previous.id, schoolId: previous.schoolId, version: previous.version + 1,
            personId: previous.personId, membershipId: previous.membershipId, kind: body.kind,
            status: body.currentStep == .review ? "READY" : "IN_PROGRESS", currentStep: body.currentStep,
            skippedOptionalSteps: [], policyVersionId: previous.policyVersionId, lastSavedAt: "2026-10-17T10:00:00Z",
            pendingActions: body.currentStep == .review ? [] : [.init(code: "ONBOARDING_REVIEW_REQUIRED", message: "Relis ton accueil.",
                field: nil, purpose: nil, resourceId: nil, destinationKey: "PROFILE")], returnDestinationKey: nil, returnResourceId: nil)
        savedWelcome = value
        return .onboarding(value)
    }
}

private struct SchoolRecoveryVisualTransport: SchoolHTTPTransport {
    let available: Bool
    var fails = false
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        if fails { throw URLError(.notConnectedToInternet) }
        let url: Any = available ? "https://visual.drivy.invalid/app/recover" : NSNull()
        let payload = try JSONSerialization.data(withJSONObject: ["data": ["available": available, "recoveryUrl": url],
                                                                 "serverTime": "2026-10-26T12:00:00Z"])
        return SchoolHTTPResponse(data: payload, status: 200, url: request.url!, contentType: "application/json")
    }
}

/// Journal exclusivement en mémoire pour le parcours UI synthétique, isolé des rendus sans écriture.
@MainActor private final class SchoolWelcomeVisualOutbox: SchoolCommandOutbox {
    private var command: PendingSchoolCommand?
    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand? { command?.scope == scope ? command : nil }
    func save(_ command: PendingSchoolCommand) throws { self.command = command }
    func remove(_ command: PendingSchoolCommand) throws {
        guard self.command?.id == command.id else { throw SchoolConfigurationFailure.storage }
        self.command = nil
    }
}
#endif
