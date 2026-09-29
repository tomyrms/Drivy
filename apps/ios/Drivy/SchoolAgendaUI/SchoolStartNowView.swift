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
    private(set) var learnerID: UUID?
    var trainingID: UUID?
    var meetingPoint = ""
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var pending: PendingSchoolCommand?
    /// Le serveur ne connaît pas encore « Démarrer une leçon ».
    private(set) var unsupported = false
    private(set) var started: SchoolLesson?
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var storageAvailable = false
    @ObservationIgnored private var invalidated = false

    init(scope: SchoolCommandScope, client: SchoolPlanningClient, outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope; self.client = client; self.outbox = outbox
    }

    var canStart: Bool {
        !invalidated && !isLoading && !isBusy && storageAvailable && pending == nil && started == nil
            && trainingID.map { id in trainings.contains { $0.id == id } } == true && meetingPoint.unicodeScalars.count <= 500
    }

    func load() async {
        guard !invalidated else { return }
        generation = UUID(); let request = generation
        isLoading = true; errorMessage = nil
        do { pending = try outbox.pending(for: scope); storageAvailable = true }
        catch { storageAvailable = false; errorMessage = SchoolConfigurationFailure.storage.localizedDescription }
        do {
            var all: [SchoolLearner] = [], cursor: String?, seen = Set<String>()
            repeat {
                let page = try await client.reader.learners(schoolID: scope.schoolID, query: "", cursor: cursor,
                    instructorMembershipID: scope.membershipID)
                all.append(contentsOf: page.items); cursor = page.nextCursor
                guard all.count <= 10_000 else { throw SchoolPlanningFailure.invalidResponse }
                if let cursor, !seen.insert(cursor).inserted { throw SchoolPlanningFailure.invalidResponse }
            } while cursor != nil
            guard request == generation else { return }
            learners = all.filter { $0.archivedAt == nil }
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            if learners.isEmpty { errorMessage = "Aucun élève ne t’est affecté. Demande à l’administration de vérifier les affectations." }
            isLoading = false
            if learners.count == 1, let only = learners.first { await select(only.id) }
        } catch {
            guard request == generation else { return }
            isLoading = false
            if !(error is CancellationError) { errorMessage = (error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription }
        }
    }

    /// Choisit l’élève ; sa seule formation en cours et son dernier lieu de rendez-vous sont repris.
    func select(_ id: UUID) async {
        guard !invalidated, learners.contains(where: { $0.id == id }), !isBusy else { return }
        generation = UUID(); let request = generation
        learnerID = id; trainings = []; trainingID = nil; meetingPoint = ""; errorMessage = nil; isLoading = true
        do {
            let values: [SchoolTraining] = try await client.records(scope.schoolID, path: ["trainings"],
                query: [URLQueryItem(name: "learnerId", value: id.uuidString)])
            guard request == generation else { return }
            let active = values.filter { $0.learnerId == id && $0.status == "ACTIVE" }
            trainings = active.filter { $0.startNowBlockerCode == nil }
            if trainings.count == 1 { trainingID = trainings.first?.id }
            if trainings.isEmpty { errorMessage = Self.startBlockerMessage(active.first?.startNowBlockerCode) }
            if let training = trainingID {
                let lessons: [SchoolLesson] = (try? await client.records(scope.schoolID, path: ["lessons"],
                    query: [URLQueryItem(name: "trainingId", value: training.uuidString)])) ?? []
                guard request == generation else { return }
                meetingPoint = SchoolStartNowWorkspace.lastMeetingPoint(lessons, trainingID: training) ?? ""
            }
            isLoading = false
        } catch {
            guard request == generation else { return }
            isLoading = false
            if !(error is CancellationError) { errorMessage = (error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription }
        }
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
        pending = nil; started = nil; isBusy = false; isLoading = false; storageAvailable = false; meetingPoint = ""
    }

    private func send(_ command: PendingSchoolCommand, fresh: Bool) async -> SchoolLesson? {
        let request = generation
        isBusy = true; errorMessage = nil
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
                if let error = model.errorMessage {
                    if let pending = model.pending {
                        // Résultat inconnu : même présentation que partout (« Demande à vérifier »).
                        Section {
                            DrivyPendingRequest(message: error, reference: pending.id,
                                retry: { Task { if await model.retry() != nil { dismiss() } } }, canRetry: !model.isBusy)
                        }
                            .drivyFormRows()
                    } else {
                        Section { SchoolErrorNotice(message: error) }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                Section {
                    Picker("Élève", selection: Binding(get: { model.learnerID }, set: { id in
                        if let id { Task { await model.select(id) } }
                    })) {
                        Text("Choisir un élève").tag(nil as UUID?)
                        ForEach(model.learners) { learner in Text(learner.displayName).tag(Optional(learner.id)) }
                    }
                    if model.trainings.count > 1 {
                        Picker("Formation", selection: $model.trainingID) {
                            Text("Choisir une formation").tag(nil as UUID?)
                            ForEach(model.trainings) { training in Text("Permis \(training.categoryCode)").tag(Optional(training.id)) }
                        }
                    }
                    LabeledContent("Lieu") {
                        TextField("Lieu du rendez-vous", text: $model.meetingPoint, axis: .vertical).lineLimit(1...3)
                            .multilineTextAlignment(.trailing)
                    }
                }
                    .drivyFormRows()
                .disabled(model.isBusy)
                if model.isLoading {
                    Section { DrivyLoadingState(title: model.learnerID == nil ? "Chargement des élèves…" : "Chargement de la formation…") }
                        .drivyFormRows()
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: SchoolFormLayout.maxWidth).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    Button {
                        Task {
                            _ = await model.start()
                            if model.started != nil || model.unsupported { dismiss() }
                        }
                    } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            if model.isBusy { ProgressView().tint(DrivyTheme.disabledText).accessibilityHidden(true) }
                            Label("Démarrer maintenant", systemImage: "location.fill")
                        }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!model.canStart)
                    .accessibilityIdentifier("start-now-confirm")
                }
            }
            .navigationTitle("Démarrer une leçon").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .task { if model.learners.isEmpty { await model.load() } }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }
}
