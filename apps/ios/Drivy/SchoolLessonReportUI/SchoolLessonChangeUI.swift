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
            SchoolBoxesSignal.shared.settled()
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

/// Ce que la ligne choisie désigne : l'élève, puis la leçon d'une demande ou la formation et l'examen d'un examen à renseigner.
/// Le dossier la consomme une fois, puis la retire : le retour garde le contexte de la liste.
struct SchoolBoxTarget: Equatable {
    let learnerID: UUID
    var lessonID: UUID? = nil
    var trainingID: UUID? = nil
    var examID: UUID? = nil
}

/// Signal local : un traitement confirmé (demande de leçon, résultat d'examen) demande une relecture des boîtes de l'onglet Élèves.
/// Un compteur, pas de minuterie : la relecture suit l'événement.
@MainActor @Observable final class SchoolBoxesSignal {
    static let shared = SchoolBoxesSignal()
    private(set) var revision = 0
    func settled() { revision += 1 }
}

/// Lecture d'une boîte du personnel : dernière lecture conservée en cas de panne, réponse tardive d'un autre contexte ignorée,
/// accès perdu purgé. `context` nomme compte, école, époque et droits ; il change dès que l'un d'eux change.
@MainActor @Observable final class SchoolBoxReading<Item> {
    private(set) var items: [Item] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private var generation = 0
    private var context: String?

    func load(context: String, failure: String, fetch: (() async throws -> [Item])?) async {
        generation += 1
        let mine = generation
        if self.context != context { items = []; errorMessage = nil; self.context = context }
        guard let fetch else { items = []; errorMessage = nil; isLoading = false; return }
        isLoading = true
        defer { if mine == generation { isLoading = false } }
        do {
            let loaded = try await fetch()
            guard mine == generation, self.context == context else { return }
            items = loaded; errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard mine == generation, self.context == context else { return }
            switch error as? SchoolPlanningFailure {
            case .forbidden?, .notFound?, .unauthorized?:
                items = []                                       // l'accès n'existe plus : rien d'interdit ne reste à l'écran
            default: break                                       // une panne garde la dernière lecture, signalée comme telle
            }
            errorMessage = failure
        }
    }
}

typealias SchoolLessonRequestInboxModel = SchoolBoxReading<SchoolLessonChangeInboxItem>

extension SchoolBoxReading where Item == SchoolLessonChangeInboxItem {
    func load(client: SchoolLessonChangeClient?, schoolID: UUID?, context: String) async {
        let fetch: (() async throws -> [SchoolLessonChangeInboxItem])?
        if let client, let schoolID { fetch = { try await client.inbox(schoolID: schoolID) } } else { fetch = nil }
        await load(context: context, failure: "Les demandes n’ont pas pu être relues.", fetch: fetch)
    }
}

/// Plus de huit lignes : les huit premières, puis un contrôle qui déplie la liste complète.
enum SchoolBoxExpansion {
    static let collapsedCount = 8
    static func visible<T>(_ items: [T], expanded: Bool) -> ArraySlice<T> {
        expanded ? items[...] : items.prefix(collapsedCount)
    }
    static func hiddenCount(_ total: Int, expanded: Bool) -> Int { expanded ? 0 : max(0, total - collapsedCount) }
    static func canExpand(_ total: Int) -> Bool { total > collapsedCount }
}

/// « Demandes des élèves », en tête de la liste d'élèves : chaque ligne ouvre le dossier de l'élève, où la leçon porte la demande.
struct SchoolPendingRequestRows: View {
    let items: [SchoolLessonChangeInboxItem]
    let open: (SchoolBoxTarget) -> Void
    @State private var expanded = false

    @MainActor private func summary(_ item: SchoolLessonChangeInboxItem) -> String {
        let what = item.request.requestKind == .cancel ? "Annulation demandée" : "Déplacement demandé"
        guard let start = SchoolLesson.date(item.lesson.plannedStart) else { return what }
        let when = SchoolDateFormat.template("EEEdMMMjmm", start, zone: item.lesson.timeZone)
        return "\(what) · leçon du \(when)\(item.request.late == true ? " · hors délai" : "")"
    }

    var body: some View {
        if !items.isEmpty {
            Text("Demandes des élèves")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.muted)
                .accessibilityAddTraits(.isHeader)
                .listRowSeparator(.hidden)
                .drivyPlainRows()
            ForEach(SchoolBoxExpansion.visible(items, expanded: expanded)) { item in
                Button { open(SchoolBoxTarget(learnerID: item.lesson.learnerId, lessonID: item.lesson.id)) } label: {
                    DrivyEntityRow(title: item.lesson.learnerDisplayName.isEmpty ? "Élève" : item.lesson.learnerDisplayName,
                        meta: summary(item), leading: .symbol("arrow.left.arrow.right"), showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.lesson.learnerDisplayName), \(summary(item))")
                .accessibilityIdentifier("pending-request-\(item.request.id.uuidString)")
                .listRowSeparator(.hidden)
                .drivyPlainRows()
            }
            if SchoolBoxExpansion.canExpand(items.count) {
                SchoolBoxExpansionButton(expanded: $expanded, hidden: SchoolBoxExpansion.hiddenCount(items.count, expanded: expanded),
                    noun: "demandes", identifier: "pending-requests-expansion")
            }
        }
    }
}

/// Déplier ou replier une boîte de plus de huit lignes : un bouton réel, annoncé avec son état.
struct SchoolBoxExpansionButton: View {
    @Binding var expanded: Bool
    let hidden: Int
    let noun: String
    let identifier: String

    var body: some View {
        Button { expanded.toggle() } label: {
            Text(expanded ? "Réduire" : "Afficher les \(hidden) autres")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: DrivyLayout.tapTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.drivyText)
        .accessibilityLabel(expanded ? "Réduire la liste des \(noun)" : "Afficher les \(hidden) autres \(noun)")
        .accessibilityValue(expanded ? "Liste complète" : "Liste réduite")
        .accessibilityIdentifier(identifier)
        .listRowSeparator(.hidden)
        .drivyPlainRows()
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
