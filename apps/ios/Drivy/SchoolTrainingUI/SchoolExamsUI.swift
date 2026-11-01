import SwiftUI

// Examens d'une formation (#54). Le personnel prévoit, reporte et renseigne ; l'élève lit les siens. Ces gestes passent directement
// par l'école, sans file locale : sans réseau, rien ne part et l'écran le dit. Une date passée n'est jamais un résultat.

/// État et gestes des examens d'une formation.
@MainActor @Observable final class SchoolExamModel {
    let schoolID: UUID
    let trainingID: UUID
    private let client: SchoolExamClient
    private(set) var state: SchoolExamState?
    private(set) var isLoading = false
    private(set) var isSending = false
    var errorMessage: String?
    /// Une opération par geste, gardée jusqu'à son aboutissement ou son refus définitif : un nouvel essai après une réponse perdue
    /// rejoue le même geste au lieu d'en créer un second.
    private var operation: (key: String, id: UUID)?

    init(client: SchoolExamClient, schoolID: UUID, trainingID: UUID) {
        self.client = client; self.schoolID = schoolID; self.trainingID = trainingID
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do { state = try await client.state(schoolID: schoolID, trainingID: trainingID); errorMessage = nil }
        catch is CancellationError { return }
        catch { errorMessage = Self.message(error) }
    }

    func create(kind: SchoolExam.Kind, schedule: SchoolExamSchedule) async -> Bool {
        let id = operationID(for: "create|\(kind.rawValue)|\(schedule.key)")
        return await send { try await client.create(schoolID: schoolID, trainingID: trainingID, operationID: id, kind: kind, schedule: schedule) }
    }

    func update(_ exam: SchoolExam, schedule: SchoolExamSchedule, reason: String) async -> Bool {
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = operationID(for: "update|\(exam.id)|\(exam.version)|\(schedule.key)|\(text)")
        return await send { try await client.update(schoolID: schoolID, exam: exam, operationID: id, schedule: schedule, reason: text) }
    }

    func postpone(_ exam: SchoolExam, schedule: SchoolExamSchedule, reason: String) async -> Bool {
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = operationID(for: "postpone|\(exam.id)|\(exam.version)|\(schedule.key)|\(text)")
        return await send { try await client.postpone(schoolID: schoolID, exam: exam, operationID: id, schedule: schedule, reason: text) }
    }

    func setResult(_ exam: SchoolExam, result: SchoolExam.Status, note: String, reason: String) async -> Bool {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines), why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = operationID(for: "result|\(exam.id)|\(exam.version)|\(result.rawValue)|\(text)|\(why)")
        return await send { try await client.setResult(schoolID: schoolID, exam: exam, operationID: id, result: result, note: text, reason: why) }
    }

    private func operationID(for key: String) -> UUID {
        if let operation, operation.key == key { return operation.id }
        let created = UUID(); operation = (key, created); return created
    }

    private func send(_ work: () async throws -> SchoolExamState) async -> Bool {
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
        guard let failure = error as? SchoolPlanningFailure else { return "L’opération n’a pas pu aboutir. Réessaie." }
        switch failure {
        case .unavailable: return "L’école est momentanément inaccessible. Réessaie : l’opération ne sera enregistrée qu’une fois."
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

    private var ownInstructorID: UUID? {
        training.membership.roles.contains("INSTRUCTOR") ? training.membership.membershipId : nil
    }

    var body: some View {
        Group {
            if let model {
                if let state = model.state {
                    if state.canManage || !state.exams.isEmpty { content(model, state) }
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
            model = SchoolExamModel(client: training.client.examClient, schoolID: training.scope.schoolID, trainingID: training.trainingID)
        }
        await model?.load()
    }

    @ViewBuilder private func content(_ model: SchoolExamModel, _ state: SchoolExamState) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Examens").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                let kinds = SchoolExam.Kind.allCases.filter { state.canSchedule($0) }
                if state.canManage && !kinds.isEmpty {
                    Menu("Prévoir") {
                        ForEach(kinds, id: \.self) { kind in
                            Button(examKindTitle(kind)) { sheet = .create(kind) }
                        }
                    }
                    .frame(minHeight: DrivyLayout.tapTarget)
                    .accessibilityIdentifier("exams-schedule")
                }
            }
            ForEach(state.exams) { exam in row(exam, canManage: state.canManage) }
            if let message = model.errorMessage { DrivyActionNote(text: message, isError: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("training-exams")
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

    @ViewBuilder private func sheetView(_ sheet: SchoolExamSheet) -> some View {
        if let model {
            switch sheet {
            case .create(let kind): SchoolExamScheduleSheet(model: model, mode: .create(kind), zone: schoolTimeZone, ownInstructorID: ownInstructorID)
            case .edit(let exam): SchoolExamScheduleSheet(model: model, mode: .edit(exam), zone: schoolTimeZone, ownInstructorID: ownInstructorID)
            case .postpone(let exam): SchoolExamScheduleSheet(model: model, mode: .postpone(exam), zone: schoolTimeZone, ownInstructorID: ownInstructorID)
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
    let ownInstructorID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var startsAt: Date
    @State private var location: String
    @State private var escorts: Bool
    @State private var escortStart: Date
    @State private var escortEnd: Date
    @State private var reason = ""
    /// Le moniteur qui accompagne : celui de l'examen modifié, sinon l'appelant s'il est moniteur.
    private let escortInstructorID: UUID?

    init(model: SchoolExamModel, mode: Mode, zone: String, ownInstructorID: UUID?) {
        _model = Bindable(wrappedValue: model); self.mode = mode; self.zone = zone; self.ownInstructorID = ownInstructorID
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
        escortInstructorID = escort?.instructorMembershipId ?? ownInstructorID
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
    private var escortValid: Bool { !escorts || (escortEnd > escortStart && escortEnd.timeIntervalSince(escortStart) <= 12 * 3_600) }
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
                if escortInstructorID != nil {
                    Section {
                        Toggle("Accompagnement du moniteur", isOn: $escorts)
                            .accessibilityIdentifier("exam-escort")
                        if escorts {
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
                    else if !escortValid { DrivyActionNote(text: "L’accompagnement doit finir après son début, en 12 heures au plus.", isError: true) }
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
        if escorts, let instructor = escortInstructorID {
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
