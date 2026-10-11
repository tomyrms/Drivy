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
            // Une demande neuve vient d’être enregistrée par `start()` : la réécrire ne ferait que retarder l’envoi.
            if !fresh { try outbox.save(command) }
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

/// La feuille « Démarrer une leçon » : élève, récapitulatif (formation, lieu, accord GPS), puis la leçon quand elle
/// démarre sans trajet. Les étapes se remplacent sur place, sans pousser de page ni changer de hauteur ; le départ
/// avec GPS passe sous le rideau de marque (`SchoolStartNowLaunch`).
struct SchoolStartNowView: View {
    @Bindable var launch: SchoolStartNowLaunch
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var form: SchoolStartNowWorkspace { launch.form }

    var body: some View {
        NavigationStack {
            ZStack {
                switch launch.step {
                case .learner:
                    learnerStep.transition(stepTransition(from: .leading))
                case .summary:
                    summaryStep.transition(stepTransition(from: .trailing))
                case .lesson(let lesson):
                    lessonStep(lesson).transition(stepTransition(from: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DrivyTheme.canvas)
        }
        // Une seule hauteur pour tout le parcours : la liste en a besoin, et la feuille ne se redimensionne
        // jamais pendant qu’une étape en remplace une autre.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .presentationBackground(DrivyTheme.canvas)
        .tint(DrivyTheme.accent)
        .sensoryFeedback(.start, trigger: launch.launches)
        .task { await launch.open() }
        .onChange(of: launch.closesSheet) { _, closes in if closes { dismiss() } }
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
        .navigationTitle("Démarrer une leçon").navigationBarTitleDisplayMode(.inline)
        .toolbar { closeItem }
        // Réglé par étape : la leçon ouverte sur place garde sa propre protection (bilan modifié).
        .interactiveDismissDisabled(launch.isBusy)
    }

    // MARK: - Récapitulatif

    private var summaryStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                notices
                identity
                if form.learnerID != nil {
                    fields
                    if let gps = launch.gps { gpsSection(gps) }
                }
            }
            .drivyPageContent(maxWidth: DrivyLayout.compactColumn)
            // Formation et lieu arrivent après la lecture : ils se posent sans pousser le reste d’un coup.
            .animation(DrivyMotion.reveal(reduceMotion), value: form.isLoading)
            .animation(DrivyMotion.reveal(reduceMotion), value: form.trainings.count)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DrivyStickyActionBar(maxWidth: DrivyLayout.compactColumn) { primaryAction }
        }
        .navigationTitle("Démarrer une leçon").navigationBarTitleDisplayMode(.inline)
        .toolbar { closeItem }
        .interactiveDismissDisabled(launch.isBusy)
    }

    @ViewBuilder private var notices: some View {
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
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
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
                        ForEach(form.trainings) { training in Text("Permis \(training.categoryCode)").tag(Optional(training.id)) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                // Les formations de l’élève se relisent : le choix attend leur réponse.
                .disabled(form.isLoading)
                Divider()
            }
            // Le lieu se remplit avec celui de la dernière leçon de l’élève : on n’écrit pas dessus pendant la lecture.
            SchoolMeetingPointField(text: meetingPoint)
                .padding(.vertical, DrivySpacing.s)
                .frame(minHeight: 44)
                .disabled(form.isLoading)
            if form.meetingPointTooLong {
                DrivyFormMessage(text: "Raccourcis le lieu à 500 caractères.", tone: .danger)
                    .padding(.bottom, DrivySpacing.s)
            }
        }
        .padding(.horizontal, DrivySpacing.m)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
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
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    /// Accord de l’élève, puis l’état de cet appareil seulement s’il empêchera l’enregistrement.
    private func gpsSection(_ gps: SchoolStartNowGPS) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            SchoolRecordingChoiceInline(model: gps.consent, answer: gps.answer,
                isEnabled: !launch.isBusy && form.pending == nil) { status in gps.select(status) }
            if gps.answer == .allowed && gps.consentIsClear {
                switch gps.device {
                case .denied: deviceNotice("Localisation désactivée pour Drivy. La leçon démarrera sans GPS.")
                case .approximate: deviceNotice("Position exacte désactivée pour Drivy. La leçon démarrera sans GPS.")
                case .ready, .needsPermission: EmptyView()
                }
            }
        }
        .padding(DrivySpacing.m)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
        .animation(DrivyMotion.reveal(reduceMotion), value: gps.device)
    }

    private func deviceNotice(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivyInlineMessage(text: text, tone: .warning)
            Button("Ouvrir Réglages", systemImage: "gearshape") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
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
                DrivyBusyLabel(title: "Démarrer maintenant",
                    busyTitle: launch.phase == .requestingPermission ? "Autorisation de localisation…" : "Démarrage…",
                    isBusy: launch.isBusy)
            }
            .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
            // L’accord de l’élève se lit encore : un départ maintenant partirait sans GPS sans l’avoir voulu.
            .disabled(!form.canStart || launch.phase != .editing || launch.gps?.isReading == true)
            .accessibilityIdentifier("start-now-confirm")
        }
    }

    // MARK: - Leçon

    /// Leçon démarrée sans trajet : elle s’ouvre à la place du récapitulatif, dans la même feuille.
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

