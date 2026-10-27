import SwiftUI

/// Sauvegarde des clés (#67) : clé de récupération montrée une seule fois, restauration, retard signalé seulement s'il existe.
@MainActor
@Observable
final class MessagingKeyBackupModel {
    enum Failure: Equatable {
        case createFailed, existingBackup, emptyKey, contextChanged
        /// Clé refusée par la vérification (ou sauvegarde absente, volontairement indistincte).
        case wrongKey
        /// La requête n'a pas abouti : la clé n'a pas été vérifiée.
        case unreachable
        /// Session expirée ou droits retirés.
        case sessionExpired
        /// Protection locale ou réponse illisible : rien n'accuse la clé.
        case restoreFailed

        var message: String {
            switch self {
            case .createFailed: "La sauvegarde n'a pas pu être créée. Réessaie plus tard."
            case .existingBackup: "Une sauvegarde existe déjà pour ce compte. Restaure-la avec ta clé de récupération."
            case .wrongKey: "Clé de récupération refusée. Vérifie-la puis réessaie. Rien n'a été modifié."
            case .unreachable: "Messages est injoignable. Ta clé n'a pas été vérifiée et rien n'a été modifié."
            case .sessionExpired: "Ta session a expiré. Reconnecte-toi puis réessaie. Rien n'a été modifié."
            case .restoreFailed: "La restauration n'a pas abouti. Ta clé n'est pas en cause. Réessaie plus tard."
            case .emptyKey: "Saisis ta clé de récupération."
            case .contextChanged: MessagingFailure.contextChanged.localizedDescription
            }
        }

        /// Une nouvelle tentative avec la même saisie a un sens.
        var retryable: Bool { self == .unreachable || self == .restoreFailed }
        /// Seul un refus de clé est une erreur de saisie ; le reste est un empêchement temporaire.
        var tone: DrivyTone {
            switch self {
            case .wrongKey, .emptyKey, .existingBackup, .createFailed: .danger
            case .unreachable, .sessionExpired, .restoreFailed, .contextChanged: .warning
            }
        }
    }

    let scope: MessagingScope
    private let keys: any MessagingKeyManagement
    private let currentScope: @MainActor @Sendable () -> MessagingScope?
    private(set) var pending = false
    /// Présente seulement entre la création et la confirmation : jamais persistée, copiée ni réaffichée.
    private var issuedKey: String?
    private(set) var notRestored: Int?
    private(set) var restored = false
    private(set) var failure: Failure?
    private(set) var working = false
    /// Code court non sensible de la panne, affiché sous l'erreur.
    private(set) var diagnosticCode: String?
    private let diagnostics: MessagingDiagnostics

    init(scope: MessagingScope, keys: any MessagingKeyManagement, diagnostics: MessagingDiagnostics = .shared,
         currentScope: @escaping @MainActor @Sendable () -> MessagingScope? = { nil }) {
        self.scope = scope
        self.keys = keys
        self.diagnostics = diagnostics
        self.currentScope = currentScope
    }

    /// La clé n'est lisible que pour le compte et l'école qui l'ont créée : un autre contexte la purge.
    var recoveryKey: String? {
        guard let issuedKey else { return nil }
        if let current = currentScope(), current != scope { return nil }
        return issuedKey
    }

    /// Vrai tant qu'une clé affichée n'a pas été confirmée : la sortie doit être protégée.
    var holdsUnconfirmedKey: Bool { recoveryKey != nil }

    func refresh() async { pending = await keys.backupPending(scope: scope) }

    func create() async {
        guard !working else { return }
        working = true; failure = nil; diagnosticCode = nil
        defer { working = false }
        do {
            let key = try await keys.enableBackup(scope: scope)
            if let current = currentScope(), current != scope { failure = .contextChanged }
            else { issuedKey = key }
        }
        catch MessagingFailure.stateConflict { failure = .existingBackup }
        catch MessagingFailure.contextChanged { failure = .contextChanged }
        catch { failure = .createFailed; diagnosticCode = diagnostics.last }
        await refresh()
    }

    /// Confirmation ou sortie explicite : seule voie qui oublie la clé pendant le parcours normal.
    func acknowledgeKey() { issuedKey = nil }

    /// Changement de compte ou d'école : purge sans rien montrer.
    func purgeIfContextChanged() {
        if let current = currentScope(), current != scope { issuedKey = nil }
    }

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
        } catch {
            failure = Self.classify(error)
            if failure == .restoreFailed || failure == .unreachable { diagnosticCode = diagnostics.last }
        }
        await refresh()
    }

    /// Seul un refus explicite de la vérification accuse la clé (#169).
    static func classify(_ error: any Error) -> Failure {
        switch error as? MessagingFailure {
        case .recoveryKeyRefused: .wrongKey
        case .contextChanged: .contextChanged
        case .accessChanged: .sessionExpired
        case .unavailable: .unreachable
        default: .restoreFailed
        }
    }

    static func notRestoredText(_ count: Int) -> String {
        count == 1 ? "1 conversation non restaurée" : "\(count) conversations non restaurées"
    }
}

/// Paramètres de Messages : point d'entrée de la sauvegarde des clés et des appareils.
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
                        MessagingKeyBackupView(model: MessagingKeyBackupModel(scope: scope, keys: keys, currentScope: currentScope))
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
        .navigationTitle("Paramètres de Messages")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("messaging.settings")
    }
}

