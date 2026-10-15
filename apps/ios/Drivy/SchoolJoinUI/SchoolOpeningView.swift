import Observation
import SwiftUI

/// Ouvrir son école avec un code d’ouverture, connecté. La demande garde son opération tant que
/// la réponse n’est pas connue : « Réessayer » renvoie la même, et le serveur rend le même reçu.
@MainActor @Observable final class SchoolOpeningWorkspace: Identifiable {
    let id = UUID()
    let code: String
    var displayName: String
    var schoolName = ""
    var contactEmail: String
    var phone = ""
    var instructs = true
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var receipt: SchoolOpeningReceipt?
    @ObservationIgnored private var pending: SchoolOpeningCommand?
    @ObservationIgnored private let client: SchoolOpeningClient

    init(client: SchoolOpeningClient, code: String, displayName: String?, email: String?) {
        self.client = client; self.code = code
        self.displayName = displayName ?? ""; self.contactEmail = email ?? ""
    }

    /// Une demande dont la réponse manque : les champs restent figés jusqu’à son résultat.
    var isPending: Bool { pending != nil && receipt == nil }
    var canSubmit: Bool {
        !isBusy && receipt == nil && (isPending || (!displayName.trimmed.isEmpty && !schoolName.trimmed.isEmpty
            && contactEmail.trimmed.contains("@") && phone.trimmed.count <= 32))
    }

    func submit() async {
        guard canSubmit else { return }
        let command = pending ?? SchoolOpeningCommand(
            operationId: UUID(), token: code, schoolName: schoolName.trimmed, displayName: displayName.trimmed,
            contactEmail: contactEmail.trimmed.lowercased(), contactPhone: phone.trimmed.isEmpty ? nil : phone.trimmed,
            timeZone: Self.timeZone, instructs: instructs)
        pending = command; isBusy = true; errorMessage = nil
        do {
            receipt = try await client.open(command)
            isBusy = false
        } catch {
            isBusy = false
            let failure = error as? SchoolOpeningFailure ?? .unavailable
            // Refus certain : rien n’a été créé, une correction repart d’une nouvelle demande.
            if !failure.keepsOperation { pending = nil }
            if !error.isRequestCancellation { errorMessage = failure.localizedDescription }
        }
    }

    /// Le fuseau de l’appareil quand il est nommé (Europe/Zurich), sinon celui de l’école par défaut.
    static var timeZone: String {
        let identifier = TimeZone.current.identifier
        return identifier.contains("/") ? identifier : "Europe/Zurich"
    }
}

struct SchoolOpeningView: View {
    @Bindable var model: SchoolOpeningWorkspace
    let openSchool: (SchoolOpeningReceipt) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: SchoolAccountFieldID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    if let receipt = model.receipt {
                        SchoolJoinSchoolHeader(name: receipt.schoolName,
                            facts: [SchoolJoinFact(symbol: "person.crop.circle", text: SchoolPresentation.roles(receipt.roles), isEmphasized: true)],
                            isConfirmed: true)
                        DrivyInlineMessage(text: "Ton école est créée. Termine sa préparation sur le portail web.")
                    } else {
                        if let message = model.errorMessage { SchoolErrorNotice(message: message) }
                        fields.disabled(model.isBusy || model.isPending)
                    }
                }
                .drivyPageContent(maxWidth: DrivyLayout.compactColumn)
            }
            .background(DrivyTheme.surface)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { actionBar }
            .navigationTitle(model.receipt == nil ? "Ouvrir ton école" : "École créée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy || model.isPending) }
            }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.isBusy || model.isPending)
        .onAppear { focus = model.displayName.isEmpty ? .displayName : .schoolName }
        .accessibilityIdentifier("school-opening")
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            SchoolAccountField(label: "Ton nom", text: $model.displayName, kind: .name, id: .displayName, focus: $focus,
                               identifier: "opening-display-name", onSubmit: { focus = .schoolName })
            SchoolAccountField(label: "Nom de l’auto-école", text: $model.schoolName, kind: .organization, id: .schoolName, focus: $focus,
                               identifier: "opening-school-name", onSubmit: { focus = .contactEmail })
            SchoolAccountField(label: "E-mail professionnel", text: $model.contactEmail, kind: .email, id: .contactEmail, focus: $focus,
                               identifier: "opening-contact-email", onSubmit: { focus = .phone })
            SchoolAccountField(label: "Téléphone (facultatif)", text: $model.phone, kind: .phone, id: .phone, focus: $focus,
                               identifier: "opening-phone", submitLabel: .done, onSubmit: { focus = nil })
            Toggle("Je donne aussi des leçons", isOn: $model.instructs)
                .font(.body)
                .tint(DrivyTheme.accent)
                .frame(minHeight: DrivyLayout.tapTarget)
                .accessibilityIdentifier("opening-instructs")
        }
    }

    private var actionBar: some View {
        DrivyFormActionBar(hint: model.isPending && !model.isBusy ? "La réponse n’est pas arrivée : la même demande sera renvoyée." : nil) {
            if let receipt = model.receipt {
                Button("Ouvrir mon école") { openSchool(receipt) }
                    .accessibilityIdentifier("opening-open-school")
            } else {
                Button { Task { await model.submit() } } label: {
                    DrivyBusyLabel(title: model.isPending ? "Réessayer" : "Créer mon école", busyTitle: "Création…", isBusy: model.isBusy)
                }
                .disabled(!model.canSubmit)
                .accessibilityIdentifier("opening-submit")
            }
        }
        .buttonStyle(DrivyPrimaryButtonStyle())
        .frame(maxWidth: DrivyLayout.compactColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.surface)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
