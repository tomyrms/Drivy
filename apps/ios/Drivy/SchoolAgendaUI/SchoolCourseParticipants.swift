import SwiftUI

/// Aucune fermeture ne jette la saisie sans choix explicite. Une fois enregistré, le montant part dans la file de
/// l’élève et la feuille se ferme : la ligne l’affiche « en cours » (jamais dans le montant payé) jusqu’à la
/// réponse, puis propose de renvoyer la même opération s’il n’est pas confirmé (#129).
struct SchoolCoursePaymentSheet: View {
    @Bindable var model: SchoolCourseAttendanceWorkspace
    let row: SchoolCourseSheetRow
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var confirmsDiscard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(row.learnerDisplayName).font(.headline)
                    TextField("Montant en CHF", text: $amount).keyboardType(.decimalPad)
                        .accessibilityIdentifier("course-payment-amount")
                    Button("Enregistrer le règlement") {
                        guard let cents = SchoolCatalogFormatting.cents(amount), cents > 0 else { return }
                        model.submit(.payment(enrollmentID: row.enrollmentId, amountCents: cents), learnerName: row.learnerDisplayName)
                        dismiss()
                    }
                    .disabled((SchoolCatalogFormatting.cents(amount) ?? 0) <= 0)
                    .accessibilityIdentifier("course-payment-submit")
                }.drivyFormRows()
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .navigationTitle("Règlement sur place").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") { if amount.isEmpty { dismiss() } else { confirmsDiscard = true } }
            } }
            .alert("Quitter sans conserver le montant ?", isPresented: $confirmsDiscard) {
                Button("Quitter", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(!amount.isEmpty)
        .tint(DrivyTheme.accent)
    }
}

/// Recherche commune, sans limite UI de 20 noms. L’école revalide l’admissibilité lors de l’inscription.
struct SchoolCourseParticipantPicker: View {
    @Bindable var model: SchoolCourseRosterWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var selected: SchoolLearner?

    var body: some View {
        NavigationStack {
            SchoolLearnerPicker(learners: model.candidates, selectedID: selected?.id, showsHomonymReference: true) { id in
                selected = model.candidates.first { $0.id == id }
            }
            .disabled(model.isBusy)
            .safeAreaInset(edge: .bottom) {
                if let error = model.errorMessage {
                    DrivyFormMessage(text: error, tone: .danger).padding().background(DrivyTheme.canvas)
                }
            }
            .background(DrivyTheme.canvas)
            .navigationTitle("Inscrire un élève").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .confirmationDialog(selected.map { "Inscrire \(label($0)) ?" } ?? "Inscrire un élève",
                                isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
                if let learner = selected {
                    Button("Inscrire à toute la série") {
                        Task { if await model.enroll(learner) { dismiss() } }
                    }
                }
                Button("Annuler", role: .cancel) { selected = nil }
            } message: { Text("L’inscription couvre toutes les séances, à la demande de l’élève.") }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }

    private func label(_ learner: SchoolLearner) -> String {
        HomonymReference.label(learner.displayName,
            reference: HomonymReference.references(model.candidates.map { ($0.id, $0.displayName) })[learner.id])
    }
}

/// Le motif reste présent après un refus ou une réponse incertaine.
struct SchoolCourseCancelEnrollmentSheet: View {
    @Bindable var model: SchoolCourseRosterWorkspace
    let row: SchoolCourseRosterEnrollment
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var confirmsCancellation = false
    @State private var confirmsDiscard = false

    var body: some View {
        NavigationStack {
            Form {
                if let error = model.errorMessage {
                    Section { DrivyFormMessage(text: error, tone: .danger) }.drivyFormRows()
                }
                Section {
                    Text(row.learnerDisplayName.isEmpty ? "Élève" : row.learnerDisplayName).font(.headline)
                    TextField("Motif", text: $reason, axis: .vertical).lineLimit(2...6)
                        .disabled(model.isBusy).accessibilityIdentifier("course-cancel-reason")
                    Button("Annuler l’inscription", role: .destructive) { confirmsCancellation = true }
                        .disabled(model.isBusy || SchoolCourseSheetFormat.reason(reason) == nil)
                }.drivyFormRows()
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .navigationTitle("Annuler l’inscription").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") { if reason.isEmpty { dismiss() } else { confirmsDiscard = true } }.disabled(model.isBusy)
            } }
            .confirmationDialog("Annuler la participation à toute la série ?", isPresented: $confirmsCancellation, titleVisibility: .visible) {
                Button("Annuler l’inscription", role: .destructive) {
                    Task { if await model.cancel(row, reason: reason) { dismiss() } }
                }
                Button("Garder l’inscription", role: .cancel) {}
            }
            .alert("Quitter sans conserver le motif ?", isPresented: $confirmsDiscard) {
                Button("Quitter", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(model.isBusy || !reason.isEmpty)
        .tint(DrivyTheme.accent)
    }
}
