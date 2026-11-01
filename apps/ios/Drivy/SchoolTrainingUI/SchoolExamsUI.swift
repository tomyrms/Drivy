import SwiftUI

// Examens d'une formation (#54). Le personnel prévoit, reporte et renseigne ; l'élève lit les siens. Chaque geste est écrit dans la
// file chiffrée des commandes de l'école avant tout envoi, puis envoyé et rejoué à l'identique tant que l'école n'a pas répondu :
// rien n'est annoncé avant sa réponse, et rien n'est perdu si l'app s'arrête. Une date passée n'est jamais un résultat.

/// État et gestes des examens d'une formation.
@MainActor @Observable final class SchoolExamModel {
    let scope: SchoolCommandScope
    let trainingID: UUID
    private let client: SchoolExamClient
    private let outbox: any SchoolCommandOutbox
    private(set) var state: SchoolExamState?
    private(set) var isLoading = false
    private(set) var isSending = false
    /// Geste conservé sur l'appareil, pas encore confirmé par l'école.
    private(set) var pending: PendingSchoolCommand?
    var errorMessage: String?

    var schoolID: UUID { scope.schoolID }

    init(client: SchoolExamClient, scope: SchoolCommandScope, trainingID: UUID, outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.client = client; self.scope = scope; self.trainingID = trainingID; self.outbox = outbox
    }

    /// Relit les examens ; un geste resté sans réponse (arrêt de l'app, panne) est rejoué aussitôt.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        do {
            pending = try outbox.pendingCommands(for: scope).first { $0.kind.isExam && $0.scope == scope && $0.routeResourceID == trainingID }
        } catch {
            errorMessage = "Cet appareil ne peut pas relire les demandes conservées."
        }
        do { state = try await client.state(schoolID: schoolID, trainingID: trainingID); if pending == nil { errorMessage = nil } }
        catch is CancellationError { isLoading = false; return }
        catch { errorMessage = Self.message(error) }
        isLoading = false
        if pending != nil { _ = await transmit() }
    }

    func create(kind: SchoolExam.Kind, schedule: SchoolExamSchedule) async -> Bool {
        let id = UUID()
        return await enqueue(.createExam, id: id, body: .create(operationID: id, kind: kind, schedule: schedule), exam: nil)
    }

    func update(_ exam: SchoolExam, schedule: SchoolExamSchedule, reason: String) async -> Bool {
        let id = UUID()
        return await enqueue(.updateExam, id: id, body: .reschedule(operationID: id, schedule: schedule, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)), exam: exam)
    }

    func postpone(_ exam: SchoolExam, schedule: SchoolExamSchedule, reason: String) async -> Bool {
        let id = UUID()
        return await enqueue(.postponeExam, id: id, body: .reschedule(operationID: id, schedule: schedule, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)), exam: exam)
    }

    func setResult(_ exam: SchoolExam, result: SchoolExam.Status, note: String, reason: String) async -> Bool {
        let id = UUID()
        return await enqueue(.setExamResult, id: id, body: .result(operationID: id, result: result, note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)), exam: exam)
    }

    /// Écrit le geste dans la file, puis l'envoie. Vrai quand il est confirmé ou conservé en attente de réponse : la feuille se ferme et
    /// la section dit où il en est. Faux quand il est refusé ou n'a pas pu être conservé : la saisie reste à l'écran avec sa raison.
    private func enqueue(_ kind: SchoolCommandKind, id: UUID, body: SchoolExamBody, exam: SchoolExam?) async -> Bool {
        guard pending == nil, !isSending else {
            errorMessage = "Un geste précédent attend encore la réponse de l’école."
            return false
        }
        errorMessage = nil
        do {
            let command = PendingSchoolCommand(id: id, scope: scope, kind: kind, resourceVersion: exam?.version ?? 0, createdAt: Date(),
                body: try body.encoded(), resourceID: exam?.id, routeResourceID: trainingID)
            try outbox.save(command)
            pending = command
        } catch SchoolConfigurationFailure.pendingCommand {
            errorMessage = "Une autre demande de cette école attend sa réponse. Réessaie dans un instant."
            return false
        } catch {
            errorMessage = "Cet appareil ne peut pas conserver la demande : rien n’a été envoyé."
            return false
        }
        let confirmed = await transmit()
        return confirmed || pending != nil
    }

    /// Envoie ou rejoue le geste conservé : mêmes octets, même clé, même version. L'école répond une seule fois à une même opération.
    @discardableResult func transmit() async -> Bool {
        guard let command = pending, !isSending else { return false }
        isSending = true; errorMessage = nil; defer { isSending = false }
        do {
            let next = try await client.replay(command)
            try? outbox.remove(command)
            state = next; pending = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            // Un refus définitif ne se rejoue pas : le geste est retiré et l'état de l'école relu. Une panne ou une réponse perdue
            // garde le geste pour le prochain essai.
            if (error as? SchoolPlanningFailure)?.definitiveRejection == true {
                try? outbox.remove(command); pending = nil
                if let fresh = try? await client.state(schoolID: schoolID, trainingID: trainingID) { state = fresh }
            }
            errorMessage = Self.message(error)
            return false
        }
    }

    /// Renonce à un geste que l'école n'a pas confirmé, puis relit ses examens : rien n'est supposé enregistré.
    func abandon() async {
        guard let command = pending, !isSending else { return }
        do { try outbox.remove(command) } catch { errorMessage = "Cet appareil ne peut pas retirer la demande conservée."; return }
        pending = nil; errorMessage = nil
        await load()
    }

    static func message(_ error: Error) -> String {
        guard let failure = error as? SchoolPlanningFailure else { return "L’opération n’a pas pu aboutir. Réessaie." }
        switch failure {
        case .unavailable: return "L’école est momentanément inaccessible. Le geste est conservé : il sera envoyé une seule fois."
        case .conflict: return "Cet examen a changé. Il a été relu : reprends ta saisie."
        default: return failure.errorDescription ?? "L’opération n’a pas pu aboutir. Réessaie."
        }
    }
}

