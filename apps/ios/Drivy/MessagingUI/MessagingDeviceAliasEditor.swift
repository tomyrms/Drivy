import SwiftUI

struct MessagingDeviceAliasEditor: View {
    @Bindable var model: MessagingOwnDevicesModel
    let device: MessagingOwnDevice
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(model: MessagingOwnDevicesModel, device: MessagingOwnDevice) {
        self.model = model; self.device = device
        _name = State(initialValue: model.alias(device) ?? "")
    }

    private var isValid: Bool { MessagingDeviceAliasRules.valid(MessagingDeviceAliasRules.normalized(name)) }

    var body: some View {
        Form {
            Section {
                TextField("Nom de l’appareil", text: $name)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .accessibilityIdentifier("messaging.devices.alias")
                if !isValid {
                    DrivyFormMessage(text: "Choisis un nom de 64 caractères au maximum, sur une seule ligne.")
                }
                if let error = model.aliasError { SchoolErrorNotice(message: error) }
            } header: {
                Text("Nom local")
            } footer: {
                Text("Visible uniquement sur cet appareil. Efface le nom pour retrouver la référence.")
            }
            Section("Identité") {
                Text(device.id).font(.body.monospaced()).textSelection(.enabled)
                Text(device.fingerprint).font(.body.monospaced()).textSelection(.enabled)
                    .accessibilityLabel("Empreinte de l’appareil")
                    .accessibilityValue(device.fingerprint.map(String.init).joined(separator: " "))
            }
        }
        .scrollContentBackground(.hidden)
        .background(DrivyTheme.canvas)
        .navigationTitle("Nommer l’appareil")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.working)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(model.working) }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { if await model.saveAlias(name, device: device) { dismiss() } }
                } label: {
                    DrivyBusyLabel(title: "Enregistrer", busyTitle: "Enregistrement…", isBusy: model.working)
                }
                .disabled(!isValid || !model.canRename(device))
                .accessibilityIdentifier("messaging.devices.saveAlias")
            }
        }
        .interactiveDismissDisabled(model.working)
    }
}
