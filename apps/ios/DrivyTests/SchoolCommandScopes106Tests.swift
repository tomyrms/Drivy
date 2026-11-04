import Foundation
import Testing
@testable import Drivy

/// #106, tâches 1 à 3 : la barrière d'un écran est exactement la règle d'admission de la file.
///
/// Chaque site est vérifié sur des états réels de la file chiffrée : une commande en attente, puis la commande que
/// l'écran émettrait. L'écran ne doit jamais s'ouvrir pour une écriture que `save` refusera, et la réciproque est
/// vérifiée aussi pour les paires dont l'admission a été desserrée avec preuve côté API.
@MainActor struct SchoolCommandScopes106Tests {
    private let key = Data(repeating: 0x07, count: 32)
    private let scope = ConfigurationFixture.scope()

    // MARK: - Admission dans la file

    @Test func twoDistinctInvitationsCoexistAndTheSameInvitationStaysSequential() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.createInvitation))
            try store.save(command(.createInvitation))
            let target = UUID(), other = UUID()
            try store.save(command(.resendInvitation, resourceID: target, version: 2))
            try store.save(command(.resendInvitation, resourceID: other, version: 2))
            // Le renvoi et la révocation de la même invitation restent séquentiels.
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.revokeInvitation, resourceID: target, version: 2))
            }
            let reopened = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            #expect(try reopened.pendingCommands(for: scope).count == 4)
        }
    }

    /// `profiles.ts:122-161` ne vérifie que la version du dossier et de la personne ; `invitations.ts:385-415`
    /// n'en vérifie aucune et écrit une ligne d'invitation. Les deux peuvent donc coexister.
    @Test func anInvitationAndAProfileRecordDoNotShareAVersion() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.createInvitation))
            try store.save(command(.updateProfile, resourceID: UUID(),
                routeResourceID: ProfileFixture.learnerID, version: 1))
            try store.save(command(.saveOnboarding, resourceID: UUID(), version: 1))
            #expect(try store.pendingCommands(for: scope).count == 3)
        }
    }

    /// Même preuve, dans l'ordre inverse : l'accueil guidé écrit `drivy.onboarding_progress` (`profiles.ts:266`,
    /// `:277-278`), le dossier administratif `drivy.learner_profile` puis `drivy.person` (`profiles.ts:127`, `:148`,
    /// `:152`). Aucune version n'est partagée : la paire n'attend pas, et l'archive chiffrée se relit avec ses entrées.
    @Test func aProfileRecordAndAnOnboardingSaveCoexistInEitherOrder() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.saveOnboarding, resourceID: UUID(), version: 1))
            try store.save(command(.updateProfile, resourceID: UUID(),
                routeResourceID: ProfileFixture.learnerID, version: 1))
            #expect(try store.pendingCommands(for: scope).count == 2)
            // Relecture du coffre : la règle desserrée vaut aussi pour la validation de l'archive.
            let reopened = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            #expect(try reopened.pendingCommands(for: scope).count == 2)
        }
    }

    /// Ce que la preuve ne couvre pas reste séquentiel : la finalisation de l'accueil relit le dossier et ses champs
    /// manquants (`profiles.ts:167-173`, `:268`), deux enregistrements d'accueil partagent
    /// `onboarding_progress.version`, deux dossiers partagent `learner_profile.version`, et une politique de champ
    /// avance la version de l'école (`profiles.ts:208`, `:221`).
    @Test func theProfileAndOnboardingExceptionStopsAtCompletionAndAtTheSameRecord() throws {
        // Dossier puis finalisation : la finalisation dépend du dossier, elle attend.
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.updateProfile, resourceID: UUID(),
                routeResourceID: ProfileFixture.learnerID, version: 1))
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.completeOnboarding, resourceID: UUID(), version: 1))
            }
        }
        // Finalisation puis dossier : même dépendance, l'exception ne nomme que `saveOnboarding`.
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.completeOnboarding, resourceID: UUID(), version: 1))
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.updateProfile, resourceID: UUID(),
                    routeResourceID: ProfileFixture.learnerID, version: 1))
            }
        }
        // Deux enregistrements d'accueil : une seule ligne de progression, une seule version.
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.saveOnboarding, resourceID: UUID(), version: 1))
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.saveOnboarding, resourceID: UUID(), version: 2))
            }
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.completeOnboarding, resourceID: UUID(), version: 1))
            }
        }
        // Deux dossiers : une seule ligne `learner_profile`, une seule version, même pour deux élèves.
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.updateProfile, resourceID: UUID(),
                routeResourceID: ProfileFixture.learnerID, version: 1))
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.updateProfile, resourceID: UUID(),
                    routeResourceID: UUID(), version: 1))
            }
        }
        // Politique de champ : elle avance la version de l'école, elle reste une barrière.
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.createProfilePolicy, version: 0, expectedVersion: 8))
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.saveOnboarding, resourceID: UUID(), version: 1))
            }
        }
    }

    /// L'exception ne franchit ni une autre époque d'accès ni une autre adhésion : la barrière de portée reste intacte.
    @Test func theProfileAndOnboardingExceptionKeepsTheAccessBarrier() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.saveOnboarding, resourceID: UUID(), version: 1))
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.updateProfile, scope: ConfigurationFixture.scope(epoch: 2),
                    resourceID: UUID(), routeResourceID: ProfileFixture.learnerID, version: 1))
            }
        }
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let otherMembership = SchoolCommandScope(personID: ConfigurationFixture.personID,
                schoolID: ConfigurationFixture.schoolID, membershipID: UUID(), accessEpoch: 1,
                apiBaseURL: ConfigurationFixture.scope().apiBaseURL)
            try store.save(command(.saveOnboarding, scope: otherMembership, resourceID: UUID(), version: 1))
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.updateProfile, resourceID: UUID(),
                    routeResourceID: ProfileFixture.learnerID, version: 1))
            }
        }
    }

    /// Une politique de champ avance la version de l'école (`profiles.ts:69`, `:208`, `:221`) : elle reste une
    /// barrière pour tout le reste, invitation comprise.
    @Test func aProfilePolicyStillBlocksAnInvitation() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.createProfilePolicy, version: 0, expectedVersion: 8))
            #expect(throws: SchoolConfigurationFailure.pendingCommand) { try store.save(command(.createInvitation)) }
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.updateProfile, resourceID: UUID(),
                    routeResourceID: ProfileFixture.learnerID, version: 1))
            }
        }
    }

    /// `capture-observations.ts:143-165` : la création ne vérifie aucune version et n'écrit que sa leçon, son
    /// brouillon et ses captures. Deux leçons différentes n'ont donc rien en commun.
    @Test func observationsOfDifferentLessonsDoNotShareALesson() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let lesson = UUID()
            try store.save(command(.createObservation, routeResourceID: lesson, version: 0))
            try store.save(command(.createObservation, routeResourceID: UUID(), version: 0))
            // La fin de cette leçon écrit sa version et rattache ses observations (`lesson-reports.ts:158`, `:171`).
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.completeLesson, resourceID: lesson, version: 2))
            }
            #expect(try store.pendingCommands(for: scope).count == 2)
        }
    }

    @Test func aSchoolWriteStillBlocksEverything() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.updateSchool))
            #expect(throws: SchoolConfigurationFailure.pendingCommand) { try store.save(command(.createInvitation)) }
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.createObservation, routeResourceID: UUID(), version: 0))
            }
        }
    }

    @Test func theAdmissionProbeKeepsTheAccessEpochBarrier() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let invitation = try command(.createInvitation)
            try store.save(invitation)
            #expect(try store.pending(for: scope, refusing: .updateProfile,
                routeResourceID: ProfileFixture.learnerID) == nil)
            let later = ConfigurationFixture.scope(epoch: 2)
            #expect(try store.pending(for: later, refusing: .updateProfile,
                routeResourceID: ProfileFixture.learnerID) == invitation)
        }
    }

    // MARK: - Un test par site : écran ouvert <=> la file accepte

    @Test func startNowIsOfferedExactlyWhenTheQueueAcceptsIt() async throws {
        let states = try pendingStates()
        for state in states {
            try await inExperiment(state.pending) { store in
                let model = SchoolStartNowWorkspace(scope: state.screen, client: planningClient(), outbox: store)
                await model.load()
                let start = try command(.startLessonNow, scope: state.screen,
                    routeResourceID: HubFixture.trainingID, version: 0)
                #expect(model.canStart == accepts(store, start), "\(state.label)")
            }
        }
    }

    @Test func theDossierIsEditableExactlyWhenTheQueueAcceptsItsProfile() async throws {
        let states = try pendingStates()
        for state in states {
            try await inExperiment(state.pending) { store in
                let model = SchoolProfileWorkspace(scope: state.screen, roles: ["ADMIN"],
                    learnerID: ProfileFixture.learnerID, api: ProfileAPIStub(), outbox: store)
                await model.load()
                let profile = try command(.updateProfile, scope: state.screen, resourceID: ProfileFixture.profileID,
                    routeResourceID: ProfileFixture.learnerID, version: 1)
                let accepted = accepts(store, profile)
                #expect(model.canMutate == accepted, "\(state.label)")
                #expect(model.acceptsInput == accepted, "\(state.label)")
            }
        }
    }

    @Test func observationsAreOfferedExactlyWhenTheQueueAcceptsThem() async throws {
        let states = try pendingStates()
        for state in states {
            try await inExperiment(state.pending) { store in
                let model = SchoolObservationWorkspace(scope: state.screen, lessonID: HubFixture.lessonID,
                    client: observationClient(state.screen), outbox: store,
                    correctionStore: SchoolObservationCorrectionMemoryStore())
                await model.load()
                let observation = try command(.createObservation, scope: state.screen,
                    routeResourceID: HubFixture.lessonID, version: 0)
                #expect(model.canMutate == accepts(store, observation), "\(state.label)")
            }
        }
    }

    @Test func theInvitationFormIsOpenExactlyWhenTheQueueAcceptsAnInvitation() async throws {
        let states = try pendingStates()
        for state in states where state.pending.kind != .createInvitation {
            try await inExperiment(state.pending) { store in
                let api = InvitationAPIStub()
                api.items = [InvitationFixture.invitation()]
                let model = SchoolInvitationWorkspace(scope: state.screen, roles: ["ADMIN"], api: api, outbox: store)
                await model.load()
                let creation = try command(.createInvitation, scope: state.screen, version: 0)
                #expect(model.mayEdit == accepts(store, creation), "\(state.label)")
            }
        }
    }

    /// Une création dont l’issue reste inconnue ferme le formulaire : la file accepterait une autre création, mais
    /// le code de la première serait perdu. C’est la seule barrière volontairement plus stricte que la file, et elle
    /// ne peut pas produire le défaut inverse (saisir puis être refusé).
    @Test func anInvitationCreationWhoseOutcomeIsUnknownStillClosesTheForm() async throws {
        try await inExperiment(try command(.createInvitation)) { store in
            let api = InvitationAPIStub()
            let target = InvitationFixture.invitation()
            api.items = [target]
            let model = SchoolInvitationWorkspace(scope: scope, roles: ["ADMIN"], api: api, outbox: store)
            await model.load()
            #expect(!model.mayEdit && model.creationInProgressTitle == "Création en cours")
            let anotherCreation = try command(.createInvitation, version: 0)
            #expect(accepts(store, anotherCreation))
            #expect(!model.canManage(target))
            let resend = try command(.resendInvitation, resourceID: target.id, version: 2)
            #expect(accepts(store, resend))
        }
    }

    @Test func aResendIsOfferedExactlyWhenTheQueueAcceptsIt() async throws {
        let target = InvitationFixture.invitation()
        let other = InvitationFixture.invitation(id: UUID(), email: "b***@example.invalid")
        let cases = [(try command(.resendInvitation, resourceID: target.id, version: 2), "même invitation"),
                     (try command(.resendInvitation, resourceID: other.id, version: 2), "autre invitation"),
                     (try command(.createServiceProduct, version: 0), "tarif"),
                     (try command(.updateSchool), "école")]
        for (pending, label) in cases {
            try await inExperiment(pending) { store in
                let api = InvitationAPIStub()
                api.items = [target, other]
                let model = SchoolInvitationWorkspace(scope: scope, roles: ["ADMIN"], api: api, outbox: store)
                await model.load()
                let resend = try command(.resendInvitation, resourceID: target.id, version: 2)
                #expect(model.canManage(target) == accepts(store, resend), "\(label)")
            }
        }
    }

    @Test func aResendOfOneInvitationDoesNotCloseTheOthers() async throws {
        let api = InvitationAPIStub()
        let target = InvitationFixture.invitation()
        let other = InvitationFixture.invitation(id: UUID(), email: "b***@example.invalid")
        api.items = [target, other]
        let resend = try command(.resendInvitation, resourceID: target.id, version: 2)
        try await inExperiment(resend) { store in
            let model = SchoolInvitationWorkspace(scope: scope, roles: ["ADMIN"], api: api, outbox: store)
            await model.load()
            #expect(model.mayEdit && model.pending == resend)
            #expect(model.progressTitle(for: target) == "Renvoi en cours")
            // La même invitation attend sa réponse ; une autre invitation reste invitée et gérée.
            #expect(!model.canManage(target) && model.canManage(other))
        }
    }

    // MARK: - Tâche 4 : le domaine « enseignement » par agrégat

    /// `lesson-reports.ts:137-138` vérifie la version de la préparation d'une leçon, `lessons.ts:414` celle d'une autre
    /// leçon : ni la même version, ni le même créneau, ni le même agrégat.
    @Test func twoCommandsOfDifferentLessonsCoexist() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let lesson = UUID()
            try store.save(command(.savePreparation, resourceID: UUID(), routeResourceID: lesson, version: 4))
            try store.save(command(.cancelLesson, resourceID: UUID(), version: 3))
            try store.save(command(.createObservation, routeResourceID: UUID(), version: 0))
            #expect(try store.pendingCommands(for: scope).count == 3)
            // Même leçon : `lesson-reports.ts:158` vérifie la version de cette leçon, la paire reste séquentielle.
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.completeLesson, resourceID: lesson, version: 5))
            }
        }
    }

    /// `lesson-reports.ts:197` exige une leçon réalisée pour un brouillon, `lessons.ts:390` une leçon planifiée pour un
    /// déplacement : la même leçon ne peut pas être les deux. Le partage, lui, ne dépend d'aucun état
    /// (`sharing.ts:48`) et reste bloqué par un brouillon dont la file ne connaît pas la leçon.
    @Test func aReportDraftAndAPlannedLessonCommandNeverShareALesson() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.saveReportDraft, resourceID: UUID(), version: 2))
            try store.save(command(.moveLesson, resourceID: UUID(), version: 3))
            try store.save(command(.cancelLesson, resourceID: UUID(), version: 2))
            #expect(try store.pendingCommands(for: scope).count == 3)
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.updateLessonSharing, resourceID: UUID(), version: 4))
            }
        }
    }

    /// `exams.ts:243` vérifie la version de l'examen visé ; seule une création (`:189`) ou un report (`:227-232`)
    /// relit les épreuves prévues de la formation.
    @Test func examsAreKeyedByExamAndByTheScheduledList() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let exam = UUID(), other = UUID(), training = HubFixture.trainingID
            try store.save(command(.setExamResult, resourceID: exam, routeResourceID: training, version: 2))
            // Une autre épreuve de la même formation se modifie : aucune version commune, aucun accompagnement pris.
            try store.save(command(.updateExam, resourceID: other, routeResourceID: training, version: 1))
            try store.save(command(.savePreparation, resourceID: UUID(), routeResourceID: UUID(), version: 2))
            #expect(try store.pendingCommands(for: scope).count == 3)
            // Deux épreuves prévues de la même formation se disputent l'unicité (`exams.ts:189`).
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.setExamResult, resourceID: UUID(), routeResourceID: training, version: 1))
            }
            // Deux accompagnements peuvent se recouvrir : le moniteur n'est pas dans la file (`exams.ts:195`).
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.updateExam, resourceID: UUID(), routeResourceID: UUID(), version: 1))
            }
        }
    }

    /// `permits.ts:69-82` vérifie et avance `drivy.training.version` ; `lesson-reports.ts:163` relit l'avertissement de
    /// permis de la formation de la leçon, que la file ne nomme pas.
    @Test func aPermitCheckKeepsTheCompletionOfItsTraining() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.recordPermitCheck, routeResourceID: HubFixture.trainingID, version: 0, expectedVersion: 3))
            try store.save(command(.savePreparation, resourceID: UUID(), routeResourceID: UUID(), version: 2))
            #expect(try store.pendingCommands(for: scope).count == 2)
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.completeLesson, resourceID: UUID(), version: 3))
            }
        }
    }

    /// Ce dont la preuve manque reste bloquant : un tarif relit le catalogue que toute écriture de leçon revalide
    /// (`lessons.ts:102-114`) et le produit visé reste dans le corps, hors de la file.
    @Test func teachingCommandsWithoutProofStillQueue() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(command(.createServiceProduct, version: 0))
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.savePreparation, resourceID: UUID(), routeResourceID: UUID(), version: 2))
            }
            #expect(throws: SchoolConfigurationFailure.pendingCommand) {
                try store.save(command(.createLesson, routeResourceID: UUID(), version: 0))
            }
            #expect(try store.pendingCommands(for: scope).count == 1)
        }
    }

    // MARK: - Tâche 4 : écran ouvert <=> la file accepte le geste

    @Test func thePlanningSheetOpensExactlyWhenTheQueueAcceptsItsGesture() async throws {
        for item in try planningStates() {
            try await inQueue(item.pending) { directory, store in
                let model = SchoolPlanningWorkspace(scope: scope, client: planningClient(PlanningDefaultsServer()),
                    date: Date().addingTimeInterval(86_400), lesson: item.lesson, outbox: store)
                model.readsForCancellation = item.cancellation
                await model.load()
                let probe: PendingSchoolCommand
                if let lesson = item.lesson {
                    probe = item.cancellation
                        ? try command(.cancelLesson, scope: scope, resourceID: lesson.id, version: lesson.version)
                        : try command(.moveLesson, scope: scope, resourceID: lesson.id, version: lesson.version)
                } else {
                    probe = try command(.createLesson, scope: scope, routeResourceID: HubFixture.trainingID, version: 0)
                }
                #expect(model.canMutate == admits(directory, probe), "\(item.label)")
            }
        }
    }

    @Test func theReportSheetOpensExactlyWhenTheQueueAcceptsItsGestures() async throws {
        for item in try reportStates() {
            try await inQueue(item.pending) { directory, store in
                let model = SchoolLessonReportWorkspace(scope: scope, membership: instructorMembership(), lessonID: HubFixture.lessonID,
                    client: reportClient(), outbox: store, textDrafts: textDraftStore(directory))
                await model.load()
                let accepted = try reportProbes(model).allSatisfy { admits(directory, $0) }
                #expect(model.canMutate == accepted, "\(item.label)")
            }
        }
    }

    /// Les gestes que la fiche peut réellement écrire, avec les identifiants qu'elle leur donne : la fiche n'est
    /// éditable que si la file les accepte tous. Les fixtures servent une leçon réalisée (`LessonFinishServer`), donc un
    /// brouillon et, quand l'école l'expose, le réglage de partage.
    private func reportProbes(_ model: SchoolLessonReportWorkspace) throws -> [PendingSchoolCommand] {
        var probes: [PendingSchoolCommand] = []
        if model.sharing != nil {
            probes.append(try command(.updateLessonSharing, scope: scope, resourceID: HubFixture.lessonID, version: 2))
        }
        if let draft = model.draft {
            probes.append(try command(.saveReportDraft, scope: scope, resourceID: draft.id, version: draft.version))
        }
        return probes
    }

    @Test func theExamRowOpensExactlyWhenTheQueueAcceptsItsGesture() async throws {
        let exam = examFixture(), other = examFixture(id: UUID())
        let cases: [(String, PendingSchoolCommand, SchoolCommandKind, SchoolExam?)] = [
            ("invitation", try command(.createInvitation), .setExamResult, exam),
            ("résultat d'une autre épreuve",
             try command(.setExamResult, resourceID: other.id, routeResourceID: HubFixture.trainingID, version: 2),
             .updateExam, exam),
            ("résultat de cette épreuve",
             try command(.setExamResult, resourceID: exam.id, routeResourceID: HubFixture.trainingID, version: 2),
             .setExamResult, exam),
            ("épreuve prévue de la formation",
             try command(.createExam, routeResourceID: HubFixture.trainingID, version: 0), .createExam, nil),
            ("accompagnement d'une autre épreuve",
             try command(.updateExam, resourceID: other.id, routeResourceID: HubFixture.trainingID, version: 2),
             .updateExam, exam),
            ("leçon d'une autre formation", try command(.moveLesson, resourceID: UUID(), version: 2), .setExamResult, exam),
            ("tarif", try command(.createServiceProduct, version: 0), .setExamResult, exam)
        ]
        for (label, pending, kind, target) in cases {
            try await inQueue(pending) { directory, store in
                let model = SchoolExamModel(client: examClient(), scope: scope, trainingID: HubFixture.trainingID, outbox: store)
                await model.load()
                let probe = try command(kind, scope: scope, resourceID: target?.id,
                    routeResourceID: HubFixture.trainingID, version: target?.version ?? 0)
                #expect(model.blocks(kind, exam: target) == !admits(directory, probe), "\(label)")
            }
        }
    }

    // MARK: - Outils

    /// États de file retenus pour les quatre écrans. `screen` est la portée de l'écran : l'état « ancienne époque »
    /// vient d'une commande d'époque 1 lue par un écran d'époque 2.
    private struct PendingState {
        let label: String
        let pending: PendingSchoolCommand
        let screen: SchoolCommandScope
    }

    private func pendingStates() throws -> [PendingState] {
        [
            PendingState(label: "invitation", pending: try command(.createInvitation), screen: scope),
            PendingState(label: "tarif", pending: try command(.createServiceProduct, version: 0), screen: scope),
            PendingState(label: "bilan d'une autre leçon",
                pending: try command(.completeLesson, resourceID: UUID(), version: 2), screen: scope),
            PendingState(label: "observation d'une autre leçon",
                pending: try command(.createObservation, routeResourceID: UUID(), version: 0), screen: scope),
            PendingState(label: "observation de cette leçon",
                pending: try command(.createObservation, routeResourceID: HubFixture.lessonID, version: 0), screen: scope),
            PendingState(label: "profil d'un autre élève",
                pending: try command(.updateProfile, resourceID: UUID(), routeResourceID: UUID(), version: 1),
                screen: scope),
            PendingState(label: "changement d'accès",
                pending: try command(.updateMember, resourceID: UUID(), version: 2), screen: scope),
            PendingState(label: "configuration de l'école", pending: try command(.updateSchool), screen: scope),
            PendingState(label: "ancienne époque", pending: try command(.createInvitation),
                screen: ConfigurationFixture.scope(epoch: 2))
        ]
    }

    private func inExperiment(_ pending: PendingSchoolCommand,
                              _ body: @MainActor (EncryptedSchoolCommandOutbox) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Scopes106-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
        try store.save(pending)
        try await body(store)
    }

    /// Même expérience, avec le dossier : une sonde peut ainsi être essayée sur une copie de la file.
    private func inQueue(_ pending: PendingSchoolCommand,
                         _ body: @MainActor (URL, EncryptedSchoolCommandOutbox) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Scopes106-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
        try store.save(pending)
        try await body(directory, store)
    }

    /// Cette commande entrerait-elle dans la file telle qu'elle est ? Une copie du coffre chiffré est essayée : l'état
    /// observé par l'écran n'est pas modifié.
    private func admits(_ directory: URL, _ candidate: PendingSchoolCommand) -> Bool {
        let copy = directory.appendingPathComponent("probe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: copy) }
        do {
            try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("pending-v1.bin")
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.copyItem(at: file, to: copy.appendingPathComponent("pending-v1.bin"))
            }
            try EncryptedSchoolCommandOutbox(directory: copy, keyData: key).save(candidate)
            return true
        } catch { return false }
    }

    private struct PlanningState {
        let label: String
        let pending: PendingSchoolCommand
        let cancellation: Bool
        let lesson: SchoolLesson?
    }

    /// États réels de la file pour la feuille de planification : le geste comparé est le déplacement (ou l'annulation)
    /// de la leçon ouverte, et la création quand la feuille n'a pas encore de leçon.
    private func planningStates() throws -> [PlanningState] {
        let lesson = HubFixture.lesson()
        return [
            PlanningState(label: "invitation", pending: try command(.createInvitation), cancellation: false, lesson: lesson),
            PlanningState(label: "préparation d'une autre leçon",
                pending: try command(.savePreparation, resourceID: UUID(), routeResourceID: UUID(), version: 2),
                cancellation: false, lesson: lesson),
            PlanningState(label: "bilan d'une autre leçon",
                pending: try command(.completeLesson, resourceID: UUID(), version: 2), cancellation: false, lesson: lesson),
            PlanningState(label: "brouillon d'une autre leçon",
                pending: try command(.saveReportDraft, resourceID: UUID(), version: 2), cancellation: false, lesson: lesson),
            PlanningState(label: "résultat d'examen",
                pending: try command(.setExamResult, resourceID: UUID(), routeResourceID: UUID(), version: 2),
                cancellation: false, lesson: lesson),
            PlanningState(label: "tarif", pending: try command(.createServiceProduct, version: 0),
                cancellation: false, lesson: lesson),
            PlanningState(label: "déplacement d'une autre leçon",
                pending: try command(.moveLesson, resourceID: UUID(), version: 2), cancellation: false, lesson: lesson),
            PlanningState(label: "déplacement de cette leçon",
                pending: try command(.moveLesson, resourceID: HubFixture.lessonID, version: 2), cancellation: false, lesson: lesson),
            PlanningState(label: "annulation d'une autre leçon",
                pending: try command(.cancelLesson, resourceID: UUID(), version: 2), cancellation: true, lesson: lesson),
            PlanningState(label: "annulation de cette leçon",
                pending: try command(.cancelLesson, resourceID: HubFixture.lessonID, version: 2), cancellation: true, lesson: lesson),
            PlanningState(label: "création : préparation d'une autre leçon",
                pending: try command(.savePreparation, resourceID: UUID(), routeResourceID: UUID(), version: 2),
                cancellation: false, lesson: nil),
            PlanningState(label: "création : bilan d'une autre leçon",
                pending: try command(.completeLesson, resourceID: UUID(), version: 2), cancellation: false, lesson: nil),
            PlanningState(label: "création : un créneau se prend déjà",
                pending: try command(.moveLesson, resourceID: UUID(), version: 2), cancellation: false, lesson: nil),
            PlanningState(label: "création : tarif", pending: try command(.createServiceProduct, version: 0),
                cancellation: false, lesson: nil)
        ]
    }

    /// États réels de la file pour la fiche de leçon : elle est ouverte sur la leçon réalisée des fixtures, dont les
    /// gestes sont l'enregistrement du brouillon et le partage.
    private func reportStates() throws -> [(label: String, pending: PendingSchoolCommand)] {
        [
            ("invitation", try command(.createInvitation)),
            ("préparation d'une autre leçon",
                try command(.savePreparation, resourceID: UUID(), routeResourceID: UUID(), version: 2)),
            ("bilan d'une autre leçon", try command(.completeLesson, resourceID: UUID(), version: 2)),
            ("brouillon d'une autre leçon", try command(.saveReportDraft, resourceID: UUID(), version: 2)),
            ("résultat d'examen", try command(.setExamResult, resourceID: UUID(), routeResourceID: UUID(), version: 2)),
            ("déplacement d'une autre leçon", try command(.moveLesson, resourceID: UUID(), version: 2)),
            ("création de leçon", try command(.createLesson, routeResourceID: UUID(), version: 0)),
            ("tarif", try command(.createServiceProduct, version: 0)),
            ("observation de cette leçon", try command(.createObservation, routeResourceID: HubFixture.lessonID, version: 0)),
            ("partage de cette leçon", try command(.updateLessonSharing, resourceID: HubFixture.lessonID, version: 2))
        ]
    }

    private func examFixture(id: UUID = UUID()) -> SchoolExam {
        SchoolExam(id: id, trainingId: HubFixture.trainingID, kind: "THEORY", categoryCode: "B", status: "SCHEDULED",
            startsAt: "2026-12-01T09:00:00Z", timeZone: "Europe/Zurich", location: "", escort: nil, resultNote: "",
            resultRecordedAt: nil, postponedToExamId: nil, attempt: 1, needsResult: false, version: 2,
            createdAt: "2026-09-28T12:00:00Z")
    }

    private func instructorMembership() -> SchoolMembership {
        SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
    }

    private func textDraftStore(_ directory: URL) -> any SchoolLessonTextDraftStore {
        EncryptedSchoolLessonTextDraftStore(directory: directory.appendingPathComponent("text-drafts", isDirectory: true),
            keyData: Data(repeating: 0x42, count: 32))
    }

    private func reportClient() -> SchoolLessonReportClient {
        SchoolLessonReportClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: LessonFinishServer())
    }

    private func examClient() -> SchoolExamClient {
        SchoolExamClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(),
            transport: ExamStateTransport(trainingID: HubFixture.trainingID))
    }

    private func planningClient(_ server: PlanningDefaultsServer) -> SchoolPlanningClient {
        SchoolPlanningClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: server)
    }

    /// La commande que l'écran émettrait entre-t-elle réellement dans la file ? Même `save` que l'app.
    private func accepts(_ store: EncryptedSchoolCommandOutbox, _ candidate: PendingSchoolCommand) -> Bool {
        do { try store.save(candidate); return true } catch { return false }
    }

    private func command(_ kind: SchoolCommandKind, scope: SchoolCommandScope? = nil, resourceID: UUID? = nil,
                         routeResourceID: UUID? = nil, version: Int? = nil,
                         expectedVersion: Int? = nil) throws -> PendingSchoolCommand {
        let id = UUID()
        return PendingSchoolCommand(id: id, scope: scope ?? self.scope, kind: kind,
            resourceVersion: version ?? (kind == .createInvitation ? 0 : 1), createdAt: Date(),
            body: try JSONEncoder().encode(["operationId": id.uuidString]),
            resourceID: resourceID, routeResourceID: routeResourceID, expectedVersion: expectedVersion)
    }

    private func planningClient() -> SchoolPlanningClient {
        SchoolPlanningClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: LessonFinishServer())
    }

    private func observationClient(_ scope: SchoolCommandScope) -> SchoolObservationClient {
        SchoolObservationClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(),
            transport: ObservationReadServer())
    }

    private func inDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Scopes106-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

/// État d'examens synthétique, sans aucune donnée réelle : la section des examens se relit hors ligne, et une écriture
/// n'aboutit jamais ici (l'école est indisponible) — le geste conservé reste donc en place.
private struct ExamStateTransport: SchoolHTTPTransport {
    let trainingID: UUID

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        if request.httpMethod != "GET" {
            let problem = try JSONSerialization.data(withJSONObject: ["code": "SERVICE_UNAVAILABLE", "title": "Indisponible"])
            return SchoolHTTPResponse(data: problem, status: 503, url: url, contentType: "application/problem+json")
        }
        let payload: [String: Any] = [
            "data": ["trainingId": trainingID.uuidString, "canManage": true, "escortCandidates": [], "exams": [],
                     "summary": [["kind": "THEORY", "passed": false, "attempts": 0, "scheduledExamId": NSNull()],
                                 ["kind": "PRACTICAL", "passed": false, "attempts": 0, "scheduledExamId": NSNull()]]],
            "requestId": "synthetic-exams",
            "serverTime": "2026-09-28T12:00:00Z"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return SchoolHTTPResponse(data: data, status: 200, url: url, contentType: "application/json")
    }
}
