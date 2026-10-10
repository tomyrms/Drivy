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
/// La demande est chiffrée dans la file avant l’envoi ; un refus reste visible dans ce parcours.
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
    /// Demande que l’école a déclaré ne pas connaître : elle peut être renvoyée comme neuve, ou abandonnée.
    private(set) var absentPendingID: UUID?
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
    var pendingAbsent: Bool { pending != nil && pending?.id == absentPendingID }

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
            if Self.isAccessRefusal(error) { clearContext() }
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
                let lessons: [SchoolLesson]
                do {
                    lessons = try await client.records(scope.schoolID, path: ["lessons"],
                        query: [URLQueryItem(name: "trainingId", value: training.uuidString)])
                } catch {
                    if Self.isAccessRefusal(error) || error is CancellationError { throw error }
                    lessons = []
                }
                guard request == generation else { return }
                meetingPoint = SchoolStartNowWorkspace.lastMeetingPoint(lessons, trainingID: training) ?? ""
            }
            if trainingID != nil && trainingID == previousTrainingID { meetingPoint = previousMeetingPoint }
            contextValid = true; isLoading = false
        } catch {
            guard request == generation else { return }
            isLoading = false
            if Self.isAccessRefusal(error) { clearContext() }
            if !(error is CancellationError) { setContextError((error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription) }
        }
    }

    private static func isAccessRefusal(_ error: Error) -> Bool {
        if let failure = error as? SchoolPlanningFailure {
            return failure == .unauthorized || failure == .forbidden
        }
        if let failure = error as? SchoolAPIError {
            return failure == .unauthorized || failure == .forbidden || failure == .identityNotLinked
        }
        return false
    }

    /// Un refus explicite retire les données affichées sans effacer une demande durable en attente.
    private func clearContext() {
        learners = []; trainings = []; defaults = nil; learnerID = nil; trainingID = nil; meetingPoint = ""
        contextValid = false; started = nil; conflicted = false; planInstead = false
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
        case "OFFERING_NOT_READY": "L’offre de cette formation n’est pas prête. Demande à l’administration de vérifier sa durée et sa procédure."
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

    /// Demande son issue à l’école, quelle que soit l’action d’où la demande est partie. Confirmée, elle quitte
    /// la file (une leçon démarrée ici s’ouvre) ; inconnue de l’école, elle peut être abandonnée.
    func verify() async -> SchoolLesson? {
        guard !invalidated, let command = pending, !isBusy else { return nil }
        let request = generation
        isBusy = true; errorMessage = nil
        defer { if request == generation { isBusy = false } }
        do {
            let receipt = try await client.receipt(for: command)
            try outbox.remove(command)
            guard request == generation else { return nil }
            pending = nil; absentPendingID = nil
            guard command.kind == .startLessonNow, command.scope == scope else { return nil }
            guard let lesson = try? await client.lesson(schoolID: scope.schoolID, id: receipt.resourceId), request == generation else {
                errorMessage = "La leçon est enregistrée. Ferme cette fenêtre pour la retrouver dans Aujourd’hui."
                return nil
            }
            started = lesson
            return lesson
        } catch SchoolPlanningFailure.notFound {
            guard request == generation else { return nil }
            absentPendingID = command.id
        } catch {
            guard request == generation else { return nil }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription
        }
        return nil
    }

    /// Retire une demande que l’école ne connaît pas : rien n’a été enregistré, le parcours reprend.
    func abandon() async {
        guard !invalidated, let command = pending, pendingAbsent, !isBusy else { return }
        do { try outbox.remove(command) }
        catch { storageAvailable = false; errorMessage = SchoolConfigurationFailure.storage.localizedDescription; return }
        pending = nil; absentPendingID = nil; errorMessage = nil
        if !contextValid { await load() }
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
            // Une demande que l’école ne connaît pas se renvoie comme neuve : son refus est alors définitif.
            if fresh || command.id == absentPendingID, let failure = error as? SchoolPlanningFailure,
               failure == .notFound || failure.definitiveRejection {
                do { try outbox.remove(command); pending = nil; absentPendingID = nil }
                catch { storageAvailable = false; errorMessage = SchoolConfigurationFailure.storage.localizedDescription; return nil }
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
    @Environment(\.dynamicTypeSize) private var typeSize
    /// La recherche d’un élève prend toute la hauteur ; le formulaire, lui, tient dans une demi-feuille.
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    if let pending = model.pending {
                        // Toute demande restée en file se résout ici, même partie d’un autre écran : sans cela,
                        // rien ne peut démarrer et rien n’explique pourquoi.
                        let idle = !model.isBusy && !model.isLoading
                        DrivyPendingRequest(message: pending.waitingMessage(absent: model.pendingAbsent),
                            notes: model.errorMessage.map { [$0] } ?? [], reference: pending.id,
                            verify: model.pendingAbsent ? nil : { Task { if await model.verify() != nil { dismiss() } } }, canVerify: idle,
                            retry: pending.kind == .startLessonNow && pending.scope == model.scope ? { Task { if await model.retry() != nil { dismiss() } } } : nil,
                            canRetry: idle,
                            abandon: model.pendingAbsent ? { Task { await model.abandon() } } : nil, canAbandon: idle)
                    } else if let error = model.errorMessage {
                        SchoolErrorNotice(message: error, retry: !model.contextValid || model.learners.isEmpty || model.trainings.isEmpty || !model.storageAvailable
                            ? { Task { await reloadContext() } } : nil)
                        .disabled(model.isBusy || model.isLoading)
                    }
                    if model.learners.isEmpty && (model.isLoading || (model.defaults == nil && model.errorMessage == nil)) {
                        DrivySkeletonRows(count: 3).drivySkeleton("Chargement des élèves…")
                    } else {
                        // Le choix de l’élève reste actif pendant la lecture de ses formations : seules les lignes qui
                        // en dépendent (formation, lieu) se verrouillent, dans `fields`.
                        fields
                            .disabled(model.isBusy || model.pending != nil)
                    }
                    primaryAction
                }.drivyPageContent(maxWidth: DrivyLayout.compactColumn)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(DrivyTheme.canvas)
            .navigationTitle("Démarrer une leçon").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .task { if model.learners.isEmpty { await model.load() } }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large], selection: $detent)
        .onAppear { if typeSize.isAccessibilitySize { detent = .large } }
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldRow("Élève") {
                if model.hasPresetLearner, let name = model.learnerName {
                    Text(name).fixedSize(horizontal: false, vertical: true)
                } else {
                    NavigationLink {
                        SchoolLearnerSearchList(learners: model.learners, selectedID: model.learnerID) { id in
                            Task { await model.select(id) }
                        }
                        .onAppear { detent = .large }
                    } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            Text(model.learnerName ?? "Choisir un élève").fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                                .foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Élève")
                    .accessibilityValue(model.learnerName ?? "Aucun élève choisi")
                    .accessibilityIdentifier("start-now-learner")
                }
            }
            if model.isLoading && model.trainings.isEmpty && model.learnerID != nil {
                Divider()
                DrivySkeletonRow().drivySkeleton("Chargement de la formation…")
                    .padding(.vertical, DrivySpacing.s)
            } else if model.trainings.count > 1 {
                Divider()
                fieldRow("Formation") {
                    Picker("Formation", selection: $model.trainingID) {
                        Text("Choisir une formation").tag(nil as UUID?)
                        ForEach(model.trainings) { training in Text("Permis \(training.categoryCode)").tag(Optional(training.id)) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                // Les formations de l’élève se relisent : le choix attend leur réponse.
                .disabled(model.isLoading)
            } else if let training = model.trainings.first, training.id == model.trainingID {
                Divider()
                fieldRow("Formation") { Text("Permis \(training.categoryCode)") }
            }
            Divider()
            // Le lieu se remplit avec celui de la dernière leçon de l’élève : on n’écrit pas dessus pendant la lecture.
            SchoolMeetingPointField(text: $model.meetingPoint)
                .padding(.vertical, DrivySpacing.s)
                .frame(minHeight: 44)
                .disabled(model.isLoading)
            if model.meetingPointTooLong {
                DrivyFormMessage(text: "Raccourcis le lieu à 500 caractères.", tone: .danger)
                    .padding(.bottom, DrivySpacing.s)
            }
        }
        .padding(.horizontal, DrivySpacing.m)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.content))
    }

    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DrivySpacing.m))
        return layout {
            Text(title).fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize { Spacer(minLength: DrivySpacing.xs) }
            content()
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .padding(.vertical, DrivySpacing.s)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    @ViewBuilder private var primaryAction: some View {
        if model.conflicted {
            // Rien n’est forcé : le serveur a refusé, la seule issue est de planifier autrement.
            Button {
                model.planLater(); dismiss()
            } label: { Text("Planifier à un autre moment") }
                .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
                .accessibilityIdentifier("start-now-plan-later")
        } else {
            Button {
                Task {
                    _ = await model.start()
                    if model.started != nil { dismiss() }
                }
            } label: {
                DrivyBusyLabel(title: "Démarrer maintenant", busyTitle: "Démarrage…", isBusy: model.isBusy)
            }
            .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
            .disabled(!model.canStart)
            .accessibilityIdentifier("start-now-confirm")
        }
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
    /// La chaîne entière garde son hôte : création, préparation du GPS, puis fiche de leçon ou planification.
    var onPresentationChanged: (Bool) -> Void = { _ in }
    @ViewBuilder let label: Content

    @State private var startNow: SchoolStartNowWorkspace?
    @State private var lastStartNow: SchoolStartNowWorkspace?
    @State private var preparation: SchoolCapturePreparationWorkspace?
    @State private var preparingLesson: SchoolLesson?
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
                preparation?.invalidate(); preparation = nil; preparingLesson = nil
                planning?.invalidate(); planning = nil; opened = nil
                onPresentationChanged(false)
            }
            .sheet(item: $startNow, onDismiss: { closed() }) { model in
                SchoolStartNowView(model: model)
            }
            .fullScreenCover(item: $preparation, onDismiss: {
                if let lesson = preparingLesson, SchoolLessonCaptureStatus(controller: captureController, lessonID: lesson.id) != .collecting {
                    opened = lesson
                } else { finished() }
                preparingLesson = nil
            }) { model in
                SchoolCapturePreparationView(model: model, schoolWorkspace: workspace)
            }
            .sheet(item: $planning, onDismiss: { finished() }) { model in
                SchoolPlanningView(model: model)
            }
            .sheet(item: $opened, onDismiss: { finished() }) { lesson in
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
        onPresentationChanged(true)
        lastStartNow = model; startNow = model
    }

    private func finished() {
        onPresentationChanged(false)
        onFinished()
    }

    /// Leçon créée : le trajet part aussitôt si possible, sinon la leçon s’ouvre. En cas de conflit,
    /// la planification est choisie explicitement, avec l’élève déjà connu.
    private func closed() {
        guard let model = lastStartNow else { return }
        lastStartNow = nil
        if let lesson = model.started {
            if mayStart(lesson), let agendaClient, let person = workspace.person, let membership = workspace.membership {
                preparingLesson = lesson
                preparation = agendaClient.capturePreparation(scope: agendaClient.scope(person: person, membership: membership),
                    lessonID: lesson.id, controller: captureController)
            } else { opened = lesson }
        } else if model.planInstead {
            guard let agendaClient, let person = workspace.person, let membership = workspace.membership else { return finished() }
            let planned = SchoolPlanningWorkspace(scope: agendaClient.scope(person: person, membership: membership),
                client: agendaClient.planningClient, date: Date().addingTimeInterval(120))
            planned.learnerID = model.learnerID
            planning = planned
        } else { finished(); return }
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
