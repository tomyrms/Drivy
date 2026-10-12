import Foundation
import Testing
@testable import Drivy

/// Les règles qui changent des données en actions à faire, et l’endroit unique qui les garde : un indicateur suit
/// l’état réel et part dès que l’action est résolue.
@MainActor
struct SchoolRequiredActionsTests {
    private static let school = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private static let instructor = UUID(uuidString: "30000000-0000-4000-8000-000000000002")!

    private static func learner(_ index: Int, readiness: String?, archived: Bool = false) -> SchoolLearner {
        SchoolLearner(id: UUID(uuidString: String(format: "40000000-0000-4000-8000-%012d", index))!, schoolId: school,
            personId: UUID(), version: 1, displayName: "Élève \(index)", contactEmail: nil, contactPhone: nil,
            archivedAt: archived ? "2026-10-01T08:00:00Z" : nil, profileReadiness: readiness, profilePhotoDocumentId: nil)
    }

    private static func lesson(_ index: Int, start: Date, minutes: Double = 50, started: Bool, status: String = "PLANNED",
                               instructor: UUID = instructor) -> SchoolLesson {
        let iso = ISO8601DateFormatter()
        return SchoolLesson(id: UUID(uuidString: String(format: "50000000-0000-4000-8000-%012d", index))!, schoolId: school,
            version: 1, trainingId: UUID(), learnerId: UUID(), instructorMembershipId: instructor,
            plannedStart: iso.string(from: start), plannedEnd: iso.string(from: start.addingTimeInterval(minutes * 60)),
            timeZone: "Europe/Zurich", meetingPoint: "Gare", status: status, priceCentsSnapshot: 9_000, bufferMinutesSnapshot: 10,
            actualStart: started ? iso.string(from: start) : nil, actualEnd: nil, permitWarning: false, publicationVersion: 0,
            currentPublishedRevisionId: nil, commercialRevisionVersion: 1)
    }

    // MARK: Profils

    @Test func onlyAProfileTheSchoolSaysIsNotReadyIsIncomplete() {
        #expect(!SchoolRequiredActionRules.profileIsIncomplete(Self.learner(1, readiness: "READY")))
        #expect(SchoolRequiredActionRules.profileIsIncomplete(Self.learner(2, readiness: "MINIMAL")))
        #expect(SchoolRequiredActionRules.profileIsIncomplete(Self.learner(3, readiness: "ACTION_REQUIRED")))
        // Rien de lu n’est jamais un problème affirmé, et un dossier archivé n’attend plus rien.
        #expect(!SchoolRequiredActionRules.profileIsIncomplete(Self.learner(4, readiness: nil)))
        #expect(!SchoolRequiredActionRules.profileIsIncomplete(Self.learner(5, readiness: "MINIMAL", archived: true)))
    }

    @Test func theSchoolWideListLightsTheTabWhateverPageIsShown() {
        let shown = [Self.learner(1, readiness: "READY")]
        let elsewhere = Self.learner(9, readiness: "ACTION_REQUIRED").id
        let actions = SchoolRequiredActionRules.incompleteProfiles(shown, schoolWide: [elsewhere], roles: ["ADMIN"])
        #expect(actions.map(\.entityID) == [elsewhere])
        #expect(actions.allSatisfy { $0.tab == .learners && $0.recipient == .administrator })
        // Sans lecture de l’école, la page affichée sert de repli.
        let fallback = SchoolRequiredActionRules.incompleteProfiles([Self.learner(2, readiness: "MINIMAL")] + shown, roles: ["ADMIN"])
        #expect(fallback.map(\.entityID) == [Self.learner(2, readiness: nil).id])
    }

    @Test func anInstructorNeverGetsTheProfileDot() {
        let learners = [Self.learner(1, readiness: "MINIMAL")]
        #expect(SchoolRequiredActionRules.incompleteProfiles(learners, schoolWide: [learners[0].id], roles: ["INSTRUCTOR"]).isEmpty)
    }

