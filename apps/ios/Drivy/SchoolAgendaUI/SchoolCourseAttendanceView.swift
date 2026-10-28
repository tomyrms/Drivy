import SwiftUI
import UIKit

/// Appel d’une séance commencée : un élève par ligne, trois gros boutons. Le choix s’affiche aussitôt, chaque
/// ligne suit son propre envoi (#128-#130) ; « Appel renseigné » ne compte que ce que l’école a enregistré.
struct SchoolCourseAttendanceView: View {
    @Bindable var model: SchoolCourseAttendanceWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var paying: SchoolCourseSheetRow?
    @State private var validating: SchoolCourseSheetRow?
    @State private var reversal: SchoolCourseReversal?
    @State private var mode: SchoolCourseParticipantMode = .attendance
    @State private var onlyUnmarked = false
    @State private var confirmsClose = false

    var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Section { DrivyFormMessage(text: message, tone: .danger) }.drivyFormRows()
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
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") { if model.hasUnconfirmed { confirmsClose = true } else { dismiss() } }
                    .disabled(model.isSending)
            } }
            .task { await model.load() }
            .refreshable { await model.load() }
            .onChange(of: model.rights, initial: true) { _, rights in
                let modes = SchoolCourseParticipantMode.available(rights)
                if !modes.contains(mode), let first = modes.first { mode = first }
            }
            .onChange(of: model.errorMessage) { _, message in
                if let message { UIAccessibility.post(notification: .announcement, argument: message) }
            }
            .onChange(of: model.announcement) { _, announcement in
                if let announcement { UIAccessibility.post(notification: .announcement, argument: announcement.text) }
            }
            .confirmationDialog("Des changements ne sont pas confirmés", isPresented: $confirmsClose, titleVisibility: .visible) {
                Button("Fermer sans les reprendre", role: .destructive) { dismiss() }
                Button("Rester", role: .cancel) {}
            }
            .sheet(item: $paying) { row in SchoolCoursePaymentSheet(model: model, row: row) }
            .confirmationDialog(validating.map { "Valider le cours pour \(name($0)) ?" } ?? "",
                                isPresented: Binding(get: { validating != nil }, set: { if !$0 { validating = nil } }),
                                titleVisibility: .visible) {
                if let row = validating {
                    Button("Valider") { model.submit(.validate(enrollmentID: row.enrollmentId), learnerName: name(row)) }
                }
                Button("Annuler", role: .cancel) { validating = nil }
            }
            .sheet(item: $reversal) { target in
                SchoolCourseReversalSheet(model: model, target: target)
            }
        }
        .interactiveDismissDisabled(model.isSending || model.hasUnconfirmed)
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
        let shown = model.displayedStatus(row, occurrenceID: occurrence.id)
        let rights = model.rights
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            learnerHeader(row)
            if shown == nil { Text("Non renseigné").font(.subheadline).foregroundStyle(DrivyTheme.muted) }
            if rights?.canTakeAttendance == true {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DrivySpacing.xs) { statusButtons(row, shown: shown, occurrence: occurrence) }
                    VStack(spacing: DrivySpacing.xs) { statusButtons(row, shown: shown, occurrence: occurrence) }
                }
            } else if let status = shown {
                Text(SchoolCourseSheetFormat.title(status)).font(.subheadline)
            }
            rowFeedback(row)
        }
        .padding(.vertical, DrivySpacing.xxs)
    }

    private func learnerHeader(_ row: SchoolCourseSheetRow) -> some View {
        HStack(spacing: DrivySpacing.xs) {
            Text(name(row)).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if model.isSending(row) { ProgressView().accessibilityLabel("Envoi en cours") }
        }
    }

    /// Retour propre à la ligne : reprise d’un envoi non confirmé, ou refus de l’école à lire puis masquer.
    @ViewBuilder private func rowFeedback(_ row: SchoolCourseSheetRow) -> some View {
        if let pending = model.unconfirmed(row) {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Label(pending.message, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                HStack(spacing: DrivySpacing.xs) {
                    Button("Réessayer") { model.retry(row.enrollmentId) }
                        .buttonStyle(DrivySecondaryButtonStyle())
                        .accessibilityLabel("Réessayer, \(name(row))")
                        .accessibilityHint("Renvoie la même demande, sans doublon")
                        .accessibilityIdentifier("course-sheet-retry")
                    Button("Abandonner", role: .destructive) { model.abandon(row.enrollmentId) }
                        .buttonStyle(DrivySecondaryButtonStyle())
                        .accessibilityLabel("Abandonner, \(name(row))")
                        .accessibilityHint("Elle a peut-être été enregistrée : la liste est relue")
                        .accessibilityIdentifier("course-sheet-abandon")
                }
            }
        } else if let notice = model.notices[row.enrollmentId] {
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
                DrivyFormMessage(text: notice, tone: .danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("course-sheet-notice")
                Button("Masquer", systemImage: "xmark") { model.clearNotice(row.enrollmentId) }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(DrivyTheme.muted)
                    .frame(minWidth: DrivyLayout.tapTarget, minHeight: DrivyLayout.tapTarget)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .accessibilityLabel("Masquer le refus, \(name(row))")
            }
        }
    }

    @ViewBuilder private func paymentRow(_ row: SchoolCourseSheetRow) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            learnerHeader(row)
            if model.rights?.canRecordPayment == true {
                // Montant payé : règlements enregistrés seulement ; une saisie en cours est listée à part.
                let paid = row.payments.filter { $0.voidedAt == nil }.reduce(Int64(0)) { $0 + $1.amountCents }
                if paid > 0 {
                    Text("Payé : \(SchoolCatalogFormatting.price(paid))").font(.subheadline).monospacedDigit()
                }
                ForEach(model.pendingPayments(row)) { intent in
                    if case .payment(_, let cents) = intent.action {
                        let state = intent.state == .sending || intent.state == .queued ? "envoi en cours" : "non confirmé"
                        Label("\(SchoolCatalogFormatting.price(cents)) · \(state)", systemImage: "clock")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted).monospacedDigit()
                            // Un seul élément : l’icône ne porte ni l’identifiant ni l’annonce.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Règlement de \(SchoolCatalogFormatting.price(cents)), \(state)")
                            .accessibilityIdentifier("course-payment-pending")
                    }
                }
                ForEach(row.payments.filter { $0.voidedAt == nil }) { payment in
                    if model.isVoiding(payment.id, in: row) {
                        Label("Annulation du règlement de \(SchoolCatalogFormatting.price(payment.amountCents)) en cours", systemImage: "clock")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    } else {
                        Button {
                            reversal = SchoolCourseReversal(kind: .payment(payment.id, payment.amountCents), enrollmentID: row.enrollmentId, learnerName: name(row))
                        } label: { Label("Annuler le règlement de \(SchoolCatalogFormatting.price(payment.amountCents))", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(DrivySecondaryButtonStyle())
                            .accessibilityLabel("Annuler le règlement de \(SchoolCatalogFormatting.price(payment.amountCents)), \(name(row))")
                            .accessibilityIdentifier("course-payment-void")
                    }
                }
                // Une action, pas un état (#226) : « Payé » reste réservé aux montants enregistrés.
                Button { paying = row } label: { Label("Enregistrer un règlement", systemImage: "banknote") }
                    .buttonStyle(DrivySecondaryButtonStyle())
                    .accessibilityLabel("Enregistrer un règlement pour \(name(row))")
                    .accessibilityIdentifier("course-payment")
            }
            rowFeedback(row)
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
                if model.isRevoking(row) {
                    Label("Retrait de la validation en cours", systemImage: "clock").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                } else if model.rights?.canValidate == true {
                    Button {
                        reversal = SchoolCourseReversal(kind: .completion(completion.id), enrollmentID: row.enrollmentId, learnerName: name(row))
                    } label: { Label("Retirer la validation", systemImage: "xmark.seal") }
                        .buttonStyle(DrivySecondaryButtonStyle())
                        .accessibilityLabel("Retirer la validation, \(name(row))")
                        .accessibilityIdentifier("course-completion-revoke")
                }
            } else if model.isValidating(row) {
                // Jamais « Cours validé » avant la réponse de l’école.
                Label("Validation en cours", systemImage: "clock").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .accessibilityIdentifier("course-validate-pending")
            } else if model.rights?.canValidate == true && row.requirements.required > 0 {
                Button { validating = row } label: { Label("Valider le cours", systemImage: "checkmark.seal") }
                    .buttonStyle(DrivySecondaryButtonStyle())
                    .disabled(!model.canValidate(row))
                    .accessibilityLabel("Valider le cours, \(name(row))")
                    .accessibilityIdentifier("course-validate")
            }
            rowFeedback(row)
        }
        .padding(.vertical, DrivySpacing.xxs)
    }

    @ViewBuilder private func statusButtons(_ row: SchoolCourseSheetRow, shown: SchoolCourseAttendanceStatus?, occurrence: SchoolCourseOccurrence) -> some View {
        ForEach(SchoolCourseAttendanceStatus.allCases, id: \.self) { status in
            let selected = shown == status
            Button {
                // Retoucher l’état affiché n’envoie rien ; la version attendue est lue au moment de l’envoi.
                guard !selected else { return }
                model.submit(.attendance(enrollmentID: row.enrollmentId, occurrenceID: occurrence.id, status: status,
                    expectedVersion: nil), learnerName: name(row))
            } label: {
                Label(SchoolCourseSheetFormat.title(status), systemImage: selected ? "checkmark.circle.fill" : icon(status))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(selected ? DrivyTheme.accent : nil)
            .fontWeight(selected ? .semibold : .regular)
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

/// Motif obligatoire puis confirmation. La feuille se ferme aussitôt ; la ligne de l’élève suit l’envoi et,
/// s’il n’est pas confirmé, propose de renvoyer la même opération.
struct SchoolCourseReversalSheet: View {
    let model: SchoolCourseAttendanceWorkspace
    let target: SchoolCourseReversal
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var confirming = false
    @State private var confirmsDiscard = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Motif", text: $reason, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focused)
                        .accessibilityIdentifier("course-reversal-reason")
                } header: { Text(target.learnerName).drivyFormSectionHeader() }
                .drivyFormRows()
                Section {
                    Button(target.title, role: .destructive) { confirming = true }
                    .disabled(SchoolCourseSheetFormat.reason(reason) == nil)
                    .accessibilityIdentifier("course-reversal-submit")
                }
                .drivyFormRows()
            }
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .navigationTitle(target.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") { if reason.isEmpty { dismiss() } else { confirmsDiscard = true } }
            } }
            // L’annonce VoiceOver de l’erreur et de la confirmation vient de l’écran d’appel (model.announcement).
            .onAppear { focused = true }
            .confirmationDialog(target.question, isPresented: $confirming, titleVisibility: .visible) {
                Button(target.title, role: .destructive) { submit() }
                Button("Ne rien changer", role: .cancel) {}
            }
            .alert("Quitter sans conserver le motif ?", isPresented: $confirmsDiscard) {
                Button("Quitter", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(!reason.isEmpty)
        .tint(DrivyTheme.accent)
    }

    private func submit() {
        guard let clean = SchoolCourseSheetFormat.reason(reason) else { return }
        model.submit(target.action(reason: clean), learnerName: target.learnerName)
        dismiss()
    }
}
