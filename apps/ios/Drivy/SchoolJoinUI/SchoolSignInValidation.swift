import Foundation

/// Aide de saisie uniquement : le fournisseur reste l’autorité sur l’adresse et les identifiants.
enum SchoolSignInValidation {
    static func emailIssue(_ value: String) -> String? {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty { return "Saisis ton e-mail." }
        return email.contains("@") ? nil : "Complète ton adresse e-mail avec @."
    }

    static func passwordIssue(_ value: String) -> String? {
        value.isEmpty ? "Saisis ton mot de passe." : nil
    }

    static func canSubmit(email: String, password: String) -> Bool {
        emailIssue(email) == nil && passwordIssue(password) == nil
    }
}
