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
    /// Choix déjà lu par l’hôte (le Profil s’en sert pour signaler une réponse attendue) ; sinon la ligne lit le sien.
    var shared: SchoolRecordingChoiceWorkspace? = nil
    @Environment(SchoolCaptureSessionController.self) private var capture: SchoolCaptureSessionController?
    @Environment(\.scenePhase) private var scenePhase
    @State private var owned: SchoolRecordingChoiceWorkspace?
    /// Réponse en cours d’envoi ; `nil` : la réponse montrée est celle que l’école a enregistrée.
    @State private var sending: SchoolRecordingChoice.Status?

    private var key: String {
        "\(scope.personID):\(scope.schoolID):\(scope.membershipID):\(scope.accessEpoch):\(scope.apiBaseURL):\(lessonID?.uuidString ?? "general"):\(learnerID?.uuidString ?? "")"
    }

    /// Le choix montré : celui de l’hôte s’il vaut pour ce compte et cette leçon, sinon celui de la ligne.
    private var model: SchoolRecordingChoiceWorkspace? {
        if let shared, matches(shared) { return shared }
        return owned
    }

    var body: some View {
        // Un conteneur stable, pas un `Group` : sous un `Group`, la tâche suivait chaque branche, et le passage de
        // l’attente au choix lu annulait la lecture en cours sans la relancer (squelette sans fin, octobre 2026).
        VStack(alignment: .leading, spacing: 0) {
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
            // Une lecture interrompue (la ligne a quitté l’écran avant la réponse) reprend ici, sans passer pour une panne.
            if let model, matches(model) {
                if model.needsReload, !model.isLoading, !model.isBusy, !model.accessRevoked { await model.load() }
                return
            }
            owned?.invalidate(); sending = nil
            let value = Self.makeModel(scope: scope, lessonID: lessonID, learnerID: learnerID, agenda: agenda, capture: capture)
            owned = value
            await value.load()
        }
        .onChange(of: model.map(Self.readWasInterrupted) ?? false) { _, interrupted in
            // Une lecture interrompue (ligne sortie de l’écran, compte relu) ne laisse jamais l’attente affichée : elle
            // reprend aussitôt, et une vraie panne s’affiche avec « Réessayer ».
            guard interrupted, let model else { return }
            Task { await model.load() }
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

    /// Le choix de l’élève pour cette portée ; un refus confirmé arrête aussitôt le trajet en cours, s’il y en a un.
    @MainActor static func makeModel(scope: SchoolCommandScope, lessonID: UUID?, learnerID: UUID?, agenda: SchoolAgendaClient,
                                     capture controller: SchoolCaptureSessionController?) -> SchoolRecordingChoiceWorkspace {
        var journal: (@MainActor () async throws -> SQLCipherSchoolCaptureStore)?
        if let controller { journal = { try await controller.journal() } }
        return SchoolRecordingChoiceWorkspace(scope: scope, lessonID: lessonID, learnerID: learnerID, client: agenda.captureClient,
            reader: agenda.reader, agenda: agenda,
            onRefusalConfirmed: { learner, lesson in controller?.learnerRefused(learnerID: learner, lessonID: lesson) },
            journalProvider: journal)
    }

    /// Rien de lu, rien en cours, aucune panne : la dernière lecture a été interrompue avant sa réponse.
    static func readWasInterrupted(_ model: SchoolRecordingChoiceWorkspace) -> Bool {
        interruptedRead(hasNotice: model.notice != nil, isLoading: model.isLoading, hasError: model.errorMessage != nil,
            accessRevoked: model.accessRevoked, needsReload: model.needsReload)
    }

    static func interruptedRead(hasNotice: Bool, isLoading: Bool, hasError: Bool, accessRevoked: Bool, needsReload: Bool) -> Bool {
        !hasNotice && !isLoading && !hasError && !accessRevoked && needsReload
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
