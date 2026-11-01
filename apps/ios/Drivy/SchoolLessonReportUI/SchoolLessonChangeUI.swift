import SwiftUI

// Demandes de l'élève sur sa leçon (#52). Une demande ne change pas la leçon : tant que le personnel n'a pas répondu, le créneau
// d'origine reste valable et l'écran le dit. Ces gestes passent directement par l'école, sans file locale : sans réseau, rien ne
// part et l'écran le dit, sans jamais afficher « envoyée » avant la réponse de l'école.

/// État et gestes des demandes d'une leçon, pour l'élève comme pour le personnel qui la gère.
@MainActor @Observable final class SchoolLessonChangeModel {
    let schoolID: UUID
    let lessonID: UUID
    private let client: SchoolLessonChangeClient
    private(set) var state: SchoolLessonChangeState?
    private(set) var isLoading = false
    private(set) var isSending = false
    var errorMessage: String?
    /// Une opération par geste, gardée jusqu'à son aboutissement ou son refus définitif : un nouvel essai après une réponse
    /// perdue rejoue la même demande au lieu d'en créer une seconde.
    private var operation: (key: String, id: UUID)?

    init(client: SchoolLessonChangeClient, schoolID: UUID, lessonID: UUID) {
        self.client = client; self.schoolID = schoolID; self.lessonID = lessonID
    }

    var pending: SchoolLessonChangeRequest? { state?.pending }
    var canRequest: Bool { state?.conditions.canRequest == true }

    func load() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do { state = try await client.state(schoolID: schoolID, lessonID: lessonID) }
        catch is CancellationError { return }
        catch { errorMessage = Self.message(error) }
    }

    func create(kind: SchoolLessonChangeRequest.Kind, note: String) async -> Bool {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = operationID(for: "create|\(kind.rawValue)|\(text)")
        return await send { try await client.create(schoolID: schoolID, lessonID: lessonID, operationID: id, kind: kind, note: text) }
    }

    func withdraw() async -> Bool {
        guard let request = pending, request.mine else { return false }
        let id = operationID(for: "withdraw|\(request.id)|\(request.version)")
        return await send { try await client.withdraw(schoolID: schoolID, request: request, operationID: id) }
    }

    func refuse(_ request: SchoolLessonChangeRequest, note: String) async -> Bool {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = operationID(for: "refuse|\(request.id)|\(request.version)|\(text)")
        return await send { try await client.refuse(schoolID: schoolID, request: request, operationID: id, note: text) }
    }

    private func operationID(for key: String) -> UUID {
        if let operation, operation.key == key { return operation.id }
        let created = UUID(); operation = (key, created); return created
    }

    private func send(_ work: () async throws -> SchoolLessonChangeState) async -> Bool {
        guard !isSending else { return false }
        isSending = true; errorMessage = nil; defer { isSending = false }
        do {
            state = try await work(); operation = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            // Un refus définitif ne se rejoue pas ; une panne ou une réponse perdue garde l'opération pour le prochain essai.
            if (error as? SchoolPlanningFailure)?.definitiveRejection == true { operation = nil }
            errorMessage = Self.message(error)
            return false
        }
    }

    static func message(_ error: Error) -> String {
        guard let failure = error as? SchoolPlanningFailure else { return "La demande n’a pas pu aboutir. Réessaie." }
        switch failure {
        case .unavailable: return "L’école est momentanément inaccessible. Réessaie : la demande ne sera enregistrée qu’une fois."
        case .conflict: return "Cette demande a changé. Elle a été relue."
        default: return failure.errorDescription ?? "La demande n’a pas pu aboutir. Réessaie."
        }
    }
}

/// Texte court d'une échéance dans le fuseau de la leçon.
@MainActor private func changeDeadlineText(_ date: Date, zone: String) -> String {
    SchoolDateFormat.template("EEEdMMMjmm", date, zone: zone)
}

/// Demande en cours ou dernière réponse, au-dessus du corps d'une leçon planifiée. L'élève retire sa demande ; le personnel
/// l'accepte par le déplacement ou l'annulation de la leçon, ou la refuse.
struct SchoolLessonChangeSection: View {
    @Bindable var model: SchoolLessonChangeModel
    let isLearner: Bool
    let accept: (SchoolLessonChangeRequest) -> Void
    let refuse: (SchoolLessonChangeRequest) -> Void

    var body: some View {
        if let request = model.pending {
            card(request)
        } else if isLearner, let closed = model.state?.lastClosed, closed.mine, closed.requestStatus == .refused {
            refused(closed)
        }
    }

    private func title(_ request: SchoolLessonChangeRequest) -> String {
        switch (request.requestKind, isLearner) {
        case (.reschedule, true): "Demande de déplacement envoyée"
        case (.cancel, true): "Demande d’annulation envoyée"
        case (.reschedule, false): "L’élève demande un déplacement"
        case (.cancel, false): "L’élève demande l’annulation"
        case (nil, _): "Demande"
        }
    }