    @Test func theCountSaysHowManyInformationsAreMissing() {
        #expect(SchoolRequiredActionRules.missingCount(1) == "1 information manquante")
        #expect(SchoolRequiredActionRules.missingCount(3) == "3 informations manquantes")
    }

    @Test func aMissingFieldStaysMarkedUntilSomethingIsTyped() {
        var draft = SchoolProfileDraft()
        #expect(draft.isEmpty(.contactPhone))
        draft.contactPhone = "   "
        #expect(draft.isEmpty(.contactPhone))
        draft.contactPhone = "+41 21 000 00 00"
        #expect(!draft.isEmpty(.contactPhone))
        // Une adresse à moitié saisie manque encore ; la photo n’est jamais une information à renseigner ici.
        #expect(draft.isEmpty(.postalAddress))
        draft.hasAddress = true
        draft.address = SchoolPostalAddress(line1: "Rue du Lac 1", line2: nil, postalCode: "1000", locality: "", countryCode: "CH")
        #expect(draft.isEmpty(.postalAddress))
        draft.address.locality = "Lausanne"
        #expect(!draft.isEmpty(.postalAddress))
        #expect(!draft.isEmpty(.profilePhotoDocumentId))
    }

    // MARK: Leçons à terminer

    @Test func aStartedLessonBecomesToFinishAtItsPlannedEnd() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let running = Self.lesson(1, start: now.addingTimeInterval(-20 * 60), started: true)
        let due = Self.lesson(2, start: now.addingTimeInterval(-90 * 60), started: true)
        let notStarted = Self.lesson(3, start: now.addingTimeInterval(-90 * 60), started: false)
        let someoneElse = Self.lesson(4, start: now.addingTimeInterval(-90 * 60), started: true, instructor: UUID())
        let lessons = [running, due, notStarted, someoneElse]
        #expect(SchoolRequiredActionRules.lessonsToFinish(lessons, instructorMembershipID: Self.instructor, now: now).map(\.entityID) == [due.id])
        #expect(SchoolRequiredActionRules.nextFinishDeadline(lessons, instructorMembershipID: Self.instructor, now: now) == running.endsAt)
        let later = now.addingTimeInterval(31 * 60)
        #expect(Set(SchoolRequiredActionRules.lessonsToFinish(lessons, instructorMembershipID: Self.instructor, now: later).compactMap(\.entityID))
                == [due.id, running.id])
        #expect(SchoolRequiredActionRules.nextFinishDeadline(lessons, instructorMembershipID: Self.instructor, now: later) == nil)
    }

    // MARK: Le store

    @Test func aResolvedActionLeavesItsTabAtOnceAndAReplacementOnlyTouchesItsKind() {
        let store = SchoolRequiredActionStore()
        let learner = UUID(), lesson = UUID()
        store.replace(.completeLearnerProfile, with: [SchoolRequiredAction(kind: .completeLearnerProfile, entityID: learner,
            recipient: .administrator, title: "Profil à compléter")])
        store.replace(.finishLesson, with: [SchoolRequiredAction(kind: .finishLesson, entityID: lesson, recipient: .instructor,
            title: "Leçon à terminer")])
        #expect(store.needsAttention(.learners) && store.needsAttention(.session))
        store.resolve(.finishLesson, entityID: lesson)
        #expect(!store.needsAttention(.session))
        #expect(store.needsAttention(.learners))
        store.replace(.completeLearnerProfile, with: [])
        #expect(!store.needsAttention(.learners))
        #expect(store.actions.isEmpty)
    }

    @Test func consentWaitingForAnAnswerLightsTheLearnerProfile() {
        #expect(SchoolRequiredActionRules.recordingConsent(attention: nil).isEmpty)
        let actions = SchoolRequiredActionRules.recordingConsent(attention: "À donner")
        #expect(actions.map(\.tab) == [.profile])
        #expect(actions.first?.title == "Accord GPS à donner")
    }
}
