import SwiftUI

/// Uniquement l’exception permis de R07. Les horaires sont calculés et ne demandent aucune confirmation.
struct SchoolLessonCompletionSheet: View {
    @Bindable var model: SchoolLessonReportWorkspace
    let finish: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
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
                    .listRowBackground(DrivyTheme.surface)
                }
                if model.completionNeedsReason {
                    Section("Permis non présenté") {
                        TextField("Situation du permis", text: $reason, axis: .vertical).lineLimit(2...6)
                            .disabled(isSubmitting)
                            .accessibilityLabel("Situation du permis")
                            .accessibilityIdentifier("lesson-permit-reason")
                        if reason.unicodeScalars.count > 1_000 {
                            DrivyActionNote(text: "Raccourcissez le motif à 1 000 caractères.", isError: true)
                        }
                    }
                    .listRowBackground(DrivyTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 820).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if let message = model.errorMessage {
                        DrivyActionNote(text: message, isError: true)
                    } else if model.completionNeedsReason && !validReason && !isSubmitting {
                        // Une action indisponible dit pourquoi, au-dessus d’elle.
                        DrivyActionNote(text: "Indiquez la situation du permis.")
                    }
                    Button {
                        isSubmitting = true
                        Task {
                            if await finish(reason) { dismiss() }
                            isSubmitting = false
                        }
                    } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            if isSubmitting { ProgressView().accessibilityHidden(true) }
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
                    // Une feuille qui porte une saisie se quitte par « Annuler ».
                    Button("Annuler") { dismiss() }.disabled(model.isBusy || isSubmitting)
                }
            }
        }
        // Feuille courte : mi-hauteur sur iPhone, pleine hauteur aux tailles d’accessibilité.
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .interactiveDismissDisabled(model.isBusy || isSubmitting)
        .tint(DrivyTheme.accent)
    }
}

/// Les données financières restent accessibles sans occuper le formulaire du bilan.
struct SchoolLessonTariffSheet: View {
    @Bindable var model: SchoolLessonReportWorkspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            Form {
                // Montants en chiffres tabulaires, empilés aux tailles d’accessibilité.
                if let lesson = model.lesson {
                    DrivyKeyValueRow(title: "Prix convenu", value: SchoolCatalogFormatting.price(lesson.priceCentsSnapshot), numeric: true)
                        .listRowBackground(DrivyTheme.surface)
                }
                if let account = model.account {
                    DrivyKeyValueRow(title: "À payer", value: SchoolCatalogFormatting.price(account.balanceCents), numeric: true)
                        .listRowBackground(DrivyTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 820).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .navigationTitle("Tarif").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .tint(DrivyTheme.accent)
    }
}
