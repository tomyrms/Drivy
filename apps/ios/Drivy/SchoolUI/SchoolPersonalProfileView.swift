import SwiftUI

/// Édition du compte global de la personne connectée, sans modifier Keycloak ni les dossiers scolaires.
/// Les autres champs et la photo seront branchés ici lorsque leurs contrats sécurisés seront disponibles.
struct SchoolPersonalProfileView: View {
    let person: SchoolPerson
    let save: @MainActor (String, Int, UUID) async throws -> Void

    @State private var name: String
    @State private var operationID = UUID()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmsDiscard = false
    @Environment(\.dismiss) private var dismiss

    init(person: SchoolPerson, save: @escaping @MainActor (String, Int, UUID) async throws -> Void) {
        self.person = person
        self.save = save
        _name = State(initialValue: person.displayName)
    }

    private var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping }
    private var nameIsValid: Bool {
        !normalizedName.isEmpty && normalizedName.unicodeScalars.count <= 200
            && normalizedName.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
    private var hasEdits: Bool { normalizedName != person.displayName }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom affiché", text: $name)
                        .textContentType(.nickname)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("personal-profile-display-name")
                        .disabled(isSaving)
                    if !nameIsValid {
                        Text("Indique un nom de 1 à 200 caractères, sans caractère de contrôle.")
                            .foregroundStyle(DrivyTheme.danger)
                            .font(.footnote)
                    }
                } header: {
                    Text("Identité du compte").drivyFormSectionHeader()
                } footer: {
                    Text("Ce nom est visible dans Drivy. Il ne change ni l’e-mail de connexion ni les informations scolaires.")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(DrivyTheme.danger)
                            .accessibilityIdentifier("personal-profile-error")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .navigationTitle("Modifier mon profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        if hasEdits { confirmsDiscard = true } else { dismiss() }
                    }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Enregistrer") }
                    }
                    .disabled(isSaving || !hasEdits || !nameIsValid)
                    .accessibilityIdentifier("personal-profile-save")
                }
            }
            .onChange(of: name) { _, _ in
                // Un nouvel ensemble de valeurs doit avoir une nouvelle clé d'idempotence.
                operationID = UUID()
                errorMessage = nil
            }
            .confirmationDialog("Abandonner les modifications ?", isPresented: $confirmsDiscard) {
                Button("Quitter sans enregistrer", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(isSaving || hasEdits)
    }

    private func submit() async {
        guard !isSaving, nameIsValid, hasEdits else { return }
        isSaving = true
        errorMessage = nil
        do {
            try await save(normalizedName, person.version, operationID)
            dismiss()
        } catch {
            // La saisie et la clé d'opération survivent aux erreurs réseau : un second essai est idempotent.
            if !error.isRequestCancellation {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Enregistrement impossible. Réessaie."
            }
        }
        isSaving = false
    }
}
