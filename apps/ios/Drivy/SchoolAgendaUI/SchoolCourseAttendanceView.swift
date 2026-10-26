import SwiftUI
import UIKit

/// Appel d’une séance commencée : un élève par ligne, trois gros boutons, l’état affiché vient du serveur.
struct SchoolCourseAttendanceView: View {
    @Bindable var model: SchoolCourseAttendanceWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var paying: SchoolCourseSheetRow?
    @State private var validating: SchoolCourseSheetRow?
    @State private var reversal: SchoolCourseReversal?
    @State private var mode: SchoolCourseParticipantMode = .attendance
    @State private var onlyUnmarked = false

    var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Section { DrivyFormMessage(text: message, tone: .danger) }.drivyFormRows()
                }
                if let confirmation = model.confirmation {
                    Section { DrivyFormMessage(text: confirmation, tone: .success) }.drivyFormRows()
                }
                if model.sheet != nil {
                    content
                } else if model.isLoading || model.errorMessage == nil {
                    Section { DrivyLoadingState(title: "Chargement…") }.drivyFormRows()
                } else {
                    Section { Button("Réessayer") { Task { await model.load() } } }.drivyFormRows()
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: SchoolFormLayout.maxWidth).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .navigationTitle("Participants").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .task { await model.load() }
            .refreshable { await model.load() }
            .onChange(of: model.rights, initial: true) { _, rights in
                let modes = SchoolCourseParticipantMode.available(rights)
                if !modes.contains(mode), let first = modes.first { mode = first }
            }
            .onChange(of: model.errorMessage) { _, message in
                if let message { UIAccessibility.post(notification: .announcement, argument: message) }
            }
            .onChange(of: model.confirmation) { _, message in
                if let message { UIAccessibility.post(notification: .announcement, argument: message) }
            }
            .sheet(item: $paying) { row in SchoolCoursePaymentSheet(model: model, row: row) }
            .confirmationDialog(validating.map { "Valider le cours pour \(name($0)) ?" } ?? "",
                                isPresented: Binding(get: { validating != nil }, set: { if !$0 { validating = nil } }),
                                titleVisibility: .visible) {
                if let row = validating {
                    Button("Valider") { Task { await model.perform(.validate(enrollmentID: row.enrollmentId), learnerName: name(row)) } }
                }
                Button("Annuler", role: .cancel) { validating = nil }
            }
            .sheet(item: $reversal) { target in
                SchoolCourseReversalSheet(model: model, target: target)
            }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }

    @ViewBuilder private var content: some View {
        let modes = SchoolCourseParticipantMode.available(model.rights)
        if modes.count > 1 {
            Section {
                Picker("Suivi", selection: $mode) {
                    ForEach(modes) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("course-participant-mode")
            }.drivyFormRows()
        }
        if mode == .attendance && modes.contains(.attendance) { attendanceContent }
        else if mode == .payments && modes.contains(.payments) {
            Section {
                if model.rows.isEmpty { Text("Aucun inscrit").foregroundStyle(DrivyTheme.muted) }
                ForEach(model.rows) { row in paymentRow(row) }
            } header: { Text("Règlements sur place").drivyFormSectionHeader() }
            .drivyFormRows()
        } else if mode == .validation && modes.contains(.validation) {
            Section {
                if model.rows.isEmpty { Text("Aucun inscrit").foregroundStyle(DrivyTheme.muted) }
                ForEach(model.rows) { row in validationRow(row) }
            } header: { Text("Validation du cours").drivyFormSectionHeader() }
            .drivyFormRows()
        }
    }

    @ViewBuilder private var attendanceContent: some View {
        let started = model.startedOccurrences()
        if started.isEmpty {
            Section { Text("Aucune séance commencée").foregroundStyle(DrivyTheme.muted) }.drivyFormRows()
        } else {
            if started.count > 1 {
                Section {
                    Picker("Séance", selection: $model.occurrenceID) {
                        ForEach(started) { occurrence in
                            Text(SchoolPlanningFormat.interval(occurrence.startsAt, occurrence.endsAt, zone: model.timeZone))
                                .tag(Optional(occurrence.id))
                        }
                    }
                    .disabled(model.isBusy)
                }
                .drivyFormRows()
            }
            if let occurrence = model.occurrence {
                let unmarked = model.rows.filter { $0.mark(occurrence.id)?.status == nil }
                Section {
                    LabeledContent("Appel renseigné", value: "\(model.rows.count - unmarked.count) sur \(model.rows.count)")
                    Toggle("À renseigner", isOn: $onlyUnmarked).drivyControlTint()
                }.drivyFormRows()
                Section {
                    if model.rows.isEmpty { Text("Aucun inscrit").foregroundStyle(DrivyTheme.muted) }
                    else if onlyUnmarked && unmarked.isEmpty { Text("Appel complet").foregroundStyle(DrivyTheme.muted) }
                    ForEach(onlyUnmarked ? unmarked : model.rows) { row in learnerRow(row, occurrence: occurrence) }
                } header: {
                    Text(SchoolPlanningFormat.interval(occurrence.startsAt, occurrence.endsAt, zone: model.timeZone)).drivyFormSectionHeader()
                }
                .drivyFormRows()
            }
        }
    }

    private func name(_ row: SchoolCourseSheetRow) -> String { row.learnerDisplayName.isEmpty ? "Élève" : row.learnerDisplayName }

    @ViewBuilder private func learnerRow(_ row: SchoolCourseSheetRow, occurrence: SchoolCourseOccurrence) -> some View {
        let mark = row.mark(occurrence.id)
        let rights = model.rights
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            learnerHeader(row)
            if mark?.status == nil { Text("Non renseigné").font(.subheadline).foregroundStyle(DrivyTheme.muted) }
            if rights?.canTakeAttendance == true {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DrivySpacing.xs) { statusButtons(row, mark: mark, occurrence: occurrence) }
                    VStack(spacing: DrivySpacing.xs) { statusButtons(row, mark: mark, occurrence: occurrence) }
                }
            } else if let status = mark?.status {
                Text(SchoolCourseSheetFormat.title(status)).font(.subheadline)
            }
        }
        .padding(.vertical, DrivySpacing.xxs)
    }

    private func learnerHeader(_ row: SchoolCourseSheetRow) -> some View {
        HStack(spacing: DrivySpacing.xs) {
            Text(name(row)).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if model.busyEnrollment == row.enrollmentId { ProgressView().accessibilityLabel("Envoi en cours") }
        }
    }

    @ViewBuilder private func paymentRow(_ row: SchoolCourseSheetRow) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            learnerHeader(row)
            if model.rights?.canRecordPayment == true {
                let paid = row.payments.filter { $0.voidedAt == nil }.reduce(Int64(0)) { $0 + $1.amountCents }
                if paid > 0 {
                    Text("Payé : \(SchoolCatalogFormatting.price(paid))").font(.subheadline).monospacedDigit()
                }
                ForEach(row.payments.filter { $0.voidedAt == nil }) { payment in
                    Button {
                        reversal = SchoolCourseReversal(kind: .payment(payment.id, payment.amountCents), enrollmentID: row.enrollmentId, learnerName: name(row))
                    } label: { Label("Annuler le règlement de \(SchoolCatalogFormatting.price(payment.amountCents))", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(DrivySecondaryButtonStyle())
                        .disabled(model.isBusy)
                        .accessibilityLabel("Annuler le règlement de \(SchoolCatalogFormatting.price(payment.amountCents)), \(name(row))")
                        .accessibilityIdentifier("course-payment-void")
                }
                Button { paying = row } label: { Label("Payé sur place", systemImage: "banknote") }
                    .buttonStyle(DrivySecondaryButtonStyle())
                    .disabled(model.isBusy)
                    .accessibilityLabel("Payé sur place, \(name(row))")
                    .accessibilityIdentifier("course-payment")
            }
        }
        .padding(.vertical, DrivySpacing.xxs)
    }

    @ViewBuilder private func validationRow(_ row: SchoolCourseSheetRow) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            learnerHeader(row)
            if row.requirements.required > 0 {
                Text(SchoolCourseSheetFormat.progress(row.requirements))
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted).monospacedDigit()
            }
            if let completion = row.completion, completion.revokedAt == nil {
                Label("Cours validé", systemImage: "checkmark.seal.fill").font(.subheadline.weight(.semibold))
                if model.rights?.canValidate == true {
                    Button {
                        reversal = SchoolCourseReversal(kind: .completion(completion.id), enrollmentID: row.enrollmentId, learnerName: name(row))
                    } label: { Label("Retirer la validation", systemImage: "xmark.seal") }
                        .buttonStyle(DrivySecondaryButtonStyle())
                        .disabled(model.isBusy)
                        .accessibilityLabel("Retirer la validation, \(name(row))")
                        .accessibilityIdentifier("course-completion-revoke")
                }
            } else if model.rights?.canValidate == true && row.requirements.required > 0 {
                Button { validating = row } label: { Label("Valider le cours", systemImage: "checkmark.seal") }
                    .buttonStyle(DrivySecondaryButtonStyle())
                    .disabled(model.isBusy || !model.canValidate(row))
                    .accessibilityLabel("Valider le cours, \(name(row))")
                    .accessibilityIdentifier("course-validate")
            }
        }
        .padding(.vertical, DrivySpacing.xxs)
    }

    @ViewBuilder private func statusButtons(_ row: SchoolCourseSheetRow, mark: SchoolCourseAttendanceMark?, occurrence: SchoolCourseOccurrence) -> some View {
        ForEach(SchoolCourseAttendanceStatus.allCases, id: \.self) { status in
            let selected = mark?.status == status
            Button {
                // Retoucher l’état déjà enregistré n’envoie rien.
                guard !selected else { return }
                Task {
                    await model.perform(.attendance(enrollmentID: row.enrollmentId, occurrenceID: occurrence.id, status: status,
                        expectedVersion: mark?.version), learnerName: name(row))
                }
            } label: {
                Label(SchoolCourseSheetFormat.title(status), systemImage: selected ? "checkmark.circle.fill" : icon(status))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(selected ? DrivyTheme.accent : nil)
            .fontWeight(selected ? .semibold : .regular)
            .disabled(model.isBusy)
            .accessibilityLabel("\(SchoolCourseSheetFormat.title(status)), \(name(row))")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("course-attendance-\(status.rawValue.lowercased())")
        }
    }

    private func icon(_ status: SchoolCourseAttendanceStatus) -> String {
        switch status {
        case .present: "circle"
        case .absent: "xmark.circle"
        case .excused: "envelope"
        }
    }
}

