import SwiftUI

struct MessagingOwnDevicesView: View {
    @State var model: MessagingOwnDevicesModel
    @AccessibilityFocusState private var errorFocused: Bool

    var body: some View {
        List {
            if let snapshot = model.snapshot {
                Section("Cet appareil") {
                    Text(snapshot.localDevice.id).font(.subheadline.monospaced())
                    fingerprint(snapshot.localDevice.fingerprint)
                        .accessibilityIdentifier("messaging.devices.localFingerprint")
                }
                if let message = capabilityMessage {
                    Section { Label(message, systemImage: "exclamationmark.lock") }
                }
                Section("Autres appareils") {
                    if snapshot.devices.isEmpty {
                        Text("Aucun autre appareil").foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.devices) { device in
                        Button { model.select(device) } label: {
                            HStack {
                                Text(device.id).font(.body.monospaced())
                                Spacer()
                                if device.isVerified {
                                    Image(systemName: "checkmark.shield")
                                        .accessibilityLabel("Vérifié")
                                }
                            }
                        }
                        .disabled(model.working)
                        .accessibilityIdentifier("messaging.devices.device.\(device.id)")
                    }
                }
            }
            if model.selected == nil, let failure = model.failure {
                Section {
                    error(failure.message)
                    Button("Réessayer") { Task { await model.refresh() } }
                        .disabled(model.working)
                }
            }
        }
        .navigationTitle("Mes appareils")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await model.refresh() } } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .disabled(model.working)
                .accessibilityIdentifier("messaging.devices.refresh")
            }
        }
        .overlay { if model.working && model.selected == nil { ProgressView().accessibilityLabel("Chargement des appareils") } }
        .sheet(item: Binding(get: { model.selected }, set: { if $0 == nil { model.cancelComparison() } })) { device in
            comparison(device)
        }
        .task { await model.activate() }
        .onDisappear { model.invalidate() }
        .onChange(of: model.failure) { _, value in errorFocused = value != nil }
    }

    private var capabilityMessage: String? {
        switch model.snapshot?.capability {
        case .originalDeviceRequired: "Utilise l’appareil qui a configuré la vérification."
        case .identityConflict: "L’identité de vérification ne correspond plus. Aucun appareil ne sera signé."
        default: nil
        }
    }

    private func comparison(_ device: MessagingOwnDevice) -> some View {
        NavigationStack {
            Form {
                Section {
                    Text(device.id).font(.body.monospaced())
                    fingerprint(device.fingerprint)
                }
                if model.verifiedDeviceID == device.id || device.isVerified {
                    Label("Vérifié", systemImage: "checkmark.shield")
                        .accessibilityIdentifier("messaging.devices.verified")
                } else {
                    if let message = capabilityMessage {
                        Section { Label(message, systemImage: "exclamationmark.lock") }
                    } else {
                        Section {
                            Text("Compare cette empreinte avec celle affichée dans « Cet appareil » sur l’autre appareil.")
                            Toggle("Les empreintes correspondent", isOn: $model.compared)
                                .disabled(model.working)
                                .accessibilityIdentifier("messaging.devices.compared")
                            Button("Vérifier") { Task { await model.confirm() } }
                                .disabled(!model.canConfirm)
                                .accessibilityIdentifier("messaging.devices.confirm")
                        }
                    }
                }
                if let failure = model.failure { Section { error(failure.message) } }
                if model.working { ProgressView().accessibilityLabel("Vérification en cours") }
            }
            .navigationTitle("Comparer les empreintes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.verifiedDeviceID == device.id ? "Fermer" : "Annuler") { model.cancelComparison() }
                        .disabled(model.working)
                        .accessibilityIdentifier("messaging.devices.cancel")
                }
            }
            .interactiveDismissDisabled(model.working)
        }
    }

    private func fingerprint(_ value: String) -> some View {
        Text(value)
            .font(.body.monospaced())
            .textSelection(.enabled)
            .accessibilityLabel("Empreinte de l’appareil")
            .accessibilityValue(value.map(String.init).joined(separator: " "))
    }

    private func error(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .accessibilityIdentifier("messaging.devices.error")
            .accessibilityFocused($errorFocused)
    }
}