/// Le geste complet « lancer une leçon tout de suite », réutilisable depuis Aujourd’hui et depuis la fiche d’un élève.
/// La feuille porte tout le parcours (`SchoolStartNowLaunch`) ; seul un conflit de planning ouvre une autre feuille,
/// la planification, avec l’élève déjà connu. Le style du bouton est celui de l’appelant.
struct SchoolStartNowButton<Content: View>: View {
    @Bindable var workspace: SchoolWorkspace
    let agendaClient: SchoolAgendaClient?
    let captureController: SchoolCaptureSessionController?
    var learnerID: UUID?
    /// Appelé quand le geste est terminé (feuille fermée, ou trajet à l’écran) pour que l’écran d’origine se relise.
    var onFinished: () -> Void = {}
    /// Toute la chaîne garde son hôte : l’écran d’origine ne se relit pas pendant qu’elle est présentée.
    var onPresentationChanged: (Bool) -> Void = { _ in }
    @ViewBuilder let label: Content

    @State private var launch: SchoolStartNowLaunch?
    @State private var lastLaunch: SchoolStartNowLaunch?
    @State private var planning: SchoolPlanningWorkspace?

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
                lastLaunch?.invalidate(); lastLaunch = nil; launch = nil
                planning?.invalidate(); planning = nil
                onPresentationChanged(false)
            }
            .sheet(item: $launch, onDismiss: { closed() }) { model in
                SchoolStartNowView(launch: model)
            }
            .sheet(item: $planning, onDismiss: { finished() }) { model in
                SchoolPlanningView(model: model)
            }
    }

    private func open() {
        // Une seule chaîne à la fois : un second appui avant l’apparition de la feuille ne la remplace pas.
        guard launch == nil, lastLaunch == nil, planning == nil else { return }
        guard let agendaClient, let person = workspace.person, let membership = workspace.membership, instructs else { return }
        let form = SchoolStartNowWorkspace(scope: agendaClient.scope(person: person, membership: membership),
            client: agendaClient.planningClient, learnerID: learnerID)
        let model = SchoolStartNowLaunch(form: form, agenda: agendaClient, workspace: workspace, controller: captureController)
        let presentationChanged = onPresentationChanged, finishedAction = onFinished
        model.onFinished = { presentationChanged(false); finishedAction() }
        onPresentationChanged(true)
        lastLaunch = model; launch = model
    }

    private func finished() {
        onPresentationChanged(false)
        onFinished()
    }

    /// Feuille fermée. Un conflit de planning ouvre la planification ; un trajet qui démarre termine la chaîne
    /// lui-même (la carte remplace l’écran d’origine) ; sinon l’écran d’origine se relit maintenant.
    private func closed() {
        guard let model = lastLaunch else { return }
        lastLaunch = nil
        if model.form.planInstead, let agendaClient, let person = workspace.person, let membership = workspace.membership {
            let planned = SchoolPlanningWorkspace(scope: agendaClient.scope(person: person, membership: membership),
                client: agendaClient.planningClient, date: Date().addingTimeInterval(120))
            planned.learnerID = model.form.learnerID
            planning = planned
        } else if !model.finishesItself {
            model.complete()
        }
    }
}
