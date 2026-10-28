import Foundation
import Observation
import SwiftUI

/// Corps de « Démarrer une leçon » : le serveur fixe l’heure (maintenant), la durée, la prestation et le moniteur.
struct SchoolStartNowBody: Encodable, Sendable {
    let operationId: UUID
    let trainingId: UUID
    let meetingPoint: String?
    var prepareForGPS: Bool? = nil
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
            // Préférences et élèves ne dépendent pas l’un de l’autre : ils se lisent ensemble (#86).
            let schoolID = scope.schoolID, membershipID = scope.membershipID, client = self.client
            let defaultsRead = Task { @MainActor in try await client.defaults(schoolID: schoolID, membershipID: membershipID) }
            defer { defaultsRead.cancel() }
            var all: [SchoolLearner] = []
            if let preset = presetLearnerID {
                // Élève connu depuis sa fiche : seul son dossier est relu. Le serveur ne le rend visible à un moniteur
                // que s’il lui est affecté ; ses formations (relues ensuite) disent s’il peut démarrer.
                do { all = [try await client.reader.learner(schoolID: schoolID, id: preset)] }
                catch SchoolAPIError.notFound { all = [] }
            } else {
                var cursor: String?, seen = Set<String>()
                repeat {
                    let page = try await client.reader.learners(schoolID: schoolID, query: "", cursor: cursor,
                        instructorMembershipID: membershipID, pageSize: 100)
                    all.append(contentsOf: page.items); cursor = page.nextCursor
                    guard all.count <= 10_000 else { throw SchoolPlanningFailure.invalidResponse }
                    if let cursor, !seen.insert(cursor).inserted { throw SchoolPlanningFailure.invalidResponse }
                    // Première page affichée tout de suite : la liste se consulte pendant que la suite arrive.
                    if cursor != nil, request == generation, !Task.isCancelled, learners.isEmpty {
                        learners = Self.visible(all)
                    }
                } while cursor != nil
            }
            let defaults = try await defaultsRead.value
            guard request == generation, !Task.isCancelled else { return }
            self.defaults = defaults
            learners = Self.visible(all)
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

    private static func visible(_ all: [SchoolLearner]) -> [SchoolLearner] {
        all.filter { $0.archivedAt == nil }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
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
            if trainingID != nil && trainingID == previousTrainingID { meetingPoint = previousMeetingPoint }
            // La formation suffit pour démarrer : le dernier lieu n’est qu’un préremplissage, lu ensuite sans bloquer.
            contextValid = true; isLoading = false
            if let training = trainingID, training != previousTrainingID {
                await prefillMeetingPoint(training: training, request: request)
            }
        } catch {
            guard request == generation else { return }
            isLoading = false
            if Self.isAccessRefusal(error) { clearContext() }
            if !(error is CancellationError) { setContextError((error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription) }
        }
    }