    @ViewBuilder private func card(_ request: SchoolLessonChangeRequest) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
                Text(title(request)).font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                // Seulement l'inhabituel : la demande faite après le délai que l'école a fixé.
                if request.late == true { Text("Hors délai").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.warning) }
            }
            if isLearner { Text("En attente de ton moniteur").font(.subheadline).foregroundStyle(.secondary) }
            if !request.note.isEmpty {
                Text(request.note).font(.body).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lesson-change-note-text")
            }
            if let message = model.errorMessage { DrivyActionNote(text: message, isError: true) }
            if isLearner {
                if request.mine {
                    Button("Retirer la demande") { Task { _ = await model.withdraw() } }
                        .disabled(model.isSending)
                        .frame(minHeight: DrivyLayout.tapTarget)
                        .accessibilityIdentifier("lesson-change-withdraw")
                }
            } else {
                HStack(spacing: DrivySpacing.s) {
                    Button(request.requestKind == .cancel ? "Annuler la leçon" : "Déplacer") { accept(request) }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .disabled(model.isSending)
                        .accessibilityIdentifier("lesson-change-accept")
                    Button("Refuser") { refuse(request) }
                        .frame(minHeight: DrivyLayout.tapTarget)
                        .disabled(model.isSending)
                        .accessibilityIdentifier("lesson-change-refuse")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lesson-change-card")
    }

    @ViewBuilder private func refused(_ request: SchoolLessonChangeRequest) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text(request.requestKind == .cancel ? "Demande d’annulation refusée" : "Demande de déplacement refusée").font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let note = request.resolutionNote, !note.isEmpty { Text(note).font(.body).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lesson-change-refused")
    }
}

/// L'élève précise sa demande : ses disponibilités pour un déplacement, un motif facultatif pour une annulation.
struct SchoolLessonChangeRequestSheet: View {
    @Bindable var model: SchoolLessonChangeModel
    let kind: SchoolLessonChangeRequest.Kind
    let timeZone: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var note = ""
    @State private var confirmsDiscard = false

    private var trimmed: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var tooLong: Bool { note.unicodeScalars.count > 1_000 }
    private var valid: Bool { !tooLong && (kind == .cancel || !trimmed.isEmpty) }
    private var title: String { kind == .reschedule ? "Demander un déplacement" : "Demander l’annulation" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(kind == .reschedule ? "Tes disponibilités ou une proposition" : "Motif (facultatif)", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .disabled(model.isSending)
                        .accessibilityIdentifier("lesson-change-note")
                    if tooLong { DrivyActionNote(text: "Raccourcis le texte à 1 000 caractères.", isError: true) }
                }
                .drivyFormRows()
                if let conditions = model.state?.conditions { conditionsSection(conditions) }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: DrivyLayout.formColumn).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if let message = model.errorMessage { DrivyActionNote(text: message, isError: true) }
                    else if kind == .reschedule && trimmed.isEmpty && !model.isSending { DrivyActionNote(text: "Indique tes disponibilités.") }
                    Button {
                        Task { if await model.create(kind: kind, note: note) { dismiss() } }
                    } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            if model.isSending { ProgressView().accessibilityHidden(true) }
                            Text("Envoyer la demande")
                        }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!valid || model.isSending)
                    .accessibilityIdentifier("lesson-change-send")
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { if trimmed.isEmpty { dismiss() } else { confirmsDiscard = true } }
                        .disabled(model.isSending)
                }
            }
            .alert("Quitter sans envoyer ?", isPresented: $confirmsDiscard) {
                Button("Quitter sans envoyer", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) { }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(!trimmed.isEmpty || model.isSending)
        .tint(DrivyTheme.accent)
        .onAppear { model.errorMessage = nil }
    }

    /// Le délai fixé par l'école, tel que sa procédure l'indique, et la procédure complète à la demande. Rien n'est supposé
    /// quand l'école n'a pas fixé de délai, et aucun frais n'est annoncé : l'école ne calcule rien automatiquement.
    @ViewBuilder private func conditionsSection(_ conditions: SchoolLessonChangeConditions) -> some View {
        let hasDeadline = conditions.deadline != nil
        let hasText = !conditions.cancellationPolicyText.isEmpty
        if hasDeadline || hasText {
            Section {
                if let deadline = conditions.deadline {
                    HStack(alignment: .firstTextBaseline) {
                        Text("À demander avant le \(changeDeadlineText(deadline, zone: timeZone))")
                        Spacer(minLength: 0)
                        if conditions.late == true { Text("Délai dépassé").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.warning) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("lesson-change-deadline")
                }
                if hasText {
                    DisclosureGroup("Conditions de l’école") {
                        Text(conditions.cancellationPolicyText).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("lesson-change-conditions")
                }
            }
            .drivyFormRows()
        }
    }
}

/// Le personnel refuse une demande : le motif, facultatif, est lu par l'élève. La leçon reste telle quelle.
struct SchoolLessonChangeRefuseSheet: View {
    @Bindable var model: SchoolLessonChangeModel
    let request: SchoolLessonChangeRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var note = ""

    private var tooLong: Bool { note.unicodeScalars.count > 1_000 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Motif (facultatif)", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .disabled(model.isSending)
                        .accessibilityIdentifier("lesson-change-refuse-note")
                    if tooLong { DrivyActionNote(text: "Raccourcis le texte à 1 000 caractères.", isError: true) }
                }
                .drivyFormRows()
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: DrivyLayout.formColumn).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if let message = model.errorMessage { DrivyActionNote(text: message, isError: true) }
                    Button {
                        Task { if await model.refuse(request, note: note) { dismiss() } }
                    } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            if model.isSending { ProgressView().accessibilityHidden(true) }
                            Text("Refuser la demande")
                        }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(tooLong || model.isSending)
                    .accessibilityIdentifier("lesson-change-refuse-send")
                }
            }
            .navigationTitle("Refuser la demande").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(model.isSending) }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isSending)
        .tint(DrivyTheme.accent)
        .onAppear { model.errorMessage = nil }
    }
}