enum SchoolExamSheet: Identifiable {
    case create(SchoolExam.Kind)
    case edit(SchoolExam)
    case postpone(SchoolExam)
    case result(SchoolExam)

    var id: String {
        switch self {
        case .create(let kind): "create-\(kind.rawValue)"
        case .edit(let exam): "edit-\(exam.id.uuidString)"
        case .postpone(let exam): "postpone-\(exam.id.uuidString)"
        case .result(let exam): "result-\(exam.id.uuidString)"
        }
    }
}

private func examKindTitle(_ kind: SchoolExam.Kind?) -> String {
    switch kind {
    case .theory: "Examen théorique"
    case .practical: "Examen pratique"
    case nil: "Examen"
    }
}

/// Les examens d'une formation, sous sa progression : prévus, reportés, absents, réussis ou échoués, chacun avec sa tentative.
struct SchoolTrainingExamsSection: View {
    let training: SchoolTrainingWorkspace
    let schoolTimeZone: String
    @State private var model: SchoolExamModel?
    @State private var sheet: SchoolExamSheet?

    var body: some View {
        Group {
            if let model {
                if let state = model.state {
                    if state.canManage || !state.exams.isEmpty || model.pending != nil { content(model, state) }
                } else if let message = model.errorMessage {
                    SchoolErrorNotice(message: message, retry: { Task { await model.load() } }, retryIdentifier: "exams-retry")
                }
            }
        }
        .task(id: training.trainingID) { await prepare() }
        .sheet(item: $sheet) { sheet in sheetView(sheet) }
    }

    private func prepare() async {
        guard training.hasPedagogicalRole, !training.invalidated, !training.accessRevoked else { return }
        if model == nil || model?.trainingID != training.trainingID {
            model = SchoolExamModel(client: training.client.examClient, scope: training.scope, trainingID: training.trainingID)
        }
        await model?.load()
    }

