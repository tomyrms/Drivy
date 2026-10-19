import Foundation
import Observation

/// Ce qu’il reste à faire, connecté, avec le code saisi avant la connexion.
struct SchoolAccessOutcome: Equatable {
    let input: SchoolAccessInput
    let kind: SchoolAccessKind
    /// Nom saisi à la création du compte, repris par le formulaire de l’école.
    let displayName: String?
    let email: String?
}

/// « J’ai un code » avant connexion : lire le code, puis créer le compte (seul un code valable le permet)
/// ou se connecter à un compte existant. Le code n’est consommé qu’ensuite, connecté, par l’écran qui suit.
@MainActor @Observable final class SchoolAccessWorkspace: Identifiable {
    enum Step: Equatable { case code, register, signIn }

    let id = UUID()
    var step: Step = .code
    var codeText = ""
    var firstName = ""
    var lastName = ""
    var email = ""
    var password = ""
    private(set) var input: SchoolAccessInput?
    private(set) var preview: SchoolAccessPreview?
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    /// Connecté : la racine ferme la feuille et poursuit avec ce résultat.
    private(set) var outcome: SchoolAccessOutcome?
    /// Connecté : la feuille peut se fermer (avec ou sans suite à donner).
    private(set) var isFinished = false
    @ObservationIgnored private let client: SchoolAccountClient
    @ObservationIgnored private let identity: IdentitySession
    @ObservationIgnored private var generation = UUID()

    init(client: SchoolAccountClient, identity: IdentitySession, link: String? = nil) {
        self.client = client; self.identity = identity
        if let link { codeText = link }
    }

    var parsedInput: SchoolAccessInput? { SchoolAccessInput.parse(codeText, configuration: client.configuration) }
    var canInspect: Bool { !isBusy && parsedInput != nil }
    var canRegister: Bool {
        !isBusy && input != nil && !firstName.trimmed.isEmpty && !lastName.trimmed.isEmpty
            && email.trimmed.contains("@") && password.count >= 8
    }
    var canSignIn: Bool { !isBusy && email.trimmed.contains("@") && !password.isEmpty }

    /// Titre de l’étape de création : ce que le code ouvre.
    var registerTitle: String {
        switch preview?.kind {
        case .schoolOpening: "Ouvrir ton école"
        case .learnerInvitation: preview?.schoolName.map { "Rejoindre \($0)" } ?? "Rejoindre ton école"
        case .emailInvitation, nil: "Rejoindre ton école"
        }
    }

    func inspect() async {
        await inspect(next: .register)
    }

    /// Un compte existant garde aussi le code déjà saisi avant de se connecter.
    func continueWithExistingAccount() async {
        guard !isBusy else { return }
        if codeText.trimmed.isEmpty { show(.signIn); return }
        await inspect(next: .signIn)
    }

    private func inspect(next: Step) async {
        guard !isBusy else { return }
        guard let parsed = parsedInput else {
            errorMessage = SchoolAccountFailure.invalidCode.localizedDescription
            return
        }
        let request = begin()
        do {
            let value = try await client.preview(parsed)
            guard request == generation else { return }
            input = parsed; preview = value; step = next; isBusy = false
        } catch { fail(error, request) }
    }

    func register() async {
        guard canRegister, let input else { return }
        let request = begin()
        let account = SchoolNewAccount(code: input.secret, firstName: firstName.trimmed, lastName: lastName.trimmed,
                                       email: email.trimmed.lowercased(), password: password)
        do {
            let kind = try await client.create(account, input: input)
            guard request == generation else { return }
            // Le compte existe : la connexion se fait avec le mot de passe qui vient d’être choisi.
            await connect(kind: kind, displayName: "\(account.firstName) \(account.lastName)", request: request)
        } catch SchoolAccountFailure.accountExists {
            guard request == generation else { return }
            // Même adresse, compte déjà là : on passe à la connexion en gardant le code.
            isBusy = false; password = ""; step = .signIn; errorMessage = SchoolAccountFailure.accountExists.localizedDescription
        } catch { fail(error, request) }
    }

    func signIn() async {
        guard canSignIn else { return }
        let request = begin()
        await connect(kind: preview?.kind, displayName: nil, request: request)
    }

    func show(_ next: Step) {
        guard !isBusy else { return }
        errorMessage = nil; password = ""
        step = next == .register && input == nil ? .code : next
    }

    func invalidate() { generation = UUID(); isBusy = false; password = "" }

    private func connect(kind: SchoolAccessKind?, displayName: String?, request: UUID) async {
        let connected = await identity.signIn(email: email.trimmed, password: password)
        guard request == generation else { return }
        isBusy = false
        guard connected else {
            errorMessage = identity.errorMessage ?? IdentityFailure.unavailable.localizedDescription
            identity.clearError()
            return
        }
        password = ""
        defer { isFinished = true }
        if let input, let kind {
            outcome = SchoolAccessOutcome(input: input, kind: kind, displayName: displayName, email: email.trimmed.lowercased())
        } else {
            outcome = nil
        }
    }

    private func begin() -> UUID {
        generation = UUID(); isBusy = true; errorMessage = nil
        return generation
    }

    private func fail(_ error: Error, _ request: UUID) {
        guard request == generation else { return }
        isBusy = false
        if error.isRequestCancellation { return }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? SchoolAccountFailure.unavailable.localizedDescription
    }
}

#if DEBUG
extension SchoolAccessWorkspace {
    /// Captures d’écran : l’étape de création telle qu’après la lecture d’un code, sans réseau.
    func review(_ preview: SchoolAccessPreview, input: SchoolAccessInput) {
        self.preview = preview; self.input = input; step = .register
    }
}
#endif

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
