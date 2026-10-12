import Observation
import SwiftUI

/// Something the person signed in has to do, and can do from here. Never a status to look at: an action
/// exists only when the data shows it is pending and when this person holds the means to resolve it.
/// What someone else must do (a learner's own consent, a setting kept on the web) is not an action here.
struct SchoolRequiredAction: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        /// A lesson started whose planned end has passed: its instructor records how it went.
        case finishLesson
        /// A learner's profile lacks information the school requires: whoever may edit it completes it.
        case completeLearnerProfile
        /// The learner has not answered the school's recording notice.
        case giveRecordingConsent
        /// The guided welcome was left unfinished.
        case resumeOnboarding
    }
    enum Recipient: Equatable { case instructor, administrator, learner }

    let kind: Kind
    /// The lesson or the learner concerned; nil when the action concerns the account itself.
    let entityID: UUID?
    let recipient: Recipient
    /// What to do, in words: never « à vérifier » alone.
    let title: String

    var id: String { "\(kind.rawValue):\(entityID?.uuidString ?? "account")" }

    /// The tab where the action is resolved. One action, one tab: the same thing never lights two.
    var tab: SchoolHomeTab {
        switch kind {
        case .finishLesson: .session
        case .completeLearnerProfile: .learners
        case .giveRecordingConsent, .resumeOnboarding: .profile
        }
    }
}

/// The pending actions of the account in its current school, in one place. Each source replaces its own
/// kind when the data it already reads changes, so an indicator disappears as soon as the action is
/// resolved and no screen keeps a state of its own. Nothing is stored: a relaunch reads the data again.
@MainActor @Observable
final class SchoolRequiredActionStore {
    private(set) var actions: [SchoolRequiredAction] = []

    /// The current state of one kind of action, as its source reads it.
    func replace(_ kind: SchoolRequiredAction.Kind, with pending: [SchoolRequiredAction]) {
        let next = actions.filter { $0.kind != kind } + pending.filter { $0.kind == kind }
        if next != actions { actions = next }
    }

    /// One action is done, or turned out not to apply: its indicators go at once, before any reread.
    func resolve(_ kind: SchoolRequiredAction.Kind, entityID: UUID?) {
        let next = actions.filter { !($0.kind == kind && $0.entityID == entityID) }
        if next != actions { actions = next }
    }

    /// Another account, school or set of rights: nothing of the previous scope remains.
    func reset() { if !actions.isEmpty { actions = [] } }

    func needsAttention(_ tab: SchoolHomeTab) -> Bool { actions.contains { $0.tab == tab } }

    func action(_ kind: SchoolRequiredAction.Kind, entityID: UUID?) -> SchoolRequiredAction? {
        actions.first { $0.kind == kind && $0.entityID == entityID }
    }
}

/// The rules that turn data into actions, outside the views: they are tested as they are.
enum SchoolRequiredActionRules {
    /// Lessons the signed-in instructor started and whose planned end has passed, today or before.
    static func lessonsToFinish(_ lessons: [SchoolLesson], instructorMembershipID: UUID?, now: Date) -> [SchoolRequiredAction] {
        guard let instructorMembershipID else { return [] }
        var seen = Set<UUID>()
        return lessons.filter { lesson in
            lesson.instructorMembershipId == instructorMembershipID && lesson.drivyState(now: now) == .toFinish
                && seen.insert(lesson.id).inserted
        }.map { SchoolRequiredAction(kind: .finishLesson, entityID: $0.id, recipient: .instructor, title: "Leçon à terminer") }
    }

    /// The school's own state of a learner's profile: anything but « READY » lacks required information.
    static func profileIsIncomplete(_ learner: SchoolLearner) -> Bool {
        learner.archivedAt == nil && learner.profileReadiness != nil && learner.profileReadiness != "READY"
    }

    /// Only the administration may edit every field of a learner's profile. An instructor may complete
    /// contacts only, and cannot know from the list which field is missing: for them the list states the
    /// fact on the learner's line, and the dossier says what they can do. No dot on their tab.
    static func incompleteProfiles(_ learners: [SchoolLearner], roles: [String]) -> [SchoolRequiredAction] {
        guard roles.contains("ADMIN") else { return [] }
        return learners.filter(profileIsIncomplete).map {
            SchoolRequiredAction(kind: .completeLearnerProfile, entityID: $0.id, recipient: .administrator, title: "Profil à compléter")
        }
    }

    /// The learner answers the school's recording notice themselves, in their settings.
    static func recordingConsent(attention: String?) -> [SchoolRequiredAction] {
        guard let attention else { return [] }
        return [SchoolRequiredAction(kind: .giveRecordingConsent, entityID: nil, recipient: .learner,
                                     title: attention == "À donner" ? "Accord GPS à donner" : "Accord GPS à vérifier")]
    }

    static func onboarding(canResume: Bool, isLearner: Bool) -> [SchoolRequiredAction] {
        canResume ? [SchoolRequiredAction(kind: .resumeOnboarding, entityID: nil, recipient: isLearner ? .learner : .instructor,
                                          title: "Accueil à terminer")] : []
    }

    /// The field a profile blocker names, as a person reads it.
    static func fieldName(_ field: String) -> String {
        switch field {
        case "firstName": "Prénom"
        case "lastName": "Nom"
        case "birthDate": "Date de naissance"
        case "postalAddress": "Adresse"
        case "contactEmail": "E-mail"
        case "contactPhone": "Téléphone"
        default: "Information"
        }
    }

    /// Fields an instructor may complete themselves; the others belong to the learner or the administration.
    static let instructorEditableFields: Set<String> = ["contactEmail", "contactPhone"]
}

/// The discreet mark of a pending action on a line: a small dot in the accent, aligned on the text.
struct DrivyActionDot: View {
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 8

    var body: some View {
        Circle().fill(DrivyTheme.accent).frame(width: size, height: size).accessibilityHidden(true)
    }
}