    @ViewBuilder private func content(_ model: SchoolExamModel, _ state: SchoolExamState) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Examens").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                let kinds = SchoolExam.Kind.allCases.filter { state.canSchedule($0) }
                if state.canManage && !kinds.isEmpty && model.pending == nil {
                    Menu("Prévoir") {
                        ForEach(kinds, id: \.self) { kind in
                            Button(examKindTitle(kind)) { sheet = .create(kind) }
                        }
                    }
                    .frame(minHeight: DrivyLayout.tapTarget)
                    .accessibilityIdentifier("exams-schedule")
                }
            }
            if let pending = model.pending { pendingBanner(model, pending) }
            ForEach(state.exams) { exam in row(exam, canManage: state.canManage && model.pending == nil) }
            if let message = model.errorMessage, model.pending == nil { DrivyActionNote(text: message, isError: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("training-exams")
    }

    /// Le geste conservé sur l'appareil et pas encore confirmé : l'école n'a rien annoncé, l'écran ne le présente jamais comme fait.
    private func pendingBanner(_ model: SchoolExamModel, _ pending: PendingSchoolCommand) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text("« \(pending.kind.requestTitle) » attend la réponse de l’école").font(.subheadline.weight(.semibold))
            Text("Le geste est conservé sur cet appareil et ne sera envoyé qu’une fois.").font(.subheadline).foregroundStyle(DrivyTheme.muted)
            if let message = model.errorMessage { DrivyActionNote(text: message, isError: true) }
            HStack(spacing: DrivySpacing.s) {
                Button { Task { await model.transmit() } } label: { DrivyBusyLabel(title: "Réessayer", busyTitle: "Envoi…", isBusy: model.isSending) }
                    .disabled(model.isSending)
                    .frame(minHeight: DrivyLayout.tapTarget)
                    .accessibilityIdentifier("exams-pending-retry")
                Button("Abandonner", role: .destructive) { Task { await model.abandon() } }
                    .disabled(model.isSending)
                    .frame(minHeight: DrivyLayout.tapTarget)
                    .accessibilityIdentifier("exams-pending-abandon")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exams-pending")
    }

    private func row(_ exam: SchoolExam, canManage: Bool) -> some View {
        HStack(alignment: .top, spacing: DrivySpacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(exam)).font(.body.weight(.semibold))
                if let date = exam.date {
                    Text(SchoolDateFormat.template("EEEdMMMjmm", date, zone: exam.timeZone)).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                }
                if !exam.location.isEmpty { Text(exam.location).font(.subheadline).foregroundStyle(DrivyTheme.muted) }
                if !exam.resultNote.isEmpty {
                    Text("À travailler : \(exam.resultNote)").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: DrivySpacing.xs) {
                statusText(exam, canManage: canManage)
                if canManage { actions(exam) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exam-\(exam.id.uuidString)")
    }

    private func rowTitle(_ exam: SchoolExam) -> String {
        let base = examKindTitle(exam.examKind)
        guard let attempt = exam.attempt, attempt > 1 else { return base }
        return "\(base) · tentative \(attempt)"
    }

    /// Le résultat manquant d'une date passée est le seul état signalé : tout le reste se lit à son mot.
    @ViewBuilder private func statusText(_ exam: SchoolExam, canManage: Bool) -> some View {
        if exam.needsResult {
            Text(canManage ? "Résultat à renseigner" : "Résultat en attente").font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.warning)
        } else {
            switch exam.examStatus {
            case .scheduled: Text("Prévu").font(.subheadline).foregroundStyle(DrivyTheme.muted)
            case .postponed: Text("Reporté").font(.subheadline).foregroundStyle(DrivyTheme.muted)
            case .absent: Text("Absent").font(.subheadline).foregroundStyle(DrivyTheme.muted)
            case .passed: Text("Réussi").font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.success)
            case .failed: Text("Échoué").font(.subheadline.weight(.semibold))
            case nil: EmptyView()
            }
        }
    }

    @ViewBuilder private func actions(_ exam: SchoolExam) -> some View {
        let scheduled = exam.examStatus == .scheduled
        let started = (exam.date ?? .distantFuture) <= Date()
        if scheduled || exam.hasResult {
            Menu {
                if scheduled && started { Button("Renseigner le résultat") { sheet = .result(exam) } }
                if scheduled {
                    Button("Modifier la date") { sheet = .edit(exam) }
                    Button("Reporter") { sheet = .postpone(exam) }
                }
                if exam.hasResult { Button("Corriger le résultat") { sheet = .result(exam) } }
            } label: {
                Label("Actions", systemImage: "ellipsis")
            }
            .frame(minHeight: DrivyLayout.tapTarget)
            .accessibilityLabel("Actions pour \(rowTitle(exam))")
            .accessibilityIdentifier("exam-actions-\(exam.id.uuidString)")
        }
    }

    private func scheduleSheet(_ model: SchoolExamModel, _ mode: SchoolExamScheduleSheet.Mode) -> some View {
        SchoolExamScheduleSheet(model: model, mode: mode, zone: schoolTimeZone, candidates: model.state?.escortCandidates ?? [],
            ownMembershipID: training.membership.membershipId)
    }

    @ViewBuilder private func sheetView(_ sheet: SchoolExamSheet) -> some View {
        if let model {
            switch sheet {
            case .create(let kind): scheduleSheet(model, .create(kind))
            case .edit(let exam): scheduleSheet(model, .edit(exam))
            case .postpone(let exam): scheduleSheet(model, .postpone(exam))
            case .result(let exam): SchoolExamResultSheet(model: model, exam: exam)
            }
        }
    }
}