struct MessagingKeyBackupView: View {
    @State var model: MessagingKeyBackupModel
    @State private var input = ""
    @State private var confirmsExit = false
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var errorFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let errorRow = "messaging.backup.errorRow"

    var body: some View {
        ScrollViewReader { proxy in
            form.onChange(of: model.failure) { _, value in
                errorFocused = value != nil
                // L'erreur s'insère en tête du formulaire, loin du bouton touché : en grand texte
                // ou sur iPad elle restait hors écran. La montrer une fois la ligne insérée.
                guard value != nil else { return }
                DispatchQueue.main.async {
                    withAnimation(DrivyMotion.settle(reduceMotion)) { proxy.scrollTo(Self.errorRow, anchor: .top) }
                }
            }
        }
    }

    private var form: some View {
        Form {
            if model.pending {
                Section {
                    DrivyFormMessage(text: "Sauvegarde en retard", tone: .warning)
                        .accessibilityIdentifier("messaging.backup.pending")
                }
                .drivyFormRows()
            }
            if let failure = model.failure {
                Section {
                    DrivyFormMessage(text: failure.message, tone: failure.tone)
                        .accessibilityIdentifier("messaging.backup.error")
                        .accessibilityFocused($errorFocused)
                        .id(Self.errorRow)
                    if let code = model.diagnosticCode {
                        Text("Code : \(code)")
                            .font(.footnote.monospaced())
                            .foregroundStyle(DrivyTheme.muted)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("messaging.error.code")
                    }
                    if failure.retryable {
                        Button("Réessayer") { Task { await restore() } }
                            .disabled(model.working || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .frame(minHeight: DrivyLayout.tapTarget)
                            .accessibilityIdentifier("messaging.backup.retry")
                    }
                }
                .drivyFormRows()
            }
            Section {
                if let key = model.recoveryKey {
                    Text(key)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .privacySensitive()
                        .accessibilityLabel("Clé de récupération")
                        .accessibilityValue(key.map(String.init).joined(separator: " "))
                        .accessibilityIdentifier("messaging.backup.key")
                    Button("J'ai noté la clé") { model.acknowledgeKey() }
                        .frame(minHeight: DrivyLayout.tapTarget)
                        .accessibilityIdentifier("messaging.backup.key.done")
                } else {
                    Button { Task { await model.create() } } label: {
                        Label("Créer une clé de récupération", systemImage: "key.fill")
                    }
                    .disabled(model.working)
                    .accessibilityIdentifier("messaging.backup.create")
                }
            } header: {
                Text("Nouvelle sauvegarde")
            } footer: {
                if model.holdsUnconfirmedKey {
                    Text("Affichée une seule fois. Note-la avant de quitter.")
                        .accessibilityIdentifier("messaging.backup.key.once")
                }
            }
            .drivyFormRows()
            Section("Restaurer") {
                SecureField("Clé de récupération", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.oneTimeCode)
                    .accessibilityIdentifier("messaging.backup.input")
                Button { Task { await restore() } } label: {
                    Label("Restaurer", systemImage: "arrow.down.circle")
                }
                .disabled(model.working || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("messaging.backup.restore")
                if let count = model.notRestored {
                    DrivyFormMessage(text: MessagingKeyBackupModel.notRestoredText(count), tone: .warning)
                        .accessibilityIdentifier("messaging.backup.notRestored")
                    Button("Réessayer") { Task { await restore() } }
                        .disabled(model.working || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .frame(minHeight: DrivyLayout.tapTarget)
                        .accessibilityIdentifier("messaging.backup.retryPartial")
                } else if model.restored {
                    DrivyFormMessage(text: "Restaurée", tone: .success)
                        .accessibilityIdentifier("messaging.backup.restored")
                }
            }
            .drivyFormRows()
        }
        .scrollContentBackground(.hidden)
        .background(DrivyTheme.canvas)
        .overlay { if model.working { ProgressView().accessibilityLabel("En cours") } }
        .navigationTitle("Sauvegarde des clés")
        // Clé non confirmée : ni retour, ni glissement, ni balayage de la feuille ne la font disparaître en silence.
        .navigationBarBackButtonHidden(model.holdsUnconfirmedKey)
        .interactiveDismissDisabled(model.holdsUnconfirmedKey)
        .toolbar {
            if model.holdsUnconfirmedKey {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Quitter") { confirmsExit = true }
                        .accessibilityIdentifier("messaging.backup.exit")
                }
            }
        }
        .confirmationDialog("Quitter sans avoir noté la clé ?", isPresented: $confirmsExit, titleVisibility: .visible) {
            Button("Quitter sans la clé", role: .destructive) {
                model.acknowledgeKey()
                dismiss()
            }
            .accessibilityIdentifier("messaging.backup.exit.confirm")
            Button("Revenir à la clé", role: .cancel) { }
                .accessibilityIdentifier("messaging.backup.exit.cancel")
        } message: {
            Text("Elle ne sera plus jamais affichée. Sans elle, tes messages ne pourront pas être restaurés sur un autre appareil.")
        }
        .task { await model.refresh() }
        .onAppear { model.purgeIfContextChanged() }
        .onDisappear { model.purgeIfContextChanged() }
    }

    private func restore() async {
        await model.restore(input)
        // Une restauration complète oublie la saisie ; une restauration partielle la garde pour réessayer.
        if model.restored && model.notRestored == nil { input = "" }
    }
}
