import Foundation
import Observation
import SwiftUI

/// Corps de « Démarrer une leçon » : le serveur fixe l’heure (maintenant), la durée, la prestation et le moniteur.
struct SchoolStartNowBody: Encodable, Sendable {
    let operationId: UUID
    let trainingId: UUID
    let meetingPoint: String?
}

/// Une leçon qui commence maintenant, avec un élève : choisir l’élève suffit quand il n’a qu’une formation.
/// La demande est chiffrée dans la file avant l’envoi ; sans la route côté serveur (404), la planification
/// classique prend le relais.
@MainActor @Observable final class SchoolStartNowWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let client: SchoolPlanningClient
    private(set) var learners: [SchoolLearner] = []
    private(set) var trainings: [SchoolTraining] = []
    private(set) var defaults: SchoolPlanningDefaults?
    private(set) var learnerID: UUID?
    var trainingID: UUID?
    var meetingPoint = ""
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var contextValid = false
    private(set) var errorMessage: String?
    private(set) var pending: PendingSchoolCommand?
    /// Le serveur ne connaît pas encore « Démarrer une leçon ».
    private(set) var unsupported = false
    private(set) var started: SchoolLesson?
    /// Le serveur a refusé : un rendez-vous du moniteur ou de l’élève tombe pendant la leçon. Rien n’est forcé.
    private(set) var conflicted = false
    /// Après un conflit, le moniteur choisit de planifier la leçon à un autre moment.
    private(set) var planInstead = false
    /// Élève déjà connu (fiche élève) : il est choisi d’emblée et la liste n’est pas proposée.
    let presetLearnerID: UUID?
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private(set) var storageAvailable = false
    @ObservationIgnored private var invalidated = false

    init(scope: SchoolCommandScope, client: SchoolPlanningClient, learnerID: UUID? = nil,
         outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope; self.client = client; self.outbox = outbox; presetLearnerID = learnerID
    }

    /// L’élève est imposé par la fiche d’où l’on part, et il est bien parmi les élèves affectés.
    var hasPresetLearner: Bool { presetLearnerID != nil && presetLearnerID == learnerID }
    var learnerName: String? { learners.first { $0.id == learnerID }?.displayName }

    func planLater() { if conflicted { planInstead = true } }

    /// Same trimmed UTF-16 length as the API and the planning form.
    var meetingPointTooLong: Bool { meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 500 }
    var canStart: Bool {
        !invalidated && contextValid && !isLoading && !isBusy && storageAvailable && pending == nil && started == nil
            && learnerID.map { id in learners.contains { $0.id == id } } == true
            && trainingID.map { id in trainings.contains { $0.id == id && $0.learnerId == learnerID } } == true && !meetingPointTooLong
    }

    func load() async {
        guard !invalidated, !isBusy else { return }
        generation = UUID(); let request = generation
        let previousLearnerID = learnerID
        isLoading = true; contextValid = false; errorMessage = nil
        do { pending = try outbox.pending(for: scope); storageAvailable = true }
        catch { storageAvailable = false; errorMessage = SchoolConfigurationFailure.storage.localizedDescription }
        do {
            let defaults = try await client.defaults(schoolID: scope.schoolID, membershipID: scope.membershipID)
            var all: [SchoolLearner] = [], cursor: String?, seen = Set<String>()
            repeat {
                let page = try await client.reader.learners(schoolID: scope.schoolID, query: "", cursor: cursor,
                    instructorMembershipID: scope.membershipID)
                all.append(contentsOf: page.items); cursor = page.nextCursor
                guard all.count <= 10_000 else { throw SchoolPlanningFailure.invalidResponse }
                if let cursor, !seen.insert(cursor).inserted { throw SchoolPlanningFailure.invalidResponse }
            } while cursor != nil
            guard request == generation, !Task.isCancelled else { return }
            self.defaults = defaults
            learners = all.filter { $0.archivedAt == nil }
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            if learners.isEmpty { setContextError("Aucun élève ne t’est affecté. Demande à l’administration de vérifier les affectations.") }
            isLoading = false
            if let preset = presetLearnerID {
                if learners.contains(where: { $0.id == preset }) { await select(preset) }
                else {
                    learnerID = nil; trainings = []; trainingID = nil; meetingPoint = ""
                    setContextError("Cet élève n’est plus disponible avec tes affectations. Actualise son dossier avant de démarrer.")
                }
            }
            else if let previousLearnerID, learners.contains(where: { $0.id == previousLearnerID }) { await select(previousLearnerID) }
            else if learners.count == 1, let only = learners.first { await select(only.id) }
            else { learnerID = nil; trainings = []; trainingID = nil; meetingPoint = "" }
        } catch {
            guard request == generation else { return }
            isLoading = false
            if !(error is CancellationError) { setContextError((error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription) }
        }
    }

    /// Choisit l’élève ; sa seule formation en cours et son dernier lieu de rendez-vous sont repris.
    func select(_ id: UUID) async {
        guard !invalidated, learners.contains(where: { $0.id == id }), !isBusy else { return }
        generation = UUID(); let request = generation
        let previousTrainingID = learnerID == id ? trainingID : nil
        let previousMeetingPoint = meetingPoint
        if learnerID != id { trainings = []; trainingID = nil; meetingPoint = "" }
        learnerID = id; contextValid = false; setContextError(nil); isLoading = true
        do {
            let values: [SchoolTraining] = try await client.records(scope.schoolID, path: ["trainings"],
                query: [URLQueryItem(name: "learnerId", value: id.uuidString)])
            guard request == generation, !Task.isCancelled else { return }
            let active = values.filter { $0.learnerId == id && $0.status == "ACTIVE" }
            trainings = active.filter { $0.startNowBlockerCode == nil }
            trainingID = trainings.contains(where: { $0.id == previousTrainingID }) ? previousTrainingID : defaults?.trainingID(in: trainings)
            if trainings.isEmpty { setContextError(Self.startBlockerMessage(active.first?.startNowBlockerCode)) }
            if let training = trainingID, training != previousTrainingID {
                let lessons: [SchoolLesson] = (try? await client.records(scope.schoolID, path: ["lessons"],
                    query: [URLQueryItem(name: "trainingId", value: training.uuidString)])) ?? []
                guard request == generation else { return }
                meetingPoint = SchoolStartNowWorkspace.lastMeetingPoint(lessons, trainingID: training) ?? ""
            }
            if trainingID != nil && trainingID == previousTrainingID { meetingPoint = previousMeetingPoint }
            contextValid = true; isLoading = false
        } catch {
            guard request == generation else { return }
            isLoading = false
            if !(error is CancellationError) { setContextError((error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription) }
        }
    }

    /// A successful context read cannot repair the encrypted outbox. Its failure
    /// stays visible until load() has actually read that storage successfully.
    private func setContextError(_ message: String?) {
        errorMessage = storageAvailable ? message : SchoolConfigurationFailure.storage.localizedDescription
    }

    static func startBlockerMessage(_ code: String?) -> String {
        switch code {
        case "INSTRUCTOR_NOT_ASSIGNED", "ASSIGNMENT_ENDS_BEFORE_LESSON_END":
            "Ton affectation ne couvre pas cette leçon. Demande à l’administration de la vérifier."
        case "INSTRUCTOR_REQUIRED": "Seul un moniteur peut démarrer une leçon."
        case "OFFERING_NOT_READY": "Le tarif de cette formation n’est pas prêt. Demande à l’administration de la vérifier."
        case "SCHOOL_NOT_ACTIVE": "L’école n’est pas active. Contacte son administration."
        default: "Aucune formation disponible pour démarrer avec cet élève. Demande à l’administration de vérifier sa formation."
        }
    }

    static func lastMeetingPoint(_ lessons: [SchoolLesson], trainingID: UUID) -> String? {
        lessons.filter { $0.trainingId == trainingID && $0.status != "CANCELLED" }
            .max { $0.plannedStart < $1.plannedStart }
            .map { $0.meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Démarre la leçon ; la leçon renvoyée par l’école est la preuve de son enregistrement.
    func start() async -> SchoolLesson? {
        guard canStart, let trainingID else { return nil }
        let operation = UUID()
        let point = meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let command: PendingSchoolCommand
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let body = try encoder.encode(SchoolStartNowBody(operationId: operation, trainingId: trainingID, meetingPoint: point.isEmpty ? nil : point))
            command = PendingSchoolCommand(id: operation, scope: scope, kind: .startLessonNow, resourceVersion: 0,
                createdAt: Date(), body: body, routeResourceID: trainingID)
            try outbox.save(command); pending = command
        } catch {
            storageAvailable = false; errorMessage = SchoolConfigurationFailure.storage.localizedDescription; return nil
        }
        return await send(command, fresh: true)
    }

    /// Reprend la même demande (même identifiant d’opération) après une réponse perdue.
    func retry() async -> SchoolLesson? {
        guard !invalidated, let pending, pending.kind == .startLessonNow, pending.scope == scope, !isBusy else { return nil }
        return await send(pending, fresh: false)
    }

    func invalidate() {
        invalidated = true; generation = UUID(); learners = []; trainings = []; learnerID = nil; trainingID = nil
        pending = nil; started = nil; isBusy = false; isLoading = false; contextValid = false; storageAvailable = false; meetingPoint = ""
    }

    private func send(_ command: PendingSchoolCommand, fresh: Bool) async -> SchoolLesson? {
        let request = generation
        isBusy = true; errorMessage = nil; conflicted = false
        defer { if request == generation { isBusy = false } }
        do {
            try outbox.save(command)
            let lesson = try await client.startNow(command)
            try outbox.remove(command)
            guard request == generation else { return lesson }
            pending = nil; started = lesson
            return lesson
        } catch {
            guard request == generation else { return nil }
            if fresh, let failure = error as? SchoolPlanningFailure, failure == .notFound || failure.definitiveRejection {
                do { try outbox.remove(command); pending = nil }
                catch { storageAvailable = false; errorMessage = SchoolConfigurationFailure.storage.localizedDescription; return nil }
                if failure == .notFound { unsupported = true; return nil }
            }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription
            if let failure = error as? SchoolPlanningFailure {
                conflicted = failure == .rejected(SchoolPlanningClient.startNowConflictMessage)
            }
            return nil
        }
    }
}

struct SchoolStartNowView: View {
    @Bindable var model: SchoolStartNowWorkspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let pending = model.pending {
                    Section {
                        DrivyPendingRequest(message: model.errorMessage ?? "Une demande attend sa confirmation.", reference: pending.id,
                            retry: pending.kind == .startLessonNow && pending.scope == model.scope ? { Task { if await model.retry() != nil { dismiss() } } } : nil,
                            canRetry: !model.isBusy && !model.isLoading)
                    }
                    .drivyFormRows()
                } else if let error = model.errorMessage {
                    Section {
                        SchoolErrorNotice(message: error, retry: !model.contextValid || model.learners.isEmpty || model.trainings.isEmpty || !model.storageAvailable
                            ? { Task { await reloadContext() } } : nil)
                        .disabled(model.isBusy || model.isLoading)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                if model.learners.isEmpty && (model.isLoading || (model.defaults == nil && model.errorMessage == nil)) {
                    Section {
                        DrivySkeletonRows(count: 3).drivySkeleton("Chargement des élèves…")
                    }.drivyFormRows()
                } else {
                Section {
                    if model.hasPresetLearner, let name = model.learnerName {
                        LabeledContent("Élève", value: name)
                    } else {
                        Picker("Élève", selection: Binding(get: { model.learnerID }, set: { id in
                            if let id { Task { await model.select(id) } }
                        })) {
                            Text("Choisir un élève").tag(nil as UUID?)
                            ForEach(model.learners) { learner in Text(learner.displayName).tag(Optional(learner.id)) }
                        }
                    }
                    if model.isLoading && model.trainings.isEmpty && model.learnerID != nil {
                        DrivySkeletonRow().drivySkeleton("Chargement de la formation…")
                    } else if model.trainings.count > 1 {
                        Picker("Formation", selection: $model.trainingID) {
                            Text("Choisir une formation").tag(nil as UUID?)
                            ForEach(model.trainings) { training in Text("Permis \(training.categoryCode)").tag(Optional(training.id)) }
                        }
                    } else if let training = model.trainings.first, training.id == model.trainingID {
                        LabeledContent("Formation", value: "Permis \(training.categoryCode)")
                    }
                    SchoolMeetingPointField(text: $model.meetingPoint)
                    if model.meetingPointTooLong {
                        DrivyFormMessage(text: "Raccourcis le lieu à 500 caractères.", tone: .danger)
                    }
                }
                    .drivyFormRows()
                .disabled(model.isBusy || model.isLoading || model.pending != nil)
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: SchoolFormLayout.maxWidth).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if model.conflicted {
                        // Rien n’est forcé : le serveur a refusé, la seule issue est de planifier autrement.
                        Button {
                            model.planLater(); dismiss()
                        } label: { Label("Planifier à un autre moment", systemImage: "calendar") }
                            .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
                            .accessibilityIdentifier("start-now-plan-later")
                    } else {
                        Button {
                            Task {
                                _ = await model.start()
                                if model.started != nil || model.unsupported { dismiss() }
                            }
                        } label: {
                            DrivyBusyLabel(title: "Démarrer maintenant", busyTitle: "Démarrage…", isBusy: model.isBusy)
                        }
                        .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
                        .disabled(!model.canStart)
                        .accessibilityIdentifier("start-now-confirm")
                    }
                }
            }
            .navigationTitle("Démarrer une leçon").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .task { if model.learners.isEmpty { await model.load() } }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }

    @MainActor private func reloadContext() async {
        await model.load()
    }
}

/// Le geste complet « lancer une leçon tout de suite », réutilisable depuis Aujourd’hui et depuis la fiche d’un élève :
/// choix de l’élève (déjà connu depuis sa fiche), création de la leçon par le serveur, puis départ direct du trajet.
/// Si le trajet ne peut pas partir (GPS de l’école, fenêtre), la leçon s’ouvre ; si le serveur signale un conflit
/// de planning, le moniteur peut planifier la leçon autrement. Le style du bouton est celui de l’appelant.
struct SchoolStartNowButton<Content: View>: View {
    @Bindable var workspace: SchoolWorkspace
    let agendaClient: SchoolAgendaClient?
    let captureController: SchoolCaptureSessionController?
    var learnerID: UUID?
    /// Appelé quand le geste est terminé (feuille fermée) pour que l’écran d’origine se relise.
    var onFinished: () -> Void = {}
    @ViewBuilder let label: Content

    @State private var startNow: SchoolStartNowWorkspace?
    @State private var lastStartNow: SchoolStartNowWorkspace?
    @State private var preparation: SchoolCapturePreparationWorkspace?
    @State private var planning: SchoolPlanningWorkspace?
    @State private var opened: SchoolLesson?

    private var scopeKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0)"
    }
    /// Comme partout : moniteur d’une école active ; les droits sont relus par le serveur.
    private var instructs: Bool {
        workspace.membership?.roles.contains("INSTRUCTOR") == true && workspace.school?.status == "ACTIVE"
    }

    var body: some View {
        Button { open() } label: { label }
            .disabled(agendaClient == nil || !instructs)
            .onChange(of: scopeKey) { _, _ in
                lastStartNow?.invalidate(); lastStartNow = nil; startNow = nil
                preparation?.invalidate(); preparation = nil
                planning?.invalidate(); planning = nil; opened = nil
            }
            .sheet(item: $startNow, onDismiss: { closed() }) { model in
                SchoolStartNowView(model: model)
            }
            .sheet(item: $preparation, onDismiss: { onFinished() }) { model in
                SchoolCapturePreparationView(model: model, schoolWorkspace: workspace)
            }
            .sheet(item: $planning, onDismiss: { onFinished() }) { model in
                SchoolPlanningView(model: model)
            }
            .sheet(item: $opened, onDismiss: { onFinished() }) { lesson in
                if let agendaClient {
                    NavigationStack {
                        SchoolLessonReportView(client: agendaClient.reportClient, schoolWorkspace: workspace, lessonID: lesson.id,
                            learnerName: learnerName(lesson), opensCompletion: false)
                    }
                    .tint(DrivyTheme.accent)
                    .environment(captureController)
                }
            }
    }

    private func open() {
        guard let agendaClient, let person = workspace.person, let membership = workspace.membership, instructs else { return }
        let model = SchoolStartNowWorkspace(scope: agendaClient.scope(person: person, membership: membership),
            client: agendaClient.planningClient, learnerID: learnerID)
        lastStartNow = model; startNow = model
    }

    /// Leçon créée : le trajet part aussitôt si possible, sinon la leçon s’ouvre. Conflit de planning ou serveur sans
    /// la route : la planification classique s’ouvre avec l’élève déjà choisi.
    private func closed() {
        guard let model = lastStartNow else { return }
        lastStartNow = nil
        if let lesson = model.started {
            if mayStart(lesson), let agendaClient, let person = workspace.person, let membership = workspace.membership {
                preparation = agendaClient.capturePreparation(scope: agendaClient.scope(person: person, membership: membership),
                    lessonID: lesson.id, controller: captureController)
            } else { opened = lesson }
        } else if model.planInstead || model.unsupported {
            guard let agendaClient, let person = workspace.person, let membership = workspace.membership else { return onFinished() }
            let planned = SchoolPlanningWorkspace(scope: agendaClient.scope(person: person, membership: membership),
                client: agendaClient.planningClient, date: Date().addingTimeInterval(120))
            planned.learnerID = model.learnerID
            planning = planned
        } else { onFinished(); return }
        // Une feuille de suite vient d’être demandée : l’écran d’origine ne se relit qu’à sa fermeture (onDismiss).
        // Relire aussitôt fait apparaître la leçon créée, l’écran d’origine remplace alors ce bouton par « Démarrer le
        // trajet », la vue qui porte la feuille disparaît et la feuille de suite n’est jamais affichée.
    }

    private func mayStart(_ lesson: SchoolLesson) -> Bool {
        guard instructs, let captureController else { return false }
        return SchoolLessonHubRules.mayStartCapture(lesson: lesson,
            isAuthor: lesson.instructorMembershipId == workspace.membership?.membershipId, school: workspace.school,
            capture: SchoolLessonCaptureStatus(controller: captureController, lessonID: lesson.id),
            controllerCanPrepare: captureController.canPrepareCapture, now: Date())
    }

    private func learnerName(_ lesson: SchoolLesson) -> String {
        lesson.providedLearnerName
            ?? workspace.learners.first { $0.id == lesson.learnerId }?.displayName
            ?? (workspace.learner?.id == lesson.learnerId ? workspace.learner?.displayName : nil) ?? "Leçon de conduite"
    }
}