/// Date, lieu et accompagnement facultatif d'un examen : pour le prévoir, le modifier ou le reporter.
struct SchoolExamScheduleSheet: View {
    enum Mode {
        case create(SchoolExam.Kind)
        case edit(SchoolExam)
        case postpone(SchoolExam)
    }

    @Bindable var model: SchoolExamModel
    let mode: Mode
    let zone: String
    let candidates: [SchoolExamState.Candidate]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var startsAt: Date
    @State private var location: String
    @State private var escorts: Bool
    @State private var escortStart: Date
    @State private var escortEnd: Date
    @State private var reason = ""
    /// Le moniteur qui accompagne : celui de l'examen modifié, sinon l'appelant s'il est proposable, sinon le premier proposé.
    @State private var escortInstructor: UUID?

    init(model: SchoolExamModel, mode: Mode, zone: String, candidates: [SchoolExamState.Candidate], ownMembershipID: UUID?) {
        _model = Bindable(wrappedValue: model); self.mode = mode; self.zone = zone; self.candidates = candidates
        var date = Date().addingTimeInterval(7 * 86_400), place = "", escort: SchoolExam.Escort?
        switch mode {
        case .create: break
        case .edit(let exam), .postpone(let exam):
            date = exam.date ?? date; place = exam.location; escort = exam.escort
        }
        _startsAt = State(initialValue: date); _location = State(initialValue: place)
        _escorts = State(initialValue: escort != nil)
        _escortStart = State(initialValue: escort.flatMap { SchoolLesson.date($0.startsAt) } ?? date.addingTimeInterval(-3_600))
        _escortEnd = State(initialValue: escort.flatMap { SchoolLesson.date($0.endsAt) } ?? date.addingTimeInterval(3_600))
        _escortInstructor = State(initialValue: escort?.instructorMembershipId
            ?? candidates.first { $0.membershipId == ownMembershipID }?.membershipId ?? candidates.first?.membershipId)
    }