    /// Préremplit le lieu depuis les leçons récentes, sans jamais écraser une saisie faite entre-temps.
    private func prefillMeetingPoint(training: UUID, request: UUID) async {
        let typedBefore = meetingPoint
        do {
            let lessons = try await client.recentLessons(schoolID: scope.schoolID, trainingID: training)
            guard request == generation, trainingID == training, meetingPoint == typedBefore, typedBefore.isEmpty else { return }
            meetingPoint = Self.lastMeetingPoint(lessons, trainingID: training) ?? ""
        } catch {
            guard request == generation, Self.isAccessRefusal(error) else { return }
            clearContext()
            setContextError((error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription)
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
    func start(prepareForGPS: Bool = false) async -> SchoolLesson? {
        guard canStart, let trainingID else { return nil }
        let operation = UUID()
        let point = meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let command: PendingSchoolCommand
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let body = try encoder.encode(SchoolStartNowBody(operationId: operation, trainingId: trainingID, meetingPoint: point.isEmpty ? nil : point, prepareForGPS: prepareForGPS ? true : nil))
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
            announceStarted(lesson)
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

    /// Émis après confirmation durable seulement, sans contenu pédagogique ni position.
    private func announceStarted(_ lesson: SchoolLesson) {
        NotificationCenter.default.post(name: .drivyLessonsDidChange, object: SchoolLessonChange(
            schoolID: scope.schoolID, trainingID: lesson.trainingId, lessonID: lesson.id, kind: .startLessonNow))
    }

    private func send(_ command: PendingSchoolCommand, fresh: Bool) async -> SchoolLesson? {
        let request = generation
        isBusy = true; errorMessage = nil; conflicted = false
        defer { if request == generation { isBusy = false } }
        do {
            // Une demande neuve vient d’être enregistrée par `start()` : la réécrire ne ferait que retarder l’envoi.
            if !fresh { try outbox.save(command) }
            let lesson = try await client.startNow(command)
            try outbox.remove(command)
            // L’école a créé la leçon : l’agenda et la liste des formations se relisent, même si cet écran est déjà refermé.
            announceStarted(lesson)
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

/// La fenêtre « Démarrer une leçon » : élève (liste en plein écran), récapitulatif (petite carte flottante centrée dont la
/// hauteur suit le contenu), puis la leçon quand elle démarre sans trajet (plein écran, format normal). Les étapes se
/// remplacent sur place dans une même présentation à fond transparent ; le départ avec GPS passe sous le rideau de
/// marque (`SchoolStartNowLaunch`).
struct SchoolStartNowView: View {
    @Bindable var launch: SchoolStartNowLaunch
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var form: SchoolStartNowWorkspace { launch.form }

    var body: some View {
        ZStack {
            switch launch.step {
            case .learner:
                NavigationStack { learnerStep }
                    .background(DrivyTheme.canvas.ignoresSafeArea())
                    .transition(stepTransition(from: .leading))
            case .summary:
                summaryCard.transition(stepTransition(from: .trailing))
            case .lesson(let lesson):
                NavigationStack { lessonStep(lesson) }
                    .background(DrivyTheme.canvas.ignoresSafeArea())
                    .transition(stepTransition(from: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Fond transparent : l’écran d’origine reste visible, atténué par la carte. Les étapes plein écran portent le leur.
        .presentationBackground(.clear)
        .tint(DrivyTheme.accent)
        .sensoryFeedback(.start, trigger: launch.launches)
        .task { await launch.open() }
        .onChange(of: launch.closesSheet) { _, closes in if closes { dismiss() } }
        .onChange(of: launch.workspace.school?.modules.gpsEnabled) { _, _ in launch.refreshGPSAvailability() }
        .onChange(of: launch.controller?.canPrepareCapture) { _, _ in launch.refreshGPSAvailability() }
        // Retour d’arrière-plan : le choix a pu changer ailleurs, il se relit sans rien écrire.
        .onChange(of: scenePhase) { _, phase in if phase == .active { launch.refreshConsent() } }
        // Lecture interrompue (ni réponse ni panne) : elle reprend, elle ne passe pas pour une absence de choix.
        .onChange(of: launch.gps?.readWasInterrupted ?? false) { _, interrupted in if interrupted { launch.refreshConsent() } }
        .onDisappear { launch.sheetClosed() }
    }

    /// Une étape glisse à peine et se fond ; sous Réduire les animations, un fondu seulement.
    private func stepTransition(from edge: Edge) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let offset: CGFloat = edge == .leading ? -36 : 36
        return .offset(x: offset).combined(with: .opacity)
    }

    @ToolbarContentBuilder private var closeItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Fermer") { dismiss() }.disabled(launch.isBusy)
        }
    }

    // MARK: - Élève

    private var learnerStep: some View {
        Group {
            if form.learners.isEmpty && (form.isLoading || (form.defaults == nil && form.errorMessage == nil)) {
                ScrollView {
                    DrivySkeletonRows(count: 6, leading: .avatar, lines: 1)
                        .drivySkeleton("Chargement des élèves…")
                        .drivyPageContent(maxWidth: DrivyLayout.compactColumn)
                }
                .scrollDisabled(true)
            } else if form.learners.isEmpty {
                ScrollView {
                    if let error = form.errorMessage {
                        SchoolErrorNotice(message: error, retry: { Task { await launch.reload() } })
                            .disabled(form.isLoading)
                            .drivyPageContent(maxWidth: DrivyLayout.compactColumn)
                    }
                }
            } else {
                SchoolLearnerPicker(learners: form.learners, selectedID: form.learnerID) { id in
                    withAnimation(DrivyMotion.step(reduceMotion)) { launch.choose(id) }
                }
            }
        }
        .background(DrivyTheme.canvas)
        .navigationTitle("Démarrer une leçon").navigationBarTitleDisplayMode(.inline)
        .toolbar { closeItem }
    }

    // MARK: - Récapitulatif

    /// Carte flottante : seul ce que le cas demande s’y trouve. Un choix GPS connu n’y laisse que le bouton de départ
    /// et une action discrète ; la question, longue, n’apparaît que sans choix applicable, et la carte défile alors.
    private var summaryCard: some View {
        DrivyFloatingCard(title: "Démarrer une leçon", isClosable: !launch.isBusy, close: { dismiss() }) {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                notices
                identity
                if form.learnerID != nil {
                    fields
                    if launch.isReadingPolicy {
                        DrivySkeletonRow(lines: 1).drivySkeleton("Vérification des conditions de départ…")
                    } else if let error = launch.policyError {
                        SchoolErrorNotice(message: error, retry: { Task { await launch.loadStartPolicy() } })
                            .disabled(launch.isBusy)
                    } else if let reason = launch.gpsUnavailableReason {
                        SchoolGPSUnavailableNotice(reason: reason, workspace: launch.workspace,
                            managementURL: AppConfiguration.fromBundle()?.gpsManagementURL(schoolID: form.scope.schoolID))
                    } else if let gps = launch.gps, launch.gpsMatchesLearner {
                        gpsSection(gps)
                    }
                }
            }
            // Formation et lieu arrivent après la lecture : ils se posent sans pousser le reste d’un coup.
            .animation(DrivyMotion.reveal(reduceMotion), value: form.isLoading)
            .animation(DrivyMotion.reveal(reduceMotion), value: form.trainings.count)
            .animation(DrivyMotion.reveal(reduceMotion), value: launch.gps?.display)
        } footer: {
            primaryAction
        }
    }

    @ViewBuilder private var notices: some View {
        if let issue = launch.tripIssue { DrivyInlineMessage(text: issue, tone: .warning) }
        if let pending = form.pending {
            // Toute demande restée en file se résout ici, même partie d’un autre écran : sans cela,
            // rien ne peut démarrer et rien n’explique pourquoi.
            let idle = !form.isBusy && !form.isLoading
            DrivyPendingRequest(message: pending.waitingMessage(absent: form.pendingAbsent),
                notes: form.errorMessage.map { [$0] } ?? [], reference: pending.id,
                verify: form.pendingAbsent ? nil : { Task {
                    if let lesson = await form.verify() { launch.resolved(lesson) } else { launch.pendingCleared() }
                } },
                canVerify: idle,
                retry: pending.kind == .startLessonNow && pending.scope == form.scope
                    ? { Task { if let lesson = await form.retry() { launch.resolved(lesson) } } } : nil,
                canRetry: idle,
                abandon: form.pendingAbsent ? { Task { await form.abandon(); launch.pendingCleared() } } : nil, canAbandon: idle)
        } else if let error = form.errorMessage {
            SchoolErrorNotice(message: error, retry: !form.contextValid || form.learners.isEmpty || form.trainings.isEmpty || !form.storageAvailable
                ? { Task { await launch.reload() } } : nil)
                .disabled(form.isBusy || form.isLoading)
        }
    }

    @ViewBuilder private var identity: some View {
        if let name = form.learnerName {
            DrivyLearnerIdentity(name: name, detail: trainingDetail, variant: .compact) {
                if form.presetLearnerID == nil && form.learners.count > 1 {
                    Button("Changer") {
                        withAnimation(DrivyMotion.step(reduceMotion)) { launch.changeLearner() }
                    }
                    .buttonStyle(.drivyText)
                    .disabled(launch.isBusy)
                    .accessibilityLabel("Changer d’élève")
                    .accessibilityIdentifier("start-now-learner")
                }
            }
        } else if form.pending == nil && (form.isLoading || (form.learners.isEmpty && form.errorMessage == nil)) {
            DrivySkeletonRow(leading: .avatar, lines: 2).drivySkeleton("Chargement de l’élève…")
        }
    }

    /// Une seule formation : elle se lit sous le nom, sans ligne à elle.
    private var trainingDetail: String? {
        guard form.trainings.count == 1, let training = form.trainings.first, training.id == form.trainingID else { return nil }
        return "Permis \(training.categoryCode)"
    }

    private var meetingPoint: Binding<String> {
        Binding(get: { form.meetingPoint }, set: { form.meetingPoint = $0 })
    }

    private var trainingID: Binding<UUID?> {
        Binding(get: { form.trainingID }, set: { form.trainingID = $0 })
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 0) {
            if form.trainings.count > 1 {
                fieldRow("Formation") {
                    Picker("Formation", selection: trainingID) {
                        Text("Choisir une formation").tag(nil as UUID?)
                        ForEach(form.trainings) { training in
                            DrivingLicenseLabel(title: "Permis \(training.categoryCode)", code: training.categoryCode)
                                .tag(Optional(training.id))
                        }
                    }
                    .pickerStyle(.menu).labelsHidden()
                    .frame(minHeight: DrivyLayout.tapTarget).contentShape(Rectangle())
                }
                // Les formations de l’élève se relisent : le choix attend leur réponse.
                .disabled(form.isLoading)
                Divider()
            }
            // Le lieu se remplit avec celui de la dernière leçon de l’élève : on n’écrit pas dessus pendant la lecture.
            SchoolMeetingPointField(text: meetingPoint)
                .padding(.vertical, DrivySpacing.s)
                .frame(minHeight: DrivyLayout.tapTarget)
                .disabled(form.isLoading)
            if form.meetingPointTooLong {
                DrivyFormMessage(text: "Raccourcis le lieu à 500 caractères.", tone: .danger)
                    .padding(.bottom, DrivySpacing.s)
            }
        }
        .padding(.horizontal, DrivySpacing.m)
        .background(DrivyTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
        .disabled(launch.isBusy || form.pending != nil)
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
        .frame(maxWidth: .infinity, minHeight: DrivyLayout.tapTarget, alignment: .leading)
    }

    /// Le choix GPS, selon ce qui est réellement vérifié. Lecture ou panne ne valent ni absence de choix ni accord ;
    /// un choix connu ne montre ni cartes ni panneau, seulement le bouton de départ et une action discrète.
    @ViewBuilder private func gpsSection(_ gps: SchoolStartNowGPS) -> some View {
        switch gps.display {
        case .reading:
            DrivySkeletonRow(lines: 1).drivySkeleton("Lecture de l’accord GPS…")
        case .unavailable:
            gpsUnavailable(gps)
        case .needsReview, .question:
            SchoolRecordingChoiceInline(model: gps.consent, answer: gps.answer,
                isEnabled: !launch.isBusy && form.pending == nil, forcesQuestion: gps.isChanging) { status in gps.select(status) }
                .padding(DrivySpacing.m)
                .background(DrivyTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
        case .known:
            knownChoice(gps)
        }
    }

    private func gpsUnavailable(_ gps: SchoolStartNowGPS) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivyInlineMessage(text: gps.consent.errorMessage ?? "L’accord GPS n’a pas pu être lu. Réessaie avant le départ.",
                tone: .warning)
            if !gps.consent.accessRevoked {
                Button { Task { await gps.load() } } label: { Label("Réessayer", systemImage: "arrow.clockwise") }
                    .buttonStyle(.drivyText)
                    .disabled(gps.consent.isLoading || launch.isBusy)
                    .accessibilityIdentifier("start-now-gps-retry")
            }
        }
    }

    /// Choix valide : rien à décider. L’état de cet appareil (autorisation d’iOS) reste expliqué quand il empêchera le trajet.
    private func knownChoice(_ gps: SchoolStartNowGPS) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            if gps.answer == .allowed && gps.consentIsClear {
                switch gps.device {
                case .denied: deviceNotice(launch.requiresGPS ? "Autorise la localisation dans Réglages avant de démarrer."
                    : "Localisation désactivée pour Drivy. La leçon démarrera sans GPS.")
                case .approximate: deviceNotice(launch.requiresGPS ? "Active la position exacte dans Réglages avant de démarrer."
                    : "Position exacte désactivée pour Drivy. La leçon démarrera sans GPS.")
                case .ready, .needsPermission: EmptyView()
                }
            }
            // Une réponse envoyée qui n’a pas abouti : le choix enregistré revient, avec la raison.
            if !gps.consent.isBusy, let error = gps.consent.storageError ?? gps.consent.errorMessage {
                DrivyInlineMessage(text: error, tone: .warning)
            }
            Button("Modifier le choix GPS") {
                withAnimation(DrivyMotion.reveal(reduceMotion)) { gps.beginChanging() }
            }
            .buttonStyle(.drivyText)
            .frame(minHeight: DrivyLayout.tapTarget, alignment: .leading)
            .disabled(launch.isBusy || form.pending != nil || gps.consent.isBusy)
            .accessibilityIdentifier("start-now-gps-change")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(DrivyMotion.reveal(reduceMotion), value: gps.device)
    }

    private func deviceNotice(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivyInlineMessage(text: text, tone: .warning)
            Button("Ouvrir Réglages", systemImage: "gearshape") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.drivyText)
        }
        .accessibilityIdentifier("start-now-gps-device")
    }

    @ViewBuilder private var primaryAction: some View {
        if form.conflicted {
            // Rien n’est forcé : le serveur a refusé, la seule issue est de planifier autrement.
            Button {
                form.planLater(); dismiss()
            } label: { Text("Planifier à un autre moment") }
                .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
                .accessibilityIdentifier("start-now-plan-later")
        } else {
            Button { launch.launch() } label: {
                DrivyBusyLabel(title: launch.startTitle,
                    busyTitle: launch.phase == .requestingPermission ? "Autorisation de localisation…" : "Démarrage…",
                    isBusy: launch.isBusy)
            }
            .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
            // L’accord de l’élève se lit encore : un départ maintenant partirait sans GPS sans l’avoir voulu.
            .disabled(!launch.canLaunch)
            .accessibilityIdentifier("start-now-confirm")
        }
    }

    // MARK: - Leçon

    /// Leçon démarrée sans trajet : elle s’ouvre en plein écran, dans son format normal, à la place du récapitulatif.
    private func lessonStep(_ lesson: SchoolLesson) -> some View {
        SchoolLessonReportView(client: launch.agenda.reportClient, schoolWorkspace: launch.workspace, lessonID: lesson.id,
            learnerName: launch.learnerName(lesson), opensCompletion: false)
            .environment(launch.controller)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let issue = launch.tripIssue {
                    SchoolTripIssueBanner(text: issue) {
                        withAnimation(DrivyMotion.reveal(reduceMotion)) { launch.dismissTripIssue() }
                    }
                    .transition(.opacity)
                }
            }
    }
}

/// Présentation de « Démarrer une leçon » : la feuille du parcours, puis la planification après un conflit.
/// Elle appartient à un écran stable. Un bouton rendu dans une branche de l’écran (la carte d’Aujourd’hui change
/// avec l’heure) ne la porte pas lui-même : en quittant la hiérarchie, il fermerait la feuille ouverte.
@MainActor @Observable final class SchoolStartNowPresentation {
    var launch: SchoolStartNowLaunch?
    var planning: SchoolPlanningWorkspace?
    @ObservationIgnored private var lastLaunch: SchoolStartNowLaunch?
    @ObservationIgnored private var onFinished: () -> Void = {}
    @ObservationIgnored private var onPresentationChanged: (Bool) -> Void = { _ in }

    func open(workspace: SchoolWorkspace, agendaClient: SchoolAgendaClient?, captureController: SchoolCaptureSessionController?,
              learnerID: UUID?, onFinished: @escaping () -> Void, onPresentationChanged: @escaping (Bool) -> Void) {
        // Une seule chaîne à la fois : un second appui avant l’apparition de la feuille ne la remplace pas.
        guard launch == nil, lastLaunch == nil, planning == nil else { return }
        guard let agendaClient, let person = workspace.person, let membership = workspace.membership,
              membership.roles.contains("INSTRUCTOR"), workspace.school?.status == "ACTIVE" else { return }
        let form = SchoolStartNowWorkspace(scope: agendaClient.scope(person: person, membership: membership),
            client: agendaClient.planningClient, learnerID: learnerID)
        let model = SchoolStartNowLaunch(form: form, agenda: agendaClient, workspace: workspace, controller: captureController)
        self.onFinished = onFinished
        self.onPresentationChanged = onPresentationChanged
        model.onFinished = { onPresentationChanged(false); onFinished() }
        onPresentationChanged(true)
        lastLaunch = model; launch = model
    }

    /// Feuille fermée. Un conflit de planning ouvre la planification ; un trajet qui démarre termine la chaîne
    /// lui-même (la carte remplace l’écran d’origine) ; sinon l’écran d’origine se relit maintenant.
    func closed(workspace: SchoolWorkspace, agendaClient: SchoolAgendaClient?) {
        guard let model = lastLaunch else { return }
        lastLaunch = nil
        if model.form.planInstead, let agendaClient, let person = workspace.person, let membership = workspace.membership {
            let planned = SchoolPlanningWorkspace(scope: agendaClient.scope(person: person, membership: membership),
                client: agendaClient.planningClient, date: Date().addingTimeInterval(120), suggestingNextSlotFrom: Date())
            planned.learnerID = model.form.learnerID
            planning = planned
        } else if !model.finishesItself {
            model.complete()
        }
    }

    /// Planification refermée : fin de la chaîne.
    func finished() {
        onPresentationChanged(false)
        onFinished()
    }

    /// Autre compte, autre école ou autres droits : rien de la chaîne en cours ne reste présenté.
    func reset() {
        lastLaunch?.invalidate(); lastLaunch = nil; launch = nil
        planning?.invalidate(); planning = nil
        onPresentationChanged(false)
    }
}

/// Les deux feuilles de la chaîne, posées sur une vue qui reste en place pendant tout le parcours.
struct SchoolStartNowSheets: ViewModifier {
    @Bindable var presentation: SchoolStartNowPresentation
    let workspace: SchoolWorkspace
    let agendaClient: SchoolAgendaClient?

    private var scopeKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0)"
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: scopeKey) { _, _ in presentation.reset() }
            .fullScreenCover(item: $presentation.launch, onDismiss: { presentation.closed(workspace: workspace, agendaClient: agendaClient) }) { model in
                SchoolStartNowView(launch: model)
            }
            .sheet(item: $presentation.planning, onDismiss: { presentation.finished() }) { model in
                SchoolPlanningView(model: model)
            }
    }
}

