import SwiftUI

/// Sauvegarde des clés (#67) : clé de récupération montrée une seule fois, restauration, retard signalé seulement s'il existe.
@MainActor
@Observable
final class MessagingKeyBackupModel {
    enum Failure: Equatable {
        case createFailed, existingBackup, wrongKey, emptyKey, contextChanged
        var message: String {
            switch self {
            case .createFailed: "La sauvegarde n'a pas pu être créée. Réessaie plus tard."
            case .existingBackup: "Une sauvegarde existe déjà pour ce compte. Restaure-la avec ta clé de récupération."
            case .wrongKey: "Clé de récupération incorrecte ou sauvegarde introuvable. Rien n'a été modifié."
            case .emptyKey: "Saisis ta clé de récupération."
            case .contextChanged: MessagingFailure.contextChanged.localizedDescription
            }
        }
    }

    let scope: MessagingScope
    private let keys: any MessagingKeyManagement
    private(set) var pending = false
    /// Présente seulement entre la création et la confirmation : jamais persistée ni réaffichée.
    private(set) var recoveryKey: String?
    private(set) var notRestored: Int?
    private(set) var restored = false
    private(set) var failure: Failure?
    private(set) var working = false
    /// Code court non sensible de la panne, affiché sous l'erreur de création.
    private(set) var diagnosticCode: String?
    private let diagnostics: MessagingDiagnostics

    init(scope: MessagingScope, keys: any MessagingKeyManagement, diagnostics: MessagingDiagnostics = .shared) {
        self.scope = scope
        self.keys = keys
        self.diagnostics = diagnostics
    }

    func refresh() async { pending = await keys.backupPending(scope: scope) }

    func create() async {
        guard !working else { return }
        working = true; failure = nil; diagnosticCode = nil
        defer { working = false }
        do { recoveryKey = try await keys.enableBackup(scope: scope) }
        catch MessagingFailure.stateConflict { failure = .existingBackup }
        catch MessagingFailure.contextChanged { failure = .contextChanged }
        catch { failure = .createFailed; diagnosticCode = diagnostics.last }
        await refresh()
    }

    func acknowledgeKey() { recoveryKey = nil }

    func restore(_ input: String) async {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { failure = .emptyKey; return }
        guard !working else { return }
        working = true; failure = nil; diagnosticCode = nil; notRestored = nil; restored = false
        defer { working = false }
        do {
            let result = try await keys.restoreBackup(recoveryKey: key, scope: scope)
            restored = true
            notRestored = result.failed > 0 ? result.failed : nil
        }
        catch MessagingFailure.contextChanged { failure = .contextChanged }
        catch { failure = .wrongKey }
        await refresh()
    }

    static func notRestoredText(_ count: Int) -> String {
        count == 1 ? "1 conversation non restaurée" : "\(count) conversations non restaurées"
    }
}

/// Réglages de Messages : point d'entrée de la sauvegarde des clés.
struct MessagingSettingsView: View {
    let keys: (any MessagingKeyManagement)?
    let scope: MessagingScope
    let currentScope: @MainActor @Sendable () -> MessagingScope?

    func makeDevicesModel(keys: any MessagingKeyManagement) -> MessagingOwnDevicesModel {
        MessagingOwnDevicesModel(scope: scope, keys: keys, currentScope: currentScope)
    }

    var body: some View {
        List {
            Section {
                if let keys {
                    NavigationLink {
                        MessagingKeyBackupView(model: MessagingKeyBackupModel(scope: scope, keys: keys))
                    } label: {
                        Label("Sauvegarde des clés", systemImage: "key")
                    }
                    .accessibilityIdentifier("messaging.backup.open")
                    NavigationLink {
                        MessagingOwnDevicesView(model: makeDevicesModel(keys: keys))
                    } label: {
                        Label("Mes appareils", systemImage: "iphone.and.ipad")
                    }
                    .accessibilityIdentifier("messaging.devices.open")
                } else {
                    Label("Sauvegarde des clés indisponible", systemImage: "key.slash")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Réglages")
        .accessibilityIdentifier("messaging.settings")
    }
}

struct MessagingKeyBackupView: View {
    @State var model: MessagingKeyBackupModel
    @State private var input = ""
    @AccessibilityFocusState private var errorFocused: Bool

    var body: some View {
        Form {
            if model.pending {
                Section {
                    Label("Sauvegarde en retard", systemImage: "exclamationmark.arrow.circlepath")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("messaging.backup.pending")
                }
            }
            if let failure = model.failure {
                Section {
                    Label(failure.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("messaging.backup.error")
                        .accessibilityFocused($errorFocused)
                    if let code = model.diagnosticCode {
                        Text("Code : \(code)")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("messaging.error.code")
                    }
                }
            }
            Section("Nouvelle sauvegarde") {
                if let key = model.recoveryKey {
                    Text(key)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .accessibilityLabel("Clé de récupération")
                        .accessibilityValue(key.map(String.init).joined(separator: " "))
                        .accessibilityIdentifier("messaging.backup.key")
                    Button("J'ai noté la clé") { model.acknowledgeKey() }
                        .accessibilityIdentifier("messaging.backup.key.done")
                } else {
                    Button { Task { await model.create() } } label: {
                        Label("Créer une clé de récupération", systemImage: "key.fill")
                    }
                    .disabled(model.working)
                    .accessibilityIdentifier("messaging.backup.create")
                }
            }
            Section("Restaurer") {
                SecureField("Clé de récupération", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.oneTimeCode)
                    .accessibilityIdentifier("messaging.backup.input")
                Button { Task { await model.restore(input); if model.restored { input = "" } } } label: {
                    Label("Restaurer", systemImage: "arrow.down.circle")
                }
                .disabled(model.working || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("messaging.backup.restore")
                if let count = model.notRestored {
                    Label(MessagingKeyBackupModel.notRestoredText(count), systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("messaging.backup.notRestored")
                } else if model.restored {
                    Label("Restaurée", systemImage: "checkmark.circle")
                        .accessibilityIdentifier("messaging.backup.restored")
                }
            }
        }
        .overlay { if model.working { ProgressView().accessibilityLabel("En cours") } }
        .navigationTitle("Sauvegarde des clés")
        .task { await model.refresh() }
        .onChange(of: model.failure) { _, value in errorFocused = value != nil }
        .onDisappear { model.acknowledgeKey() }
    }
}
