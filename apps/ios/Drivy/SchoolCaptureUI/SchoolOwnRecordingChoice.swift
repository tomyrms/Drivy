import SwiftUI

/// L’élève donne ou modifie lui-même son accord GPS (source `SELF`) : dans la fiche de sa prochaine leçon, sous
/// « Mon souhait » (le choix qui vaut pour cette leçon), ou dans son profil (`lessonID` nil : son choix général).
/// L’école enregistre la réponse au niveau du choix lu. Une réponse part aussitôt, d’abord dans la file chiffrée,
/// puis à l’école ; elle se montre avec son attente, et l’ancienne revient si l’école ne la confirme pas.
struct SchoolOwnRecordingChoice: View {
    let scope: SchoolCommandScope
    let lessonID: UUID?
    var learnerID: UUID? = nil
    let agenda: SchoolAgendaClient
    @Environment(SchoolCaptureSessionController.self) private var capture: SchoolCaptureSessionController?
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: SchoolRecordingChoiceWorkspace?
    /// Réponse en cours d’envoi ; `nil` : la réponse montrée est celle que l’école a enregistrée.
    @State private var sending: SchoolRecordingChoice.Status?

    private var key: String {
        "\(scope.personID):\(scope.schoolID):\(scope.membershipID):\(scope.accessEpoch):\(scope.apiBaseURL):\(lessonID?.uuidString ?? "general"):\(learnerID?.uuidString ?? "")"
    }

    var body: some View {
        Group {
            if let model, matches(model) {
                SchoolRecordingChoiceInline(model: model, answer: sending ?? model.validAnswer, isEnabled: sending == nil) { status in
                    choose(status, with: model)
                }
            } else {
                DrivySkeletonRow(lines: 2).drivySkeleton("Lecture de l’accord GPS…")
            }
        }
        .task(id: key) {
            // La ligne peut quitter l’écran et revenir : le choix lu reste tant que le compte et la leçon ne changent pas.
            if let model, matches(model) { return }
            model?.invalidate(); sending = nil
            let controller = capture
            var journal: (@MainActor () async throws -> SQLCipherSchoolCaptureStore)?
            if let controller { journal = { try await controller.journal() } }
            let value = SchoolRecordingChoiceWorkspace(scope: scope, lessonID: lessonID, learnerID: learnerID, client: agenda.captureClient,
                reader: agenda.reader, agenda: agenda,
                onRefusalConfirmed: { learner, lesson in controller?.learnerRefused(learnerID: learner, lessonID: lesson) },
                journalProvider: journal)
            model = value
            await value.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .drivyRecordingChoiceDidChange)) { notification in
            // Réponse confirmée ailleurs (fiche de la prochaine leçon ↔ Profil) : ce choix-ci se relit.
            guard let model, notification.object as? UUID != model.id, sending == nil,
                  !model.isBusy, !model.isLoading else { return }
            Task { await model.load() }
        }
        .onChange(of: scenePhase) { _, phase in
            // De retour dans l’app : le moniteur a pu enregistrer un choix entre-temps.
            guard phase == .active, sending == nil, let model, !model.isBusy, !model.isLoading else { return }
            Task { await model.load() }
        }
    }

    private func matches(_ model: SchoolRecordingChoiceWorkspace) -> Bool {
        model.scope == scope && model.lessonID == lessonID && model.learnerID == learnerID
    }

    /// Une réponse explicite, envoyée aussitôt ; la même réponse que le choix enregistré n’envoie rien.
    private func choose(_ status: SchoolRecordingChoice.Status, with model: SchoolRecordingChoiceWorkspace) {
        guard sending == nil, status != model.validAnswer else { return }
        sending = status
        Task {
            let saved = await model.choose(status)
            sending = nil
            if saved { NotificationCenter.default.post(name: .drivyRecordingChoiceDidChange, object: model.id) }
        }
    }
}

extension Notification.Name {
    /// L’élève a changé son accord GPS : les autres lignes d’accord affichées se relisent.
    static let drivyRecordingChoiceDidChange = Notification.Name("drivy.recordingChoiceDidChange")
}