/// Le geste complet « lancer une leçon tout de suite », réutilisable depuis Aujourd’hui et depuis la fiche d’un élève.
/// La feuille porte tout le parcours (`SchoolStartNowLaunch`) ; seul un conflit de planning ouvre une autre feuille,
/// la planification, avec l’élève déjà connu. Le style du bouton est celui de l’appelant.
/// Sans `presentation`, le bouton porte lui-même ses feuilles : il doit alors rester en place tant qu’elles sont
/// ouvertes (barre d’action du dossier). Dans un contenu qui change, l’écran hôte fournit la présentation et pose
/// `SchoolStartNowSheets` sur une vue stable.
struct SchoolStartNowButton<Content: View>: View {
    @Bindable var workspace: SchoolWorkspace
    let agendaClient: SchoolAgendaClient?
    let captureController: SchoolCaptureSessionController?
    var learnerID: UUID?
    /// Appelé quand le geste est terminé (feuille fermée, ou trajet à l’écran) pour que l’écran d’origine se relise.
    var onFinished: () -> Void = {}
    /// Toute la chaîne garde son hôte : l’écran d’origine ne se relit pas pendant qu’elle est présentée.
    var onPresentationChanged: (Bool) -> Void = { _ in }
    /// Présentation tenue par l’écran hôte ; `nil` : celle de ce bouton.
    var presentation: SchoolStartNowPresentation? = nil
    @ViewBuilder let label: Content

    @State private var ownPresentation = SchoolStartNowPresentation()

    /// Comme partout : moniteur d’une école active ; les droits sont relus par le serveur.
    private var instructs: Bool {
        workspace.membership?.roles.contains("INSTRUCTOR") == true && workspace.school?.status == "ACTIVE"
    }

    var body: some View {
        let button = Button {
            (presentation ?? ownPresentation).open(workspace: workspace, agendaClient: agendaClient,
                captureController: captureController, learnerID: learnerID, onFinished: onFinished,
                onPresentationChanged: onPresentationChanged)
        } label: { label }
            .disabled(agendaClient == nil || !instructs)
        if presentation == nil {
            button.modifier(SchoolStartNowSheets(presentation: ownPresentation, workspace: workspace, agendaClient: agendaClient))
        } else {
            button
        }
    }
}
