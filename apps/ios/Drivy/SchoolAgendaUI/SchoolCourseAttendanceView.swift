import SwiftUI
import UIKit

/// Appel d’une séance commencée : un élève par ligne, trois gros boutons, l’état affiché vient du serveur.
struct SchoolCourseAttendanceView: View {
    @Bindable var model: SchoolCourseAttendanceWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var paying: SchoolCourseSheetRow?
    @State private var amount = ""
    @State private var validating: SchoolCourseSheetRow?

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
            .navigationTitle("Appel").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .task { await model.load() }
            .refreshable { await model.load() }
            .onChange(of: model.errorMessage) { _, message in
                if let message { UIAccessibility.post(notification: .announcement, argument: message) }
            }
            .onChange(of: model.confirmation) { _, message in
                if let message { UIAccessibility.post(notification: .announcement, argument: message) }
            }
            .alert("Payé sur place", isPresented: Binding(get: { paying != nil }, set: { if !$0 { paying = nil } })) {
                TextField("Montant en CHF", text: $amount).keyboardType(.decimalPad)
                Button("Enregistrer") {
                    if let row = paying, let cents = SchoolCatalogFormatting.cents(amount) {
                        Task { await model.perform(.payment(enrollmentID: row.enrollmentId, amountCents: cents), learnerName: name(row)) }
                    }
                    paying = nil
                }
                .disabled(SchoolCatalogFormatting.cents(amount) == nil)
                Button("Annuler", role: .cancel) { paying = nil }
            } message: { if let row = paying { Text(name(row)) } }
            .confirmationDialog(validating.map { "Valider le cours pour \(name($0)) ?" } ?? "",
                                isPresented: Binding(get: { validating != nil }, set: { if !$0 { validating = nil } }),
                                titleVisibility: .visible) {
                if let row = validating {
                    Button("Valider") { Task { await model.perform(.validate(enrollmentID: row.enrollmentId), learnerName: name(row)) } }
                }
                Button("Annuler", role: .cancel) { validating = nil }
            }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }

    @ViewBuilder private var content: some View {
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
                Section {
                    if model.rows.isEmpty { Text("Aucun inscrit").foregroundStyle(DrivyTheme.muted) }
                    ForEach(model.rows) { row in learnerRow(row, occurrence: occurrence) }
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
        let busy = model.busyEnrollment == row.enrollmentId
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            HStack(spacing: DrivySpacing.xs) {
                Text(name(row)).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if busy { ProgressView().accessibilityLabel("Envoi en cours") }
            }
            if rights?.canTakeAttendance == true {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DrivySpacing.xs) { statusButtons(row, mark: mark, occurrence: occurrence) }
                    VStack(spacing: DrivySpacing.xs) { statusButtons(row, mark: mark, occurrence: occurrence) }
                }
            } else if let status = mark?.status {
                Text(SchoolCourseSheetFormat.title(status)).font(.subheadline)
            }
            if row.requirements.required > 0 {
                Text(SchoolCourseSheetFormat.progress(row.requirements))
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted).monospacedDigit()
            }
            if rights?.canRecordPayment == true {
                let paid = row.payments.filter { $0.voidedAt == nil }.reduce(Int64(0)) { $0 + $1.amountCents }
                if paid > 0 {
                    Text("Payé : \(SchoolCatalogFormatting.price(paid))").font(.subheadline).monospacedDigit()
                }
                Button { amount = ""; paying = row } label: { Label("Payé sur place", systemImage: "banknote") }
                    .buttonStyle(DrivySecondaryButtonStyle())
                    .disabled(model.isBusy)
                    .accessibilityLabel("Payé sur place, \(name(row))")
                    .accessibilityIdentifier("course-payment")
            }
            if row.completion != nil {
                Label("Cours validé", systemImage: "checkmark.seal.fill").font(.subheadline.weight(.semibold))
            } else if rights?.canValidate == true && row.requirements.required > 0 {
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
