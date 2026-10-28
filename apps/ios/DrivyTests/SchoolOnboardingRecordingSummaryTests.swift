import Foundation
import Testing
@testable import Drivy

struct SchoolOnboardingRecordingSummaryTests {
    @Test func uncertainWritesNeverLookLikeAConfirmedAnswer() {
        let answers: [SchoolRecordingChoice.Status?] = [.allowed, .refused, nil]
        for answer in answers {
            #expect(SchoolOnboardingRecordingSummary.label(answer: answer, isLoading: false, isSaving: true,
                hasPending: false, needsVerification: false) == "Enregistrement du choix…")
            #expect(SchoolOnboardingRecordingSummary.label(answer: answer, isLoading: false, isSaving: false,
                hasPending: true, needsVerification: false) == "Choix en attente de confirmation")
            #expect(SchoolOnboardingRecordingSummary.label(answer: answer, isLoading: false, isSaving: false,
                hasPending: false, needsVerification: true) == "Choix à vérifier dans Profil")
        }
    }

    @Test func onlyTheApplicableConfirmedAnswerIsNamed() {
        func label(_ answer: SchoolRecordingChoice.Status?) -> String {
            SchoolOnboardingRecordingSummary.label(answer: answer, isLoading: false, isSaving: false,
                hasPending: false, needsVerification: false)
        }
        #expect(label(.allowed) == "Enregistrement accepté")
        #expect(label(.refused) == "Enregistrement refusé")
        #expect(label(.unknown) == "Pas encore décidé")
        #expect(label(nil) == "Pas encore décidé")
        #expect(SchoolOnboardingRecordingSummary.label(answer: .allowed, isLoading: true, isSaving: false,
            hasPending: false, needsVerification: false) == "Vérification du choix…")
    }
}
