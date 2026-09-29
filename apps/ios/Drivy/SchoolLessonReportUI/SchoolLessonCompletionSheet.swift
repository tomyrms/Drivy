import SwiftUI

/// Uniquement l’exception permis de R07. Les horaires sont calculés et ne demandent aucune confirmation.
struct SchoolLessonCompletionSheet: View {
    @Bindable var model: SchoolLessonReportWorkspace
    let finish: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var isSubmitting = false

    private var validReason: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reason.unicodeScalars.count <= 1_000
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.mayRecordPermit {
                    Section {
                        Button {
                            isSubmitting = true
                            Task {
                                if await model.recordPermitSeen(), await finish("") { dismiss() }
                                isSubmitting = false
                            }
                        } label: {
                            Label("J’ai vu le permis d’élève", systemImage: "checkmark.seal")
                                .font(.body.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                        .disabled(!model.canMutate || isSubmitting)
                        .accessibilityIdentifier("lesson-permit-seen")
                    }
                }
                if model.completionNeedsReason {
                    Section("Permis non présenté") {
                        TextField("Situation du permis", text: $reason, axis: .vertical).lineLimit(2...6)
                            .disabled(isSubmitting)
                        if reason.unicodeScalars.count > 1_000 {
                            DrivyActionNote(text: "Raccourcissez le motif à 1 000 caractères.", isError: true)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 820).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if let message = model.errorMessage { DrivyActionNote(text: message, isError: true) }
                    Button {
                        isSubmitting = true
                        Task {
                            if await finish(reason) { dismiss() }
                            isSubmitting = false
                        }
                    } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            if isSubmitting { ProgressView() }
                            Label("Terminer la leçon", systemImage: "checkmark.circle")
                        }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!model.canMutate || isSubmitting || (model.completionNeedsReason && !validReason))
                    .accessibilityIdentifier("lesson-complete-permit")
                }
            }
            .navigationTitle("Permis d’élève").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }.disabled(model.isBusy || isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(model.isBusy || isSubmitting)
        .tint(DrivyTheme.accent)
    }
}

/// Les données financières restent accessibles sans occuper le formulaire du bilan.
struct SchoolLessonTariffSheet: View {
    @Bindable var model: SchoolLessonReportWorkspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let lesson = model.lesson {
                    LabeledContent("Prix convenu", value: SchoolCatalogFormatting.price(lesson.priceCentsSnapshot))
                }
                if let account = model.account {
                    LabeledContent("À payer", value: SchoolCatalogFormatting.price(account.balanceCents))
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 820).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .navigationTitle("Tarif").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        .tint(DrivyTheme.accent)
    }
}