/// Règlement à annuler ou validation à retirer, avec motif.
struct SchoolCourseReversal: Identifiable {
    enum Kind { case payment(UUID, Int64), completion(UUID) }
    let id = UUID()
    let kind: Kind
    let enrollmentID: UUID
    let learnerName: String

    var title: String {
        switch kind {
        case .payment: "Annuler le règlement"
        case .completion: "Retirer la validation"
        }
    }
    var question: String {
        switch kind {
        case .payment(_, let cents): "Annuler le règlement de \(SchoolCatalogFormatting.price(cents)) pour \(learnerName) ?"
        case .completion: "Retirer la validation pour \(learnerName) ?"
        }
    }
    func action(reason: String) -> SchoolCourseSheetAction {
        switch kind {
        case .payment(let id, _): .voidPayment(enrollmentID: enrollmentID, paymentID: id, reason: reason)
        case .completion(let id): .revokeCompletion(enrollmentID: enrollmentID, completionID: id, reason: reason)
        }
    }
}

/// Motif obligatoire puis confirmation ; une nouvelle tentative avec le même motif rejoue la même opération.
struct SchoolCourseReversalSheet: View {
    let model: SchoolCourseAttendanceWorkspace
    let target: SchoolCourseReversal
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var confirming = false
    @State private var confirmsDiscard = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { DrivyFormMessage(text: error, tone: .danger) }.drivyFormRows()
                }
                Section {
                    TextField("Motif", text: $reason, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focused)
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("course-reversal-reason")
                } header: { Text(target.learnerName).drivyFormSectionHeader() }
                .drivyFormRows()
                Section {
                    Button(role: .destructive) { confirming = true } label: {
                        HStack {
                            Text(target.title)
                            Spacer(minLength: 0)
                            if model.isBusy { ProgressView().accessibilityLabel("Envoi en cours") }
                        }
                    }
                    .disabled(model.isBusy || SchoolCourseSheetFormat.reason(reason) == nil)
                    .accessibilityIdentifier("course-reversal-submit")
                }
                .drivyFormRows()
            }
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .navigationTitle(target.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") { if reason.isEmpty { dismiss() } else { confirmsDiscard = true } }.disabled(model.isBusy)
            } }
            // L’annonce VoiceOver de l’erreur et de la confirmation vient de l’écran d’appel (model.errorMessage / confirmation).
            .onAppear { focused = true }
            .confirmationDialog(target.question, isPresented: $confirming, titleVisibility: .visible) {
                Button(target.title, role: .destructive) { Task { await submit() } }
                Button("Ne rien changer", role: .cancel) {}
            }
            .alert("Quitter sans conserver le motif ?", isPresented: $confirmsDiscard) {
                Button("Quitter", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(model.isBusy || !reason.isEmpty)
        .tint(DrivyTheme.accent)
    }

    private func submit() async {
        guard !model.isBusy, let clean = SchoolCourseSheetFormat.reason(reason) else { return }
        error = nil
        if await model.perform(target.action(reason: clean), learnerName: target.learnerName) {
            dismiss()
        } else {
            error = model.errorMessage ?? "Échec de l’envoi. Réessayez."
        }
    }
}