    private var title: String {
        switch mode {
        case .create(let kind): "Prévoir : \(examKindTitle(kind).lowercased())"
        case .edit: "Modifier la date"
        case .postpone: "Reporter l’examen"
        }
    }
    private var asksReason: Bool {
        switch mode {
        case .create: false
        case .edit, .postpone: true
        }
    }
    private var escortValid: Bool {
        !escorts || (escortInstructor != nil && escortEnd > escortStart && escortEnd.timeIntervalSince(escortStart) <= 12 * 3_600)
    }
    private var tooLong: Bool { location.unicodeScalars.count > 200 || reason.unicodeScalars.count > 1_000 }
    private var timeZone: TimeZone { TimeZone(identifier: zone) ?? .current }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date et heure", selection: $startsAt, displayedComponents: [.date, .hourAndMinute])
                        .accessibilityIdentifier("exam-date")
                    TextField("Lieu (facultatif)", text: $location)
                        .accessibilityIdentifier("exam-location")
                }
                .drivyFormRows()
                if !candidates.isEmpty {
                    Section {
                        Toggle("Accompagnement du moniteur", isOn: $escorts)
                            .accessibilityIdentifier("exam-escort")
                        if escorts {
                            Picker("Moniteur", selection: $escortInstructor) {
                                ForEach(candidates) { candidate in Text(candidate.displayName).tag(Optional(candidate.membershipId)) }
                            }
                            .accessibilityIdentifier("exam-escort-instructor")
                            DatePicker("De", selection: $escortStart, displayedComponents: [.date, .hourAndMinute])
                            DatePicker("À", selection: $escortEnd, displayedComponents: [.date, .hourAndMinute])
                        }
                    }
                    .drivyFormRows()
                }
                if asksReason {
                    Section {
                        TextField("Motif (facultatif)", text: $reason, axis: .vertical).lineLimit(2...5)
                            .accessibilityIdentifier("exam-reason")
                    }
                    .drivyFormRows()
                }
            }
            .environment(\.timeZone, timeZone)
            .environment(\.locale, Locale(identifier: "fr_CH"))
            .scrollContentBackground(.hidden)
            .frame(maxWidth: DrivyLayout.formColumn).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if let message = model.errorMessage { DrivyActionNote(text: message, isError: true) }
                    else if !escortValid { DrivyActionNote(text: "Choisis le moniteur et une durée d’accompagnement de 12 heures au plus, qui finit après son début.", isError: true) }
                    else if tooLong { DrivyActionNote(text: "Raccourcis le texte saisi.", isError: true) }
                    Button { Task { if await submit() { dismiss() } } } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            if model.isSending { ProgressView().accessibilityHidden(true) }
                            Text(asksReason ? "Enregistrer" : "Prévoir l’examen")
                        }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!escortValid || tooLong || model.isSending)
                    .accessibilityIdentifier("exam-schedule-send")
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
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

    private func submit() async -> Bool {
        var escort: SchoolExamSchedule.Escort?
        if escorts, let instructor = escortInstructor {
            escort = SchoolExamSchedule.Escort(instructorMembershipID: instructor, startsAt: escortStart, endsAt: escortEnd)
        }
        let schedule = SchoolExamSchedule(startsAt: startsAt, timeZone: zone, location: location.trimmingCharacters(in: .whitespacesAndNewlines), escort: escort)
        switch mode {
        case .create(let kind): return await model.create(kind: kind, schedule: schedule)
        case .edit(let exam): return await model.update(exam, schedule: schedule, reason: reason)
        case .postpone(let exam): return await model.postpone(exam, schedule: schedule, reason: reason)
        }
    }
}

/// Résultat d'un examen dont la date est passée : réussi, échoué ou absent. Une correction demande son motif.
struct SchoolExamResultSheet: View {
    @Bindable var model: SchoolExamModel
    let exam: SchoolExam
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var result: SchoolExam.Status
    @State private var note: String
    @State private var reason = ""

    init(model: SchoolExamModel, exam: SchoolExam) {
        _model = Bindable(wrappedValue: model); self.exam = exam
        _result = State(initialValue: exam.hasResult ? (exam.examStatus ?? .failed) : .passed)
        _note = State(initialValue: exam.resultNote)
    }

    private var correction: Bool { exam.hasResult }
    private var tooLong: Bool { note.unicodeScalars.count > 1_000 || reason.unicodeScalars.count > 1_000 }
    private var missingReason: Bool { correction && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Résultat", selection: $result) {
                        Text("Réussi").tag(SchoolExam.Status.passed)
                        Text("Échoué").tag(SchoolExam.Status.failed)
                        Text("Absent").tag(SchoolExam.Status.absent)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("exam-result")
                }
                .drivyFormRows()
                Section {
                    TextField("Points à travailler (facultatif)", text: $note, axis: .vertical).lineLimit(2...6)
                        .accessibilityIdentifier("exam-result-note")
                }
                .drivyFormRows()
                if correction {
                    Section {
                        TextField("Motif de la correction", text: $reason, axis: .vertical).lineLimit(2...5)
                            .accessibilityIdentifier("exam-result-reason")
                    }
                    .drivyFormRows()
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: DrivyLayout.formColumn).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if let message = model.errorMessage { DrivyActionNote(text: message, isError: true) }
                    else if missingReason && !model.isSending { DrivyActionNote(text: "Indique le motif de la correction.") }
                    else if tooLong { DrivyActionNote(text: "Raccourcis le texte saisi.", isError: true) }
                    Button {
                        Task { if await model.setResult(exam, result: result, note: note, reason: reason) { dismiss() } }
                    } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            if model.isSending { ProgressView().accessibilityHidden(true) }
                            Text(correction ? "Corriger le résultat" : "Enregistrer le résultat")
                        }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(missingReason || tooLong || model.isSending)
                    .accessibilityIdentifier("exam-result-send")
                }
            }
            .navigationTitle(correction ? "Corriger le résultat" : "Résultat de l’examen").navigationBarTitleDisplayMode(.inline)
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
