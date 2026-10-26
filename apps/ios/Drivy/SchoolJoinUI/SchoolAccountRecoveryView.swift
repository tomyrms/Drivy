import SwiftUI

/// La récupération appartient au fournisseur d'identité ; ouvrir son formulaire ne signifie pas qu'un mail est parti.
struct SchoolAccountRecoveryView: View {
    let client: SchoolAccountRecoveryClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var options: SchoolAccountRecoveryOptions?
    @State private var errorMessage: String?
    @State private var reloadID = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    if let errorMessage {
                        SchoolErrorNotice(message: errorMessage, retry: reload)
                            .accessibilityIdentifier("account-recovery-error")
                    } else if let options {
                        if options.available, let url = options.recoveryUrl {
                            Button {
                                openURL(url) { accepted in
                                    if !accepted { errorMessage = "Le navigateur n’a pas pu s’ouvrir. Réessaie." }
                                }
                            } label: { Label("Continuer dans le navigateur", systemImage: "safari") }
                            .buttonStyle(DrivyPrimaryButtonStyle())
                            .accessibilityIdentifier("account-recovery-open")
                        } else {
                            SchoolErrorNotice(message: "La récupération par e-mail n’est pas encore disponible.", retry: reload)
                                .accessibilityIdentifier("account-recovery-unavailable")
                        }
                    } else {
                        ProgressView("Vérification de la récupération…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .drivyPageContent(maxWidth: DrivyLayout.narrowColumn)
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Mot de passe oublié")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .task(id: reloadID) {
                do {
                    let result = try await client.options()
                    guard !Task.isCancelled else { return }
                    options = result
                } catch {
                    guard !error.isRequestCancellation else { return }
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? SchoolAccountRecoveryFailure.unavailable.localizedDescription
                }
            }
        }
    }
    private func reload() { options = nil; errorMessage = nil; reloadID = UUID() }
}
