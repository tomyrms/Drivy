import SwiftUI

/// Uniquement l’exception permis de R07. Les horaires sont calculés et ne demandent aucune confirmation.
struct SchoolLessonCompletionSheet: View {
    @Bindable var model: SchoolLessonReportWorkspace
    let finish: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var confirmsDiscard = false

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
                    .drivyFormRows()
                }
                if model.completionNeedsReason {
                    Section {
                        TextField("Situation du permis", text: $reason, axis: .vertical).lineLimit(2...6)
                            .disabled(isSubmitting)
                            .accessibilityLabel("Situation du permis")
                            .accessibilityIdentifier("lesson-permit-reason")
                        if reason.unicodeScalars.count > 1_000 {
                            DrivyActionNote(text: "Raccourcis le motif à 1 000 caractères.", isError: true)
                        }
                    } header: { Text("Permis non présenté").drivyFormSectionHeader() }
                    .drivyFormRows()
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: DrivyLayout.formColumn).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if let message = model.errorMessage {
                        DrivyActionNote(text: message, isError: true)
                    } else if model.completionNeedsReason && !validReason && !isSubmitting {
                        // Une action indisponible dit pourquoi, au-dessus d’elle.
                        DrivyActionNote(text: "Indique la situation du permis.")
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
                    Button("Annuler") {
                        if reason.isEmpty { dismiss() } else { confirmsDiscard = true }
                    }.disabled(model.isBusy || isSubmitting)
                }
            }
            .alert("Quitter sans enregistrer ?", isPresented: $confirmsDiscard) {
                Button("Quitter sans enregistrer", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) { }
            }
        }
        // Feuille courte : mi-hauteur sur iPhone, pleine hauteur aux tailles d’accessibilité.
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(!reason.isEmpty || model.isBusy || isSubmitting)
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
                // Montants en chiffres tabulaires : le prix convenu se lit, le solde à payer est le point focal.
                if let lesson = model.lesson {
                    amountRow("Prix convenu", SchoolCatalogFormatting.price(lesson.priceCentsSnapshot), emphasized: false)
                        .drivyFormRows()
                }
                if let account = model.account {
                    amountRow("À payer", SchoolCatalogFormatting.price(account.balanceCents), emphasized: true)
                        .drivyFormRows()
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: DrivyLayout.formColumn).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .navigationTitle("Tarif").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(DrivyTheme.accent)
    }

    /// Libellé et montant sur une ligne ; empilés aux tailles d’accessibilité.
    private func amountRow(_ title: String, _ amount: String, emphasized: Bool) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DrivySpacing.s))
        return layout {
            Text(title).font(emphasized ? .headline : .body).foregroundStyle(emphasized ? DrivyTheme.text : DrivyTheme.muted)
            if !typeSize.isAccessibilitySize { Spacer(minLength: DrivySpacing.s) }
            Text(amount)
                .font(emphasized ? .title2.weight(.bold) : .body)
                .monospacedDigit()
                .foregroundStyle(DrivyTheme.text)
        }
        .padding(.vertical, emphasized ? DrivySpacing.xs : DrivySpacing.xxs)
        .frame(minHeight: emphasized ? DrivySpacing.xxl + DrivySpacing.m : 44)
        .accessibilityElement(children: .combine)
    }
}
